class_name Door
extends Interactable
## Sliding security door. Blocks movement, vision and bullets when closed.
## Locks: none / keycard / console (unlocked remotely by a SecurityConsole).
## Enemies with access open it automatically when they walk through.

enum Lock { NONE, KEYCARD, CONSOLE }

@export var width: float = 1.6
@export var height: float = 2.6
@export var lock: Lock = Lock.NONE
@export var keycard_id: String = ""
@export var door_id: String = ""
@export var enemy_access: bool = true
@export var start_open: bool = false
@export var material_path: String = "res://assets/textures/painted_metal_shutter/albedo.jpg"

var is_open: bool = false
var locked: bool = false
var _panel: AnimatableBody3D
var _open_amount: float = 0.0
var _sensor: Area3D
var _status_mat: StandardMaterial3D
var _auto_close: float = 0.0


func _ready() -> void:
	super()
	add_to_group("door")
	noise_radius = 0.0
	locked = lock != Lock.NONE
	_panel = AnimatableBody3D.new()
	_panel.collision_layer = 16
	_panel.collision_mask = 0
	_panel.sync_to_physics = false
	_panel.add_to_group("door")
	add_child(_panel)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(width, height, 0.12)
	cs.shape = bs
	cs.position = Vector3(0, height * 0.5, 0)
	_panel.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(width, height, 0.1)
	mi.mesh = bm
	mi.position = Vector3(0, height * 0.5, 0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.36, 0.38, 0.4)
	if ResourceLoader.exists(material_path):
		m.albedo_texture = load(material_path)
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(0.6, 0.6, 0.6)
	m.roughness = 0.55
	m.metallic = 0.5
	mi.material_override = m
	_panel.add_child(mi)
	# hazard stripe + status light on both faces
	for side in [-1.0, 1.0]:
		var stripe := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(width * 0.96, 0.12, 0.02)
		stripe.mesh = sb
		var smat := StandardMaterial3D.new()
		smat.albedo_color = Color(0.75, 0.55, 0.12)
		stripe.material_override = smat
		stripe.position = Vector3(0, 1.0, 0.06 * side)
		_panel.add_child(stripe)
	_status_mat = StandardMaterial3D.new()
	_status_mat.emission_enabled = true
	_status_mat.emission_energy_multiplier = 2.5
	for side in [-1.0, 1.0]:
		var led := MeshInstance3D.new()
		var lb := BoxMesh.new()
		lb.size = Vector3(0.18, 0.08, 0.03)
		led.mesh = lb
		led.material_override = _status_mat
		led.position = Vector3(width * 0.5 + 0.18, 1.35, 0.1 * side)
		add_child(led)
	_sensor = Area3D.new()
	_sensor.collision_layer = 0
	_sensor.collision_mask = 4
	_sensor.monitorable = false
	var ss := CollisionShape3D.new()
	var sbs := BoxShape3D.new()
	sbs.size = Vector3(width + 0.6, 2.0, 3.2)
	ss.shape = sbs
	ss.position = Vector3(0, 1.0, 0)
	_sensor.add_child(ss)
	add_child(_sensor)
	if start_open:
		is_open = true
		_open_amount = 1.0
	_apply()
	_refresh_status()


func get_interact_position() -> Vector3:
	return global_position + Vector3.UP * 1.2


func get_prompt(by: Node) -> String:
	if locked:
		if lock == Lock.KEYCARD:
			if by is Player and (by as Player).has_keycard(keycard_id):
				return "Unlock door (keycard)"
			return "Locked — keycard required"
		return "Locked — security console"
	return "Close door" if is_open else "Open door"


func can_interact(by: Node) -> bool:
	return enabled


func _on_interact(by: Node) -> void:
	_used_once = false
	if locked:
		if lock == Lock.KEYCARD and by is Player and (by as Player).has_keycard(keycard_id):
			unlock()
		else:
			AudioManager.play_3d(&"door_locked", get_interact_position(), -4.0)
			return
	set_open(not is_open)


func unlock() -> void:
	locked = false
	AudioManager.play_3d(&"door_unlock", get_interact_position(), -4.0)
	_refresh_status()


func set_open(o: bool) -> void:
	if o == is_open:
		return
	is_open = o
	AudioManager.play_3d(&"door_slide", get_interact_position(), -4.0)
	SoundEvents.emit_sound(global_position, 6.0, SoundEvent.Type.DOOR, 0.5, null)


func _physics_process(delta: float) -> void:
	# Enemies open unlocked (or accessible) doors as they approach.
	if enemy_access and not is_open:
		for b in _sensor.get_overlapping_bodies():
			if b is Enemy and not (b as Enemy).is_dead() and (b as Enemy)._moving and (not locked or lock == Lock.KEYCARD):
				is_open = true
				_auto_close = 3.0
				AudioManager.play_3d(&"door_slide", get_interact_position(), -6.0)
				break
	if _auto_close > 0.0:
		_auto_close -= delta
		var occupied := false
		for b in _sensor.get_overlapping_bodies():
			if b is Enemy and not (b as Enemy).is_dead():
				occupied = true
		if occupied:
			_auto_close = 2.0
		elif _auto_close <= 0.0:
			is_open = false
	var target := 1.0 if is_open else 0.0
	if not is_equal_approx(_open_amount, target):
		_open_amount = move_toward(_open_amount, target, delta * 1.6)
		_apply()


func _apply() -> void:
	_panel.position = Vector3(width * 0.98 * _open_amount, 0, 0)


func _refresh_status() -> void:
	var c := Color(0.85, 0.15, 0.1) if locked else Color(0.2, 0.85, 0.3)
	_status_mat.albedo_color = c
	_status_mat.emission = c


func get_save_state() -> Dictionary:
	return {"locked": locked, "open": is_open}


func apply_save_state(s: Dictionary) -> void:
	locked = bool(s.get("locked", locked))
	is_open = bool(s.get("open", is_open))
	_open_amount = 1.0 if is_open else 0.0
	_apply()
	_refresh_status()
