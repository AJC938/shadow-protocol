class_name MissionUI
extends CanvasLayer
## In-mission interface: HUD panels, messages, subtitles, interaction prompt,
## recon overlay, pause menu, death screen and the full objective list.
## Reads gameplay state through signals; never drives gameplay logic itself.

var controller: MissionController
var player: Player
var overlay: HudOverlay

var _root: Control
var _obj_title: Label
var _obj_current: Label
var _obj_optional: VBoxContainer
var _obj_full: PanelContainer
var _obj_full_list: VBoxContainer
var _messages: VBoxContainer
var _alarm_banner: PanelContainer
var _restricted: Label
var _subtitle: Label
var _subtitle_t: float = 0.0
var _prompt: Label
var _prompt_bar: ProgressBar
var _health_bar: ProgressBar
var _health_label: Label
var _vis_bar: ProgressBar
var _stance: Label
var _weapon_name: Label
var _ammo: Label
var _reload_label: Label
var _gadget_name: Label
var _gadget_status: Label
var _timer_label: Label
var _fps: Label
var _vignette: TextureRect
var _recon: Control
var _pause: Control
var _death: Control
var _settings: SettingsMenu
var _paused: bool = false


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UIKit.theme()
	add_child(_root)


func setup(mc: MissionController, p: Player) -> void:
	controller = mc
	player = p
	_build_hud()
	_build_pause()
	_build_death()
	overlay.setup(p, mc)
	mc.objectives_changed.connect(_refresh_objectives)
	mc.mission_message.connect(_on_message)
	mc.player_died.connect(_on_player_died)
	p.health_changed.connect(_on_health)
	p.stealth_visibility_changed.connect(func(_v): _refresh_stance())
	p.stance_changed.connect(func(_c): _refresh_stance())
	p.weapons.weapon_changed.connect(func(_i, d): _weapon_name.text = d.display_name.to_upper())
	p.weapons.ammo_changed.connect(func(m, r): _ammo.text = "%d  /  %d" % [m, r])
	p.weapons.reload_started.connect(func(_d): _reload_label.text = "RELOADING")
	p.weapons.reload_finished.connect(func(): _reload_label.text = "")
	p.gadgets.gadget_changed.connect(func(_i, _d): _refresh_gadget())
	p.gadgets.state_changed.connect(_refresh_gadget)
	p.gadgets.message.connect(func(t): _on_message(t, "info"))
	p.gadgets.recon_mode_changed.connect(func(on): _recon.visible = on)
	p.interactor.focus_changed.connect(_on_focus)
	p.interactor.hold_progress.connect(func(r):
		_prompt_bar.visible = r > 0.0
		_prompt_bar.value = r * 100.0)
	AudioManager.voice_line.connect(_on_voice)
	ControllerBridge.controller_connected_changed.connect(func(c):
		_on_message("SHADOW CONTROLLER V2 " + ("CONNECTED" if c else "DISCONNECTED — input released"), "info" if c else "warning"))
	var alarm := AlarmSystem.find(mc)
	if alarm:
		alarm.raised.connect(func(_o, _r): _alarm_banner.visible = true)
		alarm.cleared.connect(func(): _alarm_banner.visible = false)
	# Initial values
	var w := p.weapons.get_data()
	if w:
		_weapon_name.text = w.display_name.to_upper()
		var ws := p.weapons.get_current()
		_ammo.text = "%d  /  %d" % [ws.mag, ws.reserve]
	_on_health(p.health.current, p.health.max_health)
	_refresh_gadget()
	_refresh_stance()
	_refresh_objectives()


# =========================================================================== build

## Corner-anchored container. margin = distance from the anchored screen edges.
func _corner(anchor: int, margin: Vector2) -> VBoxContainer:
	var v := VBoxContainer.new()
	var right := anchor in [Control.PRESET_TOP_RIGHT, Control.PRESET_BOTTOM_RIGHT]
	var bottom := anchor in [Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT]
	v.anchor_left = 1.0 if right else 0.0
	v.anchor_right = v.anchor_left
	v.anchor_top = 1.0 if bottom else 0.0
	v.anchor_bottom = v.anchor_top
	v.offset_left = -absf(margin.x) if right else absf(margin.x)
	v.offset_right = v.offset_left
	v.offset_top = -absf(margin.y) if bottom else absf(margin.y)
	v.offset_bottom = v.offset_top
	v.grow_horizontal = Control.GROW_DIRECTION_BEGIN if right else Control.GROW_DIRECTION_END
	v.grow_vertical = Control.GROW_DIRECTION_BEGIN if bottom else Control.GROW_DIRECTION_END
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(v)
	return v


func _build_hud() -> void:
	# Damage vignette
	_vignette = TextureRect.new()
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 1.0)
	var grad := Gradient.new()
	grad.set_color(0, Color(0.6, 0.0, 0.0, 0.0))
	grad.set_color(1, Color(0.6, 0.02, 0.0, 0.85))
	grad.add_point(0.55, Color(0.6, 0.0, 0.0, 0.0))
	g.gradient = grad
	_vignette.texture = g
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.modulate.a = 0.0
	_root.add_child(_vignette)

	overlay = HudOverlay.new()
	_root.add_child(overlay)

	# --- objectives (top-left)
	var tl := _corner(Control.PRESET_TOP_LEFT, Vector2(36, 30))
	var mp := controller.mission
	_obj_title = UIKit.label("OP %02d  ·  %s" % [mp.number, mp.title.to_upper()], 15, UIKit.AMBER, "label")
	tl.add_child(_obj_title)
	tl.add_child(UIKit.accent_line(60))
	_obj_current = UIKit.label("", 22, UIKit.TEXT, "heading")
	_obj_current.custom_minimum_size = Vector2(440, 0)
	_obj_current.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tl.add_child(_obj_current)
	_obj_optional = VBoxContainer.new()
	_obj_optional.add_theme_constant_override("separation", 2)
	tl.add_child(_obj_optional)
	_timer_label = UIKit.label("", 14, UIKit.TEXT_DIM, "mono")
	tl.add_child(_timer_label)

	# --- full objective list (Tab)
	_obj_full = UIKit.panel(Vector2(560, 0))
	_obj_full.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_obj_full.position = Vector2(-280, -220)
	_obj_full.visible = false
	_obj_full.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_obj_full_list = VBoxContainer.new()
	_obj_full.add_child(_obj_full_list)
	_root.add_child(_obj_full)

	# --- messages + alarm (top-centre)
	var tc := VBoxContainer.new()
	tc.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	tc.position = Vector2(-300, 26)
	tc.custom_minimum_size = Vector2(600, 0)
	tc.alignment = BoxContainer.ALIGNMENT_BEGIN
	tc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(tc)
	_alarm_banner = UIKit.panel(Vector2(600, 0), Color(0.45, 0.05, 0.03, 0.85))
	var al := UIKit.label("ALARM RAISED — FACILITY ON ALERT", 20, Color(1, 0.85, 0.8), "heading")
	al.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_alarm_banner.add_child(al)
	_alarm_banner.visible = false
	tc.add_child(_alarm_banner)
	_messages = VBoxContainer.new()
	_messages.add_theme_constant_override("separation", 4)
	tc.add_child(_messages)
	_restricted = UIKit.label("", 16, UIKit.RED, "label")
	_restricted.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tc.add_child(_restricted)

	# --- subtitles + prompt (bottom-centre)
	_subtitle = UIKit.label("", 22, UIKit.TEXT)
	_subtitle.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_subtitle.position = Vector2(-520, -150)
	_subtitle.custom_minimum_size = Vector2(1040, 0)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_subtitle.add_theme_constant_override("outline_size", 6)
	_root.add_child(_subtitle)
	var pc := VBoxContainer.new()
	pc.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	pc.position = Vector2(-200, 90)
	pc.custom_minimum_size = Vector2(400, 0)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(pc)
	_prompt = UIKit.label("", 20, Color(1, 0.95, 0.85), "label")
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_prompt.add_theme_constant_override("outline_size", 6)
	pc.add_child(_prompt)
	_prompt_bar = ProgressBar.new()
	_prompt_bar.custom_minimum_size = Vector2(400, 6)
	_prompt_bar.show_percentage = false
	_prompt_bar.visible = false
	pc.add_child(_prompt_bar)

	# --- health / visibility (bottom-left)
	var bl := _corner(Control.PRESET_BOTTOM_LEFT, Vector2(36, 36))
	var hp := UIKit.panel(Vector2(360, 0))
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 6)
	hp.add_child(hv)
	bl.add_child(hp)
	var hrow := HBoxContainer.new()
	hrow.add_child(UIKit.label("HEALTH", 13, UIKit.TEXT_DIM, "label"))
	_health_label = UIKit.label("100", 13, UIKit.TEXT, "label")
	_health_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hrow.add_child(_health_label)
	hv.add_child(hrow)
	_health_bar = ProgressBar.new()
	_health_bar.custom_minimum_size = Vector2(320, 10)
	_health_bar.show_percentage = false
	_health_bar.add_theme_stylebox_override("fill", UIKit.flat(Color(0.75, 0.78, 0.72), Color(0, 0, 0, 0), 0, 1, 0))
	hv.add_child(_health_bar)
	var vrow := HBoxContainer.new()
	vrow.add_child(UIKit.label("VISIBILITY", 13, UIKit.TEXT_DIM, "label"))
	_stance = UIKit.label("STANDING", 13, UIKit.TEXT, "label")
	_stance.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stance.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vrow.add_child(_stance)
	hv.add_child(vrow)
	_vis_bar = ProgressBar.new()
	_vis_bar.custom_minimum_size = Vector2(320, 6)
	_vis_bar.show_percentage = false
	_vis_bar.max_value = 1.25
	hv.add_child(_vis_bar)

	# --- weapon / gadget (bottom-right)
	var br := _corner(Control.PRESET_BOTTOM_RIGHT, Vector2(36, 36))
	var gp := UIKit.panel(Vector2(360, 0))
	var gv := VBoxContainer.new()
	gv.add_theme_constant_override("separation", 2)
	gp.add_child(gv)
	gv.add_child(UIKit.label("GADGET  [%s]  ·  SWITCH [%s]" % [InputRouter.get_binding_text(&"gadget_use"), InputRouter.get_binding_text(&"gadget_next")], 12, UIKit.TEXT_DIM, "label"))
	_gadget_name = UIKit.label("", 18, UIKit.BLUE, "heading")
	gv.add_child(_gadget_name)
	_gadget_status = UIKit.label("", 14, UIKit.TEXT, "label")
	gv.add_child(_gadget_status)
	br.add_child(gp)
	var wp := UIKit.panel(Vector2(360, 0))
	var wv := VBoxContainer.new()
	wv.add_theme_constant_override("separation", 0)
	wp.add_child(wv)
	_weapon_name = UIKit.label("", 16, UIKit.AMBER, "label")
	wv.add_child(_weapon_name)
	_ammo = UIKit.label("", 34, UIKit.TEXT, "heading")
	wv.add_child(_ammo)
	_reload_label = UIKit.label("", 13, UIKit.AMBER, "label")
	wv.add_child(_reload_label)
	br.add_child(wp)

	_fps = UIKit.label("", 14, UIKit.TEXT_DIM, "mono")
	_fps.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_fps.position = Vector2(-120, 12)
	_root.add_child(_fps)

	# --- recon overlay
	_recon = Control.new()
	_recon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_recon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_recon.visible = false
	var tint := ColorRect.new()
	tint.color = Color(0.1, 0.4, 0.2, 0.12)
	tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_recon.add_child(tint)
	var rl := UIKit.label("RECON FEED  —  [%s] exit   [%s] recall device" % [InputRouter.get_binding_text(&"interact"), InputRouter.get_binding_text(&"reload")], 18, UIKit.GREEN, "label")
	rl.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	rl.position = Vector2(-320, 90)
	_recon.add_child(rl)
	_root.add_child(_recon)


func _build_pause() -> void:
	_pause = Control.new()
	_pause.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.025, 0.03, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause.add_child(dim)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	v.position = Vector2(140, -260)
	v.add_theme_constant_override("separation", 12)
	_pause.add_child(v)
	v.add_child(UIKit.label("PAUSED", 54, UIKit.TEXT, "title"))
	v.add_child(UIKit.accent_line(120))
	v.add_child(UIKit.label(controller.mission.title.to_upper(), 18, UIKit.TEXT_DIM, "label"))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 18)
	v.add_child(spacer)
	v.add_child(UIKit.button("RESUME", _resume))
	v.add_child(UIKit.button("RESTART FROM CHECKPOINT", func(): Game.restart_from_checkpoint()))
	v.add_child(UIKit.button("RESTART MISSION", func(): Game.restart_mission()))
	v.add_child(UIKit.button("SETTINGS", _open_settings))
	v.add_child(UIKit.button("MAIN MENU", func(): Game.goto_main_menu()))
	_root.add_child(_pause)
	_settings = SettingsMenu.new()
	_settings.visible = false
	_settings.closed.connect(func():
		_settings.visible = false
		_pause.visible = true)
	_root.add_child(_settings)


func _build_death() -> void:
	_death = Control.new()
	_death.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_death.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.12, 0.0, 0.0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_death.add_child(dim)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	v.position = Vector2(-220, -160)
	v.add_theme_constant_override("separation", 12)
	_death.add_child(v)
	v.add_child(UIKit.label("GHOST DOWN", 58, Color(1, 0.5, 0.45), "title"))
	v.add_child(UIKit.accent_line(140, UIKit.RED))
	v.add_child(UIKit.label("Mission failed. Signal lost.", 18, UIKit.TEXT_DIM))
	v.add_child(UIKit.button("RESTART FROM CHECKPOINT", func(): Game.restart_from_checkpoint(), 440))
	v.add_child(UIKit.button("RESTART MISSION", func(): Game.restart_mission(), 440))
	v.add_child(UIKit.button("MAIN MENU", func(): Game.goto_main_menu(), 440))
	_root.add_child(_death)


# =========================================================================== updates

func _process(delta: float) -> void:
	if controller == null:
		return
	if InputRouter.is_just_pressed(&"pause") and not _death.visible and not controller.finished and not Game.is_transitioning():
		if _settings.visible:
			_settings.visible = false
			_pause.visible = true
		elif _paused:
			_resume()
		elif player.gadgets.recon_active:
			player.gadgets.exit_recon()
		else:
			_open_pause()
	_obj_full.visible = InputRouter.is_pressed(&"toggle_objectives") and not _paused
	_timer_label.text = "T+ " + UIKit.format_time(controller.elapsed)
	_vis_bar.value = player.get_visibility()
	var vis := player.get_visibility()
	_vis_bar.add_theme_stylebox_override("fill", UIKit.flat(UIKit.GREEN.lerp(UIKit.AMBER, clampf((vis - 0.3) / 0.6, 0.0, 1.0)), Color(0, 0, 0, 0), 0, 1, 0))
	var target_vig := clampf(1.0 - player.health.ratio(), 0.0, 1.0) * 0.9
	_vignette.modulate.a = lerpf(_vignette.modulate.a, target_vig, clampf(delta * 4.0, 0.0, 1.0))
	if _subtitle_t > 0.0:
		_subtitle_t -= delta
		if _subtitle_t <= 0.0:
			_subtitle.text = ""
	_restricted.text = ("! " + str(player.get_meta("restricted_name", "RESTRICTED AREA")).to_upper()) if player.get_meta("restricted", false) else ""
	_fps.visible = Settings.show_fps
	if Settings.show_fps:
		_fps.text = "%d FPS" % Engine.get_frames_per_second()
	if _prompt.text != "" and player.interactor.focus and is_instance_valid(player.interactor.focus):
		_prompt.text = "[%s]  %s" % [InputRouter.get_binding_text(&"interact"), player.interactor.focus.get_prompt(player)]


func _on_health(cur: float, mx: float) -> void:
	_health_bar.max_value = mx
	_health_bar.value = cur
	_health_label.text = str(int(ceil(cur)))
	var low := cur / mx < 0.35
	_health_bar.add_theme_stylebox_override("fill", UIKit.flat(UIKit.RED if low else Color(0.75, 0.78, 0.72), Color(0, 0, 0, 0), 0, 1, 0))


func _refresh_stance() -> void:
	if player.hidden_in:
		_stance.text = "HIDDEN"
	elif player.crouching:
		_stance.text = "CROUCHED"
	else:
		_stance.text = "STANDING"
	var v := player.get_visibility()
	_stance.text += "  ·  " + ("LOW" if v < 0.35 else ("MEDIUM" if v < 0.7 else "HIGH"))


func _refresh_gadget() -> void:
	var gs := player.gadgets.get_selected()
	if gs == null:
		_gadget_name.text = "—"
		_gadget_status.text = ""
		return
	_gadget_name.text = gs.data.display_name.to_upper()
	var parts := []
	if gs.charges_left >= 0:
		parts.append("CHARGES %d" % gs.charges_left)
	if gs.data.kind == GadgetData.Kind.RECON_CAMERA and is_instance_valid(player.gadgets.recon_device):
		parts.append("DEPLOYED — PRESS TO VIEW")
	elif gs.cooldown_left > 0.0:
		parts.append("RECHARGING %.0fs" % ceil(gs.cooldown_left))
	elif gs.charges_left == 0:
		parts.append("DEPLETED")
	else:
		parts.append("READY")
	_gadget_status.text = "  ·  ".join(parts)
	_gadget_status.add_theme_color_override("font_color", UIKit.GREEN if parts[-1] == "READY" else UIKit.TEXT_DIM)


func _refresh_objectives() -> void:
	var cur := controller.current_objective()
	_obj_current.text = cur.text if cur else ("Extraction complete" if controller.finished else "Reach extraction")
	if cur and cur.required_count > 1:
		_obj_current.text += "  (%d/%d)" % [controller.get_count(cur.id), cur.required_count]
	for c in _obj_optional.get_children():
		c.queue_free()
	for o in controller.mission.objectives:
		if o.optional and controller.objective_state[o.id]["revealed"]:
			var mark := "+" if controller.is_done(o.id) else ("×" if controller.is_failed(o.id) else "·")
			var col := UIKit.GREEN if controller.is_done(o.id) else (UIKit.RED if controller.is_failed(o.id) else UIKit.TEXT_DIM)
			_obj_optional.add_child(UIKit.label("%s  OPTIONAL · %s" % [mark, o.text], 14, col, "label"))
	for c in _obj_full_list.get_children():
		c.queue_free()
	_obj_full_list.add_child(UIKit.label("OBJECTIVES", 22, UIKit.AMBER, "heading"))
	_obj_full_list.add_child(UIKit.accent_line(60))
	for o in controller.mission.objectives:
		if not controller.objective_state[o.id]["revealed"]:
			continue
		var done := controller.is_done(o.id)
		var t := ("+  " if done else ("×  " if controller.is_failed(o.id) else "·  ")) + o.text
		if o.required_count > 1:
			t += "  (%d/%d)" % [controller.get_count(o.id), o.required_count]
		if o.optional:
			t += "   [optional]"
		_obj_full_list.add_child(UIKit.label(t, 18, UIKit.GREEN if done else (UIKit.TEXT_DIM if o.optional else UIKit.TEXT)))


func _on_message(text: String, kind: String) -> void:
	var col := UIKit.TEXT
	match kind:
		"complete": col = UIKit.GREEN
		"objective": col = UIKit.AMBER
		"danger", "failed": col = UIKit.RED
		"warning": col = UIKit.AMBER
		"checkpoint": col = UIKit.TEXT_DIM
		"intel": col = UIKit.BLUE
	var l := UIKit.label(text.to_upper() if kind in ["danger", "complete", "objective"] else text, 18 if kind != "danger" else 26, col, "label" if kind != "danger" else "heading")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 5)
	_messages.add_child(l)
	while _messages.get_child_count() > 4:
		_messages.get_child(0).queue_free()
		_messages.remove_child(_messages.get_child(0))
	var t := l.create_tween()
	t.tween_interval(3.5)
	t.tween_property(l, "modulate:a", 0.0, 0.8)
	t.tween_callback(l.queue_free)


func _on_voice(speaker: String, text: String, duration: float) -> void:
	if not Settings.subtitles or text == "":
		return
	_subtitle.text = "%s:  %s" % [speaker, text]
	_subtitle_t = maxf(duration + 0.6, 2.5)


func _on_focus(target: Interactable) -> void:
	if target:
		_prompt.text = "[%s]  %s" % [InputRouter.get_binding_text(&"interact"), target.get_prompt(player)]
	else:
		_prompt.text = ""
		_prompt_bar.visible = false


func _on_player_died() -> void:
	Game.set_mouse_captured(false)
	var t := create_tween()
	t.tween_interval(2.2)
	t.tween_callback(func():
		_death.visible = true
		var b := _death.find_children("*", "Button", true, false)
		if not b.is_empty():
			(b[0] as Button).grab_focus())


func _open_pause() -> void:
	_paused = true
	_pause.visible = true
	Game.set_paused(true)
	Game.set_mouse_captured(false)
	AudioManager.play_ui(&"ui_open")
	var b := _pause.find_children("*", "Button", true, false)
	if not b.is_empty():
		(b[0] as Button).grab_focus()


func _resume() -> void:
	_paused = false
	_pause.visible = false
	_settings.visible = false
	Game.set_paused(false)
	Game.set_mouse_captured(true)


func _open_settings() -> void:
	_pause.visible = false
	_settings.open()
