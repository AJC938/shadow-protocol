extends TestCase
## SHADOW CONTROLLER V2 integration tests (tactical layout):
##   J1 X/Y = camera look velocity, J1 button = fire; J2 X/Y = strafe/forward, J2 button = interact.
## Real localhost UDP packets (as sent by the Python bridge) drive the real camera rig,
## player, weapons and interaction; game state + health are reported back over UDP.
## No Arduino hardware involved (see controller_bridge tests, firmware host tests and
## controller_bridge/fake_arduino.py for the other links of the chain).

var world: Node3D
var player: Player
var sender: PacketPeerUDP
var cb: Node
var _seq := 0


func before_each() -> void:
	cb = tree.root.get_node("ControllerBridge")
	if not cb.is_listening():
		cb.start()
	Settings.controller_look_sensitivity = 1.0
	Settings.controller_look_smoothing = 0.05
	Settings.controller_invert_y = false
	sender = PacketPeerUDP.new()
	sender.set_dest_address("127.0.0.1", cb.listen_port)
	world = await make_arena(60.0, false)
	player = make_player(world, Vector3.ZERO)
	player.place_at(Vector3.ZERO, 0.0)
	player.camera_rig.pitch = 0.0


func after_each() -> void:
	sender.put_packet("LINK,0,-".to_ascii_buffer())
	await frames(3)
	sender.close()
	await super()


func _frame(j1x := 512, j1y := 512, j2x := 512, j2y := 512, b1 := 0, b2 := 0) -> void:
	_seq += 1
	sender.put_packet(("CTRL,%d,%d,%d,%d,%d,%d,%d" % [_seq, j1x, j1y, j2x, j2y, b1, b2]).to_ascii_buffer())


## Streams one controller frame per physics frame for `secs` seconds of game time.
func _hold(secs: float, j1x := 512, j1y := 512, j2x := 512, j2y := 512, b1 := 0, b2 := 0) -> void:
	for i in int(secs * 60.0):
		_frame(j1x, j1y, j2x, j2y, b1, b2)
		await tree.physics_frame


func _speed() -> float:
	return Vector2(player.velocity.x, player.velocity.z).length()


# ------------------------------------------------------------------ mapping math

func test_axis_mapping_math() -> void:
	var cls = cb.get_script()
	eq(cls.normalize_axis(512), 0.0, "MAP-01 centre")
	eq(cls.normalize_axis(512 + 129), 0.0, "MAP-01 inside dead zone (firmware DEADZONE 130)")
	near(cls.normalize_axis(1023), 1.0, 0.001, "MAP-02 full deflection")
	var edge: float = cls.normalize_axis(512 + 140)
	check(edge > 0.0 and edge < 0.05, "MAP-03 no jump at the dead-zone edge (%.3f)" % edge)
	var mv: Vector2 = cls.movement_from_frame(PackedInt32Array([1, 0, 0, 1023, 0, 0, 0]))
	check(mv.x > 0.6 and mv.y > 0.6 and mv.length() <= 1.0001, "MAP-04 J2 right+up = strafe right + forward, normalised (%s)" % mv)
	eq(cls.movement_from_frame(PackedInt32Array([1, 0, 0, 512, 512, 0, 0])), Vector2.ZERO, "MAP-05 J1 never moves the player")
	eq(cls.look_from_frame(PackedInt32Array([1, 512, 512, 0, 0, 0, 0])), Vector2.ZERO, "MAP-06 J2 never turns the camera")
	var lk: Vector2 = cls.look_from_frame(PackedInt32Array([1, 1023, 0, 512, 512, 0, 0]))
	check(lk.x > 0.99 and lk.y > 0.99, "MAP-07 J1 right/up = look right/up (%s)" % lk)
	var half: Vector2 = cls.look_from_frame(PackedInt32Array([1, 512 + 320, 512, 512, 512, 0, 0]))
	check(half.x > 0.0 and half.x < 0.5, "MAP-08 response curve gives fine control at partial deflection (%.2f)" % half.x)


# ------------------------------------------------------------------ 1, 2, 13: camera

func test_01_j1x_camera_yaw() -> void:
	await _hold(0.2)
	var y0 := player.camera_rig.yaw
	await _hold(1.0, 1023)
	var turned := y0 - player.camera_rig.yaw
	note("yaw change after 1 s full right: %.1f deg" % turned)
	check(turned > 100.0 and turned < 170.0, "CAM-01 J1 right rotates the view right at the configured speed (%.1f deg/s)" % turned)
	var y1 := player.camera_rig.yaw
	await _hold(0.5, 0)
	check(player.camera_rig.yaw > y1 + 40.0, "CAM-01 J1 left rotates the view left")
	check(_speed() < 0.1, "CAM-01 camera stick does not move the player")


func test_02_j1y_camera_pitch_clamped() -> void:
	await _hold(0.2)
	await _hold(0.3, 512, 0)
	check(player.camera_rig.pitch > 20.0, "CAM-02 J1 up looks up (pitch %.1f)" % player.camera_rig.pitch)
	await _hold(3.0, 512, 0)
	near(player.camera_rig.pitch, CameraRig.PITCH_MAX, 0.01, "CAM-03 pitch clamped at the top")
	await _hold(4.0, 512, 1023)
	near(player.camera_rig.pitch, CameraRig.PITCH_MIN, 0.01, "CAM-03 pitch clamped at the bottom (no full rotation)")


func test_13_camera_stops_when_centred() -> void:
	await _hold(0.6, 1023, 0)
	await _hold(1.0 / 60.0)
	var yaw := player.camera_rig.yaw
	var pitch := player.camera_rig.pitch
	await _hold(1.0)
	near(player.camera_rig.yaw, yaw, 0.01, "CAM-04 yaw stops immediately at centre (no drift)")
	near(player.camera_rig.pitch, pitch, 0.01, "CAM-04 pitch stops immediately at centre")
	eq(cb.look, Vector2.ZERO, "CAM-04 look velocity zero")


func test_camera_sensitivity_and_invert_settings() -> void:
	Settings.controller_look_sensitivity = 2.0
	await _hold(0.2)
	var y0 := player.camera_rig.yaw
	await _hold(0.5, 1023)
	var fast := y0 - player.camera_rig.yaw
	Settings.controller_look_sensitivity = 0.5
	var y1 := player.camera_rig.yaw
	await _hold(0.5, 1023)
	var slow := y1 - player.camera_rig.yaw
	check(fast > slow * 3.0, "CAM-05 sensitivity setting scales look speed (%.1f vs %.1f)" % [fast, slow])
	Settings.controller_invert_y = true
	var p0 := player.camera_rig.pitch
	await _hold(0.3, 512, 0)
	check(player.camera_rig.pitch < p0, "CAM-06 invert-Y option")


# ------------------------------------------------------------------ 3, 4, 5, 14: movement

func test_03_j2y_forward_backward() -> void:
	await _hold(1.2, 512, 512, 512, 0)
	check(player.velocity.z < -3.0, "MOV-01 J2 up = forward (vz %.2f)" % player.velocity.z)
	await _hold(1.2, 512, 512, 512, 1023)
	check(player.velocity.z > 3.0, "MOV-02 J2 down = backward (vz %.2f)" % player.velocity.z)


func test_04_j2x_strafe() -> void:
	await _hold(1.2, 512, 512, 1023, 512)
	check(player.velocity.x > 3.0 and absf(player.velocity.z) < 0.5, "MOV-03 J2 right = strafe right (%s)" % player.velocity)
	await _hold(1.2, 512, 512, 0, 512)
	check(player.velocity.x < -3.0, "MOV-04 J2 left = strafe left")


func test_05_diagonal_normalised_and_analog() -> void:
	await _hold(1.2, 512, 512, 1023, 0)
	var v := player.velocity
	check(v.x > 2.0 and v.z < -2.0, "MOV-05 diagonal combines both axes (%s)" % v)
	check(_speed() <= Player.SPEED_JOG + 0.2, "MOV-06 diagonal is normalised (no faster than straight, %.2f)" % _speed())
	await _hold(1.2, 512, 512, 512, 512 - 230)
	check(_speed() > 0.3 and _speed() < Player.SPEED_JOG - 0.5, "MOV-07 partial deflection = analog speed (%.2f)" % _speed())


func test_camera_relative_movement_with_j1_turning() -> void:
	player.camera_rig.yaw = 90.0
	await _hold(1.2, 512, 512, 512, 0)
	check(player.velocity.x < -3.0, "MOV-08 J2 forward follows the camera direction (v %s)" % player.velocity)


func test_14_player_stops_when_centred() -> void:
	await _hold(1.0, 512, 512, 1023, 0)
	await _hold(0.8)
	check(_speed() < 0.15, "MOV-09 centred J2 stops the player (%.2f)" % _speed())


# ------------------------------------------------------------------ 6, 7, 8: fire

func test_06_08_fire_pistol_and_shotgun_per_press() -> void:
	var w := player.weapons
	await _hold(0.3)
	var mag := w.get_current().mag
	await _hold(1.0, 512, 512, 512, 512, 1)
	eq(w.get_current().mag, mag - 1, "FIRE-01 pistol: holding J1 fires exactly once")
	await _hold(0.2)
	await _hold(0.2, 512, 512, 512, 512, 1)
	eq(w.get_current().mag, mag - 2, "FIRE-02 pistol: release + press fires again")
	await _hold(0.3)
	w.select(2)
	await _hold(0.8)
	var smag := w.get_current().mag
	await _hold(2.0, 512, 512, 512, 512, 1)
	eq(w.get_current().mag, smag - 1, "FIRE-03 shotgun: one shot per press (held 2 s)")


func test_07_rifle_auto_and_release() -> void:
	var w := player.weapons
	w.select(1)
	await _hold(0.8)
	var rmag := w.get_current().mag
	await _hold(0.5, 512, 512, 512, 512, 1)
	var fired := rmag - w.get_current().mag
	check(fired >= 3 and fired <= 6, "FIRE-04 rifle: automatic while J1 held, at its fire rate (%d in 0.5 s)" % fired)
	await _hold(0.3)
	var after := w.get_current().mag
	await _hold(0.6)
	eq(w.get_current().mag, after, "FIRE-05 release stops automatic fire")


# ------------------------------------------------------------------ 9, 10: interact

func test_09_10_interact_press_and_hold_to_hack() -> void:
	player.weapons.get_current().reserve = 0
	var ammo := Pickup.new()
	ammo.kind = Pickup.Kind.AMMO
	ammo.position = Vector3(0, 0, -1.2)
	world.add_child(ammo)
	await _hold(0.4)
	await _hold(0.2, 512, 512, 512, 512, 0, 1)
	await _hold(0.2)
	check(ammo.collected, "INT-01 J2 press = interact (pickup)")
	var console := SecurityConsole.new()
	console.position = Vector3(0, 0, -1.6)
	console.rotation_degrees.y = 180
	console.hold_time = 1.0
	world.add_child(console)
	await _hold(0.3)
	await _hold(0.5, 512, 512, 512, 512, 0, 1)
	check(not console.done, "INT-02 hack not instant")
	await _hold(0.9, 512, 512, 512, 512, 0, 1)
	check(console.done, "INT-03 holding J2 completes hold-to-hack")


# ------------------------------------------------------------------ 11, 12: mouse + keyboard

func test_11_mouse_camera_still_works() -> void:
	await _hold(0.3)   # controller connected, centred
	var y0 := player.camera_rig.yaw
	InputRouter.native.add_mouse_motion(Vector2(250, 0))
	await _hold(2.0 / 60.0)
	check(player.camera_rig.yaw < y0 - 5.0, "KBM-01 mouse look still rotates the camera (%.1f -> %.1f)" % [y0, player.camera_rig.yaw])
	var y1 := player.camera_rig.yaw
	await _hold(0.5)
	near(player.camera_rig.yaw, y1, 0.01, "KBM-02 mouse delta applied once (no double application / drift)")


func test_12_keyboard_still_works() -> void:
	await _hold(0.3)
	Input.action_press(&"move_forward")
	await _hold(1.2)
	Input.action_release(&"move_forward")
	check(player.velocity.z < -3.0, "KBM-03 keyboard movement works with the controller connected (vz %.2f)" % player.velocity.z)
	Input.action_press(&"crouch")
	await _hold(2.0 / 60.0)
	Input.action_release(&"crouch")
	check(player.crouching, "KBM-04 keyboard-only actions (crouch) still work")


# ------------------------------------------------------------------ 15: disconnect

func test_15_disconnect_releases_everything() -> void:
	player.weapons.select(1)
	await _hold(0.8)
	var w := player.weapons
	await _hold(0.6, 1023, 512, 512, 0, 1)   # turning + moving + firing
	check(_speed() > 2.0, "DISC-01 moving before unplug")
	await seconds(0.5)                        # frames stop arriving
	check(not cb.controller_connected, "DISC-02 frame timeout detected")
	var mag := w.get_current().mag
	var yaw := player.camera_rig.yaw
	await seconds(1.0)
	check(_speed() < 0.15, "DISC-03 movement stops")
	eq(w.get_current().mag, mag, "DISC-04 fire released (no stuck trigger)")
	near(player.camera_rig.yaw, yaw, 0.01, "DISC-05 camera stops turning")
	await _hold(0.4, 512, 512, 512, 0)
	sender.put_packet("LINK,0,-".to_ascii_buffer())
	await frames(2)
	check(not cb.controller_connected, "DISC-06 bridge LINK,0 releases immediately")


# ------------------------------------------------------------------ 17-21: real game states -> bridge -> OLED

func _drain(listener: PacketPeerUDP) -> Array:
	var got := []
	while listener.get_available_packet_count() > 0:
		got.append(listener.get_packet().get_string_from_ascii())
	return got


func _wait_mission(id: String, cp: Dictionary = {}) -> MissionLevel:
	tree.root.get_node("Game").deploy(id, cp)
	for i in 600:
		await tree.process_frame
		var s := tree.current_scene
		if s is MissionLevel and (s as MissionLevel).controller and not tree.root.get_node("Game").is_transitioning():
			return s
	return null


func test_17_21_game_states_from_real_events() -> void:
	var listener := PacketPeerUDP.new()
	if not check(listener.bind(cb.bridge_port, "127.0.0.1") == OK, "STATE-00 can listen on the bridge port"):
		return
	await seconds(1.2)
	check(_drain(listener).has("SPSTATE,READY"), "STATE-01 READY outside missions")
	var level := await _wait_mission("m01")
	if not check(level != null, "STATE-02 mission loaded"):
		listener.close()
		return
	level.player.place_at(Vector3(-70, 0.1, -55), 0.0)   # far corner, away from guards
	await seconds(0.6)
	var got := _drain(listener)
	check(got.has("SPSTATE,ALIVE"), "STATE-02 ALIVE in a mission")
	check(got.has("SPHEALTH,100"), "STATE-03 health reported (%s)" % str(got.slice(-4)))
	# Invulnerable hit = no real damage = no DAMAGED event (nothing fabricated).
	level.player.health.invulnerable = true
	level.player.take_damage(DamageInfo.make(10, Vector3.ZERO, Vector3.FORWARD, null))
	await seconds(0.3)
	check(not _drain(listener).has("SPSTATE,DAMAGED"), "STATE-04 no DAMAGED without real damage")
	level.player.health.invulnerable = false
	# Real damage
	level.player.take_damage(DamageInfo.make(25, Vector3.ZERO, Vector3.FORWARD, null))
	await seconds(0.3)
	got = _drain(listener)
	check(got.has("SPSTATE,DAMAGED"), "STATE-05 DAMAGED after real damage (%s)" % str(got))
	check(got.has("SPHEALTH,75"), "STATE-06 health 75% reported")
	await seconds(cb.damaged_display_time + 0.4)
	got = _drain(listener)
	check(got.has("SPSTATE,ALIVE") and cb.current_state == "ALIVE", "STATE-07 back to ALIVE after the hit window")
	# Pause beats damage
	level.player.take_damage(DamageInfo.make(5, Vector3.ZERO, Vector3.FORWARD, null))
	tree.paused = true
	await tree.process_frame
	eq(cb.compute_game_state(), "PAUSED", "STATE-08 PAUSED outranks DAMAGED")
	await seconds(0.3)
	check(_drain(listener).has("SPSTATE,PAUSED"), "STATE-08 PAUSED sent")
	tree.paused = false
	# Death
	level.player.take_damage(DamageInfo.make(999, Vector3.ZERO, Vector3.FORWARD, null))
	await seconds(0.3)
	got = _drain(listener)
	check(got.has("SPSTATE,DEAD") and not got.has("SPSTATE,DAMAGED"), "STATE-09 DEAD after lethal damage, not DAMAGED (%s)" % str(got))
	eq(cb.compute_game_state(), "DEAD", "STATE-09 DEAD persists")
	# Respawn (the game's checkpoint restart creates a fresh player)
	tree.root.get_node("Game").restart_from_checkpoint()
	await seconds(0.5)
	level = null
	for i in 600:
		await tree.process_frame
		if tree.current_scene is MissionLevel and (tree.current_scene as MissionLevel).controller and not tree.root.get_node("Game").is_transitioning():
			level = tree.current_scene
			break
	await seconds(0.5)
	check(level != null and not level.player.is_dead(), "STATE-10 player respawned")
	got = _drain(listener)
	check(got.has("SPSTATE,ALIVE") and cb.current_state == "ALIVE", "STATE-10 ALIVE after respawn (%s)" % str(got.slice(-3)))
	# Mission complete
	level.controller.finished = true
	await seconds(0.3)
	check(_drain(listener).has("SPSTATE,MISSION_COMPLETE"), "STATE-11 MISSION_COMPLETE when the mission ends")
	level.controller.finished = false
	# No per-frame spam
	await seconds(0.1)
	_drain(listener)
	await seconds(2.0)
	var n := _drain(listener).filter(func(s): return String(s).begins_with("SPSTATE")).size()
	check(n <= 3, "STATE-12 unchanged state resent at most ~1/s, not every frame (%d in 2 s)" % n)
	listener.close()
	tree.root.get_node("Game").goto_main_menu()
	for i in 120:
		await tree.process_frame
