class_name InputProvider
extends RefCounted
## Base class for every physical input source (keyboard/mouse, gamepad, future Arduino).
##
## Gameplay never talks to a provider directly: InputRouter merges all registered
## providers and exposes device-agnostic gameplay actions.
##
## Axis conventions (same as Input.get_vector):
##   move  -> x = right(+), y = back(+)   (forward is negative y)
##   look  -> x = yaw right(+), y = pitch down(+)   in "look units" per frame

## Human readable name used in debug overlays and docs.
var provider_name: String = "base"
## Providers can be switched off without unregistering them.
var enabled: bool = true


## Called once per frame by InputRouter before gameplay reads input.
func poll(_delta: float) -> void:
	pass


func get_move() -> Vector2:
	return Vector2.ZERO


## Returns look delta for this frame (already scaled by the provider's own sensitivity).
func get_look(_delta: float) -> Vector2:
	return Vector2.ZERO


func is_pressed(_action: StringName) -> bool:
	return false


func is_just_pressed(_action: StringName) -> bool:
	return false


func is_just_released(_action: StringName) -> bool:
	return false
