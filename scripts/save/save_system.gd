extends Node
## Autoload "SaveSystem" — versioned, validated campaign persistence.
##
## File: user://savegame.json   (atomic write via temp file + rename)
## Campaign progress and the in-mission checkpoint live in separate sections so a
## checkpoint can never overwrite campaign progress. Progress only changes through
## record_mission_complete().

signal progress_changed

const PATH := "user://savegame.json"
const VERSION := 2
const GRADES := ["S", "A", "B", "C", "D"]

## Last load result: "ok", "missing", "corrupt", "unsupported_version", "repaired".
var last_load_status: String = "missing"
var data: Dictionary = {}

## Overridable for tests.
var save_path: String = PATH


func _ready() -> void:
	load_game()


static func default_data() -> Dictionary:
	return {
		"version": VERSION,
		"campaign": {
			"started": false,
			"unlocked": ["m01"],
			"completed": {},
			"current": "m01",
			"campaign_complete": false,
		},
		"checkpoint": {},
		"stats": {"missions_played": 0, "total_kills": 0, "total_detections": 0},
	}


# --------------------------------------------------------------------------- load

func load_game() -> String:
	data = default_data()
	if not FileAccess.file_exists(save_path):
		last_load_status = "missing"
		return last_load_status
	var f := FileAccess.open(save_path, FileAccess.READ)
	if f == null:
		last_load_status = "corrupt"
		return last_load_status
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_backup("corrupt")
		last_load_status = "corrupt"
		return last_load_status
	var v := int(parsed.get("version", -1)) if parsed.get("version") is float or parsed.get("version") is int else -1
	if v < 1 or v > VERSION:
		_backup("unsupported")
		last_load_status = "unsupported_version"
		return last_load_status
	if v == 1:
		parsed = _migrate_v1(parsed)
	var repaired := _validate_into(parsed)
	last_load_status = "repaired" if repaired else "ok"
	return last_load_status


## Copies a valid subset of `src` into `data`. Returns true if anything was discarded.
func _validate_into(src: Dictionary) -> bool:
	var repaired := false
	var camp = src.get("campaign")
	if typeof(camp) != TYPE_DICTIONARY:
		return true
	var c: Dictionary = data["campaign"]
	c["started"] = bool(camp.get("started", false))
	# unlocked
	var unlocked: Array = []
	if typeof(camp.get("unlocked")) == TYPE_ARRAY:
		for id in camp["unlocked"]:
			if typeof(id) == TYPE_STRING and Campaign.is_valid(id) and not unlocked.has(id):
				unlocked.append(id)
			else:
				repaired = true
	if not unlocked.has("m01"):
		unlocked.push_front("m01")
	c["unlocked"] = unlocked
	# completed
	var completed := {}
	if typeof(camp.get("completed")) == TYPE_DICTIONARY:
		for id in camp["completed"].keys():
			var rec = camp["completed"][id]
			if Campaign.is_valid(str(id)) and typeof(rec) == TYPE_DICTIONARY:
				completed[str(id)] = {
					"grade": str(rec.get("grade", "D")) if str(rec.get("grade", "D")) in GRADES else "D",
					"best_time": maxf(0.0, float(rec.get("best_time", 0.0))),
					"score": maxi(0, int(rec.get("score", 0))),
					"optional_done": maxi(0, int(rec.get("optional_done", 0))),
				}
			else:
				repaired = true
	c["completed"] = completed
	# A completed mission's successor must be unlocked.
	for id in completed.keys():
		var nxt := Campaign.next_of(id)
		if nxt != "" and not unlocked.has(nxt):
			unlocked.append(nxt)
			repaired = true
	var cur := str(camp.get("current", "m01"))
	if not Campaign.is_valid(cur) or not unlocked.has(cur):
		cur = unlocked[unlocked.size() - 1]
		repaired = true
	c["current"] = cur
	c["campaign_complete"] = completed.has("m03")
	# checkpoint
	var cp = src.get("checkpoint", {})
	if typeof(cp) == TYPE_DICTIONARY and not cp.is_empty():
		if Campaign.is_valid(str(cp.get("mission", ""))) and unlocked.has(str(cp.get("mission", ""))) and typeof(cp.get("state")) == TYPE_DICTIONARY:
			data["checkpoint"] = {"mission": str(cp["mission"]), "state": cp["state"]}
		else:
			repaired = true
	var st = src.get("stats", {})
	if typeof(st) == TYPE_DICTIONARY:
		for k in data["stats"].keys():
			data["stats"][k] = maxi(0, int(st.get(k, 0)))
	return repaired


func _migrate_v1(old: Dictionary) -> Dictionary:
	# v1 (prototype) stored {"version":1,"unlocked":[...],"completed":[...]}.
	var out := default_data()
	out["campaign"]["started"] = true
	if typeof(old.get("unlocked")) == TYPE_ARRAY:
		out["campaign"]["unlocked"] = old["unlocked"]
	if typeof(old.get("completed")) == TYPE_ARRAY:
		var comp := {}
		for id in old["completed"]:
			comp[str(id)] = {"grade": "C", "best_time": 0.0, "score": 0, "optional_done": 0}
		out["campaign"]["completed"] = comp
	return out


func _backup(tag: String) -> void:
	var dst := save_path + "." + tag + ".bak"
	var d := DirAccess.open(save_path.get_base_dir())
	if d:
		d.copy(save_path, dst)
	push_warning("SaveSystem: save file was %s — backed up to %s and reset" % [tag, dst])


# --------------------------------------------------------------------------- save

func save_game() -> bool:
	data["version"] = VERSION
	var tmp := save_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("SaveSystem: cannot write %s" % tmp)
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	var d := DirAccess.open(save_path.get_base_dir())
	if d == null:
		return false
	if FileAccess.file_exists(save_path):
		d.remove(save_path)
	var err := d.rename(tmp, save_path)
	if err != OK:
		push_error("SaveSystem: rename failed %s" % error_string(err))
		return false
	return true


func delete_save() -> void:
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)
	data = default_data()
	progress_changed.emit()


# --------------------------------------------------------------------------- campaign API

func has_progress() -> bool:
	return bool(data["campaign"]["started"])


func new_campaign() -> void:
	data = default_data()
	data["campaign"]["started"] = true
	save_game()
	progress_changed.emit()


func is_unlocked(id: String) -> bool:
	return data["campaign"]["unlocked"].has(id)


func is_completed(id: String) -> bool:
	return data["campaign"]["completed"].has(id)


func get_record(id: String) -> Dictionary:
	return data["campaign"]["completed"].get(id, {})


func get_current_mission() -> String:
	return data["campaign"]["current"]


func is_campaign_complete() -> bool:
	return bool(data["campaign"]["campaign_complete"])


## Called only from the results flow after a successful extraction.
func record_mission_complete(id: String, grade: String, time_s: float, score: int, optional_done: int, kills: int, detections: int) -> void:
	if not Campaign.is_valid(id):
		push_error("SaveSystem: unknown mission %s" % id)
		return
	var c: Dictionary = data["campaign"]
	c["started"] = true
	var prev: Dictionary = c["completed"].get(id, {})
	var rec := {
		"grade": grade,
		"best_time": time_s,
		"score": score,
		"optional_done": optional_done,
	}
	if not prev.is_empty():
		rec["best_time"] = minf(float(prev["best_time"]), time_s) if float(prev["best_time"]) > 0.0 else time_s
		rec["score"] = maxi(int(prev["score"]), score)
		rec["optional_done"] = maxi(int(prev["optional_done"]), optional_done)
		if GRADES.find(str(prev["grade"])) < GRADES.find(grade):
			rec["grade"] = prev["grade"]
	c["completed"][id] = rec
	var nxt := Campaign.next_of(id)
	if nxt != "":
		if not c["unlocked"].has(nxt):
			c["unlocked"].append(nxt)
		c["current"] = nxt
	else:
		c["campaign_complete"] = true
	data["stats"]["missions_played"] += 1
	data["stats"]["total_kills"] += kills
	data["stats"]["total_detections"] += detections
	clear_checkpoint(false)
	save_game()
	progress_changed.emit()


func set_current(id: String) -> void:
	if is_unlocked(id):
		data["campaign"]["current"] = id
		data["campaign"]["started"] = true
		save_game()


# --------------------------------------------------------------------------- checkpoints

func store_checkpoint(mission_id: String, state: Dictionary) -> void:
	if not is_unlocked(mission_id):
		return
	data["checkpoint"] = {"mission": mission_id, "state": state}
	data["campaign"]["started"] = true
	save_game()


func get_checkpoint() -> Dictionary:
	return data.get("checkpoint", {})


func has_checkpoint() -> bool:
	return not get_checkpoint().is_empty()


func clear_checkpoint(write: bool = true) -> void:
	data["checkpoint"] = {}
	if write:
		save_game()
