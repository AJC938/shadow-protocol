extends Node
## Autoload "Game" — application flow: menus, briefing, deployment, results, ending.
## Holds only transient hand-over data between scenes; persistence is SaveSystem's job.

signal paused_changed(paused: bool)

const MAIN_MENU := "res://scenes/ui/main_menu.tscn"
const BRIEFING := "res://scenes/ui/briefing.tscn"
const RESULTS := "res://scenes/ui/results.tscn"
const ENDING := "res://scenes/ui/ending.tscn"

## Mission chosen for the briefing / currently deployed.
var current_mission_id: String = ""
## Checkpoint state to restore when the next mission scene loads (empty = fresh start).
var pending_checkpoint: Dictionary = {}
## Results of the last completed mission (read by the results screen).
var last_results: Dictionary = {}
## Automation flags parsed from the command line (used by capture/test tooling).
var automation: Dictionary = {}

var _fade_layer: CanvasLayer
var _fade_rect: ColorRect
var _transitioning: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_parse_cmdline()
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 100
	add_child(_fade_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0.02, 0.025, 0.03, 0.0)
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.add_child(_fade_rect)


func _parse_cmdline() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sp-"):
			var kv := a.substr(5).split("=", true, 1)
			automation[kv[0]] = kv[1] if kv.size() > 1 else "1"


# --------------------------------------------------------------------------- transitions

func change_scene(path: String, fade_time: float = 0.45) -> void:
	if _transitioning:
		return
	_transitioning = true
	set_paused(false)
	var t := create_tween()
	t.tween_property(_fade_rect, "color:a", 1.0, fade_time)
	await t.finished
	AudioManager.clear_voice()
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("Game: cannot load %s (%s)" % [path, error_string(err)])
	await get_tree().process_frame
	await get_tree().process_frame
	var t2 := create_tween()
	t2.tween_property(_fade_rect, "color:a", 0.0, fade_time)
	_transitioning = false


func fade_flash(color: Color, time: float) -> void:
	_fade_rect.color = Color(color.r, color.g, color.b, 0.0)
	var t := create_tween()
	t.tween_property(_fade_rect, "color:a", color.a, time * 0.3)
	t.tween_property(_fade_rect, "color:a", 0.0, time * 0.7)
	t.tween_callback(func(): _fade_rect.color = Color(0.02, 0.025, 0.03, 0.0))


func is_transitioning() -> bool:
	return _transitioning


# --------------------------------------------------------------------------- flow

func goto_main_menu() -> void:
	current_mission_id = ""
	pending_checkpoint = {}
	set_mouse_captured(false)
	change_scene(MAIN_MENU)


func start_new_game() -> void:
	SaveSystem.new_campaign()
	open_briefing("m01")


func can_continue() -> bool:
	return SaveSystem.has_progress()


func continue_game() -> void:
	var cp := SaveSystem.get_checkpoint()
	if not cp.is_empty():
		deploy(str(cp["mission"]), cp["state"])
		return
	if SaveSystem.is_campaign_complete():
		open_briefing("m03")
		return
	open_briefing(SaveSystem.get_current_mission())


func open_briefing(mission_id: String) -> void:
	if not Campaign.is_valid(mission_id):
		push_error("Game: unknown mission %s" % mission_id)
		return
	current_mission_id = mission_id
	set_mouse_captured(false)
	change_scene(BRIEFING)


## Loads a mission scene. `checkpoint` restores a saved in-mission state.
func deploy(mission_id: String, checkpoint: Dictionary = {}) -> void:
	var m := Campaign.get_mission(mission_id)
	if m == null:
		push_error("Game: cannot deploy %s" % mission_id)
		return
	current_mission_id = mission_id
	pending_checkpoint = checkpoint
	SaveSystem.set_current(mission_id)
	change_scene(m.scene_path)


func restart_mission() -> void:
	SaveSystem.clear_checkpoint()
	deploy(current_mission_id, {})


func restart_from_checkpoint() -> void:
	var cp := SaveSystem.get_checkpoint()
	if not cp.is_empty() and str(cp["mission"]) == current_mission_id:
		deploy(current_mission_id, cp["state"])
	else:
		deploy(current_mission_id, {})


## Called by MissionController after successful extraction.
func mission_completed(results: Dictionary) -> void:
	last_results = results
	SaveSystem.record_mission_complete(results["mission_id"], results["grade"], results["time"],
		results["score"], results["optional_done"], results["kills"], results["detections"])
	set_mouse_captured(false)
	change_scene(RESULTS, 0.8)


func after_results() -> void:
	var nxt := Campaign.next_of(str(last_results.get("mission_id", "")))
	if nxt == "":
		change_scene(ENDING, 1.0)
	else:
		open_briefing(nxt)


# --------------------------------------------------------------------------- pause / mouse

func set_paused(p: bool) -> void:
	if get_tree().paused == p:
		return
	get_tree().paused = p
	InputRouter.gameplay_blocked = p
	paused_changed.emit(p)


func set_mouse_captured(c: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if c else Input.MOUSE_MODE_VISIBLE


func quit_game() -> void:
	SaveSystem.save_game()
	Settings.save_settings()
	get_tree().quit()
