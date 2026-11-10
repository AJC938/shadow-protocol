class_name SettingsMenu
extends Control
## Settings screen used by the main menu and the pause menu.
## Graphics, audio and controls (including key remapping). Changes apply live and
## are saved when the screen closes.

signal closed

var _tabs: TabContainer
var _waiting_action: StringName = &""
var _bind_buttons: Dictionary = {}
var _capture_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UIKit.theme()
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.025, 0.03, 0.85)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var outer := VBoxContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	outer.position = Vector2(-460, -380)
	outer.custom_minimum_size = Vector2(920, 760)
	add_child(outer)
	outer.add_child(UIKit.label("SETTINGS", 40, UIKit.TEXT, "title"))
	outer.add_child(UIKit.accent_line(100))
	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(920, 600)
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_tabs)
	_tabs.add_child(_graphics_tab())
	_tabs.add_child(_audio_tab())
	_tabs.add_child(_controls_tab())
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	outer.add_child(row)
	row.add_child(UIKit.button("BACK", close, 220))


func open() -> void:
	visible = true
	_refresh_bindings()
	var b := find_children("*", "Button", true, false)
	if not b.is_empty():
		(b[-1] as Button).grab_focus()


func close() -> void:
	_waiting_action = &""
	Settings.save_settings()
	closed.emit()


func _scroll(title: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = title
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 12)
	sc.add_child(v)
	return v


func _row(parent: VBoxContainer, text: String, control: Control) -> void:
	var h := HBoxContainer.new()
	var l := UIKit.label(text, 18, UIKit.TEXT, "label")
	l.custom_minimum_size = Vector2(320, 0)
	h.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(control)
	parent.add_child(h)


func _option(items: Array, selected: int, cb: Callable) -> OptionButton:
	var o := OptionButton.new()
	for i in items:
		o.add_item(str(i))
	o.selected = selected
	o.item_selected.connect(func(i):
		AudioManager.play_ui(&"ui_click")
		cb.call(i))
	return o


func _slider(minv: float, maxv: float, step: float, value: float, cb: Callable, fmt: String = "%d%%", scale: float = 100.0) -> HBoxContainer:
	var h := HBoxContainer.new()
	var s := HSlider.new()
	s.min_value = minv
	s.max_value = maxv
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(360, 28)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := UIKit.label(fmt % (value * scale), 16, UIKit.TEXT_DIM, "mono")
	l.custom_minimum_size = Vector2(70, 0)
	s.value_changed.connect(func(v):
		l.text = fmt % (v * scale)
		cb.call(v))
	h.add_child(s)
	h.add_child(l)
	return h


func _check(value: bool, cb: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.button_pressed = value
	c.toggled.connect(func(on):
		AudioManager.play_ui(&"ui_click")
		cb.call(on))
	return c


func _graphics_tab() -> Control:
	var v := _scroll("Graphics")
	_row(v, "Display mode", _option(["Windowed", "Borderless", "Fullscreen"], Settings.display_mode, func(i):
		Settings.display_mode = i
		Settings.apply()))
	var res_names := []
	var cur := 0
	for i in Settings.RESOLUTIONS.size():
		var r: Vector2i = Settings.RESOLUTIONS[i]
		res_names.append("%d × %d" % [r.x, r.y])
		if r == Settings.resolution:
			cur = i
	_row(v, "Resolution (windowed)", _option(res_names, cur, func(i):
		Settings.resolution = Settings.RESOLUTIONS[i]
		Settings.apply()))
	_row(v, "V-Sync", _check(Settings.vsync, func(on):
		Settings.vsync = on
		Settings.apply()))
	_row(v, "Render scale (FSR)", _slider(0.5, 1.0, 0.05, Settings.render_scale, func(x):
		Settings.render_scale = x
		Settings.apply()))
	_row(v, "Graphics quality", _option(Settings.QUALITY_NAMES, Settings.quality, func(i):
		Settings.quality = i
		Settings.apply()))
	_row(v, "Shadow quality", _option(["Off", "Low", "Medium", "High"], Settings.shadow_quality, func(i):
		Settings.shadow_quality = i
		Settings.apply()))
	_row(v, "Field of view", _slider(55.0, 95.0, 1.0, Settings.fov, func(x):
		Settings.fov = x
		Settings.apply(), "%d°", 1.0))
	_row(v, "Show FPS", _check(Settings.show_fps, func(on): Settings.show_fps = on))
	_row(v, "Subtitles", _check(Settings.subtitles, func(on): Settings.subtitles = on))
	v.add_child(UIKit.label("Detected GPU: %s" % RenderingServer.get_video_adapter_name(), 14, UIKit.TEXT_DIM))
	return v.get_parent()


func _audio_tab() -> Control:
	var v := _scroll("Audio")
	for pair in [["Master", "master_volume"], ["Music", "music_volume"], ["Effects", "sfx_volume"], ["Voice", "voice_volume"], ["Interface", "ui_volume"]]:
		var prop: String = pair[1]
		_row(v, pair[0], _slider(0.0, 1.0, 0.05, Settings.get(prop), func(x):
			Settings.set(prop, x)
			Settings.apply()))
	return v.get_parent()


func _controls_tab() -> Control:
	var v := _scroll("Controls")
	_row(v, "Mouse sensitivity", _slider(0.1, 3.0, 0.05, Settings.mouse_sensitivity, func(x): Settings.mouse_sensitivity = x, "%.2f", 1.0))
	_row(v, "Gamepad camera sensitivity", _slider(0.1, 3.0, 0.05, Settings.camera_sensitivity, func(x): Settings.camera_sensitivity = x, "%.2f", 1.0))
	_row(v, "Invert Y axis", _check(Settings.invert_y, func(on): Settings.invert_y = on))
	v.add_child(UIKit.accent_line(60))
	_capture_label = UIKit.label("Select an action, then press a key or mouse button. Esc cancels.", 15, UIKit.TEXT_DIM)
	v.add_child(_capture_label)
	for pair in InputRouter.REMAPPABLE:
		var action: StringName = pair[0]
		var b := Button.new()
		b.custom_minimum_size = Vector2(260, 40)
		b.pressed.connect(func(): _begin_capture(action))
		_bind_buttons[action] = b
		_row(v, pair[1], b)
	v.add_child(UIKit.button("RESET TO DEFAULTS", func():
		InputRouter.reset_bindings()
		_refresh_bindings(), 300))
	v.add_child(UIKit.accent_line(60))
	var hw := "connected" if ControllerBridge.controller_connected else ("bridge running, controller not sending" if ControllerBridge.serial_link else "not detected (start controller_bridge/run_bridge.bat)")
	v.add_child(UIKit.label("SHADOW CONTROLLER V2: %s" % hw, 15, UIKit.AMBER, "label"))
	v.add_child(UIKit.label("Left stick (J1) look/aim · J1 press fire · Right stick (J2) move & strafe · J2 press interact, hold to hack", 14, UIKit.TEXT_DIM))
	_row(v, "Controller look sensitivity", _slider(0.2, 3.0, 0.05, Settings.controller_look_sensitivity, func(x): Settings.controller_look_sensitivity = x, "%.2f", 1.0))
	_row(v, "Controller look smoothing", _slider(0.0, 0.3, 0.01, Settings.controller_look_smoothing, func(x): Settings.controller_look_smoothing = x, "%.2f s", 1.0))
	_row(v, "Controller invert look Y", _check(Settings.controller_invert_y, func(on): Settings.controller_invert_y = on))
	v.add_child(UIKit.label("Gamepad: left stick move · right stick camera · LT aim · RT fire · A interact · B crouch · X reload · Y gadget · L3 sprint · LB/RB weapons · D-pad right next gadget · Start pause", 14, UIKit.TEXT_DIM))
	_refresh_bindings()
	return v.get_parent()


func _refresh_bindings() -> void:
	for a in _bind_buttons.keys():
		(_bind_buttons[a] as Button).text = InputRouter.get_binding_text(a)


func _begin_capture(action: StringName) -> void:
	_waiting_action = action
	(_bind_buttons[action] as Button).text = "…press input…"
	_capture_label.text = "Rebinding: %s" % action


func _input(event: InputEvent) -> void:
	if _waiting_action == &"" or not visible:
		return
	var accept := false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			_waiting_action = &""
			_refresh_bindings()
			get_viewport().set_input_as_handled()
			return
		accept = true
	elif event is InputEventMouseButton and event.pressed:
		accept = true
	if accept:
		var swapped := InputRouter.rebind(_waiting_action, event)
		_capture_label.text = "Bound %s%s" % [_waiting_action, (" (swapped with %s)" % swapped) if swapped != &"" else ""]
		_waiting_action = &""
		_refresh_bindings()
		get_viewport().set_input_as_handled()
