class_name WeaponData
extends Resource
## Configurable weapon definition shared by the player and enemies.

enum Model { PISTOL, RIFLE, SHOTGUN }

@export var id: StringName = &"pistol"
@export var display_name: String = "Weapon"
@export var model: Model = Model.PISTOL
@export_group("Firing")
@export var damage: float = 30.0
@export var headshot_multiplier: float = 2.5
## Rounds per second.
@export var fire_rate: float = 3.0
@export var automatic: bool = false
## >1 for shotguns.
@export var pellets: int = 1
@export var range: float = 60.0
## Damage multiplier at max range (linear falloff from falloff_start).
@export var falloff_start: float = 25.0
@export var min_damage_scale: float = 0.5
@export_group("Ammunition")
@export var magazine_size: int = 12
@export var start_reserve: int = 48
@export var max_reserve: int = 96
@export var reload_time: float = 1.5
@export_group("Accuracy")
## Cone half-angles in degrees.
@export var spread_hip: float = 3.0
@export var spread_aim: float = 0.6
@export var spread_move_add: float = 1.5
@export var recoil_pitch: float = 1.2
@export var recoil_yaw: float = 0.4
@export_group("Stealth")
## Perception radius of the shot sound in metres.
@export var noise_radius: float = 8.0
@export var suppressed: bool = false
@export_group("Presentation")
@export var fire_sound: StringName = &"pistol_fire"
@export var muzzle_flash_scale: float = 0.6
@export var switch_time: float = 0.35
