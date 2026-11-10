class_name Interactor
extends Node
## Finds the best interactable in front of the player and handles press / hold.

signal focus_changed(target: Interactable)
signal hold_progress(ratio: float)

const LOS_MASK := 1 | 16

var player: Node3D
var camera_rig: CameraRig
var focus: Interactable
var _hold: float = 0.0
var _scan_timer: float = 0.0


func setup(p: Node3D, cam: CameraRig) -> void:
	player = p
	camera_rig = cam


func _find_best() -> Interactable:
	var best: Interactable = null
	var best_score := INF
	var fwd := camera_rig.get_forward()
	fwd.y = 0.0
	fwd = fwd.normalized()
	var origin := player.global_position + Vector3.UP * 1.2
	for n in get_tree().get_nodes_in_group("interactable"):
		var it := n as Interactable
		if it == null or not it.is_visible_in_tree() or not it.can_interact(player):
			continue
		var p := it.get_interact_position()
		var d := origin.distance_to(p)
		if d > it.interact_distance:
			continue
		var to := p - origin
		to.y = 0.0
		var facing := fwd.dot(to.normalized()) if to.length() > 0.05 else 1.0
		if facing < 0.15 and d > 0.9:
			continue
		var q := PhysicsRayQueryParameters3D.create(origin, p, LOS_MASK)
		q.exclude = [player.get_rid()]
		var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty() and hit.position.distance_to(p) > 0.45:
			var c: Node = hit.collider
			if not (c == it or it.is_ancestor_of(c) or c.is_ancestor_of(it)):
				continue
		var score := d * (2.0 - facing)
		if score < best_score:
			best_score = score
			best = it
	return best


func process_interaction(delta: float, pressed: bool, held: bool) -> void:
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = 0.1
		var b := _find_best()
		if b != focus:
			focus = b
			_hold = 0.0
			hold_progress.emit(0.0)
			focus_changed.emit(focus)
	if focus == null:
		return
	if focus.hold_time <= 0.0:
		if pressed:
			focus.interact(player)
			if player.has_method("on_interacted"):
				player.on_interacted()
			_scan_timer = 0.0
		return
	if held:
		if _hold == 0.0 and player.has_method("on_interacted"):
			player.on_interacted()
		_hold += delta
		hold_progress.emit(clampf(_hold / focus.hold_time, 0.0, 1.0))
		if _hold >= focus.hold_time:
			_hold = 0.0
			hold_progress.emit(0.0)
			focus.interact(player)
			_scan_timer = 0.0
	elif _hold > 0.0:
		_hold = 0.0
		hold_progress.emit(0.0)


func is_holding() -> bool:
	return _hold > 0.0
