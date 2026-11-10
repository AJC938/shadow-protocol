class_name AIState
extends RefCounted
## Base class for enemy FSM states. One instance per state per enemy.

var enemy: Enemy
var name: StringName = &"state"
var time_in_state: float = 0.0


func _init(e: Enemy) -> void:
	enemy = e


func enter(_previous: StringName) -> void:
	pass


func exit() -> void:
	pass


func physics_update(_delta: float) -> void:
	pass


## A sound was heard (estimate is a noisy position). Default: calm-state reaction.
func on_noise(event: SoundEvent, estimate: Vector3, _loudness: float) -> void:
	if event.is_combat_sound():
		enemy.set_stimulus(estimate)
		enemy.change_state(&"alert")
	elif enemy.perception.suspicion >= Perception.INVESTIGATE:
		enemy.set_stimulus(estimate)
		enemy.change_state(&"investigate")
	elif enemy.perception.suspicion >= Perception.SUSPICIOUS:
		enemy.set_stimulus(estimate)
		enemy.change_state(&"suspicious")


## Shared escalation check for calm states. Returns true if the state changed.
func check_awareness() -> bool:
	var s := enemy.perception.suspicion
	if s >= Perception.CONFIRMED:
		enemy.change_state(&"combat")
		return true
	if enemy.perception.player_visible:
		enemy.set_stimulus(enemy.perception.last_seen_position)
	if s >= Perception.INVESTIGATE and enemy.perception.player_visible:
		enemy.change_state(&"investigate")
		return true
	if s >= Perception.SUSPICIOUS:
		enemy.change_state(&"suspicious")
		return true
	return false
