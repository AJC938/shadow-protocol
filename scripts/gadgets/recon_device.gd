class_name ReconDevice
extends Node3D
## Deployed recon camera: small sticky device with its own Camera3D.
## The view is limited (yaw/pitch range, 25 m tagging range, line of sight).

const YAW_LIMIT := 75.0
const PITCH_MIN := -50.0
const PITCH_MAX := 35.0
const TAG_RANGE := 25.0

var cam: Camera3D
var _yaw := 0.0
var _pitch := -10.0
var _base_basis: Basis
var _light: OmniLight3D
var _blink := 0.0
var _tag_timer := 0.0


func _ready() -> void:
	add_to_group("recon_device")
	var body := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.07
	s.height = 0.1
	body.mesh = s
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.1, 0.11, 0.12)
	m.metallic = 0.6
	m.roughness = 0.4
	body.material_override = m
	add_child(body)
	var lens := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.025
	c.bottom_radius = 0.03
	c.height = 0.05
	lens.mesh = c
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(0.2, 0.9, 0.5)
	lm.emission_enabled = true
	lm.emission = Color(0.2, 0.9, 0.5)
	lm.emission_energy_multiplier = 2.0
	lens.material_override = lm
	lens.rotation_degrees = Vector3(90, 0, 0)
	lens.position = Vector3(0, 0.02, -0.06)
	add_child(lens)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.2, 1.0, 0.5)
	_light.light_energy = 0.0
	_light.omni_range = 0.6
	add_child(_light)
	cam = Camera3D.new()
	cam.fov = 80.0
	cam.near = 0.03
	cam.position = Vector3(0, 0.06, -0.05)
	add_child(cam)


## Sticks the device to a surface and faces it toward the player's view direction.
func place(pos: Vector3, normal: Vector3, view_dir: Vector3) -> void:
	global_position = pos + normal * 0.06
	var look := view_dir
	if normal.y > 0.7:
		look.y = 0.0
	else:
		look = normal  # on walls the camera looks out of the wall
	look = look.normalized() if look.length() > 0.01 else Vector3.FORWARD
	var basis := Basis.looking_at(look, Vector3.UP)
	global_transform.basis = basis
	_base_basis = basis


func activate(on: bool) -> void:
	cam.current = on
	_light.light_energy = 0.0


func rotate_view(look: Vector2) -> void:
	_yaw = clampf(_yaw - look.x, -YAW_LIMIT, YAW_LIMIT)
	_pitch = clampf(_pitch - look.y, PITCH_MIN, PITCH_MAX)
	cam.global_transform.basis = _base_basis * Basis.from_euler(Vector3(deg_to_rad(_pitch), deg_to_rad(_yaw), 0))


## Tags enemies that are inside the camera frustum, in range and in line of sight.
func tag_visible_enemies(duration: float) -> void:
	_tag_timer -= get_process_delta_time()
	if _tag_timer > 0.0:
		return
	_tag_timer = 0.25
	var space := get_world_3d().direct_space_state
	for n in get_tree().get_nodes_in_group("enemy"):
		var e := n as Node3D
		if e == null or not e.has_method("tag") or (e.has_method("is_dead") and e.is_dead()):
			continue
		var p := e.global_position + Vector3.UP * 1.2
		if p.distance_to(cam.global_position) > TAG_RANGE or cam.is_position_behind(p):
			continue
		var sp := cam.unproject_position(p)
		var vr := get_viewport().get_visible_rect()
		if not vr.has_point(sp):
			continue
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, p, 1 | 16)
		if space.intersect_ray(q).is_empty():
			e.tag(duration)


func _process(delta: float) -> void:
	_blink += delta
	if not cam.current:
		_light.light_energy = 1.5 if fmod(_blink, 1.2) < 0.08 else 0.0
