extends Node
## SimulationClock Autoload (GDD Sections 2.3 and 12.1, v0.2).
## Keeps Engine.time_scale strictly at 1.0, manages TempoMode (PEACEFUL 1.0x vs COMBAT_OVERDRIVE),
## tracks active_aggro_ids to block mid-combat disengage toggle, executes local Hitstop (0.03-0.07s)
## without slowing WorldCalendar, and computes separated world_delta and action_delta values.

enum TempoMode {
	PEACEFUL = 0,
	COMBAT_OVERDRIVE = 1,
}

const REFERENCE_STAT: float = 10.0
const MIN_WORLD_TIME_SCALE: float = 0.02
const MAX_WORLD_TIME_SCALE: float = 1.0
const MIN_PERCEPTION_REGULATOR: float = 0.0
const MAX_PERCEPTION_REGULATOR: float = 1.0
const MIN_SPEED_REGULATOR: float = 0.02
const MAX_SPEED_REGULATOR: float = 1.0
const MAX_ACTION_MICRO_STEP: float = 0.02
const UI_SLOWDOWN_SCALE: float = 0.1
const LOSS_OF_CONTROL_SPD_TP_RATIO: float = 1.5
const IMPERCEPTIBLE_SPEED_RATIO: float = 10.0
const MIN_HITSTOP_SEC: float = 0.03
const MAX_HITSTOP_SEC: float = 0.07

var tempo_mode: TempoMode = TempoMode.PEACEFUL
var active_aggro_ids: Dictionary[int, bool] = {}
var manual_overdrive_requested: bool = false

var hitstop_timer: float = 0.0
var hitstop_actor_ids: Dictionary[int, bool] = {}

var perception_regulator: float = 1.0:
	set(value):
		perception_regulator = clampf(value, MIN_PERCEPTION_REGULATOR, MAX_PERCEPTION_REGULATOR)
		_recalculate_cached_scales()

var speed_regulator: float = 1.0:
	set(value):
		speed_regulator = clampf(value, MIN_SPEED_REGULATOR, MAX_SPEED_REGULATOR)

var player_tp: float = REFERENCE_STAT:
	set(value):
		player_tp = maxf(0.0, value)
		_recalculate_cached_scales()

var player_spd: float = REFERENCE_STAT:
	set(value):
		player_spd = maxf(0.0, value)

var player_ctrl: float = REFERENCE_STAT:
	set(value):
		player_ctrl = maxf(0.0, value)

var player_agi: float = REFERENCE_STAT:
	set(value):
		player_agi = maxf(0.0, value)

## Optional Standard-mode UI slowdown (GDD 12.7); false by default for pure combat math.
var ui_slowdown_active: bool = false:
	set(value):
		ui_slowdown_active = value
		_recalculate_cached_scales()

var effective_tp: float = REFERENCE_STAT
var world_time_scale: float = MAX_WORLD_TIME_SCALE
var tp_penalty_mult: float = 1.0
var last_raw_delta: float = 0.0
var world_delta: float = 0.0
var player_action_delta: float = 0.0

var _bound_player_stats: StatSheet = null


func _ready() -> void:
	Engine.time_scale = 1.0
	_recalculate_cached_scales()


func _process(delta: float) -> void:
	if not is_equal_approx(Engine.time_scale, 1.0):
		Engine.time_scale = 1.0
	tick_hitstop(delta)
	_sync_from_bound_stats()
	_recalculate_cached_scales()
	last_raw_delta = delta
	world_delta = delta * world_time_scale
	player_action_delta = get_player_action_delta(delta)


func bind_player_stats(stat_sheet: StatSheet) -> void:
	_bound_player_stats = stat_sheet
	_sync_from_bound_stats()
	_recalculate_cached_scales()


func unbind_player_stats() -> void:
	_bound_player_stats = null


func unbind_player_stats_if_matches(stat_sheet: StatSheet) -> void:
	if _bound_player_stats == stat_sheet:
		_bound_player_stats = null


func set_player_stats(
	p_tp: float,
	p_spd: float,
	p_ctrl: float = REFERENCE_STAT,
	p_agi: float = REFERENCE_STAT
) -> void:
	_bound_player_stats = null
	player_tp = p_tp
	player_spd = p_spd
	player_ctrl = p_ctrl
	player_agi = p_agi
	_recalculate_cached_scales()


func reset_defaults() -> void:
	_bound_player_stats = null
	tempo_mode = TempoMode.PEACEFUL
	active_aggro_ids.clear()
	manual_overdrive_requested = false
	hitstop_timer = 0.0
	hitstop_actor_ids.clear()
	perception_regulator = 1.0
	speed_regulator = 1.0
	player_tp = REFERENCE_STAT
	player_spd = REFERENCE_STAT
	player_ctrl = REFERENCE_STAT
	player_agi = REFERENCE_STAT
	ui_slowdown_active = false
	last_raw_delta = 0.0
	world_delta = 0.0
	player_action_delta = 0.0
	Engine.time_scale = 1.0
	_recalculate_cached_scales()


# ---------------------------------------------------------------------------
# TempoMode & Active Aggro Registry (GDD 2.3, 12.1)
# ---------------------------------------------------------------------------

func is_peaceful() -> bool:
	return tempo_mode == TempoMode.PEACEFUL


func is_combat_overdrive() -> bool:
	return tempo_mode == TempoMode.COMBAT_OVERDRIVE


## Passive running wall ramming is strictly disabled in PEACEFUL (GDD 2.3, 12.1, 14.5).
func is_wall_ramming_allowed() -> bool:
	return tempo_mode == TempoMode.COMBAT_OVERDRIVE


func has_active_aggro() -> bool:
	return not active_aggro_ids.is_empty()


func get_active_aggro_count() -> int:
	return active_aggro_ids.size()


func get_active_aggro_ids() -> Array[int]:
	var ids: Array[int] = []
	for key: int in active_aggro_ids.keys():
		ids.append(key)
	return ids


func register_aggro(enemy_id: int) -> void:
	active_aggro_ids[enemy_id] = true
	if tempo_mode != TempoMode.COMBAT_OVERDRIVE:
		_apply_tempo_mode(TempoMode.COMBAT_OVERDRIVE, "aggro_engaged")


func unregister_aggro(enemy_id: int, auto_return_peaceful: bool = true) -> bool:
	active_aggro_ids.erase(enemy_id)
	if active_aggro_ids.is_empty() and auto_return_peaceful and not manual_overdrive_requested:
		if tempo_mode != TempoMode.PEACEFUL:
			_apply_tempo_mode(TempoMode.PEACEFUL, "aggro_cleared")
			return true
	return false


func clear_all_aggro(auto_return_peaceful: bool = true) -> void:
	active_aggro_ids.clear()
	if auto_return_peaceful and not manual_overdrive_requested and tempo_mode != TempoMode.PEACEFUL:
		_apply_tempo_mode(TempoMode.PEACEFUL, "aggro_cleared")


func notify_player_attack() -> void:
	if tempo_mode != TempoMode.COMBAT_OVERDRIVE:
		_apply_tempo_mode(TempoMode.COMBAT_OVERDRIVE, "player_attack")


## Manual toggle bound to G (GDD 2.3, 12.1, 14.5).
## Turning OFF COMBAT_OVERDRIVE is strictly blocked while active_aggro_ids is non-empty!
func toggle_player_tempo() -> bool:
	return toggle_tempo_mode_manual()


func toggle_tempo_mode_manual() -> bool:
	if tempo_mode == TempoMode.PEACEFUL:
		manual_overdrive_requested = true
		_apply_tempo_mode(TempoMode.COMBAT_OVERDRIVE, "manual_toggle")
		return true
	if has_active_aggro():
		return false
	manual_overdrive_requested = false
	_apply_tempo_mode(TempoMode.PEACEFUL, "manual_toggle")
	return true


func set_tempo_mode(new_mode: TempoMode, force: bool = false, reason: String = "manual") -> bool:
	if new_mode == TempoMode.PEACEFUL and has_active_aggro() and not force:
		return false
	if new_mode == TempoMode.COMBAT_OVERDRIVE and reason == "manual":
		manual_overdrive_requested = true
	elif new_mode == TempoMode.PEACEFUL:
		manual_overdrive_requested = false
	_apply_tempo_mode(new_mode, reason)
	return true


func _apply_tempo_mode(new_mode: TempoMode, reason: String) -> void:
	if tempo_mode == new_mode:
		_recalculate_cached_scales()
		return
	var old_mode: TempoMode = tempo_mode
	tempo_mode = new_mode
	_recalculate_cached_scales()
	var bus: Node = _get_event_bus()
	if bus != null:
		bus.emit_signal("tempo_mode_changed", old_mode, new_mode, reason)


# ---------------------------------------------------------------------------
# Local Hitstop (0.03..0.07 s for combat pair / arena without slowing WorldCalendar)
# ---------------------------------------------------------------------------

func trigger_hitstop(
	duration_sec: float = 0.05,
	source: Node = null,
	target: Node = null,
	arena_wide: bool = false
) -> float:
	var clamped_dur: float = clampf(duration_sec, MIN_HITSTOP_SEC, MAX_HITSTOP_SEC)
	var was_inactive: bool = hitstop_timer <= 0.0
	hitstop_timer = maxf(hitstop_timer, clamped_dur)

	if arena_wide or (source == null and target == null):
		hitstop_actor_ids.clear()
	else:
		if was_inactive:
			hitstop_actor_ids.clear()
		if source != null:
			hitstop_actor_ids[source.get_instance_id()] = true
		if target != null:
			hitstop_actor_ids[target.get_instance_id()] = true

	var bus: Node = _get_event_bus()
	if bus != null:
		bus.emit_signal("hitstop_triggered", clamped_dur, source, target)
	return clamped_dur


func tick_hitstop(raw_delta: float) -> void:
	if hitstop_timer <= 0.0 or raw_delta <= 0.0:
		return
	hitstop_timer = maxf(0.0, hitstop_timer - raw_delta)
	if hitstop_timer <= 0.0:
		hitstop_actor_ids.clear()


func clear_hitstop() -> void:
	hitstop_timer = 0.0
	hitstop_actor_ids.clear()


func is_in_hitstop(actor_id: int = 0) -> bool:
	if hitstop_timer <= 0.0:
		return false
	if hitstop_actor_ids.is_empty() or actor_id == 0:
		return true
	return hitstop_actor_ids.has(actor_id)


# ---------------------------------------------------------------------------
# Regulators & Internal Scale Synchronization
# ---------------------------------------------------------------------------

func toggle_perception_regulator() -> float:
	perception_regulator = 0.0 if perception_regulator > 0.5 else 1.0
	return perception_regulator


func adjust_speed_regulator(direction: int) -> float:
	_sync_from_bound_stats()
	var step: float = get_speed_regulator_step(player_ctrl)
	speed_regulator = clampf(speed_regulator + float(signi(direction)) * step, MIN_SPEED_REGULATOR, MAX_SPEED_REGULATOR)
	return speed_regulator


func _sync_from_bound_stats() -> void:
	if _bound_player_stats == null:
		return
	player_tp = _bound_player_stats.get_stat(StatSheet.Stat.TP)
	player_spd = _bound_player_stats.get_stat(StatSheet.Stat.SPD)
	player_ctrl = _bound_player_stats.get_stat(StatSheet.Stat.CTRL)
	player_agi = _bound_player_stats.get_stat(StatSheet.Stat.AGI)


func _recalculate_cached_scales() -> void:
	if tempo_mode == TempoMode.PEACEFUL:
		effective_tp = REFERENCE_STAT
		world_time_scale = MAX_WORLD_TIME_SCALE
	else:
		effective_tp = compute_effective_tp(player_tp, perception_regulator)
		world_time_scale = compute_world_time_scale(player_tp, perception_regulator)
	if ui_slowdown_active:
		world_time_scale = minf(world_time_scale, UI_SLOWDOWN_SCALE)
	tp_penalty_mult = compute_tp_penalty_mult(player_tp)


# ---------------------------------------------------------------------------
# Pure Formula Functions (GDD Section 2.3)
# ---------------------------------------------------------------------------

func compute_effective_spd(raw_spd: float, p_tempo_mode: TempoMode = TempoMode.COMBAT_OVERDRIVE) -> float:
	var safe_spd: float = maxf(0.0, raw_spd)
	if p_tempo_mode == TempoMode.PEACEFUL:
		return minf(safe_spd, REFERENCE_STAT)
	return safe_spd


func compute_effective_tp(p_player_tp: float, p_perception_regulator: float) -> float:
	var reg: float = clampf(p_perception_regulator, MIN_PERCEPTION_REGULATOR, MAX_PERCEPTION_REGULATOR)
	return maxf(REFERENCE_STAT, REFERENCE_STAT + (p_player_tp - REFERENCE_STAT) * reg)


func compute_world_time_scale(p_player_tp: float, p_perception_regulator: float) -> float:
	var eff_tp: float = compute_effective_tp(p_player_tp, p_perception_regulator)
	return clampf(REFERENCE_STAT / eff_tp, MIN_WORLD_TIME_SCALE, MAX_WORLD_TIME_SCALE)


func compute_tp_penalty_mult(p_player_tp: float) -> float:
	return clampf(p_player_tp / REFERENCE_STAT, 0.0, 1.0)


func compute_world_delta(raw_delta: float, p_player_tp: float, p_perception_regulator: float) -> float:
	return maxf(0.0, raw_delta) * compute_world_time_scale(p_player_tp, p_perception_regulator)


func compute_enemy_action_delta(p_world_delta: float, enemy_spd: float) -> float:
	return maxf(0.0, p_world_delta) * (maxf(0.0, enemy_spd) / REFERENCE_STAT)


func compute_player_action_delta(
	p_world_delta: float,
	p_player_spd: float,
	p_player_tp: float,
	p_speed_regulator: float
) -> float:
	var s_reg: float = clampf(p_speed_regulator, MIN_SPEED_REGULATOR, MAX_SPEED_REGULATOR)
	var penalty: float = compute_tp_penalty_mult(p_player_tp)
	return maxf(0.0, p_world_delta) * (maxf(0.0, p_player_spd) / REFERENCE_STAT) * s_reg * penalty


func compute_action_micro_steps(action_delta: float, max_step: float = MAX_ACTION_MICRO_STEP) -> Array[float]:
	var steps: Array[float] = []
	if action_delta <= 0.0:
		return steps
	var safe_max: float = maxf(0.001, max_step)
	if action_delta <= safe_max:
		steps.append(action_delta)
		return steps
	var count: int = ceili(action_delta / safe_max)
	var step_size: float = action_delta / float(count)
	for _i: int in range(count):
		steps.append(step_size)
	return steps


func get_speed_regulator_step(ctrl: float) -> float:
	if ctrl >= 80.0:
		return 0.02
	if ctrl >= 30.0:
		return 0.05
	if ctrl >= 10.0:
		return 0.10
	return 0.25


func is_losing_control(p_player_spd: float, p_player_tp: float, p_speed_regulator: float = 1.0) -> bool:
	var s_reg: float = clampf(p_speed_regulator, MIN_SPEED_REGULATOR, MAX_SPEED_REGULATOR)
	return (p_player_spd * s_reg) / maxf(1.0, p_player_tp) > LOSS_OF_CONTROL_SPD_TP_RATIO


func is_player_losing_control() -> bool:
	if tempo_mode == TempoMode.PEACEFUL:
		return false
	_sync_from_bound_stats()
	return is_losing_control(player_spd, player_tp, speed_regulator)


func get_player_spd_to_tp_ratio() -> float:
	if tempo_mode == TempoMode.PEACEFUL:
		return 1.0
	_sync_from_bound_stats()
	var s_reg: float = clampf(speed_regulator, MIN_SPEED_REGULATOR, MAX_SPEED_REGULATOR)
	return (player_spd * s_reg) / maxf(1.0, player_tp)


## Always checks against REAL player.TP regardless of TempoMode (GDD 2.3, 12.1 ambush protection).
func is_imperceptible_speed(enemy_spd: float, p_player_tp: float) -> bool:
	return enemy_spd / maxf(1.0, p_player_tp) >= IMPERCEPTIBLE_SPEED_RATIO


## Evaluates ambush / imperceptible-speed threat strictly from REAL player TP, AGI, and SPD
## even when the player was walking in PEACEFUL (1.0x) mode (GDD 2.3 & 12.1).
func evaluate_ambush_imperceptible(
	enemy_spd: float,
	real_player_tp: float = -1.0,
	real_player_agi: float = -1.0,
	real_player_spd: float = -1.0
) -> Dictionary:
	_sync_from_bound_stats()
	var tp_val: float = real_player_tp if real_player_tp >= 0.0 else player_tp
	var agi_val: float = real_player_agi if real_player_agi >= 0.0 else player_agi
	var spd_val: float = real_player_spd if real_player_spd >= 0.0 else player_spd
	var ratio: float = enemy_spd / maxf(1.0, tp_val)
	var dodge_chance: float = 0.0
	if agi_val > 5.0:
		var spd_ratio: float = minf(1.0, spd_val / maxf(0.001, enemy_spd))
		dodge_chance = clampf(((agi_val - 5.0) / (agi_val + 80.0)) * spd_ratio, 0.0, 1.0)
	return {
		"imperceptible": ratio >= IMPERCEPTIBLE_SPEED_RATIO,
		"speed_ratio": ratio,
		"real_tp": tp_val,
		"real_agi": agi_val,
		"real_spd": spd_val,
		"instinct_dodge_chance": dodge_chance,
		"evaluated_in_peaceful": tempo_mode == TempoMode.PEACEFUL,
	}


# ---------------------------------------------------------------------------
# Instance Convenience Methods (using current SimulationClock state)
# ---------------------------------------------------------------------------

func get_effective_tp() -> float:
	_sync_from_bound_stats()
	_recalculate_cached_scales()
	return effective_tp


func get_world_time_scale() -> float:
	_sync_from_bound_stats()
	_recalculate_cached_scales()
	return world_time_scale


func get_tp_penalty_mult() -> float:
	_sync_from_bound_stats()
	_recalculate_cached_scales()
	return tp_penalty_mult


func get_world_delta(raw_delta: float) -> float:
	return maxf(0.0, raw_delta) * get_world_time_scale()


func get_enemy_action_delta(
	raw_delta: float,
	enemy_spd: float,
	is_patrolling: bool = false,
	actor_id: int = 0
) -> float:
	if is_in_hitstop(actor_id):
		return 0.0
	var cap_to_peaceful: bool = (tempo_mode == TempoMode.PEACEFUL) or is_patrolling
	var eff_spd: float = minf(maxf(0.0, enemy_spd), REFERENCE_STAT) if cap_to_peaceful else maxf(0.0, enemy_spd)
	return compute_enemy_action_delta(get_world_delta(raw_delta), eff_spd)


func get_player_action_delta(raw_delta: float, actor_id: int = 0) -> float:
	if is_in_hitstop(actor_id):
		return 0.0
	var w_delta: float = get_world_delta(raw_delta)
	if tempo_mode == TempoMode.PEACEFUL:
		var eff_spd: float = minf(maxf(0.0, player_spd), REFERENCE_STAT)
		return maxf(0.0, w_delta) * (eff_spd / REFERENCE_STAT) * tp_penalty_mult
	return compute_player_action_delta(w_delta, player_spd, player_tp, speed_regulator)


func _get_event_bus() -> Node:
	if is_inside_tree() and get_tree().root != null:
		return get_tree().root.get_node_or_null("EventBus")
	var main_loop: MainLoop = Engine.get_main_loop()
	if main_loop is SceneTree:
		var tree: SceneTree = main_loop as SceneTree
		if tree.root != null:
			return tree.root.get_node_or_null("EventBus")
	return null
