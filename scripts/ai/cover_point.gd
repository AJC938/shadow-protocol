class_name CoverPoint
extends Marker3D
## A spot behind low/high cover that enemies can claim during combat.
## `high` = full-height cover (lean out) vs low cover (crouch).

@export var high: bool = false
var claimed_by: Node = null


func _ready() -> void:
	add_to_group("cover_point")


func is_free_for(n: Node) -> bool:
	return claimed_by == null or claimed_by == n or not is_instance_valid(claimed_by) \
		or (claimed_by.has_method("is_dead") and claimed_by.is_dead())
