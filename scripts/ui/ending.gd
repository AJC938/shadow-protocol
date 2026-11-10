extends Control
## Campaign ending: narrative closure sequence, then credits and return to menu.

const LINES := [
	["ORACLE", "GHOST, the package is clean. Every transfer, every name, every signature. Northgate's black network is finished.", &"vo_end_1"],
	["ORACLE", "The tribunal has the files. Commander Voss's operation goes dark tonight, and the facility goes with it.", &"vo_end_2"],
	["ORACLE", "No flags. No medals. No record you were ever there. That was always the protocol.", &"vo_end_3"],
	["GHOST", "Copy that, Oracle. Shadow Protocol complete. Coming home.", &"vo_end_4"],
]

var _label: Label
var _speaker: Label
var _index: int = -1
var _wait: float = 0.0
var _done: Control


func _ready() -> void:
	theme = UIKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	InputRouter.gameplay_blocked = true
	Game.set_mouse_captured(false)
	add_child(MenuStage.new())
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.012, 0.015, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	v.position = Vector2(-560, -140)
	v.custom_minimum_size = Vector2(1120, 0)
	v.add_theme_constant_override("separation", 14)
	add_child(v)
	_speaker = UIKit.label("", 18, UIKit.AMBER, "label")
	v.add_child(_speaker)
	_label = UIKit.label("", 30, UIKit.TEXT, "heading")
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_label)
	_done = VBoxContainer.new()
	_done.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_done.position = Vector2(-300, -170)
	_done.visible = false
	add_child(_done)
	_done.add_child(UIKit.label("SHADOW PROTOCOL", 60, UIKit.TEXT, "title"))
	_done.add_child(UIKit.label("CAMPAIGN COMPLETE", 22, UIKit.AMBER, "label"))
	_done.add_child(UIKit.accent_line(200))
	var st: Dictionary = SaveSystem.data.get("stats", {})
	_done.add_child(UIKit.label("Operations completed: 3   ·   Hostiles neutralised: %d   ·   Detections: %d" % [int(st.get("total_kills", 0)), int(st.get("total_detections", 0))], 16, UIKit.TEXT_DIM))
	_done.add_child(UIKit.button("RETURN TO MAIN MENU", func(): Game.goto_main_menu(), 400))
	AudioManager.play_music(&"ending", 2.0)
	_wait = 1.5


func _process(delta: float) -> void:
	if _done.visible:
		return
	_wait -= delta
	if _wait > 0.0:
		return
	_index += 1
	if _index >= LINES.size():
		_label.text = ""
		_speaker.text = ""
		_done.visible = true
		(_done.find_children("*", "Button", true, false)[0] as Button).grab_focus()
		return
	var line: Array = LINES[_index]
	_speaker.text = line[0]
	_label.text = line[1]
	_label.modulate.a = 0.0
	create_tween().tween_property(_label, "modulate:a", 1.0, 0.6)
	AudioManager.play_voice(line[2], line[0], "")
	var s := AudioManager.get_stream(line[2])
	_wait = maxf(5.5, (s.get_length() + 1.2) if s else 5.5)


func _unhandled_input(event: InputEvent) -> void:
	if not _done.visible and (event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"ui_cancel")):
		_wait = 0.0
