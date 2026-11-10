class_name HidingSpot
extends Interactable
## Equipment locker the player can hide in. Hidden players are invisible to vision
## unless an enemy is already in combat and watched them enter (then they check it).

var occupant: Player = null
var _door: MeshInstance3D
var _exit_offset := Vector3(0, 0, -0.9)


func _ready() -> void:
	super()
	add_to_group("hiding_spot")
	prompt = "Hide in locker"
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.3, 0.27)
	mat.metallic = 0.5
	mat.roughness = 0.45
	var shell := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.75, 2.0, 0.65)
	shell.mesh = sm
	shell.material_override = mat
	shell.position = Vector3(0, 1.0, 0)
	add_child(shell)
	_door = MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(0.7, 1.9, 0.04)
	_door.mesh = dm
	var dmat := mat.duplicate() as StandardMaterial3D
	dmat.albedo_color = Color(0.3, 0.35, 0.32)
	_door.material_override = dmat
	_door.position = Vector3(0, 1.0, -0.34)
	add_child(_door)
	for i in 4:
		var slit := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.4, 0.02, 0.02)
		slit.mesh = b
		var sm2 := StandardMaterial3D.new()
		sm2.albedo_color = Color(0.02, 0.02, 0.02)
		slit.material_override = sm2
		slit.position = Vector3(0, 1.55 + i * 0.06, -0.365)
		add_child(slit)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.75, 2.0, 0.65)
	cs.shape = bs
	cs.position = Vector3(0, 1.0, 0)
	body.add_child(cs)
	body.set_meta("surface", "metal")
	add_child(body)


func get_interact_position() -> Vector3:
	return global_position + Vector3(0, 1.1, 0) + global_transform.basis * Vector3(0, 0, -0.4)


func get_prompt(_by: Node) -> String:
	return "Exit locker" if occupant else prompt


func can_interact(by: Node) -> bool:
	return enabled and (occupant == null or occupant == by)


func _on_interact(by: Node) -> void:
	_used_once = false
	if occupant == null and by is Player:
		enter_spot(by)


func enter_spot(p: Player) -> void:
	# Seen entering by a fighting enemy? Then hiding fails.
	occupant = p
	p.hidden_in = self
	p.visible = false
	p.set_crouch(false)
	p.velocity = Vector3.ZERO
	p.global_position = global_position + Vector3.UP * 0.05
	p.collision_layer = 0
	AudioManager.play_3d(&"locker", get_interact_position(), -4.0)
	SoundEvents.emit_sound(global_position, 4.0, SoundEvent.Type.DOOR, 0.4, p)
	for n in get_tree().get_nodes_in_group("enemy"):
		var e := n as Enemy
		if e and not e.is_dead() and e.state_name == &"combat" and e.perception.time_since_seen() < 1.0:
			e.last_known_pos = global_position + global_transform.basis * _exit_offset


func exit_spot(p: Player) -> void:
	if occupant != p:
		return
	occupant = null
	p.hidden_in = null
	p.visible = true
	p.collision_layer = 2
	p.global_position = global_position + global_transform.basis * _exit_offset
	AudioManager.play_3d(&"locker", get_interact_position(), -4.0)
	SoundEvents.emit_sound(global_position, 4.0, SoundEvent.Type.DOOR, 0.4, p)
