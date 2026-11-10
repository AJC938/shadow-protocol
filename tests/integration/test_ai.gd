extends TestCase
## Integration tests for enemy perception and the AI state machine, run in a
## real physics world with a baked navmesh.

var world: Node3D
var player: Player


func before_each() -> void:
	world = await make_arena(60.0, false)


func _setup_player(pos: Vector3) -> void:
	player = make_player(world, pos)
	player.input_enabled = false


func _light_at(pos: Vector3) -> void:
	var l := OmniLight3D.new()
	l.omni_range = 8.0
	l.light_energy = 3.0
	l.add_to_group("level_light")
	world.add_child(l)
	l.global_position = pos


# ------------------------------------------------------------------ vision

func test_vision_detects_player_in_view() -> void:
	await bake(world)
	_setup_player(Vector3(0, 0, -8))
	var e := make_enemy(world, "guard", Vector3.ZERO, 0.0)
	await seconds(1.5)
	check(e.perception.player_visible, "AI-V01 player visible in front")
	check(e.perception.suspicion > 5.0, "AI-V01 suspicion accumulates (%.1f)" % e.perception.suspicion)
	await seconds(8.0)
	eq(e.state_name, &"combat", "AI-V02 full detection -> combat")
	note("suspicion after 9.5s: %.1f, state %s" % [e.perception.suspicion, e.state_name])


func test_vision_blocked_by_wall() -> void:
	add_wall(world, Vector3(0, 1.5, -4), Vector3(6, 3, 0.4))
	await bake(world)
	_setup_player(Vector3(0, 0, -8))
	var e := make_enemy(world, "guard", Vector3.ZERO, 0.0)
	await seconds(4.0)
	check(not e.perception.player_visible, "AI-V03 wall occludes vision")
	near(e.perception.suspicion, 0.0, 0.01, "AI-V03 no suspicion through wall")


func test_vision_fov_behind() -> void:
	await bake(world)
	_setup_player(Vector3(0, 0, 8))   # behind the guard
	var e := make_enemy(world, "guard", Vector3.ZERO, 0.0)
	await seconds(3.0)
	check(not e.perception.player_visible, "AI-V04 player behind is outside FOV")


func test_vision_range_limit() -> void:
	await bake(world)
	_setup_player(Vector3(0, 0, -27))
	var e := make_enemy(world, "guard", Vector3.ZERO, 0.0)
	await seconds(2.0)
	check(not e.perception.player_visible, "AI-V05 beyond vision range (22 m) not seen")


func test_light_and_stance_affect_detection() -> void:
	await bake(world)
	_setup_player(Vector3(0, 0, -10))
	_light_at(Vector3(0, 2.5, -10))
	var e := make_enemy(world, "guard", Vector3.ZERO, 0.0)
	await seconds(0.6)
	var lit_standing := e.perception.current_gain
	player.set_crouch(true)
	for l in tree.get_nodes_in_group("level_light"):
		(l as Light3D).visible = false
	await seconds(0.6)
	var dark_crouched := e.perception.current_gain
	note("gain lit/standing %.2f vs dark/crouched %.2f" % [lit_standing, dark_crouched])
	check(lit_standing > 0.0, "AI-V06 lit player detected")
	check(dark_crouched < lit_standing * 0.6, "AI-V06 darkness + crouch reduce detection rate")


# ------------------------------------------------------------------ hearing

func test_hearing_investigates_noise() -> void:
	await bake(world)
	_setup_player(Vector3(0, 0, 30))
	var e := make_enemy(world, "guard", Vector3.ZERO, 0.0)
	await seconds(0.5)
	var noise_pos := Vector3(3, 0, 6)  # behind the guard
	for i in 4:
		SoundEvents.emit_sound(noise_pos, 14.0, SoundEvent.Type.SPRINT, 1.0, player)
		await seconds(0.25)
	check(e.perception.suspicion >= Perception.SUSPICIOUS, "AI-H01 noise raises suspicion (%.1f)" % e.perception.suspicion)
	check(e.state_name in [&"suspicious", &"investigate"], "AI-H01 reacts to noise (state %s)" % e.state_name)
	check(e.stimulus_pos.distance_to(noise_pos) < 3.0, "AI-H02 estimate is near, not exact player position")
	check(e.state_name != &"combat", "AI-H03 hearing alone never confirms the player")
	await seconds(6.0)
	var d := e.global_position.distance_to(noise_pos)
	note("distance to noise after investigating: %.2f (state %s)" % [d, e.state_name])
	check(d < 4.5, "AI-H04 guard walked to investigate (dist %.1f)" % d)


func test_hearing_out_of_range_and_muffled() -> void:
	add_wall(world, Vector3(0, 1.5, 5), Vector3(8, 3, 0.4))
	await bake(world)
	_setup_player(Vector3(0, 0, 30))
	var e := make_enemy(world, "guard", Vector3.ZERO, 0.0)
	await seconds(0.3)
	SoundEvents.emit_sound(Vector3(0, 0, 13), 10.0, SoundEvent.Type.FOOTSTEP, 1.0, player)
	await seconds(0.2)
	near(e.perception.suspicion, 0.0, 0.01, "AI-H05 sound outside radius not heard")
	# 7 m away behind a wall with a 10 m radius: muffled radius 5.5 m -> not heard
	SoundEvents.emit_sound(Vector3(0, 0, 7), 10.0, SoundEvent.Type.FOOTSTEP, 1.0, player)
	await seconds(0.2)
	near(e.perception.suspicion, 0.0, 0.01, "AI-H06 wall muffles sound")


func test_gunshot_triggers_alert_and_search() -> void:
	await bake(world)
	_setup_player(Vector3(0, 0, 40))
	var e := make_enemy(world, "guard", Vector3.ZERO, 0.0)
	await seconds(0.3)
	SoundEvents.emit_sound(Vector3(8, 0, 8), 40.0, SoundEvent.Type.GUNSHOT, 1.0, player)
	await seconds(0.3)
	eq(e.state_name, &"alert", "AI-H07 gunshot -> alert")
	await seconds(10.0)
	eq(e.state_name, &"search", "AI-S01 alert reaches position -> search")


# ------------------------------------------------------------------ states

func test_patrol_follows_route() -> void:
	await bake(world)
	_setup_player(Vector3(0, 0, 50) if false else Vector3(25, 0, 25))
	player.visible = false
	player.hidden_in = world   # make the player unseen for this test
	var e := make_enemy(world, "guard", Vector3(-10, 0, 0), 0.0, [Vector3(-10, 0, 0), Vector3(10, 0, 0)])
	await seconds(1.0)
	eq(e.state_name, &"patrol", "AI-P01 patrol state")
	await seconds(14.0)
	var reached := e.global_position.distance_to(Vector3(10, 0, 0)) < 2.0 or e.patrol_index != 0
	check(reached, "AI-P02 patrol progressed (pos %s idx %d)" % [e.global_position, e.patrol_index])
	player.hidden_in = null


func test_combat_shoots_player_and_reports() -> void:
	await bake(world)
	_setup_player(Vector3(0, 0, -6))
	_light_at(Vector3(0, 2.5, -6))
	var e := make_enemy(world, "guard", Vector3.ZERO, 0.0)
	var ally := make_enemy(world, "guard", Vector3(12, 0, 6), 180.0)
	await seconds(6.0)
	eq(e.state_name, &"combat", "AI-C01 combat")
	await seconds(5.0)
	check(player.health.current < 100.0, "AI-C02 enemy fire damages player (hp %.0f)" % player.health.current)
	check(ally.state_name in [&"alert", &"search", &"combat"], "AI-C03 nearby ally alerted (state %s)" % ally.state_name)


func test_lost_contact_leads_to_search_then_return() -> void:
	await bake(world)
	_setup_player(Vector3(0, 0, -6))
	_light_at(Vector3(0, 2.5, -6))
	var e := make_enemy(world, "guard", Vector3.ZERO, 0.0, [Vector3(0, 0, 0), Vector3(0, 0, 10)])
	await seconds(7.0)
	eq(e.state_name, &"combat", "AI-S02 combat first")
	# Player vanishes (teleport far away behind a wall).
	add_wall(world, Vector3(0, 1.5, -26), Vector3(30, 3, 0.5))
	player.place_at(Vector3(0, 0, -29), 0)
	player.health.invulnerable = true
	await seconds(12.0)
	eq(e.state_name, &"search", "AI-S03 lost contact -> search")
	await seconds(34.0)
	check(e.state_name in [&"return", &"patrol"], "AI-S04 search ends -> return to patrol (state %s)" % e.state_name)
	check(e.alerted_once, "AI-S05 stays more aware afterwards")


func test_specialist_raises_alarm() -> void:
	await bake(world)
	var alarm := AlarmSystem.new()
	world.add_child(alarm)
	var panel := AlarmPanel.new()
	panel.position = Vector3(8, 0, 4)
	world.add_child(panel)
	_setup_player(Vector3(0, 0, -6))
	_light_at(Vector3(0, 2.5, -6))
	player.health.invulnerable = true
	var s := make_enemy(world, "specialist", Vector3.ZERO, 0.0)
	await seconds(14.0)
	check(alarm.active, "AI-SP01 specialist ran to the panel and raised the alarm")
	panel.sabotaged = true
	alarm.clear_alarm()
	check(not panel.can_be_triggered(), "AI-SP02 sabotaged panel cannot be used")


func test_heavy_pushes_toward_player() -> void:
	await bake(world)
	_setup_player(Vector3(0, 0, -18))
	_light_at(Vector3(0, 2.5, -18))
	player.health.invulnerable = true
	var h := make_enemy(world, "heavy", Vector3.ZERO, 0.0)
	await seconds(10.0)
	var d := h.global_position.distance_to(player.global_position)
	note("heavy distance after 10 s: %.1f (state %s)" % [d, h.state_name])
	eq(h.state_name, &"combat", "AI-HV01 heavy engaged")
	check(d < 14.0, "AI-HV02 heavy advances on the player")
	check(h.health.armor > 0.3 and h.health.max_health > 250.0, "AI-HV03 heavy durability")


func test_body_discovery_alerts() -> void:
	await bake(world)
	_setup_player(Vector3(0, 0, 40))
	player.hidden_in = world
	var victim := make_enemy(world, "guard", Vector3(0, 0, -8), 0.0)
	var e := make_enemy(world, "guard", Vector3.ZERO, 0.0)
	await seconds(0.5)
	victim.take_damage(DamageInfo.make(500, victim.global_position, Vector3.FORWARD, player, true))
	await seconds(2.0)
	check(e.state_name in [&"alert", &"search"], "AI-B01 seeing a body alerts (state %s)" % e.state_name)
	player.hidden_in = null
