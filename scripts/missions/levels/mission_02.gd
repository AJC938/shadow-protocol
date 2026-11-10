extends MissionLevel
## MISSION 02 — BLACK SIGNAL
## Communications sector: service yard, loading bay, maintenance room with a crawl
## duct, main corridor, security control room (relay 1), comms hall (relay 2),
## server hall (files), stair office (relay 3), rooftop extraction. North = -Z.
## Downloading the files triggers a scripted lockdown with reinforcements.

const LOCKDOWN_TIME := 90.0

var _relays: Array[SecurityConsole] = []
var _files: SecurityConsole
var _reinforcements: Array[Enemy] = []
var _lockdown_left: float = -1.0
var _last_announce: int = 0


func configure_environment(e: EnvironmentController) -> void:
	e.sky_energy = 0.6
	e.ambient_energy = 0.55
	e.fog_density = 0.004
	e.volumetric_density = 0.01


func get_player_start() -> Array:
	return [Vector3(0, 0.1, 30), 0.0]


func get_ambient_light() -> float:
	return 0.14


func get_ambience() -> StringName:
	return &"amb_industrial_hum"


func build_level() -> void:
	var b := builder
	# ---------------------------------------------------------------- service yard
	b.floor_rect(-44, 14, 44, 38, 0.0, "asphalt", "concrete")
	b.wall(Vector2(-42, 36), Vector2(42, 36), 0.0, 3.6, "wall_exterior", 0.5)
	b.wall(Vector2(-42, 14), Vector2(-42, 36), 0.0, 3.6, "wall_exterior", 0.5)
	b.wall(Vector2(42, 14), Vector2(42, 36), 0.0, 3.6, "wall_exterior", 0.5)
	_container(Vector3(-28, 0, 24), 90, "navy")
	_container(Vector3(-20, 0, 29), 0, "olive")
	_container(Vector3(22, 0, 25), 0, "rust")
	_container(Vector3(31, 0, 30), 90, "olive")
	b.cover_block(Vector3(-6, 0, 20), Vector3(3.2, 1.1, 0.8), "wall_exterior", 0)
	b.cover_block(Vector3(8, 0, 21), Vector3(3.2, 1.1, 0.8), "wall_exterior", 15)
	b.crate_stack(Vector3(14, 0, 17), 0)
	b.prop("portable_generator", Vector3(-12, 0, 16.5), 0, 1.2, true, true)
	b.prop("Barrel_01", Vector3(4, 0, 16.3), 0, 1.0, true)
	b.prop("barrel_03", Vector3(4.8, 0, 16.7), 0, 1.0, true)

	# ---------------------------------------------------------------- building shell
	var H := 4.0
	b.floor_rect(-36, -36, 36, 14, 0.02, "floor_concrete", "concrete")
	b.wall(Vector2(-36, 14), Vector2(36, 14), 0.0, H, "wall_exterior", 0.4,
		[{"at": 12.0, "w": 5.0, "top": 3.6}, {"at": 46.0, "w": 1.2, "top": 1.3}, {"at": 69.0, "w": 1.6, "top": 2.6}])
	b.wall(Vector2(-36, -36), Vector2(36, -36), 0.0, H, "wall_exterior", 0.4)
	b.wall(Vector2(-36, -36), Vector2(-36, 14), 0.0, H, "wall_exterior", 0.4)
	b.wall(Vector2(36, -36), Vector2(36, 14), 0.0, H, "wall_exterior", 0.4)
	b.box(Vector3(-24, 3.8, 14.0), Vector3(5.2, 0.4, 0.5), "shutter", false)
	# Roof slab with the stairwell opening (x 31.6..36, z -21..-11)
	b.ceiling_rect(-36.2, -36.2, 36.2, -21, H)
	b.ceiling_rect(-36.2, -11, 36.2, 14.2, H)
	b.ceiling_rect(-36.2, -21, 31.6, -11, H)
	# Interior walls
	b.wall(Vector2(-36, -4), Vector2(36, -4), 0.0, H, "wall_interior", 0.25,
		[{"at": 12.0, "w": 3.0, "top": 3.0}, {"at": 33.0, "w": 1.4, "top": 2.5}, {"at": 46.0, "w": 1.2, "top": 1.3}, {"at": 63.0, "w": 1.6, "top": 2.6}])
	b.wall(Vector2(-36, -10), Vector2(36, -10), 0.0, H, "wall_interior", 0.25,
		[{"at": 12.0, "w": 2.0, "top": 2.6}, {"at": 30.0, "w": 1.8, "top": 2.6}, {"at": 46.0, "w": 1.8, "top": 2.6}, {"at": 60.0, "w": 1.6, "top": 2.6}])
	b.wall(Vector2(-12, -4), Vector2(-12, 14), 0.0, H, "wall_olive", 0.25, [{"at": 9.0, "w": 1.4, "top": 2.5}])
	b.wall(Vector2(18, -4), Vector2(18, 14), 0.0, H, "wall_navy", 0.25,
		[{"at": 9.0, "w": 2.4, "bottom": 1.0, "top": 2.3, "glass": true}])
	b.wall(Vector2(-12, -36), Vector2(-12, -10), 0.0, H, "wall_interior", 0.25, [{"at": 20.0, "w": 2.6, "bottom": 1.0, "top": 2.3, "glass": true}])
	b.wall(Vector2(18, -36), Vector2(18, -10), 0.0, H, "wall_navy", 0.25, [{"at": 6.0, "w": 1.4, "top": 2.5}])
	# Stair cage
	b.wall(Vector2(31.6, -25), Vector2(31.6, -11), 0.0, H, "wall_interior", 0.2)
	b.wall(Vector2(31.6, -25), Vector2(36, -25), 0.0, H, "wall_interior", 0.2)
	b.wall(Vector2(31.6, -11), Vector2(36, -11), 0.0, H, "wall_interior", 0.2, [{"at": 2.2, "w": 1.4, "top": 2.5}])
	b.stairs(Vector3(33.8, 0.0, -12.2), Vector3(0, 0, -1), 1.8, H + 0.25, 8.6)
	# Room accent floors
	b.floor_rect(18.2, -3.8, 35.8, 13.8, 0.04, "tile", "tile")
	b.floor_rect(-11.8, -35.8, 17.8, -10.2, 0.04, "metal_floor", "metal")
	b.floor_rect(-35.8, -9.8, 35.8, -4.2, 0.04, "floor_dark", "concrete")

	# ---------------------------------------------------------------- crawl duct (maintenance room)
	b.box(Vector3(9.35, 0.65, 5.0), Vector3(0.12, 1.3, 18.0), "trim_steel", true, "metal")
	b.box(Vector3(10.65, 0.65, 5.0), Vector3(0.12, 1.3, 18.0), "trim_steel", true, "metal")
	b.box(Vector3(10.0, 1.37, 5.0), Vector3(1.42, 0.14, 18.0), "trim_steel", true, "metal")
	b.box(Vector3(10.0, 0.06, 5.0), Vector3(1.2, 0.04, 18.0), "grate", false, "grate")
	b.box(Vector3(10.0, 0.75, 15.6), Vector3(1.6, 1.5, 0.2), "trim_dark", false)
	b.ceiling_light(Vector3(10.0, 1.25, 5.0), "strip", Color(0.6, 0.8, 1.0), 0.25, 3.0)

	# ---------------------------------------------------------------- loading bay
	b.crate_stack(Vector3(-30, 0, 9), 0)
	b.crate_stack(Vector3(-20, 0, 6), 90)
	b.crate_stack(Vector3(-27, 0, 2), 10, 3)
	b.prop("industrial_storage_cart", Vector3(-16, 0, 11), 45, 1.2, true, true)
	b.prop("metal_tool_chest", Vector3(-35.4, 0, 4), 90, 1.2, true)
	b.prop("propane_tank", Vector3(-35.2, 0, 12), 0, 1.2, true)
	for x in [-30.0, -18.0]:
		b.ceiling_light(Vector3(x, 3.95, 5.0), "industrial", Color(1.0, 0.78, 0.5), 2.4, 11.0, x == -30.0)
	# ---------------------------------------------------------------- maintenance
	b.prop("metal_tool_chest", Vector3(-10.8, 0, -2.5), 90, 1.2, true)
	b.prop("portable_generator", Vector3(2, 0, 12.8), 0, 1.2, true, true)
	b.prop("power_box_01", Vector3(-1, 1.4, 13.7), 180, 1.5, false)
	b.prop("modular_industrial_pipes_01", Vector3(4, 2.6, 13.75), 0, 1.4, false)
	b.ceiling_light(Vector3(-2, 3.95, 5.0), "fluorescent", Color(0.85, 0.92, 1.0), 1.3, 8.0)
	# ---------------------------------------------------------------- control room
	for i in 3:
		_console_bank(Vector3(21.5 + i * 4.5, 0, -2.6), 180)
	b.prop("metal_office_desk", Vector3(32, 0, 4), -90, 1.0, true, true)
	b.prop("vintage_radio_transceiver", Vector3(32, 0.79, 4), -90, 1.0, false)
	b.ceiling_light(Vector3(23, 3.95, 5), "fluorescent", Color(0.8, 0.9, 1.0), 1.2, 8.0)
	b.ceiling_light(Vector3(31, 3.95, 5), "fluorescent", Color(0.8, 0.9, 1.0), 1.2, 8.0)
	# ---------------------------------------------------------------- corridor
	for x in range(-32, 33, 8):
		b.ceiling_light(Vector3(x, 3.95, -7), "strip", Color(0.75, 0.88, 1.0), 1.1, 7.5)
	b.prop("metal_trash_can", Vector3(-6, 0, -9.4), 0, 1.0, true, true)
	b.prop("cardboard_box_01", Vector3(14, 0, -4.6), 0, 1.4, true)
	b.alarm_light(Vector3(-20, 3.8, -7))
	b.alarm_light(Vector3(4, 3.8, -7))
	b.alarm_light(Vector3(28, 3.8, -7))
	# ---------------------------------------------------------------- comms hall
	for p in [Vector3(-28, 0, -25), Vector3(-20, 0, -19)]:
		_antenna(p)
	b.prop("metal_office_desk", Vector3(-16, 0, -33.5), 0, 1.0, true, true)
	b.prop("vintage_radio_transceiver", Vector3(-16.6, 0.79, -33.6), 10, 1.0, false)
	b.crate_stack(Vector3(-32, 0, -32), 0)
	b.ceiling_light(Vector3(-24, 3.95, -16), "industrial", Color(1.0, 0.75, 0.45), 2.2, 11.0)
	b.ceiling_light(Vector3(-24, 3.95, -30), "industrial", Color(1.0, 0.75, 0.45), 2.2, 11.0, true)
	b.alarm_light(Vector3(-24, 3.8, -23))
	# ---------------------------------------------------------------- server hall
	for row_z in [-31.0, -24.0, -17.0]:
		for x in [-9.0, -6.6, -4.2, 3.0, 5.4, 7.8, 13.0, 15.4]:
			_server_rack(Vector3(x, 0, row_z), 0)
	for z in [-27.5, -20.5, -13.5]:
		b.ceiling_light(Vector3(3, 3.95, z), "strip", Color(0.5, 0.75, 1.0), 1.2, 9.0, z == -20.5)
	# ---------------------------------------------------------------- stair office
	b.prop("metal_office_desk", Vector3(24, 0, -33.6), 0, 1.0, true, true)
	b.prop("steel_frame_shelves_01", Vector3(29.5, 0, -35.1), 0, 0.11, true)
	b.prop("cardboard_box_01", Vector3(20, 0, -14), 30, 1.4, true)
	b.crate_stack(Vector3(26, 0, -17), 90)
	b.ceiling_light(Vector3(25, 3.95, -28), "fluorescent", Color(0.8, 0.9, 1.0), 1.2, 9.0)
	b.ceiling_light(Vector3(33.8, 3.95, -23.5), "strip", Color(1.0, 0.8, 0.5), 1.0, 6.0)

	# ---------------------------------------------------------------- roof
	var R := H + 0.25
	for seg in [[Vector2(-36, -36), Vector2(36, -36)], [Vector2(-36, 14), Vector2(36, 14)], [Vector2(-36, -36), Vector2(-36, 14)], [Vector2(36, -36), Vector2(36, 14)]]:
		b.wall(seg[0], seg[1], R, 1.1, "wall_exterior", 0.4)
	b.railing(Vector3(31.6, R, -21), Vector3(31.6, R, -11))
	b.railing(Vector3(31.6, R, -11), Vector3(35.8, R, -11))
	b.box(Vector3(17, R + 0.03, -25), Vector3(12, 0.04, 12), "trim_dark", false)
	b.box(Vector3(17, R + 0.05, -25), Vector3(1.0, 0.03, 7), "trim_amber", false)
	b.box(Vector3(17, R + 0.05, -25), Vector3(5, 0.03, 1.0), "trim_amber", false)
	for c in [Vector3(11.2, 0, -30.8), Vector3(22.8, 0, -30.8), Vector3(11.2, 0, -19.2), Vector3(22.8, 0, -19.2)]:
		b.box(c + Vector3(0, R + 0.1, 0), Vector3(0.25, 0.15, 0.25), "emissive_green", false)
	for p in [Vector3(-25, R, 0), Vector3(-15, R, -26), Vector3(0, R, 6), Vector3(28, R, 5)]:
		b.prop("exterior_aircon_unit", p, 0, 1.5, true, true)
	b.omni(Vector3(17, R + 3.0, -25), Color(0.6, 0.8, 1.0), 1.0, 12.0)
	# ---------------------------------------------------------------- yard lighting
	b.flood_light(Vector3(-24, 3.9, 14.4), Vector3(-24, 0, 24), Color(1.0, 0.85, 0.6), 6.0, 22.0, 45.0)
	b.flood_light(Vector3(26, 3.9, 14.4), Vector3(26, 0, 24), Color(1.0, 0.85, 0.6), 6.0, 22.0, 45.0)
	b.prop("street_lamp_01", Vector3(0, 0, 33), 180, 1.45, true)
	b.spot(Vector3(0, 5.6, 32), Vector3(0, 0, 28), Color(1.0, 0.72, 0.42), 3.5, 14.0, 50.0, false)


func _container(pos: Vector3, yaw: float, tint: String) -> void:
	var key := "container_" + tint
	if not builder._mats.has(key):
		var base := builder.mat("corrugated").duplicate() as StandardMaterial3D
		base.albedo_color = {"olive": Color(0.36, 0.42, 0.28), "navy": Color(0.2, 0.27, 0.4), "rust": Color(0.55, 0.3, 0.2)}[tint]
		builder._mats[key] = base
	var size := Vector3(6.1, 2.6, 2.44)
	builder.box(pos + Vector3.UP * 1.3, size, key, true, "metal", yaw)
	builder.add_cover_points(pos + Vector3.UP * 1.3, size, yaw, true)


func _server_rack(pos: Vector3, yaw: float) -> void:
	builder.box(pos + Vector3(0, 1.1, 0), Vector3(0.6, 2.2, 1.0), "trim_dark", true, "metal", yaw)
	var led_mat := "emissive_blue" if int(pos.x * 7.0 + pos.z) % 3 != 0 else "emissive_green"
	for i in 5:
		builder.box(pos + Vector3(0, 0.4 + i * 0.38, 0.505), Vector3(0.42, 0.025, 0.01), led_mat, false)
		builder.box(pos + Vector3(0, 0.4 + i * 0.38, -0.505), Vector3(0.42, 0.025, 0.01), led_mat, false)
	builder.add_cover_points(pos + Vector3(0, 1.1, 0), Vector3(0.6, 2.2, 1.0), yaw, true)


func _antenna(pos: Vector3) -> void:
	builder.box(pos + Vector3(0, 0.3, 0), Vector3(2.0, 0.6, 2.0), "trim_steel", true, "metal")
	builder.box(pos + Vector3(0, 2.1, 0), Vector3(0.25, 3.6, 0.25), "trim_steel", false)
	for h in [1.6, 2.6, 3.4]:
		builder.box(pos + Vector3(0, h, 0), Vector3(1.6, 0.05, 0.05), "trim_steel", false)
		builder.box(pos + Vector3(0, h, 0), Vector3(0.05, 0.05, 1.6), "trim_steel", false)
	builder.box(pos + Vector3(0, 3.92, 0), Vector3(0.12, 0.12, 0.12), "emissive_red", false)
	builder.add_cover_points(pos + Vector3(0, 0.3, 0), Vector3(2.0, 0.6, 2.0), 0.0, false)
	var l := builder.omni(pos + Vector3(0, 3.6, 0), Color(1.0, 0.2, 0.15), 0.6, 4.0)
	l.remove_from_group("level_light")


func _console_bank(pos: Vector3, yaw: float) -> void:
	builder.box(pos + Vector3(0, 0.45, 0), Vector3(3.6, 0.9, 0.8), "trim_dark", true, "metal", yaw)
	builder.box(pos + Vector3(0, 1.25, 0.2), Vector3(3.4, 0.7, 0.08), "trim_dark", false, "metal", yaw)
	builder.box(pos + Vector3(0, 1.25, 0.15), Vector3(3.2, 0.55, 0.02), "emissive_blue", false, "metal", yaw)


func place_devices() -> void:
	add_door(Vector3(33, 0, 14), 0, {"name": "PersonnelDoor"})
	add_door(Vector3(-12, 0, 5), 90, {"width": 1.4, "height": 2.5, "name": "BayMaintDoor"})
	add_door(Vector3(-3, 0, -4), 0, {"width": 1.4, "height": 2.5, "name": "MaintCorrDoor"})
	add_door(Vector3(27, 0, -4), 0, {"name": "ControlDoor"})
	add_door(Vector3(-24, 0, -10), 0, {"width": 2.0, "name": "CommsDoor"})
	add_door(Vector3(-6, 0, -10), 0, {"width": 1.8, "name": "ServerDoorW"})
	add_door(Vector3(10, 0, -10), 0, {"width": 1.8, "name": "ServerDoorE"})
	add_door(Vector3(24, 0, -10), 0, {"name": "StairOfficeDoor"})
	add_door(Vector3(18, 0, -30), 90, {"width": 1.4, "height": 2.5, "name": "ServerStairDoor"})
	add_door(Vector3(33.8, 0, -11), 0, {"width": 1.4, "height": 2.5, "lock": Door.Lock.CONSOLE, "id": "roof_access", "enemy_access": false, "name": "RoofDoor"})
	_relays.append(add_console(Vector3(24, 0, 13.3), 0, {"prompt": "Disable surveillance relay", "hold": 2.5, "cameras": "sector,yard", "name": "Relay1"}))
	_relays.append(add_console(Vector3(-35.3, 0, -24), -90, {"prompt": "Disable surveillance relay", "hold": 2.5, "cameras": "comms", "name": "Relay2"}))
	_relays.append(add_console(Vector3(20, 0, -35.3), 180, {"prompt": "Disable surveillance relay", "hold": 2.5, "cameras": "servers,stair", "name": "Relay3"}))
	_files = add_console(Vector3(3, 0, -35.3), 180, {"prompt": "Download communication files", "hold": 4.0, "objective": &"retrieve_files",
		"name": "FilesTerminal", "noise": 4.0})
	_files.screen_color = Color(1.0, 0.6, 0.2)
	add_pickup(Pickup.Kind.INTEL, Vector3(-15.5, 0.79, -33.5), {"id": "transmission_log", "label": "encrypted transmission log",
		"objective": &"transmission_log", "hold": 1.5, "name": "TransmissionLog"})
	add_pickup(Pickup.Kind.AMMO, Vector3(-34.5, 0, 0), {"amount": 0.5, "name": "AmmoBay"})
	add_pickup(Pickup.Kind.AMMO, Vector3(16.5, 0, -12), {"amount": 0.5, "name": "AmmoServer"})
	add_pickup(Pickup.Kind.AMMO, Vector3(34.5, 0, -30), {"amount": 0.6, "name": "AmmoStair"})
	add_pickup(Pickup.Kind.MEDKIT, Vector3(-10, 0, 12.5), {"amount": 0.6, "name": "MedMaint"})
	add_pickup(Pickup.Kind.MEDKIT, Vector3(34.5, 0, 12.5), {"amount": 0.6, "name": "MedControl"})
	add_hiding_spot(Vector3(-11.4, 0, 1), -90)
	add_hiding_spot(Vector3(-11.4, 0, 2), -90)
	add_hiding_spot(Vector3(-35.4, 0, -12), -90)
	add_hiding_spot(Vector3(17.4, 0, -33), 90)
	add_alarm_panel(Vector3(0, 0, -9.85), 180, "PanelCorridor")
	add_alarm_panel(Vector3(-35.8, 0, -16), -90, "PanelComms")
	add_alarm_panel(Vector3(-12.15, 0, 10.5), 90, "PanelBay")
	add_camera(Vector3(0, 3.6, 14.35), 180, "yard", {"name": "CamYard", "sweep": 90.0, "range": 19.0})
	add_camera(Vector3(-13.0, 3.5, 13.5), 63, "sector", {"name": "CamBay"})
	add_camera(Vector3(-35.5, 3.5, -7.0), -90, "sector", {"name": "CamCorrW", "sweep": 30.0, "tilt": -14.0, "range": 22.0})
	add_camera(Vector3(35.5, 3.5, -7.0), 90, "sector", {"name": "CamCorrE", "sweep": 30.0, "tilt": -14.0, "range": 22.0})
	add_camera(Vector3(-12.6, 3.5, -11.0), 43, "comms", {"name": "CamComms"})
	add_camera(Vector3(-11.5, 3.5, -35.4), -135, "servers", {"name": "CamServerA"})
	add_camera(Vector3(17.5, 3.5, -10.6), 45, "servers", {"name": "CamServerB"})
	add_camera(Vector3(35.4, 3.5, -35.4), 135, "stair", {"name": "CamStair"})
	add_zone(Vector3(3, 0, -23), Vector3(29, 4, 25), "Server Hall — Restricted")
	add_zone(Vector3(27, 0, 5), Vector3(17, 4, 17), "Security Control — Restricted")
	add_trigger(Vector3(0, 0, 12), Vector3(72, 4, 3.2), ObjectiveTrigger.Mode.COMPLETE, &"enter_sector", {"name": "TrigSector",
		"message": "You're in. The control room is on the east side of the sector. Watch for specialists. Blue visors, long range radios.", "voice": &"vo_m02_sector"})
	add_trigger(Vector3(27, 0, 5), Vector3(16, 4, 16), ObjectiveTrigger.Mode.COMPLETE, &"find_control", {"name": "TrigControl",
		"message": "Security control room. Their relay grid runs through here. Take three relays offline. One is in this room, the other two are out on the sector network.", "voice": &"vo_m02_control"})
	add_trigger(Vector3(17, 4.25, -25), Vector3(10, 4, 10), ObjectiveTrigger.Mode.EXTRACT, &"extract", {"name": "Extraction"})


func spawn_enemies() -> void:
	spawn_enemy("guard", Vector3(-15, 0, 22), 90, [Vector3(-15, 0, 22), Vector3(26, 0, 21)], "YardGuard", {"loop": false, "wait": 3.0})
	spawn_enemy("guard", Vector3(-32, 0, 8), 0, [Vector3(-32, 0, 8), Vector3(-16, 0, 8), Vector3(-16, 0, 0), Vector3(-32, 0, -1)], "BayGuard")
	spawn_enemy("specialist", Vector3(-24, 0, -1.5), 180, [], "BaySpecialist")
	spawn_enemy("specialist", Vector3(-32, 0, -7), -90, [Vector3(-32, 0, -7), Vector3(32, 0, -7)], "CorridorSpecialist", {"loop": false, "wait": 4.0})
	spawn_enemy("guard", Vector3(30, 0, 7), 180, [], "ControlOperator")
	spawn_enemy("guard", Vector3(-32, 0, -14), 0, [Vector3(-32, 0, -14), Vector3(-15, 0, -14), Vector3(-15, 0, -32), Vector3(-30, 0, -32)], "CommsGuard")
	spawn_enemy("specialist", Vector3(-17, 0, -26), -90, [], "CommsSpecialist")
	spawn_enemy("guard", Vector3(-10, 0, -20.5), -90, [Vector3(-10, 0, -20.5), Vector3(16, 0, -20.5)], "ServerGuardA", {"loop": false, "wait": 3.0})
	spawn_enemy("guard", Vector3(16, 0, -27.5), 90, [Vector3(16, 0, -27.5), Vector3(-10, 0, -27.5)], "ServerGuardB", {"loop": false, "wait": 3.5})
	spawn_enemy("guard", Vector3(26, 0, -21), 90, [], "StairGuard")
	_reinforcements.append(spawn_enemy("heavy", Vector3(-28, 0, 10), 180, [], "ResponseHeavyA", {"dormant": true}))
	_reinforcements.append(spawn_enemy("heavy", Vector3(32, 0, -7), 90, [], "ResponseHeavyB", {"dormant": true}))
	_reinforcements.append(spawn_enemy("guard", Vector3(-26, 0, 4), 0, [], "ResponseGuardA", {"dormant": true}))
	_reinforcements.append(spawn_enemy("specialist", Vector3(26, 0, 2), 0, [], "ResponseSpecB", {"dormant": true}))


func post_setup() -> void:
	controller.set_objective_target(&"enter_sector", Vector3(10, 0, 14))
	controller.set_objective_target(&"find_control", Vector3(27, 0, -4))
	controller.set_objective_target(&"retrieve_files", _files)
	controller.set_objective_target(&"extract", Vector3(33.8, 0, -11))
	for r in _relays:
		r.hacked.connect(_on_relay_hacked)
	_files.hacked.connect(_start_lockdown.bind(LOCKDOWN_TIME))
	devices.get_node("TransmissionLog").used.connect(func(_b): radio(&"vo_m02_log", "That's the encrypted transmission log. Good find. The buyers' keys are in there."))


func _on_relay_hacked() -> void:
	controller.progress_objective(&"disable_relays")
	_update_relay_target()
	if controller.is_done(&"disable_relays"):
		radio(&"vo_m02_relays_done", "Relays are down. Their camera grid is half blind. The server hall is north. Get me those files.")


func _update_relay_target() -> void:
	for r in _relays:
		if not r.done:
			controller.set_objective_target(&"disable_relays", r)
			return


func _start_lockdown(duration: float) -> void:
	if not controller.is_failed(&"undetected_files") and controller.detections == 0:
		controller.complete_objective(&"undetected_files")
	controller.reveal_objective(&"survive")
	controller.ignore_alarm_detection = true
	alarm.set_offline(false)
	alarm.reset_after = 99999.0
	alarm.raise_alarm(Vector3(3, 0, -12), "lockdown")
	for e in _reinforcements:
		if is_instance_valid(e) and e.dormant:
			e.activate_reinforcement(Vector3(3, 0, -12))
	_lockdown_left = duration
	_last_announce = int(duration)
	AudioManager.play_voice(&"vo_m02_files", "ORACLE", "Download started, and there it is. They've locked down the sector. Hold out until the uplink completes. Ninety seconds.", true)


func _process(delta: float) -> void:
	if _lockdown_left < 0.0 or controller == null or controller.failed:
		return
	_lockdown_left -= delta
	var secs := int(ceil(_lockdown_left))
	if secs % 15 == 0 and secs != _last_announce and secs > 0:
		_last_announce = secs
		controller.mission_message.emit("Uplink: %d seconds remaining" % secs, "warning")
	if _lockdown_left <= 0.0:
		_end_lockdown()


func _end_lockdown() -> void:
	_lockdown_left = -1.0
	controller.complete_objective(&"survive")
	for n in devices.get_children():
		if n is Door and (n as Door).door_id == "roof_access":
			(n as Door).unlock()
			(n as Door).set_open(true)
	alarm.reset_after = 25.0
	controller.ignore_alarm_detection = false
	controller.set_objective_target(&"extract", Vector3(17, 4.25, -25))
	radio(&"vo_m02_survive_done", "Uplink complete. The lockdown is lifting on the roof stairwell. Get up there.")


func get_level_state() -> Dictionary:
	return {"lockdown_left": _lockdown_left}


func apply_level_state(s: Dictionary) -> void:
	if controller.is_done(&"retrieve_files") and not controller.is_done(&"survive"):
		var left := float(s.get("lockdown_left", -1.0))
		_start_lockdown(left if left > 5.0 else LOCKDOWN_TIME)
	_update_relay_target()


func on_mission_start() -> void:
	_update_relay_target()
	radio(&"vo_m02_start", "GHOST, you're at the service entrance of the communications sector. Cameras everywhere in there. Find the security control room first.")


func capture_points() -> Array:
	return [
		["yard", Vector3(-10, 6, 34), Vector3(4, 0, 14)],
		["corridor", Vector3(-34, 1.7, -7), Vector3(10, 1.4, -7)],
		["server_hall", Vector3(-10.5, 3.0, -12), Vector3(8, 0.8, -30)],
		["comms_hall", Vector3(-14, 3.0, -12), Vector3(-28, 1.0, -28)],
		["control_room", Vector3(20, 2.2, 12), Vector3(30, 1.0, -2)],
		["duct", Vector3(10, 0.8, 12.5), Vector3(10, 0.6, -2)],
		["roof", Vector3(2, 12, 5), Vector3(17, 4, -25)],
	]
