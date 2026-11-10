class_name MenuStage
extends SubViewportContainer
## Small 3D presentation stage behind menus: GHOST under a cold rim light.

var rig: CharacterRig
var _t: float = 0.0
var _cam: Camera3D


func _ready() -> void:
	stretch = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.transparent_bg = false
	add_child(vp)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.035, 0.045)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.15, 0.18, 0.24)
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.fog_enabled = true
	env.fog_light_color = Color(0.06, 0.08, 0.11)
	env.fog_density = 0.05
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.04
	env.volumetric_fog_albedo = Color(0.7, 0.75, 0.85)
	env.ssao_enabled = true
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.15
	env.adjustment_saturation = 0.85
	we.environment = env
	vp.add_child(we)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.35, 0.37, 0.4)
	if ResourceLoader.exists("res://assets/textures/metal_plate/albedo.jpg"):
		fm.albedo_texture = load("res://assets/textures/metal_plate/albedo.jpg")
		fm.normal_enabled = true
		fm.normal_texture = load("res://assets/textures/metal_plate/normal.jpg")
		fm.uv1_scale = Vector3(10, 10, 10)
	fm.roughness = 0.45
	fm.metallic = 0.6
	floor_mi.material_override = fm
	vp.add_child(floor_mi)
	rig = CharacterRig.new()
	vp.add_child(rig)
	rig.setup("ghost")
	rig.set_weapon(WeaponData.Model.RIFLE)
	rig.position = Vector3(0.9, 0, 0)
	rig.rotation_degrees.y = 28.0
	var key := SpotLight3D.new()
	key.light_color = Color(0.55, 0.7, 1.0)
	key.light_energy = 9.0
	key.spot_range = 14.0
	key.spot_angle = 26.0
	key.shadow_enabled = true
	key.light_volumetric_fog_energy = 3.0
	vp.add_child(key)
	key.position = Vector3(3.5, 6.0, -3.0)
	key.look_at(rig.position + Vector3.UP, Vector3.UP)
	var warm := SpotLight3D.new()
	warm.light_color = Color(1.0, 0.65, 0.3)
	warm.light_energy = 5.0
	warm.spot_range = 12.0
	warm.spot_angle = 30.0
	warm.light_volumetric_fog_energy = 2.0
	vp.add_child(warm)
	warm.position = Vector3(-3.0, 3.0, 3.5)
	warm.look_at(rig.position + Vector3.UP * 1.2, Vector3.UP)
	_cam = Camera3D.new()
	_cam.fov = 38.0
	vp.add_child(_cam)
	_cam.position = Vector3(-0.4, 1.45, 5.2)
	_cam.look_at(Vector3(-0.3, 1.05, 0), Vector3.UP)
	_cam.current = true


func _process(delta: float) -> void:
	_t += delta
	if Game.automation.has("debug_stage") and int(_t * 60) == 200:
		var vp := get_child(0) as SubViewport
		print("[STAGE] container size=", size, " vp size=", vp.size, " cam current=", _cam.current, " visible=", is_visible_in_tree())
	if rig:
		rig.update_locomotion(0.0, false, fmod(_t, 12.0) > 6.0, 0.05, delta)
	if _cam:
		_cam.position.x = -0.4 + sin(_t * 0.15) * 0.25
