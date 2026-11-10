class_name MissionLevel
extends Node3D
## Base class for mission scenes. Sets up environment, geometry (LevelBuilder),
## navigation baking, player, AI, mission controller, UI and checkpoint restore.
## Each mission overrides the virtual build/populate hooks.

const ENEMY_DATA := {
	"guard": "res://resources/enemies/standard_guard.tres",
	"specialist": "res://resources/enemies/security_specialist.tres",
	"heavy": "res://resources/enemies/heavy_response.tres",
	"commander": "res://resources/enemies/commander.tres",
}

@export var mission_id: String = "m01"

var mission: MissionData
var env: EnvironmentController
var nav_region: NavigationRegion3D
var geometry: Node3D
var builder: LevelBuilder
var devices: Node3D
var enemies_root: Node3D
var alarm: AlarmSystem
var player: Player
var controller: MissionController
var ui: MissionUI
var nav_bake_ms: int = 0
var build_ms: int = 0


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	mission = Campaign.get_mission(mission_id)
	env = EnvironmentController.new()
	env.name = "Environment"
	configure_environment(env)
	add_child(env)
	nav_region = NavigationRegion3D.new()
	nav_region.name = "Navigation"
	add_child(nav_region)
	geometry = Node3D.new()
	geometry.name = "Geometry"
	nav_region.add_child(geometry)
	var covers := Node3D.new()
	covers.name = "Cover"
	add_child(covers)
	devices = Node3D.new()
	devices.name = "Devices"
	add_child(devices)
	enemies_root = Node3D.new()
	enemies_root.name = "Enemies"
	add_child(enemies_root)
	builder = LevelBuilder.new(geometry, covers)
	alarm = AlarmSystem.new()
	alarm.name = "Alarm"
	add_child(alarm)

	build_level()
	place_devices()
	build_ms = Time.get_ticks_msec() - t0
	var t1 := Time.get_ticks_msec()
	_bake_navigation()
	nav_bake_ms = Time.get_ticks_msec() - t1

	player = Player.new()
	player.name = "Player"
	player.weapon_ids.assign(mission.weapons)
	player.gadget_ids.assign(mission.gadgets)
	add_child(player)
	var start := get_player_start()
	player.place_at(start[0], start[1])
	player.ambient_light = get_ambient_light()

	controller = MissionController.new()
	controller.name = "MissionController"
	add_child(controller)
	controller.setup(mission, player, self)

	spawn_enemies()

	ui = MissionUI.new()
	ui.name = "UI"
	add_child(ui)
	ui.setup(controller, player)

	post_setup()
	if not Game.pending_checkpoint.is_empty():
		var cp := Game.pending_checkpoint
		Game.pending_checkpoint = {}
		controller.restore_checkpoint.call_deferred(cp)
	else:
		on_mission_start.call_deferred()
	Game.set_mouse_captured(true)
	InputRouter.gameplay_blocked = false
	AudioManager.play_music(mission.music, 2.0)
	AudioManager.play_ambience(get_ambience())
	print("[SHADOW] %s ready: build %d ms, navmesh %d ms, lights %d (%d shadowed)" % [mission_id, build_ms, nav_bake_ms, builder.light_count, builder.shadow_light_count])


func _bake_navigation() -> void:
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.25
	nm.agent_max_slope = 46.0
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.region_min_size = 6.0
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1 | 32
	nav_region.navigation_mesh = nm
	nav_region.bake_navigation_mesh(false)


# =========================================================================== virtual hooks

func configure_environment(_e: EnvironmentController) -> void:
	pass


func build_level() -> void:
	pass


func place_devices() -> void:
	pass


func spawn_enemies() -> void:
	pass


func post_setup() -> void:
	pass


func on_mission_start() -> void:
	pass


## [position, yaw_degrees]
func get_player_start() -> Array:
	return [Vector3.ZERO, 0.0]


func get_ambient_light() -> float:
	return 0.22


func get_ambience() -> StringName:
	return &"amb_night_wind"


func get_level_state() -> Dictionary:
	return {}


func apply_level_state(_s: Dictionary) -> void:
	pass


# =========================================================================== placement helpers

func spawn_enemy(kind: String, pos: Vector3, yaw: float, patrol: Array = [], id: String = "", opts: Dictionary = {}) -> Enemy:
	var e := Enemy.new()
	e.data = load(ENEMY_DATA.get(kind, ENEMY_DATA["guard"]))
	e.name = id if id != "" else "%s_%d" % [kind, enemies_root.get_child_count()]
	var pts: Array[Vector3] = []
	for p in patrol:
		pts.append(p)
	e.patrol_points = pts
	e.patrol_loop = opts.get("loop", true)
	e.patrol_wait = opts.get("wait", 2.5)
	e.dormant = opts.get("dormant", false)
	e.start_state = &"patrol" if not pts.is_empty() else &"idle"
	e.position = pos
	e.rotation_degrees.y = yaw
	enemies_root.add_child(e)
	return e


func add_camera(pos: Vector3, yaw: float, network: String = "main", opts: Dictionary = {}) -> SecurityCamera:
	var c := SecurityCamera.new()
	c.network = network
	c.sweep_angle = opts.get("sweep", 70.0)
	c.tilt = opts.get("tilt", -28.0)
	c.view_range = opts.get("range", 17.0)
	c.name = opts.get("name", "Camera_%d" % devices.get_child_count())
	c.position = pos
	c.rotation_degrees.y = yaw
	devices.add_child(c)
	# Wall bracket
	builder.box(pos + Vector3(0, 0.12, 0) + Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(0, 0, 0.15), Vector3(0.08, 0.25, 0.3), "trim_dark", false)
	return c


## Doors live in the geometry tree (wall openings) but are excluded from the nav bake by layer.
func add_door(pos: Vector3, yaw: float, opts: Dictionary = {}) -> Door:
	var d := Door.new()
	d.width = opts.get("width", 1.6)
	d.height = opts.get("height", 2.6)
	d.lock = opts.get("lock", Door.Lock.NONE)
	d.keycard_id = opts.get("keycard", "")
	d.door_id = opts.get("id", "")
	d.enemy_access = opts.get("enemy_access", true)
	d.start_open = opts.get("open", false)
	d.name = opts.get("name", "Door_%s" % (d.door_id if d.door_id != "" else str(devices.get_child_count())))
	d.position = pos
	d.rotation_degrees.y = yaw
	devices.add_child(d)
	return d


func add_console(pos: Vector3, yaw: float, opts: Dictionary = {}) -> SecurityConsole:
	var c := SecurityConsole.new()
	c.prompt = opts.get("prompt", "Hack terminal")
	c.hold_time = opts.get("hold", 2.5)
	c.objective_id = opts.get("objective", &"")
	c.disable_camera_network = opts.get("cameras", "")
	c.unlock_door_ids = PackedStringArray(opts.get("doors", []))
	c.disable_alarm = opts.get("alarm", false)
	c.story_text = opts.get("story", "")
	c.story_speaker = opts.get("speaker", "ORACLE")
	c.story_voice = opts.get("voice", &"")
	c.noise_radius = opts.get("noise", 3.0)
	c.name = opts.get("name", "Console_%d" % devices.get_child_count())
	c.position = pos
	c.rotation_degrees.y = yaw
	geometry.add_child(c)   # its desk collider is part of the navmesh bake
	return c


func add_alarm_panel(pos: Vector3, yaw: float, name_: String = "") -> AlarmPanel:
	var p := AlarmPanel.new()
	p.name = name_ if name_ != "" else "AlarmPanel_%d" % devices.get_child_count()
	p.position = pos
	p.rotation_degrees.y = yaw
	devices.add_child(p)
	return p


func add_pickup(kind: int, pos: Vector3, opts: Dictionary = {}) -> Pickup:
	var p := Pickup.new()
	p.kind = kind
	p.item_id = opts.get("id", "")
	p.display_name = opts.get("label", "")
	p.objective_id = opts.get("objective", &"")
	p.amount = opts.get("amount", 0.35)
	if opts.has("model"):
		p.model_path = opts["model"]
	p.hold_time = opts.get("hold", 0.0)
	p.name = opts.get("name", "Pickup_%d" % devices.get_child_count())
	p.position = pos
	p.rotation_degrees.y = opts.get("yaw", 0.0)
	devices.add_child(p)
	return p


func add_trigger(pos: Vector3, size: Vector3, mode: int, objective: StringName = &"", opts: Dictionary = {}) -> ObjectiveTrigger:
	var t := ObjectiveTrigger.new()
	t.size = size
	t.mode = mode
	t.objective_id = objective
	t.requires = opts.get("requires", &"")
	t.message = opts.get("message", "")
	t.voice = opts.get("voice", &"")
	t.speaker = opts.get("speaker", "ORACLE")
	t.show_marker = opts.get("marker", false)
	t.name = opts.get("name", "Trigger_%d" % devices.get_child_count())
	t.position = pos
	devices.add_child(t)
	return t


func add_hiding_spot(pos: Vector3, yaw: float) -> HidingSpot:
	var h := HidingSpot.new()
	h.name = "Locker_%d" % devices.get_child_count()
	h.position = pos
	h.rotation_degrees.y = yaw
	geometry.add_child(h)
	return h


func add_zone(pos: Vector3, size: Vector3, zone_name: String = "Restricted Area") -> RestrictedZone:
	var z := RestrictedZone.new()
	z.size = size
	z.zone_name = zone_name
	z.position = pos
	devices.add_child(z)
	return z


func radio(voice: StringName, text: String, speaker: String = "ORACLE") -> void:
	AudioManager.play_voice(voice, speaker, text)
