extends TestCase
## End-to-end mission tests in the real mission scenes: navigation on every patrol
## route, AI running in the level, scripted objective walkthroughs, extraction,
## results, campaign progression, checkpoint restore and both Voss outcomes.


func _game() -> Node:
	return tree.root.get_node("Game")


func _save() -> Node:
	return tree.root.get_node("SaveSystem")


func _load_mission(id: String, checkpoint: Dictionary = {}) -> MissionLevel:
	_game().deploy(id, checkpoint)
	for i in 600:
		await tree.process_frame
		var s := tree.current_scene
		if s is MissionLevel and (s as MissionLevel).controller != null and not _game().is_transitioning():
			await frames(5)
			return s
	failures.append("mission %s did not load" % id)
	return null


func _goto(level: MissionLevel, pos: Vector3) -> void:
	level.player.place_at(pos, 0.0)
	await frames(4)


func _use(level: MissionLevel, node_name: String) -> void:
	var n := level.devices.get_node_or_null(node_name)
	if n == null:
		n = level.geometry.get_node_or_null(node_name)
	if n == null:
		failures.append("missing interactable %s" % node_name)
		return
	(n as Interactable).interact(level.player)
	await frames(2)


func _expect_done(level: MissionLevel, ids: Array, tag: String) -> void:
	for id in ids:
		check(level.controller.is_done(StringName(id)), "%s objective %s complete" % [tag, id])


func _check_navigation(level: MissionLevel, tag: String) -> void:
	var map := level.get_world_3d().navigation_map
	await frames(2)
	var polys := level.nav_region.navigation_mesh.get_polygon_count()
	check(polys > 50, "%s NAV-01 navmesh baked (%d polygons)" % [tag, polys])
	var routes := 0
	var broken: Array[String] = []
	for n in level.enemies_root.get_children():
		var e := n as Enemy
		var pts: Array[Vector3] = e.patrol_points.duplicate()
		if pts.is_empty():
			continue
		pts.push_front(e.global_position)
		for i in pts.size() - 1:
			var a := NavigationServer3D.map_get_closest_point(map, pts[i])
			var b := NavigationServer3D.map_get_closest_point(map, pts[i + 1])
			var path := NavigationServer3D.map_get_path(map, a, b, true)
			routes += 1
			if path.is_empty() or path[path.size() - 1].distance_to(b) > 1.0 or b.distance_to(pts[i + 1]) > 1.5:
				broken.append("%s %d->%d" % [e.name, i, i + 1])
	note("%s: %d polygons, %d patrol legs, broken: %s" % [tag, polys, routes, str(broken)])
	check(broken.is_empty(), "%s NAV-02 every patrol leg has a valid path %s" % [tag, str(broken)])


func _check_ai_running(level: MissionLevel, tag: String) -> void:
	level.player.health.invulnerable = true
	level.player.hidden_in = level   # keep the player out of the fight while sampling patrols
	var start := {}
	for n in level.enemies_root.get_children():
		var e := n as Enemy
		if not e.dormant and not e.patrol_points.is_empty():
			start[e] = e.global_position
	await seconds(25.0)
	var moved := 0
	var fell := []
	var still := []
	for e in start.keys():
		if (e as Enemy).global_position.distance_to(start[e]) > 2.0:
			moved += 1
		else:
			still.append("%s(%s @%s)" % [e.name, (e as Enemy).state_name, (e as Enemy).global_position])
	for n in level.enemies_root.get_children():
		if (n as Node3D).global_position.y < -2.0:
			fell.append(n.name)
	note("%s: %d/%d patrolling enemies moved in 25 s; not moved: %s" % [tag, moved, start.size(), str(still)])
	check(moved >= int(start.size() * 0.75), "%s NAV-03 patrols move through the real level (%d/%d)" % [tag, moved, start.size()])
	check(fell.is_empty(), "%s NAV-04 no agent fell through the world %s" % [tag, str(fell)])
	level.player.hidden_in = null


# ------------------------------------------------------------------ MISSION 01

func test_m01_navigation_and_ai() -> void:
	_save().new_campaign()
	var level := await _load_mission("m01")
	if level == null:
		return
	await _check_navigation(level, "M01")
	await _check_ai_running(level, "M01")


func test_m01_full_walkthrough_and_checkpoint() -> void:
	_save().new_campaign()
	var level := await _load_mission("m01")
	if level == null:
		return
	var mc := level.controller
	level.player.health.invulnerable = true
	eq(mc.current_objective().id, &"reach_perimeter", "M01-01 first objective")
	await _goto(level, Vector3(-45, 0.1, 31))
	await _goto(level, Vector3(-23, 0.1, 4))
	await _use(level, "AdminKeycard")
	check(level.player.has_keycard("admin_card"), "M01-02 keycard taken")
	await _goto(level, Vector3(-11, 0.1, 0))
	_expect_done(level, ["reach_perimeter", "enter_checkpoint", "pass_checkpoint"], "M01-03")
	check(_save().has_checkpoint(), "M01-04 checkpoint saved on objective completion")
	# Restore from the checkpoint into a fresh scene.
	var cp: Dictionary = _save().get_checkpoint()["state"]
	level = await _load_mission("m01", cp)
	if level == null:
		return
	mc = level.controller
	await frames(5)
	_expect_done(level, ["reach_perimeter", "enter_checkpoint", "pass_checkpoint"], "M01-05 restored")
	check(level.player.global_position.distance_to(Vector3(-11, 0, 0)) < 3.0, "M01-05 player restored near checkpoint (%s)" % level.player.global_position)
	check(level.player.has_keycard("admin_card"), "M01-05 keycard restored")
	level.player.health.invulnerable = true
	var archive := level.devices.get_node("ArchiveDoor") as Door
	check(archive.locked, "M01-06 archive locked before terminal")
	await _use(level, "ControlTerminal")
	check(not archive.locked, "M01-07 terminal unlocks archive door")
	await _use(level, "IntelPackage")
	await _use(level, "Shard1")
	await _use(level, "Shard2")
	_expect_done(level, ["access_terminal", "retrieve_intel", "data_shards"], "M01-08")
	await _goto(level, Vector3(64, 0.1, 0))
	await frames(10)
	check(mc.finished, "M01-09 extraction completes the mission")
	for i in 240:
		await tree.process_frame
	check(tree.current_scene != null and tree.current_scene.scene_file_path.ends_with("results.tscn"), "M01-10 results screen shown")
	check(_save().is_completed("m01") and _save().is_unlocked("m02"), "M01-11 progression saved, m02 unlocked")
	var r: Dictionary = _game().last_results
	note("M01 results: grade %s score %d time %.0f detections %d optional %d/%d" % [r["grade"], r["score"], r["time"], r["detections"], r["optional_done"], r["optional_total"]])
	check(r["optional_done"] >= 1, "M01-12 optional objective credited")


# ------------------------------------------------------------------ MISSION 02

func test_m02_navigation_and_ai() -> void:
	_save().new_campaign()
	var level := await _load_mission("m02")
	if level == null:
		return
	await _check_navigation(level, "M02")
	await _check_ai_running(level, "M02")


func test_m02_full_walkthrough() -> void:
	_save().new_campaign()
	_save().record_mission_complete("m01", "B", 600, 1000, 0, 0, 0)
	var level := await _load_mission("m02")
	if level == null:
		return
	var mc := level.controller
	level.player.health.invulnerable = true
	await _goto(level, Vector3(0, 0.1, 12))
	await _goto(level, Vector3(27, 0.1, 5))
	_expect_done(level, ["enter_sector", "find_control"], "M02-01")
	for r in ["Relay1", "Relay2", "Relay3"]:
		await _use(level, r)
	check(mc.is_done(&"disable_relays"), "M02-02 three relays complete counted objective")
	var cams_off := 0
	for c in tree.get_nodes_in_group("security_camera"):
		if (c as SecurityCamera).disabled:
			cams_off += 1
	check(cams_off == tree.get_nodes_in_group("security_camera").size(), "M02-03 relays disable all camera networks (%d)" % cams_off)
	var roof := level.devices.get_node("RoofDoor") as Door
	check(roof.locked, "M02-04 roof locked before lockdown")
	await _use(level, "TransmissionLog")
	await _use(level, "FilesTerminal")
	check(mc.is_done(&"retrieve_files"), "M02-05 files retrieved")
	check(mc.objective_state[&"survive"]["revealed"], "M02-06 survive objective revealed")
	check(level.alarm.active, "M02-07 lockdown alarm raised")
	var active := 0
	for e in level.enemies_root.get_children():
		if String(e.name).begins_with("Response") and not (e as Enemy).dormant:
			active += 1
	eq(active, 4, "M02-08 response team deployed")
	check(mc.detections == 0, "M02-09 scripted lockdown does not count as a detection")
	level.set("_lockdown_left", 0.5)
	await seconds(1.0)
	check(mc.is_done(&"survive") and not roof.locked, "M02-10 surviving opens the roof")
	await _goto(level, Vector3(17, 4.4, -25))
	await frames(10)
	check(mc.finished, "M02-11 rooftop extraction completes the mission")
	for i in 240:
		await tree.process_frame
	check(_save().is_unlocked("m03"), "M02-12 m03 unlocked")
	var r: Dictionary = _game().last_results
	note("M02 results: grade %s optional %d/%d" % [r["grade"], r["optional_done"], r["optional_total"]])


# ------------------------------------------------------------------ MISSION 03

func test_m03_navigation_and_ai() -> void:
	_save().new_campaign()
	var level := await _load_mission("m03")
	if level == null:
		return
	await _check_navigation(level, "M03")
	await _check_ai_running(level, "M03")


func test_m03_containment_walkthrough_and_campaign_end() -> void:
	_save().new_campaign()
	_save().record_mission_complete("m01", "B", 600, 1000, 0, 0, 0)
	_save().record_mission_complete("m02", "B", 600, 1000, 0, 0, 0)
	var level := await _load_mission("m03")
	if level == null:
		return
	var mc := level.controller
	level.player.health.invulnerable = true
	await _use(level, "BlastOverride")
	check(not (level.devices.get_node("BlastDoor") as Door).locked, "M03-01 guardhouse override unlocks blast door")
	await _goto(level, Vector3(0, 0.1, 16))
	check(mc.is_done(&"enter_restricted"), "M03-02 restricted area entered")
	var front := level.devices.get_node("CommandFront") as Door
	check(front.locked, "M03-03 command sector locked before network shutdown")
	await _use(level, "LabArchive")
	await _use(level, "NetworkCore")
	check(mc.is_done(&"disable_network") and not front.locked, "M03-04 network core unlocks command sector")
	check(level.alarm.offline, "M03-05 main security network takes alarm offline")
	await _goto(level, Vector3(24, 0.1, -15))
	check(mc.is_done(&"reach_command"), "M03-06 command sector reached")
	var voss: Enemy = level.get("_voss")
	voss.global_position = Vector3(26, 0, -34)
	await frames(2)
	await _use(level, "LockdownOverride")
	check(mc.is_done(&"overcome_commander"), "M03-07 containing Voss overcomes the commander")
	check((level.devices.get_node("StrategyDoorS") as Door).locked, "M03-08 strategy room sealed")
	check(not (level.devices.get_node("VaultDoor") as Door).locked, "M03-09 vault opened")
	await _use(level, "Ledger")
	check(mc.is_done(&"retrieve_ledger"), "M03-10 ledger retrieved")
	await _goto(level, Vector3(22, 4.9, -45))
	await frames(10)
	check(mc.finished, "M03-11 helipad extraction completes the mission")
	var r: Dictionary = _game().last_results
	check(mc.is_done(&"contain_voss"), "M03-12 'contain Voss alive' optional credited")
	note("M03 results: grade %s optional %d/%d" % [r["grade"], r["optional_done"], r["optional_total"]])
	for i in 240:
		await tree.process_frame
	check(_save().is_campaign_complete(), "M03-13 campaign marked complete")
	_game().after_results()
	for i in 200:
		await tree.process_frame
	check(tree.current_scene != null and tree.current_scene.scene_file_path.ends_with("ending.tscn"), "M03-14 campaign ending sequence shown")


func test_m03_override_refused_when_voss_outside_and_kill_path() -> void:
	_save().new_campaign()
	var level := await _load_mission("m03")
	if level == null:
		return
	var mc := level.controller
	level.player.health.invulnerable = true
	var voss: Enemy = level.get("_voss")
	voss.global_position = Vector3(24, 0, -14)   # in the hall, outside the strategy room
	await frames(2)
	await _use(level, "LockdownOverride")
	check(not mc.is_done(&"overcome_commander"), "M03-15 override refused when Voss is outside the room")
	voss.take_damage(DamageInfo.make(620, voss.global_position, Vector3.FORWARD, level.player))
	await frames(3)
	check(not (level.enemies_root.get_node("PhaseGuardA") as Enemy).dormant, "M03-16 Voss calls reinforcements when wounded")
	voss.take_damage(DamageInfo.make(5000, voss.global_position, Vector3.FORWARD, level.player, true))
	await frames(3)
	check(voss.is_dead() and mc.is_done(&"overcome_commander"), "M03-17 defeating Voss overcomes the commander")
	check(mc.is_failed(&"contain_voss"), "M03-18 killing Voss fails the containment optional")
	check(not (level.devices.get_node("VaultDoor") as Door).locked, "M03-19 vault opens after Voss falls")


# ------------------------------------------------------------------ flow

func test_continue_flow_from_menu_state() -> void:
	_save().new_campaign()
	_save().record_mission_complete("m01", "A", 500, 1300, 1, 0, 0)
	_game().continue_game()
	for i in 120:
		await tree.process_frame
	check(tree.current_scene.scene_file_path.ends_with("briefing.tscn"), "FLOW-01 continue without checkpoint opens next briefing")
	eq(_game().current_mission_id, "m02", "FLOW-01 briefing for m02")
	_save().store_checkpoint("m02", {"elapsed": 33.0, "objectives": {"enter_sector": {"done": true, "count": 1, "revealed": true}}})
	_game().continue_game()
	var level: MissionLevel = null
	for i in 600:
		await tree.process_frame
		if tree.current_scene is MissionLevel and (tree.current_scene as MissionLevel).controller and not _game().is_transitioning():
			level = tree.current_scene
			break
	await frames(5)
	check(level != null and level.mission_id == "m02", "FLOW-02 continue with checkpoint deploys that mission")
	if level:
		check(level.controller.is_done(&"enter_sector"), "FLOW-03 checkpoint objectives restored")
		near(level.controller.elapsed, 33.0, 1.0, "FLOW-03 elapsed time restored")
	_game().goto_main_menu()
	for i in 120:
		await tree.process_frame
	check(tree.current_scene.scene_file_path.ends_with("main_menu.tscn"), "FLOW-04 back to main menu")
