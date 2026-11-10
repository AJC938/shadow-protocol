class_name SecurityCamera
extends Node3D
## Sweeping surveillance camera with its own vision cone and suspicion meter.
## Full detection raises the alarm and reports the position to nearby guards.
## Can be disrupted (temporary), disabled through a console (network), or shot.

signal detected_player(position: Vector3)
signal state_changed(cam: SecurityCamera)

const VISION_MASK := 1 | 16
const MODEL := "res://assets/models/polyhaven/security_camera_01/security_camera_01_1k.gltf"

@export var network: String = "main"
@export var sweep_angle: float = 70.0
@export var sweep_speed: float = 14.0
@export var tilt: float = -28.0
@export var view_range: float = 17.0
@export var fov_degrees: float = 50.0
@export var detection_rate: float = 55.0

var disabled: bool = false       # permanently (console / destroyed)
var destroyed: bool = false
var suspicion: float = 0.0
var _disrupted: float = 0.0
var _sweep_t: float = 0.0
var _hold: float = 0.0
var _head: Node3D
var _cone: SpotLight3D
var _led: OmniLight3D
var _cone_mesh: MeshInstance3D
var _cone_mat: StandardMaterial3D
var _player: Node3D
var _check_t: float = 0.0
var _seeing: bool = false
var _tag_left: float = 0.0
var _body: StaticBody3D


func _ready() -> void:
	add_to_group("security_camera")
	add_to_group("persistent")
	add_to_group("security_device")
	add_to_group("electronic")
	_sweep_t = randf() * 10.0
	# Mount + head
	_head = Node3D.new()
	_head.name = "Head"
	add_child(_head)
	var model_ok := false
	if ResourceLoader.exists(MODEL):
		var ps := load(MODEL) as PackedScene
		if ps:
			var m := ps.instantiate() as Node3D
			m.rotation_degrees = Vector3(0, 180, 0)
			m.scale = Vector3.ONE * 1.3
			_head.add_child(m)
			model_ok = true
	if not model_ok:
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.16, 0.14, 0.34)
		mi.mesh = b
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.75, 0.76, 0.74)
		mi.material_override = mat
		_head.add_child(mi)
	# Small collider so it can be shot.
	_body = StaticBody3D.new()
	_body.collision_layer = 1
	_body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.22, 0.2, 0.36)
	cs.shape = bs
	_body.add_child(cs)
	_body.set_script(load("res://scripts/security/damage_relay.gd"))
	_body.set("target", self)
	_head.add_child(_body)
	_cone = SpotLight3D.new()
	_cone.spot_range = view_range
	_cone.spot_angle = fov_degrees * 0.5
	_cone.light_energy = 0.8
	_cone.shadow_enabled = false
	_cone.light_volumetric_fog_energy = 2.0
	_cone.position = Vector3(0, 0, -0.2)
	_head.add_child(_cone)
	_led = OmniLight3D.new()
	_led.omni_range = 0.5
	_led.light_energy = 1.5
	_led.position = Vector3(0, 0.08, -0.15)
	_head.add_child(_led)
	# Visible translucent vision cone (readable detection feedback).
	_cone_mesh = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	var length := view_range * 0.4
	cm.top_radius = 0.02
	cm.bottom_radius = tan(deg_to_rad(fov_degrees * 0.5)) * length
	cm.height = length
	cm.radial_segments = 20
	cm.cap_bottom = false
	cm.cap_top = false
	_cone_mesh.mesh = cm
	_cone_mat = StandardMaterial3D.new()
	_cone_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cone_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_cone_mat.cull_mode = BaseMaterial3D.CULL_BACK
	_cone_mat.albedo_color = Color(0.4, 0.7, 1.0, 0.025)
	_cone_mesh.material_override = _cone_mat
	_cone_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cone_mesh.rotation_degrees = Vector3(90, 0, 0)
	_cone_mesh.position = Vector3(0, 0, -length * 0.5 - 0.2)
	_head.add_child(_cone_mesh)
	_apply_visual_state()


func is_operational() -> bool:
	return not disabled and not destroyed and _disrupted <= 0.0


func disrupt(duration: float) -> void:
	if disabled:
		return
	_disrupted = maxf(_disrupted, duration)
	suspicion = 0.0
	_apply_visual_state()
	state_changed.emit(self)


func set_disabled(d: bool) -> void:
	disabled = d
	suspicion = 0.0
	_apply_visual_state()
	state_changed.emit(self)


func take_damage(_info: DamageInfo) -> void:
	if destroyed:
		return
	destroyed = true
	suspicion = 0.0
	CombatFX.impact(self, _head.global_position, Vector3.UP, false)
	AudioManager.play_3d(&"camera_break", _head.global_position, 0.0)
	SoundEvents.emit_sound(_head.global_position, 9.0, SoundEvent.Type.IMPACT, 0.8, null)
	_head.rotation_degrees.x = -60.0
	_apply_visual_state()
	state_changed.emit(self)


func is_dead() -> bool:
	return destroyed


func tag(duration: float) -> void:
	_tag_left = maxf(_tag_left, duration)
	add_to_group("tagged")


func is_tagged() -> bool:
	return _tag_left > 0.0


func _apply_visual_state() -> void:
	if _cone == null:
		return
	var op := is_operational()
	_cone.visible = op
	_cone_mesh.visible = op
	_led.light_color = Color(0.2, 1.0, 0.3) if op else Color(0.3, 0.3, 0.3)
	_led.light_energy = 1.5 if op else 0.0


func _physics_process(delta: float) -> void:
	if _tag_left > 0.0:
		_tag_left -= delta
		if _tag_left <= 0.0:
			remove_from_group("tagged")
	if _disrupted > 0.0:
		_disrupted -= delta
		# Flicker while jammed.
		_led.light_energy = 1.0 if fmod(_disrupted, 0.5) < 0.1 else 0.0
		_led.light_color = Color(0.3, 0.5, 1.0)
		if _disrupted <= 0.0:
			_apply_visual_state()
		return
	if not is_operational():
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	# Sweep (pauses while tracking).
	if not _seeing:
		_sweep_t += delta
		var yaw := sin(_sweep_t * deg_to_rad(sweep_speed) * 2.0) * sweep_angle * 0.5
		_head.rotation_degrees = Vector3(tilt, yaw, 0)
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = 0.1
		_seeing = _can_see_player()
	if _seeing:
		var d := _head.global_position.distance_to(_player.global_position)
		var vis: float = _player.get_visibility() if _player.has_method("get_visibility") else 1.0
		var zone := 1.5 if _player.get_meta("restricted", false) else 1.0
		var dist_factor := clampf(1.2 - d / view_range, 0.25, 1.2)
		suspicion = minf(100.0, suspicion + detection_rate * vis * dist_factor * zone * delta)
		# Track the target.
		var to := _player.global_position + Vector3.UP - _head.global_position
		var local := global_transform.basis.inverse() * to
		var yaw_t := rad_to_deg(atan2(-local.x, -local.z))
		_head.rotation_degrees.y = lerpf(_head.rotation_degrees.y, clampf(yaw_t, -sweep_angle * 0.7, sweep_angle * 0.7), delta * 3.0)
		if suspicion >= 100.0:
			_trigger()
	else:
		suspicion = maxf(0.0, suspicion - 12.0 * delta)
	var c := Color(0.4, 0.7, 1.0).lerp(Color(1.0, 0.55, 0.1), clampf(suspicion / 60.0, 0.0, 1.0))
	if suspicion >= 99.0:
		c = Color(1.0, 0.15, 0.1)
	_cone.light_color = c
	_cone_mat.albedo_color = Color(c.r, c.g, c.b, 0.022 + suspicion / 100.0 * 0.06)
	_led.light_color = c


func _can_see_player() -> bool:
	if _player == null or (_player.has_method("is_dead") and _player.is_dead()):
		return false
	if _player.has_method("is_hidden") and _player.is_hidden():
		return false
	var eye := _head.global_position
	var fwd := -_head.global_transform.basis.z
	var pts: Array = _player.get_vision_points() if _player.has_method("get_vision_points") else [_player.global_position + Vector3.UP]
	var space := get_world_3d().direct_space_state
	for p in pts:
		var to: Vector3 = p - eye
		if to.length() > view_range:
			continue
		if rad_to_deg(fwd.angle_to(to.normalized())) > fov_degrees * 0.5:
			continue
		var q := PhysicsRayQueryParameters3D.create(eye, p, VISION_MASK)
		q.exclude = [_body.get_rid()]
		if space.intersect_ray(q).is_empty():
			return true
	return false


func _trigger() -> void:
	_hold += 1.0
	if _hold > 1.0:
		# Already reported; keep the alarm topped up while still seeing the player.
		var alarm := AlarmSystem.find(self)
		if alarm and alarm.active:
			alarm.raise_alarm(_player.global_position, "camera")
		return
	var pos := _player.global_position
	detected_player.emit(pos)
	AudioManager.play_3d(&"camera_alert", _head.global_position, 0.0)
	var alarm := AlarmSystem.find(self)
	if alarm:
		alarm.raise_alarm(pos, "camera")
	# Nearby guards are radioed even if the alarm network is offline.
	for n in get_tree().get_nodes_in_group("enemy"):
		var e := n as Enemy
		if e and not e.is_dead() and e.global_position.distance_to(global_position) < 30.0:
			e.receive_alert(pos)
	get_tree().create_timer(8.0).timeout.connect(func(): _hold = 0.0)


func get_save_state() -> Dictionary:
	return {"disabled": disabled, "destroyed": destroyed}


func apply_save_state(s: Dictionary) -> void:
	disabled = bool(s.get("disabled", false))
	destroyed = bool(s.get("destroyed", false))
	if destroyed:
		_head.rotation_degrees.x = -60.0
	_apply_visual_state()
