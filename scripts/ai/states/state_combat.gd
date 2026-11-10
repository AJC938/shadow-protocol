class_name AIStateCombat
extends AIState
## Confirmed contact. Archetype-specific tactics:
##  * Standard guard   — takes cover, peeks and fires bursts, repositions.
##  * Specialist       — raises the alarm if possible, radios positions, flanks via cover.
##  * Heavy / commander— advances on the player, suppressive long bursts, no cover.
## Loses contact -> pursues the last known position -> Search.

const LOST_PURSUE := 2.5
const LOST_SEARCH := 9.0

var _lost: float = 0.0
var _reposition: float = 0.0
var _share_timer: float = 0.0
var _alarm_panel: Node3D
var _peek_timer: float = 0.0
var _pursuing: bool = false


func _init(e: Enemy) -> void:
	super(e)
	name = &"combat"


func enter(previous: StringName) -> void:
	enemy.aiming = true
	enemy.alerted_once = true
	enemy.perception.state_multiplier = 3.0
	enemy.perception.floor_value = 60.0
	enemy.perception.suspicion = Perception.CONFIRMED
	enemy.reset_reaction(previous)
	_lost = 0.0
	_pursuing = false
	_reposition = 0.0
	enemy.last_known_pos = enemy.perception.last_seen_position if enemy.perception.time_since_seen() < 1.0 else enemy.last_known_pos
	enemy.bark(&"contact")
	enemy.report_contact(enemy.last_known_pos)
	_alarm_panel = null
	if enemy.data.can_use_alarm and not enemy.radio_jammed():
		_alarm_panel = enemy.find_alarm_panel()
		if _alarm_panel:
			enemy.bark(&"alarm")
			enemy.move_to(_alarm_panel.global_position, true)


func exit() -> void:
	enemy.perception.floor_value = 0.0
	enemy.crouching = false


func physics_update(delta: float) -> void:
	var sees := enemy.perception.player_visible
	var player := enemy.perception.player
	if sees and player:
		_lost = 0.0
		_pursuing = false
		enemy.last_known_pos = player.global_position
	else:
		_lost += delta

	# Specialist: run to the alarm first.
	if _alarm_panel:
		if not is_instance_valid(_alarm_panel) or not _alarm_panel.call("can_be_triggered"):
			_alarm_panel = null
		elif enemy.global_position.distance_to(_alarm_panel.global_position) < 1.8:
			_alarm_panel.call("trigger_by", enemy)
			_alarm_panel = null
		else:
			if enemy.is_at_destination():
				enemy.move_to(_alarm_panel.global_position, true)
			enemy.face_point(_alarm_panel.global_position)
			return

	# Share the position with allies while it is actually seen.
	_share_timer -= delta
	if sees and _share_timer <= 0.0:
		_share_timer = 2.0
		enemy.report_contact(enemy.last_known_pos)

	if _lost > LOST_SEARCH:
		enemy.release_cover()
		enemy.change_state(&"search")
		return

	if sees:
		enemy.face_point(player.global_position)
		enemy.try_shoot(delta)
	else:
		enemy.face_point(enemy.last_known_pos)
		if _lost > LOST_PURSUE and not _pursuing:
			_pursuing = true
			enemy.release_cover()
			enemy.crouching = false
			enemy.move_to(enemy.random_nav_point_near(enemy.last_known_pos, 1.5), true, 0.8)
		return

	# Movement tactics while the player is visible.
	if enemy.data.aggressive_push:
		var d := enemy.global_position.distance_to(player.global_position)
		if d > enemy.data.preferred_range:
			if enemy.is_at_destination() or enemy.move_time > 2.0:
				enemy.move_to(player.global_position, false, 1.0)
		else:
			enemy.stop_moving()
		return
	if enemy.data.uses_cover:
		_reposition -= delta
		var cover := enemy.cover
		if cover == null or _reposition <= 0.0 or not enemy.cover_is_safe(cover, player.global_position):
			_reposition = randf_range(5.0, 8.0)
			var c := enemy.find_cover(player.global_position)
			if c:
				enemy.claim_cover(c)
				enemy.move_to(c.global_position, true)
			else:
				enemy.release_cover()
				var side := enemy.global_transform.basis.x * (1.0 if randf() > 0.5 else -1.0)
				enemy.move_to(enemy.random_nav_point_near(enemy.global_position + side * 3.0, 1.5), true)
		if enemy.cover and enemy.is_at_destination():
			# Peek: crouch behind cover between bursts.
			_peek_timer -= delta
			enemy.crouching = enemy.is_between_bursts() and _peek_timer < 0.0
			if not enemy.is_between_bursts():
				_peek_timer = 0.4


func on_noise(event: SoundEvent, estimate: Vector3, loudness: float) -> void:
	# Already fighting: noises only matter while contact is lost.
	if _lost > 1.0 and (event.is_combat_sound() or loudness > 0.3):
		enemy.last_known_pos = estimate
		_pursuing = false
