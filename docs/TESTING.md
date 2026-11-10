# Testing and validation

The repository contains a Godot test runner, Python bridge tests, and a firmware protocol test. The committed report at `docs/test_results_latest.json` records **60 passed and 0 failed** for the Godot suite. This is the last stored result and was not rerun for publication.

## Godot suite

From the project root, with Godot 4.7.2 available as `godot`:

```powershell
godot --headless --path . --fixed-fps 60 res://tests/test_runner.tscn
```

The suite covers input routing, saves, health, settings, AI perception and state transitions, player and weapon behavior, gadgets, security, controller integration, and mission walkthroughs.

## Python bridge

```powershell
python -m unittest discover -s controller_bridge/tests -v
```

## Firmware protocol

With a C++17 compiler installed:

```powershell
g++ -std=c++17 -I controller_firmware/ShadowController_V2_Link controller_firmware/tests/firmware_link_test.cpp -o fwtest.exe
.\fwtest.exe
```

The existing integration guide records 19 Python bridge tests and 33 firmware parser checks from its prior validation. These figures are historical documentation; they are not a new publication-time test run.

## Hardware validation

The included hardware photographs show the prototype connected to a running game. They are visual evidence only; this repository does not claim automated electrical safety or a fresh hardware test from publication.
