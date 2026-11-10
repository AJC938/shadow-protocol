"""SHADOW PROTOCOL — Python serial bridge for the SHADOW CONTROLLER V2 (Arduino Uno).

USB serial  <-->  this bridge  <-->  Godot (localhost UDP only)

* Finds the Arduino (or uses the configured COM port), never Bluetooth/unknown ports.
* Parses and validates SPV2 controller frames, forwards them to Godot.
* Sends SPV2,PING heartbeats to the Arduino every ~500 ms.
* Receives SPSTATE,<state> from Godot and forwards it to the Arduino OLED.
* Survives unplugging / Arduino resets: reconnects automatically, tells Godot the
  link is down so the game releases movement and fire.

Usage:  python serial_bridge.py [--port COM5] [--config config.json] [--list]
"""
import argparse
import json
import logging
import os
import socket
import sys
import threading
import time

import serial
import serial.tools.list_ports

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import protocol  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
LOG = logging.getLogger("bridge")

DEFAULT_CONFIG = {
    "port": "auto",
    "baud": 115200,
    "godot_host": "127.0.0.1",
    "to_godot_port": 42420,
    "from_godot_port": 42421,
    "ping_interval": 0.5,
    "state_resend_interval": 2.0,
    "link_report_interval": 0.25,
    "probe_seconds": 6.0,
    "reconnect_delay": 1.5,
}

# USB vendor ids of Arduino boards and common USB-serial chips used on Uno clones.
KNOWN_VIDS = {0x2341: "Arduino", 0x2A03: "Arduino.org", 0x1A86: "CH340", 0x0403: "FTDI", 0x10C4: "CP210x"}


def load_config(path):
    cfg = dict(DEFAULT_CONFIG)
    if path and os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            user = json.load(f)
        unknown = set(user) - set(cfg)
        if unknown:
            LOG.warning("ignoring unknown config keys: %s", ", ".join(sorted(unknown)))
        cfg.update({k: v for k, v in user.items() if k in cfg})
    for key in ("to_godot_port", "from_godot_port"):
        if not 1024 <= int(cfg[key]) <= 65535:
            raise ValueError("%s must be 1024..65535" % key)
    if cfg["godot_host"] not in ("127.0.0.1", "localhost", "::1"):
        raise ValueError("godot_host must be a loopback address (localhost only)")
    return cfg


def candidate_ports():
    """USB serial ports that could be the controller (Bluetooth and unknown devices excluded)."""
    out = []
    for p in serial.tools.list_ports.comports():
        desc = (p.description or "") + " " + (p.hwid or "")
        if "bluetooth" in desc.lower() or "BTHENUM" in desc:
            continue
        if p.vid in KNOWN_VIDS or "arduino" in desc.lower() or "ch340" in desc.lower():
            out.append(p)
    return out


def probe_port(device, baud, seconds):
    """Opens a port and waits for SPV2 traffic. Returns an open Serial or None."""
    try:
        ser = serial.Serial(device, baud, timeout=0.1, write_timeout=0.2)
    except (serial.SerialException, OSError) as e:
        LOG.info("cannot open %s: %s", device, e)
        return None
    deadline = time.monotonic() + seconds   # opening resets the Uno; boot takes ~3.5 s
    buf = b""
    while time.monotonic() < deadline:
        try:
            chunk = ser.read(256)
        except (serial.SerialException, OSError):
            break
        buf += chunk
        if b"SPV2," in buf:
            LOG.info("controller confirmed on %s", device)
            return ser
    LOG.info("%s did not send SHADOW CONTROLLER packets", device)
    ser.close()
    return None


class Bridge:
    def __init__(self, cfg, port_override=None):
        self.cfg = cfg
        self.port_override = port_override
        self.ser = None
        self.port_name = None
        self.running = True
        self.state = None              # last game state from Godot
        self.health = None             # last health % from Godot (optional)
        self.health_dirty = False
        self.last_state_sent = 0.0
        self.last_ping = 0.0
        self.last_link_report = 0.0
        self.last_seq = None
        self.stats = {"frames": 0, "dropped": 0, "malformed": 0, "stale": 0, "states": 0}
        self._rx = b""
        self._lock = threading.Lock()
        self.to_godot = (cfg["godot_host"], int(cfg["to_godot_port"]))
        # Socket for sending to Godot.
        self.tx_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        # Socket for receiving from Godot. Binding it also acts as the single-instance lock.
        self.rx_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        if hasattr(socket, "SO_EXCLUSIVEADDRUSE"):
            self.rx_sock.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        try:
            self.rx_sock.bind(("127.0.0.1", int(cfg["from_godot_port"])))
        except OSError:
            self.rx_sock.close()
            self.tx_sock.close()
            raise
        self.rx_sock.setblocking(False)   # never stall the serial loop

    # ------------------------------------------------------------- serial lifecycle

    def connect(self):
        port = self.port_override or (None if self.cfg["port"] == "auto" else self.cfg["port"])
        if port:
            try:
                if "://" in port:   # e.g. socket://127.0.0.1:47000 (fake_arduino.py simulator)
                    self.ser = serial.serial_for_url(port, self.cfg["baud"], timeout=0.01, write_timeout=0.2)
                else:
                    self.ser = serial.Serial(port, self.cfg["baud"], timeout=0.01, write_timeout=0.2)
                self.port_name = port
                LOG.info("opened configured port %s", port)
                return True
            except (serial.SerialException, OSError) as e:
                LOG.warning("cannot open %s: %s", port, e)
                return False
        cands = candidate_ports()
        if not cands:
            LOG.info("no Arduino USB serial port found (plug in the controller)")
            return False
        for p in cands:
            LOG.info("probing %s (%s)", p.device, p.description)
            ser = probe_port(p.device, self.cfg["baud"], self.cfg["probe_seconds"])
            if ser:
                ser.timeout = 0.01
                self.ser = ser
                self.port_name = p.device
                return True
        return False

    def disconnect(self, reason):
        if self.ser is not None:
            LOG.warning("serial link lost (%s)", reason)
            try:
                self.ser.close()
            except Exception:
                pass
        self.ser = None
        self.port_name = None
        self.last_seq = None
        self._rx = b""
        self.report_link(force=True)

    # ------------------------------------------------------------- data paths

    def report_link(self, force=False):
        now = time.monotonic()
        if force or now - self.last_link_report >= self.cfg["link_report_interval"]:
            self.last_link_report = now
            self._send_godot(protocol.link_message(self.ser is not None, self.port_name))

    def _send_godot(self, data):
        try:
            self.tx_sock.sendto(data, self.to_godot)
        except OSError:
            pass   # Godot not running yet: fine, UDP is fire-and-forget

    def handle_line(self, line):
        try:
            msg = protocol.parse_line(line)
        except protocol.ParseError as e:
            self.stats["malformed"] += 1
            LOG.debug("malformed packet: %s", e)
            return None
        if isinstance(msg, protocol.Ready):
            LOG.info("controller READY (OLED %s)", "OK" if msg.oled else "NOT FOUND")
            self.last_seq = None
            self.last_state_sent = 0.0   # push the current game state to the fresh board
            return msg
        if isinstance(msg, protocol.Frame):
            kind, dropped = protocol.classify_seq(self.last_seq, msg.seq)
            if kind in ("duplicate", "stale"):
                self.stats["stale"] += 1
                return None
            self.stats["dropped"] += dropped
            self.last_seq = msg.seq
            self.stats["frames"] += 1
            self._send_godot(msg.to_godot())
        return msg

    def feed_serial(self, data):
        """Accumulates raw bytes and dispatches complete lines (used by run loop and tests)."""
        self._rx += data
        if len(self._rx) > 4096:          # garbage without newlines: resync
            self._rx = self._rx[-256:]
            self.stats["malformed"] += 1
        out = []
        while b"\n" in self._rx:
            line, self._rx = self._rx.split(b"\n", 1)
            out.append(self.handle_line(line))
        return out

    def write_serial(self, data):
        if self.ser is None:
            return False
        try:
            self.ser.write(data)
            return True
        except (serial.SerialException, OSError) as e:
            self.disconnect("write failed: %s" % e)
            return False

    def poll_godot(self):
        """Receives state messages from Godot (localhost only)."""
        while True:
            try:
                data, addr = self.rx_sock.recvfrom(256)
            except (BlockingIOError, socket.timeout):
                return
            except OSError:
                return
            if addr[0] not in ("127.0.0.1", "::1"):
                continue
            try:
                kind, value = protocol.parse_godot_message(data)
            except protocol.ParseError:
                self.stats["malformed"] += 1
                continue
            if kind == "health":
                if value != self.health:
                    self.health = value
                    self.health_dirty = True
                continue
            self.stats["states"] += 1
            if value != self.state:
                LOG.info("game state -> %s", value)
                self.state = value
                self.last_state_sent = 0.0   # changes are forwarded immediately
            # unchanged repeats only refresh via the periodic resend (no duplicate spam)

    def tick(self, now):
        if self.ser is not None:
            if now - self.last_ping >= self.cfg["ping_interval"]:
                self.last_ping = now
                self.write_serial(protocol.PING_LINE)
            if self.state and now - self.last_state_sent >= self.cfg["state_resend_interval"]:
                if self.write_serial(protocol.state_line(self.state)):
                    self.last_state_sent = now
                    self.health_dirty = self.health is not None   # resend health with the state
            if self.health_dirty and self.ser is not None:
                if self.write_serial(protocol.health_line(self.health)):
                    self.health_dirty = False
        self.report_link()

    # ------------------------------------------------------------- main loop

    def run(self):
        LOG.info("UDP -> Godot %s:%d   Godot -> UDP 127.0.0.1:%d", self.to_godot[0], self.to_godot[1], self.cfg["from_godot_port"])
        last_stats = time.monotonic()
        frames_at_stats = 0
        while self.running:
            if self.ser is None:
                self.report_link()
                self.poll_godot()
                if not self.connect():
                    deadline = time.monotonic() + self.cfg["reconnect_delay"]
                    while self.running and time.monotonic() < deadline:
                        self.poll_godot()
                        self.report_link()
                        time.sleep(0.02)
                    continue
                self.report_link(force=True)
                self.last_ping = 0.0
                self.last_state_sent = 0.0
            try:
                n = self.ser.in_waiting
                # Everything already buffered, else wait <=10 ms for a chunk (works for real
                # COM ports and socket:// simulators alike). Latency stays under one frame.
                data = self.ser.read(n) if n else self.ser.read(256)
            except (serial.SerialException, OSError) as e:
                self.disconnect("read failed: %s" % e)
                continue
            if data:
                self.feed_serial(data)
            self.poll_godot()
            now = time.monotonic()
            self.tick(now)
            if now - last_stats >= 5.0:
                rate = (self.stats["frames"] - frames_at_stats) / (now - last_stats)
                LOG.info("%s  %.1f frames/s  dropped=%d malformed=%d state=%s", self.port_name or "no port", rate,
                         self.stats["dropped"], self.stats["malformed"], self.state or "-")
                last_stats = now
                frames_at_stats = self.stats["frames"]

    def close(self):
        self.running = False
        if self.ser is not None:
            try:
                self.ser.close()
            except Exception:
                pass
        self.ser = None
        self._send_godot(protocol.link_message(False, None))
        self.rx_sock.close()
        self.tx_sock.close()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", help="COM port (overrides config.json), e.g. COM5")
    ap.add_argument("--config", default=os.path.join(HERE, "config.json"))
    ap.add_argument("--list", action="store_true", help="list serial ports and exit")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(errors="replace")   # Windows port names contain Unicode marks
    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO,
                        format="%(asctime)s %(levelname)-7s %(message)s", datefmt="%H:%M:%S")
    if args.list:
        for p in serial.tools.list_ports.comports():
            flag = "candidate" if p in candidate_ports() else "ignored"
            print("%-8s %-10s %s  [%s]" % (p.device, ("%04X" % p.vid) if p.vid else "-", p.description, flag))
        return 0
    cfg = load_config(args.config)
    try:
        bridge = Bridge(cfg, args.port)
    except OSError as e:
        LOG.error("UDP port %d is busy — is another bridge already running? (%s)", cfg["from_godot_port"], e)
        return 2
    LOG.info("SHADOW CONTROLLER V2 bridge started (Ctrl+C to stop)")
    try:
        bridge.run()
    except KeyboardInterrupt:
        LOG.info("stopping")
    finally:
        bridge.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
