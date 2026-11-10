@echo off
setlocal
rem Launch a local packaged build when present; otherwise run the Godot source project.
cd /d "%~dp0"
if exist "build\windows\ShadowProtocol_runtime.exe" if exist "build\windows\ShadowProtocol.pck" (
  start "" "build\windows\ShadowProtocol_runtime.exe" --main-pack "build\windows\ShadowProtocol.pck"
  exit /b 0
)
where godot >nul 2>&1
if errorlevel 1 (
  echo Godot 4.7.2 Standard was not found on PATH.
  echo Install Godot and make its executable available as "godot", then retry.
  pause
  exit /b 1
)
start "" godot --path "%~dp0."
