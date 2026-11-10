class_name TestCase
extends RefCounted
## Minimal test base: assertions, scene helpers and frame waiting.

var tree: SceneTree
var failures: Array[String] = []
var notes: Array[String] = []
var _spawned: Array[Node] = []


func reset() -> void:
	failures.clear()
	notes.clear()
	# Isolate tests from global state left by earlier ones (menus block input, etc.).
	var router := tree.root.get_node("InputRouter")
	router.set("gameplay_blocked", false)
	router.get("external").call("reset")
	tree.paused = false


func before_each() -> void:
	pass


func after_each() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.queue_free()
	_spawned.clear()
	await tree.process_frame
	await tree.process_frame


func free_case() -> void:
	pass


func note(s: String) -> void:
	notes.append(s)


func check(cond: bool, msg: String) -> bool:
	if not cond:
		failures.append(msg)
	return cond


func eq(a, b, msg: String = "") -> bool:
	return check(a == b, "%s expected %s got %s" % [msg, str(b), str(a)])


func near(a: float, b: float, tol: float, msg: String = "") -> bool:
	return check(absf(a - b) <= tol, "%s expected %.3f±%.3f got %.3f" % [msg, b, tol, a])


func frames(n: int) -> void:
	for i in n:
		await tree.physics_frame


func seconds(s: float) -> void:
	await frames(int(s * 60.0))


## Adds a node to a fresh test world and tracks it for cleanup.
func spawn(n: Node, parent: Node = null) -> Node:
	(parent if parent else tree.root).add_child(n)
	_spawned.append(n)
	return n


## A flat test arena with floor collision (and optional navmesh bake).
func make_arena(size: float = 40.0, with_nav: bool = false) -> Node3D:
	var world := Node3D.new()
	world.name = "TestArena"
	spawn(world)
	var region := NavigationRegion3D.new()
	world.add_child(region)
	var geo := Node3D.new()
	region.add_child(geo)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(size, 0.5, size)
	cs.shape = bs
	body.add_child(cs)
	body.position = Vector3(0, -0.25, 0)
	geo.add_child(body)
	world.set_meta("geo", geo)
	world.set_meta("region", region)
	if with_nav:
		await bake(world)
	return world


func add_wall(world: Node3D, center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	body.position = center
	(world.get_meta("geo") as Node3D).add_child(body)
	return body


func bake(world: Node3D) -> void:
	var region: NavigationRegion3D = world.get_meta("region")
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.25
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1 | 32
	region.navigation_mesh = nm
	region.bake_navigation_mesh(false)
	await frames(3)


func make_player(world: Node3D, pos: Vector3) -> Player:
	var p := Player.new()
	world.add_child(p)
	p.place_at(pos, 0.0)
	return p


func make_enemy(world: Node3D, kind: String, pos: Vector3, yaw: float, patrol: Array = []) -> Enemy:
	var e := Enemy.new()
	e.data = load(MissionLevel.ENEMY_DATA[kind])
	var pts: Array[Vector3] = []
	for p in patrol:
		pts.append(p)
	e.patrol_points = pts
	e.start_state = &"patrol" if not pts.is_empty() else &"idle"
	e.position = pos
	e.rotation_degrees.y = yaw
	world.add_child(e)
	return e
