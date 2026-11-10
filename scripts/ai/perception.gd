class_name Perception
extends Node
## Enemy senses: vision (FOV, range, occlusion, distance, light-aware visibility,
## detection accumulation) and event-based hearing. Produces a suspicion value
## (0..100) plus stimulus positions; the FSM decides what to do with them.

signal noise_heard(event: SoundEvent, estimate: Vector3, loudness: float)
signal body_seen(body: Node3D)

const VISION_MASK := 1 | 16          # world + doors (glass is see-through)
const SUSPICIOUS := 20.0
const INVESTIGATE := 50.0
const CONFIRMED := 100.0
const NEAR_DISTANCE := 3.5
const PERIPHERAL_EXTRA := 25.0
const PERIPHERAL_RANGE := 10.0
const DECAY_GRACE := 2.0
const NOISE_CAP := 90.0

var enemy: Node3D
var data: EnemyData
var player: Node3D
var suspicion: float = 0.0
var player_visible: bool = false
var visible_fraction: float = 0.0
var last_seen_position: Vector3
var last_seen_time: float = -1000.0
var current_gain: float = 0.0
## Multiplier set by the FSM (alert states see faster).
var state_multiplier: float = 1.0
## Suspicion never decays below this (set by states such as Investigate).
var floor_value: float = 0.0
var enabled: bool = true

var _vision_timer: float = 0.0
var _body_timer: float = 0.0
var _unseen_time: float = 99.0
var _rng := RandomNumberGenerator.new()


func setup(e: Node3D, d: EnemyData) -> void:
	enemy = e
	data = d
	_rng.randomize()
	_vision_timer = _rng.randf() * 0.1   # stagger enemies
	_body_timer = _rng.randf() * 0.5
	SoundEvents.sound_emitted.connect(_on_sound)


func _exit_tree() -> void:
	if SoundEvents.sound_emitted.is_connected(_on_sound):
		SoundEvents.sound_emitted.disconnect(_on_sound)


func get_eye_position() -> Vector3:
	return enemy.global_position + Vector3.UP * 1.62 * data.visual_scale


func get_forward() -> Vector3:
	var f := -enemy.global_transform.basis.z
	f.y = 0.0
	return f.normalized()


func time_since_seen() -> float:
	return Time.get_ticks_msec() / 1000.0 - last_seen_time


func update(delta: float) -> void:
	if not enabled:
		player_visible = false
		return
	if player == null or not is_instance_valid(player):
		player = enemy.get_tree().get_first_node_in_group("player") as Node3D
	_vision_timer -= delta
	if _vision_timer <= 0.0:
		_vision_timer = 0.1
		_check_vision()
	_body_timer -= delta
	if _body_timer <= 0.0:
		_body_timer = 0.5
		_check_bodies()
	if player_visible:
		_unseen_time = 0.0
		suspicion = minf(CONFIRMED, suspicion + current_gain * delta)
	else:
		_unseen_time += delta
		if _unseen_time > DECAY_GRACE:
			suspicion = maxf(floor_value, suspicion - data.suspicion_decay * delta)


## Pure visibility test for one target point (used by tests and cameras).
func can_see_point(point: Vector3, extra_fov: float = 0.0) -> bool:
	var eye := get_eye_position()
	var to := point - eye
	if to.length() > data.vision_range:
		return false
	var flat := Vector3(to.x, 0, to.z)
	if flat.length() > 0.1 and rad_to_deg(get_forward().angle_to(flat.normalized())) > data.fov_degrees * 0.5 + extra_fov:
		return false
	return _line_clear(eye, point)


func _line_clear(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, VISION_MASK)
	q.exclude = [enemy.get_rid()]
	return enemy.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _check_vision() -> void:
	player_visible = false
	visible_fraction = 0.0
	current_gain = 0.0
	if player == null or (player.has_method("is_dead") and player.is_dead()):
		return
	if player.has_method("is_hidden") and player.is_hidden():
		return
	var eye := get_eye_position()
	var chest: Vector3 = player.get_chest_position() if player.has_method("get_chest_position") else player.global_position + Vector3.UP
	var d := eye.distance_to(chest)
	var vrange := data.vision_range * (1.15 if state_multiplier > 1.5 else 1.0)
	if d > vrange:
		return
	var flat := Vector3(chest.x - eye.x, 0, chest.z - eye.z)
	var angle := rad_to_deg(get_forward().angle_to(flat.normalized())) if flat.length() > 0.05 else 0.0
	var half := data.fov_degrees * 0.5
	var peripheral := angle > half
	if angle > half + PERIPHERAL_EXTRA:
		return
	if peripheral and d > PERIPHERAL_RANGE:
		return
	var pts: Array = player.get_vision_points() if player.has_method("get_vision_points") else [chest]
	var seen := 0
	for p in pts:
		if _line_clear(eye, p):
			seen += 1
	if seen == 0:
		return
	visible_fraction = float(seen) / pts.size()
	var dist_factor: float
	if d < NEAR_DISTANCE:
		dist_factor = 2.5
	else:
		dist_factor = 0.12 + pow(clampf(1.0 - (d - NEAR_DISTANCE) / maxf(1.0, vrange - NEAR_DISTANCE), 0.0, 1.0), 1.2)
	var angle_factor := 0.3 if peripheral else lerpf(1.0, 0.6, clampf(angle / maxf(half, 1.0), 0.0, 1.0))
	var vis: float = player.get_visibility() if player.has_method("get_visibility") else 1.0
	var zone := 1.6 if player.has_meta("restricted") and player.get_meta("restricted") else 1.0
	current_gain = data.detection_rate * visible_fraction * dist_factor * angle_factor * vis * zone * state_multiplier
	if current_gain <= 0.01:
		return
	player_visible = true
	last_seen_position = player.global_position
	last_seen_time = Time.get_ticks_msec() / 1000.0


func _check_bodies() -> void:
	var eye := get_eye_position()
	for n in enemy.get_tree().get_nodes_in_group("enemy_body"):
		var b := n as Node3D
		if b == null or b == enemy or b.get_meta("discovered", false):
			continue
		var p := b.global_position + Vector3.UP * 0.3
		if eye.distance_to(p) > minf(18.0, data.vision_range):
			continue
		if can_see_point(p):
			b.set_meta("discovered", true)
			body_seen.emit(b)
			return


func _on_sound(e: SoundEvent) -> void:
	if not enabled or e.source == enemy or not is_instance_valid(enemy):
		return
	if enemy.has_method("is_dead") and enemy.is_dead():
		return
	var ear := get_eye_position()
	var d := ear.distance_to(e.position)
	var eff := e.radius * data.hearing_multiplier
	if d > eff:
		return
	# Walls muffle sound.
	if not _line_clear(ear, e.position + Vector3.UP * 0.5):
		eff *= 0.55
		if d > eff:
			return
	var loud := clampf(1.0 - d / eff, 0.0, 1.0)
	# Position estimate gets worse with distance — enemies don't get exact positions.
	var err := d * 0.12
	var estimate := e.position + Vector3(_rng.randf_range(-err, err), 0, _rng.randf_range(-err, err))
	var from_ally: bool = e.source != null and is_instance_valid(e.source) and e.source.is_in_group("enemy")
	if not from_ally:
		var weight: float = SoundEvent.SUSPICION_WEIGHT.get(e.type, 20.0)
		var add := weight * (0.4 + 0.6 * loud)
		# Hearing alone never confirms the player (capped below CONFIRMED).
		if suspicion < NOISE_CAP:
			suspicion = minf(NOISE_CAP, suspicion + add)
		_unseen_time = 0.0
	noise_heard.emit(e, estimate, loud)
