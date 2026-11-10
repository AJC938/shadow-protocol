class_name Campaign
extends RefCounted
## Static registry of the campaign's missions (single source of truth for ids/order).

const MISSION_IDS: Array[String] = ["m01", "m02", "m03"]
const MISSION_RESOURCES := {
	"m01": "res://resources/missions/m01_silent_entry.tres",
	"m02": "res://resources/missions/m02_black_signal.tres",
	"m03": "res://resources/missions/m03_final_extraction.tres",
}


static func is_valid(id: String) -> bool:
	return MISSION_RESOURCES.has(id)


static func get_mission(id: String) -> MissionData:
	if not is_valid(id):
		return null
	return load(MISSION_RESOURCES[id]) as MissionData


static func next_of(id: String) -> String:
	var i := MISSION_IDS.find(id)
	if i < 0 or i + 1 >= MISSION_IDS.size():
		return ""
	return MISSION_IDS[i + 1]


static func index_of(id: String) -> int:
	return MISSION_IDS.find(id)
