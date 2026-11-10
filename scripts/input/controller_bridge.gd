extends Node
## Autoload "ControllerBridge" — SHADOW CONTROLLER V2 (Arduino) integration.
##
## controller_bridge/serial_bridge.py reads the Arduino over USB and talks to the
## game over localhost UDP only:
##   bridge -> game (UDP 42420): CTRL,<seq>,<J1X>,<J1Y>,<J2X>,<J2Y>,<B1>,<B2>   |   LINK,<0/1>,<port>
##   game -> bridge (UDP 42421): SPSTATE,<READY|ALIVE|DAMAGED|DEAD|PAUSED|MISSION_COMPLETE>
##                               SPHEALTH,<0..100>
##
## Hardware input is fed into InputRouter.external (ExternalInputProvider), so the
## existing camera rig, player controller (camera-relative movement), weapons and
## interaction are used unchanged; keyboard, mouse and gamepad keep working alongside.
##
## Mapping (v2 tactical layout)
##   Joystick 1 (left)  X/Y -> camera yaw / pitch (look velocity)    button -> FIRE
##   Joystick 2 (right) X/Y -> strafe / forward-back (analog, combined)  button -> INTERACT

signal controller_connected_changed(connected: bool)
signal state_sent(state: String)

const CENTER := 512.0
const HALF_RANGE := 511.0
## Same dead zone as the firmware (130 of 512).
const DEAD_ZONE := 130.0 / 512.0
## No frame for this long = controller treated as disconnected; everything is released.
const FRAME_TIMEOUT := 0.25
## Movement smoothing time constant (seconds) — removes ADC jitter without adding lag.
const MOVE_SMOOTHING := 0.035
## Look velocity at full deflection before the sensitivity setting (degrees per second).
const BASE_LOOK_SPEED := 150.0
## Look response curve exponent (>1 = finer control near the centre).
const LOOK_CURVE := 1.6
const STATE_RESEND := 1.0
const HEALTH_MIN_INTERVAL := 0.1

const STATE_PRIORITY := ["DEAD", "PAUSED", "MISSION_COMPLETE", "DAMAGED", "ALIVE", "READY"]

var listen_port: int = 42420
var bridge_port: int = 42421
var enabled: bool = true
## How long PLAYER: DAMAGED is reported after a real hit (seconds).
var damaged_display_time: float = 1.2

## True while valid controller frames are arriving.
var controller_connected: bool = false
## True while the Python bridge reports an open serial port.
var serial_link: bool = false
var last_frame: PackedInt32Array = PackedInt32Array([0, 512, 512, 512, 512, 0, 0])
var frames_received: int = 0
var frames_rejected: int = 0
var current_state: String = ""
var current_health: int = -1
## Current look velocity fed to the camera (x = yaw right, y = pitch up), -1..1.
var look: Vector2 = Vector2.ZERO

var _rx: PacketPeerUDP
var _tx: PacketPeerUDP
var _since_frame: float = 999.0
var _move: Vector2 = Vector2.ZERO
var _target_move: Vector2 = Vector2.ZERO
var _target_look: Vector2 = Vector2.ZERO
var _state_timer: float = 0.0
var _state_sent_at: float = -999.0
var _health_sent_at: float = -999.0
var _clock: float = 0.0
var _damaged_until: float = -1.0
var _tracked_player: Node = null
var _log: bool = false
var _log_timer: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -200   # before InputRouter (-100) so input is current this frame
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sp-controller-port="):
			listen_port = int(a.get_slice("=", 1))
		elif a.begins_with("--sp-bridge-port="):
			bridge_port = int(a.get_slice("=", 1))
		elif a.begins_with("--sp-damage-display="):
			damaged_display_time = maxf(0.2, float(a.get_slice("=", 1)))
		elif a == "--sp-no-controller":
			enabled = false
		elif a == "--sp-controller-log":
			_log = true
	# The bridge applies its own dead zone (matching the firmware); avoid a second one.
	InputRouter.external.dead_zone = 0.0
	if enabled:
		start()


## Opens the localhost sockets. Safe to call again (tests use other ports).
func start() -> void:
	stop()
	_rx = PacketPeerUDP.new()
	var err := _rx.bind(listen_port, "127.0.0.1")
	if err != OK:
		push_warning("ControllerBridge: cannot listen on 127.0.0.1:%d (%s) — hardware controller disabled" % [listen_port, error_string(err)])
		_rx = null
	_tx = PacketPeerUDP.new()
	_tx.set_dest_address("127.0.0.1", bridge_port)


func stop() -> void:
	if _rx:
		_rx.close()
	_rx = null
	if _tx:
		_tx.close()
	_tx = null
	_release_all()


func is_listening() -> bool:
	return _rx != null and _rx.is_bound()


# =========================================================================== receive

func _process(delta: float) -> void:
	_clock += delta
	_since_frame += delta
	if _rx:
		while _rx.get_available_packet_count() > 0:
			var pkt := _rx.get_packet()
			if _rx.get_packet_ip() != "127.0.0.1":
				continue
			handle_packet(pkt.get_string_from_ascii())
	if controller_connected and _since_frame > FRAME_TIMEOUT:
		_set_connected(false)
	_apply_input(delta)
	_track_player()
	_state_timer -= delta
	if _state_timer <= 0.0:
		_state_timer = 0.1
		report_state(compute_game_state())
		_report_health()
	if _log:
		_log_timer -= delta
		if _log_timer <= 0.0:
			_log_timer = 1.0
			var p := get_tree().get_first_node_in_group("player") as Node3D
			var cam := ""
			if p is Player:
				cam = " yaw=%.1f pitch=%.1f" % [(p as Player).camera_rig.yaw, (p as Player).camera_rig.pitch]
			print("[CTRL] t=%.0f frames=%d rejected=%d connected=%s link=%s state=%s hp=%d fire=%d use=%d player=%s%s" % [_clock, frames_received,
				frames_rejected, controller_connected, serial_link, current_state, current_health, last_frame[5], last_frame[6],
				str(p.global_position.snapped(Vector3.ONE * 0.01)) if p else "-", cam])


## Parses one bridge message. Returns true if it was a valid controller frame.
func handle_packet(text: String) -> bool:
	var parts := text.strip_edges().split(",")
	if parts.is_empty():
		return false
	match parts[0]:
		"CTRL":
			var f := parse_frame(parts)
			if f.is_empty():
				frames_rejected += 1
				return false
			last_frame = f
			frames_received += 1
			_since_frame = 0.0
			if not controller_connected:
				_set_connected(true)
			_target_move = movement_from_frame(f)
			_target_look = look_from_frame(f)
			return true
		"LINK":
			serial_link = parts.size() >= 2 and parts[1] == "1"
			if not serial_link:
				# Serial port lost: release immediately, never wait for the frame timeout.
				_set_connected(false)
	return false


## Validates CTRL fields. Returns [seq, j1x, j1y, j2x, j2y, b1, b2] or [] if invalid.
static func parse_frame(parts: PackedStringArray) -> PackedInt32Array:
	if parts.size() != 8:
		return PackedInt32Array()
	var out := PackedInt32Array()
	for i in range(1, 8):
		if not parts[i].is_valid_int():
			return PackedInt32Array()
		out.append(parts[i].to_int())
	for i in range(1, 5):
		if out[i] < 0 or out[i] > 1023:
			return PackedInt32Array()
	if out[5] not in [0, 1] or out[6] not in [0, 1]:
		return PackedInt32Array()
	return out


## Raw 0..1023 -> -1..1 with dead zone and rescaling (no jump at the dead-zone edge).
static func normalize_axis(raw: float) -> float:
	var n := clampf((raw - CENTER) / HALF_RANGE, -1.0, 1.0)
	var m := absf(n)
	if m < DEAD_ZONE:
		return 0.0
	return signf(n) * clampf((m - DEAD_ZONE) / (1.0 - DEAD_ZONE), 0.0, 1.0)


## Joystick 2: X = strafe (right +), Y = forward/back (stick up = lower value = forward).
## Returns Vector2(strafe right +, forward +), length limited to 1 (normalised diagonals).
static func movement_from_frame(f: PackedInt32Array) -> Vector2:
	var strafe := normalize_axis(f[3])
	var forward := -normalize_axis(f[4])
	return Vector2(strafe, forward).limit_length(1.0)


## Joystick 1: X = yaw (right +), Y = pitch (stick up = look up +). Response-curved.
static func look_from_frame(f: PackedInt32Array, invert_y: bool = false) -> Vector2:
	var x := normalize_axis(f[1])
	var y := -normalize_axis(f[2])
	if invert_y:
		y = -y
	return Vector2(signf(x) * pow(absf(x), LOOK_CURVE), signf(y) * pow(absf(y), LOOK_CURVE))


func _apply_input(delta: float) -> void:
	var ext: ExternalInputProvider = InputRouter.external
	if ext == null or not controller_connected:
		return
	# Movement: light smoothing, snaps to zero when centred.
	var k := 1.0 - exp(-delta / MOVE_SMOOTHING)
	_move = _move.lerp(_target_move, k)
	if _target_move == Vector2.ZERO and _move.length() < 0.02:
		_move = Vector2.ZERO
	ext.set_axis(&"move_x", _move.x)
	ext.set_axis(&"move_y", _move.y)
	# Camera: analog look *velocity* (never an absolute angle). Centred stick = stop now.
	var target := look_from_frame(last_frame, Settings.controller_invert_y)
	if target == Vector2.ZERO:
		look = Vector2.ZERO
	else:
		var smoothing := maxf(Settings.controller_look_smoothing, 0.0)
		var kl := 1.0 if smoothing <= 0.0001 else 1.0 - exp(-delta / smoothing)
		look = look.lerp(target, kl)
	ext.camera_speed = BASE_LOOK_SPEED * Settings.controller_look_sensitivity
	ext.set_axis(&"camera_x", look.x)
	ext.set_axis(&"camera_y", look.y)
	ext.set_button(&"fire", last_frame[5] == 1)
	ext.set_button(&"interact", last_frame[6] == 1)


func _set_connected(c: bool) -> void:
	if c == controller_connected:
		return
	controller_connected = c
	if not c:
		_release_all()
	controller_connected_changed.emit(c)


## Stops movement and camera and releases fire/interact (disconnect, timeout, shutdown).
func _release_all() -> void:
	_move = Vector2.ZERO
	_target_move = Vector2.ZERO
	look = Vector2.ZERO
	_target_look = Vector2.ZERO
	if InputRouter and InputRouter.external:
		InputRouter.external.reset()


# =========================================================================== game state -> OLED

## Hooks the real damage signal of whichever player is currently in play
## (a checkpoint respawn creates a new player).
func _track_player() -> void:
	var scene := get_tree().current_scene
	var p: Player = (scene as MissionLevel).player if scene is MissionLevel else null
	if p == _tracked_player:
		return
	_tracked_player = p
	_damaged_until = -1.0
	current_health = -1
	if p:
		p.damaged.connect(_on_player_damaged.bind(p))


func _on_player_damaged(_dir: Vector3, p: Player) -> void:
	# A lethal hit emits `damaged` just before `died`: health is already 0 then, so
	# report DEAD directly instead of a one-frame DAMAGED.
	if p == _tracked_player and not p.is_dead() and not p.health.is_dead():
		_damaged_until = _clock + damaged_display_time
	if p == _tracked_player:
		report_state(compute_game_state())
		_report_health(true)


## Derived from the real game state. Priority:
## DEAD > PAUSED > MISSION_COMPLETE > DAMAGED (transient) > ALIVE > READY.
func compute_game_state() -> String:
	var tree := get_tree()
	var scene := tree.current_scene
	if scene is MissionLevel:
		var level := scene as MissionLevel
		var mc := level.controller
		if level.player and (level.player.is_dead() or level.player.health.is_dead()):
			return "DEAD"
		if tree.paused:
			return "PAUSED"
		if mc and mc.finished:
			return "MISSION_COMPLETE"
		if _clock < _damaged_until and level.player == _tracked_player:
			return "DAMAGED"
		return "ALIVE"
	if scene and (scene.scene_file_path.ends_with("results.tscn") or scene.scene_file_path.ends_with("ending.tscn")):
		return "MISSION_COMPLETE"
	return "READY"


func report_state(state: String) -> void:
	if _tx == null:
		return
	if state != current_state or _clock - _state_sent_at >= STATE_RESEND:
		current_state = state
		_state_sent_at = _clock
		_tx.put_packet(("SPSTATE,%s" % state).to_ascii_buffer())
		state_sent.emit(state)


## Health percentage of the current player (only in missions), sent on change.
func _report_health(force: bool = false) -> void:
	if _tx == null or _tracked_player == null or not is_instance_valid(_tracked_player):
		return
	var p := _tracked_player as Player
	var pct := int(round(p.health.ratio() * 100.0))
	if pct == current_health and _clock - _health_sent_at < STATE_RESEND:
		return
	if pct != current_health and not force and _clock - _health_sent_at < HEALTH_MIN_INTERVAL:
		return
	current_health = pct
	_health_sent_at = _clock
	_tx.put_packet(("SPHEALTH,%d" % pct).to_ascii_buffer())


func _exit_tree() -> void:
	stop()
