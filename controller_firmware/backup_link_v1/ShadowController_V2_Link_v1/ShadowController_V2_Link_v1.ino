
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>

// ============================================
// SHADOW PROTOCOL
// SHADOW CONTROLLER V2 - LINK FIRMWARE
// OLED + DUAL JOYSTICK + LEDS + GAME LINK
// Arduino UNO
//
// Based on COntrol_game.ino (original kept in
// controller_firmware/original_backup). Same pins,
// same OLED initialisation, same boot sequence.
//
// SERIAL PROTOCOL (115200 baud, '\n' terminated)
//  Arduino -> PC
//   SPV2,DATA,<seq>,<J1X>,<J1Y>,<J2X>,<J2Y>,<B1>,<B2>   50 Hz
//   SPV2,READY,<oled 0/1>                                once after boot
//   # ...                                                boot diagnostics only
//  PC -> Arduino
//   SPV2,PING                                            heartbeat (~500 ms)
//   SPSTATE,READY|ALIVE|DEAD|PAUSED|MISSION_COMPLETE
// Axis values are AFTER the SWAP / INVERT mapping.
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

// JOYSTICK 1
#define J1_X A0
#define J1_Y A1
#define J1_SW 2

// JOYSTICK 2
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
const unsigned long FRAME_INTERVAL = 20;    // 50 Hz controller frames
const unsigned long OLED_INTERVAL = 300;    // OLED refresh
const unsigned long PAGE_INTERVAL = 2500;   // dashboard page rotation
const unsigned long LINK_TIMEOUT = 1500;    // no PING for this long = link lost
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
enum GameState : byte {
  GS_NONE,
  GS_READY,
  GS_ALIVE,
  GS_DEAD,
  GS_PAUSED,
  GS_COMPLETE
};

byte gameState = GS_NONE;
unsigned long lastPing = 0;
bool everLinked = false;

uint16_t frameSeq = 0;
unsigned long lastFrame = 0;
unsigned long lastOled = 0;
unsigned long lastPageSwitch = 0;
byte oledPage = 0;

char rxBuf[24];
byte rxLen = 0;
bool rxOverflow = false;

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
// AXIS STATES
// ============================================

void printXState(Print &out, int x) {

  if (x > CENTER + DEADZONE) {
    out.print(F("RIGHT"));
  }
  else if (x < CENTER - DEADZONE) {
    out.print(F("LEFT"));
  }
  else {
    out.print(F("CENTER"));
  }
}

void printYState(Print &out, int y) {

  if (y < CENTER - DEADZONE) {
    out.print(F("UP"));
  }
  else if (y > CENTER + DEADZONE) {
    out.print(F("DOWN"));
  }
  else {
    out.print(F("CENTER"));
  }
}

// ============================================
// GAME LINK
// ============================================

bool linkConnected() {
  return everLinked && (millis() - lastPing < LINK_TIMEOUT);
}

void setGameState(byte s) {
  if (s != gameState) {
    gameState = s;
    // Show the status page immediately when the game state changes.
    oledPage = 1;
    lastPageSwitch = millis();
    lastOled = 0;
  }
}

void handleLine() {

  if (strcmp_P(rxBuf, PSTR("SPV2,PING")) == 0) {
    lastPing = millis();
    everLinked = true;
    return;
  }

  if (strncmp_P(rxBuf, PSTR("SPSTATE,"), 8) == 0) {
    const char *s = rxBuf + 8;
    byte next = 0xFF;
    if (strcmp_P(s, PSTR("READY")) == 0) next = GS_READY;
    else if (strcmp_P(s, PSTR("ALIVE")) == 0) next = GS_ALIVE;
    else if (strcmp_P(s, PSTR("DEAD")) == 0) next = GS_DEAD;
    else if (strcmp_P(s, PSTR("PAUSED")) == 0) next = GS_PAUSED;
    else if (strcmp_P(s, PSTR("MISSION_COMPLETE")) == 0) next = GS_COMPLETE;
    if (next != 0xFF) {
      lastPing = millis();
      everLinked = true;
      setGameState(next);
    }
  }
  // Anything else is ignored (malformed / unknown).
}

// Non-blocking: consumes at most 32 bytes per loop so sampling never stalls.
void processSerialInput() {

  byte budget = 32;

  while (budget-- && Serial.available() > 0) {

    char c = (char)Serial.read();

    if (c == '\n' || c == '\r') {
      if (rxLen > 0 && !rxOverflow) {
        rxBuf[rxLen] = '\0';
        handleLine();
      }
      rxLen = 0;
      rxOverflow = false;
    }
    else if (rxLen < sizeof(rxBuf) - 1) {
      rxBuf[rxLen++] = c;
    }
    else {
      rxOverflow = true;   // line too long: drop it entirely
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
// OLED DASHBOARD - PAGE 0 (original joystick dashboard)
// ============================================

void drawJoystickPage() {

  display.setCursor(12, 0);
  display.println(F("SHADOW PROTOCOL"));

  display.setCursor(0, 11);
  display.print(F("CONTROL: ON  "));
  display.println(linkConnected() ? F("LINK:OK") : F("LINK:--"));

  // Joystick 1
  display.setCursor(0, 22);
  display.print(F("J1 X:"));
  display.print(j1.x);
  display.print(F(" Y:"));
  display.println(j1.y);

  display.setCursor(0, 32);
  display.print(F("X:"));
  printXState(display, j1.x);
  display.print(F(" Y:"));
  printYState(display, j1.y);
  display.print(j1.pressed ? F(" B:P") : F(" B:R"));

  // Joystick 2
  display.setCursor(0, 43);
  display.print(F("J2 X:"));
  display.print(j2.x);
  display.print(F(" Y:"));
  display.println(j2.y);

  display.setCursor(0, 53);
  display.print(F("X:"));
  printXState(display, j2.x);
  display.print(F(" Y:"));
  printYState(display, j2.y);
  display.print(j2.pressed ? F(" B:P") : F(" B:R"));
}

// ============================================
// OLED DASHBOARD - PAGE 1 (game link status)
// ============================================

void drawStatusPage() {

  bool link = linkConnected();

  display.setCursor(12, 0);
  display.println(F("SHADOW PROTOCOL"));

  display.setCursor(0, 12);
  display.println(F("CONTROLLER: ON"));

  display.setCursor(0, 23);
  display.print(F("PC LINK: "));
  display.println(link ? F("CONNECTED") : F("WAITING"));

  display.setCursor(0, 34);
  if (!link) {
    display.println(F("GAME: --"));
  } else {
    switch (gameState) {
      case GS_READY:    display.println(F("GAME: MENU/READY")); break;
      case GS_ALIVE:    display.println(F("PLAYER: ALIVE")); break;
      case GS_DEAD:     display.println(F("PLAYER: DEAD")); break;
      case GS_PAUSED:   display.println(F("GAME: PAUSED")); break;
      case GS_COMPLETE: display.println(F("MISSION COMPLETE")); break;
      default:          display.println(F("GAME: STARTING")); break;
    }
  }

  display.setCursor(0, 45);
  display.print(F("TX 50HZ SEQ:"));
  display.println(frameSeq);

  display.setCursor(0, 55);
  display.print(F("B1:"));
  display.print(j1.pressed ? F("FIRE ") : F("---- "));
  display.print(F("B2:"));
  display.print(j2.pressed ? F("USE") : F("---"));
}

void updateOLED() {

  if (!oledReady) return;

  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);

  if (oledPage == 0) {
    drawJoystickPage();
  } else {
    drawStatusPage();
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

  updateOLED();

  // Discard anything the PC sent while we were booting.
  while (Serial.available() > 0) Serial.read();

  Serial.print(F("SPV2,READY,"));
  Serial.write(oledReady ? '1' : '0');
  Serial.write('\n');

  unsigned long now = millis();
  lastFrame = now;
  lastOled = now;
  lastPageSwitch = now;
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

  // Alternate dashboard pages
  if (now - lastPageSwitch >= PAGE_INTERVAL) {
    lastPageSwitch = now;
    oledPage = oledPage == 0 ? 1 : 0;
    lastOled = 0;
  }

  // OLED refresh (independent of the data stream)
  if (now - lastOled >= OLED_INTERVAL) {
    lastOled = now;
    updateOLED();
  }
}
