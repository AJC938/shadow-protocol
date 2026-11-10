class_name GadgetController
extends Node
## Player gadgets: Tactical Recon Camera, Signal Disruptor, Tactical Scanner.
## Each has a GadgetData resource (cooldown, duration, range, charges).

signal gadget_changed(index: int, data: GadgetData)
signal state_changed
signal message(text: String)
signal recon_mode_changed(active: bool)

const GADGET_PATHS := {
	&"recon": "res://resources/gadgets/recon_camera.tres",
	&"disruptor": "res://resources/gadgets/signal_disruptor.tres",
	&"scanner": "res://resources/gadgets/tactical_scanner.tres",
}
const RECON_MASK := 1 | 16

class GadgetState:
	var data: GadgetData
	var cooldown_left: float = 0.0
	var charges_left: int = -1
	var active_left: float = 0.0

var gadgets: Array[GadgetState] = []
var selected: int = 0
var player: CharacterBody3D
var camera_rig: CameraRig
var recon_device: ReconDevice
var recon_active: bool = false
var uses: int = 0


func setup(p: CharacterBody3D, cam: CameraRig, ids: Array) -> void:
	player = p
	camera_rig = cam
	gadgets.clear()
	for id in ids:
		if GADGET_PATHS.has(StringName(id)):
			var gs := GadgetState.new()
			gs.data = load(GADGET_PATHS[StringName(id)])
			gs.charges_left = gs.data.charges
			gadgets.append(gs)
	selected = 0
	if not gadgets.is_empty():
		gadget_changed.emit(0, gadgets[0].data)


func get_selected() -> GadgetState:
	return gadgets[selected] if selected < gadgets.size() else null


func cycle() -> void:
	if gadgets.size() > 1 and not recon_active:
		selected = (selected + 1) % gadgets.size()
		AudioManager.play_ui(&"ui_tick")
		gadget_changed.emit(selected, gadgets[selected].data)


func is_ready(gs: GadgetState) -> bool:
	return gs.cooldown_left <= 0.0 and gs.charges_left != 0


func _process(delta: float) -> void:
	var changed := false
	for gs in gadgets:
		if gs.cooldown_left > 0.0:
			gs.cooldown_left = maxf(0.0, gs.cooldown_left - delta)
			changed = true
		if gs.active_left > 0.0:
			gs.active_left = maxf(0.0, gs.active_left - delta)
			changed = true
	if changed:
		state_changed.emit()
	if recon_active:
		_process_recon(delta)


func use_selected() -> void:
	var gs := get_selected()
	if gs == null:
		return
	if recon_active:
		exit_recon()
		return
	match gs.data.kind:
		GadgetData.Kind.RECON_CAMERA:
			if is_instance_valid(recon_device):
				enter_recon()
			elif is_ready(gs):
				_deploy_recon(gs)
			else:
				message.emit("Recon camera recharging")
		GadgetData.Kind.SIGNAL_DISRUPTOR:
			if is_ready(gs):
				_disrupt(gs)
			else:
				message.emit("Disruptor %s" % ("depleted" if gs.charges_left == 0 else "recharging"))
		GadgetData.Kind.TACTICAL_SCANNER:
			if is_ready(gs):
				_scan(gs)
			else:
				message.emit("Scanner recharging")


func _consume(gs: GadgetState) -> void:
	gs.cooldown_left = gs.data.cooldown
	gs.active_left = gs.data.duration
	if gs.charges_left > 0:
		gs.charges_left -= 1
	uses += 1
	state_changed.emit()


# --------------------------------------------------------------------------- recon camera

## Returns the placement result for the current aim: {ok, position, normal}.
func find_recon_placement(range_m: float) -> Dictionary:
	var cam := camera_rig.camera
	var from := cam.global_position
	var dir := -cam.global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * (range_m + 3.0), RECON_MASK)
	q.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return {"ok": false, "reason": "No surface in range"}
	var p: Vector3 = hit.position
	if p.distance_to(player.global_position) > range_m:
		return {"ok": false, "reason": "Out of range"}
	# The player must have a clear throw line (no placing through walls).
	var q2 := PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP * 1.4, p + hit.normal * 0.1, RECON_MASK)
	q2.exclude = [player.get_rid()]
	var h2 := player.get_world_3d().direct_space_state.intersect_ray(q2)
	if not h2.is_empty() and h2.position.distance_to(p) > 0.4:
		return {"ok": false, "reason": "No clear line"}
	if hit.collider is Node and (hit.collider as Node).is_in_group("door"):
		return {"ok": false, "reason": "Invalid surface"}
	return {"ok": true, "position": p, "normal": hit.normal}


func _deploy_recon(gs: GadgetState) -> void:
	var r := find_recon_placement(gs.data.range)
	if not r["ok"]:
		message.emit("Recon camera: %s" % r["reason"])
		AudioManager.play_ui(&"ui_error")
		return
	recon_device = ReconDevice.new()
	player.get_parent().add_child(recon_device)
	recon_device.place(r["position"], r["normal"], camera_rig.get_forward())
	_consume(gs)
	gs.cooldown_left = 2.0
	SoundEvents.emit_sound(r["position"], gs.data.noise_radius, SoundEvent.Type.GADGET, 0.3, player)
	AudioManager.play_3d(&"gadget_deploy", r["position"], -4.0)
	message.emit("Recon camera deployed — [%s] to view" % InputRouter.get_binding_text(&"gadget_use"))


func enter_recon() -> void:
	if not is_instance_valid(recon_device) or recon_active:
		return
	recon_active = true
	camera_rig.suspended = true
	recon_device.activate(true)
	AudioManager.play_ui(&"ui_scan")
	recon_mode_changed.emit(true)


func exit_recon() -> void:
	if not recon_active:
		return
	recon_active = false
	camera_rig.suspended = false
	camera_rig.camera.current = true
	if is_instance_valid(recon_device):
		recon_device.activate(false)
	recon_mode_changed.emit(false)


func recall_recon() -> void:
	exit_recon()
	if is_instance_valid(recon_device):
		recon_device.queue_free()
	recon_device = null
	for gs in gadgets:
		if gs.data.kind == GadgetData.Kind.RECON_CAMERA:
			gs.cooldown_left = gs.data.cooldown
	message.emit("Recon camera recalled")
	state_changed.emit()


func _process_recon(delta: float) -> void:
	if not is_instance_valid(recon_device):
		exit_recon()
		return
	# Recon view owns look input while active; gameplay movement is blocked by the player.
	var look := Vector2.ZERO
	for p in InputRouter.get_providers():
		if p.enabled:
			look += p.get_look(delta)
	recon_device.rotate_view(look)
	recon_device.tag_visible_enemies(12.0)
	if InputRouter.is_just_pressed(&"interact") or InputRouter.is_just_pressed(&"aim"):
		exit_recon()
	elif InputRouter.is_just_pressed(&"reload"):
		recall_recon()


# --------------------------------------------------------------------------- disruptor

func _disrupt(gs: GadgetState) -> void:
	_consume(gs)
	var origin := player.global_position
	var count := 0
	for n in get_tree().get_nodes_in_group("electronic"):
		var n3 := n as Node3D
		if n3 and n3.has_method("disrupt") and n3.global_position.distance_to(origin) <= gs.data.range:
			n3.disrupt(gs.data.duration)
			count += 1
	SoundEvents.emit_sound(origin, gs.data.noise_radius, SoundEvent.Type.GADGET, 0.5, player)
	AudioManager.play_3d(&"gadget_emp", origin + Vector3.UP, 0.0)
	GadgetFX.pulse(player, origin + Vector3.UP, gs.data.range, Color(0.35, 0.6, 1.0, 0.5))
	message.emit("Signal disruptor: %d device%s offline" % [count, "" if count == 1 else "s"])


# --------------------------------------------------------------------------- scanner

func _scan(gs: GadgetState) -> void:
	_consume(gs)
	var origin := player.global_position
	var enemies := 0
	var devices := 0
	for n in get_tree().get_nodes_in_group("enemy"):
		var e := n as Node3D
		if e and e.has_method("tag") and not (e.has_method("is_dead") and e.is_dead()) and e.global_position.distance_to(origin) <= gs.data.range:
			e.tag(gs.data.duration)
			enemies += 1
	for n in get_tree().get_nodes_in_group("security_device"):
		var d := n as Node3D
		if d and d.has_method("tag") and d.global_position.distance_to(origin) <= gs.data.range * 1.2:
			d.tag(gs.data.duration)
			devices += 1
	SoundEvents.emit_sound(origin, gs.data.noise_radius, SoundEvent.Type.GADGET, 0.2, player)
	AudioManager.play_3d(&"gadget_scan", origin + Vector3.UP, -2.0)
	GadgetFX.pulse(player, origin + Vector3.UP * 0.2, gs.data.range, Color(1.0, 0.7, 0.25, 0.35))
	message.emit("Scan: %d hostile%s, %d security device%s" % [enemies, "" if enemies == 1 else "s", devices, "" if devices == 1 else "s"])


func get_state() -> Array:
	var out := []
	for gs in gadgets:
		out.append([String(gs.data.id), gs.charges_left])
	return out


func apply_state(s: Array) -> void:
	for e in s:
		if typeof(e) == TYPE_ARRAY and e.size() == 2:
			for gs in gadgets:
				if String(gs.data.id) == str(e[0]):
					gs.charges_left = int(e[1]) if gs.data.charges >= 0 else -1
	state_changed.emit()
