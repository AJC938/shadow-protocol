"""SHADOW CONTROLLER V2 simulator — speaks the exact firmware protocol over TCP so the
bridge and the game can be tested without hardware.

    python fake_arduino.py --port 47000 [--duration 40] [--drop-after N]
    python serial_bridge.py --port socket://127.0.0.1:47000

Sends '# boot' diagnostics, SPV2,READY,1 and SPV2,DATA frames at 50 Hz from a scripted
stick timeline (tactical layout: J1 = look + fire, J2 = move + interact). Receives PING /
SPSTATE / SPHEALTH and emulates the firmware's OLED status logic (link timeout, DAMAGED
fallback), printing each new screen. Prints a JSON summary at the end.
This is a SIMULATION — it proves nothing about the physical controller or OLED.
"""
import argparse
import json
import socket
import time

C = 512
LINK_TIMEOUT = 1.5
DAMAGED_TIMEOUT = 3.0


def scripted_input(t):
    """(j1x, j1y, j2x, j2y, b1, b2) at time t (s). J1 = look/fire, J2 = move/interact."""
    if t < 8.0:
        return (C, C, C, C, 0, 0)          # idle while the mission loads
    if t < 8.6:
        return (1023, C, C, C, 0, 0)       # J1 right: look right
    if t < 9.2:
        return (0, C, C, C, 0, 0)          # J1 left: look back
    if t < 9.5:
        return (C, 0, C, C, 0, 0)          # J1 up: look up
    if t < 9.8:
        return (C, C, C, C, 1, 0)          # J1 press: fire
    if t < 20.0:
        return (C, C, C, 0, 0, 0)          # J2 up: advance through the breach (toward the perimeter guard)
    return (C, C, C, C, 0, 0)              # hold still


def screen(link, state, health):
    if not link:
        return "PC LINK: DISCONNECTED | STANDBY"
    words = {"ALIVE": "PLAYER: ALIVE", "DAMAGED": "PLAYER: DAMAGED", "DEAD": "PLAYER: DEAD",
             "PAUSED": "PLAYER: PAUSED", "MISSION_COMPLETE": "MISSION COMPLETE", "READY": "GAME: READY"}
    s = "PC LINK: CONNECTED | " + words.get(state, "GAME: LINKING")
    if state in ("ALIVE", "DAMAGED") and health is not None:
        s += " | HEALTH %d%%" % health
    return s


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=47000)
    ap.add_argument("--duration", type=float, default=40.0)
    ap.add_argument("--drop-after", type=float, default=0.0, help="simulate unplugging after N seconds")
    args = ap.parse_args()
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", args.port))
    srv.listen(1)
    srv.settimeout(30)
    print("[FAKE] waiting for bridge on 127.0.0.1:%d" % args.port, flush=True)
    conn, _ = srv.accept()
    conn.setblocking(False)
    print("[FAKE] bridge connected", flush=True)
    conn.sendall(b"# [OLED] SCANNING...\n# [OLED] INITIALIZED\n# SHADOW PROTOCOL - SYSTEM BOOTING\nSPV2,READY,1\n")
    summary = {"frames_sent": 0, "pings": 0, "states": [], "health": [], "screens": [], "malformed_rx": 0}
    state, health, last_ping, damaged_since = None, None, -99.0, 0.0
    seq, rx, last_screen = 0, b"", None
    start = time.monotonic()
    next_frame = start
    while time.monotonic() - start < args.duration:
        now = time.monotonic()
        t = now - start
        if args.drop_after and t > args.drop_after:
            print("[FAKE] simulating USB unplug", flush=True)
            break
        if now >= next_frame:
            next_frame += 0.02
            seq = seq % 65535 + 1
            vals = scripted_input(t)
            try:
                conn.sendall(("SPV2,DATA,%d,%d,%d,%d,%d,%d,%d\n" % ((seq,) + vals)).encode())
            except OSError:
                break
            summary["frames_sent"] += 1
        try:
            data = conn.recv(256)
            if not data:
                break
            rx += data
        except BlockingIOError:
            pass
        except OSError:
            break
        while b"\n" in rx:
            line, rx = rx.split(b"\n", 1)
            line = line.decode("ascii", "replace").strip()
            if line == "SPV2,PING":
                summary["pings"] += 1
                last_ping = now
            elif line.startswith("SPSTATE,"):
                last_ping = now
                state = line[8:]
                if state == "DAMAGED":
                    damaged_since = now
                if not summary["states"] or summary["states"][-1] != state:
                    summary["states"].append(state)
            elif line.startswith("SPHEALTH,") and line[9:].isdigit():
                health = int(line[9:])
                if not summary["health"] or summary["health"][-1] != health:
                    summary["health"].append(health)
            else:
                summary["malformed_rx"] += 1
        shown = state
        if shown == "DAMAGED" and now - damaged_since > DAMAGED_TIMEOUT:
            shown = "ALIVE"
        scr = screen(now - last_ping < LINK_TIMEOUT, shown, health)
        if scr != last_screen:
            last_screen = scr
            summary["screens"].append(scr)
            print("[FAKE OLED t=%.1f] %s" % (t, scr), flush=True)
        time.sleep(0.002)
    elapsed = time.monotonic() - start
    summary["seconds"] = round(elapsed, 2)
    summary["frame_rate_hz"] = round(summary["frames_sent"] / max(elapsed, 0.001), 1)
    conn.close()
    srv.close()
    print("[FAKE] SUMMARY " + json.dumps(summary), flush=True)


if __name__ == "__main__":
    main()
