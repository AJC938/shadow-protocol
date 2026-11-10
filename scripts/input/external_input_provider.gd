class_name ExternalInputProvider
extends InputProvider
## Data-driven provider for future external hardware (e.g. the Arduino controller V2).
##
## This release contains NO serial communication. A future ArduinoSerialProvider
## only has to parse its packets and call set_axis()/set_button() — see
## ARDUINO_INTEGRATION.md. The game is fully playable while this provider is idle.

const AXES := [&"move_x", &"move_y", &"camera_x", &"camera_y"]
## Gameplay actions an external device may drive.
const BUTTONS := [&"fire", &"aim", &"sprint", &"crouch", &"interact", &"gadget_use",
	&"gadget_next", &"reload", &"weapon_1", &"weapon_2", &"weapon_3", &"weapon_next",
	&"weapon_prev", &"pause"]

## Analog dead zone applied to incoming normalised axis values (-1..1).
var dead_zone: float = 0.08
## Degrees of camera rotation per second at full camera-axis deflection.
var camera_speed: float = 160.0

var _axes: Dictionary = {}
var _buttons: Dictionary = {}
var _prev_buttons: Dictionary = {}
var _edges_pressed: Dictionary = {}
var _edges_released: Dictionary = {}


func _init() -> void:
	provider_name = "external"
	for a in AXES:
		_axes[a] = 0.0
	for b in BUTTONS:
		_buttons[b] = false
		_prev_buttons[b] = false


## value: normalised -1..1 analog value.
func set_axis(axis: StringName, value: float) -> void:
	if not _axes.has(axis):
		push_warning("ExternalInputProvider: unknown axis %s" % axis)
		return
	value = clampf(value, -1.0, 1.0)
	_axes[axis] = 0.0 if absf(value) < dead_zone else value


func set_button(action: StringName, down: bool) -> void:
	if not _buttons.has(action):
		push_warning("ExternalInputProvider: unknown button %s" % action)
		return
	_buttons[action] = down


## Releases everything (call when the device disconnects).
func reset() -> void:
	for a in _axes:
		_axes[a] = 0.0
	for b in _buttons:
		_buttons[b] = false


func poll(_delta: float) -> void:
	for b in _buttons:
		var now: bool = _buttons[b]
		var before: bool = _prev_buttons[b]
		_edges_pressed[b] = now and not before
		_edges_released[b] = before and not now
		_prev_buttons[b] = now


func get_move() -> Vector2:
	var v := Vector2(_axes[&"move_x"], -float(_axes[&"move_y"]))  # device +Y = forward
	return v.limit_length(1.0)


func get_look(delta: float) -> Vector2:
	# camera_speed is set by the feeding integration (e.g. ControllerBridge from its own sensitivity setting).
	return Vector2(_axes[&"camera_x"], -float(_axes[&"camera_y"])) * camera_speed * delta


func is_pressed(action: StringName) -> bool:
	return _buttons.get(action, false)


func is_just_pressed(action: StringName) -> bool:
	return _edges_pressed.get(action, false)


func is_just_released(action: StringName) -> bool:
	return _edges_released.get(action, false)
