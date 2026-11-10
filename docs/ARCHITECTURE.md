# Architecture

## Game runtime

The Godot project uses GDScript autoloads for settings, campaign flow, save state, audio, input routing, and the optional controller bridge. The boot scene routes into the main menu or into an automation path used by the existing test and screenshot tools.

```text
Keyboard + mouse ─┐
Gamepad ──────────┼─> InputRouter ─> Player / CameraRig / interactions
ControllerBridge ┘

Main menu ─> Briefing ─> MissionLevel ─> Results / next mission
                         ├─ MissionController + objectives
                         ├─ Enemy perception + state machine
                         ├─ Security systems + alarms
                         └─ SaveSystem checkpoints / campaign progress
```

Mission scenes and reusable systems are separated under `scenes/`, `scripts/`, and `resources/`. Mission-specific code lives in `scripts/missions/levels/`; shared mission flow lives in `scripts/missions/`.

## Controller runtime

The firmware samples two analog joysticks and buttons, applies the configured axis mapping and dead zone, and sends newline-terminated `SPV2` frames over USB serial at 115200 baud. It also receives game state and health messages for the OLED and LEDs.

`controller_bridge/serial_bridge.py` owns the COM port. It validates controller messages and relays input to Godot over UDP at `127.0.0.1:42420`. Game state flows back to the bridge on `127.0.0.1:42421`, then over serial to the Uno. Both UDP endpoints are loopback-only.

The game consumes external input through the same input routing layer as keyboard, mouse, and gamepad input. If the serial or UDP link is lost, the bridge reports disconnection and the controller input provider stops applying movement, camera, fire, and interact input.

For exact packet fields and reconnect behavior, see [ARDUINO_INTEGRATION.md](../ARDUINO_INTEGRATION.md).
