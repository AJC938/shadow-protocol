class_name ObjectiveData
extends Resource
## One mission objective. Level nodes (ObjectiveTrigger, interactables, …) complete it
## by id through MissionController.complete_objective().

@export var id: StringName = &"objective"
@export var text: String = "Objective"
@export var optional: bool = false
## Count-based objectives (e.g. "Disable relays 0/3"). 1 = simple.
@export var required_count: int = 1
## Hidden objectives are revealed by the mission script when relevant.
@export var hidden: bool = false
## Objectives sharing a non-empty group are active together; others activate in order.
@export var parallel_group: String = ""
