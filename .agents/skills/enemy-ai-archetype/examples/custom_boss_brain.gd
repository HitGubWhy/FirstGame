class_name ExecutionerBossBrain
extends CombatBrain
## Reference template for a custom boss / unique enemy CombatBrain subclass.
## Register via BrainFactory.register_brain(&"executioner_boss", ...) before spawning or calling set_ai_profile().


static func create_profile() -> EnemyAIProfile:
	var p: EnemyAIProfile = EnemyAIProfile.new()
	p.archetype_id = &"duelist"
	p.custom_brain_id = &"executioner_boss"
	p.aggression = 0.80
	p.caution = 0.35
	p.flank_tendency = 0.65
	p.feint_affinity = 0.68
	p.dodge_affinity = 0.60
	p.parry_affinity = 0.70
	p.hardening_affinity = 0.55
	p.clinch_affinity = 0.50
	p.aura_burst_affinity = 0.75
	p.weak_point_focus = 0.78
	p.preferred_range_ratio = 0.85
	p.adaptation_rate = 0.80
	p.can_use_mana_flight = false
	p.can_use_wing_flight = false
	p.flight_pursuit_enabled = false
	p.retreats_when_crippled = false
	p.allows_self_heal_spacing = false
	return p


static func register() -> void:
	BrainFactory.register_brain(&"executioner_boss", func(p: EnemyAIProfile) -> CombatBrain:
		return ExecutionerBossBrain.new(p)
	)


## Hook 1: Utility scoring adjustments on top of base CombatBrain.
func _score_actions(ctx: Dictionary) -> Dictionary:
	var scores: Dictionary = super._score_actions(ctx)

	# Punish blocking/turtling targets with Feint or Aura Burst (honestly gated by base readiness)
	if bool(ctx["target_blocking"]) and memory.target_block_ratio >= 0.45:
		if float(scores.get(ACTION_AURA_BURST, 0.0)) > 0.0:
			scores[ACTION_AURA_BURST] = float(scores[ACTION_AURA_BURST]) + 0.22
		elif float(scores.get(ACTION_FEINT_CANCEL, 0.0)) > 0.0:
			scores[ACTION_FEINT_CANCEL] = float(scores[ACTION_FEINT_CANCEL]) + 0.20

	# Exploit open/staggered targets with precise THRUST or SLASH dismemberment
	if bool(ctx["target_open"]):
		if float(ctx["target_armor_barrier"]) >= 12.0:
			scores[ACTION_ATTACK_THRUST] = float(scores.get(ACTION_ATTACK_THRUST, 0.0)) + 0.25
		else:
			scores[ACTION_ATTACK_SLASH] = float(scores.get(ACTION_ATTACK_SLASH, 0.0)) + 0.22

	return scores


## Hook 2: Custom attack planning (prefer weak point on open targets).
func _select_attack_plan(ctx: Dictionary, chosen_action: StringName) -> Dictionary:
	var plan: Dictionary = super._select_attack_plan(ctx, chosen_action)
	var target: CombatActor = ctx["target"] as CombatActor
	if target != null and bool(ctx["target_open"]):
		var wp: Vector2 = _find_target_weak_point(target)
		if is_finite(wp.x):
			plan["aim_pos"] = wp
			plan["aimed_weak_point"] = true
	return plan


## Hook 3: Post-feint instant followup.
func _on_feint_resolved(actor: CombatActor, target: CombatActor, was_reactive: bool) -> Dictionary:
	var followup: Dictionary = super._on_feint_resolved(actor, target, was_reactive)
	if not followup.is_empty() and target != null and not actor.is_unarmed():
		followup["action"] = ACTION_ATTACK_THRUST
	return followup


# ---------------------------------------------------------------------------
# Usage snippet in a headless test (remember BrainFactory.unregister_brain in teardown!):
#
#   ExecutionerBossBrain.register()
#   var profile: EnemyAIProfile = ExecutionerBossBrain.create_profile()
#   var brain: CombatBrain = enemy.set_ai_profile(profile.create_runtime_copy())
#   _assert_true(brain is ExecutionerBossBrain, "Boss brain registered via BrainFactory")
#   ...
#   BrainFactory.unregister_brain(&"executioner_boss")
# ---------------------------------------------------------------------------
