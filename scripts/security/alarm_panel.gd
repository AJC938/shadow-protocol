class_name AlarmPanel
extends Interactable
## Wall alarm panel. Security specialists run here to raise the alarm.
## The player can sabotage it (permanent) or jam it with the disruptor (temporary).

var sabotaged: bool = false
var _jammed: float = 0.0
var _lamp: OmniLight3D
var _screen_mat: StandardMaterial3D


func _ready() -> void:
	super()
	add_to_group("alarm_panel")
	add_to_group("security_device")
	add_to_group("electronic")
	prompt = "Sabotage alarm panel"
	hold_time = 2.0
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.7, 0.14)
	box.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.12, 0.1)
	m.roughness = 0.5
	m.metallic = 0.3
	box.material_override = m
	box.position = Vector3(0, 1.4, 0)
	add_child(box)
	var screen := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.3, 0.18, 0.02)
	screen.mesh = sm
	_screen_mat = StandardMaterial3D.new()
	_screen_mat.emission_enabled = true
	screen.material_override = _screen_mat
	screen.position = Vector3(0, 1.5, -0.075)
	add_child(screen)
	_lamp = OmniLight3D.new()
	_lamp.omni_range = 1.6
	_lamp.light_energy = 0.8
	_lamp.position = Vector3(0, 1.5, -0.3)
	add_child(_lamp)
	_refresh()


func get_interact_position() -> Vector3:
	return global_position + Vector3.UP * 1.4


func can_interact(by: Node) -> bool:
	return super(by) and not sabotaged


func can_be_triggered() -> bool:
	var alarm := AlarmSystem.find(self)
	return not sabotaged and _jammed <= 0.0 and alarm != null and not alarm.active and not alarm.offline


func trigger_by(enemy: Node3D) -> void:
	if not can_be_triggered():
		return
	AudioManager.play_3d(&"panel_beep", get_interact_position(), 0.0)
	var alarm := AlarmSystem.find(self)
	var p: Vector3 = enemy.last_known_pos if enemy is Enemy else global_position
	alarm.raise_alarm(p, "panel")


func disrupt(duration: float) -> void:
	_jammed = maxf(_jammed, duration)
	_refresh()


func _on_interact(_by: Node) -> void:
	sabotaged = true
	AudioManager.play_3d(&"panel_sabotage", get_interact_position(), -2.0)
	_refresh()


func tag(_d: float) -> void:
	pass


func _process(delta: float) -> void:
	if _jammed > 0.0:
		_jammed -= delta
		if _jammed <= 0.0:
			_refresh()


func _refresh() -> void:
	var c := Color(0.2, 0.9, 0.3)
	if sabotaged:
		c = Color(0.1, 0.1, 0.1)
	elif _jammed > 0.0:
		c = Color(0.3, 0.5, 1.0)
	_screen_mat.albedo_color = c
	_screen_mat.emission = c
	_lamp.light_color = c
	_lamp.visible = not sabotaged


func get_save_state() -> Dictionary:
	return {"sabotaged": sabotaged}


func apply_save_state(s: Dictionary) -> void:
	sabotaged = bool(s.get("sabotaged", false))
	_refresh()
