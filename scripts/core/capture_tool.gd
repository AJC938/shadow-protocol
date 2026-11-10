extends Node
## Development capture tool (only active with --sp-capture=<dir>).
## Waits for the mission to settle, then saves screenshots from the player camera
## and from the level's `capture_points()` (if defined), logs FPS, then quits.
## Used for visual verification and performance measurement — never in normal play.

var out_dir: String = ""
var _frames: int = 0
var _shots: Array = []
var _index: int = -1
var _wait: int = 0
var _cam: Camera3D
var _fps_samples: Array[float] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	out_dir = str(Game.automation.get("capture", ""))
	DirAccess.make_dir_recursive_absolute(out_dir)


func _process(delta: float) -> void:
	_frames += 1
	var scene := get_tree().current_scene
	if not (scene is MissionLevel) and not Game.automation.has("menu_shot"):
		if _frames > 1200:
			get_tree().quit()
		return
	if Game.automation.has("menu_shot"):
		if _frames == 240:
			_save(str(Game.automation.get("menu_shot", "menu")))
			get_tree().quit()
		return
	var level := scene as MissionLevel
	if _index == -1:
		if _frames < 240:
			return
		_shots = [["player", null]]
		if level.has_method("capture_points"):
			for p in level.capture_points():
				_shots.append(p)
		_index = 0
		_wait = 30
		_fps_samples.clear()
	if _wait > 0:
		_wait -= 1
		if _index < _shots.size() and _wait < 20:
			_fps_samples.append(1.0 / maxf(delta, 0.0001))
		return
	if _index >= _shots.size():
		var avg := 0.0
		for f in _fps_samples:
			avg += f
		avg /= maxf(1.0, _fps_samples.size())
		print("[CAPTURE] avg fps %.1f over %d samples  draw_calls=%d  objects=%d" % [avg, _fps_samples.size(),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)])
		get_tree().quit()
		return
	var shot: Array = _shots[_index]
	_save(str(shot[0]))
	_index += 1
	if _index < _shots.size():
		var s: Array = _shots[_index]
		if s[1] != null:
			if _cam == null:
				_cam = Camera3D.new()
				_cam.fov = 70.0
				level.add_child(_cam)
			_cam.global_position = s[1]
			_cam.look_at(s[2], Vector3.UP)
			_cam.current = true
		_wait = 30


func _save(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var prefix := Game.current_mission_id if Game.current_mission_id != "" and not Game.automation.has("menu_shot") else "ui"
	var path := out_dir.path_join("%s_%s.png" % [prefix, name])
	img.save_png(path)
	print("[CAPTURE] saved ", path)
