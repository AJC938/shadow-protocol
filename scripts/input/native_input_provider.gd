class_name NativeInputProvider
extends InputProvider
## Keyboard, mouse and standard gamepad through Godot's InputMap.
## Mouse motion is accumulated by InputRouter._input and handed to this provider.

var _mouse_accum: Vector2 = Vector2.ZERO


func _init() -> void:
	provider_name = "keyboard_mouse_gamepad"


func add_mouse_motion(rel: Vector2) -> void:
	_mouse_accum += rel


func get_move() -> Vector2:
	return Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")


func get_look(delta: float) -> Vector2:
	var mouse := _mouse_accum * 0.08 * Settings.mouse_sensitivity
	_mouse_accum = Vector2.ZERO
	var stick := Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
	# Response curve gives fine aim near the centre of the stick.
	stick = stick.normalized() * pow(stick.length(), 1.6) if stick.length() > 0.0 else Vector2.ZERO
	var pad := stick * 180.0 * delta * Settings.camera_sensitivity
	return mouse + pad


func is_pressed(action: StringName) -> bool:
	return InputMap.has_action(action) and Input.is_action_pressed(action)


func is_just_pressed(action: StringName) -> bool:
	return InputMap.has_action(action) and Input.is_action_just_pressed(action)


func is_just_released(action: StringName) -> bool:
	return InputMap.has_action(action) and Input.is_action_just_released(action)
