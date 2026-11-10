# SHADOW CONTROLLER V2 bridge

See ../ARDUINO_INTEGRATION.md for setup, mapping, protocol and troubleshooting.

- `run_bridge.bat` — start (auto-detects the Uno; `--port COM5` to force, `--list` to list ports)
- `config.json` — COM port, baud, localhost UDP ports, timings
- `serial_bridge.py` / `protocol.py` — bridge and protocol
- `fake_arduino.py` — firmware simulator for testing without hardware
- `tests/` — `python -m unittest discover -s controller_bridge/tests -v`
