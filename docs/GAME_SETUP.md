# Game setup (Windows 11)

## Run from source

1. Install Godot **4.7.2 Standard** (not the .NET build) and add the executable to `PATH` under the name `godot`.
2. Clone or extract the repository.
3. Double-click `Play SHADOW PROTOCOL.bat` from the project root, or open a terminal in the root and run:

   ```powershell
   godot --path .
   ```

The first editor or runtime launch may import project resources. The source project is the supported distribution in this repository; generated Windows export packages are excluded.

## Run without the physical controller

Use the normal launcher. Keyboard and mouse controls work by default, and standard gamepads are supported. No Python bridge is needed.

## Run with the physical controller

1. Install Python 3.10 or newer.
2. Flash `controller_firmware/ShadowController_V2_Link/ShadowController_V2_Link.ino` to an Arduino Uno. Install the Adafruit SSD1306 and Adafruit GFX libraries using Arduino IDE's Library Manager.
3. Connect the Uno over USB.
4. Close Arduino IDE's Serial Monitor. Only one program can own the COM port at a time.
5. Double-click `Play with Shadow Controller.bat`.

The launcher starts `controller_bridge/run_bridge.bat`, which installs the declared `pyserial` dependency if needed, then starts the game. To start the bridge manually, run `controller_bridge/run_bridge.bat`; it auto-detects the Uno, or accepts a port override such as `controller_bridge/run_bridge.bat --port COM5`.

## Voice assets

The public source snapshot does not include the 104 Windows SAPI-generated voice WAV files because their redistribution rights have not been established. The game continues with subtitles when a voice asset is absent. On a Windows system with the intended voices installed, the original audio-generation workflow is:

```powershell
powershell -NoProfile -File tools/gen_voice.ps1 .
python -I tools/gen_audio.py .
```

This writes local generated audio under `tools/voice_raw/` and `assets/audio/voice/`. Those files are ignored by Git. Confirm the rights for your installed TTS voices before redistributing generated audio.
