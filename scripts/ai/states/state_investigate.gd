class_name AIStateInvestigate
extends AIState
## Walks (weapon raised) to the stimulus, inspects, checks a nearby spot, then gives up.

enum Phase { GO, INSPECT, CHECK_NEARBY, LOOK }

var _phase: int = Phase.GO
var _timer: float = 0.0
var _look_base: float = 0.0
var _retarget: float = 0.0


func _init(e: Enemy) -> void:
	super(e)
	name = &"investigate"


func enter(_previous: StringName) -> void:
	enemy.aiming = true
	enemy.perception.state_multiplier = 1.6
	enemy.perception.floor_value = 30.0
	_phase = Phase.GO
	enemy.bark(&"investigate")
	enemy.move_to(enemy.stimulus_pos, false, 0.85)


func exit() -> void:
	enemy.perception.floor_value = 0.0


func physics_update(delta: float) -> void:
	if enemy.perception.suspicion >= Perception.CONFIRMED:
		enemy.change_state(&"combat")
		return
	_retarget -= delta
	if enemy.perception.player_visible and _retarget <= 0.0:
		# Partial sighting while investigating: refine the target.
		_retarget = 0.5
		enemy.set_stimulus(enemy.perception.last_seen_position)
		_phase = Phase.GO
		enemy.move_to(enemy.stimulus_pos, false, 0.85)
	match _phase:
		Phase.GO:
			if enemy.is_at_destination() or time_in_state > 25.0:
				_phase = Phase.INSPECT
				_timer = 3.5
				_look_base = enemy.get_yaw()
				enemy.stop_moving()
		Phase.INSPECT:
			_timer -= delta
			enemy.face_yaw(_look_base + sin(_timer * 1.4) * 70.0)
			if _timer <= 0.0:
				_phase = Phase.CHECK_NEARBY
				enemy.move_to(enemy.random_nav_point_near(enemy.stimulus_pos, 4.5), false, 0.85)
		Phase.CHECK_NEARBY:
			if enemy.is_at_destination() or enemy.move_time > 10.0:
				_phase = Phase.LOOK
				_timer = 2.5
				_look_base = enemy.get_yaw()
				enemy.stop_moving()
		Phase.LOOK:
			_timer -= delta
			enemy.face_yaw(_look_base + sin(_timer * 1.8) * 60.0)
			if _timer <= 0.0:
				enemy.perception.floor_value = 0.0
				enemy.perception.suspicion = minf(enemy.perception.suspicion, 25.0)
				enemy.bark(&"nothing")
				enemy.change_state(&"return")


func on_noise(event: SoundEvent, estimate: Vector3, _loudness: float) -> void:
	enemy.set_stimulus(estimate)
	if event.is_combat_sound():
		enemy.change_state(&"alert")
		return
	_phase = Phase.GO
	enemy.move_to(enemy.stimulus_pos, false, 0.85)
