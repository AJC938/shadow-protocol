extends Control
## Mission briefing: name, background, narrative, objectives, equipment, deploy.

const WEAPON_INFO := {
	&"pistol": ["MK-9 SUPPRESSED PISTOL", "Quiet semi-automatic sidearm. Short sound radius."],
	&"rifle": ["AR-7 ASSAULT RIFLE", "Automatic, accurate at range. Loud — every guard nearby will hear it."],
	&"shotgun": ["SG-12 TACTICAL SHOTGUN", "Devastating up close, slow, very loud."],
}
const GADGET_INFO := {
	&"recon": ["RECON CAMERA", "Throw onto a surface, view remotely and tag hostiles in its view."],
	&"disruptor": ["SIGNAL DISRUPTOR", "Jams cameras, alarm panels and radios within 10 m for 12 s. 3 charges."],
	&"scanner": ["TACTICAL SCANNER", "Pulse that reveals hostiles and security devices within 25 m for 6 s."],
}

var mission: MissionData


func _ready() -> void:
	theme = UIKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	InputRouter.gameplay_blocked = true
	Game.set_mouse_captured(false)
	mission = Campaign.get_mission(Game.current_mission_id)
	if mission == null:
		Game.goto_main_menu()
		return
	UIKit.backdrop(self)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 110)
	margin.add_theme_constant_override("margin_top", 70)
	margin.add_theme_constant_override("margin_bottom", 60)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)
	root.add_child(UIKit.label("OPERATION %02d  ·  %s" % [mission.number, mission.location.to_upper()], 18, UIKit.AMBER, "label"))
	root.add_child(UIKit.label(mission.title.to_upper(), 64, UIKit.TEXT, "title"))
	root.add_child(UIKit.accent_line(200))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 30)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.4
	cols.add_child(left)
	var bp := UIKit.panel()
	bp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var bv := VBoxContainer.new()
	bp.add_child(bv)
	bv.add_child(UIKit.label("BACKGROUND", 15, UIKit.TEXT_DIM, "label"))
	var bg := UIKit.label(mission.background, 18, UIKit.TEXT_DIM)
	bg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bv.add_child(bg)
	bv.add_child(UIKit.accent_line(40, UIKit.LINE))
	bv.add_child(UIKit.label("BRIEFING  —  ORACLE", 15, UIKit.TEXT_DIM, "label"))
	var br := UIKit.label(mission.briefing, 20, UIKit.TEXT)
	br.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bv.add_child(br)
	left.add_child(bp)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	var op := UIKit.panel()
	var ov := VBoxContainer.new()
	ov.add_theme_constant_override("separation", 6)
	op.add_child(ov)
	ov.add_child(UIKit.label("OBJECTIVES", 15, UIKit.TEXT_DIM, "label"))
	var n := 1
	for o in mission.objectives:
		if o.hidden:
			continue
		var t := ("·  OPTIONAL · " if o.optional else "%d.  " % n) + o.text
		if not o.optional:
			n += 1
		var l := UIKit.label(t, 17, UIKit.TEXT_DIM if o.optional else UIKit.TEXT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ov.add_child(l)
	right.add_child(op)
	var ep := UIKit.panel()
	var ev := VBoxContainer.new()
	ev.add_theme_constant_override("separation", 4)
	ep.add_child(ev)
	ev.add_child(UIKit.label("EQUIPMENT", 15, UIKit.TEXT_DIM, "label"))
	for w in mission.weapons:
		var wi: Array = WEAPON_INFO.get(w, [String(w), ""])
		ev.add_child(UIKit.label(wi[0], 16, UIKit.AMBER, "label"))
		ev.add_child(UIKit.label(wi[1], 15, UIKit.TEXT_DIM))
	for g in mission.gadgets:
		var gi: Array = GADGET_INFO.get(g, [String(g), ""])
		ev.add_child(UIKit.label(gi[0], 16, UIKit.BLUE, "label"))
		ev.add_child(UIKit.label(gi[1], 15, UIKit.TEXT_DIM))
	right.add_child(ep)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	root.add_child(row)
	var deploy := UIKit.button("DEPLOY", func(): Game.deploy(mission.id), 300)
	row.add_child(deploy)
	if SaveSystem.has_checkpoint() and str(SaveSystem.get_checkpoint()["mission"]) == mission.id:
		row.add_child(UIKit.button("RESUME CHECKPOINT", func(): Game.deploy(mission.id, SaveSystem.get_checkpoint()["state"]), 340))
	row.add_child(UIKit.button("BACK", func(): Game.goto_main_menu(), 200))
	deploy.grab_focus.call_deferred()
	AudioManager.play_music(&"briefing", 1.5)
	if mission.briefing_voice != &"":
		AudioManager.play_voice(mission.briefing_voice, "ORACLE", "")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		Game.goto_main_menu()
