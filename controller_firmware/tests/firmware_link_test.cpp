// Host unit tests for the firmware's game-link parser (the exact header the
// Arduino compiles). Build & run:
//   g++ -std=c++17 -I ../ShadowController_V2_Link firmware_link_test.cpp -o firmware_link_test && ./firmware_link_test
#include <cstdio>
#include <cstring>
#include <string>
#include "link_protocol.h"

static int failures = 0;
static int checks = 0;
#define CHECK(cond, msg) do { checks++; if (!(cond)) { failures++; std::printf("FAIL: %s\n", msg); } } while (0)

static uint8_t parse(const char *line, uint8_t &state, uint8_t &health) {
  state = GS_NONE;
  health = 255;
  return parseLinkLine(line, &state, &health);
}

// Feeds a whole string through the LineReader; returns the last complete line (or "").
static std::string feedAll(LineReader &r, const char *bytes, int *lines) {
  std::string last;
  *lines = 0;
  for (const char *p = bytes; *p; ++p) {
    if (r.feed(*p)) { last = r.buf; (*lines)++; }
  }
  return last;
}

int main() {
  uint8_t st, hp;
  CHECK(parse("SPV2,PING", st, hp) == MSG_PING, "PING recognised");
  CHECK(parse("SPSTATE,ALIVE", st, hp) == MSG_STATE && st == GS_ALIVE, "ALIVE");
  CHECK(parse("SPSTATE,DAMAGED", st, hp) == MSG_STATE && st == GS_DAMAGED, "DAMAGED");
  CHECK(parse("SPSTATE,DEAD", st, hp) == MSG_STATE && st == GS_DEAD, "DEAD");
  CHECK(parse("SPSTATE,PAUSED", st, hp) == MSG_STATE && st == GS_PAUSED, "PAUSED");
  CHECK(parse("SPSTATE,READY", st, hp) == MSG_STATE && st == GS_READY, "READY");
  CHECK(parse("SPSTATE,MISSION_COMPLETE", st, hp) == MSG_STATE && st == GS_COMPLETE, "MISSION_COMPLETE");
  CHECK(parse("SPHEALTH,73", st, hp) == MSG_HEALTH && hp == 73, "health 73");
  CHECK(parse("SPHEALTH,0", st, hp) == MSG_HEALTH && hp == 0, "health 0");
  CHECK(parse("SPHEALTH,100", st, hp) == MSG_HEALTH && hp == 100, "health 100");
  const char *bad[] = {"SPSTATE,EXPLODE", "SPSTATE,", "SPSTATE,alive", "SPSTATE,ALIVE ", "SPV2,PINGX", "SPHEALTH,101",
                       "SPHEALTH,", "SPHEALTH,-1", "SPHEALTH,7a", "SPHEALTH,0100", "PING", "", "SPSTATE"};
  for (const char *b : bad) {
    char msg[64];
    std::snprintf(msg, sizeof msg, "rejects '%s'", b);
    CHECK(parse(b, st, hp) == MSG_NONE, msg);
  }

  // Line framing: CRLF, split lines, the longest message (24 chars), overflow drop.
  LineReader r;
  r.reset();
  int n;
  CHECK(feedAll(r, "SPSTATE,MISSION_COMPLETE\n", &n) == "SPSTATE,MISSION_COMPLETE" && n == 1,
        "24-char MISSION_COMPLETE line fits (v1 firmware dropped it)");
  CHECK(feedAll(r, "SPV2,PI", &n).empty() && n == 0, "partial line waits");
  CHECK(feedAll(r, "NG\r\n", &n) == "SPV2,PING" && n == 1, "split line + CRLF assembled");
  CHECK(feedAll(r, "SPSTATE,ALIVExxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\nSPSTATE,DEAD\n", &n) == "SPSTATE,DEAD" && n == 1,
        "over-long line dropped entirely, next line still parsed");
  CHECK(feedAll(r, "\n\n\r\n", &n).empty() && n == 0, "blank lines ignored");

  // Transient DAMAGED display fallback.
  CHECK(displayedState(GS_DAMAGED, 1000, 0, 3000) == GS_DAMAGED, "DAMAGED shown within window");
  CHECK(displayedState(GS_DAMAGED, 3500, 500, 3000) == GS_DAMAGED, "exactly at the 3000 ms boundary still DAMAGED");
  CHECK(displayedState(GS_DAMAGED, 4000, 500, 3000) == GS_ALIVE, "DAMAGED falls back to ALIVE if no update");
  CHECK(displayedState(GS_DEAD, 999999, 0, 3000) == GS_DEAD, "DEAD is never timed out");
  CHECK(displayedState(GS_DAMAGED, 100, 4294967000u, 3000) == GS_DAMAGED, "millis() wrap-around safe");

  std::printf("%d checks, %d failures\n", checks, failures);
  return failures == 0 ? 0 : 1;
}
