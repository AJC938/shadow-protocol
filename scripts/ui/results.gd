extends Control
## Mission results: objectives, optional objectives, time, detections, tactical
## performance, grade and campaign progression.

func _ready() -> void:
	theme = UIKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	InputRouter.gameplay_blocked = true
	Game.set_mouse_captured(false)
	var r: Dictionary = Game.last_results
	if r.is_empty():
		Game.goto_main_menu()
		return
	UIKit.backdrop(self)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 120)
	margin.add_theme_constant_override("margin_right", 120)
	margin.add_theme_constant_override("margin_top", 70)
	margin.add_theme_constant_override("margin_bottom", 60)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)
	root.add_child(UIKit.label("MISSION COMPLETE", 18, UIKit.GREEN, "label"))
	root.add_child(UIKit.label(str(r["title"]).to_upper(), 58, UIKit.TEXT, "title"))
	root.add_child(UIKit.accent_line(200))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 30)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)

	# Grade block
	var gp := UIKit.panel(Vector2(300, 0))
	var gv := VBoxContainer.new()
	gv.alignment = BoxContainer.ALIGNMENT_CENTER
	gp.add_child(gv)
	gv.add_child(UIKit.label("GRADE", 16, UIKit.TEXT_DIM, "label"))
	var grade := UIKit.label(str(r["grade"]), 150, UIKit.AMBER, "title")
	grade.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gv.add_child(grade)
	var style := UIKit.label(str(r["style"]).to_upper(), 20, UIKit.TEXT, "heading")
	style.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gv.add_child(style)
	var score := UIKit.label("SCORE  %d" % int(r["score"]), 18, UIKit.TEXT_DIM, "label")
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gv.add_child(score)
	cols.add_child(gp)
	grade.scale = Vector2(1.6, 1.6)
	grade.pivot_offset = Vector2(80, 90)
	grade.modulate.a = 0.0
	var t := create_tween()
	t.tween_interval(0.5)
	t.tween_property(grade, "modulate:a", 1.0, 0.25)
	t.parallel().tween_property(grade, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_callback(func(): AudioManager.play_ui(&"ui_grade"))

	# Objectives
	var op := UIKit.panel()
	op.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ov := VBoxContainer.new()
	ov.add_theme_constant_override("separation", 6)
	op.add_child(ov)
	ov.add_child(UIKit.label("OBJECTIVES", 15, UIKit.TEXT_DIM, "label"))
	for o in r["objectives"]:
		var mark := "+" if o["done"] else ("×" if o["failed"] else "—")
		var col := UIKit.GREEN if o["done"] else (UIKit.RED if o["failed"] else UIKit.TEXT_DIM)
		ov.add_child(UIKit.label("%s  %s%s" % [mark, o["text"], "   (optional)" if o["optional"] else ""], 17, col))
	ov.add_child(UIKit.label("Optional objectives: %d / %d" % [r["optional_done"], r["optional_total"]], 16, UIKit.TEXT, "label"))
	cols.add_child(op)

	# Stats
	var sp := UIKit.panel(Vector2(380, 0))
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 6)
	sp.add_child(sv)
	sv.add_child(UIKit.label("TACTICAL PERFORMANCE", 15, UIKit.TEXT_DIM, "label"))
	var rows := [
		["Time", UIKit.format_time(r["time"])],
		["Detection events", str(r["detections"])],
		["Alarms raised", str(r["alarms"])],
		["Hostiles neutralised", str(r["kills"])],
		["Headshots", str(r["headshots"])],
		["Accuracy", "%d%%" % int(round(float(r["accuracy"]) * 100.0))],
		["Gadget uses", str(r["gadget_uses"])],
		["Intel recovered", str(r["intel"])],
		["Retries", str(r["deaths"])],
	]
	for row in rows:
		var h := HBoxContainer.new()
		var a := UIKit.label(row[0], 17, UIKit.TEXT_DIM)
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(a)
		h.add_child(UIKit.label(row[1], 17, UIKit.TEXT, "label"))
		sv.add_child(h)
	cols.add_child(sp)

	var nxt := Campaign.next_of(str(r["mission_id"]))
	var progress := "Campaign complete." if nxt == "" else "Next operation unlocked: %s" % Campaign.get_mission(nxt).title
	root.add_child(UIKit.label(progress.to_upper(), 18, UIKit.AMBER, "label"))
	var brow := HBoxContainer.new()
	root.add_child(brow)
	var cont := UIKit.button("CONTINUE" if nxt != "" else "FINAL DEBRIEF", func(): Game.after_results(), 320)
	brow.add_child(cont)
	brow.add_child(UIKit.button("REPLAY MISSION", func(): Game.deploy(str(r["mission_id"])), 300))
	brow.add_child(UIKit.button("MAIN MENU", func(): Game.goto_main_menu(), 240))
	cont.grab_focus.call_deferred()
	AudioManager.play_music(&"debrief", 1.0)
	var m := Campaign.get_mission(str(r["mission_id"]))
	if m and m.debrief != "":
		AudioManager.play_voice(StringName("vo_debrief_%s" % m.id), "ORACLE", m.debrief)
