extends SceneTree
## Generates all data resources (.tres). Single source of truth for tuning numbers
## and mission text. Run:  godot --headless --path . -s tools/make_resources.gd


func _init() -> void:
	_weapons()
	_gadgets()
	_enemies()
	_missions()
	print("resources generated")
	quit()


func _save(r: Resource, path: String) -> void:
	var err := ResourceSaver.save(r, path)
	if err != OK:
		push_error("save failed %s %s" % [path, error_string(err)])


func _w(id: StringName, name: String, model: int, d: Dictionary) -> WeaponData:
	var w := WeaponData.new()
	w.id = id
	w.display_name = name
	w.model = model
	for k in d:
		w.set(k, d[k])
	return w


func _weapons() -> void:
	_save(_w(&"pistol", "MK-9 Suppressed Pistol", WeaponData.Model.PISTOL, {
		"damage": 34.0, "headshot_multiplier": 3.0, "fire_rate": 3.5, "automatic": false, "range": 70.0,
		"falloff_start": 25.0, "min_damage_scale": 0.6, "magazine_size": 12, "start_reserve": 36, "max_reserve": 72,
		"reload_time": 1.3, "spread_hip": 2.2, "spread_aim": 0.35, "spread_move_add": 1.2, "recoil_pitch": 1.0,
		"recoil_yaw": 0.3, "noise_radius": 6.0, "suppressed": true, "fire_sound": &"pistol_fire",
		"muzzle_flash_scale": 0.4, "switch_time": 0.3}), "res://resources/weapons/suppressed_pistol.tres")
	_save(_w(&"rifle", "AR-7 Assault Rifle", WeaponData.Model.RIFLE, {
		"damage": 26.0, "headshot_multiplier": 2.5, "fire_rate": 9.5, "automatic": true, "range": 120.0,
		"falloff_start": 45.0, "min_damage_scale": 0.6, "magazine_size": 30, "start_reserve": 90, "max_reserve": 180,
		"reload_time": 2.1, "spread_hip": 3.0, "spread_aim": 0.9, "spread_move_add": 2.0, "recoil_pitch": 0.9,
		"recoil_yaw": 0.45, "noise_radius": 38.0, "suppressed": false, "fire_sound": &"rifle_fire",
		"muzzle_flash_scale": 1.0, "switch_time": 0.45}), "res://resources/weapons/assault_rifle.tres")
	_save(_w(&"shotgun", "SG-12 Tactical Shotgun", WeaponData.Model.SHOTGUN, {
		"damage": 15.0, "headshot_multiplier": 1.5, "fire_rate": 1.2, "automatic": false, "pellets": 9, "range": 30.0,
		"falloff_start": 8.0, "min_damage_scale": 0.25, "magazine_size": 6, "start_reserve": 18, "max_reserve": 36,
		"reload_time": 2.6, "spread_hip": 5.5, "spread_aim": 4.0, "spread_move_add": 1.5, "recoil_pitch": 4.5,
		"recoil_yaw": 1.0, "noise_radius": 45.0, "suppressed": false, "fire_sound": &"shotgun_fire",
		"muzzle_flash_scale": 1.5, "switch_time": 0.5}), "res://resources/weapons/tactical_shotgun.tres")
	_save(_w(&"enemy_rifle", "Guard Rifle", WeaponData.Model.RIFLE, {
		"damage": 9.0, "fire_rate": 8.0, "automatic": true, "range": 80.0, "noise_radius": 38.0,
		"fire_sound": &"rifle_fire_enemy", "muzzle_flash_scale": 0.9}), "res://resources/weapons/enemy_rifle.tres")
	_save(_w(&"enemy_smg", "Specialist SMG", WeaponData.Model.PISTOL, {
		"damage": 7.0, "fire_rate": 11.0, "automatic": true, "range": 60.0, "noise_radius": 32.0,
		"fire_sound": &"smg_fire", "muzzle_flash_scale": 0.7}), "res://resources/weapons/enemy_smg.tres")
	_save(_w(&"enemy_lmg", "Heavy LMG", WeaponData.Model.RIFLE, {
		"damage": 11.0, "fire_rate": 10.0, "automatic": true, "range": 80.0, "noise_radius": 45.0,
		"fire_sound": &"lmg_fire", "muzzle_flash_scale": 1.2}), "res://resources/weapons/enemy_lmg.tres")
	_save(_w(&"commander_rifle", "Commander Carbine", WeaponData.Model.RIFLE, {
		"damage": 13.0, "fire_rate": 6.0, "automatic": true, "range": 90.0, "noise_radius": 40.0,
		"fire_sound": &"rifle_fire_enemy", "muzzle_flash_scale": 1.0}), "res://resources/weapons/commander_rifle.tres")


func _g(id: StringName, name: String, kind: int, desc: String, d: Dictionary, path: String) -> void:
	var g := GadgetData.new()
	g.id = id
	g.display_name = name
	g.kind = kind
	g.description = desc
	for k in d:
		g.set(k, d[k])
	_save(g, path)


func _gadgets() -> void:
	_g(&"recon", "Recon Camera", GadgetData.Kind.RECON_CAMERA,
		"Deployable camera. Remote view with limited arc; tags hostiles in view.",
		{"cooldown": 8.0, "duration": 0.0, "range": 14.0, "charges": -1, "noise_radius": 2.0},
		"res://resources/gadgets/recon_camera.tres")
	_g(&"disruptor", "Signal Disruptor", GadgetData.Kind.SIGNAL_DISRUPTOR,
		"Jams cameras, alarm panels and specialist radios within range.",
		{"cooldown": 12.0, "duration": 12.0, "range": 10.0, "charges": 3, "noise_radius": 4.0},
		"res://resources/gadgets/signal_disruptor.tres")
	_g(&"scanner", "Tactical Scanner", GadgetData.Kind.TACTICAL_SCANNER,
		"Short pulse revealing hostiles and security devices for a few seconds.",
		{"cooldown": 18.0, "duration": 6.0, "range": 25.0, "charges": -1, "noise_radius": 1.5},
		"res://resources/gadgets/tactical_scanner.tres")


func _e(path: String, d: Dictionary) -> void:
	var e := EnemyData.new()
	for k in d:
		e.set(k, d[k])
	_save(e, path)


func _enemies() -> void:
	_e("res://resources/enemies/standard_guard.tres", {
		"archetype": EnemyData.Archetype.STANDARD_GUARD, "display_name": "Guard", "max_health": 100.0, "armor": 0.0,
		"walk_speed": 1.5, "run_speed": 4.2, "vision_range": 22.0, "fov_degrees": 105.0, "detection_rate": 55.0,
		"suspicion_decay": 9.0, "hearing_multiplier": 1.0, "weapon": load("res://resources/weapons/enemy_rifle.tres"),
		"accuracy": 0.42, "reaction_time": 0.75, "burst_size": 3, "burst_interval": 1.4, "preferred_range": 14.0,
		"uses_cover": true, "aggressive_push": false, "can_use_alarm": false, "radio_range": 16.0})
	_e("res://resources/enemies/security_specialist.tres", {
		"archetype": EnemyData.Archetype.SECURITY_SPECIALIST, "display_name": "Security Specialist", "max_health": 90.0,
		"armor": 0.1, "walk_speed": 1.6, "run_speed": 4.4, "vision_range": 28.0, "fov_degrees": 130.0,
		"detection_rate": 70.0, "suspicion_decay": 7.0, "hearing_multiplier": 1.25,
		"weapon": load("res://resources/weapons/enemy_smg.tres"), "accuracy": 0.4, "reaction_time": 0.6, "burst_size": 4,
		"burst_interval": 1.2, "preferred_range": 12.0, "uses_cover": true, "can_use_alarm": true, "radio_range": 45.0})
	_e("res://resources/enemies/heavy_response.tres", {
		"archetype": EnemyData.Archetype.HEAVY_RESPONSE, "display_name": "Heavy Response Unit", "max_health": 320.0,
		"armor": 0.45, "walk_speed": 1.2, "run_speed": 2.6, "visual_scale": 1.12, "vision_range": 20.0,
		"fov_degrees": 95.0, "detection_rate": 45.0, "suspicion_decay": 6.0, "hearing_multiplier": 0.8,
		"weapon": load("res://resources/weapons/enemy_lmg.tres"), "accuracy": 0.35, "reaction_time": 0.9,
		"burst_size": 7, "burst_interval": 1.8, "preferred_range": 7.0, "uses_cover": false, "aggressive_push": true,
		"radio_range": 20.0})
	_e("res://resources/enemies/commander.tres", {
		"archetype": EnemyData.Archetype.COMMANDER, "display_name": "Commander Voss", "max_health": 700.0, "armor": 0.5,
		"walk_speed": 1.4, "run_speed": 3.2, "visual_scale": 1.08, "vision_range": 30.0, "fov_degrees": 120.0,
		"detection_rate": 80.0, "suspicion_decay": 5.0, "hearing_multiplier": 1.2,
		"weapon": load("res://resources/weapons/commander_rifle.tres"), "accuracy": 0.5, "reaction_time": 0.5,
		"burst_size": 5, "burst_interval": 1.3, "preferred_range": 10.0, "uses_cover": true, "aggressive_push": false,
		"radio_range": 60.0})


func _o(id: StringName, text: String, optional: bool = false, count: int = 1, hidden: bool = false) -> ObjectiveData:
	var o := ObjectiveData.new()
	o.id = id
	o.text = text
	o.optional = optional
	o.required_count = count
	o.hidden = hidden
	return o


func _missions() -> void:
	var m1 := MissionData.new()
	m1.id = "m01"
	m1.number = 1
	m1.title = "Silent Entry"
	m1.codename = "SILENT ENTRY"
	m1.location = "Kestrel Ridge Facility — Outer Sector"
	m1.background = "Kestrel Ridge is a fenced industrial complex owned on paper by Northgate Systems, a defence contractor that builds secure communications hardware. For six months, encrypted traffic leaving the site has matched the signatures of an intelligence-trafficking ring that sells surveillance data on allied operatives."
	m1.briefing = "GHOST, this is ORACLE. You go in tonight through the western perimeter. Get through the security checkpoint, reach the control terminal in the admin block and pull the initial intelligence package. Then out through the loading yard to the east.\n\nTheir guards are contractors, not soldiers — but they are armed and they patrol. Stay in the shadows, keep it quiet, and nobody needs to know we were there."
	m1.objectives.assign([
		_o(&"reach_perimeter", "Reach the facility perimeter"),
		_o(&"enter_checkpoint", "Enter the security checkpoint"),
		_o(&"pass_checkpoint", "Get past the checkpoint security — avoid or neutralise"),
		_o(&"access_terminal", "Access the facility control terminal"),
		_o(&"retrieve_intel", "Retrieve the initial intelligence package"),
		_o(&"extract", "Reach the extraction area"),
		_o(&"undetected_checkpoint", "Pass the checkpoint undetected", true),
		_o(&"data_shards", "Recover classified data shards", true, 2),
		_o(&"no_alarm", "Do not raise the alarm", true),
	])
	m1.weapons.assign([&"pistol", &"rifle"])
	m1.gadgets.assign([&"scanner", &"recon"])
	m1.scene_path = "res://scenes/missions/mission_01.tscn"
	m1.par_time = 720.0
	m1.music = &"mission_1"
	m1.briefing_voice = &"vo_brief_m01"
	m1.debrief = "Package received. Northgate isn't building radios, GHOST — they're hiding a surveillance network inside them. Rest up. Black Signal is next."
	_save(m1, "res://resources/missions/m01_silent_entry.tres")

	var m2 := MissionData.new()
	m2.id = "m02"
	m2.number = 2
	m2.title = "Black Signal"
	m2.codename = "BLACK SIGNAL"
	m2.location = "Kestrel Ridge Facility — Communications Sector"
	m2.background = "The Silent Entry package contained relay schedules for a network codenamed BLACK SIGNAL: hidden transmitters inside Northgate's own security grid, used to intercept allied communications and sell them to the highest bidder."
	m2.briefing = "The communications sector is wired tight — cameras in every corridor, and security specialists who will run for an alarm panel the moment they see you. Find the security control room and take their surveillance relays offline, then pull the classified communication files from the server hall.\n\nDownloading those files will trip a network lockdown. When it does, survive until the uplink completes, then get to the roof. Use the service ducts, use the disruptor — and remember that specialists carry radios."
	m2.objectives.assign([
		_o(&"enter_sector", "Enter the communications sector"),
		_o(&"find_control", "Locate the security control room"),
		_o(&"disable_relays", "Disable the surveillance relays", false, 3),
		_o(&"retrieve_files", "Retrieve the classified communication files"),
		_o(&"survive", "Survive the security response until the uplink completes", false, 1, true),
		_o(&"extract", "Extract from the rooftop"),
		_o(&"undetected_files", "Retrieve the files without being detected", true),
		_o(&"transmission_log", "Recover the encrypted transmission log", true),
	])
	m2.weapons.assign([&"pistol", &"rifle", &"shotgun"])
	m2.gadgets.assign([&"disruptor", &"scanner", &"recon"])
	m2.scene_path = "res://scenes/missions/mission_02.tscn"
	m2.par_time = 900.0
	m2.music = &"mission_2"
	m2.briefing_voice = &"vo_brief_m02"
	m2.debrief = "The files confirm it. BLACK SIGNAL is run from the command sector by the facility's own security commander, Elias Voss. He is selling our people, GHOST. One more night."
	_save(m2, "res://resources/missions/m02_black_signal.tres")

	var m3 := MissionData.new()
	m3.id = "m03"
	m3.number = 3
	m3.title = "Final Extraction"
	m3.codename = "FINAL EXTRACTION"
	m3.location = "Kestrel Ridge Facility — Command Sector"
	m3.background = "Elias Voss, Northgate's head of security, built BLACK SIGNAL from inside the company. The final evidence — the buyer ledger — sits in the command sector vault. With it, the network and everyone who paid for it can be exposed."
	m3.briefing = "This is the last run. Get through the blast doors into the restricted command area, then shut down the main security network from the research lab's network core — that unlocks the command sector.\n\nVoss is on site with his heavy response team. Fight him, or seal him inside the strategy room with the lockdown override — either way he cannot be allowed to stop you. Take the ledger from the vault and get to the helipad. I'll have a bird waiting."
	m3.objectives.assign([
		_o(&"enter_restricted", "Enter the restricted command area"),
		_o(&"disable_network", "Disable the main security network"),
		_o(&"reach_command", "Reach the command sector"),
		_o(&"overcome_commander", "Defeat or contain Commander Voss"),
		_o(&"retrieve_ledger", "Retrieve the final classified package"),
		_o(&"extract", "Reach the helipad extraction point"),
		_o(&"undetected_lab", "Reach the network core undetected", true),
		_o(&"lab_archive", "Recover the research lab archive", true),
		_o(&"contain_voss", "Contain Voss without killing him", true),
	])
	m3.weapons.assign([&"pistol", &"rifle", &"shotgun"])
	m3.gadgets.assign([&"disruptor", &"scanner", &"recon"])
	m3.scene_path = "res://scenes/missions/mission_03.tscn"
	m3.par_time = 1080.0
	m3.music = &"mission_3"
	m3.briefing_voice = &"vo_brief_m03"
	m3.debrief = ""
	_save(m3, "res://resources/missions/m03_final_extraction.tres")
