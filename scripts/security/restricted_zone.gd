class_name RestrictedZone
extends Area3D
## Restricted area: enemies and cameras detect the player faster inside it.
## The HUD shows a "RESTRICTED AREA" warning while the player is inside.

signal player_entered_zone(zone: RestrictedZone)
signal player_exited_zone(zone: RestrictedZone)

@export var size: Vector3 = Vector3(10, 4, 10)
@export var zone_name: String = "Restricted Area"


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = Vector3(0, size.y * 0.5, 0)
	add_child(cs)
	body_entered.connect(_on_enter)
	body_exited.connect(_on_exit)


func _on_enter(b: Node3D) -> void:
	if b.is_in_group("player"):
		b.set_meta("restricted", true)
		b.set_meta("restricted_name", zone_name)
		player_entered_zone.emit(self)


func _on_exit(b: Node3D) -> void:
	if b.is_in_group("player"):
		b.set_meta("restricted", false)
		player_exited_zone.emit(self)
