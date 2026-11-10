
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>

// ============================================
// SHADOW PROTOCOL
// SHADOW CONTROLLER V2
// OLED + DUAL JOYSTICK + LEDS
// Arduino UNO
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

// LEDS - NEW PINS
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
const unsigned long UPDATE_INTERVAL = 1000;
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

unsigned long lastUpdate = 0;

// ============================================
// OLED INITIALIZATION
// ============================================

void initializeOLED() {

  Wire.begin();
  Wire.setClock(100000);

  Serial.println(F("[OLED] SCANNING..."));

  bool found = false;

  for (byte address = 1; address < 127; address++) {

    Wire.beginTransmission(address);

    if (Wire.endTransmission() == 0) {

      Serial.print(F("[I2C] DEVICE: 0x"));
      Serial.println(address, HEX);

      if (address == OLED_ADDRESS) {
        found = true;
      }
    }
  }

  if (!found) {
    Serial.println(F("[OLED] DEVICE NOT FOUND"));
    return;
  }

  oledReady = display.begin(
    SSD1306_SWITCHCAPVCC,
    OLED_ADDRESS
  );

  if (oledReady) {
    Serial.println(F("[OLED] INITIALIZED"));
  } else {
    Serial.println(F("[OLED] INITIALIZATION FAILED"));
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
// STARTUP SEQUENCE
// ============================================

void startupSequence() {

  digitalWrite(YELLOW_LED, LOW);
  digitalWrite(RED_LED, LOW);

  Serial.println();
  Serial.println(F("================================"));
  Serial.println(F("     SHADOW PROTOCOL"));
  Serial.println(F("     SYSTEM BOOTING"));
  Serial.println(F("================================"));

  showMessage(
    F("SHADOW PROTOCOL"),
    F("SYSTEM BOOTING"),
    F("INITIALIZING...")
  );

  // Yellow LED flashes 3 times

  for (int i = 1; i <= 3; i++) {

    Serial.print(F("[YELLOW LED] FLASH "));
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

  Serial.println(F("[SYSTEM] CONTROL ON"));
  Serial.println(F("[YELLOW] OFF"));
  Serial.println(F("[RED] ON"));

  showMessage(
    F("SHADOW PROTOCOL"),
    F("CONTROL: ON"),
    F("JOYSTICKS READY")
  );

  delay(1000);
}

// ============================================
// BUTTON INITIALIZATION
// ============================================

void initButton(Button &button, int pin) {

  bool state = digitalRead(pin) == LOW;

  button.lastReading = state;
  button.stable = state;
  button.lastChange = millis();
}

// ============================================
// BUTTON DEBOUNCE
// ============================================

bool readButton(
  Button &button,
  int pin,
  byte number
) {

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

    Serial.print(F("[BUTTON EVENT] J"));
    Serial.print(number);

    Serial.println(
      button.stable ? F(" PRESSED") : F(" RELEASED")
    );
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
  bool invertY,
  byte number
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

  j.pressed = readButton(
    button,
    swPin,
    number
  );
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

void printDirection(Print &out, int x, int y) {

  bool left = x < CENTER - DEADZONE;
  bool right = x > CENTER + DEADZONE;

  bool up = y < CENTER - DEADZONE;
  bool down = y > CENTER + DEADZONE;

  if (up && right) out.print(F("UP-RIGHT"));
  else if (up && left) out.print(F("UP-LEFT"));
  else if (down && right) out.print(F("DOWN-RIGHT"));
  else if (down && left) out.print(F("DOWN-LEFT"));
  else if (up) out.print(F("UP"));
  else if (down) out.print(F("DOWN"));
  else if (left) out.print(F("LEFT"));
  else if (right) out.print(F("RIGHT"));
  else out.print(F("CENTER"));
}

// ============================================
// OLED DASHBOARD
// ============================================

void updateOLED() {

  if (!oledReady) return;

  display.clearDisplay();

  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);

  // Game title
  display.setCursor(12, 0);
  display.println(F("SHADOW PROTOCOL"));

  // Controller status
  display.setCursor(0, 11);
  display.println(F("CONTROL: ON"));

  // Joystick 1
  display.setCursor(0, 22);

  display.print(F("J1 X:"));
  display.print(j1.x);

  display.print(F(" Y:"));
  display.println(j1.y);

  display.setCursor(0, 32);

  display.print(F("J1 X:"));
  printXState(display, j1.x);

  display.print(F(" Y:"));
  printYState(display, j1.y);

  display.print(F(" B:"));
  display.println(j1.pressed ? F("PRESS") : F("REL"));

  // Joystick 2
  display.setCursor(0, 43);

  display.print(F("J2 X:"));
  display.print(j2.x);

  display.print(F(" Y:"));
  display.println(j2.y);

  display.setCursor(0, 53);

  display.print(F("J2 X:"));
  printXState(display, j2.x);

  display.print(F(" Y:"));
  printYState(display, j2.y);

  display.print(F(" B:"));
  display.println(j2.pressed ? F("PRESS") : F("REL"));

  display.display();
}

// ============================================
// SERIAL REPORT
// ============================================

void printJoystick(
  const __FlashStringHelper *name,
  Joystick &j
) {

  Serial.println();
  Serial.println(name);

  Serial.print(F("RAW X: "));
  Serial.print(j.rawX);

  Serial.print(F(" | RAW Y: "));
  Serial.println(j.rawY);

  Serial.print(F("GAME X: "));
  Serial.print(j.x);

  Serial.print(F(" | GAME Y: "));
  Serial.println(j.y);

  Serial.print(F("X STATE: "));
  printXState(Serial, j.x);
  Serial.println();

  Serial.print(F("Y STATE: "));
  printYState(Serial, j.y);
  Serial.println();

  Serial.print(F("GEAR COMMAND: "));
  printDirection(Serial, j.x, j.y);
  Serial.println();

  Serial.print(F("PUSH BUTTON: "));
  Serial.println(j.pressed ? F("PRESSED") : F("RELEASED"));
}

void updateSerial() {

  Serial.println();
  Serial.println(F("================================"));
  Serial.println(F("SHADOW PROTOCOL - CONTROLLER"));

  Serial.print(F("OLED: "));
  Serial.println(oledReady ? F("CONNECTED") : F("FAILED"));

  Serial.print(F("YELLOW LED: "));
  Serial.println(digitalRead(YELLOW_LED) ? F("ON") : F("OFF"));

  Serial.print(F("RED LED: "));
  Serial.println(digitalRead(RED_LED) ? F("ON") : F("OFF"));

  Serial.println(F("CONTROL: ON"));

  printJoystick(F("JOYSTICK 1"), j1);
  printJoystick(F("JOYSTICK 2"), j2);

  Serial.println(F("================================"));
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

  // Initialize buttons
  initButton(b1, J1_SW);
  initButton(b2, J2_SW);

  // OLED
  initializeOLED();

  // Startup
  startupSequence();

  // Initial joystick readings
  readJoystick(
    j1, b1, J1_X, J1_Y, J1_SW,
    SWAP_J1, INVERT_J1_X, INVERT_J1_Y, 1
  );

  readJoystick(
    j2, b2, J2_X, J2_Y, J2_SW,
    SWAP_J2, INVERT_J2_X, INVERT_J2_Y, 2
  );

  updateOLED();

  Serial.println(F("[SYSTEM] CONTROLLER READY"));
}

// ============================================
// MAIN LOOP
// ============================================

void loop() {

  // Read both joysticks continuously
  readJoystick(
    j1, b1, J1_X, J1_Y, J1_SW,
    SWAP_J1, INVERT_J1_X, INVERT_J1_Y, 1
  );

  readJoystick(
    j2, b2, J2_X, J2_Y, J2_SW,
    SWAP_J2, INVERT_J2_X, INVERT_J2_Y, 2
  );

  // Maintain running LED state
  digitalWrite(YELLOW_LED, LOW);
  digitalWrite(RED_LED, HIGH);

  unsigned long now = millis();

  // OLED + Serial update every secondS
  if (now - lastUpdate >= UPDATE_INTERVAL) {

    lastUpdate = now;

    updateOLED();
    updateSerial();
  }
}
