class_name EnemyData
extends Resource
## Archetype configuration for an enemy. Behaviour differences live in Enemy/AI states
## and are switched by `archetype`; numbers live here.

enum Archetype { STANDARD_GUARD, SECURITY_SPECIALIST, HEAVY_RESPONSE, COMMANDER }

@export var archetype: Archetype = Archetype.STANDARD_GUARD
@export var display_name: String = "Guard"
@export_group("Body")
@export var max_health: float = 100.0
## Fraction of incoming damage ignored (body shots).
@export var armor: float = 0.0
@export var walk_speed: float = 1.6
@export var run_speed: float = 4.4
@export var visual_scale: float = 1.0
@export_group("Vision")
@export var vision_range: float = 24.0
@export var fov_degrees: float = 110.0
## Suspicion gained per second at full visibility, close range, centre of view.
@export var detection_rate: float = 60.0
@export var suspicion_decay: float = 9.0
@export_group("Hearing")
@export var hearing_multiplier: float = 1.0
@export_group("Combat")
@export var weapon: WeaponData
@export var accuracy: float = 0.55
@export var reaction_time: float = 0.7
@export var burst_size: int = 3
@export var burst_interval: float = 1.3
@export var preferred_range: float = 14.0
@export var uses_cover: bool = true
@export var aggressive_push: bool = false
@export_group("Support")
## Specialists can raise alarms and relay the player's position by radio.
@export var can_use_alarm: bool = false
@export var radio_range: float = 18.0
