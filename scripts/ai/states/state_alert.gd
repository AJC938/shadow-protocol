class_name AIStateAlert
extends AIState
## Hostile activity reported (alarm, gunfire, ally call, body found): move fast to
## the reported position with weapon ready. The enemy does not know where the
## player actually is — only the reported position.


func _init(e: Enemy) -> void:
	super(e)
	name = &"alert"


func enter(_previous: StringName) -> void:
	enemy.aiming = true
	enemy.crouching = false
	enemy.perception.state_multiplier = 3.0
	enemy.perception.floor_value = 40.0
	enemy.alerted_once = true
	enemy.bark(&"alert")
	enemy.move_to(enemy.random_nav_point_near(enemy.stimulus_pos, 2.0), true)


func exit() -> void:
	enemy.perception.floor_value = 0.0


func physics_update(_delta: float) -> void:
	if enemy.perception.player_visible and enemy.perception.suspicion >= 60.0:
		enemy.perception.suspicion = Perception.CONFIRMED
		enemy.change_state(&"combat")
		return
	if enemy.is_at_destination() or enemy.global_position.distance_to(enemy.stimulus_pos) < 3.0 or time_in_state > 30.0:
		enemy.last_known_pos = enemy.stimulus_pos
		enemy.change_state(&"search")


func on_noise(event: SoundEvent, estimate: Vector3, loudness: float) -> void:
	if event.is_combat_sound() or loudness > 0.3:
		enemy.set_stimulus(estimate)
		enemy.move_to(enemy.random_nav_point_near(estimate, 2.0), true)
