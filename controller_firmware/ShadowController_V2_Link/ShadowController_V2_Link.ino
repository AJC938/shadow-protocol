
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include "link_protocol.h"

// ============================================
// SHADOW PROTOCOL
// SHADOW CONTROLLER V2 - LINK FIRMWARE v2 (game status display)
// OLED + DUAL JOYSTICK + LEDS + GAME LINK
// Arduino UNO
//
// Based on COntrol_game.ino (original kept in controller_firmware/original_backup;
// link firmware v1 kept in controller_firmware/backup_link_v1). Same pins, same OLED
// initialisation, same boot sequence. The OLED is now a GAME STATUS display.
//
// SERIAL PROTOCOL (115200 baud, '\n' terminated)
//  Arduino -> PC
//   SPV2,DATA,<seq>,<J1X>,<J1Y>,<J2X>,<J2Y>,<B1>,<B2>   50 Hz
//   SPV2,READY,<oled 0/1>                                once after boot
//   # ...                                                boot diagnostics only
//  PC -> Arduino
//   SPV2,PING                                            heartbeat (~500 ms)
//   SPSTATE,READY|ALIVE|DAMAGED|DEAD|PAUSED|MISSION_COMPLETE
//   SPHEALTH,<0..100>                                    optional health %
// Axis values are AFTER the SWAP / INVERT mapping. Game logic (movement, camera)
// lives in the game; the controller only reports sticks and buttons.
// ============================================

// OLED
#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define OLED_RESET -1
#define OLED_ADDRESS 0x3C

Adafruit_SSD1306 display(
  SCREEN_WIDTH,
  SCREEN_HEIGHT,
  &Wire,
  OLED_RESET
);

bool oledReady = false;

// JOYSTICK 1 (camera / fire)
#define J1_X A0
#define J1_Y A1
#define J1_SW 2

// JOYSTICK 2 (movement / interact)
#define J2_X A2
#define J2_Y A3
#define J2_SW 3

// LEDS
#define YELLOW_LED 6
#define RED_LED 7

// AXIS CONFIGURATION
const int CENTER = 512;
const int DEADZONE = 130;

const bool SWAP_J1 = true;
const bool SWAP_J2 = true;

const bool INVERT_J1_X = false;
const bool INVERT_J1_Y = false;
const bool INVERT_J2_X = false;
const bool INVERT_J2_Y = false;

// TIMING
const unsigned long FRAME_INTERVAL = 20;       // 50 Hz controller frames
const unsigned long OLED_INTERVAL = 200;       // OLED refresh
const unsigned long LINK_TIMEOUT = 1500;       // no PING for this long = link lost
const unsigned long DAMAGED_TIMEOUT = 3000;    // safety fallback DAMAGED -> ALIVE
const unsigned long DEBOUNCE_MS = 35;

// DATA STRUCTURES
struct Joystick {
  int rawX;
  int rawY;
  int x;
  int y;
  bool pressed;
};

struct Button {
  bool lastReading;
  bool stable;
  unsigned long lastChange;
};

Joystick j1, j2;
Button b1, b2;

// GAME LINK STATE
uint8_t gameState = GS_NONE;
uint8_t healthPct = 255;          // 255 = unknown
unsigned long lastPing = 0;
unsigned long damagedSince = 0;
bool everLinked = false;
bool blink = false;

uint16_t frameSeq = 0;
unsigned long lastFrame = 0;
unsigned long lastOled = 0;

LineReader rx;

// ============================================
// OLED INITIALIZATION (unchanged from the working firmware)
// ============================================

void initializeOLED() {

  Wire.begin();
  Wire.setClock(100000);

  Serial.println(F("# [OLED] SCANNING..."));

  bool found = false;

  for (byte address = 1; address < 127; address++) {

    Wire.beginTransmission(address);

    if (Wire.endTransmission() == 0) {

      Serial.print(F("# [I2C] DEVICE: 0x"));
      Serial.println(address, HEX);

      if (address == OLED_ADDRESS) {
        found = true;
      }
    }
  }

  if (!found) {
    Serial.println(F("# [OLED] DEVICE NOT FOUND"));
    return;
  }

  oledReady = display.begin(
    SSD1306_SWITCHCAPVCC,
    OLED_ADDRESS
  );

  if (oledReady) {
    Serial.println(F("# [OLED] INITIALIZED"));
  } else {
    Serial.println(F("# [OLED] INITIALIZATION FAILED"));
  }
}

// ============================================
// OLED MESSAGE
// ============================================

void showMessage(
  const __FlashStringHelper *line1,
  const __FlashStringHelper *line2,
  const __FlashStringHelper *line3
) {

  if (!oledReady) return;

  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);
  display.setTextSize(1);

  display.setCursor(8, 5);
  display.println(line1);

  display.setCursor(8, 27);
  display.println(line2);

  display.setCursor(8, 47);
  display.println(line3);

  display.display();
}

// ============================================
// STARTUP SEQUENCE (unchanged behaviour)
// ============================================

void startupSequence() {

  digitalWrite(YELLOW_LED, LOW);
  digitalWrite(RED_LED, LOW);

  Serial.println(F("# SHADOW PROTOCOL - SYSTEM BOOTING"));

  showMessage(
    F("SHADOW PROTOCOL"),
    F("SYSTEM BOOTING"),
    F("INITIALIZING...")
  );

  // Yellow LED flashes 3 times
  for (int i = 1; i <= 3; i++) {

    Serial.print(F("# [YELLOW LED] FLASH "));
    Serial.println(i);

    digitalWrite(YELLOW_LED, HIGH);

    showMessage(
      F("SHADOW PROTOCOL"),
      F("BOOT SEQUENCE"),
      F("INITIALIZING...")
    );

    delay(300);

    digitalWrite(YELLOW_LED, LOW);

    delay(300);
  }

  // Controller becomes ON
  digitalWrite(YELLOW_LED, LOW);
  digitalWrite(RED_LED, HIGH);

  Serial.println(F("# [SYSTEM] CONTROL ON"));

  showMessage(
    F("SHADOW PROTOCOL"),
    F("CONTROL: ON"),
    F("JOYSTICKS READY")
  );

  delay(1000);
}

// ============================================
// BUTTONS (debounced, silent - no text in the data stream)
// ============================================

void initButton(Button &button, int pin) {

  bool state = digitalRead(pin) == LOW;

  button.lastReading = state;
  button.stable = state;
  button.lastChange = millis();
}

bool readButton(Button &button, int pin) {

  unsigned long now = millis();

  bool reading = digitalRead(pin) == LOW;

  if (reading != button.lastReading) {
    button.lastReading = reading;
    button.lastChange = now;
  }

  if (
    now - button.lastChange >= DEBOUNCE_MS &&
    button.stable != button.lastReading
  ) {
    button.stable = button.lastReading;
  }

  return button.stable;
}

// ============================================
// JOYSTICK READING
// ============================================

void readJoystick(
  Joystick &j,
  Button &button,
  int xPin,
  int yPin,
  int swPin,
  bool swap,
  bool invertX,
  bool invertY
) {

  j.rawX = analogRead(xPin);
  j.rawY = analogRead(yPin);

  if (swap) {
    j.x = j.rawY;
    j.y = j.rawX;
  } else {
    j.x = j.rawX;
    j.y = j.rawY;
  }

  if (invertX) j.x = 1023 - j.x;
  if (invertY) j.y = 1023 - j.y;

  j.pressed = readButton(button, swPin);
}

// ============================================
// GAME LINK
// ============================================

bool linkConnected() {
  return everLinked && (millis() - lastPing < LINK_TIMEOUT);
}

// Non-blocking: consumes at most 32 bytes per loop so sampling never stalls.
void processSerialInput() {

  byte budget = 32;

  while (budget-- && Serial.available() > 0) {

    if (!rx.feed((char)Serial.read())) continue;

    uint8_t state = GS_NONE;
    uint8_t health = 0;
    uint8_t msg = parseLinkLine(rx.buf, &state, &health);

    if (msg == MSG_NONE) continue;   // malformed / unknown: ignored

    lastPing = millis();             // any valid message proves the PC link
    everLinked = true;

    if (msg == MSG_STATE) {
      if (state == GS_DAMAGED) damagedSince = lastPing;
      if (state != gameState) {
        gameState = state;
        lastOled = 0;                // redraw now
      }
    }
    else if (msg == MSG_HEALTH) {
      healthPct = health;
    }
  }
}

// One controller frame. Skipped (never blocks) if the TX buffer is busy.
void sendFrame() {

  if (Serial.availableForWrite() < 40) return;

  frameSeq++;

  Serial.print(F("SPV2,DATA,"));
  Serial.print(frameSeq);
  Serial.write(',');
  Serial.print(j1.x);
  Serial.write(',');
  Serial.print(j1.y);
  Serial.write(',');
  Serial.print(j2.x);
  Serial.write(',');
  Serial.print(j2.y);
  Serial.write(',');
  Serial.write(j1.pressed ? '1' : '0');
  Serial.write(',');
  Serial.write(j2.pressed ? '1' : '0');
  Serial.write('\n');
}

// ============================================
// OLED GAME STATUS DISPLAY
// ============================================

// Prints flash text centred horizontally (size 1 = 6 px, size 2 = 12 px per char).
void printCentered(const __FlashStringHelper *text, byte size, byte y) {
  byte len = strlen_P((PGM_P)text);
  int x = (SCREEN_WIDTH - (int)len * 6 * size) / 2;
  if (x < 0) x = 0;
  display.setTextSize(size);
  display.setCursor(x, y);
  display.print(text);
}

void updateOLED() {

  if (!oledReady) return;

  bool link = linkConnected();
  uint8_t shown = displayedState(gameState, millis(), damagedSince, DAMAGED_TIMEOUT);
  blink = !blink;

  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);

  // Header + connection
  printCentered(F("SHADOW PROTOCOL"), 1, 0);
  display.setTextSize(1);
  display.setCursor(0, 11);
  display.print(link ? F("PC LINK: CONNECTED") : F("PC LINK: DISCONNECTED"));
  display.drawFastHLine(0, 21, SCREEN_WIDTH, SSD1306_WHITE);

  if (!link) {
    printCentered(F("CONTROLLER ON"), 1, 26);
    printCentered(F("STANDBY"), 2, 37);
    printCentered(F("START BRIDGE + GAME"), 1, 56);
    display.display();
    return;
  }

  // Main status: small label + large state word
  bool showHealth = false;
  switch (shown) {
    case GS_ALIVE:
      printCentered(F("PLAYER:"), 1, 26);
      printCentered(F("ALIVE"), 2, 37);
      showHealth = true;
      break;
    case GS_DAMAGED:
      // Flashing inverted banner so a hit is noticed at a glance.
      if (blink) {
        display.fillRect(0, 35, SCREEN_WIDTH, 19, SSD1306_WHITE);
        display.setTextColor(SSD1306_BLACK);
      }
      printCentered(F("DAMAGED"), 2, 37);
      display.setTextColor(SSD1306_WHITE);
      printCentered(F("PLAYER:"), 1, 26);
      showHealth = true;
      break;
    case GS_DEAD:
      printCentered(F("PLAYER:"), 1, 26);
      printCentered(F("DEAD"), 2, 37);
      printCentered(F("AWAITING RESPAWN"), 1, 56);
      break;
    case GS_PAUSED:
      printCentered(F("PLAYER:"), 1, 26);
      printCentered(F("PAUSED"), 2, 37);
      printCentered(F("GAME PAUSED"), 1, 56);
      break;
    case GS_COMPLETE:
      printCentered(F("MISSION"), 1, 26);
      printCentered(F("COMPLETE"), 2, 37);
      printCentered(F("EXTRACTION OK"), 1, 56);
      break;
    case GS_READY:
      printCentered(F("GAME:"), 1, 26);
      printCentered(F("READY"), 2, 37);
      printCentered(F("MAIN MENU / BRIEFING"), 1, 56);
      break;
    default:
      printCentered(F("GAME:"), 1, 26);
      printCentered(F("LINKING"), 2, 37);
      break;
  }

  if (showHealth && healthPct <= 100) {
    display.setTextSize(1);
    display.setCursor(31, 56);
    display.print(F("HEALTH "));
    display.print(healthPct);
    display.print('%');
  }

  display.display();
}

// ============================================
// SETUP
// ============================================

void setup() {

  Serial.begin(115200);

  // Joystick buttons
  pinMode(J1_SW, INPUT_PULLUP);
  pinMode(J2_SW, INPUT_PULLUP);

  // LED outputs
  pinMode(YELLOW_LED, OUTPUT);
  pinMode(RED_LED, OUTPUT);

  digitalWrite(YELLOW_LED, LOW);
  digitalWrite(RED_LED, LOW);

  initButton(b1, J1_SW);
  initButton(b2, J2_SW);

  initializeOLED();

  startupSequence();

  readJoystick(j1, b1, J1_X, J1_Y, J1_SW, SWAP_J1, INVERT_J1_X, INVERT_J1_Y);
  readJoystick(j2, b2, J2_X, J2_Y, J2_SW, SWAP_J2, INVERT_J2_X, INVERT_J2_Y);

  rx.reset();

  updateOLED();

  // Discard anything the PC sent while we were booting.
  while (Serial.available() > 0) Serial.read();

  Serial.print(F("SPV2,READY,"));
  Serial.write(oledReady ? '1' : '0');
  Serial.write('\n');

  unsigned long now = millis();
  lastFrame = now;
  lastOled = now;
}

// ============================================
// MAIN LOOP (non-blocking)
// ============================================

void loop() {

  // Read both joysticks continuously
  readJoystick(j1, b1, J1_X, J1_Y, J1_SW, SWAP_J1, INVERT_J1_X, INVERT_J1_Y);
  readJoystick(j2, b2, J2_X, J2_Y, J2_SW, SWAP_J2, INVERT_J2_X, INVERT_J2_Y);

  // Maintain running LED state
  digitalWrite(YELLOW_LED, LOW);
  digitalWrite(RED_LED, HIGH);

  processSerialInput();

  unsigned long now = millis();

  // 50 Hz controller frames
  if (now - lastFrame >= FRAME_INTERVAL) {
    lastFrame += FRAME_INTERVAL;
    if (now - lastFrame >= FRAME_INTERVAL) lastFrame = now;  // catch up after OLED refresh
    sendFrame();
  }

  // OLED refresh (independent of the data stream)
  if (now - lastOled >= OLED_INTERVAL) {
    lastOled = now;
    updateOLED();
  }
}
