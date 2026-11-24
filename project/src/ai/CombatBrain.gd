class_name CombatBrain
extends RefCounted
## Base Extensible Utility AI Brain (Stat-Driven + Per-Enemy Subclassable).
## Separates perception/memory (CombatMemory), archetype tuning (EnemyAIProfile),
## action scoring (_score_actions), movement/flanking (_compute_movement_intent),
## attack planning (_select_attack_plan), and feint followups (_on_feint_resolved).
## Unique enemies and bosses can subclass CombatBrain and override only the needed hooks.

const ACTION_HOLD: StringName = &"hold"
const ACTION_ATTACK_SLASH: StringName = &"attack_slash"
const ACTION_ATTACK_THRUST: StringName = &"attack_thrust"
const ACTION_ATTACK_BLUNT: StringName = &"attack_blunt"
const ACTION_CLINCH_THROW: StringName = &"clinch_throw"
const ACTION_CLINCH_SWEEP: StringName = &"clinch_sweep"
const ACTION_CLINCH_SHOVE: StringName = &"clinch_shove"
const ACTION_DEFEND_PARRY: StringName = &"defend_parry"
const ACTION_DEFEND_BLOCK: StringName = &"defend_block"
const ACTION_DEFEND_SIDESTEP: StringName = &"defend_sidestep"
const ACTION_DEFEND_DASH: StringName = &"defend_dash"
const ACTION_DEFEND_HARDENING: StringName = &"defend_hardening"
const ACTION_FEINT_CANCEL: StringName = &"feint_cancel"
const ACTION_AURA_BURST: StringName = &"aura_burst"
const ACTION_RECOVER_STAMINA: StringName = &"recover_stamina"
const ACTION_REGEN_SPACING: StringName = &"regen_spacing"

const WALL_SCAN_DISTANCES: Array[float] = [44.0, 68.0, 96.0]
const ALLY_SEPARATION_RADIUS_PX: float = 42.0

var profile: EnemyAIProfile = null
var memory: CombatMemory = null

var decision_timer: float = 0.0
var last_scores: Dictionary = {}
var last_chosen_action: StringName = ACTION_HOLD
var last_attack_plan: Dictionary = {}
var queued_followup: Dictionary = {}

var recovering_stamina: bool = false
var regen_spacing_timer: float = 0.0
var _regen_spacing_cooldown: float = 0.0
var _strafe_dir: float = 1.0
var _strafe_switch_timer: float = 1.4
var _last_decision_target_state: int = CombatActor.CombatState.IDLE
var _last_decision_target_blocking: bool = false
var _last_decision_target_hardening: bool = false
var _clinch_env_cache: Dictionary = {}
var _attack_variety_counter: int = 0


func _init(p_profile: EnemyAIProfile = null) -> void:
	profile = p_profile if p_profile != null else EnemyAIProfile.create_duelist_profile()
	memory = CombatMemory.new()


func reset() -> void:
	if memory != null:
		memory.reset()
	decision_timer = 0.0
	last_scores.clear()
	last_chosen_action = ACTION_HOLD
	last_attack_plan.clear()
	queued_followup.clear()
	recovering_stamina = false
	regen_spacing_timer = 0.0
	_regen_spacing_cooldown = 0.0
	_strafe_switch_timer = 1.4
	_last_decision_target_state = CombatActor.CombatState.IDLE
	_last_decision_target_blocking = false
	_last_decision_target_hardening = false
	_clinch_env_cache.clear()


static func compute_decision_interval(enemy_tp: float) -> float:
	return clampf(0.18 / pow(maxf(5.0, enemy_tp) / 10.0, 0.45), 0.04, 0.22)


func on_hit_received(severity: float = 1.0) -> void:
	if memory != null:
		memory.record_damage_taken(severity)


func on_attack_defended_by_target(was_parry: bool) -> void:
	if memory != null:
		memory.record_target_defended(was_parry)


## Builds a normalized tactical snapshot for scoring, movement, and attack planning.
func build_context(
	actor: CombatActor,
	target: CombatActor,
	arena: TestArena,
	action_dt: float,
	world_dt: float
) -> Dictionary:
	var sheet: StatSheet = actor.stat_sheet
	var t_sheet: StatSheet = target.stat_sheet if target != null else null
	var wpn: WeaponData = actor.get_active_weapon()
	var t_wpn: WeaponData = target.get_active_weapon() if target != null else null

	var my_str: float = sheet.get_stat(StatSheet.Stat.STR) if sheet != null else 10.0
	var my_ctrl: float = sheet.get_stat(StatSheet.Stat.CTRL) if sheet != null else 10.0
	var my_spd: float = sheet.get_stat(StatSheet.Stat.SPD) if sheet != null else 10.0
	var my_agi: float = sheet.get_stat(StatSheet.Stat.AGI) if sheet != null else 10.0
	var my_con: float = sheet.get_stat(StatSheet.Stat.CON) if sheet != null else 10.0
	var my_tp: float = sheet.get_stat(StatSheet.Stat.TP) if sheet != null else 10.0
	var my_int: float = sheet.get_stat(StatSheet.Stat.INT) if sheet != null else 10.0
	var my_m_ctrl: float = sheet.get_stat(StatSheet.Stat.M_CTRL) if (sheet != null and sheet.mana_awakened) else 0.0
	var my_reg: float = sheet.get_stat(StatSheet.Stat.REG) if sheet != null else 10.0

	var max_sta: float = maxf(1.0, sheet.get_max_stamina()) if sheet != null else 150.0
	var max_mp: float = sheet.get_max_mp() if sheet != null else 0.0
	var sta_ratio: float = clampf(actor.current_stamina / max_sta, 0.0, 1.0)
	var mp_ratio: float = clampf(actor.current_mp / maxf(1.0, max_mp), 0.0, 1.0) if max_mp > 0.0 else 0.0
	var blood_ratio: float = actor.anatomy.get_blood_ratio() if actor.anatomy != null else 1.0

	var attack_range: float = (wpn.hilt_offset_px + wpn.get_effective_blade_length(actor.half_swording)) if wpn != null else 28.0
	var v_reach: float = wpn.vertical_reach if wpn != null else 0.6
	var min_opt_range: float = wpn.min_optimal_range if (wpn != null and not actor.half_swording) else 0.0

	var to_target: Vector2 = (target.global_position - actor.global_position) if target != null else Vector2.RIGHT
	var dist: float = to_target.length()
	var surf_dist: float = maxf(0.0, dist - actor.get_body_collision_radius() - (target.get_body_collision_radius() if target != null else 8.0))
	var height_diff: float = absf(actor.get_height_z() - target.get_height_z()) if target != null else 0.0
	var in_clinch: bool = target != null and actor.is_within_clinch_range(target)

	var t_str: float = t_sheet.get_stat(StatSheet.Stat.STR) if t_sheet != null else 10.0
	var t_spd: float = t_sheet.get_stat(StatSheet.Stat.SPD) if t_sheet != null else 10.0
	var t_armor_barrier: float = _estimate_target_armor_barrier(target)
	var t_hardening: bool = target != null and target.is_hardening_active()
	var t_blocking: bool = target != null and target.is_blocking
	var t_parry: bool = target != null and target.is_in_parry_window()
	var t_open: bool = target != null and (
		target.combat_state == CombatActor.CombatState.RECOVERY
		or target.combat_state == CombatActor.CombatState.STAGGERED
		or target.is_prone()
		or (target.anatomy != null and target.anatomy.is_unconscious)
		or actor.counter_window_timer > 0.0
		or memory.counter_punish_timer > 0.0
	)

	var has_arm_impairment: bool = false
	var has_severed_limb: bool = false
	var has_arterial_bleed: bool = false
	if actor.anatomy != null:
		for az: StringName in AnatomyComponent.ARM_ZONES:
			var apart: AnatomyComponent.BodyPart = actor.anatomy.get_body_part(az)
			if apart != null and (apart.limb_status != AnatomyComponent.LimbStatus.INTACT or apart.has_tendon_tear):
				has_arm_impairment = true
		for z: StringName in actor.anatomy.get_zone_names():
			if actor.anatomy.is_limb_severed(z):
				has_severed_limb = true
			if actor.anatomy.has_arterial_bleeding(z):
				has_arterial_bleed = true

	var clinch_env: Dictionary = _scan_clinch_environment(actor, target, arena) if (in_clinch or dist <= 56.0) else {
		"wall_slam_available": false,
		"wall_slam_dir": Vector2.ZERO,
		"wall_slam_dist": INF,
		"floor_drop_available": false,
		"floor_drop_dir": Vector2.ZERO,
	}
	_clinch_env_cache = clinch_env

	var can_fly_now: bool = (
		(profile.can_use_mana_flight and actor.can_use_mana_flight())
		or (profile.can_use_wing_flight and actor.can_use_wing_flight())
	)

	return {
		"actor": actor,
		"target": target,
		"arena": arena,
		"action_dt": action_dt,
		"world_dt": world_dt,
		"weapon": wpn,
		"target_weapon": t_wpn,
		"str": my_str,
		"ctrl": my_ctrl,
		"spd": my_spd,
		"agi": my_agi,
		"con": my_con,
		"tp": my_tp,
		"int": my_int,
		"m_ctrl": my_m_ctrl,
		"reg": my_reg,
		"mana_awakened": sheet != null and sheet.mana_awakened,
		"sta_ratio": sta_ratio,
		"mp_ratio": mp_ratio,
		"blood_ratio": blood_ratio,
		"attack_range": attack_range,
		"vertical_reach": v_reach,
		"min_optimal_range": min_opt_range,
		"to_target": to_target,
		"dist": dist,
		"surface_dist": surf_dist,
		"height_diff": height_diff,
		"in_vertical_reach": height_diff <= v_reach,
		"in_clinch_range": in_clinch,
		"target_str": t_str,
		"target_spd": t_spd,
		"target_armor_barrier": t_armor_barrier,
		"target_hardening": t_hardening,
		"target_blocking": t_blocking,
		"target_parry": t_parry,
		"target_open": t_open,
		"target_min_optimal_range": t_wpn.min_optimal_range if (t_wpn != null and target != null and not target.half_swording) else 0.0,
		"has_arm_impairment": has_arm_impairment,
		"has_severed_limb": has_severed_limb,
		"has_arterial_bleed": has_arterial_bleed,
		"can_fly": can_fly_now,
		"clinch_env": clinch_env,
		"threat_ready": memory.has_ready_threat(),
		"threat": memory.pending_threat,
	}


## Main entry point for active COMBAT state when actor is in WINDUP or ACTIVE.
## Handles Sidestep during own WINDUP, Smart Reactive Feint -> Followup, and conscious Aura Burst.
func tick_active_attack_tactics(
	actor: CombatActor,
	target: CombatActor,
	arena: TestArena,
	action_dt: float,
	world_dt: float
) -> void:
	if actor == null or target == null or not actor.is_alive() or not target.is_alive():
		return
	memory.observe(actor, target, action_dt, world_dt)
	var ctx: Dictionary = build_context(actor, target, arena, action_dt, world_dt)
	var scores: Dictionary = _score_actions(ctx)
	last_scores = scores

	# 1. Conscious Aura Burst during WINDUP/ACTIVE against blocking or hardened opponent
	if (
		(actor.combat_state == CombatActor.CombatState.WINDUP or actor.combat_state == CombatActor.CombatState.ACTIVE)
		and not actor.current_attack_aura_burst
		and float(scores.get(ACTION_AURA_BURST, 0.0)) >= 0.65
	):
		if actor.try_trigger_aura_burst():
			last_chosen_action = ACTION_AURA_BURST
			return

	# 2. Micro-Sidestep during own WINDUP when opponent counter-attacks!
	if actor.combat_state == CombatActor.CombatState.WINDUP:
		var sidestep_score: float = float(scores.get(ACTION_DEFEND_SIDESTEP, 0.0))
		if sidestep_score >= 0.72 and actor.sidestep_cooldown_timer <= 0.0 and actor.sidestep_timer <= 0.0:
			var to_t: Vector2 = ctx["to_target"] as Vector2
			var fwd: Vector2 = to_t.normalized() if to_t.length_squared() > 0.001 else Vector2.from_angle(actor.aim_angle)
			var perp: Vector2 = Vector2(-fwd.y, fwd.x) * _strafe_dir
			if actor.start_sidestep(perp):
				memory.mark_threat_reacted()
				last_chosen_action = ACTION_DEFEND_SIDESTEP
				return

		# 3. Smart Reactive Feint when target raises Block/Parry during our WINDUP -> instant queued_followup!
		var feint_score: float = float(scores.get(ACTION_FEINT_CANCEL, 0.0))
		if feint_score >= 0.72 and actor.state_timer > 0.04 and not actor.current_attack_aura_burst:
			if actor.try_feint_cancel():
				if actor.get("planned_feint_active") != null:
					actor.set("planned_feint_active", false)
				if actor.get("attack_cooldown_timer") != null:
					actor.set("attack_cooldown_timer", 0.0)
				queued_followup = _on_feint_resolved(actor, target, true)
				last_chosen_action = ACTION_FEINT_CANCEL
				return


## Main entry point for active COMBAT state when actor is IDLE (returns movement velocity).
func tick_combat(
	actor: CombatActor,
	target: CombatActor,
	arena: TestArena,
	action_dt: float,
	world_dt: float
) -> Vector2:
	if actor == null or target == null or not actor.is_alive() or not target.is_alive():
		return Vector2.ZERO

	memory.observe(actor, target, action_dt, world_dt)

	if decision_timer > 0.0:
		decision_timer = maxf(0.0, decision_timer - action_dt)
	if regen_spacing_timer > 0.0:
		regen_spacing_timer = maxf(0.0, regen_spacing_timer - maxf(action_dt, world_dt))
	if _regen_spacing_cooldown > 0.0:
		_regen_spacing_cooldown = maxf(0.0, _regen_spacing_cooldown - maxf(action_dt, world_dt))
	_strafe_switch_timer -= action_dt
	if _strafe_switch_timer <= 0.0:
		_strafe_dir = -_strafe_dir
		_strafe_switch_timer = 1.1 + (1.0 - profile.flank_tendency) * 1.4

	var ctx: Dictionary = build_context(actor, target, arena, action_dt, world_dt)
	_update_resource_and_stance_modes(ctx)

	# 1. Execute queued post-feint instant followup immediately once IDLE!
	if not queued_followup.is_empty() and actor.combat_state == CombatActor.CombatState.IDLE:
		var q: Dictionary = queued_followup.duplicate()
		queued_followup.clear()
		if _execute_queued_followup(ctx, q):
			return Vector2.ZERO

	# 2. Low-INT enemy baited by player's feint wastes reactive block/parry window!
	if memory.feint_bait_pending and not actor.has_both_arms_severed():
		memory.feint_bait_pending = false
		if float(ctx["dist"]) <= float(ctx["attack_range"]) + 36.0:
			actor.trigger_block_pressed()
			if actor.has_method("_set_ai_block_hold"):
				actor.call("_set_ai_block_hold", 0.28, 1.35)
			last_chosen_action = ACTION_DEFEND_BLOCK
			return Vector2.ZERO

	# 3. Re-evaluate Utility AI when decision_timer expires OR target tactical state changes
	var target_state_changed: bool = (
		int(target.combat_state) != _last_decision_target_state
		or target.is_blocking != _last_decision_target_blocking
		or target.is_hardening_active() != _last_decision_target_hardening
	)
	var urgent_trigger: bool = (
		bool(ctx["threat_ready"])
		or target_state_changed
		or decision_timer <= 0.0
		or memory.recent_hits_taken >= 2
		or bool(ctx["target_open"])
	)
	if urgent_trigger:
		_last_decision_target_state = int(target.combat_state)
		_last_decision_target_blocking = target.is_blocking
		_last_decision_target_hardening = target.is_hardening_active()
		decision_timer = compute_decision_interval(float(ctx["tp"]))

		var scores: Dictionary = _score_actions(ctx)
		last_scores = scores
		var best_action: StringName = _pick_best_action(scores)
		last_chosen_action = best_action
		if _execute_chosen_action(ctx, best_action):
			return Vector2.ZERO

	# 4. Tactical Movement (Distance Ring + Flank Strafe + 1vN Surround + AStar Nav)
	return _compute_movement_intent(ctx)


# ---------------------------------------------------------------------------
# Virtual Hook 1: Utility Scoring (Override in subclasses for custom enemies)
# ---------------------------------------------------------------------------

func _score_actions(ctx: Dictionary) -> Dictionary:
	var scores: Dictionary = {
		ACTION_HOLD: 0.15,
		ACTION_ATTACK_SLASH: 0.0,
		ACTION_ATTACK_THRUST: 0.0,
		ACTION_ATTACK_BLUNT: 0.0,
		ACTION_CLINCH_THROW: 0.0,
		ACTION_CLINCH_SWEEP: 0.0,
		ACTION_CLINCH_SHOVE: 0.0,
		ACTION_DEFEND_PARRY: 0.0,
		ACTION_DEFEND_BLOCK: 0.0,
		ACTION_DEFEND_SIDESTEP: 0.0,
		ACTION_DEFEND_DASH: 0.0,
		ACTION_DEFEND_HARDENING: 0.0,
		ACTION_FEINT_CANCEL: 0.0,
		ACTION_AURA_BURST: 0.0,
		ACTION_RECOVER_STAMINA: 0.0,
		ACTION_REGEN_SPACING: 0.0,
	}

	var actor: CombatActor = ctx["actor"] as CombatActor
	var target: CombatActor = ctx["target"] as CombatActor
	var wpn: WeaponData = ctx["weapon"] as WeaponData
	if actor == null or target == null:
		return scores

	var dist: float = float(ctx["dist"])
	var attack_range: float = float(ctx["attack_range"])
	var in_v_reach: bool = bool(ctx["in_vertical_reach"])
	var my_str: float = float(ctx["str"])
	var my_ctrl: float = float(ctx["ctrl"])
	var my_agi: float = float(ctx["agi"])
	var my_con: float = float(ctx["con"])
	var my_tp: float = float(ctx["tp"])
	var my_int: float = float(ctx["int"])
	var my_m_ctrl: float = float(ctx["m_ctrl"])
	var sta_ratio: float = float(ctx["sta_ratio"])
	var mp_ratio: float = float(ctx["mp_ratio"])
	var t_str: float = float(ctx["target_str"])
	var t_armor: float = float(ctx["target_armor_barrier"])
	var t_blocking: bool = bool(ctx["target_blocking"])
	var t_parry: bool = bool(ctx["target_parry"])
	var t_hardening: bool = bool(ctx["target_hardening"])
	var t_open: bool = bool(ctx["target_open"])
	var int_factor: float = clampf((my_int - 5.0) / 55.0, 0.0, 1.5)
	var ctrl_factor: float = clampf((my_ctrl - 5.0) / 55.0, 0.0, 1.5)
	var agi_factor: float = clampf((my_agi - 5.0) / 55.0, 0.0, 1.5)
	var tp_factor: float = clampf((my_tp - 5.0) / 60.0, 0.0, 1.5)
	var adapt: float = profile.adaptation_rate

	var atk_cd: float = float(actor.get("attack_cooldown_timer")) if actor.get("attack_cooldown_timer") != null else 0.0
	var blk_cd: float = float(actor.get("_reactive_block_cooldown")) if actor.get("_reactive_block_cooldown") != null else 0.0
	var clinch_cd: float = float(actor.get("_clinch_ai_cooldown")) if actor.get("_clinch_ai_cooldown") != null else 0.0

	# --- A. Stamina Recovery & REG>=150 Self-Heal Spacing ---
	if recovering_stamina:
		scores[ACTION_RECOVER_STAMINA] = 0.88 + profile.caution * 0.25
	if regen_spacing_timer > 0.0:
		scores[ACTION_REGEN_SPACING] = 0.92

	# --- B. Mid-Windup / Active Options (Aura Burst, Sidestep, Smart Feint) ---
	if actor.combat_state == CombatActor.CombatState.WINDUP or actor.combat_state == CombatActor.CombatState.ACTIVE:
		if (
			bool(ctx["mana_awakened"])
			and my_m_ctrl >= PenetrationResolver.AURA_MIN_M_CTRL
			and actor.current_mp >= PenetrationResolver.AURA_BURST_MP_COST * actor.stat_sheet.get_mp_cost_mult()
			and dist <= attack_range + 16.0
		):
			var burst_u: float = 0.20 + profile.aura_burst_affinity * 0.55 + mp_ratio * 0.20
			if t_blocking or t_hardening:
				burst_u += 0.45 + int_factor * 0.25
			if t_armor >= 20.0:
				burst_u += 0.25 * int_factor
			scores[ACTION_AURA_BURST] = burst_u

	if actor.combat_state == CombatActor.CombatState.WINDUP:
		# Micro-Sidestep during own WINDUP if enemy attacks back!
		if bool(ctx["threat_ready"]) and actor.sidestep_cooldown_timer <= 0.0 and dist <= attack_range + 38.0:
			var threat_dict: Dictionary = ctx["threat"] as Dictionary
			var threat_type: int = int(threat_dict.get("attack_type", PenetrationResolver.AttackType.SLASH))
			var heavy_bonus: float = 0.30 if (threat_type == PenetrationResolver.AttackType.BLUNT or float(threat_dict.get("attacker_str", 10.0)) > my_str * 1.2) else 0.12
			scores[ACTION_DEFEND_SIDESTEP] = 0.30 + profile.dodge_affinity * 0.48 + agi_factor * 0.35 + heavy_bonus

		# Smart reactive Feint if target raises block/parry during our WINDUP!
		if (t_blocking or t_parry) and not actor.current_attack_aura_burst and sta_ratio > 0.22:
			var feint_u: float = (
				0.22
				+ profile.feint_affinity * 0.52
				+ (int_factor * 0.22 + ctrl_factor * 0.20)
				+ memory.target_block_ratio * 0.28 * adapt
				+ minf(0.25, memory.target_parry_baits * 0.10 * adapt)
			)
			scores[ACTION_FEINT_CANCEL] = feint_u
		return scores

	# --- C. Reactive Defense against Ready Perceived Threat (Honest TP/INT reaction!) ---
	if bool(ctx["threat_ready"]) and dist <= attack_range + 42.0 and not actor.has_both_arms_severed():
		var thr: Dictionary = ctx["threat"] as Dictionary
		var thr_type: int = int(thr.get("attack_type", PenetrationResolver.AttackType.SLASH))
		var thr_str: float = float(thr.get("attacker_str", t_str))
		var thr_mass: float = float(thr.get("weapon_mass", 10.0))
		var is_heavy_threat: bool = (thr_type == PenetrationResolver.AttackType.BLUNT) or (thr_str > my_str * 1.25) or (thr_mass >= 28.0 and my_str < thr_str * 1.1)

		# Parry (best against SLASH/THRUST with high CTRL + TP)
		if blk_cd <= 0.0:
			var parry_u: float = 0.42 + profile.parry_affinity * 0.50 + ctrl_factor * 0.22 + tp_factor * 0.18
			if is_heavy_threat:
				parry_u -= 0.18
			if actor.is_unarmed():
				parry_u -= 0.22
			scores[ACTION_DEFEND_PARRY] = maxf(0.0, parry_u)

			# Passive Block (drops sharply against heavy BLUNT / high STR advantage / unarmed)
			var block_u: float = 0.34 + profile.caution * 0.32 + (0.15 if my_str >= thr_str else -0.20)
			if is_heavy_threat:
				block_u -= 0.40 + int_factor * 0.20
			if actor.is_unarmed():
				block_u -= 0.45
			scores[ACTION_DEFEND_BLOCK] = maxf(0.0, block_u)

		# Evade Dash (best against heavy BLUNT / overwhelming STR when AGI is solid)
		if actor.dash_cooldown_timer <= 0.0 and sta_ratio > 0.25:
			var dash_u: float = 0.25 + profile.dodge_affinity * 0.52 + agi_factor * 0.38
			if is_heavy_threat:
				dash_u += 0.42 + int_factor * 0.18
			if actor.is_unarmed():
				dash_u += 0.22
			scores[ACTION_DEFEND_DASH] = dash_u

		# Hardening (high CON / M_CTRL tanks & trolls to bounce or lodge enemy blade!)
		if actor.hardening_cooldown_timer <= 0.0 and not actor.is_hardening_active() and sta_ratio > 0.22:
			var con_factor: float = clampf((my_con - 10.0) / 50.0, 0.0, 1.4)
			var hard_u: float = 0.12 + profile.hardening_affinity * 0.65 + con_factor * 0.28 + clampf(my_m_ctrl / 80.0, 0.0, 0.30)
			if thr_type != PenetrationResolver.AttackType.BLUNT and dist <= attack_range + 16.0:
				hard_u += 0.22
			if memory.recent_hits_taken >= 2:
				hard_u += 0.48
			scores[ACTION_DEFEND_HARDENING] = hard_u

	# Proactive Hardening after taking a flurry of hits (>=2 hits, even between enemy swings!)
	if memory.recent_hits_taken >= 2 and actor.hardening_cooldown_timer <= 0.0 and not actor.is_hardening_active() and sta_ratio > 0.20:
		var flurry_hard: float = 0.40 + profile.hardening_affinity * 0.72 + clampf((my_con - 10.0) / 50.0, 0.0, 0.35)
		scores[ACTION_DEFEND_HARDENING] = maxf(float(scores[ACTION_DEFEND_HARDENING]), flurry_hard)

	# --- D. Clinch Actions (with Environment Wall Slam & Floor +1 Hole Scan!) ---
	if (
		bool(ctx["in_clinch_range"])
		and clinch_cd <= 0.0
		and atk_cd <= 0.0
		and not actor.has_both_arms_severed()
		and not bool(ctx["has_arm_impairment"])
		and not recovering_stamina
		and sta_ratio > 0.20
	):
		var c_env: Dictionary = ctx["clinch_env"] as Dictionary
		var wall_avail: bool = bool(c_env.get("wall_slam_available", false))
		var drop_avail: bool = bool(c_env.get("floor_drop_available", false))
		var str_adv: float = clampf((my_str - t_str) / maxf(10.0, t_str), -0.6, 1.2)

		var throw_u: float = 0.25 + profile.clinch_affinity * 0.52 + maxf(0.0, str_adv) * 0.35
		if wall_avail:
			throw_u += 0.70 + int_factor * 0.25
		if drop_avail:
			throw_u += 0.80 + int_factor * 0.25
		scores[ACTION_CLINCH_THROW] = throw_u

		var sweep_u: float = 0.22 + profile.clinch_affinity * 0.45 + ctrl_factor * 0.18 + maxf(0.0, str_adv) * 0.25
		if t_blocking:
			sweep_u += 0.38
		if target.is_prone():
			sweep_u = 0.0
		scores[ACTION_CLINCH_SWEEP] = sweep_u

		var shove_u: float = 0.18 + profile.clinch_affinity * 0.32
		if float(ctx["min_optimal_range"]) > 0.0:
			shove_u += 0.30 # Shove target back out of greatsword dead zone!
		scores[ACTION_CLINCH_SHOVE] = shove_u

	# --- E. Melee Attacks (SLASH / THRUST / BLUNT) ---
	if (
		dist <= attack_range * 1.02
		and in_v_reach
		and atk_cd <= 0.0
		and not actor.has_both_arms_severed()
		and not recovering_stamina
		and regen_spacing_timer <= 0.0
	):
		var open_bonus: float = 0.48 if t_open else 0.0
		var base_atk: float = 0.42 + profile.aggression * 0.42 + open_bonus
		var is_unarmed_now: bool = actor.is_unarmed()
		var armored_target: bool = t_armor >= 14.0 or t_hardening
		var heavy_weapon: bool = wpn != null and (wpn.mass_factor >= 24.0 or wpn.blunt_impulse_mult >= 1.25)

		if is_unarmed_now:
			scores[ACTION_ATTACK_BLUNT] = base_atk + 0.15
		else:
			# SLASH: strong vs unarmored flesh, penalized vs heavy plate/Hardening when enemy has INT!
			var slash_u: float = base_atk + 0.12
			if armored_target:
				slash_u -= (0.28 + 0.45 * int_factor)
			if t_blocking:
				slash_u -= 0.18 * int_factor
			if (_attack_variety_counter % 3) == 1:
				slash_u += 0.05
			scores[ACTION_ATTACK_SLASH] = maxf(0.05, slash_u)

			# THRUST: excels at weak-point precision vs armor, open windows, and high CTRL/INT!
			var thrust_u: float = base_atk + 0.05 + profile.weak_point_focus * 0.25 + ctrl_factor * 0.12
			if armored_target:
				thrust_u += 0.22 + 0.38 * int_factor
			if t_open:
				thrust_u += 0.16 * profile.weak_point_focus
			if actor.half_swording:
				thrust_u += 0.25
			if (_attack_variety_counter % 3) == 2:
				thrust_u += 0.06
			scores[ACTION_ATTACK_THRUST] = maxf(0.05, thrust_u)

			# BLUNT: excels with heavy weapons or high INT against armor / Hardening / Block!
			var blunt_u: float = base_atk - 0.06 + (0.32 if heavy_weapon else 0.0)
			if armored_target:
				blunt_u += 0.25 + 0.36 * int_factor
			if t_blocking:
				blunt_u += 0.22 + 0.18 * int_factor
			if t_hardening:
				blunt_u += 0.20 * int_factor
			scores[ACTION_ATTACK_BLUNT] = maxf(0.05, blunt_u)

	return scores


# ---------------------------------------------------------------------------
# Virtual Hook 2: Tactical Movement, Range Ring, Flank Strafe & 1vN Surround
# ---------------------------------------------------------------------------

func _compute_movement_intent(ctx: Dictionary) -> Vector2:
	var actor: CombatActor = ctx["actor"] as CombatActor
	var target: CombatActor = ctx["target"] as CombatActor
	var arena: TestArena = ctx["arena"] as TestArena
	var action_dt: float = float(ctx["action_dt"])
	if actor == null or target == null:
		return Vector2.ZERO

	# If direct ground path is obstructed (LOW_OBSTACLE fence / wall), follow AStarGrid2D cleanly!
	if actor.has_method("_has_clear_walk_path") and not bool(actor.call("_has_clear_walk_path", target.global_position)):
		if actor.has_method("_compute_nav_steering_dir"):
			var nav_dir: Vector2 = actor.call("_compute_nav_steering_dir", target.global_position, arena, action_dt) as Vector2
			return nav_dir * CombatActor.BASE_RUN_SPEED_PX * 0.88 * actor.get_flight_speed_mult()

	var to_target: Vector2 = ctx["to_target"] as Vector2
	var dist: float = float(ctx["dist"])
	var fwd: Vector2 = to_target.normalized() if dist > 0.01 else Vector2.from_angle(actor.aim_angle)
	var tang: Vector2 = Vector2(-fwd.y, fwd.x)

	var attack_range: float = float(ctx["attack_range"])
	var min_opt: float = float(ctx["min_optimal_range"])
	var target_min_opt: float = float(ctx["target_min_optimal_range"])
	var my_int: float = float(ctx["int"])
	var int_factor: float = clampf((my_int - 5.0) / 55.0, 0.0, 1.4)

	# 1. Unreachable flying target when we cannot fly -> reposition laterally/back instead of standing under shadow
	if not bool(ctx["in_vertical_reach"]) and not bool(ctx["can_fly"]) and target.get_height_z() >= VerticalityComponent.LOW_OBSTACLE_CLEARANCE_Z:
		var cover_dir: Vector2 = (-fwd * 0.70 + tang * _strafe_dir * 0.72).normalized()
		if dist > attack_range * 2.2:
			cover_dir = tang * _strafe_dir
		return cover_dir * CombatActor.BASE_RUN_SPEED_PX * 0.72 * actor.get_flight_speed_mult()

	# 2. Compute desired range ring [desired_min .. desired_max]
	var desired_dist: float = attack_range * clampf(profile.preferred_range_ratio, 0.40, 1.05)
	if min_opt > 0.0:
		# Long weapon without Half-swording keeps outside dead zone
		desired_dist = maxf(desired_dist, min_opt + actor.get_body_collision_radius() + target.get_body_collision_radius() + 6.0)
	elif target_min_opt > 0.0 and profile.aggression >= 0.45:
		# Short weapon presses INSIDE enemy greatsword dead zone!
		desired_dist = minf(desired_dist, maxf(18.0, target_min_opt * 0.85))

	var backing_off: bool = recovering_stamina or regen_spacing_timer > 0.0 or (
		profile.retreats_when_crippled
		and (float(ctx["blood_ratio"]) < 0.62 or bool(ctx["has_severed_limb"]))
	)
	if backing_off:
		desired_dist = maxf(desired_dist * 1.45, attack_range * 1.30)

	var radial: float = 0.0
	if dist > desired_dist + 8.0:
		radial = 1.0
	elif dist < desired_dist - 8.0:
		radial = -0.78 if backing_off else -0.55

	# 3. Tangential Strafe & Flank-around Target's 150 deg Block Cone!
	var strafe_weight: float = 0.0
	var flank_sign: float = _strafe_dir
	if bool(ctx["target_blocking"]) and dist <= attack_range * 1.65:
		# Pick the shortest tangential side to break outside target's front +/-75 deg block cone
		var target_fwd: Vector2 = Vector2.from_angle(target.aim_angle)
		var from_target: Vector2 = -fwd
		var cross_z: float = target_fwd.x * from_target.y - target_fwd.y * from_target.x
		flank_sign = 1.0 if cross_z >= 0.0 else -1.0
		strafe_weight = clampf(0.45 + profile.flank_tendency * 0.55 + int_factor * 0.25, 0.35, 1.25)
		if dist > attack_range * 0.85:
			radial = maxf(radial, 0.35)
	elif dist <= attack_range * 1.60:
		strafe_weight = profile.flank_tendency * 0.55

	# 4. 1vN Anti-Clumping & Angular Surround Slot across sibling enemies in COMBAT!
	var sep_vec: Vector2 = _compute_ally_separation_and_surround(actor, target)

	var combined: Vector2 = fwd * radial + tang * (flank_sign * strafe_weight) + sep_vec
	if combined.length_squared() <= 0.002:
		return Vector2.ZERO

	var speed_mult: float = 0.86 if radial > 0.2 else (0.68 if backing_off else 0.74)
	if bool(ctx["target_blocking"]) and strafe_weight >= 0.5:
		speed_mult = 0.82
	return combined.normalized() * CombatActor.BASE_RUN_SPEED_PX * speed_mult * actor.get_flight_speed_mult()


# ---------------------------------------------------------------------------
# Virtual Hook 3: Attack Plan (Type, Weak-Point Aim, Feint, Aura Burst)
# ---------------------------------------------------------------------------

func _select_attack_plan(ctx: Dictionary, chosen_action: StringName) -> Dictionary:
	var target: CombatActor = ctx["target"] as CombatActor
	var atk_type: PenetrationResolver.AttackType = PenetrationResolver.AttackType.SLASH
	if chosen_action == ACTION_ATTACK_THRUST:
		atk_type = PenetrationResolver.AttackType.THRUST
	elif chosen_action == ACTION_ATTACK_BLUNT:
		atk_type = PenetrationResolver.AttackType.BLUNT

	var aim_pos: Vector2 = target.get_combat_origin() if target != null else Vector2.ZERO
	var my_ctrl: float = float(ctx["ctrl"])
	var want_wp: bool = (
		target != null
		and (
			atk_type == PenetrationResolver.AttackType.THRUST
			or bool(ctx["target_open"])
			or float(ctx["target_armor_barrier"]) >= 14.0
		)
		and (profile.weak_point_focus >= 0.35 or my_ctrl >= 25.0)
	)
	var aimed_weak_point: bool = false
	if want_wp:
		var wp: Vector2 = _find_target_weak_point(target)
		if is_finite(wp.x):
			aim_pos = wp
			aimed_weak_point = true

	var t_blocking: bool = bool(ctx["target_blocking"])
	var t_hardening: bool = bool(ctx["target_hardening"])
	var want_burst: bool = (
		bool(ctx["mana_awakened"])
		and float(ctx["m_ctrl"]) >= PenetrationResolver.AURA_MIN_M_CTRL
		and float(ctx["mp_ratio"]) >= 0.20
		and profile.aura_burst_affinity >= 0.45
		and (t_blocking or t_hardening)
	)

	var planned_feint: bool = false
	if (
		not want_burst
		and not bool(ctx["target_open"])
		and profile.feint_affinity >= 0.30
		and float(ctx["sta_ratio"]) > 0.35
		and (t_blocking or memory.target_block_ratio > 0.35 or memory.target_parry_baits >= 1.0)
	):
		planned_feint = ((_attack_variety_counter % 2) == 0)

	return {
		"attack_type": atk_type,
		"aim_pos": aim_pos,
		"aimed_weak_point": aimed_weak_point,
		"planned_feint": planned_feint,
		"aura_burst_intent": want_burst,
	}


# ---------------------------------------------------------------------------
# Virtual Hook 4: Post-Feint Instant Followup Plan
# ---------------------------------------------------------------------------

func _on_feint_resolved(actor: CombatActor, target: CombatActor, _was_reactive: bool) -> Dictionary:
	if actor == null or target == null:
		return {}
	var aim_pos: Vector2 = _find_target_weak_point(target)
	if not is_finite(aim_pos.x):
		aim_pos = target.get_combat_origin()
	var followup_action: StringName = ACTION_ATTACK_THRUST
	if actor.is_within_clinch_range(target) and profile.clinch_affinity >= 0.45:
		followup_action = ACTION_CLINCH_SWEEP
	elif actor.is_unarmed():
		followup_action = ACTION_ATTACK_BLUNT
	return {
		"action": followup_action,
		"aim_pos": aim_pos,
		"use_aura_burst": profile.aura_burst_affinity >= 0.55 and target.is_blocking and actor.stat_sheet != null and actor.stat_sheet.mana_awakened,
	}


# ---------------------------------------------------------------------------
# Execution & Helper Methods
# ---------------------------------------------------------------------------

func _update_resource_and_stance_modes(ctx: Dictionary) -> void:
	var actor: CombatActor = ctx["actor"] as CombatActor
	var target: CombatActor = ctx["target"] as CombatActor
	var action_dt: float = float(ctx["action_dt"])
	var sta_ratio: float = float(ctx["sta_ratio"])
	var wpn: WeaponData = ctx["weapon"] as WeaponData
	var dist: float = float(ctx["dist"])
	var surf_dist: float = float(ctx["surface_dist"])

	# 1. Stamina recovery hysteresis (<25% enter, >=45% exit; fearless berserkers with caution < 0.20 ignore)
	if profile.caution >= 0.20:
		if not recovering_stamina and sta_ratio < 0.25:
			recovering_stamina = true
		elif recovering_stamina and sta_ratio >= 0.45:
			recovering_stamina = false
	else:
		recovering_stamina = false

	# 2. REG >= 150 brief self-heal spacing when severed/arterially bleeding and not cornered
	if (
		profile.allows_self_heal_spacing
		and float(ctx["reg"]) >= StatSheet.REG_LIMB_REGROW_THRESHOLD
		and (bool(ctx["has_severed_limb"]) or bool(ctx["has_arterial_bleed"]))
		and regen_spacing_timer <= 0.0
		and _regen_spacing_cooldown <= 0.0
		and not _is_cornered(actor, target, ctx["arena"] as TestArena)
	):
		regen_spacing_timer = 1.5
		_regen_spacing_cooldown = 6.0

	# 3. Sustained Aura for awakened high-M_CTRL / Guardian enemies
	if bool(ctx["mana_awakened"]) and float(ctx["m_ctrl"]) >= PenetrationResolver.AURA_MIN_M_CTRL:
		if not actor.aura_active and actor.current_mp > 25.0 and (profile.aura_burst_affinity >= 0.65 or float(ctx["m_ctrl"]) >= 30.0):
			actor.set_aura_active(true)

	# 4. Half-swording inside long weapon dead zone when 2 arms intact & CTRL >= 15
	if actor.equipped_weapon != null and actor.equipped_weapon.can_half_sword and actor.get_usable_arm_count() >= 2 and float(ctx["ctrl"]) >= 15.0:
		if surf_dist < actor.equipped_weapon.min_optimal_range * 1.15 and not actor.half_swording:
			actor.set_half_swording(true)
			ctx["attack_range"] = wpn.hilt_offset_px + wpn.get_effective_blade_length(true)
			ctx["min_optimal_range"] = 0.0
		elif surf_dist > actor.equipped_weapon.min_optimal_range * 1.65 and actor.half_swording:
			actor.set_half_swording(false)
			ctx["attack_range"] = wpn.hilt_offset_px + wpn.get_effective_blade_length(false)
			ctx["min_optimal_range"] = wpn.min_optimal_range

	# 5. Flight pursuit / tactical altitude match (MANA_FLIGHT or WING_FLIGHT)
	if actor.verticality != null and profile.flight_pursuit_enabled:
		var target_z: float = target.get_height_z()
		var v_reach: float = float(ctx["vertical_reach"])
		if target_z >= VerticalityComponent.LOW_OBSTACLE_CLEARANCE_Z:
			# Target is airborne -> take off & pursue in midair if capable!
			if profile.can_use_mana_flight and actor.can_use_mana_flight():
				if not actor.is_flying():
					actor.set_flight_mode(VerticalityComponent.FlightMode.MANA_FLIGHT, target_z)
				else:
					var next_up: float = move_toward(actor.get_height_z(), target_z, 3.2 * minf(action_dt, 0.25))
					actor.verticality.set_height_z(next_up)
			elif profile.can_use_wing_flight and actor.can_use_wing_flight():
				if not actor.is_flying():
					actor.set_flight_mode(VerticalityComponent.FlightMode.WING_FLIGHT, target_z)
				else:
					var next_w: float = move_toward(actor.get_height_z(), target_z, 3.0 * minf(action_dt, 0.25))
					actor.verticality.set_height_z(next_w)
			ctx["height_diff"] = absf(actor.get_height_z() - target_z)
			ctx["in_vertical_reach"] = float(ctx["height_diff"]) <= v_reach
		elif actor.get_height_z() > target_z + v_reach * 0.75 and dist <= 185.0:
			# Hovering enemy dives into melee reach of grounded target!
			var desired_z: float = clampf(target_z + 0.30, 0.0, maxf(1.5, target_z))
			var next_down: float = move_toward(actor.get_height_z(), desired_z, 3.2 * minf(action_dt, 0.25))
			actor.verticality.set_height_z(next_down)
			ctx["height_diff"] = absf(actor.get_height_z() - target_z)
			ctx["in_vertical_reach"] = float(ctx["height_diff"]) <= v_reach


func _pick_best_action(scores: Dictionary) -> StringName:
	var best_key: StringName = ACTION_HOLD
	var best_val: float = -INF
	for k_var: Variant in scores.keys():
		var k: StringName = k_var as StringName
		var v: float = float(scores[k])
		if v > best_val:
			best_val = v
			best_key = k
	return best_key


func _execute_chosen_action(ctx: Dictionary, action: StringName) -> bool:
	var actor: CombatActor = ctx["actor"] as CombatActor
	var target: CombatActor = ctx["target"] as CombatActor
	if actor == null or target == null:
		return false

	match action:
		ACTION_HOLD, ACTION_RECOVER_STAMINA, ACTION_REGEN_SPACING:
			return false

		ACTION_DEFEND_PARRY:
			actor.trigger_block_pressed()
			memory.mark_threat_reacted()
			if actor.has_method("_set_ai_block_hold"):
				actor.call("_set_ai_block_hold", 0.26, 1.05 if profile.parry_affinity >= 0.7 else 1.55)
			return true

		ACTION_DEFEND_BLOCK:
			actor.trigger_block_pressed()
			memory.mark_threat_reacted()
			if actor.has_method("_set_ai_block_hold"):
				actor.call("_set_ai_block_hold", 0.34, 1.40)
			return true

		ACTION_DEFEND_DASH:
			var to_t: Vector2 = ctx["to_target"] as Vector2
			var fwd: Vector2 = to_t.normalized() if to_t.length_squared() > 0.001 else Vector2.from_angle(actor.aim_angle)
			var evade_dir: Vector2 = (Vector2(-fwd.y, fwd.x) * _strafe_dir - fwd * 0.45).normalized()
			if actor.start_dash(evade_dir):
				memory.mark_threat_reacted()
				return false # Keep moving during dash!
			return false

		ACTION_DEFEND_HARDENING:
			if actor.activate_hardening():
				memory.mark_threat_reacted()
				memory.recent_hits_taken = 0
				if actor.get("_recent_hits_taken") != null:
					actor.set("_recent_hits_taken", 0)
				return true
			return false

		ACTION_CLINCH_THROW:
			var c_env: Dictionary = ctx["clinch_env"] as Dictionary
			var dir: Vector2 = (ctx["to_target"] as Vector2).normalized()
			if bool(c_env.get("floor_drop_available", false)):
				dir = c_env["floor_drop_dir"] as Vector2
			elif bool(c_env.get("wall_slam_available", false)):
				dir = c_env["wall_slam_dir"] as Vector2
			var res_t: Dictionary = actor.perform_clinch_throw(target, dir)
			if bool(res_t.get("success", false)):
				if actor.has_method("_on_ai_clinch_executed"):
					actor.call("_on_ai_clinch_executed", 2.2, 0.55)
				return true
			return false

		ACTION_CLINCH_SWEEP:
			var res_sw: Dictionary = actor.perform_clinch_sweep(target)
			if bool(res_sw.get("success", false)):
				if actor.has_method("_on_ai_clinch_executed"):
					actor.call("_on_ai_clinch_executed", 2.2, 0.35)
				return true
			return false

		ACTION_CLINCH_SHOVE:
			var s_dir: Vector2 = (ctx["to_target"] as Vector2).normalized()
			var res_sh: Dictionary = actor.perform_clinch_shove(target, s_dir)
			if bool(res_sh.get("success", false)):
				if actor.has_method("_on_ai_clinch_executed"):
					actor.call("_on_ai_clinch_executed", 1.8, 0.45)
				return true
			return false

		ACTION_ATTACK_SLASH, ACTION_ATTACK_THRUST, ACTION_ATTACK_BLUNT:
			_attack_variety_counter += 1
			var plan: Dictionary = _select_attack_plan(ctx, action)
			last_attack_plan = plan
			var atk_type: PenetrationResolver.AttackType = int(plan["attack_type"]) as PenetrationResolver.AttackType
			var aim_pt: Vector2 = plan["aim_pos"] as Vector2
			if actor.start_attack(aim_pt, atk_type):
				if actor.has_method("_on_ai_attack_started"):
					actor.call("_on_ai_attack_started", bool(plan.get("planned_feint", false)))
				if bool(plan.get("aura_burst_intent", false)):
					actor.try_trigger_aura_burst()
				return true
			return false

	return false


func _execute_queued_followup(ctx: Dictionary, q: Dictionary) -> bool:
	var actor: CombatActor = ctx["actor"] as CombatActor
	var target: CombatActor = ctx["target"] as CombatActor
	if actor == null or target == null or actor.has_both_arms_severed():
		return false
	var q_act: StringName = q.get("action", ACTION_ATTACK_THRUST) as StringName
	if q_act == ACTION_CLINCH_SWEEP and actor.is_within_clinch_range(target):
		var sw: Dictionary = actor.perform_clinch_sweep(target)
		if bool(sw.get("success", false)):
			if actor.has_method("_on_ai_clinch_executed"):
				actor.call("_on_ai_clinch_executed", 2.0, 0.35)
			return true
	var atk_type: PenetrationResolver.AttackType = PenetrationResolver.AttackType.THRUST
	if q_act == ACTION_ATTACK_BLUNT or actor.is_unarmed():
		atk_type = PenetrationResolver.AttackType.BLUNT
	elif q_act == ACTION_ATTACK_SLASH:
		atk_type = PenetrationResolver.AttackType.SLASH
	var aim_pt: Vector2 = q.get("aim_pos", target.get_combat_origin()) as Vector2
	if float(ctx["dist"]) <= float(ctx["attack_range"]) * 1.15 and bool(ctx["in_vertical_reach"]):
		if actor.start_attack(aim_pt, atk_type):
			if actor.has_method("_on_ai_attack_started"):
				actor.call("_on_ai_attack_started", false)
			if bool(q.get("use_aura_burst", false)):
				actor.try_trigger_aura_burst()
			last_chosen_action = q_act
			return true
	return false


func _estimate_target_armor_barrier(target: CombatActor) -> float:
	if target == null:
		return 0.0
	var best_barrier: float = 0.0
	for hz: HitboxZone in target.hitbox_zones:
		if is_instance_valid(hz) and (hz.zone_name == AnatomyComponent.ZONE_CHEST or hz.zone_name == AnatomyComponent.ZONE_HEAD):
			best_barrier = maxf(best_barrier, hz.armor_thickness * hz.armor_hardness)
	if target.is_hardening_active():
		best_barrier += target.hardening_bonus_value
	return best_barrier


func _find_target_weak_point(target: CombatActor) -> Vector2:
	if target == null:
		return Vector2(INF, INF)
	for preferred_zone: StringName in [AnatomyComponent.ZONE_HEAD, AnatomyComponent.ZONE_NECK, AnatomyComponent.ZONE_CHEST]:
		for hz: HitboxZone in target.hitbox_zones:
			if is_instance_valid(hz) and hz.zone_name == preferred_zone:
				var wps: Array[Vector2] = hz.get_world_weak_points()
				if not wps.is_empty():
					return wps[0]
	return Vector2(INF, INF)


## Scans 8 radial directions (40..100 px) around target for solid walls (Wall Slam) or Floor +1 holes.
func _scan_clinch_environment(actor: CombatActor, target: CombatActor, arena: TestArena) -> Dictionary:
	var result: Dictionary = {
		"wall_slam_available": false,
		"wall_slam_dir": Vector2.ZERO,
		"wall_slam_dist": INF,
		"floor_drop_available": false,
		"floor_drop_dir": Vector2.ZERO,
	}
	if actor == null or target == null or arena == null:
		return result
	var fl: int = target.get_floor_level()
	var base_dir: Vector2 = (target.global_position - actor.global_position).normalized()
	if base_dir.length_squared() <= 0.001:
		base_dir = Vector2.RIGHT

	# Sample 8 directions biased toward behind the target first
	var sample_angles: Array[float] = [0.0, 0.55, -0.55, 1.15, -1.15, 2.0, -2.0, PI]
	for rel_ang: float in sample_angles:
		var dir: Vector2 = base_dir.rotated(rel_ang)
		for check_d: float in WALL_SCAN_DISTANCES:
			var pt: Vector2 = target.global_position + dir * check_d
			var cell: Vector2i = arena.world_to_cell(pt)
			if arena.is_wall_solid_at(fl, cell):
				if check_d < float(result["wall_slam_dist"]):
					result["wall_slam_available"] = true
					result["wall_slam_dir"] = dir
					result["wall_slam_dist"] = check_d
				break
			if fl >= 1 and FloorLayerManager != null:
				var no_floor: bool = not FloorLayerManager.has_floor_at(fl, cell)
				var breakable_cell: bool = TestArena.BREAKABLE_FLOOR_RECT.has_point(cell)
				if (no_floor or breakable_cell) and not bool(result["floor_drop_available"]):
					result["floor_drop_available"] = true
					result["floor_drop_dir"] = dir
	return result


func _is_cornered(actor: CombatActor, target: CombatActor, arena: TestArena) -> bool:
	if actor == null or target == null or arena == null:
		return false
	var back_dir: Vector2 = (actor.global_position - target.global_position).normalized()
	if back_dir.length_squared() <= 0.001:
		return false
	var cell: Vector2i = arena.world_to_cell(actor.global_position + back_dir * 34.0)
	return arena.is_wall_solid_at(actor.get_floor_level(), cell)


## Computes anti-clumping repulsion + angular surround slot vector for 1vN group combat.
func _compute_ally_separation_and_surround(actor: CombatActor, target: CombatActor) -> Vector2:
	if actor == null or target == null or not actor.is_inside_tree():
		return Vector2.ZERO
	var sep: Vector2 = Vector2.ZERO
	var fl: int = actor.get_floor_level()
	var allies: Array[CombatActor] = []
	for n: Node in actor.get_tree().get_nodes_in_group(&"enemies"):
		if n == actor or not (n is CombatActor):
			continue
		var other: CombatActor = n as CombatActor
		if not other.is_alive() or other.get_floor_level() != fl:
			continue
		if other.get("current_target") != target:
			continue
		allies.append(other)
		var away: Vector2 = actor.global_position - other.global_position
		var d: float = away.length()
		if d > 0.1 and d < ALLY_SEPARATION_RADIUS_PX:
			var push_strength: float = (ALLY_SEPARATION_RADIUS_PX - d) / ALLY_SEPARATION_RADIUS_PX
			sep += away.normalized() * push_strength * 0.95
	if allies.is_empty():
		return sep
	# Light surround slot bias so allies fan around the target instead of queuing in a single line
	var my_angle: float = (actor.global_position - target.global_position).angle()
	var nearest_ang_diff: float = INF
	var repel_sign: float = 0.0
	for other: CombatActor in allies:
		var other_angle: float = (other.global_position - target.global_position).angle()
		var diff: float = angle_difference(other_angle, my_angle)
		if absf(diff) < absf(nearest_ang_diff):
			nearest_ang_diff = diff
			repel_sign = 1.0 if diff >= 0.0 else -1.0
	if absf(nearest_ang_diff) < deg_to_rad(55.0):
		var from_t: Vector2 = (actor.global_position - target.global_position).normalized()
		var tang: Vector2 = Vector2(-from_t.y, from_t.x)
		sep += tang * (repel_sign * 0.45)
	return sep
