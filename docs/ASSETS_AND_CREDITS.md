# Assets and credits

## Poly Haven assets

The repository manifest lists the Poly Haven assets used by the game. Poly Haven states that its assets are released under CC0; attribution is not required, but is provided here as a courtesy. Each source link below points to the asset page.

| Asset | Creator(s) | Source |
| --- | --- | --- |
| Concrete Floor Worn 001 | Dimitrios Savva, Rico Cilliers | [Poly Haven](https://polyhaven.com/a/concrete_floor_worn_001) |
| Painted Concrete | Dario Barresi, Dimitrios Savva | [Poly Haven](https://polyhaven.com/a/painted_concrete) |
| Concrete Wall 008 | Dario Barresi, Charlotte Baglioni | [Poly Haven](https://polyhaven.com/a/concrete_wall_008) |
| Asphalt 02 | Rob Tuytel | [Poly Haven](https://polyhaven.com/a/asphalt_02) |
| Metal Plate | Rob Tuytel | [Poly Haven](https://polyhaven.com/a/metal_plate) |
| Rusty Corrugated Iron | Charlotte Baglioni | [Poly Haven](https://polyhaven.com/a/rusty_corrugated_iron) |
| Painted Metal Shutter | Dario Barresi, Rico Cilliers, Charlotte Baglioni | [Poly Haven](https://polyhaven.com/a/painted_metal_shutter) |
| Worn Tile Floor | Dimitrios Savva | [Poly Haven](https://polyhaven.com/a/worn_tile_floor) |
| Rusty Metal Grid | Amal Kumar | [Poly Haven](https://polyhaven.com/a/rusty_metal_grid) |
| Gravel Floor | Jenelle van Heerden, Matterfield | [Poly Haven](https://polyhaven.com/a/gravel_floor) |
| Kloppenheim 02 (Pure Sky) | Greg Zaal, Jarod Guest | [Poly Haven](https://polyhaven.com/a/kloppenheim_02_puresky) |
| Security Camera 01 | Alexander Otterbeck, Yann Kervran | [Poly Haven](https://polyhaven.com/a/security_camera_01) |
| Metal Office Desk | Ulan Cabanilla | [Poly Haven](https://polyhaven.com/a/metal_office_desk) |
| Steel Frame Shelves 01 | James Ray Cock | [Poly Haven](https://polyhaven.com/a/steel_frame_shelves_01) |
| Wooden Military Crate | Prabhjinder Singh | [Poly Haven](https://polyhaven.com/a/wooden_military_crate) |
| Old Military Crate | Jack Mava | [Poly Haven](https://polyhaven.com/a/old_military_crate) |
| Barrel_01 | Jorge Camacho | [Poly Haven](https://polyhaven.com/a/Barrel_01) |
| Barrel 03 | Serhii Khromov | [Poly Haven](https://polyhaven.com/a/barrel_03) |
| Concrete Road Barrier | Amal Kumar | [Poly Haven](https://polyhaven.com/a/concrete_road_barrier) |
| Power Box 01 | Rico Cilliers, Yann Kervran | [Poly Haven](https://polyhaven.com/a/power_box_01) |
| Hanging Industrial Lamp | Kuutti Siitonen | [Poly Haven](https://polyhaven.com/a/hanging_industrial_lamp) |
| Mounted Fluorescent Lights | Ulan Cabanilla | [Poly Haven](https://polyhaven.com/a/mounted_fluorescent_lights) |
| Propane Tank | Slinc | [Poly Haven](https://polyhaven.com/a/propane_tank) |
| Metal Jerrycan Green | Ulan Cabanilla | [Poly Haven](https://polyhaven.com/a/metal_jerrycan_green) |
| Utility Box 01 | James Ray Cock | [Poly Haven](https://polyhaven.com/a/utility_box_01) |
| Exterior Aircon Unit | Monsta3D | [Poly Haven](https://polyhaven.com/a/exterior_aircon_unit) |
| Ammo Box | DanKit | [Poly Haven](https://polyhaven.com/a/ammo_box) |
| Portable Generator | James Ray Cock | [Poly Haven](https://polyhaven.com/a/portable_generator) |
| Metal Tool Chest | Yann Kervran, John Hutcheson | [Poly Haven](https://polyhaven.com/a/metal_tool_chest) |
| Cardboard Box 01 | Rahul Chaudhary | [Poly Haven](https://polyhaven.com/a/cardboard_box_01) |
| Industrial Storage Cart | Jule Bielitz | [Poly Haven](https://polyhaven.com/a/industrial_storage_cart) |
| Security Light | Maximilian Schuster | [Poly Haven](https://polyhaven.com/a/security_light) |
| Classic Laptop | Arrangemonk | [Poly Haven](https://polyhaven.com/a/classic_laptop) |
| Vintage Radio Transceiver | Mateusz Sadek | [Poly Haven](https://polyhaven.com/a/vintage_radio_transceiver) |
| Circuit Board | Benny Weimer | [Poly Haven](https://polyhaven.com/a/circuit_board) |
| Modular Industrial Pipes 01 | Jorge Camacho | [Poly Haven](https://polyhaven.com/a/modular_industrial_pipes_01) |
| Metal Trash Can | GurJas Studios | [Poly Haven](https://polyhaven.com/a/metal_trash_can) |
| Portable Searchlight | Elijah Cragg | [Poly Haven](https://polyhaven.com/a/portable_searchlight) |
| Street Lamp 01 | Josh Dean | [Poly Haven](https://polyhaven.com/a/street_lamp_01) |
| Old Military Compressor | Brian Speight | [Poly Haven](https://polyhaven.com/a/old_military_compressor) |
| Metal Toolbox | Mateusz Sadek | [Poly Haven](https://polyhaven.com/a/metal_toolbox) |

## Generated audio

Sound effects, ambience, and music are generated procedurally by `tools/gen_audio.py`; the script states that it uses no third-party samples. Voice lines are synthesized by `tools/gen_voice.ps1` through installed Windows SAPI voices and post-processed by the audio generator. The public snapshot omits the generated voice WAV files because their redistribution terms have not been established. The missing voice assets affect spoken audio only; the game emits subtitles and continues when a clip is absent. Do not redistribute locally generated clips until their rights are confirmed.

## Third-party software

| Component | Use | License / distribution note |
| --- | --- | --- |
| [Godot Engine](https://godotengine.org/license/) 4.7.2 | Game engine | MIT; the Godot runtime binary is not included in this source repository. |
| [Adafruit SSD1306](https://github.com/adafruit/Adafruit_SSD1306) | OLED driver used by the firmware | BSD license; install separately through Arduino IDE Library Manager. |
| [Adafruit GFX](https://github.com/adafruit/Adafruit-GFX-Library) | Graphics primitives used by the OLED driver | BSD license; install separately through Arduino IDE Library Manager. |
| [pyserial](https://github.com/pyserial/pyserial) | Python USB serial bridge | BSD-3-Clause; installed from `controller_bridge/requirements.txt`. |

These dependencies are not copied into the repository. Follow each upstream project's license when installing or redistributing its code.

## SHADOW PROTOCOL project code

No project-level license is currently provided. Public visibility on GitHub does not grant permission to reuse or redistribute the game code beyond the rights granted by third-party licenses.

## Screenshots and hardware photographs

Gameplay captures were generated from the project's built-in Godot capture tool. The controller photographs were supplied by the project owner and show the prototype in use.
