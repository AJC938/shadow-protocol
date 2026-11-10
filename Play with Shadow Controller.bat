@echo off
setlocal
rem Start the serial bridge and the game using a locally installed Godot runtime.
rem Close Arduino IDE's Serial Monitor before launching; it owns the COM port.
cd /d "%~dp0"

if not exist "build\windows\ShadowProtocol_runtime.exe" (
  where godot >nul 2>&1
  if errorlevel 1 (
    echo Godot 4.7.2 Standard was not found on PATH.
    echo Install Godot and make its executable available as "godot", then retry.
    pause
    exit /b 1
  )
)

start "SHADOW CONTROLLER V2 BRIDGE" cmd /c "controller_bridge\run_bridge.bat %*"
timeout /t 2 /nobreak >nul
if exist "build\windows\ShadowProtocol_runtime.exe" if exist "build\windows\ShadowProtocol.pck" (
  start "" "build\windows\ShadowProtocol_runtime.exe" --main-pack "build\windows\ShadowProtocol.pck"
) else (
  start "" godot --path "%~dp0."
)
