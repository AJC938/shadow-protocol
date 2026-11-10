"""SHADOW CONTROLLER V2 <-> SHADOW PROTOCOL wire protocol (pure functions, no I/O).

Arduino -> PC (serial, 115200, '\\n' terminated)
    SPV2,DATA,<seq>,<J1X>,<J1Y>,<J2X>,<J2Y>,<B1>,<B2>
    SPV2,READY,<oled 0/1>
    # free text               (boot diagnostics; ignored)
PC -> Arduino
    SPV2,PING
    SPSTATE,<READY|ALIVE|DAMAGED|DEAD|PAUSED|MISSION_COMPLETE>
    SPHEALTH,<0..100>
Bridge -> Godot (UDP, localhost)
    CTRL,<seq>,<J1X>,<J1Y>,<J2X>,<J2Y>,<B1>,<B2>
    LINK,<serial 0/1>,<port or ->
Godot -> Bridge (UDP, localhost)
    SPSTATE,<state>
    SPHEALTH,<0..100>
"""
from dataclasses import dataclass

GAME_STATES = ("READY", "ALIVE", "DAMAGED", "DEAD", "PAUSED", "MISSION_COMPLETE")
AXIS_MIN, AXIS_MAX = 0, 1023
SEQ_MOD = 65536


@dataclass(frozen=True)
class Frame:
    seq: int
    j1x: int
    j1y: int
    j2x: int
    j2y: int
    b1: int
    b2: int

    def to_godot(self) -> bytes:
        return ("CTRL,%d,%d,%d,%d,%d,%d,%d" % (self.seq, self.j1x, self.j1y, self.j2x, self.j2y, self.b1, self.b2)).encode("ascii")


@dataclass(frozen=True)
class Ready:
    oled: bool


class ParseError(ValueError):
    pass


def parse_line(raw) -> object:
    """Returns Frame, Ready, or None (diagnostic / blank line). Raises ParseError if malformed."""
    if isinstance(raw, (bytes, bytearray)):
        try:
            line = raw.decode("ascii")
        except UnicodeDecodeError as e:
            raise ParseError("non-ascii bytes") from e
    else:
        line = raw
    line = line.strip()
    if not line or line.startswith("#"):
        return None
    parts = line.split(",")
    if parts[0] != "SPV2":
        raise ParseError("unknown prefix: %r" % line[:24])
    if len(parts) >= 2 and parts[1] == "READY":
        if len(parts) != 3 or parts[2] not in ("0", "1"):
            raise ParseError("bad READY")
        return Ready(parts[2] == "1")
    if len(parts) < 2 or parts[1] != "DATA":
        raise ParseError("unknown message: %r" % line[:24])
    if len(parts) != 9:
        raise ParseError("DATA field count %d" % len(parts))
    try:
        vals = [int(p) for p in parts[2:]]
    except ValueError as e:
        raise ParseError("non-integer field") from e
    for p in parts[2:]:
        if not p.isdigit():   # rejects signs, spaces, empty fields
            raise ParseError("invalid integer %r" % p)
    seq, j1x, j1y, j2x, j2y, b1, b2 = vals
    if not 0 <= seq < SEQ_MOD:
        raise ParseError("sequence out of range")
    for v in (j1x, j1y, j2x, j2y):
        if not AXIS_MIN <= v <= AXIS_MAX:
            raise ParseError("axis out of range: %d" % v)
    if b1 not in (0, 1) or b2 not in (0, 1):
        raise ParseError("button must be 0/1")
    return Frame(seq, j1x, j1y, j2x, j2y, b1, b2)


def seq_delta(prev: int, cur: int) -> int:
    """Forward distance from prev to cur with 16-bit wrap (1 = next frame)."""
    return (cur - prev) % SEQ_MOD


def classify_seq(prev, cur: int):
    """Returns ('first'|'next'|'gap'|'duplicate'|'stale', dropped_count)."""
    if prev is None:
        return "first", 0
    d = seq_delta(prev, cur)
    if d == 0:
        return "duplicate", 0
    if d == 1:
        return "next", 0
    if d < SEQ_MOD // 2:
        return "gap", d - 1
    return "stale", 0


def parse_state_message(raw) -> str:
    """Validates a Godot -> bridge message. Returns the state name or raises ParseError."""
    if isinstance(raw, (bytes, bytearray)):
        raw = raw.decode("ascii", errors="replace")
    line = raw.strip()
    if not line.startswith("SPSTATE,"):
        raise ParseError("not a state message")
    state = line[8:]
    if state not in GAME_STATES:
        raise ParseError("unknown state %r" % state)
    return state


def parse_godot_message(raw):
    """Godot -> bridge. Returns ('state', name) or ('health', 0..100); raises ParseError."""
    if isinstance(raw, (bytes, bytearray)):
        raw = raw.decode("ascii", errors="replace")
    line = raw.strip()
    if line.startswith("SPHEALTH,"):
        v = line[9:]
        if not v.isdigit() or not 0 <= int(v) <= 100:
            raise ParseError("bad health %r" % v)
        return ("health", int(v))
    return ("state", parse_state_message(line))


def health_line(pct: int) -> bytes:
    if not 0 <= int(pct) <= 100:
        raise ParseError("health out of range")
    return ("SPHEALTH,%d\n" % int(pct)).encode("ascii")


def state_line(state: str) -> bytes:
    if state not in GAME_STATES:
        raise ParseError("unknown state %r" % state)
    return ("SPSTATE,%s\n" % state).encode("ascii")


PING_LINE = b"SPV2,PING\n"


def link_message(connected: bool, port) -> bytes:
    return ("LINK,%d,%s" % (1 if connected else 0, port or "-")).encode("ascii")
