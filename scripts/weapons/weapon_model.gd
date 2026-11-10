class_name WeaponModel
extends RefCounted
## Builds the procedural (mid-poly, kit-bashed) weapon meshes. Grip at origin,
## barrel along -Z, a "Muzzle" Node3D at the barrel tip.

static var _mats: Dictionary = {}


static func _m(key: String) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	match key:
		"metal":
			m.albedo_color = Color(0.09, 0.095, 0.1)
			m.metallic = 0.85
			m.roughness = 0.38
		"polymer":
			m.albedo_color = Color(0.13, 0.135, 0.13)
			m.roughness = 0.75
		"tan":
			m.albedo_color = Color(0.36, 0.32, 0.24)
			m.roughness = 0.7
		"wood":
			m.albedo_color = Color(0.22, 0.14, 0.08)
			m.roughness = 0.6
		"glass":
			m.albedo_color = Color(0.25, 0.6, 0.4)
			m.emission_enabled = true
			m.emission = Color(0.2, 0.9, 0.4)
			m.emission_energy_multiplier = 0.6
			m.metallic = 0.5
			m.roughness = 0.1
	_mats[key] = m
	return m


static func _box(root: Node3D, size: Vector3, pos: Vector3, mat: String, rot: Vector3 = Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = _m(mat)
	mi.position = pos
	mi.rotation_degrees = rot
	root.add_child(mi)


static func _cyl(root: Node3D, r: float, length: float, pos: Vector3, mat: String) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = length
	c.radial_segments = 10
	mi.mesh = c
	mi.material_override = _m(mat)
	mi.position = pos
	mi.rotation_degrees = Vector3(90, 0, 0)
	root.add_child(mi)


static func build(model: int) -> Node3D:
	var root := Node3D.new()
	root.name = "WeaponModel"
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	match model:
		WeaponData.Model.PISTOL:
			_box(root, Vector3(0.035, 0.11, 0.05), Vector3(0, -0.04, 0.01), "polymer", Vector3(-12, 0, 0))   # grip
			_box(root, Vector3(0.036, 0.04, 0.2), Vector3(0, 0.035, -0.06), "metal")                         # slide
			_box(root, Vector3(0.03, 0.02, 0.12), Vector3(0, 0.005, -0.04), "polymer")                       # frame
			_cyl(root, 0.017, 0.16, Vector3(0, 0.035, -0.24), "metal")                                       # suppressor
			muzzle.position = Vector3(0, 0.035, -0.33)
		WeaponData.Model.RIFLE:
			_box(root, Vector3(0.05, 0.08, 0.32), Vector3(0, 0.05, -0.1), "metal")          # receiver
			_box(root, Vector3(0.055, 0.07, 0.26), Vector3(0, 0.05, -0.38), "polymer")      # handguard
			_cyl(root, 0.012, 0.22, Vector3(0, 0.05, -0.6), "metal")                        # barrel
			_cyl(root, 0.02, 0.07, Vector3(0, 0.05, -0.72), "metal")                        # flash hider
			_box(root, Vector3(0.035, 0.12, 0.05), Vector3(0, -0.05, 0.0), "polymer", Vector3(-15, 0, 0))  # grip
			_box(root, Vector3(0.035, 0.14, 0.06), Vector3(0, -0.04, -0.17), "polymer", Vector3(10, 0, 0)) # magazine
			_box(root, Vector3(0.045, 0.09, 0.24), Vector3(0, 0.03, 0.17), "tan")           # stock
			_box(root, Vector3(0.04, 0.05, 0.12), Vector3(0, 0.115, -0.1), "metal")         # optic body
			_box(root, Vector3(0.03, 0.03, 0.005), Vector3(0, 0.12, -0.04), "glass")        # optic lens
			muzzle.position = Vector3(0, 0.05, -0.77)
		WeaponData.Model.SHOTGUN:
			_box(root, Vector3(0.055, 0.08, 0.3), Vector3(0, 0.05, -0.08), "metal")
			_cyl(root, 0.02, 0.5, Vector3(0, 0.07, -0.45), "metal")                          # barrel
			_cyl(root, 0.018, 0.42, Vector3(0, 0.03, -0.42), "metal")                        # tube
			_box(root, Vector3(0.06, 0.06, 0.16), Vector3(0, 0.03, -0.42), "polymer")       # pump
			_box(root, Vector3(0.035, 0.12, 0.05), Vector3(0, -0.05, 0.0), "polymer", Vector3(-15, 0, 0))
			_box(root, Vector3(0.05, 0.1, 0.26), Vector3(0, 0.02, 0.18), "polymer")         # stock
			muzzle.position = Vector3(0, 0.07, -0.71)
	root.add_child(muzzle)
	for mi in root.get_children():
		if mi is MeshInstance3D:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return root
