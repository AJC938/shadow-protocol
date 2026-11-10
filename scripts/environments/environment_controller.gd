class_name EnvironmentController
extends WorldEnvironment
## Night-time tactical look: HDRI sky, moonlight, fog, glow, SSAO and colour grading.
## Expensive features follow the graphics quality setting.

const HDRI := "res://assets/hdri/kloppenheim_02_puresky_1k.hdr"

@export var sky_energy: float = 0.7
@export var ambient_energy: float = 1.0
@export var fog_density: float = 0.004
@export var volumetric_density: float = 0.008
@export var fog_color: Color = Color(0.09, 0.11, 0.15)
@export var interior: bool = false

var moon: DirectionalLight3D


func _ready() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	if ResourceLoader.exists(HDRI):
		var pm := PanoramaSkyMaterial.new()
		pm.panorama = load(HDRI)
		pm.energy_multiplier = sky_energy
		sky.sky_material = pm
	else:
		var ps := ProceduralSkyMaterial.new()
		ps.sky_top_color = Color(0.04, 0.05, 0.08)
		ps.sky_horizon_color = Color(0.1, 0.12, 0.16)
		ps.ground_bottom_color = Color(0.02, 0.02, 0.03)
		sky.sky_material = ps
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = ambient_energy
	env.ambient_light_sky_contribution = 0.35
	env.ambient_light_color = Color(0.3, 0.36, 0.48)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.35
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_strength = 0.9
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_light_color = fog_color
	env.fog_density = fog_density
	env.fog_sky_affect = 0.4
	env.fog_aerial_perspective = 0.3
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 0.85
	env.adjustment_brightness = 1.0
	environment = env
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.62, 0.72, 0.95)
	moon.light_energy = 0.0 if interior else 0.75
	moon.rotation_degrees = Vector3(-38, 35, 0)
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 70.0
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	moon.light_volumetric_fog_energy = 0.4
	add_child(moon)
	Settings.changed.connect(apply_quality)
	apply_quality()


func apply_quality() -> void:
	var env := environment
	var q := Settings.quality
	env.ssao_enabled = q >= 1
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.2
	env.ssao_light_affect = 0.15
	env.ssil_enabled = q >= 3
	env.ssr_enabled = q >= 3
	env.volumetric_fog_enabled = q >= 2
	env.volumetric_fog_density = volumetric_density
	env.volumetric_fog_albedo = Color(0.6, 0.65, 0.75)
	env.volumetric_fog_length = 48.0
	env.volumetric_fog_gi_inject = 0.5
	env.volumetric_fog_ambient_inject = 0.15
	env.sdfgi_enabled = false
	env.glow_enabled = q >= 1
	moon.shadow_enabled = Settings.shadow_quality > 0
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if Settings.shadow_quality >= 2 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	# Positional shadows off entirely on the lowest shadow setting.
	for n in get_tree().get_nodes_in_group("level_light"):
		var l := n as Light3D
		if l == null:
			continue
		if not l.has_meta("shadow_default"):
			l.set_meta("shadow_default", l.shadow_enabled)
		l.shadow_enabled = bool(l.get_meta("shadow_default")) and Settings.shadow_quality > 0
		l.distance_fade_enabled = true
		l.distance_fade_begin = 45.0 if q >= 2 else 30.0
		l.distance_fade_length = 10.0
