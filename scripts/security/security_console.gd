class_name SecurityConsole
extends Interactable
## Hackable terminal. Configurable actions (any combination):
##  * disable a camera network,  * unlock doors by id,  * take the alarm offline,
##  * complete an objective (inherited objective_id),  * show a story message.

signal hacked

@export var disable_camera_network: String = ""
@export var unlock_door_ids: PackedStringArray = []
@export var disable_alarm: bool = false
@export var story_speaker: String = ""
@export_multiline var story_text: String = ""
@export var story_voice: StringName = &""
@export var screen_color: Color = Color(0.25, 0.75, 1.0)

var done: bool = false
var _screen_mat: StandardMaterial3D
var _light: OmniLight3D


func _ready() -> void:
	super()
	add_to_group("security_device")
	if prompt == "Interact":
		prompt = "Hack terminal"
	if hold_time <= 0.0:
		hold_time = 2.5
	one_shot = true
	_build()


func _build() -> void:
	var desk := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(1.1, 0.9, 0.6)
	desk.mesh = dm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.17, 0.18, 0.2)
	m.metallic = 0.4
	m.roughness = 0.5
	desk.material_override = m
	desk.position = Vector3(0, 0.45, 0)
	add_child(desk)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.1, 0.9, 0.6)
	cs.shape = bs
	cs.position = Vector3(0, 0.45, 0)
	body.add_child(cs)
	body.set_meta("surface", "metal")
	add_child(body)
	for i in 2:
		var mon := MeshInstance3D.new()
		var mm := BoxMesh.new()
		mm.size = Vector3(0.48, 0.32, 0.04)
		mon.mesh = mm
		mon.material_override = m
		mon.position = Vector3(-0.26 + i * 0.52, 1.18, 0.12)
		mon.rotation_degrees = Vector3(-12, 0, 0)
		add_child(mon)
		var scr := MeshInstance3D.new()
		var sm := QuadMesh.new()
		sm.size = Vector2(0.44, 0.28)
		scr.mesh = sm
		if _screen_mat == null:
			_screen_mat = StandardMaterial3D.new()
			_screen_mat.emission_enabled = true
			_screen_mat.emission_energy_multiplier = 1.6
			_screen_mat.albedo_texture = _make_screen_texture()
			_screen_mat.emission_texture = _screen_mat.albedo_texture
		scr.material_override = _screen_mat
		scr.position = Vector3(-0.26 + i * 0.52, 1.18, 0.095)
		scr.rotation_degrees = Vector3(-12, 180, 0)
		add_child(scr)
	_light = OmniLight3D.new()
	_light.omni_range = 2.8
	_light.light_energy = 0.9
	_light.position = Vector3(0, 1.3, -0.4)
	add_child(_light)
	_refresh()


static func _make_screen_texture() -> ImageTexture:
	var img := Image.create(64, 40, false, Image.FORMAT_RGB8)
	img.fill(Color(0.02, 0.05, 0.08))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for y in range(3, 38, 4):
		var w := rng.randi_range(10, 58)
		for x in range(3, w):
			img.set_pixel(x, y, Color(0.6, 0.9, 1.0) * rng.randf_range(0.5, 1.0))
	return ImageTexture.create_from_image(img)


func get_interact_position() -> Vector3:
	return global_position + Vector3(0, 1.0, -0.35).rotated(Vector3.UP, global_rotation.y)


func _on_interact(_by: Node) -> void:
	done = true
	AudioManager.play_3d(&"hack_complete", get_interact_position(), -2.0)
	if disable_camera_network != "":
		for n in get_tree().get_nodes_in_group("security_camera"):
			var c := n as SecurityCamera
			if c and (disable_camera_network == "*" or c.network in disable_camera_network.split(",")):
				c.set_disabled(true)
	for id in unlock_door_ids:
		for n in get_tree().get_nodes_in_group("door"):
			var d := n as Door
			if d and d.door_id == id:
				d.unlock()
	if disable_alarm:
		var alarm := AlarmSystem.find(self)
		if alarm:
			alarm.set_offline(true)
	if story_text != "":
		AudioManager.play_voice(story_voice, story_speaker if story_speaker != "" else "ORACLE", story_text)
	_refresh()
	hacked.emit()


func _refresh() -> void:
	if _screen_mat == null:
		return
	var c := Color(0.25, 1.0, 0.45) if done else screen_color
	_screen_mat.albedo_color = c
	_screen_mat.emission = c
	_light.light_color = c


func get_save_state() -> Dictionary:
	return {"used": _used_once, "done": done}


func apply_save_state(s: Dictionary) -> void:
	_used_once = bool(s.get("used", false))
	done = bool(s.get("done", false))
	_refresh()
