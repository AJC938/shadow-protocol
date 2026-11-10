class_name Interactable
extends Node3D
## Base class for anything the player can use with the Interact action.
## Subclasses override _on_interact(). Hold interactions use hold_time > 0.

signal used(by: Node)

@export var prompt: String = "Interact"
@export var hold_time: float = 0.0
@export var interact_distance: float = 2.3
@export var enabled: bool = true
## Noise produced while operating (radius, metres). 0 = silent.
@export var noise_radius: float = 0.0
## Objective completed when used (optional).
@export var objective_id: StringName = &""
@export var one_shot: bool = false

var _used_once: bool = false


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("persistent")


func can_interact(_by: Node) -> bool:
	return enabled and not (one_shot and _used_once)


## Text shown in the HUD prompt (may depend on state, e.g. "Locked").
func get_prompt(_by: Node) -> String:
	return prompt


## Point used for distance / line-of-sight checks.
func get_interact_position() -> Vector3:
	return global_position


func interact(by: Node) -> void:
	if not can_interact(by):
		return
	_used_once = true
	if noise_radius > 0.0:
		SoundEvents.emit_sound(global_position, noise_radius, SoundEvent.Type.GADGET, 0.5, by)
	_on_interact(by)
	used.emit(by)
	if objective_id != &"":
		var mc := MissionController.find(self)
		if mc:
			mc.complete_objective(objective_id)


func _on_interact(_by: Node) -> void:
	pass


## Persistent state for checkpoints (override when the object has state).
func get_save_state() -> Dictionary:
	return {"used": _used_once, "enabled": enabled}


func apply_save_state(s: Dictionary) -> void:
	_used_once = bool(s.get("used", false))
	enabled = bool(s.get("enabled", enabled))
