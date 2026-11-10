extends Node3D
## Dev tool: renders every character outfit/pose side by side and saves a PNG.
## godot --path . res://tools/rig_preview.tscn -- --sp-out=<png>

var _frames := 0
var _rigs: Array[CharacterRig] = []


func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.12, 0.13, 0.15)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.55, 0.65)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.ssao_enabled = true
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 30, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	add_child(sun)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	fl.mesh = pm
	add_child(fl)
	var specs := [["ghost", false, 0], ["ghost", true, 0], ["ghost", false, 1], ["guard", false, 0], ["specialist", false, 0], ["heavy", true, 0], ["commander", false, 0]]
	for i in specs.size():
		var r := CharacterRig.new()
		add_child(r)
		r.setup(specs[i][0])
		r.set_weapon(WeaponData.Model.PISTOL if specs[i][0] == "commander" else WeaponData.Model.RIFLE)
		r.position = Vector3(-6.3 + i * 2.1, 0, 0)
		r.rotation_degrees.y = 200.0
		r.set_meta("aim", specs[i][1])
		r.set_meta("crouch", specs[i][2] == 1)
		_rigs.append(r)
	var cam := Camera3D.new()
	cam.fov = 40
	add_child(cam)
	cam.position = Vector3(0, 1.3, 8)
	cam.look_at(Vector3(0, 0.95, 0), Vector3.UP)
	cam.current = true


func _process(delta: float) -> void:
	_frames += 1
	for r in _rigs:
		r.update_locomotion(0.0, r.get_meta("crouch"), r.get_meta("aim"), 0.0, delta)
	if _frames == 120:
		var out := "res://tests/output/rigs.png"
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--sp-out="):
				out = a.substr(9)
		get_viewport().get_texture().get_image().save_png(out)
		get_tree().quit()
