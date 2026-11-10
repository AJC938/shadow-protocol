extends TestCase
## Unit tests: input layer, health, sound events, settings persistence.


# ------------------------------------------------------------------ input (INP)

func test_external_provider_axes_and_deadzone() -> void:
	var p := ExternalInputProvider.new()
	p.set_axis(&"move_x", 0.05)
	eq(p.get_move(), Vector2.ZERO, "INP-01 dead zone")
	p.set_axis(&"move_x", 0.5)
	p.set_axis(&"move_y", 1.0)
	var m := p.get_move()
	near(m.x, 0.5 / sqrt(1.25), 0.001, "INP-01 x (normalised)")
	near(m.y, -1.0 / sqrt(1.25), 0.001, "INP-01 device forward maps to -y")
	check(m.length() <= 1.0001, "INP-01 move vector limited to 1")


func test_external_provider_button_edges() -> void:
	var p := ExternalInputProvider.new()
	p.set_button(&"fire", true)
	p.poll(0.016)
	check(p.is_pressed(&"fire") and p.is_just_pressed(&"fire"), "INP-02 press edge")
	p.poll(0.016)
	check(p.is_pressed(&"fire") and not p.is_just_pressed(&"fire"), "INP-02 held, no edge")
	p.set_button(&"fire", false)
	p.poll(0.016)
	check(p.is_just_released(&"fire"), "INP-02 release edge")


func test_router_merges_external_provider_and_blocking() -> void:
	InputRouter.external.set_axis(&"move_x", 1.0)
	await frames(1)
	check(InputRouter.get_move_vector().x > 0.9, "INP-03 router reads external provider")
	InputRouter.gameplay_blocked = true
	eq(InputRouter.get_move_vector(), Vector2.ZERO, "INP-03 blocked gameplay input")
	InputRouter.gameplay_blocked = false
	InputRouter.external.reset()
	InputRouter.external.set_button(&"crouch", true)
	await tree.process_frame
	check(InputRouter.is_pressed(&"crouch"), "INP-03 external button reaches router")
	InputRouter.external.reset()
	await tree.process_frame


func test_rebind_swaps_conflicts() -> void:
	var before_reload := InputRouter.get_kbm_spec(&"reload")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_E   # currently "interact"
	var old_path := Settings.path
	Settings.path = "user://test_settings.cfg"
	var swapped := InputRouter.rebind(&"reload", ev)
	eq(swapped, &"interact", "INP-04 conflicting action swapped")
	eq(InputRouter.get_kbm_spec(&"reload"), ["key", KEY_E], "INP-04 new binding")
	eq(InputRouter.get_kbm_spec(&"interact"), before_reload, "INP-04 swapped receives old key")
	InputRouter.reset_bindings()
	eq(InputRouter.get_kbm_spec(&"interact"), ["key", KEY_E], "INP-04 reset restores defaults")
	Settings.path = old_path


# ------------------------------------------------------------------ health (HP)

func test_health_damage_armor_headshot_death() -> void:
	var h := Health.new()
	h.max_health = 100.0
	h.armor = 0.5
	spawn(h)
	var died := [false]
	h.died.connect(func(_i): died[0] = true)
	h.apply_damage(DamageInfo.make(40, Vector3.ZERO, Vector3.FORWARD, null))
	near(h.current, 80.0, 0.01, "HP-01 armour halves body damage")
	h.apply_damage(DamageInfo.make(40, Vector3.ZERO, Vector3.FORWARD, null, true))
	near(h.current, 40.0, 0.01, "HP-02 headshots bypass armour")
	h.apply_damage(DamageInfo.make(200, Vector3.ZERO, Vector3.FORWARD, null, true))
	check(h.is_dead() and died[0], "HP-03 death signal")
	h.apply_damage(DamageInfo.make(10, Vector3.ZERO, Vector3.FORWARD, null))
	eq(h.current, 0.0, "HP-03 no damage after death")


func test_health_regen() -> void:
	var h := Health.new()
	h.max_health = 100.0
	h.regen_delay = 0.2
	h.regen_rate = 50.0
	spawn(h)
	h.apply_damage(DamageInfo.make(50, Vector3.ZERO, Vector3.FORWARD, null))
	await seconds(0.1)
	check(h.current < 51.0, "HP-04 no regen during delay")
	await seconds(0.8)
	check(h.current > 70.0, "HP-04 regen after delay (got %.1f)" % h.current)


# ------------------------------------------------------------------ sound events (SND)

func test_sound_event_bus() -> void:
	var got := []
	var cb := func(e): got.append(e)
	SoundEvents.sound_emitted.connect(cb)
	var e := SoundEvents.emit_sound(Vector3(1, 0, 2), 7.5, SoundEvent.Type.SPRINT, 0.8, null)
	SoundEvents.sound_emitted.disconnect(cb)
	eq(got.size(), 1, "SND-01 event delivered")
	eq(e.position, Vector3(1, 0, 2), "SND-01 position")
	eq(e.radius, 7.5, "SND-01 radius")
	eq(e.type, SoundEvent.Type.SPRINT, "SND-01 type")
	near(e.intensity, 0.8, 0.001, "SND-01 intensity")
	check(SoundEvent.SUSPICION_WEIGHT[SoundEvent.Type.GUNSHOT] > SoundEvent.SUSPICION_WEIGHT[SoundEvent.Type.FOOTSTEP], "SND-02 weights ordered")
	check(not SoundEvent.new().is_combat_sound(), "SND-02 footstep not combat")


# ------------------------------------------------------------------ settings (SET)

func test_settings_roundtrip_and_clamping() -> void:
	var old_path := Settings.path
	var old_music := Settings.music_volume
	var old_q := Settings.quality
	Settings.path = "user://test_settings.cfg"
	Settings.music_volume = 0.33
	Settings.quality = 3
	Settings.mouse_sensitivity = 1.7
	Settings.save_settings()
	Settings.music_volume = 1.0
	Settings.quality = 0
	Settings.load_settings()
	near(Settings.music_volume, 0.33, 0.001, "SET-01 music volume persisted")
	eq(Settings.quality, 3, "SET-01 quality persisted")
	near(Settings.mouse_sensitivity, 1.7, 0.001, "SET-01 sensitivity persisted")
	var cfg := ConfigFile.new()
	cfg.load(Settings.path)
	cfg.set_value("audio", "music", 7.0)
	cfg.set_value("graphics", "quality", 99)
	cfg.save(Settings.path)
	Settings.load_settings()
	near(Settings.music_volume, 1.0, 0.001, "SET-02 out-of-range volume clamped")
	eq(Settings.quality, 3, "SET-02 out-of-range quality clamped")
	Settings.apply()
	near(Settings.get_bus_linear("Music"), 1.0, 0.01, "SET-03 bus volume applied")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	Settings.path = old_path
	Settings.music_volume = old_music
	Settings.quality = old_q
	Settings.mouse_sensitivity = 1.0
	Settings.apply()
