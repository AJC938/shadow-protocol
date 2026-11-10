extends Node
## Autoload "InputRouter" — the Input Abstraction Layer.
##
## * Owns the default action map (keyboard, mouse, gamepad) and remapping.
## * Merges every registered InputProvider into device-agnostic gameplay input.
## * Gameplay scripts only call InputRouter.* — never Input or raw InputEvents.

signal bindings_changed

const NativeProvider := preload("res://scripts/input/native_input_provider.gd")
const ExternalProvider := preload("res://scripts/input/external_input_provider.gd")

## Actions shown in the remapping menu, in display order, with labels.
const REMAPPABLE := [
	[&"move_forward", "Move Forward"], [&"move_back", "Move Back"],
	[&"move_left", "Move Left"], [&"move_right", "Move Right"],
	[&"aim", "Aim"], [&"fire", "Fire"], [&"sprint", "Sprint"], [&"walk", "Walk (slow)"],
	[&"crouch", "Crouch"], [&"reload", "Reload"], [&"interact", "Interact"],
	[&"gadget_use", "Use Gadget"], [&"gadget_next", "Next Gadget"],
	[&"weapon_1", "Pistol"], [&"weapon_2", "Rifle"], [&"weapon_3", "Shotgun"],
	[&"swap_shoulder", "Swap Shoulder"], [&"pause", "Pause"],
]

# Default keyboard/mouse bindings.  ["key", Key] or ["mouse", MouseButton]
const DEFAULT_KBM := {
	&"move_forward": ["key", KEY_W], &"move_back": ["key", KEY_S],
	&"move_left": ["key", KEY_A], &"move_right": ["key", KEY_D],
	&"aim": ["mouse", MOUSE_BUTTON_RIGHT], &"fire": ["mouse", MOUSE_BUTTON_LEFT],
	&"sprint": ["key", KEY_SHIFT], &"walk": ["key", KEY_ALT], &"crouch": ["key", KEY_C],
	&"reload": ["key", KEY_R], &"interact": ["key", KEY_E],
	&"gadget_use": ["key", KEY_Q], &"gadget_next": ["key", KEY_T],
	&"weapon_1": ["key", KEY_1], &"weapon_2": ["key", KEY_2], &"weapon_3": ["key", KEY_3],
	&"weapon_next": ["mouse", MOUSE_BUTTON_WHEEL_DOWN], &"weapon_prev": ["mouse", MOUSE_BUTTON_WHEEL_UP],
	&"swap_shoulder": ["key", KEY_V], &"pause": ["key", KEY_ESCAPE],
	&"toggle_objectives": ["key", KEY_TAB],
}

# Default gamepad bindings.  ["button", JoyButton] or ["axis", JoyAxis, sign]
const DEFAULT_PAD := {
	&"move_forward": ["axis", JOY_AXIS_LEFT_Y, -1.0], &"move_back": ["axis", JOY_AXIS_LEFT_Y, 1.0],
	&"move_left": ["axis", JOY_AXIS_LEFT_X, -1.0], &"move_right": ["axis", JOY_AXIS_LEFT_X, 1.0],
	&"look_up": ["axis", JOY_AXIS_RIGHT_Y, -1.0], &"look_down": ["axis", JOY_AXIS_RIGHT_Y, 1.0],
	&"look_left": ["axis", JOY_AXIS_RIGHT_X, -1.0], &"look_right": ["axis", JOY_AXIS_RIGHT_X, 1.0],
	&"aim": ["axis", JOY_AXIS_TRIGGER_LEFT, 1.0], &"fire": ["axis", JOY_AXIS_TRIGGER_RIGHT, 1.0],
	&"sprint": ["button", JOY_BUTTON_LEFT_STICK], &"crouch": ["button", JOY_BUTTON_B],
	&"reload": ["button", JOY_BUTTON_X], &"interact": ["button", JOY_BUTTON_A],
	&"gadget_use": ["button", JOY_BUTTON_Y], &"gadget_next": ["button", JOY_BUTTON_DPAD_RIGHT],
	&"weapon_next": ["button", JOY_BUTTON_RIGHT_SHOULDER], &"weapon_prev": ["button", JOY_BUTTON_LEFT_SHOULDER],
	&"swap_shoulder": ["button", JOY_BUTTON_RIGHT_STICK], &"pause": ["button", JOY_BUTTON_START],
	&"toggle_objectives": ["button", JOY_BUTTON_BACK], &"walk": ["button", JOY_BUTTON_DPAD_DOWN],
}

const ALL_ACTIONS := [&"move_forward", &"move_back", &"move_left", &"move_right",
	&"look_up", &"look_down", &"look_left", &"look_right", &"aim", &"fire", &"sprint", &"walk",
	&"crouch", &"reload", &"interact", &"gadget_use", &"gadget_next", &"weapon_1", &"weapon_2",
	&"weapon_3", &"weapon_next", &"weapon_prev", &"swap_shoulder", &"pause", &"toggle_objectives"]

## When true, gameplay queries return neutral values (menus, cutscenes, recon camera owns input).
var gameplay_blocked: bool = false

var native: NativeInputProvider
## Ready-to-use provider for external hardware. Idle unless something feeds it.
var external: ExternalInputProvider
var _providers: Array[InputProvider] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -100
	_build_default_map()
	apply_saved_bindings(Settings.bindings)
	native = NativeProvider.new()
	external = ExternalProvider.new()
	register_provider(native)
	register_provider(external)


func register_provider(p: InputProvider) -> void:
	if p and not _providers.has(p):
		_providers.append(p)


func unregister_provider(p: InputProvider) -> void:
	_providers.erase(p)


func get_providers() -> Array[InputProvider]:
	return _providers


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		native.add_mouse_motion(event.relative)


func _process(delta: float) -> void:
	for p in _providers:
		if p.enabled:
			p.poll(delta)


# --------------------------------------------------------------------------- queries

func get_move_vector() -> Vector2:
	if gameplay_blocked:
		return Vector2.ZERO
	var v := Vector2.ZERO
	for p in _providers:
		if p.enabled:
			v += p.get_move()
	return v.limit_length(1.0)


## Consumes the accumulated look delta (degrees). Call once per frame.
func consume_look(delta: float) -> Vector2:
	var v := Vector2.ZERO
	for p in _providers:
		if p.enabled:
			v += p.get_look(delta)
	if gameplay_blocked:
		return Vector2.ZERO
	if Settings.invert_y:
		v.y = -v.y
	return v


func is_pressed(action: StringName) -> bool:
	if gameplay_blocked and action != &"pause":
		return false
	for p in _providers:
		if p.enabled and p.is_pressed(action):
			return true
	return false


func is_just_pressed(action: StringName) -> bool:
	if gameplay_blocked and action != &"pause":
		return false
	for p in _providers:
		if p.enabled and p.is_just_pressed(action):
			return true
	return false


func is_just_released(action: StringName) -> bool:
	for p in _providers:
		if p.enabled and p.is_just_released(action):
			return true
	return false


# --------------------------------------------------------------------------- bindings

func _build_default_map() -> void:
	for a in ALL_ACTIONS:
		if InputMap.has_action(a):
			InputMap.erase_action(a)
		InputMap.add_action(a, 0.25)
		if DEFAULT_KBM.has(a):
			InputMap.action_add_event(a, _make_event(DEFAULT_KBM[a]))
		if DEFAULT_PAD.has(a):
			InputMap.action_add_event(a, _make_event(DEFAULT_PAD[a]))


func _make_event(spec: Array) -> InputEvent:
	match spec[0]:
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = spec[1]
			return k
		"mouse":
			var m := InputEventMouseButton.new()
			m.button_index = spec[1]
			return m
		"button":
			var b := InputEventJoypadButton.new()
			b.button_index = spec[1]
			return b
		"axis":
			var j := InputEventJoypadMotion.new()
			j.axis = spec[1]
			j.axis_value = spec[2]
			return j
	return null


## Serialisable form of the current keyboard/mouse binding of an action.
func get_kbm_spec(action: StringName) -> Array:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			return ["key", e.physical_keycode]
		if e is InputEventMouseButton:
			return ["mouse", e.button_index]
	return []


func get_binding_text(action: StringName) -> String:
	var spec := get_kbm_spec(action)
	if spec.is_empty():
		return "—"
	if spec[0] == "key":
		return OS.get_keycode_string(spec[1])
	match int(spec[1]):
		MOUSE_BUTTON_LEFT: return "Left Mouse"
		MOUSE_BUTTON_RIGHT: return "Right Mouse"
		MOUSE_BUTTON_MIDDLE: return "Middle Mouse"
		MOUSE_BUTTON_WHEEL_UP: return "Wheel Up"
		MOUSE_BUTTON_WHEEL_DOWN: return "Wheel Down"
	return "Mouse %d" % spec[1]


## Replaces the keyboard/mouse binding of an action; gamepad bindings are untouched.
## Returns the action that previously used this input (it is swapped), or &"".
func rebind(action: StringName, event: InputEvent) -> StringName:
	var spec: Array
	if event is InputEventKey:
		spec = ["key", event.physical_keycode if event.physical_keycode != 0 else event.keycode]
	elif event is InputEventMouseButton:
		spec = ["mouse", event.button_index]
	else:
		return &""
	var old_spec := get_kbm_spec(action)
	var swapped: StringName = &""
	for a in DEFAULT_KBM.keys():
		if a != action and get_kbm_spec(a) == spec:
			_set_kbm(a, old_spec)
			swapped = a
	_set_kbm(action, spec)
	_store()
	bindings_changed.emit()
	return swapped


func _set_kbm(action: StringName, spec: Array) -> void:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey or e is InputEventMouseButton:
			InputMap.action_erase_event(action, e)
	if not spec.is_empty():
		InputMap.action_add_event(action, _make_event(spec))


func reset_bindings() -> void:
	_build_default_map()
	_store()
	bindings_changed.emit()


func apply_saved_bindings(saved: Dictionary) -> void:
	for a in saved.keys():
		var sn := StringName(a)
		var spec = saved[a]
		if not InputMap.has_action(sn) or typeof(spec) != TYPE_ARRAY or spec.size() != 2:
			continue
		if spec[0] in ["key", "mouse"]:
			_set_kbm(sn, [spec[0], int(spec[1])])


func _store() -> void:
	var d := {}
	for a in DEFAULT_KBM.keys():
		d[String(a)] = get_kbm_spec(a)
	Settings.bindings = d
	Settings.save_settings()
