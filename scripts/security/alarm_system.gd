class_name AlarmSystem
extends Node3D
## Facility alarm for one mission. Raised by cameras, alarm panels (specialists)
## or scripted events. While active: siren, red alarm lights, enemies receive the
## *reported* position (not the player's live position). Auto-resets after a quiet period.

signal raised(origin: Vector3, reason: String)
signal cleared

@export var reset_after: float = 60.0

var active: bool = false
var times_raised: int = 0
## When true the alarm can no longer be raised (security network disabled).
var offline: bool = false
var _quiet: float = 0.0
var _siren: AudioStreamPlayer
var _flash_t: float = 0.0


func _ready() -> void:
	add_to_group("alarm_system")
	_siren = AudioStreamPlayer.new()
	_siren.bus = "SFX"
	_siren.volume_db = -10.0
	add_child(_siren)
	_siren.finished.connect(func(): if active: _siren.play())


static func find(n: Node) -> AlarmSystem:
	return n.get_tree().get_first_node_in_group("alarm_system") as AlarmSystem


func raise_alarm(origin: Vector3, reason: String = "") -> bool:
	if offline:
		return false
	_quiet = 0.0
	if active:
		_broadcast(origin)
		return true
	active = true
	times_raised += 1
	var s := AudioManager.get_stream(&"alarm_siren")
	if s:
		_siren.stream = s
		_siren.play()
	_broadcast(origin)
	for l in get_tree().get_nodes_in_group("alarm_light"):
		(l as Light3D).visible = true
	raised.emit(origin, reason)
	AudioManager.play_voice(&"vo_alarm", "ORACLE", "They've raised the alarm. Break contact or find another route.")
	return true


func _broadcast(origin: Vector3) -> void:
	for n in get_tree().get_nodes_in_group("enemy"):
		var e := n as Enemy
		if e and not e.is_dead() and not e.dormant:
			e.receive_alert(origin)


func clear_alarm() -> void:
	if not active:
		return
	active = false
	_siren.stop()
	for l in get_tree().get_nodes_in_group("alarm_light"):
		(l as Light3D).visible = false
	cleared.emit()


## Disables the alarm network for the rest of the mission.
func set_offline(o: bool) -> void:
	offline = o
	if o:
		clear_alarm()


func _process(delta: float) -> void:
	if not active:
		return
	_flash_t += delta
	var e := 0.5 + 0.5 * sin(_flash_t * 7.0)
	for l in get_tree().get_nodes_in_group("alarm_light"):
		(l as Light3D).light_energy = 2.5 * e
	# Auto-reset when no enemy is in combat.
	var fighting := false
	for n in get_tree().get_nodes_in_group("enemy"):
		var en := n as Enemy
		if en and not en.is_dead() and en.state_name == &"combat":
			fighting = true
			break
	_quiet = 0.0 if fighting else _quiet + delta
	if _quiet > reset_after:
		clear_alarm()
