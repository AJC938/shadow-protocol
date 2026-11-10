// ============================================
// SHADOW CONTROLLER V2 - game link protocol (PC -> Arduino)
// Pure C++ with no Arduino dependencies so the exact same code is compiled
// into the firmware AND into the host unit tests (tests/firmware_link_test.cpp).
//
//   SPV2,PING
//   SPSTATE,READY|ALIVE|DAMAGED|DEAD|PAUSED|MISSION_COMPLETE
//   SPHEALTH,<0..100>
// ============================================
#pragma once

#include <stdint.h>
#include <string.h>

#ifdef ARDUINO
#include <avr/pgmspace.h>
#else
#define PSTR(s) (s)
#define strcmp_P strcmp
#define strncmp_P strncmp
#endif

enum GameState : uint8_t {
  GS_NONE,
  GS_READY,
  GS_ALIVE,
  GS_DAMAGED,
  GS_DEAD,
  GS_PAUSED,
  GS_COMPLETE
};

enum LinkMsg : uint8_t {
  MSG_NONE,     // unknown / malformed: ignored
  MSG_PING,
  MSG_STATE,
  MSG_HEALTH
};

// Longest valid line is "SPSTATE,MISSION_COMPLETE" (24 chars) + terminator.
#define LINK_LINE_MAX 32

// Line assembler: feed one byte at a time; returns true when a complete,
// non-overflowed line is available in buf (NUL terminated).
struct LineReader {
  char buf[LINK_LINE_MAX];
  uint8_t len;
  bool overflow;

  void reset() { len = 0; overflow = false; buf[0] = '\0'; }

  bool feed(char c) {
    if (c == '\n' || c == '\r') {
      bool ok = len > 0 && !overflow;
      buf[ok ? len : 0] = '\0';
      len = 0;
      bool wasOverflow = overflow;
      overflow = false;
      return ok && !wasOverflow;
    }
    if (len < LINK_LINE_MAX - 1) {
      buf[len++] = c;
    } else {
      overflow = true;   // too long: the whole line is dropped
    }
    return false;
  }
};

// Parses one complete line. Writes *state or *health for MSG_STATE / MSG_HEALTH.
inline uint8_t parseLinkLine(const char *line, uint8_t *state, uint8_t *health) {
  if (strcmp_P(line, PSTR("SPV2,PING")) == 0) {
    return MSG_PING;
  }
  if (strncmp_P(line, PSTR("SPSTATE,"), 8) == 0) {
    const char *s = line + 8;
    uint8_t next = GS_NONE;
    if (strcmp_P(s, PSTR("READY")) == 0) next = GS_READY;
    else if (strcmp_P(s, PSTR("ALIVE")) == 0) next = GS_ALIVE;
    else if (strcmp_P(s, PSTR("DAMAGED")) == 0) next = GS_DAMAGED;
    else if (strcmp_P(s, PSTR("DEAD")) == 0) next = GS_DEAD;
    else if (strcmp_P(s, PSTR("PAUSED")) == 0) next = GS_PAUSED;
    else if (strcmp_P(s, PSTR("MISSION_COMPLETE")) == 0) next = GS_COMPLETE;
    if (next == GS_NONE) return MSG_NONE;
    *state = next;
    return MSG_STATE;
  }
  if (strncmp_P(line, PSTR("SPHEALTH,"), 9) == 0) {
    const char *s = line + 9;
    if (*s == '\0') return MSG_NONE;
    uint16_t v = 0;
    uint8_t digits = 0;
    while (*s) {
      if (*s < '0' || *s > '9' || ++digits > 3) return MSG_NONE;
      v = v * 10 + (uint16_t)(*s - '0');
      s++;
    }
    if (v > 100) return MSG_NONE;
    *health = (uint8_t)v;
    return MSG_HEALTH;
  }
  return MSG_NONE;
}

// State actually shown on the OLED. DAMAGED is transient: the game sends ALIVE
// when the hit window ends; if that never arrives (link hiccup) the display falls
// back to ALIVE after damagedTimeoutMs. Permanent states are shown as received.
inline uint8_t displayedState(uint8_t state, uint32_t now, uint32_t damagedSince, uint32_t damagedTimeoutMs) {
  if (state == GS_DAMAGED && (uint32_t)(now - damagedSince) > damagedTimeoutMs) {
    return GS_ALIVE;
  }
  return state;
}
