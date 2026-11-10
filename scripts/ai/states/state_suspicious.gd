class_name AIStateSuspicious
extends AIState
## Something is off: stop, turn toward the stimulus and watch.

var _timer: float = 0.0


func _init(e: Enemy) -> void:
	super(e)
	name = &"suspicious"


func enter(_previous: StringName) -> void:
	enemy.stop_moving()
	enemy.aiming = false
	enemy.perception.state_multiplier = 1.3
	enemy.perception.floor_value = 0.0
	_timer = randf_range(2.2, 3.4)
	enemy.bark(&"huh")


func physics_update(delta: float) -> void:
	var s := enemy.perception.suspicion
	if s >= Perception.CONFIRMED:
		enemy.change_state(&"combat")
		return
	if enemy.perception.player_visible:
		enemy.set_stimulus(enemy.perception.last_seen_position)
	if s >= Perception.INVESTIGATE:
		enemy.change_state(&"investigate")
		return
	enemy.face_point(enemy.stimulus_pos)
	_timer -= delta
	if _timer <= 0.0:
		if s >= 32.0:
			enemy.change_state(&"investigate")
		else:
			enemy.bark(&"nothing")
			enemy.change_state(&"return")


func on_noise(event: SoundEvent, estimate: Vector3, _loudness: float) -> void:
	enemy.set_stimulus(estimate)
	if event.is_combat_sound():
		enemy.change_state(&"alert")
	else:
		_timer = maxf(_timer, 1.5)
