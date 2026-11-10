extends StaticBody3D
## Forwards hits on a child collider to its owning gameplay node.

var target: Node


func take_damage(info: DamageInfo) -> void:
	if is_instance_valid(target) and target.has_method("take_damage"):
		target.take_damage(info)


func is_dead() -> bool:
	return is_instance_valid(target) and target.has_method("is_dead") and target.is_dead()
