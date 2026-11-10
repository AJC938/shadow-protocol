class_name CameraRig
extends Node3D
## Over-the-shoulder third-person camera with collision, smoothing, aim zoom,
## swappable shoulder, recoil and shake.

const HEIGHT_STAND := 1.62
const HEIGHT_CROUCH := 1.15
const ARM_LENGTH := 3.0
const ARM_LENGTH_AIM := 1.45
const SHOULDER := 0.62
const SHOULDER_AIM := 0.5
const PITCH_MIN := -70.0
const PITCH_MAX := 55.0
const COLLISION_MASK := 1 | 16   # world + doors

var target: Node3D
var yaw: float = 0.0
var pitch: float = -8.0
var shoulder_side: float = 1.0
var aiming: bool = false
var crouching: bool = false
## While true, the rig ignores look input (recon camera / death cam).
var suspended: bool = false

var yaw_node: Node3D
var pitch_node: Node3D
var arm: SpringArm3D
var camera: Camera3D
var _offset_x: float = SHOULDER
var _height: float = HEIGHT_STAND
var _recoil: Vector2 = Vector2.ZERO
var _shake: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	top_level = true
	yaw_node = Node3D.new()
	yaw_node.name = "Yaw"
	add_child(yaw_node)
	pitch_node = Node3D.new()
	pitch_node.name = "Pitch"
	yaw_node.add_child(pitch_node)
	arm = SpringArm3D.new()
	arm.name = "Arm"
	arm.spring_length = ARM_LENGTH
	arm.margin = 0.15
	arm.collision_mask = COLLISION_MASK
	var s := SphereShape3D.new()
	s.radius = 0.22
	arm.shape = s
	pitch_node.add_child(arm)
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.fov = Settings.fov
	camera.near = 0.05
	camera.far = 400.0
	arm.add_child(camera)
	camera.current = true
	Settings.changed.connect(func(): camera.fov = Settings.fov)


func attach(t: Node3D) -> void:
	target = t
	arm.add_excluded_object(t.get_rid())
	global_position = t.global_position + Vector3.UP * HEIGHT_STAND
	yaw = rad_to_deg(t.global_rotation.y)


func swap_shoulder() -> void:
	shoulder_side = -shoulder_side


func add_recoil(pitch_deg: float, yaw_deg: float) -> void:
	_recoil += Vector2(yaw_deg, pitch_deg)


func add_shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func get_forward() -> Vector3:
	return -camera.global_transform.basis.z


func get_yaw_basis() -> Basis:
	return Basis(Vector3.UP, deg_to_rad(yaw))


func get_aim_ray_origin() -> Vector3:
	return camera.global_position


func _physics_process(delta: float) -> void:
	if target == null:
		return
	if not suspended:
		var look := InputRouter.consume_look(delta)
		yaw -= look.x
		pitch = clampf(pitch - look.y, PITCH_MIN, PITCH_MAX)
	# recoil applied then recovered
	if _recoil.length() > 0.001:
		var step := _recoil * minf(1.0, delta * 18.0)
		yaw -= step.x
		pitch = clampf(pitch + step.y, PITCH_MIN, PITCH_MAX)
		_recoil -= step
	var want_h := HEIGHT_CROUCH if crouching else HEIGHT_STAND
	_height = lerpf(_height, want_h, clampf(delta * 8.0, 0.0, 1.0))
	var follow := target.global_position + Vector3.UP * _height
	global_position = global_position.lerp(follow, clampf(delta * 18.0, 0.0, 1.0))
	yaw_node.rotation_degrees.y = yaw
	pitch_node.rotation_degrees.x = pitch
	# Shoulder offset clamped by a side ray so it never pokes into walls.
	var want_offset := (SHOULDER_AIM if aiming else SHOULDER) * shoulder_side
	var side_dir := yaw_node.global_transform.basis.x * signf(want_offset)
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position, global_position + side_dir * (absf(want_offset) + 0.3), COLLISION_MASK)
	q.exclude = [target.get_rid()]
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		var free := maxf(0.0, global_position.distance_to(hit.position) - 0.3)
		want_offset = signf(want_offset) * minf(absf(want_offset), free)
	_offset_x = lerpf(_offset_x, want_offset, clampf(delta * 10.0, 0.0, 1.0))
	arm.position = Vector3(_offset_x, 0, 0)
	arm.spring_length = lerpf(arm.spring_length, ARM_LENGTH_AIM if aiming else ARM_LENGTH, clampf(delta * 10.0, 0.0, 1.0))
	var want_fov := Settings.fov * (0.72 if aiming else 1.0)
	camera.fov = lerpf(camera.fov, want_fov, clampf(delta * 10.0, 0.0, 1.0))
	# shake
	if _shake > 0.001:
		camera.h_offset = _rng.randf_range(-1, 1) * _shake * 0.08
		camera.v_offset = _rng.randf_range(-1, 1) * _shake * 0.08
		_shake = move_toward(_shake, 0.0, delta * 3.0)
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
