extends MissionLevel
## MISSION 01 — SILENT ENTRY
## Outer sector of Kestrel Ridge: approach, perimeter wall (gate + breach), checkpoint,
## inner fence (gate / cut hole), warehouse with catwalk, container yard, admin block
## (control terminal + archive), loading yard extraction. North = -Z.

var _terminal: SecurityConsole


func configure_environment(e: EnvironmentController) -> void:
	e.sky_energy = 0.7
	e.ambient_energy = 1.0
	e.fog_density = 0.004
	e.volumetric_density = 0.008


func get_player_start() -> Array:
	return [Vector3(-63, 0.1, 31), -90.0]


func get_ambient_light() -> float:
	return 0.16


func get_ambience() -> StringName:
	return &"amb_night_wind"


func build_level() -> void:
	var b := builder
	# ---------------------------------------------------------------- ground
	b.floor_rect(-78, -64, 74, 64, 0.0, "gravel", "gravel")
	b.floor_rect(-20, -58, 70, 58, 0.02, "asphalt", "concrete")
	b.floor_rect(-78, -4, 70, 4, 0.04, "asphalt", "concrete")
	for x in range(-70, 66, 6):  # road centre markings
		b.box(Vector3(x, 0.045, 0), Vector3(2.5, 0.01, 0.15), "trim_amber", false)
	# Boundary of the playable space (outer fence line, approach side)
	b.fence(Vector2(-76, -62), Vector2(-76, 62), 0.0, 3.2)
	b.fence(Vector2(-76, -62), Vector2(-45, -62), 0.0, 3.2)
	b.fence(Vector2(-76, 62), Vector2(-45, 62), 0.0, 3.2)
	# ---------------------------------------------------------------- outer perimeter wall
	b.wall(Vector2(-45, -58), Vector2(-45, 58), 0.0, 3.4, "wall_exterior", 0.5,
		[{"at": 58.0, "w": 8.0, "top": 3.4}, {"at": 89.25, "w": 2.6, "top": 3.4}])
	b.wall(Vector2(-45, -58), Vector2(70, -58), 0.0, 3.4, "wall_exterior", 0.5)
	b.wall(Vector2(-45, 58), Vector2(70, 58), 0.0, 3.4, "wall_exterior", 0.5)
	b.wall(Vector2(70, -58), Vector2(70, 58), 0.0, 3.4, "wall_exterior", 0.5, [{"at": 58.0, "w": 8.0, "top": 3.4}])
	for z in range(-56, 58, 8):  # wall pillars for rhythm
		if absf(z) > 5 and absf(z - 31) > 3:
			b.pillar(Vector3(-45, 0, z), Vector2(0.8, 0.8), 3.7, "wall_exterior")
	# Breach rubble
	b.box(Vector3(-44.2, 0.35, 29.4), Vector3(1.4, 0.7, 1.0), "wall_exterior", true, "concrete", 25)
	b.box(Vector3(-46.0, 0.25, 33.4), Vector3(1.1, 0.5, 1.2), "wall_exterior", true, "concrete", -15)
	b.box(Vector3(-47.0, 0.15, 30.8), Vector3(0.7, 0.3, 0.6), "wall_exterior", false, "concrete", 40)
	# Approach cover
	b.cover_block(Vector3(-58, 0, 22), Vector3(3.2, 1.1, 0.8), "wall_exterior", 10)
	b.cover_block(Vector3(-55, 0, 38), Vector3(3.2, 1.1, 0.8), "wall_exterior", -20)
	b.cover_block(Vector3(-60, 0, -8), Vector3(3.2, 1.1, 0.8), "wall_exterior", 0)
	b.prop("concrete_road_barrier", Vector3(-52, 0, -6.5), 0, 1.3, true, true, "concrete")
	b.prop("concrete_road_barrier", Vector3(-52, 0, 6.5), 0, 1.3, true, true, "concrete")
	b.prop("Barrel_01", Vector3(-50, 0, 26), 0, 1.0, true, true)
	b.prop("barrel_03", Vector3(-50.8, 0, 26.6), 30, 1.0, true)
	b.prop("old_military_compressor", Vector3(-56, 0, 46), 70, 1.2, true, true)
	_shed(Vector3(-64, 0, -30))

	# ---------------------------------------------------------------- perimeter yard (between walls)
	b.box(Vector3(-30, 0.6, -52), Vector3(0.8, 1.2, 0.8), "trim_dark", true, "metal")
	b.prop("portable_searchlight", Vector3(-30, 1.3, -52), 160, 4.0, false)
	b.spot(Vector3(-30, 2.2, -51.5), Vector3(-34, 0, -30), Color(0.85, 0.9, 1.0), 4.0, 30.0, 18.0, false)
	b.crate_stack(Vector3(-32, 0, 22), 15)
	b.crate_stack(Vector3(-36, 0, -24), -10, 1)
	b.prop("propane_tank", Vector3(-26, 0, 44), 0, 1.2, true, true)
	b.prop("utility_box_01", Vector3(-44.6, 0, 18), 90, 1.2, true)

	# ---------------------------------------------------------------- inner fence + checkpoint
	b.fence(Vector2(-20, -58), Vector2(-20, -41.2), 0.0, 3.0)
	b.fence(Vector2(-20, -39.6), Vector2(-20, -4.5), 0.0, 3.0)
	b.fence(Vector2(-20, 4.5), Vector2(-20, 6.0), 0.0, 3.0)
	b.fence(Vector2(-20, 14.0), Vector2(-20, 58), 0.0, 3.0)
	b.box(Vector3(-20, 1.2, -40.4), Vector3(0.05, 0.05, 1.6), "trim_steel", false)  # cut fence edge
	# Barrier arm + booth posts at the road gate
	b.box(Vector3(-20, 1.05, -2.2), Vector3(0.25, 0.25, 4.0), "trim_red", false)
	b.box(Vector3(-20, 0.5, -4.4), Vector3(0.4, 1.0, 0.4), "trim_amber", true, "metal")
	b.room(-24, 6, -16, 14, 0.0, 3.2, "wall_olive", "tile",
		{"n": [{"at": 4.0, "w": 3.0, "bottom": 1.0, "top": 2.2, "glass": true}],
		 "w": [{"at": 4.0, "w": 1.4, "top": 2.4}], "e": [{"at": 4.0, "w": 1.4, "top": 2.4}]}, [], true, "tile")
	b.box(Vector3(-20, 3.35, 10), Vector3(8.8, 0.2, 8.8), "trim_dark", false)
	b.prop("metal_office_desk", Vector3(-20, 0, 7.4), 180, 1.0, true)
	b.prop("vintage_radio_transceiver", Vector3(-21.0, 0.78, 7.3), 170, 1.0, false)
	b.prop("metal_trash_can", Vector3(-23.3, 0, 7.0), 0, 1.0, true)
	b.ceiling_light(Vector3(-20, 3.15, 10), "fluorescent", Color(0.85, 0.92, 1.0), 1.6, 7.0)

	# ---------------------------------------------------------------- warehouse
	b.room(-2, -48, 26, -18, 0.0, 9.0, "corrugated", "floor_concrete",
		{"s": [{"at": 8.0, "w": 6.0, "top": 5.0}], "w": [{"at": 18.0, "w": 1.6, "top": 2.6}],
		 "e": [{"at": 24.0, "w": 1.6, "top": 2.6}]}, [], true)
	b.box(Vector3(6, 7.0, -18.05), Vector3(6.2, 4.0, 0.12), "shutter", false)
	for x in range(0, 26, 6):
		b.pillar(Vector3(x, 0, -18.4), Vector2(0.35, 0.35), 9.0, "trim_dark")
	# shelving rows (high cover)
	for row_z in [-40.0, -34.0, -28.0]:
		for x in [3.0, 7.0, 11.0, 15.0, 19.0]:
			if row_z == -28.0 and x == 11.0:
				continue
			b.prop("steel_frame_shelves_01", Vector3(x, 0, row_z), 0, 0.18, true, true)
	b.crate_stack(Vector3(3, 0, -22.5), 5)
	b.crate_stack(Vector3(17, 0, -22), -12)
	b.prop("industrial_storage_cart", Vector3(10.5, 0, -24.5), 30, 1.2, true, true)
	b.prop("cardboard_box_01", Vector3(21.5, 0, -24), 10, 1.5, true)
	b.prop("metal_tool_chest", Vector3(24.8, 0, -36), -90, 1.2, true, true)
	b.prop("portable_generator", Vector3(0.5, 0, -45), 90, 1.2, true, true)
	# catwalk + stairs
	b.floor_rect(-1.8, -47.8, 25.8, -45.0, 4.0, "grate", "grate", 0.15)
	for x in range(0, 26, 4):
		b.box(Vector3(x, 1.95, -45.2), Vector3(0.15, 3.9, 0.15), "trim_dark", true, "metal")
	b.railing(Vector3(-1.8, 4.0, -45.0), Vector3(23.6, 4.0, -45.0))
	b.stairs(Vector3(24.6, 0.0, -39.5), Vector3(0, 0, -1), 1.5, 4.0, 5.5)
	b.railing(Vector3(23.8, 0.0, -39.5), Vector3(23.8, 4.0, -45.0))
	for x in [3.0, 10.0, 17.0, 23.0]:
		for z in [-40.0, -27.0]:
			b.ceiling_light(Vector3(x, 8.7, z), "industrial", Color(1.0, 0.78, 0.5), 2.6, 13.0, x == 10.0)

	# ---------------------------------------------------------------- container yard (south of road)
	_container(Vector3(3, 0, 14), 0, "olive")
	_container(Vector3(11, 0, 14), 0, "navy")
	_container(Vector3(4, 0, 24), 90, "rust")
	_container(Vector3(16, 0, 25), 0, "olive", true)
	_container(Vector3(26, 0, 24), 90, "navy")
	_container(Vector3(1, 0, 35), 0, "rust")
	_container(Vector3(11, 0, 36), 0, "olive")
	_container(Vector3(11, 2.6, 36), 0, "navy")
	b.cover_block(Vector3(-6, 0, 10), Vector3(3.2, 1.1, 0.8), "wall_exterior", 90)
	b.prop("Barrel_01", Vector3(22, 0, 11), 0, 1.0, true, true)
	b.prop("Barrel_01", Vector3(22.8, 0, 11.5), 0, 1.0, true)
	b.prop("metal_jerrycan_green", Vector3(21.6, 0, 12.3), 40, 1.0, false)

	# ---------------------------------------------------------------- admin block
	b.room(32, 8, 54, 28, 0.0, 3.6, "wall_exterior", "tile",
		{"n": [{"at": 4.0, "w": 1.6, "top": 2.6}, {"at": 11.5, "w": 2.2, "bottom": 1.0, "top": 2.3, "glass": true},
			   {"at": 18.5, "w": 2.2, "bottom": 1.0, "top": 2.3, "glass": true}],
		 "e": [{"at": 10.25, "w": 1.4, "top": 2.6}],
		 "w": [{"at": 6.0, "w": 2.0, "bottom": 1.0, "top": 2.3, "glass": true}],
		 "s": [{"at": 6.0, "w": 2.0, "bottom": 1.0, "top": 2.3, "glass": true}]}, [], true, "tile")
	b.box(Vector3(43, 3.75, 18), Vector3(22.6, 0.3, 20.6), "trim_dark", false)
	# interior walls
	b.wall(Vector2(32, 17), Vector2(54, 17), 0.0, 3.6, "wall_interior", 0.2,
		[{"at": 4.0, "w": 1.2, "top": 2.4}, {"at": 11.5, "w": 1.2, "top": 2.4}, {"at": 18.5, "w": 1.2, "top": 2.4}])
	b.wall(Vector2(32, 19.5), Vector2(54, 19.5), 0.0, 3.6, "wall_interior", 0.2,
		[{"at": 5.5, "w": 1.2, "top": 2.4}, {"at": 16.5, "w": 1.2, "top": 2.4}])
	b.wall(Vector2(40, 8), Vector2(40, 17), 0.0, 3.6, "wall_interior", 0.2)
	b.wall(Vector2(47, 8), Vector2(47, 17), 0.0, 3.6, "wall_interior", 0.2)
	b.wall(Vector2(43, 19.5), Vector2(43, 28), 0.0, 3.6, "wall_interior", 0.2)
	# furniture
	b.prop("metal_office_desk", Vector3(36.5, 0, 11), 0, 1.0, true, true)
	b.prop("metal_office_desk", Vector3(43.5, 0, 13.5), 90, 1.0, true, true)
	b.prop("classic_laptop", Vector3(43.5, 0.78, 13.5), 90, 1.0, false)
	b.prop("steel_frame_shelves_01", Vector3(45.6, 0, 9.0), 0, 0.11, true)
	b.prop("metal_office_desk", Vector3(51, 0, 26.6), 0, 1.0, true)
	b.prop("steel_frame_shelves_01", Vector3(44.5, 0, 27.2), 0, 0.11, true)
	b.prop("steel_frame_shelves_01", Vector3(53.2, 0, 22.5), 90, 0.11, true)
	b.prop("cardboard_box_01", Vector3(45.5, 0, 21.0), 20, 1.2, true)
	b.prop("metal_trash_can", Vector3(33, 0, 16.4), 0, 1.0, true)
	for x in [36.0, 43.5, 50.5]:
		b.ceiling_light(Vector3(x, 3.5, 12.5), "fluorescent", Color(0.82, 0.9, 1.0), 1.4, 7.0)
	for x in [36.0, 48.0]:
		b.ceiling_light(Vector3(x, 3.5, 23.5), "fluorescent", Color(0.82, 0.9, 1.0), 1.2, 7.0)
	b.ceiling_light(Vector3(37, 3.5, 18.25), "strip", Color(0.82, 0.9, 1.0), 1.0, 6.0)
	b.ceiling_light(Vector3(49, 3.5, 18.25), "strip", Color(0.82, 0.9, 1.0), 1.0, 6.0)
	b.alarm_light(Vector3(43, 3.4, 18.25))

	# ---------------------------------------------------------------- loading yard + dock
	b.floor_rect(58, -32, 69.7, -12, 1.2, "floor_dark", "concrete", 1.2)
	b.box(Vector3(58.05, 0.6, -22), Vector3(0.1, 1.2, 20), "trim_amber", false)
	b.stairs(Vector3(54.0, 0.0, -14.5), Vector3(1, 0, 0), 2.0, 1.2, 4.0, "floor_dark")
	b.crate_stack(Vector3(64, 1.2, -28), 0)
	b.crate_stack(Vector3(61, 1.2, -24), 90)
	b.prop("exterior_aircon_unit", Vector3(69.0, 1.2, -18), -90, 1.3, true)
	_truck(Vector3(63, 0, 14), 90)
	b.cover_block(Vector3(56, 0, -4.8), Vector3(3.0, 1.1, 0.8), "wall_exterior", 0)
	b.cover_block(Vector3(56, 0, 4.8), Vector3(3.0, 1.1, 0.8), "wall_exterior", 0)

	# ---------------------------------------------------------------- lighting
	b.flood_light(Vector3(-16.6, 3.6, 5.7), Vector3(-26, 0, 0), Color(1.0, 0.85, 0.62), 7.0, 28.0, 40.0)
	b.box(Vector3(-24, 2.6, -6.4), Vector3(0.2, 5.2, 0.2), "trim_steel", true, "metal")
	b.flood_light(Vector3(-24, 5.3, -6.0), Vector3(-19, 0, 0), Color(1.0, 0.85, 0.62), 6.0, 24.0, 42.0)
	b.flood_light(Vector3(6, 6.2, -17.6), Vector3(6, 0, -6), Color(1.0, 0.82, 0.58), 6.5, 22.0, 45.0)
	b.flood_light(Vector3(31.7, 4.0, 22), Vector3(16, 0, 24), Color(0.8, 0.88, 1.0), 4.5, 24.0, 40.0)
	b.flood_light(Vector3(64, 5.0, -31.6), Vector3(62, 0, -18), Color(1.0, 0.82, 0.58), 5.0, 22.0, 45.0)
	for x in [-8.0, 20.0, 46.0]:
		b.prop("street_lamp_01", Vector3(x, 0, -5.6), 0, 1.45, true)
		b.spot(Vector3(x, 5.6, -4.6), Vector3(x, 0, -2.0), Color(1.0, 0.72, 0.42), 4.0, 14.0, 50.0, true)
	b.alarm_light(Vector3(25.6, 6.0, -18.0))
	b.alarm_light(Vector3(-16.0, 3.0, 14.2))


func _container(pos: Vector3, yaw: float, tint: String, open_end: bool = false) -> void:
	var m := "corrugated"
	if not builder._mats.has("container_" + tint):
		var base := builder.mat("corrugated").duplicate() as StandardMaterial3D
		match tint:
			"olive": base.albedo_color = Color(0.36, 0.42, 0.28)
			"navy": base.albedo_color = Color(0.2, 0.27, 0.4)
			"rust": base.albedo_color = Color(0.55, 0.3, 0.2)
		builder._mats["container_" + tint] = base
	m = "container_" + tint
	var size := Vector3(6.1, 2.6, 2.44)
	if not open_end:
		builder.box(pos + Vector3.UP * 1.3, size, m, true, "metal", yaw)
		builder.add_cover_points(pos + Vector3.UP * 1.3, size, yaw, true)
	else:
		var basis := Basis(Vector3.UP, deg_to_rad(yaw))
		builder.box(pos + basis * Vector3(0, 1.3, -1.17), Vector3(6.1, 2.6, 0.1), m, true, "metal", yaw)
		builder.box(pos + basis * Vector3(0, 1.3, 1.17), Vector3(6.1, 2.6, 0.1), m, true, "metal", yaw)
		builder.box(pos + basis * Vector3(0, 2.55, 0), Vector3(6.1, 0.1, 2.44), m, true, "metal", yaw)
		builder.box(pos + basis * Vector3(-3.0, 1.3, 0), Vector3(0.1, 2.6, 2.44), m, true, "metal", yaw)
		builder.box(pos + basis * Vector3(0, 0.05, 0), Vector3(6.1, 0.1, 2.44), "metal_floor", true, "metal", yaw)


func _truck(pos: Vector3, yaw: float) -> void:
	var basis := Basis(Vector3.UP, deg_to_rad(yaw))
	builder.box(pos + basis * Vector3(0, 2.0, 1.5), Vector3(2.5, 2.8, 8.0), "container_navy" if builder._mats.has("container_navy") else "corrugated", true, "metal", yaw)
	builder.box(pos + basis * Vector3(0, 1.4, -4.0), Vector3(2.4, 2.2, 2.4), "trim_olive", true, "metal", yaw)
	builder.box(pos + basis * Vector3(0, 2.0, -5.15), Vector3(2.0, 0.8, 0.05), "glass", false, "glass", yaw)
	for z in [-4.0, -1.0, 3.5]:
		for x in [-1.2, 1.2]:
			builder.box(pos + basis * Vector3(x, 0.45, z), Vector3(0.35, 0.9, 0.9), "rubber", false, "metal", yaw)
	builder.add_cover_points(pos + Vector3.UP * 1.5, Vector3(2.6, 3, 10.5), yaw, true)


func _shed(pos: Vector3) -> void:
	builder.room(pos.x - 3, pos.z - 2.5, pos.x + 3, pos.z + 2.5, 0.0, 2.6, "corrugated", "floor_dark",
		{"e": [{"at": 2.5, "w": 1.4, "top": 2.2}]}, [], true)
	builder.prop("metal_toolbox", pos + Vector3(-2, 0, -1.6), 0, 1.0, false)


func place_devices() -> void:
	# Checkpoint building
	add_door(Vector3(-24, 0, 10), 90, {"width": 1.4, "height": 2.4, "name": "CheckpointDoorW"})
	add_door(Vector3(-16, 0, 10), 90, {"width": 1.4, "height": 2.4, "name": "CheckpointDoorE"})
	add_pickup(Pickup.Kind.KEYCARD, Vector3(-19.4, 0.79, 7.3), {"id": "admin_card", "label": "admin keycard", "name": "AdminKeycard"})
	add_pickup(Pickup.Kind.MEDKIT, Vector3(-23.2, 0.0, 13.2), {"amount": 0.6, "name": "MedkitCheckpoint"})
	add_hiding_spot(Vector3(-16.6, 0, 13.4), 90)
	# Warehouse
	add_door(Vector3(-2, 0, -30), 90, {"name": "WarehouseDoorW"})
	add_door(Vector3(26, 0, -24), 90, {"name": "WarehouseDoorE"})
	add_pickup(Pickup.Kind.INTEL, Vector3(4, 4.0, -46.6), {"id": "shard_1", "label": "data shard", "name": "Shard1", "hold": 1.0,
		"model": "res://assets/models/polyhaven/circuit_board/circuit_board_1k.gltf"})
	add_pickup(Pickup.Kind.AMMO, Vector3(20, 0, -46.4), {"amount": 0.5, "name": "AmmoWarehouse"})
	add_hiding_spot(Vector3(25.4, 0, -44), 90)
	# Container yard: shard in the open container
	add_pickup(Pickup.Kind.INTEL, Vector3(14.0, 0.1, 25), {"id": "shard_2", "label": "data shard", "name": "Shard2", "hold": 1.0,
		"model": "res://assets/models/polyhaven/circuit_board/circuit_board_1k.gltf"})
	# Admin block
	add_door(Vector3(36, 0, 8), 0, {"lock": Door.Lock.KEYCARD, "keycard": "admin_card", "id": "admin_front", "name": "AdminFront"})
	add_door(Vector3(54, 0, 18.25), 90, {"width": 1.4, "name": "AdminBack"})
	add_door(Vector3(50.5, 0, 17), 0, {"width": 1.2, "height": 2.4, "name": "ControlRoomDoor"})
	add_door(Vector3(48.5, 0, 19.5), 0, {"width": 1.2, "height": 2.4, "lock": Door.Lock.CONSOLE, "id": "archive", "enemy_access": false, "name": "ArchiveDoor"})
	add_door(Vector3(37.5, 0, 19.5), 0, {"width": 1.2, "height": 2.4, "name": "BreakRoomDoor"})
	_terminal = add_console(Vector3(51, 0, 8.6), 180, {"prompt": "Access control terminal", "hold": 3.0, "objective": &"access_terminal",
		"doors": ["archive"], "name": "ControlTerminal",
		"story": "Terminal is ours. The archive door just unlocked — the package is in the south-east office.", "voice": &"vo_m01_terminal"})
	add_pickup(Pickup.Kind.INTEL, Vector3(51, 0.79, 26.6), {"id": "package_1", "label": "intelligence package", "objective": &"retrieve_intel",
		"hold": 2.0, "name": "IntelPackage"})
	add_alarm_panel(Vector3(43.5, 0, 8.25), 180, "AdminAlarmPanel")
	add_hiding_spot(Vector3(33, 0, 27.4), 0)
	add_pickup(Pickup.Kind.AMMO, Vector3(56.5, 0, -9.5), {"amount": 0.5, "name": "AmmoYard"})
	add_zone(Vector3(43, 0, 18), Vector3(22, 4, 20), "Admin Block — Restricted")
	# Cameras
	add_camera(Vector3(-16.3, 3.0, 6.3), 60, "gate", {"name": "CamGate", "sweep": 60.0})
	add_camera(Vector3(26.3, 5.0, -17.7), -135, "yard", {"name": "CamYard", "sweep": 80.0, "range": 20.0})
	add_camera(Vector3(53.5, 3.0, 18.25), 90, "admin", {"name": "CamAdmin", "sweep": 40.0, "tilt": -18.0})
	# Objective triggers
	add_trigger(Vector3(-45, 0, 0), Vector3(6, 4, 116), ObjectiveTrigger.Mode.COMPLETE, &"reach_perimeter", {"name": "TrigPerimeter",
		"message": "You're at the wall. The checkpoint sits on the inner fence, south of the main road.", "voice": &"vo_m01_perimeter"})
	add_trigger(Vector3(-23, 0, 4), Vector3(12, 4, 22), ObjectiveTrigger.Mode.COMPLETE, &"enter_checkpoint", {"name": "TrigCheckpoint",
		"message": "The checkpoint guard keeps an admin keycard on his desk. Lift it and the front door is yours.", "voice": &"vo_m01_checkpoint"})
	var inside_trig := add_trigger(Vector3(-12, 0, 0), Vector3(10, 4, 116), ObjectiveTrigger.Mode.COMPLETE, &"pass_checkpoint", {"name": "TrigInside",
		"message": "You're inside the fence. Admin block is east, past the warehouse and the container yard.", "voice": &"vo_m01_inside"})
	inside_trig.triggered.connect(func():
		if controller.detections == 0:
			controller.complete_objective(&"undetected_checkpoint"))
	add_trigger(Vector3(64, 0, 0), Vector3(8, 4, 8), ObjectiveTrigger.Mode.EXTRACT, &"extract", {"name": "Extraction"})


func spawn_enemies() -> void:
	# Perimeter yard
	spawn_enemy("guard", Vector3(-35, 0, -38), 180, [Vector3(-35, 0, -38), Vector3(-35, 0, 40)], "PerimeterGuard", {"loop": false, "wait": 4.0})
	spawn_enemy("guard", Vector3(-23, 0, -6.5), 90, [], "GateGuard")
	spawn_enemy("guard", Vector3(-20.5, 0, 9.2), 0, [], "CheckpointGuard")
	# Warehouse
	spawn_enemy("guard", Vector3(-6, 0, -14), 0, [Vector3(-6, 0, -14), Vector3(30, 0, -14), Vector3(30, 0, -52), Vector3(-6, 0, -52)], "WarehouseOuter", {"wait": 2.0})
	spawn_enemy("guard", Vector3(4, 0, -37), 0, [Vector3(4, 0, -37), Vector3(21, 0, -37), Vector3(21, 0, -31), Vector3(4, 0, -31)], "WarehouseInner", {"wait": 3.0})
	# Container yard
	spawn_enemy("guard", Vector3(-1, 0, 19), 0, [Vector3(-1, 0, 19.2), Vector3(29, 0, 19.2), Vector3(29, 0, 30), Vector3(-1, 0, 30)], "YardPatrol", {"wait": 2.5})
	# Admin
	spawn_enemy("guard", Vector3(34, 0, 18.25), -90, [Vector3(33.6, 0, 18.25), Vector3(52.4, 0, 18.25)], "AdminCorridor", {"loop": false, "wait": 3.5})
	spawn_enemy("guard", Vector3(36, 0, 5.4), 0, [], "AdminFrontGuard")
	# Loading yard
	spawn_enemy("guard", Vector3(57, 0, -26), 0, [Vector3(57, 0, -26), Vector3(57, 0, 26)], "LoadingPatrol", {"loop": false, "wait": 3.0})
	spawn_enemy("guard", Vector3(62, 1.2, -16), 90, [], "DockGuard")


func post_setup() -> void:
	controller.set_objective_target(&"reach_perimeter", Vector3(-45, 0, 31))
	controller.set_objective_target(&"enter_checkpoint", Vector3(-24.5, 0, 10))
	controller.set_objective_target(&"pass_checkpoint", Vector3(-12, 0, 10))
	controller.set_objective_target(&"access_terminal", _terminal)
	controller.set_objective_target(&"retrieve_intel", devices.get_node("IntelPackage"))
	controller.set_objective_target(&"extract", Vector3(64, 0, 0))
	alarm.raised.connect(func(_o, _r): controller.fail_optional(&"no_alarm"))
	controller.objective_completed.connect(func(id, _opt):
		if id == &"retrieve_intel":
			radio(&"vo_m01_intel", "Package secured. Extraction is the east gate, past the loading yard. Go."))
	for n in devices.get_children():
		if n is Pickup and String((n as Pickup).item_id).begins_with("shard_"):
			(n as Pickup).used.connect(func(_by): controller.progress_objective(&"data_shards"))
	# Completing extraction with no alarms satisfies the optional objective.
	controller.before_finish.connect(func():
		if alarm.times_raised == 0:
			controller.complete_objective(&"no_alarm", true))


func on_mission_start() -> void:
	radio(&"vo_m01_start", "GHOST, ORACLE. You're on the ground west of Kestrel Ridge. There's a breach in the perimeter wall to your east — or take your chances at the main gate.")


## Development screenshots (capture tool): [name, camera position, look target].
func capture_points() -> Array:
	return [
		["player_side", Vector3(-60.5, 1.4, 33.0), Vector3(-63, 1.0, 31)],
		["guard_close", Vector3(-20.5, 1.5, 7.0), Vector3(-20.5, 1.1, 9.2)],
		["gate", Vector3(-56, 9, 18), Vector3(-22, 0, 2)],
		["warehouse_in", Vector3(1, 3.2, -20), Vector3(15, 1.5, -40)],
		["yard", Vector3(-4, 8, 42), Vector3(18, 0, 16)],
		["admin_corridor", Vector3(33.2, 1.7, 18.25), Vector3(52, 1.4, 18.25)],
		["aerial", Vector3(-10, 90, 75), Vector3(0, 0, 0)],
	]
