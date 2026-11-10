extends Node
## Autoload "SoundEvents" — event-based sound perception bus.
## Anything that makes gameplay-relevant noise calls emit_sound(); enemy Perception
## components listen to `sound_emitted` and decide individually whether they heard it.

signal sound_emitted(event: SoundEvent)

## Set true to draw expanding rings for every event (debug).
var debug_draw: bool = false
var _history: Array[SoundEvent] = []


func emit_sound(position: Vector3, radius: float, type: int, intensity: float = 1.0, source: Node = null) -> SoundEvent:
	var e := SoundEvent.new()
	e.position = position
	e.radius = radius
	e.type = type
	e.intensity = clampf(intensity, 0.0, 1.0)
	e.source = source
	e.time = Time.get_ticks_msec() / 1000.0
	_history.append(e)
	if _history.size() > 64:
		_history.pop_front()
	sound_emitted.emit(e)
	if debug_draw:
		_debug_ring(e)
	return e


func recent_events() -> Array[SoundEvent]:
	return _history


func clear_history() -> void:
	_history.clear()


func _debug_ring(e: SoundEvent) -> void:
	var scene := get_tree().current_scene
	if scene == null or not scene is Node3D:
		return
	var mi := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = e.radius - 0.05
	torus.outer_radius = e.radius
	mi.mesh = torus
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1, 0.6, 0.1, 0.6)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	scene.add_child(mi)
	mi.global_position = e.position + Vector3.UP * 0.1
	get_tree().create_timer(0.5).timeout.connect(mi.queue_free)
