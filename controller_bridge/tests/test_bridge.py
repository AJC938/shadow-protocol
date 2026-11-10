"""Automated tests for the SHADOW CONTROLLER V2 bridge (no hardware needed).
Run from the project root:  python -m unittest discover -s controller_bridge/tests -v
"""
import os
import socket
import sys
import time
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import protocol  # noqa: E402
import serial  # noqa: E402
import serial_bridge  # noqa: E402

TEST_TO_GODOT = 52420
TEST_FROM_GODOT = 52421


class FakeSerial:
    """Stands in for pyserial: records writes, serves queued reads, can be 'unplugged'."""

    def __init__(self):
        self.written = b""
        self.incoming = b""
        self.unplugged = False
        self.closed = False
        self.timeout = 0.02

    @property
    def in_waiting(self):
        if self.unplugged:
            raise serial.SerialException("device disconnected")
        return len(self.incoming)

    def read(self, n=1):
        if self.unplugged:
            raise serial.SerialException("device disconnected")
        data, self.incoming = self.incoming[:n], self.incoming[n:]
        return data

    def write(self, data):
        if self.unplugged:
            raise serial.SerialException("write failed")
        self.written += data
        return len(data)

    def close(self):
        self.closed = True


class ProtocolTests(unittest.TestCase):
    def test_valid_frame(self):
        f = protocol.parse_line(b"SPV2,DATA,125,512,210,800,512,1,0\r\n")
        self.assertEqual(f, protocol.Frame(125, 512, 210, 800, 512, 1, 0))
        self.assertEqual(f.to_godot(), b"CTRL,125,512,210,800,512,1,0")

    def test_ready_and_diagnostics(self):
        self.assertEqual(protocol.parse_line("SPV2,READY,1"), protocol.Ready(True))
        self.assertIsNone(protocol.parse_line("# [OLED] INITIALIZED"))
        self.assertIsNone(protocol.parse_line("   "))

    def test_malformed_frames_rejected(self):
        bad = [
            "SPV2,DATA,1,512,512,512,512,1",           # missing field
            "SPV2,DATA,1,512,512,512,512,1,0,9",       # extra field
            "SPV2,DATA,1,1024,512,512,512,0,0",        # axis > 1023
            "SPV2,DATA,1,-5,512,512,512,0,0",          # negative
            "SPV2,DATA,1,512,512,512,512,2,0",         # button not 0/1
            "SPV2,DATA,x,512,512,512,512,0,0",         # non-integer
            "SPV2,DATA,70000,512,512,512,512,0,0",     # seq out of range
            "SPV2,DATA,1,51 2,512,512,512,0,0",        # embedded space
            "SPV2,DATA,1,,512,512,512,0,0",            # empty field
            "PV2,DATA,1,512,512,512,512,0,0",          # lost leading bytes
            "SPV2,DAT",                                # truncated line
            "garbage",
        ]
        for line in bad:
            with self.assertRaises(protocol.ParseError, msg=line):
                protocol.parse_line(line)
        with self.assertRaises(protocol.ParseError):
            protocol.parse_line(b"SPV2,DATA,1,5\xff2,512,512,512,0,0")

    def test_sequence_classification(self):
        self.assertEqual(protocol.classify_seq(None, 5), ("first", 0))
        self.assertEqual(protocol.classify_seq(5, 6), ("next", 0))
        self.assertEqual(protocol.classify_seq(5, 9), ("gap", 3))
        self.assertEqual(protocol.classify_seq(9, 9), ("duplicate", 0))
        self.assertEqual(protocol.classify_seq(9, 4), ("stale", 0))
        self.assertEqual(protocol.classify_seq(65535, 0), ("next", 0))   # 16-bit wrap

    def test_state_messages(self):
        for s in protocol.GAME_STATES:
            self.assertEqual(protocol.parse_state_message(("SPSTATE,%s\n" % s).encode()), s)
            self.assertEqual(protocol.state_line(s), ("SPSTATE,%s\n" % s).encode())
        for bad in [b"SPSTATE,EXPLODE", b"STATE,ALIVE", b"SPSTATE,"]:
            with self.assertRaises(protocol.ParseError):
                protocol.parse_state_message(bad)


class BridgeTests(unittest.TestCase):
    def setUp(self):
        cfg = serial_bridge.load_config(None)
        cfg.update({"to_godot_port": TEST_TO_GODOT, "from_godot_port": TEST_FROM_GODOT})
        self.godot = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.godot.bind(("127.0.0.1", TEST_TO_GODOT))
        self.godot.settimeout(0.5)
        self.bridge = serial_bridge.Bridge(cfg)
        self.fake = FakeSerial()
        self.bridge.ser = self.fake
        self.bridge.port_name = "COMTEST"

    def tearDown(self):
        self.bridge.close()
        self.godot.close()

    def recv_godot(self, prefix):
        deadline = time.monotonic() + 1.0
        while time.monotonic() < deadline:
            data, _ = self.godot.recvfrom(256)
            if data.startswith(prefix):
                return data
        self.fail("no %r message" % prefix)

    def test_frames_forwarded_to_godot(self):
        self.bridge.feed_serial(b"# boot text\nSPV2,READY,1\nSPV2,DATA,1,512,100,900,512,1,0\n")
        self.assertEqual(self.recv_godot(b"CTRL"), b"CTRL,1,512,100,900,512,1,0")
        self.assertEqual(self.bridge.stats["frames"], 1)

    def test_split_packets_and_garbage_resync(self):
        self.bridge.feed_serial(b"SPV2,DATA,7,51")
        self.assertEqual(self.bridge.stats["frames"], 0)          # incomplete: waits
        self.bridge.feed_serial(b"2,512,512,512,0,1\nnoise!!\nSPV2,DATA,8,0,0,1023,1023,0,0\n")
        self.assertEqual(self.recv_godot(b"CTRL"), b"CTRL,7,512,512,512,512,0,1")
        self.assertEqual(self.recv_godot(b"CTRL"), b"CTRL,8,0,0,1023,1023,0,0")
        self.assertEqual(self.bridge.stats["malformed"], 1)

    def test_duplicates_and_gaps(self):
        self.bridge.feed_serial(b"SPV2,DATA,10,512,512,512,512,0,0\nSPV2,DATA,10,512,512,512,512,0,0\n"
                                b"SPV2,DATA,14,512,512,512,512,0,0\nSPV2,DATA,12,512,512,512,512,0,0\n")
        self.assertEqual(self.bridge.stats["frames"], 2)
        self.assertEqual(self.bridge.stats["dropped"], 3)
        self.assertEqual(self.bridge.stats["stale"], 2)

    def test_ping_and_state_forwarding(self):
        sender = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sender.sendto(b"SPSTATE,DEAD", ("127.0.0.1", TEST_FROM_GODOT))
        sender.sendto(b"SPSTATE,BOGUS", ("127.0.0.1", TEST_FROM_GODOT))
        sender.close()
        time.sleep(0.05)
        self.bridge.poll_godot()
        self.bridge.tick(time.monotonic())
        self.assertIn(b"SPV2,PING\n", self.fake.written)
        self.assertIn(b"SPSTATE,DEAD\n", self.fake.written)
        self.assertNotIn(b"BOGUS", self.fake.written)
        self.assertEqual(self.bridge.stats["malformed"], 1)

    def test_state_resent_after_arduino_reset(self):
        self.bridge.state = "ALIVE"
        self.bridge.tick(time.monotonic())
        self.fake.written = b""
        self.bridge.feed_serial(b"SPV2,READY,1\n")      # board rebooted
        self.bridge.tick(time.monotonic())
        self.assertIn(b"SPSTATE,ALIVE\n", self.fake.written)

    def test_unplug_reports_link_down(self):
        self.fake.unplugged = True
        self.assertFalse(self.bridge.write_serial(b"SPV2,PING\n"))
        self.assertIsNone(self.bridge.ser)
        self.assertTrue(self.fake.closed)
        self.assertEqual(self.recv_godot(b"LINK"), b"LINK,0,-")

    def test_reconnect_with_configured_port(self):
        self.fake.unplugged = True
        self.bridge.write_serial(b"x")
        self.assertIsNone(self.bridge.ser)
        new = FakeSerial()
        original = serial_bridge.serial.Serial
        serial_bridge.serial.Serial = lambda *a, **k: new
        try:
            self.bridge.port_override = "COM77"
            self.assertTrue(self.bridge.connect())
        finally:
            serial_bridge.serial.Serial = original
        self.assertIs(self.bridge.ser, new)
        self.assertEqual(self.bridge.port_name, "COM77")

    def _from_godot(self, *msgs):
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        for m in msgs:
            s.sendto(m, ("127.0.0.1", TEST_FROM_GODOT))
        s.close()
        time.sleep(0.05)
        self.bridge.poll_godot()

    def test_damaged_and_health_forwarded(self):
        self._from_godot(b"SPSTATE,ALIVE", b"SPHEALTH,100")
        self.bridge.tick(time.monotonic())
        self._from_godot(b"SPSTATE,DAMAGED", b"SPHEALTH,73")
        self.bridge.tick(time.monotonic())
        self.assertIn(b"SPSTATE,DAMAGED\n", self.fake.written)
        self.assertIn(b"SPHEALTH,73\n", self.fake.written)
        self._from_godot(b"SPSTATE,ALIVE")
        self.bridge.tick(time.monotonic())
        states = [l for l in self.fake.written.split(b"\n") if l.startswith(b"SPSTATE,")]
        self.assertEqual(states[-1], b"SPSTATE,ALIVE")   # back to ALIVE immediately after the hit window

    def test_bad_health_rejected(self):
        for bad in (b"SPHEALTH,101", b"SPHEALTH,-3", b"SPHEALTH,", b"SPHEALTH,5x"):
            with self.assertRaises(protocol.ParseError):
                protocol.parse_godot_message(bad)
        self.assertEqual(protocol.parse_godot_message(b"SPHEALTH,0"), ("health", 0))

    def test_repeated_state_not_spammed(self):
        self._from_godot(b"SPSTATE,ALIVE")
        self.bridge.tick(time.monotonic())
        for _ in range(5):
            self._from_godot(b"SPSTATE,ALIVE")
            self.bridge.tick(time.monotonic())
        self.assertEqual(self.fake.written.count(b"SPSTATE,ALIVE\n"), 1)

    def test_godot_poll_never_blocks(self):
        # Regression: a blocking UDP receive capped the bridge at ~0.4 frames/s.
        t0 = time.perf_counter()
        for _ in range(100):
            self.bridge.poll_godot()
        self.assertLess(time.perf_counter() - t0, 0.05)

    def test_single_instance_lock(self):
        cfg = serial_bridge.load_config(None)
        cfg.update({"to_godot_port": TEST_TO_GODOT + 10, "from_godot_port": TEST_FROM_GODOT})
        with self.assertRaises(OSError):
            serial_bridge.Bridge(cfg)

    def test_config_rejects_non_loopback(self):
        path = os.path.join(os.path.dirname(__file__), "_bad_cfg.json")
        with open(path, "w") as f:
            f.write('{"godot_host": "0.0.0.0"}')
        try:
            with self.assertRaises(ValueError):
                serial_bridge.load_config(path)
        finally:
            os.remove(path)

    def test_bluetooth_ports_never_candidates(self):
        for p in serial_bridge.candidate_ports():
            self.assertNotIn("bluetooth", (p.description or "").lower())


if __name__ == "__main__":
    unittest.main()
