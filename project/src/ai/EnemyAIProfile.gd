class_name EnemyAIProfile
extends Resource
## Data-driven Combat AI Archetype Profile (Utility AI + Stat-Driven + Per-Enemy Extensible).
## Tuning parameters control personality/preferences while real capabilities (reaction time,
## stamina discounts, feint reading, weak-point aim, flight) scale directly from StatSheet & Anatomy.

@export var archetype_id: StringName = &"duelist"
## Optional override id registered in BrainFactory for unique enemy / boss subclasses.
@export var custom_brain_id: StringName = &""

@export_range(0.0, 1.0) var aggression: float = 0.55
@export_range(0.0, 1.0) var caution: float = 0.45
@export_range(0.0, 1.0) var flank_tendency: float = 0.50

@export_range(0.0, 1.0) var feint_affinity: float = 0.35
@export_range(0.0, 1.0) var dodge_affinity: float = 0.40
@export_range(0.0, 1.0) var parry_affinity: float = 0.45
@export_range(0.0, 1.0) var hardening_affinity: float = 0.20
@export_range(0.0, 1.0) var clinch_affinity: float = 0.30
@export_range(0.0, 1.0) var aura_burst_affinity: float = 0.30

@export_range(0.0, 1.0) var weak_point_focus: float = 0.35
@export_range(0.35, 1.15) var preferred_range_ratio: float = 0.80
@export_range(0.0, 1.0) var adaptation_rate: float = 0.45

@export var can_use_mana_flight: bool = false
@export var can_use_wing_flight: bool = false
@export var flight_pursuit_enabled: bool = true
@export var retreats_when_crippled: bool = true
@export var allows_self_heal_spacing: bool = false


func create_runtime_copy() -> EnemyAIProfile:
	return self.duplicate(true) as EnemyAIProfile


static func create_duelist_profile() -> EnemyAIProfile:
	var p: EnemyAIProfile = EnemyAIProfile.new()
	p.archetype_id = &"duelist"
	p.aggression = 0.52
	p.caution = 0.55
	p.flank_tendency = 0.58
	p.feint_affinity = 0.38
	p.dodge_affinity = 0.48
	p.parry_affinity = 0.55
	p.hardening_affinity = 0.10
	p.clinch_affinity = 0.22
	p.aura_burst_affinity = 0.25
	p.weak_point_focus = 0.45
	p.preferred_range_ratio = 0.84
	p.adaptation_rate = 0.50
	p.can_use_mana_flight = false
	p.can_use_wing_flight = false
	p.flight_pursuit_enabled = false
	p.retreats_when_crippled = true
	p.allows_self_heal_spacing = false
	return p


static func create_berserker_profile() -> EnemyAIProfile:
	var p: EnemyAIProfile = EnemyAIProfile.new()
	p.archetype_id = &"berserker"
	p.aggression = 0.90
	p.caution = 0.14
	p.flank_tendency = 0.25
	p.feint_affinity = 0.12
	p.dodge_affinity = 0.18
	p.parry_affinity = 0.12
	p.hardening_affinity = 0.85
	p.clinch_affinity = 0.85
	p.aura_burst_affinity = 0.35
	p.weak_point_focus = 0.20
	p.preferred_range_ratio = 0.62
	p.adaptation_rate = 0.30
	p.can_use_mana_flight = false
	p.can_use_wing_flight = false
	p.flight_pursuit_enabled = false
	p.retreats_when_crippled = false
	p.allows_self_heal_spacing = true
	return p


static func create_guardian_profile() -> EnemyAIProfile:
	var p: EnemyAIProfile = EnemyAIProfile.new()
	p.archetype_id = &"guardian"
	p.aggression = 0.72
	p.caution = 0.48
	p.flank_tendency = 0.82
	p.feint_affinity = 0.72
	p.dodge_affinity = 0.78
	p.parry_affinity = 0.82
	p.hardening_affinity = 0.40
	p.clinch_affinity = 0.42
	p.aura_burst_affinity = 0.85
	p.weak_point_focus = 0.82
	p.preferred_range_ratio = 0.86
	p.adaptation_rate = 0.85
	p.can_use_mana_flight = true
	p.can_use_wing_flight = false
	p.flight_pursuit_enabled = true
	p.retreats_when_crippled = false
	p.allows_self_heal_spacing = true
	return p
