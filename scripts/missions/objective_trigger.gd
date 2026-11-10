class_name ObjectiveTrigger
extends Area3D
## Completes (or progresses) an objective when the player enters the volume.
## Also used for checkpoints, story radio lines and extraction.

signal triggered

enum Mode { COMPLETE, PROGRESS, EXTRACT, CHECKPOINT, MESSAGE_ONLY }

@export var size: Vector3 = Vector3(4, 3, 4)
@export var objective_id: StringName = &""
@export var mode: Mode = Mode.COMPLETE
## Only fires when this objective is already done (sequencing), if set.
@export var requires: StringName = &""
@export var voice: StringName = &""
@export var speaker: String = "ORACLE"
@export_multiline var message: String = ""
@export var show_marker: bool = false

var fired: bool = false
var _marker: Node3D


func _ready() -> void:
	add_to_group("persistent")
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = Vector3(0, size.y * 0.5, 0)
	add_child(cs)
	body_entered.connect(_on_body_entered)
	if mode == Mode.EXTRACT or show_marker:
		_build_marker()


func _build_marker() -> void:
	_marker = Node3D.new()
	add_child(_marker)
	var ring := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = minf(size.x, size.z) * 0.42
	t.outer_radius = minf(size.x, size.z) * 0.47
	t.rings = 48
	ring.mesh = t
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.3, 1.0, 0.55, 0.6)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ring.material_override = m
	ring.position.y = 0.05
	_marker.add_child(ring)
	var beam := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.05
	c.bottom_radius = 0.25
	c.height = 6.0
	beam.mesh = c
	var bm := m.duplicate() as StandardMaterial3D
	bm.albedo_color = Color(0.3, 1.0, 0.55, 0.12)
	beam.material_override = bm
	beam.position.y = 3.0
	_marker.add_child(beam)
	var l := OmniLight3D.new()
	l.light_color = Color(0.3, 1.0, 0.55)
	l.omni_range = 4.0
	l.light_energy = 0.8
	l.position.y = 0.5
	_marker.add_child(l)


func _on_body_entered(b: Node3D) -> void:
	if fired or not b.is_in_group("player"):
		return
	var mc := MissionController.find(self)
	if mc == null:
		return
	if requires != &"" and not mc.is_done(requires):
		return
	match mode:
		Mode.COMPLETE:
			if objective_id != &"":
				mc.complete_objective(objective_id)
			fired = true
		Mode.PROGRESS:
			mc.progress_objective(objective_id)
			fired = true
		Mode.EXTRACT:
			if not mc.try_extract(objective_id):
				return
			fired = true
		Mode.CHECKPOINT:
			fired = true
			mc.save_checkpoint()
		Mode.MESSAGE_ONLY:
			fired = true
	if fired and (message != "" or voice != &""):
		AudioManager.play_voice(voice, speaker, message)
	if fired:
		triggered.emit()


func _process(delta: float) -> void:
	if _marker:
		_marker.rotation.y += delta * 0.5


func get_save_state() -> Dictionary:
	return {"fired": fired}


func apply_save_state(s: Dictionary) -> void:
	fired = bool(s.get("fired", false)) and mode != Mode.EXTRACT
