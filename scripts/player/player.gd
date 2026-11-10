class_name Player
extends CharacterBody3D
## GHOST — third-person tactical player controller.
## Movement states, stance, noise emission, light-aware visibility, health,
## weapons, gadgets and interaction. All input comes from InputRouter.

signal died
signal health_changed(current: float, maximum: float)
signal damaged(from_direction: Vector3)
signal stance_changed(crouching: bool)
signal stealth_visibility_changed(value: float)
signal noise_made(radius: float)

enum Move { IDLE, WALK, JOG, SPRINT }

const SPEED_WALK := 1.7
const SPEED_JOG := 3.7
const SPEED_SPRINT := 6.2
const SPEED_CROUCH := 1.7
const SPEED_AIM := 2.3
const SPEED_AIM_CROUCH := 1.3
const ACCEL := 13.0
const DECEL := 16.0
const GRAVITY := 22.0
const TURN_SPEED := 12.0
## Perception radius of one footstep per move state (metres) before surface multiplier.
const STEP_NOISE := {Move.WALK: 3.0, Move.JOG: 7.5, Move.SPRINT: 14.0}
const CROUCH_NOISE := 1.2
const SURFACE_NOISE := {"concrete": 1.0, "metal": 1.45, "gravel": 1.25, "tile": 1.1, "grate": 1.5}

@export var weapon_ids: Array[StringName] = [&"pistol", &"rifle", &"shotgun"]
@export var gadget_ids: Array[StringName] = [&"recon", &"disruptor", &"scanner"]

var rig: CharacterRig
var camera_rig: CameraRig
var health: Health
var weapons: WeaponInventory
var gadgets: GadgetController
var interactor: Interactor

var move_state: int = Move.IDLE
var crouching: bool = false
var aiming: bool = false
var hidden_in: Node = null          # HidingSpot currently occupied
var visibility: float = 1.0
var light_level: float = 0.5
var ambient_light: float = 0.25    # set by the mission environment
var input_enabled: bool = true
var keycards: Array[String] = []

var _step_accum: float = 0.0
var _vis_timer: float = 0.0
var _dead: bool = false
var _collision: CollisionShape3D
var _capsule: CapsuleShape3D
var _hip_fire_face: float = 0.0


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1 | 4 | 16 | 32
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(50)
	_capsule = CapsuleShape3D.new()
	_capsule.radius = 0.32
	_capsule.height = 1.8
	_collision = CollisionShape3D.new()
	_collision.shape = _capsule
	_collision.position = Vector3(0, 0.9, 0)
	add_child(_collision)

	rig = CharacterRig.new()
	rig.name = "Rig"
	add_child(rig)
	rig.setup("ghost")

	health = Health.new()
	health.name = "Health"
	health.max_health = 100.0
	health.regen_delay = 6.0
	health.regen_rate = 8.0
	add_child(health)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)

	camera_rig = CameraRig.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)
	camera_rig.attach(self)

	weapons = WeaponInventory.new()
	weapons.name = "Weapons"
	add_child(weapons)
	weapons.setup(self, camera_rig, rig, weapon_ids)

	gadgets = GadgetController.new()
	gadgets.name = "Gadgets"
	add_child(gadgets)
	gadgets.setup(self, camera_rig, gadget_ids)

	interactor = Interactor.new()
	interactor.name = "Interactor"
	add_child(interactor)
	interactor.setup(self, camera_rig)


## Rebuilds weapons/gadgets for a mission loadout.
func set_loadout(weapon_list: Array, gadget_list: Array) -> void:
	weapons.setup(self, camera_rig, rig, weapon_list)
	gadgets.setup(self, camera_rig, gadget_list)


func _physics_process(delta: float) -> void:
	if _dead:
		velocity.x = move_toward(velocity.x, 0, DECEL * delta)
		velocity.z = move_toward(velocity.z, 0, DECEL * delta)
		velocity.y -= GRAVITY * delta
		move_and_slide()
		return
	if hidden_in != null:
		velocity = Vector3.ZERO
		if input_enabled and InputRouter.is_just_pressed(&"interact"):
			hidden_in.call("exit_spot", self)
		_update_visibility(delta)
		return
	var can_act := input_enabled and not gadgets.recon_active
	_handle_actions(can_act)
	_handle_movement(delta, can_act)
	weapons.process_weapon(delta,
		can_act and InputRouter.is_pressed(&"fire"),
		can_act and InputRouter.is_just_pressed(&"fire"),
		aiming, Vector2(velocity.x, velocity.z).length())
	if can_act and InputRouter.is_pressed(&"fire"):
		_hip_fire_face = 0.6
	_hip_fire_face = maxf(0.0, _hip_fire_face - delta)
	if input_enabled:
		interactor.process_interaction(delta, InputRouter.is_just_pressed(&"interact") and not gadgets.recon_active,
			InputRouter.is_pressed(&"interact") and not gadgets.recon_active)
	_update_visibility(delta)
	var pitch := deg_to_rad(camera_rig.pitch) if (aiming or _hip_fire_face > 0.0) else deg_to_rad(camera_rig.pitch) * 0.3
	rig.update_locomotion(Vector2(velocity.x, velocity.z).length(), crouching, aiming or _hip_fire_face > 0.0, pitch, delta)


func _handle_actions(can_act: bool) -> void:
	if InputRouter.is_just_pressed(&"gadget_use") and input_enabled and hidden_in == null:
		gadgets.use_selected()
	if not can_act:
		aiming = false
		camera_rig.aiming = false
		return
	aiming = InputRouter.is_pressed(&"aim")
	camera_rig.aiming = aiming
	if InputRouter.is_just_pressed(&"crouch"):
		set_crouch(not crouching)
	if InputRouter.is_just_pressed(&"reload"):
		weapons.start_reload()
	for i in 3:
		if InputRouter.is_just_pressed(StringName("weapon_%d" % (i + 1))):
			weapons.select(i)
	if InputRouter.is_just_pressed(&"weapon_next"):
		weapons.cycle(1)
	if InputRouter.is_just_pressed(&"weapon_prev"):
		weapons.cycle(-1)
	if InputRouter.is_just_pressed(&"gadget_next"):
		gadgets.cycle()
	if InputRouter.is_just_pressed(&"swap_shoulder"):
		camera_rig.swap_shoulder()


func set_crouch(c: bool) -> void:
	if c == crouching:
		return
	if not c and not _can_stand():
		return
	crouching = c
	_capsule.height = 1.2 if c else 1.8
	_collision.position.y = _capsule.height * 0.5
	camera_rig.crouching = c
	stance_changed.emit(c)


func _can_stand() -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var s := CapsuleShape3D.new()
	s.radius = 0.3
	s.height = 1.75
	q.shape = s
	q.transform = Transform3D(Basis(), global_position + Vector3.UP * 0.92)
	q.collision_mask = 1 | 16
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func _handle_movement(delta: float, can_act: bool) -> void:
	var input := InputRouter.get_move_vector() if can_act else Vector2.ZERO
	var basis := camera_rig.get_yaw_basis()
	var dir := basis * Vector3(input.x, 0, input.y)
	dir.y = 0.0
	var amount := minf(1.0, input.length())
	if dir.length() > 0.001:
		dir = dir.normalized()
	var sprinting := can_act and InputRouter.is_pressed(&"sprint") and not aiming and input.y < 0.2 and amount > 0.5
	if sprinting and crouching:
		set_crouch(false)
		sprinting = not crouching
	var walking := can_act and InputRouter.is_pressed(&"walk")
	var target_speed: float
	if aiming:
		target_speed = SPEED_AIM_CROUCH if crouching else SPEED_AIM
	elif crouching:
		target_speed = SPEED_CROUCH
	elif sprinting:
		target_speed = SPEED_SPRINT
	elif walking or amount < 0.45:
		target_speed = SPEED_WALK
	else:
		target_speed = SPEED_JOG
	target_speed *= clampf(amount * 1.3, 0.0, 1.0)
	var target_vel := dir * target_speed
	var horizontal := Vector3(velocity.x, 0, velocity.z)
	var rate := ACCEL if target_vel.length() > horizontal.length() else DECEL
	if not is_on_floor():
		rate *= 0.3
	horizontal = horizontal.move_toward(target_vel, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()

	# Facing: aim / hip-fire -> camera yaw, otherwise movement direction.
	var speed := horizontal.length()
	var face_yaw := rig.rotation.y
	if aiming or _hip_fire_face > 0.0:
		face_yaw = deg_to_rad(camera_rig.yaw)
	elif speed > 0.2:
		face_yaw = atan2(-horizontal.x, -horizontal.z)
	rig.rotation.y = lerp_angle(rig.rotation.y, face_yaw, clampf(TURN_SPEED * delta, 0.0, 1.0))

	# Move state + footsteps.
	if speed < 0.15:
		move_state = Move.IDLE
	elif sprinting and speed > SPEED_JOG:
		move_state = Move.SPRINT
	elif speed > SPEED_WALK + 0.4:
		move_state = Move.JOG
	else:
		move_state = Move.WALK
	if is_on_floor() and speed > 0.15:
		_step_accum += speed * delta
		var stride := 0.62 if crouching else (0.75 if move_state == Move.WALK else (1.05 if move_state == Move.JOG else 1.45))
		if _step_accum >= stride:
			_step_accum = 0.0
			_footstep()


func get_surface() -> String:
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.3, global_position + Vector3.DOWN * 0.5, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and hit.collider is Node and (hit.collider as Node).has_meta("surface"):
		return str((hit.collider as Node).get_meta("surface"))
	return "concrete"


func _footstep() -> void:
	var surface := get_surface()
	var mult: float = SURFACE_NOISE.get(surface, 1.0)
	var radius: float
	if crouching:
		radius = CROUCH_NOISE * mult
	else:
		radius = STEP_NOISE.get(move_state, 3.0) * mult
	var vol := -14.0 if crouching else (-9.0 if move_state == Move.WALK else (-5.0 if move_state == Move.JOG else -2.0))
	AudioManager.play_3d(StringName("step_" + surface), global_position, vol, 25.0, 0.1)
	var type := SoundEvent.Type.SPRINT if move_state == Move.SPRINT else SoundEvent.Type.FOOTSTEP
	SoundEvents.emit_sound(global_position, radius, type, clampf(radius / 14.0, 0.1, 1.0), self)
	noise_made.emit(radius)


# --------------------------------------------------------------------------- perception API

## Points enemies test for line of sight (head, chest, hips).
func get_vision_points() -> Array[Vector3]:
	var p := global_position
	if crouching:
		return [p + Vector3.UP * 1.1, p + Vector3.UP * 0.8, p + Vector3.UP * 0.45]
	return [p + Vector3.UP * 1.65, p + Vector3.UP * 1.25, p + Vector3.UP * 0.85]


func get_chest_position() -> Vector3:
	return global_position + Vector3.UP * (0.85 if crouching else 1.3)


func is_hidden() -> bool:
	return hidden_in != null


func is_dead() -> bool:
	return _dead


func get_visibility() -> float:
	return 0.0 if hidden_in else visibility


func _update_visibility(delta: float) -> void:
	_vis_timer -= delta
	if _vis_timer > 0.0:
		return
	_vis_timer = 0.2
	light_level = LightSampler.sample(get_tree(), global_position + Vector3.UP * 1.0, ambient_light)
	var stance := 0.6 if crouching else 1.0
	var motion := 0.85
	match move_state:
		Move.WALK: motion = 0.95
		Move.JOG: motion = 1.05
		Move.SPRINT: motion = 1.25
	var v := clampf(stance * motion * lerpf(0.3, 1.0, light_level), 0.05, 1.25)
	if absf(v - visibility) > 0.01:
		visibility = v
		stealth_visibility_changed.emit(v)


# --------------------------------------------------------------------------- damage

func take_damage(info: DamageInfo) -> void:
	if _dead:
		return
	health.apply_damage(info)


func is_headshot(_p: Vector3) -> bool:
	return false


func _on_damaged(info: DamageInfo, remaining: float) -> void:
	rig.play_hit()
	camera_rig.add_shake(0.35)
	AudioManager.play_2d(&"player_hit", -4.0)
	health_changed.emit(remaining, health.max_health)
	damaged.emit(info.direction)


func _process(_delta: float) -> void:
	# Health regen is silent; keep the HUD in sync.
	if not _dead and health.current < health.max_health:
		health_changed.emit(health.current, health.max_health)


func _on_died(_info: DamageInfo) -> void:
	_dead = true
	input_enabled = false
	gadgets.exit_recon()
	rig.play_death()
	camera_rig.aiming = false
	AudioManager.play_2d(&"player_death", -2.0)
	died.emit()


func on_interacted() -> void:
	rig.play_interact()


## Teleports (checkpoint restore / tests).
func place_at(pos: Vector3, yaw_deg: float) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	rig.rotation.y = deg_to_rad(yaw_deg)
	camera_rig.yaw = yaw_deg
	camera_rig.global_position = pos + Vector3.UP * CameraRig.HEIGHT_STAND


func add_keycard(id: String) -> void:
	if not keycards.has(id):
		keycards.append(id)


func has_keycard(id: String) -> bool:
	return keycards.has(id)


func get_save_state() -> Dictionary:
	return {
		"pos": [global_position.x, global_position.y, global_position.z],
		"yaw": camera_rig.yaw,
		"health": health.current,
		"weapons": weapons.get_state(),
		"gadgets": gadgets.get_state(),
		"keycards": keycards.duplicate(),
		"weapon": weapons.current,
	}


func apply_save_state(s: Dictionary) -> void:
	var p = s.get("pos", [])
	if typeof(p) == TYPE_ARRAY and p.size() == 3:
		place_at(Vector3(float(p[0]), float(p[1]), float(p[2])), float(s.get("yaw", 0.0)))
	health.reset(float(s.get("health", health.max_health)))
	if typeof(s.get("weapons")) == TYPE_ARRAY:
		weapons.apply_state(s["weapons"])
	if typeof(s.get("gadgets")) == TYPE_ARRAY:
		gadgets.apply_state(s["gadgets"])
	keycards.clear()
	if typeof(s.get("keycards")) == TYPE_ARRAY:
		for k in s["keycards"]:
			keycards.append(str(k))
	weapons.select(clampi(int(s.get("weapon", 0)), 0, maxi(0, weapons.weapons.size() - 1)))
