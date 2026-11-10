@echo off
rem SHADOW CONTROLLER V2 serial bridge.
rem   run_bridge.bat            auto-detect the Arduino Uno (Bluetooth ports are ignored)
rem   run_bridge.bat --port COM5   use a specific port
rem   run_bridge.bat --list     show serial ports
title SHADOW CONTROLLER V2 BRIDGE
cd /d "%~dp0"
python --version >nul 2>&1 || (echo Python 3 is required: https://www.python.org/downloads/ & pause & exit /b 1)
python -c "import serial" >nul 2>&1 || (
  echo Installing pyserial...
  python -m pip install -r requirements.txt || (echo pip install failed & pause & exit /b 1)
)
python serial_bridge.py %*
pause
