class_name AIStateSearch
extends AIState
## Systematic search around the last known position: visit plausible nearby points.

const DURATION := 28.0

var _points: Array[Vector3] = []
var _index: int = 0
var _look: float = 0.0
var _look_base: float = 0.0


func _init(e: Enemy) -> void:
	super(e)
	name = &"search"


func enter(_previous: StringName) -> void:
	enemy.aiming = true
	enemy.crouching = false
	enemy.perception.state_multiplier = 2.6
	enemy.perception.floor_value = 35.0
	enemy.alerted_once = true
	enemy.release_cover()
	enemy.bark(&"search")
	_points.clear()
	_points.append(enemy.last_known_pos)
	for i in 4:
		_points.append(enemy.random_nav_point_near(enemy.last_known_pos, 9.0))
	_index = 0
	_look = 0.0
	enemy.move_to(_points[0], true, 0.75)


func exit() -> void:
	enemy.perception.floor_value = 0.0


func physics_update(delta: float) -> void:
	if enemy.perception.player_visible and enemy.perception.suspicion >= 60.0:
		enemy.perception.suspicion = Perception.CONFIRMED
		enemy.change_state(&"combat")
		return
	var limit := DURATION * (1.6 if enemy.data.archetype == EnemyData.Archetype.HEAVY_RESPONSE else 1.0)
	if time_in_state > limit:
		enemy.perception.suspicion = minf(enemy.perception.suspicion, 25.0)
		enemy.bark(&"giveup")
		enemy.change_state(&"return")
		return
	if _look > 0.0:
		_look -= delta
		enemy.face_yaw(_look_base + sin(_look * 2.0) * 80.0)
		if _look <= 0.0:
			_index = (_index + 1) % _points.size()
			enemy.move_to(_points[_index], false, 0.9)
		return
	if enemy.is_at_destination() or enemy.move_time > 12.0:
		enemy.stop_moving()
		_look = 2.4
		_look_base = enemy.get_yaw()


func on_noise(event: SoundEvent, estimate: Vector3, loudness: float) -> void:
	if loudness > 0.15 or event.is_combat_sound():
		enemy.last_known_pos = estimate
		_points[0] = estimate
		_index = 0
		_look = 0.0
		enemy.move_to(estimate, true, 0.75)
