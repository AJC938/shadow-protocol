class_name Pickup
extends Interactable
## Collectible item: ammo crate, med kit, keycard, intel / data shard.

enum Kind { AMMO, MEDKIT, KEYCARD, INTEL }

@export var kind: Kind = Kind.AMMO
@export var item_id: String = ""
@export var display_name: String = ""
@export var amount: float = 0.35
@export var model_path: String = ""

var collected: bool = false
var _visual: Node3D
var _glow: OmniLight3D
var _t: float = 0.0


func _ready() -> void:
	super()
	add_to_group("pickup")
	one_shot = true
	interact_distance = 2.0
	match kind:
		Kind.AMMO:
			prompt = "Take ammunition"
			if model_path == "":
				model_path = "res://assets/models/polyhaven/ammo_box/ammo_box_1k.gltf"
		Kind.MEDKIT:
			prompt = "Use med kit"
		Kind.KEYCARD:
			prompt = "Take %s" % (display_name if display_name != "" else "keycard")
		Kind.INTEL:
			prompt = "Collect %s" % (display_name if display_name != "" else "intel")
			hold_time = maxf(hold_time, 1.0)
			if model_path == "":
				model_path = "res://assets/models/polyhaven/classic_laptop/classic_laptop_1k.gltf"
	_build_visual()


func _build_visual() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	var loaded := false
	if model_path != "" and ResourceLoader.exists(model_path):
		var ps := load(model_path) as PackedScene
		if ps:
			_visual.add_child(ps.instantiate())
			loaded = true
	if not loaded:
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		var m := StandardMaterial3D.new()
		match kind:
			Kind.MEDKIT:
				b.size = Vector3(0.35, 0.18, 0.25)
				m.albedo_color = Color(0.85, 0.85, 0.82)
			Kind.KEYCARD:
				b.size = Vector3(0.09, 0.01, 0.055)
				m.albedo_color = Color(0.9, 0.65, 0.15)
				m.emission_enabled = true
				m.emission = Color(0.9, 0.6, 0.1)
			_:
				b.size = Vector3(0.3, 0.2, 0.25)
				m.albedo_color = Color(0.25, 0.28, 0.2)
		mi.mesh = b
		mi.material_override = m
		_visual.add_child(mi)
		if kind == Kind.MEDKIT:
			var cross := MeshInstance3D.new()
			var cb := BoxMesh.new()
			cb.size = Vector3(0.14, 0.02, 0.04)
			cross.mesh = cb
			var cm := StandardMaterial3D.new()
			cm.albedo_color = Color(0.75, 0.1, 0.1)
			cross.material_override = cm
			cross.position.y = 0.1
			_visual.add_child(cross)
	_glow = OmniLight3D.new()
	_glow.omni_range = 1.2
	_glow.light_energy = 0.6
	_glow.light_color = Color(1.0, 0.75, 0.3) if kind != Kind.INTEL else Color(0.3, 0.8, 1.0)
	_glow.position = Vector3.UP * 0.4
	add_child(_glow)


func get_interact_position() -> Vector3:
	return global_position + Vector3.UP * 0.2


func can_interact(by: Node) -> bool:
	if collected or not enabled:
		return false
	if kind == Kind.MEDKIT and by is Player and (by as Player).health.current >= (by as Player).health.max_health:
		return false
	return true


func get_prompt(by: Node) -> String:
	if kind == Kind.AMMO and by is Player:
		return prompt
	return prompt


func _on_interact(by: Node) -> void:
	var p := by as Player
	if p == null:
		return
	match kind:
		Kind.AMMO:
			if not p.weapons.refill_all(amount):
				_used_once = false
				return
			AudioManager.play_3d(&"pickup_ammo", global_position, -4.0)
		Kind.MEDKIT:
			p.health.heal(p.health.max_health * amount)
			AudioManager.play_3d(&"pickup_med", global_position, -4.0)
		Kind.KEYCARD:
			p.add_keycard(item_id)
			AudioManager.play_3d(&"pickup_key", global_position, -4.0)
		Kind.INTEL:
			AudioManager.play_3d(&"pickup_intel", global_position, -2.0)
			var mc := MissionController.find(self)
			if mc:
				mc.on_intel_collected(item_id, display_name)
	collected = true
	visible = false


func _process(delta: float) -> void:
	if collected or _visual == null:
		return
	_t += delta
	if kind == Kind.KEYCARD:
		_visual.rotation.y += delta * 1.5
		_visual.position.y = 0.05 * sin(_t * 2.0)
	_glow.light_energy = 0.45 + 0.2 * sin(_t * 3.0)


func get_save_state() -> Dictionary:
	return {"collected": collected}


func apply_save_state(s: Dictionary) -> void:
	collected = bool(s.get("collected", false))
	_used_once = collected
	visible = not collected
