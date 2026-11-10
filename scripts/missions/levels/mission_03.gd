extends MissionLevel
## MISSION 03 — FINAL EXTRACTION
## Outer courtyard (guardhouse override / culvert crawl) -> blast doors -> inner
## courtyard -> research lab (network core) -> command building: hall, gallery with
## lockdown override, strategy room (Commander Voss), anteroom, vault (ledger),
## stairwell -> rooftop helipad. North = -Z.

const STRATEGY_ROOM := Rect2(18.3, -39.7, 15.4, 19.4)   # x, z, w, d

var _voss: Enemy
var _voss_contained: bool = false
var _voss_phase: int = 0
var _phase_reinforcements: Array[Enemy] = []
var _roof_team: Array[Enemy] = []
var _core: SecurityConsole
var _override: SecurityConsole
var _ledger: Pickup


func configure_environment(e: EnvironmentController) -> void:
	e.sky_energy = 0.65
	e.ambient_energy = 0.75
	e.fog_density = 0.005
	e.volumetric_density = 0.012
	e.fog_color = Color(0.1, 0.1, 0.14)


func get_player_start() -> Array:
	return [Vector3(0, 0.1, 43), 0.0]


func get_ambient_light() -> float:
	return 0.16


func get_ambience() -> StringName:
	return &"amb_night_wind"


func build_level() -> void:
	var b := builder
	# ================================================================ ground + outer walls
	b.floor_rect(-62, -62, 62, 50, 0.0, "gravel", "gravel")
	b.floor_rect(-40, -10, 40, 46, 0.02, "asphalt", "concrete")
	b.floor_rect(-10, -52, 8, -10, 0.02, "asphalt", "concrete")
	for seg in [[Vector2(-40, 46), Vector2(40, 46)], [Vector2(-40, -10), Vector2(-40, 46)], [Vector2(40, -10), Vector2(40, 46)]]:
		b.wall(seg[0], seg[1], 0.0, 4.0, "wall_exterior", 0.6)
	b.wall(Vector2(-10, -52), Vector2(8, -52), 0.0, 4.0, "wall_exterior", 0.6)
	# Blast wall (z = 20): blast door at x 0 (5 m), culvert crawl at x 30
	b.wall(Vector2(-40, 20), Vector2(40, 20), 0.0, 5.0, "wall_exterior", 0.8,
		[{"at": 40.0, "w": 5.2, "top": 4.6}, {"at": 70.0, "w": 1.4, "top": 1.35}])
	b.box(Vector3(0, 4.85, 20), Vector3(6.4, 0.3, 1.2), "trim_amber", false)
	b.box(Vector3(30, 0.08, 20), Vector3(1.4, 0.06, 2.0), "grate", false, "grate")
	for x in [-36.0, -24.0, -12.0, 12.0, 24.0, 36.0]:
		b.pillar(Vector3(x, 0, 20), Vector2(1.2, 1.2), 5.4, "wall_exterior")

	# ================================================================ outer courtyard (start)
	b.room(-22, 24, -12, 32, 0.0, 3.2, "wall_olive", "tile",
		{"e": [{"at": 4.0, "w": 1.4, "top": 2.4}], "n": [{"at": 5.0, "w": 3.0, "bottom": 1.0, "top": 2.2, "glass": true}]}, [], true, "tile")
	b.box(Vector3(-17, 3.35, 28), Vector3(10.8, 0.2, 8.8), "trim_dark", false)
	b.ceiling_light(Vector3(-17, 3.15, 28), "fluorescent", Color(0.85, 0.92, 1.0), 1.4, 7.0)
	b.truck(Vector3(-28, 0, 38), 90)
	b.truck(Vector3(22, 0, 36), -80)
	b.container(Vector3(32, 0, 27), 0, "navy")
	b.container(Vector3(-32, 0, 25), 90, "olive")
	for p in [Vector3(-6, 0, 30), Vector3(7, 0, 29), Vector3(-3, 0, 24), Vector3(14, 0, 25)]:
		b.prop("concrete_road_barrier", p, randf_range(-15, 15), 1.3, true, true, "concrete")
	b.crate_stack(Vector3(10, 0, 40), 20)
	b.crate_stack(Vector3(-10, 0, 37), -10)
	b.flood_light(Vector3(-4, 4.6, 20.6), Vector3(-2, 0, 30), Color(1.0, 0.85, 0.6), 7.0, 26.0, 42.0)
	b.flood_light(Vector3(4, 4.6, 20.6), Vector3(3, 0, 32), Color(1.0, 0.85, 0.6), 7.0, 26.0, 42.0)
	b.prop("street_lamp_01", Vector3(-20, 0, 42), 180, 1.45, true)
	b.spot(Vector3(-20, 5.6, 41), Vector3(-20, 0, 38), Color(1.0, 0.72, 0.42), 3.5, 14.0, 50.0, false)

	# ================================================================ inner courtyard
	b.truck(Vector3(-22, 0, 4), 0)
	b.container(Vector3(20, 0, 10), 90, "rust")
	b.container(Vector3(28, 0, 2), 0, "olive")
	b.container(Vector3(28, 2.6, 2), 0, "navy")
	b.cover_block(Vector3(-4, 0, 6), Vector3(3.2, 1.1, 0.8), "wall_exterior", 0)
	b.cover_block(Vector3(6, 0, 0), Vector3(3.2, 1.1, 0.8), "wall_exterior", 0)
	b.cover_block(Vector3(-8, 0, -4), Vector3(3.2, 1.1, 0.8), "wall_exterior", 90)
	b.crate_stack(Vector3(10, 0, 12), 0)
	b.crate_stack(Vector3(-32, 0, 13), 90, 3)
	b.prop("portable_generator", Vector3(-14, 0, 14), 0, 1.3, true, true)
	b.prop("propane_tank", Vector3(36, 0, 16), 0, 1.3, true)
	b.flood_light(Vector3(-12, 3.9, -9.6), Vector3(-10, 0, 4), Color(0.8, 0.88, 1.0), 5.5, 24.0, 45.0)
	b.flood_light(Vector3(9, 4.4, -9.6), Vector3(12, 0, 4), Color(1.0, 0.82, 0.55), 5.5, 24.0, 45.0)
	b.alarm_light(Vector3(0, 4.8, 19.5))

	# ================================================================ research lab (x -40..-10, z -50..-10)
	var LH := 4.0
	b.floor_rect(-40, -50, -10, -10, 0.04, "tile", "tile")
	b.wall(Vector2(-40, -10), Vector2(-10, -10), 0.0, LH, "wall_exterior", 0.4,
		[{"at": 15.0, "w": 1.8, "top": 2.6}, {"at": 6.0, "w": 2.6, "bottom": 1.0, "top": 2.4, "glass": true}, {"at": 24.0, "w": 2.6, "bottom": 1.0, "top": 2.4, "glass": true}])
	b.wall(Vector2(-40, -50), Vector2(-10, -50), 0.0, LH, "wall_exterior", 0.4)
	b.wall(Vector2(-40, -50), Vector2(-40, -10), 0.0, LH, "wall_exterior", 0.4)
	b.wall(Vector2(-10, -50), Vector2(-10, -10), 0.0, LH, "wall_exterior", 0.4, [{"at": 20.0, "w": 1.6, "top": 2.6}])
	b.ceiling_rect(-40.2, -50.2, -9.8, -9.8, LH)
	b.wall(Vector2(-40, -18), Vector2(-10, -18), 0.0, LH, "wall_white", 0.25,
		[{"at": 7.0, "w": 1.6, "top": 2.6}, {"at": 23.0, "w": 1.6, "top": 2.6}])
	b.wall(Vector2(-25, -50), Vector2(-25, -18), 0.0, LH, "wall_white", 0.25,
		[{"at": 10.0, "w": 1.4, "top": 2.5}, {"at": 20.0, "w": 6.0, "bottom": 0.9, "top": 2.6, "glass": true}])
	for z in [-14.0]:
		for x in [-34.0, -24.0, -15.0]:
			b.ceiling_light(Vector3(x, 3.95, z), "fluorescent", Color(0.9, 0.95, 1.0), 1.4, 8.0)
	for p in [Vector3(-36, 3.95, -26), Vector3(-30, 3.95, -40), Vector3(-17, 3.95, -26), Vector3(-17, 3.95, -40)]:
		b.ceiling_light(p, "fluorescent", Color(0.9, 0.95, 1.0), 1.5, 9.0, p.x == -17.0 and p.z == -40.0)
	# lab furniture
	for z in [-24.0, -32.0]:
		b.box(Vector3(-32.5, 0.45, z), Vector3(6.0, 0.9, 1.2), "wall_white", true, "metal")
		b.box(Vector3(-32.5, 0.92, z), Vector3(6.1, 0.04, 1.3), "trim_dark", false)
		b.add_cover_points(Vector3(-32.5, 0.45, z), Vector3(6.0, 0.9, 1.2), 0.0, false)
		b.prop("circuit_board", Vector3(-34, 0.94, z), 20, 1.0, false)
		b.prop("classic_laptop", Vector3(-31, 0.94, z), -15, 1.0, false)
	b.prop("metal_office_desk", Vector3(-37, 0, -46), 90, 1.0, true, true)
	b.prop("steel_frame_shelves_01", Vector3(-31, 0, -49.3), 0, 0.11, true)
	b.prop("metal_tool_chest", Vector3(-39.3, 0, -36), 90, 1.2, true)
	# network core
	b.box(Vector3(-17.5, 1.6, -47.6), Vector3(5.0, 3.2, 2.2), "trim_dark", true, "metal")
	for i in 6:
		b.box(Vector3(-19.5 + i * 0.8, 1.6, -46.48), Vector3(0.12, 2.6, 0.02), "emissive_blue", false)
	b.box(Vector3(-17.5, 3.4, -47.6), Vector3(5.4, 0.2, 2.6), "trim_steel", false)
	var core_light := b.omni(Vector3(-17.5, 2.0, -45.5), Color(0.35, 0.6, 1.0), 2.0, 9.0)
	core_light.name = "CoreLight"
	for p in [Vector3(-13, 0, -30), Vector3(-21, 0, -24)]:
		b.prop("power_box_01", p + Vector3(0, 1.2, 0), 0, 1.5, false)
	b.crate_stack(Vector3(-13, 0, -36), 90)
	b.alarm_light(Vector3(-25, 3.8, -14))

	# ================================================================ service alley (x -10..8)
	b.container(Vector3(-5, 0, -22), 90, "olive")
	b.container(Vector3(3, 0, -34), 90, "rust")
	b.container(Vector3(-5, 0, -44), 0, "navy")
	b.crate_stack(Vector3(4, 0, -16), 0)
	b.prop("Barrel_01", Vector3(-8.5, 0, -30), 0, 1.0, true, true)
	b.prop("barrel_03", Vector3(-8.3, 0, -31), 0, 1.0, true)
	b.omni(Vector3(-1, 3.5, -28), Color(1.0, 0.7, 0.4), 1.2, 9.0)
	b.box(Vector3(-1, 3.6, -28), Vector3(0.3, 0.15, 0.3), "emissive_warm", false)

	# ================================================================ command building (x 8..40, z -56..-10)
	var CH := 4.5
	b.floor_rect(8, -56, 40, -10, 0.04, "floor_dark", "concrete")
	b.wall(Vector2(8, -10), Vector2(40, -10), 0.0, CH, "wall_exterior", 0.5, [{"at": 16.0, "w": 2.0, "top": 2.8}])
	b.wall(Vector2(8, -56), Vector2(40, -56), 0.0, CH, "wall_exterior", 0.5)
	b.wall(Vector2(8, -56), Vector2(8, -10), 0.0, CH, "wall_exterior", 0.5, [{"at": 36.0, "w": 1.6, "top": 2.6}])
	b.wall(Vector2(40, -56), Vector2(40, -10), 0.0, CH, "wall_exterior", 0.5)
	# roof slab with stair opening (x 34..40, z -33..-21)
	b.ceiling_rect(7.8, -56.2, 40.2, -33, CH)
	b.ceiling_rect(7.8, -21, 40.2, -9.8, CH)
	b.ceiling_rect(7.8, -33, 34, -21, CH)
	# interior walls
	b.wall(Vector2(8, -20), Vector2(40, -20), 0.0, CH, "wall_navy", 0.3,
		[{"at": 5.0, "w": 1.4, "top": 2.5}, {"at": 18.0, "w": 2.0, "top": 2.8}, {"at": 29.0, "w": 1.4, "top": 2.5}])
	b.wall(Vector2(18, -40), Vector2(18, -20), 0.0, CH, "wall_navy", 0.3,
		[{"at": 10.0, "w": 10.0, "bottom": 1.0, "top": 2.6, "glass": true}])
	b.wall(Vector2(34, -40), Vector2(34, -20), 0.0, CH, "wall_navy", 0.3, [{"at": 10.0, "w": 1.4, "top": 2.5}])
	b.wall(Vector2(8, -40), Vector2(40, -40), 0.0, CH, "wall_navy", 0.3, [{"at": 5.0, "w": 1.4, "top": 2.5}])
	b.wall(Vector2(18, -56), Vector2(18, -40), 0.0, CH, "wall_interior", 0.3, [{"at": 8.0, "w": 1.6, "top": 2.6}])
	b.wall(Vector2(34, -56), Vector2(34, -40), 0.0, CH, "wall_interior", 0.3)
	# hall
	for x in [14.0, 24.0, 34.0]:
		b.ceiling_light(Vector3(x, 4.45, -15), "strip", Color(1.0, 0.75, 0.5), 1.3, 8.0)
	b.prop("metal_office_desk", Vector3(24, 0, -12), 180, 1.0, true, true)
	b.crate_stack(Vector3(12, 0, -17.5), 0)
	b.prop("cardboard_box_01", Vector3(31, 0, -11), 0, 1.4, true)
	b.alarm_light(Vector3(24, 4.3, -15))
	# gallery
	b.ceiling_light(Vector3(13, 4.45, -30), "fluorescent", Color(0.85, 0.9, 1.0), 1.0, 8.0)
	b.prop("steel_frame_shelves_01", Vector3(9.0, 0, -28), 90, 0.11, true)
	# strategy room
	b.box(Vector3(26, 0.45, -30), Vector3(7.0, 0.9, 3.0), "trim_dark", true, "metal")
	b.box(Vector3(26, 0.93, -30), Vector3(6.6, 0.04, 2.6), "emissive_blue", false)
	b.add_cover_points(Vector3(26, 0.45, -30), Vector3(7.0, 0.9, 3.0), 0.0, false)
	b.crate_stack(Vector3(21, 0, -37), 0)
	b.crate_stack(Vector3(31, 0, -23.5), 90)
	b.spot(Vector3(26, 4.4, -30), Vector3(26, 0, -30), Color(1.0, 0.35, 0.25), 3.5, 8.0, 60.0, true)
	b.ceiling_light(Vector3(21, 4.45, -24), "strip", Color(1.0, 0.6, 0.4), 0.9, 7.0)
	b.ceiling_light(Vector3(31, 4.45, -36), "strip", Color(1.0, 0.6, 0.4), 0.9, 7.0)
	# anteroom + vault
	b.ceiling_light(Vector3(13, 4.45, -48), "fluorescent", Color(0.85, 0.9, 1.0), 1.0, 7.0)
	b.prop("metal_office_desk", Vector3(11, 0, -54.5), 0, 1.0, true)
	b.box(Vector3(26, 0.5, -50), Vector3(1.2, 1.0, 1.2), "trim_steel", true, "metal")
	b.box(Vector3(26, 1.02, -50), Vector3(1.0, 0.04, 1.0), "emissive_cool", false)
	for x in [20.0, 32.0]:
		for z in [-54.0, -44.0]:
			b.box(Vector3(x, 1.2, z), Vector3(1.6, 2.4, 0.8), "trim_steel", true, "metal")
	b.ceiling_light(Vector3(26, 4.45, -48), "fluorescent", Color(0.75, 0.85, 1.0), 1.4, 9.0, true)
	# stairwell (x 34..40, z -40..-20)
	b.stairs(Vector3(37, 0.0, -21.8), Vector3(0, 0, -1), 2.0, CH + 0.25, 10.5)
	b.ceiling_light(Vector3(37, 4.45, -36), "strip", Color(1.0, 0.8, 0.5), 1.0, 6.0)

	# ================================================================ roof + helipad
	var R := CH + 0.25
	for seg in [[Vector2(8, -56), Vector2(40, -56)], [Vector2(8, -10), Vector2(40, -10)], [Vector2(8, -56), Vector2(8, -10)], [Vector2(40, -56), Vector2(40, -10)]]:
		b.wall(seg[0], seg[1], R, 1.1, "wall_exterior", 0.5)
	b.railing(Vector3(34, R, -33), Vector3(34, R, -21))
	b.railing(Vector3(34, R, -21), Vector3(39.7, R, -21))
	b.box(Vector3(22, R + 0.03, -45), Vector3(14, 0.04, 14), "trim_dark", false)
	b.box(Vector3(22, R + 0.05, -45), Vector3(1.0, 0.03, 8), "trim_amber", false)
	b.box(Vector3(22, R + 0.05, -45), Vector3(6, 0.03, 1.0), "trim_amber", false)
	for c in [Vector3(15.2, 0, -51.8), Vector3(28.8, 0, -51.8), Vector3(15.2, 0, -38.2), Vector3(28.8, 0, -38.2)]:
		b.box(c + Vector3(0, R + 0.1, 0), Vector3(0.25, 0.15, 0.25), "emissive_green", false)
	for p in [Vector3(12, R, -16), Vector3(30, R, -14), Vector3(12, R, -30)]:
		b.prop("exterior_aircon_unit", p, 90, 1.5, true, true)
	b.omni(Vector3(22, R + 3.0, -45), Color(0.6, 0.8, 1.0), 1.2, 14.0)


func place_devices() -> void:
	# Outer courtyard / blast door
	add_door(Vector3(-12, 0, 28), 90, {"width": 1.4, "height": 2.4, "name": "GuardhouseDoor"})
	add_door(Vector3(0, 0, 20), 0, {"width": 5.0, "height": 4.5, "lock": Door.Lock.CONSOLE, "id": "blast", "name": "BlastDoor"})
	add_console(Vector3(-17, 0, 24.6), 180, {"prompt": "Override blast door", "hold": 3.0, "doors": ["blast"], "name": "BlastOverride",
		"story": "Blast door override accepted. It's open, GHOST. Move.", "speaker": "ORACLE"})
	add_pickup(Pickup.Kind.MEDKIT, Vector3(-21, 0, 31), {"amount": 0.6, "name": "MedGuardhouse"})
	add_hiding_spot(Vector3(-21.4, 0, 25), -90)
	# Lab
	add_door(Vector3(-25, 0, -10), 0, {"width": 1.8, "name": "LabFront"})
	add_door(Vector3(-10, 0, -30), 90, {"name": "LabSide"})
	add_door(Vector3(-33, 0, -18), 0, {"name": "LabWestDoor"})
	add_door(Vector3(-17, 0, -18), 0, {"name": "CoreRoomDoor"})
	add_door(Vector3(-25, 0, -40), 90, {"width": 1.4, "height": 2.5, "name": "LabPartitionDoor"})
	_core = add_console(Vector3(-17.5, 0, -45.6), 180, {"prompt": "Shut down main security network", "hold": 4.0, "objective": &"disable_network",
		"cameras": "*", "alarm": true, "doors": ["command"], "name": "NetworkCore",
		"story": "Network core is down. Cameras are dark and the command sector door is open. Voss knows you're here.", "voice": &"vo_m03_network"})
	_core.screen_color = Color(0.3, 0.6, 1.0)
	add_pickup(Pickup.Kind.INTEL, Vector3(-37, 0.79, -46), {"id": "lab_archive", "label": "research lab archive", "objective": &"lab_archive",
		"hold": 1.5, "name": "LabArchive"})
	add_pickup(Pickup.Kind.AMMO, Vector3(-39, 0, -20), {"amount": 0.5, "name": "AmmoLab"})
	add_hiding_spot(Vector3(-24.4, 0, -46), 90)
	add_alarm_panel(Vector3(-10.25, 0, -14), 90, "PanelLab")
	# Alley
	add_pickup(Pickup.Kind.AMMO, Vector3(6, 0, -48), {"amount": 0.6, "name": "AmmoAlley"})
	add_pickup(Pickup.Kind.MEDKIT, Vector3(-8, 0, -48), {"amount": 0.6, "name": "MedAlley"})
	# Command building
	add_door(Vector3(24, 0, -10), 0, {"width": 2.0, "height": 2.8, "lock": Door.Lock.CONSOLE, "id": "command", "name": "CommandFront"})
	add_door(Vector3(8, 0, -46), 90, {"lock": Door.Lock.CONSOLE, "id": "command", "name": "CommandSide"})
	add_door(Vector3(13, 0, -20), 0, {"width": 1.4, "height": 2.5, "name": "GalleryDoor"})
	add_door(Vector3(26, 0, -20), 0, {"width": 2.0, "height": 2.8, "id": "strategy_s", "name": "StrategyDoorS"})
	add_door(Vector3(37, 0, -20), 0, {"width": 1.4, "height": 2.5, "name": "StairDoor"})
	add_door(Vector3(34, 0, -30), 90, {"width": 1.4, "height": 2.5, "id": "strategy_e", "name": "StrategyDoorE"})
	add_door(Vector3(13, 0, -40), 0, {"width": 1.4, "height": 2.5, "name": "AnteroomDoor"})
	add_door(Vector3(18, 0, -48), 90, {"width": 1.6, "lock": Door.Lock.CONSOLE, "id": "vault", "enemy_access": false, "name": "VaultDoor"})
	_override = add_console(Vector3(9.0, 0, -36), -90, {"prompt": "Lockdown override — seal strategy room", "hold": 3.0, "name": "LockdownOverride"})
	_override.screen_color = Color(1.0, 0.3, 0.2)
	_ledger = add_pickup(Pickup.Kind.INTEL, Vector3(26, 1.05, -50), {"id": "ledger", "label": "buyer ledger", "objective": &"retrieve_ledger",
		"hold": 2.0, "name": "Ledger", "model": "res://assets/models/polyhaven/classic_laptop/classic_laptop_1k.gltf"})
	add_pickup(Pickup.Kind.AMMO, Vector3(10, 0, -11), {"amount": 0.6, "name": "AmmoHall"})
	add_pickup(Pickup.Kind.MEDKIT, Vector3(39, 0, -38), {"amount": 0.7, "name": "MedStair"})
	add_hiding_spot(Vector3(8.6, 0, -24), -90)
	add_alarm_panel(Vector3(39.75, 0, -14), 90, "PanelHall")
	# Cameras
	add_camera(Vector3(-3.5, 4.6, 20.5), 160, "outer", {"name": "CamBlastW", "sweep": 70.0, "range": 20.0})
	add_camera(Vector3(3.5, 4.6, 20.5), -160, "outer", {"name": "CamBlastE", "sweep": 70.0, "range": 20.0})
	add_camera(Vector3(-12.3, 2.9, 31.7), -45, "outer", {"name": "CamGuardhouse", "sweep": 50.0})
	add_camera(Vector3(-10.5, 3.6, -9.6), -150, "inner", {"name": "CamInnerW", "sweep": 80.0, "range": 20.0})
	add_camera(Vector3(8.5, 4.1, -9.6), 150, "inner", {"name": "CamInnerE", "sweep": 80.0, "range": 20.0})
	add_camera(Vector3(-39.5, 3.6, -19), -125, "lab", {"name": "CamLab"})
	add_camera(Vector3(-10.6, 3.6, -49.5), 135, "lab", {"name": "CamCore", "sweep": 50.0})
	add_camera(Vector3(39.5, 4.0, -10.6), 60, "command", {"name": "CamHall", "sweep": 50.0})
	# Zones + triggers
	add_zone(Vector3(0, 0, 5), Vector3(80, 5, 30), "Restricted Command Area")
	add_zone(Vector3(-25, 0, -30), Vector3(30, 4, 40), "Research Lab — Restricted")
	add_zone(Vector3(24, 0, -33), Vector3(32, 5, 46), "Command Sector — Restricted")
	add_trigger(Vector3(0, 0, 16), Vector3(80, 5, 6), ObjectiveTrigger.Mode.COMPLETE, &"enter_restricted", {"name": "TrigRestricted",
		"message": "You're past the blast doors. The research lab and its network core are on the west side.", "voice": &"vo_m03_restricted"})
	var cmd := add_trigger(Vector3(24, 0, -15), Vector3(30, 4, 9), ObjectiveTrigger.Mode.COMPLETE, &"reach_command", {"name": "TrigCommand",
		"message": "Command sector. Voss is in the strategy room with his response team. Fight him, or use the lockdown override on the gallery to seal him in.", "voice": &"vo_m03_command"})
	cmd.triggered.connect(func():
		get_tree().create_timer(8.0).timeout.connect(func():
			if is_instance_valid(_voss) and not _voss.is_dead():
				AudioManager.play_voice(&"vo_m03_voss_intro", "VOSS", "You made it this far, ghost. It ends in this room.")))
	add_trigger(Vector3(22, R_Y, -45), Vector3(12, 4, 12), ObjectiveTrigger.Mode.EXTRACT, &"extract", {"name": "Extraction"})


const R_Y := 4.75


func spawn_enemies() -> void:
	# Outer courtyard
	spawn_enemy("guard", Vector3(-30, 0, 33), 90, [Vector3(-30, 0, 33), Vector3(-6, 0, 34), Vector3(-6, 0, 26), Vector3(-30, 0, 30)], "OuterPatrolW")
	spawn_enemy("guard", Vector3(2.5, 0, 22.5), 180, [], "BlastGuard")
	spawn_enemy("guard", Vector3(34, 0, 38), 0, [Vector3(34, 0, 38), Vector3(34, 0, 23), Vector3(18, 0, 23)], "OuterPatrolE", {"loop": false, "wait": 3.0})
	spawn_enemy("specialist", Vector3(-17, 0, 30), 0, [], "GuardhouseSpecialist")
	# Inner courtyard
	spawn_enemy("heavy", Vector3(0, 0, 10), 0, [Vector3(0, 0, 10), Vector3(0, 0, -6), Vector3(14, 0, -6), Vector3(14, 0, 10)], "CourtHeavy", {"wait": 3.0})
	spawn_enemy("guard", Vector3(-30, 0, -4), 0, [Vector3(-30, 0, -4), Vector3(-30, 0, 15), Vector3(-15, 0, 15)], "CourtGuardW", {"loop": false})
	spawn_enemy("guard", Vector3(34, 0, 14), 180, [Vector3(34, 0, 14), Vector3(34, 0, -5), Vector3(20, 0, -5)], "CourtGuardE", {"loop": false})
	spawn_enemy("specialist", Vector3(20, 0, -6), 0, [], "CommandEntrySpecialist")
	# Lab
	spawn_enemy("guard", Vector3(-38, 0, -14), -90, [Vector3(-38, 0, -14), Vector3(-12, 0, -14)], "LabLobbyGuard", {"loop": false, "wait": 3.0})
	spawn_enemy("specialist", Vector3(-33, 0, -28), 0, [Vector3(-33, 0, -28), Vector3(-33, 0, -44), Vector3(-28, 0, -44)], "LabSpecialist", {"loop": false})
	spawn_enemy("guard", Vector3(-14, 0, -40), 90, [Vector3(-14, 0, -40), Vector3(-14, 0, -22), Vector3(-21, 0, -22)], "CoreGuard", {"loop": false})
	# Alley
	spawn_enemy("guard", Vector3(1, 0, -14), 0, [Vector3(1, 0, -14), Vector3(0, 0, -49), Vector3(-8, 0, -49)], "AlleyGuard", {"loop": false, "wait": 3.0})
	# Command
	spawn_enemy("guard", Vector3(16, 0, -13), 90, [Vector3(16, 0, -13), Vector3(36, 0, -13)], "HallGuard", {"loop": false})
	_voss = spawn_enemy("commander", Vector3(26, 0, -34), 180, [], "CommanderVoss")
	spawn_enemy("heavy", Vector3(21, 0, -25), 180, [], "VossHeavyA")
	spawn_enemy("heavy", Vector3(31, 0, -32), 90, [], "VossHeavyB")
	# Voss's phase reinforcements and the rooftop team
	_phase_reinforcements.append(spawn_enemy("guard", Vector3(38, 0, -12), 90, [], "PhaseGuardA", {"dormant": true}))
	_phase_reinforcements.append(spawn_enemy("guard", Vector3(10, 0, -12), -90, [], "PhaseGuardB", {"dormant": true}))
	_roof_team.append(spawn_enemy("guard", Vector3(14, R_Y, -24), 180, [], "RoofGuardA", {"dormant": true}))
	_roof_team.append(spawn_enemy("guard", Vector3(32, R_Y, -50), 0, [], "RoofGuardB", {"dormant": true}))
	_roof_team.append(spawn_enemy("heavy", Vector3(37, 0, -38), 180, [], "StairHeavy", {"dormant": true}))


func post_setup() -> void:
	controller.set_objective_target(&"enter_restricted", Vector3(0, 0, 20))
	controller.set_objective_target(&"disable_network", _core)
	controller.set_objective_target(&"reach_command", Vector3(24, 0, -10))
	controller.set_objective_target(&"overcome_commander", _voss)
	controller.set_objective_target(&"retrieve_ledger", _ledger)
	controller.set_objective_target(&"extract", Vector3(22, R_Y, -45))
	_voss.killed.connect(_on_voss_killed)
	_voss.health_ratio_changed.connect(_on_voss_health)
	_voss.state_changed.connect(func(_e, _o, n):
		if n == &"combat":
			AudioManager.play_voice(&"vo_m03_voss_taunt", "VOSS", "Every operative you're protecting has a price. I just collected it."))
	_override.hacked.connect(_on_override)
	_core.hacked.connect(func():
		if controller.detections == 0:
			controller.complete_objective(&"undetected_lab"))
	_ledger.used.connect(func(_b): _on_ledger())
	controller.before_finish.connect(func():
		if _voss_contained and is_instance_valid(_voss) and not _voss.is_dead():
			controller.complete_objective(&"contain_voss", true))


func _voss_in_room() -> bool:
	var p := _voss.global_position
	return STRATEGY_ROOM.has_point(Vector2(p.x, p.z))


func _on_override() -> void:
	if _voss.is_dead() or controller.is_done(&"overcome_commander"):
		controller.mission_message.emit("Lockdown override no longer needed", "info")
		return
	if not _voss_in_room():
		controller.mission_message.emit("Voss is not inside the strategy room — override aborted", "warning")
		_override.done = false
		_override._used_once = false
		_override.call("_refresh")
		return
	_contain()


func _contain() -> void:
	_voss_contained = true
	for n in devices.get_children():
		if n is Door and (n as Door).door_id in ["strategy_s", "strategy_e"]:
			var d := n as Door
			d.is_open = false
			d.lock = Door.Lock.CONSOLE
			d.locked = true
			d.enemy_access = false
			d.call("_refresh_status")
	# Voss stays sealed: he can no longer leave the room.
	_voss.release_cover()
	controller.complete_objective(&"overcome_commander")
	_open_vault()
	radio(&"vo_m03_voss_contained", "Strategy room sealed. Voss isn't going anywhere. The vault is open. Take the ledger.")


func _on_voss_killed(_e: Enemy) -> void:
	if _voss_contained:
		controller.fail_optional(&"contain_voss")
		return
	controller.fail_optional(&"contain_voss")
	controller.complete_objective(&"overcome_commander")
	_open_vault()
	radio(&"vo_m03_voss_down", "Voss is down. The vault is open. Take the ledger.")


func _on_voss_health(_e: Enemy, ratio: float) -> void:
	var phase := 0
	if ratio < 0.66:
		phase = 1
	if ratio < 0.33:
		phase = 2
	if phase > _voss_phase:
		_voss_phase = phase
		var e: Enemy = _phase_reinforcements[phase - 1] if phase - 1 < _phase_reinforcements.size() else null
		if e and e.dormant:
			e.activate_reinforcement(_voss.global_position)
		controller.mission_message.emit("Voss is calling reinforcements", "warning")


func _open_vault() -> void:
	for n in devices.get_children():
		if n is Door and (n as Door).door_id == "vault":
			(n as Door).unlock()


func _on_ledger() -> void:
	radio(&"vo_m03_ledger", "That's the ledger. Everything we need. The helipad is on the roof. The bird is inbound.")
	controller.ignore_alarm_detection = true
	alarm.set_offline(false)
	alarm.raise_alarm(Vector3(26, 0, -45), "ledger")
	for e in _roof_team:
		if e.dormant:
			e.activate_reinforcement(Vector3(26, 0, -45))


func get_level_state() -> Dictionary:
	return {"contained": _voss_contained, "phase": _voss_phase}


func apply_level_state(s: Dictionary) -> void:
	_voss_phase = int(s.get("phase", 0))
	if bool(s.get("contained", false)) and not _voss.is_dead():
		_contain()
	elif controller.is_done(&"overcome_commander"):
		_open_vault()


func on_mission_start() -> void:
	radio(&"vo_m03_start", "Last run, GHOST. The blast doors to the restricted command area are ahead. Voss's people are on high alert tonight.")


func capture_points() -> Array:
	return [
		["outer", Vector3(-12, 7, 45), Vector3(0, 1, 20)],
		["inner", Vector3(-30, 8, 18), Vector3(10, 0, -8)],
		["lab", Vector3(-38, 2.6, -20), Vector3(-20, 1, -46)],
		["core", Vector3(-22, 1.8, -36), Vector3(-17.5, 1.5, -47)],
		["hall", Vector3(10, 2.0, -12), Vector3(36, 1.2, -18)],
		["strategy", Vector3(10, 1.8, -30), Vector3(28, 1.2, -30)],
		["voss", Vector3(26, 1.6, -31.5), Vector3(26, 1.3, -34)],
		["roof", Vector3(4, 14, -22), Vector3(22, 4.7, -45)],
	]
