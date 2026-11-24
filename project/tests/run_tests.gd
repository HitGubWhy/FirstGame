extends Node
## Standalone Unit Test Suite for Core Architecture (Stage 0 - Step 1).
## Zero external plugins. Attached to res://tests/test_runner.tscn.
## Verifies project.godot config, Autoloads, EventBus, SimulationClock, WorldCalendar,
## FloorLayerManager, StatSheet/StatModifier, PenetrationResolver, and AnatomyComponent/WoundResource.

var _passed_assertions: int = 0
var _failed_assertions: int = 0
var _suite_failures: int = 0
var _failure_messages: Array[String] = []


func _ready() -> void:
	# Pause automatic WorldCalendar ticks during deterministic tests
	WorldCalendar.paused = true
	print("==================================================================")
	print("  CORE & ARENA UNIT TEST SUITE (STAGE 0)")
	print("==================================================================")

	_run_suite("1. Project Config & Autoloads", _test_project_config_and_autoloads)
	_run_suite("2. EventBus Signals & Pipelines", _test_event_bus)
	_run_suite("3. SimulationClock (10..500, TP=5 bug-test, perception 0 vs 1)", _test_simulation_clock)
	_run_suite("4. WorldCalendar (Scale, Blood Moon, Stages 0..24, Interrupts)", _test_world_calendar)
	_run_suite("5. FloorLayerManager (4 Slots, 18 Bits, Flight, Floor Support)", _test_floor_layer_manager)
	_run_suite("6. StatSheet & StatModifier (12 Stats, Awakening, Circulation)", _test_stat_sheet)
	_run_suite("7. PenetrationResolver (Rank 6 Guardian, Weak Point, Aura)", _test_penetration_resolver)
	_run_suite("8. AnatomyComponent & WoundResource (Blood, Organs, Shock, Fall)", _test_anatomy_component)
	_run_suite("9. Step 2: ProceduralTileSetBuilder, VerticalityComponent & TestArena", _test_stage0_step2_arena_and_verticality)
	_run_suite("10. Step 3: Weapons, Sweeper, Player, Rank 1 & Rank 6 Enemies", _test_stage0_step3_combat_and_entities)
	await _run_suite_async("11. Step 4: DebugHUD, Main Scene & Anti-Tunneling Acceptance (14.2)", _test_stage0_step4_debug_hud_and_acceptance)
	await _run_suite_async("12. Regression Suite: Real Physics Sweep vs Rank 6, Flight Alignment & Fixes", _test_stage0_bugfixes_real_physics)
	_run_suite("13. v0.2 Core: 12th Stat REG, Human/Troll Presets & CON Separation", _test_v02_stat_sheet_reg_and_races)
	await _run_suite_async("14. v0.2 TempoMode (PEACEFUL/OVERDRIVE), Aggro Lock, Hitstop & Ambush", _test_v02_tempo_mode_hitstop_and_ambush)
	_run_suite("15. v0.2 Weapons, 4 Barriers, Strike Types, Dead Zone, Aura Burst & Blade Clash", _test_v02_weapons_barriers_and_clash)
	_run_suite("16. v0.2 Anatomy (4 Layers, Arterial, Tendons, Dismemberment, Lodged, REG, Anti-Regen)", _test_v02_anatomy_reg_and_dismemberment)
	await _run_suite_async("17. v0.2 Step 2: Warhammer, InputMap, 3 Attacks, Feint, Sidestep, Hardening, Clash, Clinch & Wall Slam", _test_v02_step2_combat_clinch_and_wall_slam)
	await _run_suite_async("18. v0.2 Step 3: SafeZone, Troll REG=160, Escape AI Cycle, Severed Limbs, INT+TP Telegraphs & Game Feel", _test_v02_step3_arena_ai_and_game_feel)
	await _run_suite_async("19. v0.2 Step 4: DebugHUD v0.2 & Full Section 14.2 Definition of Done Acceptance", _test_v02_step4_debug_hud_and_full_14_2_acceptance)
	await _run_suite_async("20. v0.2 Combat Balance: Kinetic, Starter Weapons, Blunt Lethality, Aura, Dead Zone, Clinch & Timers", _test_v02_combat_balance_fixes)
	await _run_suite_async("21. v0.2 AI Nav/Dive/Stairs, Disarm/Unarmed/Lodged, Counter-Window, Anti-Regen Contact & Drift/Dash Physics", _test_v02_ai_disarm_counter_and_physics_fixes)
	await _run_suite_async("22. v0.2 Polish: Wall/Floor Durability, Multi-Floor Visibility, 12-Stat DebugHUD, Death Overlay & Procedural Audio", _test_v02_polish_durability_visibility_hud_death_and_audio)
	await _run_suite_async("23. Stage A: Full HD Fullscreen, Adaptive HUD Anchors & Unified E-Interact Priority", _test_stage_a_fullscreen_anchors_and_interact)
	await _run_suite_async("24. Stage B: Game Combat HUD, KO Overlay, Pause Menu, Reticle & World Feedback", _test_stage_b_combat_hud_ko_pause_reticle_and_world_feedback)
	await _run_suite_async("25. Stage C: Disarmed AI, Directional/Unarmed Block, Stealth Backstab, Thrust Lunge & WorldCalendar Visuals", _test_stage_c_melee_polish_disarmed_ai_and_calendar_visuals)
	await _run_suite_async("26. Flight System: Leg-Injury Independence, MANA_FLIGHT, WING_FLIGHT & HUD Controls", _test_flight_modes_and_leg_injury_independence)
	await _run_suite_async("27. Modular Combat AI: Utility AI, TP/INT Reaction, Feints, Mid-Windup Sidestep, Flank, Clinch & Archetypes", _test_modular_combat_ai_system)
	await _run_suite_async("28. Stealth System: Crouch, Low-Obstacle Cover, StealthCoverZone, Suspicion, Distract, Backstab & Takedown", _test_stealth_system_crouch_cover_suspicion_distract_and_takedown)
	await _run_suite_async("29. 3/4 Top-Down Visuals: Rig, Front/Back, Walk/Limp/Flight Anim, Half-Swording, LodgedWeapon & 3/4 Tiles", _test_three_quarter_visuals_and_procedural_animation)

	print("==================================================================")
	print("  SUMMARY: %d passed, %d failed" % [_passed_assertions, _failed_assertions])
	if _failed_assertions == 0:
		print("  RESULT: ALL TESTS PASSED (GREEN)")
	else:
		print("  RESULT: TESTS FAILED (RED)")
		for msg: String in _failure_messages:
			print("    FAIL: %s" % msg)
	print("==================================================================")

	# Reset autoload state and flush cached telemetry references cleanly before exit
	EventBus.last_penetration_log = {}
	EventBus.last_combat_outcome = {}
	EventBus.last_blade_clash = {}
	EventBus.set_debug_highlight_weak_points(false)
	EventBus.set_debug_anti_regen_attacks(false)
	SimulationClock.reset_defaults()
	WorldCalendar.reset_calendar(0)
	FloorLayerManager.reset(0)

	# Auto-quit immediately in headless/CI mode; wait 2 frames so all queue_free() arenas flush cleanly!
	if DisplayServer.get_name() == "headless" or OS.get_cmdline_user_args().has("--auto-quit"):
		await get_tree().process_frame
		await get_tree().process_frame
		get_tree().quit(0 if _failed_assertions == 0 else 1)
	else:
		set_process(false)
		set_physics_process(false)
		print("  [TestRunner] Finished and stopped cleanly (press ESC or close window to exit).")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and key_event.keycode == KEY_ESCAPE:
			get_tree().quit(0 if _failed_assertions == 0 else 1)


func _run_suite(suite_name: String, test_fn: Callable) -> void:
	_suite_failures = 0
	var before_passed: int = _passed_assertions
	test_fn.call()
	var suite_passed: int = _passed_assertions - before_passed
	var status: String = "PASS" if _suite_failures == 0 else "FAIL"
	print("[%s] %s (%d assertions, %d failed)" % [status, suite_name, suite_passed + _suite_failures, _suite_failures])


func _run_suite_async(suite_name: String, test_fn: Callable) -> void:
	_suite_failures = 0
	var before_passed: int = _passed_assertions
	await test_fn.call()
	var suite_passed: int = _passed_assertions - before_passed
	var status: String = "PASS" if _suite_failures == 0 else "FAIL"
	print("[%s] %s (%d assertions, %d failed)" % [status, suite_name, suite_passed + _suite_failures, _suite_failures])


func _assert_true(condition: bool, message: String) -> void:
	if condition:
		_passed_assertions += 1
	else:
		_failed_assertions += 1
		_suite_failures += 1
		_failure_messages.append(message)
		printerr("  [FAIL] %s" % message)


func _assert_false(condition: bool, message: String) -> void:
	_assert_true(not condition, message)


func _assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual == expected:
		_passed_assertions += 1
	else:
		_failed_assertions += 1
		_suite_failures += 1
		var detail: String = "%s (expected: %s, got: %s)" % [message, str(expected), str(actual)]
		_failure_messages.append(detail)
		printerr("  [FAIL] %s" % detail)


func _assert_approx(actual: float, expected: float, tolerance: float, message: String) -> void:
	if absf(actual - expected) <= tolerance:
		_passed_assertions += 1
	else:
		_failed_assertions += 1
		_suite_failures += 1
		var detail: String = "%s (expected: %.6f +/- %.6f, got: %.6f)" % [message, expected, tolerance, actual]
		_failure_messages.append(detail)
		printerr("  [FAIL] %s" % detail)


func _assert_neq(actual: Variant, unexpected: Variant, message: String) -> void:
	if actual != unexpected:
		_passed_assertions += 1
	else:
		_failed_assertions += 1
		_suite_failures += 1
		var detail: String = "%s (did not expect: %s)" % [message, str(unexpected)]
		_failure_messages.append(detail)
		printerr("  [FAIL] %s" % detail)


func _find_zone(actor: CombatActor, zone_name: StringName) -> HitboxZone:
	if actor == null:
		return null
	for hz: HitboxZone in actor.hitbox_zones:
		if is_instance_valid(hz) and hz.zone_name == zone_name:
			return hz
	return null


# ===========================================================================
# SUITE 1: Project Configuration & Autoloads
# ===========================================================================

func _test_project_config_and_autoloads() -> void:
	# Virtual resolution 640x360
	_assert_eq(int(ProjectSettings.get_setting("display/window/size/viewport_width")), 640, "Viewport width is 640")
	_assert_eq(int(ProjectSettings.get_setting("display/window/size/viewport_height")), 360, "Viewport height is 360")

	# Texture filter Nearest (0)
	_assert_eq(int(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter")), 0, "Default texture filter is Nearest (0)")

	# Renderer preserved as GL Compatibility
	_assert_eq(String(ProjectSettings.get_setting("rendering/renderer/rendering_method")), "gl_compatibility", "Renderer remains gl_compatibility")

	# All 18 2D physics layer names (GDD 12.6)
	var expected_layers: Array[String] = [
		"Slot0_HighWalls", "Slot0_LowObstacles", "Slot0_Actors",
		"Slot1_HighWalls", "Slot1_LowObstacles", "Slot1_Actors",
		"Slot2_HighWalls", "Slot2_LowObstacles", "Slot2_Actors",
		"Slot3_HighWalls", "Slot3_LowObstacles", "Slot3_Actors",
		"HitboxZones", "Projectiles", "Interactables",
		"MindDomains", "FloorSupport", "Triggers_Stealth",
	]
	for i: int in range(expected_layers.size()):
		var setting_key: String = "layer_names/2d_physics/layer_%d" % (i + 1)
		_assert_eq(String(ProjectSettings.get_setting(setting_key, "")), expected_layers[i], "Physics layer %d name" % (i + 1))

	# All v0.2 InputMap actions (GDD 14.5, zero legacy conflicts)
	for legacy_action: StringName in [&"toggle_perception", &"attack_primary", &"block_parry", &"dash", &"toggle_aura"]:
		_assert_false(InputMap.has_action(legacy_action), "Deprecated v0.1 action %s removed from InputMap" % String(legacy_action))

	var expected_key_actions: Dictionary[StringName, Key] = {
		&"move_up": KEY_W,
		&"move_down": KEY_S,
		&"move_left": KEY_A,
		&"move_right": KEY_D,
		&"attack_blunt_clinch": KEY_Q,
		&"sidestep_dash": KEY_SPACE,
		&"hardening_guard": KEY_H,
		&"toggle_halfsword": KEY_TAB,
		&"feint_cancel": KEY_C,
		&"toggle_tempo_mode": KEY_G,
		&"aura_and_burst": KEY_R,
		&"switch_weapon_1": KEY_1,
		&"switch_weapon_2": KEY_2,
		&"switch_weapon_3": KEY_3,
		&"toggle_flight": KEY_F,
		&"interact": KEY_E,
		&"speed_reg_down": KEY_Z,
		&"speed_reg_up": KEY_X,
		&"toggle_debug_hud": KEY_F1,
	}
	for action_name: StringName in expected_key_actions.keys():
		_assert_true(InputMap.has_action(action_name), "InputMap has action %s" % String(action_name))
		var events: Array[InputEvent] = InputMap.action_get_events(action_name)
		_assert_true(events.size() >= 1 and events[0] is InputEventKey, "Action %s has InputEventKey" % String(action_name))
		if events.size() >= 1 and events[0] is InputEventKey:
			var key_ev: InputEventKey = events[0] as InputEventKey
			_assert_eq(key_ev.physical_keycode, expected_key_actions[action_name], "Action %s keycode matches" % String(action_name))

	_assert_true(InputMap.has_action(&"attack_slash"), "InputMap has attack_slash")
	var slash_events: Array[InputEvent] = InputMap.action_get_events(&"attack_slash")
	_assert_true(slash_events.size() >= 1 and slash_events[0] is InputEventMouseButton, "attack_slash is mouse button")
	if slash_events.size() >= 1 and slash_events[0] is InputEventMouseButton:
		_assert_eq((slash_events[0] as InputEventMouseButton).button_index, MOUSE_BUTTON_LEFT, "attack_slash is LMB")

	_assert_true(InputMap.has_action(&"attack_thrust"), "InputMap has attack_thrust")
	var thrust_events: Array[InputEvent] = InputMap.action_get_events(&"attack_thrust")
	_assert_true(thrust_events.size() >= 2, "attack_thrust has both Shift+LMB and V bindings")
	var has_shift_lmb: bool = false
	var has_key_v: bool = false
	for ev: InputEvent in thrust_events:
		if ev is InputEventMouseButton:
			var mb: InputEventMouseButton = ev as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT and mb.shift_pressed:
				has_shift_lmb = true
		elif ev is InputEventKey:
			if (ev as InputEventKey).physical_keycode == KEY_V:
				has_key_v = true
	_assert_true(has_shift_lmb, "attack_thrust includes Shift + LMB")
	_assert_true(has_key_v, "attack_thrust includes KEY_V")

	_assert_true(InputMap.has_action(&"offhand_defend"), "InputMap has offhand_defend")
	var rmb_events: Array[InputEvent] = InputMap.action_get_events(&"offhand_defend")
	_assert_true(rmb_events.size() >= 1 and rmb_events[0] is InputEventMouseButton, "offhand_defend is mouse button")
	if rmb_events.size() >= 1 and rmb_events[0] is InputEventMouseButton:
		_assert_eq((rmb_events[0] as InputEventMouseButton).button_index, MOUSE_BUTTON_RIGHT, "offhand_defend is RMB")

	# Autoloads
	_assert_true(get_tree().root.get_node_or_null("EventBus") != null, "EventBus autoload present")
	_assert_true(get_tree().root.get_node_or_null("SimulationClock") != null, "SimulationClock autoload present")
	_assert_true(get_tree().root.get_node_or_null("WorldCalendar") != null, "WorldCalendar autoload present")
	_assert_true(get_tree().root.get_node_or_null("FloorLayerManager") != null, "FloorLayerManager autoload present")
	_assert_approx(Engine.time_scale, 1.0, 1e-6, "Engine.time_scale strictly 1.0")


# ===========================================================================
# SUITE 2: EventBus Signals & Pipelines
# ===========================================================================

func _test_event_bus() -> void:
	# Damage pipeline interception
	var dmg_interceptor: Callable = func(ctx: Dictionary) -> void:
		ctx["effective_depth"] = float(ctx.get("effective_depth", 0.0)) * 2.0
	EventBus.damage_pipeline.connect(dmg_interceptor)
	var dmg_out: Dictionary = EventBus.run_damage_pipeline({"effective_depth": 5.0})
	EventBus.damage_pipeline.disconnect(dmg_interceptor)
	_assert_approx(float(dmg_out["effective_depth"]), 10.0, 1e-5, "damage_pipeline interceptor doubles depth")
	_assert_false(bool(dmg_out["cancelled"]), "damage_pipeline not cancelled by default")

	# Heal pipeline cancellation
	var heal_blocker: Callable = func(ctx: Dictionary) -> void:
		ctx["cancelled"] = true
	EventBus.heal_pipeline.connect(heal_blocker)
	var heal_out: Dictionary = EventBus.run_heal_pipeline({"amount_ml": 500.0})
	EventBus.heal_pipeline.disconnect(heal_blocker)
	_assert_true(bool(heal_out["cancelled"]), "heal_pipeline interceptor can cancel healing")

	# Penetration log signal
	var received_logs: Array[Dictionary] = []
	var log_cb: Callable = func(data: Dictionary) -> void:
		received_logs.append(data)
	EventBus.penetration_resolved.connect(log_cb)
	EventBus.publish_penetration_log({"penetrated": true, "effective_depth": 14.5})
	EventBus.penetration_resolved.disconnect(log_cb)
	_assert_eq(received_logs.size(), 1, "penetration_resolved signal emitted")
	_assert_approx(float(EventBus.last_penetration_log.get("effective_depth", 0.0)), 14.5, 1e-5, "EventBus stores last_penetration_log")

	# v0.2 EventBus signals presence & Blade Clash / Wall Slam publishers
	for sig_name: StringName in [&"tempo_mode_changed", &"hitstop_triggered", &"limb_severed", &"limb_regrown", &"blade_clashed", &"weapon_lodged", &"wall_slammed"]:
		_assert_true(EventBus.has_signal(sig_name), "EventBus declares v0.2 signal %s" % String(sig_name))
	var slam_events: Array[Dictionary] = []
	var slam_cb: Callable = func(ent: Node, cell: Vector2i, imp: float, broken: bool) -> void:
		slam_events.append({"entity": ent, "cell": cell, "impulse": imp, "broken": broken})
	EventBus.wall_slammed.connect(slam_cb)
	EventBus.publish_wall_slam(self, Vector2i(3, 4), 250.0, true)
	EventBus.wall_slammed.disconnect(slam_cb)
	_assert_eq(slam_events.size(), 1, "wall_slammed signal emitted")
	_assert_true(bool(slam_events[0]["broken"]), "wall_slammed carries wall_broken flag")


# ===========================================================================
# SUITE 3: SimulationClock
# ===========================================================================

func _test_simulation_clock() -> void:
	SimulationClock.reset_defaults()
	var dt: float = 0.016

	# Default TempoMode is PEACEFUL (1.0x) per GDD 2.3/12.1
	_assert_true(SimulationClock.is_peaceful(), "SimulationClock defaults to PEACEFUL TempoMode")
	SimulationClock.set_player_stats(500.0, 500.0, 500.0)
	_assert_approx(SimulationClock.get_world_time_scale(), 1.0, 1e-5, "PEACEFUL forces world_time_scale == 1.0 even at TP=500")
	_assert_approx(SimulationClock.get_player_action_delta(dt), dt, 1e-6, "PEACEFUL caps player eff_SPD at 10 (1.0x)")
	_assert_approx(SimulationClock.get_enemy_action_delta(dt, 500.0), dt, 1e-6, "PEACEFUL caps enemy eff_SPD at 10 (1.0x)")

	# Enter COMBAT_OVERDRIVE to verify full overdrive 10..500 math & regulators
	SimulationClock.set_tempo_mode(SimulationClock.TempoMode.COMBAT_OVERDRIVE)

	# Edge 10 (Human baseline)
	SimulationClock.set_player_stats(10.0, 10.0, 10.0)
	SimulationClock.perception_regulator = 1.0
	SimulationClock.speed_regulator = 1.0
	_assert_approx(SimulationClock.get_effective_tp(), 10.0, 1e-5, "TP=10 effective_TP == 10")
	_assert_approx(SimulationClock.get_world_time_scale(), 1.0, 1e-5, "TP=10 world_time_scale == 1.0")
	_assert_approx(SimulationClock.get_tp_penalty_mult(), 1.0, 1e-5, "TP=10 tp_penalty_mult == 1.0")
	_assert_approx(SimulationClock.get_world_delta(dt), dt, 1e-6, "TP=10 world_delta == delta")
	_assert_approx(SimulationClock.get_player_action_delta(dt), dt, 1e-6, "TP=10 SPD=10 player_action_delta == delta")
	_assert_approx(SimulationClock.get_enemy_action_delta(dt, 10.0), dt, 1e-6, "TP=10 enemy(SPD=10) action_delta == delta")

	# Edge 500 (Demigod max, perception_regulator = 1.0)
	SimulationClock.set_player_stats(500.0, 500.0, 500.0)
	SimulationClock.perception_regulator = 1.0
	SimulationClock.speed_regulator = 1.0
	_assert_approx(SimulationClock.get_effective_tp(), 500.0, 1e-5, "TP=500 perc=1.0 effective_TP == 500")
	_assert_approx(SimulationClock.get_world_time_scale(), 0.02, 1e-6, "TP=500 perc=1.0 world_time_scale == 0.02 (50x slow-mo)")
	_assert_approx(SimulationClock.get_world_delta(dt), dt * 0.02, 1e-7, "TP=500 world_delta slowed 50x")
	_assert_approx(SimulationClock.get_enemy_action_delta(dt, 10.0), dt * 0.02, 1e-7, "Rank 1 enemy slowed 50x")
	_assert_approx(SimulationClock.get_enemy_action_delta(dt, 500.0), dt, 1e-6, "Rank 11 enemy(SPD=500) matches 1x subjective time")
	_assert_approx(SimulationClock.get_player_action_delta(dt), dt, 1e-6, "TP=500 SPD=500 player_action_delta == 1x subjective time")

	# BUG-TEST: TP = 5 (deprivation/debuff -> player MUST slow down 0.5x, NOT speed up!)
	SimulationClock.set_player_stats(5.0, 10.0, 10.0)
	SimulationClock.perception_regulator = 1.0
	SimulationClock.speed_regulator = 1.0
	_assert_approx(SimulationClock.get_effective_tp(), 10.0, 1e-5, "TP=5 bug-test: effective_TP clamped at >= 10.0")
	_assert_approx(SimulationClock.get_world_time_scale(), 1.0, 1e-5, "TP=5 bug-test: world_time_scale NEVER exceeds 1.0")
	_assert_approx(SimulationClock.get_tp_penalty_mult(), 0.5, 1e-5, "TP=5 bug-test: tp_penalty_mult == 0.5")
	_assert_approx(SimulationClock.get_world_delta(dt), dt, 1e-6, "TP=5 bug-test: world_delta stays 1.0x")
	_assert_approx(SimulationClock.get_player_action_delta(dt), dt * 0.5, 1e-6, "TP=5 bug-test: player_action_delta slows to 0.5x")
	_assert_true(SimulationClock.get_player_action_delta(dt) < dt, "TP=5 bug-test: player strictly slower than normal")

	# perception_regulator = 0.0 vs 1.0 (GDD 2.3 & 14.2)
	SimulationClock.set_player_stats(500.0, 500.0, 500.0)
	SimulationClock.perception_regulator = 0.0
	SimulationClock.speed_regulator = 0.02
	_assert_approx(SimulationClock.get_effective_tp(), 10.0, 1e-5, "TP=500 perc=0.0 effective_TP == 10.0")
	_assert_approx(SimulationClock.get_world_time_scale(), 1.0, 1e-5, "TP=500 perc=0.0 world_time_scale == 1.0 (real-time world)")
	_assert_approx(SimulationClock.get_player_action_delta(dt), dt, 1e-6, "TP=500 SPD=500 perc=0.0 speed_reg=0.02 walks at normal 1x speed")

	# High-speed real-time travel (perc=0.0, speed_reg=1.0 -> 50x action_delta + micro-steps)
	SimulationClock.speed_regulator = 1.0
	var travel_action_dt: float = SimulationClock.get_player_action_delta(dt)
	_assert_approx(travel_action_dt, dt * 50.0, 1e-5, "TP=500 SPD=500 perc=0.0 speed_reg=1.0 moves 50x in real-time")
	var micro_steps: Array[float] = SimulationClock.compute_action_micro_steps(travel_action_dt)
	_assert_true(micro_steps.size() >= 40, "action_delta=0.8s split into >=40 micro-steps (<=0.02s each)")
	var micro_sum: float = 0.0
	for s: float in micro_steps:
		_assert_true(s <= SimulationClock.MAX_ACTION_MICRO_STEP + 1e-6, "Each micro-step <= 0.02s")
		micro_sum += s
	_assert_approx(micro_sum, travel_action_dt, 1e-5, "Micro-steps sum equals exact action_delta")

	# Intermediate perception_regulator = 0.5
	SimulationClock.perception_regulator = 0.5
	_assert_approx(SimulationClock.get_effective_tp(), 255.0, 1e-5, "TP=500 perc=0.5 effective_TP == 255")
	_assert_approx(SimulationClock.get_world_time_scale(), 10.0 / 255.0, 1e-6, "TP=500 perc=0.5 world_time_scale == 10/255")

	# Clamping of regulators and Engine.time_scale invariant
	SimulationClock.speed_regulator = 0.0001
	_assert_approx(SimulationClock.speed_regulator, 0.02, 1e-6, "speed_regulator min clamp == 0.02")
	SimulationClock.speed_regulator = 5.0
	_assert_approx(SimulationClock.speed_regulator, 1.0, 1e-6, "speed_regulator max clamp == 1.0")
	SimulationClock.perception_regulator = -1.0
	_assert_approx(SimulationClock.perception_regulator, 0.0, 1e-6, "perception_regulator min clamp == 0.0")
	SimulationClock.perception_regulator = 3.0
	_assert_approx(SimulationClock.perception_regulator, 1.0, 1e-6, "perception_regulator max clamp == 1.0")
	_assert_true(SimulationClock.is_imperceptible_speed(100.0, 10.0), "100 SPD vs 10 TP is imperceptible (>=10x)")
	_assert_false(SimulationClock.is_imperceptible_speed(99.0, 10.0), "99 SPD vs 10 TP is not imperceptible (<10x)")
	_assert_true(SimulationClock.is_losing_control(20.0, 10.0, 1.0), "20 SPD vs 10 TP loses control (>1.5x)")
	_assert_false(SimulationClock.is_losing_control(20.0, 10.0, 0.5), "Lowering speed_regulator prevents loss of control")
	_assert_approx(Engine.time_scale, 1.0, 1e-6, "Engine.time_scale stays 1.0 after all clock operations")


# ===========================================================================
# SUITE 4: WorldCalendar
# ===========================================================================

func _test_world_calendar() -> void:
	WorldCalendar.reset_calendar(0)

	var hours_seen: Array[int] = []
	var days_seen: Array[int] = []
	var stages_seen: Array[int] = []
	var interrupts_seen: Array[String] = []

	var on_hour: Callable = func(h: int) -> void: hours_seen.append(h)
	var on_day: Callable = func(d: int) -> void: days_seen.append(d)
	var on_stage: Callable = func(s: int) -> void: stages_seen.append(s)
	var on_interrupt: Callable = func(r: String) -> void: interrupts_seen.append(r)

	EventBus.hour_changed.connect(on_hour)
	EventBus.day_passed.connect(on_day)
	EventBus.world_stage_changed.connect(on_stage)
	EventBus.time_acceleration_interrupted.connect(on_interrupt)

	# 1 game hour = 2 real minutes (120 real seconds), independent of SimulationClock slow-mo
	SimulationClock.set_tempo_mode(SimulationClock.TempoMode.COMBAT_OVERDRIVE)
	SimulationClock.set_player_stats(500.0, 500.0)
	SimulationClock.perception_regulator = 1.0
	_assert_approx(SimulationClock.get_world_time_scale(), 0.02, 1e-6, "SimulationClock in 50x slow-mo during calendar test")

	WorldCalendar.advance_real_seconds(120.0)
	_assert_eq(WorldCalendar.get_hour(), 1, "120 real sec advances exactly 1 game hour")
	_assert_eq(hours_seen.size(), 1, "hour_changed emitted once after 120 real sec")

	# Complete first full day: 23 more game hours = 23 * 120 = 2760 real sec (total 48 real min)
	WorldCalendar.advance_real_seconds(23.0 * 120.0)
	_assert_eq(WorldCalendar.get_total_day(), 2, "48 real min advances to Day 2")
	_assert_eq(WorldCalendar.get_hour(), 0, "Hour wraps cleanly to 00:00")
	_assert_eq(days_seen.size(), 1, "day_passed emitted once after 1 day")
	_assert_eq(WorldCalendar.get_world_stage(), 0, "Day 2 is still world_stage 0")

	# Advance to Day 16 (elapsed_days = 15) -> world_stage becomes 1
	WorldCalendar.fast_forward_days(14.0, false)
	_assert_eq(WorldCalendar.get_total_day(), 16, "Fast forward to Day 16")
	_assert_eq(WorldCalendar.get_world_stage(), 1, "Day 16 (15 elapsed days) triggers world_stage 1")
	_assert_eq(stages_seen.size(), 1, "world_stage_changed emitted once")
	_assert_false(WorldCalendar.is_blood_moon(), "Day 16 is not Blood Moon")

	# Test time acceleration (30x) + automatic Blood Moon interruption on Day 30
	WorldCalendar.start_time_acceleration(30.0)
	_assert_true(WorldCalendar.is_accelerating(), "Time acceleration active at 30x")
	# Attempt to fast-forward 20 days with stop_on_blood_moon = true; must stop right at Day 30 (14 days forward)
	var days_elapsed: float = WorldCalendar.fast_forward_days(20.0, true)
	_assert_approx(days_elapsed, 14.0, 1e-4, "Fast-forward stopped precisely at Blood Moon onset (14 days from Day 16 -> Day 30)")
	_assert_eq(WorldCalendar.get_total_day(), 30, "Stopped on Day 30")
	_assert_eq(WorldCalendar.get_day_of_month(), 30, "Day of month is 30")
	_assert_true(WorldCalendar.is_blood_moon(), "Day 30 is Blood Moon")
	_assert_approx(WorldCalendar.get_mana_training_mult(), 2.0, 1e-5, "Blood Moon gives 2x mana training mult")
	_assert_false(WorldCalendar.is_accelerating(), "Blood Moon automatically interrupted time acceleration")
	_assert_eq(WorldCalendar.last_interrupt_reason, WorldCalendar.INTERRUPT_BLOOD_MOON, "Interrupt reason is blood_moon_started")
	_assert_eq(interrupts_seen.size(), 1, "time_acceleration_interrupted emitted once")

	# Explicit interruption by hostile threat
	WorldCalendar.start_time_acceleration(60.0)
	_assert_approx(WorldCalendar.time_acceleration, 60.0, 1e-5, "Acceleration set to 60x")
	var did_interrupt: bool = WorldCalendar.interrupt_acceleration(WorldCalendar.INTERRUPT_HOSTILE)
	_assert_true(did_interrupt, "Hostile interrupt succeeded")
	_assert_false(WorldCalendar.is_accelerating(), "Acceleration reset to 1x after hostile interrupt")
	_assert_eq(WorldCalendar.last_interrupt_reason, WorldCalendar.INTERRUPT_HOSTILE, "Interrupt reason recorded as hostile_detected")

	# Day 31 -> Month 2, Day 1, not Blood Moon
	WorldCalendar.fast_forward_days(1.0, false)
	_assert_eq(WorldCalendar.get_month(), 2, "30 days per month: Day 31 is Month 2")
	_assert_eq(WorldCalendar.get_day_of_month(), 1, "Day 31 is Day 1 of Month 2")
	_assert_false(WorldCalendar.is_blood_moon(), "Day 1 of Month 2 is not Blood Moon")

	# Fast-forward full 1-year cycle to Day 360 and Day 361 (Conquered World, stage 24)
	WorldCalendar.reset_calendar(0)
	stages_seen.clear()
	WorldCalendar.fast_forward_days(359.0, false) # elapsed 359 -> Day 360, Month 12, Day 30, Year 1
	_assert_eq(WorldCalendar.get_year(), 1, "Day 360 is still Year 1")
	_assert_eq(WorldCalendar.get_month(), 12, "Day 360 is Month 12")
	_assert_eq(WorldCalendar.get_day_of_month(), 30, "Day 360 is Day 30 (Blood Moon)")
	_assert_true(WorldCalendar.is_blood_moon(), "Day 360 is Blood Moon")
	_assert_eq(WorldCalendar.get_world_stage(), 23, "Day 360 is world_stage 23")
	_assert_false(WorldCalendar.is_world_conquered(), "World not yet conquered on Day 360")

	WorldCalendar.fast_forward_days(1.0, false) # elapsed 360 -> Day 361, Year 2, Month 1, Day 1
	_assert_eq(WorldCalendar.get_year(), 2, "360 days/year: Day 361 is Year 2")
	_assert_eq(WorldCalendar.get_month(), 1, "Day 361 is Month 1")
	_assert_eq(WorldCalendar.get_day_of_month(), 1, "Day 361 is Day 1")
	_assert_eq(WorldCalendar.get_world_stage(), 24, "Day 361 reaches final world_stage 24")
	_assert_true(WorldCalendar.is_world_conquered(), "World is conquered at stage 24")
	_assert_eq(stages_seen.size(), 24, "Exactly 24 world_stage_changed transitions over 1 year")

	# Stage stays capped at 24 beyond Day 361
	WorldCalendar.fast_forward_days(60.0, false)
	_assert_eq(WorldCalendar.get_world_stage(), 24, "world_stage remains capped at 24")

	EventBus.hour_changed.disconnect(on_hour)
	EventBus.day_passed.disconnect(on_day)
	EventBus.world_stage_changed.disconnect(on_stage)
	EventBus.time_acceleration_interrupted.disconnect(on_interrupt)


# ===========================================================================
# SUITE 5: FloorLayerManager
# ===========================================================================

func _test_floor_layer_manager() -> void:
	FloorLayerManager.reset(0)

	# Focus floor 0 -> active window [-1, 0, 1, 2]
	_assert_eq(FloorLayerManager.get_window_min_floor(), -1, "Focus 0 min floor == -1")
	_assert_eq(FloorLayerManager.get_window_max_floor(), 2, "Focus 0 max floor == 2")
	_assert_true(FloorLayerManager.is_floor_active(-1), "Floor -1 active")
	_assert_true(FloorLayerManager.is_floor_active(0), "Floor 0 active")
	_assert_true(FloorLayerManager.is_floor_active(1), "Floor 1 active")
	_assert_true(FloorLayerManager.is_floor_active(2), "Floor 2 active")
	_assert_false(FloorLayerManager.is_floor_active(-2), "Floor -2 inactive")
	_assert_false(FloorLayerManager.is_floor_active(3), "Floor 3 inactive")

	# Exact slot & bit mapping for floors 0, 1, 2, -1
	_assert_eq(FloorLayerManager.get_slot_for_floor(0), 0, "Floor 0 -> Slot 0")
	_assert_eq(FloorLayerManager.get_slot_for_floor(1), 1, "Floor 1 -> Slot 1")
	_assert_eq(FloorLayerManager.get_slot_for_floor(2), 2, "Floor 2 -> Slot 2")
	_assert_eq(FloorLayerManager.get_slot_for_floor(-1), 3, "Floor -1 -> Slot 3")
	_assert_eq(FloorLayerManager.get_slot_for_floor(3), -1, "Inactive floor 3 -> slot -1")

	# Slot 0: layers 1, 2, 3 (bits 0, 1, 2 -> 1, 2, 4)
	_assert_eq(FloorLayerManager.get_high_walls_bit(0), 1 << 0, "Floor 0 HighWalls == bit 0 (Layer 1)")
	_assert_eq(FloorLayerManager.get_low_obstacles_bit(0), 1 << 1, "Floor 0 LowObstacles == bit 1 (Layer 2)")
	_assert_eq(FloorLayerManager.get_actors_bit(0), 1 << 2, "Floor 0 Actors == bit 2 (Layer 3)")

	# Slot 1: layers 4, 5, 6 (bits 3, 4, 5)
	_assert_eq(FloorLayerManager.get_high_walls_bit(1), 1 << 3, "Floor 1 HighWalls == bit 3 (Layer 4)")
	_assert_eq(FloorLayerManager.get_low_obstacles_bit(1), 1 << 4, "Floor 1 LowObstacles == bit 4 (Layer 5)")
	_assert_eq(FloorLayerManager.get_actors_bit(1), 1 << 5, "Floor 1 Actors == bit 5 (Layer 6)")

	# Slot 2: layers 7, 8, 9 (bits 6, 7, 8)
	_assert_eq(FloorLayerManager.get_high_walls_bit(2), 1 << 6, "Floor 2 HighWalls == bit 6 (Layer 7)")
	_assert_eq(FloorLayerManager.get_low_obstacles_bit(2), 1 << 7, "Floor 2 LowObstacles == bit 7 (Layer 8)")
	_assert_eq(FloorLayerManager.get_actors_bit(2), 1 << 8, "Floor 2 Actors == bit 8 (Layer 9)")

	# Slot 3: layers 10, 11, 12 (bits 9, 10, 11)
	_assert_eq(FloorLayerManager.get_high_walls_bit(-1), 1 << 9, "Floor -1 HighWalls == bit 9 (Layer 10)")
	_assert_eq(FloorLayerManager.get_low_obstacles_bit(-1), 1 << 10, "Floor -1 LowObstacles == bit 10 (Layer 11)")
	_assert_eq(FloorLayerManager.get_actors_bit(-1), 1 << 11, "Floor -1 Actors == bit 11 (Layer 12)")

	# Inactive floor returns 0 bitmask
	_assert_eq(FloorLayerManager.get_actor_collision_mask(3, 0.0), 0, "Inactive floor returns mask 0")

	# Verify zero bit overlap across all 4 active floors AND shared layers 13..18 within 18 bits
	var combined_mask: int = 0
	for fl: int in [-1, 0, 1, 2]:
		var fl_mask: int = FloorLayerManager.get_high_walls_bit(fl) | FloorLayerManager.get_low_obstacles_bit(fl) | FloorLayerManager.get_actors_bit(fl)
		_assert_eq(combined_mask & fl_mask, 0, "Floor %d bits do not overlap other active floors" % fl)
		combined_mask |= fl_mask
	var shared_mask: int = (
		FloorLayerManager.BIT_HITBOX_ZONES
		| FloorLayerManager.BIT_PROJECTILES
		| FloorLayerManager.BIT_INTERACTABLES
		| FloorLayerManager.BIT_MIND_DOMAINS
		| FloorLayerManager.BIT_FLOOR_SUPPORT
		| FloorLayerManager.BIT_TRIGGERS_STEALTH
	)
	_assert_eq(combined_mask & shared_mask, 0, "Shared layers 13..18 do not overlap floor slots 1..12")
	_assert_eq(combined_mask | shared_mask, FloorLayerManager.ALL_USED_LAYERS_MASK, "Total physics layout uses exact 18 bits (layers 1..18)")

	# Flight mask check: ground includes LowObstacles, flying (height_z >= 1.0) excludes LowObstacles
	var ground_mask: int = FloorLayerManager.get_actor_collision_mask(0, 0.0, true)
	var expected_ground: int = (1 << 0) | (1 << 1) | (1 << 2)
	_assert_eq(ground_mask, expected_ground, "Ground actor mask on floor 0 = HighWalls | LowObstacles | Actors")

	var flying_mask: int = FloorLayerManager.get_actor_collision_mask(0, 1.5, true)
	var expected_flying: int = (1 << 0) | (1 << 2)
	_assert_eq(flying_mask, expected_flying, "Flying actor mask (height_z=1.5) disables LowObstacles, keeps HighWalls & Actors")

	# Shifting focus floor (e.g., climbing tower to floor 5 -> active window [4, 5, 6, 7])
	FloorLayerManager.set_focus_floor(5)
	_assert_false(FloorLayerManager.is_floor_active(0), "Floor 0 deactivated after moving focus to 5")
	_assert_true(FloorLayerManager.is_floor_active(4) and FloorLayerManager.is_floor_active(7), "Floors 4..7 active at focus 5")
	var shifted_mask: int = 0
	for fl: int in [4, 5, 6, 7]:
		var fl_mask: int = FloorLayerManager.get_high_walls_bit(fl) | FloorLayerManager.get_low_obstacles_bit(fl) | FloorLayerManager.get_actors_bit(fl)
		_assert_eq(shifted_mask & fl_mask, 0, "Shifted floor %d has unique slot bits" % fl)
		shifted_mask |= fl_mask

	# Floor integrity storage & breaking floor tile
	FloorLayerManager.reset(0)
	var test_cell: Vector2i = Vector2i(4, 3)
	_assert_false(FloorLayerManager.has_floor_at(1, test_cell), "Unregistered upper floor cell returns false")
	FloorLayerManager.register_floor_rect(1, Rect2i(0, 0, 8, 8))
	_assert_true(FloorLayerManager.has_floor_at(1, test_cell), "Registered upper floor cell returns true")
	_assert_false(FloorLayerManager.should_entity_fall(1, test_cell, 0.0), "Standing on intact floor does not fall")

	var broken_events: Array[Dictionary] = []
	var on_broken: Callable = func(fl: int, c: Vector2i) -> void:
		broken_events.append({"floor": fl, "cell": c})
	EventBus.floor_tile_broken.connect(on_broken)
	var did_break: bool = FloorLayerManager.break_floor_at(1, test_cell)
	EventBus.floor_tile_broken.disconnect(on_broken)

	_assert_true(did_break, "break_floor_at returns true for intact tile")
	_assert_false(FloorLayerManager.has_floor_at(1, test_cell), "has_floor_at becomes false after breaking")
	_assert_eq(broken_events.size(), 1, "floor_tile_broken signal emitted")
	_assert_true(FloorLayerManager.should_entity_fall(1, test_cell, 0.0), "Grounded entity falls through broken floor")
	_assert_false(FloorLayerManager.should_entity_fall(1, test_cell, 1.5), "Flying entity (height_z=1.5) hovers over hole")
	_assert_eq(FloorLayerManager.get_visual_z_index(1, 1.5), 115, "Visual z_index = floor*100 + int(height_z*10)")


# ===========================================================================
# SUITE 6: StatSheet & StatModifier
# ===========================================================================

func _test_stat_sheet() -> void:
	# Default Human before mana awakening (GDD 14.4)
	var sheet: StatSheet = StatSheet.new(StatSheet.DEFAULT_HUMAN_RACIAL_CAP)
	_assert_false(sheet.mana_awakened, "Starts with mana unawakened")
	_assert_approx(sheet.get_stat(StatSheet.Stat.STR), 10.0, 1e-5, "Default STR == 10")
	_assert_approx(sheet.get_stat(StatSheet.Stat.SOUL), 10.0, 1e-5, "Default SOUL == 10")
	_assert_approx(sheet.get_stat(StatSheet.Stat.MP_CAP), 0.0, 1e-5, "Before awakening MP_CAP == 0")
	_assert_approx(sheet.get_stat(StatSheet.Stat.M_CTRL), 0.0, 1e-5, "Before awakening M_CTRL == 0")
	_assert_approx(sheet.get_max_mp(), 0.0, 1e-5, "Before awakening max MP == 0")
	_assert_approx(sheet.get_circulation_mult(), 1.0, 1e-5, "Before awakening circ_mult == 1.0")
	_assert_approx(sheet.get_mana_skin_density(), 0.0, 1e-5, "Before awakening mana_skin_density == 0.0")
	_assert_approx(sheet.get_circulation_stat_bonus(), 0.0, 1e-5, "Before awakening circ_stat_bonus == 0.0")
	_assert_approx(sheet.get_sp_cap(), 100.0, 1e-5, "SOUL=10 -> SP_CAP == 100")
	_assert_eq(sheet.get_essence_slots(), 1, "SOUL=10 -> 1 essence slot")

	# Racial cap enforced before awakening (Human cap = 22) + racial multiplier active
	sheet.set_base_stat(StatSheet.Stat.STR, 40.0)
	sheet.add_modifier(StatModifier.create_multiplier(&"human_str_penalty", StatSheet.Stat.AGI, 0.8, &"race", 0, [StatSheet.TAG_RACIAL_MULT]))
	_assert_approx(sheet.get_stat(StatSheet.Stat.STR), 22.0, 1e-5, "Human racial cap clamps STR=40 to 22 before awakening")
	_assert_approx(sheet.get_stat(StatSheet.Stat.AGI), 8.0, 1e-5, "Racial multiplier active before awakening (10*0.8=8)")

	# Mana Awakening removes ALL racial caps and racial multipliers! (GDD 2.1, 14.4)
	sheet.awaken_mana(10.0, 10.0)
	_assert_true(sheet.mana_awakened, "Mana awakened")
	_assert_approx(sheet.get_stat(StatSheet.Stat.MP_CAP), 10.0, 1e-5, "After awakening MP_CAP == 10")
	_assert_approx(sheet.get_stat(StatSheet.Stat.M_CTRL), 10.0, 1e-5, "After awakening M_CTRL == 10")
	_assert_approx(sheet.get_max_mp(), 100.0, 1e-4, "MP_CAP=10 -> max MP == 100")
	# At M_CTRL=10: circ_mult = 1.15, circ_stat_bonus = floor(0.5 * 1 * 1.15) = 0
	_assert_approx(sheet.get_stat(StatSheet.Stat.STR), 40.0, 1e-5, "Racial cap removed after awakening: STR unlocks to 40")
	_assert_approx(sheet.get_stat(StatSheet.Stat.AGI), 10.0, 1e-5, "Racial multiplier disabled after awakening: AGI returns to 10")

	# External Circulation exact math (GDD Section 2.2)
	var circ_sheet: StatSheet = StatSheet.new()
	circ_sheet.awaken_mana(100.0, 100.0)
	circ_sheet.set_all_base_stats(50.0, false)
	_assert_approx(circ_sheet.get_circulation_mult(), 2.5, 1e-5, "M_CTRL=100 -> circ_mult == 2.5")
	_assert_approx(circ_sheet.get_mana_skin_density(), 313.9858, 0.05, "M_CTRL=100 -> mana_skin_density ~= 314")
	_assert_approx(circ_sheet.get_circulation_stat_bonus(), 12.0, 1e-5, "M_CTRL=100 -> circ_stat_bonus == +12")
	# Applied to STR, CTRL, SPD, TP, CON ONLY
	_assert_approx(circ_sheet.get_stat(StatSheet.Stat.STR), 62.0, 1e-5, "Circulation adds +12 to STR")
	_assert_approx(circ_sheet.get_stat(StatSheet.Stat.CTRL), 62.0, 1e-5, "Circulation adds +12 to CTRL")
	_assert_approx(circ_sheet.get_stat(StatSheet.Stat.SPD), 62.0, 1e-5, "Circulation adds +12 to SPD")
	_assert_approx(circ_sheet.get_stat(StatSheet.Stat.TP), 62.0, 1e-5, "Circulation adds +12 to TP")
	_assert_approx(circ_sheet.get_stat(StatSheet.Stat.CON), 62.0, 1e-5, "Circulation adds +12 to CON")
	# NOT applied to AGI, STA, INT, SOUL
	_assert_approx(circ_sheet.get_stat(StatSheet.Stat.AGI), 50.0, 1e-5, "Circulation does NOT add to AGI")
	_assert_approx(circ_sheet.get_stat(StatSheet.Stat.STA), 50.0, 1e-5, "Circulation does NOT add to STA")
	_assert_approx(circ_sheet.get_stat(StatSheet.Stat.INT), 50.0, 1e-5, "Circulation does NOT add to INT")
	_assert_approx(circ_sheet.get_stat(StatSheet.Stat.SOUL), 50.0, 1e-5, "Circulation does NOT add to SOUL")

	# M_CTRL = 400 and hard ceiling 500 check (GDD 2.2)
	circ_sheet.set_base_stat(StatSheet.Stat.M_CTRL, 400.0)
	circ_sheet.set_base_stat(StatSheet.Stat.STR, 400.0)
	_assert_approx(circ_sheet.get_circulation_mult(), 7.0, 1e-5, "M_CTRL=400 -> circ_mult == 7.0")
	_assert_approx(circ_sheet.get_mana_skin_density(), 5.0 * pow(40.0, 1.4) * 7.0, 1e-3, "M_CTRL=400 -> mana_skin_density == 6122.83 (~6120)")
	_assert_approx(circ_sheet.get_circulation_stat_bonus(), 140.0, 1e-5, "M_CTRL=400 -> circ_stat_bonus == +140")
	_assert_approx(circ_sheet.get_stat(StatSheet.Stat.STR), 500.0, 1e-5, "400 base + 140 circ clamped at hard ceiling 500")

	# M_CTRL = 500 edge
	circ_sheet.set_base_stat(StatSheet.Stat.M_CTRL, 500.0)
	_assert_approx(circ_sheet.get_circulation_mult(), 8.5, 1e-5, "M_CTRL=500 -> circ_mult == 8.5")
	_assert_approx(circ_sheet.get_circulation_stat_bonus(), 212.0, 1e-5, "M_CTRL=500 -> circ_stat_bonus == +212")

	# Scale edges 10 vs 500 derived formulas (GDD Table 3.1 & 3.2)
	var s10: StatSheet = StatSheet.new()
	s10.awaken_mana(10.0, 10.0)
	_assert_approx(s10.get_melee_damage_mult(), 1.0, 1e-5, "STR=10 melee mult == 1x")
	_assert_approx(s10.get_carry_capacity_kg(1.0), 60.0, 1e-5, "STR=10 carry == 60 kg")
	_assert_approx(s10.get_move_speed_mult(), 1.0, 1e-5, "SPD=10 move mult == 1x")
	_assert_approx(s10.get_con_skin_density(), 10.0, 1e-4, "CON=10 skin density == 10")
	_assert_approx(s10.get_max_stamina(), 150.0, 1e-4, "STA=10 max stamina == 150")
	_assert_approx(s10.get_dash_mult(), 1.0, 1e-5, "AGI=10 dash mult == 1.0x")
	_assert_approx(s10.get_instinct_dodge_chance(10.0), 5.0 / 90.0, 1e-5, "AGI=10 instinct dodge ~= 5.6%")

	var s500: StatSheet = StatSheet.new()
	s500.awaken_mana(500.0, 500.0)
	s500.set_all_base_stats(500.0, true)
	_assert_approx(s500.get_melee_damage_mult(), 2500.0, 1e-3, "STR=500 melee mult == 2500x")
	_assert_approx(s500.get_carry_capacity_kg(1.0), 150000.0, 1e-2, "STR=500 carry == 150 tons")
	_assert_approx(s500.get_move_speed_mult(), 50.0, 1e-5, "SPD=500 move mult == 50x")
	_assert_approx(s500.get_run_speed_px(), 11000.0, 1e-2, "SPD=500 run speed == 11000 px/s")
	_assert_approx(s500.get_con_skin_density(), 10.0 * pow(50.0, 1.8), 1e-3, "CON=500 skin density == 11432.63 (~11450)")
	_assert_approx(s500.get_max_stamina(), 17777.67, 1.0, "STA=500 max stamina ~= 17778")
	_assert_approx(s500.get_sp_cap(), 5000.0, 1e-4, "SOUL=500 -> SP_CAP == 5000")
	_assert_eq(s500.get_essence_slots(), 15, "SOUL=500 -> 15 essence slots")
	_assert_approx(s500.get_dash_mult(), 13.25, 1e-5, "AGI=500 dash mult == 13.25x")
	_assert_approx(s500.get_instinct_dodge_chance(500.0), 495.0 / 580.0, 1e-5, "AGI=500 instinct dodge ~= 85.3%")
	_assert_approx(s500.get_mp_cost_mult(), 0.20, 1e-5, "M_CTRL=500 MP cost discount capped at -80% (0.20x)")
	_assert_true(s500.has_mental_shield(1.0), "SOUL=500 with SP>0 has Mental Shield")
	_assert_false(s500.has_mental_shield(0.0), "SOUL=500 with SP==0 loses Mental Shield")

	# 4-layer ordering & Overrides & Tag Ignoring
	var pipe: StatSheet = StatSheet.new()
	pipe.awaken_mana(10.0, 10.0)
	pipe.set_base_stat(StatSheet.Stat.INT, 20.0)
	pipe.add_modifier(StatModifier.create_base(&"b1", StatSheet.Stat.INT, 5.0)) # 20 + 5 = 25
	pipe.add_modifier(StatModifier.create_flat(&"f1", StatSheet.Stat.INT, 15.0, &"eq", 0, [StatSheet.TAG_EQUIPMENT])) # 25 + 15 = 40
	pipe.add_modifier(StatModifier.create_multiplier(&"m1", StatSheet.Stat.INT, 1.5)) # 40 * 1.5 = 60
	_assert_approx(pipe.get_stat(StatSheet.Stat.INT), 60.0, 1e-5, "4-layer pipeline: ((20+5)+15)*1.5 == 60")

	pipe.add_ignored_tag(StatSheet.TAG_EQUIPMENT)
	_assert_approx(pipe.get_stat(StatSheet.Stat.INT), 37.5, 1e-5, "Ignoring equipment tag skips flat +15: (25)*1.5 == 37.5")
	pipe.clear_ignored_tags()

	# Hard floor 1.0 for normal penalties vs explicit OVERRIDE SET_VALUE 0.0 (overload AGI = 0)
	pipe.add_modifier(StatModifier.create_multiplier(&"tiny", StatSheet.Stat.INT, 0.001))
	_assert_approx(pipe.get_stat(StatSheet.Stat.INT), 1.0, 1e-5, "Normal multiplier floors stat at 1.0")
	pipe.add_modifier(StatModifier.create_override(&"overload_agi", StatSheet.Stat.AGI, 0.0, &"overload"))
	_assert_approx(pipe.get_stat(StatSheet.Stat.AGI), 0.0, 1e-5, "Explicit OVERRIDE SET_VALUE allows AGI = 0.0 on overload")

	# Relative Control Deficit Penalty (STR > CTRL * 1.15)
	var ctrl_sheet: StatSheet = StatSheet.new()
	ctrl_sheet.awaken_mana(10.0, 10.0)
	ctrl_sheet.set_base_stat(StatSheet.Stat.STR, 11.5)
	ctrl_sheet.set_base_stat(StatSheet.Stat.CTRL, 10.0)
	_assert_approx(ctrl_sheet.get_control_deficit_ratio(), 0.0, 1e-5, "STR == CTRL*1.15 has zero control deficit")
	_assert_approx(ctrl_sheet.get_corpse_obliteration_chance(), 0.0, 1e-5, "No obliteration chance at 1.15 ratio")

	ctrl_sheet.set_base_stat(StatSheet.Stat.STR, 20.0)
	_assert_approx(ctrl_sheet.get_control_deficit_ratio(), 0.85, 1e-5, "STR=20 CTRL=10 -> R = 0.85")
	_assert_approx(ctrl_sheet.get_corpse_obliteration_chance(), 1.0, 1e-5, "Obliteration chance clamped at 100% (0.85*1.2=1.02)")
	_assert_approx(ctrl_sheet.get_extra_weapon_wear_mult(), 0.85, 1e-5, "Extra weapon wear == +85%")
	_assert_approx(ctrl_sheet.get_accidental_break_chance(false), 1.0, 1e-5, "Accidental break chance 100% in rough mode")
	_assert_approx(ctrl_sheet.get_accidental_break_chance(true), 0.0, 1e-5, "Accidental break disabled in careful mode")

	# Multiplicative Stamina Discounts (CTRL + STA, cap -85% -> min cost mult 0.15)
	var stam_sheet: StatSheet = StatSheet.new()
	stam_sheet.awaken_mana(10.0, 10.0)
	stam_sheet.set_base_stat(StatSheet.Stat.STR, 10.0)
	stam_sheet.set_base_stat(StatSheet.Stat.CTRL, 50.0) # excess 40 -> d_ctrl = 40*0.005 = 0.20 (-20%)
	stam_sheet.set_base_stat(StatSheet.Stat.STA, 255.0) # (245/490)*0.75 = 0.375 (-37.5%)
	_assert_approx(stam_sheet.get_ctrl_stamina_discount(), 0.20, 1e-5, "CTRL excess 40 gives 20% discount")
	_assert_approx(stam_sheet.get_sta_stamina_discount(), 0.375, 1e-5, "STA=255 gives 37.5% discount")
	_assert_approx(stam_sheet.get_stamina_cost_mult(true), 0.50, 1e-5, "Multiplicative stamina mult: (1-0.375)*(1-0.20) == 0.50 (not additive 0.425)")

	stam_sheet.set_base_stat(StatSheet.Stat.CTRL, 200.0) # capped at -40%
	stam_sheet.set_base_stat(StatSheet.Stat.STA, 500.0) # -75%
	_assert_approx(stam_sheet.get_stamina_cost_mult(true), 0.15, 1e-5, "Combined STA + CTRL stamina discount capped at -85% (mult 0.15)")
	_assert_approx(stam_sheet.get_effective_stamina_cost(100.0), 15.0, 1e-4, "100 base stamina cost becomes 15.0 at -85% cap")


# ===========================================================================
# SUITE 7: PenetrationResolver
# ===========================================================================

func _test_penetration_resolver() -> void:
	# Rank 6 Armored Hovering Guardian defense parameters (GDD Section 14.4)
	# CON=100, M_CTRL=100 (mana_skin_density ~= 313.99), armor thickness=20, hardness=15 (armor_barrier=300)
	var guardian_sheet: StatSheet = StatSheet.new()
	guardian_sheet.awaken_mana(100.0, 100.0)
	guardian_sheet.set_external_circulation_enabled(false) # Exact target final stats = 100 per GDD 14.4
	guardian_sheet.set_all_base_stats(100.0, true)

	var guardian_def: PenetrationResolver.DefenseParams = PenetrationResolver.DefenseParams.new()
	guardian_def.target_con = guardian_sheet.get_stat(StatSheet.Stat.CON)
	guardian_def.mana_skin_density = guardian_sheet.get_mana_skin_density()
	guardian_def.size_mult = 1.0
	guardian_def.base_anatomy_thickness = 2.0
	guardian_def.armor_thickness = 20.0
	guardian_def.armor_hardness = 15.0
	guardian_def.target_height_z = 1.5

	# Short Dagger attack parameters (GDD 14.4): base_pen=12, blade_len=12, sharpness=1.0, mass=4.0, reach=0.6
	var dagger_body: PenetrationResolver.AttackParams = PenetrationResolver.AttackParams.new()
	dagger_body.attacker_str = 10.0
	dagger_body.attacker_m_ctrl = 0.0
	dagger_body.weapon_base_penetration = 12.0
	dagger_body.weapon_blade_length = 12.0
	dagger_body.edge_sharpness = 1.0
	dagger_body.weapon_mass_factor = 4.0
	dagger_body.kinetic_mult = 1.0
	dagger_body.aura_active = false
	dagger_body.is_weak_point = false
	dagger_body.attacker_height_z = 0.0
	dagger_body.weapon_vertical_reach = 0.6

	# Case 1: Dagger vs Guardian body without Aura -> MUST NOT penetrate (barrier_depth ~= 1247)
	var res_body_no_aura: PenetrationResolver.ResolutionResult = PenetrationResolver.resolve(dagger_body, guardian_def, false, true)
	_assert_approx(res_body_no_aura.armor_barrier, 300.0, 1e-4, "Guardian body armor_barrier == 300")
	_assert_approx(res_body_no_aura.barrier_depth, 1246.943, 0.5, "Guardian body barrier_depth ~= 1247")
	_assert_approx(res_body_no_aura.penetration, 12.0, 1e-4, "Dagger (STR=10, no Aura) penetration == 12")
	_assert_false(res_body_no_aura.penetrated, "Dagger without Aura does NOT penetrate Rank 6 Guardian body")
	_assert_approx(res_body_no_aura.effective_depth, 0.0, 1e-5, "Non-penetrating hit has effective_depth == 0")
	_assert_false(res_body_no_aura.in_vertical_reach, "Grounded dagger (z=0, reach=0.6) cannot reach hovering guardian (z=1.5)")
	_assert_true(EventBus.last_penetration_log.has("barrier_depth"), "emit_log publishes resolution dict to EventBus")

	# Case 2: Dagger vs Guardian weak point WITHOUT Aura -> barrier_depth ~= 238, still too tough for bare STR=10 dagger
	var dagger_wp_no_aura: PenetrationResolver.AttackParams = PenetrationResolver.AttackParams.new()
	dagger_wp_no_aura.attacker_str = 10.0
	dagger_wp_no_aura.attacker_m_ctrl = 0.0
	dagger_wp_no_aura.weapon_base_penetration = 12.0
	dagger_wp_no_aura.weapon_blade_length = 12.0
	dagger_wp_no_aura.edge_sharpness = 1.0
	dagger_wp_no_aura.aura_active = false
	dagger_wp_no_aura.is_weak_point = true
	var res_wp_no_aura: PenetrationResolver.ResolutionResult = PenetrationResolver.resolve(dagger_wp_no_aura, guardian_def)
	_assert_approx(res_wp_no_aura.armor_barrier, 0.0, 1e-5, "Weak point bypasses 100% of armor_barrier")
	_assert_approx(res_wp_no_aura.tissue_bypass_mult, 0.25, 1e-5, "Weak point sets tissue_bypass_mult == 0.25")
	_assert_approx(res_wp_no_aura.barrier_depth, 238.236, 0.5, "Guardian weak-point barrier_depth ~= 238")
	_assert_false(res_wp_no_aura.penetrated, "STR=10 dagger without Aura still fails weak-point barrier (12 < 238)")

	# Case 3: Dagger vs Guardian weak point WITH Aura (M_CTRL = 10):
	# Rebalanced sustained Aura (+130 pierce, +6 ext) requires Aura Burst (1.8x -> +234) or M_CTRL>=20 to breach 238.2!
	var dagger_wp_aura: PenetrationResolver.AttackParams = PenetrationResolver.AttackParams.new()
	dagger_wp_aura.attacker_str = 10.0
	dagger_wp_aura.attacker_m_ctrl = 10.0
	dagger_wp_aura.weapon_base_penetration = 12.0
	dagger_wp_aura.weapon_blade_length = 12.0
	dagger_wp_aura.edge_sharpness = 1.0
	dagger_wp_aura.aura_active = true
	dagger_wp_aura.is_weak_point = true
	dagger_wp_aura.attacker_height_z = 1.5
	dagger_wp_aura.weapon_vertical_reach = 0.6
	var res_wp_aura: PenetrationResolver.ResolutionResult = PenetrationResolver.resolve(dagger_wp_aura, guardian_def, true)
	_assert_true(res_wp_aura.in_vertical_reach, "Flying attacker (z=1.5) reaches hovering guardian (z=1.5)")
	_assert_approx(res_wp_aura.aura_pierce_bonus, 130.0, 1e-4, "Balanced Aura at M_CTRL=10 gives +130 pierce")
	_assert_approx(res_wp_aura.aura_blade_extension, 6.0, 1e-4, "Balanced Aura at M_CTRL=10 gives +6 blade extension")
	_assert_approx(res_wp_aura.penetration, 142.0, 1e-4, "Dagger + sustained Aura(10) penetration == 142")
	dagger_wp_aura.aura_burst = true
	var res_wp_burst: PenetrationResolver.ResolutionResult = PenetrationResolver.resolve(dagger_wp_aura, guardian_def, true)
	_assert_true(res_wp_burst.penetrated, "Weak-point strike under Aura Burst (M_CTRL=10) penetrates Rank 6 Guardian")
	_assert_approx(res_wp_burst.effective_depth, res_wp_burst.penetration - res_wp_burst.barrier_depth, 1e-3, "Effective depth matches penetration - barrier_depth")

	# Case 4: Dagger vs Guardian BODY with Aura Burst at M_CTRL = 50 -> PENETRATES full armor!
	var dagger_body_aura50: PenetrationResolver.AttackParams = PenetrationResolver.AttackParams.new()
	dagger_body_aura50.attacker_str = 10.0
	dagger_body_aura50.attacker_m_ctrl = 50.0
	dagger_body_aura50.weapon_base_penetration = 12.0
	dagger_body_aura50.weapon_blade_length = 12.0
	dagger_body_aura50.edge_sharpness = 1.0
	dagger_body_aura50.aura_active = true
	dagger_body_aura50.aura_burst = true
	dagger_body_aura50.is_weak_point = false
	var res_body_aura50: PenetrationResolver.ResolutionResult = PenetrationResolver.resolve(dagger_body_aura50, guardian_def)
	_assert_true(res_body_aura50.penetrated, "Aura Burst at M_CTRL=50 penetrates Rank 6 Guardian armored body")
	var expected_max_reach: float = 12.0 + 6.0 * pow(5.0, 0.5)
	_assert_approx(res_body_aura50.effective_depth, expected_max_reach, 1e-3, "Excess penetration clamps to blade_length + aura_blade_extension")

	# Case 5: Aura requires M_CTRL >= 1.0 (GDD 12.2)
	var aura_zero: PenetrationResolver.AuraBonuses = PenetrationResolver.calculate_aura_bonuses(true, 0.5)
	_assert_false(aura_zero.active, "Aura inactive when M_CTRL < 1.0")
	_assert_approx(aura_zero.pierce_bonus, 0.0, 1e-5, "Aura pierce == 0 when M_CTRL < 1.0")

	# Case 6: Scale edge STR = 500 without Aura (blade length clamp + huge blunt impulse)
	var demigod_atk: PenetrationResolver.AttackParams = PenetrationResolver.AttackParams.new()
	demigod_atk.attacker_str = 500.0
	demigod_atk.weapon_base_penetration = 28.0
	demigod_atk.weapon_blade_length = 42.0
	demigod_atk.edge_sharpness = 1.1
	demigod_atk.weapon_mass_factor = 18.0
	demigod_atk.kinetic_mult = 1.0
	demigod_atk.aura_active = false
	var res_demigod: PenetrationResolver.ResolutionResult = PenetrationResolver.resolve(demigod_atk, guardian_def)
	_assert_true(res_demigod.penetrated, "STR=500 greatsword penetrates Rank 6 Guardian without Aura")
	_assert_approx(res_demigod.effective_depth, 42.0, 1e-4, "Without Aura, depth strictly capped by blade_length == 42")
	_assert_approx(res_demigod.blunt_impulse, 18.0 * 2500.0, 1e-2, "STR=500 greatsword blunt_impulse == 45000")


# ===========================================================================
# SUITE 8: AnatomyComponent & WoundResource
# ===========================================================================

func _test_anatomy_component() -> void:
	# 1. Core zones & blood_volume scaling (5000 * size_mult)
	var stats: StatSheet = StatSheet.new()
	var anatomy: AnatomyComponent = AnatomyComponent.new(stats, 1.0, 100.0)

	for z: StringName in AnatomyComponent.CORE_ZONES:
		_assert_true(anatomy.has_zone(z), "Anatomy has core zone %s" % String(z))
	_assert_eq(anatomy.get_zone_names().size(), 8, "Exactly 8 core zones initialized")
	_assert_approx(anatomy.max_blood_volume, 5000.0, 1e-4, "size_mult=1.0 -> max_blood_volume == 5000 ml")
	_assert_approx(anatomy.get_organ_integrity(AnatomyComponent.ZONE_HEAD), 100.0, 1e-4, "Head organ integrity starts at 100%")
	_assert_approx(anatomy.get_organ_integrity(AnatomyComponent.ZONE_NECK), 100.0, 1e-4, "Neck organ integrity starts at 100%")
	_assert_approx(anatomy.get_organ_integrity(AnatomyComponent.ZONE_CHEST), 100.0, 1e-4, "Chest organ integrity starts at 100%")

	var giant_anatomy: AnatomyComponent = AnatomyComponent.new(null, 2.2, 100.0)
	_assert_approx(giant_anatomy.max_blood_volume, 11000.0, 1e-3, "Giant size_mult=2.2 -> max_blood_volume == 11000 ml")

	# 2. Blood loss progression: Severe (>25%) -> Knockout (>45%) -> Death (>=65%)
	var ko_events: Array[Dictionary] = []
	var death_events: Array[Dictionary] = []
	var on_ko: Callable = func(ent: Node, reason: String, dur: float) -> void:
		ko_events.append({"entity": ent, "reason": reason, "dur": dur})
	var on_death: Callable = func(ent: Node, cause: String, zone: StringName) -> void:
		death_events.append({"entity": ent, "cause": cause, "zone": zone})
	EventBus.entity_knocked_out.connect(on_ko)
	EventBus.entity_died.connect(on_death)

	# Inflict neck cut (depth=10.0, vascular_mult=2.0, CON=10 -> bleed_rate = 10 * 0.45 * 2.0 * 1.0 = 9.0 ml/s)
	var neck_hit: Dictionary = anatomy.apply_penetrating_hit(AnatomyComponent.ZONE_NECK, 10.0, false)
	_assert_approx(float(neck_hit["bleed_added"]), 9.0, 1e-4, "Neck cut (depth 10) bleeds at 9.0 ml/s")
	_assert_approx(float(neck_hit["organ_damage_pct"]), 0.0, 1e-4, "Depth 10 < normal organ threshold 12 -> 0% organ damage")

	# Bleed 1300 ml (> 25% of 5000 = 1250 ml): 1300 / 9.0 ~= 144.45 sec
	anatomy.tick(145.0) # 1305 ml lost -> 26.1% loss
	_assert_true(anatomy.is_severe_blood_loss(), "Blood loss 26.1% triggers severe blood loss (>25%)")
	_assert_approx(stats.get_stat(StatSheet.Stat.SPD), 8.0, 1e-4, "Severe blood loss debuffs SPD via StatSheet")
	_assert_approx(stats.get_stat(StatSheet.Stat.TP), 8.0, 1e-4, "Severe blood loss debuffs TP via StatSheet")
	_assert_approx(stats.get_stat(StatSheet.Stat.CTRL), 8.0, 1e-4, "Severe blood loss debuffs CTRL via StatSheet")
	_assert_false(anatomy.is_unconscious, "26.1% blood loss does NOT cause knockout yet")
	_assert_false(anatomy.is_dead, "26.1% blood loss does NOT cause death yet")

	# Bleed further past 45% (> 2250 ml lost): add 108s -> +972 ml = 2277 ml lost (45.54%)
	anatomy.tick(108.0)
	_assert_true(anatomy.is_unconscious, "Blood loss >45% triggers Hemorrhagic Shock / Knockout")
	_assert_eq(anatomy.knockout_reason, "hemorrhagic_shock", "Knockout reason is hemorrhagic_shock")
	_assert_eq(ko_events.size(), 1, "EventBus.entity_knocked_out emitted")
	_assert_false(anatomy.is_dead, "45.54% blood loss is KO, not death")

	# Bleed further to >= 65% (>= 3250 ml lost): add 110s -> +990 ml = 3267 ml lost (65.34%)
	anatomy.tick(110.0)
	_assert_true(anatomy.is_dead, "Blood loss >=65% causes Death")
	_assert_eq(anatomy.death_cause, "exsanguination", "Death cause is exsanguination")
	_assert_eq(death_events.size(), 1, "EventBus.entity_died emitted")

	# 3. Vital organ destruction -> instant death even at 100% blood
	var organ_stats: StatSheet = StatSheet.new()
	var organ_anat: AnatomyComponent = AnatomyComponent.new(organ_stats, 1.0, 100.0)
	death_events.clear()
	# Weak point on Chest lowers organ threshold to 6.0; depth = 21.0 -> (21-6)/15 * 100% = 100% organ damage!
	var fatal_hit: Dictionary = organ_anat.apply_penetrating_hit(AnatomyComponent.ZONE_CHEST, 21.0, true)
	_assert_approx(float(fatal_hit["organ_damage_pct"]), 100.0, 1e-4, "Weak-point depth 21 deals 100% heart integrity damage")
	_assert_approx(organ_anat.get_organ_integrity(AnatomyComponent.ZONE_CHEST), 0.0, 1e-4, "Chest organ integrity dropped to 0%")
	_assert_true(organ_anat.is_dead, "0% vital organ integrity causes instant death")
	_assert_eq(organ_anat.death_cause, "vital_organ_destroyed", "Death cause is vital_organ_destroyed")
	_assert_eq(organ_anat.fatal_zone, AnatomyComponent.ZONE_CHEST, "Fatal zone recorded as Chest")
	_assert_approx(organ_anat.get_blood_ratio(), 1.0, 1e-4, "Instant organ death occurs even at 100% blood")
	_assert_eq(death_events.size(), 1, "EventBus.entity_died emitted for vital organ destruction")

	# 4. Traumatic shock KO (100%) and recovery
	var shock_stats: StatSheet = StatSheet.new()
	var shock_anat: AnatomyComponent = AnatomyComponent.new(shock_stats, 1.0, 100.0)
	ko_events.clear()
	# Two heavy leg fractures (blunt_impulse=200 -> shock = clamp(2*35, 5, 80) = 70 each -> capped at 100%)
	shock_anat.apply_blunt_hit(AnatomyComponent.ZONE_LEFT_ARM, 200.0, 1.0)
	_assert_approx(shock_anat.shock_level, 70.0, 1e-4, "First blunt fracture adds 70% shock")
	_assert_false(shock_anat.is_unconscious, "70% shock does not KO")
	shock_anat.apply_blunt_hit(AnatomyComponent.ZONE_RIGHT_ARM, 200.0, 1.0)
	_assert_approx(shock_anat.shock_level, 100.0, 1e-4, "Second blunt fracture caps shock at 100%")
	_assert_true(shock_anat.is_unconscious, "100% shock triggers Knockout")
	_assert_eq(shock_anat.knockout_reason, "traumatic_shock", "Knockout reason is traumatic_shock")
	_assert_true(shock_anat.knockout_timer >= 10.0 and shock_anat.knockout_timer <= 60.0, "Shock KO duration within 10..60s")
	# Advance world_delta past KO duration -> recovers consciousness
	shock_anat.tick(65.0)
	_assert_false(shock_anat.is_unconscious, "Entity recovers consciousness after shock KO timer expires")

	# 5. Fall impulse & fracture (GDD Section 3.4 #5)
	var fall_stats: StatSheet = StatSheet.new() # AGI=10, CON=10
	var fall_anat: AnatomyComponent = AnatomyComponent.new(fall_stats, 1.0, 100.0)
	var fall_res: Dictionary = fall_anat.apply_fall_damage(1, 1.0)
	_assert_approx(float(fall_res["fall_impulse"]), 120.0, 1e-4, "Base human 1-floor fall impulse == 120.0")
	_assert_true(bool(fall_res["fractured"]), "120.0 > 100.0 bone_density causes leg fracture")
	_assert_true(fall_anat.has_fracture(AnatomyComponent.ZONE_LEFT_LEG), "LeftLeg fractured from fall")
	_assert_true(fall_anat.has_fracture(AnatomyComponent.ZONE_RIGHT_LEG), "RightLeg fractured from fall")
	_assert_approx(float(fall_res["shock_added"]), 42.0, 1e-4, "Fall fracture adds 42.0 shock ((120/100)*35)")
	_assert_true(fall_stats.get_stat(StatSheet.Stat.SPD) < 10.0, "Leg fracture reduces SPD through StatSheet modifier")

	# High AGI (AGI=40) mitigates fall impulse below bone_density -> no fracture
	var agile_stats: StatSheet = StatSheet.new()
	agile_stats.awaken_mana(10.0, 10.0)
	agile_stats.set_base_stat(StatSheet.Stat.AGI, 40.0)
	var agile_anat: AnatomyComponent = AnatomyComponent.new(agile_stats, 1.0, 100.0)
	var agile_fall: Dictionary = agile_anat.apply_fall_damage(1, 1.0)
	_assert_approx(float(agile_fall["fall_impulse"]), 91.2, 1e-3, "AGI=40 reduces 1-floor fall impulse to 91.2")
	_assert_false(bool(agile_fall["fractured"]), "AGI=40 avoids leg fracture on 1-floor fall (91.2 <= 100)")

	# High CON (CON=15 -> bone_density_mult=1.5 -> effective 150) withstands 120 impulse
	var tough_stats: StatSheet = StatSheet.new()
	tough_stats.set_base_stat(StatSheet.Stat.CON, 15.0)
	var tough_anat: AnatomyComponent = AnatomyComponent.new(tough_stats, 1.0, 100.0)
	var tough_fall: Dictionary = tough_anat.apply_fall_damage(1, 1.0)
	_assert_false(bool(tough_fall["fractured"]), "CON=15 (bone_density=150) avoids fracture from 120 fall impulse")

	# 6. WoundResource template immutability (GDD 12.5) + heal_pipeline cancellation
	var template: WoundResource = WoundResource.new()
	template.wound_id = &"test_cut"
	template.bleed_rate_ml_per_sec = 5.0
	template.is_bandaged = false
	var runtime_copy: WoundResource = template.create_runtime_copy()
	runtime_copy.is_bandaged = true
	_assert_false(template.is_bandaged, "Mutating runtime WoundResource copy does NOT mutate read-only template")
	_assert_approx(runtime_copy.get_effective_bleed_rate(), 0.0, 1e-5, "Bandaging stops cut bleeding")

	# Heal pipeline interception inside AnatomyComponent
	var heal_test_anat: AnatomyComponent = AnatomyComponent.new(null, 1.0, 100.0)
	heal_test_anat.blood_volume = 3000.0
	var forbid_heal: Callable = func(ctx: Dictionary) -> void:
		ctx["cancelled"] = true
	EventBus.heal_pipeline.connect(forbid_heal)
	var blocked_restored: float = heal_test_anat.heal_blood(500.0, &"potion")
	EventBus.heal_pipeline.disconnect(forbid_heal)
	_assert_approx(blocked_restored, 0.0, 1e-5, "EventBus heal_pipeline can block AnatomyComponent.heal_blood")
	var allowed_restored: float = heal_test_anat.heal_blood(500.0, &"potion")
	_assert_approx(allowed_restored, 500.0, 1e-5, "Unblocked heal_blood restores 500 ml")

	EventBus.entity_knocked_out.disconnect(on_ko)
	EventBus.entity_died.disconnect(on_death)
	anatomy.free()
	giant_anatomy.free()
	organ_anat.free()
	shock_anat.free()
	fall_anat.free()
	agile_anat.free()
	tough_anat.free()
	heal_test_anat.free()


# ===========================================================================
# SUITE 9: Step 2 - ProceduralTileSetBuilder, VerticalityComponent & TestArena
# ===========================================================================

func _test_stage0_step2_arena_and_verticality() -> void:
	FloorLayerManager.reset(0)

	# 1. ProceduralTileSetBuilder image, colors, polygons & custom_data
	var atlas_img: Image = ProceduralTileSetBuilder.build_atlas_image()
	_assert_eq(atlas_img.get_width(), ProceduralTileSetBuilder.ATLAS_COLUMNS * 32, "Procedural atlas width == 12 * 32 px")
	_assert_eq(atlas_img.get_height(), 32, "Procedural atlas height == 32 px")

	# Check exact GDD 14.3 tile fill colors (sampling tile centers at y=16)
	var c_floor0: Color = atlas_img.get_pixel(ProceduralTileSetBuilder.TILE_FLOOR_0.x * 32 + 16, 16)
	_assert_approx(c_floor0.r, Color("#2B2D31").r, 0.02, "Floor 0 color matches #2B2D31 (R)")
	_assert_approx(c_floor0.g, Color("#2B2D31").g, 0.02, "Floor 0 color matches #2B2D31 (G)")
	_assert_approx(c_floor0.b, Color("#2B2D31").b, 0.02, "Floor 0 color matches #2B2D31 (B)")

	var c_floor1: Color = atlas_img.get_pixel(ProceduralTileSetBuilder.TILE_FLOOR_1.x * 32 + 16, 16)
	_assert_approx(c_floor1.r, Color("#5C4033").r, 0.02, "Floor +1 color matches #5C4033")

	var c_hole_center: Color = atlas_img.get_pixel(ProceduralTileSetBuilder.TILE_FLOOR_HOLE.x * 32 + 16, 16)
	var c_hole_rim: Color = atlas_img.get_pixel(ProceduralTileSetBuilder.TILE_FLOOR_HOLE.x * 32 + 0, 0)
	_assert_approx(c_hole_center.a, 0.0, 0.01, "Broken floor hole center is fully transparent (alpha=0)")
	_assert_approx(c_hole_rim.a, 1.0, 0.01, "Broken floor hole rim is opaque")

	var c_roof: Color = atlas_img.get_pixel(ProceduralTileSetBuilder.TILE_ROOF.x * 32 + 16, 16)
	_assert_approx(c_roof.a, 0.85, 0.02, "Roof tile alpha matches 0.85")

	var shared_tex: ImageTexture = ImageTexture.create_from_image(atlas_img)
	var ts0: TileSet = ProceduralTileSetBuilder.build_tileset_for_floor(0, shared_tex)
	var ts1: TileSet = ProceduralTileSetBuilder.build_tileset_for_floor(1, shared_tex)

	_assert_eq(ts0.get_physics_layer_collision_layer(0), FloorLayerManager.get_high_walls_bit(0), "Floor0 TileSet physics_layer 0 == Slot0_HighWalls")
	_assert_eq(ts0.get_physics_layer_collision_layer(1), FloorLayerManager.get_low_obstacles_bit(0), "Floor0 TileSet physics_layer 1 == Slot0_LowObstacles")
	_assert_eq(ts1.get_physics_layer_collision_layer(0), FloorLayerManager.get_high_walls_bit(1), "Floor1 TileSet physics_layer 0 == Slot1_HighWalls")
	_assert_eq(ts1.get_physics_layer_collision_layer(1), FloorLayerManager.get_low_obstacles_bit(1), "Floor1 TileSet physics_layer 1 == Slot1_LowObstacles")

	var atlas0: TileSetAtlasSource = ts0.get_source(0) as TileSetAtlasSource
	_assert_true(atlas0 != null, "TileSet has TileSetAtlasSource")
	var td_wood: TileData = atlas0.get_tile_data(ProceduralTileSetBuilder.TILE_WALL_WOOD, 0)
	var td_brick: TileData = atlas0.get_tile_data(ProceduralTileSetBuilder.TILE_WALL_BRICK, 0)
	var td_stone: TileData = atlas0.get_tile_data(ProceduralTileSetBuilder.TILE_WALL_STONE, 0)
	var td_fence: TileData = atlas0.get_tile_data(ProceduralTileSetBuilder.TILE_LOW_OBSTACLE, 0)
	var td_bfloor: TileData = atlas0.get_tile_data(ProceduralTileSetBuilder.TILE_FLOOR_1_BREAKABLE, 0)

	_assert_approx(float(td_wood.get_custom_data("wall_threshold")), 15.0, 1e-4, "Wood wall threshold == 15")
	_assert_approx(float(td_brick.get_custom_data("wall_threshold")), 40.0, 1e-4, "Brick wall threshold == 40")
	_assert_approx(float(td_stone.get_custom_data("wall_threshold")), 90.0, 1e-4, "Stone wall threshold == 90")
	_assert_true(bool(td_wood.get_custom_data("destructible")), "Wood wall is destructible")
	_assert_true(bool(td_bfloor.get_custom_data("breakable_floor")), "Breakable floor flag set")
	_assert_eq(td_wood.get_collision_polygons_count(0), 1, "Wood wall has HighWalls polygon")
	_assert_eq(td_wood.get_collision_polygons_count(1), 0, "Wood wall has no LowObstacles polygon")
	_assert_eq(td_fence.get_collision_polygons_count(0), 0, "LowObstacle fence has no HighWalls polygon")
	_assert_eq(td_fence.get_collision_polygons_count(1), 1, "LowObstacle fence has LowObstacles polygon")

	# 2. VerticalityComponent visuals, shadow, z_index & dynamic collision_mask
	var mock_body: CharacterBody2D = CharacterBody2D.new()
	var mock_sprite: Node2D = Node2D.new()
	var mock_shadow: Node2D = Node2D.new()
	var vert: VerticalityComponent = VerticalityComponent.new()
	mock_body.add_child(mock_shadow)
	mock_body.add_child(mock_sprite)
	mock_body.add_child(vert)
	add_child(mock_body)
	vert.setup(mock_sprite, mock_shadow, mock_body, 0, 0.0)

	# Ground on Floor 0
	_assert_approx(mock_sprite.position.y, 0.0, 1e-4, "Ground sprite y == 0")
	_assert_approx(mock_sprite.scale.x, 1.0, 1e-4, "Ground sprite scale == 1.0")
	_assert_eq(mock_sprite.z_index, 0, "Ground Floor 0 sprite z_index == 0")
	_assert_eq(mock_shadow.z_index, 0, "Ground Floor 0 shadow z_index == 0")
	_assert_eq(mock_body.collision_layer, FloorLayerManager.get_actors_bit(0), "Floor 0 actor collision_layer == Slot0_Actors")
	_assert_eq(
		mock_body.collision_mask,
		FloorLayerManager.get_high_walls_bit(0) | FloorLayerManager.get_low_obstacles_bit(0) | FloorLayerManager.get_actors_bit(0),
		"Ground Floor 0 actor collides with HighWalls + LowObstacles + Actors"
	)

	# Flying on Floor 0 (height_z = 1.5 -> sprite offset -67.5, scale 1.225, z_index = 15, LowObstacles disabled!)
	vert.set_height_z(1.5)
	_assert_approx(mock_sprite.position.y, -1.5 * 45.0, 1e-4, "Flight z=1.5 shifts sprite.position.y by -67.5")
	_assert_approx(mock_sprite.scale.x, 1.0 + 1.5 * 0.15, 1e-4, "Flight z=1.5 scales sprite to 1.225")
	_assert_approx(mock_shadow.position.y, 0.0, 1e-4, "Shadow stays grounded at y == 0 during flight")
	_assert_eq(mock_sprite.z_index, 15, "Flight z=1.5 on Floor 0 -> body z_index == 15")
	_assert_eq(mock_shadow.z_index, 0, "Flight z=1.5 on Floor 0 -> shadow z_index stays 0")
	_assert_eq(
		mock_body.collision_mask,
		FloorLayerManager.get_high_walls_bit(0) | FloorLayerManager.get_actors_bit(0),
		"Flight z=1.5 disables LowObstacles bit while preserving HighWalls"
	)

	# Switch to Floor +1 while flying (z = 1.5 -> z_index = 115, shadow = 100, Slot1 layers)
	vert.set_floor_level(1)
	_assert_eq(mock_sprite.z_index, 115, "Flight z=1.5 on Floor +1 -> body z_index == 115")
	_assert_eq(mock_shadow.z_index, 100, "Floor +1 shadow z_index == 100")
	_assert_eq(mock_body.collision_layer, FloorLayerManager.get_actors_bit(1), "Floor +1 actor layer switches to Slot1_Actors")
	_assert_eq(
		mock_body.collision_mask,
		FloorLayerManager.get_high_walls_bit(1) | FloorLayerManager.get_actors_bit(1),
		"Floor +1 flying mask uses Slot1 HighWalls + Actors (no LowObstacles)"
	)
	mock_body.queue_free()

	# 3. TestArena scene instantiation, strict TileMapLayer, destruction, stairs, visibility & floor fall
	var arena_scene: PackedScene = load("res://scenes/test_arena.tscn") as PackedScene
	_assert_true(arena_scene != null, "res://scenes/test_arena.tscn loads cleanly")
	var arena: TestArena = arena_scene.instantiate() as TestArena
	_assert_true(arena != null, "TestArena instantiates as TestArena")
	add_child(arena)

	_assert_true(arena.floor0_floor_layer is TileMapLayer, "Floor0/FloorLayer is TileMapLayer")
	_assert_true(arena.floor0_wall_layer is TileMapLayer, "Floor0/WallLayer is TileMapLayer")
	_assert_true(arena.floor1_floor_layer is TileMapLayer, "Floor1/FloorLayer is TileMapLayer")
	_assert_true(arena.floor1_wall_layer is TileMapLayer, "Floor1/WallLayer is TileMapLayer")
	_assert_true(arena.floor1_roof_layer is TileMapLayer, "Floor1/RoofLayer is TileMapLayer")
	_assert_eq(arena.stairs_area.collision_layer, FloorLayerManager.BIT_INTERACTABLES, "StairsArea uses Interactables layer")
	_assert_eq(arena.floor1_support_zone.collision_layer, FloorLayerManager.BIT_FLOOR_SUPPORT, "FloorSupportZone uses FloorSupport layer")

	# Wall destruction thresholds & AStarGrid2D isolation (GDD 14.2)
	var wood_cell: Vector2i = TestArena.WOOD_WALL_CELLS[0]
	var brick_cell: Vector2i = TestArena.BRICK_WALL_CELLS[0]
	var stone_cell: Vector2i = TestArena.STONE_WALL_CELLS[0]
	var outer_cell: Vector2i = Vector2i(0, 0)

	_assert_false(arena.is_cell_walkable(0, wood_cell), "Wood wall initially blocks Floor 0 nav grid")
	var weak_wood: Dictionary = arena.try_damage_wall_at(0, wood_cell, 10.0, -1.0, false)
	_assert_false(bool(weak_wood["destroyed"]), "STR=10 cannot destroy wood wall (needs >=15)")
	_assert_true(bool(weak_wood["weapon_wear"]), "Failed hit without Aura causes weapon wear")

	var ok_wood: Dictionary = arena.try_damage_wall_at(0, wood_cell, 15.0)
	_assert_true(bool(ok_wood["destroyed"]), "STR=15 destroys wood wall")
	_assert_true(arena.is_cell_walkable(0, wood_cell), "Destroying wood wall updates Floor 0 nav passability")
	_assert_false(arena.is_wall_solid_at(0, wood_cell), "Wood wall no longer solid after destruction")

	var weak_brick: Dictionary = arena.try_damage_wall_at(0, brick_cell, 39.0)
	_assert_false(bool(weak_brick["destroyed"]), "STR=39 cannot destroy brick wall (needs >=40)")
	var ok_brick: Dictionary = arena.try_damage_wall_at(0, brick_cell, 40.0)
	_assert_true(bool(ok_brick["destroyed"]), "STR=40 destroys brick wall")

	var weak_stone: Dictionary = arena.try_damage_wall_at(0, stone_cell, 89.0)
	_assert_false(bool(weak_stone["destroyed"]), "STR=89 cannot destroy stone wall (needs >=90)")
	var ok_stone: Dictionary = arena.try_damage_wall_at(0, stone_cell, 90.0)
	_assert_true(bool(ok_stone["destroyed"]), "STR=90 destroys stone wall")

	var hit_outer: Dictionary = arena.try_damage_wall_at(0, outer_cell, 500.0)
	_assert_false(bool(hit_outer["destroyed"]), "Outer perimeter wall stays indestructible even at STR=500")

	# Destroying Floor 0 building wall does NOT affect Floor +1 building wall at same coordinates
	var bldg_wall_cell: Vector2i = Vector2i(14, 3)
	_assert_true(arena.is_wall_solid_at(0, bldg_wall_cell), "Floor 0 building wall solid")
	_assert_true(arena.is_wall_solid_at(1, bldg_wall_cell), "Floor 1 building wall solid")
	arena.try_damage_wall_at(0, bldg_wall_cell, 90.0)
	_assert_false(arena.is_wall_solid_at(0, bldg_wall_cell), "Floor 0 building wall destroyed at STR=90")
	_assert_true(arena.is_wall_solid_at(1, bldg_wall_cell), "Floor +1 wall unaffected by Floor 0 destruction")

	# Roof & floor visibility transitions (GDD 12.6)
	arena.update_floor_visibility(0, true, true)
	_assert_approx(arena.floor1_roof_layer.modulate.a, 0.0, 1e-4, "Entering building on Floor 0 dissolves RoofLayer to alpha 0.0")
	_assert_approx(arena.floor1_floor_layer.modulate.a, 0.0, 1e-4, "Entering building on Floor 0 dissolves Floor +1 to alpha 0.0")
	arena.update_floor_visibility(1, true, true)
	_assert_approx(arena.floor1_floor_layer.modulate.a, 1.0, 1e-4, "On Floor +1, Floor +1 is visible")
	_assert_approx(arena.floor1_roof_layer.modulate.a, 0.0, 1e-4, "On Floor +1, RoofLayer is hidden")
	_assert_true(arena.floor0_container.modulate.r < 0.6, "On Floor +1, Floor 0 is dimmed")

	# Stairs transition (0 <-> 1) + 0.4s cooldown guard
	var stair_actor: CharacterBody2D = CharacterBody2D.new()
	var stair_vert: VerticalityComponent = VerticalityComponent.new()
	stair_actor.add_child(stair_vert)
	arena.entities_container.add_child(stair_actor)
	stair_actor.global_position = arena.cell_to_world_center(TestArena.STAIRS_RECT.position)
	arena.register_entity(stair_actor, false)

	_assert_eq(stair_vert.floor_level, 0, "Stair actor starts on Floor 0")
	_assert_true(arena.try_use_stairs(stair_actor), "Stairs move actor from Floor 0 to Floor +1")
	_assert_eq(stair_vert.floor_level, 1, "Stair actor now on Floor +1")
	_assert_false(arena.try_use_stairs(stair_actor), "Stairs 0.4s cooldown prevents immediate loop back")

	# Breakable floor on +1 drops grounded entity with fall_impulse & leg fracture, while flying entity hovers!
	var hole_cell: Vector2i = TestArena.BREAKABLE_FLOOR_RECT.position
	var grounded_actor: CharacterBody2D = CharacterBody2D.new()
	var g_stats: StatSheet = StatSheet.new()
	var g_vert: VerticalityComponent = VerticalityComponent.new()
	var g_anat: AnatomyComponent = AnatomyComponent.new(g_stats, 1.0, 100.0)
	grounded_actor.add_child(g_vert)
	grounded_actor.add_child(g_anat)
	arena.entities_container.add_child(grounded_actor)
	g_vert.set_floor_level(1)
	g_vert.set_height_z(0.0)
	grounded_actor.global_position = arena.cell_to_world_center(hole_cell)
	arena.register_entity(grounded_actor, false)

	var flying_actor: CharacterBody2D = CharacterBody2D.new()
	var f_vert: VerticalityComponent = VerticalityComponent.new()
	flying_actor.add_child(f_vert)
	arena.entities_container.add_child(flying_actor)
	f_vert.set_floor_level(1)
	f_vert.set_height_z(1.5)
	flying_actor.global_position = arena.cell_to_world_center(hole_cell)
	arena.register_entity(flying_actor, false)

	_assert_true(FloorLayerManager.has_floor_at(1, hole_cell), "Breakable Floor +1 tile intact initially")
	var weak_floor: Dictionary = arena.try_break_floor_at(1, hole_cell, 10.0)
	_assert_false(bool(weak_floor["broken"]), "STR=10 cannot break Floor +1 (needs >=15)")

	var ok_floor: Dictionary = arena.try_break_floor_at(1, hole_cell, 15.0)
	_assert_true(bool(ok_floor["broken"]), "STR=15 breaks Floor +1 tile")
	_assert_false(FloorLayerManager.has_floor_at(1, hole_cell), "FloorLayerManager marks Floor +1 cell broken")
	_assert_eq(g_vert.floor_level, 0, "Grounded entity falls from Floor +1 to Floor 0")
	_assert_true(g_anat.has_fracture(AnatomyComponent.ZONE_LEFT_LEG), "Grounded entity fractures leg on fall from +1 -> 0")
	_assert_eq(f_vert.floor_level, 1, "Flying entity (height_z=1.5) stays hovering safely on Floor +1")

	remove_child(arena)
	arena.queue_free()


# ===========================================================================
# SUITE 10: Step 3 - Weapons, HitboxZone, WeaponRaySweeper, Player & Enemies
# ===========================================================================

func _test_stage0_step3_combat_and_entities() -> void:
	SimulationClock.reset_defaults()
	FloorLayerManager.reset(0)

	# 1. Read-only WeaponData templates (dagger.tres & greatsword.tres) & clone immutability
	var dagger_tpl: WeaponData = load("res://data/dagger.tres") as WeaponData
	var gs_tpl: WeaponData = load("res://data/greatsword.tres") as WeaponData
	_assert_true(dagger_tpl != null, "res://data/dagger.tres loads cleanly")
	_assert_true(gs_tpl != null, "res://data/greatsword.tres loads cleanly")

	_assert_approx(dagger_tpl.base_penetration, 12.0, 1e-4, "Dagger base_penetration == 12.0")
	_assert_approx(dagger_tpl.blade_length, 14.0, 1e-4, "Dagger blade_length == 14.0 (v0.2)")
	_assert_approx(dagger_tpl.min_optimal_range, 0.0, 1e-4, "Dagger min_optimal_range == 0.0")
	_assert_approx(dagger_tpl.durability, 40.0, 1e-4, "Dagger durability == 40.0")
	_assert_approx(dagger_tpl.edge_sharpness, 1.0, 1e-4, "Dagger edge_sharpness == 1.0")
	_assert_approx(dagger_tpl.mass_factor, 4.0, 1e-4, "Dagger mass_factor == 4.0")
	_assert_approx(dagger_tpl.vertical_reach, 0.6, 1e-4, "Dagger vertical_reach == 0.6")
	_assert_false(dagger_tpl.can_half_sword, "Dagger cannot half-sword")

	_assert_approx(gs_tpl.base_penetration, 28.0, 1e-4, "Greatsword base_penetration == 28.0")
	_assert_approx(gs_tpl.blade_length, 46.0, 1e-4, "Greatsword blade_length == 46.0 (v0.2)")
	_assert_approx(gs_tpl.min_optimal_range, 20.0, 1e-4, "Greatsword min_optimal_range == 20.0")
	_assert_approx(gs_tpl.durability, 100.0, 1e-4, "Greatsword durability == 100.0")
	_assert_approx(gs_tpl.edge_sharpness, 1.1, 1e-4, "Greatsword edge_sharpness == 1.1")
	_assert_approx(gs_tpl.mass_factor, 18.0, 1e-4, "Greatsword mass_factor == 18.0")
	_assert_approx(gs_tpl.vertical_reach, 1.0, 1e-4, "Greatsword vertical_reach == 1.0 (v0.2)")
	_assert_true(gs_tpl.can_half_sword, "Greatsword supports Half-swording")

	var dagger_copy: WeaponData = dagger_tpl.create_runtime_copy()
	var aura_wear: float = dagger_copy.apply_wear(0.15, 0.0, true)
	_assert_approx(aura_wear, 0.0, 1e-5, "Active Aura prevents blade wear")
	var real_wear: float = dagger_copy.apply_wear(0.15, 0.0, false)
	_assert_approx(real_wear, 0.15, 1e-5, "Wear without Aura reduces runtime copy edge_sharpness")
	_assert_approx(dagger_copy.edge_sharpness, 0.85, 1e-5, "Runtime copy sharpness == 0.85")
	_assert_approx(dagger_tpl.edge_sharpness, 1.0, 1e-5, "Read-only dagger.tres template remains untouched (1.0)")

	# 2. WeaponRaySweeper angular substeps (<= 5 deg) & double weak-point condition
	var substeps: PackedFloat64Array = WeaponRaySweeper.compute_angular_substeps(0.0, deg_to_rad(45.0))
	_assert_eq(substeps.size(), 9, "45 deg swing split into 9 micro-steps of 5 deg each")
	var dist_on_seg: float = WeaponRaySweeper.distance_point_to_segment(Vector2(10.0, 2.0), Vector2(0.0, 0.0), Vector2(20.0, 0.0))
	_assert_approx(dist_on_seg, 2.0, 1e-4, "Point-to-segment distance exact")

	var wp_ok: bool = WeaponRaySweeper.check_weak_point_double_condition(
		Vector2(20.0, 0.0), Vector2(22.0, 1.0), Vector2(10.0, 0.0), Vector2(30.0, 0.0),
		12.0, 3.0, 0, 0, 0.0, 0.0, 0.6
	)
	_assert_true(wp_ok, "Double weak-point condition passes when cursor, blade, floor & height match")

	var wp_bad_aim: bool = WeaponRaySweeper.check_weak_point_double_condition(
		Vector2(20.0, 0.0), Vector2(60.0, 0.0), Vector2(10.0, 0.0), Vector2(30.0, 0.0),
		12.0, 3.0, 0, 0, 0.0, 0.0, 0.6
	)
	_assert_false(wp_bad_aim, "Double weak-point condition rejects cursor outside aim_tolerance")

	var wp_bad_height: bool = WeaponRaySweeper.check_weak_point_double_condition(
		Vector2(20.0, 0.0), Vector2(20.0, 0.0), Vector2(10.0, 0.0), Vector2(30.0, 0.0),
		12.0, 3.0, 0, 0, 0.0, 1.5, 0.6
	)
	_assert_false(wp_bad_height, "Double weak-point condition rejects target above vertical_reach (z=1.5 vs reach 0.6)")

	# 3. PlayerController, Rank 1 Swordsman & Rank 6 Guard scenes on TestArena
	var arena_scene: PackedScene = load("res://scenes/test_arena.tscn") as PackedScene
	var arena: TestArena = arena_scene.instantiate() as TestArena
	add_child(arena)

	var player: PlayerController = arena.entities_container.get_node_or_null("Player") as PlayerController
	var rank1: EnemyDummy = arena.entities_container.get_node_or_null("Rank1Swordsman") as EnemyDummy
	var rank6: EnemyDummy = arena.entities_container.get_node_or_null("Rank6Guard") as EnemyDummy
	_assert_true(player != null, "TestArena spawns PlayerController")
	_assert_true(rank1 != null, "TestArena spawns Rank1Swordsman")
	_assert_true(rank6 != null, "TestArena spawns Rank6Guard")
	rank1.ai_enabled = false
	rank6.ai_enabled = false

	# Player defaults & dynamic Camera2D zoom (GDD 12.7, 14.4)
	_assert_approx(player.stat_sheet.get_stat(StatSheet.Stat.STR), 10.0, 1e-4, "Player starts with STR=10")
	_assert_approx(player.stat_sheet.get_stat(StatSheet.Stat.M_CTRL), 0.0, 1e-4, "Player starts with unawakened M_CTRL=0")
	_assert_eq(player.weapon_slots.size(), 3, "Player has 3 cloned weapon slots (Dagger, Greatsword, Warhammer)")
	_assert_eq(player.equipped_weapon.weapon_id, &"dagger", "Player starts with Short Dagger")
	_assert_true(player.select_weapon_slot(1) and player.equipped_weapon.weapon_id == &"greatsword", "Player switches to Greatsword")
	_assert_true(player.select_weapon_slot(2) and player.equipped_weapon.weapon_id == &"warhammer", "Player switches to Heavy Warhammer")
	_assert_true(player.select_weapon_slot(0) and player.equipped_weapon.weapon_id == &"dagger", "Player switches back to Dagger")
	_assert_approx(player.compute_target_camera_zoom().x, 1.0, 1e-4, "Camera zoom == 1.0 at size=1.0, z=0.0")
	player.verticality.set_height_z(1.5)
	_assert_approx(player.compute_target_camera_zoom().x, 1.0 / 1.18, 1e-4, "Camera zoom scales cleanly at height_z=1.5")
	player.verticality.set_height_z(0.0)

	# Aura requires awakened mana & drains MP by world_delta
	_assert_false(player.set_aura_active(true), "Aura blocked before mana awakening")
	player.stat_sheet.awaken_mana(10.0, 10.0)
	player.refill_resources()
	_assert_true(player.set_aura_active(true), "Aura activates after mana awakening")
	var mp_before: float = player.current_mp
	player.tick_physiology(1.0, false) # MP regen +2.5, Aura drain -1.96 -> net remains capped/valid
	_assert_true(player.aura_active and mp_before > 0.0, "Aura stays active while MP > 0")
	player.set_aura_active(false)

	# Rank 1 Swordsman preset verification (GDD 14.4)
	_assert_approx(rank1.stat_sheet.get_stat(StatSheet.Stat.STR), 10.0, 1e-4, "Rank 1 Swordsman STR == 10")
	_assert_approx(rank1.get_height_z(), 0.0, 1e-4, "Rank 1 Swordsman height_z == 0.0")
	_assert_approx(rank1.attack_windup_override, 0.45, 1e-4, "Rank 1 Windup == 0.45s")
	_assert_approx(rank1.attack_active_override, 0.15, 1e-4, "Rank 1 Active == 0.15s")
	_assert_approx(rank1.attack_recovery_override, 0.40, 1e-4, "Rank 1 Recovery == 0.40s")

	# Rank 6 Guard preset verification (GDD 14.4): CON=100, M_CTRL=100, mana_skin~=314, height_z=1.5, armor=20x15
	_assert_approx(rank6.stat_sheet.get_stat(StatSheet.Stat.CON), 100.0, 1e-4, "Rank 6 Guard effective CON == 100 (88 base + 12 circ)")
	_assert_approx(rank6.stat_sheet.get_stat(StatSheet.Stat.SPD), 100.0, 1e-4, "Rank 6 Guard effective SPD == 100")
	_assert_approx(rank6.stat_sheet.get_mana_skin_density(), 313.9858, 0.1, "Rank 6 Guard mana_skin_density ~= 314")
	_assert_approx(rank6.get_height_z(), 1.5, 1e-4, "Rank 6 Guard hovering at height_z == 1.5")

	# Combat check: Dagger without Aura fails to penetrate Rank 6 Guard body, dulling blade
	var guard_chest: HitboxZone = null
	for hz: HitboxZone in rank6.hitbox_zones:
		if hz.zone_name == AnatomyComponent.ZONE_CHEST:
			guard_chest = hz
			break
	_assert_true(guard_chest != null, "Rank 6 Guard has Chest HitboxZone")
	player.verticality.set_height_z(1.5) # Match guard altitude
	var sharp_before: float = player.equipped_weapon.edge_sharpness
	var no_aura_hit: Dictionary = rank6.receive_melee_hit(player, guard_chest, player.equipped_weapon, false, 1.0, false)
	var no_aura_res: PenetrationResolver.ResolutionResult = no_aura_hit["resolution"] as PenetrationResolver.ResolutionResult
	_assert_false(no_aura_res.penetrated, "Short Dagger without Aura does NOT penetrate Rank 6 Guard body")
	_assert_true(player.equipped_weapon.edge_sharpness < sharp_before, "Bouncing off Rank 6 armor without Aura dulls dagger")

	# Combat check: Aura Burst at M_CTRL=50 penetrates Rank 6 Guard armored body
	player.stat_sheet.set_base_stat(StatSheet.Stat.M_CTRL, 50.0)
	player.refill_resources()
	player.set_aura_active(true)
	var aura_hit: Dictionary = rank6.receive_melee_hit(
		player, guard_chest, player.equipped_weapon, false, 1.0, true,
		PenetrationResolver.AttackType.STANDARD, -1.0, false, true
	)
	var aura_res: PenetrationResolver.ResolutionResult = aura_hit["resolution"] as PenetrationResolver.ResolutionResult
	_assert_true(aura_res.penetrated, "Short Dagger under Aura Burst (M_CTRL=50) penetrates Rank 6 Guard body")
	player.set_aura_active(false)

	# Parry 0.18s subjective window deflects Rank 1 Swordsman strike and staggers attacker
	player.verticality.set_height_z(0.0)
	var player_chest: HitboxZone = null
	for hz: HitboxZone in player.hitbox_zones:
		if hz.zone_name == AnatomyComponent.ZONE_CHEST:
			player_chest = hz
			break
	player.trigger_block_pressed()
	_assert_true(player.is_in_parry_window(), "Parry window active immediately after block press")
	var parry_res: Dictionary = player.receive_melee_hit(rank1, player_chest, rank1.equipped_weapon, false, 1.0, false)
	_assert_eq(String(parry_res["outcome"]), "parried", "Active 0.18s parry window parries incoming attack")
	_assert_eq(rank1.combat_state, CombatActor.CombatState.STAGGERED, "Parried attacker becomes STAGGERED")

	# Strict 3-condition Imperceptible Speed check (GDD 12.1)
	# Reset Rank 6 Guard after the lethal Aura test above, and reset player to base TP=10
	rank6.anatomy.reset_anatomy()
	rank6.verticality.sync_collisions()
	player.stat_sheet.set_mana_awakened(false)
	player.stat_sheet.set_all_base_stats(10.0, false)
	player.is_blocking = false
	player.parry_window_timer = 0.0
	player.global_position = rank6.global_position + Vector2(-40.0, 0.0)

	# 1) Grounded player (z=0.0) vs hovering guard (z=1.5, reach=0.9) -> blocked by vertical_reach!
	player.verticality.set_height_z(0.0)
	var imp_z_fail: Dictionary = rank6.try_imperceptible_speed_strike(player, 0.99)
	_assert_false(bool(imp_z_fail["triggered"]), "Imperceptible Speed fails when out of vertical_reach")
	_assert_eq(String(imp_z_fail["reason"]), "out_of_vertical_reach", "Failure reason is out_of_vertical_reach")

	# 2) Same height_z=1.5, but player AGI auto-dodge succeeds (roll=0.0) -> avoided!
	player.verticality.set_height_z(1.5)
	var imp_dodge: Dictionary = rank6.try_imperceptible_speed_strike(player, 0.0)
	_assert_false(bool(imp_dodge["triggered"]), "Imperceptible Speed avoided when AGI instinct dodge succeeds")
	_assert_eq(String(imp_dodge["reason"]), "instinctively_dodged", "Failure reason is instinctively_dodged")

	# 3) Player blocking -> prevented!
	player.is_blocking = true
	var imp_block: Dictionary = rank6.try_imperceptible_speed_strike(player, 0.99)
	_assert_false(bool(imp_block["triggered"]), "Imperceptible Speed prevented by active block")
	player.is_blocking = false

	# 4) Player raises TP=20 (ratio 100/20 = 5x < 10x) -> prevented!
	player.stat_sheet.set_base_stat(StatSheet.Stat.TP, 20.0)
	var imp_tp: Dictionary = rank6.try_imperceptible_speed_strike(player, 0.99)
	_assert_false(bool(imp_tp["triggered"]), "Imperceptible Speed fails when SPD/TP < 10")
	player.stat_sheet.set_base_stat(StatSheet.Stat.TP, 10.0)

	# 5) ALL 3 conditions met -> triggers 0.15s flash + fatal vital organ trauma!
	var imp_kill: Dictionary = rank6.try_imperceptible_speed_strike(player, 0.99)
	_assert_true(bool(imp_kill["triggered"]), "Imperceptible Speed triggers when all 3 strict GDD 12.1 conditions hold")
	_assert_true(player.anatomy.is_dead, "Imperceptible Speed inflicts fatal vital-organ injury")
	_assert_eq(player.anatomy.death_cause, "vital_organ_destroyed", "Fatal injury cause is vital_organ_destroyed")

	remove_child(arena)
	arena.queue_free()


# ===========================================================================
# SUITE 11: Step 4 - DebugHUD, Main Scene & Section 14.2 Acceptance
# ===========================================================================

func _test_stage0_step4_debug_hud_and_acceptance() -> void:
	SimulationClock.reset_defaults()
	WorldCalendar.reset_calendar(0)
	FloorLayerManager.reset(0)

	# 1. Verify run/main_scene in project.godot
	_assert_eq(String(ProjectSettings.get_setting("application/run/main_scene", "")), "res://scenes/test_arena.tscn", "run/main_scene points to res://scenes/test_arena.tscn")

	# 2. Instantiate full test_arena.tscn with DebugHUD
	var arena_scene: PackedScene = load("res://scenes/test_arena.tscn") as PackedScene
	var arena: TestArena = arena_scene.instantiate() as TestArena
	add_child(arena)

	var hud: DebugHUD = arena.get_node_or_null("DebugHUD") as DebugHUD
	var player: PlayerController = arena.entities_container.get_node_or_null("Player") as PlayerController
	_assert_true(hud != null, "TestArena contains DebugHUD CanvasLayer")
	_assert_true(player != null, "TestArena contains Player")

	# Pause dummy AI during deterministic HUD tests
	for e: Node in get_tree().get_nodes_in_group(&"enemies"):
		if e is EnemyDummy:
			(e as EnemyDummy).ai_enabled = false

	# Toggle Debug Panel (F1)
	_assert_true(hud.debug_panel.visible, "DebugPanel visible by default")
	_assert_false(hud.toggle_debug_panel(), "toggle_debug_panel hides DebugPanel")
	_assert_true(hud.toggle_debug_panel(), "toggle_debug_panel shows DebugPanel again")

	# Awaken / Sleep Mana button + racial cap check
	hud.set_player_base_stat(StatSheet.Stat.STR, 40.0)
	_assert_approx(player.stat_sheet.get_stat(StatSheet.Stat.STR), 22.0, 1e-4, "Before awakening, slider STR=40 stays capped at 22")
	_assert_true(hud.toggle_player_mana_awakening(), "Awaken Mana unlocks player mana")
	_assert_approx(player.stat_sheet.get_stat(StatSheet.Stat.STR), 40.0, 1e-4, "After awakening via DebugHUD, STR unlocks to 40")
	_assert_false(hud.toggle_player_mana_awakening(), "Sleep Mana restores unawakened state")
	_assert_approx(player.stat_sheet.get_stat(StatSheet.Stat.STR), 22.0, 1e-4, "After sleeping mana, racial cap 22 re-engages")

	# Quick Stat Presets: 10 / 100 / 250 / 500
	hud.apply_stat_preset(100.0)
	_assert_true(player.stat_sheet.mana_awakened, "Preset 100 awakens mana")
	_assert_approx(player.stat_sheet.get_base_stat(StatSheet.Stat.STR), 100.0, 1e-4, "Preset 100 sets base STR=100")
	_assert_approx(player.stat_sheet.get_stat(StatSheet.Stat.STR), 112.0, 1e-4, "Preset 100 includes +12 External Circulation")

	hud.apply_stat_preset(250.0)
	_assert_approx(player.stat_sheet.get_base_stat(StatSheet.Stat.STR), 250.0, 1e-4, "Preset 250 sets base STR=250")

	hud.apply_stat_preset(500.0)
	_assert_approx(player.stat_sheet.get_stat(StatSheet.Stat.SPD), 500.0, 1e-4, "Preset 500 caps SPD at 500")
	_assert_approx(player.stat_sheet.get_stat(StatSheet.Stat.TP), 500.0, 1e-4, "Preset 500 caps TP at 500")
	SimulationClock.set_tempo_mode(SimulationClock.TempoMode.COMBAT_OVERDRIVE)
	_assert_approx(SimulationClock.get_world_time_scale(), 0.02, 1e-5, "Preset 500 yields 50x slow-mo (0.02) in COMBAT_OVERDRIVE")

	# Weak-point highlight checkbox via EventBus
	hud.set_weak_points_highlight(true)
	_assert_true(EventBus.debug_highlight_weak_points, "DebugHUD enables EventBus.debug_highlight_weak_points")
	hud.set_weak_points_highlight(false)
	_assert_false(EventBus.debug_highlight_weak_points, "DebugHUD disables EventBus.debug_highlight_weak_points")

	# Anatomy zone colors + Heal Player revives dead player (use mortal REG=10; REG>=400 survives heart loss per GDD 3.2 #12)
	hud.apply_stat_preset(10.0)
	_assert_eq(DebugHUD.get_zone_color(player.anatomy, AnatomyComponent.ZONE_CHEST), DebugHUD.COLOR_ZONE_HEALTHY, "Healthy Chest is green")
	player.anatomy.apply_penetrating_hit(AnatomyComponent.ZONE_CHEST, 21.0, true)
	_assert_true(player.anatomy.is_dead, "Lethal chest wound kills player")
	_assert_eq(DebugHUD.get_zone_color(player.anatomy, AnatomyComponent.ZONE_CHEST), DebugHUD.COLOR_ZONE_DESTROYED, "Destroyed Chest organ renders dark crimson")
	hud.heal_player_all()
	_assert_false(player.anatomy.is_dead, "Heal Player button revives dead player")
	_assert_approx(player.anatomy.blood_volume, 5000.0, 1e-4, "Heal Player restores full 5000 ml blood")
	_assert_eq(DebugHUD.get_zone_color(player.anatomy, AnatomyComponent.ZONE_CHEST), DebugHUD.COLOR_ZONE_HEALTHY, "Healed Chest returns to green")

	# Respawn Dummies button
	var old_r1: EnemyDummy = arena.entities_container.get_node_or_null("Rank1Swordsman") as EnemyDummy
	old_r1.anatomy.apply_penetrating_hit(AnatomyComponent.ZONE_HEAD, 25.0, true)
	_assert_true(old_r1.anatomy.is_dead, "Old Rank 1 dummy killed before respawn")
	hud.respawn_dummies()
	var new_r1: EnemyDummy = arena.entities_container.get_node_or_null("Rank1Swordsman") as EnemyDummy
	var new_r6: EnemyDummy = arena.entities_container.get_node_or_null("Rank6Guard") as EnemyDummy
	_assert_true(new_r1 != null and new_r1.is_alive(), "Respawn creates fresh alive Rank 1 Swordsman")
	_assert_true(new_r6 != null and new_r6.is_alive(), "Respawn creates fresh alive Rank 6 Guard")

	# Combat outcome telemetry updates DebugHUD target & penetration panel via EventBus
	var r1_chest: HitboxZone = null
	for hz: HitboxZone in new_r1.hitbox_zones:
		if hz.zone_name == AnatomyComponent.ZONE_CHEST:
			r1_chest = hz
			break
	hud.apply_stat_preset(10.0)
	new_r1.receive_melee_hit(player, r1_chest, player.equipped_weapon, false, 1.0, false)
	hud._refresh_all_views()
	_assert_eq(hud.last_attacked_target, new_r1, "DebugHUD tracks last attacked target via EventBus")
	_assert_true(hud.lbl_target_title.text.contains("Rank1_Swordsman"), "Target anatomy header displays attacked enemy")

	# Calendar controls: +1 day and Skip to Blood Moon (Day 30)
	WorldCalendar.reset_calendar(0)
	hud.advance_one_day()
	_assert_eq(WorldCalendar.get_total_day(), 2, "+1 Day button advances WorldCalendar to Day 2")
	hud.skip_to_blood_moon()
	_assert_eq(WorldCalendar.get_day_of_month(), 30, "Skip to Blood Moon lands on Day 30")
	_assert_true(WorldCalendar.is_blood_moon(), "WorldCalendar.is_blood_moon() is true on Day 30")

	# 3. Section 14.2 Anti-Tunneling Acceptance Test at SPD=500 (11,000 px/s against 32 px outer wall)
	hud.apply_stat_preset(500.0)
	SimulationClock.set_tempo_mode(SimulationClock.TempoMode.COMBAT_OVERDRIVE)
	SimulationClock.perception_regulator = 0.0
	SimulationClock.speed_regulator = 1.0
	player.global_position = Vector2(80.0, 256.0)
	await get_tree().physics_frame
	var supersonic_action_dt: float = SimulationClock.get_player_action_delta(0.016) # 0.8s -> 176 px requested motion!
	player.move_with_substepping(Vector2(-CombatActor.BASE_RUN_SPEED_PX, 0.0), supersonic_action_dt, false, false)
	_assert_true(
		player.global_position.x >= 32.0,
		"SPD=500 (176 px/frame) does NOT tunnel through 32 px perimeter wall (x=%.2f)" % player.global_position.x
	)

	remove_child(arena)
	arena.queue_free()
	EventBus.set_debug_highlight_weak_points(false)


# ===========================================================================
# SUITE 12: Real Physics Combat Sweep vs Rank 6 & All Audit Bugfixes
# ===========================================================================

func _test_stage0_bugfixes_real_physics() -> void:
	SimulationClock.reset_defaults()
	WorldCalendar.reset_calendar(0)
	FloorLayerManager.reset(0)

	var arena_scene: PackedScene = load("res://scenes/test_arena.tscn") as PackedScene
	var arena: TestArena = arena_scene.instantiate() as TestArena
	add_child(arena)

	var hud: DebugHUD = arena.get_node_or_null("DebugHUD") as DebugHUD
	var player: PlayerController = arena.entities_container.get_node_or_null("Player") as PlayerController
	var rank6: EnemyDummy = arena.entities_container.get_node_or_null("Rank6Guard") as EnemyDummy
	arena.set_all_enemies_ai_enabled(false)

	# 1. All 8 anatomical HitboxZones exist and move with HitboxRoot during flight
	_assert_eq(rank6.hitbox_zones.size(), 8, "Rank 6 Guard has all 8 anatomical HitboxZones")
	var expected_guard_visual_y: float = rank6.global_position.y - 1.5 * VerticalityComponent.VISUAL_Y_OFFSET_PER_Z
	_assert_approx(rank6.get_combat_origin().y, expected_guard_visual_y, 0.5, "Guard combat_origin matches visual height_z=-67.5px")
	var guard_chest: HitboxZone = null
	for hz: HitboxZone in rank6.hitbox_zones:
		if hz.zone_name == AnatomyComponent.ZONE_CHEST:
			guard_chest = hz
			break
	_assert_true(guard_chest != null, "Guard Chest HitboxZone found")
	var guard_wps: Array[Vector2] = guard_chest.get_world_weak_points()
	_assert_true(guard_wps.size() >= 1, "Guard Chest has weak point")
	_assert_approx(guard_wps[0].y, expected_guard_visual_y, 2.0, "Guard weak-point world Y matches visible floating sprite (not shadow!)")

	# Position player 26 px left of Rank 6 Guard on Floor 0
	player.global_position = rank6.global_position + Vector2(-26.0, 0.0)
	player.verticality.set_floor_level(0)
	player.verticality.set_height_z(0.0)
	player.select_weapon_slot(0) # Dagger (reach=0.6)
	await get_tree().physics_frame
	await get_tree().physics_frame

	# 2. Grounded player swinging at hovering Guard misses by vertical_reach AND reports OUT_OF_VERTICAL_REACH!
	EventBus.last_combat_outcome = {}
	player.start_primary_attack(rank6.get_combat_origin())
	player.step_combat_fsm(0.60)
	_assert_eq(String(EventBus.last_combat_outcome.get("outcome", "")), "out_of_vertical_reach", "Grounded swing vs hovering Guard logs out_of_vertical_reach")
	_assert_approx(rank6.anatomy.get_blood_ratio(), 1.0, 1e-4, "Grounded swing deals 0 damage to hovering Guard")

	# 3. Flying player (z=1.5) aiming at Guard's visible floating sprite with STR=10 Dagger (no Aura):
	#    MUST physically connect via CapsuleShape2D sweep, bounce off armor, and dull dagger!
	player.verticality.set_height_z(1.5)
	player.refill_resources()
	await get_tree().physics_frame
	await get_tree().physics_frame

	var sharp_before: float = player.equipped_weapon.edge_sharpness
	EventBus.last_combat_outcome = {}
	# Aim slightly off weak-point center so it tests normal armored body hit
	player.start_primary_attack(rank6.get_combat_origin() + Vector2(0.0, 14.0))
	player.step_combat_fsm(0.60)
	_assert_eq(String(EventBus.last_combat_outcome.get("outcome", "")), "no_penetration", "Flying STR=10 Dagger physically hits Rank 6 armor (no elevation/SegmentShape2D miss!)")
	_assert_true(player.equipped_weapon.edge_sharpness < sharp_before, "Real sweep bounce off Rank 6 armor dulls dagger")

	# 4. Flying player aiming directly at Guard's VISIBLE red weak point with Aura Burst (M_CTRL=10):
	#    MUST trigger is_weak_point=true (not locked out by Chest edge graze!) and penetrate!
	player.equipped_weapon.edge_sharpness = 1.0
	player.stat_sheet.awaken_mana(10.0, 10.0)
	player.refill_resources()
	player.set_aura_active(true)
	EventBus.last_combat_outcome = {}
	var visible_wp: Vector2 = guard_chest.get_world_weak_points()[0]
	player.start_primary_attack(visible_wp)
	player.try_trigger_aura_burst()
	player.step_combat_fsm(0.60)
	_assert_eq(String(EventBus.last_combat_outcome.get("outcome", "")), "penetrated", "Real sweep under Aura Burst at visible weak point penetrates Rank 6 Guard")
	_assert_true(bool(EventBus.last_combat_outcome.get("is_weak_point", false)), "Real sweep registers is_weak_point == true on floating Guard")
	_assert_true(rank6.anatomy.get_all_wounds().size() > 0, "Rank 6 Guard actually received wounds from real physics swing")

	# 5. Flying player at MAX STATS (500) via DebugHUD kills Rank 6 Guard with a REAL swing,
	#    and dead Guard's HitboxZones become monitorable == false!
	rank6.revive_and_heal_all()
	await get_tree().physics_frame
	hud.apply_stat_preset(500.0)
	player.select_weapon_slot(1) # Greatsword
	player.set_aura_active(false)
	EventBus.last_combat_outcome = {}
	player.start_primary_attack(rank6.get_combat_origin())
	player.step_combat_fsm(1.0)
	_assert_true(rank6.anatomy.is_dead, "MAX STATS (500) real physics swing KILLS Rank 6 Guard!")
	_assert_false(guard_chest.monitorable, "Dead corpse HitboxZone disables monitorable")

	# 6. Preset 10 cleanly resets unawakened human state
	hud.apply_stat_preset(10.0)
	_assert_false(player.stat_sheet.mana_awakened, "Preset 10 resets mana_awakened back to false")
	_assert_approx(player.stat_sheet.get_stat(StatSheet.Stat.M_CTRL), 0.0, 1e-4, "Preset 10 resets M_CTRL to 0")

	# 7. Holding block during attack WINDUP/ACTIVE must NOT re-enable is_blocking
	player.refill_resources()
	player.start_primary_attack(player.get_combat_origin() + Vector2(30.0, 0.0))
	player.set_block_held(true)
	_assert_false(player.is_blocking, "Held block cannot re-engage while in attack WINDUP/ACTIVE")
	player.step_combat_fsm(1.0)

	# 8. Calm walking at SPD=500 with speed_regulator=0.02 must NOT smash walls
	hud.apply_stat_preset(500.0)
	SimulationClock.perception_regulator = 0.0
	SimulationClock.speed_regulator = 0.02
	var wood_cell: Vector2i = TestArena.WOOD_WALL_CELLS[0]
	player.verticality.set_height_z(0.0)
	player.global_position = arena.cell_to_world_center(wood_cell) + Vector2(-28.0, 0.0)
	await get_tree().physics_frame
	player.move_with_substepping(Vector2(CombatActor.BASE_RUN_SPEED_PX, 0.0), 0.10, false, true)
	_assert_true(arena.is_wall_solid_at(0, wood_cell), "Walking calmly at speed_regulator=0.02 with SPD=500 does NOT smash wood wall")

	# 9. Flying on Floor +1 (height_z=1.5) swinging weapon must NOT break Floor +1 beneath
	var hole_cell: Vector2i = TestArena.BREAKABLE_FLOOR_RECT.position
	player.verticality.set_floor_level(1)
	player.verticality.set_height_z(1.5)
	player.global_position = arena.cell_to_world_center(hole_cell) + Vector2(-36.0, 0.0)
	await get_tree().physics_frame
	player.start_primary_attack(arena.cell_to_world_center(hole_cell) + Vector2(0.0, -67.5))
	player.step_combat_fsm(1.0)
	_assert_true(FloorLayerManager.has_floor_at(1, hole_cell), "Swinging while flying (z=1.5) on Floor +1 does NOT accidentally break floor")

	# 10. Dead entity cannot use stairs
	player.verticality.set_floor_level(0)
	player.verticality.set_height_z(0.0)
	player.global_position = arena.cell_to_world_center(TestArena.STAIRS_RECT.position)
	player.anatomy.apply_penetrating_hit(AnatomyComponent.ZONE_HEAD, 30.0, true)
	_assert_true(player.anatomy.is_dead, "Player killed for stair test")
	_assert_false(arena.try_use_stairs(player), "Dead player cannot use stairs")
	hud.heal_player_all()
	_assert_true(arena.try_use_stairs(player), "Revived player can use stairs again")

	remove_child(arena)
	arena.queue_free()
	EventBus.set_debug_highlight_weak_points(false)


# ===========================================================================
# SUITE 13: v0.2 Core - 12th Stat REG, Human/Troll Presets & CON Separation
# ===========================================================================

func _test_v02_stat_sheet_reg_and_races() -> void:
	# 1. 12 distributable stats including REG (1..500, reference 10)
	_assert_eq(StatSheet.ALL_STATS.size(), 12, "StatSheet has exactly 12 distributable stats")
	_assert_eq(StatSheet.get_stat_name(StatSheet.Stat.REG), &"REG", "Stat.REG name is REG")
	_assert_false(StatSheet.CIRCULATION_STATS.has(StatSheet.Stat.REG), "External Circulation does NOT buff REG")

	# 2. Human racial ceilings before awakening: REG <= 12, others <= 22
	var human: StatSheet = StatSheet.new(StatSheet.DEFAULT_HUMAN_RACIAL_CAP, StatSheet.RacePreset.HUMAN)
	_assert_eq(human.race_preset, StatSheet.RacePreset.HUMAN, "Default race preset is HUMAN")
	_assert_approx(human.get_stat(StatSheet.Stat.REG), 10.0, 1e-5, "Default REG == 10")
	human.set_base_stat(StatSheet.Stat.REG, 50.0)
	human.set_base_stat(StatSheet.Stat.CON, 50.0)
	human.set_base_stat(StatSheet.Stat.STR, 50.0)
	_assert_approx(human.get_stat(StatSheet.Stat.REG), 12.0, 1e-5, "Human pre-awakening REG clamped at <= 12")
	_assert_approx(human.get_stat(StatSheet.Stat.CON), 22.0, 1e-5, "Human pre-awakening CON clamped at <= 22")
	_assert_approx(human.get_stat(StatSheet.Stat.STR), 22.0, 1e-5, "Human pre-awakening STR clamped at <= 22")

	# 3. Switchable Troll preset before awakening: REG <= 65, CON <= 45, others <= 22
	human.apply_race_preset(StatSheet.RacePreset.TROLL)
	_assert_eq(human.race_preset, StatSheet.RacePreset.TROLL, "Switched to TROLL race preset")
	human.set_base_stat(StatSheet.Stat.REG, 100.0)
	human.set_base_stat(StatSheet.Stat.CON, 100.0)
	human.set_base_stat(StatSheet.Stat.STR, 100.0)
	_assert_approx(human.get_stat(StatSheet.Stat.REG), 65.0, 1e-5, "Troll pre-awakening REG clamped at <= 65")
	_assert_approx(human.get_stat(StatSheet.Stat.CON), 45.0, 1e-5, "Troll pre-awakening CON clamped at <= 45")
	_assert_approx(human.get_stat(StatSheet.Stat.STR), 22.0, 1e-5, "Troll other stats stay under default cap 22 before awakening")
	_assert_false(human.uses_magical_regen(), "Unawakened Troll (REG=65) does not consume MP before mana awakening")

	# 4. Mana awakening removes ALL racial caps (Human & Troll)
	human.awaken_mana(100.0, 100.0)
	_assert_approx(human.get_stat(StatSheet.Stat.REG), 100.0, 1e-5, "Mana awakening lifts Troll REG cap to 100 (and no circ bonus)")
	_assert_approx(human.get_stat(StatSheet.Stat.CON), 112.0, 1e-5, "Mana awakening lifts CON cap + applies +12 External Circulation")
	_assert_true(human.uses_magical_regen(), "Awakened REG > 50 uses magical regen (MP cost)")

	# 5. Exact REG derived formulas matching Table 3.1 & Section 3.2 #12
	var reg_sheet: StatSheet = StatSheet.new()
	reg_sheet.awaken_mana(100.0, 100.0)
	reg_sheet.set_base_stat(StatSheet.Stat.REG, 10.0)
	_assert_approx(reg_sheet.get_clot_rate(), 1.0, 1e-5, "REG=10 clot_rate == 1.0")
	_assert_approx(reg_sheet.get_heal_rate(), 1.0, 1e-5, "REG=10 heal_rate == 1.0")
	_assert_false(reg_sheet.can_combat_clot(), "REG=10 cannot combat-clot (<40)")
	_assert_false(reg_sheet.can_regrow_limbs(), "REG=10 cannot regrow limbs (<150)")
	_assert_false(reg_sheet.can_reconstruct_organs(), "REG=10 cannot reconstruct organs (<400)")

	reg_sheet.set_base_stat(StatSheet.Stat.REG, 55.0)
	_assert_approx(reg_sheet.get_clot_rate(), pow(5.5, 1.5), 1e-4, "REG=55 clot_rate == 5.5^1.5")
	_assert_approx(reg_sheet.get_heal_rate(), 21.522, 0.05, "REG=55 heal_rate ~= 21.5x (Table 3.1)")
	_assert_true(reg_sheet.can_combat_clot(), "REG=55 can combat-clot (>=40)")

	reg_sheet.set_base_stat(StatSheet.Stat.REG, 160.0)
	_assert_approx(reg_sheet.get_clot_rate(), 64.0, 1e-4, "REG=160 (Troll Berserker) clot_rate == 64.0")
	_assert_approx(reg_sheet.get_heal_rate(), pow(16.0, 1.8), 1e-3, "REG=160 heal_rate == 16^1.8")
	_assert_true(reg_sheet.can_regrow_limbs(), "REG=160 can regrow severed limbs (>=150)")
	_assert_false(reg_sheet.can_reconstruct_organs(), "REG=160 cannot reconstruct vital organs (<400)")

	reg_sheet.set_base_stat(StatSheet.Stat.REG, 400.0)
	_assert_approx(reg_sheet.get_heal_rate(), 765.08, 0.2, "REG=400 heal_rate ~= 765x (Table 3.1)")
	_assert_true(reg_sheet.can_reconstruct_organs(), "REG=400 can reconstruct vital organs (>=400)")

	reg_sheet.set_base_stat(StatSheet.Stat.REG, 500.0)
	_assert_approx(reg_sheet.get_heal_rate(), pow(50.0, 1.8), 1e-2, "REG=500 heal_rate == 50^1.8 (~1143x)")

	# 6. Separation of CON from REG
	var sep_sheet: StatSheet = StatSheet.new()
	sep_sheet.awaken_mana(10.0, 10.0)
	sep_sheet.set_base_stat(StatSheet.Stat.REG, 10.0)
	sep_sheet.set_base_stat(StatSheet.Stat.CON, 100.0)
	_assert_approx(sep_sheet.get_clot_rate(), 1.0, 1e-5, "Raising CON to 100 does NOT raise REG clot_rate")
	_assert_approx(sep_sheet.get_heal_rate(), 1.0, 1e-5, "Raising CON to 100 does NOT raise REG heal_rate")
	_assert_true(sep_sheet.get_con_skin_density() > 600.0, "CON=100 retains skin density")
	_assert_true(sep_sheet.get_bone_density_mult() >= 10.0, "CON=100 retains bone density mult")
	_assert_true(sep_sheet.get_bleed_resist_mult() < 1.0, "CON=100 retains passive bleed resistance")
	_assert_true(sep_sheet.get_con_stamina_synergy_bonus() > 0.0, "CON=100 retains STA reserve synergy")


# ===========================================================================
# SUITE 14: v0.2 TempoMode (PEACEFUL/OVERDRIVE), Aggro Lock, Hitstop & Ambush
# ===========================================================================

func _test_v02_tempo_mode_hitstop_and_ambush() -> void:
	SimulationClock.reset_defaults()
	WorldCalendar.reset_calendar(0)
	FloorLayerManager.reset(0)

	var tempo_events: Array[Dictionary] = []
	var hitstop_events: Array[Dictionary] = []
	var on_tempo: Callable = func(old_m: int, new_m: int, reason: String) -> void:
		tempo_events.append({"old": old_m, "new": new_m, "reason": reason})
	var on_hitstop: Callable = func(dur: float, src: Node, tgt: Node) -> void:
		hitstop_events.append({"dur": dur, "src": src, "tgt": tgt})
	EventBus.tempo_mode_changed.connect(on_tempo)
	EventBus.hitstop_triggered.connect(on_hitstop)

	var dt: float = 0.016

	# 1. PEACEFUL (1.0x) default limits demigod player (SPD=500, TP=500) & patrolling enemies (SPD=100)
	SimulationClock.set_player_stats(500.0, 500.0, 500.0, 100.0)
	_assert_true(SimulationClock.is_peaceful(), "Starts in PEACEFUL TempoMode")
	_assert_false(SimulationClock.is_wall_ramming_allowed(), "Wall ramming disabled in PEACEFUL")
	_assert_approx(SimulationClock.get_world_time_scale(), 1.0, 1e-5, "PEACEFUL forces world_time_scale == 1.0")
	_assert_approx(SimulationClock.get_effective_tp(), 10.0, 1e-5, "PEACEFUL fixes effective_TP == 10.0")
	_assert_approx(SimulationClock.get_player_action_delta(dt), dt, 1e-6, "PEACEFUL caps player eff_SPD = min(500, 10) -> 1.0x")
	_assert_approx(SimulationClock.get_enemy_action_delta(dt, 100.0, true), dt, 1e-6, "PEACEFUL caps patrolling Rank 6 Guard to 1.0x")

	# 2. Manual toggle (G) switches PEACEFUL <-> COMBAT_OVERDRIVE when out of aggro
	_assert_true(SimulationClock.toggle_tempo_mode_manual(), "Manual G toggle enters COMBAT_OVERDRIVE")
	_assert_true(SimulationClock.is_combat_overdrive(), "Now in COMBAT_OVERDRIVE")
	_assert_true(SimulationClock.is_wall_ramming_allowed(), "Wall ramming enabled in COMBAT_OVERDRIVE")
	_assert_approx(SimulationClock.get_world_time_scale(), 0.02, 1e-6, "COMBAT_OVERDRIVE activates 50x slow-mo at TP=500")
	_assert_eq(tempo_events.size(), 1, "tempo_mode_changed emitted on manual toggle ON")
	_assert_true(SimulationClock.toggle_tempo_mode_manual(), "Manual G toggle returns to PEACEFUL when no aggro")
	_assert_true(SimulationClock.is_peaceful(), "Returned to PEACEFUL")

	# 3. active_aggro_ids engages COMBAT_OVERDRIVE and BLOCKS manual G toggle off!
	SimulationClock.register_aggro(9001)
	_assert_true(SimulationClock.is_combat_overdrive(), "register_aggro forces COMBAT_OVERDRIVE")
	_assert_true(SimulationClock.has_active_aggro(), "has_active_aggro is true")
	_assert_eq(SimulationClock.get_active_aggro_count(), 1, "active_aggro_ids count == 1")
	_assert_false(SimulationClock.toggle_tempo_mode_manual(), "Manual G toggle OFF blocked while pursuers active")
	_assert_false(SimulationClock.set_tempo_mode(SimulationClock.TempoMode.PEACEFUL, false), "Non-forced PEACEFUL switch blocked while aggro active")
	_assert_true(SimulationClock.is_combat_overdrive(), "Still locked in COMBAT_OVERDRIVE during combat")

	# Second pursuer joins; removing only first keeps overdrive locked
	SimulationClock.register_aggro(9002)
	SimulationClock.unregister_aggro(9001)
	_assert_true(SimulationClock.has_active_aggro(), "Second pursuer keeps aggro active")
	_assert_false(SimulationClock.toggle_tempo_mode_manual(), "Still cannot turn off overdrive with 1 pursuer left")

	# Last pursuer transitions SEARCH -> PATROL (unregisters) -> returns to PEACEFUL!
	SimulationClock.unregister_aggro(9002)
	_assert_false(SimulationClock.has_active_aggro(), "All pursuers cleared")
	_assert_true(SimulationClock.is_peaceful(), "Auto-returns to PEACEFUL once all pursuers return to PATROL")

	# 4. Player attack auto-enters COMBAT_OVERDRIVE (and manual toggle off works since no enemy aggro yet)
	SimulationClock.notify_player_attack()
	_assert_true(SimulationClock.is_combat_overdrive(), "notify_player_attack engages COMBAT_OVERDRIVE")
	_assert_true(SimulationClock.toggle_tempo_mode_manual(), "Can return to PEACEFUL after solo attack with no pursuers")

	# 5. Ambush & Imperceptible Speed ALWAYS evaluates against REAL player TP & AGI even in PEACEFUL!
	_assert_true(SimulationClock.is_peaceful(), "Player walking in PEACEFUL mode")
	SimulationClock.set_player_stats(50.0, 50.0, 50.0, 80.0) # Master walking peacefully at 1.0x
	var master_ambush: Dictionary = SimulationClock.evaluate_ambush_imperceptible(100.0)
	_assert_true(bool(master_ambush["evaluated_in_peaceful"]), "Ambush evaluated while in PEACEFUL")
	_assert_false(bool(master_ambush["imperceptible"]), "Rank 6 (SPD=100) vs peaceful Master (real TP=50 -> ratio 2x) is NOT imperceptible")
	_assert_approx(float(master_ambush["real_tp"]), 50.0, 1e-5, "Ambush check uses REAL TP=50, not PEACEFUL 10.0")
	_assert_true(float(master_ambush["instinct_dodge_chance"]) > 0.2, "Ambush check preserves REAL AGI instinct dodge")

	SimulationClock.set_player_stats(10.0, 10.0, 10.0, 10.0) # Novice in PEACEFUL
	var novice_ambush: Dictionary = SimulationClock.evaluate_ambush_imperceptible(100.0)
	_assert_true(bool(novice_ambush["imperceptible"]), "Rank 6 (SPD=100) vs peaceful Novice (real TP=10 -> ratio 10x) IS imperceptible")

	# 6. Local Hitstop (0.03..0.07s) freezes combat pair action_delta without slowing WorldCalendar or unrelated actors
	SimulationClock.set_tempo_mode(SimulationClock.TempoMode.COMBAT_OVERDRIVE)
	SimulationClock.set_player_stats(10.0, 10.0, 10.0, 10.0)
	var fighter_a: Node = Node.new()
	var fighter_b: Node = Node.new()
	var bystander: Node = Node.new()
	var dur_clamped_low: float = SimulationClock.trigger_hitstop(0.005, fighter_a, fighter_b)
	_assert_approx(dur_clamped_low, SimulationClock.MIN_HITSTOP_SEC, 1e-5, "Hitstop clamps min duration to 0.03s")
	SimulationClock.clear_hitstop()
	var dur_clamped_high: float = SimulationClock.trigger_hitstop(0.50, fighter_a, fighter_b)
	_assert_approx(dur_clamped_high, SimulationClock.MAX_HITSTOP_SEC, 1e-5, "Hitstop clamps max duration to 0.07s")
	_assert_eq(hitstop_events.size(), 2, "EventBus.hitstop_triggered emitted")

	_assert_true(SimulationClock.is_in_hitstop(fighter_a.get_instance_id()), "Fighter A frozen during pair hitstop")
	_assert_true(SimulationClock.is_in_hitstop(fighter_b.get_instance_id()), "Fighter B frozen during pair hitstop")
	_assert_false(SimulationClock.is_in_hitstop(bystander.get_instance_id()), "Unrelated bystander NOT frozen by pair hitstop")
	_assert_approx(SimulationClock.get_player_action_delta(dt, fighter_a.get_instance_id()), 0.0, 1e-6, "Frozen player gets action_delta == 0.0")
	_assert_approx(SimulationClock.get_enemy_action_delta(dt, 10.0, false, fighter_b.get_instance_id()), 0.0, 1e-6, "Frozen enemy gets action_delta == 0.0")
	_assert_approx(SimulationClock.get_enemy_action_delta(dt, 10.0, false, bystander.get_instance_id()), dt, 1e-6, "Bystander still advances action_delta")

	# WorldCalendar advances unaffected during Hitstop (Engine.time_scale remains 1.0)
	var cal_min_before: float = WorldCalendar.total_minutes
	WorldCalendar.advance_real_seconds(120.0)
	_assert_approx(WorldCalendar.total_minutes - cal_min_before, 60.0, 1e-4, "WorldCalendar completely unaffected by Hitstop")
	_assert_approx(Engine.time_scale, 1.0, 1e-6, "Engine.time_scale stays strictly 1.0 during Hitstop")

	SimulationClock.tick_hitstop(0.08)
	_assert_false(SimulationClock.is_in_hitstop(fighter_a.get_instance_id()), "Hitstop expires cleanly after raw_delta >= duration")
	_assert_approx(SimulationClock.get_player_action_delta(dt, fighter_a.get_instance_id()), dt, 1e-6, "Action delta resumes after Hitstop")
	fighter_a.free()
	fighter_b.free()
	bystander.free()

	# 7. Real TestArena check: running in PEACEFUL at STR=500, SPD=500 does NOT break wood wall!
	SimulationClock.reset_defaults()
	var arena_scene: PackedScene = load("res://scenes/test_arena.tscn") as PackedScene
	var arena: TestArena = arena_scene.instantiate() as TestArena
	add_child(arena)
	arena.set_all_enemies_ai_enabled(false)
	var player: PlayerController = arena.entities_container.get_node_or_null("Player") as PlayerController
	player.stat_sheet.awaken_mana(500.0, 500.0)
	player.stat_sheet.set_all_base_stats(500.0, true)
	SimulationClock.set_tempo_mode(SimulationClock.TempoMode.PEACEFUL, true)
	var wood_cell: Vector2i = TestArena.WOOD_WALL_CELLS[0]
	player.global_position = arena.cell_to_world_center(wood_cell) + Vector2(-26.0, 0.0)
	await get_tree().physics_frame
	player.move_with_substepping(Vector2(CombatActor.BASE_RUN_SPEED_PX, 0.0), 0.12, false, true)
	_assert_true(arena.is_wall_solid_at(0, wood_cell), "PEACEFUL mode blocks passive wall ramming even at STR=500, SPD=500")

	# Switching to COMBAT_OVERDRIVE enables wall ramming!
	SimulationClock.set_tempo_mode(SimulationClock.TempoMode.COMBAT_OVERDRIVE)
	SimulationClock.speed_regulator = 1.0
	player.move_with_substepping(Vector2(CombatActor.BASE_RUN_SPEED_PX, 0.0), 0.12, false, true)
	_assert_false(arena.is_wall_solid_at(0, wood_cell), "COMBAT_OVERDRIVE allows STR=500 player to ram through wood wall")

	remove_child(arena)
	arena.queue_free()
	EventBus.tempo_mode_changed.disconnect(on_tempo)
	EventBus.hitstop_triggered.disconnect(on_hitstop)


# ===========================================================================
# SUITE 15: v0.2 WeaponData, 4 Barriers, Strike Types, Dead Zone, Aura Burst & Blade Clash
# ===========================================================================

func _test_v02_weapons_barriers_and_clash() -> void:
	# 1. WeaponData v0.2 properties: Half-swording & durability breakage
	var gs_tpl: WeaponData = load("res://data/greatsword.tres") as WeaponData
	var gs: WeaponData = gs_tpl.create_runtime_copy()
	_assert_approx(gs.get_effective_blade_length(false), 46.0, 1e-4, "Greatsword full blade length == 46")
	_assert_approx(gs.get_effective_blade_length(true), 46.0 * 0.55, 1e-4, "Half-swording reduces reach to 55%")
	_assert_approx(gs.get_effective_min_optimal_range(false), 20.0, 1e-4, "Greatsword dead zone min_optimal_range == 20")
	_assert_approx(gs.get_effective_min_optimal_range(true), 0.0, 1e-4, "Half-swording eliminates min_optimal_range")
	_assert_false(gs.is_broken(), "Fresh greatsword is not broken")
	gs.apply_durability_damage(200.0, 0.0, true)
	_assert_false(gs.is_broken(), "Active Aura prevents durability damage")
	gs.apply_durability_damage(100.0, 0.0, false)
	_assert_true(gs.is_broken(), "Zero durability marks weapon broken")
	_assert_approx(gs_tpl.durability, 100.0, 1e-4, "Read-only greatsword.tres durability untouched")

	# 2. 4 Sequential Tissue Barriers (Armor -> Skin -> Muscle/Tendon -> Bone/Vessel/Organ)
	var def_human: PenetrationResolver.DefenseParams = PenetrationResolver.DefenseParams.new()
	def_human.target_con = 10.0
	def_human.armor_thickness = 5.0
	def_human.armor_hardness = 4.0 # armor_barrier = 20.0; skin_barrier = 12.0; barrier_depth = 32.0
	def_human.zone_name = AnatomyComponent.ZONE_RIGHT_ARM

	# Stopped at Armor (pen 15 < armor 20)
	var atk_b0: PenetrationResolver.AttackParams = PenetrationResolver.AttackParams.new()
	atk_b0.weapon_base_penetration = 15.0
	atk_b0.weapon_blade_length = 30.0
	var r_b0: PenetrationResolver.ResolutionResult = PenetrationResolver.resolve(atk_b0, def_human)
	_assert_false(r_b0.armor_breached, "Pen 15 fails Armor barrier 20")
	_assert_eq(r_b0.deepest_barrier_reached, PenetrationResolver.TissueBarrier.NONE, "Stopped by Armor -> deepest == NONE")

	# Breaches Armor (25 > 20) but stopped by Skin/CON (25 < 32)
	var atk_b1: PenetrationResolver.AttackParams = PenetrationResolver.AttackParams.new()
	atk_b1.weapon_base_penetration = 25.0
	atk_b1.weapon_blade_length = 30.0
	var r_b1: PenetrationResolver.ResolutionResult = PenetrationResolver.resolve(atk_b1, def_human)
	_assert_true(r_b1.armor_breached, "Pen 25 breaches Armor barrier 20")
	_assert_false(r_b1.skin_breached, "Pen 25 stopped by Skin/CON barrier 32")
	_assert_eq(r_b1.deepest_barrier_reached, PenetrationResolver.TissueBarrier.ARMOR, "Deepest barrier reached == ARMOR")

	# Breaches Skin (pen 35 -> depth 3.0 < muscle_tendon_barrier 5.0)
	var atk_b2: PenetrationResolver.AttackParams = PenetrationResolver.AttackParams.new()
	atk_b2.weapon_base_penetration = 35.0
	atk_b2.weapon_blade_length = 30.0
	var r_b2: PenetrationResolver.ResolutionResult = PenetrationResolver.resolve(atk_b2, def_human)
	_assert_true(r_b2.skin_breached, "Pen 35 breaches Skin (depth 3.0)")
	_assert_false(r_b2.muscle_tendon_breached, "Depth 3.0 does not breach Muscle/Tendon barrier (5.0)")
	_assert_eq(r_b2.deepest_barrier_reached, PenetrationResolver.TissueBarrier.SKIN, "Deepest barrier reached == SKIN")

	# Breaches Muscle/Tendon (pen 40 -> depth 8.0 >= 5.0, < bone_vessel_barrier 12.0)
	var atk_b3: PenetrationResolver.AttackParams = PenetrationResolver.AttackParams.new()
	atk_b3.weapon_base_penetration = 40.0
	atk_b3.weapon_blade_length = 30.0
	atk_b3.attack_type = PenetrationResolver.AttackType.SLASH
	atk_b3.type_pierce_mult_override = 1.0
	var r_b3: PenetrationResolver.ResolutionResult = PenetrationResolver.resolve(atk_b3, def_human)
	_assert_true(r_b3.muscle_tendon_breached, "Depth 8.0 breaches Muscle/Tendon barrier")
	_assert_false(r_b3.bone_vessel_breached, "Depth 8.0 does not reach Bone/Vessel barrier (12.0)")
	_assert_eq(r_b3.deepest_barrier_reached, PenetrationResolver.TissueBarrier.MUSCLE_TENDON, "Deepest barrier == MUSCLE_TENDON")
	_assert_true(r_b3.tendon_severed, "SLASH into muscle layer flags tendon_severed")

	# Breaches all 4 barriers (pen 55 -> depth 23.0 >= 12.0)
	var atk_b4: PenetrationResolver.AttackParams = PenetrationResolver.AttackParams.new()
	atk_b4.weapon_base_penetration = 55.0
	atk_b4.weapon_blade_length = 30.0
	atk_b4.attack_type = PenetrationResolver.AttackType.THRUST
	var r_b4: PenetrationResolver.ResolutionResult = PenetrationResolver.resolve(atk_b4, def_human)
	_assert_true(r_b4.bone_vessel_breached, "Deep strike breaches Barrier 4 (Bone/Vessels/Organs)")
	_assert_eq(r_b4.deepest_barrier_reached, PenetrationResolver.TissueBarrier.BONE_VESSEL_ORGAN, "Deepest barrier == BONE_VESSEL_ORGAN")
	_assert_true(r_b4.arterial_hit, "Barrier 4 breach triggers arterial_hit")

	# 3. Three Strike Types: THRUST (1.35x) vs SLASH (0.85x + sever) vs BLUNT (blunt_impulse focus)
	var bare_arm: PenetrationResolver.DefenseParams = PenetrationResolver.DefenseParams.new()
	bare_arm.target_con = 10.0
	bare_arm.bone_density = 100.0
	bare_arm.zone_name = AnatomyComponent.ZONE_RIGHT_ARM

	var atk_thrust: PenetrationResolver.AttackParams = PenetrationResolver.AttackParams.new()
	atk_thrust.attacker_str = 25.0
	atk_thrust.weapon_base_penetration = 28.0
	atk_thrust.weapon_blade_length = 46.0
	atk_thrust.weapon_mass_factor = 18.0
	atk_thrust.attack_type = PenetrationResolver.AttackType.THRUST
	var res_thrust: PenetrationResolver.ResolutionResult = PenetrationResolver.resolve(atk_thrust, bare_arm)

	var atk_slash: PenetrationResolver.AttackParams = PenetrationResolver.AttackParams.new()
	atk_slash.attacker_str = 25.0
	atk_slash.weapon_base_penetration = 28.0
	atk_slash.weapon_blade_length = 46.0
	atk_slash.weapon_mass_factor = 18.0
	atk_slash.attack_type = PenetrationResolver.AttackType.SLASH
	var res_slash: PenetrationResolver.ResolutionResult = PenetrationResolver.resolve(atk_slash, bare_arm)

	var atk_blunt: PenetrationResolver.AttackParams = PenetrationResolver.AttackParams.new()
	atk_blunt.attacker_str = 25.0
	atk_blunt.weapon_base_penetration = 28.0
	atk_blunt.weapon_blade_length = 46.0
	atk_blunt.weapon_mass_factor = 18.0
	atk_blunt.attack_type = PenetrationResolver.AttackType.BLUNT
	var res_blunt: PenetrationResolver.ResolutionResult = PenetrationResolver.resolve(atk_blunt, bare_arm)

	_assert_approx(res_thrust.type_pierce_mult, 1.35, 1e-5, "THRUST type_pierce_mult == 1.35")
	_assert_approx(res_slash.type_pierce_mult, 0.85, 1e-5, "SLASH type_pierce_mult == 0.85")
	_assert_true(res_thrust.penetration > res_slash.penetration, "THRUST has higher penetration than SLASH")
	_assert_true(res_slash.severed, "Strong SLASH above sever_threshold severs RightArm")
	_assert_false(res_thrust.severed, "THRUST does NOT dismember even with higher penetration")
	_assert_true(res_blunt.blunt_impulse > res_slash.blunt_impulse, "BLUNT boosts blunt_impulse for fractures & Wall Slam")
	_assert_approx(res_blunt.wall_slam_impulse, res_blunt.blunt_impulse, 1e-5, "BLUNT populates wall_slam_impulse")

	# Non-severable Chest never dismembers on SLASH
	var bare_chest: PenetrationResolver.DefenseParams = PenetrationResolver.DefenseParams.new()
	bare_chest.target_con = 10.0
	bare_chest.zone_name = AnatomyComponent.ZONE_CHEST
	var res_slash_chest: PenetrationResolver.ResolutionResult = PenetrationResolver.resolve(atk_slash, bare_chest)
	_assert_false(res_slash_chest.severed, "Non-severable Chest zone never triggers dismemberment")

	# 4. Dead Zone (dead_zone_mult = 0.30 at dist < min_optimal_range) vs Half-swording removal
	var atk_dead: PenetrationResolver.AttackParams = PenetrationResolver.AttackParams.new()
	atk_dead.attacker_str = 10.0
	atk_dead.weapon_base_penetration = 28.0
	atk_dead.weapon_blade_length = 46.0
	atk_dead.min_optimal_range = 20.0
	atk_dead.distance_to_target = 10.0
	atk_dead.can_half_sword = true
	atk_dead.half_swording = false
	var res_dead: PenetrationResolver.ResolutionResult = PenetrationResolver.resolve(atk_dead, bare_arm)
	_assert_true(res_dead.in_dead_zone, "Long sword at dist 10 < min_optimal_range 20 enters Dead Zone")
	_assert_approx(res_dead.dead_zone_mult, 0.30, 1e-5, "Dead Zone applies dead_zone_mult == 0.30")
	_assert_approx(res_dead.penetration, 28.0 * 0.30, 1e-4, "Dead Zone cuts penetration by 70%")

	atk_dead.half_swording = true
	var res_half: PenetrationResolver.ResolutionResult = PenetrationResolver.resolve(atk_dead, bare_arm)
	_assert_false(res_half.in_dead_zone, "Half-swording completely removes Dead Zone penalty")
	_assert_approx(res_half.dead_zone_mult, 1.0, 1e-5, "Half-swording restores dead_zone_mult == 1.0")
	_assert_approx(res_half.penetration, 28.0, 1e-4, "Half-swording restores full penetration up close")
	_assert_approx(res_half.max_blade_reach, 46.0 * 0.55, 1e-4, "Half-swording caps blade reach to 55%")

	# 5. Hardening bonus & Weapon Lodging (LodgedWeapon)
	var def_hardened: PenetrationResolver.DefenseParams = PenetrationResolver.DefenseParams.new()
	def_hardened.target_con = 20.0
	def_hardened.hardening_bonus = 40.0
	def_hardened.zone_name = AnatomyComponent.ZONE_CHEST
	var atk_lodge: PenetrationResolver.AttackParams = PenetrationResolver.AttackParams.new()
	atk_lodge.attacker_str = 20.0
	atk_lodge.weapon_base_penetration = 28.0 # 28 * 2^1.6 = 84.88 vs barrier ~76.8 -> depth ~8.0 (< bone_vessel 12) -> LODGED!
	atk_lodge.weapon_blade_length = 30.0
	atk_lodge.attack_type = PenetrationResolver.AttackType.THRUST
	atk_lodge.type_pierce_mult_override = 1.0
	var res_lodge: PenetrationResolver.ResolutionResult = PenetrationResolver.resolve(atk_lodge, def_hardened)
	_assert_true(res_lodge.skin_breached, "Blade breaches hardened skin")
	_assert_false(res_lodge.bone_vessel_breached, "Blade stopped inside hardened muscle before bone/organs")
	_assert_true(res_lodge.weapon_lodged, "Hardening traps penetrating blade as LodgedWeapon")

	# 6. Aura Burst (+1.8x to aura_pierce_bonus & aura_impact, forces guard break)
	var atk_aura: PenetrationResolver.AttackParams = PenetrationResolver.AttackParams.new()
	atk_aura.attacker_str = 10.0
	atk_aura.attacker_m_ctrl = 20.0
	atk_aura.weapon_base_penetration = 12.0
	atk_aura.aura_active = true
	atk_aura.aura_burst = false
	var res_aura_normal: PenetrationResolver.ResolutionResult = PenetrationResolver.resolve(atk_aura, bare_chest)

	atk_aura.aura_burst = true
	var res_aura_burst: PenetrationResolver.ResolutionResult = PenetrationResolver.resolve(atk_aura, bare_chest)
	_assert_true(res_aura_burst.aura_burst, "Aura Burst flagged active")
	_assert_true(res_aura_burst.guard_break_forced, "Aura Burst sets guard_break_forced")
	_assert_approx(res_aura_burst.aura_pierce_bonus, res_aura_normal.aura_pierce_bonus * PenetrationResolver.AURA_BURST_MULT, 1e-3, "Aura Burst multiplies aura_pierce_bonus by 1.8x")
	_assert_approx(res_aura_burst.aura_impact, res_aura_normal.aura_impact * PenetrationResolver.AURA_BURST_MULT, 1e-3, "Aura Burst multiplies aura_impact by 1.8x")

	# 7. Pure Blade Clash resolution (STR stagger, CTRL deflection counter, Aura vs non-Aura breakage)
	var clash_events: Array[Dictionary] = []
	var on_clash: Callable = func(d: Dictionary) -> void: clash_events.append(d)
	EventBus.blade_clashed.connect(on_clash)

	# 7a. STR dominance -> loser staggered & knocked back
	var ca: PenetrationResolver.ClashParams = PenetrationResolver.ClashParams.new()
	ca.strength = 30.0
	ca.control = 10.0
	ca.weapon_mass = 18.0
	var cb: PenetrationResolver.ClashParams = PenetrationResolver.ClashParams.new()
	cb.strength = 10.0
	cb.control = 10.0
	cb.weapon_mass = 8.0
	var clash_str: PenetrationResolver.ClashResult = PenetrationResolver.resolve_blade_clash(ca, cb, false, true)
	_assert_eq(clash_str.winner, 1, "Higher STR (30 vs 10) wins Blade Clash")
	_assert_true(clash_str.stagger_b_sec >= 0.6, "Blade Clash loser receives stagger")
	_assert_true(clash_str.knockback_b >= 80.0, "Blade Clash loser receives knockback")
	_assert_eq(clash_events.size(), 1, "EventBus.blade_clashed emitted")

	# 7b. CTRL dominance -> redirects opponent blade & opens counter window
	var cc_a: PenetrationResolver.ClashParams = PenetrationResolver.ClashParams.new()
	cc_a.strength = 15.0
	cc_a.control = 40.0
	var cc_b: PenetrationResolver.ClashParams = PenetrationResolver.ClashParams.new()
	cc_b.strength = 15.0
	cc_b.control = 15.0
	var clash_ctrl: PenetrationResolver.ClashResult = PenetrationResolver.resolve_blade_clash(cc_a, cc_b, false, false)
	_assert_eq(clash_ctrl.ctrl_deflect_winner, 1, "High CTRL (40 vs 15) deflects opponent blade aside")
	_assert_true(clash_ctrl.counter_window_sec > 0.0, "CTRL deflection opens counter-attack window")

	# 7c. Aura blade vs plain iron dagger -> iron dagger breaks, Aura blade intact!
	var aura_sword: WeaponData = gs_tpl.create_runtime_copy()
	var plain_dagger: WeaponData = (load("res://data/dagger.tres") as WeaponData).create_runtime_copy()
	var cd_a: PenetrationResolver.ClashParams = PenetrationResolver.ClashParams.new()
	cd_a.strength = 20.0
	cd_a.aura_active = true
	cd_a.m_ctrl = 25.0
	cd_a.weapon = aura_sword
	var cd_b: PenetrationResolver.ClashParams = PenetrationResolver.ClashParams.new()
	cd_b.strength = 20.0
	cd_b.aura_active = false
	cd_b.weapon = plain_dagger
	var clash_aura: PenetrationResolver.ClashResult = PenetrationResolver.resolve_blade_clash(cd_a, cd_b, true, false)
	_assert_true(clash_aura.weapon_b_broken, "Non-Aura dagger (durability 40) snaps against Aura blade")
	_assert_true(plain_dagger.is_broken(), "Runtime dagger durability reached 0")
	_assert_false(clash_aura.weapon_a_broken, "Aura blade remains unbroken")
	_assert_approx(aura_sword.durability, aura_sword.max_durability, 1e-4, "Aura blade takes zero durability loss in clash")

	EventBus.blade_clashed.disconnect(on_clash)


# ===========================================================================
# SUITE 16: v0.2 Anatomy (4 Layers, Arterial, Tendons, Dismemberment, Lodged, REG, Anti-Regen)
# ===========================================================================

func _test_v02_anatomy_reg_and_dismemberment() -> void:
	var severed_events: Array[StringName] = []
	var regrown_events: Array[StringName] = []
	var organ_rec_events: Array[StringName] = []
	var dropped_events: Array[StringName] = []
	var lodged_events: Array[StringName] = []
	var dislodged_events: Array[StringName] = []

	var on_sev: Callable = func(_e: Node, z: StringName, _a: Node) -> void: severed_events.append(z)
	var on_reg: Callable = func(_e: Node, z: StringName) -> void: regrown_events.append(z)
	var on_org: Callable = func(_e: Node, z: StringName) -> void: organ_rec_events.append(z)
	var on_drp: Callable = func(_e: Node, z: StringName, _w: WeaponData) -> void: dropped_events.append(z)
	var on_ldg: Callable = func(_e: Node, z: StringName, _w: WeaponData, _a: Node) -> void: lodged_events.append(z)
	var on_dis: Callable = func(_e: Node, z: StringName, _w: WeaponData) -> void: dislodged_events.append(z)

	EventBus.limb_severed.connect(on_sev)
	EventBus.limb_regrown.connect(on_reg)
	EventBus.organ_reconstructed.connect(on_org)
	EventBus.weapon_dropped.connect(on_drp)
	EventBus.weapon_lodged.connect(on_ldg)
	EventBus.weapon_dislodged.connect(on_dis)

	# 1. 4-layer BodyPart initialization & LimbStatus
	var h_stats: StatSheet = StatSheet.new()
	var h_anat: AnatomyComponent = AnatomyComponent.new(h_stats, 1.0, 100.0)
	var layers: Dictionary = h_anat.get_layer_integrities(AnatomyComponent.ZONE_RIGHT_ARM)
	_assert_approx(float(layers["skin"]), 100.0, 1e-4, "BodyPart skin layer starts at 100")
	_assert_approx(float(layers["muscle_tendon"]), 100.0, 1e-4, "BodyPart muscle_tendon layer starts at 100")
	_assert_approx(float(layers["bone"]), 100.0, 1e-4, "BodyPart bone layer starts at 100")
	_assert_approx(float(layers["vessels_organ"]), 100.0, 1e-4, "BodyPart vessels_organ layer starts at 100")
	_assert_eq(h_anat.get_limb_status(AnatomyComponent.ZONE_RIGHT_ARM), AnatomyComponent.LimbStatus.INTACT, "Limb starts INTACT")

	# 2. Arterial bleeding pulses above base rate (>=1.25x)
	var art_w: WoundResource = h_anat.apply_arterial_bleed(AnatomyComponent.ZONE_LEFT_ARM, 10.0)
	_assert_true(art_w != null and art_w.is_arterial, "Arterial bleed wound created")
	_assert_true(h_anat.has_arterial_bleeding(AnatomyComponent.ZONE_LEFT_ARM), "Zone tracks active arterial bleeding")
	var base_art: float = art_w.bleed_rate_ml_per_sec
	var eff_art_t0: float = art_w.get_effective_bleed_rate()
	_assert_true(eff_art_t0 >= base_art * 1.24, "Arterial effective bleed >= 1.25x base rate")
	h_anat.tick(0.35)
	var eff_art_t1: float = art_w.get_effective_bleed_rate()
	_assert_true(eff_art_t1 > eff_art_t0, "Arterial bleed pulses dynamically during tick")

	# 3. Tendon tear: Arm -> CRIPPLED, STR/CTRL penalty & weapon drop; Leg -> CRIPPLED & Limp
	var test_sword: WeaponData = (load("res://data/greatsword.tres") as WeaponData).create_runtime_copy()
	var arm_td: Dictionary = h_anat.apply_tendon_tear(AnatomyComponent.ZONE_RIGHT_ARM, 8.0, test_sword)
	_assert_true(bool(arm_td["weapon_dropped"]), "Arm tendon tear causes weapon drop")
	_assert_eq(h_anat.get_limb_status(AnatomyComponent.ZONE_RIGHT_ARM), AnatomyComponent.LimbStatus.CRIPPLED, "Torn arm becomes CRIPPLED")
	_assert_true(h_stats.get_stat(StatSheet.Stat.STR) < 10.0, "Arm tendon tear debuffs STR via StatSheet")
	_assert_true(h_stats.get_stat(StatSheet.Stat.CTRL) < 10.0, "Arm tendon tear debuffs CTRL via StatSheet")
	_assert_eq(dropped_events.size(), 1, "EventBus.weapon_dropped emitted on arm tendon tear")

	var leg_td: Dictionary = h_anat.apply_tendon_tear(AnatomyComponent.ZONE_LEFT_LEG, 8.0)
	_assert_true(bool(leg_td["causes_limp"]), "Leg tendon tear causes Limp")
	_assert_true(h_anat.has_limp, "AnatomyComponent tracks has_limp == true")
	_assert_true(h_stats.get_stat(StatSheet.Stat.SPD) < 10.0, "Leg tendon tear debuffs SPD")

	# 4. LodgedWeapon: attaches weapon, slows movement, blocks wound healing, extraction returns weapon + rip bleed
	var lodge_stats: StatSheet = StatSheet.new()
	var lodge_anat: AnatomyComponent = AnatomyComponent.new(lodge_stats, 1.0, 100.0)
	var dagger_inst: WeaponData = (load("res://data/dagger.tres") as WeaponData).create_runtime_copy()
	var lodged_w: WoundResource = lodge_anat.lodge_weapon(AnatomyComponent.ZONE_CHEST, dagger_inst, null, 7.0)
	_assert_true(lodged_w != null and lodge_anat.has_lodged_weapon(AnatomyComponent.ZONE_CHEST), "Weapon lodged in Chest")
	_assert_eq(lodged_events.size(), 1, "EventBus.weapon_lodged emitted")
	_assert_true(lodge_stats.get_stat(StatSheet.Stat.SPD) < 10.0, "Lodged weapon slows SPD via StatSheet")
	lodged_w.advance_healing(100.0, 10.0)
	_assert_false(lodged_w.is_healed(), "Lodged weapon wound does NOT heal while blade remains inside")
	var extr: Dictionary = lodge_anat.dislodge_weapon(AnatomyComponent.ZONE_CHEST, false)
	_assert_true(bool(extr["extracted"]), "dislodge_weapon extracts lodged weapon")
	_assert_eq(extr["weapon"], dagger_inst, "dislodge_weapon returns the exact lodged WeaponData instance")
	_assert_true(float(extr["ripped_bleed"]) > 0.0, "Rough extraction causes rip bleed")
	_assert_false(lodge_anat.has_lodged_weapon(AnatomyComponent.ZONE_CHEST), "Chest has no lodged weapon after extraction")
	_assert_eq(dislodged_events.size(), 1, "EventBus.weapon_dislodged emitted")

	# 5. Physical Dismemberment: Leg -> Prone, Neck -> Decapitation instant death
	var dism_stats: StatSheet = StatSheet.new()
	var dism_anat: AnatomyComponent = AnatomyComponent.new(dism_stats, 1.0, 100.0)
	var leg_sev: Dictionary = dism_anat.sever_limb(AnatomyComponent.ZONE_RIGHT_LEG)
	_assert_true(bool(leg_sev["severed"]), "RightLeg severed")
	_assert_eq(dism_anat.get_limb_status(AnatomyComponent.ZONE_RIGHT_LEG), AnatomyComponent.LimbStatus.SEVERED, "RightLeg status == SEVERED")
	_assert_true(dism_anat.is_prone, "Severing leg knocks target Prone")
	_assert_true(dism_anat.has_arterial_bleeding(AnatomyComponent.ZONE_RIGHT_LEG), "Severed stump causes arterial bleeding")
	_assert_eq(severed_events.size(), 1, "EventBus.limb_severed emitted")

	var neck_sev: Dictionary = dism_anat.sever_limb(AnatomyComponent.ZONE_NECK)
	_assert_true(bool(neck_sev["severed"]), "Neck severed (decapitation)")
	_assert_true(dism_anat.is_dead, "Decapitation causes instant death")
	_assert_eq(dism_anat.death_cause, "decapitation", "Death cause recorded as decapitation")

	# 6. Troll Berserker REG=160: rapid arterial hemostasis, limb regrowth (10..60s), STA/MP/calories burn!
	var troll_stats: StatSheet = StatSheet.new()
	troll_stats.awaken_mana(80.0, 80.0)
	troll_stats.set_base_stat(StatSheet.Stat.CON, 45.0)
	troll_stats.set_base_stat(StatSheet.Stat.STA, 80.0)
	troll_stats.set_base_stat(StatSheet.Stat.REG, 160.0)
	var troll_anat: AnatomyComponent = AnatomyComponent.new(troll_stats, 1.3, 100.0)

	troll_anat.sever_limb(AnatomyComponent.ZONE_RIGHT_ARM)
	_assert_true(troll_anat.is_limb_severed(AnatomyComponent.ZONE_RIGHT_ARM), "Troll RightArm severed")
	var sta_before: float = troll_anat.standalone_stamina
	var mp_before: float = troll_anat.standalone_mp
	var cal_before: float = troll_anat.calories

	# Tick 10s in 1s increments -> arterial stump bleeding stops in seconds, regrowth progresses
	for _i: int in range(10):
		troll_anat.tick(1.0)
	_assert_approx(troll_anat.get_total_bleed_rate(), 0.0, 1e-3, "Troll REG=160 clots arterial stump bleeding within seconds")
	_assert_true(troll_anat.standalone_stamina < sta_before, "Active REG consumes STA")
	_assert_true(troll_anat.standalone_mp < mp_before, "Magical REG (>50, awakened) consumes MP")
	_assert_true(troll_anat.calories < cal_before, "Active REG consumes calories")

	# Tick remaining regrowth time (~25 more seconds -> total 35s, inside 10..60s GDD spec!)
	for _i: int in range(30):
		troll_anat.tick(1.0)
	_assert_eq(troll_anat.get_limb_status(AnatomyComponent.ZONE_RIGHT_ARM), AnatomyComponent.LimbStatus.INTACT, "Troll REG=160 regrows severed arm completely within 10..60s")
	_assert_eq(regrown_events.size(), 1, "EventBus.limb_regrown emitted")
	_assert_approx(float(troll_anat.get_layer_integrities(AnatomyComponent.ZONE_RIGHT_ARM)["bone"]), 100.0, 1e-4, "Regrown arm restores all 4 tissue layers to 100%")

	# 7. Anti-Regen (burn / suppressing Aura) freezes clotting, healing & limb regrowth until expiry
	troll_anat.refill_regen_resources()
	troll_anat.sever_limb(AnatomyComponent.ZONE_LEFT_ARM)
	troll_anat.apply_burn_anti_regen(AnatomyComponent.ZONE_LEFT_ARM, 8.0)
	_assert_true(troll_anat.is_anti_regen_active(AnatomyComponent.ZONE_LEFT_ARM), "Anti-Regen burn active on LeftArm")
	var bleed_with_anti: float = troll_anat.get_total_bleed_rate()
	var regrow_before_anti: float = troll_anat.get_body_part(AnatomyComponent.ZONE_LEFT_ARM).regrowth_progress
	troll_anat.tick(4.0) # Still 4s left on Anti-Regen!
	_assert_approx(troll_anat.get_body_part(AnatomyComponent.ZONE_LEFT_ARM).regrowth_progress, regrow_before_anti, 1e-5, "Anti-Regen completely freezes limb regrowth")
	_assert_true(troll_anat.get_total_bleed_rate() > bleed_with_anti * 0.5, "Anti-Regen prevents REG clotting on suppressed stump")
	# Advance past Anti-Regen expiry -> REG resumes!
	troll_anat.tick(5.0)
	troll_anat.tick(5.0)
	_assert_true(troll_anat.get_body_part(AnatomyComponent.ZONE_LEFT_ARM).regrowth_progress > 0.0, "REG resumes limb regrowth after Anti-Regen expires")

	# 8. Resource Starvation pauses REG cleanly (STA == 0, MP == 0, calories == 0)
	var pause_stats: StatSheet = StatSheet.new()
	pause_stats.awaken_mana(50.0, 50.0)
	pause_stats.set_base_stat(StatSheet.Stat.REG, 160.0)
	var pause_anat: AnatomyComponent = AnatomyComponent.new(pause_stats, 1.0, 100.0)
	pause_anat.sever_limb(AnatomyComponent.ZONE_RIGHT_ARM)

	pause_anat.standalone_stamina = 0.0
	pause_anat.tick(2.0)
	_assert_eq(pause_anat.last_regen_paused_reason, "no_stamina", "REG pauses when STA == 0")
	_assert_approx(pause_anat.get_body_part(AnatomyComponent.ZONE_RIGHT_ARM).regrowth_progress, 0.0, 1e-5, "Zero regrowth progress at STA == 0")

	pause_anat.standalone_stamina = 200.0
	pause_anat.standalone_mp = 0.0
	pause_anat.tick(2.0)
	_assert_eq(pause_anat.last_regen_paused_reason, "no_mp", "Magical REG (>50) pauses when MP == 0")
	_assert_approx(pause_anat.get_body_part(AnatomyComponent.ZONE_RIGHT_ARM).regrowth_progress, 0.0, 1e-5, "Zero regrowth progress at MP == 0")

	pause_anat.standalone_mp = 500.0
	pause_anat.calories = 0.0
	pause_anat.tick(2.0)
	_assert_eq(pause_anat.last_regen_paused_reason, "no_calories", "REG pauses when calories == 0")
	_assert_approx(pause_anat.get_body_part(AnatomyComponent.ZONE_RIGHT_ARM).regrowth_progress, 0.0, 1e-5, "Zero regrowth progress at calories == 0")

	# 9. Organ Reconstruction at REG >= 400 (2..10s if Brain/SOUL intact; Brain destruction still fatal!)
	var demi_stats: StatSheet = StatSheet.new()
	demi_stats.awaken_mana(400.0, 400.0)
	demi_stats.set_all_base_stats(400.0, true)
	var demi_anat: AnatomyComponent = AnatomyComponent.new(demi_stats, 1.0, 100.0)
	# Destroy Heart (Chest -> 0%) while Brain (Head=100%) and SOUL=400 are intact
	demi_anat.apply_penetrating_hit(AnatomyComponent.ZONE_CHEST, 21.0, true)
	_assert_approx(demi_anat.get_organ_integrity(AnatomyComponent.ZONE_CHEST), 0.0, 1e-4, "Heart integrity dropped to 0%")
	_assert_false(demi_anat.is_dead, "REG=400 survives heart destruction while Brain & SOUL intact")
	for _i: int in range(6):
		demi_anat.tick(1.0)
	_assert_approx(demi_anat.get_organ_integrity(AnatomyComponent.ZONE_CHEST), 100.0, 1e-3, "REG=400 reconstructs Heart back to 100% within 2..10s")
	_assert_eq(organ_rec_events.size(), 1, "EventBus.organ_reconstructed emitted")

	# Destroying Brain (Head) is STILL fatal even at REG=400!
	demi_anat.apply_penetrating_hit(AnatomyComponent.ZONE_HEAD, 21.0, true)
	_assert_true(demi_anat.is_dead, "Destroying Brain (Head) is fatal even at REG=400")

	EventBus.limb_severed.disconnect(on_sev)
	EventBus.limb_regrown.disconnect(on_reg)
	EventBus.organ_reconstructed.disconnect(on_org)
	EventBus.weapon_dropped.disconnect(on_drp)
	EventBus.weapon_lodged.disconnect(on_ldg)
	EventBus.weapon_dislodged.disconnect(on_dis)
	h_anat.free()
	lodge_anat.free()
	dism_anat.free()
	troll_anat.free()
	pause_anat.free()
	demi_anat.free()


# ===========================================================================
# SUITE 17: v0.2 Step 2 - Warhammer, 3 Attacks, Feint, Sidestep, Half-swording,
#           Hardening, Live Blade Clash, Clinch, Wall Slam & PEACEFUL
# ===========================================================================

func _test_v02_step2_combat_clinch_and_wall_slam() -> void:
	SimulationClock.reset_defaults()
	WorldCalendar.reset_calendar(0)
	FloorLayerManager.reset(0)

	# 1. Heavy Warhammer resource constants (GDD 14.4)
	var hammer_tpl: WeaponData = load("res://data/warhammer.tres") as WeaponData
	_assert_true(hammer_tpl != null, "res://data/warhammer.tres loads cleanly")
	_assert_eq(hammer_tpl.weapon_id, &"warhammer", "Warhammer weapon_id == warhammer")
	_assert_approx(hammer_tpl.base_penetration, 16.0, 1e-4, "Warhammer base_penetration == 16.0")
	_assert_approx(hammer_tpl.blade_length, 34.0, 1e-4, "Warhammer blade_length == 34.0")
	_assert_approx(hammer_tpl.min_optimal_range, 16.0, 1e-4, "Warhammer min_optimal_range == 16.0")
	_assert_approx(hammer_tpl.edge_sharpness, 0.6, 1e-4, "Warhammer edge_sharpness == 0.6")
	_assert_approx(hammer_tpl.mass_factor, 36.0, 1e-4, "Warhammer mass_factor == 36.0")
	_assert_approx(hammer_tpl.vertical_reach, 0.9, 1e-4, "Warhammer vertical_reach == 0.9")
	_assert_approx(hammer_tpl.durability, 140.0, 1e-4, "Warhammer durability == 140.0")
	_assert_false(hammer_tpl.can_half_sword, "Warhammer cannot Half-sword")

	# 2. WeaponRaySweeper geometric segment intersection & Half-swording CTRL precision boost
	var cross_hit: Dictionary = WeaponRaySweeper.segments_intersect(Vector2(0.0, 0.0), Vector2(40.0, 0.0), Vector2(20.0, -20.0), Vector2(20.0, 20.0), 2.0)
	_assert_true(bool(cross_hit["intersects"]), "Crossing blade segments geometrically intersect")
	_assert_approx((cross_hit["point"] as Vector2).x, 20.0, 1e-3, "Crossing intersection X == 20")
	var miss_hit: Dictionary = WeaponRaySweeper.segments_intersect(Vector2(0.0, 0.0), Vector2(10.0, 0.0), Vector2(50.0, -10.0), Vector2(50.0, 10.0), 2.0)
	_assert_false(bool(miss_hit["intersects"]), "Distant segments do not clash")

	var prec_sheet: StatSheet = StatSheet.new()
	prec_sheet.awaken_mana(10.0, 10.0)
	prec_sheet.set_base_stat(StatSheet.Stat.STR, 20.0)
	prec_sheet.set_base_stat(StatSheet.Stat.CTRL, 20.0)
	var prec_normal: float = WeaponRaySweeper.get_effective_precision_radius_px(prec_sheet, PenetrationResolver.AttackType.SLASH, false)
	var prec_half: float = WeaponRaySweeper.get_effective_precision_radius_px(prec_sheet, PenetrationResolver.AttackType.THRUST, true)
	_assert_true(prec_half > prec_normal, "Half-swording + THRUST expands weak-point precision radius via +50% CTRL boost")

	# 3. Instantiate live TestArena with Player & Rank 1 Swordsman
	var arena_scene: PackedScene = load("res://scenes/test_arena.tscn") as PackedScene
	var arena: TestArena = arena_scene.instantiate() as TestArena
	add_child(arena)
	arena.set_all_enemies_ai_enabled(false)

	var player: PlayerController = arena.entities_container.get_node_or_null("Player") as PlayerController
	var rank1: EnemyDummy = arena.entities_container.get_node_or_null("Rank1Swordsman") as EnemyDummy
	_assert_true(player != null and rank1 != null, "Arena loaded Player and Rank1Swordsman")

	# 4. Feint (C) cancels WINDUP for STA without entering ACTIVE, scaling recovery speed by CTRL
	player.select_weapon_slot(1) # Greatsword
	player.refill_resources()
	_assert_true(player.start_attack(player.get_combat_origin() + Vector2(40.0, 0.0), PenetrationResolver.AttackType.SLASH), "Started SLASH WINDUP")
	_assert_eq(player.combat_state, CombatActor.CombatState.WINDUP, "In WINDUP before feint")
	var sta_pre_feint: float = player.current_stamina
	_assert_true(player.try_feint_cancel(), "Feint (C) cancels WINDUP")
	_assert_eq(player.combat_state, CombatActor.CombatState.RECOVERY, "Feint transitions straight to short RECOVERY (skipping ACTIVE)")
	_assert_true(player.current_stamina < sta_pre_feint, "Feint spends small STA")
	_assert_false(player.try_feint_cancel(), "Feint returns false outside WINDUP")
	player.step_combat_fsm(0.5)
	_assert_eq(player.combat_state, CombatActor.CombatState.IDLE, "Returned to IDLE after feint recovery")

	# 5. Micro-Sidestep (Space during WINDUP) moves actor WITHOUT interrupting WINDUP!
	player.refill_resources()
	player.global_position = Vector2(180.0, 200.0)
	player.start_attack(Vector2(240.0, 200.0), PenetrationResolver.AttackType.THRUST)
	_assert_eq(player.combat_state, CombatActor.CombatState.WINDUP, "Started THRUST WINDUP for sidestep test")
	var dodge_kind: StringName = player.start_sidestep_or_dash(Vector2(0.0, 1.0))
	_assert_eq(dodge_kind, &"sidestep", "Space during WINDUP triggers Micro-Sidestep (not Dash)")
	_assert_eq(player.combat_state, CombatActor.CombatState.WINDUP, "Micro-Sidestep does NOT cancel own WINDUP!")
	_assert_true(player.sidestep_timer > 0.0, "Sidestep timer active")
	var y_before_side: float = player.global_position.y
	player.move_with_substepping(player.sidestep_direction * CombatActor.BASE_SIDESTEP_SPEED_PX, 0.08, false, false)
	_assert_true(player.global_position.y > y_before_side + 15.0, "Micro-Sidestep shifts actor laterally during WINDUP")
	player.step_combat_fsm(1.0) # Finish swing cleanly
	_assert_eq(player.combat_state, CombatActor.CombatState.IDLE, "Attack completed cleanly after sidestep")

	# Outside WINDUP, Space triggers regular Dash
	var outside_kind: StringName = player.start_sidestep_or_dash(Vector2(1.0, 0.0))
	_assert_eq(outside_kind, &"dash", "Space outside WINDUP triggers full Dash")
	player.step_combat_fsm(1.0)

	# 6. Half-swording (Tab) removes Greatsword Dead Zone in close range (dist = 12 < 20)
	player.select_weapon_slot(1) # Greatsword (min_optimal_range=20, can_half_sword=true)
	player.stat_sheet.awaken_mana(20.0, 20.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.STR, 10.0)
	player.refill_resources()
	var r1_chest: HitboxZone = null
	for hz: HitboxZone in rank1.hitbox_zones:
		if hz.zone_name == AnatomyComponent.ZONE_CHEST:
			r1_chest = hz
			break
	_assert_true(r1_chest != null, "Found Rank 1 Chest HitboxZone")

	var hit_dead_zone: Dictionary = rank1.receive_melee_hit(
		player, r1_chest, player.equipped_weapon, false, 1.0, false,
		PenetrationResolver.AttackType.THRUST, 12.0, false, false
	)
	var res_dz: PenetrationResolver.ResolutionResult = hit_dead_zone["resolution"] as PenetrationResolver.ResolutionResult
	_assert_true(res_dz.in_dead_zone, "Greatsword at dist 12 (<20) triggers Dead Zone")
	_assert_approx(res_dz.dead_zone_mult, 0.30, 1e-4, "Dead Zone applies 0.30x multiplier")

	_assert_true(player.toggle_half_swording(), "Tab toggles Half-swording ON for Greatsword")
	rank1.revive_and_heal_all()
	var hit_half_sword: Dictionary = rank1.receive_melee_hit(
		player, r1_chest, player.equipped_weapon, false, 1.0, false,
		PenetrationResolver.AttackType.THRUST, 12.0, player.half_swording, false
	)
	var res_hs: PenetrationResolver.ResolutionResult = hit_half_sword["resolution"] as PenetrationResolver.ResolutionResult
	_assert_false(res_hs.in_dead_zone, "Half-swording eliminates Dead Zone at dist 12")
	_assert_true(res_hs.penetration > res_dz.penetration * 2.5, "Half-swording restores full thrust penetration up close")
	player.select_weapon_slot(2) # Warhammer (can_half_sword=false) auto-disables Half-swording
	_assert_false(player.half_swording, "Switching to Warhammer automatically turns OFF Half-swording")

	# 7. Aura Burst (R during WINDUP/ACTIVE) breaks active Block and burns 15 MP
	player.select_weapon_slot(0) # Dagger
	player.stat_sheet.awaken_mana(50.0, 25.0)
	player.refill_resources()
	var idle_r: Dictionary = player.handle_aura_or_burst_input()
	_assert_eq(String(idle_r["action"]), "toggle_aura", "R in IDLE toggles sustained Aura")
	_assert_true(player.aura_active, "Sustained Aura enabled")
	player.set_aura_active(false)

	player.start_attack(rank1.get_combat_origin(), PenetrationResolver.AttackType.SLASH)
	var mp_pre_burst: float = player.current_mp
	var burst_r: Dictionary = player.handle_aura_or_burst_input()
	_assert_eq(String(burst_r["action"]), "aura_burst", "R during WINDUP triggers Aura Burst")
	_assert_true(bool(burst_r["success"]), "Aura Burst succeeded")
	_assert_true(player.current_attack_aura_burst, "current_attack_aura_burst armed for contact")
	_assert_true(player.current_mp < mp_pre_burst, "Aura Burst spent extra MP")

	# Enemy actively blocking (facing attacker) is Guard-Broken by Aura Burst!
	rank1.revive_and_heal_all()
	rank1.aim_angle = (player.global_position - rank1.global_position).angle()
	rank1.is_blocking = true
	rank1.parry_window_timer = 0.0
	var burst_hit: Dictionary = rank1.receive_melee_hit(
		player, r1_chest, player.equipped_weapon, false, 1.0, false,
		PenetrationResolver.AttackType.SLASH, 24.0, false, player.current_attack_aura_burst
	)
	_assert_eq(String(burst_hit["outcome"]), "guard_break_hit", "Aura Burst smashes straight through enemy Block (guard_break_hit)")
	player.step_combat_fsm(1.0)

	# 8. Hardening (H) bounces weak blows with attacker stagger AND lodges mid-tier blades (LodgedWeapon) + E extraction!
	player.revive_and_heal_all()
	rank1.revive_and_heal_all()
	player.stat_sheet.set_mana_awakened(false)
	player.stat_sheet.set_all_base_stats(10.0, false)
	player.refill_resources()

	# 8a. Weak strike vs Hardened player -> bounce & attacker staggered!
	_assert_true(player.activate_hardening(), "H activates Hardening guard")
	_assert_true(player.is_hardening_active(), "Hardening active")
	var player_chest: HitboxZone = null
	for hz: HitboxZone in player.hitbox_zones:
		if hz.zone_name == AnatomyComponent.ZONE_CHEST:
			player_chest = hz
			break
	rank1.stat_sheet.set_all_base_stats(10.0, false)
	var bounce_hit: Dictionary = player.receive_melee_hit(
		rank1, player_chest, rank1.equipped_weapon, false, 1.0, false,
		PenetrationResolver.AttackType.SLASH, 22.0, false, false
	)
	_assert_eq(String(bounce_hit["outcome"]), "hardening_bounce", "Weak slash bounces off Hardening")
	_assert_eq(rank1.combat_state, CombatActor.CombatState.STAGGERED, "Hardening bounce staggers attacker")

	# 8b. Mid-strength thrust breaches skin but gets trapped in Hardened muscles -> LodgedWeapon + E extracts it!
	rank1.revive_and_heal_all()
	rank1.stat_sheet.awaken_mana(10.0, 10.0)
	rank1.stat_sheet.set_base_stat(StatSheet.Stat.STR, 18.0) # pen ~12 * 2.56 * 1.35 = 41.5 vs barrier 12 + 45 = 57 -> let's use STR 24 -> pen 66 vs barrier 57 -> depth 9 (<12) -> LODGED!
	rank1.stat_sheet.set_base_stat(StatSheet.Stat.STR, 24.0)
	player.hardening_timer = 0.5
	player.hardening_bonus_value = 45.0
	var lodge_hit: Dictionary = player.receive_melee_hit(
		rank1, player_chest, rank1.equipped_weapon, false, 1.0, false,
		PenetrationResolver.AttackType.THRUST, 22.0, false, false
	)
	_assert_eq(String(lodge_hit["outcome"]), "hardening_lodged", "Blade penetrating Hardened muscles triggers hardening_lodged")
	_assert_true(player.anatomy.has_lodged_weapon(AnatomyComponent.ZONE_CHEST), "Enemy blade physically lodged in player Chest")
	_assert_eq(rank1.combat_state, CombatActor.CombatState.STAGGERED, "Lodged weapon staggers attacker")
	var ext_res: Dictionary = player.try_extract_lodged_weapon(true)
	_assert_true(bool(ext_res["extracted"]), "Interact (E) extracts lodged weapon")
	_assert_false(player.anatomy.has_lodged_weapon(AnatomyComponent.ZONE_CHEST), "Chest cleared of lodged weapon after E extraction")

	# 9. Live Mid-Air Blade Clash between Player (Aura Greatsword) and Rank 1 (Iron Short Sword)!
	player.revive_and_heal_all()
	rank1.revive_and_heal_all()
	player.stat_sheet.awaken_mana(50.0, 40.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.STR, 40.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.CTRL, 40.0)
	player.refill_resources()
	player.select_weapon_slot(1) # Greatsword
	player.set_aura_active(true)
	rank1.stat_sheet.set_all_base_stats(10.0, false)
	rank1.equipped_weapon.durability = 40.0
	rank1.refill_resources()

	player.global_position = Vector2(200.0, 200.0)
	rank1.global_position = Vector2(254.0, 200.0)
	await get_tree().physics_frame

	# Put both fighters into ACTIVE simultaneously facing each other with THRUST/SLASH across mid-air centerline!
	player.start_attack(rank1.get_combat_origin(), PenetrationResolver.AttackType.THRUST)
	rank1.start_attack(player.get_combat_origin(), PenetrationResolver.AttackType.SLASH)
	player.state_timer = 0.001
	rank1.state_timer = 0.001
	player.step_combat_fsm(0.01) # Enters ACTIVE
	rank1.step_combat_fsm(0.01)  # Enters ACTIVE
	player.last_blade_clash_result = null
	rank1.last_blade_clash_result = null
	# Step both actors together in realistic 16ms frames until blades collide mid-air
	for _frame: int in range(8):
		player.step_combat_fsm(0.016)
		rank1.step_combat_fsm(0.016)
		if player.last_blade_clash_result != null:
			break
	_assert_true(player.last_blade_clash_result != null, "Live simultaneous swings geometrically trigger mid-air Blade Clash")
	if player.last_blade_clash_result != null:
		_assert_eq(player.last_blade_clash_result.winner, 1, "Stronger Player (STR=40 + Aura) wins live Blade Clash")
		_assert_true(player.last_blade_clash_result.weapon_b_broken, "Rank 1 plain iron sword snaps against Player's Aura Greatsword")
		_assert_true(rank1.equipped_weapon.is_broken(), "Rank 1 weapon durability reduced to 0")
		_assert_eq(rank1.combat_state, CombatActor.CombatState.STAGGERED, "Clash loser Rank 1 is STAGGERED")
	player.set_aura_active(false)
	player.step_combat_fsm(1.0)

	# 10. Clinch Sweep (Prone) + Clinch Throw ((STR/10)^2) -> Wall Slam & Wall Destruction + Floor +1 Drop!
	player.revive_and_heal_all()
	rank1.revive_and_heal_all()
	player.stat_sheet.awaken_mana(30.0, 10.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.M_CTRL, 10.0) # Exact circ bonus = 0 so effective STR == 25.0
	player.stat_sheet.set_base_stat(StatSheet.Stat.STR, 25.0) # (25/10)^2 = 6.25 -> throw impulse = 312.5
	player.refill_resources()

	var wood_wall: Vector2i = TestArena.WOOD_WALL_CELLS[1]
	_assert_true(arena.is_wall_solid_at(0, wood_wall), "Target wood wall intact before Clinch Throw")
	rank1.global_position = arena.cell_to_world_center(wood_wall) + Vector2(-42.0, 0.0)
	player.global_position = rank1.global_position + Vector2(-24.0, 0.0)
	await get_tree().physics_frame

	# 10a. Clinch Sweep -> Prone
	var sweep_res: Dictionary = player.perform_clinch_sweep(rank1)
	_assert_true(bool(sweep_res["success"]), "Clinch Sweep succeeds within clinch range")
	_assert_true(rank1.is_prone(), "Clinch Sweep knocks enemy into Prone state")
	_assert_false(rank1.can_act(), "Prone enemy cannot act until recovery")

	# 10b. Clinch Throw into Wood Wall -> Wall Slam fractures spine/back & smashes wall with enemy body!
	rank1.revive_and_heal_all()
	rank1.global_position = arena.cell_to_world_center(wood_wall) + Vector2(-38.0, 0.0)
	player.global_position = rank1.global_position + Vector2(-24.0, 0.0)
	await get_tree().physics_frame
	var slam_signals: Array[Dictionary] = []
	var on_slam: Callable = func(ent: Node, cell: Vector2i, imp: float, brk: bool) -> void:
		slam_signals.append({"entity": ent, "cell": cell, "impulse": imp, "broken": brk})
	EventBus.wall_slammed.connect(on_slam)

	var throw_res: Dictionary = player.perform_clinch_throw(rank1, Vector2.RIGHT)
	_assert_true(bool(throw_res["success"]), "Clinch Throw succeeds")
	_assert_approx(float(throw_res["impulse"]), 50.0 * pow(2.5, 2.0), 1.0, "Clinch Throw impulse scales by (STR/10)^2")
	var kb_report: Dictionary = rank1.step_knockback(0.35)
	EventBus.wall_slammed.disconnect(on_slam)

	_assert_true(bool(kb_report["wall_slammed"]), "Thrown enemy slams into wood wall (Wall Slam)")
	_assert_true(bool(kb_report["wall_broken"]), "High-impulse thrown body smashes wood wall tile!")
	_assert_false(arena.is_wall_solid_at(0, wood_wall), "Wood wall tile destroyed by Wall Slam")
	_assert_true(rank1.anatomy.has_fracture(AnatomyComponent.ZONE_CHEST), "Wall Slam inflicts spine/chest fracture bypassing front armor")
	_assert_eq(slam_signals.size(), 1, "EventBus.wall_slammed emitted")

	# 10c. Clinch Throw on Floor +1 over breakable floor drops enemy down to Floor 0 with leg fracture!
	rank1.revive_and_heal_all()
	var hole_cell: Vector2i = TestArena.BREAKABLE_FLOOR_RECT.position
	player.verticality.set_floor_level(1)
	player.verticality.set_height_z(0.0)
	rank1.verticality.set_floor_level(1)
	rank1.verticality.set_height_z(0.0)
	rank1.global_position = arena.cell_to_world_center(hole_cell) + Vector2(-30.0, 0.0)
	player.global_position = rank1.global_position + Vector2(-24.0, 0.0)
	await get_tree().physics_frame
	player.perform_clinch_throw(rank1, Vector2.RIGHT)
	var floor_kb: Dictionary = rank1.step_knockback(0.30)
	_assert_true(bool(floor_kb["fell_through_floor"]), "Thrown enemy on Floor +1 breaks/falls through floor hole")
	_assert_eq(rank1.get_floor_level(), 0, "Thrown enemy lands on Floor 0")
	_assert_true(rank1.anatomy.has_fracture(AnatomyComponent.ZONE_LEFT_LEG), "Thrown enemy fractures legs on Floor +1 -> 0 fall")

	# 11. G key helper SimulationClock.toggle_player_tempo() & PEACEFUL blocks wall ramming
	SimulationClock.reset_defaults()
	_assert_true(SimulationClock.is_peaceful(), "Reset starts in PEACEFUL 1.0x")
	_assert_true(SimulationClock.toggle_player_tempo(), "toggle_player_tempo() switches PEACEFUL -> COMBAT_OVERDRIVE")
	_assert_true(SimulationClock.is_combat_overdrive(), "Active COMBAT_OVERDRIVE after G")
	_assert_true(SimulationClock.toggle_player_tempo(), "toggle_player_tempo() switches back to PEACEFUL when no aggro")
	_assert_true(SimulationClock.is_peaceful(), "Back in PEACEFUL 1.0x")

	var intact_wood: Vector2i = TestArena.WOOD_WALL_CELLS[2]
	player.verticality.set_floor_level(0)
	player.stat_sheet.set_all_base_stats(500.0, true)
	player.global_position = arena.cell_to_world_center(intact_wood) + Vector2(-26.0, 0.0)
	await get_tree().physics_frame
	player.move_with_substepping(Vector2(CombatActor.BASE_RUN_SPEED_PX, 0.0), 0.12, false, true)
	_assert_true(arena.is_wall_solid_at(0, intact_wood), "In PEACEFUL 1.0x, STR=500 running never breaks wood wall")

	remove_child(arena)
	arena.queue_free()


# ===========================================================================
# SUITE 18: v0.2 Step 3 - SafeZone, 3 Enemies (Troll REG=160), Escape Cycle,
#           Severed Limbs, INT+TP Telegraphs & Game Feel
# ===========================================================================

func _test_v02_step3_arena_ai_and_game_feel() -> void:
	SimulationClock.reset_defaults()
	WorldCalendar.reset_calendar(0)
	FloorLayerManager.reset(0)

	var arena_scene: PackedScene = load("res://scenes/test_arena.tscn") as PackedScene
	var arena: TestArena = arena_scene.instantiate() as TestArena
	add_child(arena)
	arena.set_all_enemies_ai_enabled(false)

	var player: PlayerController = arena.entities_container.get_node_or_null("Player") as PlayerController
	var rank1: EnemyDummy = arena.entities_container.get_node_or_null("Rank1Swordsman") as EnemyDummy
	var troll: EnemyDummy = arena.entities_container.get_node_or_null("TrollBerserker") as EnemyDummy
	var rank6: EnemyDummy = arena.entities_container.get_node_or_null("Rank6Guard") as EnemyDummy

	# 1. SafeBarrierZone & all 3 enemies spawned cleanly
	_assert_true(arena.safe_barrier_zone != null, "TestArena has Floor0/SafeBarrierZone Area2D")
	_assert_true(arena.is_position_in_safe_zone(arena.cell_to_world_center(TestArena.SAFE_ZONE_RECT.position), 0), "SafeBarrierZone tile detected on Floor 0")
	_assert_false(arena.is_position_in_safe_zone(arena.cell_to_world_center(TestArena.SAFE_ZONE_RECT.position), 1), "SafeBarrierZone applies strictly to Floor 0")
	_assert_true(rank1 != null and troll != null and rank6 != null, "All 3 test enemies spawned (Rank 1, Troll Berserker, Rank 6 Guard)")

	# 2. Exact GDD 14.4 stats for Troll Berserker & Rank 6 Guard REG
	_assert_eq(troll.preset, EnemyDummy.EnemyPreset.TROLL_BERSERKER, "TrollBerserker preset == TROLL_BERSERKER")
	_assert_approx(troll.stat_sheet.get_stat(StatSheet.Stat.STR), 45.0, 1e-4, "Troll STR == 45")
	_assert_approx(troll.stat_sheet.get_stat(StatSheet.Stat.CON), 45.0, 1e-4, "Troll CON == 45")
	_assert_approx(troll.stat_sheet.get_stat(StatSheet.Stat.SPD), 25.0, 1e-4, "Troll SPD == 25")
	_assert_approx(troll.stat_sheet.get_stat(StatSheet.Stat.TP), 25.0, 1e-4, "Troll TP == 25")
	_assert_approx(troll.stat_sheet.get_stat(StatSheet.Stat.REG), 160.0, 1e-4, "Troll REG == 160")
	_assert_approx(troll.actor_size_mult, 1.3, 1e-4, "Troll size_mult == 1.3")
	_assert_approx(rank6.stat_sheet.get_stat(StatSheet.Stat.REG), 60.0, 1e-4, "Rank 6 Guard REG == 60 (GDD 14.4)")

	# 3. Segmented limb polygons + Physical Severed Limb spawn + Troll REG=160 regrowth + Anti-Regen
	_assert_eq(troll.limb_polygons.size(), 5, "Actor builds 5 procedural limb segments (Head, L/R Arms, L/R Legs)")
	_assert_true(troll.limb_polygons[AnatomyComponent.ZONE_RIGHT_ARM].visible, "Troll RightArm visual starts visible")
	var limbs_before: int = arena.severed_limb_nodes.size()
	var blood_before: int = arena.blood_decal_nodes.size()

	troll.anatomy.sever_limb(AnatomyComponent.ZONE_RIGHT_ARM, player)
	_assert_false(troll.limb_polygons[AnatomyComponent.ZONE_RIGHT_ARM].visible, "Severed RightArm immediately disappears from Troll model")
	_assert_eq(arena.severed_limb_nodes.size(), limbs_before + 1, "Physical severed limb Polygon2D spawned on TestArena")
	_assert_true(arena.blood_decal_nodes.size() > blood_before, "Blood pools spawned beneath severed limb")
	var spawned_limb: Node2D = arena.severed_limb_nodes[arena.severed_limb_nodes.size() - 1]
	_assert_eq(spawned_limb.z_index, 0, "Floor 0 severed limb sorts on floor_level * 100 (z=0)")
	_assert_true(player.get_active_camera_shake_offset().length() > 0.5, "Dismemberment triggers Camera Shake on player Camera2D")

	# Troll REG=160 stops arterial bleeding & regrows severed RightArm visually and anatomically!
	for _s: int in range(36):
		troll.tick_physiology(1.0, false)
	_assert_approx(troll.anatomy.get_total_bleed_rate(), 0.0, 1e-3, "Troll REG=160 halts arterial stump bleeding in seconds")
	_assert_eq(troll.anatomy.get_limb_status(AnatomyComponent.ZONE_RIGHT_ARM), AnatomyComponent.LimbStatus.INTACT, "Troll REG=160 regrows RightArm to INTACT")
	_assert_true(troll.limb_polygons[AnatomyComponent.ZONE_RIGHT_ARM].visible, "Regrown RightArm visual reappears on Troll model")

	# Anti-Regen burn freezes Troll regrowth on LeftArm
	troll.refill_resources()
	troll.anatomy.sever_limb(AnatomyComponent.ZONE_LEFT_ARM, player)
	troll.anatomy.apply_burn_anti_regen(AnatomyComponent.ZONE_LEFT_ARM, 10.0)
	troll.tick_physiology(4.0, false)
	_assert_approx(troll.anatomy.get_body_part(AnatomyComponent.ZONE_LEFT_ARM).regrowth_progress, 0.0, 1e-5, "Anti-Regen freezes Troll LeftArm regrowth")

	# 4. Escape AI Cycle: PATROL (1.0x) -> COMBAT (COMBAT_OVERDRIVE + G blocked) -> SEARCH (4s) -> PATROL (PEACEFUL)
	SimulationClock.reset_defaults()
	rank1.revive_and_heal_all()
	rank1.reset_aggro(0.0)
	rank1.ai_enabled = false # Step deterministically via step_ai_tick() after physics transform sync
	player.revive_and_heal_all()
	player.verticality.set_floor_level(0)
	player.verticality.set_height_z(0.0)

	# Position player cleanly in front of Rank 1 Swordsman (facing right, 54 px away, clear LOS)
	var wood_wall: Vector2i = TestArena.WOOD_WALL_CELLS[0]
	var wall_center: Vector2 = arena.cell_to_world_center(wood_wall)
	rank1.global_position = wall_center + Vector2(-90.0, 0.0)
	rank1.aim_angle = 0.0
	player.global_position = wall_center + Vector2(-36.0, 0.0)
	await get_tree().physics_frame

	_assert_eq(rank1.ai_state, EnemyDummy.AIState.PATROL, "Rank 1 starts in PATROL (1.0x)")
	_assert_true(SimulationClock.is_peaceful(), "Player starts in PEACEFUL before detection")
	var patrol_dt_troll: float = SimulationClock.get_enemy_action_delta(0.1, troll.stat_sheet.get_stat(StatSheet.Stat.SPD), true, troll.get_instance_id())
	_assert_approx(patrol_dt_troll, 0.1, 1e-4, "PATROL enemy (Troll SPD=25) ticks at strict 1.0x baseline")

	# 4a. Detection -> COMBAT + COMBAT_OVERDRIVE + G blocked!
	rank1.step_ai_tick(0.05, 0.05)
	_assert_eq(rank1.ai_state, EnemyDummy.AIState.COMBAT, "Spotting player transitions Rank 1 PATROL -> COMBAT")
	_assert_true(SimulationClock.is_combat_overdrive(), "Enemy aggro automatically triggers COMBAT_OVERDRIVE")
	_assert_false(SimulationClock.toggle_player_tempo(), "G toggle OFF blocked while Rank 1 is pursuing")
	var combat_dt_troll: float = SimulationClock.get_enemy_action_delta(0.1, troll.stat_sheet.get_stat(StatSheet.Stat.SPD), false, troll.get_instance_id())
	_assert_true(combat_dt_troll > patrol_dt_troll * 2.0, "COMBAT enemy (Troll SPD=25) accelerates to full SPD action delta")

	# 4b. Escape by breaking LOS behind solid wood wall -> COMBAT -> SEARCH (4.0s) -> PATROL (1.0x)!
	player.global_position = wall_center + Vector2(64.0, 0.0) # Opposite side of solid wall
	await get_tree().physics_frame
	rank1.step_ai_tick(0.05, 0.05)
	_assert_eq(rank1.ai_state, EnemyDummy.AIState.SEARCH, "Breaking LOS behind wall transitions COMBAT -> SEARCH")
	_assert_true(rank1.search_timer > 3.5, "SEARCH timer initialized to 4.0s")
	_assert_false(SimulationClock.toggle_player_tempo(), "G toggle OFF stays blocked during SEARCH")

	# Wait out 4.2s of SEARCH with no re-contact -> returns to PATROL (1.0x) and unlocks PEACEFUL!
	for _t: int in range(9):
		rank1.step_ai_tick(0.05, 0.5)
	_assert_eq(rank1.ai_state, EnemyDummy.AIState.PATROL, "Expiring SEARCH returns Rank 1 to PATROL (1.0x)")
	_assert_true(SimulationClock.is_peaceful(), "Clearing all pursuers restores PEACEFUL 1.0x")

	# 4c. Escape by switching floor_level (0 -> +1) -> SEARCH -> PATROL
	player.global_position = rank1.global_position + Vector2(40.0, 0.0)
	rank1.aim_angle = 0.0
	await get_tree().physics_frame
	rank1.step_ai_tick(0.05, 0.05)
	_assert_eq(rank1.ai_state, EnemyDummy.AIState.COMBAT, "Re-engaged Rank 1 on Floor 0")
	player.verticality.set_floor_level(1)
	rank1.step_ai_tick(0.05, 0.05)
	_assert_eq(rank1.ai_state, EnemyDummy.AIState.SEARCH, "Switching to Floor +1 breaks pursuit into SEARCH")
	for _t: int in range(9):
		rank1.step_ai_tick(0.05, 0.5)
	_assert_eq(rank1.ai_state, EnemyDummy.AIState.PATROL, "Floor escape completes SEARCH -> PATROL")

	# 4d. Escape by entering SafeBarrierZone -> instant reset to PATROL & PEACEFUL!
	player.verticality.set_floor_level(0)
	player.global_position = rank1.global_position + Vector2(40.0, 0.0)
	rank1.aim_angle = 0.0
	await get_tree().physics_frame
	rank1.step_ai_tick(0.05, 0.05)
	_assert_eq(rank1.ai_state, EnemyDummy.AIState.COMBAT, "Re-engaged Rank 1 before SafeZone test")
	player.global_position = arena.cell_to_world_center(TestArena.SAFE_ZONE_RECT.position)
	arena.notify_entity_entered_safe_zone(player)
	_assert_eq(rank1.ai_state, EnemyDummy.AIState.PATROL, "Entering SafeBarrierZone immediately resets enemy aggro to PATROL")
	_assert_true(SimulationClock.is_peaceful(), "Entering SafeBarrierZone restores PEACEFUL 1.0x")

	# 4e. Sensory Hearing (with cross-floor attenuation) & Blood Trail tracking
	var n_pos: Vector2 = Vector2(300.0, 300.0)
	arena.record_noise(n_pos, 0, 200.0, player)
	var heard_same_floor: Dictionary = arena.find_loudest_noise_for(n_pos + Vector2(150.0, 0.0), 0, rank1)
	var heard_upper_floor_far: Dictionary = arena.find_loudest_noise_for(n_pos + Vector2(150.0, 0.0), 1, rank1)
	var heard_upper_floor_near: Dictionary = arena.find_loudest_noise_for(n_pos + Vector2(80.0, 0.0), 1, rank1)
	_assert_false(heard_same_floor.is_empty(), "Noise within 200px heard on same floor")
	_assert_true(heard_upper_floor_far.is_empty(), "Noise at 150px attenuated across floors (200*0.55=110 < 150)")
	_assert_false(heard_upper_floor_near.is_empty(), "Loud noise at 80px penetrates to adjacent floor (80 <= 110)")

	arena.spawn_blood_decal(Vector2(260.0, 260.0), 0, Vector2.RIGHT, 1.0, true)
	var trail_hit: Dictionary = arena.find_recent_blood_trail(Vector2(220.0, 260.0), 0, 120.0)
	_assert_false(trail_hit.is_empty(), "SEARCH AI sensory query finds recent blood trail drop")

	# 5. Intention Reading Telegraphs (INT + TP): Colors, Dashed Feint, Speed Cutoff & INT>=300 Weak Points
	var novice_sheet: StatSheet = StatSheet.new() # INT=10, TP=10
	var duelist_sheet: StatSheet = StatSheet.new() # INT=20, TP=15
	duelist_sheet.awaken_mana(10.0, 10.0)
	duelist_sheet.set_base_stat(StatSheet.Stat.INT, 20.0)
	duelist_sheet.set_base_stat(StatSheet.Stat.TP, 15.0)
	var master_sheet: StatSheet = StatSheet.new() # INT=300, TP=50
	master_sheet.awaken_mana(100.0, 100.0)
	master_sheet.set_base_stat(StatSheet.Stat.INT, 300.0)
	master_sheet.set_base_stat(StatSheet.Stat.TP, 50.0)

	# Novice vs Rank 1 (SPD=10): reads attack colors, does not spot feint (INT<15)
	var tg_thrust: Dictionary = EnemyDummy.compute_telegraph_readability(novice_sheet, 10.0, PenetrationResolver.AttackType.THRUST, false)
	var tg_slash: Dictionary = EnemyDummy.compute_telegraph_readability(novice_sheet, 10.0, PenetrationResolver.AttackType.SLASH, false)
	var tg_blunt: Dictionary = EnemyDummy.compute_telegraph_readability(novice_sheet, 10.0, PenetrationResolver.AttackType.BLUNT, false)
	_assert_true(bool(tg_thrust["readable"]), "Novice reads Rank 1 THRUST")
	_assert_eq(tg_thrust["color"], EnemyDummy.COLOR_TELEGRAPH_THRUST, "THRUST telegraph color is red")
	_assert_eq(tg_slash["color"], EnemyDummy.COLOR_TELEGRAPH_SLASH, "SLASH telegraph color is orange")
	_assert_eq(tg_blunt["color"], EnemyDummy.COLOR_TELEGRAPH_BLUNT, "BLUNT telegraph color is violet-blue")

	var tg_novice_feint: Dictionary = EnemyDummy.compute_telegraph_readability(novice_sheet, 10.0, PenetrationResolver.AttackType.SLASH, true)
	_assert_false(bool(tg_novice_feint["dashed"]), "Novice (INT=10) does NOT detect enemy feint as dashed")

	# Duelist (INT=20, TP=15) vs Rank 1 feint -> dashed feint telegraph!
	var tg_duelist_feint: Dictionary = EnemyDummy.compute_telegraph_readability(duelist_sheet, 10.0, PenetrationResolver.AttackType.SLASH, true)
	_assert_true(bool(tg_duelist_feint["feint_detected"]) and bool(tg_duelist_feint["dashed"]), "High INT+TP detects enemy feint as dashed telegraph")

	# Novice (TP=10) vs Rank 6 Guard (SPD=100) -> unreadable gray!
	var tg_too_fast: Dictionary = EnemyDummy.compute_telegraph_readability(novice_sheet, 100.0, PenetrationResolver.AttackType.THRUST, true)
	_assert_false(bool(tg_too_fast["readable"]), "Novice (TP=10) cannot read Rank 6 Guard (SPD=100) attack type")
	_assert_eq(tg_too_fast["color"], EnemyDummy.COLOR_TELEGRAPH_UNREADABLE, "Unreadable fast strike renders neutral color")

	# Master (INT=300, TP=50) vs Rank 6 Guard (SPD=100) -> reads type, detects feint & highlights 1-px weak points!
	var tg_master: Dictionary = EnemyDummy.compute_telegraph_readability(master_sheet, 100.0, PenetrationResolver.AttackType.THRUST, true)
	_assert_true(bool(tg_master["readable"]) and bool(tg_master["dashed"]), "Master reads Rank 6 feint telegraph")
	_assert_true(bool(tg_master["highlight_weak_points"]), "INT >= 300 enables automatic 1-px weak-point highlight")

	# Live EnemyDummy TelegraphDrawer activates during WINDUP
	rank1.ai_enabled = false
	rank1.planned_feint_active = true
	rank1.start_attack(player.get_combat_origin(), PenetrationResolver.AttackType.THRUST)
	var live_tg: Dictionary = rank1.update_telegraph_visual(duelist_sheet)
	_assert_true(bool(live_tg["visible"]) and bool(live_tg["dashed"]), "Live EnemyDummy displays dashed THRUST feint telegraph during WINDUP")

	# 6. Game Feel: Sparks + Camera Shake decay + Respawn brings back all 3 enemies
	EventBus.request_sparks(Vector2(200.0, 200.0), 0, 0.0, Color("#FFE875"), 6)
	_assert_true(arena.active_spark_count >= 6, "Procedural sparks spawned on TestArena Effects layer")
	player.trigger_camera_shake(6.0, 0.10)
	_assert_true(player.get_active_camera_shake_offset().length() > 1.0, "Camera Shake offsets Camera2D")
	player._update_dynamic_camera(0.15)
	player._update_dynamic_camera(0.05)
	_assert_approx(player.get_active_camera_shake_offset().length(), 0.0, 1e-3, "Camera Shake smoothly returns offset to Vector2.ZERO")

	var respawned: Array[Node] = arena.respawn_test_dummies()
	_assert_eq(respawned.size(), 3, "respawn_test_dummies respawns all 3 enemies (Rank 1, Troll Berserker, Rank 6 Guard)")

	remove_child(arena)
	arena.queue_free()


# ===========================================================================
# SUITE 19: v0.2 Step 4 - DebugHUD v0.2 & Full Section 14.2 Definition of Done
# ===========================================================================

func _count_focusable_controls(node: Node) -> int:
	var count: int = 0
	if node is Control:
		var ctrl: Control = node as Control
		if ctrl.focus_mode != Control.FOCUS_NONE:
			count += 1
	for child: Node in node.get_children():
		count += _count_focusable_controls(child)
	return count


func _test_v02_step4_debug_hud_and_full_14_2_acceptance() -> void:
	SimulationClock.reset_defaults()
	WorldCalendar.reset_calendar(0)
	FloorLayerManager.reset(0)
	EventBus.set_debug_highlight_weak_points(false)
	EventBus.set_debug_anti_regen_attacks(false)

	var arena_scene: PackedScene = load("res://scenes/test_arena.tscn") as PackedScene
	var arena: TestArena = arena_scene.instantiate() as TestArena
	add_child(arena)
	arena.set_all_enemies_ai_enabled(false)

	var hud: DebugHUD = arena.get_node_or_null("DebugHUD") as DebugHUD
	var player: PlayerController = arena.entities_container.get_node_or_null("Player") as PlayerController
	var rank1: EnemyDummy = arena.entities_container.get_node_or_null("Rank1Swordsman") as EnemyDummy
	var troll: EnemyDummy = arena.entities_container.get_node_or_null("TrollBerserker") as EnemyDummy
	var rank6: EnemyDummy = arena.entities_container.get_node_or_null("Rank6Guard") as EnemyDummy
	_assert_true(hud != null and player != null and rank1 != null and troll != null and rank6 != null, "14.2 Arena loaded DebugHUD, Player & all 3 test enemies")

	# -----------------------------------------------------------------------
	# A. DebugHUD v0.2 Focus Safety, Click Pass-Through, Race Preset, INT=300,
	#    Stances, 4-Layer Anatomy, Anti-Regen Toggle, Heal All & Arena Reset
	# -----------------------------------------------------------------------
	_assert_eq(_count_focusable_controls(hud), 0, "ALL DebugHUD Controls have focus_mode == FOCUS_NONE (Space never triggers UI buttons)")
	_assert_eq(hud.telemetry_panel.mouse_filter, Control.MOUSE_FILTER_IGNORE, "TelemetryPanel passes combat clicks through")
	_assert_eq(hud.anatomy_panel.mouse_filter, Control.MOUSE_FILTER_IGNORE, "AnatomyPanel passes combat clicks through")
	_assert_eq(hud.debug_panel.mouse_filter, Control.MOUSE_FILTER_IGNORE, "DebugPanel background passes non-button combat clicks through")

	hud._refresh_all_views()
	_assert_true(hud.lbl_tempo.text.contains("PEACEFUL 1.0x"), "DebugHUD displays PEACEFUL 1.0x TempoMode")
	_assert_true(hud.lbl_tempo.text.contains("Aggro: 0"), "DebugHUD displays active_aggro_ids.size() == 0")
	_assert_true(hud.lbl_tempo.text.contains("R1:PATROL") and hud.lbl_tempo.text.contains("Tr:PATROL") and hud.lbl_tempo.text.contains("R6:PATROL"), "DebugHUD displays all 3 enemy AI states")

	# Race preset switcher: Human (REG<=12) <-> Troll (REG<=65, CON<=45)
	hud.set_player_base_stat(StatSheet.Stat.REG, 50.0)
	hud.set_player_base_stat(StatSheet.Stat.CON, 40.0)
	_assert_approx(player.stat_sheet.get_stat(StatSheet.Stat.REG), 12.0, 1e-4, "Human preset caps unawakened REG at 12")
	_assert_eq(hud.toggle_race_preset(), StatSheet.RacePreset.TROLL, "DebugHUD toggles race preset Human -> Troll")
	_assert_approx(player.stat_sheet.get_stat(StatSheet.Stat.REG), 50.0, 1e-4, "Troll preset allows unawakened REG up to 65")
	_assert_approx(player.stat_sheet.get_stat(StatSheet.Stat.CON), 40.0, 1e-4, "Troll preset allows unawakened CON up to 45")
	_assert_true(hud.btn_race_preset.text.contains("Тролль"), "Race button updates label to Troll")
	_assert_eq(hud.toggle_race_preset(), StatSheet.RacePreset.HUMAN, "DebugHUD toggles race preset Troll -> Human")
	hud.apply_stat_preset(10.0)

	# Quick INT=300 button for weak-point auto-highlight & Rank 6 telegraph reading
	hud.apply_int_300_preset()
	_assert_approx(player.stat_sheet.get_stat(StatSheet.Stat.INT), 300.0, 1e-4, "INT=300 quick preset sets INT == 300")
	_assert_true(player.stat_sheet.can_auto_highlight_weak_points(), "INT=300 enables automatic 1-px weak-point highlight")
	var tg_r6: Dictionary = EnemyDummy.compute_telegraph_readability(player.stat_sheet, 100.0, PenetrationResolver.AttackType.THRUST, true)
	_assert_true(bool(tg_r6["readable"]) and bool(tg_r6["dashed"]) and bool(tg_r6["highlight_weak_points"]), "INT=300 preset reads Rank 6 feints & highlights weak points")

	# Current stances & Anti-Regen attack toggle reflected in HUD
	player.select_weapon_slot(1) # Greatsword
	player.toggle_half_swording()
	player.activate_hardening()
	player.set_aura_active(true)
	hud.set_anti_regen_attacks(true)
	hud._refresh_all_views()
	_assert_true(EventBus.debug_anti_regen_attacks, "DebugHUD Anti-Regen toggle enables EventBus.debug_anti_regen_attacks")
	_assert_true(hud.lbl_weapon.text.contains("HS:ON") and hud.lbl_weapon.text.contains("Hrd:ON") and hud.lbl_weapon.text.contains("Aura:ON") and hud.lbl_weapon.text.contains("AR:ON"), "DebugHUD displays Half-swording, Hardening, Aura & Anti-Regen stances")
	hud.set_anti_regen_attacks(false)
	player.set_aura_active(false)
	player.toggle_half_swording()

	# 4 layers, SEVERED limb, LodgedWeapon, calories & Anti-Regen in Anatomy panel + Heal All limb reset
	player.anatomy.sever_limb(AnatomyComponent.ZONE_RIGHT_ARM, rank1)
	player.anatomy.lodge_weapon(AnatomyComponent.ZONE_CHEST, rank1.equipped_weapon, rank1)
	player.anatomy.apply_burn_anti_regen(AnatomyComponent.ZONE_RIGHT_ARM, 10.0)
	hud._refresh_all_views()
	_assert_eq(DebugHUD.get_zone_color(player.anatomy, AnatomyComponent.ZONE_RIGHT_ARM), DebugHUD.COLOR_ZONE_SEVERED, "Severed limb renders COLOR_ZONE_SEVERED on anatomy diagram")
	_assert_true(hud.lbl_player_limbs.text.contains("RArm:SEVERED"), "Anatomy panel displays SEVERED limb status")
	_assert_true(hud.lbl_player_layers.text.contains("4L Sk:"), "Anatomy panel displays 4-layer integrities")
	_assert_true(hud.lbl_player_res.text.contains("Cal:"), "Anatomy panel displays simplified REG calories pool")
	_assert_true(hud.lbl_player_wounds.text.contains("[LODGED") and hud.lbl_player_wounds.text.contains("[ANTI-REGEN"), "Anatomy panel displays LodgedWeapon & Anti-Regen flag")
	_assert_true(hud.lbl_event_log.text.contains("Anti-Regen"), "Event log updates on Anti-Regen / Dismemberment / LodgedWeapon")

	hud.heal_player_all()
	_assert_eq(player.anatomy.get_limb_status(AnatomyComponent.ZONE_RIGHT_ARM), AnatomyComponent.LimbStatus.INTACT, "Heal All resets SEVERED limb back to INTACT")
	_assert_true(player.limb_polygons[AnatomyComponent.ZONE_RIGHT_ARM].visible, "Heal All restores severed limb Polygon2D visibility")
	_assert_false(player.anatomy.has_lodged_weapon(), "Heal All clears LodgedWeapon")
	_assert_false(player.anatomy.is_anti_regen_active(), "Heal All clears Anti-Regen")

	# Arena Reset / Respawn button restores broken wall + broken Floor +1 tile + all 3 enemies
	var test_wood: Vector2i = TestArena.WOOD_WALL_CELLS[0]
	var test_floor1: Vector2i = TestArena.BREAKABLE_FLOOR_RECT.position
	arena.try_damage_wall_at(0, test_wood, 100.0, 1000.0, true)
	arena.try_break_floor_at(1, test_floor1, 100.0, true)
	_assert_false(arena.is_wall_solid_at(0, test_wood), "Wood wall broken prior to arena reset")
	hud.respawn_dummies()
	_assert_true(arena.is_wall_solid_at(0, test_wood), "DebugHUD Respawn/Reset restores broken wood wall")
	_assert_true(FloorLayerManager.has_floor_at(1, test_floor1), "DebugHUD Respawn/Reset restores broken Floor +1 tile")
	rank1 = arena.entities_container.get_node_or_null("Rank1Swordsman") as EnemyDummy
	troll = arena.entities_container.get_node_or_null("TrollBerserker") as EnemyDummy
	rank6 = arena.entities_container.get_node_or_null("Rank6Guard") as EnemyDummy
	_assert_true(rank1 != null and troll != null and rank6 != null, "DebugHUD Respawn/Reset creates fresh Rank 1, Troll & Rank 6")

	# -----------------------------------------------------------------------
	# B. Section 14.2 #1: STR=500, SPD=500 in PEACEFUL (1.0x) does NOT break walls,
	#    and patrolling mobs move strictly at 1.0x
	# -----------------------------------------------------------------------
	hud.apply_stat_preset(500.0)
	SimulationClock.set_tempo_mode(SimulationClock.TempoMode.PEACEFUL, true, "acceptance_test")
	SimulationClock.speed_regulator = 1.0
	player.verticality.set_floor_level(0)
	player.verticality.set_height_z(0.0)
	player.global_position = arena.cell_to_world_center(test_wood) + Vector2(-26.0, 0.0)
	await get_tree().physics_frame
	player.move_with_substepping(Vector2(CombatActor.BASE_RUN_SPEED_PX, 0.0), 0.14, false, true)
	_assert_true(arena.is_wall_solid_at(0, test_wood), "14.2#1: STR=500, SPD=500 running in PEACEFUL (1.0x) does NOT destroy wood wall")
	var r6_patrol_dt: float = SimulationClock.get_enemy_action_delta(0.1, rank6.stat_sheet.get_stat(StatSheet.Stat.SPD), true, rank6.get_instance_id())
	_assert_approx(r6_patrol_dt, 0.1, 1e-4, "14.2#1: Patrolling Rank 6 Guard (SPD=100) ticks strictly at 1.0x in PATROL")

	# -----------------------------------------------------------------------
	# C. Section 14.2 #2 & #3: Detection/Strike -> COMBAT_OVERDRIVE (G blocked),
	#    and Escape (Wall LOS Break / Floor +1 / SafeZone) -> SEARCH -> PATROL (1.0x)
	# -----------------------------------------------------------------------
	hud.apply_stat_preset(10.0)
	SimulationClock.reset_defaults()
	var wall_center: Vector2 = arena.cell_to_world_center(test_wood)
	rank1.global_position = wall_center + Vector2(-90.0, 0.0)
	rank1.aim_angle = 0.0
	player.global_position = wall_center + Vector2(-36.0, 0.0)
	await get_tree().physics_frame

	rank1.step_ai_tick(0.05, 0.05)
	hud._refresh_all_views()
	_assert_eq(rank1.ai_state, EnemyDummy.AIState.COMBAT, "14.2#2: Approaching enemy triggers COMBAT")
	_assert_true(SimulationClock.is_combat_overdrive(), "14.2#2: Enemy aggro auto-enables COMBAT_OVERDRIVE")
	_assert_false(SimulationClock.toggle_player_tempo(), "14.2#2: G cannot force PEACEFUL during active combat")
	_assert_true(hud.lbl_tempo.text.contains("COMBAT_OVERDRIVE") and hud.lbl_tempo.text.contains("Aggro: 1") and hud.lbl_tempo.text.contains("R1:COMBAT"), "DebugHUD live-tracks COMBAT_OVERDRIVE & Aggro: 1")
	var troll_combat_dt: float = SimulationClock.get_enemy_action_delta(0.1, troll.stat_sheet.get_stat(StatSheet.Stat.SPD), false, troll.get_instance_id())
	_assert_true(troll_combat_dt > 0.20, "14.2#2: Engaged enemy accelerates to full enemy.SPD")

	# Escape 1: Break LOS behind solid wall -> SEARCH (4s) -> PATROL (1.0x) -> PEACEFUL
	player.global_position = wall_center + Vector2(64.0, 0.0)
	await get_tree().physics_frame
	rank1.step_ai_tick(0.05, 0.05)
	hud._refresh_all_views()
	_assert_eq(rank1.ai_state, EnemyDummy.AIState.SEARCH, "14.2#3: Breaking LOS transitions COMBAT -> SEARCH")
	_assert_true(hud.lbl_tempo.text.contains("R1:SEARCH"), "DebugHUD displays R1:SEARCH during pursuit")
	for _s: int in range(9):
		rank1.step_ai_tick(0.05, 0.5)
	_assert_eq(rank1.ai_state, EnemyDummy.AIState.PATROL, "14.2#3: 4.0s SEARCH timeout returns enemy to PATROL (1.0x)")
	_assert_true(SimulationClock.is_peaceful(), "14.2#3: PEACEFUL 1.0x restored after escape")

	# Escape 2: Switch Floor 0 -> +1
	player.global_position = rank1.global_position + Vector2(40.0, 0.0)
	rank1.aim_angle = 0.0
	await get_tree().physics_frame
	rank1.step_ai_tick(0.05, 0.05)
	_assert_eq(rank1.ai_state, EnemyDummy.AIState.COMBAT, "14.2#3: Re-engaged before Floor +1 escape")
	player.verticality.set_floor_level(1)
	rank1.step_ai_tick(0.05, 0.05)
	_assert_eq(rank1.ai_state, EnemyDummy.AIState.SEARCH, "14.2#3: Moving to Floor +1 breaks pursuit into SEARCH")
	for _s: int in range(9):
		rank1.step_ai_tick(0.05, 0.5)
	_assert_eq(rank1.ai_state, EnemyDummy.AIState.PATROL, "14.2#3: Floor +1 escape finishes into PATROL (1.0x)")
	player.verticality.set_floor_level(0)

	# Escape 3: SafeBarrierZone
	player.global_position = rank1.global_position + Vector2(40.0, 0.0)
	rank1.aim_angle = 0.0
	await get_tree().physics_frame
	rank1.step_ai_tick(0.05, 0.05)
	_assert_eq(rank1.ai_state, EnemyDummy.AIState.COMBAT, "14.2#3: Re-engaged before SafeZone escape")
	player.global_position = arena.cell_to_world_center(TestArena.SAFE_ZONE_RECT.position)
	arena.notify_entity_entered_safe_zone(player)
	_assert_eq(rank1.ai_state, EnemyDummy.AIState.PATROL, "14.2#3: SafeBarrierZone instantly resets COMBAT -> PATROL")
	_assert_true(SimulationClock.is_peaceful(), "14.2#3: SafeBarrierZone unlocks PEACEFUL 1.0x")

	# -----------------------------------------------------------------------
	# D. Section 14.2 #4: Rank 6 Guard — Dagger SLASH bounces vs THRUST (Half-swording)
	#    in 1-px WP vs Warhammer BLUNT vs Aura Burst (+ Hitstop & Blood Spray)
	# -----------------------------------------------------------------------
	var blood_fx: Array[int] = [0]
	var on_blood_fx: Callable = func(_p: Vector2, _f: int, _d: Vector2, _a: float, _tr: bool) -> void:
		blood_fx[0] += 1
	EventBus.blood_effect_requested.connect(on_blood_fx)

	var r6_chest: HitboxZone = null
	var r6_head: HitboxZone = null
	for hz: HitboxZone in rank6.hitbox_zones:
		if hz.zone_name == AnatomyComponent.ZONE_CHEST:
			r6_chest = hz
		elif hz.zone_name == AnatomyComponent.ZONE_HEAD:
			r6_head = hz
	_assert_true(r6_chest != null and r6_head != null, "Found Rank 6 Guard Chest & Head HitboxZones")

	player.verticality.set_height_z(1.5)
	player.stat_sheet.set_all_base_stats(10.0, false)
	player.select_weapon_slot(0) # Dagger
	player.equipped_weapon.edge_sharpness = 1.0
	var slash_bounce: Dictionary = rank6.receive_melee_hit(
		player, r6_chest, player.equipped_weapon, false, 1.0, false,
		PenetrationResolver.AttackType.SLASH, 18.0, false, false
	)
	var slash_res: PenetrationResolver.ResolutionResult = slash_bounce["resolution"] as PenetrationResolver.ResolutionResult
	_assert_false(slash_res.penetrated, "14.2#4: Plain Dagger SLASH fails to penetrate Rank 6 Guard chest armor")
	_assert_true(player.equipped_weapon.edge_sharpness < 1.0, "14.2#4: Dagger dulls on Rank 6 Guard armor bounce")

	# Half-swording THRUST in close range (dist=14 < 20) into 1-px weak point penetrates with Hitstop & blood!
	rank6.revive_and_heal_all()
	player.stat_sheet.awaken_mana(50.0, 15.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.STR, 30.0)
	player.refill_resources()
	player.select_weapon_slot(1) # Greatsword
	player.toggle_half_swording()
	SimulationClock.hitstop_timer = 0.0
	blood_fx[0] = 0
	var wp_thrust: Dictionary = rank6.receive_melee_hit(
		player, r6_head, player.equipped_weapon, true, 1.0, true,
		PenetrationResolver.AttackType.THRUST, 14.0, player.half_swording, false
	)
	var wp_res: PenetrationResolver.ResolutionResult = wp_thrust["resolution"] as PenetrationResolver.ResolutionResult
	_assert_true(wp_res.penetrated and not wp_res.in_dead_zone, "14.2#4: Half-swording THRUST into 1-px weak point penetrates Rank 6 Guard up close")
	_assert_true(SimulationClock.is_in_hitstop(), "14.2#4: Weak-point penetration triggers tactile Hitstop")
	_assert_true(blood_fx[0] > 0, "14.2#4: Penetration emits directional blood splatter")
	player.toggle_half_swording()

	# Warhammer BLUNT breaks Rank 6 Guard bones through armor via blunt_impulse!
	rank6.revive_and_heal_all()
	player.stat_sheet.set_base_stat(StatSheet.Stat.STR, 55.0)
	player.select_weapon_slot(2) # Heavy Warhammer (mass_factor=36)
	SimulationClock.hitstop_timer = 0.0
	var blunt_hit: Dictionary = rank6.receive_melee_hit(
		player, r6_chest, player.equipped_weapon, false, 1.0, false,
		PenetrationResolver.AttackType.BLUNT, 24.0, false, false
	)
	var blunt_res: PenetrationResolver.ResolutionResult = blunt_hit["resolution"] as PenetrationResolver.ResolutionResult
	_assert_true(blunt_res.blunt_impulse >= 1000.0, "14.2#4: Heavy Warhammer BLUNT delivers massive blunt_impulse through armor")
	_assert_true(rank6.anatomy.has_fracture(AnatomyComponent.ZONE_CHEST), "14.2#4: Warhammer BLUNT fractures Rank 6 Guard ribs through plate armor")
	_assert_true(SimulationClock.is_in_hitstop(), "14.2#4: Heavy Warhammer fracture triggers Hitstop")

	# Aura Burst smashes through Rank 6 Guard's active Block (facing attacker) & penetrates!
	rank6.revive_and_heal_all()
	rank6.aim_angle = (player.global_position - rank6.global_position).angle()
	rank6.is_blocking = true
	rank6.parry_window_timer = 0.0
	player.stat_sheet.set_base_stat(StatSheet.Stat.STR, 60.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.M_CTRL, 60.0)
	player.select_weapon_slot(1) # Greatsword
	SimulationClock.hitstop_timer = 0.0
	blood_fx[0] = 0
	var burst_r6: Dictionary = rank6.receive_melee_hit(
		player, r6_chest, player.equipped_weapon, false, 1.0, true,
		PenetrationResolver.AttackType.THRUST, 32.0, false, true
	)
	_assert_eq(String(burst_r6["outcome"]), "guard_break_hit", "14.2#4: Aura Burst breaks Rank 6 Guard active Block")
	_assert_true((burst_r6["resolution"] as PenetrationResolver.ResolutionResult).penetrated, "14.2#4: Aura Burst penetrates Rank 6 Guard armor")
	_assert_true(SimulationClock.is_in_hitstop() and blood_fx[0] > 0, "14.2#4: Aura Burst triggers Hitstop & blood splatter")
	EventBus.blood_effect_requested.disconnect(on_blood_fx)

	# -----------------------------------------------------------------------
	# E. Section 14.2 #5: Blade Clash (Iron vs Aura break, STR -> Stagger,
	#    CTRL -> Counter Window) + Greatsword Dead Zone vs Half-swording
	# -----------------------------------------------------------------------
	# E1. Plain iron blade vs Aura blade (higher STR -> Stagger + break + HUD clash log)
	player.revive_and_heal_all()
	rank1.revive_and_heal_all()
	player.verticality.set_height_z(0.0)
	player.stat_sheet.awaken_mana(50.0, 40.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.STR, 45.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.CTRL, 20.0)
	player.select_weapon_slot(1) # Greatsword
	player.set_aura_active(true)
	rank1.stat_sheet.set_all_base_stats(10.0, false)
	rank1.equipped_weapon.durability = 40.0
	player.global_position = Vector2(200.0, 200.0)
	rank1.global_position = Vector2(254.0, 200.0)
	await get_tree().physics_frame

	player.start_attack(rank1.get_combat_origin(), PenetrationResolver.AttackType.THRUST)
	rank1.start_attack(player.get_combat_origin(), PenetrationResolver.AttackType.SLASH)
	player.state_timer = 0.001
	rank1.state_timer = 0.001
	player.step_combat_fsm(0.01)
	rank1.step_combat_fsm(0.01)
	player.last_blade_clash_result = null
	for _f: int in range(8):
		player.step_combat_fsm(0.016)
		rank1.step_combat_fsm(0.016)
		if player.last_blade_clash_result != null:
			break
	hud._refresh_all_views()
	_assert_true(player.last_blade_clash_result != null, "14.2#5: Simultaneous swings trigger Blade Clash")
	if player.last_blade_clash_result != null:
		_assert_true(player.last_blade_clash_result.weapon_b_broken, "14.2#5: Plain iron sword breaks against Aura blade")
		_assert_eq(rank1.combat_state, CombatActor.CombatState.STAGGERED, "14.2#5: Higher STR clash winner staggers loser")
		_assert_true(hud.lbl_clash_log.text.contains("A WIN") and hud.lbl_clash_log.text.contains("B:BRK"), "DebugHUD logs Blade Clash result & broken blade")
	player.set_aura_active(false)
	player.step_combat_fsm(1.0)

	# E2. Equal STR, higher CTRL -> opens counterattack window!
	player.revive_and_heal_all()
	rank1.revive_and_heal_all()
	player.stat_sheet.awaken_mana(10.0, 10.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.M_CTRL, 10.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.STR, 10.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.CTRL, 50.0)
	player.select_weapon_slot(0) # Dagger (comparable mass to Short Sword)
	rank1.stat_sheet.set_all_base_stats(10.0, false)
	player.global_position = Vector2(200.0, 200.0)
	rank1.global_position = Vector2(236.0, 200.0)
	await get_tree().physics_frame

	player.start_attack(rank1.get_combat_origin(), PenetrationResolver.AttackType.THRUST)
	rank1.start_attack(player.get_combat_origin(), PenetrationResolver.AttackType.SLASH)
	player.state_timer = 0.001
	rank1.state_timer = 0.001
	player.step_combat_fsm(0.01)
	rank1.step_combat_fsm(0.01)
	player.last_blade_clash_result = null
	player.counter_window_timer = 0.0
	for _f: int in range(8):
		player.step_combat_fsm(0.016)
		rank1.step_combat_fsm(0.016)
		if player.last_blade_clash_result != null:
			break
	_assert_true(player.last_blade_clash_result != null, "14.2#5: CTRL-advantage Blade Clash triggered")
	if player.last_blade_clash_result != null:
		_assert_true(player.last_blade_clash_result.ctrl_deflect_winner != 0, "14.2#5: Higher CTRL wins Blade Clash deflection")
		_assert_true(player.counter_window_timer > 0.2 and rank1.counter_window_timer <= 0.0, "14.2#5: Higher CTRL opens counterattack window strictly for Player (counter_window_timer > 0)")
	player.step_combat_fsm(1.0)

	# E3. Dead Zone: Greatsword penalized at dist 12 vs Dagger, fixed by Half-swording!
	var r1_chest: HitboxZone = null
	for hz: HitboxZone in rank1.hitbox_zones:
		if hz.zone_name == AnatomyComponent.ZONE_CHEST:
			r1_chest = hz
			break
	rank1.revive_and_heal_all()
	player.stat_sheet.set_base_stat(StatSheet.Stat.STR, 10.0)
	player.select_weapon_slot(0) # Dagger (min_optimal_range=0)
	var dz_dag: PenetrationResolver.ResolutionResult = rank1.receive_melee_hit(
		player, r1_chest, player.equipped_weapon, false, 1.0, false,
		PenetrationResolver.AttackType.THRUST, 12.0, false, false
	)["resolution"] as PenetrationResolver.ResolutionResult
	_assert_false(dz_dag.in_dead_zone, "14.2#5: Dagger has no Dead Zone at dist=12")

	rank1.revive_and_heal_all()
	player.select_weapon_slot(1) # Greatsword (min_optimal_range=20)
	var dz_gs_off: PenetrationResolver.ResolutionResult = rank1.receive_melee_hit(
		player, r1_chest, player.equipped_weapon, false, 1.0, false,
		PenetrationResolver.AttackType.THRUST, 12.0, false, false
	)["resolution"] as PenetrationResolver.ResolutionResult
	_assert_true(dz_gs_off.in_dead_zone and is_equal_approx(dz_gs_off.dead_zone_mult, 0.30), "14.2#5: Greatsword at dist=12 penalized by 0.30x Dead Zone")

	rank1.revive_and_heal_all()
	player.toggle_half_swording()
	var dz_gs_on: PenetrationResolver.ResolutionResult = rank1.receive_melee_hit(
		player, r1_chest, player.equipped_weapon, false, 1.0, false,
		PenetrationResolver.AttackType.THRUST, 12.0, player.half_swording, false
	)["resolution"] as PenetrationResolver.ResolutionResult
	_assert_false(dz_gs_on.in_dead_zone, "14.2#5: Half-swording removes Greatsword Dead Zone at dist=12")
	player.toggle_half_swording()

	# -----------------------------------------------------------------------
	# F. Section 14.2 #6: Hardening (H) -> LodgedWeapon & Heavy Warhammer BLUNT
	#    -> Wall Slam + Wall Break with Enemy Body + Floor +1 Drop
	# -----------------------------------------------------------------------
	player.revive_and_heal_all()
	rank1.revive_and_heal_all()
	player.stat_sheet.set_mana_awakened(false)
	player.stat_sheet.set_all_base_stats(10.0, false)
	player.refill_resources()
	player.hardening_timer = 0.5
	player.hardening_bonus_value = 45.0
	var p_chest: HitboxZone = null
	for hz: HitboxZone in player.hitbox_zones:
		if hz.zone_name == AnatomyComponent.ZONE_CHEST:
			p_chest = hz
			break
	rank1.stat_sheet.awaken_mana(10.0, 10.0)
	rank1.stat_sheet.set_base_stat(StatSheet.Stat.STR, 24.0)
	var harden_lodge: Dictionary = player.receive_melee_hit(
		rank1, p_chest, rank1.equipped_weapon, false, 1.0, false,
		PenetrationResolver.AttackType.THRUST, 22.0, false, false
	)
	_assert_eq(String(harden_lodge["outcome"]), "hardening_lodged", "14.2#6: Hardening (H) traps enemy blade in hardened muscles (LodgedWeapon)")
	_assert_true(player.anatomy.has_lodged_weapon(AnatomyComponent.ZONE_CHEST), "14.2#6: Enemy blade physically lodged in player Chest")

	# Heavy Warhammer BLUNT slams enemy into wood wall -> Wall Slam + Wall Destruction!
	player.revive_and_heal_all()
	rank1.revive_and_heal_all()
	rank1.stat_sheet.set_mana_awakened(false)
	rank1.stat_sheet.set_all_base_stats(10.0, false)
	player.stat_sheet.awaken_mana(50.0, 10.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.M_CTRL, 10.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.STR, 35.0)
	player.select_weapon_slot(2) # Heavy Warhammer (mass=36 -> massive wall_slam_impulse!)
	var slam_wall: Vector2i = TestArena.WOOD_WALL_CELLS[1]
	_assert_true(arena.is_wall_solid_at(0, slam_wall), "Target wood wall intact before Warhammer Wall Slam")
	rank1.global_position = arena.cell_to_world_center(slam_wall) + Vector2(-40.0, 0.0)
	player.global_position = rank1.global_position + Vector2(-28.0, 0.0)
	await get_tree().physics_frame

	rank1.receive_melee_hit(
		player, r1_chest, player.equipped_weapon, false, 1.0, false,
		PenetrationResolver.AttackType.BLUNT, 28.0, false, false
	)
	var hammer_kb: Dictionary = rank1.step_knockback(0.35)
	hud._refresh_all_views()
	_assert_true(bool(hammer_kb["wall_slammed"]), "14.2#6: Heavy Warhammer BLUNT triggers Wall Slam")
	_assert_true(bool(hammer_kb["wall_broken"]), "14.2#6: Wall Slam smashes wood wall with enemy body")
	_assert_false(arena.is_wall_solid_at(0, slam_wall), "14.2#6: Wood wall tile destroyed by enemy body impact")
	_assert_true(hud.lbl_event_log.text.contains("WallSlam"), "DebugHUD logs Wall Slam event")

	# -----------------------------------------------------------------------
	# G. Section 14.2 #7: Troll Berserker (REG=160) stops bleeding & regrows arm
	#    (spending STA/MP/calories) UNTIL hit with DebugHUD Anti-Regen mode!
	# -----------------------------------------------------------------------
	troll.revive_and_heal_all()
	var sta_before: float = troll.current_stamina
	var mp_before: float = troll.current_mp
	var cal_before: float = troll.anatomy.calories
	troll.anatomy.sever_limb(AnatomyComponent.ZONE_RIGHT_ARM, player)
	_assert_true(troll.anatomy.get_total_bleed_rate() > 0.0, "14.2#7: Severed Troll arm initially bleeds arterially")
	for _t: int in range(36):
		troll.tick_physiology(1.0, false)
	_assert_approx(troll.anatomy.get_total_bleed_rate(), 0.0, 1e-3, "14.2#7: Troll REG=160 stops bleeding in seconds")
	_assert_eq(troll.anatomy.get_limb_status(AnatomyComponent.ZONE_RIGHT_ARM), AnatomyComponent.LimbStatus.INTACT, "14.2#7: Troll REG=160 regrows severed RightArm to INTACT")
	_assert_true(troll.limb_polygons[AnatomyComponent.ZONE_RIGHT_ARM].visible, "14.2#7: Regrown Troll arm visual reappears")
	var spent_energy: bool = (troll.current_stamina < sta_before) or (troll.current_mp < mp_before) or (troll.anatomy.calories < cal_before)
	_assert_true(spent_energy, "14.2#7: Troll REG consumes STA/MP/calories during regrowth")

	# Now enable DebugHUD Anti-Regen toggle -> live player sweep hit freezes Troll regrowth!
	troll.refill_resources()
	troll.anatomy.sever_limb(AnatomyComponent.ZONE_LEFT_ARM, player)
	hud.set_anti_regen_attacks(true)
	player.stat_sheet.set_base_stat(StatSheet.Stat.STR, 40.0)
	player.select_weapon_slot(0) # Dagger
	player.global_position = troll.global_position + Vector2(-24.0, 0.0)
	await get_tree().physics_frame
	player.start_attack(troll.get_combat_origin(), PenetrationResolver.AttackType.THRUST)
	player.step_combat_fsm(0.60)
	_assert_true(troll.anatomy.is_anti_regen_active(), "14.2#7: Live player hit with DebugHUD Anti-Regen toggle applies Anti-Regen to Troll")

	# Also verify 1-click DebugHUD test burn button freezes severed LeftArm regrowth completely
	_assert_true(hud.apply_test_anti_regen_to_target(12.0), "DebugHUD 1-click Anti-Regen burn applies to Troll target")
	var prog_before_freeze: float = troll.anatomy.get_body_part(AnatomyComponent.ZONE_LEFT_ARM).regrowth_progress
	troll.tick_physiology(4.0, false)
	_assert_approx(troll.anatomy.get_body_part(AnatomyComponent.ZONE_LEFT_ARM).regrowth_progress, prog_before_freeze, 1e-5, "14.2#7: Anti-Regen completely freezes Troll LeftArm regrowth over 4s")
	hud.set_anti_regen_attacks(false)

	remove_child(arena)
	arena.queue_free()
	EventBus.set_debug_highlight_weak_points(false)
	EventBus.set_debug_anti_regen_attacks(false)


# ===========================================================================
# SUITE 20: v0.2 Combat Balance Fixes (Kinetic, Starter Weapons, Blunt
#           Lethality & Damping, Aura Economy, Dead Zone Contact, Clinch
#           Contest & Subjective Status Timers)
# ===========================================================================

func _test_v02_combat_balance_fixes() -> void:
	SimulationClock.reset_defaults()
	WorldCalendar.reset_calendar(0)
	FloorLayerManager.reset(0)
	EventBus.set_debug_highlight_weak_points(false)
	EventBus.set_debug_anti_regen_attacks(false)

	var arena_scene: PackedScene = load("res://scenes/test_arena.tscn") as PackedScene
	var arena: TestArena = arena_scene.instantiate() as TestArena
	add_child(arena)
	arena.set_all_enemies_ai_enabled(false)

	var player: PlayerController = arena.entities_container.get_node_or_null("Player") as PlayerController
	var rank1: EnemyDummy = arena.entities_container.get_node_or_null("Rank1Swordsman") as EnemyDummy
	var troll: EnemyDummy = arena.entities_container.get_node_or_null("TrollBerserker") as EnemyDummy
	var rank6: EnemyDummy = arena.entities_container.get_node_or_null("Rank6Guard") as EnemyDummy
	_assert_true(player != null and rank1 != null and troll != null and rank6 != null, "Balance arena loaded all actors")

	# -----------------------------------------------------------------------
	# 1. No WASD kin_mult exploit + TempoMode/speed_regulator/tp_penalty + AI symmetry
	# -----------------------------------------------------------------------
	player.stat_sheet.awaken_mana(100.0, 10.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.M_CTRL, 10.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.STR, 100.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.SPD, 100.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.TP, 100.0)
	player.refill_resources()

	# 1a. In PEACEFUL (1.0x), even SPD=100 running OR dashing stays <= 1.35x (never 100x!)
	SimulationClock.set_tempo_mode(SimulationClock.TempoMode.PEACEFUL, true, "balance_test")
	var peaceful_run_kin: float = player.get_kinetic_mult(CombatActor.BASE_RUN_SPEED_PX, false, 1.0)
	var peaceful_dash_kin: float = player.get_kinetic_mult(CombatActor.BASE_DASH_SPEED_PX, true, 1.0)
	_assert_true(peaceful_run_kin <= 1.20, "PEACEFUL run kin_mult <= 1.20 (got %.2f)" % peaceful_run_kin)
	_assert_true(peaceful_dash_kin <= 1.35, "PEACEFUL dash kin_mult <= 1.35 (got %.2f)" % peaceful_dash_kin)

	# 1b. In COMBAT_OVERDRIVE, normal WASD run (220 px/s, not dashing) stays <= 1.35x ->
	#     Dagger at STR=100, SPD=100 running MUST NOT penetrate Rank 6 Guard chest (barrier ~= 1247)!
	SimulationClock.set_tempo_mode(SimulationClock.TempoMode.COMBAT_OVERDRIVE, true, "balance_test")
	SimulationClock.speed_regulator = 1.0
	var overdrive_run_kin: float = player.get_kinetic_mult(CombatActor.BASE_RUN_SPEED_PX, false, 1.0)
	_assert_true(overdrive_run_kin >= 1.15 and overdrive_run_kin <= 1.35, "OVERDRIVE WASD run kin_mult bounded in [1.15, 1.35] (got %.2f)" % overdrive_run_kin)

	var r6_chest: HitboxZone = null
	for hz: HitboxZone in rank6.hitbox_zones:
		if hz.zone_name == AnatomyComponent.ZONE_CHEST:
			r6_chest = hz
			break
	player.select_weapon_slot(0) # Dagger (base_pen=12)
	var run_dagger_r6: Dictionary = rank6.receive_melee_hit(
		player, r6_chest, player.equipped_weapon, false, overdrive_run_kin, false,
		PenetrationResolver.AttackType.SLASH, 18.0, false, false
	)
	_assert_false((run_dagger_r6["resolution"] as PenetrationResolver.ResolutionResult).penetrated, "STR=100, SPD=100 WASD-running Dagger does NOT penetrate Rank 6 Guard body")

	# 1c. speed_regulator & tp_penalty_mult scale dash kin_mult; full supersonic dash reaches (SPD/10)^2
	var full_dash_kin: float = player.get_kinetic_mult(CombatActor.BASE_DASH_SPEED_PX, true, 1.0)
	_assert_approx(full_dash_kin, 100.0, 0.5, "Full COMBAT_OVERDRIVE dash at SPD=100 reaches (SPD/10)^2 == 100x")
	SimulationClock.speed_regulator = 0.05 # eff_spd = 5 <= 10
	var reg_dash_kin: float = player.get_kinetic_mult(CombatActor.BASE_DASH_SPEED_PX, true, 1.0)
	_assert_true(reg_dash_kin <= 1.35, "Low speed_regulator (0.05) caps dash kin_mult <= 1.35x")
	SimulationClock.speed_regulator = 1.0
	player.stat_sheet.set_base_stat(StatSheet.Stat.TP, 5.0) # tp_penalty_mult = 0.5 -> eff_spd = 50 -> 25x
	var low_tp_dash_kin: float = player.get_kinetic_mult(CombatActor.BASE_DASH_SPEED_PX, true, 1.0)
	_assert_approx(low_tp_dash_kin, 25.0, 0.5, "TP=5 penalty (0.5x) cuts SPD=100 dash kin_mult from 100x down to 25x")
	player.stat_sheet.set_base_stat(StatSheet.Stat.TP, 100.0)

	# 1d. Approach inertia symmetry: charging EnemyDummy retains momentum when starting attack!
	rank1.revive_and_heal_all()
	rank1.ai_state = EnemyDummy.AIState.COMBAT
	rank1.move_with_substepping(Vector2(CombatActor.BASE_RUN_SPEED_PX * 0.85, 0.0), 0.05, false, false)
	rank1.current_move_velocity = Vector2.ZERO # Simulates AI stopping right before swing!
	rank1.start_attack(rank1.get_combat_origin() + Vector2(30.0, 0.0), PenetrationResolver.AttackType.SLASH)
	_assert_true(rank1._attack_launch_velocity.length() > 150.0, "Charging AI retains approach velocity through attack launch")
	var ai_kin: float = rank1.get_kinetic_mult(rank1._attack_launch_velocity.length(), false, 1.0)
	_assert_true(ai_kin > 1.10, "Charging AI receives symmetric momentum bonus (> 1.10x)")
	rank1.ai_state = EnemyDummy.AIState.PATROL

	# -----------------------------------------------------------------------
	# 2. Starter Weapon Balance at STR=10 vs Bare Human CON=10 (barrier=12, bone=100)
	# -----------------------------------------------------------------------
	player.revive_and_heal_all()
	player.stat_sheet.set_mana_awakened(false)
	player.stat_sheet.set_all_base_stats(10.0, false)
	player.refill_resources()

	var r1_chest: HitboxZone = null
	var r1_head: HitboxZone = null
	var r1_neck: HitboxZone = null
	var r1_stomach: HitboxZone = null
	for hz: HitboxZone in rank1.hitbox_zones:
		if hz.zone_name == AnatomyComponent.ZONE_CHEST:
			r1_chest = hz
		elif hz.zone_name == AnatomyComponent.ZONE_HEAD:
			r1_head = hz
		elif hz.zone_name == AnatomyComponent.ZONE_NECK:
			r1_neck = hz
		elif hz.zone_name == AnatomyComponent.ZONE_STOMACH:
			r1_stomach = hz
	_assert_true(r1_chest != null and r1_head != null and r1_neck != null and r1_stomach != null, "Found Rank 1 Chest/Head/Neck/Stomach zones")

	# 2a. Dagger SLASH (10 vs 10): scratches bare skin (depth 1.0..2.5), THRUST cuts deeper
	rank1.revive_and_heal_all()
	player.select_weapon_slot(0) # Dagger
	var dag_slash: Dictionary = rank1.receive_melee_hit(
		player, r1_chest, player.equipped_weapon, false, 1.0, false,
		PenetrationResolver.AttackType.SLASH, 16.0, false, false
	)
	var dag_slash_res: PenetrationResolver.ResolutionResult = dag_slash["resolution"] as PenetrationResolver.ResolutionResult
	_assert_true(dag_slash_res.penetrated and dag_slash_res.effective_depth >= 1.0 and dag_slash_res.effective_depth <= 2.5, "10v10 Dagger SLASH scratches bare skin (depth=%.2f in [1.0, 2.5])" % dag_slash_res.effective_depth)

	rank1.revive_and_heal_all()
	var dag_thrust: Dictionary = rank1.receive_melee_hit(
		player, r1_chest, player.equipped_weapon, false, 1.0, false,
		PenetrationResolver.AttackType.THRUST, 16.0, false, false
	)
	var dag_thrust_res: PenetrationResolver.ResolutionResult = dag_thrust["resolution"] as PenetrationResolver.ResolutionResult
	_assert_true(dag_thrust_res.effective_depth > dag_slash_res.effective_depth * 2.0, "10v10 Dagger THRUST cuts noticeably deeper than SLASH")

	# 2b. Warhammer BLUNT (10 vs 10): fractures bare human bone + shock, yet Rank 6 stays tough below STR=40
	rank1.revive_and_heal_all()
	player.select_weapon_slot(2) # Heavy Warhammer
	var wh_10v10: Dictionary = rank1.receive_melee_hit(
		player, r1_chest, player.equipped_weapon, false, 1.0, false,
		PenetrationResolver.AttackType.BLUNT, 22.0, false, false
	)
	_assert_true(rank1.anatomy.has_fracture(AnatomyComponent.ZONE_CHEST), "10v10 Warhammer BLUNT fractures bare human ribs")
	_assert_true(rank1.anatomy.shock_level >= 30.0, "10v10 Warhammer BLUNT inflicts real shock/concussion (%.1f%%)" % rank1.anatomy.shock_level)
	_assert_false(rank1.anatomy.is_dead, "Single 10v10 Warhammer Chest hit fractures without instant kill")

	rank6.revive_and_heal_all()
	player.verticality.set_height_z(1.5)
	player.stat_sheet.awaken_mana(10.0, 10.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.M_CTRL, 10.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.STR, 40.0)
	rank6.receive_melee_hit(
		player, r6_chest, player.equipped_weapon, false, 1.0, false,
		PenetrationResolver.AttackType.BLUNT, 24.0, false, false
	)
	_assert_false(rank6.anatomy.has_fracture(AnatomyComponent.ZONE_CHEST), "Rank 6 Guard plate cushion + ManaSkin + CON resists STR=40 Warhammer fracture")
	_assert_true(rank6.anatomy.shock_level > 0.0, "Near-threshold heavy Warhammer hit still causes concussive rattle shock")
	player.verticality.set_height_z(0.0)

	# 2c. Greatsword THRUST (10 vs 10): heavy deep wound to normal Chest (NO 1-shot!), 1-shot strictly on 1-px Weak Point
	player.stat_sheet.set_mana_awakened(false)
	player.stat_sheet.set_all_base_stats(10.0, false)
	player.select_weapon_slot(1) # Greatsword
	rank1.revive_and_heal_all()
	var gs_chest: Dictionary = rank1.receive_melee_hit(
		player, r1_chest, player.equipped_weapon, false, 1.0, false,
		PenetrationResolver.AttackType.THRUST, 28.0, false, false
	)
	var gs_ws: Dictionary = gs_chest["wound_summary"] as Dictionary
	_assert_false(rank1.anatomy.is_dead, "10v10 Greatsword THRUST to normal Chest does NOT 1-shot kill")
	_assert_true(float(gs_ws["organ_damage_pct"]) > 20.0 and float(gs_ws["organ_damage_pct"]) < 80.0, "10v10 Greatsword THRUST deals serious partial organ trauma (%.1f%%)" % float(gs_ws["organ_damage_pct"]))
	_assert_true(rank1.anatomy.get_total_bleed_rate() > 5.0, "10v10 Greatsword THRUST inflicts severe bleeding")

	rank1.revive_and_heal_all()
	rank1.receive_melee_hit(
		player, r1_chest, player.equipped_weapon, true, 1.0, false,
		PenetrationResolver.AttackType.THRUST, 28.0, false, false
	)
	_assert_true(rank1.anatomy.is_dead, "10v10 Greatsword THRUST into 1-px Chest Weak Point IS a lethal 1-shot kill")

	# -----------------------------------------------------------------------
	# 3. Blunt Lethality (Organ Crush + Internal Hemorrhage), Chest/Neck/Stomach
	#    Fracture Penalties & Armor/Mana/Hardening Blunt Damping
	# -----------------------------------------------------------------------
	# 3a. Heavy Warhammer skull crush kills via vital_organ_destroyed + internal hemorrhage
	rank1.revive_and_heal_all()
	player.stat_sheet.awaken_mana(10.0, 10.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.M_CTRL, 10.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.STR, 25.0)
	player.select_weapon_slot(2) # Warhammer -> impulse = 113.4 * 6.25 = 708.75 (ratio = 7.09x on bare skull!)
	rank1.receive_melee_hit(
		player, r1_head, player.equipped_weapon, false, 1.0, false,
		PenetrationResolver.AttackType.BLUNT, 24.0, false, false
	)
	_assert_true(rank1.anatomy.is_dead, "Heavy Warhammer BLUNT skull crush kills target")
	_assert_eq(rank1.anatomy.death_cause, "vital_organ_destroyed", "Blunt skull crush cause == vital_organ_destroyed")
	_assert_true(rank1.anatomy.get_total_bleed_rate() > 0.0, "Severe blunt crush causes Internal Hemorrhage")

	# 3b. Fracture stat penalties on Chest (STA/STR/SPD), Neck (TP/CTRL), Stomach (STA/AGI)
	var pen_stats: StatSheet = StatSheet.new()
	var pen_anat: AnatomyComponent = AnatomyComponent.new(pen_stats, 1.0, 100.0)
	pen_anat.apply_blunt_hit(AnatomyComponent.ZONE_CHEST, 130.0, 1.0, 0.0, false)
	_assert_true(pen_stats.get_stat(StatSheet.Stat.STA) < 10.0 and pen_stats.get_stat(StatSheet.Stat.STR) < 10.0 and pen_stats.get_stat(StatSheet.Stat.SPD) < 10.0, "Chest fracture debuffs STA, STR & SPD")
	pen_anat.apply_blunt_hit(AnatomyComponent.ZONE_NECK, 130.0, 1.0, 0.0, false)
	_assert_true(pen_stats.get_stat(StatSheet.Stat.TP) < 10.0 and pen_stats.get_stat(StatSheet.Stat.CTRL) < 10.0, "Neck fracture debuffs TP & CTRL")
	pen_anat.apply_blunt_hit(AnatomyComponent.ZONE_STOMACH, 130.0, 1.0, 0.0, false)
	_assert_true(pen_stats.get_stat(StatSheet.Stat.AGI) < 10.0, "Stomach fracture debuffs AGI & STA")
	pen_anat.free()

	# 3c. Armor cushion + ManaSkin + Hardening raise blunt resistance threshold
	_assert_true(r6_chest.armor_cushion_mult > 1.5, "Rank 6 heavy plate has armor_cushion_mult > 1.5 (got %.2f)" % r6_chest.armor_cushion_mult)
	var base_thresh: float = rank6.anatomy.get_blunt_resistance_threshold(1.0, 0.0)
	var plate_thresh: float = rank6.anatomy.get_blunt_resistance_threshold(r6_chest.armor_cushion_mult, 0.0)
	var harden_thresh: float = rank6.anatomy.get_blunt_resistance_threshold(r6_chest.armor_cushion_mult, 200.0)
	_assert_true(plate_thresh > base_thresh * 1.4, "Armor cushion significantly raises blunt fracture threshold")
	_assert_true(harden_thresh > plate_thresh + 400.0, "Active Hardening adds substantial blunt resistance")

	# -----------------------------------------------------------------------
	# 4. Aura Economy (M_CTRL=10 NOT free!) & Scaling Harmony (Dagger vs Greatsword)
	# -----------------------------------------------------------------------
	player.revive_and_heal_all()
	player.stat_sheet.awaken_mana(10.0, 10.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.STR, 10.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.MP_CAP, 10.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.M_CTRL, 10.0)
	player.refill_resources()
	player.set_aura_active(true)
	var mp_start: float = player.current_mp
	player.tick_physiology(2.0, false)
	_assert_true(player.current_mp < mp_start - 3.0, "At MP_CAP=10, M_CTRL=10 Aura net-drains MP over time (not free infinite Aura!)")
	var mp_before_swing: float = player.current_mp
	player.select_weapon_slot(0)
	player.start_attack(player.get_combat_origin() + Vector2(20.0, 0.0), PenetrationResolver.AttackType.SLASH)
	_assert_true(player.current_mp < mp_before_swing - 3.0, "Each attack swing with Aura ON consumes extra AURA_MP_PER_SWING")
	player.step_combat_fsm(1.0)
	player.set_aura_active(false)

	# Scaling harmony: at STR=100, M_CTRL=100 and STR=500, M_CTRL=500 Greatsword stays meaningfully stronger than Dagger
	var aura_100: PenetrationResolver.AuraBonuses = PenetrationResolver.calculate_aura_bonuses(true, 100.0, false)
	var dag_p100: float = PenetrationResolver.calculate_penetration(12.0, 100.0, 1.0, aura_100.pierce_bonus, 1.0)
	var gs_p100: float = PenetrationResolver.calculate_penetration(28.0, 100.0, 1.0, aura_100.pierce_bonus, 1.1)
	_assert_true(gs_p100 > dag_p100 * 1.20, "At STR=100, M_CTRL=100 Greatsword + Aura stays >20% ahead of Dagger + Aura")

	# -----------------------------------------------------------------------
	# 5. Live Collider-Contact Dead Zone & Tightened Clinch Range
	# -----------------------------------------------------------------------
	player.revive_and_heal_all()
	rank1.revive_and_heal_all()
	player.stat_sheet.set_mana_awakened(false)
	player.stat_sheet.set_all_base_stats(10.0, false)
	player.refill_resources()
	player.verticality.set_floor_level(0)
	player.verticality.set_height_z(0.0)
	rank1.verticality.set_floor_level(0)
	rank1.verticality.set_height_z(0.0)

	# Physically touch Player & Rank 1 colliders (8 + 8 = 16 px center-to-center)
	rank1.global_position = Vector2(240.0, 240.0)
	player.global_position = Vector2(224.0, 240.0) # Exact physical contact (16 px)
	await get_tree().physics_frame
	await get_tree().physics_frame

	player.select_weapon_slot(1) # Greatsword (min_optimal_range=20)
	EventBus.last_penetration_log = {}
	player.start_attack(rank1.get_combat_origin(), PenetrationResolver.AttackType.THRUST)
	player.step_combat_fsm(0.90)
	_assert_true(bool(EventBus.last_penetration_log.get("in_dead_zone", false)), "Live collider-contact Greatsword THRUST triggers real Dead Zone!")

	# Toggling Half-swording removes live collider-contact Dead Zone!
	rank1.revive_and_heal_all()
	player.toggle_half_swording()
	EventBus.last_penetration_log = {}
	player.start_attack(rank1.get_combat_origin(), PenetrationResolver.AttackType.THRUST)
	player.step_combat_fsm(0.90)
	_assert_false(bool(EventBus.last_penetration_log.get("in_dead_zone", true)), "Live collider-contact Greatsword with Half-swording removes Dead Zone")
	player.toggle_half_swording()

	# Clinch range tightened: 34 px is out_of_range (cannot clinch from beyond dagger length!)
	rank1.revive_and_heal_all()
	player.global_position = rank1.global_position + Vector2(-34.0, 0.0)
	var far_clinch: Dictionary = player.perform_clinch_throw(rank1, Vector2.RIGHT)
	_assert_false(bool(far_clinch["success"]), "Clinch rejects 34 px distance")
	_assert_eq(String(far_clinch["reason"]), "out_of_range", "34 px is out_of_range for tightened Clinch")

	# -----------------------------------------------------------------------
	# 6. Clinch Stat Contest, Stone Wall Throw Cap & Non-50x-Frozen Status Timers
	# -----------------------------------------------------------------------
	# 6a. Weak STR=10 human CANNOT throw or sweep healthy active Troll (STR=45, size=1.3) or Rank 6 Guard (STR=100)
	troll.revive_and_heal_all()
	player.global_position = troll.global_position + Vector2(-24.0, 0.0)
	var weak_throw_troll: Dictionary = player.perform_clinch_throw(troll, Vector2.RIGHT)
	_assert_false(bool(weak_throw_troll["success"]), "STR=10 human fails Clinch Throw against healthy active Troll (STR=45, size=1.3)")
	_assert_eq(String(weak_throw_troll["reason"]), "resisted", "Troll resists weak Clinch Throw (reason=resisted)")

	var weak_sweep_troll: Dictionary = player.perform_clinch_sweep(troll)
	_assert_false(bool(weak_sweep_troll["success"]), "STR=10 human fails Clinch Sweep against healthy active Troll")
	_assert_eq(String(weak_sweep_troll["reason"]), "resisted", "Troll resists weak Clinch Sweep (reason=resisted)")

	# Once Troll is STAGGERED and attacker has sufficient strength (STR=30), Clinch Throw succeeds!
	player.stat_sheet.awaken_mana(10.0, 10.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.M_CTRL, 10.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.STR, 30.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.CTRL, 30.0)
	troll.apply_stagger(1.0)
	var staggered_throw_troll: Dictionary = player.perform_clinch_throw(troll, Vector2.RIGHT)
	_assert_true(bool(staggered_throw_troll["success"]), "Clinch Throw succeeds against STAGGERED Troll when contest threshold is met")

	# 6b. STR=27 throw into STONE wall (threshold >= 90) MUST NOT break the stone wall!
	rank1.revive_and_heal_all()
	player.stat_sheet.set_base_stat(StatSheet.Stat.STR, 27.0)
	player.refill_resources()
	var stone_wall: Vector2i = TestArena.STONE_WALL_CELLS[0]
	_assert_true(arena.is_wall_solid_at(0, stone_wall), "Stone wall intact before STR=27 throw")
	rank1.global_position = arena.cell_to_world_center(stone_wall) + Vector2(-36.0, 0.0)
	player.global_position = rank1.global_position + Vector2(-22.0, 0.0)
	await get_tree().physics_frame
	var s27_throw: Dictionary = player.perform_clinch_throw(rank1, Vector2.RIGHT)
	_assert_true(bool(s27_throw["success"]), "STR=27 throws Rank 1 into stone wall")
	var stone_kb: Dictionary = rank1.step_knockback(0.35)
	_assert_true(bool(stone_kb["wall_slammed"]), "Rank 1 slams against stone wall")
	_assert_false(bool(stone_kb["wall_broken"]), "STR=27 throw does NOT smash stone wall (threshold STR >= 90)")
	_assert_true(arena.is_wall_solid_at(0, stone_wall), "Stone wall remains solid after STR=27 Wall Slam")

	# 6c. At TP=500, SPD=500 (world_time_scale = 0.02, 50x slow-mo): Prone & Hardening expire in ~2s real time, NOT 100s!
	player.revive_and_heal_all()
	player.stat_sheet.awaken_mana(500.0, 500.0)
	player.stat_sheet.set_all_base_stats(500.0, true)
	player.refill_resources()
	SimulationClock.set_tempo_mode(SimulationClock.TempoMode.COMBAT_OVERDRIVE, true, "timer_test")
	SimulationClock.perception_regulator = 1.0
	SimulationClock.speed_regulator = 1.0
	_assert_approx(SimulationClock.get_world_time_scale(), 0.02, 1e-4, "TP=500 runs at 50x slow-mo (world_time_scale == 0.02)")

	player.activate_hardening()
	_assert_true(player.is_hardening_active(), "Hardening active at TP=500")
	player.set_prone(2.0)
	_assert_true(player.is_prone(), "Player Prone for 2.0s at TP=500")

	# Simulate 2.2 real seconds (132 frames of raw_delta=1/60s)
	SimulationClock.clear_hitstop()
	for _i: int in range(132):
		var raw_dt: float = 1.0 / 60.0
		SimulationClock.tick_hitstop(raw_dt)
		var act_dt: float = SimulationClock.get_player_action_delta(raw_dt, player.get_instance_id())
		player.tick_combat_status_timers(act_dt, raw_dt)
	_assert_false(player.is_hardening_active(), "Hardening (0.55s) expired cleanly within 2.2s real time at TP=500 (not 27.5s!)")
	_assert_approx(player.hardening_cooldown_timer, 0.0, 1e-4, "Hardening cooldown (1.60s) expired within 2.2s real time at TP=500 (not 80s!)")
	_assert_false(player.is_prone(), "Prone (2.0s) recovered within 2.2s real time at TP=500 (not 100s!)")

	remove_child(arena)
	arena.queue_free()
	EventBus.set_debug_highlight_weak_points(false)
	EventBus.set_debug_anti_regen_attacks(false)


# ===========================================================================
# SUITE 21: v0.2 AI Navigation/Dive/Stairs/Reactions, Real Disarm & Unarmed,
#           Counter-Window Bonus, Anti-Regen Contact, Drift & Dash Overshoot
# ===========================================================================

func _test_v02_ai_disarm_counter_and_physics_fixes() -> void:
	SimulationClock.reset_defaults()
	WorldCalendar.reset_calendar(0)
	FloorLayerManager.reset(0)
	EventBus.set_debug_anti_regen_attacks(false)

	var arena_scene: PackedScene = load("res://scenes/test_arena.tscn") as PackedScene
	var arena: TestArena = arena_scene.instantiate() as TestArena
	add_child(arena)
	arena.set_all_enemies_ai_enabled(false)

	var player: PlayerController = arena.entities_container.get_node_or_null("Player") as PlayerController
	var rank1: EnemyDummy = arena.entities_container.get_node_or_null("Rank1Swordsman") as EnemyDummy
	var troll: EnemyDummy = arena.entities_container.get_node_or_null("TrollBerserker") as EnemyDummy
	var rank6: EnemyDummy = arena.entities_container.get_node_or_null("Rank6Guard") as EnemyDummy

	await get_tree().physics_frame

	# -----------------------------------------------------------------------
	# 1. Rank 6 Guard Tactical Dive (z=1.5 -> grounded melee), Aura, Half-swording & Ascend
	# -----------------------------------------------------------------------
	_assert_approx(rank6.get_height_z(), 1.5, 1e-4, "Rank 6 Guard still spawns hovering at height_z == 1.5")
	_assert_false(rank6.aura_active, "Rank 6 Guard starts with Aura OFF in PATROL")

	# Raise player TP=50 so Imperceptible Speed (100/50=2x < 10x) doesn't shortcut melee dive test
	player.stat_sheet.awaken_mana(50.0, 20.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.TP, 50.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.CON, 40.0)
	player.refill_resources()
	player.verticality.set_floor_level(0)
	player.verticality.set_height_z(0.0)

	rank6.global_position = Vector2(200.0, 380.0)
	player.global_position = rank6.global_position + Vector2(36.0, 0.0)
	rank6.engage_target(player)
	await get_tree().physics_frame

	var started_melee_attack: bool = false
	for _i: int in range(18):
		var vel: Vector2 = rank6.step_ai_tick(0.08, 0.08)
		rank6.move_with_substepping(vel, 0.08, false, true)
		if rank6.combat_state == CombatActor.CombatState.WINDUP:
			started_melee_attack = true
			break
	_assert_true(rank6.aura_active, "Rank 6 Guard activates Aura automatically in COMBAT")
	_assert_true(rank6.get_height_z() < 1.0, "Rank 6 Guard dives from z=1.5 into grounded strike range (z=%.2f)" % rank6.get_height_z())
	_assert_true(started_melee_attack, "Rank 6 Guard executes melee attack against grounded player after diving")

	# Up close inside Greatsword dead zone -> Rank 6 Guard switches to Half-swording!
	rank6.combat_state = CombatActor.CombatState.IDLE
	rank6.state_timer = 0.0
	rank6.attack_cooldown_timer = 1.0
	player.global_position = rank6.global_position + Vector2(20.0, 0.0)
	await get_tree().physics_frame
	rank6.step_ai_tick(0.05, 0.05)
	_assert_true(rank6.half_swording, "Rank 6 Guard enables Half-swording when player closes into Greatsword dead zone")

	# Returning to PATROL turns Aura OFF and smoothly ascends back toward height_z = 1.5
	rank6.reset_aggro(0.0)
	player.global_position = Vector2(64.0, 64.0)
	await get_tree().physics_frame
	for _i: int in range(16):
		rank6.step_ai_tick(0.08, 0.08)
	_assert_false(rank6.aura_active, "Rank 6 Guard turns Aura OFF on PATROL")
	_assert_approx(rank6.get_height_z(), 1.5, 0.05, "Rank 6 Guard ascends back to hover altitude z=1.5 in PATROL")

	# -----------------------------------------------------------------------
	# 2. AStarGrid2D Navigation around LOW_OBSTACLE Fence + Stairs Pursuit
	# -----------------------------------------------------------------------
	SimulationClock.reset_defaults()
	SimulationClock.bind_player_stats(player.stat_sheet)
	player.revive_and_heal_all()
	player.stat_sheet.set_mana_awakened(false)
	player.stat_sheet.set_all_base_stats(10.0, false)
	player.refill_resources()
	rank1.revive_and_heal_all()
	rank1.reset_aggro(0.0)

	# Fence line is at x=6, y=3..6 (world x=192..224, y=96..224). Place rank1 left of fence, player right of fence!
	rank1.global_position = arena.cell_to_world_center(Vector2i(5, 4))
	player.global_position = arena.cell_to_world_center(Vector2i(7, 4))
	rank1.aim_angle = 0.0
	await get_tree().physics_frame

	_assert_true(rank1.can_see_target(player, arena), "Rank 1 sees player over LOW_OBSTACLE fence")
	_assert_false(rank1._has_clear_walk_path(player.global_position), "Direct walk path blocked by LOW_OBSTACLE fence")

	rank1.engage_target(player)
	var nav_path_used: bool = false
	for _i: int in range(70):
		var v: Vector2 = rank1.step_ai_tick(0.04, 0.04)
		if rank1.get_current_nav_path().size() > 0:
			nav_path_used = true
		rank1.move_with_substepping(v, 0.04, false, false)
		if rank1.global_position.x > arena.cell_to_world_center(Vector2i(6, 4)).x + 4.0:
			break
	_assert_true(nav_path_used, "Rank 1 computes AStarGrid2D nav path around LOW_OBSTACLE fence")
	_assert_true(rank1.global_position.x > arena.cell_to_world_center(Vector2i(6, 4)).x, "Rank 1 navigates cleanly around LOW_OBSTACLE fence to player's side instead of getting stuck")

	# Stairs Pursuit: player climbs stairs 0 -> +1 near STAIRS_RECT -> Rank 1 follows via stairs!
	rank1.revive_and_heal_all()
	rank1.reset_aggro(0.0)
	rank1.verticality.set_floor_level(0)
	player.verticality.set_floor_level(0)
	var stairs_c: Vector2 = arena.get_stairs_center()
	rank1.global_position = stairs_c + Vector2(-42.0, 0.0)
	player.global_position = stairs_c
	rank1.aim_angle = 0.0
	await get_tree().physics_frame
	rank1.engage_target(player)
	rank1.step_ai_tick(0.04, 0.04) # Record last_known_target_pos at stairs
	_assert_true(arena.try_use_stairs(player), "Player climbs stairs from Floor 0 to Floor +1")
	_assert_eq(player.get_floor_level(), 1, "Player is now on Floor +1")
	player.global_position = stairs_c + Vector2(28.0, 0.0)
	await get_tree().physics_frame

	var climbed_stairs: bool = false
	for _i: int in range(35):
		var sv: Vector2 = rank1.step_ai_tick(0.04, 0.04)
		rank1.move_with_substepping(sv, 0.04, false, false)
		if rank1.get_floor_level() == 1:
			climbed_stairs = true
			break
	_assert_true(climbed_stairs, "Pursuing enemy uses stairs to follow player onto Floor +1")
	_assert_eq(rank1.get_floor_level(), 1, "Rank 1 transitioned cleanly to Floor +1")

	# -----------------------------------------------------------------------
	# 3. Reactive Preset Tactics (Troll Hardening after hits, Rank 1 Reactive Block)
	# -----------------------------------------------------------------------
	rank1.revive_and_heal_all()
	rank1.reset_aggro(0.0)
	rank1.verticality.set_floor_level(0)
	player.verticality.set_floor_level(0)
	rank1.global_position = Vector2(220.0, 260.0)
	player.global_position = rank1.global_position + Vector2(-28.0, 0.0)
	rank1.engage_target(player)
	await get_tree().physics_frame
	player.select_weapon_slot(0)
	player.start_attack(rank1.get_combat_origin(), PenetrationResolver.AttackType.SLASH)
	_assert_eq(player.combat_state, CombatActor.CombatState.WINDUP, "Player enters WINDUP in front of Rank 1")
	for _r: int in range(8):
		rank1.step_ai_tick(0.05, 0.05)
		if rank1.is_blocking:
			break
	_assert_true(rank1.is_blocking and rank1.is_in_parry_window(), "Rank 1 reactively raises Deflect/Block during player WINDUP")
	player.combat_state = CombatActor.CombatState.IDLE
	player.state_timer = 0.0

	# Troll Berserker activates Hardening after taking >= 2 hits
	troll.revive_and_heal_all()
	troll.reset_aggro(0.0)
	troll.global_position = Vector2(360.0, 260.0)
	player.global_position = troll.global_position + Vector2(-30.0, 0.0)
	await get_tree().physics_frame
	var troll_chest: HitboxZone = _find_zone(troll, AnatomyComponent.ZONE_CHEST)
	troll.receive_melee_hit(player, troll_chest, player.get_active_weapon(), false, 1.0, false, PenetrationResolver.AttackType.SLASH)
	troll.receive_melee_hit(player, troll_chest, player.get_active_weapon(), false, 1.0, false, PenetrationResolver.AttackType.SLASH)
	troll.step_ai_tick(0.04, 0.04)
	_assert_true(troll.is_hardening_active(), "Troll Berserker reactively activates Hardening after taking >= 2 hits")

	# -----------------------------------------------------------------------
	# 4. Real Disarm on Tendon Tear / Arm Sever, Unarmed (Fists), Pickup (E),
	#    Both Arms Severed Restriction, & LodgedWeapon Disarm + Careful/Fast Extract
	# -----------------------------------------------------------------------
	player.revive_and_heal_all()
	rank1.revive_and_heal_all()
	rank1.reset_aggro(0.0)
	arena.reset_arena_geometry_and_decals()
	player.global_position = Vector2(240.0, 300.0)
	rank1.global_position = Vector2(270.0, 300.0)
	player.select_weapon_slot(0) # Dagger
	_assert_false(player.is_unarmed(), "Player starts armed with Short Dagger")
	_assert_eq(arena.dropped_weapon_pickups.size(), 0, "Zero dropped pickups before disarm")

	# 4a. Arm tendon tear physically drops Dagger onto TestArena and switches player to Unarmed (Fists)
	player.anatomy.apply_tendon_tear(AnatomyComponent.ZONE_RIGHT_ARM, 10.0, player.equipped_weapon)
	_assert_true(player.equipped_weapon == null, "Tendon tear clears player.equipped_weapon")
	_assert_true(player.weapon_slots[0] == null, "Tendon tear clears active player.weapon_slots[0]")
	_assert_true(player.is_unarmed(), "Player is now unarmed")
	_assert_eq(player.get_active_weapon().display_name, "Unarmed (Fists)", "Fallback active weapon is Unarmed (Fists)")
	_assert_eq(arena.dropped_weapon_pickups.size(), 1, "Dropped Dagger spawned as interactive pickup on TestArena")

	# Unarmed punch works and always uses BLUNT attack type
	_assert_true(player.start_attack(rank1.get_combat_origin(), PenetrationResolver.AttackType.SLASH), "Disarmed player can still punch with Unarmed (Fists)")
	_assert_eq(player.current_attack_type, PenetrationResolver.AttackType.BLUNT, "Unarmed attack automatically forces AttackType.BLUNT")
	player.combat_state = CombatActor.CombatState.IDLE
	player.state_timer = 0.0

	# Interact (E) picks the dropped Dagger back up into the empty slot!
	var pickup_res: Dictionary = player.handle_interact_action(false)
	_assert_true(bool(pickup_res.get("handled", false)), "Pressing E near dropped weapon handles interaction")
	_assert_eq(pickup_res.get("action", &""), &"pickup", "Interaction action is pickup")
	_assert_false(player.is_unarmed(), "Player re-armed after picking up dropped Dagger")
	_assert_eq(player.equipped_weapon.weapon_id, &"dagger", "Picked up the exact Short Dagger")
	_assert_eq(arena.dropped_weapon_pickups.size(), 0, "Dropped pickup removed from TestArena after pickup")

	# 4b. Severing 1 arm blocks two-handed Half-swording; severing BOTH arms blocks ALL attacks, block, clinch & pickup!
	player.select_weapon_slot(1) # Greatsword (can_half_sword = true)
	_assert_true(player.toggle_half_swording(), "Half-swording succeeds with 2 usable arms")
	player.anatomy.sever_limb(AnatomyComponent.ZONE_LEFT_ARM, rank1, false, player.equipped_weapon)
	_assert_false(player.half_swording, "Severing 1 arm cancels active Half-swording")
	_assert_true(player.equipped_weapon == null, "Severing arm drops active Greatsword onto TestArena")
	player.select_weapon_slot(2) # Warhammer in remaining intact arm
	_assert_false(player.toggle_half_swording(), "Half-swording blocked when usable_arm_count < 2")

	player.anatomy.sever_limb(AnatomyComponent.ZONE_RIGHT_ARM, rank1, false, player.equipped_weapon)
	# Keep player awake so we specifically verify has_both_arms_severed() blocks all combat actions
	player.anatomy.shock_level = 0.0
	player.anatomy.is_unconscious = false
	_assert_true(player.has_both_arms_severed(), "Both arms severed detected cleanly")
	_assert_false(player.start_attack(rank1.get_combat_origin(), PenetrationResolver.AttackType.BLUNT), "Actor with both arms severed cannot attack even unarmed")
	player.trigger_block_pressed()
	_assert_false(player.is_blocking, "Actor with both arms severed cannot block")
	player.global_position = rank1.global_position + Vector2(-18.0, 0.0)
	var no_arm_clinch: Dictionary = player.perform_clinch_shove(rank1)
	_assert_false(bool(no_arm_clinch["success"]), "Actor with both arms severed cannot clinch")
	_assert_eq(String(no_arm_clinch["reason"]), "no_arms", "Clinch rejection reason is no_arms")
	_assert_true(player.try_pickup_dropped_weapon() == null, "Actor with both arms severed cannot pick up weapons")

	# 4c. LodgedWeapon genuinely disarms attacker; Careful Extract (Shift+E) vs Fast Rip (E) returns weapon!
	player.revive_and_heal_all()
	rank1.revive_and_heal_all()
	arena.reset_arena_geometry_and_decals()
	_assert_true(player.weapon_slots[0] != null and player.weapon_slots[1] != null and player.weapon_slots[2] != null, "revive_and_heal_all() restores all 3 player weapon slots")
	_assert_true(rank1.equipped_weapon != null, "revive_and_heal_all() restores Rank 1 Short Sword")

	player.stat_sheet.set_mana_awakened(false)
	player.stat_sheet.set_all_base_stats(10.0, false)
	player.refill_resources()
	player.activate_hardening()
	rank1.stat_sheet.awaken_mana(10.0, 10.0)
	rank1.stat_sheet.set_base_stat(StatSheet.Stat.M_CTRL, 10.0)
	rank1.stat_sheet.set_base_stat(StatSheet.Stat.STR, 26.0)
	var p_chest: HitboxZone = _find_zone(player, AnatomyComponent.ZONE_CHEST)
	var r1_sword: WeaponData = rank1.equipped_weapon
	var lodge_hit: Dictionary = player.receive_melee_hit(rank1, p_chest, r1_sword, false, 1.0, false, PenetrationResolver.AttackType.SLASH)
	_assert_eq(String(lodge_hit["outcome"]), "hardening_lodged", "Rank 1 blade lodges inside hardened Player")
	_assert_true(rank1.equipped_weapon == null and rank1.is_unarmed(), "LodgedWeapon genuinely disarms attacker into Unarmed (Fists)")

	# Careful extraction (Shift+E / careful=true): zero rip bleed/shock; full player slots drops recovered sword cleanly onto floor (not void!)
	var careful_ext: Dictionary = player.handle_interact_action(true)
	_assert_true(bool(careful_ext.get("extracted", false)), "Careful Shift+E extracts lodged weapon")
	_assert_approx(float(careful_ext.get("ripped_bleed", -1.0)), 0.0, 1e-5, "Careful extraction causes ZERO extra rip bleed")
	_assert_approx(float(careful_ext.get("shock_added", -1.0)), 0.0, 1e-5, "Careful extraction causes ZERO extra shock")
	_assert_eq(arena.dropped_weapon_pickups.size(), 1, "When player slots are full, extracted weapon drops safely on floor (never lost into void)")

	# Re-lodge & test fast extraction (E / careful=false) when player has an empty slot -> returns straight into inventory!
	var recovered_sword: WeaponData = arena.try_pickup_nearest_weapon(player.global_position, 0, 80.0)
	_assert_true(recovered_sword == r1_sword, "Floor pickup holds the exact extracted Short Sword")
	player.disarm_active_weapon(false, &"test_empty_slot")
	_assert_true(player.weapon_slots[player.active_weapon_index] == null, "Emptied active player slot")
	player.anatomy.lodge_weapon(AnatomyComponent.ZONE_CHEST, recovered_sword, rank1, 6.0)
	var fast_ext: Dictionary = player.handle_interact_action(false)
	_assert_true(bool(fast_ext.get("extracted", false)), "Quick E extracts lodged weapon")
	_assert_true(float(fast_ext.get("ripped_bleed", 0.0)) > 0.0, "Fast rip extraction causes rip bleed")
	_assert_true(float(fast_ext.get("shock_added", 0.0)) > 0.0, "Fast rip extraction causes shock")
	_assert_true(player.equipped_weapon == recovered_sword, "Extracted weapon returned straight into player's empty weapon slot")

	# -----------------------------------------------------------------------
	# 5. counter_window_timer Bonus: 2x Faster Windup + Bypass Passive Block + +35% Penetration
	# -----------------------------------------------------------------------
	player.revive_and_heal_all()
	rank1.revive_and_heal_all()
	rank1.reset_aggro(0.0)
	player.stat_sheet.set_mana_awakened(false)
	player.stat_sheet.set_all_base_stats(10.0, false)
	player.refill_resources()
	player.select_weapon_slot(0) # Dagger
	player.global_position = Vector2(240.0, 300.0)
	rank1.global_position = Vector2(262.0, 300.0)
	await get_tree().physics_frame

	# Measure normal windup vs counter windup
	player.counter_window_timer = 0.0
	player.start_attack(rank1.get_combat_origin(), PenetrationResolver.AttackType.SLASH)
	var normal_windup: float = player.state_timer
	player.combat_state = CombatActor.CombatState.IDLE
	player.state_timer = 0.0

	player.counter_window_timer = 0.65
	player.start_attack(rank1.get_combat_origin(), PenetrationResolver.AttackType.SLASH)
	var counter_windup: float = player.state_timer
	_assert_approx(counter_windup, normal_windup * CombatActor.COUNTER_WINDUP_MULT, 1e-4, "Counterattack cuts Windup duration in half (0.50x)")
	_assert_approx(player.counter_window_timer, 0.0, 1e-5, "Starting counterattack consumes counter_window_timer")
	_assert_true(player.current_attack_is_counter, "current_attack_is_counter active during counter strike")

	# Passive hold-Block (facing attacker) stops normal attack, but Counterattack bypasses passive hold-Block & boosts penetration!
	player.combat_state = CombatActor.CombatState.IDLE
	player.state_timer = 0.0
	player.current_attack_is_counter = false
	rank1.aim_angle = (player.global_position - rank1.global_position).angle()
	rank1.is_blocking = true
	rank1.parry_window_timer = 0.0
	var r1_chest: HitboxZone = _find_zone(rank1, AnatomyComponent.ZONE_CHEST)
	var normal_vs_blk: Dictionary = rank1.receive_melee_hit(player, r1_chest, player.get_active_weapon(), false, 1.0, false, PenetrationResolver.AttackType.SLASH, -1.0, false, false, false, false)
	_assert_eq(String(normal_vs_blk["outcome"]), "blocked", "Normal strike is stopped by passive hold-Block")

	rank1.refill_resources()
	rank1.is_blocking = true
	rank1.parry_window_timer = 0.0
	var counter_vs_blk: Dictionary = rank1.receive_melee_hit(player, r1_chest, player.get_active_weapon(), false, 1.0, false, PenetrationResolver.AttackType.SLASH, -1.0, false, false, false, true)
	_assert_neq(String(counter_vs_blk["outcome"]), "blocked", "Counterattack bypasses passive hold-Block")
	var cnt_res: PenetrationResolver.ResolutionResult = counter_vs_blk["resolution"] as PenetrationResolver.ResolutionResult
	_assert_true(cnt_res.penetration > 15.0, "Counterattack boosts penetration by +35%% (pen=%.1f)" % cnt_res.penetration)

	# -----------------------------------------------------------------------
	# 6. Anti-Regen Strictly on Real Penetration / Fracture (Never on depth=0 Armor Bounce!)
	# -----------------------------------------------------------------------
	rank6.revive_and_heal_all()
	rank6.reset_aggro(0.0)
	player.revive_and_heal_all()
	player.stat_sheet.set_mana_awakened(false)
	player.stat_sheet.set_all_base_stats(10.0, false)
	player.select_weapon_slot(0) # Starter Dagger vs Rank 6 heavy armor (depth == 0.0 bounce)
	var r6_chest: HitboxZone = _find_zone(rank6, AnatomyComponent.ZONE_CHEST)
	var bounce_ar: Dictionary = rank6.receive_melee_hit(player, r6_chest, player.get_active_weapon(), false, 1.0, false, PenetrationResolver.AttackType.SLASH, -1.0, false, false, true, false)
	_assert_eq(String(bounce_ar["outcome"]), "no_penetration", "Starter Dagger bounces off Rank 6 armor (depth == 0)")
	_assert_false(rank6.anatomy.is_anti_regen_active(), "Non-penetrating armor bounce NEVER applies Anti-Regen")

	rank1.revive_and_heal_all()
	rank1.reset_aggro(0.0)
	var pen_ar: Dictionary = rank1.receive_melee_hit(player, r1_chest, player.get_active_weapon(), true, 1.0, false, PenetrationResolver.AttackType.THRUST, -1.0, false, false, true, false)
	_assert_eq(String(pen_ar["outcome"]), "penetrated", "Thrust weak-point penetrates unarmored Rank 1")
	_assert_true(rank1.anatomy.is_anti_regen_active(), "Real penetrating strike DOES apply Anti-Regen")

	# -----------------------------------------------------------------------
	# 7. Physics Fixes: Inertial Drift (SPD/TP > 1.5) + Aim Lag + No Dash Overshoot (SPD=500, TP=10)
	# -----------------------------------------------------------------------
	SimulationClock.reset_defaults()
	SimulationClock.bind_player_stats(player.stat_sheet)
	player.revive_and_heal_all()
	player.stat_sheet.awaken_mana(100.0, 100.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.SPD, 200.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.TP, 10.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.AGI, 10.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.M_CTRL, 10.0)
	player.refill_resources()
	SimulationClock.set_tempo_mode(SimulationClock.TempoMode.COMBAT_OVERDRIVE, true, "drift_test")
	SimulationClock.speed_regulator = 1.0
	SimulationClock.perception_regulator = 1.0
	_assert_true(SimulationClock.is_player_losing_control(), "SPD=200 / TP=10 triggers loss of control (ratio=20 > 1.5)")

	# 7a. Inertial acceleration & release slide (must NOT snap to full speed on frame 1 or 0 on release!)
	var raw_dt: float = 1.0 / 60.0
	player._drift_velocity = Vector2.ZERO
	var v_frame1: Vector2 = player.compute_run_velocity_with_drift(Vector2.RIGHT, raw_dt)
	_assert_true(v_frame1.x > 0.0 and v_frame1.x < CombatActor.BASE_RUN_SPEED_PX * 0.25, "High SPD/TP accelerates gradually on raw_delta (frame1 vx=%.1f)" % v_frame1.x)
	for _f: int in range(30):
		player.compute_run_velocity_with_drift(Vector2.RIGHT, raw_dt)
	var v_before_release: Vector2 = player._drift_velocity
	var v_after_release: Vector2 = player.compute_run_velocity_with_drift(Vector2.ZERO, raw_dt)
	_assert_true(v_after_release.x > v_before_release.x * 0.80, "Releasing WASD under high SPD/TP slides inertially instead of snapping to zero (vx=%.1f)" % v_after_release.x)

	# 7b. Aim angle inertia lag during loss of control
	player.aim_angle = 0.0
	var opposite_target: Vector2 = player.get_combat_origin() + Vector2(-100.0, 0.0) # PI rad
	var lagged_angle: float = player.update_aim_with_drift(opposite_target, raw_dt)
	_assert_true(absf(angle_difference(lagged_angle, PI)) > 1.0, "High SPD/TP causes genuine aim_angle turn lag (err=%.2f rad)" % absf(angle_difference(lagged_angle, PI)))

	# 7c. First-frame Dash on SPD=500, TP=10 (action_delta ~= 0.833s) MUST NOT overshoot BASE_DASH_DURATION_SEC * dash_speed!
	player.stat_sheet.set_base_stat(StatSheet.Stat.SPD, 500.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.TP, 10.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.AGI, 10.0)
	player.refill_resources()
	player._drift_velocity = Vector2.ZERO
	player.dash_cooldown_timer = 0.0
	player.dash_timer = 0.0
	player.verticality.set_floor_level(0)
	player.global_position = Vector2(128.0, 256.0)
	rank1.global_position = Vector2(500.0, 380.0)
	troll.global_position = Vector2(500.0, 320.0)
	rank6.global_position = Vector2(500.0, 420.0)
	await get_tree().physics_frame

	SimulationClock.clear_hitstop()
	var high_spd_action_dt: float = SimulationClock.get_player_action_delta(raw_dt, player.get_instance_id())
	_assert_true(high_spd_action_dt > 0.70, "SPD=500, TP=10 produces huge single-frame action_delta (%.3fs)" % high_spd_action_dt)
	var expected_dash_dist: float = CombatActor.BASE_DASH_SPEED_PX * player.stat_sheet.get_dash_mult() * CombatActor.BASE_DASH_DURATION_SEC
	var start_dash_pos: Vector2 = player.global_position
	_assert_true(player.start_dash(Vector2.RIGHT), "Player starts dash at SPD=500, TP=10")
	player.step_movement_and_combat(Vector2.ZERO, high_spd_action_dt, raw_dt)
	var actual_dash_dist: float = start_dash_pos.distance_to(player.global_position)
	_assert_approx(player.dash_timer, 0.0, 1e-5, "Dash timer completes cleanly within high-SPD frame")
	_assert_true(absf(actual_dash_dist - expected_dash_dist) <= 3.0, "High-SPD dash distance matches exact duration (actual=%.1f px vs expected=%.1f px, NO 6x overshoot!)" % [actual_dash_dist, expected_dash_dist])

	remove_child(arena)
	arena.queue_free()
	EventBus.set_debug_anti_regen_attacks(false)
	SimulationClock.reset_defaults()


# ===========================================================================
# SUITE 22: v0.2 Polish - Real Wall/Floor Durability, Multi-Floor Entity
#           Visibility, 12-Stat DebugHUD + Perception + First Aid + Mini-HUD,
#           Death Overlay/Respawn & Headless-Safe Procedural Audio
# ===========================================================================

func _test_v02_polish_durability_visibility_hud_death_and_audio() -> void:
	SimulationClock.reset_defaults()
	WorldCalendar.reset_calendar(0)
	FloorLayerManager.reset(0)
	EventBus.set_debug_highlight_weak_points(false)
	EventBus.set_debug_anti_regen_attacks(false)

	# 0. Verify new InputMap actions (P -> toggle_perception_regulator, F2 -> toggle_compact_hud)
	_assert_true(InputMap.has_action(&"toggle_perception_regulator"), "InputMap has toggle_perception_regulator (P)")
	_assert_true(InputMap.has_action(&"toggle_compact_hud"), "InputMap has toggle_compact_hud (F2)")
	var perc_ev: Array[InputEvent] = InputMap.action_get_events(&"toggle_perception_regulator")
	_assert_true(perc_ev.size() >= 1 and perc_ev[0] is InputEventKey and (perc_ev[0] as InputEventKey).physical_keycode == KEY_P, "toggle_perception_regulator is bound to KEY_P")
	var mini_ev: Array[InputEvent] = InputMap.action_get_events(&"toggle_compact_hud")
	_assert_true(mini_ev.size() >= 1 and mini_ev[0] is InputEventKey and (mini_ev[0] as InputEventKey).physical_keycode == KEY_F2, "toggle_compact_hud is bound to KEY_F2")

	var arena_scene: PackedScene = load("res://scenes/test_arena.tscn") as PackedScene
	var arena: TestArena = arena_scene.instantiate() as TestArena
	add_child(arena)
	arena.set_all_enemies_ai_enabled(false)

	var hud: DebugHUD = arena.get_node_or_null("DebugHUD") as DebugHUD
	var player: PlayerController = arena.entities_container.get_node_or_null("Player") as PlayerController
	var rank1: EnemyDummy = arena.entities_container.get_node_or_null("Rank1Swordsman") as EnemyDummy
	var troll: EnemyDummy = arena.entities_container.get_node_or_null("TrollBerserker") as EnemyDummy
	var audio_mgr: ProceduralAudioManager = arena.audio_manager
	_assert_true(hud != null and player != null and rank1 != null and troll != null and audio_mgr != null, "Polish arena loaded HUD, actors & ProceduralAudioManager")
	await get_tree().physics_frame

	# -----------------------------------------------------------------------
	# 1. Real Wall & Floor Durability (Gradual Damage, Cracks & Heavy Break)
	# -----------------------------------------------------------------------
	var wood_cell: Vector2i = TestArena.WOOD_WALL_CELLS[0]
	var wood_cell2: Vector2i = TestArena.WOOD_WALL_CELLS[2]
	var brick_cell: Vector2i = TestArena.BRICK_WALL_CELLS[0]
	var floor_cell: Vector2i = TestArena.BREAKABLE_FLOOR_RECT.position

	_assert_approx(arena.get_wall_durability(0, wood_cell), 30.0, 1e-4, "Wood wall starts at durability 30.0")
	_assert_approx(arena.get_wall_durability(0, brick_cell), 80.0, 1e-4, "Brick wall starts at durability 80.0")
	_assert_approx(arena.get_floor_durability(1, floor_cell), 25.0, 1e-4, "Breakable Floor +1 starts at durability 25.0")

	var wall_dmg_events: Array[Dictionary] = []
	var on_wall_dmg: Callable = func(fl: int, c: Vector2i, mat: String, rem: float, mx: float) -> void:
		wall_dmg_events.append({"floor": fl, "cell": c, "mat": mat, "rem": rem, "max": mx})
	arena.wall_damaged.connect(on_wall_dmg)

	# 1a. Dagger at minimal Wood threshold (STR=15) chips Wood wall gradually (does NOT 1-shot!)
	player.stat_sheet.set_mana_awakened(false)
	player.stat_sheet.set_base_stat(StatSheet.Stat.STR, 15.0)
	player.refill_resources()
	player.select_weapon_slot(0) # Short Dagger
	player.verticality.set_floor_level(0)
	player.verticality.set_height_z(0.0)
	player.global_position = arena.cell_to_world_center(wood_cell) + Vector2(-24.0, 0.0)
	await get_tree().physics_frame

	player.start_attack(arena.cell_to_world_center(wood_cell), PenetrationResolver.AttackType.SLASH)
	player.step_combat_fsm(1.0)
	_assert_true(arena.is_wall_solid_at(0, wood_cell), "Dagger at STR=15 does NOT destroy Wood wall on hit 1")
	var rem_after_1: float = arena.get_wall_durability(0, wood_cell)
	_assert_true(rem_after_1 > 0.0 and rem_after_1 < 30.0, "Hit 1 reduces Wood wall durability gradually (rem=%.1f)" % rem_after_1)
	_assert_true(wall_dmg_events.size() >= 1, "TestArena.wall_damaged signal emitted on partial wall damage")
	_assert_true(arena._structure_crack_overlays.size() >= 1, "Procedural crack overlay spawned on damaged Wood wall")

	# Repeated Dagger swings eventually break through Wood wall and clean up crack overlay
	for _s: int in range(6):
		if not arena.is_wall_solid_at(0, wood_cell):
			break
		player.refill_resources()
		player.start_attack(arena.cell_to_world_center(wood_cell), PenetrationResolver.AttackType.SLASH)
		player.step_combat_fsm(1.0)
	_assert_false(arena.is_wall_solid_at(0, wood_cell), "Repeated Dagger swings at STR=15 break through Wood wall")
	_assert_approx(arena.get_wall_durability(0, wood_cell), 0.0, 1e-4, "Destroyed Wood wall durability is 0")
	arena.wall_damaged.disconnect(on_wall_dmg)

	# 1b. Heavy Warhammer (BLUNT) at STR=15 shatters intact Wood wall in 1 heavy blow
	player.select_weapon_slot(2) # Heavy Warhammer
	player.refill_resources()
	player.global_position = arena.cell_to_world_center(wood_cell2) + Vector2(-34.0, 0.0)
	await get_tree().physics_frame
	player.start_attack(arena.cell_to_world_center(wood_cell2), PenetrationResolver.AttackType.BLUNT)
	player.step_combat_fsm(1.2)
	_assert_false(arena.is_wall_solid_at(0, wood_cell2), "Heavy Warhammer BLUNT at STR=15 smashes Wood wall in 1 blow")

	# 1c. Greatsword at minimal Brick threshold (STR=40) cracks Brick wall (80.0) on hit 1 and destroys on hit 2!
	player.stat_sheet.awaken_mana(20.0, 10.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.M_CTRL, 10.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.STR, 40.0)
	player.refill_resources()
	player.select_weapon_slot(1) # Greatsword
	player.global_position = arena.cell_to_world_center(brick_cell) + Vector2(-42.0, 0.0)
	await get_tree().physics_frame
	player.start_attack(arena.cell_to_world_center(brick_cell), PenetrationResolver.AttackType.SLASH)
	player.step_combat_fsm(1.2)
	_assert_true(arena.is_wall_solid_at(0, brick_cell), "Greatsword SLASH at STR=40 cracks Brick wall on hit 1 without 1-shotting")
	_assert_true(arena.get_wall_durability(0, brick_cell) > 0.0 and arena.get_wall_durability(0, brick_cell) < 80.0, "Brick wall durability dropped after hit 1")
	player.refill_resources()
	player.start_attack(arena.cell_to_world_center(brick_cell), PenetrationResolver.AttackType.SLASH)
	player.step_combat_fsm(1.2)
	_assert_false(arena.is_wall_solid_at(0, brick_cell), "Greatsword SLASH at STR=40 shatters cracked Brick wall on hit 2")

	# 1d. Breakable Floor +1 (durability 25.0): Dagger at STR=15 chips it gradually instead of 1-shotting!
	player.stat_sheet.set_mana_awakened(false)
	player.stat_sheet.set_base_stat(StatSheet.Stat.STR, 15.0)
	player.refill_resources()
	player.select_weapon_slot(0) # Short Dagger
	player.verticality.set_floor_level(1)
	player.verticality.set_height_z(0.0)
	player.global_position = arena.cell_to_world_center(floor_cell) + Vector2(-18.0, 0.0)
	await get_tree().physics_frame
	player.start_attack(arena.cell_to_world_center(floor_cell), PenetrationResolver.AttackType.SLASH)
	player.step_combat_fsm(1.0)
	_assert_true(FloorLayerManager.has_floor_at(1, floor_cell), "Dagger at STR=15 cracks Breakable Floor +1 without breaking on hit 1")
	_assert_true(arena.get_floor_durability(1, floor_cell) > 0.0 and arena.get_floor_durability(1, floor_cell) < 25.0, "Floor +1 durability decreased gradually")
	for _s: int in range(5):
		if not FloorLayerManager.has_floor_at(1, floor_cell):
			break
		player.refill_resources()
		player.start_attack(arena.cell_to_world_center(floor_cell), PenetrationResolver.AttackType.SLASH)
		player.step_combat_fsm(1.0)
	_assert_false(FloorLayerManager.has_floor_at(1, floor_cell), "Repeated Dagger strikes break through cracked Floor +1 into a hole")

	# -----------------------------------------------------------------------
	# 2. Multi-Floor Entity & Decal Visibility (Hide Upper Floor Inside Floor 0, Dim Floor 0 from Floor +1)
	# -----------------------------------------------------------------------
	arena.reset_arena_geometry_and_decals()
	player.verticality.set_floor_level(0)
	rank1.verticality.set_floor_level(1)
	rank1.global_position = arena.cell_to_world_center(TestArena.BUILDING_INTERIOR_RECT.position + Vector2i(2, 2))
	troll.verticality.set_floor_level(0)
	troll.global_position = arena.cell_to_world_center(TestArena.BUILDING_INTERIOR_RECT.position + Vector2i(3, 3))
	var f1_blood: Node2D = arena.spawn_blood_decal(rank1.global_position, 1, Vector2.RIGHT, 1.0, false)
	var f0_blood: Node2D = arena.spawn_blood_decal(troll.global_position, 0, Vector2.RIGHT, 1.0, false)

	# Player inside building on Floor 0 -> Floor +1 entities & decals MUST be hidden!
	arena.update_floor_visibility(0, true, true)
	_assert_false(rank1.visible, "Floor +1 enemy is HIDDEN while viewer is inside building on Floor 0")
	_assert_false(f1_blood.visible, "Floor +1 blood decal is HIDDEN while viewer is inside building on Floor 0")
	_assert_true(troll.visible and troll.modulate == TestArena.FLOOR0_BRIGHT_COLOR, "Floor 0 enemy stays visible & bright on Floor 0")
	_assert_true(f0_blood.visible and f0_blood.modulate == TestArena.FLOOR0_BRIGHT_COLOR, "Floor 0 decal stays visible & bright on Floor 0")

	# Player climbs to Floor +1 -> Floor +1 visible/bright; Floor 0 remains visible & dimmed (for yard / broken floor holes)!
	player.verticality.set_floor_level(1)
	arena.update_floor_visibility(1, true, true)
	_assert_true(rank1.visible and rank1.modulate == TestArena.FLOOR0_BRIGHT_COLOR, "Floor +1 enemy becomes visible & bright when viewer ascends to Floor +1")
	_assert_true(f1_blood.visible and f1_blood.modulate == TestArena.FLOOR0_BRIGHT_COLOR, "Floor +1 decal becomes visible & bright on Floor +1")
	_assert_true(troll.visible and troll.modulate == TestArena.FLOOR0_DIMMED_COLOR, "Floor 0 enemy stays visible & dimmed when viewer is on Floor +1")
	_assert_true(f0_blood.visible and f0_blood.modulate == TestArena.FLOOR0_DIMMED_COLOR, "Floor 0 decal is dimmed when viewer is on Floor +1")

	# Dynamic EventBus.floor_changed updates enemy visibility immediately when enemy moves floors!
	rank1.verticality.set_floor_level(0)
	_assert_true(rank1.visible and rank1.modulate == TestArena.FLOOR0_DIMMED_COLOR, "Enemy dropping from Floor +1 -> 0 immediately dims to FLOOR0_DIMMED_COLOR")
	player.verticality.set_floor_level(0)
	arena.update_floor_visibility(0, false, true)

	# -----------------------------------------------------------------------
	# 3. DebugHUD: All 12 Stat Sliders, Perception Regulator, First Aid / Calories & Mini-HUD
	# -----------------------------------------------------------------------
	_assert_eq(hud.stat_sliders.size(), 12, "DebugHUD builds sliders for ALL 12 core stats")
	for s_id: int in StatSheet.ALL_STATS:
		_assert_true(hud.stat_sliders.has(s_id), "DebugHUD has slider for stat %s" % String(StatSheet.get_stat_name(s_id)))
	_assert_eq(_count_focusable_controls(hud), 0, "ALL DebugHUD controls (including 12 sliders, Mini-HUD & Death Overlay) have FOCUS_NONE")

	# Newly added sliders (AGI, STA, MP_CAP, SOUL) update player StatSheet cleanly
	player.stat_sheet.awaken_mana(50.0, 20.0)
	hud.set_player_base_stat(StatSheet.Stat.AGI, 35.0)
	hud.set_player_base_stat(StatSheet.Stat.STA, 45.0)
	hud.set_player_base_stat(StatSheet.Stat.MP_CAP, 80.0)
	hud.set_player_base_stat(StatSheet.Stat.SOUL, 55.0)
	_assert_approx(player.stat_sheet.get_base_stat(StatSheet.Stat.AGI), 35.0, 1e-4, "AGI slider sets base AGI=35")
	_assert_approx(player.stat_sheet.get_base_stat(StatSheet.Stat.STA), 45.0, 1e-4, "STA slider sets base STA=45")
	_assert_approx(player.stat_sheet.get_base_stat(StatSheet.Stat.MP_CAP), 80.0, 1e-4, "MP_CAP slider sets base MP_CAP=80")
	_assert_approx(player.stat_sheet.get_base_stat(StatSheet.Stat.SOUL), 55.0, 1e-4, "SOUL slider sets base SOUL=55")

	# Perception regulator button & slider sync with SimulationClock
	SimulationClock.perception_regulator = 1.0
	_assert_approx(hud.toggle_perception_regulator(), 0.0, 1e-4, "DebugHUD toggle_perception_regulator flips 1.0 -> 0.0")
	_assert_approx(SimulationClock.perception_regulator, 0.0, 1e-4, "SimulationClock.perception_regulator == 0.0")
	hud.set_perception_regulator(0.5)
	_assert_approx(SimulationClock.perception_regulator, 0.5, 1e-4, "DebugHUD slider sets perception_regulator == 0.5")
	_assert_true(hud.btn_toggle_perception.text.contains("0.50"), "Perception button text reflects 0.50")
	hud.set_perception_regulator(1.0)

	# Refill STA/MP/Calories + Bandage & Splint buttons
	player.current_stamina = 5.0
	player.current_mp = 2.0
	player.anatomy.calories = 120.0
	_assert_true(hud.refill_player_resources_and_calories(), "DebugHUD Refill STA/MP/Cal succeeds")
	_assert_approx(player.current_stamina, player.stat_sheet.get_max_stamina(), 1e-3, "Refill restores full stamina")
	_assert_approx(player.current_mp, player.stat_sheet.get_max_mp(), 1e-3, "Refill restores full MP")
	_assert_approx(player.anatomy.calories, player.anatomy.max_calories, 1e-3, "Refill restores full calories")

	player.anatomy.apply_penetrating_hit(AnatomyComponent.ZONE_LEFT_ARM, 6.0, false)
	player.anatomy.apply_blunt_hit(AnatomyComponent.ZONE_LEFT_LEG, 220.0, 1.0, 0.5, false)
	var bnd_count: int = hud.bandage_player_wounds()
	var spl_count: int = hud.splint_player_fractures()
	_assert_true(bnd_count >= 1, "DebugHUD Bandage button bandages player's bleeding wound(s)")
	_assert_true(spl_count >= 1, "DebugHUD Splint button splints player's fracture(s)")
	hud._refresh_all_views()
	_assert_true(hud.lbl_player_wounds.text.contains("[BND]") and hud.lbl_player_wounds.text.contains("[SPL]"), "Anatomy panel displays [BND] and [SPL] badges after first aid")

	# Compact Mini-HUD mode (F2) frees screen center and cleanly restores full panels
	_assert_false(hud.compact_hud_mode, "Starts in full HUD mode")
	_assert_true(hud.toggle_compact_hud(), "toggle_compact_hud activates Mini-HUD mode")
	_assert_false(hud.telemetry_panel.visible or hud.anatomy_panel.visible or hud.debug_panel.visible, "Mini-HUD hides Telemetry, Anatomy & Debug panels")
	_assert_true(hud.mini_hud_panel.visible, "Mini-HUD strip becomes visible")
	_assert_false(hud.toggle_compact_hud(), "Toggling Mini-HUD off restores full HUD panels")
	_assert_true(hud.telemetry_panel.visible and hud.anatomy_panel.visible and hud.debug_panel.visible, "Full HUD panels restored")

	# -----------------------------------------------------------------------
	# 4. Death / Defeat Overlay & Quick Respawn
	# -----------------------------------------------------------------------
	hud.apply_stat_preset(10.0)
	hud.heal_player_all()
	_assert_false(hud.death_overlay.visible, "DeathOverlay hidden while player is alive")
	rank1.engage_target(player)
	player.anatomy.apply_penetrating_hit(AnatomyComponent.ZONE_CHEST, 25.0, true)
	_assert_true(player.anatomy.is_dead, "Player died from lethal Chest strike")
	hud._refresh_all_views()
	_assert_true(hud.death_overlay.visible, "DeathOverlay automatically appears when player dies")
	_assert_true(hud.lbl_death_cause.text.contains("Chest"), "DeathOverlay displays fatal zone (Chest)")

	hud.respawn_player_from_death()
	_assert_true(player.is_alive(), "respawn_player_from_death revives player cleanly")
	_assert_false(hud.death_overlay.visible, "DeathOverlay hides automatically upon respawn")
	_assert_eq(rank1.ai_state, EnemyDummy.AIState.PATROL, "respawn_player_from_death resets enemy aggro to PATROL")

	# -----------------------------------------------------------------------
	# 5. Headless-Safe Procedural Audio Manager (In-Memory PCM WAVs + EventBus)
	# -----------------------------------------------------------------------
	_assert_true(audio_mgr.is_headless_mode, "ProceduralAudioManager detects headless mode safely")
	_assert_eq(audio_mgr.get_registered_cues().size(), 8, "Synthesized all 8 procedural combat sound cues in memory")
	for cue: StringName in [
		ProceduralAudioManager.CUE_SWING_WHOOSH,
		ProceduralAudioManager.CUE_FLESH_HIT,
		ProceduralAudioManager.CUE_METAL_CLASH,
		ProceduralAudioManager.CUE_BLOCK_CLANK,
		ProceduralAudioManager.CUE_BONE_CRUNCH,
		ProceduralAudioManager.CUE_WALL_BREAK,
		ProceduralAudioManager.CUE_AURA_BURST,
		ProceduralAudioManager.CUE_WEAPON_DROP,
	]:
		var clip: AudioStreamWAV = audio_mgr.get_clip(cue)
		_assert_true(clip != null and clip.data.size() > 1000, "Procedural WAV clip '%s' synthesized with non-empty 16-bit PCM buffer" % String(cue))

	var before_sfx: int = audio_mgr.played_cue_count
	player.start_attack(player.global_position + Vector2(30.0, 0.0), PenetrationResolver.AttackType.SLASH)
	_assert_eq(audio_mgr.last_played_cue, ProceduralAudioManager.CUE_SWING_WHOOSH, "Weapon swing emits procedural swing_whoosh cue")
	EventBus.publish_blade_clash({"winner": 1})
	_assert_eq(audio_mgr.last_played_cue, ProceduralAudioManager.CUE_METAL_CLASH, "Blade Clash emits procedural metal_clash cue")
	EventBus.publish_wall_slam(rank1, TestArena.WOOD_WALL_CELLS[0], 300.0, true)
	_assert_eq(audio_mgr.last_played_cue, ProceduralAudioManager.CUE_WALL_BREAK, "Destructive Wall Slam emits procedural wall_break cue")
	EventBus.request_sfx(ProceduralAudioManager.CUE_AURA_BURST, 1.1, 1.0)
	_assert_eq(audio_mgr.last_played_cue, ProceduralAudioManager.CUE_AURA_BURST, "Aura Burst emits procedural aura_burst cue")
	_assert_true(audio_mgr.played_cue_count >= before_sfx + 4, "ProceduralAudioManager tracked all triggered combat cues safely in headless mode")

	remove_child(arena)
	arena.queue_free()
	EventBus.set_debug_highlight_weak_points(false)
	EventBus.set_debug_anti_regen_attacks(false)
	SimulationClock.reset_defaults()


# ===========================================================================
# SUITE 23: Stage A - Full HD Fullscreen, Adaptive HUD Anchors & Unified E-Interact
# ===========================================================================

func _test_stage_a_fullscreen_anchors_and_interact() -> void:
	SimulationClock.reset_defaults()
	WorldCalendar.reset_calendar(0)
	FloorLayerManager.reset(0)

	# 1. Display settings in project.godot (640x360 virtual -> crisp 3x integer scale in 1920x1080 Fullscreen)
	_assert_eq(int(ProjectSettings.get_setting("display/window/size/viewport_width")), 640, "Stage A: virtual viewport_width preserved at 640")
	_assert_eq(int(ProjectSettings.get_setting("display/window/size/viewport_height")), 360, "Stage A: virtual viewport_height preserved at 360")
	_assert_eq(int(ProjectSettings.get_setting("display/window/size/mode")), 3, "Stage A: window/size/mode == 3 (Fullscreen)")
	_assert_eq(int(ProjectSettings.get_setting("display/window/size/window_width_override")), 1920, "Stage A: window_width_override == 1920")
	_assert_eq(int(ProjectSettings.get_setting("display/window/size/window_height_override")), 1080, "Stage A: window_height_override == 1080")
	_assert_eq(String(ProjectSettings.get_setting("display/window/stretch/mode")), "canvas_items", "Stage A: stretch/mode == canvas_items")
	_assert_eq(String(ProjectSettings.get_setting("display/window/stretch/scale_mode")), "integer", "Stage A: stretch/scale_mode == integer (crisp 3x scale)")
	_assert_eq(String(ProjectSettings.get_setting("display/window/stretch/aspect")), "expand", "Stage A: stretch/aspect == expand")

	# toggle_fullscreen InputMap action bound to KEY_F11
	_assert_true(InputMap.has_action(&"toggle_fullscreen"), "Stage A: InputMap has toggle_fullscreen action")
	var fs_events: Array[InputEvent] = InputMap.action_get_events(&"toggle_fullscreen")
	_assert_true(fs_events.size() >= 1 and fs_events[0] is InputEventKey, "Stage A: toggle_fullscreen has InputEventKey")
	if fs_events.size() >= 1 and fs_events[0] is InputEventKey:
		_assert_eq((fs_events[0] as InputEventKey).physical_keycode, KEY_F11, "Stage A: toggle_fullscreen bound to KEY_F11")

	var arena_scene: PackedScene = load("res://scenes/test_arena.tscn") as PackedScene
	var arena: TestArena = arena_scene.instantiate() as TestArena
	add_child(arena)
	arena.set_all_enemies_ai_enabled(false)

	var hud: DebugHUD = arena.get_node_or_null("DebugHUD") as DebugHUD
	var player: PlayerController = arena.entities_container.get_node_or_null("Player") as PlayerController
	var rank1: EnemyDummy = arena.entities_container.get_node_or_null("Rank1Swordsman") as EnemyDummy
	_assert_true(hud != null and player != null and rank1 != null, "Stage A: arena loaded DebugHUD, Player & Rank 1")
	await get_tree().physics_frame

	# Fullscreen toggle is strictly a safe no-op in headless mode and never touches Engine.time_scale
	_assert_false(hud.toggle_fullscreen(), "Stage A: toggle_fullscreen() safely no-ops in headless mode")
	_assert_approx(Engine.time_scale, 1.0, 1e-6, "Stage A: toggle_fullscreen() preserves Engine.time_scale == 1.0")

	# 2. Adaptive UI Anchors for aspect="expand" on AnatomyPanel & DebugPanel
	_assert_approx(hud.anatomy_panel.anchor_left, 0.0, 1e-5, "Stage A: AnatomyPanel anchor_left == 0.0")
	_assert_approx(hud.anatomy_panel.anchor_right, 0.0, 1e-5, "Stage A: AnatomyPanel anchor_right == 0.0")
	_assert_approx(hud.anatomy_panel.anchor_top, 1.0, 1e-5, "Stage A: AnatomyPanel anchor_top == 1.0")
	_assert_approx(hud.anatomy_panel.anchor_bottom, 1.0, 1e-5, "Stage A: AnatomyPanel anchor_bottom == 1.0")
	_assert_approx(hud.anatomy_panel.offset_left, 4.0, 1e-4, "Stage A: AnatomyPanel offset_left == 4.0")
	_assert_approx(hud.anatomy_panel.offset_right, 266.0, 1e-4, "Stage A: AnatomyPanel offset_right == 266.0")
	_assert_approx(hud.anatomy_panel.offset_top, -164.0, 1e-4, "Stage A: AnatomyPanel offset_top == -164.0")
	_assert_approx(hud.anatomy_panel.offset_bottom, -4.0, 1e-4, "Stage A: AnatomyPanel offset_bottom == -4.0")
	_assert_eq(hud.anatomy_panel.focus_mode, Control.FOCUS_NONE, "Stage A: AnatomyPanel keeps FOCUS_NONE")
	_assert_eq(hud.anatomy_panel.mouse_filter, Control.MOUSE_FILTER_IGNORE, "Stage A: AnatomyPanel keeps MOUSE_FILTER_IGNORE")

	_assert_approx(hud.debug_panel.anchor_left, 1.0, 1e-5, "Stage A: DebugPanel anchor_left == 1.0")
	_assert_approx(hud.debug_panel.anchor_right, 1.0, 1e-5, "Stage A: DebugPanel anchor_right == 1.0")
	_assert_approx(hud.debug_panel.anchor_top, 0.0, 1e-5, "Stage A: DebugPanel anchor_top == 0.0")
	_assert_approx(hud.debug_panel.anchor_bottom, 1.0, 1e-5, "Stage A: DebugPanel anchor_bottom == 1.0")
	_assert_approx(hud.debug_panel.offset_left, -188.0, 1e-4, "Stage A: DebugPanel offset_left == -188.0")
	_assert_approx(hud.debug_panel.offset_right, -4.0, 1e-4, "Stage A: DebugPanel offset_right == -4.0")
	_assert_approx(hud.debug_panel.offset_top, 4.0, 1e-4, "Stage A: DebugPanel offset_top == 4.0")
	_assert_approx(hud.debug_panel.offset_bottom, -4.0, 1e-4, "Stage A: DebugPanel offset_bottom == -4.0")
	_assert_eq(hud.debug_panel.focus_mode, Control.FOCUS_NONE, "Stage A: DebugPanel keeps FOCUS_NONE")
	_assert_eq(hud.debug_panel.mouse_filter, Control.MOUSE_FILTER_IGNORE, "Stage A: DebugPanel keeps MOUSE_FILTER_IGNORE")
	_assert_eq(_count_focusable_controls(hud), 0, "Stage A: zero focusable controls in DebugHUD")

	# 3. Unified E (interact) Priority & No Duplicate TestArena Stairs Trigger
	_assert_false(arena.has_method("_unhandled_input"), "Stage A: TestArena no longer has duplicate _unhandled_input stealing interact")

	# Place player directly on STAIRS_RECT (Floor 0) with a lodged blade AND a dropped weapon at feet
	var stairs_pos: Vector2 = arena.get_stairs_center()
	player.revive_and_heal_all()
	player.verticality.set_floor_level(0)
	player.verticality.set_height_z(0.0)
	player.global_position = stairs_pos
	await get_tree().physics_frame
	_assert_true(arena.is_entity_on_stairs(player), "Stage A: Player standing directly on stairs")

	# Empty slot 0 so player can also accept pickups; drop Dagger onto stairs, lodge Rank 1's sword in player Chest
	var dropped_dagger: WeaponData = player.disarm_active_weapon(true, &"stage_a_test")
	_assert_true(dropped_dagger != null and arena.dropped_weapon_pickups.size() == 1, "Stage A: Dagger dropped on stairs floor")
	var lodged_blade: WeaponData = rank1.equipped_weapon.create_runtime_copy()
	player.anatomy.lodge_weapon(AnatomyComponent.ZONE_CHEST, lodged_blade, rank1, 6.0)
	_assert_true(player.anatomy.has_lodged_weapon(), "Stage A: Blade lodged in player on stairs")

	# 3a. Hold E (>= 0.35s) on stairs: careful extraction fires during hold, releasing E does NOT trigger stairs!
	var press_e: InputEventAction = InputEventAction.new()
	press_e.action = &"interact"
	press_e.pressed = true
	player._unhandled_input(press_e)
	_assert_eq(player.get_floor_level(), 0, "Stage A: Pressing E on stairs does NOT warp floor before hold/release")
	player._process(0.40) # Exceeds CAREFUL_EXTRACT_HOLD_SEC (0.35s)
	_assert_false(player.anatomy.has_lodged_weapon(), "Stage A: Holding E >= 0.35s extracts LodgedWeapon carefully")
	_assert_eq(player.get_floor_level(), 0, "Stage A: Holding E on stairs does NOT trigger stairs")
	var release_e: InputEventAction = InputEventAction.new()
	release_e.action = &"interact"
	release_e.pressed = false
	player._unhandled_input(release_e)
	_assert_eq(player.get_floor_level(), 0, "Stage A: Releasing E after hold-extract does NOT trigger stairs")

	# 3b. careful == true with NO lodged blade on stairs: NEVER uses stairs or picks up floor weapon!
	var careful_empty: Dictionary = player.handle_interact_action(true)
	_assert_false(bool(careful_empty.get("handled", true)), "Stage A: careful E with no lodged blade returns handled=false")
	_assert_eq(player.get_floor_level(), 0, "Stage A: careful E never triggers stairs")

	# 3c. Short tap E priority #1: LodgedWeapon extraction beats pickup and stairs!
	player.disarm_active_weapon(false, &"clear_slot_for_prio")
	var lodged_blade2: WeaponData = rank1.equipped_weapon.create_runtime_copy()
	player.anatomy.lodge_weapon(AnatomyComponent.ZONE_CHEST, lodged_blade2, rank1, 6.0)
	var tap1: Dictionary = player.handle_interact_action(false)
	_assert_true(bool(tap1.get("handled", false)), "Stage A: Short tap E priority #1 handled")
	_assert_eq(tap1.get("action", &""), &"extract_lodged", "Stage A: Short tap E prioritizes LodgedWeapon over pickup & stairs")
	_assert_eq(player.get_floor_level(), 0, "Stage A: Priority #1 extraction keeps player on Floor 0")

	# 3d. Short tap E priority #2: Dropped weapon pickup beats stairs when empty slot available!
	player.disarm_active_weapon(false, &"clear_slot_for_pickup")
	var tap2: Dictionary = player.handle_interact_action(false)
	_assert_true(bool(tap2.get("handled", false)), "Stage A: Short tap E priority #2 handled")
	_assert_eq(tap2.get("action", &""), &"pickup", "Stage A: Short tap E prioritizes ground pickup over stairs")
	_assert_eq(player.get_floor_level(), 0, "Stage A: Priority #2 pickup keeps player on Floor 0")

	# 3e. Short tap E priority #3: Stairs activates cleanly when no lodged blade and no ground pickup!
	var tap3: Dictionary = player.handle_interact_action(false)
	_assert_true(bool(tap3.get("handled", false)), "Stage A: Short tap E priority #3 handled")
	_assert_eq(tap3.get("action", &""), &"stairs", "Stage A: Short tap E uses stairs when nothing to extract or pick up")
	_assert_eq(player.get_floor_level(), 1, "Stage A: Player transitions cleanly from Floor 0 -> Floor +1 on stairs")

	remove_child(arena)
	arena.queue_free()
	SimulationClock.reset_defaults()


# ===========================================================================
# SUITE 24: Stage B - Game Combat HUD, KO Overlay, Pause Menu, Reticle &
#           World-Space Indicators / Prompts / Floating Impact Callouts
# ===========================================================================

func _test_stage_b_combat_hud_ko_pause_reticle_and_world_feedback() -> void:
	SimulationClock.reset_defaults()
	WorldCalendar.reset_calendar(0)
	FloorLayerManager.reset(0)
	EventBus.set_debug_highlight_weak_points(false)
	EventBus.set_debug_anti_regen_attacks(false)

	# 1. InputMap has pause_menu bound to KEY_ESCAPE
	_assert_true(InputMap.has_action(&"pause_menu"), "Stage B: InputMap has pause_menu action")
	var pm_events: Array[InputEvent] = InputMap.action_get_events(&"pause_menu")
	_assert_true(pm_events.size() >= 1 and pm_events[0] is InputEventKey, "Stage B: pause_menu has InputEventKey")
	if pm_events.size() >= 1 and pm_events[0] is InputEventKey:
		_assert_eq((pm_events[0] as InputEventKey).physical_keycode, KEY_ESCAPE, "Stage B: pause_menu bound to KEY_ESCAPE")

	var arena_scene: PackedScene = load("res://scenes/test_arena.tscn") as PackedScene
	var arena: TestArena = arena_scene.instantiate() as TestArena
	add_child(arena)
	arena.set_all_enemies_ai_enabled(false)

	var hud: DebugHUD = arena.get_node_or_null("DebugHUD") as DebugHUD
	var player: PlayerController = arena.entities_container.get_node_or_null("Player") as PlayerController
	var rank1: EnemyDummy = arena.entities_container.get_node_or_null("Rank1Swordsman") as EnemyDummy
	var audio_mgr: ProceduralAudioManager = arena.audio_manager
	_assert_true(hud != null and player != null and rank1 != null and audio_mgr != null, "Stage B: Arena loaded HUD, Player, Rank 1 & Audio")
	_assert_true(arena.combat_reticle != null and arena.combat_reticle.z_index == 900, "Stage B: CombatReticle attached on z_index=900")
	await get_tree().physics_frame

	# 1b. Zero focusable controls across ALL new HUD panels, KO overlay & Pause Menu layer
	_assert_eq(_count_focusable_controls(hud), 0, "Stage B: zero focusable controls across DebugHUD, Game HUD, KO & Pause Menu")
	_assert_eq(hud.game_hud_root.mouse_filter, Control.MOUSE_FILTER_IGNORE, "Stage B: game_hud_root has MOUSE_FILTER_IGNORE")
	_assert_eq(hud.mini_hud_panel.mouse_filter, Control.MOUSE_FILTER_IGNORE, "Stage B: mini_hud_panel has MOUSE_FILTER_IGNORE")
	_assert_eq(hud.game_hud_top_right.mouse_filter, Control.MOUSE_FILTER_IGNORE, "Stage B: game_hud_top_right has MOUSE_FILTER_IGNORE")
	_assert_eq(hud.game_hud_weapon_panel.mouse_filter, Control.MOUSE_FILTER_IGNORE, "Stage B: game_hud_weapon_panel has MOUSE_FILTER_IGNORE")
	_assert_eq(hud.ko_overlay.mouse_filter, Control.MOUSE_FILTER_IGNORE, "Stage B: ko_overlay has MOUSE_FILTER_IGNORE")
	_assert_eq(hud.process_mode, Node.PROCESS_MODE_ALWAYS, "Stage B: DebugHUD uses PROCESS_MODE_ALWAYS")
	_assert_true(hud.pause_layer != null and hud.pause_layer.layer == 65, "Stage B: PauseLayer placed at layer 65")

	# 2. Full Game Combat HUD (compact_hud_mode / F2)
	_assert_false(hud.game_hud_root.visible, "Stage B: Game Combat HUD starts hidden in default Debug mode")
	_assert_true(hud.set_compact_hud_mode(true), "Stage B: set_compact_hud_mode(true) switches to Game Combat HUD")
	_assert_true(hud.game_hud_root.visible and hud.mini_hud_panel.visible, "Stage B: Game Combat HUD root & vitals panel visible")
	_assert_true(hud.game_hud_top_right.visible and hud.game_hud_weapon_panel.visible, "Stage B: Top-right & Weapon panels visible")
	_assert_false(hud.telemetry_panel.visible or hud.anatomy_panel.visible or hud.debug_panel.visible, "Stage B: Debug panels hidden in Game HUD mode")

	# Unawakened MP shows "Спит"; awakened MP fills bar & displays numeric MP
	_assert_eq(hud.lbl_game_mp.text, "Спит", "Stage B: Unawakened MP label shows 'Спит'")
	_assert_approx(hud.bar_game_mp.value, 0.0, 1e-4, "Stage B: Unawakened MP bar value is 0")
	player.stat_sheet.awaken_mana(40.0, 30.0)
	player.refill_resources()
	hud._refresh_all_views()
	_assert_true(hud.lbl_game_mp.text != "Спит" and hud.bar_game_mp.value > 0.0, "Stage B: Awakened MP bar fills and displays numeric value")

	# Weapon switch, stances, counter window, Dead Zone, TempoMode & Blood Moon badges
	player.select_weapon_slot(1) # Greatsword
	player.set_half_swording(true)
	player.activate_hardening()
	player.set_aura_active(true)
	player.set_block_held(true)
	player.counter_window_timer = 0.45
	arena.combat_reticle.last_state["in_dead_zone"] = true
	SimulationClock.set_tempo_mode(SimulationClock.TempoMode.COMBAT_OVERDRIVE, true, "stage_b_test")
	WorldCalendar.fast_forward_days(float(WorldCalendar.BLOOD_MOON_DAY - WorldCalendar.get_day_of_month()), false)
	hud._refresh_all_views()
	_assert_true(hud.lbl_game_weapon_name.text.contains("Greatsword"), "Stage B: Game HUD weapon panel shows Greatsword")
	_assert_true(hud.game_stance_badges["HALF-SWORD"].visible, "Stage B: HALF-SWORD badge active")
	_assert_true(hud.game_stance_badges["HARDENING"].visible, "Stage B: HARDENING badge active")
	_assert_true(hud.game_stance_badges["AURA"].visible, "Stage B: AURA badge active")
	_assert_true(hud.game_stance_badges["BLOCK"].visible, "Stage B: BLOCK badge active")
	_assert_true(hud.game_stance_badges["COUNTER!"].visible, "Stage B: COUNTER! badge active")
	_assert_true(hud.game_stance_badges["DEAD ZONE"].visible, "Stage B: DEAD ZONE badge active")
	_assert_true(hud.lbl_game_tempo.text.contains("OVERDRIVE"), "Stage B: Game HUD tempo badge shows OVERDRIVE")
	_assert_true(hud.lbl_game_calendar.text.contains("КРОВ. ЛУНА"), "Stage B: Game HUD calendar badge shows Blood Moon")

	# Clean reset of combat stances and restore debug HUD mode
	player.set_half_swording(false)
	player.set_aura_active(false)
	player.set_block_held(false)
	player.hardening_timer = 0.0
	player.counter_window_timer = 0.0
	SimulationClock.set_tempo_mode(SimulationClock.TempoMode.PEACEFUL, true, "stage_b_reset")
	_assert_false(hud.set_compact_hud_mode(false), "Stage B: set_compact_hud_mode(false) restores full Debug HUD")
	_assert_false(hud.game_hud_root.visible, "Stage B: Game Combat HUD hidden again")

	# 3. Knockout (KO) Overlay without soft-locks (Traumatic & Hemorrhagic + Death takeover)
	hud.apply_stat_preset(10.0)
	hud.heal_player_all()
	_assert_false(hud.ko_overlay.visible, "Stage B: KOOverlay hidden while conscious")

	# 3a. Traumatic shock KO -> shows countdown -> natural recovery hides overlay
	player.anatomy.apply_blunt_hit(AnatomyComponent.ZONE_LEFT_ARM, 300.0, 1.0, 1.0, true)
	player.anatomy.apply_blunt_hit(AnatomyComponent.ZONE_RIGHT_ARM, 300.0, 1.0, 1.0, true)
	_assert_true(player.is_alive() and player.anatomy.is_unconscious, "Stage B: Player knocked out by traumatic shock while alive")
	_assert_eq(player.anatomy.knockout_reason, "traumatic_shock", "Stage B: KO reason is traumatic_shock")
	hud._refresh_all_views()
	_assert_true(hud.ko_overlay.visible, "Stage B: KOOverlay appears during traumatic shock KO")
	_assert_false(hud.death_overlay.visible, "Stage B: DeathOverlay remains hidden during non-lethal KO")
	_assert_true(hud.lbl_ko_reason.text.contains("Болевой шок"), "Stage B: KOOverlay displays traumatic shock countdown")
	player.anatomy.tick(65.0) # Full 60s baseline traumatic shock KO timer expires cleanly
	hud._refresh_all_views()
	_assert_false(player.anatomy.is_unconscious, "Stage B: Player recovers naturally from traumatic shock KO")
	_assert_false(hud.ko_overlay.visible, "Stage B: KOOverlay hides automatically upon consciousness recovery")

	# 3b. Hemorrhagic shock KO (no auto-recovery) -> emergency button recovers cleanly (no soft-lock!)
	player.anatomy.blood_volume = player.anatomy.max_blood_volume * 0.45 # 55% blood loss (> 45% KO, < 65% death)
	player.anatomy.tick(0.05)
	_assert_true(player.is_alive() and player.anatomy.is_unconscious, "Stage B: Player enters hemorrhagic shock KO at 55% blood loss")
	_assert_eq(player.anatomy.knockout_reason, "hemorrhagic_shock", "Stage B: KO reason is hemorrhagic_shock")
	_assert_true(player.anatomy.knockout_timer < 0.0, "Stage B: Hemorrhagic shock KO has no auto-recovery timer")
	hud._refresh_all_views()
	_assert_true(hud.ko_overlay.visible, "Stage B: KOOverlay appears during hemorrhagic shock KO")
	_assert_true(hud.lbl_ko_reason.text.contains("Критическая кровопотеря"), "Stage B: KOOverlay warns about critical blood loss")
	hud.recover_player_from_ko()
	_assert_true(player.is_alive() and not player.anatomy.is_unconscious, "Stage B: recover_player_from_ko prevents eternal hemorrhagic soft-lock")
	_assert_false(hud.ko_overlay.visible, "Stage B: KOOverlay hides after emergency KO recovery")

	# 3c. Death supersedes KO overlay cleanly
	player.anatomy.blood_volume = player.anatomy.max_blood_volume * 0.45
	player.anatomy.tick(0.05)
	player.anatomy.apply_penetrating_hit(AnatomyComponent.ZONE_CHEST, 25.0, true)
	hud._refresh_all_views()
	_assert_false(hud.ko_overlay.visible, "Stage B: KOOverlay hides when player dies")
	_assert_true(hud.death_overlay.visible, "Stage B: DeathOverlay takes over on death")
	hud.respawn_player_from_death()

	# 4. Pause Menu (Esc) & ProceduralAudioManager Mute / Volume Wiring
	_assert_false(hud.is_pause_menu_open or hud.pause_overlay.visible, "Stage B: Pause menu starts closed")
	_assert_true(hud.toggle_pause_menu(), "Stage B: toggle_pause_menu opens pause overlay")
	_assert_true(hud.pause_overlay.visible, "Stage B: Pause overlay is visible")
	_assert_false(get_tree().paused, "Stage B: Pause menu never freezes SceneTree in headless/test_runner mode")
	_assert_approx(Engine.time_scale, 1.0, 1e-6, "Stage B: Pause menu preserves Engine.time_scale == 1.0")

	hud.set_audio_muted(true)
	_assert_true(audio_mgr.muted and hud.chk_pause_mute.button_pressed, "Stage B: Pause menu mute checkbox syncs to ProceduralAudioManager.muted")
	_assert_false(audio_mgr.play_cue(ProceduralAudioManager.CUE_SWING_WHOOSH), "Stage B: Muted ProceduralAudioManager suppresses audio cues")
	hud.set_audio_muted(false)
	_assert_false(audio_mgr.muted, "Stage B: Unmuting restores ProceduralAudioManager.muted == false")
	hud.set_audio_volume_db(-14.0)
	_assert_approx(audio_mgr.master_volume_db, -14.0, 1e-4, "Stage B: Pause volume slider syncs to ProceduralAudioManager.master_volume_db")
	_assert_true(hud.lbl_pause_volume.text.contains("-14"), "Stage B: Volume label updates to -14 dB")
	hud.set_audio_volume_db(-6.0)
	_assert_false(hud.set_pause_menu_open(false), "Stage B: Closing pause menu sets is_pause_menu_open == false")
	_assert_false(hud.pause_overlay.visible, "Stage B: Pause overlay hidden when closed")

	# 5. Procedural Combat Reticle (Attack mode, Dead Zone warning, Half-swording & Weak-Point lock)
	player.verticality.set_floor_level(0)
	player.verticality.set_height_z(0.0)
	rank1.revive_and_heal_all()
	rank1.verticality.set_floor_level(0)
	rank1.verticality.set_height_z(0.0)
	player.global_position = arena.cell_to_world_center(Vector2i(10, 6))
	rank1.global_position = player.global_position + Vector2(26.0, 0.0) # Surface gap ~= 10px < Greatsword min_optimal_range (28px)
	await get_tree().physics_frame

	player.select_weapon_slot(1) # Greatsword
	player.set_half_swording(false)
	player.current_attack_type = PenetrationResolver.AttackType.THRUST
	var ret_dz: Dictionary = arena.combat_reticle.evaluate_reticle_state(player, rank1.global_position)
	_assert_true(bool(ret_dz["visible"]), "Stage B: CombatReticle visible for live player")
	_assert_eq(int(ret_dz["attack_type"]), int(PenetrationResolver.AttackType.THRUST), "Stage B: CombatReticle reflects THRUST mode")
	_assert_true(bool(ret_dz["in_dead_zone"]), "Stage B: CombatReticle flags Dead Zone for close Greatsword target")
	_assert_false(bool(ret_dz["weak_point_locked"]), "Stage B: Weak-point lock inactive at INT=10 without debug highlight")

	player.set_half_swording(true)
	var ret_hs: Dictionary = arena.combat_reticle.evaluate_reticle_state(player, rank1.global_position)
	_assert_false(bool(ret_hs["in_dead_zone"]), "Stage B: Half-swording clears CombatReticle Dead Zone warning")
	_assert_true(bool(ret_hs["half_swording"]), "Stage B: CombatReticle reflects Half-swording tightening")
	player.set_half_swording(false)

	# Enable weak-point visibility via INT=300 and aim directly on Rank 1 Head weak point
	hud.apply_int_300_preset()
	var r1_head_wp: Vector2 = rank1.global_position
	for hz: HitboxZone in rank1.hitbox_zones:
		if hz.zone_name == AnatomyComponent.ZONE_HEAD and not hz.get_world_weak_points().is_empty():
			r1_head_wp = hz.get_world_weak_points()[0]
			break
	var ret_wp: Dictionary = arena.combat_reticle.evaluate_reticle_state(player, r1_head_wp)
	_assert_true(bool(ret_wp["weak_point_locked"]), "Stage B: CombatReticle locks onto weak point when INT>=300 & cursor within aim tolerance")
	var ret_far: Dictionary = arena.combat_reticle.evaluate_reticle_state(player, r1_head_wp + Vector2(120.0, 0.0))
	_assert_false(bool(ret_far["weak_point_locked"]), "Stage B: CombatReticle releases weak-point lock when cursor moves away")
	hud.apply_stat_preset(10.0)

	# 6. Enemy World-Space Status Indicator (PATROL / SEARCH / COMBAT + tags + selective micro-bars)
	rank1.revive_and_heal_all()
	rank1.reset_aggro(0.0)
	var st_patrol: Dictionary = rank1.update_world_status_overlay()
	_assert_true(bool(st_patrol["visible"]), "Stage B: Healthy enemy status overlay visible")
	_assert_eq(String(st_patrol["ai_marker"]), "PATROL", "Stage B: Patrolling enemy shows PATROL marker")
	_assert_false(bool(st_patrol["bars_visible"]), "Stage B: Healthy patrolling enemy hides Blood/Shock micro-bars")

	rank1._set_ai_state(EnemyDummy.AIState.SEARCH)
	var st_search: Dictionary = rank1.update_world_status_overlay()
	_assert_eq(String(st_search["ai_marker"]), "?", "Stage B: Searching enemy shows '?' marker")
	_assert_true(bool(st_search["bars_visible"]), "Stage B: Searching enemy shows Blood/Shock micro-bars")

	rank1.engage_target(player)
	rank1.activate_hardening()
	rank1.apply_stagger(0.8)
	var st_combat: Dictionary = rank1.update_world_status_overlay()
	_assert_eq(String(st_combat["ai_marker"]), "!", "Stage B: Combat enemy shows '!' marker")
	_assert_true(bool(st_combat["bars_visible"]), "Stage B: Combat enemy shows Blood/Shock micro-bars")
	var st_tags: Array = st_combat["status_tags"] as Array
	_assert_true(st_tags.has("STAGGER") and st_tags.has("HARD"), "Stage B: Enemy overlay reports STAGGER and HARD tags")

	rank1.set_prone(2.0)
	rank1.anatomy.apply_blunt_hit(AnatomyComponent.ZONE_LEFT_ARM, 300.0, 1.0, 1.0, true)
	rank1.anatomy.apply_blunt_hit(AnatomyComponent.ZONE_RIGHT_ARM, 300.0, 1.0, 1.0, true)
	var st_ko_prone: Dictionary = rank1.update_world_status_overlay()
	var ko_tags: Array = st_ko_prone["status_tags"] as Array
	_assert_true(ko_tags.has("PRONE") and ko_tags.has("KO"), "Stage B: Enemy overlay reports PRONE and KO tags")

	rank1.anatomy.apply_penetrating_hit(AnatomyComponent.ZONE_HEAD, 25.0, true)
	var st_dead: Dictionary = rank1.update_world_status_overlay()
	_assert_false(bool(st_dead["visible"]) or bool(st_dead["bars_visible"]), "Stage B: Dead enemy hides world status overlay & micro-bars")

	# 7. Contextual World [E] Prompt Priority & Floating Combat Callouts
	player.revive_and_heal_all()
	player.verticality.set_floor_level(0)
	player.verticality.set_height_z(0.0)
	player.global_position = arena.get_stairs_center()
	await get_tree().physics_frame

	# Drop slot 0 Dagger onto stairs & lodge blade into player Chest -> Priority #1 extract_lodged
	player.select_weapon_slot(0)
	player.disarm_active_weapon(true, &"stage_b_prompt_test")
	var lodged_wpn: WeaponData = load(PlayerController.DAGGER_TEMPLATE_PATH).create_runtime_copy()
	player.anatomy.lodge_weapon(AnatomyComponent.ZONE_CHEST, lodged_wpn, null, 4.0)
	var p1: Dictionary = player.compute_interact_prompt()
	_assert_true(bool(p1["visible"]), "Stage B: Contextual [E] prompt visible for LodgedWeapon")
	_assert_eq(p1["action"], &"extract_lodged", "Stage B: Prompt Priority #1 is extract_lodged over pickup & stairs")
	_assert_true(String(p1["text"]).contains("Вырвать") and String(p1["text"]).contains("Аккуратно"), "Stage B: Lodged prompt explains tap vs hold E")

	# Remove lodged weapon & keep empty slot -> Priority #2 pickup
	player.handle_interact_action(true)
	player.disarm_active_weapon(false, &"clear_slot_prompt2")
	var p2: Dictionary = player.compute_interact_prompt()
	_assert_eq(p2["action"], &"pickup", "Stage B: Prompt Priority #2 is ground weapon pickup over stairs")
	_assert_true(String(p2["text"]).contains("Поднять"), "Stage B: Pickup prompt displays '[E] Поднять <weapon>'")

	# Pick up dropped weapon -> Priority #3 stairs
	player.handle_interact_action(false)
	var p3: Dictionary = player.compute_interact_prompt()
	_assert_eq(p3["action"], &"stairs", "Stage B: Prompt Priority #3 is stairs when no lodged blade or pickup")
	_assert_eq(String(p3["text"]), "[E] Этаж +1", "Stage B: Stairs prompt shows '[E] Этаж +1' from Floor 0")

	# Move away from stairs -> hidden
	player.global_position = arena.cell_to_world_center(Vector2i(10, 6))
	await get_tree().physics_frame
	var p4: Dictionary = player.compute_interact_prompt()
	_assert_false(bool(p4["visible"]), "Stage B: Contextual [E] prompt hides when nothing interactable is nearby")

	# Floating world-space impact callouts triggered via EventBus
	arena.reset_arena_geometry_and_decals()
	EventBus.publish_combat_outcome({"attacker": player, "target": rank1, "outcome": "parried"})
	_assert_eq(arena.last_floating_callout_text, "PARRY!", "Stage B: EventBus 'parried' spawns PARRY! floating callout")
	EventBus.publish_combat_outcome({"attacker": player, "target": rank1, "outcome": "guard_break_hit"})
	_assert_eq(arena.last_floating_callout_text, "GUARD BREAK!", "Stage B: EventBus 'guard_break_hit' spawns GUARD BREAK! callout")
	EventBus.publish_combat_outcome({"attacker": player, "target": rank1, "outcome": "out_of_vertical_reach"})
	_assert_eq(arena.last_floating_callout_text, "OUT OF REACH [F]", "Stage B: EventBus 'out_of_vertical_reach' spawns OUT OF REACH [F] callout")
	EventBus.publish_combat_outcome({"attacker": player, "target": rank1, "outcome": "penetrated", "is_weak_point": true})
	_assert_eq(arena.last_floating_callout_text, "WEAK-POINT!", "Stage B: EventBus weak-point hit spawns WEAK-POINT! callout")
	EventBus.publish_blade_clash({"winner": 1, "actor_a": player, "actor_b": rank1})
	_assert_eq(arena.last_floating_callout_text, "CLASH!", "Stage B: EventBus blade_clashed spawns CLASH! callout")
	EventBus.publish_wall_slam(rank1, TestArena.WOOD_WALL_CELLS[0], 300.0, true)
	_assert_eq(arena.last_floating_callout_text, "WALL BREAK!", "Stage B: EventBus wall_slammed (broken) spawns WALL BREAK! callout")
	_assert_true(arena.active_floating_callout_count >= 6, "Stage B: Floating callouts spawned cleanly on effects_container")

	remove_child(arena)
	arena.queue_free()
	EventBus.set_debug_highlight_weak_points(false)
	EventBus.set_debug_anti_regen_attacks(false)
	SimulationClock.reset_defaults()
	WorldCalendar.reset_calendar(0)


# ===========================================================================
# SUITE 25: Stage C - Disarmed AI, Directional & Unarmed Block, Stealth
#           Backstab (+35%), THRUST Lunge, Block Arc & WorldCalendar Visuals
# ===========================================================================

func _test_stage_c_melee_polish_disarmed_ai_and_calendar_visuals() -> void:
	SimulationClock.reset_defaults()
	WorldCalendar.reset_calendar(12) # Start at bright midday (12:00)
	FloorLayerManager.reset(0)
	EventBus.set_debug_highlight_weak_points(false)
	EventBus.set_debug_anti_regen_attacks(false)

	var arena_scene: PackedScene = load("res://scenes/test_arena.tscn") as PackedScene
	var arena: TestArena = arena_scene.instantiate() as TestArena
	add_child(arena)
	arena.set_all_enemies_ai_enabled(false)

	var hud: DebugHUD = arena.get_node_or_null("DebugHUD") as DebugHUD
	var player: PlayerController = arena.entities_container.get_node_or_null("Player") as PlayerController
	var rank1: EnemyDummy = arena.entities_container.get_node_or_null("Rank1Swordsman") as EnemyDummy
	_assert_true(hud != null and player != null and rank1 != null, "Stage C: Arena loaded HUD, Player & Rank 1")
	await get_tree().physics_frame

	# -----------------------------------------------------------------------
	# 1. Disarmed EnemyDummy retrieves dropped weapon & extracts lodged blades
	# -----------------------------------------------------------------------
	player.revive_and_heal_all()
	rank1.revive_and_heal_all()
	rank1.reset_aggro(0.0)
	var open_origin: Vector2 = arena.cell_to_world_center(Vector2i(11, 6))
	rank1.global_position = open_origin
	player.global_position = open_origin + Vector2(105.0, 0.0)
	await get_tree().physics_frame

	var dropped_sword: WeaponData = rank1.disarm_active_weapon(true, &"stage_c_disarm")
	_assert_true(dropped_sword != null and rank1.is_unarmed(), "Stage C: Rank 1 disarmed cleanly to Unarmed (Fists)")
	# Place dropped pickup 70px away from rank1 (within 120px retrieval radius, outside 40px instant pickup)
	var pickup_pos: Vector2 = open_origin + Vector2(-70.0, 0.0)
	var pickup_entry: Dictionary = arena.dropped_weapon_pickups[0]
	var pickup_node: Node2D = pickup_entry["node"] as Node2D
	pickup_node.position = pickup_pos
	pickup_entry["pos"] = pickup_pos

	var found_drop: Dictionary = arena.find_nearest_dropped_weapon(rank1.global_position, 0, 120.0)
	_assert_true(bool(found_drop["found"]), "Stage C: TestArena.find_nearest_dropped_weapon locates sword within 120px")
	var far_drop: Dictionary = arena.find_nearest_dropped_weapon(rank1.global_position, 0, 30.0)
	_assert_false(bool(far_drop["found"]), "Stage C: TestArena.find_nearest_dropped_weapon respects max_radius")
	var wrong_floor_drop: Dictionary = arena.find_nearest_dropped_weapon(rank1.global_position, 1, 120.0)
	_assert_false(bool(wrong_floor_drop["found"]), "Stage C: TestArena.find_nearest_dropped_weapon filters by floor_level")

	# Engage Rank 1 in COMBAT -> disarmed enemy steers to dropped sword and picks it up!
	rank1.engage_target(player)
	var steered_toward_sword: bool = false
	for _step: int in range(30):
		var vel: Vector2 = rank1.step_ai_tick(0.05, 0.05)
		if vel.x < -20.0:
			steered_toward_sword = true
		rank1.move_with_substepping(vel, 0.05, false, true)
		if not rank1.is_unarmed():
			break
	_assert_true(steered_toward_sword, "Stage C: Disarmed EnemyDummy steers toward nearby dropped sword")
	_assert_false(rank1.is_unarmed(), "Stage C: Disarmed EnemyDummy picks up dropped sword and returns to combat armed")
	_assert_eq(arena.dropped_weapon_pickups.size(), 0, "Stage C: Ground pickup removed cleanly after enemy retrieval")

	# EnemyDummy extracts lodged weapon when disengaged (SEARCH) with 3.0s cooldown (not while staggered)
	var dagger_tpl: WeaponData = load(PlayerController.DAGGER_TEMPLATE_PATH) as WeaponData
	rank1.reset_aggro(0.0)
	rank1._set_ai_state(EnemyDummy.AIState.SEARCH)
	rank1.search_timer = 4.0
	rank1._lodged_extract_cooldown = 0.0
	rank1.anatomy.lodge_weapon(AnatomyComponent.ZONE_CHEST, dagger_tpl.create_runtime_copy(), player, 5.0)
	_assert_true(rank1.anatomy.has_lodged_weapon(), "Stage C: Dagger lodged inside Rank 1 Chest")
	# While STAGGERED, AI cannot extract
	rank1.apply_stagger(0.5)
	rank1.step_ai_tick(0.05, 0.05)
	_assert_true(rank1.anatomy.has_lodged_weapon(), "Stage C: Staggered EnemyDummy cannot extract lodged weapon")
	# Once IDLE in SEARCH, AI pulls out the lodged blade and starts 3.0s cooldown
	rank1.combat_state = CombatActor.CombatState.IDLE
	rank1.state_timer = 0.0
	rank1.step_ai_tick(0.05, 0.05)
	_assert_false(rank1.anatomy.has_lodged_weapon(), "Stage C: EnemyDummy extracts lodged weapon during SEARCH")
	_assert_true(rank1._lodged_extract_cooldown > 2.5, "Stage C: Lodged extraction enforces 3.0s cooldown")

	# -----------------------------------------------------------------------
	# 2. Directional Block (+/-75 deg), Unarmed Block Realism & Stealth Backstab (+35%)
	# -----------------------------------------------------------------------
	arena.reset_arena_geometry_and_decals()
	player.revive_and_heal_all()
	rank1.revive_and_heal_all()
	rank1.reset_aggro(0.0)
	player.stat_sheet.set_mana_awakened(false)
	player.stat_sheet.set_all_base_stats(10.0, false)
	player.refill_resources()
	player.select_weapon_slot(0) # Short Dagger

	rank1.global_position = open_origin
	rank1.aim_angle = 0.0 # Facing RIGHT (+X)
	var r1_chest: HitboxZone = _find_zone(rank1, AnatomyComponent.ZONE_CHEST)

	# 2a. Front attack (+X, 0 deg) -> BLOCKED by passive hold-Block
	player.global_position = open_origin + Vector2(24.0, 0.0)
	rank1.refill_resources()
	rank1.is_blocking = true
	rank1.parry_window_timer = 0.0
	var front_blk: Dictionary = rank1.receive_melee_hit(player, r1_chest, player.get_active_weapon(), false, 1.0, false, PenetrationResolver.AttackType.SLASH)
	_assert_eq(String(front_blk["outcome"]), "blocked", "Stage C: Frontal strike (0 deg) is stopped by directional hold-Block")

	# 2b. Flank attack (+Y, 90 deg > 75 deg) -> bypasses passive hold-Block!
	rank1.revive_and_heal_all()
	rank1.aim_angle = 0.0
	rank1.is_blocking = true
	rank1.parry_window_timer = 0.0
	player.global_position = open_origin + Vector2(0.0, 24.0)
	var flank_hit: Dictionary = rank1.receive_melee_hit(player, r1_chest, player.get_active_weapon(), false, 1.0, false, PenetrationResolver.AttackType.SLASH)
	_assert_neq(String(flank_hit["outcome"]), "blocked", "Stage C: Flank strike (90 deg > 75 deg) bypasses passive hold-Block")

	# 2c. Rear backstab (-X, 180 deg) -> bypasses BOTH passive hold-Block AND parry window (> 110 deg)!
	rank1.revive_and_heal_all()
	rank1.aim_angle = 0.0
	rank1.trigger_block_pressed()
	player.global_position = open_origin + Vector2(-24.0, 0.0)
	var rear_hit: Dictionary = rank1.receive_melee_hit(player, r1_chest, player.get_active_weapon(), false, 1.0, false, PenetrationResolver.AttackType.SLASH)
	_assert_neq(String(rear_hit["outcome"]), "parried", "Stage C: Rear strike (180 deg) bypasses Deflect/Parry window")
	_assert_neq(String(rear_hit["outcome"]), "blocked", "Stage C: Rear strike (180 deg) bypasses passive hold-Block")

	# 2d. Wide frontal-flank Deflect/Parry (95 deg <= 110 deg) -> succeeds during 0.18s parry window
	rank1.revive_and_heal_all()
	rank1.aim_angle = 0.0
	rank1.trigger_block_pressed()
	player.global_position = open_origin + Vector2.from_angle(deg_to_rad(95.0)) * 24.0
	var wide_parry: Dictionary = rank1.receive_melee_hit(player, r1_chest, player.get_active_weapon(), false, 1.0, false, PenetrationResolver.AttackType.SLASH)
	_assert_eq(String(wide_parry["outcome"]), "parried", "Stage C: Active 0.18s Deflect/Parry window catches wide 95 deg flank")

	# 2e. Unarmed passive block against sharp steel & heavy Warhammer
	rank1.revive_and_heal_all()
	rank1.disarm_active_weapon(false, &"stage_c_unarmed_blk")
	_assert_true(rank1.is_unarmed(), "Stage C: Defender is unarmed for unarmed-block check")
	player.global_position = open_origin + Vector2(24.0, 0.0)
	rank1.aim_angle = 0.0 # Facing attacker
	rank1.is_blocking = true
	rank1.parry_window_timer = 0.0
	player.select_weapon_slot(0) # Sharp Short Dagger (edge_sharpness=1.0)
	var unarmed_sharp: Dictionary = rank1.receive_melee_hit(player, r1_chest, player.get_active_weapon(), false, 1.0, false, PenetrationResolver.AttackType.SLASH)
	_assert_eq(String(unarmed_sharp["outcome"]), "unarmed_block_cut", "Stage C: Unarmed passive block vs sharp steel bleeds through onto forearm (unarmed_block_cut)")
	_assert_true(rank1.anatomy.get_wounds(AnatomyComponent.ZONE_LEFT_ARM).size() >= 1 or rank1.anatomy.get_wounds(AnatomyComponent.ZONE_RIGHT_ARM).size() >= 1, "Stage C: Sharp steel cuts bare blocking arm instead of free stop")

	rank1.revive_and_heal_all()
	rank1.disarm_active_weapon(false, &"stage_c_unarmed_wh")
	rank1.aim_angle = 0.0
	rank1.is_blocking = true
	rank1.parry_window_timer = 0.0
	player.select_weapon_slot(2) # Heavy Warhammer (mass=36)
	var unarmed_blunt: Dictionary = rank1.receive_melee_hit(player, r1_chest, player.get_active_weapon(), false, 1.0, false, PenetrationResolver.AttackType.BLUNT)
	_assert_eq(String(unarmed_blunt["outcome"]), "guard_break_hit", "Stage C: Heavy Warhammer smashes straight through unarmed passive block (guard_break_hit)")

	# 2f. Stealth / Backstab +35% weak-point aim_tolerance & precision_radius (GDD 7.4)
	player.revive_and_heal_all()
	rank1.revive_and_heal_all()
	rank1.reset_aggro(0.0)
	player.stat_sheet.set_mana_awakened(false)
	player.stat_sheet.set_all_base_stats(10.0, false)
	player.select_weapon_slot(0) # Dagger
	rank1.global_position = open_origin
	rank1.aim_angle = 0.0 # Facing RIGHT, patrolling unaware
	player.global_position = open_origin + Vector2(-22.0, 0.0) # Directly behind Rank 1!
	await get_tree().physics_frame

	_assert_true(rank1.is_vulnerable_to_stealth_backstab(player), "Stage C: Patrolling enemy approached from behind is vulnerable to stealth backstab")
	var base_tol: float = WeaponRaySweeper.get_aim_tolerance_px(player.stat_sheet, PenetrationResolver.AttackType.THRUST, false)
	var r1_head: HitboxZone = _find_zone(rank1, AnatomyComponent.ZONE_HEAD)
	var head_wp: Vector2 = r1_head.get_world_weak_points()[0]
	# Aim offset at 1.18x base_tol: MISSES weak point normally (> 1.0x), HITS weak point on stealth backstab (<= 1.35x)!
	var edge_aim: Vector2 = head_wp + Vector2(0.0, -base_tol * 1.18)
	var thrust_angle: float = (head_wp - player.get_combat_origin()).angle()

	# First verify from BEHIND in PATROL -> stealth backstab triggers weak point!
	player.sweeper.begin_swing(thrust_angle, PenetrationResolver.AttackType.THRUST, false)
	var backstab_evs: Array[Dictionary] = player.sweeper.sweep_to_angle(
		player.global_position, thrust_angle, player.get_active_weapon(), player.stat_sheet,
		0, 0.0, false, edge_aim, player, arena, false, player.get_combat_origin(),
		PenetrationResolver.AttackType.THRUST, false, 1.0, false
	)
	var bs_hit: Dictionary = {}
	for ev: Dictionary in backstab_evs:
		if String(ev.get("type", "")) == "entity":
			bs_hit = ev
			break
	player.sweeper.end_swing()
	_assert_true(not bs_hit.is_empty() and bool(bs_hit.get("is_stealth_backstab", false)), "Stage C: Sweep behind patrolling enemy flags is_stealth_backstab=true")
	_assert_true(bool(bs_hit.get("is_weak_point", false)), "Stage C: +35% stealth backstab tolerance turns 1.18x-offset aim into a weak-point hit")

	# Same offset from FRONT (facing player, non-stealth) -> NOT a weak point!
	rank1.aim_angle = PI # Now facing LEFT toward player
	_assert_false(rank1.is_vulnerable_to_stealth_backstab(player), "Stage C: Facing enemy is NOT vulnerable to stealth backstab")
	player.sweeper.begin_swing(thrust_angle, PenetrationResolver.AttackType.THRUST, false)
	var frontal_evs: Array[Dictionary] = player.sweeper.sweep_to_angle(
		player.global_position, thrust_angle, player.get_active_weapon(), player.stat_sheet,
		0, 0.0, false, edge_aim, player, arena, false, player.get_combat_origin(),
		PenetrationResolver.AttackType.THRUST, false, 1.0, false
	)
	var fr_hit: Dictionary = {}
	for ev: Dictionary in frontal_evs:
		if String(ev.get("type", "")) == "entity":
			fr_hit = ev
			break
	player.sweeper.end_swing()
	_assert_true(not fr_hit.is_empty() and not bool(fr_hit.get("is_stealth_backstab", false)), "Stage C: Frontal sweep is not flagged as stealth backstab")
	_assert_false(bool(fr_hit.get("is_weak_point", false)), "Stage C: Same 1.18x-offset aim misses weak point from the front without stealth bonus")

	# -----------------------------------------------------------------------
	# 3. Visual THRUST Lunge (weapon_pivot.position) & Block Guard Arc (block_arc_line)
	# -----------------------------------------------------------------------
	player.revive_and_heal_all()
	player.select_weapon_slot(1) # Greatsword
	player.global_position = open_origin
	var thrust_target: Vector2 = open_origin + Vector2(60.0, 0.0)
	_assert_true(player.start_attack(thrust_target, PenetrationResolver.AttackType.THRUST), "Stage C: Started THRUST attack")
	_assert_eq(player.combat_state, CombatActor.CombatState.WINDUP, "Stage C: THRUST enters WINDUP")
	_assert_approx(player.weapon_pivot.position.length(), 0.0, 1e-4, "Stage C: weapon_pivot.position stays at ZERO during WINDUP")

	# Advance past windup into mid-ACTIVE
	var windup_dur: float = player.state_timer
	player.step_combat_fsm(windup_dur + 0.04)
	_assert_eq(player.combat_state, CombatActor.CombatState.ACTIVE, "Stage C: THRUST enters ACTIVE phase")
	_assert_true(player.weapon_pivot.position.length() > 4.0, "Stage C: weapon_pivot lunges forward during THRUST ACTIVE (len=%.1f)" % player.weapon_pivot.position.length())
	var lunge_dot: float = player.weapon_pivot.position.normalized().dot(Vector2.from_angle(player.aim_angle))
	_assert_true(lunge_dot > 0.99, "Stage C: weapon_pivot lunge aligns strictly along aim_angle")

	# Finish ACTIVE -> RECOVERY -> IDLE -> weapon_pivot returns cleanly to Vector2.ZERO
	player.step_combat_fsm(1.2)
	_assert_eq(player.combat_state, CombatActor.CombatState.IDLE, "Stage C: THRUST completes back to IDLE")
	_assert_approx(player.weapon_pivot.position.length(), 0.0, 1e-4, "Stage C: weapon_pivot.position returns cleanly to Vector2.ZERO after THRUST")

	# Directional Block Guard Arc visual
	_assert_true(player.block_arc_line != null and not player.block_arc_line.visible, "Stage C: BlockArc hidden while not blocking")
	player.aim_angle = deg_to_rad(35.0)
	player.set_block_held(true)
	_assert_true(player.block_arc_line.visible, "Stage C: BlockArc visible while holding block")
	_assert_approx(player.block_arc_line.rotation, deg_to_rad(35.0), 1e-4, "Stage C: BlockArc oriented to actor aim_angle")
	player.set_block_held(false)
	_assert_false(player.block_arc_line.visible, "Stage C: BlockArc hides when block is released")

	# -----------------------------------------------------------------------
	# 4. WorldCalendar Visual Cycle (CanvasModulate) & Night / Blood Moon Vision
	# -----------------------------------------------------------------------
	_assert_true(arena.ambient_modulate != null and arena.ambient_modulate.get_parent() == arena, "Stage C: CanvasModulate attached directly to TestArena (keeps DebugHUD CanvasLayer un-darkened)")

	# 4a. Day (12:00, Day 1): neutral WHITE & full 150px aggro_radius
	arena.reset_arena_geometry_and_decals()
	WorldCalendar.reset_calendar(12)
	arena.update_ambient_lighting()
	_assert_eq(arena.ambient_modulate.color, TestArena.AMBIENT_COLOR_DAY, "Stage C: Daytime (12:00) sets CanvasModulate to Color.WHITE")
	_assert_approx(rank1.get_effective_aggro_radius_px(), rank1.aggro_radius_px, 1e-3, "Stage C: Daytime aggro radius is 1.0x (150px)")

	# Position in open south corridor (row y=14, completely unobstructed x=1..24) 115px apart -> spotted during Day (130px)!
	rank1.revive_and_heal_all()
	rank1.reset_aggro(0.0)
	rank1.global_position = arena.cell_to_world_center(Vector2i(11, 14))
	rank1.aim_angle = 0.0
	player.global_position = rank1.global_position + Vector2(115.0, 0.0)
	await get_tree().physics_frame
	rank1.step_ai_tick(0.05, 0.05)
	_assert_eq(rank1.ai_state, EnemyDummy.AIState.COMBAT, "Stage C: Enemy spots player at 115px during daytime (radius 130px)")

	# 4b. Night (22:00, Day 1): atmospheric blue twilight & 0.72x vision radius (93.6px)
	rank1.reset_aggro(0.0)
	WorldCalendar.reset_calendar(22)
	arena.update_ambient_lighting()
	_assert_eq(arena.ambient_modulate.color, TestArena.AMBIENT_COLOR_NIGHT, "Stage C: Nighttime (22:00) sets CanvasModulate to bluish twilight")
	_assert_true(arena.ambient_modulate.color.b > arena.ambient_modulate.color.r, "Stage C: Night twilight has cool blue tint")
	_assert_approx(rank1.get_effective_aggro_radius_px(), rank1.aggro_radius_px * 0.72, 1e-3, "Stage C: Night aggro radius shrinks to 0.72x")
	rank1.aim_angle = 0.0
	rank1.step_ai_tick(0.05, 0.05)
	_assert_eq(rank1.ai_state, EnemyDummy.AIState.PATROL, "Stage C: At 115px during Night (vision 93.6px), enemy does NOT spot player")

	# 4c. Blood Moon Night (Day 30, 22:00): crimson lighting & boosted perception (1.25x = 162.5px)
	WorldCalendar.fast_forward_days(float(WorldCalendar.BLOOD_MOON_DAY - WorldCalendar.get_day_of_month()), false)
	_assert_true(WorldCalendar.is_blood_moon() and WorldCalendar.is_night(), "Stage C: Calendar advanced to Day 30 Blood Moon Night")
	arena.update_ambient_lighting()
	_assert_eq(arena.ambient_modulate.color, TestArena.AMBIENT_COLOR_BLOOD_MOON_NIGHT, "Stage C: Blood Moon Night sets CanvasModulate to crimson tint")
	_assert_true(arena.ambient_modulate.color.r > arena.ambient_modulate.color.b, "Stage C: Blood Moon lighting has crimson red dominance")
	_assert_true(rank1.get_effective_aggro_radius_px() > rank1.aggro_radius_px * 1.2, "Stage C: Blood Moon boosts enemy perception radius (>1.2x)")
	player.global_position = rank1.global_position + Vector2(150.0, 0.0)
	await get_tree().physics_frame
	rank1.aim_angle = 0.0
	rank1.step_ai_tick(0.05, 0.05)
	_assert_eq(rank1.ai_state, EnemyDummy.AIState.COMBAT, "Stage C: During Blood Moon, enemy spots player even at 150px (radius 162.5px)")

	# 4d. Calendar reset cleanly restores lighting & vision radius without stale state
	WorldCalendar.reset_calendar(12)
	arena._process(0.016)
	_assert_eq(arena.ambient_modulate.color, TestArena.AMBIENT_COLOR_DAY, "Stage C: Resetting calendar to midday immediately restores Color.WHITE")
	_assert_approx(rank1.get_effective_aggro_radius_px(), rank1.aggro_radius_px, 1e-3, "Stage C: Resetting calendar restores normal 1.0x aggro radius")
	WorldCalendar.reset_calendar(0)
	arena._process(0.016)
	_assert_eq(arena.ambient_modulate.color, TestArena.AMBIENT_COLOR_NIGHT, "Stage C: WorldCalendar.reset_calendar(0) cleanly syncs night twilight")

	remove_child(arena)
	arena.queue_free()
	EventBus.set_debug_highlight_weak_points(false)
	EventBus.set_debug_anti_regen_attacks(false)
	SimulationClock.reset_defaults()
	WorldCalendar.reset_calendar(0)


# ===========================================================================
# SUITE 26: Flight Modes (MANA_FLIGHT & WING_FLIGHT) & Complete Leg-Injury
#           Independence During Flight (TAG_LEG_LOCOMOTION + Aerial Prone)
# ===========================================================================

func _test_flight_modes_and_leg_injury_independence() -> void:
	SimulationClock.reset_defaults()
	WorldCalendar.reset_calendar(12)
	FloorLayerManager.reset(0)
	EventBus.set_debug_highlight_weak_points(false)
	EventBus.set_debug_anti_regen_attacks(false)

	var arena_scene: PackedScene = load("res://scenes/test_arena.tscn") as PackedScene
	var arena: TestArena = arena_scene.instantiate() as TestArena
	add_child(arena)
	arena.set_all_enemies_ai_enabled(false)

	var hud: DebugHUD = arena.get_node_or_null("DebugHUD") as DebugHUD
	var player: PlayerController = arena.entities_container.get_node_or_null("Player") as PlayerController
	var rank6: EnemyDummy = arena.entities_container.get_node_or_null("Rank6Guard") as EnemyDummy
	_assert_true(hud != null and player != null and rank6 != null, "Flight Suite: Arena loaded HUD, Player & Rank 6 Guard")
	await get_tree().physics_frame

	# 0. Focus safety & Rank 6 Guard MANA_FLIGHT preset verification
	_assert_eq(_count_focusable_controls(hud), 0, "Flight Suite: zero focusable controls after adding Wings & FlightMode HUD buttons")
	_assert_eq(rank6.get_flight_mode(), VerticalityComponent.FlightMode.MANA_FLIGHT, "Flight Suite: Rank 6 Guard starts in MANA_FLIGHT")
	_assert_true(rank6.is_flying() and rank6.mana_flight_ring != null and rank6.mana_flight_ring.visible, "Flight Suite: Rank 6 Guard displays mana levitation ring")

	# 1. Baseline unawakened wingless human pressing F gets helpful message without crashing
	player.revive_and_heal_all()
	player.set_has_wings(false)
	player.stat_sheet.set_mana_awakened(false)
	var fail_fl: Dictionary = player.try_toggle_flight()
	_assert_false(bool(fail_fl["success"]), "Flight Suite: Unawakened wingless player cannot fly on F")
	_assert_false(player.is_flying(), "Flight Suite: Player remains grounded when flight unavailable")
	_assert_true(String(fail_fl["message"]).contains("мана") and String(fail_fl["message"]).contains("крылья"), "Flight Suite: Helpful message explains mana or wings requirement")
	hud._refresh_all_views()
	_assert_true(hud.lbl_event_log.text.contains("мана"), "Flight Suite: DebugHUD surfaces flight requirement message in event log")

	# 2. MANA_FLIGHT: 100% independent of leg fracture, tendon tear, deep wound & severed legs!
	player.stat_sheet.awaken_mana(25.0, 20.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.SPD, 25.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.AGI, 25.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.CON, 35.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.SOUL, 35.0)
	player.refill_resources()
	var clean_spd: float = player.stat_sheet.get_stat(StatSheet.Stat.SPD)
	var clean_agi: float = player.stat_sheet.get_stat(StatSheet.Stat.AGI)

	# Inflict leg fracture, tendon tear, deep wound, and sever LeftLeg while grounded
	player.anatomy.apply_blunt_hit(AnatomyComponent.ZONE_RIGHT_LEG, 500.0, 1.0, 0.2, false)
	player.anatomy.apply_tendon_tear(AnatomyComponent.ZONE_RIGHT_LEG, 8.0)
	player.anatomy.apply_penetrating_hit(AnatomyComponent.ZONE_RIGHT_LEG, 12.0, false, 0.0, 0.0)
	player.anatomy.sever_limb(AnatomyComponent.ZONE_LEFT_LEG)
	player.anatomy.shock_level = 0.0 # Keep conscious to test locomotion & flight cleanly

	_assert_true(player.anatomy.is_limb_severed(AnatomyComponent.ZONE_LEFT_LEG), "Flight Suite: LeftLeg is SEVERED")
	_assert_true(player.is_prone(), "Flight Suite: Grounded player with severed leg is prone")
	_assert_false(player.can_act(), "Flight Suite: Grounded player with severed leg cannot act normally")
	_assert_true(player.stat_sheet.get_stat(StatSheet.Stat.SPD) < clean_spd * 0.5, "Flight Suite: Grounded leg injuries heavily penalize SPD")
	_assert_true(player.stat_sheet.get_stat(StatSheet.Stat.AGI) < clean_agi * 0.5, "Flight Suite: Grounded leg injuries heavily penalize AGI")

	# Takeoff directly FROM THE GROUND despite severed leg (F -> MANA_FLIGHT)!
	var mana_takeoff: Dictionary = player.try_toggle_flight(VerticalityComponent.HEIGHT_HIGH_FLIGHT)
	_assert_true(bool(mana_takeoff["success"]), "Flight Suite: Legless mage successfully takes off via MANA_FLIGHT")
	_assert_eq(player.get_flight_mode(), VerticalityComponent.FlightMode.MANA_FLIGHT, "Flight Suite: Active FlightMode == MANA_FLIGHT")
	_assert_true(player.is_flying(), "Flight Suite: Player is airborne (height_z >= 1.0)")
	_assert_true(player.stat_sheet.has_ignored_tag(StatSheet.TAG_LEG_LOCOMOTION), "Flight Suite: Airborne actor ignores TAG_LEG_LOCOMOTION")
	_assert_false(player.is_prone(), "Flight Suite: Severed leg does NOT make flying actor prone")
	_assert_true(player.can_act(), "Flight Suite: Airborne actor with severed leg retains can_act() == true")
	_assert_approx(player.stat_sheet.get_stat(StatSheet.Stat.SPD), clean_spd, 1e-4, "Flight Suite: Airborne SPD restored to 100% despite fracture+tendon+severed leg")
	_assert_approx(player.stat_sheet.get_stat(StatSheet.Stat.AGI), clean_agi, 1e-4, "Flight Suite: Airborne AGI restored to 100% despite leg injuries")
	_assert_true(player.mana_flight_ring != null and player.mana_flight_ring.visible, "Flight Suite: Mana levitation ring visible in MANA_FLIGHT")

	# Verify movement, aerial dash (extra MP), and attacks work seamlessly in midair without a leg!
	var pos_before_fly_move: Vector2 = player.global_position
	var moved_air: bool = player.step_movement_and_combat(Vector2.RIGHT, 0.12, 0.12)
	_assert_true(moved_air and player.global_position.x > pos_before_fly_move.x + 5.0, "Flight Suite: Legless flying player moves freely in midair")
	var mp_before_dash: float = player.current_mp
	_assert_true(player.start_dash(Vector2.RIGHT), "Flight Suite: Legless flying player can perform aerial Dash")
	_assert_true(player.current_mp < mp_before_dash, "Flight Suite: Aerial Dash in MANA_FLIGHT consumes extra MP")
	_assert_true(player.start_attack(player.global_position + Vector2(40.0, 0.0), PenetrationResolver.AttackType.SLASH), "Flight Suite: Legless flying player can attack in midair")
	player.step_combat_fsm(1.2)

	# Sever the SECOND leg while ALREADY airborne -> stays airborne, upright, acting at 100% SPD/AGI!
	player.anatomy.sever_limb(AnatomyComponent.ZONE_RIGHT_LEG)
	player.anatomy.shock_level = 0.0
	_assert_true(player.is_flying() and not player.is_prone() and player.can_act(), "Flight Suite: Severing second leg midair does NOT drop or paralyze flying actor")
	_assert_approx(player.stat_sheet.get_stat(StatSheet.Stat.SPD), clean_spd, 1e-4, "Flight Suite: Still 100% SPD midair with both legs severed")

	# DebugHUD displays [MANA] & Game HUD displays MANA FLY badge
	hud.set_compact_hud_mode(true)
	hud._refresh_all_views()
	_assert_true(hud.lbl_space.text.contains("[MANA]"), "Flight Suite: Debug telemetry shows [MANA] FlightMode")
	_assert_true(hud.game_stance_badges["MANA FLY"].visible and not hud.game_stance_badges["WING FLY"].visible, "Flight Suite: Game HUD shows MANA FLY badge")
	hud.set_compact_hud_mode(false)

	# Land back onto ground -> leg penalties and ground prone return honestly!
	var mana_land: Dictionary = player.try_toggle_flight()
	_assert_true(bool(mana_land["success"]) and not player.is_flying(), "Flight Suite: Manual landing sets height_z = 0.0")
	_assert_false(player.stat_sheet.has_ignored_tag(StatSheet.TAG_LEG_LOCOMOTION), "Flight Suite: Grounded actor removes TAG_LEG_LOCOMOTION from ignored tags")
	_assert_true(player.is_prone(), "Flight Suite: Grounded legless actor is prone again after landing")
	_assert_false(player.can_act(), "Flight Suite: Grounded legless actor cannot act after landing")
	_assert_true(player.stat_sheet.get_stat(StatSheet.Stat.SPD) < clean_spd * 0.5, "Flight Suite: Leg SPD penalties return cleanly on ground")

	# 3. MANA_FLIGHT upkeep drains MP on world_delta & forces landing at MP == 0 (works without arms/wings too)
	player.revive_and_heal_all()
	player.set_has_wings(false)
	player.stat_sheet.awaken_mana(10.0, 10.0)
	player.refill_resources()
	player.anatomy.sever_limb(AnatomyComponent.ZONE_LEFT_ARM)
	player.anatomy.sever_limb(AnatomyComponent.ZONE_RIGHT_ARM)
	player.anatomy.shock_level = 0.0
	_assert_true(player.set_flight_mode(VerticalityComponent.FlightMode.MANA_FLIGHT, 1.5), "Flight Suite: MANA_FLIGHT works without wings or arms")
	var mp_start: float = player.current_mp
	player.tick_physiology(2.0, true)
	_assert_true(player.current_mp < mp_start - 3.0, "Flight Suite: MANA_FLIGHT drains MP over world_delta (%.1f -> %.1f)" % [mp_start, player.current_mp])
	player.current_mp = 1.0
	player.tick_physiology(1.0, false)
	_assert_approx(player.current_mp, 0.0, 1e-4, "Flight Suite: MANA_FLIGHT drains remaining MP to 0")
	_assert_false(player.is_flying(), "Flight Suite: MP depletion forces landing from MANA_FLIGHT")
	_assert_eq(player.get_flight_mode(), VerticalityComponent.FlightMode.NONE, "Flight Suite: FlightMode resets to NONE on MP depletion")

	# Knockout while in MANA_FLIGHT drops actor to ground with fall damage
	player.revive_and_heal_all()
	player.stat_sheet.awaken_mana(10.0, 10.0)
	player.stat_sheet.set_all_base_stats(10.0, true)
	player.refill_resources()
	_assert_true(player.set_flight_mode(VerticalityComponent.FlightMode.MANA_FLIGHT, 1.5), "Flight Suite: Airborne before KO fall test")
	player.anatomy.apply_blunt_hit(AnatomyComponent.ZONE_LEFT_ARM, 300.0, 1.0, 1.0, true)
	player.anatomy.apply_blunt_hit(AnatomyComponent.ZONE_RIGHT_ARM, 300.0, 1.0, 1.0, true)
	_assert_true(player.anatomy.is_unconscious, "Flight Suite: Player knocked out in midair")
	_assert_false(player.is_flying() or player.get_height_z() > 0.0, "Flight Suite: Knockout drops airborne player to ground (height_z == 0.0)")
	_assert_true(player.anatomy.has_fracture(AnatomyComponent.ZONE_LEFT_LEG), "Flight Suite: Unconscious fall from MANA_FLIGHT applies fall damage")

	# 4. WING_FLIGHT: No mana needed, ZONE_WINGS anatomy & hitbox, ignores leg injuries, drains STA,
	#    crippled wings limit height/speed, severed ZONE_WINGS drops with fall damage & regrowth restores!
	player.revive_and_heal_all()
	player.stat_sheet.set_mana_awakened(false)
	player.stat_sheet.set_all_base_stats(10.0, false)
	player.stat_sheet.set_base_stat(StatSheet.Stat.SPD, 20.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.AGI, 10.0)
	player.refill_resources()
	_assert_false(player.stat_sheet.mana_awakened, "Flight Suite: Player has NO mana awakening for WING_FLIGHT test")

	# Enable wings via DebugHUD button API
	_assert_true(hud.toggle_player_wings(), "Flight Suite: DebugHUD toggle_player_wings enables ZONE_WINGS")
	_assert_true(player.has_wings and player.anatomy.has_zone(AnatomyComponent.ZONE_WINGS), "Flight Suite: Player has ZONE_WINGS anatomy zone")
	_assert_true(_find_zone(player, AnatomyComponent.ZONE_WINGS) != null, "Flight Suite: Player has ZONE_WINGS HitboxZone")
	_assert_true(player.wing_visual_root != null and player.wing_visual_root.visible, "Flight Suite: Procedural wing visuals visible")

	# DebugHUD preference cycling (AUTO -> MANA -> WINGS -> AUTO)
	_assert_eq(hud.cycle_player_flight_preference(), VerticalityComponent.PreferredFlightMode.MANA, "Flight Suite: Pref cycles AUTO -> MANA")
	_assert_eq(hud.cycle_player_flight_preference(), VerticalityComponent.PreferredFlightMode.WINGS, "Flight Suite: Pref cycles MANA -> WINGS")
	_assert_eq(hud.cycle_player_flight_preference(), VerticalityComponent.PreferredFlightMode.AUTO, "Flight Suite: Pref cycles WINGS -> AUTO")

	# Sever LeftLeg on ground, then take off on WINGS without mana!
	var wing_clean_spd: float = player.stat_sheet.get_stat(StatSheet.Stat.SPD)
	var wing_clean_agi: float = player.stat_sheet.get_stat(StatSheet.Stat.AGI)
	player.anatomy.sever_limb(AnatomyComponent.ZONE_LEFT_LEG)
	player.anatomy.shock_level = 0.0
	_assert_true(player.is_prone() and player.stat_sheet.get_stat(StatSheet.Stat.SPD) < wing_clean_spd * 0.5, "Flight Suite: Grounded winged actor suffers leg penalty & prone")

	var wing_takeoff: Dictionary = player.try_toggle_flight(VerticalityComponent.HEIGHT_HIGH_FLIGHT)
	_assert_true(bool(wing_takeoff["success"]), "Flight Suite: Unawakened winged player takes off via WING_FLIGHT despite severed leg")
	_assert_eq(player.get_flight_mode(), VerticalityComponent.FlightMode.WING_FLIGHT, "Flight Suite: Active FlightMode == WING_FLIGHT")
	_assert_false(player.is_prone(), "Flight Suite: WING_FLIGHT clears prone from severed leg")
	_assert_true(player.can_act(), "Flight Suite: WING_FLIGHT allows full combat/movement without leg")
	_assert_approx(player.stat_sheet.get_stat(StatSheet.Stat.SPD), wing_clean_spd, 1e-4, "Flight Suite: WING_FLIGHT restores 100% SPD ignoring leg injuries")
	_assert_approx(player.stat_sheet.get_stat(StatSheet.Stat.AGI), wing_clean_agi, 1e-4, "Flight Suite: WING_FLIGHT restores 100% AGI ignoring leg injuries")
	_assert_false(player.mana_flight_ring.visible, "Flight Suite: Mana levitation ring hidden during WING_FLIGHT")
	_assert_true(player.wing_left_poly.scale.x > 1.2, "Flight Suite: Wings spread visually during WING_FLIGHT")

	hud.set_compact_hud_mode(true)
	hud._refresh_all_views()
	_assert_true(hud.lbl_space.text.contains("[WINGS]"), "Flight Suite: Debug telemetry shows [WINGS] FlightMode")
	_assert_true(hud.game_stance_badges["WING FLY"].visible and not hud.game_stance_badges["MANA FLY"].visible, "Flight Suite: Game HUD shows WING FLY badge")
	hud.set_compact_hud_mode(false)

	# WING_FLIGHT drains STA over world_delta (no STA regen midair) & forces fall at STA == 0
	var sta_before_wing: float = player.current_stamina
	player.tick_physiology(2.0, true)
	_assert_true(player.current_stamina < sta_before_wing - 10.0, "Flight Suite: WING_FLIGHT drains stamina over world_delta (%.1f -> %.1f)" % [sta_before_wing, player.current_stamina])

	# Crippled wing lowers altitude cap to 1.0 & slows flight speed to 0.65x
	player.anatomy.apply_tendon_tear(AnatomyComponent.ZONE_WINGS, 8.0)
	player.tick_physiology(0.1, false)
	_assert_true(player.is_wings_crippled(), "Flight Suite: Wing tendon tear marks ZONE_WINGS CRIPPLED")
	_assert_approx(player.get_height_z(), VerticalityComponent.HEIGHT_LOW_FLIGHT, 1e-4, "Flight Suite: Crippled wings cap flight height at LOW_FLIGHT (1.0)")
	_assert_approx(player.get_flight_speed_mult(), CombatActor.WING_CRIPPLED_SPEED_MULT, 1e-4, "Flight Suite: Crippled wings reduce aerial speed multiplier to 0.65x")

	# Severing ZONE_WINGS midair interrupts WING_FLIGHT immediately with fall damage!
	player.revive_and_heal_all()
	player.stat_sheet.set_mana_awakened(false)
	player.stat_sheet.set_base_stat(StatSheet.Stat.AGI, 10.0)
	player.refill_resources()
	_assert_true(player.set_flight_mode(VerticalityComponent.FlightMode.WING_FLIGHT, 1.5), "Flight Suite: Airborne in WING_FLIGHT before wing severing")
	player.anatomy.sever_limb(AnatomyComponent.ZONE_WINGS)
	_assert_false(player.is_flying(), "Flight Suite: Severing ZONE_WINGS immediately interrupts WING_FLIGHT")
	_assert_approx(player.get_height_z(), 0.0, 1e-4, "Flight Suite: Severed wings drop actor to height_z == 0.0")
	_assert_eq(player.get_flight_mode(), VerticalityComponent.FlightMode.NONE, "Flight Suite: FlightMode cleared to NONE after wing severing")
	_assert_false(player.wing_visual_root.visible, "Flight Suite: Wing polygons disappear when ZONE_WINGS is severed")
	_assert_true(player.anatomy.has_fracture(AnatomyComponent.ZONE_LEFT_LEG), "Flight Suite: Sudden wing severing midair inflicts fall damage on impact")
	_assert_false(player.can_use_wing_flight(), "Flight Suite: Cannot re-enter WING_FLIGHT while ZONE_WINGS is severed")

	# Stamina depletion in WING_FLIGHT also interrupts flight cleanly
	player.revive_and_heal_all()
	player.stat_sheet.set_mana_awakened(false)
	player.refill_resources()
	_assert_true(player.set_flight_mode(VerticalityComponent.FlightMode.WING_FLIGHT, 1.5), "Flight Suite: Airborne in WING_FLIGHT before STA drain")
	player.current_stamina = 1.0
	player.tick_physiology(1.0, true)
	_assert_approx(player.current_stamina, 0.0, 1e-4, "Flight Suite: WING_FLIGHT drains remaining STA to 0")
	_assert_false(player.is_flying(), "Flight Suite: STA depletion forces landing/fall from WING_FLIGHT")

	# High REG (>=150) regrows severed ZONE_WINGS and restores wing visuals & WING_FLIGHT!
	player.revive_and_heal_all()
	player.stat_sheet.awaken_mana(80.0, 40.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.REG, 200.0)
	player.refill_resources()
	player.anatomy.sever_limb(AnatomyComponent.ZONE_WINGS)
	player.anatomy.shock_level = 0.0
	_assert_false(player.wing_visual_root.visible, "Flight Suite: Wings hidden while severed before regrowth")
	for _r: int in range(25):
		player.tick_physiology(1.0, false)
		if not player.anatomy.is_limb_severed(AnatomyComponent.ZONE_WINGS):
			break
	_assert_false(player.anatomy.is_limb_severed(AnatomyComponent.ZONE_WINGS), "Flight Suite: High REG regrows severed ZONE_WINGS")
	_assert_true(player.wing_visual_root.visible and player.can_use_wing_flight(), "Flight Suite: Regrown wings restore visuals and WING_FLIGHT capability")

	# Disabling wings removes ZONE_WINGS cleanly
	_assert_false(hud.toggle_player_wings(), "Flight Suite: DebugHUD toggle_player_wings disables wings cleanly")
	_assert_false(player.anatomy.has_zone(AnatomyComponent.ZONE_WINGS), "Flight Suite: Disabling wings removes ZONE_WINGS from AnatomyComponent")

	remove_child(arena)
	arena.queue_free()
	EventBus.set_debug_highlight_weak_points(false)
	EventBus.set_debug_anti_regen_attacks(false)
	SimulationClock.reset_defaults()
	WorldCalendar.reset_calendar(0)


# ===========================================================================
# SUITE 27: Modular Combat AI System (Utility AI + Stat-Driven + Extensible)
# ===========================================================================

class _CustomBossBrain extends CombatBrain:
	var custom_scored: bool = false

	func _score_actions(ctx: Dictionary) -> Dictionary:
		custom_scored = true
		var s: Dictionary = super._score_actions(ctx)
		s[ACTION_ATTACK_THRUST] = float(s.get(ACTION_ATTACK_THRUST, 0.0)) + 0.50
		return s


static func _build_custom_boss_brain(p: EnemyAIProfile) -> CombatBrain:
	return _CustomBossBrain.new(p)


func _test_modular_combat_ai_system() -> void:
	SimulationClock.reset_defaults()
	WorldCalendar.reset_calendar(0)
	WorldCalendar.paused = true
	FloorLayerManager.reset(0)

	var arena_scene: PackedScene = load("res://scenes/test_arena.tscn") as PackedScene
	var arena: TestArena = arena_scene.instantiate() as TestArena
	add_child(arena)
	arena.set_all_enemies_ai_enabled(false)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var player: PlayerController = arena.entities_container.get_node_or_null("Player") as PlayerController
	var rank1: EnemyDummy = arena.entities_container.get_node_or_null("Rank1Swordsman") as EnemyDummy
	var troll: EnemyDummy = arena.entities_container.get_node_or_null("TrollBerserker") as EnemyDummy
	var rank6: EnemyDummy = arena.entities_container.get_node_or_null("Rank6Guard") as EnemyDummy

	# -----------------------------------------------------------------------
	# 1. Modular Architecture, Presets & Custom Subclass Registration
	# -----------------------------------------------------------------------
	_assert_eq(rank1.ai_profile.archetype_id, &"duelist", "AI Suite: Rank 1 Swordsman uses duelist profile")
	_assert_true(rank1.ai_brain is BrainFactory.DuelistBrain, "AI Suite: Rank 1 Swordsman uses DuelistBrain")
	_assert_eq(troll.ai_profile.archetype_id, &"berserker", "AI Suite: Troll Berserker uses berserker profile")
	_assert_true(troll.ai_brain is BrainFactory.BerserkerBrain, "AI Suite: Troll Berserker uses BerserkerBrain")
	_assert_eq(rank6.ai_profile.archetype_id, &"guardian", "AI Suite: Rank 6 Guard uses guardian profile")
	_assert_true(rank6.ai_brain is BrainFactory.GuardianBrain, "AI Suite: Rank 6 Guard uses GuardianBrain")

	BrainFactory.register_brain(&"test_boss_brain", _build_custom_boss_brain)
	var boss_profile: EnemyAIProfile = EnemyAIProfile.create_guardian_profile()
	boss_profile.custom_brain_id = &"test_boss_brain"
	var custom_brain: CombatBrain = BrainFactory.create_brain(boss_profile)
	_assert_true(custom_brain is _CustomBossBrain, "AI Suite: BrainFactory resolves custom registered CombatBrain subclass")
	var boss_ctx: Dictionary = custom_brain.build_context(rank6, player, arena, 0.05, 0.05)
	custom_brain._score_actions(boss_ctx)
	_assert_true((custom_brain as _CustomBossBrain).custom_scored, "AI Suite: Custom CombatBrain subclass overrides _score_actions cleanly")
	BrainFactory.clear_custom_brains()

	# -----------------------------------------------------------------------
	# 2. Honest TP/INT Reaction Delay & Feint Bait (Low TP/INT) vs Recognition (High TP/INT)
	# -----------------------------------------------------------------------
	var delay_low: float = CombatMemory.compute_reaction_delay(10.0, 10.0)
	var delay_high: float = CombatMemory.compute_reaction_delay(100.0, 100.0)
	_assert_true(delay_low >= 0.24 and delay_low <= 0.32, "AI Suite: TP=10/INT=10 reaction delay ~0.28s (got %.3f)" % delay_low)
	_assert_true(delay_high >= 0.03 and delay_high <= 0.05, "AI Suite: TP=100/INT=100 reaction delay ~0.034s (got %.3f)" % delay_high)

	# Low TP/INT Rank 1 cannot 1-frame react in 0.04s and gets BAITED by player feint!
	player.revive_and_heal_all()
	player.stat_sheet.set_all_base_stats(10.0, false)
	player.refill_resources()
	rank1.revive_and_heal_all()
	rank1.reset_aggro(0.0)
	rank1.global_position = Vector2(220.0, 280.0)
	player.global_position = rank1.global_position + Vector2(-30.0, 0.0)
	rank1.engage_target(player)
	await get_tree().physics_frame

	player.select_weapon_slot(0)
	player.start_attack(rank1.get_combat_origin(), PenetrationResolver.AttackType.SLASH)
	rank1.step_ai_tick(0.04, 0.04)
	_assert_false(rank1.is_blocking, "AI Suite: Low TP/INT Rank 1 does NOT cheat-react in 0.04s (delay=%.2fs)" % delay_low)
	_assert_true(rank1.ai_brain.memory.reaction_timer > 0.20, "AI Suite: Rank 1 still waiting on honest reaction_timer")

	_assert_true(player.try_feint_cancel(), "AI Suite: Player cancels WINDUP via Feint")
	rank1.step_ai_tick(0.04, 0.04)
	_assert_eq(rank1.ai_brain.memory.last_feint_reaction, &"baited", "AI Suite: Low INT/TP Rank 1 is BAITED by player feint")
	_assert_true(rank1.is_blocking, "AI Suite: Baited Rank 1 wastes reactive block on feint cancel")

	# High TP/INT Rank 6 reacts fast & RECOGNIZES player feint without wasting block!
	player.revive_and_heal_all()
	player.stat_sheet.awaken_mana(60.0, 30.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.TP, 50.0)
	player.refill_resources()
	rank6.revive_and_heal_all()
	rank6.reset_aggro(0.0)
	rank6.verticality.set_height_z(0.0)
	rank6.global_position = Vector2(260.0, 340.0)
	player.global_position = rank6.global_position + Vector2(-38.0, 0.0)
	rank6.engage_target(player)
	rank6.attack_cooldown_timer = 1.0
	await get_tree().physics_frame

	player.start_attack(rank6.get_combat_origin(), PenetrationResolver.AttackType.SLASH)
	rank6.step_ai_tick(0.02, 0.02)
	_assert_true(player.try_feint_cancel(), "AI Suite: Player feints in front of Rank 6 Guard")
	rank6.step_ai_tick(0.03, 0.03)
	_assert_eq(rank6.ai_brain.memory.last_feint_reaction, &"recognized", "AI Suite: High INT+TP Rank 6 RECOGNIZES player feint")
	_assert_false(rank6.is_blocking, "AI Suite: Rank 6 does NOT waste block on recognized feint")
	_assert_true(rank6.ai_brain.memory.counter_punish_timer > 0.0, "AI Suite: Recognizing feint opens counter_punish_timer")

	# -----------------------------------------------------------------------
	# 3. Smart Reactive Feint during Own WINDUP -> Instant Queued Followup
	# -----------------------------------------------------------------------
	player.revive_and_heal_all()
	player.stat_sheet.set_base_stat(StatSheet.Stat.TP, 50.0)
	player.refill_resources()
	rank6.revive_and_heal_all()
	rank6.reset_aggro(0.0)
	rank6.verticality.set_height_z(0.0)
	rank6.current_mp = 0.0 # Force Feint branch instead of Aura Burst
	rank6.global_position = Vector2(260.0, 340.0)
	player.global_position = rank6.global_position + Vector2(-36.0, 0.0)
	rank6.engage_target(player)
	await get_tree().physics_frame

	rank6.start_attack(player.get_combat_origin(), PenetrationResolver.AttackType.SLASH)
	_assert_eq(rank6.combat_state, CombatActor.CombatState.WINDUP, "AI Suite: Rank 6 enters WINDUP before reactive feint test")
	player.set_block_held(true)
	rank6.step_ai_tick(0.04, 0.04)
	_assert_eq(rank6.combat_state, CombatActor.CombatState.RECOVERY, "AI Suite: Rank 6 reactively feint-cancels WINDUP when player blocks")
	_assert_false(rank6.ai_brain.queued_followup.is_empty(), "AI Suite: Reactive feint schedules instant queued_followup")
	_assert_approx(rank6.attack_cooldown_timer, 0.0, 1e-4, "AI Suite: Reactive feint clears artificial attack cooldown")

	# Exit short feint recovery -> queued_followup launches immediately on first IDLE tick!
	rank6.step_combat_fsm(0.50)
	_assert_eq(rank6.combat_state, CombatActor.CombatState.IDLE, "AI Suite: Rank 6 exits feint recovery to IDLE")
	rank6.step_ai_tick(0.03, 0.03)
	_assert_eq(rank6.combat_state, CombatActor.CombatState.WINDUP, "AI Suite: Queued post-feint followup strikes immediately without pause")
	_assert_true(rank6.ai_brain.queued_followup.is_empty(), "AI Suite: Queued followup consumed upon launch")
	player.set_block_held(false)

	# -----------------------------------------------------------------------
	# 4. High-AGI Mid-WINDUP Micro-Sidestep vs Counter-Attack
	# -----------------------------------------------------------------------
	player.revive_and_heal_all()
	player.stat_sheet.set_base_stat(StatSheet.Stat.TP, 50.0)
	player.refill_resources()
	rank6.revive_and_heal_all()
	rank6.reset_aggro(0.0)
	rank6.verticality.set_height_z(0.0)
	rank6.current_mp = 0.0 # Isolate sidestep from Aura Burst
	rank6.global_position = Vector2(260.0, 340.0)
	player.global_position = rank6.global_position + Vector2(-40.0, 0.0)
	rank6.engage_target(player)
	await get_tree().physics_frame

	player.select_weapon_slot(2) # Warhammer BLUNT
	player.start_attack(rank6.get_combat_origin(), PenetrationResolver.AttackType.BLUNT)
	rank6.start_attack(player.get_combat_origin(), PenetrationResolver.AttackType.SLASH)
	rank6.step_ai_tick(0.02, 0.02)
	var sidestep_vel: Vector2 = rank6.step_ai_tick(0.05, 0.05)
	_assert_eq(rank6.combat_state, CombatActor.CombatState.WINDUP, "AI Suite: High-AGI Rank 6 remains in WINDUP during mid-swing Sidestep")
	_assert_true(rank6.sidestep_timer > 0.0, "AI Suite: High-AGI enemy executes Sidestep during its own WINDUP")
	_assert_true(sidestep_vel.length() > 250.0, "AI Suite: Mid-WINDUP Sidestep returns live lateral velocity (%.1f px/s)" % sidestep_vel.length())

	# -----------------------------------------------------------------------
	# 5. Armor/Hardening/Block-Aware Scoring + Weak-Point Aim + Conscious Aura Burst
	# -----------------------------------------------------------------------
	player.revive_and_heal_all()
	player.stat_sheet.awaken_mana(80.0, 40.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.TP, 50.0)
	player.refill_resources()
	player.rebuild_hitbox_zones(20.0, 15.0, {
		AnatomyComponent.ZONE_HEAD: [Vector2(0.0, -6.0)],
		AnatomyComponent.ZONE_CHEST: [Vector2(2.0, 2.0)],
	})
	player.activate_hardening()
	player.set_block_held(true)

	rank6.revive_and_heal_all()
	rank6.reset_aggro(0.0)
	rank6.verticality.set_height_z(0.0)
	rank6.attack_cooldown_timer = 0.0
	rank6.global_position = Vector2(260.0, 340.0)
	player.global_position = rank6.global_position + Vector2(-36.0, 0.0)
	rank6.engage_target(player)
	await get_tree().physics_frame

	var armor_ctx: Dictionary = rank6.ai_brain.build_context(rank6, player, arena, 0.05, 0.05)
	var armor_scores: Dictionary = rank6.ai_brain._score_actions(armor_ctx)
	_assert_true(
		float(armor_scores[CombatBrain.ACTION_ATTACK_THRUST]) > float(armor_scores[CombatBrain.ACTION_ATTACK_SLASH]),
		"AI Suite: Smart INT enemy scores THRUST (%.2f) > SLASH (%.2f) vs plate/Hardening" % [float(armor_scores[CombatBrain.ACTION_ATTACK_THRUST]), float(armor_scores[CombatBrain.ACTION_ATTACK_SLASH])]
	)
	_assert_true(
		float(armor_scores[CombatBrain.ACTION_ATTACK_BLUNT]) > float(armor_scores[CombatBrain.ACTION_ATTACK_SLASH]),
		"AI Suite: Smart INT enemy scores BLUNT (%.2f) > SLASH (%.2f) vs plate/Hardening/Block" % [float(armor_scores[CombatBrain.ACTION_ATTACK_BLUNT]), float(armor_scores[CombatBrain.ACTION_ATTACK_SLASH])]
	)
	var thrust_plan: Dictionary = rank6.ai_brain._select_attack_plan(armor_ctx, CombatBrain.ACTION_ATTACK_THRUST)
	_assert_true(bool(thrust_plan["aimed_weak_point"]), "AI Suite: THRUST plan targets real HitboxZone weak point")
	var head_hz: HitboxZone = _find_zone(player, AnatomyComponent.ZONE_HEAD)
	var head_wps: Array[Vector2] = head_hz.get_world_weak_points()
	_assert_true(
		not head_wps.is_empty() and (thrust_plan["aim_pos"] as Vector2).distance_to(head_wps[0]) < 1.0,
		"AI Suite: Attack plan aim_pos aligns with target's Head weak-point world coordinates"
	)

	# Conscious Aura Burst during WINDUP against blocking/hardened target
	var mp_before_burst: float = rank6.current_mp
	rank6.start_attack(player.get_combat_origin(), PenetrationResolver.AttackType.THRUST)
	rank6.step_ai_tick(0.04, 0.04)
	_assert_true(rank6.current_attack_aura_burst, "AI Suite: Rank 6 triggers conscious Aura Burst during WINDUP vs Block+Hardening")
	_assert_true(rank6.current_mp < mp_before_burst, "AI Suite: Conscious Aura Burst spends MP")
	player.set_block_held(false)

	# -----------------------------------------------------------------------
	# 6. Flank-Strafe around Block Cone & 1vN Anti-Clumping Separation
	# -----------------------------------------------------------------------
	player.revive_and_heal_all()
	player.stat_sheet.set_all_base_stats(10.0, false)
	player.refill_resources()
	rank1.revive_and_heal_all()
	rank1.reset_aggro(0.0)
	troll.revive_and_heal_all()
	troll.reset_aggro(0.0)
	rank6.reset_aggro(0.0)

	player.global_position = Vector2(220.0, 280.0)
	player.aim_angle = 0.0
	player.set_block_held(true)
	rank1.global_position = player.global_position + Vector2(40.0, 2.0)
	rank1.engage_target(player)
	rank1.attack_cooldown_timer = 1.0
	await get_tree().physics_frame

	var flank_vel: Vector2 = rank1.step_ai_tick(0.05, 0.05)
	_assert_true(absf(flank_vel.y) > 40.0, "AI Suite: Enemy flank-strafes laterally around blocking target's front cone (vy=%.1f)" % flank_vel.y)

	# 1vN Anti-Clumping: place Troll 14 px above Rank 1 both targeting player
	troll.global_position = rank1.global_position + Vector2(0.0, -14.0)
	troll.engage_target(player)
	var sep_vec: Vector2 = rank1.ai_brain._compute_ally_separation_and_surround(rank1, player)
	var away_from_troll: Vector2 = (rank1.global_position - troll.global_position).normalized()
	_assert_true(sep_vec.dot(away_from_troll) > 0.3, "AI Suite: 1vN anti-clumping pushes nearby allies apart instead of stacking")
	player.set_block_held(false)

	# -----------------------------------------------------------------------
	# 7. Clinch Environment Scan (Wall Slam) & Directed Throw into Solid Wall
	# -----------------------------------------------------------------------
	player.revive_and_heal_all()
	troll.revive_and_heal_all()
	troll.reset_aggro(0.0)
	rank1.reset_aggro(0.0)
	# Outer left arena perimeter wall is at x=0; cell (1, 8) is directly beside solid wall (0, 8) ~32-44px left!
	player.global_position = arena.cell_to_world_center(Vector2i(1, 8)) + Vector2(8.0, 0.0)
	troll.global_position = player.global_position + Vector2(24.0, 0.0)
	troll.engage_target(player)
	troll.attack_cooldown_timer = 0.0
	await get_tree().physics_frame

	var clinch_ctx: Dictionary = troll.ai_brain.build_context(troll, player, arena, 0.05, 0.05)
	var c_env: Dictionary = clinch_ctx["clinch_env"] as Dictionary
	_assert_true(bool(c_env["wall_slam_available"]), "AI Suite: Clinch environment scan detects solid wall behind target")
	_assert_true((c_env["wall_slam_dir"] as Vector2).x < -0.5, "AI Suite: Clinch wall_slam_dir points directly toward left wall")
	troll.step_ai_tick(0.05, 0.05)
	_assert_eq(troll.ai_brain.last_chosen_action, CombatBrain.ACTION_CLINCH_THROW, "AI Suite: Troll prioritizes CLINCH_THROW when wall slam is available")
	_assert_true(player.knockback_velocity.x < -50.0, "AI Suite: Clinch throw launches player directly toward the scanned wall (vx=%.1f)" % player.knockback_velocity.x)

	# -----------------------------------------------------------------------
	# 8. Stamina Hysteresis, Duelist vs Berserker Divergence, REG>=150 Spacing & Flight Pursuit
	# -----------------------------------------------------------------------
	player.revive_and_heal_all()
	player.global_position = Vector2(260.0, 280.0)
	rank1.revive_and_heal_all()
	rank1.reset_aggro(0.0)
	rank1.global_position = player.global_position + Vector2(26.0, 0.0)
	rank1.engage_target(player)
	rank1.attack_cooldown_timer = 0.0
	rank1.current_stamina = rank1.stat_sheet.get_max_stamina() * 0.15
	await get_tree().physics_frame

	var low_sta_vel: Vector2 = rank1.step_ai_tick(0.05, 0.05)
	_assert_true(rank1.ai_brain.recovering_stamina, "AI Suite: Duelist enters stamina recovery below 25% STA")
	_assert_eq(rank1.combat_state, CombatActor.CombatState.IDLE, "AI Suite: Duelist suppresses melee attacks while recovering stamina")
	_assert_true(low_sta_vel.x > 10.0, "AI Suite: Duelist backs off slightly while recovering stamina (vx=%.1f)" % low_sta_vel.x)

	rank1.current_stamina = rank1.stat_sheet.get_max_stamina() * 0.50
	rank1.step_ai_tick(0.05, 0.05)
	_assert_false(rank1.ai_brain.recovering_stamina, "AI Suite: Duelist exits stamina recovery hysteresis once STA >= 45%")

	# Berserker (caution=0.14 < 0.20) ignores low stamina pause and keeps pressing!
	troll.revive_and_heal_all()
	troll.reset_aggro(0.0)
	troll.global_position = player.global_position + Vector2(36.0, 0.0)
	troll.engage_target(player)
	troll.attack_cooldown_timer = 0.0
	troll.current_stamina = troll.stat_sheet.get_max_stamina() * 0.15
	await get_tree().physics_frame
	troll.step_ai_tick(0.05, 0.05)
	_assert_false(troll.ai_brain.recovering_stamina, "AI Suite: Fearless Berserker (caution < 0.20) ignores stamina pause")
	_assert_true(
		troll.combat_state == CombatActor.CombatState.WINDUP or troll.ai_brain.last_chosen_action == CombatBrain.ACTION_CLINCH_THROW,
		"AI Suite: Berserker keeps attacking aggressively at low STA"
	)

	# REG >= 150 brief self-heal spacing on severed limb in open space (not cornered)
	troll.revive_and_heal_all()
	troll.reset_aggro(0.0)
	player.global_position = Vector2(260.0, 380.0)
	troll.global_position = Vector2(210.0, 380.0) # Open space to the left (cell 5,11); stone wall is at cell 9,11
	troll.engage_target(player)
	troll.anatomy.sever_limb(AnatomyComponent.ZONE_LEFT_ARM)
	troll.anatomy.shock_level = 0.0
	await get_tree().physics_frame
	troll.step_ai_tick(0.05, 0.05)
	troll.step_ai_tick(0.05, 0.05)
	_assert_true(troll.ai_brain.regen_spacing_timer > 0.0, "AI Suite: High-REG Troll triggers brief self-heal spacing after losing a limb")

	# Flight pursuit (Rank 6 MANA_FLIGHT chases airborne player) vs Grounded enemy cover reposition
	player.revive_and_heal_all()
	player.stat_sheet.awaken_mana(100.0, 40.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.TP, 50.0)
	player.refill_resources()
	player.global_position = Vector2(260.0, 320.0)
	_assert_true(player.set_flight_mode(VerticalityComponent.FlightMode.MANA_FLIGHT, 2.0), "AI Suite: Player takes off to z=2.0 via MANA_FLIGHT")

	rank6.revive_and_heal_all()
	rank6.reset_aggro(0.0)
	rank6.verticality.set_height_z(0.4)
	rank6.global_position = player.global_position + Vector2(60.0, 0.0)
	rank6.engage_target(player)
	await get_tree().physics_frame
	for _f: int in range(6):
		rank6.step_ai_tick(0.08, 0.08)
	_assert_true(rank6.is_flying() and rank6.get_height_z() > 1.2, "AI Suite: Flying-capable Rank 6 ascends in MANA_FLIGHT to pursue airborne player (z=%.2f)" % rank6.get_height_z())

	# Grounded Rank 1 facing player at z=1.05 (visible, above Short Sword 0.6 reach) repositions laterally/back!
	player.verticality.set_height_z(1.05)
	rank1.revive_and_heal_all()
	rank1.reset_aggro(0.0)
	rank1.global_position = player.global_position + Vector2(28.0, 0.0)
	rank1.engage_target(player)
	await get_tree().physics_frame
	var anti_air_vel: Vector2 = rank1.step_ai_tick(0.05, 0.05)
	var to_air_player: Vector2 = (player.global_position - rank1.global_position).normalized()
	_assert_true(anti_air_vel.length() > 50.0 and anti_air_vel.dot(to_air_player) <= 0.1, "AI Suite: Grounded enemy repositions laterally/back against unreachable flying target")

	BrainFactory.clear_custom_brains()
	remove_child(arena)
	arena.queue_free()
	EventBus.set_debug_highlight_weak_points(false)
	EventBus.set_debug_anti_regen_attacks(false)
	SimulationClock.reset_defaults()
	WorldCalendar.reset_calendar(0)


# ===========================================================================
# SUITE 28: Full Stealth System (Crouch, Low-Obstacle Cover, StealthCoverZone,
#           Suspicion, Vision Cones, Noise Distraction T, Backstab & Takedown Q)
# ===========================================================================

func _test_stealth_system_crouch_cover_suspicion_distract_and_takedown() -> void:
	SimulationClock.reset_defaults()
	WorldCalendar.reset_calendar(12) # Daytime 12:00
	WorldCalendar.paused = true
	FloorLayerManager.reset(0)

	# -----------------------------------------------------------------------
	# 1. InputMap actions: toggle_crouch (KEY_CTRL) & stealth_distract (KEY_T)
	# -----------------------------------------------------------------------
	_assert_true(InputMap.has_action(&"toggle_crouch"), "Stealth Suite: InputMap has toggle_crouch action")
	var crouch_events: Array[InputEvent] = InputMap.action_get_events(&"toggle_crouch")
	_assert_true(
		not crouch_events.is_empty() and crouch_events[0] is InputEventKey and (crouch_events[0] as InputEventKey).physical_keycode == KEY_CTRL,
		"Stealth Suite: toggle_crouch bound to KEY_CTRL"
	)
	_assert_true(InputMap.has_action(&"stealth_distract"), "Stealth Suite: InputMap has stealth_distract action")
	var distract_events: Array[InputEvent] = InputMap.action_get_events(&"stealth_distract")
	_assert_true(
		not distract_events.is_empty() and distract_events[0] is InputEventKey and (distract_events[0] as InputEventKey).physical_keycode == KEY_T,
		"Stealth Suite: stealth_distract bound to KEY_T"
	)

	var arena_scene: PackedScene = load("res://scenes/test_arena.tscn") as PackedScene
	var arena: TestArena = arena_scene.instantiate() as TestArena
	add_child(arena)
	arena.set_all_enemies_ai_enabled(false)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var hud: DebugHUD = arena.get_node_or_null("DebugHUD") as DebugHUD
	var player: PlayerController = arena.entities_container.get_node_or_null("Player") as PlayerController
	var rank1: EnemyDummy = arena.entities_container.get_node_or_null("Rank1Swordsman") as EnemyDummy
	var troll: EnemyDummy = arena.entities_container.get_node_or_null("TrollBerserker") as EnemyDummy
	var rank6: EnemyDummy = arena.entities_container.get_node_or_null("Rank6Guard") as EnemyDummy

	# -----------------------------------------------------------------------
	# 2. Crouch Stance (Ctrl), Speed Scaling, Acoustics, Stealth Roll & Flight Reset
	# -----------------------------------------------------------------------
	player.revive_and_heal_all()
	player.stat_sheet.set_all_base_stats(10.0, false)
	player.refill_resources()

	_assert_false(player.is_crouching, "Stealth Suite: Player starts standing (is_crouching == false)")
	_assert_true(player.toggle_crouch(), "Stealth Suite: toggle_crouch enables crouch")
	_assert_true(player.is_crouching, "Stealth Suite: is_crouching == true after toggle")
	_assert_approx(player.body_visual.scale.x, CombatActor.CROUCH_VISUAL_SCALE, 1e-3, "Stealth Suite: Crouch shrinks BodyVisual scale to 0.84")
	_assert_approx(player.get_crouch_speed_mult(), 0.52, 1e-3, "Stealth Suite: Base crouch speed mult is 0.52 at AGI=10")
	var crouch_run_vel: Vector2 = player.compute_run_velocity_with_drift(Vector2.RIGHT, 0.016)
	_assert_approx(crouch_run_vel.length(), CombatActor.BASE_RUN_SPEED_PX * 0.52, 0.5, "Stealth Suite: Crouch reduces movement speed to 52%")

	# Acoustics: crouch walking 15px at AGI=10, silent (0px) at AGI>=30; crouch dash/roll 25px keeping crouch!
	_assert_approx(player.get_movement_noise_radius(false, 114.0), 15.0, 1e-3, "Stealth Suite: Crouch walk noise drops to 15px at AGI=10")
	_assert_approx(player.get_movement_noise_radius(true, 400.0), 25.0, 1e-3, "Stealth Suite: Crouch Space roll noise drops from 145px to 25px")
	_assert_true(player.start_dash(Vector2.RIGHT), "Stealth Suite: Space roll executes while crouched")
	_assert_true(player.is_crouching, "Stealth Suite: Quiet crouch roll preserves is_crouching == true")
	player.dash_timer = 0.0
	player.dash_cooldown_timer = 0.0

	player.stat_sheet.awaken_mana(60.0, 10.0)
	player.stat_sheet.set_base_stat(StatSheet.Stat.AGI, 60.0)
	_assert_approx(player.get_crouch_speed_mult(), 0.62, 1e-3, "Stealth Suite: High AGI=60 raises crouch speed mult to 0.62")
	_assert_approx(player.get_movement_noise_radius(false, 130.0), 0.0, 1e-3, "Stealth Suite: AGI >= 30 makes crouch walking completely silent (0px)")
	player.stat_sheet.set_base_stat(StatSheet.Stat.AGI, 150.0)
	_assert_approx(player.get_crouch_speed_mult(), 0.72, 1e-3, "Stealth Suite: Crouch speed mult caps cleanly at 0.72")
	player.stat_sheet.set_base_stat(StatSheet.Stat.AGI, 10.0)

	# Takeoff auto-cancels crouch & prevents crouching midair; Prone / Stagger also cancel crouch
	player.stat_sheet.awaken_mana(60.0, 30.0)
	player.refill_resources()
	_assert_true(player.set_flight_mode(VerticalityComponent.FlightMode.MANA_FLIGHT, 1.5), "Stealth Suite: Player takes off in MANA_FLIGHT")
	_assert_false(player.is_crouching, "Stealth Suite: Taking off automatically disables crouch")
	_assert_false(player.set_crouch(true), "Stealth Suite: Cannot enable crouch while flying")
	player.land_from_flight(false, "")
	_assert_true(player.set_crouch(true), "Stealth Suite: Can crouch again after landing")
	player.set_prone(1.0)
	_assert_false(player.is_crouching, "Stealth Suite: Falling Prone automatically disables crouch")
	player.revive_and_heal_all()

	# -----------------------------------------------------------------------
	# 3. LOW_OBSTACLE Fence Cover vs Grounded (z=0) & Hovering (z=1.5) Observers
	# -----------------------------------------------------------------------
	rank1.revive_and_heal_all()
	rank1.reset_aggro(0.0)
	rank6.revive_and_heal_all()
	rank6.reset_aggro(0.0)

	# Low fence is at x=6, y=3..6. Observer on left (5, 4), player on right (7, 4)
	rank1.global_position = arena.cell_to_world_center(Vector2i(5, 4))
	rank1.aim_angle = 0.0
	player.global_position = arena.cell_to_world_center(Vector2i(7, 4))
	await get_tree().physics_frame

	_assert_true(rank1.can_see_target(player, arena), "Stealth Suite: Grounded enemy sees STANDING player over LOW_OBSTACLE fence")
	player.set_crouch(true)
	await get_tree().physics_frame
	_assert_false(rank1.can_see_target(player, arena), "Stealth Suite: Grounded enemy CANNOT see CROUCHED player behind LOW_OBSTACLE fence")
	rank1.step_ai_tick(0.05, 0.05)
	_assert_eq(rank1.ai_state, EnemyDummy.AIState.PATROL, "Stealth Suite: Grounded patrol stays in PATROL when player crouches behind fence")

	# Hovering Rank 6 Guard (z=1.5 >= 1.0) sees right over the low fence!
	rank6.global_position = arena.cell_to_world_center(Vector2i(5, 4))
	rank6.aim_angle = 0.0
	await get_tree().physics_frame
	_assert_true(rank6.get_height_z() >= FloorLayerManager.LOW_OBSTACLE_CLEARANCE_Z, "Stealth Suite: Rank 6 Guard hovers above LOW_OBSTACLE clearance")
	_assert_true(rank6.can_see_target(player, arena), "Stealth Suite: Hovering Rank 6 Guard sees crouched player OVER LOW_OBSTACLE fence")

	# -----------------------------------------------------------------------
	# 4. StealthCoverZone (Layer 18), Visibility Factor, Bush Rustle & Gradual Suspicion
	# -----------------------------------------------------------------------
	_assert_eq(arena.stealth_cover_zones.size(), 3, "Stealth Suite: TestArena spawns 3 procedural StealthCoverZones")
	for cz: Area2D in arena.stealth_cover_zones:
		_assert_eq(cz.collision_layer, FloorLayerManager.BIT_TRIGGERS_STEALTH, "Stealth Suite: StealthCoverZone uses Layer 18 BIT_TRIGGERS_STEALTH")

	var cover_center: Vector2 = arena.cell_to_world_center(TestArena.STEALTH_COVER_RECTS[0].position)
	player.revive_and_heal_all()
	player.stat_sheet.set_all_base_stats(10.0, false)
	player.refill_resources()
	player.global_position = arena.cell_to_world_center(Vector2i(11, 14)) # Open corridor
	await get_tree().physics_frame
	_assert_false(arena.is_entity_in_stealth_cover(player), "Stealth Suite: Open ground is not in StealthCoverZone")
	_assert_approx(arena.get_stealth_visibility_factor(player), 1.0, 1e-3, "Stealth Suite: Standing open visibility factor == 1.0")
	player.set_crouch(true)
	_assert_approx(arena.get_stealth_visibility_factor(player), 0.58, 1e-3, "Stealth Suite: Crouched open visibility factor == 0.58")

	player.global_position = cover_center
	await get_tree().physics_frame
	_assert_true(arena.is_entity_in_stealth_cover(player), "Stealth Suite: Player inside StealthCoverZone detected accurately")
	_assert_approx(arena.get_stealth_visibility_factor(player), 0.25, 1e-3, "Stealth Suite: Crouched inside StealthCoverZone lowers visibility to 0.25")
	WorldCalendar.reset_calendar(22) # Night
	_assert_true(arena.get_stealth_visibility_factor(player) < 0.25, "Stealth Suite: Nighttime further reduces stealth visibility factor")
	WorldCalendar.reset_calendar(12) # Back to midday

	# Bush rustling: running standing inside StealthCoverZone emits 75px noise every 0.6s; crouched does NOT rustle!
	arena.recent_noises.clear()
	player.set_crouch(false)
	player._bush_rustle_timer = 0.58
	player.move_with_substepping(Vector2(180.0, 0.0), 0.05, false, false)
	var saw_rustle: bool = false
	for nr: Dictionary in arena.recent_noises:
		if is_equal_approx(float(nr.get("radius", 0.0)), CombatActor.BUSH_RUSTLE_NOISE_PX):
			saw_rustle = true
			break
	_assert_true(saw_rustle, "Stealth Suite: Running standing through StealthCoverZone emits 75px bush rustle noise")

	# Gradual suspicion_level: PATROL -> SEARCH (>=0.35) -> COMBAT (1.0) inside StealthCoverZone + crouch!
	arena.recent_noises.clear()
	player.global_position = cover_center
	player.set_crouch(true)
	rank1.revive_and_heal_all()
	rank1.reset_aggro(0.0)
	rank1.global_position = cover_center + Vector2(-72.0, 0.0) # Clear LOS into cover, cell (2,5)->(4,5)
	rank1.aim_angle = 0.0
	await get_tree().physics_frame

	rank1.step_ai_tick(0.05, 0.05)
	_assert_eq(rank1.ai_state, EnemyDummy.AIState.PATROL, "Stealth Suite: Crouched in StealthCoverZone does NOT trigger instant 1-tick aggro")
	_assert_true(rank1.suspicion_level > 0.0 and rank1.suspicion_level < 0.35, "Stealth Suite: Suspicion grows gradually on first tick (%.3f)" % rank1.suspicion_level)
	_assert_true(rank1.update_vision_cone_visual(), "Stealth Suite: Enemy VisionConeDrawer becomes visible when player crouches")
	_assert_eq(rank1.vision_cone_drawer.z_index, -2, "Stealth Suite: VisionConeDrawer sits on floor at z_index = floor*100 - 2")

	var reached_search: bool = false
	var search_marker: String = ""
	var reached_combat: bool = false
	for _s: int in range(60):
		rank1.step_ai_tick(0.12, 0.12)
		if rank1.ai_state == EnemyDummy.AIState.SEARCH and not reached_search:
			reached_search = true
			search_marker = String(rank1.update_world_status_overlay()["ai_marker"])
		if rank1.ai_state == EnemyDummy.AIState.COMBAT:
			reached_combat = true
			break
	_assert_true(reached_search, "Stealth Suite: Rising suspicion >= 0.35 transitions PATROL -> SEARCH")
	_assert_true(search_marker.contains("?") and search_marker.contains("%"), "Stealth Suite: StatusOverlay shows suspicion percent in SEARCH ('%s')" % search_marker)
	_assert_true(reached_combat, "Stealth Suite: Sustained visibility fills suspicion to 1.0 -> COMBAT")

	# -----------------------------------------------------------------------
	# 5. Noise Distraction (T / perform_stealth_distract) lures PATROL -> SEARCH
	# -----------------------------------------------------------------------
	arena.reset_arena_geometry_and_decals()
	player.revive_and_heal_all()
	player.global_position = arena.cell_to_world_center(Vector2i(11, 14))
	player.set_crouch(true)
	rank1.revive_and_heal_all()
	rank1.reset_aggro(0.0)
	rank1.global_position = arena.cell_to_world_center(Vector2i(13, 14))
	rank1.aim_angle = 0.0 # Facing right, away from player
	await get_tree().physics_frame

	var distract_pt: Vector2 = rank1.global_position + Vector2(90.0, 0.0) # Ahead-right of rank1, within 180px of player
	var d_res: Dictionary = player.perform_stealth_distract(distract_pt)
	_assert_true(bool(d_res["success"]), "Stealth Suite: perform_stealth_distract (T) succeeds")
	_assert_approx(float(d_res["radius"]), 170.0, 1e-3, "Stealth Suite: Distraction emits 170px noise radius")
	_assert_true(arena.active_noise_ripple_count >= 1, "Stealth Suite: Distraction spawns visual floor NoiseRipple ring")

	rank1.step_ai_tick(0.05, 0.05)
	_assert_eq(rank1.ai_state, EnemyDummy.AIState.SEARCH, "Stealth Suite: Patrol reacts to distraction noise (T) by entering SEARCH")
	_assert_true(rank1.search_target_pos.distance_to(d_res["pos"] as Vector2) < 2.0, "Stealth Suite: Patrol investigates exact distraction landing spot")

	# Wall-blocked distraction throw stops cleanly in front of solid high wall!
	player._distract_cooldown_timer = 0.0
	var wood_wall_c: Vector2 = arena.cell_to_world_center(TestArena.WOOD_WALL_CELLS[0])
	player.global_position = wood_wall_c + Vector2(-48.0, 0.0)
	await get_tree().physics_frame
	var d_wall: Dictionary = player.perform_stealth_distract(wood_wall_c + Vector2(80.0, 0.0))
	_assert_true(bool(d_wall["success"]) and bool(d_wall["blocked_by_wall"]), "Stealth Suite: Distraction throw detects blocking high wall")
	_assert_true((d_wall["pos"] as Vector2).x < wood_wall_c.x, "Stealth Suite: Wall-blocked distraction lands in front of wall")

	# -----------------------------------------------------------------------
	# 6. Rear Sneak Proximity (16px), 1.60x Backstab, Instinct-Dodge Bypass & Stealth Takedown (Q)
	# -----------------------------------------------------------------------
	arena.reset_arena_geometry_and_decals()
	player.revive_and_heal_all()
	player.stat_sheet.set_all_base_stats(10.0, false)
	player.refill_resources()
	player.select_weapon_slot(0) # Short Dagger
	player.set_crouch(true)

	rank1.revive_and_heal_all()
	rank1.reset_aggro(0.0)
	rank1.global_position = arena.cell_to_world_center(Vector2i(11, 14))
	rank1.spawn_origin = rank1.global_position
	rank1.patrol_dir = 1.0
	rank1.aim_angle = 0.0 # Facing right
	# Place crouched player 22px directly BEHIND Rank 1 (inside 45px standing sense, outside 16px crouch sense!)
	player.global_position = rank1.global_position + Vector2(-22.0, 0.0)
	# Place Troll far away (>160px) to verify quiet 40px takedown does NOT alert distant enemies
	troll.revive_and_heal_all()
	troll.reset_aggro(0.0)
	troll.global_position = arena.cell_to_world_center(Vector2i(17, 14))
	troll.spawn_origin = troll.global_position
	troll.patrol_dir = 1.0
	troll.aim_angle = 0.0
	await get_tree().physics_frame

	rank1.step_ai_tick(0.05, 0.05)
	_assert_eq(rank1.ai_state, EnemyDummy.AIState.PATROL, "Stealth Suite: Crouched player 22px behind enemy stays undetected (crouch proximity 16px)")
	_assert_approx(player.get_stealth_backstab_aim_mult(arena), 1.60, 1e-3, "Stealth Suite: Crouched stealth backstab boosts aim tolerance to 1.60x")

	var ret_stealth: Dictionary = arena.combat_reticle.evaluate_reticle_state(player, rank1.get_combat_origin())
	_assert_true(bool(ret_stealth["stealth_backstab_ready"]), "Stealth Suite: CombatReticle flags stealth_backstab_ready on unaware rear")
	_assert_true(bool(ret_stealth["stealth_takedown_ready"]), "Stealth Suite: CombatReticle flags stealth_takedown_ready when crouched behind enemy")
	_assert_true(String(ret_stealth["stealth_hint_text"]).contains("BACKSTAB") and String(ret_stealth["stealth_hint_text"]).contains("Q: KO"), "Stealth Suite: Reticle shows BACKSTAB | Q: KO hint")

	var td_prompt: Dictionary = player.compute_stealth_takedown_prompt()
	_assert_true(bool(td_prompt["visible"]) and String(td_prompt["text"]) == "[Q] Оглушить", "Stealth Suite: World takedown hint displays '[Q] Оглушить'")
	_assert_false(bool(player.compute_interact_prompt()["visible"]), "Stealth Suite: Takedown hint does not break compute_interact_prompt()")

	# Enhanced Backstab disables instinct_dodge at equal TP/SPD and emits quiet 55px dagger noise
	rank1.enable_instinct_dodge = true
	rank1.stat_sheet.set_base_stat(StatSheet.Stat.AGI, 200.0) # ~70% dodge chance normally
	arena.recent_noises.clear()
	var r1_chest: HitboxZone = _find_zone(rank1, AnatomyComponent.ZONE_CHEST)
	var bs_hit: Dictionary = rank1.receive_melee_hit(player, r1_chest, player.get_active_weapon(), true, 1.0, false, PenetrationResolver.AttackType.THRUST, 14.0, false, false, false, false, true)
	_assert_true(String(bs_hit.get("outcome", "")) != "dodged", "Stealth Suite: Surprise stealth backstab disables instinct_dodge at equal TP/SPD")
	var quiet_dagger_noise: bool = false
	for nr: Dictionary in arena.recent_noises:
		if is_equal_approx(float(nr.get("radius", 0.0)), CombatActor.STEALTH_DAGGER_HIT_NOISE_PX):
			quiet_dagger_noise = true
			break
	_assert_true(quiet_dagger_noise, "Stealth Suite: Stealth dagger backstab emits lowered 55px hit noise")
	rank1.enable_instinct_dodge = false
	rank1.stat_sheet.set_base_stat(StatSheet.Stat.AGI, 10.0)

	# Stealth Takedown (Q) vs Rank 1 Swordsman (CON=10) -> clean bloodless KO (25..45s) & distant Troll stays PATROL!
	arena.recent_noises.clear()
	arena.blood_trail_points.clear()
	rank1.revive_and_heal_all()
	rank1.reset_aggro(0.0)
	rank1.global_position = arena.cell_to_world_center(Vector2i(11, 14))
	rank1.spawn_origin = rank1.global_position
	rank1.patrol_dir = 1.0
	rank1.aim_angle = 0.0
	player.global_position = rank1.global_position + Vector2(-22.0, 0.0)
	player.set_crouch(true)
	await get_tree().physics_frame

	var td_ok: Dictionary = player.perform_stealth_takedown(rank1)
	_assert_true(bool(td_ok["success"]), "Stealth Suite: Stealth Takedown (Q) succeeds behind Rank 1 Swordsman (CON=10)")
	_assert_true(rank1.anatomy.is_unconscious, "Stealth Suite: Rank 1 falls cleanly into KO")
	_assert_approx(rank1.anatomy.shock_level, 100.0, 1e-3, "Stealth Suite: Takedown raises shock_level to 100%")
	_assert_approx(rank1.anatomy.get_blood_ratio(), 1.0, 1e-3, "Stealth Suite: Non-lethal takedown causes zero blood loss")
	_assert_true(float(td_ok["ko_duration"]) >= 25.0 and float(td_ok["ko_duration"]) <= 45.0, "Stealth Suite: KO duration is 25..45s (%.1fs)" % float(td_ok["ko_duration"]))
	_assert_eq(arena.last_floating_callout_text, "TAKEDOWN!", "Stealth Suite: Successful takedown spawns TAKEDOWN! floating callout")

	troll.step_ai_tick(0.05, 0.05)
	_assert_eq(troll.ai_state, EnemyDummy.AIState.PATROL, "Stealth Suite: Quiet 40px takedown does NOT wake distant Troll (>130px away)")

	# Downed Ally Discovery: Troll walking up and seeing KO'd Rank 1 in vision cone raises suspicion & enters SEARCH!
	troll.global_position = rank1.global_position + Vector2(-70.0, 0.0)
	troll.aim_angle = 0.0 # Looking straight at unconscious Rank 1
	player.global_position = arena.cell_to_world_center(TestArena.SAFE_ZONE_RECT.position) # Out of sight
	await get_tree().physics_frame
	troll.step_ai_tick(0.05, 0.05)
	_assert_eq(troll.ai_state, EnemyDummy.AIState.SEARCH, "Stealth Suite: Patrol spotting freshly KO'd ally enters SEARCH")
	_assert_true(troll.suspicion_level >= 0.35, "Stealth Suite: Spotting downed ally raises suspicion_level (%.2f)" % troll.suspicion_level)

	# Stealth Takedown (Q) vs Rank 6 Guard (CON=100) -> honestly FAILS (no free oneshot), staggers & enters COMBAT!
	rank6.revive_and_heal_all()
	rank6.reset_aggro(0.0)
	rank6.verticality.set_height_z(0.0)
	rank6.global_position = arena.cell_to_world_center(Vector2i(11, 14))
	rank6.aim_angle = 0.0
	player.global_position = rank6.global_position + Vector2(-22.0, 0.0)
	player.set_crouch(true)
	await get_tree().physics_frame

	var td_fail: Dictionary = player.perform_stealth_takedown(rank6)
	_assert_false(bool(td_fail["success"]), "Stealth Suite: Rank 1 player CANNOT free-takedown Rank 6 Guard (CON=100)")
	_assert_eq(String(td_fail.get("reason", "")), "resisted", "Stealth Suite: Failed takedown returns reason 'resisted'")
	_assert_false(rank6.anatomy.is_unconscious, "Stealth Suite: Rank 6 Guard stays conscious after resisting takedown")
	_assert_eq(rank6.combat_state, CombatActor.CombatState.STAGGERED, "Stealth Suite: Resisted takedown applies brief Stagger")
	_assert_eq(rank6.ai_state, EnemyDummy.AIState.COMBAT, "Stealth Suite: Resisted takedown immediately alerts Rank 6 into COMBAT")

	# -----------------------------------------------------------------------
	# 7. Stealth HUD Indicator (HIDDEN -> CAUTION -> DETECTED) & CROUCH Badge
	# -----------------------------------------------------------------------
	rank1.revive_and_heal_all()
	rank1.reset_aggro(0.0)
	troll.revive_and_heal_all()
	troll.reset_aggro(0.0)
	rank6.revive_and_heal_all()
	rank6.reset_aggro(0.0)
	player.revive_and_heal_all()
	player.global_position = cover_center
	player.set_crouch(true)
	hud.set_compact_hud_mode(true)
	hud._refresh_all_views()

	_assert_true(hud.game_stance_badges["CROUCH"].visible, "Stealth Suite: Game HUD displays CROUCH badge")
	_assert_true(hud.lbl_game_stealth.visible and hud.lbl_game_stealth.text.contains("STEALTH: HIDDEN"), "Stealth Suite: Game HUD shows STEALTH: HIDDEN when hidden")

	rank1._set_ai_state(EnemyDummy.AIState.SEARCH)
	rank1.suspicion_level = 0.64
	hud._refresh_all_views()
	_assert_true(hud.lbl_game_stealth.text.contains("CAUTION"), "Stealth Suite: Game HUD switches to STEALTH: CAUTION when an enemy suspects")

	rank1.engage_target(player)
	hud._refresh_all_views()
	_assert_true(hud.lbl_game_stealth.text.contains("DETECTED"), "Stealth Suite: Game HUD switches to STEALTH: DETECTED in COMBAT")
	hud.set_compact_hud_mode(false)

	remove_child(arena)
	arena.queue_free()
	EventBus.set_debug_highlight_weak_points(false)
	EventBus.set_debug_anti_regen_attacks(false)
	SimulationClock.reset_defaults()
	WorldCalendar.reset_calendar(0)


# ===========================================================================
# SUITE 29: 3/4 Top-Down Visuals, Procedural Animation & 3/4 Environment
# ===========================================================================

func _test_three_quarter_visuals_and_procedural_animation() -> void:
	SimulationClock.reset_defaults()
	WorldCalendar.reset_calendar(12)
	WorldCalendar.paused = true
	FloorLayerManager.reset(0)

	var arena_scene: PackedScene = load("res://scenes/test_arena.tscn") as PackedScene
	var arena: TestArena = arena_scene.instantiate() as TestArena
	add_child(arena)
	arena.set_all_enemies_ai_enabled(false)
	await get_tree().physics_frame

	var player: PlayerController = arena.entities_container.get_node("Player") as PlayerController
	var rank1: EnemyDummy = arena.entities_container.get_node("Rank1Swordsman") as EnemyDummy
	var troll: EnemyDummy = arena.entities_container.get_node("TrollBerserker") as EnemyDummy
	var rank6: EnemyDummy = arena.entities_container.get_node("Rank6Guard") as EnemyDummy

	# 1. Distinct 3/4 VisualStyles, zero NosePoly, intact core visual contracts
	_assert_eq(player.visual_style, CombatActor.VisualStyle.PLAYER_ADVENTURER, "3/4 Visuals: Player uses PLAYER_ADVENTURER style")
	_assert_eq(rank1.visual_style, CombatActor.VisualStyle.RANK_1_SWORDSMAN, "3/4 Visuals: Rank 1 uses RANK_1_SWORDSMAN style")
	_assert_eq(troll.visual_style, CombatActor.VisualStyle.TROLL_BERSERKER, "3/4 Visuals: Troll uses TROLL_BERSERKER style")
	_assert_eq(rank6.visual_style, CombatActor.VisualStyle.RANK_6_GUARD, "3/4 Visuals: Rank 6 Guard uses RANK_6_GUARD style")
	_assert_true(player.nose_polygon == null and player.body_visual.get_node_or_null("NosePoly") == null, "3/4 Visuals: Obsolete top-down NosePoly removed")
	_assert_true(player.visual_rig != null and player.visual_rig.get_parent() == player.body_visual, "3/4 Visuals: Internal VisualRig lives inside BodyVisual")
	_assert_eq(player.limb_polygons.size(), 5, "3/4 Visuals: limb_polygons preserves all 5 anatomical limb keys")
	_assert_true(player.body_visual.get_node_or_null("WeaponPivot") == player.weapon_pivot, "3/4 Visuals: WeaponPivot stays accessible under BodyVisual")
	_assert_true(player.body_visual.get_node_or_null("WingVisualRoot") == player.wing_visual_root, "3/4 Visuals: WingVisualRoot stays accessible under BodyVisual")
	_assert_true(player.body_visual.get_node_or_null("ManaFlightRing") == player.mana_flight_ring, "3/4 Visuals: ManaFlightRing stays accessible under BodyVisual")
	_assert_true(player.body_visual.get_node_or_null("BlockArc") == player.block_arc_line, "3/4 Visuals: BlockArc stays accessible under BodyVisual")
	_assert_true(player.body_visual.get_node_or_null("SlashTrail") == player.slash_trail_line, "3/4 Visuals: SlashTrail stays accessible under BodyVisual")

	# 2. Front / Back switching & Left / Right mirroring without rotating BodyVisual
	player.aim_angle = 0.45 # Down-right: sin > -0.35, cos > 0
	player._update_visual_facing(player.aim_angle)
	_assert_false(player.is_facing_back, "3/4 Facing: Aiming down-right shows Front view")
	_assert_false(player.is_facing_left, "3/4 Facing: Aiming down-right faces Right")
	_assert_true(player.head_front_details.visible and not player.head_back_details.visible, "3/4 Facing: Front view shows head front details & hides back")
	_assert_true(player.torso_front_details.visible and not player.torso_back_details.visible, "3/4 Facing: Front view shows torso front details & hides back")
	_assert_true(player.weapon_pivot.z_index > 0, "3/4 Facing: Front view layers WeaponPivot in front of torso")
	_assert_approx(player.weapon_pivot.scale.y, 1.0, 1e-4, "3/4 Facing: Aiming right keeps WeaponPivot.scale.y == 1.0")
	_assert_true(player.wing_visual_root.z_index < 0, "3/4 Facing: Front view places wings behind torso")
	_assert_approx(player.body_visual.rotation, 0.0, 1e-4, "3/4 Facing: BodyVisual stays strictly upright to camera")

	player.aim_angle = -2.20 # Up-left: sin < -0.35, cos < 0
	player._update_visual_facing(player.aim_angle)
	_assert_true(player.is_facing_back, "3/4 Facing: Aiming up (sin < -0.35) switches to Back view")
	_assert_true(player.is_facing_left, "3/4 Facing: Aiming left (cos < 0) sets is_facing_left=true")
	_assert_true(not player.head_front_details.visible and player.head_back_details.visible, "3/4 Facing: Back view shows occiput/back details & hides face")
	_assert_true(not player.torso_front_details.visible and player.torso_back_details.visible, "3/4 Facing: Back view shows back torso details & hides chest")
	_assert_eq(player.weapon_pivot.z_index, -1, "3/4 Facing: Back view sends WeaponPivot behind torso (z_index = -1)")
	_assert_approx(player.weapon_pivot.scale.y, -1.0, 1e-4, "3/4 Facing: Aiming left flips WeaponPivot.scale.y == -1.0")
	_assert_approx(player.head_front_details.scale.x, -1.0, 1e-4, "3/4 Facing: Aiming left mirrors head detail scale.x == -1.0")
	_assert_true(player.wing_visual_root.z_index > 0, "3/4 Facing: Back view renders wings in front of back")
	_assert_approx(player.body_visual.rotation, 0.0, 1e-4, "3/4 Facing: BodyVisual still upright in Back view")

	# 3. Procedural walk cycle on action_delta without mutating BodyVisual.position/scale
	player.aim_angle = 0.0
	player._update_visual_facing(0.0)
	player.set_crouch(true)
	player.current_move_velocity = Vector2(180.0, 0.0)
	var phase_before: float = player.walk_cycle_phase
	player.step_procedural_animation(0.0)
	_assert_approx(player.walk_cycle_phase, phase_before, 1e-5, "3/4 Anim: Zero action_delta freezes walk cycle (Hitstop safe)")
	player.step_procedural_animation(0.18)
	_assert_true(player.walk_cycle_phase > phase_before + 0.5, "3/4 Anim: Positive action_delta advances walk_cycle_phase")
	var l_leg_pos: Vector2 = player.limb_polygons[AnatomyComponent.ZONE_LEFT_LEG].position
	var r_leg_pos: Vector2 = player.limb_polygons[AnatomyComponent.ZONE_RIGHT_LEG].position
	_assert_true(absf(l_leg_pos.y - r_leg_pos.y) > 0.3, "3/4 Anim: Left & right legs step alternately in elliptical cycle")
	player.trigger_squash(Vector2(1.16, 0.86))
	_assert_approx(player.body_visual.scale.x, CombatActor.CROUCH_VISUAL_SCALE, 1e-4, "3/4 Anim: Crouch BodyVisual.scale.x (0.84) preserved during squash & walk")
	_assert_approx(player.body_visual.position.y, 0.0, 1e-4, "3/4 Anim: BodyVisual.position.y stays owned by VerticalityComponent")
	player.set_crouch(false)
	player.current_move_velocity = Vector2.ZERO

	# 4. Leg injury limp, bloody stump, Prone drop & Flight leg dangle + wing flapping
	var leg_frac: Dictionary = rank1.anatomy.apply_blunt_hit(AnatomyComponent.ZONE_LEFT_LEG, 260.0, 1.0, 0.0, false)
	_assert_true(bool(leg_frac["fractured"]), "3/4 Limp: Fractured Rank 1 left leg for limp check")
	_assert_true(rank1.is_visual_limping(), "3/4 Limp: Fractured leg activates visual limping")
	rank1.current_move_velocity = Vector2(110.0, 0.0)
	rank1.step_procedural_animation(0.22)
	_assert_true(absf(rank1.visual_rig.rotation) > 0.05, "3/4 Limp: VisualRig tilts noticeably during limping gait")

	troll.anatomy.sever_limb(AnatomyComponent.ZONE_LEFT_LEG, player)
	_assert_false(troll.limb_polygons[AnatomyComponent.ZONE_LEFT_LEG].visible, "3/4 Sever: Severed left leg hides Limb_LeftLeg")
	_assert_true(troll.stump_nodes[AnatomyComponent.ZONE_LEFT_LEG].visible, "3/4 Sever: Severed left leg reveals bloody amputation stump")
	_assert_true(troll.visual_rig.position.y > 4.0, "3/4 Prone: Severed leg drops VisualRig toward floor")
	_assert_approx(troll.body_visual.rotation, 0.0, 1e-4, "3/4 Prone: BodyVisual itself remains upright during Prone collapse")

	player.set_has_wings(true)
	player.set_flight_mode(VerticalityComponent.FlightMode.WING_FLIGHT, VerticalityComponent.HEIGHT_HIGH_FLIGHT)
	var wing_rot_0: float = player.wing_left_poly.rotation
	player.step_procedural_animation(0.14)
	_assert_true(absf(player.wing_left_poly.rotation - wing_rot_0) > 0.08, "3/4 Flight: Wings flap rhythmically in WING_FLIGHT on action_delta")
	_assert_true(player.wing_left_poly.scale.x > 1.2, "3/4 Flight: Flapping wing keeps spread scale.x > 1.2")
	_assert_true(player.limb_polygons[AnatomyComponent.ZONE_LEFT_LEG].position.y > player._limb_base_positions[AnatomyComponent.ZONE_LEFT_LEG].y + 1.0, "3/4 Flight: Legs dangle downward while airborne")
	player.land_from_flight(false, "test_done")
	player.set_has_wings(false)

	# 5. Half-swording off-hand shift, WINDUP pullback, LodgedWeapon attachment & Hitflash
	player.revive_and_heal_all()
	player.select_weapon_slot(1) # Greatsword (can_half_sword = true)
	player.aim_angle = 0.0
	player._update_visual_facing(0.0)
	var hand_normal_x: float = player.get_offhand_hand_rig_pos().x
	_assert_true(player.set_half_swording(true), "3/4 Combat: Enabled Half-swording on Greatsword")
	var hand_hs_x: float = player.get_offhand_hand_rig_pos().x
	_assert_true(hand_hs_x > hand_normal_x + 2.5, "3/4 Combat: Half-swording shifts off-hand forward onto mid-blade (%.1f -> %.1f)" % [hand_normal_x, hand_hs_x])
	player.set_half_swording(false)

	_assert_true(player.start_attack(player.global_position + Vector2(60.0, 0.0), PenetrationResolver.AttackType.THRUST), "3/4 Combat: Started THRUST for windup pullback check")
	_assert_approx(player.weapon_pivot.position.length(), 0.0, 1e-4, "3/4 Combat: weapon_pivot.position remains ZERO during WINDUP")
	_assert_true(player.weapon_model_root.position.x < -1.0, "3/4 Combat: WeaponModelRoot visually pulls back during THRUST WINDUP")
	player.step_combat_fsm(1.2)

	var dagger_tpl: WeaponData = load(PlayerController.DAGGER_TEMPLATE_PATH) as WeaponData
	var lodged_w: WeaponData = dagger_tpl.create_runtime_copy()
	troll.revive_and_heal_all()
	troll.anatomy.lodge_weapon(AnatomyComponent.ZONE_CHEST, lodged_w, player, 8.0)
	_assert_eq(troll.get_lodged_visual_count(AnatomyComponent.ZONE_CHEST), 1, "3/4 Lodged: Lodging blade attaches visual weapon to Chest zone")
	troll.anatomy.dislodge_weapon(AnatomyComponent.ZONE_CHEST, true)
	_assert_eq(troll.get_lodged_visual_count(AnatomyComponent.ZONE_CHEST), 0, "3/4 Lodged: Extracting blade cleanly removes visual weapon")

	player.trigger_hitflash(Color(2.3, 2.3, 2.3, 1.0), 0.065)
	_assert_true(player.visual_rig.modulate.r > 1.8, "3/4 GameFeel: Hitflash brightens VisualRig modulate")
	player.step_procedural_animation(0.10)
	_assert_approx(player.visual_rig.modulate.r, 1.0, 1e-3, "3/4 GameFeel: Hitflash decays cleanly back to Color.WHITE")

	# 6. 3/4 Procedural Atlas Shading (Top Cap brighter than Front Facade) & Arena Wall Overlays
	var atlas_img: Image = ProceduralTileSetBuilder.build_atlas_image()
	for wall_tile: Vector2i in [
		ProceduralTileSetBuilder.TILE_WALL_WOOD,
		ProceduralTileSetBuilder.TILE_WALL_BRICK,
		ProceduralTileSetBuilder.TILE_WALL_STONE,
	]:
		var top_col: Color = atlas_img.get_pixel(wall_tile.x * 32 + 12, 5)
		var front_col: Color = atlas_img.get_pixel(wall_tile.x * 32 + 12, 22)
		_assert_true(top_col.get_luminance() > front_col.get_luminance(), "3/4 Atlas: Wall tile %s top cap is brighter than front facade" % str(wall_tile))
	var fence_corner: Color = atlas_img.get_pixel(ProceduralTileSetBuilder.TILE_LOW_OBSTACLE.x * 32 + 1, 1)
	var fence_post: Color = atlas_img.get_pixel(ProceduralTileSetBuilder.TILE_LOW_OBSTACLE.x * 32 + 5, 14)
	_assert_approx(fence_corner.a, 0.0, 0.01, "3/4 Atlas: LowObstacle fence leaves transparent floor margin at top corner")
	_assert_approx(fence_post.a, 1.0, 0.01, "3/4 Atlas: LowObstacle fence renders solid wooden posts")

	_assert_true(arena.floor0_wall_shadows != null and not arena.floor0_wall_shadows.shadow_rects.is_empty(), "3/4 Arena: Floor 0 renders cast wall shadows")
	_assert_true(arena.floor0_wall_crowns != null and not arena.floor0_wall_crowns.crown_entries.is_empty(), "3/4 Arena: Floor 0 renders 3/4 wall parapet crowns")
	var shadows_before: int = arena.floor0_wall_shadows.shadow_rects.size()
	arena.try_damage_wall_at(0, TestArena.WOOD_WALL_CELLS[2], 30.0) # South-most wood wall casts a shadow
	_assert_true(arena.floor0_wall_shadows.shadow_rects.size() != shadows_before or not arena.is_wall_solid_at(0, TestArena.WOOD_WALL_CELLS[2]), "3/4 Arena: Breaking wall updates 3/4 cast shadows cleanly")
	arena.update_floor_visibility(0, true, true)
	_assert_approx(arena.floor1_wall_shadows.modulate.a, 0.0, 1e-4, "3/4 Arena: Floor 1 wall shadows fade cleanly with RoofLayer/Floor 1")
	_assert_approx(arena.floor1_wall_crowns.modulate.a, 0.0, 1e-4, "3/4 Arena: Floor 1 wall crowns fade cleanly with RoofLayer/Floor 1")

	remove_child(arena)
	arena.queue_free()
	EventBus.set_debug_highlight_weak_points(false)
	EventBus.set_debug_anti_regen_attacks(false)
	SimulationClock.reset_defaults()
	WorldCalendar.reset_calendar(0)
