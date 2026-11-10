class_name WeaponInventory
extends Node
## Player weapon handling: ammo, fire rate, spread, recoil, reload, switching and
## hitscan resolution. Weapon numbers come from WeaponData resources.

signal weapon_changed(index: int, data: WeaponData)
signal ammo_changed(mag: int, reserve: int)
signal fired(data: WeaponData)
signal reload_started(duration: float)
signal reload_finished
signal hit_confirmed(target: Node, killed: bool, headshot: bool)

const WEAPON_PATHS := {
	&"pistol": "res://resources/weapons/suppressed_pistol.tres",
	&"rifle": "res://resources/weapons/assault_rifle.tres",
	&"shotgun": "res://resources/weapons/tactical_shotgun.tres",
}
const HIT_MASK := 1 | 4 | 16   # world, enemies, doors (fences/glass on layer 6 are shoot-through)

class WeaponState:
	var data: WeaponData
	var mag: int
	var reserve: int

var weapons: Array[WeaponState] = []
var current: int = 0
var owner_body: CharacterBody3D
var camera_rig: CameraRig
var rig: CharacterRig

var shots_fired: int = 0
var shots_hit: int = 0

var _cooldown: float = 0.0
var _reloading: float = 0.0
var _switching: float = 0.0
var _bloom: float = 0.0
var _rng := RandomNumberGenerator.new()


func setup(body: CharacterBody3D, cam: CameraRig, character_rig: CharacterRig, ids: Array) -> void:
	owner_body = body
	camera_rig = cam
	rig = character_rig
	_rng.randomize()
	weapons.clear()
	for id in ids:
		if WEAPON_PATHS.has(StringName(id)):
			var ws := WeaponState.new()
			ws.data = load(WEAPON_PATHS[StringName(id)])
			ws.mag = ws.data.magazine_size
			ws.reserve = ws.data.start_reserve
			weapons.append(ws)
	current = 0
	if not weapons.is_empty():
		rig.set_weapon(weapons[0].data.model)
		weapon_changed.emit(0, weapons[0].data)
		_emit_ammo()


func get_current() -> WeaponState:
	return weapons[current] if current < weapons.size() else null


func get_data() -> WeaponData:
	var w := get_current()
	return w.data if w else null


func is_reloading() -> bool:
	return _reloading > 0.0


func is_busy() -> bool:
	return _reloading > 0.0 or _switching > 0.0


## Current spread half-angle (degrees) — read by the HUD crosshair.
func current_spread(aiming: bool, moving_speed: float) -> float:
	var d := get_data()
	if d == null:
		return 0.0
	var s := d.spread_aim if aiming else d.spread_hip
	s += d.spread_move_add * clampf(moving_speed / 4.0, 0.0, 1.5)
	return s + _bloom


func _emit_ammo() -> void:
	var w := get_current()
	if w:
		ammo_changed.emit(w.mag, w.reserve)


func select(index: int) -> void:
	if index < 0 or index >= weapons.size() or index == current:
		return
	_reloading = 0.0
	rig.cancel_reload()
	current = index
	var d := weapons[current].data
	_switching = d.switch_time
	rig.play_switch()
	# Swap the model halfway through the switch animation.
	get_tree().create_timer(d.switch_time * 0.5).timeout.connect(func(): rig.set_weapon(d.model))
	AudioManager.play_3d(&"weapon_switch", owner_body.global_position + Vector3.UP, -6.0)
	weapon_changed.emit(current, d)
	_emit_ammo()


func cycle(dir: int) -> void:
	if weapons.size() > 1:
		select(posmod(current + dir, weapons.size()))


func start_reload() -> void:
	var w := get_current()
	if w == null or is_busy() or w.mag >= w.data.magazine_size or w.reserve <= 0:
		return
	_reloading = w.data.reload_time
	rig.play_reload(w.data.reload_time)
	AudioManager.play_3d(&"reload_%s" % String(w.data.id), owner_body.global_position + Vector3.UP, -3.0)
	SoundEvents.emit_sound(owner_body.global_position, 3.0, SoundEvent.Type.GADGET, 0.4, owner_body)
	reload_started.emit(w.data.reload_time)


func add_reserve(weapon_id: StringName, amount: int) -> int:
	for w in weapons:
		if w.data.id == weapon_id:
			var before := w.reserve
			w.reserve = mini(w.data.max_reserve, w.reserve + amount)
			_emit_ammo()
			return w.reserve - before
	return 0


## Adds a share of ammo to every weapon (generic ammo crate). Returns true if anything was added.
func refill_all(fraction: float) -> bool:
	var any := false
	for w in weapons:
		var add := int(ceil(w.data.max_reserve * fraction))
		var before := w.reserve
		w.reserve = mini(w.data.max_reserve, w.reserve + add)
		any = any or w.reserve > before
	_emit_ammo()
	return any


func process_weapon(delta: float, trigger_held: bool, trigger_pressed: bool, aiming: bool, move_speed: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_bloom = move_toward(_bloom, 0.0, delta * 6.0)
	if _switching > 0.0:
		_switching = maxf(0.0, _switching - delta)
	if _reloading > 0.0:
		_reloading -= delta
		if _reloading <= 0.0:
			_finish_reload()
		return
	var w := get_current()
	if w == null or _switching > 0.0:
		return
	var wants := trigger_held if w.data.automatic else trigger_pressed
	if not wants or _cooldown > 0.0:
		return
	if w.mag <= 0:
		if trigger_pressed:
			AudioManager.play_3d(&"dry_fire", owner_body.global_position + Vector3.UP, -6.0)
			start_reload()
		return
	_fire(w, aiming, move_speed)


func _finish_reload() -> void:
	_reloading = 0.0
	var w := get_current()
	var need := w.data.magazine_size - w.mag
	var take := mini(need, w.reserve)
	w.mag += take
	w.reserve -= take
	_emit_ammo()
	reload_finished.emit()


func _fire(w: WeaponState, aiming: bool, move_speed: float) -> void:
	var d := w.data
	w.mag -= 1
	_cooldown = 1.0 / d.fire_rate
	shots_fired += 1
	var spread := current_spread(aiming, move_speed)
	var cam := camera_rig.camera
	var origin := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var right := cam.global_transform.basis.x
	var up := cam.global_transform.basis.y
	var muzzle := rig.get_muzzle_position()
	var space := owner_body.get_world_3d().direct_space_state
	# Skip geometry between camera and player.
	var start_offset := origin.distance_to(owner_body.global_position + Vector3.UP * 1.4) * 0.9
	var any_hit := false
	for i in d.pellets:
		var a := _rng.randf() * TAU
		var r := deg_to_rad(spread) * sqrt(_rng.randf())
		var dir := (fwd + right * cos(a) * tan(r) + up * sin(a) * tan(r)).normalized()
		var from := origin + dir * start_offset
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * d.range, HIT_MASK)
		q.exclude = [owner_body.get_rid()]
		q.collide_with_areas = false
		var hit := space.intersect_ray(q)
		var end_point: Vector3 = hit.position if not hit.is_empty() else from + dir * d.range
		# Verify the weapon actually has a line to the aim point (no shooting around corners).
		var q2 := PhysicsRayQueryParameters3D.create(muzzle, end_point + (end_point - muzzle).normalized() * 0.05, HIT_MASK)
		q2.exclude = [owner_body.get_rid()]
		var hit2 := space.intersect_ray(q2)
		if not hit2.is_empty() and (hit.is_empty() or hit2.collider != hit.collider or hit2.position.distance_to(hit.position) > 0.3):
			hit = hit2
			end_point = hit2.position
		if i < 3:
			CombatFX.tracer(owner_body, muzzle, end_point, Color(1.0, 0.82, 0.5, 0.55))
		if not hit.is_empty():
			any_hit = _apply_hit(hit, d, muzzle, end_point) or any_hit
	if any_hit:
		shots_hit += 1
	CombatFX.muzzle_flash(owner_body, muzzle, fwd, d.muzzle_flash_scale, d.suppressed)
	AudioManager.play_3d(d.fire_sound, muzzle, 0.0 if not d.suppressed else -4.0, 80.0)
	SoundEvents.emit_sound(owner_body.global_position, d.noise_radius,
		SoundEvent.Type.SUPPRESSED_SHOT if d.suppressed else SoundEvent.Type.GUNSHOT, 1.0, owner_body)
	camera_rig.add_recoil(d.recoil_pitch * (0.6 if aiming else 1.0), _rng.randf_range(-d.recoil_yaw, d.recoil_yaw))
	camera_rig.add_shake(0.15 if d.pellets > 1 else 0.05)
	_bloom = minf(_bloom + d.recoil_pitch * 0.5, 4.0)
	rig.play_fire()
	_emit_ammo()
	fired.emit(d)


func _apply_hit(hit: Dictionary, d: WeaponData, from: Vector3, point: Vector3) -> bool:
	var col: Object = hit.collider
	var dist := from.distance_to(point)
	var falloff := 1.0
	if dist > d.falloff_start:
		falloff = lerpf(1.0, d.min_damage_scale, clampf((dist - d.falloff_start) / maxf(1.0, d.range - d.falloff_start), 0.0, 1.0))
	var target := col as Node
	var flesh := false
	if target and target.has_method("take_damage"):
		var head := false
		if target.has_method("is_headshot"):
			head = target.is_headshot(point)
		var amount := d.damage * falloff * (d.headshot_multiplier if head else 1.0)
		var info := DamageInfo.make(amount, point, (point - from).normalized(), owner_body, head, d.id)
		var was_alive: bool = not (target.has_method("is_dead") and target.is_dead())
		target.take_damage(info)
		var killed: bool = was_alive and target.has_method("is_dead") and target.is_dead()
		flesh = target.is_in_group("enemy")
		hit_confirmed.emit(target, killed, head)
	CombatFX.impact(owner_body, point, hit.normal, flesh)
	if not flesh:
		AudioManager.play_3d(&"impact", point, -8.0, 30.0)
		SoundEvents.emit_sound(point, 5.0, SoundEvent.Type.IMPACT, 0.6, owner_body)
	return target != null and target.has_method("take_damage")


func get_state() -> Array:
	var out := []
	for w in weapons:
		out.append([String(w.data.id), w.mag, w.reserve])
	return out


func apply_state(state: Array) -> void:
	for s in state:
		if typeof(s) != TYPE_ARRAY or s.size() != 3:
			continue
		for w in weapons:
			if String(w.data.id) == str(s[0]):
				w.mag = clampi(int(s[1]), 0, w.data.magazine_size)
				w.reserve = clampi(int(s[2]), 0, w.data.max_reserve)
	_emit_ammo()
