class_name BrainFactory
extends RefCounted
## Archetype Registry & Factory mapping EnemyAIProfile -> CombatBrain subclass.
## Supports built-in archetypes (&"duelist", &"berserker", &"guardian") and runtime registration
## of custom boss/enemy CombatBrain subclasses via register_brain().


## Disciplined duelist brain: balanced spacing, patient parry/feint cadence, stamina discipline.
class DuelistBrain extends CombatBrain:
	func _score_actions(ctx: Dictionary) -> Dictionary:
		var s: Dictionary = super._score_actions(ctx)
		if bool(ctx["target_open"]):
			s[ACTION_ATTACK_THRUST] = float(s[ACTION_ATTACK_THRUST]) + 0.14
		if float(ctx["sta_ratio"]) < 0.32 and not recovering_stamina:
			s[ACTION_RECOVER_STAMINA] = maxf(float(s[ACTION_RECOVER_STAMINA]), 0.55)
		return s


## Relentless berserker brain: forward pressure, aggressive Hardening & Clinch Throw/Sweep into walls.
class BerserkerBrain extends CombatBrain:
	func _score_actions(ctx: Dictionary) -> Dictionary:
		var s: Dictionary = super._score_actions(ctx)
		if float(s[ACTION_ATTACK_BLUNT]) > 0.0:
			s[ACTION_ATTACK_BLUNT] = float(s[ACTION_ATTACK_BLUNT]) + 0.16
		if float(s[ACTION_CLINCH_THROW]) > 0.0:
			s[ACTION_CLINCH_THROW] = float(s[ACTION_CLINCH_THROW]) + 0.18
		if float(s[ACTION_CLINCH_SWEEP]) > 0.0:
			s[ACTION_CLINCH_SWEEP] = float(s[ACTION_CLINCH_SWEEP]) + 0.12
		if memory.recent_hits_taken >= 2 and float(s[ACTION_DEFEND_HARDENING]) > 0.0:
			s[ACTION_DEFEND_HARDENING] = float(s[ACTION_DEFEND_HARDENING]) + 0.45
		return s


## Elite Guardian brain: high-speed flanking, mid-windup Sidestep, Feint->Thrust weak-point punishes,
## Aura Burst vs Block/Hardening, and aerial MANA_FLIGHT pursuit.
class GuardianBrain extends CombatBrain:
	func _score_actions(ctx: Dictionary) -> Dictionary:
		var s: Dictionary = super._score_actions(ctx)
		if bool(ctx["target_blocking"]) or bool(ctx["target_hardening"]):
			if float(s[ACTION_AURA_BURST]) > 0.0:
				s[ACTION_AURA_BURST] = float(s[ACTION_AURA_BURST]) + 0.25
			if float(s[ACTION_FEINT_CANCEL]) > 0.0:
				s[ACTION_FEINT_CANCEL] = float(s[ACTION_FEINT_CANCEL]) + 0.18
		if float(s[ACTION_DEFEND_SIDESTEP]) > 0.0:
			s[ACTION_DEFEND_SIDESTEP] = float(s[ACTION_DEFEND_SIDESTEP]) + 0.18
		if float(s[ACTION_ATTACK_THRUST]) > 0.0 and (float(ctx["target_armor_barrier"]) >= 12.0 or bool(ctx["target_open"])):
			s[ACTION_ATTACK_THRUST] = float(s[ACTION_ATTACK_THRUST]) + 0.18
		return s


static var _custom_builders: Dictionary[StringName, Callable] = {}


static func register_brain(brain_id: StringName, builder: Callable) -> void:
	if brain_id == &"" or not builder.is_valid():
		return
	_custom_builders[brain_id] = builder


static func unregister_brain(brain_id: StringName) -> void:
	_custom_builders.erase(brain_id)


static func clear_custom_brains() -> void:
	_custom_builders.clear()


static func create_brain(profile: EnemyAIProfile) -> CombatBrain:
	var resolved_profile: EnemyAIProfile = profile if profile != null else EnemyAIProfile.create_duelist_profile()
	if resolved_profile.custom_brain_id != &"" and _custom_builders.has(resolved_profile.custom_brain_id):
		var custom_res: Variant = _custom_builders[resolved_profile.custom_brain_id].call(resolved_profile)
		if custom_res is CombatBrain:
			return custom_res as CombatBrain
	if _custom_builders.has(resolved_profile.archetype_id):
		var arch_res: Variant = _custom_builders[resolved_profile.archetype_id].call(resolved_profile)
		if arch_res is CombatBrain:
			return arch_res as CombatBrain

	match resolved_profile.archetype_id:
		&"berserker":
			return BerserkerBrain.new(resolved_profile)
		&"guardian":
			return GuardianBrain.new(resolved_profile)
		&"duelist":
			return DuelistBrain.new(resolved_profile)
		_:
			return CombatBrain.new(resolved_profile)
