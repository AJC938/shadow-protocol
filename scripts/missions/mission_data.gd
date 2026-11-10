class_name MissionData
extends Resource
## Data-driven mission definition used by briefing, HUD, controller, results and save.

@export var id: String = "m01"
@export var number: int = 1
@export var title: String = "Mission"
@export var codename: String = ""
@export var location: String = ""
@export_multiline var background: String = ""
@export_multiline var briefing: String = ""
@export var objectives: Array[ObjectiveData] = []
@export var weapons: Array[StringName] = [&"pistol"]
@export var gadgets: Array[StringName] = [&"scanner"]
@export_file("*.tscn") var scene_path: String = ""
@export var par_time: float = 600.0
@export var music: StringName = &"mission_tense"
@export var briefing_voice: StringName = &""
@export_multiline var debrief: String = ""
