extends Node
## Autoload "Settings" — player configuration (graphics, audio, controls).
## Persisted separately from campaign progress in user://settings.cfg (versioned).

signal changed

const PATH := "user://settings.cfg"
const VERSION := 2
const QUALITY_NAMES := ["Low", "Medium", "High", "Ultra"]
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]

enum DisplayMode { WINDOWED, BORDERLESS, FULLSCREEN }

var display_mode: int = DisplayMode.WINDOWED
var resolution: Vector2i = Vector2i(1600, 900)
var vsync: bool = true
var render_scale: float = 1.0
var quality: int = 2            # 0 low .. 3 ultra
var shadow_quality: int = 2     # 0 off .. 3 high
var fov: float = 70.0
var master_volume: float = 0.9
var music_volume: float = 0.6
var sfx_volume: float = 0.9
var voice_volume: float = 1.0
var ui_volume: float = 0.7
var mouse_sensitivity: float = 1.0
var camera_sensitivity: float = 1.0
var invert_y: bool = false
## SHADOW CONTROLLER V2 camera stick (Joystick 1).
var controller_look_sensitivity: float = 1.0
var controller_look_smoothing: float = 0.05
var controller_invert_y: bool = false
var subtitles: bool = true
var show_fps: bool = false
var bindings: Dictionary = {}
## True once a profile has been chosen from hardware detection or by the player.
var initialised: bool = false
## Overridable for tests.
var path: String = PATH


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	if not initialised:
		_choose_hardware_defaults()
	# Applied on the next frame so the window and audio buses exist.
	apply.call_deferred()


func _choose_hardware_defaults() -> void:
	var adapter := RenderingServer.get_video_adapter_name().to_lower()
	if adapter.contains("rtx") or adapter.contains("radeon rx") or adapter.contains("arc a"):
		quality = 2
		shadow_quality = 2
	elif adapter.contains("gtx") or adapter.contains("radeon"):
		quality = 1
		shadow_quality = 1
	else:
		quality = 1
		shadow_quality = 1
		render_scale = 0.85
	initialised = true


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	if int(cfg.get_value("meta", "version", 0)) > VERSION:
		push_warning("Settings: newer settings version, using defaults")
		return
	display_mode = clampi(int(cfg.get_value("display", "mode", display_mode)), 0, 2)
	var r = cfg.get_value("display", "resolution", resolution)
	if r is Vector2i and r.x >= 640 and r.y >= 360:
		resolution = r
	vsync = bool(cfg.get_value("display", "vsync", vsync))
	render_scale = clampf(float(cfg.get_value("graphics", "render_scale", render_scale)), 0.5, 1.0)
	quality = clampi(int(cfg.get_value("graphics", "quality", quality)), 0, 3)
	shadow_quality = clampi(int(cfg.get_value("graphics", "shadows", shadow_quality)), 0, 3)
	fov = clampf(float(cfg.get_value("graphics", "fov", fov)), 55.0, 95.0)
	master_volume = clampf(float(cfg.get_value("audio", "master", master_volume)), 0.0, 1.0)
	music_volume = clampf(float(cfg.get_value("audio", "music", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx", sfx_volume)), 0.0, 1.0)
	voice_volume = clampf(float(cfg.get_value("audio", "voice", voice_volume)), 0.0, 1.0)
	ui_volume = clampf(float(cfg.get_value("audio", "ui", ui_volume)), 0.0, 1.0)
	mouse_sensitivity = clampf(float(cfg.get_value("controls", "mouse_sensitivity", mouse_sensitivity)), 0.1, 4.0)
	camera_sensitivity = clampf(float(cfg.get_value("controls", "camera_sensitivity", camera_sensitivity)), 0.1, 4.0)
	invert_y = bool(cfg.get_value("controls", "invert_y", invert_y))
	controller_look_sensitivity = clampf(float(cfg.get_value("controller", "look_sensitivity", controller_look_sensitivity)), 0.2, 3.0)
	controller_look_smoothing = clampf(float(cfg.get_value("controller", "look_smoothing", controller_look_smoothing)), 0.0, 0.3)
	controller_invert_y = bool(cfg.get_value("controller", "invert_y", controller_invert_y))
	subtitles = bool(cfg.get_value("ui", "subtitles", subtitles))
	show_fps = bool(cfg.get_value("ui", "show_fps", show_fps))
	var b = cfg.get_value("controls", "bindings", {})
	bindings = b if b is Dictionary else {}
	initialised = bool(cfg.get_value("meta", "initialised", true))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", VERSION)
	cfg.set_value("meta", "initialised", initialised)
	cfg.set_value("display", "mode", display_mode)
	cfg.set_value("display", "resolution", resolution)
	cfg.set_value("display", "vsync", vsync)
	cfg.set_value("graphics", "render_scale", render_scale)
	cfg.set_value("graphics", "quality", quality)
	cfg.set_value("graphics", "shadows", shadow_quality)
	cfg.set_value("graphics", "fov", fov)
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "voice", voice_volume)
	cfg.set_value("audio", "ui", ui_volume)
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("controls", "camera_sensitivity", camera_sensitivity)
	cfg.set_value("controls", "invert_y", invert_y)
	cfg.set_value("controls", "bindings", bindings)
	cfg.set_value("controller", "look_sensitivity", controller_look_sensitivity)
	cfg.set_value("controller", "look_smoothing", controller_look_smoothing)
	cfg.set_value("controller", "invert_y", controller_invert_y)
	cfg.set_value("ui", "subtitles", subtitles)
	cfg.set_value("ui", "show_fps", show_fps)
	var err := cfg.save(path)
	if err != OK:
		push_error("Settings: could not save (%s)" % error_string(err))


## Applies every setting to the engine and notifies listeners (environments, cameras).
func apply() -> void:
	var headless := DisplayServer.get_name() == "headless"
	if not headless:
		match display_mode:
			DisplayMode.FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
			DisplayMode.BORDERLESS:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			_:
				if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				var screen := DisplayServer.screen_get_size()
				var size := Vector2i(mini(resolution.x, screen.x), mini(resolution.y, screen.y))
				DisplayServer.window_set_size(size)
				DisplayServer.window_set_position((screen - size) / 2)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
		var vp := get_viewport()
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if render_scale < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = render_scale
		vp.msaa_3d = Viewport.MSAA_DISABLED if quality < 2 else Viewport.MSAA_2X
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		var dir_sizes := [1024, 2048, 4096, 4096]
		var pos_sizes := [1024, 2048, 4096, 8192]
		RenderingServer.directional_shadow_atlas_set_size(dir_sizes[shadow_quality], shadow_quality >= 2)
		vp.positional_shadow_atlas_size = pos_sizes[shadow_quality]
		var soft := [RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW,
			RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_HIGH]
		RenderingServer.directional_soft_shadow_filter_set_quality(soft[shadow_quality])
		RenderingServer.positional_soft_shadow_filter_set_quality(soft[shadow_quality])
	_apply_audio()
	changed.emit()


func _apply_audio() -> void:
	_set_bus("Master", master_volume)
	_set_bus("Music", music_volume)
	_set_bus("SFX", sfx_volume)
	_set_bus("Ambience", sfx_volume)
	_set_bus("Voice", voice_volume)
	_set_bus("UI", ui_volume)


func _set_bus(bus_name: String, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))
	AudioServer.set_bus_mute(idx, v <= 0.001)


func get_bus_linear(bus_name: String) -> float:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return -1.0
	if AudioServer.is_bus_mute(idx):
		return 0.0
	return db_to_linear(AudioServer.get_bus_volume_db(idx))
