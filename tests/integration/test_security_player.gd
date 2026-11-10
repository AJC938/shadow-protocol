extends TestCase
## Integration tests: security devices, stealth helpers, player controller,
## weapons, interaction and gadgets.

var world: Node3D
var player: Player


func before_each() -> void:
	world = await make_arena(60.0, false)
	InputRouter.external.reset()


func after_each() -> void:
	InputRouter.external.reset()
	await super()


func _player(pos: Vector3, yaw: float = 0.0) -> void:
	player = make_player(world, pos)
	player.place_at(pos, yaw)


func _light_at(pos: Vector3) -> void:
	var l := OmniLight3D.new()
	l.omni_range = 9.0
	l.light_energy = 3.0
	l.add_to_group("level_light")
	world.add_child(l)
	l.global_position = pos


# ------------------------------------------------------------------ cameras / alarm

func test_camera_detects_and_raises_alarm() -> void:
	await bake(world)
	var alarm := AlarmSystem.new()
	world.add_child(alarm)
	var cam := SecurityCamera.new()
	cam.position = Vector3(0, 3, 0)
	cam.sweep_angle = 0.0
	world.add_child(cam)
	_player(Vector3(0, 0, -7))
	player.input_enabled = false
	_light_at(Vector3(0, 2.5, -7))
	var guard := make_enemy(world, "guard", Vector3(10, 0, 10), 180.0)
	await seconds(6.0)
	check(cam.suspicion > 50.0 or alarm.active, "SEC-01 camera builds suspicion (%.0f)" % cam.suspicion)
	await seconds(4.0)
	check(alarm.active, "SEC-02 full detection raises alarm")
	check(guard.state_name in [&"alert", &"search", &"combat"], "SEC-03 alarm alerts guards (state %s)" % guard.state_name)
	check(guard.stimulus_pos.distance_to(player.global_position) < 2.0 or guard.state_name == &"combat", "SEC-03 guards get the reported position")


func test_disruptor_and_console_disable_camera() -> void:
	var alarm := AlarmSystem.new()
	world.add_child(alarm)
	var cam := SecurityCamera.new()
	cam.position = Vector3(0, 3, 0)
	cam.sweep_angle = 0.0
	cam.network = "net_a"
	world.add_child(cam)
	_player(Vector3(0, 0, -6))
	player.input_enabled = false
	_light_at(Vector3(0, 2.5, -6))
	cam.disrupt(3.0)
	await seconds(2.0)
	check(not cam.is_operational(), "SEC-04 disrupted camera offline")
	near(cam.suspicion, 0.0, 0.01, "SEC-04 disrupted camera sees nothing")
	await seconds(1.5)
	check(cam.is_operational(), "SEC-05 disruption is temporary")
	var console := SecurityConsole.new()
	console.disable_camera_network = "net_a"
	console.disable_alarm = true
	world.add_child(console)
	console.interact(player)
	check(cam.disabled and not cam.is_operational(), "SEC-06 console disables the camera network")
	check(alarm.offline, "SEC-07 console takes the alarm offline")
	check(not alarm.raise_alarm(Vector3.ZERO), "SEC-07 offline alarm cannot be raised")


func test_alarm_auto_clears() -> void:
	var alarm := AlarmSystem.new()
	alarm.reset_after = 1.0
	world.add_child(alarm)
	alarm.raise_alarm(Vector3.ZERO)
	check(alarm.active, "SEC-08 raised")
	await seconds(1.6)
	check(not alarm.active, "SEC-08 alarm clears after a quiet period")


func test_door_blocks_vision_and_opens() -> void:
	add_wall(world, Vector3(-2.3, 1.5, -4), Vector3(3, 3, 0.3))
	add_wall(world, Vector3(2.3, 1.5, -4), Vector3(3, 3, 0.3))
	await bake(world)
	var door := Door.new()
	door.position = Vector3(0, 0, -4)
	door.enemy_access = false
	world.add_child(door)
	_player(Vector3(0, 0, -8))
	player.input_enabled = false
	var e := make_enemy(world, "guard", Vector3.ZERO, 0.0)
	await seconds(1.0)
	check(not e.perception.player_visible, "SEC-09 closed door blocks vision")
	door.set_open(true)
	await seconds(2.0)
	check(e.perception.player_visible, "SEC-10 open door lets vision through")


func test_keycard_door() -> void:
	var door := Door.new()
	door.lock = Door.Lock.KEYCARD
	door.keycard_id = "red"
	world.add_child(door)
	_player(Vector3(0, 0, 2))
	door.interact(player)
	check(not door.is_open and door.locked, "SEC-11 locked without keycard")
	player.add_keycard("red")
	door.interact(player)
	check(not door.locked and door.is_open, "SEC-12 keycard unlocks and opens")


func test_hiding_spot_hides_player() -> void:
	await bake(world)
	var spot := HidingSpot.new()
	spot.position = Vector3(0, 0, -6)
	world.add_child(spot)
	_player(Vector3(0, 0, -4.8))
	player.input_enabled = false
	_light_at(Vector3(0, 2.5, -5))
	var e := make_enemy(world, "guard", Vector3.ZERO, 0.0)
	spot.interact(player)
	check(player.is_hidden(), "STL-01 player hidden in locker")
	await seconds(3.0)
	near(e.perception.suspicion, 0.0, 0.5, "STL-02 hidden player not detected")
	spot.exit_spot(player)
	check(not player.is_hidden(), "STL-03 exit locker")


func test_restricted_zone_flag() -> void:
	var z := RestrictedZone.new()
	z.size = Vector3(6, 3, 6)
	world.add_child(z)
	_player(Vector3(0, 0, 0))
	await seconds(0.3)
	check(player.get_meta("restricted", false), "STL-04 restricted flag set inside zone")
	player.place_at(Vector3(15, 0, 15), 0)
	await seconds(0.3)
	check(not player.get_meta("restricted", false), "STL-04 cleared outside")


# ------------------------------------------------------------------ player movement / noise

func test_movement_speeds_and_noise() -> void:
	_player(Vector3(0, 0, 0))
	var radii := []
	var cb := func(ev: SoundEvent):
		if ev.source == player and ev.type in [SoundEvent.Type.FOOTSTEP, SoundEvent.Type.SPRINT]:
			radii.append(ev.radius)
	SoundEvents.sound_emitted.connect(cb)
	InputRouter.external.set_axis(&"move_y", 1.0)
	await seconds(1.5)
	var jog := Vector2(player.velocity.x, player.velocity.z).length()
	check(player.velocity.z < -1.0, "PLY-01 forward input moves along camera forward (-Z)")
	var jog_noise: float = radii.max() if not radii.is_empty() else 0.0
	radii.clear()
	InputRouter.external.set_button(&"sprint", true)
	await seconds(1.5)
	var sprint := Vector2(player.velocity.x, player.velocity.z).length()
	var sprint_noise: float = radii.max() if not radii.is_empty() else 0.0
	InputRouter.external.set_button(&"sprint", false)
	radii.clear()
	player.set_crouch(true)
	await seconds(1.5)
	var crouch := Vector2(player.velocity.x, player.velocity.z).length()
	var crouch_noise: float = radii.max() if not radii.is_empty() else 0.0
	InputRouter.external.reset()
	SoundEvents.sound_emitted.disconnect(cb)
	note("speeds jog %.2f sprint %.2f crouch %.2f; noise %.1f / %.1f / %.1f" % [jog, sprint, crouch, jog_noise, sprint_noise, crouch_noise])
	near(jog, Player.SPEED_JOG, 0.3, "PLY-02 jog speed")
	near(sprint, Player.SPEED_SPRINT, 0.4, "PLY-03 sprint speed")
	near(crouch, Player.SPEED_CROUCH, 0.3, "PLY-04 crouch speed")
	check(sprint_noise > jog_noise and jog_noise > crouch_noise and crouch_noise > 0.0, "PLY-05 noise: sprint > jog > crouch")
	await seconds(1.0)
	check(Vector2(player.velocity.x, player.velocity.z).length() < 0.2, "PLY-06 decelerates to rest (no sliding)")


func test_wall_collision() -> void:
	add_wall(world, Vector3(0, 1.5, -3), Vector3(6, 3, 0.4))
	_player(Vector3(0, 0, 0))
	InputRouter.external.set_axis(&"move_y", 1.0)
	await seconds(3.0)
	InputRouter.external.reset()
	check(player.global_position.z > -2.9, "PLY-07 player cannot pass through walls (z %.2f)" % player.global_position.z)


func test_camera_collision() -> void:
	_player(Vector3(0, 0, 0))
	await seconds(0.5)
	var free_len := player.camera_rig.arm.get_hit_length()
	add_wall(world, Vector3(0, 1.5, 1.3), Vector3(6, 3, 0.3))   # wall right behind the player
	await seconds(0.5)
	var blocked_len := player.camera_rig.arm.get_hit_length()
	note("arm length free %.2f vs blocked %.2f" % [free_len, blocked_len])
	check(blocked_len < free_len - 1.0, "PLY-08 camera pulls in instead of clipping through walls")


func test_crouch_blocked_under_low_ceiling() -> void:
	_player(Vector3(0, 0, 0))
	player.set_crouch(true)
	add_wall(world, Vector3(0, 1.45, 0), Vector3(3, 0.2, 3))
	await seconds(0.2)
	player.set_crouch(false)
	check(player.crouching, "PLY-09 cannot stand up under a low ceiling")


# ------------------------------------------------------------------ weapons

func test_weapon_fire_reload_switch() -> void:
	_player(Vector3(0, 0, 0))
	await seconds(0.3)
	var w := player.weapons
	var start_mag := w.get_current().mag
	InputRouter.external.set_button(&"fire", true)
	await frames(2)
	InputRouter.external.set_button(&"fire", false)
	await frames(2)
	eq(w.get_current().mag, start_mag - 1, "WPN-01 semi-auto fires one round per press")
	InputRouter.external.set_button(&"reload", true)
	await frames(2)
	InputRouter.external.set_button(&"reload", false)
	check(w.is_reloading(), "WPN-02 reload started")
	await seconds(w.get_data().reload_time + 0.2)
	eq(w.get_current().mag, w.get_data().magazine_size, "WPN-03 magazine refilled from reserve")
	InputRouter.external.set_button(&"weapon_2", true)
	await frames(2)
	InputRouter.external.set_button(&"weapon_2", false)
	await seconds(0.6)
	eq(w.get_data().id, &"rifle", "WPN-04 switched to rifle")
	var rmag := w.get_current().mag
	InputRouter.external.set_button(&"fire", true)
	await seconds(0.5)
	InputRouter.external.set_button(&"fire", false)
	var fired := rmag - w.get_current().mag
	note("rifle rounds in 0.5 s: %d" % fired)
	check(fired >= 3 and fired <= 6, "WPN-05 automatic fire respects fire rate (%d rounds)" % fired)
	w.select(2)
	await seconds(0.6)
	eq(w.get_data().pellets, 9, "WPN-06 shotgun fires pellets")


func test_player_shot_damages_enemy_and_headshot() -> void:
	await bake(world)
	_player(Vector3(0, 0, 0))
	await seconds(0.3)
	var e := make_enemy(world, "guard", Vector3(0, 0, -7), 180.0)
	e.perception.enabled = false
	player.camera_rig.pitch = -6.0
	await seconds(0.3)
	var hp := e.health.current
	InputRouter.external.set_button(&"aim", true)
	await seconds(0.4)
	InputRouter.external.set_button(&"fire", true)
	await frames(2)
	InputRouter.external.set_button(&"fire", false)
	await seconds(0.2)
	InputRouter.external.reset()
	check(e.health.current < hp, "WPN-07 hitscan damages enemy (hp %.0f -> %.0f)" % [hp, e.health.current])
	check(e.is_headshot(e.global_position + Vector3.UP * 1.65) and not e.is_headshot(e.global_position + Vector3.UP * 1.1), "WPN-08 headshot zone")


func test_suppressed_vs_loud_noise() -> void:
	var p := load("res://resources/weapons/suppressed_pistol.tres") as WeaponData
	var r := load("res://resources/weapons/assault_rifle.tres") as WeaponData
	var s := load("res://resources/weapons/tactical_shotgun.tres") as WeaponData
	check(p.suppressed and p.noise_radius < 10.0, "WPN-09 pistol is suppressed and quiet")
	check(r.noise_radius > 30.0 and r.automatic, "WPN-10 rifle loud and automatic")
	check(s.noise_radius > r.noise_radius and s.pellets > 1, "WPN-11 shotgun loudest, multi-pellet")


# ------------------------------------------------------------------ interaction / gadgets

func test_pickups_and_interaction() -> void:
	_player(Vector3(0, 0, 0))
	await seconds(0.2)
	player.weapons.get_current().reserve = 0
	var ammo := Pickup.new()
	ammo.kind = Pickup.Kind.AMMO
	ammo.position = Vector3(0, 0, -1.2)
	world.add_child(ammo)
	await seconds(0.3)
	eq(player.interactor.focus, ammo, "INT-01 interactor focuses the pickup in front")
	InputRouter.external.set_button(&"interact", true)
	await frames(2)
	InputRouter.external.set_button(&"interact", false)
	await frames(2)
	check(ammo.collected and player.weapons.get_current().reserve > 0, "INT-02 ammo collected")
	var key := Pickup.new()
	key.kind = Pickup.Kind.KEYCARD
	key.item_id = "blue"
	world.add_child(key)
	key.interact(player)
	check(player.has_keycard("blue"), "INT-03 keycard added")


func test_hold_interaction() -> void:
	_player(Vector3(0, 0, 0))
	var console := SecurityConsole.new()
	console.position = Vector3(0, 0, -1.6)
	console.rotation_degrees.y = 180
	console.hold_time = 1.0
	world.add_child(console)
	await seconds(0.3)
	InputRouter.external.set_button(&"interact", true)
	await seconds(0.5)
	check(not console.done, "INT-04 hold interaction not instant")
	await seconds(0.8)
	InputRouter.external.set_button(&"interact", false)
	check(console.done, "INT-05 hold interaction completes")


func test_scanner_tags_enemies_temporarily() -> void:
	await bake(world)
	_player(Vector3(0, 0, 0))
	player.set_loadout([&"pistol"], [&"scanner"])
	var near_e := make_enemy(world, "guard", Vector3(10, 0, 10), 0.0)
	var far_e := make_enemy(world, "guard", Vector3(0, 0, 28), 0.0)
	add_wall(world, Vector3(5, 1.5, 5), Vector3(0.4, 3, 6))
	await seconds(0.3)
	player.gadgets.use_selected()
	check(near_e.is_tagged(), "GAD-01 scanner tags enemies in range (even behind walls, briefly)")
	check(not far_e.is_tagged(), "GAD-02 scanner range limited")
	player.gadgets.use_selected()
	check(player.gadgets.get_selected().cooldown_left > 0.0, "GAD-03 scanner has cooldown")
	await seconds(6.5)
	check(not near_e.is_tagged(), "GAD-04 tag expires (no permanent wall vision)")


func test_disruptor_charges_and_range() -> void:
	_player(Vector3(0, 0, 0))
	player.set_loadout([&"pistol"], [&"disruptor"])
	var near_c := SecurityCamera.new()
	near_c.position = Vector3(4, 3, 0)
	world.add_child(near_c)
	var far_c := SecurityCamera.new()
	far_c.position = Vector3(25, 3, 0)
	world.add_child(far_c)
	await seconds(0.2)
	player.gadgets.use_selected()
	check(not near_c.is_operational(), "GAD-05 disruptor jams nearby camera")
	check(far_c.is_operational(), "GAD-06 disruptor range limited")
	eq(player.gadgets.get_selected().charges_left, 2, "GAD-07 disruptor consumes a charge")


func test_recon_camera_placement_rules() -> void:
	_player(Vector3(0, 0, 0))
	player.set_loadout([&"pistol"], [&"recon"])
	await seconds(0.3)
	player.camera_rig.pitch = -30.0
	await seconds(0.2)
	var ok := player.gadgets.find_recon_placement(14.0)
	check(ok["ok"], "GAD-08 valid floor placement in front")
	player.gadgets.use_selected()
	check(is_instance_valid(player.gadgets.recon_device), "GAD-09 device deployed")
	player.gadgets.use_selected()
	check(player.gadgets.recon_active, "GAD-10 enters remote view")
	player.gadgets.exit_recon()
	check(not player.gadgets.recon_active and player.camera_rig.camera.current, "GAD-11 exits back to player camera")
	player.gadgets.recall_recon()
	player.camera_rig.pitch = 5.0
	await seconds(0.2)
	var none := player.gadgets.find_recon_placement(14.0)
	check(not none["ok"], "GAD-12 no surface in range -> refused")


func test_player_death_signal() -> void:
	_player(Vector3(0, 0, 0))
	var died := [false]
	player.died.connect(func(): died[0] = true)
	player.take_damage(DamageInfo.make(500, Vector3.ZERO, Vector3.FORWARD, null))
	check(died[0] and player.is_dead(), "PLY-10 death emitted")
	check(not player.input_enabled, "PLY-11 input disabled when dead")
