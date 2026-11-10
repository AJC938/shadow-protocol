# SHADOW CONTROLLER V2 — Arduino integration

```
Arduino Uno ──USB serial 115200──► controller_bridge/serial_bridge.py ──UDP 127.0.0.1:42420──► SHADOW PROTOCOL
  (OLED)    ◄──PING / SPSTATE / SPHEALTH──                          ◄──UDP 127.0.0.1:42421── (ControllerBridge.gd)
```
Godot has no reliable built-in serial API, so a small Python bridge owns the COM port and
talks to the game over **localhost-only** UDP. The game is fully playable without it.

## Quick start
1. Flash `controller_firmware/ShadowController_V2_Link/` to the Uno (see *Flashing*).
2. Plug the controller in. Close the Arduino IDE **Serial Monitor** (it would hold the COM port).
3. Double-click **`Play with Shadow Controller.bat`** in the project folder
   (or run `controller_bridge\run_bridge.bat`, then start the game normally).
4. OLED: `PC LINK: CONNECTED`, then `PLAYER: ALIVE` once a mission starts.

## Hardware wiring (Arduino Uno)

| Component | Signal | Uno pin |
| --- | --- | --- |
| OLED, I2C address `0x3C` | SDA | A4 |
| OLED | SCL / SCK | A5 |
| Joystick 1 | VRx / VRy / SW | A0 / A1 / D2 |
| Joystick 2 | VRx / VRy / SW | A2 / A3 / D3 |
| Yellow LED | Anode through a series resistor | D6 |
| Red LED | Anode through a series resistor | D7 |
| All modules | GND | Common GND |

Power the Uno over USB. Connect all module grounds to the Uno's ground. Use a suitable current-limiting resistor for each LED (typically 220–330 Ω). Check the OLED breakout's documented supply and logic-voltage compatibility before connecting it; some modules are 3.3 V only, while others include regulation and level shifting. Do not assume every SSD1306 board tolerates 5 V.

## Control mapping (tactical layout)
| Hardware | Game action | Notes |
|---|---|---|
| **Joystick 1 X** (A0, mapped) | Camera yaw — look left/right | analog look *velocity*; centred = stops immediately |
| **Joystick 1 Y** (A1, mapped) | Camera pitch — look up/down | stick up = look up; clamped −70°…+55° |
| **Joystick 1 button** (D2) | **Fire** | existing weapons: pistol & shotgun one shot per press, rifle automatic while held |
| **Joystick 2 X** (A2, mapped) | Strafe left/right | analog |
| **Joystick 2 Y** (A3, mapped) | Move forward/back | stick up = forward; combined with X, diagonals normalised |
| **Joystick 2 button** (D3) | **Interact** | press = doors, pickups, lockers; hold = hack terminals |

- Movement and look go through the existing `InputRouter` → `CameraRig` / `Player` (camera-relative
  movement, same speeds, animations, pitch clamp). Mouse, keyboard and gamepad keep working at the same
  time (mouse look and stick look simply add; neither is applied twice).
- Dead zone = firmware's 130/512, rescaled so there is no jump at its edge.
- Look: 150°/s at full deflection × **Settings → Controls → Controller look sensitivity** (0.2–3.0),
  response curve for fine aim, **Controller look smoothing** (0–0.3 s, default 0.05), **Controller invert look Y**.

## OLED — game status display
Joystick X/Y readouts were removed; the screen shows only game status:
```
        SHADOW PROTOCOL
PC LINK: CONNECTED            (or PC LINK: DISCONNECTED -> "STANDBY")
──────────────────────────────
            PLAYER:
       A L I V E              (large: ALIVE / DAMAGED / DEAD / PAUSED;
          HEALTH 75%           MISSION COMPLETE, GAME: READY in menus)
```
- `DAMAGED` flashes inverted after a real hit, then returns to `ALIVE` when the game sends it
  (~1.2 s). Safety fallback in firmware: DAMAGED with no update for 3 s shows ALIVE.
- `PC LINK: CONNECTED` only while the PC heartbeat arrives (1.5 s timeout) — USB power alone is not "connected".

## Game states (real game events only)
Priority: **DEAD > PAUSED > MISSION_COMPLETE > DAMAGED (transient) > ALIVE > READY**
| State | Source in the game |
|---|---|
| READY | main menu, briefing, any non-mission scene |
| ALIVE | mission running, player alive (also after a checkpoint respawn — new player) |
| DAMAGED | `Player.damaged` signal (emitted only when `Health` actually applies damage); held `damaged_display_time` = 1.2 s |
| DEAD | player health reached 0 (`Health` / `Player.died`) — a lethal hit goes straight to DEAD |
| PAUSED | pause menu (`SceneTree.paused`) |
| MISSION_COMPLETE | `MissionController.finished` (extraction), results and ending screens |

States are sent on change and re-sent once per second (not every frame); health % (`SPHEALTH`) on change.

## Serial protocol (115200 baud, lines end with `\n`)
Arduino → PC (unchanged)
- `SPV2,DATA,<seq>,<J1X>,<J1Y>,<J2X>,<J2Y>,<B1>,<B2>` — 50 Hz; axes 0–1023 **after** SWAP/INVERT; buttons 1 = pressed
- `SPV2,READY,<oled 0/1>` — once after boot · `# …` — boot diagnostics (ignored)

PC → Arduino
- `SPV2,PING` — heartbeat every 500 ms
- `SPSTATE,READY|ALIVE|DAMAGED|DEAD|PAUSED|MISSION_COMPLETE` — on change, re-sent every 2 s
- `SPHEALTH,<0..100>` — optional health %, on change and with each state re-send

Bridge ↔ game (UDP, 127.0.0.1 only): bridge → game `CTRL,<seq>,<J1X>,<J1Y>,<J2X>,<J2Y>,<B1>,<B2>`, `LINK,<0/1>,<port>`;
game → bridge `SPSTATE,<state>`, `SPHEALTH,<pct>`.

## Safety
- Disconnect: no frame for 250 ms, or `LINK,0` from the bridge, stops movement, stops camera rotation and releases fire/interact.
- Bridge auto-detects Arduino/CH340/FTDI/CP210x ports, **ignores Bluetooth ports**, confirms SPV2 traffic, reconnects after unplug/reset, never blocks the serial reader (non-blocking UDP).
- One bridge only (exclusive UDP 42421); pyserial opens the COM port exclusively.

## Firmware
- `controller_firmware/ShadowController_V2_Link/ShadowController_V2_Link.ino` + `link_protocol.h` — current firmware (v2).
- `controller_firmware/backup_link_v1/` — previous link firmware (joystick dashboard). Git tag `controller-v1-baseline` = whole project before this change.
- `controller_firmware/original_backup/COntrol_game/` — untouched original `COntrol_game.ino`.
- Unchanged: pins, I2C OLED init (scan + `begin(0x3C)`), 3 yellow flashes, red LED on, 115200 baud, frame format.
- Fixed in v2: v1's 24-byte receive buffer silently dropped `SPSTATE,MISSION_COMPLETE` (24 chars); buffer is now 32.
- Build (Uno): flash **18 294 B (56 %)**, globals **609 B (29 %)** (+1 KB OLED buffer at runtime).

### Flashing
Arduino IDE: open `controller_firmware\ShadowController_V2_Link\ShadowController_V2_Link.ino` (the `link_protocol.h`
tab opens with it) → *Tools › Board › Arduino Uno* → *Tools › Port* → the controller's port (**not COM3/COM4**, those
are Bluetooth) → **Upload**. Close the Serial Monitor afterwards.

CLI (from the project folder; replace COMx):
```
arduino-cli compile --fqbn arduino:avr:uno controller_firmware/ShadowController_V2_Link
arduino-cli upload  --fqbn arduino:avr:uno -p COMx controller_firmware/ShadowController_V2_Link
```

## Troubleshooting
| Symptom | Fix |
|---|---|
| Bridge: "no Arduino USB serial port found" | cable/driver; `run_bridge.bat --list`; set `"port": "COM5"` in `controller_bridge/config.json` |
| Bridge: cannot open COMx | close the Arduino IDE Serial Monitor / other serial programs |
| Bridge: "UDP port 42421 is busy" | a bridge is already running |
| OLED `PC LINK: DISCONNECTED` | bridge not running or wrong port |
| Camera too fast/slow, inverted | Settings → Controls → controller look sensitivity / smoothing / invert |
| Camera or player drifts | re-centre sticks; raise `DEADZONE` in the firmware |

## Tests
- Python: `python -m unittest discover -s controller_bridge/tests -v` (19 tests)
- Firmware parser on the PC: `g++ -std=c++17 -I controller_firmware/ShadowController_V2_Link controller_firmware/tests/firmware_link_test.cpp -o fwtest && fwtest` (33 checks)
- Godot: `tests/integration/test_controller.gd` (17 tests) inside the full suite
- Chain simulation: `python controller_bridge/fake_arduino.py` + `python controller_bridge/serial_bridge.py --port socket://127.0.0.1:47000` + the game
