class_name CombatMemory
extends RefCounted
## Short-term tactical duel memory (~9s rolling window) & honest TP/INT reaction pipeline.
## Tracks opponent habits (block ratio, parry baits, dead-zone rushes, feints) and models
## perception delay so low-TP/INT enemies cannot 1-frame react to fast strikes or feints.

const MEMORY_WINDOW_SEC: float = 9.0

# Rolling habit estimates (decay toward 0 over MEMORY_WINDOW_SEC)
var target_block_ratio: float = 0.0
var target_parry_baits: float = 0.0
var target_close_rush_count: float = 0.0
var target_feint_count: float = 0.0
var recent_damage_taken: float = 0.0
var recent_hits_taken: int = 0
var _hits_decay_timer: float = 0.0
var last_player_attack_type: PenetrationResolver.AttackType = PenetrationResolver.AttackType.SLASH
var current_stamina_pressure: float = 0.0

# Honest TP/INT reaction state
var reaction_timer: float = 0.0
var last_computed_reaction_delay: float = 0.28
var pending_threat: Dictionary = {}
var last_seen_target_state: int = CombatActor.CombatState.IDLE
var last_seen_target_blocking: bool = false
var last_feint_reaction: StringName = &""
var feint_bait_pending: bool = false
var counter_punish_timer: float = 0.0
var _close_rush_cooldown: float = 0.0


func reset() -> void:
	target_block_ratio = 0.0
	target_parry_baits = 0.0
	target_close_rush_count = 0.0
	target_feint_count = 0.0
	recent_damage_taken = 0.0
	recent_hits_taken = 0
	_hits_decay_timer = 0.0
	last_player_attack_type = PenetrationResolver.AttackType.SLASH
	current_stamina_pressure = 0.0
	reaction_timer = 0.0
	last_computed_reaction_delay = 0.28
	pending_threat = {}
	last_seen_target_state = CombatActor.CombatState.IDLE
	last_seen_target_blocking = false
	last_feint_reaction = &""
	feint_bait_pending = false
	counter_punish_timer = 0.0
	_close_rush_cooldown = 0.0


## Honest perception delay driven by enemy TP & INT:
## - TP=10, INT=10 -> ~0.28s (vulnerable to fast daggers & feints)
## - TP=100, INT=100 -> ~0.034s (superhuman reflexes & intent reading)
static func compute_reaction_delay(enemy_tp: float, enemy_int: float) -> float:
	var tp_term: float = pow(maxf(5.0, enemy_tp) / 10.0, 0.55)
	var int_term: float = 1.0 + maxf(0.0, enemy_int - 10.0) * 0.015
	return clampf(0.28 / tp_term / int_term, 0.03, 0.35)


## Returns true if observer has sufficient INT & TP relative to attacker SPD to read through feints.
static func can_recognize_feint(enemy_tp: float, enemy_int: float, target_spd: float) -> bool:
	var tp_ratio: float = enemy_tp / maxf(1.0, target_spd)
	return (enemy_int >= 35.0 and tp_ratio >= 0.65) or (enemy_int >= 70.0 and tp_ratio >= 0.40)


func record_damage_taken(severity: float = 1.0) -> void:
	recent_damage_taken = clampf(recent_damage_taken + maxf(0.5, severity), 0.0, 20.0)
	recent_hits_taken += 1
	_hits_decay_timer = 5.5


func record_target_defended(was_parry: bool) -> void:
	target_parry_baits = clampf(target_parry_baits + (1.6 if was_parry else 0.9), 0.0, 8.0)


func record_target_feint(enemy_tp: float, enemy_int: float, target_spd: float) -> StringName:
	target_feint_count = clampf(target_feint_count + 1.0, 0.0, 8.0)
	if can_recognize_feint(enemy_tp, enemy_int, target_spd):
		last_feint_reaction = &"recognized"
		feint_bait_pending = false
		counter_punish_timer = maxf(counter_punish_timer, 0.65)
		clear_threat()
		return &"recognized"
	last_feint_reaction = &"baited"
	feint_bait_pending = true
	clear_threat()
	return &"baited"


func clear_threat() -> void:
	pending_threat = {}
	reaction_timer = 0.0


func has_ready_threat() -> bool:
	return not pending_threat.is_empty() and bool(pending_threat.get("active", false)) and reaction_timer <= 0.0 and not bool(pending_threat.get("reacted", false))


func has_active_threat() -> bool:
	return not pending_threat.is_empty() and bool(pending_threat.get("active", false))


func mark_threat_reacted() -> void:
	if not pending_threat.is_empty():
		pending_threat["reacted"] = true


## Advances decay timers & observes target state transitions using honest TP/INT reaction delay.
func observe(
	actor: CombatActor,
	target: CombatActor,
	action_dt: float,
	world_dt: float
) -> void:
	var dt: float = maxf(0.0, action_dt)
	var decay_dt: float = maxf(dt, maxf(0.0, world_dt))
	if decay_dt > 0.0:
		var decay_factor: float = exp(-decay_dt / MEMORY_WINDOW_SEC)
		target_parry_baits *= decay_factor
		target_close_rush_count *= decay_factor
		target_feint_count *= decay_factor
		recent_damage_taken *= decay_factor
		if _hits_decay_timer > 0.0:
			_hits_decay_timer = maxf(0.0, _hits_decay_timer - decay_dt)
			if _hits_decay_timer <= 0.0:
				recent_hits_taken = 0
		if counter_punish_timer > 0.0:
			counter_punish_timer = maxf(0.0, counter_punish_timer - dt)
		if _close_rush_cooldown > 0.0:
			_close_rush_cooldown = maxf(0.0, _close_rush_cooldown - dt)

	if actor == null or actor.stat_sheet == null:
		return

	var max_sta: float = maxf(1.0, actor.stat_sheet.get_max_stamina())
	var sta_ratio: float = clampf(actor.current_stamina / max_sta, 0.0, 1.0)
	current_stamina_pressure = clampf(1.0 - sta_ratio, 0.0, 1.0)

	if target == null or not is_instance_valid(target) or not target.is_alive():
		clear_threat()
		return

	var enemy_tp: float = actor.stat_sheet.get_stat(StatSheet.Stat.TP)
	var enemy_int: float = actor.stat_sheet.get_stat(StatSheet.Stat.INT)
	var target_spd: float = target.stat_sheet.get_stat(StatSheet.Stat.SPD) if target.stat_sheet != null else 10.0
	last_computed_reaction_delay = compute_reaction_delay(enemy_tp, enemy_int)

	# Rolling EMA of target block usage
	var block_sample: float = 1.0 if target.is_blocking else 0.0
	var ema_alpha: float = clampf(dt * 1.4, 0.0, 1.0)
	target_block_ratio = lerpf(target_block_ratio, block_sample, ema_alpha)
	last_seen_target_blocking = target.is_blocking

	# Track dead-zone / clinch rush pressure
	var my_wpn: WeaponData = actor.get_active_weapon()
	var dist: float = actor.global_position.distance_to(target.global_position)
	var surf_dist: float = maxf(0.0, dist - actor.get_body_collision_radius() - target.get_body_collision_radius())
	var dead_zone_limit: float = my_wpn.min_optimal_range if (my_wpn != null and my_wpn.min_optimal_range > 0.0) else CombatActor.CLINCH_MAX_SURFACE_GAP_PX
	if surf_dist <= dead_zone_limit and _close_rush_cooldown <= 0.0:
		target_close_rush_count = clampf(target_close_rush_count + 1.0, 0.0, 8.0)
		_close_rush_cooldown = 1.2

	# Detect opponent combat_state transitions (new WINDUP threat vs WINDUP->RECOVERY Feint cancel!)
	var cur_t_state: int = int(target.combat_state)
	if cur_t_state == CombatActor.CombatState.WINDUP:
		if last_seen_target_state != CombatActor.CombatState.WINDUP or not has_active_threat():
			var tgt_wpn: WeaponData = target.get_active_weapon()
			var tgt_str: float = target.stat_sheet.get_stat(StatSheet.Stat.STR) if target.stat_sheet != null else 10.0
			last_player_attack_type = target.current_attack_type
			pending_threat = {
				"active": true,
				"attack_type": target.current_attack_type,
				"time_to_contact": maxf(0.01, target.state_timer),
				"elapsed_seen": 0.0,
				"attacker_str": tgt_str,
				"weapon_mass": tgt_wpn.mass_factor if tgt_wpn != null else 8.0,
				"reacted": false,
			}
			reaction_timer = last_computed_reaction_delay
			feint_bait_pending = false
		else:
			pending_threat["elapsed_seen"] = float(pending_threat.get("elapsed_seen", 0.0)) + dt
			pending_threat["time_to_contact"] = maxf(0.0, target.state_timer)
			pending_threat["attack_type"] = target.current_attack_type
			reaction_timer = maxf(0.0, reaction_timer - dt)
	elif cur_t_state == CombatActor.CombatState.ACTIVE:
		if has_active_threat():
			pending_threat["time_to_contact"] = 0.0
			pending_threat["elapsed_seen"] = float(pending_threat.get("elapsed_seen", 0.0)) + dt
			reaction_timer = maxf(0.0, reaction_timer - dt)
		else:
			var tgt_wpn_a: WeaponData = target.get_active_weapon()
			var tgt_str_a: float = target.stat_sheet.get_stat(StatSheet.Stat.STR) if target.stat_sheet != null else 10.0
			last_player_attack_type = target.current_attack_type
			pending_threat = {
				"active": true,
				"attack_type": target.current_attack_type,
				"time_to_contact": 0.0,
				"elapsed_seen": 0.0,
				"attacker_str": tgt_str_a,
				"weapon_mass": tgt_wpn_a.mass_factor if tgt_wpn_a != null else 8.0,
				"reacted": false,
			}
			reaction_timer = last_computed_reaction_delay
	else:
		# Target transitioned WINDUP -> RECOVERY (skipped ACTIVE) => genuine Feint!
		if last_seen_target_state == CombatActor.CombatState.WINDUP and cur_t_state == CombatActor.CombatState.RECOVERY:
			record_target_feint(enemy_tp, enemy_int, target_spd)
		elif has_active_threat():
			clear_threat()

	last_seen_target_state = cur_t_state
