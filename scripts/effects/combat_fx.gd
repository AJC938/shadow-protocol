class_name CombatFX
extends RefCounted
## Lightweight one-shot combat effects: muzzle flash, tracer, impact sparks/dust, blood.

static var _flash_mat: StandardMaterial3D
static var _tracer_mat: StandardMaterial3D
static var _spark_mat: StandardMaterial3D
static var _dust_mat: StandardMaterial3D
static var _blood_mat: StandardMaterial3D
static var _decal_tex: GradientTexture2D


static func _scene_root(n: Node) -> Node:
	var tree := n.get_tree()
	return tree.current_scene if tree and tree.current_scene else n


static func _unshaded(c: Color, additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = true
	return m


static func muzzle_flash(owner: Node, pos: Vector3, dir: Vector3, scale_: float, suppressed: bool) -> void:
	var root := _scene_root(owner)
	if _flash_mat == null:
		_flash_mat = _unshaded(Color(1.0, 0.75, 0.35, 0.9), true)
	var holder := Node3D.new()
	root.add_child(holder)
	holder.global_position = pos
	if not suppressed:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.35, 0.35) * scale_
		q.mesh = qm
		q.material_override = _flash_mat
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(q)
		q.rotation.z = randf() * TAU
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.7, 0.35)
	l.light_energy = (1.2 if suppressed else 4.0) * scale_
	l.omni_range = 5.0 if suppressed else 9.0
	l.shadow_enabled = false
	holder.add_child(l)
	var t := holder.create_tween()
	t.tween_interval(0.045)
	t.tween_callback(holder.queue_free)


static func tracer(owner: Node, from: Vector3, to: Vector3, color: Color = Color(1.0, 0.8, 0.45, 0.8)) -> void:
	var root := _scene_root(owner)
	var length := from.distance_to(to)
	if length < 0.5:
		return
	if _tracer_mat == null:
		_tracer_mat = StandardMaterial3D.new()
		_tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_tracer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_tracer_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_tracer_mat.albedo_color = color
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.012, 0.012, minf(length, 6.0))
	mi.mesh = b
	mi.material_override = _tracer_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var dir := (to - from).normalized()
	mi.global_position = from + dir * minf(length, 6.0) * 0.5
	if absf(dir.dot(Vector3.UP)) < 0.99:
		mi.look_at(mi.global_position + dir, Vector3.UP)
	var t := mi.create_tween()
	t.tween_property(mi, "global_position", to - dir * minf(length, 6.0) * 0.5, minf(0.08, length / 400.0))
	t.tween_callback(mi.queue_free)


static func impact(owner: Node, pos: Vector3, normal: Vector3, flesh: bool) -> void:
	var root := _scene_root(owner)
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 10 if flesh else 14
	p.lifetime = 0.45
	p.explosiveness = 1.0
	p.direction = normal
	p.spread = 35.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.0
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var qm := QuadMesh.new()
	qm.size = Vector2(0.04, 0.04)
	p.mesh = qm
	if flesh:
		if _blood_mat == null:
			_blood_mat = _unshaded(Color(0.35, 0.03, 0.03, 0.9), false)
		p.material_override = _blood_mat
		p.color = Color(0.4, 0.04, 0.04)
	else:
		if _spark_mat == null:
			_spark_mat = _unshaded(Color(1.0, 0.75, 0.4, 1.0), true)
		p.material_override = _spark_mat
		p.color = Color(1.0, 0.7, 0.35)
	root.add_child(p)
	p.global_position = pos + normal * 0.02
	p.emitting = true
	root.get_tree().create_timer(1.0).timeout.connect(p.queue_free)
	if not flesh:
		_bullet_hole(root, pos, normal)


static func _bullet_hole(root: Node, pos: Vector3, normal: Vector3) -> void:
	if _decal_tex == null:
		_decal_tex = GradientTexture2D.new()
		_decal_tex.fill = GradientTexture2D.FILL_RADIAL
		_decal_tex.fill_from = Vector2(0.5, 0.5)
		_decal_tex.fill_to = Vector2(0.5, 0.0)
		var g := Gradient.new()
		g.set_color(0, Color(0.02, 0.02, 0.02, 0.95))
		g.set_color(1, Color(0.05, 0.05, 0.05, 0.0))
		g.add_point(0.35, Color(0.03, 0.03, 0.03, 0.85))
		_decal_tex.gradient = g
		_decal_tex.width = 32
		_decal_tex.height = 32
	var d := Decal.new()
	d.texture_albedo = _decal_tex
	d.size = Vector3(0.09, 0.2, 0.09)
	d.cull_mask = 1
	root.add_child(d)
	d.global_position = pos
	# Decal projects along its local -Y; align -Y with -normal.
	var y := normal.normalized()
	var x := y.cross(Vector3.UP if absf(y.y) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	d.global_transform.basis = Basis(x, y, z)
	var t := d.create_tween()
	t.tween_interval(12.0)
	t.tween_property(d, "modulate:a", 0.0, 2.0)
	t.tween_callback(d.queue_free)
