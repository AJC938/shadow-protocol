class_name AIStateDead
extends AIState
## Terminal state.


func _init(e: Enemy) -> void:
	super(e)
	name = &"dead"


func enter(_previous: StringName) -> void:
	enemy.stop_moving()
	enemy.aiming = false


func on_noise(_event: SoundEvent, _estimate: Vector3, _loudness: float) -> void:
	pass
