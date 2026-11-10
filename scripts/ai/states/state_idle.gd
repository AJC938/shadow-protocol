class_name AIStateIdle
extends AIState
## Stationary post: the guard stands and periodically scans around its post heading.

var _look_timer: float = 0.0
var _look_offset: float = 0.0


func _init(e: Enemy) -> void:
	super(e)
	name = &"idle"


func enter(_previous: StringName) -> void:
	enemy.stop_moving()
	enemy.aiming = false
	enemy.crouching = false
	enemy.perception.state_multiplier = 1.3 if enemy.alerted_once else 1.0
	enemy.perception.floor_value = 0.0
	_look_timer = randf_range(3.0, 6.0)


func physics_update(delta: float) -> void:
	if check_awareness():
		return
	_look_timer -= delta
	if _look_timer <= 0.0:
		_look_timer = randf_range(3.5, 7.0)
		_look_offset = randf_range(-55.0, 55.0)
	enemy.face_yaw(enemy.home_yaw + _look_offset)
