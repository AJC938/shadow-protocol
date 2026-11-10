extends Control
## Main menu: Continue, New Game, Missions, Settings, Credits, Exit.

var _main: VBoxContainer
var _missions: Control
var _credits: Control
var _confirm: Control
var _settings: SettingsMenu
var _continue_btn: Button


func _ready() -> void:
	theme = UIKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	InputRouter.gameplay_blocked = true
	Game.set_mouse_captured(false)
	add_child(MenuStage.new())
	var shade := TextureRect.new()
	var g := GradientTexture2D.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.02, 0.025, 0.03, 0.97))
	grad.set_color(1, Color(0.02, 0.025, 0.03, 0.0))
	g.gradient = grad
	g.fill_from = Vector2(0, 0)
	g.fill_to = Vector2(0.75, 0)
	shade.texture = g
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	_main = VBoxContainer.new()
	_main.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	_main.position = Vector2(140, -330)
	_main.add_theme_constant_override("separation", 12)
	add_child(_main)
	_main.add_child(UIKit.label("SHADOW", 92, UIKit.TEXT, "title"))
	_main.add_child(UIKit.label("PROTOCOL", 46, UIKit.AMBER, "title"))
	_main.add_child(UIKit.accent_line(220))
	_main.add_child(UIKit.label("A tactical stealth campaign", 18, UIKit.TEXT_DIM, "label"))
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 26)
	_main.add_child(sp)
	_continue_btn = UIKit.button("CONTINUE", _on_continue)
	_main.add_child(_continue_btn)
	_main.add_child(UIKit.button("NEW GAME", _on_new_game))
	_main.add_child(UIKit.button("MISSIONS", _open_missions))
	_main.add_child(UIKit.button("SETTINGS", _open_settings))
	_main.add_child(UIKit.button("CREDITS", _open_credits))
	_main.add_child(UIKit.button("EXIT", func(): Game.quit_game()))

	var ver := UIKit.label("v%s  ·  Godot %s" % [ProjectSettings.get_setting("application/config/version", "2.0"), Engine.get_version_info()["string"]], 13, UIKit.TEXT_DIM, "mono")
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.position = Vector2(-380, -40)
	add_child(ver)

	_build_missions()
	_build_credits()
	_build_confirm()
	_settings = SettingsMenu.new()
	_settings.visible = false
	_settings.closed.connect(_back)
	add_child(_settings)
	_refresh()
	AudioManager.play_music(&"menu", 1.5)
	AudioManager.stop_ambience()
	# Dev capture hooks (only active with --sp-open=<panel>).
	match str(Game.automation.get("open", "")):
		"settings": _open_settings.call_deferred()
		"missions": _open_missions.call_deferred()
		"credits": _open_credits.call_deferred()
	if SaveSystem.last_load_status in ["corrupt", "unsupported_version"]:
		_toast("Save data could not be read (%s). A backup was kept and a fresh profile started." % SaveSystem.last_load_status)


func _refresh() -> void:
	_continue_btn.disabled = not Game.can_continue()
	if SaveSystem.has_checkpoint():
		var cp := SaveSystem.get_checkpoint()
		var m := Campaign.get_mission(str(cp["mission"]))
		_continue_btn.text = "CONTINUE  ·  %s (checkpoint)" % (m.title.to_upper() if m else "")
	elif Game.can_continue():
		var m2 := Campaign.get_mission(SaveSystem.get_current_mission())
		_continue_btn.text = "CONTINUE  ·  %s" % (m2.title.to_upper() if m2 else "")
	else:
		_continue_btn.text = "CONTINUE"
	(_continue_btn if not _continue_btn.disabled else _main.get_child(6)).grab_focus.call_deferred()


func _toast(text: String) -> void:
	var l := UIKit.label(text, 16, UIKit.AMBER)
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	l.position = Vector2(-500, -90)
	l.custom_minimum_size = Vector2(1000, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(l)
	var t := l.create_tween()
	t.tween_interval(6.0)
	t.tween_property(l, "modulate:a", 0.0, 1.0)
	t.tween_callback(l.queue_free)


func _on_continue() -> void:
	Game.continue_game()


func _on_new_game() -> void:
	if SaveSystem.has_progress():
		_main.visible = false
		_confirm.visible = true
		(_confirm.find_children("*", "Button", true, false)[1] as Button).grab_focus()
	else:
		Game.start_new_game()


func _back() -> void:
	_settings.visible = false
	_missions.visible = false
	_credits.visible = false
	_confirm.visible = false
	_main.visible = true
	_refresh()


func _open_settings() -> void:
	_main.visible = false
	_settings.open()


func _open_missions() -> void:
	_main.visible = false
	_build_missions()
	_missions.visible = true


func _open_credits() -> void:
	_main.visible = false
	_credits.visible = true
	(_credits.find_children("*", "Button", true, false)[0] as Button).grab_focus()


func _build_confirm() -> void:
	_confirm = VBoxContainer.new()
	_confirm.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	_confirm.position = Vector2(140, -160)
	_confirm.visible = false
	add_child(_confirm)
	_confirm.add_child(UIKit.label("START A NEW CAMPAIGN?", 34, UIKit.TEXT, "title"))
	_confirm.add_child(UIKit.accent_line(140))
	_confirm.add_child(UIKit.label("Existing campaign progress and checkpoints will be overwritten.", 18, UIKit.TEXT_DIM))
	_confirm.add_child(UIKit.button("YES, START OVER", func(): Game.start_new_game(), 380))
	_confirm.add_child(UIKit.button("CANCEL", _back, 380))


func _build_missions() -> void:
	if _missions:
		_missions.queue_free()
	_missions = VBoxContainer.new()
	_missions.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	_missions.position = Vector2(140, -330)
	_missions.visible = false
	_missions.add_theme_constant_override("separation", 14)
	add_child(_missions)
	_missions.add_child(UIKit.label("MISSIONS", 46, UIKit.TEXT, "title"))
	_missions.add_child(UIKit.accent_line(120))
	for id in Campaign.MISSION_IDS:
		var m := Campaign.get_mission(id)
		var unlocked := SaveSystem.is_unlocked(id)
		var rec := SaveSystem.get_record(id)
		var p := UIKit.panel(Vector2(640, 0))
		var h := HBoxContainer.new()
		p.add_child(h)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 2)
		info.add_child(UIKit.label("OPERATION %02d" % m.number, 14, UIKit.AMBER, "label"))
		info.add_child(UIKit.label(m.title.to_upper() if unlocked else "CLASSIFIED", 26, UIKit.TEXT if unlocked else UIKit.TEXT_DIM, "heading"))
		var sub := m.location
		if not rec.is_empty():
			sub += "   ·   GRADE %s   ·   BEST %s" % [rec["grade"], UIKit.format_time(rec["best_time"])]
		elif not unlocked:
			sub = "Complete the previous operation to unlock."
		info.add_child(UIKit.label(sub, 15, UIKit.TEXT_DIM))
		h.add_child(info)
		var b := UIKit.button("BRIEFING" if unlocked else "LOCKED", func(): Game.open_briefing(id), 160)
		b.disabled = not unlocked
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.add_child(b)
		_missions.add_child(p)
	_missions.add_child(UIKit.button("BACK", _back, 220))
	(_missions.find_children("*", "Button", true, false)[0] as Button).grab_focus.call_deferred()


func _build_credits() -> void:
	_credits = VBoxContainer.new()
	_credits.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	_credits.position = Vector2(140, -330)
	_credits.visible = false
	add_child(_credits)
	_credits.add_child(UIKit.label("CREDITS", 46, UIKit.TEXT, "title"))
	_credits.add_child(UIKit.accent_line(120))
	var text := """SHADOW PROTOCOL — an original tactical stealth game.

Design, code, procedural characters, weapons, audio and music:
  developed with Claude Code (Anthropic) for the project owner.

Engine: Godot Engine 4.7 (MIT licence) — godotengine.org

3D props, textures and night-sky HDRI: Poly Haven (CC0)
  polyhaven.com — authors credited per asset in ASSET_CREDITS.md

Voice lines: synthesised locally with Microsoft Windows speech voices,
  processed into radio transmissions.

All characters, places and events are fictional."""
	var l := UIKit.label(text, 18, UIKit.TEXT)
	l.custom_minimum_size = Vector2(760, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_credits.add_child(l)
	_credits.add_child(UIKit.button("BACK", _back, 220))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and not _main.visible and not _settings.visible:
		_back()
