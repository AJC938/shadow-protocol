class_name DamageInfo
extends RefCounted
## Describes one hit.

var amount: float = 0.0
var position: Vector3
var direction: Vector3 = Vector3.FORWARD
var source: Node
var headshot: bool = false
var weapon_id: StringName = &""


static func make(amount_: float, pos: Vector3, dir: Vector3, src: Node, head: bool = false, wid: StringName = &"") -> DamageInfo:
	var d := DamageInfo.new()
	d.amount = amount_
	d.position = pos
	d.direction = dir
	d.source = src
	d.headshot = head
	d.weapon_id = wid
	return d
