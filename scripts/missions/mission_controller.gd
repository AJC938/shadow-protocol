class_name MissionController
extends Node
## Runtime state of one mission: objectives, statistics, checkpoints, failure,
## extraction and results. Level scripts and objective components talk to it;
## it talks to Game/SaveSystem only at checkpoints and at the end.

signal objective_updated(id: StringName)
signal objective_completed(id: StringName, optional: bool)
signal objectives_changed
signal mission_message(text: String, kind: String)
signal player_died
signal detection_changed(detected: bool)
signal mission_finished(results: Dictionary)
signal before_finish

var mission: MissionData
var player: Player
var level_root: Node3D
## id -> {"done": bool, "count": int, "revealed": bool}
var objective_state: Dictionary = {}
var elapsed: float = 0.0
var finished: bool = false
var failed: bool = false

# statistics
var kills: int = 0
var headshots: int = 0
var detections: int = 0
var alarms: int = 0
var deaths: int = 0
var intel: Array[String] = []
## objective id -> Node3D or Vector3 used for the HUD waypoint.
var objective_targets: Dictionary = {}
## Scripted alarms (e.g. mission lockdowns) do not count as player detections.
var ignore_alarm_detection: bool = false
var _detected_now: bool = false
var _detect_check: float = 0.0
var _checkpoint_cooldown: float = 0.0


static func find(n: Node) -> MissionController:
	if n == null or not n.is_inside_tree():
		return null
	return n.get_tree().get_first_node_in_group("mission_controller") as MissionController


func _ready() -> void:
	add_to_group("mission_controller")


func setup(m: MissionData, p: Player, root: Node3D) -> void:
	mission = m
	player = p
	level_root = root
	objective_state.clear()
	for o in mission.objectives:
		objective_state[o.id] = {"done": false, "count": 0, "revealed": not o.hidden}
	player.died.connect(_on_player_died)
	player.weapons.hit_confirmed.connect(_on_hit_confirmed)
	var alarm := AlarmSystem.find(self)
	if alarm:
		alarm.raised.connect(func(_o, _r): alarms += 1)


# --------------------------------------------------------------------------- objectives

func set_objective_target(id: StringName, target) -> void:
	objective_targets[id] = target


func get_objective(id: StringName) -> ObjectiveData:
	for o in mission.objectives:
		if o.id == id:
			return o
	return null


func is_done(id: StringName) -> bool:
	return objective_state.has(id) and objective_state[id]["done"]


func get_count(id: StringName) -> int:
	return int(objective_state.get(id, {}).get("count", 0))


## First incomplete main objective (the one the HUD highlights).
func current_objective() -> ObjectiveData:
	for o in mission.objectives:
		if not o.optional and not is_done(o.id) and objective_state[o.id]["revealed"]:
			return o
	return null


func reveal_objective(id: StringName) -> void:
	if objective_state.has(id) and not objective_state[id]["revealed"]:
		objective_state[id]["revealed"] = true
		mission_message.emit("New objective: %s" % get_objective(id).text, "objective")
		objectives_changed.emit()


## Increments a counted objective; completes it when the count is reached.
func progress_objective(id: StringName, amount: int = 1) -> void:
	var o := get_objective(id)
	if o == null or is_done(id) or finished:
		return
	objective_state[id]["count"] += amount
	if objective_state[id]["count"] >= o.required_count:
		complete_objective(id)
	else:
		mission_message.emit("%s  %d/%d" % [o.text, objective_state[id]["count"], o.required_count], "progress")
		AudioManager.play_ui(&"ui_objective_progress")
		objective_updated.emit(id)
		objectives_changed.emit()


func complete_objective(id: StringName, silent: bool = false) -> void:
	var o := get_objective(id)
	if o == null or is_done(id) or finished:
		return
	objective_state[id]["done"] = true
	objective_state[id]["count"] = o.required_count
	objective_state[id]["revealed"] = true
	if not o.optional:
		# Completing a later main objective implies the earlier ones.
		for prev in mission.objectives:
			if prev == o:
				break
			if not prev.optional and not is_done(prev.id):
				objective_state[prev.id]["done"] = true
	if not silent:
		mission_message.emit(("Optional complete: " if o.optional else "Objective complete: ") + o.text, "complete")
		AudioManager.play_ui(&"ui_objective_complete")
	objective_completed.emit(id, o.optional)
	objectives_changed.emit()
	if not o.optional and not silent:
		_checkpoint_cooldown = 0.0
		save_checkpoint()


## Fails an optional objective (e.g. "no alarms") — shown struck-through.
func fail_optional(id: StringName) -> void:
	var o := get_objective(id)
	if o == null or not o.optional or is_done(id) or objective_state[id].get("failed", false):
		return
	objective_state[id]["failed"] = true
	mission_message.emit("Optional failed: " + o.text, "failed")
	objectives_changed.emit()


func is_failed(id: StringName) -> bool:
	return objective_state.has(id) and objective_state[id].get("failed", false)


func all_main_done(except: StringName = &"") -> bool:
	for o in mission.objectives:
		if not o.optional and o.id != except and not is_done(o.id):
			return false
	return true


func on_intel_collected(item_id: String, display_name: String) -> void:
	if not intel.has(item_id):
		intel.append(item_id)
	mission_message.emit("Intel secured: %s" % display_name, "intel")


# --------------------------------------------------------------------------- statistics

func _on_hit_confirmed(_target: Node, killed: bool, headshot: bool) -> void:
	if killed and _target.is_in_group("enemy"):
		kills += 1
		if headshot:
			headshots += 1


func _process(delta: float) -> void:
	if finished or failed:
		return
	elapsed += delta
	_checkpoint_cooldown -= delta
	_detect_check -= delta
	if _detect_check <= 0.0:
		_detect_check = 0.25
		var now := false
		for n in get_tree().get_nodes_in_group("enemy"):
			var e := n as Enemy
			if e and not e.is_dead() and e.state_name == &"combat":
				now = true
				break
		var alarm := AlarmSystem.find(self)
		if alarm and alarm.active and not ignore_alarm_detection:
			now = true
		if now and not _detected_now:
			detections += 1
			mission_message.emit("DETECTED", "danger")
			for o in mission.objectives:
				if o.optional and String(o.id).begins_with("undetected"):
					fail_optional(o.id)
		if now != _detected_now:
			_detected_now = now
			detection_changed.emit(now)
			AudioManager.play_music(&"combat" if now else mission.music, 2.0)


func is_detected() -> bool:
	return _detected_now


# --------------------------------------------------------------------------- checkpoints

func save_checkpoint() -> void:
	if finished or failed or player == null or player.is_dead():
		return
	var state := {
		"objectives": objective_state.duplicate(true),
		"elapsed": elapsed,
		"stats": {"kills": kills, "headshots": headshots, "detections": detections, "alarms": alarms,
			"deaths": deaths, "intel": intel.duplicate()},
		"player": player.get_save_state(),
		"enemies_dead": [],
		"objects": {},
		"alarm_offline": false,
		"level": {},
	}
	for n in get_tree().get_nodes_in_group("enemy"):
		var e := n as Enemy
		if e and e.is_dead():
			state["enemies_dead"].append(String(level_root.get_path_to(e)))
	for n in get_tree().get_nodes_in_group("persistent"):
		if n.has_method("get_save_state"):
			state["objects"][String(level_root.get_path_to(n))] = n.get_save_state()
	var alarm := AlarmSystem.find(self)
	if alarm:
		state["alarm_offline"] = alarm.offline
	if level_root.has_method("get_level_state"):
		state["level"] = level_root.get_level_state()
	# StringName keys are not JSON-safe; convert.
	var objs := {}
	for k in objective_state.keys():
		objs[String(k)] = objective_state[k]
	state["objectives"] = objs
	SaveSystem.store_checkpoint(mission.id, state)
	mission_message.emit("Checkpoint saved", "checkpoint")


func restore_checkpoint(state: Dictionary) -> void:
	var objs = state.get("objectives", {})
	if typeof(objs) == TYPE_DICTIONARY:
		for k in objs.keys():
			var id := StringName(k)
			if objective_state.has(id) and typeof(objs[k]) == TYPE_DICTIONARY:
				objective_state[id]["done"] = bool(objs[k].get("done", false))
				objective_state[id]["count"] = int(objs[k].get("count", 0))
				objective_state[id]["revealed"] = bool(objs[k].get("revealed", true))
				if objs[k].get("failed", false):
					objective_state[id]["failed"] = true
	elapsed = float(state.get("elapsed", 0.0))
	var st = state.get("stats", {})
	if typeof(st) == TYPE_DICTIONARY:
		kills = int(st.get("kills", 0))
		headshots = int(st.get("headshots", 0))
		detections = int(st.get("detections", 0))
		alarms = int(st.get("alarms", 0))
		deaths = int(st.get("deaths", 0))
		intel.clear()
		for i in st.get("intel", []):
			intel.append(str(i))
	var dead = state.get("enemies_dead", [])
	if typeof(dead) == TYPE_ARRAY:
		for p in dead:
			var e := level_root.get_node_or_null(NodePath(str(p))) as Enemy
			if e:
				e.set_dead_silent()
	var objects = state.get("objects", {})
	if typeof(objects) == TYPE_DICTIONARY:
		for p in objects.keys():
			var n := level_root.get_node_or_null(NodePath(str(p)))
			if n and n.has_method("apply_save_state") and typeof(objects[p]) == TYPE_DICTIONARY:
				n.apply_save_state(objects[p])
	var alarm := AlarmSystem.find(self)
	if alarm and bool(state.get("alarm_offline", false)):
		alarm.set_offline(true)
	if level_root.has_method("apply_level_state") and typeof(state.get("level")) == TYPE_DICTIONARY:
		level_root.apply_level_state(state["level"])
	var ps = state.get("player", {})
	if typeof(ps) == TYPE_DICTIONARY:
		player.apply_save_state(ps)
	objectives_changed.emit()
	mission_message.emit("Resumed from checkpoint", "checkpoint")


# --------------------------------------------------------------------------- end states

func _on_player_died() -> void:
	if finished:
		return
	failed = true
	deaths += 1
	var cp := SaveSystem.get_checkpoint()
	if not cp.is_empty() and str(cp.get("mission", "")) == mission.id:
		# Persist the death count into the checkpoint for the results screen.
		var s: Dictionary = cp["state"]
		if typeof(s.get("stats")) == TYPE_DICTIONARY:
			s["stats"]["deaths"] = int(s["stats"].get("deaths", 0)) + 1
			SaveSystem.store_checkpoint(mission.id, s)
	AudioManager.play_music(&"failure", 1.0)
	player_died.emit()


## Called by ExtractionZone. Returns false (with a message) when objectives remain.
func try_extract(extraction_id: StringName) -> bool:
	if finished or failed:
		return false
	if not all_main_done(extraction_id):
		var cur := current_objective()
		mission_message.emit("Extraction unavailable — %s" % (cur.text if cur else "objectives incomplete"), "warning")
		return false
	complete_objective(extraction_id, true)
	finish()
	return true


func finish() -> void:
	if finished:
		return
	# Last chance for level scripts to resolve end-of-mission optional objectives.
	before_finish.emit()
	finished = true
	var results := compute_results()
	mission_finished.emit(results)
	AudioManager.play_music(&"victory", 1.0)
	Game.mission_completed(results)


func compute_results() -> Dictionary:
	var optional_total := 0
	var optional_done := 0
	var objective_rows := []
	for o in mission.objectives:
		if o.optional:
			optional_total += 1
			if is_done(o.id):
				optional_done += 1
		objective_rows.append({"text": o.text, "optional": o.optional, "done": is_done(o.id), "failed": is_failed(o.id)})
	var accuracy := 0.0
	if player and player.weapons.shots_fired > 0:
		accuracy = float(player.weapons.shots_hit) / player.weapons.shots_fired
	var score := 1000
	score += optional_done * 250
	score -= detections * 120
	score -= alarms * 150
	score -= deaths * 100
	score -= kills * 15
	score += 300 if detections == 0 else 0
	var par := mission.par_time
	if elapsed < par:
		score += int(200.0 * (1.0 - elapsed / par))
	score = maxi(0, score)
	var grade := "D"
	if score >= 1700:
		grade = "S"
	elif score >= 1350:
		grade = "A"
	elif score >= 1000:
		grade = "B"
	elif score >= 650:
		grade = "C"
	var style := "Ghost" if detections == 0 and kills == 0 else ("Silent Professional" if detections == 0 else ("Tactical" if alarms == 0 else "Loud"))
	return {
		"mission_id": mission.id, "title": mission.title, "time": elapsed, "kills": kills, "headshots": headshots,
		"detections": detections, "alarms": alarms, "deaths": deaths, "accuracy": accuracy,
		"gadget_uses": player.gadgets.uses if player else 0,
		"optional_done": optional_done, "optional_total": optional_total, "objectives": objective_rows,
		"intel": intel.size(), "score": score, "grade": grade, "style": style,
	}
