class_name AIStateReturn
extends AIState
## Walks back to the patrol route / post and resumes duty (with raised awareness).


func _init(e: Enemy) -> void:
	super(e)
	name = &"return"


func enter(_previous: StringName) -> void:
	enemy.aiming = false
	enemy.crouching = false
	enemy.perception.state_multiplier = 1.3 if enemy.alerted_once else 1.0
	enemy.perception.floor_value = 0.0
	enemy.release_cover()
	if enemy.patrol_points.is_empty():
		enemy.move_to(enemy.home_pos, false)
	else:
		enemy.patrol_index = enemy.nearest_patrol_index()
		enemy.move_to(enemy.patrol_points[enemy.patrol_index], false)


func physics_update(_delta: float) -> void:
	if check_awareness():
		return
	if enemy.is_at_destination() or time_in_state > 40.0:
		enemy.change_state(&"patrol" if not enemy.patrol_points.is_empty() else &"idle")
