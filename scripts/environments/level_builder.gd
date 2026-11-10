class_name LevelBuilder
extends RefCounted
## Modular environment kit: textured floors, walls with door/window openings,
## rooms, stairs, railings, catwalks, light fixtures and Poly Haven props with
## generated colliders and cover points. Geometry is added under `root`
## (a child of the NavigationRegion3D so it is part of the navmesh bake).

const TEX := "res://assets/textures/%s/%s.jpg"
const MODEL := "res://assets/models/polyhaven/%s/%s_1k.gltf"

## name -> [texture id or "", tint, uv scale (tiles per metre), roughness, metallic]
const MATERIALS := {
	"floor_concrete": ["concrete_floor_worn_001", Color(0.72, 0.72, 0.72), 0.22, 0.9, 0.0],
	"floor_dark": ["concrete_floor_worn_001", Color(0.42, 0.43, 0.45), 0.22, 0.85, 0.0],
	"wall_interior": ["painted_concrete", Color(0.5, 0.54, 0.58), 0.3, 0.9, 0.0],
	"wall_navy": ["painted_concrete", Color(0.24, 0.29, 0.38), 0.3, 0.85, 0.0],
	"wall_olive": ["painted_concrete", Color(0.36, 0.38, 0.3), 0.3, 0.9, 0.0],
	"wall_white": ["painted_concrete", Color(0.72, 0.74, 0.75), 0.3, 0.8, 0.0],
	"wall_exterior": ["concrete_wall_008", Color(0.62, 0.62, 0.6), 0.2, 0.95, 0.0],
	"asphalt": ["asphalt_02", Color(0.55, 0.55, 0.55), 0.12, 0.95, 0.0],
	"gravel": ["gravel_floor", Color(0.55, 0.53, 0.5), 0.25, 1.0, 0.0],
	"metal_floor": ["metal_plate", Color(0.6, 0.62, 0.64), 0.35, 0.55, 0.6],
	"corrugated": ["rusty_corrugated_iron", Color(0.45, 0.5, 0.45), 0.3, 0.75, 0.3],
	"tile": ["worn_tile_floor", Color(0.7, 0.72, 0.74), 0.4, 0.6, 0.0],
	"grate": ["rusty_metal_grid", Color(0.55, 0.55, 0.55), 0.6, 0.6, 0.7],
	"shutter": ["painted_metal_shutter", Color(0.5, 0.52, 0.55), 0.35, 0.6, 0.4],
	"ceiling": ["painted_concrete", Color(0.3, 0.31, 0.33), 0.25, 0.95, 0.0],
	"trim_dark": ["", Color(0.07, 0.075, 0.08), 1.0, 0.45, 0.7],
	"trim_steel": ["", Color(0.32, 0.34, 0.36), 1.0, 0.4, 0.8],
	"trim_amber": ["", Color(0.78, 0.55, 0.1), 1.0, 0.55, 0.2],
	"trim_red": ["", Color(0.55, 0.08, 0.06), 1.0, 0.6, 0.1],
	"trim_olive": ["", Color(0.28, 0.3, 0.22), 1.0, 0.7, 0.2],
	"rubber": ["", Color(0.05, 0.05, 0.05), 1.0, 0.9, 0.0],
}

var root: Node3D
var cover_root: Node3D
var _mats: Dictionary = {}
var _model_cache: Dictionary = {}
var _aabb_cache: Dictionary = {}
var light_count: int = 0
var shadow_light_count: int = 0
## Hard cap on shadow-casting omni/spot lights (performance budget).
var max_shadow_lights: int = 10


func _init(geometry_root: Node3D, covers: Node3D) -> void:
	root = geometry_root
	cover_root = covers


# =========================================================================== materials

func mat(name: String) -> StandardMaterial3D:
	if _mats.has(name):
		return _mats[name]
	var m := StandardMaterial3D.new()
	if name == "glass":
		m.albedo_color = Color(0.45, 0.6, 0.7, 0.18)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.05
		m.metallic = 0.6
	elif name.begins_with("emissive_"):
		var c := Color(1.0, 0.78, 0.45)
		match name:
			"emissive_cool": c = Color(0.75, 0.88, 1.0)
			"emissive_red": c = Color(1.0, 0.15, 0.1)
			"emissive_green": c = Color(0.3, 1.0, 0.5)
			"emissive_blue": c = Color(0.3, 0.6, 1.0)
		m.albedo_color = c
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 3.0
	elif MATERIALS.has(name):
		var d: Array = MATERIALS[name]
		m.albedo_color = d[1]
		m.roughness = d[3]
		m.metallic = d[4]
		if d[0] != "":
			var a := TEX % [d[0], "albedo"]
			if ResourceLoader.exists(a):
				m.albedo_texture = load(a)
				var n := TEX % [d[0], "normal"]
				if ResourceLoader.exists(n):
					m.normal_enabled = true
					m.normal_texture = load(n)
					m.normal_scale = 0.8
				var r := TEX % [d[0], "roughness"]
				if ResourceLoader.exists(r):
					m.roughness_texture = load(r)
					m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
				m.uv1_triplanar = true
				m.uv1_world_triplanar = true
				m.uv1_triplanar_sharpness = 4.0
				var s: float = d[2]
				m.uv1_scale = Vector3(s, s, s)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	else:
		push_warning("LevelBuilder: unknown material %s" % name)
		m.albedo_color = Color(1, 0, 1)
	_mats[name] = m
	return m


# =========================================================================== primitives

func box(center: Vector3, size: Vector3, material: String, collide: bool = true, surface: String = "concrete", yaw_deg: float = 0.0, layer: int = 1) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat(material)
	if collide:
		var body := StaticBody3D.new()
		body.collision_layer = layer
		body.collision_mask = 0
		body.set_meta("surface", surface)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		body.add_child(cs)
		body.add_child(mi)
		root.add_child(body)
		body.position = center
		body.rotation_degrees.y = yaw_deg
	else:
		root.add_child(mi)
		mi.position = center
		mi.rotation_degrees.y = yaw_deg
	return mi


## Horizontal slab: top surface at y.
func floor_rect(x0: float, z0: float, x1: float, z1: float, y: float, material: String, surface: String = "concrete", thickness: float = 0.3) -> void:
	box(Vector3((x0 + x1) * 0.5, y - thickness * 0.5, (z0 + z1) * 0.5), Vector3(absf(x1 - x0), thickness, absf(z1 - z0)), material, true, surface)


func ceiling_rect(x0: float, z0: float, x1: float, z1: float, y: float, material: String = "ceiling", thickness: float = 0.25) -> void:
	var mi := box(Vector3((x0 + x1) * 0.5, y + thickness * 0.5, (z0 + z1) * 0.5), Vector3(absf(x1 - x0), thickness, absf(z1 - z0)), material, true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## Straight wall between two XZ points. openings: [{"at": metres from start (centre), "w": width, "bottom": 0, "top": 2.6}]
func wall(a: Vector2, b: Vector2, y0: float, height: float, material: String, thickness: float = 0.3, openings: Array = []) -> void:
	var length := a.distance_to(b)
	if length < 0.01:
		return
	var dir := (b - a) / length
	var yaw := rad_to_deg(atan2(-dir.y, dir.x))
	var segs := []   # [start, end, bottom, top]
	var ops := openings.duplicate()
	ops.sort_custom(func(p, q): return float(p["at"]) < float(q["at"]))
	var cursor := 0.0
	for o in ops:
		var w: float = o.get("w", 1.6)
		var s: float = clampf(float(o["at"]) - w * 0.5, 0.0, length)
		var e: float = clampf(float(o["at"]) + w * 0.5, 0.0, length)
		var bot: float = o.get("bottom", 0.0)
		var top: float = minf(o.get("top", 2.7), height)
		if s > cursor:
			segs.append([cursor, s, 0.0, height])
		if bot > 0.0:
			segs.append([s, e, 0.0, bot])
		if top < height:
			segs.append([s, e, top, height])
		if o.get("glass", false) and bot > 0.0:
			segs.append([s, e, bot, top, "glass"])
		cursor = e
	if cursor < length:
		segs.append([cursor, length, 0.0, height])
	for sg in segs:
		var l: float = sg[1] - sg[0]
		var h: float = sg[3] - sg[2]
		if l < 0.01 or h < 0.01:
			continue
		var mid: float = (sg[0] + sg[1]) * 0.5
		var p2 := a + dir * mid
		var center := Vector3(p2.x, y0 + (sg[2] + sg[3]) * 0.5, p2.y)
		if sg.size() > 4:
			box(center, Vector3(l, h, 0.04), "glass", true, "glass", yaw, 32)
		else:
			box(center, Vector3(l, h, thickness), material, true, "concrete", yaw)
	# Door / window frames in dark trim for readability.
	for o in ops:
		var w2: float = o.get("w", 1.6)
		var bot2: float = o.get("bottom", 0.0)
		var top2: float = minf(o.get("top", 2.7), height)
		for side in [-1.0, 1.0]:
			var p3: Vector2 = a + dir * (float(o["at"]) + side * (w2 * 0.5 + 0.04))
			box(Vector3(p3.x, y0 + (bot2 + top2) * 0.5, p3.y), Vector3(0.08, top2 - bot2, thickness + 0.06), "trim_dark", false, "metal", yaw)
		var pt := a + dir * float(o["at"])
		if top2 < height:
			box(Vector3(pt.x, y0 + top2 + 0.04, pt.y), Vector3(w2 + 0.16, 0.08, thickness + 0.06), "trim_dark", false, "metal", yaw)


## Room with floor, walls (with openings per side) and optional ceiling.
## sides: {"n": openings, "s": ..., "e": ..., "w": ...}; north = -Z (z0), west = -X (x0).
## skip: sides not to build (shared walls).
func room(x0: float, z0: float, x1: float, z1: float, y: float, height: float, wall_mat: String, floor_mat: String,
		sides: Dictionary = {}, skip: Array = [], ceiling: bool = true, floor_surface: String = "concrete") -> void:
	floor_rect(x0, z0, x1, z1, y, floor_mat, floor_surface)
	if not skip.has("n"):
		wall(Vector2(x0, z0), Vector2(x1, z0), y, height, wall_mat, 0.3, sides.get("n", []))
	if not skip.has("s"):
		wall(Vector2(x0, z1), Vector2(x1, z1), y, height, wall_mat, 0.3, sides.get("s", []))
	if not skip.has("w"):
		wall(Vector2(x0, z0), Vector2(x0, z1), y, height, wall_mat, 0.3, sides.get("w", []))
	if not skip.has("e"):
		wall(Vector2(x1, z0), Vector2(x1, z1), y, height, wall_mat, 0.3, sides.get("e", []))
	if ceiling:
		ceiling_rect(x0 - 0.15, z0 - 0.15, x1 + 0.15, z1 + 0.15, y + height)
	# Skirting trim
	trim_line(Vector2(x0, z0), Vector2(x1, z0), y, sides.get("n", []), skip.has("n"))
	trim_line(Vector2(x0, z1), Vector2(x1, z1), y, sides.get("s", []), skip.has("s"))


func trim_line(_a: Vector2, _b: Vector2, _y: float, _ops: Array, _skip: bool) -> void:
	pass


## Stairs rising along +dir; visual steps plus a smooth collision ramp.
func stairs(base: Vector3, dir: Vector3, width: float, rise: float, run: float, material: String = "metal_floor") -> void:
	dir = dir.normalized()
	var steps := maxi(2, int(round(rise / 0.2)))
	var step_h := rise / steps
	var step_d := run / steps
	var yaw := rad_to_deg(atan2(-dir.x, -dir.z))
	for i in steps:
		var c := base + dir * (step_d * (i + 0.5)) + Vector3.UP * (step_h * (i + 0.5))
		box(c, Vector3(width, step_h, step_d), material, false, "metal", yaw)
	var ramp_len := sqrt(rise * rise + run * run)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.set_meta("surface", "metal")
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(width, 0.1, ramp_len)
	cs.shape = bs
	body.add_child(cs)
	root.add_child(body)
	body.position = base + dir * (run * 0.5) + Vector3.UP * (rise * 0.5)
	body.basis = Basis.looking_at(dir * run + Vector3.UP * rise, Vector3.UP)
	# Side guards: stop agents/players from stepping onto the ramp sideways.
	for s2 in [-1.0, 1.0]:
		var side_body := StaticBody3D.new()
		side_body.collision_layer = 1
		var scs := CollisionShape3D.new()
		var sbs := BoxShape3D.new()
		sbs.size = Vector3(0.08, 1.1, ramp_len)
		scs.shape = sbs
		side_body.add_child(scs)
		root.add_child(side_body)
		var off: Vector3 = dir.cross(Vector3.UP).normalized() * (width * 0.5 + 0.06) * s2
		side_body.position = base + off + dir * (run * 0.5) + Vector3.UP * (rise * 0.5 + 0.5)
		side_body.basis = Basis.looking_at(dir * run + Vector3.UP * rise, Vector3.UP)
	# Side stringers
	for s in [-1.0, 1.0]:
		var side: Vector3 = dir.cross(Vector3.UP).normalized() * (width * 0.5 + 0.04) * s
		var stringer := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.06, 0.25, ramp_len)
		stringer.mesh = sm
		stringer.material_override = mat("trim_dark")
		root.add_child(stringer)
		stringer.position = base + side + dir * (run * 0.5) + Vector3.UP * (rise * 0.5)
		stringer.basis = Basis.looking_at(dir * run + Vector3.UP * rise, Vector3.UP)


func railing(a: Vector3, b: Vector3, height: float = 1.05) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.1:
		return
	var yaw := rad_to_deg(atan2(-d.z, d.x))
	var mid := (a + b) * 0.5
	box(mid + Vector3.UP * height, Vector3(length, 0.05, 0.05), "trim_amber", false, "metal", yaw)
	box(mid + Vector3.UP * height * 0.5, Vector3(length, 0.035, 0.035), "trim_amber", false, "metal", yaw)
	var posts := int(length / 1.5) + 1
	for i in posts + 1:
		var p := a.lerp(b, float(i) / posts)
		box(p + Vector3.UP * height * 0.5, Vector3(0.05, height, 0.05), "trim_dark", false, "metal")
	# Invisible collider so nobody falls off.
	var body := StaticBody3D.new()
	body.collision_layer = 32
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(length, height, 0.1)
	cs.shape = bs
	body.add_child(cs)
	root.add_child(body)
	body.position = mid + Vector3.UP * height * 0.5
	body.rotation_degrees.y = yaw


func pillar(pos: Vector3, size: Vector2, height: float, material: String = "wall_exterior") -> void:
	box(pos + Vector3.UP * height * 0.5, Vector3(size.x, height, size.y), material)


## Chain-link style fence: posts, rails and a see-through mesh panel (layer 6: blocks movement only).
func fence(a: Vector2, b: Vector2, y: float, height: float = 3.0) -> void:
	var d := b - a
	var length := d.length()
	var yaw := rad_to_deg(atan2(-d.y, d.x))
	var mid := (a + b) * 0.5
	box(Vector3(mid.x, y + height * 0.5, mid.y), Vector3(length, height, 0.04), "grate", true, "metal", yaw, 32).transparency = 0.25
	box(Vector3(mid.x, y + height, mid.y), Vector3(length, 0.06, 0.06), "trim_steel", false, "metal", yaw)
	var posts := int(length / 3.0) + 1
	for i in posts + 1:
		var p := a.lerp(b, float(i) / posts)
		box(Vector3(p.x, y + height * 0.5, p.y), Vector3(0.08, height + 0.1, 0.08), "trim_steel", false, "metal")


# =========================================================================== lights

func _register_light(l: Light3D, shadows: bool, gameplay: bool = true) -> void:
	light_count += 1
	if shadows and shadow_light_count < max_shadow_lights:
		l.shadow_enabled = true
		l.shadow_bias = 0.05
		shadow_light_count += 1
	else:
		l.shadow_enabled = false
	if gameplay:
		l.add_to_group("level_light")


func omni(pos: Vector3, color: Color, energy: float, range_m: float, shadows: bool = false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = range_m
	l.omni_attenuation = 1.2
	l.light_volumetric_fog_energy = 0.6
	root.add_child(l)
	l.position = pos
	_register_light(l, shadows)
	return l


func spot(pos: Vector3, target: Vector3, color: Color, energy: float, range_m: float, angle: float, shadows: bool = true) -> SpotLight3D:
	var l := SpotLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.spot_range = range_m
	l.spot_angle = angle
	l.spot_attenuation = 1.0
	l.light_volumetric_fog_energy = 1.5
	root.add_child(l)
	l.position = pos
	if not (target - pos).normalized().is_equal_approx(Vector3.UP) and not (target - pos).normalized().is_equal_approx(Vector3.DOWN):
		l.look_at(target, Vector3.UP)
	else:
		l.rotation_degrees.x = -90.0 if target.y < pos.y else 90.0
	_register_light(l, shadows)
	return l


## Ceiling fixture. kind: "industrial" (hanging lamp), "fluorescent", "strip", "cage"
func ceiling_light(pos: Vector3, kind: String = "industrial", color: Color = Color(1.0, 0.8, 0.55), energy: float = 2.2, range_m: float = 9.0, shadows: bool = false) -> OmniLight3D:
	match kind:
		"industrial":
			prop("hanging_industrial_lamp", pos + Vector3.UP * 0.05, 0.0, 1.0, false)
			box(pos + Vector3(0, -1.25, 0), Vector3(0.22, 0.03, 0.22), "emissive_warm", false)
			return omni(pos + Vector3(0, -1.5, 0), color, energy, range_m, shadows)
		"fluorescent":
			prop("mounted_fluorescent_lights", pos, 0.0, 1.0, false)
		"strip":
			box(pos, Vector3(1.6, 0.06, 0.18), "trim_dark", false)
			box(pos + Vector3(0, -0.035, 0), Vector3(1.5, 0.02, 0.12), "emissive_cool" if color.b > color.r else "emissive_warm", false)
	return omni(pos + Vector3(0, -0.7, 0), color, energy, range_m, shadows)


## Wall/pole flood light aimed at a target point.
func flood_light(pos: Vector3, target: Vector3, color: Color = Color(1.0, 0.85, 0.6), energy: float = 6.0, range_m: float = 26.0, angle: float = 38.0) -> SpotLight3D:
	var m := prop("security_light", pos, rad_to_deg(atan2(-(target - pos).x, -(target - pos).z)), 1.6, false)
	if m == null:
		box(pos, Vector3(0.4, 0.3, 0.3), "trim_dark", false)
	return spot(pos + (target - pos).normalized() * 0.3, target, color, energy, range_m, angle, true)


func alarm_light(pos: Vector3) -> OmniLight3D:
	box(pos, Vector3(0.18, 0.12, 0.18), "emissive_red", false)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.12, 0.08)
	l.light_energy = 0.0
	l.omni_range = 9.0
	l.visible = false
	root.add_child(l)
	l.position = pos + Vector3.DOWN * 0.2
	l.add_to_group("alarm_light")
	return l


# =========================================================================== props

func _load_model(id: String) -> PackedScene:
	if _model_cache.has(id):
		return _model_cache[id]
	var path := MODEL % [id, id]
	var ps: PackedScene = load(path) if ResourceLoader.exists(path) else null
	_model_cache[id] = ps
	return ps


func _compute_aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var inv := n.global_transform.affine_inverse()
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var bb := (inv * mi.global_transform) * mi.get_aabb()
		if first:
			out = bb
			first = false
		else:
			out = out.merge(bb)
	return out


## Places a Poly Haven model. Adds a box collider from its bounds and, for cover
## props, cover points on each side. Returns the model instance (or null if missing).
func prop(id: String, pos: Vector3, yaw_deg: float = 0.0, scale_: float = 1.0, collide: bool = true, cover: bool = false, surface: String = "metal") -> Node3D:
	var ps := _load_model(id)
	if ps == null:
		return null
	var inst := ps.instantiate() as Node3D
	var holder := Node3D.new()
	holder.name = id
	root.add_child(holder)
	holder.position = pos
	holder.rotation_degrees.y = yaw_deg
	holder.add_child(inst)
	inst.scale = Vector3.ONE * scale_
	for c in inst.find_children("*", "MeshInstance3D", true, false):
		(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if collide or cover:
		var key := "%s@%.2f" % [id, scale_]
		var bb: AABB
		if _aabb_cache.has(key):
			bb = _aabb_cache[key]
		else:
			bb = _compute_aabb(holder)
			_aabb_cache[key] = bb
		if collide:
			var body := StaticBody3D.new()
			body.collision_layer = 1
			body.set_meta("surface", surface)
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = bb.size.max(Vector3(0.1, 0.1, 0.1))
			cs.shape = bs
			cs.position = bb.get_center()
			body.add_child(cs)
			holder.add_child(body)
		if cover:
			add_cover_points(holder.global_transform * bb.get_center(), bb.size, yaw_deg, bb.size.y > 1.4)
	return inst


func add_cover_points(center: Vector3, size: Vector3, yaw_deg: float, high: bool) -> void:
	var basis := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	var ground := center.y - size.y * 0.5
	for d in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var off: Vector3 = d * (Vector3(size.x, 0, size.z) * 0.5 + Vector3(0.6, 0, 0.6))
		var cp := CoverPoint.new()
		cp.high = high
		cover_root.add_child(cp)
		cp.global_position = Vector3(center.x, ground, center.z) + basis * off


## Simple procedural cover block (concrete jersey barrier / crate stack).
func cover_block(pos: Vector3, size: Vector3, material: String = "wall_exterior", yaw_deg: float = 0.0) -> void:
	box(pos + Vector3.UP * size.y * 0.5, size, material, true, "concrete", yaw_deg)
	add_cover_points(pos + Vector3.UP * size.y * 0.5, size, yaw_deg, size.y > 1.4)


## Stack of military crates (each 1.7 x 0.64 x 0.73 m at this scale). 2 levels = crouch cover.
func crate_stack(pos: Vector3, yaw_deg: float = 0.0, levels: int = 2) -> void:
	prop("wooden_military_crate", pos, yaw_deg, 1.4, false)
	for i in range(1, levels):
		prop("wooden_military_crate", pos + Vector3(0, 0.64 * i, 0), yaw_deg + (6.0 if i % 2 == 1 else -4.0), 1.4, false)
	var size := Vector3(1.74, 0.64 * levels, 0.75)
	box(pos + Vector3.UP * size.y * 0.5, size, "trim_dark", true, "wood", yaw_deg).visible = false
	add_cover_points(pos + Vector3.UP * size.y * 0.5, size, yaw_deg, size.y > 1.4)


## Shipping container (6.1 x 2.6 x 2.44 m) with high cover points. tint: olive / navy / rust.
func container(pos: Vector3, yaw_deg: float, tint: String = "olive") -> void:
	var key := "container_" + tint
	if not _mats.has(key):
		var base := mat("corrugated").duplicate() as StandardMaterial3D
		base.albedo_color = {"olive": Color(0.36, 0.42, 0.28), "navy": Color(0.2, 0.27, 0.4), "rust": Color(0.55, 0.3, 0.2)}.get(tint, Color(0.4, 0.4, 0.4))
		_mats[key] = base
	var size := Vector3(6.1, 2.6, 2.44)
	box(pos + Vector3.UP * 1.3, size, key, true, "metal", yaw_deg)
	add_cover_points(pos + Vector3.UP * 1.3, size, yaw_deg, true)


## Parked truck (cab + box body + wheels) usable as high cover.
func truck(pos: Vector3, yaw_deg: float) -> void:
	var basis := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	box(pos + basis * Vector3(0, 2.0, 1.5), Vector3(2.5, 2.8, 8.0), "corrugated", true, "metal", yaw_deg)
	box(pos + basis * Vector3(0, 1.4, -4.0), Vector3(2.4, 2.2, 2.4), "trim_olive", true, "metal", yaw_deg)
	box(pos + basis * Vector3(0, 2.0, -5.15), Vector3(2.0, 0.8, 0.05), "glass", false, "glass", yaw_deg)
	for z in [-4.0, -1.0, 3.5]:
		for x in [-1.2, 1.2]:
			box(pos + basis * Vector3(x, 0.45, z), Vector3(0.35, 0.9, 0.9), "rubber", false, "metal", yaw_deg)
	add_cover_points(pos + Vector3.UP * 1.5, Vector3(2.6, 3, 10.5), yaw_deg, true)
