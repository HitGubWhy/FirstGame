class_name StatSheet
extends RefCounted
## 4-layer stat pipeline for all 12 stats (scale 1..500, reference 10 = human).
## Implements GDD Sections 2.1, 2.2, 3.1, 3.2, 5.2, 12.3, and 14.4 (v0.2).

signal stat_changed(stat: int, old_value: float, new_value: float)
signal mana_awakened_changed(is_awakened: bool)
signal race_preset_changed(preset: int)

enum RacePreset {
	HUMAN = 0,
	TROLL = 1,
}

enum Stat {
	STR = 0,
	CTRL = 1,
	SPD = 2,
	AGI = 3,
	CON = 4,
	STA = 5,
	TP = 6,
	INT = 7,
	MP_CAP = 8,
	M_CTRL = 9,
	SOUL = 10,
	REG = 11,
}

const ALL_STATS: Array[int] = [
	Stat.STR,
	Stat.CTRL,
	Stat.SPD,
	Stat.AGI,
	Stat.CON,
	Stat.STA,
	Stat.TP,
	Stat.INT,
	Stat.MP_CAP,
	Stat.M_CTRL,
	Stat.SOUL,
	Stat.REG,
]

const CIRCULATION_STATS: Array[int] = [
	Stat.STR,
	Stat.CTRL,
	Stat.SPD,
	Stat.TP,
	Stat.CON,
]

const STAT_MIN: float = 1.0
const STAT_MAX: float = 500.0
const STAT_STANDARD_MAX: float = 400.0
const HUMAN_REFERENCE: float = 10.0
const DEFAULT_HUMAN_RACIAL_CAP: float = 22.0
const HUMAN_REG_RACIAL_CAP: float = 12.0
const TROLL_REG_RACIAL_CAP: float = 65.0
const TROLL_CON_RACIAL_CAP: float = 45.0

const REG_COMBAT_CLOT_THRESHOLD: float = 40.0
const REG_MAGICAL_MP_THRESHOLD: float = 50.0
const REG_LIMB_REGROW_THRESHOLD: float = 150.0
const REG_ORGAN_REGROW_THRESHOLD: float = 400.0

const TAG_RACIAL_LIMIT: StringName = &"racial_limit"
const TAG_RACIAL_MULT: StringName = &"racial_mult"
const TAG_EQUIPMENT: StringName = &"equipment"
const TAG_LEG_LOCOMOTION: StringName = &"leg_locomotion"

const CONTROL_DEFICIT_THRESHOLD: float = 1.15
const STAMINA_DISCOUNT_MAX_CAP: float = 0.85
const BLEED_RESIST_MAX_CAP: float = 0.90

var mana_awakened: bool = false
var external_circulation_enabled: bool = true
var default_racial_cap: float = DEFAULT_HUMAN_RACIAL_CAP
var race_preset: RacePreset = RacePreset.HUMAN

var _base_stats: Dictionary[int, float] = {}
var _racial_caps: Dictionary[int, float] = {}
var _modifiers: Array[StatModifier] = []
var _ignored_tags: Array[StringName] = []

var _dirty: bool = true
var _cache: Dictionary[int, float] = {}
var _previous_values: Dictionary[int, float] = {}
var _cached_circ_mult: float = 1.0
var _cached_mana_skin_density: float = 0.0
var _cached_circ_stat_bonus: float = 0.0


func _init(
	p_default_racial_cap: float = DEFAULT_HUMAN_RACIAL_CAP,
	p_race_preset: RacePreset = RacePreset.HUMAN
) -> void:
	for s: int in ALL_STATS:
		if s == Stat.MP_CAP or s == Stat.M_CTRL:
			_base_stats[s] = 0.0
		else:
			_base_stats[s] = HUMAN_REFERENCE
		_cache[s] = _base_stats[s]
		_previous_values[s] = _base_stats[s]
	apply_race_preset(p_race_preset, false)
	if not is_equal_approx(p_default_racial_cap, DEFAULT_HUMAN_RACIAL_CAP):
		default_racial_cap = maxf(0.0, p_default_racial_cap)
	_dirty = true


static func get_stat_name(stat: int) -> StringName:
	match stat:
		Stat.STR:
			return &"STR"
		Stat.CTRL:
			return &"CTRL"
		Stat.SPD:
			return &"SPD"
		Stat.AGI:
			return &"AGI"
		Stat.CON:
			return &"CON"
		Stat.STA:
			return &"STA"
		Stat.TP:
			return &"TP"
		Stat.INT:
			return &"INT"
		Stat.MP_CAP:
			return &"MP_CAP"
		Stat.M_CTRL:
			return &"M_CTRL"
		Stat.SOUL:
			return &"SOUL"
		Stat.REG:
			return &"REG"
		_:
			return &"UNKNOWN"


static func get_race_preset_name(preset: RacePreset) -> StringName:
	match preset:
		RacePreset.HUMAN:
			return &"Human"
		RacePreset.TROLL:
			return &"Troll"
		_:
			return &"Unknown"


# ---------------------------------------------------------------------------
# Base stats, Racial caps, Mana awakening
# ---------------------------------------------------------------------------

func set_base_stat(stat: int, value: float) -> void:
	_base_stats[stat] = maxf(0.0, value)
	_mark_dirty()


func get_base_stat(stat: int) -> float:
	return _base_stats.get(stat, HUMAN_REFERENCE)


func set_all_base_stats(value: float, include_mana_stats: bool = false) -> void:
	var clamped_val: float = maxf(0.0, value)
	for s: int in ALL_STATS:
		if (s == Stat.MP_CAP or s == Stat.M_CTRL) and not include_mana_stats:
			continue
		_base_stats[s] = clamped_val
	_mark_dirty()


func set_racial_cap(stat: int, cap_value: float) -> void:
	_racial_caps[stat] = maxf(0.0, cap_value)
	_mark_dirty()


func set_default_racial_cap(cap_value: float) -> void:
	default_racial_cap = maxf(0.0, cap_value)
	_mark_dirty()


func get_racial_cap(stat: int) -> float:
	if _racial_caps.has(stat):
		return _racial_caps[stat]
	return default_racial_cap


## Switches pre-awakening biological ceilings for testing (GDD 3.2 #12, 14.1, 14.4).
## Human: REG <= 12, other stats <= 22. Troll: REG <= 65, CON <= 45, other stats <= 22.
## All racial ceilings are disabled automatically once mana_awakened is true.
func apply_race_preset(preset: RacePreset, emit_change: bool = true) -> void:
	var changed: bool = race_preset != preset
	race_preset = preset
	_racial_caps.clear()
	match preset:
		RacePreset.HUMAN:
			default_racial_cap = DEFAULT_HUMAN_RACIAL_CAP
			_racial_caps[Stat.REG] = HUMAN_REG_RACIAL_CAP
		RacePreset.TROLL:
			default_racial_cap = DEFAULT_HUMAN_RACIAL_CAP
			_racial_caps[Stat.REG] = TROLL_REG_RACIAL_CAP
			_racial_caps[Stat.CON] = TROLL_CON_RACIAL_CAP
	_mark_dirty()
	if emit_change and changed:
		_ensure_computed()
		race_preset_changed.emit(preset)


func awaken_mana(initial_mp_cap: float = HUMAN_REFERENCE, initial_m_ctrl: float = HUMAN_REFERENCE) -> void:
	var was_awakened: bool = mana_awakened
	mana_awakened = true
	if _base_stats.get(Stat.MP_CAP, 0.0) < initial_mp_cap:
		_base_stats[Stat.MP_CAP] = initial_mp_cap
	if _base_stats.get(Stat.M_CTRL, 0.0) < initial_m_ctrl:
		_base_stats[Stat.M_CTRL] = initial_m_ctrl
	_mark_dirty()
	_ensure_computed()
	if not was_awakened:
		mana_awakened_changed.emit(true)


func set_mana_awakened(awakened: bool, initial_mp_cap: float = HUMAN_REFERENCE, initial_m_ctrl: float = HUMAN_REFERENCE) -> void:
	if awakened:
		awaken_mana(initial_mp_cap, initial_m_ctrl)
		return
	var was_awakened: bool = mana_awakened
	mana_awakened = false
	_mark_dirty()
	_ensure_computed()
	if was_awakened:
		mana_awakened_changed.emit(false)


func set_external_circulation_enabled(enabled: bool) -> void:
	if external_circulation_enabled == enabled:
		return
	external_circulation_enabled = enabled
	_mark_dirty()


# ---------------------------------------------------------------------------
# Modifiers & Tag Filtering
# ---------------------------------------------------------------------------

func add_modifier(mod: StatModifier) -> void:
	if mod == null:
		return
	if mod.id != &"":
		for i: int in range(_modifiers.size()):
			if _modifiers[i].id == mod.id:
				_modifiers[i] = mod
				_mark_dirty()
				return
	_modifiers.append(mod)
	_mark_dirty()


func remove_modifier(mod_id: StringName) -> bool:
	for i: int in range(_modifiers.size() - 1, -1, -1):
		if _modifiers[i].id == mod_id:
			_modifiers.remove_at(i)
			_mark_dirty()
			return true
	return false


func remove_modifiers_by_source(source_name: StringName) -> int:
	var removed: int = 0
	for i: int in range(_modifiers.size() - 1, -1, -1):
		if _modifiers[i].source == source_name:
			_modifiers.remove_at(i)
			removed += 1
	if removed > 0:
		_mark_dirty()
	return removed


func has_modifier(mod_id: StringName) -> bool:
	for mod: StatModifier in _modifiers:
		if mod.id == mod_id:
			return true
	return false


func clear_modifiers() -> void:
	if _modifiers.is_empty():
		return
	_modifiers.clear()
	_mark_dirty()


func get_modifiers() -> Array[StatModifier]:
	return _modifiers.duplicate()


func add_ignored_tag(tag: StringName) -> void:
	if not _ignored_tags.has(tag):
		_ignored_tags.append(tag)
		_mark_dirty()


func remove_ignored_tag(tag: StringName) -> void:
	var idx: int = _ignored_tags.find(tag)
	if idx >= 0:
		_ignored_tags.remove_at(idx)
		_mark_dirty()


func has_ignored_tag(tag: StringName) -> bool:
	return _ignored_tags.has(tag)


func clear_ignored_tags() -> void:
	if _ignored_tags.is_empty():
		return
	_ignored_tags.clear()
	_mark_dirty()


# ---------------------------------------------------------------------------
# 4-Layer Pipeline Computation
# ---------------------------------------------------------------------------

func get_stat(stat: int) -> float:
	_ensure_computed()
	return _cache.get(stat, STAT_MIN)


func get_all_stats() -> Dictionary[int, float]:
	_ensure_computed()
	return _cache.duplicate()


func _mark_dirty() -> void:
	_dirty = true


func _ensure_computed() -> void:
	if not _dirty:
		return
	_recompute_all()


func _recompute_all() -> void:
	# Step 1: Compute M_CTRL first because External Circulation depends on it
	# (Circulation never modifies M_CTRL itself, so this is strictly acyclic).
	var final_m_ctrl: float = _evaluate_single_stat(Stat.M_CTRL, 0.0)
	_cache[Stat.M_CTRL] = final_m_ctrl

	# Step 2: Compute External Circulation values (GDD Section 2.2)
	if mana_awakened and final_m_ctrl > 0.0:
		_cached_circ_mult = 1.0 + 0.015 * final_m_ctrl
		_cached_mana_skin_density = 5.0 * pow(final_m_ctrl / 10.0, 1.4) * _cached_circ_mult
		_cached_circ_stat_bonus = floor(0.5 * (final_m_ctrl / 10.0) * _cached_circ_mult)
	else:
		_cached_circ_mult = 1.0
		_cached_mana_skin_density = 0.0
		_cached_circ_stat_bonus = 0.0

	# Step 3: Compute all remaining stats with circulation Flat Add applied to STR/CTRL/SPD/TP/CON
	for s: int in ALL_STATS:
		if s == Stat.M_CTRL:
			continue
		var circ_bonus: float = 0.0
		if mana_awakened and external_circulation_enabled and CIRCULATION_STATS.has(s):
			circ_bonus = _cached_circ_stat_bonus
		_cache[s] = _evaluate_single_stat(s, circ_bonus)

	_dirty = false

	# Step 4: Emit stat_changed notifications for any changed stat
	for s: int in ALL_STATS:
		var old_val: float = _previous_values.get(s, _cache[s])
		var new_val: float = _cache[s]
		if not is_equal_approx(old_val, new_val):
			_previous_values[s] = new_val
			stat_changed.emit(s, old_val, new_val)


func _evaluate_single_stat(stat: int, circulation_flat_bonus: float) -> float:
	# Before mana awakening, MP_CAP and M_CTRL are strictly 0.0 (GDD 3.2 #9-10, 14.4)
	if not mana_awakened and (stat == Stat.MP_CAP or stat == Stat.M_CTRL):
		return 0.0

	var stat_mods: Array[StatModifier] = _collect_active_modifiers(stat)

	# Layer 1: Base
	var value: float = _base_stats.get(stat, HUMAN_REFERENCE)
	for mod: StatModifier in stat_mods:
		if mod.layer == StatModifier.Layer.BASE:
			value += mod.value

	# Layer 2: Flat Add (includes External Circulation bonus for STR/CTRL/SPD/TP/CON)
	value += circulation_flat_bonus
	for mod: StatModifier in stat_mods:
		if mod.layer == StatModifier.Layer.FLAT_ADD:
			value += mod.value

	# Layer 3: Multipliers
	for mod: StatModifier in stat_mods:
		if mod.layer == StatModifier.Layer.MULTIPLIER:
			value *= mod.value

	# Layer 4: Overrides / Constraints
	var has_explicit_set_override: bool = false
	for mod: StatModifier in stat_mods:
		if mod.layer == StatModifier.Layer.OVERRIDE:
			match mod.override_mode:
				StatModifier.OverrideMode.SET_VALUE:
					value = mod.value
					has_explicit_set_override = true
				StatModifier.OverrideMode.CAP_MAX:
					value = minf(value, mod.value)
				StatModifier.OverrideMode.CAP_MIN:
					value = maxf(value, mod.value)

	# Racial biological cap (active ONLY before mana awakening; removed completely after awakening)
	if not mana_awakened:
		var r_cap: float = get_racial_cap(stat)
		if r_cap > 0.0:
			value = minf(value, r_cap)

	# Global hard bounds: 1..500 (explicit SET_VALUE override such as overload AGI=0 may reach 0.0)
	if has_explicit_set_override:
		return clampf(value, 0.0, STAT_MAX)
	return clampf(value, STAT_MIN, STAT_MAX)


func _collect_active_modifiers(stat: int) -> Array[StatModifier]:
	var result: Array[StatModifier] = []
	for mod: StatModifier in _modifiers:
		if mod.stat != stat:
			continue
		# Once mana is awakened, all racial limits and racial multipliers are disabled (GDD 2.1)
		if mana_awakened and (mod.tags.has(TAG_RACIAL_LIMIT) or mod.tags.has(TAG_RACIAL_MULT)):
			continue
		# Skip ignored tags (e.g. equipment modifiers inside Asceticism MindDomain, GDD 12.3)
		if not _ignored_tags.is_empty() and mod.has_any_tag(_ignored_tags):
			continue
		result.append(mod)
	result.sort_custom(func(a: StatModifier, b: StatModifier) -> bool:
		return a.priority < b.priority
	)
	return result


# ---------------------------------------------------------------------------
# External Circulation Getters (GDD Section 2.2)
# ---------------------------------------------------------------------------

func get_circulation_mult() -> float:
	_ensure_computed()
	return _cached_circ_mult


func get_mana_skin_density() -> float:
	_ensure_computed()
	return _cached_mana_skin_density


func get_circulation_stat_bonus() -> float:
	_ensure_computed()
	return _cached_circ_stat_bonus


# ---------------------------------------------------------------------------
# Derived Formulas for all 12 Stats (GDD Sections 3.1, 3.2, 5.2)
# ---------------------------------------------------------------------------

# 1. STR
func get_melee_damage_mult() -> float:
	return pow(get_stat(Stat.STR) / 10.0, 2.0)


func get_carry_capacity_kg(size_mult: float = 1.0) -> float:
	return 60.0 * pow(get_stat(Stat.STR) / 10.0, 2.0) * size_mult


func can_destroy_structure(wall_str_threshold: float) -> bool:
	return get_stat(Stat.STR) >= wall_str_threshold


# 2. CTRL (Relative penalty when STR > CTRL * 1.15 & high CTRL bonuses)
func get_control_deficit_ratio() -> float:
	var str_val: float = get_stat(Stat.STR)
	var ctrl_val: float = maxf(1.0, get_stat(Stat.CTRL))
	return maxf(0.0, (str_val / ctrl_val) - CONTROL_DEFICIT_THRESHOLD)


func has_control_deficit() -> bool:
	return get_stat(Stat.STR) > get_stat(Stat.CTRL) * CONTROL_DEFICIT_THRESHOLD


func get_corpse_obliteration_chance() -> float:
	return clampf(get_control_deficit_ratio() * 1.20, 0.0, 1.0)


func get_extra_weapon_wear_mult() -> float:
	return get_control_deficit_ratio()


func get_accidental_break_chance(careful_mode: bool = false) -> float:
	if careful_mode:
		return 0.0
	return clampf(get_control_deficit_ratio() * 1.50, 0.0, 1.0)


func get_ctrl_stamina_discount() -> float:
	var excess: float = maxf(0.0, get_stat(Stat.CTRL) - get_stat(Stat.STR))
	return clampf(excess * 0.005, 0.0, 0.40)


func get_precision_radius_px(base_radius: float = 3.0) -> float:
	var excess: float = maxf(0.0, get_stat(Stat.CTRL) - get_stat(Stat.STR))
	return base_radius + clampf(excess * 0.05, 0.0, 3.0)


# 3. SPD
func get_move_speed_mult() -> float:
	return get_stat(Stat.SPD) / 10.0


func get_run_speed_px(base_run_speed_px: float = 220.0) -> float:
	return base_run_speed_px * get_move_speed_mult()


func get_kinetic_damage_mult() -> float:
	return pow(get_stat(Stat.SPD) / 10.0, 2.0)


# 4. AGI
func get_dash_mult() -> float:
	return 1.0 + maxf(0.0, get_stat(Stat.AGI) - 10.0) * 0.025


func get_dash_cooldown_mult() -> float:
	var discount: float = clampf(maxf(0.0, get_stat(Stat.AGI) - 10.0) / 490.0 * 0.75, 0.0, 0.75)
	return 1.0 - discount


func get_instinct_dodge_chance(attack_spd: float) -> float:
	var agi_val: float = get_stat(Stat.AGI)
	if agi_val <= 5.0:
		return 0.0
	var spd_ratio: float = minf(1.0, get_stat(Stat.SPD) / maxf(0.001, attack_spd))
	return clampf(((agi_val - 5.0) / (agi_val + 80.0)) * spd_ratio, 0.0, 1.0)


# 5. CON
func get_con_skin_density() -> float:
	return 10.0 * pow(get_stat(Stat.CON) / 10.0, 1.8)


func get_bone_density_mult() -> float:
	var con_val: float = get_stat(Stat.CON)
	if con_val <= HUMAN_REFERENCE:
		return maxf(0.1, con_val / HUMAN_REFERENCE)
	return pow(con_val / HUMAN_REFERENCE, 1.15)


func get_bleed_resist_mult(extra_resist_mult: float = 1.0) -> float:
	var con_discount: float = clampf(maxf(0.0, get_stat(Stat.CON) - 10.0) / 490.0 * 0.75, 0.0, 0.75)
	var combined: float = (1.0 - con_discount) * clampf(extra_resist_mult, 0.0, 1.0)
	return clampf(combined, 1.0 - BLEED_RESIST_MAX_CAP, 1.0)


## Secondary synergy between CON and STA reserve (GDD 3.2 #5: CON retains skin/bone density,
## passive bleed resist, and stamina reserve synergy, while healing/clotting belong to REG).
func get_con_stamina_synergy_bonus() -> float:
	return maxf(0.0, get_stat(Stat.CON) - HUMAN_REFERENCE) * 2.5


func get_max_stamina_with_con() -> float:
	return get_max_stamina() + get_con_stamina_synergy_bonus()


# 6. STA + Multiplicative Stamina Discounts (CTRL + STA, total cap -85%)
func get_max_stamina() -> float:
	return 100.0 + 50.0 * pow(get_stat(Stat.STA) / 10.0, 1.5)


func get_stamina_regen_per_sec(walking: bool = false) -> float:
	var base_regen: float = 5.0 + 5.0 * pow(get_stat(Stat.STA) / 10.0, 1.4)
	return base_regen * (0.5 if walking else 1.0)


func get_sta_stamina_discount() -> float:
	return clampf(maxf(0.0, get_stat(Stat.STA) - 10.0) / 490.0 * 0.75, 0.0, 0.75)


func get_stamina_cost_mult(include_ctrl_discount: bool = true) -> float:
	var d_sta: float = get_sta_stamina_discount()
	var d_ctrl: float = get_ctrl_stamina_discount() if include_ctrl_discount else 0.0
	var raw_mult: float = (1.0 - d_sta) * (1.0 - d_ctrl)
	return clampf(raw_mult, 1.0 - STAMINA_DISCOUNT_MAX_CAP, 1.0)


func get_effective_stamina_cost(base_cost: float, include_ctrl_discount: bool = true) -> float:
	return base_cost * get_stamina_cost_mult(include_ctrl_discount)


# 7. TP
func get_brain_speed_mult() -> float:
	return get_stat(Stat.TP) / 10.0


# 8. INT
func get_essence_id_chance(essence_rank: int) -> float:
	return clampf((get_stat(Stat.INT) - float(essence_rank) * 25.0) * 0.02, 0.0, 1.0)


func get_alchemy_efficiency_mult() -> float:
	return 1.0 + maxf(0.0, get_stat(Stat.INT) - 10.0) * 0.015


func can_auto_highlight_weak_points() -> bool:
	return get_stat(Stat.INT) >= 300.0


# 9. MP_CAP & 10. M_CTRL
func get_max_mp() -> float:
	if not mana_awakened:
		return 0.0
	return 100.0 * pow(get_stat(Stat.MP_CAP) / 10.0, 1.6)


func get_mp_regen_per_sec(meditating: bool = false) -> float:
	if not mana_awakened:
		return 0.0
	var regen: float = 1.0 + 1.5 * pow(get_stat(Stat.MP_CAP) / 10.0, 1.3)
	return regen * (2.0 if meditating else 1.0)


func get_mp_cost_mult() -> float:
	if not mana_awakened:
		return 1.0
	return clampf(1.0 - get_stat(Stat.M_CTRL) * 0.002, 0.20, 1.0)


# 11. SOUL & SP_CAP (GDD Sections 3.2 #11 & 5.2)
func get_sp_cap() -> float:
	return get_stat(Stat.SOUL) * 10.0


func get_essence_slots() -> int:
	return floori(get_stat(Stat.SOUL) / 35.0) + 1


func get_soul_magic_damage_mult() -> float:
	return pow(get_stat(Stat.SOUL) / 10.0, 1.7)


func has_mental_shield(current_sp: float = 1.0) -> bool:
	return get_stat(Stat.SOUL) >= 300.0 and current_sp > 0.0


# 12. REG (Regeneration, GDD Sections 3.1 & 3.2 #12)
func get_clot_rate() -> float:
	return pow(get_stat(Stat.REG) / HUMAN_REFERENCE, 1.5)


func get_heal_rate() -> float:
	return pow(get_stat(Stat.REG) / HUMAN_REFERENCE, 1.8)


func can_combat_clot() -> bool:
	return get_stat(Stat.REG) >= REG_COMBAT_CLOT_THRESHOLD


func uses_magical_regen() -> bool:
	return mana_awakened and get_stat(Stat.REG) > REG_MAGICAL_MP_THRESHOLD


func can_regrow_limbs() -> bool:
	return get_stat(Stat.REG) >= REG_LIMB_REGROW_THRESHOLD


func can_reconstruct_organs() -> bool:
	return get_stat(Stat.REG) >= REG_ORGAN_REGROW_THRESHOLD
