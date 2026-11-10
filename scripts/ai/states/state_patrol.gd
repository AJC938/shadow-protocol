class_name AIStatePatrol
extends AIState
## Walks the patrol route, pausing and scanning at each waypoint.

var _waiting: float = 0.0
var _look_offset: float = 0.0
var _dir: int = 1


func _init(e: Enemy) -> void:
	super(e)
	name = &"patrol"


func enter(_previous: StringName) -> void:
	enemy.aiming = false
	enemy.crouching = false
	enemy.perception.state_multiplier = 1.3 if enemy.alerted_once else 1.0
	enemy.perception.floor_value = 0.0
	_waiting = 0.0
	if enemy.patrol_points.is_empty():
		enemy.change_state(&"idle")
		return
	enemy.move_to(enemy.patrol_points[enemy.patrol_index], false)


func physics_update(delta: float) -> void:
	if check_awareness():
		return
	if _waiting > 0.0:
		_waiting -= delta
		enemy.face_yaw(enemy.patrol_wait_yaw + _look_offset)
		if _waiting < enemy.patrol_wait * 0.5 and absf(_look_offset) < 1.0:
			_look_offset = randf_range(-50.0, 50.0)
		if _waiting <= 0.0:
			_advance()
		return
	if enemy.is_at_destination():
		_waiting = enemy.patrol_wait
		_look_offset = 0.0
		enemy.stop_moving()
		enemy.patrol_wait_yaw = enemy.get_yaw()


func _advance() -> void:
	var n := enemy.patrol_points.size()
	if n <= 1:
		enemy.move_to(enemy.patrol_points[0], false)
		return
	if enemy.patrol_loop:
		enemy.patrol_index = (enemy.patrol_index + 1) % n
	else:
		if enemy.patrol_index + _dir >= n or enemy.patrol_index + _dir < 0:
			_dir = -_dir
		enemy.patrol_index += _dir
	enemy.move_to(enemy.patrol_points[enemy.patrol_index], false)
