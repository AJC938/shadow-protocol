class_name CharacterRig
extends Node3D
## Procedural tactical humanoid: hierarchical joint rig, outfit meshes, keyframed
## animations generated at runtime and an AnimationTree for locomotion blending,
## crouch blending, upper-body aim layer and one-shot actions.
##
## Shared by the player (GHOST) and all enemy archetypes (different outfits).

const UPPER_BODY := ["Hips/Spine/AimPivot/Chest", "Hips/Spine/AimPivot/Chest/Neck", "Hips/Spine/AimPivot/Chest/Neck/Head",
	"Hips/Spine/AimPivot/Chest/ArmL", "Hips/Spine/AimPivot/Chest/ArmL/ForearmL", "Hips/Spine/AimPivot/Chest/ArmL/ForearmL/HandL",
	"Hips/Spine/AimPivot/Chest/ArmR", "Hips/Spine/AimPivot/Chest/ArmR/ForearmR", "Hips/Spine/AimPivot/Chest/ArmR/ForearmR/HandR",
	"Hips/Spine/AimPivot/Chest/WeaponMount"]

## Joint name -> path relative to this rig.
const JOINTS := {
	"Hips": "Hips", "Spine": "Hips/Spine", "Chest": "Hips/Spine/AimPivot/Chest",
	"Neck": "Hips/Spine/AimPivot/Chest/Neck", "Head": "Hips/Spine/AimPivot/Chest/Neck/Head",
	"ArmL": "Hips/Spine/AimPivot/Chest/ArmL", "ForearmL": "Hips/Spine/AimPivot/Chest/ArmL/ForearmL",
	"HandL": "Hips/Spine/AimPivot/Chest/ArmL/ForearmL/HandL",
	"ArmR": "Hips/Spine/AimPivot/Chest/ArmR", "ForearmR": "Hips/Spine/AimPivot/Chest/ArmR/ForearmR",
	"HandR": "Hips/Spine/AimPivot/Chest/ArmR/ForearmR/HandR",
	"ThighL": "Hips/ThighL", "ShinL": "Hips/ThighL/ShinL", "FootL": "Hips/ThighL/ShinL/FootL",
	"ThighR": "Hips/ThighR", "ShinR": "Hips/ThighR/ShinR", "FootR": "Hips/ThighR/ShinR/FootR",
	"WeaponMount": "Hips/Spine/AimPivot/Chest/WeaponMount",
}

const HIPS_Y := 0.98

## Outfit presets — palette follows the art bible (charcoal / slate / olive / navy).
const OUTFITS := {
	"ghost": {"cloth": Color(0.11, 0.12, 0.13), "armor": Color(0.2, 0.22, 0.24), "accent": Color(0.3, 0.32, 0.24),
		"skin": Color(0.08, 0.08, 0.09), "visor": Color(0.35, 1.0, 0.55), "helmet": "ops", "pack": "slim", "scale": 1.0},
	"guard": {"cloth": Color(0.27, 0.29, 0.21), "armor": Color(0.19, 0.21, 0.16), "accent": Color(0.62, 0.45, 0.18),
		"skin": Color(0.42, 0.32, 0.26), "visor": Color(0, 0, 0, 0), "helmet": "cap", "pack": "none", "scale": 1.0},
	"specialist": {"cloth": Color(0.12, 0.15, 0.22), "armor": Color(0.24, 0.28, 0.33), "accent": Color(0.3, 0.6, 0.95),
		"skin": Color(0.36, 0.28, 0.22), "visor": Color(0.3, 0.65, 1.0), "helmet": "visor", "pack": "radio", "scale": 1.0},
	"heavy": {"cloth": Color(0.1, 0.1, 0.11), "armor": Color(0.16, 0.17, 0.18), "accent": Color(0.75, 0.16, 0.12),
		"skin": Color(0.1, 0.1, 0.1), "visor": Color(1.0, 0.2, 0.12), "helmet": "heavy", "pack": "heavy", "scale": 1.12},
	"commander": {"cloth": Color(0.09, 0.1, 0.14), "armor": Color(0.22, 0.2, 0.18), "accent": Color(0.8, 0.12, 0.1),
		"skin": Color(0.4, 0.31, 0.26), "visor": Color(1.0, 0.25, 0.15), "helmet": "beret", "pack": "coat", "scale": 1.08},
}

static var _fabric_normal: NoiseTexture2D

var anim_player: AnimationPlayer
var tree: AnimationTree
var joints: Dictionary = {}
var aim_pivot: Node3D
var weapon_mount: Node3D
var weapon_node: Node3D
var muzzle: Node3D
var _aim_amount: float = 0.0
var _crouch_amount: float = 0.0
var _speed_smooth: float = 0.0
var _dead: bool = false
var _visor_mats: Array[StandardMaterial3D] = []


func setup(outfit_name: String) -> void:
	var outfit: Dictionary = OUTFITS.get(outfit_name, OUTFITS["guard"])
	_build_skeleton()
	_build_meshes(outfit)
	scale = Vector3.ONE * float(outfit["scale"])
	_build_animations()
	_build_tree()


# =========================================================================== skeleton

func _joint(parent: Node3D, n: String, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.name = n
	j.position = pos
	parent.add_child(j)
	joints[n] = j
	return j


func _build_skeleton() -> void:
	var hips := _joint(self, "Hips", Vector3(0, HIPS_Y, 0))
	var spine := _joint(hips, "Spine", Vector3(0, 0.1, 0))
	aim_pivot = Node3D.new()
	aim_pivot.name = "AimPivot"
	aim_pivot.position = Vector3(0, 0.12, 0)
	spine.add_child(aim_pivot)
	var chest := _joint(aim_pivot, "Chest", Vector3.ZERO)
	var neck := _joint(chest, "Neck", Vector3(0, 0.33, 0))
	_joint(neck, "Head", Vector3(0, 0.06, 0))
	var arm_l := _joint(chest, "ArmL", Vector3(-0.21, 0.31, 0))
	var fl := _joint(arm_l, "ForearmL", Vector3(0, -0.29, 0))
	_joint(fl, "HandL", Vector3(0, -0.26, 0))
	var arm_r := _joint(chest, "ArmR", Vector3(0.21, 0.31, 0))
	var fr := _joint(arm_r, "ForearmR", Vector3(0, -0.29, 0))
	_joint(fr, "HandR", Vector3(0, -0.26, 0))
	var tl := _joint(hips, "ThighL", Vector3(-0.1, -0.04, 0))
	var sl := _joint(tl, "ShinL", Vector3(0, -0.44, 0))
	_joint(sl, "FootL", Vector3(0, -0.44, 0))
	var tr := _joint(hips, "ThighR", Vector3(0.1, -0.04, 0))
	var sr := _joint(tr, "ShinR", Vector3(0, -0.44, 0))
	_joint(sr, "FootR", Vector3(0, -0.44, 0))
	weapon_mount = _joint(chest, "WeaponMount", Vector3(0.13, 0.12, -0.3))


# =========================================================================== meshes

static func _get_fabric_normal() -> NoiseTexture2D:
	if _fabric_normal == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_CELLULAR
		n.frequency = 0.08
		_fabric_normal = NoiseTexture2D.new()
		_fabric_normal.width = 256
		_fabric_normal.height = 256
		_fabric_normal.seamless = true
		_fabric_normal.as_normal_map = true
		_fabric_normal.bump_strength = 4.0
		_fabric_normal.noise = n
	return _fabric_normal


func _mat(c: Color, rough: float = 0.85, metal: float = 0.0, fabric: bool = true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if fabric:
		m.normal_enabled = true
		m.normal_texture = _get_fabric_normal()
		m.normal_scale = 0.35
		m.uv1_scale = Vector3(3, 3, 3)
	return m


func _glow_mat(c: Color, energy: float = 2.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.roughness = 0.2
	return m


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	parent.add_child(mi)
	return mi


func _box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b


func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 12
	c.rings = 4
	return c


func _cyl(r_top: float, r_bot: float, h: float, seg: int = 12) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


func _sphere(r: float, hemi: bool = false) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * (1.0 if hemi else 2.0)
	s.is_hemisphere = hemi
	s.radial_segments = 16
	s.rings = 8
	return s


func _build_meshes(o: Dictionary) -> void:
	var cloth := _mat(o["cloth"])
	var armor := _mat(o["armor"], 0.6, 0.15, true)
	var accent := _mat(o["accent"], 0.7)
	var skin := _mat(o["skin"], 0.7, 0.0, false)
	var boots := _mat(Color(0.07, 0.07, 0.07), 0.6)
	var strap := _mat(Color(0.08, 0.085, 0.08), 0.8)
	var heavy: bool = o["pack"] == "heavy"
	var bulk := 1.25 if heavy else 1.0

	# --- pelvis / belt
	var hips: Node3D = joints["Hips"]
	_part(hips, _box(0.33 * bulk, 0.2, 0.21 * bulk), cloth, Vector3(0, -0.02, 0))
	_part(hips, _box(0.36 * bulk, 0.06, 0.24 * bulk), strap, Vector3(0, 0.06, 0))
	_part(hips, _box(0.08, 0.1, 0.06), accent, Vector3(0.17 * bulk, 0.0, -0.06))       # pouch
	_part(hips, _box(0.07, 0.14, 0.09), strap, Vector3(0.2 * bulk, -0.06, 0.04))         # holster
	# --- abdomen
	_part(joints["Spine"], _capsule(0.135 * bulk, 0.34), cloth, Vector3(0, 0.08, 0))
	# --- chest + plate carrier
	var chest: Node3D = joints["Chest"]
	_part(chest, _capsule(0.165 * bulk, 0.52), cloth, Vector3(0, 0.14, 0), Vector3.ZERO, Vector3(1.15, 1, 0.72))
	_part(chest, _capsule(0.085 * bulk, 0.5 * bulk), cloth, Vector3(0, 0.29, 0), Vector3(0, 0, 90), Vector3(1, 1, 0.9))
	_part(chest, _box(0.36 * bulk, 0.3, 0.25 * bulk), armor, Vector3(0, 0.15, -0.005))
	_part(chest, _box(0.3 * bulk, 0.06, 0.26 * bulk), strap, Vector3(0, 0.31, 0))
	for i in 3:
		_part(chest, _box(0.09, 0.11, 0.06), accent if i == 1 else strap, Vector3(-0.11 + i * 0.11, 0.04, -0.15 * bulk))
	_part(chest, _box(0.05, 0.3, 0.03), strap, Vector3(-0.13, 0.17, -0.14 * bulk))
	_part(chest, _box(0.05, 0.3, 0.03), strap, Vector3(0.13, 0.17, -0.14 * bulk))
	match o["pack"]:
		"slim":
			_part(chest, _box(0.3, 0.32, 0.1), strap, Vector3(0, 0.15, 0.17))
		"radio":
			_part(chest, _box(0.32, 0.38, 0.16), armor, Vector3(0, 0.15, 0.2))
			_part(chest, _cyl(0.008, 0.012, 0.55, 6), strap, Vector3(0.12, 0.55, 0.22))
			var tip := _part(chest, _sphere(0.02), _glow_mat(o["accent"], 4.0), Vector3(0.12, 0.83, 0.22))
			tip.name = "AntennaLight"
		"heavy":
			_part(chest, _box(0.42, 0.4, 0.14), armor, Vector3(0, 0.15, 0.2))
			_part(chest, _box(0.2, 0.12, 0.2), armor, Vector3(-0.3, 0.3, 0), Vector3(0, 0, 18))
			_part(chest, _box(0.2, 0.12, 0.2), armor, Vector3(0.3, 0.3, 0), Vector3(0, 0, -18))
			_part(chest, _box(0.3, 0.12, 0.05), _mat(o["accent"], 0.6), Vector3(0, 0.25, -0.18))
		"coat":
			_part(hips, _box(0.4, 0.55, 0.28), cloth, Vector3(0, -0.3, 0.02))
			_part(chest, _box(0.08, 0.04, 0.02), _glow_mat(o["accent"], 1.5), Vector3(-0.12, 0.25, -0.15))
	# --- neck + head
	_part(joints["Neck"], _cyl(0.062, 0.075, 0.12), skin, Vector3(0, 0.02, 0))
	var head: Node3D = joints["Head"]
	_part(head, _sphere(0.112), skin, Vector3(0, 0.1, 0), Vector3.ZERO, Vector3(0.92, 1.08, 1.02))
	_part(head, _box(0.1, 0.07, 0.09), skin, Vector3(0, 0.02, -0.04))
	match o["helmet"]:
		"ops":
			_part(head, _sphere(0.135, true), armor, Vector3(0, 0.13, 0.01), Vector3.ZERO, Vector3(1, 0.9, 1.08))
			_part(head, _box(0.2, 0.05, 0.05), strap, Vector3(0, 0.17, -0.11))
			# quad-lens NVG
			for x in [-0.045, -0.015, 0.015, 0.045]:
				var lens := _part(head, _cyl(0.014, 0.016, 0.05, 8), _glow_mat(o["visor"], 3.0), Vector3(x, 0.19, -0.14), Vector3(90, 0, 0))
				_visor_mats.append(lens.material_override)
		"cap":
			_part(head, _sphere(0.122, true), cloth, Vector3(0, 0.13, 0))
			_part(head, _box(0.18, 0.015, 0.1), cloth, Vector3(0, 0.14, -0.13), Vector3(-8, 0, 0))
			_part(head, _box(0.06, 0.04, 0.01), accent, Vector3(0, 0.2, -0.12))
		"visor":
			_part(head, _sphere(0.135, true), armor, Vector3(0, 0.12, 0), Vector3.ZERO, Vector3(1, 1, 1.1))
			var v := _part(head, _box(0.2, 0.05, 0.03), _glow_mat(o["visor"], 2.0), Vector3(0, 0.12, -0.115))
			_visor_mats.append(v.material_override)
		"heavy":
			_part(head, _sphere(0.15), armor, Vector3(0, 0.11, 0), Vector3.ZERO, Vector3(1, 1.05, 1.1))
			var v2 := _part(head, _box(0.16, 0.025, 0.03), _glow_mat(o["visor"], 3.0), Vector3(0, 0.12, -0.155))
			_visor_mats.append(v2.material_override)
			_part(head, _box(0.12, 0.06, 0.04), armor, Vector3(0, 0.04, -0.14))
		"beret":
			_part(head, _sphere(0.12, true), _mat(o["accent"] * 0.6, 0.9), Vector3(0.015, 0.16, 0), Vector3(0, 0, -10), Vector3(1.1, 0.6, 1.05))
			var v3 := _part(head, _box(0.17, 0.03, 0.02), _glow_mat(o["visor"], 1.2), Vector3(0, 0.12, -0.105))
			_visor_mats.append(v3.material_override)
	# --- arms
	for side in ["L", "R"]:
		var sx := -1.0 if side == "L" else 1.0
		var arm: Node3D = joints["Arm" + side]
		_part(arm, _sphere(0.068 * bulk), cloth, Vector3(0, -0.03, 0))
		_part(arm, _box(0.11 * bulk, 0.08, 0.13 * bulk), armor, Vector3(sx * 0.015, 0.0, 0), Vector3(0, 0, -sx * 12))
		_part(arm, _capsule(0.066 * bulk, 0.33), cloth, Vector3(0, -0.14, 0))
		var fa: Node3D = joints["Forearm" + side]
		_part(fa, _capsule(0.056 * bulk, 0.3), cloth, Vector3(0, -0.13, 0))
		_part(fa, _box(0.11 * bulk, 0.1, 0.11 * bulk), strap, Vector3(0, -0.16, 0))
		var hand: Node3D = joints["Hand" + side]
		_part(hand, _box(0.08, 0.1, 0.09), strap, Vector3(0, 0.0, -0.01))
		# legs
		var th: Node3D = joints["Thigh" + side]
		_part(th, _capsule(0.095 * bulk, 0.5), cloth, Vector3(0, -0.21, 0))
		_part(th, _box(0.07, 0.12, 0.05), strap, Vector3(sx * 0.07 * bulk, -0.18, -0.02))
		var sh: Node3D = joints["Shin" + side]
		_part(sh, _capsule(0.072 * bulk, 0.46), cloth, Vector3(0, -0.21, 0))
		_part(sh, _box(0.11 * bulk, 0.11, 0.06), armor, Vector3(0, 0.0, -0.07))         # knee pad
		var ft: Node3D = joints["Foot" + side]
		_part(ft, _box(0.12 * bulk, 0.1, 0.28), boots, Vector3(0, -0.02, -0.05))
		_part(sh, _cyl(0.075, 0.07, 0.16), boots, Vector3(0, -0.37, 0))
	# Shadows on every part; rigs are small enough.
	for mi in find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func set_visor_color(c: Color) -> void:
	for m in _visor_mats:
		m.albedo_color = c
		m.emission = c


## Replaces the held weapon model.
func set_weapon(model: int) -> void:
	if weapon_node:
		weapon_node.queue_free()
	weapon_node = WeaponModel.build(model)
	weapon_mount.add_child(weapon_node)
	muzzle = weapon_node.get_node("Muzzle")


func get_muzzle_position() -> Vector3:
	return muzzle.global_position if muzzle else global_position + Vector3.UP * 1.4


func get_head_position() -> Vector3:
	return (joints["Head"] as Node3D).global_position + Vector3.UP * 0.1


# =========================================================================== animations

static func _pose_base() -> Dictionary:
	return {
		"Hips": Vector3.ZERO, "hips_pos": Vector3(0, HIPS_Y, 0), "Spine": Vector3.ZERO, "Chest": Vector3.ZERO,
		"Neck": Vector3.ZERO, "Head": Vector3.ZERO,
		"ArmR": Vector3(10, 0, -12), "ForearmR": Vector3(70, 0, 0), "HandR": Vector3.ZERO,
		"ArmL": Vector3(38, 0, 30), "ForearmL": Vector3(48, 0, 0), "HandL": Vector3.ZERO,
		"ThighL": Vector3.ZERO, "ShinL": Vector3.ZERO, "FootL": Vector3.ZERO,
		"ThighR": Vector3.ZERO, "ShinR": Vector3.ZERO, "FootR": Vector3.ZERO,
		"WeaponMount": Vector3(-28, 12, 0), "weapon_pos": Vector3(0.11, 0.02, -0.3),
	}


static func _pose_aim() -> Dictionary:
	var p := _pose_base()
	p["ArmR"] = Vector3(22, 0, -18)
	p["ForearmR"] = Vector3(78, 0, 0)
	p["ArmL"] = Vector3(62, 0, 34)
	p["ForearmL"] = Vector3(28, 0, 0)
	p["WeaponMount"] = Vector3(0, 0, 0)
	p["weapon_pos"] = Vector3(0.1, 0.17, -0.28)
	p["Head"] = Vector3(-4, 0, 6)
	return p


static func _gait(phi: float, amp: float, knee: float, bob: float, lean: float, base_y: float = HIPS_Y) -> Dictionary:
	var p := _pose_base()
	var s := sin(phi)
	var c := cos(phi)
	p["ThighL"] = Vector3(amp * s, 0, 0)
	p["ThighR"] = Vector3(-amp * s, 0, 0)
	p["ShinL"] = Vector3(-knee * maxf(0.0, c) - 6.0, 0, 0)
	p["ShinR"] = Vector3(-knee * maxf(0.0, -c) - 6.0, 0, 0)
	p["FootL"] = Vector3(-(p["ThighL"].x + p["ShinL"].x) * 0.55, 0, 0)
	p["FootR"] = Vector3(-(p["ThighR"].x + p["ShinR"].x) * 0.55, 0, 0)
	p["hips_pos"] = Vector3(0, base_y - bob * absf(s), 0)
	p["Hips"] = Vector3(0, 5.0 * s, 0)
	p["Spine"] = Vector3(-lean, -4.0 * s, 0)
	p["Chest"] = Vector3(0, 0, 1.5 * c)
	p["ArmL"] = p["ArmL"] + Vector3(4.0 * s, 0, 0)
	p["ArmR"] = p["ArmR"] + Vector3(-3.0 * s, 0, 0)
	return p


static func _crouch_pose(phi: float, moving: float) -> Dictionary:
	var p := _pose_base()
	var s := sin(phi) * moving
	var c := cos(phi) * moving
	p["hips_pos"] = Vector3(0, 0.6 - 0.02 * absf(s), 0)
	p["Spine"] = Vector3(-22, 0, 0)
	p["Chest"] = Vector3(8, 0, 0)
	p["ThighL"] = Vector3(72 + 16 * s, 0, -4)
	p["ThighR"] = Vector3(72 - 16 * s, 0, 4)
	p["ShinL"] = Vector3(-112 - 12 * maxf(0.0, c), 0, 0)
	p["ShinR"] = Vector3(-112 - 12 * maxf(0.0, -c), 0, 0)
	p["FootL"] = Vector3(38, 0, 0)
	p["FootR"] = Vector3(38, 0, 0)
	return p


func _build_animations() -> void:
	anim_player = AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	add_child(anim_player)
	var lib := AnimationLibrary.new()
	# Locomotion cycles are sampled from pose functions.
	lib.add_animation(&"idle", _cycle(2.4, _idle_pose))
	lib.add_animation(&"walk", _cycle(1.1, _walk_pose))
	lib.add_animation(&"jog", _cycle(0.74, _jog_pose))
	lib.add_animation(&"sprint", _cycle(0.56, _sprint_pose))
	lib.add_animation(&"crouch_idle", _cycle(2.4, _crouch_idle_pose))
	lib.add_animation(&"crouch_walk", _cycle(1.25, _crouch_walk_pose))
	# Upper-body layers / one-shots.
	lib.add_animation(&"aim", _cycle(1.0, _aim_pose_fn, true))
	lib.add_animation(&"fire", _keys(0.14, [
		[0.0, _pose_aim()],
		[0.03, _merge(_pose_aim(), {"WeaponMount": Vector3(6, 0, 0), "weapon_pos": Vector3(0.1, 0.18, -0.23), "Chest": Vector3(2, 0, 0)})],
		[0.14, _pose_aim()]], true))
	lib.add_animation(&"reload", _keys(1.0, [
		[0.0, _pose_base()],
		[0.2, _merge(_pose_base(), {"WeaponMount": Vector3(-10, 25, 35), "ArmL": Vector3(12, 0, 18), "ForearmL": Vector3(60, 0, 0)})],
		[0.5, _merge(_pose_base(), {"WeaponMount": Vector3(-10, 25, 35), "ArmL": Vector3(40, 0, 38), "ForearmL": Vector3(70, 0, 0), "Head": Vector3(-15, 0, 0)})],
		[0.75, _merge(_pose_base(), {"WeaponMount": Vector3(-5, 15, 10), "ArmL": Vector3(45, 0, 30), "ForearmL": Vector3(40, 0, 0)})],
		[1.0, _pose_base()]], true))
	lib.add_animation(&"switch", _keys(0.5, [
		[0.0, _pose_base()],
		[0.25, _merge(_pose_base(), {"WeaponMount": Vector3(-70, 30, 0), "weapon_pos": Vector3(0.15, -0.25, -0.15), "ArmR": Vector3(-5, 0, -8)})],
		[0.5, _pose_base()]], true))
	lib.add_animation(&"interact", _keys(0.8, [
		[0.0, _pose_base()],
		[0.3, _merge(_pose_base(), {"ArmL": Vector3(72, 0, 12), "ForearmL": Vector3(15, 0, 0), "Head": Vector3(-12, 0, 0)})],
		[0.6, _merge(_pose_base(), {"ArmL": Vector3(70, 0, 8), "ForearmL": Vector3(22, 0, 0), "Head": Vector3(-12, 0, 0)})],
		[0.8, _pose_base()]], true))
	lib.add_animation(&"hit", _keys(0.35, [
		[0.0, _pose_base()],
		[0.08, _merge(_pose_base(), {"Chest": Vector3(14, 0, 6), "Head": Vector3(12, 0, 0)})],
		[0.35, _pose_base()]], true))
	var lying := _merge(_pose_base(), {"Hips": Vector3(84, 0, 6), "hips_pos": Vector3(0, 0.2, 0.55), "Spine": Vector3(4, 0, 0),
		"ThighL": Vector3(-70, 0, -14), "ShinL": Vector3(-12, 0, 0), "ThighR": Vector3(-60, 0, 10), "ShinR": Vector3(-40, 0, 0),
		"ArmL": Vector3(150, 0, 40), "ForearmL": Vector3(20, 0, 0), "ArmR": Vector3(120, 0, -50), "ForearmR": Vector3(30, 0, 0),
		"Head": Vector3(-20, 30, 0), "WeaponMount": Vector3(-80, 60, 40)})
	lib.add_animation(&"death", _keys(1.1, [
		[0.0, _pose_base()],
		[0.35, _merge(_pose_base(), {"Hips": Vector3(18, 0, 3), "hips_pos": Vector3(0, 0.72, 0.12), "ThighL": Vector3(40, 0, 0),
			"ShinL": Vector3(-80, 0, 0), "ThighR": Vector3(30, 0, 0), "ShinR": Vector3(-70, 0, 0), "Chest": Vector3(15, 0, 0),
			"ArmL": Vector3(70, 0, 40), "ArmR": Vector3(60, 0, -40)})],
		[0.8, lying],
		[1.1, _merge(lying, {"hips_pos": Vector3(0, 0.17, 0.6)})]], true))
	lib.get_animation(&"death").loop_mode = Animation.LOOP_NONE
	anim_player.add_animation_library(&"", lib)


func _idle_pose(phi: float) -> Dictionary:
	var p := _pose_base()
	p["Chest"] = Vector3(1.5 * sin(phi), 0, 0)
	p["hips_pos"] = Vector3(0, HIPS_Y - 0.006 * (0.5 + 0.5 * sin(phi)), 0)
	p["Head"] = Vector3(0, 6.0 * sin(phi * 0.5), 0)
	return p


func _walk_pose(phi: float) -> Dictionary:
	return _gait(phi, 24.0, 38.0, 0.025, 3.0)


func _jog_pose(phi: float) -> Dictionary:
	return _gait(phi, 34.0, 62.0, 0.05, 8.0)


func _sprint_pose(phi: float) -> Dictionary:
	var p := _gait(phi, 46.0, 92.0, 0.07, 15.0)
	p["WeaponMount"] = Vector3(-45, 35, 20)
	p["ArmL"] = Vector3(30 - 25 * sin(phi), 0, 20)
	return p


func _crouch_idle_pose(phi: float) -> Dictionary:
	var p := _crouch_pose(0.0, 0.0)
	p["Chest"] = Vector3(8 + 1.2 * sin(phi), 0, 0)
	return p


func _crouch_walk_pose(phi: float) -> Dictionary:
	return _crouch_pose(phi, 1.0)


func _aim_pose_fn(_phi: float) -> Dictionary:
	return _pose_aim()


static func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var r := a.duplicate()
	for k in b:
		r[k] = b[k]
	return r


## Samples a looping cycle from a pose function f(phi) with phi in [0, TAU).
func _cycle(length: float, f: Callable, upper_only: bool = false) -> Animation:
	var keys := []
	var n := 12
	for i in n + 1:
		var t := length * float(i) / n
		keys.append([t, f.call(TAU * float(i) / n)])
	var a := _keys(length, keys, upper_only)
	a.loop_mode = Animation.LOOP_LINEAR
	return a


func _keys(length: float, keys: Array, upper_only: bool = false) -> Animation:
	var a := Animation.new()
	a.length = length
	var names: Array = JOINTS.keys()
	for jn in names:
		var path: String = JOINTS[jn]
		if upper_only and not UPPER_BODY.has(path):
			continue
		var tr := a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(tr, NodePath(path))
		for k in keys:
			var pose: Dictionary = k[1]
			var e: Vector3 = pose.get(jn, Vector3.ZERO)
			a.rotation_track_insert_key(tr, k[0], Quaternion.from_euler(e * (PI / 180.0)))
	if not upper_only:
		var hp := a.add_track(Animation.TYPE_POSITION_3D)
		a.track_set_path(hp, NodePath("Hips"))
		for k in keys:
			a.position_track_insert_key(hp, k[0], k[1].get("hips_pos", Vector3(0, HIPS_Y, 0)))
	var wp := a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(wp, NodePath(JOINTS["WeaponMount"]))
	for k in keys:
		a.position_track_insert_key(wp, k[0], k[1].get("weapon_pos", Vector3(0.11, 0.02, -0.3)))
	return a


func _build_tree() -> void:
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	add_child(tree)
	tree.anim_player = tree.get_path_to(anim_player)
	var bt := AnimationNodeBlendTree.new()

	var stand := AnimationNodeBlendSpace1D.new()
	for pt in [[&"idle", 0.0], [&"walk", 1.5], [&"jog", 3.6], [&"sprint", 6.2]]:
		var an := AnimationNodeAnimation.new()
		an.animation = pt[0]
		stand.add_blend_point(an, pt[1], -1, pt[0])
	stand.min_space = 0.0
	stand.max_space = 6.5
	stand.sync = true
	bt.add_node(&"stand", stand, Vector2(0, 0))

	var crouch := AnimationNodeBlendSpace1D.new()
	for pt in [[&"crouch_idle", 0.0], [&"crouch_walk", 1.6]]:
		var an2 := AnimationNodeAnimation.new()
		an2.animation = pt[0]
		crouch.add_blend_point(an2, pt[1], -1, pt[0])
	crouch.min_space = 0.0
	crouch.max_space = 2.5
	bt.add_node(&"crouch", crouch, Vector2(0, 200))

	var cb := AnimationNodeBlend2.new()
	bt.add_node(&"crouch_blend", cb, Vector2(250, 100))
	bt.connect_node(&"crouch_blend", 0, &"stand")
	bt.connect_node(&"crouch_blend", 1, &"crouch")

	var aim_anim := AnimationNodeAnimation.new()
	aim_anim.animation = &"aim"
	bt.add_node(&"aim_anim", aim_anim, Vector2(250, 300))
	var ab := AnimationNodeBlend2.new()
	ab.filter_enabled = true
	for p in UPPER_BODY:
		ab.set_filter_path(NodePath(p), true)
	bt.add_node(&"aim_blend", ab, Vector2(450, 100))
	bt.connect_node(&"aim_blend", 0, &"crouch_blend")
	bt.connect_node(&"aim_blend", 1, &"aim_anim")

	var prev := &"aim_blend"
	var x := 650
	for shot in [&"fire", &"reload", &"switch", &"interact", &"hit"]:
		var os := AnimationNodeOneShot.new()
		os.filter_enabled = true
		for p in UPPER_BODY:
			os.set_filter_path(NodePath(p), true)
		os.fadein_time = 0.06 if shot == &"fire" else 0.15
		os.fadeout_time = 0.06 if shot == &"fire" else 0.2
		var an3 := AnimationNodeAnimation.new()
		an3.animation = shot
		var ts := AnimationNodeTimeScale.new()
		var shot_name := StringName(String(shot) + "_shot")
		var anim_name := StringName(String(shot) + "_anim")
		var ts_name := StringName(String(shot) + "_speed")
		bt.add_node(anim_name, an3, Vector2(x, 300))
		bt.add_node(ts_name, ts, Vector2(x, 400))
		bt.connect_node(ts_name, 0, anim_name)
		bt.add_node(shot_name, os, Vector2(x, 100))
		bt.connect_node(shot_name, 0, prev)
		bt.connect_node(shot_name, 1, ts_name)
		prev = shot_name
		x += 200
	bt.connect_node(&"output", 0, prev)
	tree.tree_root = bt
	tree.active = true
	for shot in [&"fire", &"reload", &"switch", &"interact", &"hit"]:
		tree.set("parameters/%s_speed/scale" % shot, 1.0)


# =========================================================================== runtime API

## speed in m/s (horizontal); aim_pitch in radians (+ up).
func update_locomotion(speed: float, crouching: bool, aiming: bool, aim_pitch: float, delta: float) -> void:
	if _dead or tree == null:
		return
	_speed_smooth = lerpf(_speed_smooth, speed, clampf(delta * 10.0, 0.0, 1.0))
	_crouch_amount = move_toward(_crouch_amount, 1.0 if crouching else 0.0, delta * 5.0)
	_aim_amount = move_toward(_aim_amount, 1.0 if aiming else 0.0, delta * 7.0)
	tree.set("parameters/stand/blend_position", _speed_smooth)
	tree.set("parameters/crouch/blend_position", _speed_smooth)
	tree.set("parameters/crouch_blend/blend_amount", _crouch_amount)
	tree.set("parameters/aim_blend/blend_amount", _aim_amount)
	# Procedural aim pitch on the AimPivot (between spine and chest).
	var pitch := clampf(aim_pitch, -1.0, 1.0) * lerpf(0.35, 0.85, _aim_amount)
	aim_pivot.rotation.x = lerp_angle(aim_pivot.rotation.x, pitch, clampf(delta * 14.0, 0.0, 1.0))


func _fire_shot(shot: StringName, speed: float = 1.0) -> void:
	if _dead or tree == null:
		return
	tree.set("parameters/%s_speed/scale" % shot, speed)
	tree.set("parameters/%s_shot/request" % shot, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func play_fire() -> void:
	_fire_shot(&"fire")


func play_reload(duration: float) -> void:
	_fire_shot(&"reload", 1.0 / maxf(duration, 0.2))


func cancel_reload() -> void:
	if tree:
		tree.set("parameters/reload_shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)


func play_switch() -> void:
	_fire_shot(&"switch")


func play_interact() -> void:
	_fire_shot(&"interact")


func play_hit() -> void:
	_fire_shot(&"hit")


func play_death() -> void:
	if _dead:
		return
	_dead = true
	tree.active = false
	aim_pivot.rotation = Vector3.ZERO
	anim_player.play(&"death", 0.0)


func revive() -> void:
	_dead = false
	anim_player.stop()
	tree.active = true


func is_dead() -> bool:
	return _dead
