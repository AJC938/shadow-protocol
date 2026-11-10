class_name Enemy
extends CharacterBody3D
## Enemy agent: body, navigation, weapon handling, communication and the FSM host.
## Perception lives in the Perception component; decisions live in AIState classes.

signal state_changed(enemy: Enemy, old_state: StringName, new_state: StringName)
signal killed(enemy: Enemy)
signal contact_reported(enemy: Enemy, position: Vector3)
signal health_ratio_changed(enemy: Enemy, ratio: float)

const ARCHETYPE_OUTFIT := {
	EnemyData.Archetype.STANDARD_GUARD: "guard",
	EnemyData.Archetype.SECURITY_SPECIALIST: "specialist",
	EnemyData.Archetype.HEAVY_RESPONSE: "heavy",
	EnemyData.Archetype.COMMANDER: "commander",
}
const SHOT_MASK := 1 | 2 | 16       # world, player, doors
const GRAVITY := 22.0
const SHOUT_RANGE := 16.0

@export var data: EnemyData
@export var enemy_id: String = ""
@export var patrol_points: Array[Vector3] = []
@export var patrol_loop: bool = true
@export var patrol_wait: float = 2.5
@export var start_state: StringName = &"patrol"
## Enemies that start disabled (reinforcements) are activated by mission scripts.
@export var dormant: bool = false

var perception: Perception
var nav: NavigationAgent3D
var rig: CharacterRig
var health: Health
var states: Dictionary = {}
var state: AIState
var state_name: StringName = &""

var aiming: bool = false
var crouching: bool = false
var alerted_once: bool = false
var stimulus_pos: Vector3
var last_known_pos: Vector3
var home_pos: Vector3
var home_yaw: float = 0.0
var patrol_index: int = 0
var patrol_wait_yaw: float = 0.0
var cover: CoverPoint
var move_time: float = 0.0

var _moving: bool = false
var _speed: float = 0.0
var _target_yaw: float = 0.0
var _face_override: bool = false
var _stuck_timer: float = 0.0
var _last_pos: Vector3
var _repath_attempts: int = 0
var _bark_cd: Dictionary = {}
var _shoot_cd: float = 0.0
var _burst_left: int = 0
var _reaction: float = 0.0
var _between_bursts: bool = true
var _tag_left: float = 0.0
var _tag_mat: StandardMaterial3D
var _jammed_left: float = 0.0
var _indicator: Label3D
var _voice: AudioStreamPlayer3D
var _dead: bool = false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	add_to_group("enemy")
	if data == null:
		data = load("res://resources/enemies/standard_guard.tres")
	collision_layer = 4
	collision_mask = 1 | 4 | 16 | 32
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.34 * data.visual_scale
	cap.height = 1.8 * data.visual_scale
	cs.shape = cap
	cs.position = Vector3(0, 0.9 * data.visual_scale, 0)
	add_child(cs)

	rig = CharacterRig.new()
	rig.name = "Rig"
	add_child(rig)
	rig.setup(ARCHETYPE_OUTFIT.get(data.archetype, "guard"))
	if data.weapon:
		rig.set_weapon(data.weapon.model)

	health = Health.new()
	health.max_health = data.max_health
	health.armor = data.armor
	add_child(health)
	health.died.connect(_on_died)

	nav = NavigationAgent3D.new()
	nav.path_desired_distance = 0.6
	nav.target_desired_distance = 0.7
	nav.path_max_distance = 3.0
	nav.radius = 0.4
	nav.height = 1.8
	add_child(nav)

	perception = Perception.new()
	perception.name = "Perception"
	add_child(perception)
	perception.setup(self, data)
	perception.noise_heard.connect(_on_noise)
	perception.body_seen.connect(_on_body_seen)

	_indicator = Label3D.new()
	_indicator.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_indicator.no_depth_test = true
	_indicator.fixed_size = true
	_indicator.pixel_size = 0.0012
	_indicator.font_size = 64
	_indicator.outline_size = 12
	_indicator.position = Vector3(0, 2.25 * data.visual_scale, 0)
	_indicator.text = ""
	add_child(_indicator)

	_voice = AudioStreamPlayer3D.new()
	_voice.bus = "Voice"
	_voice.unit_size = 5.0
	_voice.max_distance = 35.0
	_voice.position = Vector3.UP * 1.6
	add_child(_voice)

	if data.archetype == EnemyData.Archetype.SECURITY_SPECIALIST:
		add_to_group("electronic")   # radio can be jammed by the disruptor

	home_pos = global_position
	home_yaw = rad_to_deg(global_rotation.y)
	_target_yaw = home_yaw
	_last_pos = global_position
	if enemy_id == "":
		enemy_id = name

	states = {
		&"idle": AIStateIdle.new(self), &"patrol": AIStatePatrol.new(self),
		&"suspicious": AIStateSuspicious.new(self), &"investigate": AIStateInvestigate.new(self),
		&"alert": AIStateAlert.new(self), &"combat": AIStateCombat.new(self),
		&"search": AIStateSearch.new(self), &"return": AIStateReturn.new(self),
		&"dead": AIStateDead.new(self),
	}
	if dormant:
		_set_dormant(true)
	else:
		_start.call_deferred()


func _start() -> void:
	change_state(start_state if not patrol_points.is_empty() or start_state != &"patrol" else &"idle")


func _set_dormant(d: bool) -> void:
	dormant = d
	visible = not d
	process_mode = Node.PROCESS_MODE_DISABLED if d else Node.PROCESS_MODE_INHERIT
	collision_layer = 0 if d else 4
	perception.enabled = not d


## Activates a reinforcement and sends it toward a position.
func activate_reinforcement(alert_position: Vector3) -> void:
	_set_dormant(false)
	alerted_once = true
	set_stimulus(alert_position)
	change_state(&"alert")


# =========================================================================== FSM

func change_state(new_name: StringName) -> void:
	if _dead and new_name != &"dead":
		return
	if not states.has(new_name):
		push_error("Enemy %s: unknown state %s" % [name, new_name])
		return
	var old := state_name
	if state:
		state.exit()
	state = states[new_name]
	state_name = new_name
	state.time_in_state = 0.0
	state.enter(old)
	state_changed.emit(self, old, new_name)


func _physics_process(delta: float) -> void:
	if _dead:
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y -= GRAVITY * delta
		move_and_slide()
		return
	if _jammed_left > 0.0:
		_jammed_left -= delta
	perception.update(delta)
	if state:
		state.time_in_state += delta
		state.physics_update(delta)
	_move(delta)
	_update_facing(delta)
	_update_presentation(delta)


# =========================================================================== movement

func move_to(pos: Vector3, run: bool, speed_scale: float = 1.0) -> void:
	_moving = true
	move_time = 0.0
	_speed = (data.run_speed if run else data.walk_speed) * speed_scale
	nav.target_position = pos
	_stuck_timer = 0.0
	_repath_attempts = 0


func stop_moving() -> void:
	_moving = false
	_speed = 0.0


func is_at_destination() -> bool:
	if not _moving:
		return true
	if nav.is_navigation_finished():
		return true
	return Vector2(global_position.x - nav.target_position.x, global_position.z - nav.target_position.z).length() < 0.8


func _nav_ready() -> bool:
	return NavigationServer3D.map_get_iteration_id(nav.get_navigation_map()) > 0


func _move(delta: float) -> void:
	var desired := Vector3.ZERO
	if _moving and _nav_ready():
		move_time += delta
		if nav.is_navigation_finished():
			_moving = false
		else:
			var next := nav.get_next_path_position()
			var dir := next - global_position
			dir.y = 0.0
			if dir.length() > 0.05:
				desired = dir.normalized() * _speed
				# Light separation from nearby allies.
				for n in get_tree().get_nodes_in_group("enemy"):
					var o := n as Node3D
					if o != self and o.visible:
						var away := global_position - o.global_position
						away.y = 0.0
						var dl := away.length()
						if dl > 0.01 and dl < 1.1:
							desired += away.normalized() * (1.1 - dl) * 2.0
	var h := Vector3(velocity.x, 0, velocity.z).move_toward(desired, 10.0 * delta)
	velocity.x = h.x
	velocity.z = h.z
	velocity.y = -0.5 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()
	# Stuck detection: re-path, then nudge to a nearby reachable point, then give up.
	if _moving and _speed > 0.1:
		if global_position.distance_to(_last_pos) < _speed * delta * 0.25:
			_stuck_timer += delta
		else:
			_stuck_timer = maxf(0.0, _stuck_timer - delta)
		if _stuck_timer > 1.6:
			_stuck_timer = 0.0
			_repath_attempts += 1
			if _repath_attempts == 1:
				nav.target_position = nav.target_position
			elif _repath_attempts == 2:
				nav.target_position = random_nav_point_near(nav.target_position, 2.5)
			else:
				stop_moving()
	_last_pos = global_position


func random_nav_point_near(center: Vector3, radius: float) -> Vector3:
	var map := nav.get_navigation_map()
	if not _nav_ready():
		return center
	for i in 8:
		var a := _rng.randf() * TAU
		var r := sqrt(_rng.randf()) * radius
		var p := center + Vector3(cos(a) * r, 0, sin(a) * r)
		var snapped := NavigationServer3D.map_get_closest_point(map, p)
		if snapped.distance_to(p) < 1.5 and absf(snapped.y - center.y) < 2.0:
			return snapped
	return NavigationServer3D.map_get_closest_point(map, center)


func nearest_patrol_index() -> int:
	var best := 0
	var bd := INF
	for i in patrol_points.size():
		var d := global_position.distance_to(patrol_points[i])
		if d < bd:
			bd = d
			best = i
	return best


# =========================================================================== facing

func get_yaw() -> float:
	return rad_to_deg(rotation.y)


func face_yaw(deg: float) -> void:
	_target_yaw = deg
	_face_override = true


func face_point(p: Vector3) -> void:
	var d := p - global_position
	d.y = 0.0
	if d.length() > 0.1:
		face_yaw(rad_to_deg(atan2(-d.x, -d.z)))


func _update_facing(delta: float) -> void:
	var v := Vector3(velocity.x, 0, velocity.z)
	if not _face_override and v.length() > 0.3:
		_target_yaw = rad_to_deg(atan2(-v.x, -v.z))
	elif _moving and v.length() > 0.3 and not aiming:
		_target_yaw = rad_to_deg(atan2(-v.x, -v.z))
	var turn := 7.0 if aiming else 4.5
	rotation.y = lerp_angle(rotation.y, deg_to_rad(_target_yaw), clampf(delta * turn, 0.0, 1.0))
	_face_override = false


# =========================================================================== perception hooks

func set_stimulus(p: Vector3) -> void:
	stimulus_pos = p


func _on_noise(e: SoundEvent, estimate: Vector3, loudness: float) -> void:
	if _dead or state == null:
		return
	# Ally gunfire: come help (they know roughly where the fight is).
	if e.source and is_instance_valid(e.source) and e.source.is_in_group("enemy"):
		if e.type == SoundEvent.Type.ENEMY_GUNSHOT and state_name in [&"idle", &"patrol", &"suspicious", &"investigate", &"return"]:
			set_stimulus(estimate)
			change_state(&"alert")
		return
	state.on_noise(e, estimate, loudness)


func _on_body_seen(body: Node3D) -> void:
	if _dead:
		return
	bark(&"body")
	set_stimulus(body.global_position)
	report_contact(body.global_position, false)
	if state_name != &"combat":
		change_state(&"alert")


## Called by allies, cameras and alarms. `position` is what the caller knows.
func receive_alert(position: Vector3) -> void:
	if _dead or dormant:
		return
	if state_name in [&"combat"]:
		return
	set_stimulus(position)
	if state_name == &"alert" or state_name == &"search":
		last_known_pos = position
		move_to(random_nav_point_near(position, 2.0), true)
	else:
		change_state(&"alert")


## Shout / radio a contact to allies in range. Specialists have long-range radio.
func report_contact(pos: Vector3, emit: bool = true) -> void:
	var radius := SHOUT_RANGE
	if data.radio_range > radius and not radio_jammed():
		radius = data.radio_range
	for n in get_tree().get_nodes_in_group("enemy"):
		var e := n as Enemy
		if e and e != self and not e.is_dead() and not e.dormant and e.global_position.distance_to(global_position) <= radius:
			e.receive_alert(pos)
	if emit:
		contact_reported.emit(self, pos)


func radio_jammed() -> bool:
	return _jammed_left > 0.0


## Signal disruptor hits specialists: radio jammed, cannot call the alarm.
func disrupt(duration: float) -> void:
	_jammed_left = maxf(_jammed_left, duration)


func find_alarm_panel() -> Node3D:
	var best: Node3D = null
	var bd := 35.0
	for n in get_tree().get_nodes_in_group("alarm_panel"):
		var p := n as Node3D
		if p and p.call("can_be_triggered"):
			var d := p.global_position.distance_to(global_position)
			if d < bd:
				bd = d
				best = p
	return best


# =========================================================================== cover

func find_cover(threat: Vector3) -> CoverPoint:
	var best: CoverPoint = null
	var best_score := -INF
	for n in get_tree().get_nodes_in_group("cover_point"):
		var cp := n as CoverPoint
		if cp == null or not cp.is_free_for(self):
			continue
		var ds := global_position.distance_to(cp.global_position)
		if ds > 16.0:
			continue
		var dt := cp.global_position.distance_to(threat)
		if dt < 4.0 or dt > 32.0:
			continue
		if not cover_is_safe(cp, threat):
			continue
		var peek := _ray_clear(cp.global_position + Vector3.UP * 1.55, threat + Vector3.UP * 1.3)
		var score := -ds * 0.6 - absf(dt - data.preferred_range) * 0.4 + (4.0 if peek else 0.0)
		if score > best_score:
			best_score = score
			best = cp
	return best


func cover_is_safe(cp: CoverPoint, threat: Vector3) -> bool:
	var h := 1.5 if cp.high else 0.9
	return not _ray_clear(cp.global_position + Vector3.UP * h, threat + Vector3.UP * 1.2)


func claim_cover(cp: CoverPoint) -> void:
	release_cover()
	cover = cp
	cp.claimed_by = self


func release_cover() -> void:
	if cover and cover.claimed_by == self:
		cover.claimed_by = null
	cover = null
	crouching = false


func _ray_clear(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1 | 16)
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


# =========================================================================== shooting

func reset_reaction(previous: StringName) -> void:
	# Enemies that were already alert react faster.
	var mult := 0.5 if previous in [&"alert", &"search", &"investigate"] else 1.0
	_reaction = data.reaction_time * mult
	_burst_left = 0
	_shoot_cd = 0.0


func is_between_bursts() -> bool:
	return _between_bursts


func try_shoot(delta: float) -> void:
	var w := data.weapon
	if w == null:
		return
	if _reaction > 0.0:
		_reaction -= delta
		return
	_shoot_cd -= delta
	if _shoot_cd > 0.0:
		return
	if _burst_left <= 0:
		_burst_left = data.burst_size
		_between_bursts = false
	_fire_once(w)
	_burst_left -= 1
	if _burst_left <= 0:
		_shoot_cd = data.burst_interval * _rng.randf_range(0.8, 1.25)
		_between_bursts = true
	else:
		_shoot_cd = 1.0 / w.fire_rate


func _fire_once(w: WeaponData) -> void:
	var player := perception.player as Player
	if player == null:
		return
	var muzzle := rig.get_muzzle_position()
	var target := player.get_chest_position()
	var dist := muzzle.distance_to(target)
	var hit_chance := data.accuracy * clampf(1.15 - dist / 55.0, 0.25, 1.0)
	if player.crouching:
		hit_chance *= 0.8
	var pv := Vector2(player.velocity.x, player.velocity.z).length()
	if pv > 4.5:
		hit_chance *= 0.6
	elif pv > 2.0:
		hit_chance *= 0.8
	hit_chance *= lerpf(0.6, 1.0, perception.visible_fraction)
	var aim_point: Vector3
	if _rng.randf() < hit_chance:
		var pts := player.get_vision_points()
		aim_point = pts[_rng.randi() % pts.size()]
	else:
		var off := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.4, 1.0), _rng.randf_range(-1, 1)).normalized() * _rng.randf_range(0.6, 1.6)
		aim_point = target + off
	var dir := (aim_point - muzzle).normalized()
	var q := PhysicsRayQueryParameters3D.create(muzzle, muzzle + dir * w.range, SHOT_MASK)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var end: Vector3 = hit.position if not hit.is_empty() else muzzle + dir * w.range
	if not hit.is_empty():
		var col: Object = hit.collider
		if col == player:
			player.take_damage(DamageInfo.make(w.damage, end, dir, self, false, w.id))
		else:
			CombatFX.impact(self, end, hit.normal, false)
			if _rng.randf() < 0.3:
				AudioManager.play_3d(&"impact", end, -10.0, 25.0)
	CombatFX.tracer(self, muzzle, end, Color(1.0, 0.5, 0.35, 0.6))
	CombatFX.muzzle_flash(self, muzzle, dir, w.muzzle_flash_scale, w.suppressed)
	AudioManager.play_3d(w.fire_sound, muzzle, -2.0, 90.0)
	SoundEvents.emit_sound(global_position, w.noise_radius, SoundEvent.Type.ENEMY_GUNSHOT, 1.0, self)
	rig.play_fire()


# =========================================================================== damage

func take_damage(info: DamageInfo) -> void:
	if _dead:
		return
	health.apply_damage(info)
	health_ratio_changed.emit(self, health.ratio())
	if _dead:
		return
	rig.play_hit()
	bark(&"hurt")
	# Being shot reveals roughly where the shot came from.
	var src_pos: Vector3 = info.source.global_position if info.source is Node3D else info.position - info.direction * 10.0
	if state_name != &"combat":
		last_known_pos = src_pos
		perception.last_seen_position = src_pos
		if perception.player_visible:
			perception.suspicion = Perception.CONFIRMED
			change_state(&"combat")
		else:
			set_stimulus(src_pos)
			change_state(&"alert")
			report_contact(src_pos)


func is_headshot(p: Vector3) -> bool:
	return p.y > global_position.y + 1.5 * data.visual_scale


func is_dead() -> bool:
	return _dead


func _on_died(_info: DamageInfo) -> void:
	_dead = true
	release_cover()
	change_state(&"dead")
	rig.play_death()
	_indicator.text = ""
	collision_layer = 0
	collision_mask = 1
	perception.enabled = false
	remove_from_group("electronic")
	add_to_group("enemy_body")
	set_meta("discovered", false)
	set_tagged(false)
	AudioManager.play_3d(&"enemy_death", global_position + Vector3.UP, -2.0)
	SoundEvents.emit_sound(global_position, 4.0, SoundEvent.Type.BODY_FALL, 0.6, self)
	killed.emit(self)


## Instant removal used when restoring a checkpoint (enemy was already neutralised).
func set_dead_silent() -> void:
	_dead = true
	health.current = 0.0
	state = states[&"dead"]
	state_name = &"dead"
	rig.play_death()
	collision_layer = 0
	collision_mask = 1
	perception.enabled = false
	remove_from_group("electronic")
	add_to_group("enemy_body")
	set_meta("discovered", true)


# =========================================================================== presentation

func bark(key: StringName) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_bark_cd.get(key, -100.0)) < 6.0 or _voice.playing:
		return
	_bark_cd[key] = now
	var voice_set := "heavy" if data.archetype in [EnemyData.Archetype.HEAVY_RESPONSE, EnemyData.Archetype.COMMANDER] else "guard"
	var s := AudioManager.get_stream(StringName("bark_%s_%s" % [voice_set, key]))
	if s == null:
		s = AudioManager.get_stream(StringName("bark_guard_%s" % key))
	if s:
		_voice.stream = s
		_voice.pitch_scale = _rng.randf_range(0.93, 1.05)
		_voice.play()


func tag(duration: float) -> void:
	if _dead:
		return
	_tag_left = maxf(_tag_left, duration)
	set_tagged(true)


func is_tagged() -> bool:
	return _tag_left > 0.0


func set_tagged(on: bool) -> void:
	if on:
		add_to_group("tagged")
	else:
		remove_from_group("tagged")
	if _tag_mat == null:
		_tag_mat = StandardMaterial3D.new()
		_tag_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_tag_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_tag_mat.no_depth_test = true
		_tag_mat.albedo_color = Color(1.0, 0.55, 0.15, 0.35)
		_tag_mat.render_priority = 1
	for mi in rig.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = _tag_mat if on else null


func _update_presentation(delta: float) -> void:
	if _tag_left > 0.0:
		_tag_left -= delta
		if _tag_left <= 0.0:
			set_tagged(false)
	var speed := Vector2(velocity.x, velocity.z).length()
	var pitch := 0.0
	if aiming and perception.player and perception.player_visible:
		var to := perception.player.global_position + Vector3.UP * 1.2 - (global_position + Vector3.UP * 1.4)
		pitch = atan2(to.y, Vector2(to.x, to.z).length())
	rig.update_locomotion(speed, crouching, aiming, pitch, delta)
	# Awareness indicator.
	var s := perception.suspicion
	match state_name:
		&"combat":
			_indicator.text = "!"
			_indicator.modulate = Color(0.95, 0.2, 0.15)
		&"alert", &"search":
			_indicator.text = "!"
			_indicator.modulate = Color(1.0, 0.55, 0.1)
		&"suspicious", &"investigate":
			_indicator.text = "?"
			_indicator.modulate = Color(1.0, 0.85, 0.25, clampf(0.4 + s / 100.0, 0.0, 1.0))
		_:
			if s > 5.0:
				_indicator.text = "?"
				_indicator.modulate = Color(1.0, 1.0, 1.0, clampf(s / 40.0, 0.0, 0.7))
			else:
				_indicator.text = ""


func get_save_state() -> Dictionary:
	return {"dead": _dead}
