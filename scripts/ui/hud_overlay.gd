class_name HudOverlay
extends Control
## Custom-drawn HUD layer: crosshair (spread-aware), hit markers, directional
## detection indicators, damage direction, scanner tags and the objective waypoint.

var player: Player
var controller: MissionController
var _hit_t: float = 0.0
var _hit_kill: bool = false
var _damage: Array = []   # [direction(Vector3), time_left]
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = UIKit.font("label")


func setup(p: Player, mc: MissionController) -> void:
	player = p
	controller = mc
	p.weapons.hit_confirmed.connect(func(_t, killed, _h):
		_hit_t = 0.18
		_hit_kill = killed)
	p.damaged.connect(func(dir): _damage.append([dir, 1.2]))


func _process(delta: float) -> void:
	_hit_t = maxf(0.0, _hit_t - delta)
	for d in _damage:
		d[1] -= delta
	_damage = _damage.filter(func(d): return d[1] > 0.0)
	queue_redraw()


func _cam() -> Camera3D:
	return get_viewport().get_camera_3d()


func _draw() -> void:
	if player == null or not is_instance_valid(player) or size.x < 200.0 or size.y < 200.0:
		return
	var center := size * 0.5
	var recon := player.gadgets.recon_active
	if not player.is_dead() and not recon and player.hidden_in == null:
		_draw_crosshair(center)
	_draw_tags()
	if not recon:
		_draw_objective_marker()
		_draw_detection(center)
		_draw_damage(center)


func _draw_crosshair(center: Vector2) -> void:
	var cam := _cam()
	if cam == null:
		return
	var spread := player.weapons.current_spread(player.aiming, Vector2(player.velocity.x, player.velocity.z).length())
	var half_h := size.y * 0.5
	var gap := clampf(tan(deg_to_rad(spread)) / tan(deg_to_rad(cam.fov * 0.5)) * half_h, 4.0, 90.0)
	var col := Color(1, 1, 1, 0.85 if player.aiming else 0.55)
	var len := 9.0
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
		draw_line(center + d * gap, center + d * (gap + len), Color(0, 0, 0, 0.5), 4.0)
		draw_line(center + d * gap, center + d * (gap + len), col, 2.0)
	draw_circle(center, 1.8, col)
	if _hit_t > 0.0:
		var c := UIKit.RED if _hit_kill else Color(1, 1, 1)
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(center + d * 7.0, center + d * 15.0, c, 2.5)


## Arcs around the screen centre pointing at enemies/cameras that are noticing the player.
func _draw_detection(center: Vector2) -> void:
	var cam := _cam()
	if cam == null:
		return
	var yaw := cam.global_rotation.y
	var radius := 150.0
	for n in get_tree().get_nodes_in_group("enemy"):
		var e := n as Enemy
		if e == null or e.is_dead() or e.dormant:
			continue
		var s := e.perception.suspicion
		var fighting := e.state_name == &"combat"
		if s < 4.0 and not fighting:
			continue
		_arc_toward(center, radius, yaw, e.global_position, s, fighting)
	for n in get_tree().get_nodes_in_group("security_camera"):
		var c := n as SecurityCamera
		if c and c.is_operational() and c.suspicion > 4.0:
			_arc_toward(center, radius + 14.0, yaw, c.global_position, c.suspicion, false)


func _arc_toward(center: Vector2, radius: float, cam_yaw: float, pos: Vector3, s: float, fighting: bool) -> void:
	var to := pos - player.global_position
	var ang := atan2(to.x, -to.z) + cam_yaw   # 0 = straight ahead on screen
	var screen_ang := ang - PI * 0.5
	var t := clampf(s / 100.0, 0.0, 1.0)
	var col := Color(1, 1, 1, 0.5).lerp(UIKit.AMBER, clampf(t * 1.6, 0.0, 1.0))
	if t >= 0.5:
		col = UIKit.AMBER.lerp(UIKit.RED, (t - 0.5) * 2.0)
	if fighting:
		col = UIKit.RED
	col.a = 0.45 + 0.5 * t
	var width := 0.25 + 0.25 * t
	draw_arc(center, radius, screen_ang - width, screen_ang + width, 16, Color(0, 0, 0, 0.35), 7.0)
	draw_arc(center, radius, screen_ang - width, screen_ang + width, 16, col, 4.0)
	# Fill tick showing how close to full detection.
	var tip := center + Vector2(cos(screen_ang), sin(screen_ang)) * (radius + 10.0)
	draw_circle(tip, 3.0 + 3.0 * t, col)


func _draw_damage(center: Vector2) -> void:
	var cam := _cam()
	if cam == null:
		return
	for d in _damage:
		var dir: Vector3 = -d[0]
		var ang := atan2(dir.x, -dir.z) + cam.global_rotation.y - PI * 0.5
		var a: float = clampf(d[1], 0.0, 1.0)
		draw_arc(center, 200.0, ang - 0.35, ang + 0.35, 20, Color(0.9, 0.1, 0.05, 0.6 * a), 10.0)


func _project(world: Vector3) -> Array:
	var cam := _cam()
	if cam == null:
		return [false, Vector2.ZERO]
	# Points on the camera plane cannot be projected; nudge them forward.
	var local := cam.global_transform.affine_inverse() * world
	if absf(local.z) < 0.05:
		world = cam.global_transform * Vector3(local.x, local.y, -0.05)
	var behind := cam.is_position_behind(world)
	var sp := cam.unproject_position(world)
	if behind:
		sp = size - sp
	var margin := 40.0
	var on := not behind and Rect2(Vector2(margin, margin), size - Vector2(margin, margin) * 2.0).has_point(sp)
	if not on:
		var c := size * 0.5
		var d := sp - c
		if d.length() < 1.0:
			d = Vector2.DOWN
		var k := minf((size.x * 0.5 - margin) / maxf(absf(d.x), 0.001), (size.y * 0.5 - margin) / maxf(absf(d.y), 0.001))
		sp = c + d * k
	return [on, sp]


func _draw_tags() -> void:
	for n in get_tree().get_nodes_in_group("tagged"):
		var node := n as Node3D
		if node == null or not node.is_visible_in_tree():
			continue
		var is_enemy := node is Enemy
		var p := node.global_position + Vector3.UP * (2.0 if is_enemy else 0.3)
		var r := _project(p)
		var col := UIKit.AMBER if is_enemy else UIKit.BLUE
		var sp: Vector2 = r[1]
		var s := 7.0
		var pts := PackedVector2Array([sp + Vector2(0, -s), sp + Vector2(s, 0), sp + Vector2(0, s), sp + Vector2(-s, 0), sp + Vector2(0, -s)])
		draw_polyline(pts, Color(0, 0, 0, 0.6), 4.0)
		draw_polyline(pts, col, 2.0)
		if r[0]:
			var dist := player.global_position.distance_to(node.global_position)
			draw_string(_font, sp + Vector2(10, 5), "%dm" % int(dist), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)


func _draw_objective_marker() -> void:
	if controller == null:
		return
	var o := controller.current_objective()
	if o == null or not controller.objective_targets.has(o.id):
		return
	var t = controller.objective_targets[o.id]
	var pos: Vector3
	if t is Node3D:
		if not is_instance_valid(t) or not (t as Node3D).is_visible_in_tree():
			return
		pos = (t as Node3D).global_position
	elif t is Vector3:
		pos = t
	else:
		return
	var r := _project(pos + Vector3.UP * 1.2)
	var sp: Vector2 = r[1]
	var col := Color(0.45, 1.0, 0.6, 0.85)
	draw_circle(sp, 5.0, Color(0, 0, 0, 0.5))
	draw_arc(sp, 9.0, 0, TAU, 24, col, 2.0)
	draw_circle(sp, 3.0, col)
	var dist := player.global_position.distance_to(pos)
	draw_string(_font, sp + Vector2(-20, 26), "%dm" % int(dist), HORIZONTAL_ALIGNMENT_CENTER, 40, 14, col)
