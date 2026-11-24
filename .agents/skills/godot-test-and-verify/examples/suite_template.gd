# Reference templates for adding new test suites to res://tests/run_tests.gd
# (or splitting new v0.5 suites into res://tests/suites/test_<domain>.gd).

# ---------------------------------------------------------------------------
# 1. Pure Math / Core Sync Suite (register via _run_suite in _ready())
# ---------------------------------------------------------------------------
func _test_example_core_math() -> void:
	# Always work with fresh instances; do not mutate shared .tres templates!
	var sheet: StatSheet = StatSheet.new(StatSheet.DEFAULT_HUMAN_RACIAL_CAP, StatSheet.RacePreset.HUMAN)
	sheet.awaken_mana(100.0, 100.0)
	sheet.set_all_base_stats(100.0, true)

	_assert_true(sheet.mana_awakened, "Example Core: mana_awakened enabled")
	_assert_approx(sheet.get_stat(StatSheet.Stat.M_CTRL), 100.0, 1e-4, "Example Core: M_CTRL == 100")

	var dagger_tpl: WeaponData = load("res://data/dagger.tres") as WeaponData
	_assert_true(dagger_tpl != null, "Example Core: dagger.tres loads cleanly")
	var runtime_weapon: WeaponData = dagger_tpl.duplicate(true) as WeaponData
	runtime_weapon.durability = 10.0
	_assert_approx(dagger_tpl.durability, 40.0, 1e-4, "Example Core: template .tres stayed immutable")


# ---------------------------------------------------------------------------
# 2. Physics / Arena Async Integration Suite (register via await _run_suite_async)
# ---------------------------------------------------------------------------
func _test_example_arena_integration() -> void:
	# 1) Clean baseline before spawning TestArena
	WorldCalendar.paused = true
	WorldCalendar.reset_calendar(0)
	SimulationClock.reset_defaults()
	FloorLayerManager.reset(0)
	EventBus.set_debug_highlight_weak_points(false)
	EventBus.set_debug_anti_regen_attacks(false)

	var arena_scene: PackedScene = load("res://scenes/test_arena.tscn") as PackedScene
	var arena: TestArena = arena_scene.instantiate() as TestArena
	add_child(arena)
	arena.set_all_enemies_ai_enabled(false) # Freeze live AI ticks so step_ai_tick() stays 100% deterministic
	await get_tree().physics_frame
	await get_tree().physics_frame

	var hud: DebugHUD = arena.get_node_or_null("DebugHUD") as DebugHUD
	var player: PlayerController = arena.entities_container.get_node_or_null("Player") as PlayerController
	var rank1: EnemyDummy = arena.entities_container.get_node_or_null("Rank1Swordsman") as EnemyDummy
	_assert_true(player != null and rank1 != null and hud != null, "Example Arena: player, Rank1, and HUD spawned")

	# 2) Deterministic positioning + physics sync (avoid real-time wall-clock timers)
	rank1.revive_and_heal_all()
	rank1.reset_aggro(0.0)
	player.revive_and_heal_all()
	player.global_position = arena.cell_to_world_center(Vector2i(8, 8))
	rank1.global_position = player.global_position + Vector2(64.0, 0.0)
	await get_tree().physics_frame

	# 3) Step AI / physiology explicitly
	rank1.step_ai_tick(0.05, 0.05)
	_assert_eq(rank1.get_floor_level(), 0, "Example Arena: Rank1 remains on floor 0")

	# 4) Mandatory teardown — never leak TestArena or autoload state into next suite!
	remove_child(arena)
	arena.queue_free()
	await get_tree().process_frame
	BrainFactory.clear_custom_brains()
	EventBus.last_penetration_log = {}
	EventBus.last_combat_outcome = {}
	EventBus.last_blade_clash = {}
	EventBus.set_debug_highlight_weak_points(false)
	EventBus.set_debug_anti_regen_attacks(false)
	SimulationClock.reset_defaults()
	WorldCalendar.reset_calendar(0)
	FloorLayerManager.reset(0)
