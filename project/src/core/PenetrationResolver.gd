class_name PenetrationResolver
extends RefCounted
## Layered 4-barrier penetration, weak-point bypass, attack-type modifiers (THRUST/SLASH/BLUNT),
## dead-zone penalty & Half-swording, Aura & Aura Burst, dismemberment threshold, weapon lodging,
## blunt impulse / Wall Slam, and Blade Clash resolver.
## Implements exact formulas from GDD Sections 3.4, 7.2, 7.3, 12.2, and 14.4 (v0.2).

enum AttackType {
	STANDARD = 0,
	THRUST = 1,
	SLASH = 2,
	BLUNT = 3,
}

enum TissueBarrier {
	NONE = 0,
	ARMOR = 1,
	SKIN = 2,
	MUSCLE_TENDON = 3,
	BONE_VESSEL_ORGAN = 4,
}

const DEFAULT_BASE_ANATOMY_THICKNESS: float = 2.0
const WEAK_POINT_ARMOR_BYPASS: float = 1.0
const WEAK_POINT_TISSUE_BYPASS_MULT: float = 0.25
const NORMAL_ARMOR_BYPASS: float = 0.0
const NORMAL_TISSUE_BYPASS_MULT: float = 1.0

const TYPE_PIERCE_MULT_STANDARD: float = 1.0
const TYPE_PIERCE_MULT_THRUST: float = 1.35
const TYPE_PIERCE_MULT_SLASH: float = 0.85
const TYPE_PIERCE_MULT_BLUNT: float = 0.15
const BLUNT_ATTACK_IMPULSE_MULT: float = 1.40

const DEAD_ZONE_MULT: float = 0.30
const DEAD_ZONE_BLUNT_MULT: float = 0.50
const HALF_SWORD_REACH_MULT: float = 0.55

const AURA_MIN_M_CTRL: float = 1.0
const AURA_MP_PER_SEC: float = 4.5
const AURA_MP_PER_SWING: float = 4.0
const AURA_MP_PER_HEAVY_HIT: float = 5.0
const AURA_BURST_MP_COST: float = 15.0
const AURA_BURST_MULT: float = 1.8

const SEVER_BONE_FACTOR: float = 0.35
const LODGE_DENSE_MUSCLE_CON_THRESHOLD: float = 35.0

const CLASH_STR_STAGGER_RATIO: float = 1.15
const CLASH_CTRL_DEFLECT_RATIO: float = 1.25
const CLASH_COUNTER_WINDOW_SEC: float = 0.65
const CLASH_AURA_VS_PLAIN_SHARPNESS_LOSS: float = 0.35
const CLASH_AURA_VS_PLAIN_DURABILITY_LOSS: float = 45.0

const SEVERABLE_ZONES: Array[StringName] = [
	&"Neck",
	&"LeftArm",
	&"RightArm",
	&"LeftLeg",
	&"RightLeg",
	&"Wings",
	&"Tail",
]


class AuraBonuses extends RefCounted:
	var active: bool = false
	var is_burst: bool = false
	var pierce_bonus: float = 0.0
	var blade_extension: float = 0.0
	var impact_bonus: float = 0.0


class AttackParams extends RefCounted:
	var attacker_str: float = 10.0
	var attacker_m_ctrl: float = 0.0
	var weapon_base_penetration: float = 12.0
	var weapon_blade_length: float = 12.0
	var edge_sharpness: float = 1.0
	var weapon_mass_factor: float = 4.0
	var kinetic_mult: float = 1.0
	var aura_active: bool = false
	var aura_burst: bool = false
	var is_weak_point: bool = false
	var attacker_height_z: float = 0.0
	var weapon_vertical_reach: float = 0.6

	# v0.2 directional attack, range dead zone, Half-swording & Anti-Regen parameters
	var attack_type: AttackType = AttackType.STANDARD
	var type_pierce_mult_override: float = -1.0
	var slash_sever_mult: float = 1.0
	var blunt_impulse_mult: float = 1.0
	var distance_to_target: float = -1.0
	var min_optimal_range: float = 0.0
	var half_swording: bool = false
	var can_half_sword: bool = false
	var anti_regen: bool = false
	var anti_regen_duration_sec: float = 8.0


class DefenseParams extends RefCounted:
	var target_con: float = 10.0
	var mana_skin_density: float = 0.0
	var hardening_bonus: float = 0.0
	var size_mult: float = 1.0
	var base_anatomy_thickness: float = DEFAULT_BASE_ANATOMY_THICKNESS
	var bone_density: float = 100.0
	var armor_thickness: float = 0.0
	var armor_hardness: float = 0.0
	var target_height_z: float = 0.0
	var zone_name: StringName = &""


class ResolutionResult extends RefCounted:
	var in_vertical_reach: bool = true
	var is_weak_point: bool = false
	var aura_active: bool = false
	var aura_burst: bool = false
	var guard_break_forced: bool = false
	var weak_point_bypass: float = 0.0
	var tissue_bypass_mult: float = 1.0

	var attack_type: AttackType = AttackType.STANDARD
	var type_pierce_mult: float = 1.0
	var in_dead_zone: bool = false
	var dead_zone_mult: float = 1.0
	var half_swording: bool = false

	var aura_pierce_bonus: float = 0.0
	var aura_blade_extension: float = 0.0
	var aura_impact: float = 0.0
	var hardening_bonus: float = 0.0

	# 4 sequential barriers: 1. Armor -> 2. Skin/CON -> 3. Muscles/Tendons -> 4. Bones/Vessels/Organs
	var armor_barrier: float = 0.0
	var skin_barrier: float = 0.0
	var barrier_depth: float = 0.0
	var muscle_tendon_barrier: float = 0.0
	var bone_vessel_barrier: float = 0.0

	var armor_breached: bool = false
	var skin_breached: bool = false
	var muscle_tendon_breached: bool = false
	var bone_vessel_breached: bool = false
	var deepest_barrier_reached: TissueBarrier = TissueBarrier.NONE

	var penetration: float = 0.0
	var raw_depth: float = 0.0
	var max_blade_reach: float = 0.0
	var effective_depth: float = 0.0
	var penetrated: bool = false
	var blunt_impulse: float = 0.0
	var wall_slam_impulse: float = 0.0

	var tendon_severed: bool = false
	var arterial_hit: bool = false
	var sever_threshold: float = 0.0
	var severed: bool = false
	var weapon_lodged: bool = false
	var anti_regen: bool = false
	var anti_regen_duration_sec: float = 0.0

	func to_dict() -> Dictionary:
		return {
			"in_vertical_reach": in_vertical_reach,
			"is_weak_point": is_weak_point,
			"aura_active": aura_active,
			"aura_burst": aura_burst,
			"guard_break_forced": guard_break_forced,
			"weak_point_bypass": weak_point_bypass,
			"tissue_bypass_mult": tissue_bypass_mult,
			"attack_type": attack_type,
			"type_pierce_mult": type_pierce_mult,
			"in_dead_zone": in_dead_zone,
			"dead_zone_mult": dead_zone_mult,
			"half_swording": half_swording,
			"aura_pierce_bonus": aura_pierce_bonus,
			"aura_blade_extension": aura_blade_extension,
			"aura_impact": aura_impact,
			"armor_barrier": armor_barrier,
			"skin_barrier": skin_barrier,
			"barrier_depth": barrier_depth,
			"muscle_tendon_barrier": muscle_tendon_barrier,
			"bone_vessel_barrier": bone_vessel_barrier,
			"armor_breached": armor_breached,
			"skin_breached": skin_breached,
			"muscle_tendon_breached": muscle_tendon_breached,
			"bone_vessel_breached": bone_vessel_breached,
			"deepest_barrier_reached": deepest_barrier_reached,
			"penetration": penetration,
			"raw_depth": raw_depth,
			"max_blade_reach": max_blade_reach,
			"effective_depth": effective_depth,
			"penetrated": penetrated,
			"blunt_impulse": blunt_impulse,
			"wall_slam_impulse": wall_slam_impulse,
			"tendon_severed": tendon_severed,
			"arterial_hit": arterial_hit,
			"sever_threshold": sever_threshold,
			"severed": severed,
			"weapon_lodged": weapon_lodged,
			"anti_regen": anti_regen,
			"anti_regen_duration_sec": anti_regen_duration_sec,
		}


class ClashParams extends RefCounted:
	var actor: Node = null
	var strength: float = 10.0
	var control: float = 10.0
	var aura_active: bool = false
	var m_ctrl: float = 0.0
	var weapon_mass: float = 10.0
	var weapon_durability: float = 100.0
	var weapon_sharpness: float = 1.0
	var weapon: WeaponData = null


class ClashResult extends RefCounted:
	## 0 = draw/mutual recoil, 1 = side A wins STR clash, 2 = side B wins STR clash
	var winner: int = 0
	var str_score_a: float = 0.0
	var str_score_b: float = 0.0
	var stagger_a_sec: float = 0.0
	var stagger_b_sec: float = 0.0
	var knockback_a: float = 0.0
	var knockback_b: float = 0.0
	## 0 = none, 1 = A deflects B aside (opens counter window for A), 2 = B deflects A aside
	var ctrl_deflect_winner: int = 0
	var counter_window_sec: float = 0.0
	var weapon_a_sharpness_loss: float = 0.0
	var weapon_b_sharpness_loss: float = 0.0
	var weapon_a_durability_loss: float = 0.0
	var weapon_b_durability_loss: float = 0.0
	var weapon_a_broken: bool = false
	var weapon_b_broken: bool = false

	func to_dict() -> Dictionary:
		return {
			"winner": winner,
			"str_score_a": str_score_a,
			"str_score_b": str_score_b,
			"stagger_a_sec": stagger_a_sec,
			"stagger_b_sec": stagger_b_sec,
			"knockback_a": knockback_a,
			"knockback_b": knockback_b,
			"ctrl_deflect_winner": ctrl_deflect_winner,
			"counter_window_sec": counter_window_sec,
			"weapon_a_sharpness_loss": weapon_a_sharpness_loss,
			"weapon_b_sharpness_loss": weapon_b_sharpness_loss,
			"weapon_a_durability_loss": weapon_a_durability_loss,
			"weapon_b_durability_loss": weapon_b_durability_loss,
			"weapon_a_broken": weapon_a_broken,
			"weapon_b_broken": weapon_b_broken,
		}


# ---------------------------------------------------------------------------
# Pure Formula Helpers (GDD Section 12.2)
# ---------------------------------------------------------------------------

static func get_default_type_pierce_mult(p_attack_type: AttackType) -> float:
	match p_attack_type:
		AttackType.THRUST:
			return TYPE_PIERCE_MULT_THRUST
		AttackType.SLASH:
			return TYPE_PIERCE_MULT_SLASH
		AttackType.BLUNT:
			return TYPE_PIERCE_MULT_BLUNT
		_:
			return TYPE_PIERCE_MULT_STANDARD


static func calculate_aura_bonuses(
	aura_active: bool,
	attacker_m_ctrl: float,
	aura_burst: bool = false
) -> AuraBonuses:
	var bonuses: AuraBonuses = AuraBonuses.new()
	if (not aura_active and not aura_burst) or attacker_m_ctrl < AURA_MIN_M_CTRL:
		return bonuses
	bonuses.active = true
	var scale: float = attacker_m_ctrl / 10.0
	bonuses.pierce_bonus = 130.0 * pow(scale, 1.25)
	bonuses.blade_extension = 6.0 * pow(scale, 0.5)
	bonuses.impact_bonus = 75.0 * pow(scale, 1.25)
	if aura_burst:
		bonuses.is_burst = true
		bonuses.pierce_bonus *= AURA_BURST_MULT
		bonuses.impact_bonus *= AURA_BURST_MULT
	return bonuses


## Barrier 1: Armor
static func calculate_armor_barrier(
	armor_thickness: float,
	armor_hardness: float,
	weak_point_bypass: float = NORMAL_ARMOR_BYPASS
) -> float:
	var bypass: float = clampf(weak_point_bypass, 0.0, 1.0)
	return maxf(0.0, armor_thickness) * maxf(0.0, armor_hardness) * (1.0 - bypass)


## Barrier 2: Skin / Subcutaneous (CON + mana_skin_density + hardening_bonus)
static func calculate_skin_barrier(
	target_con: float,
	mana_skin_density: float,
	size_mult: float = 1.0,
	base_anatomy_thickness: float = DEFAULT_BASE_ANATOMY_THICKNESS,
	tissue_bypass_mult: float = NORMAL_TISSUE_BYPASS_MULT,
	hardening_bonus: float = 0.0
) -> float:
	var con_density: float = 10.0 * pow(maxf(0.0, target_con) / 10.0, 1.8)
	var tissue_layer: float = (con_density + maxf(0.0, mana_skin_density) + maxf(0.0, hardening_bonus)) * clampf(tissue_bypass_mult, 0.0, 1.0)
	return base_anatomy_thickness * maxf(0.01, size_mult) + tissue_layer


## Combined entry barrier_depth = Barrier 1 (Armor) + Barrier 2 (Skin/CON + ManaSkin + Hardening)
static func calculate_barrier_depth(
	target_con: float,
	mana_skin_density: float,
	armor_barrier: float,
	size_mult: float = 1.0,
	base_anatomy_thickness: float = DEFAULT_BASE_ANATOMY_THICKNESS,
	tissue_bypass_mult: float = NORMAL_TISSUE_BYPASS_MULT,
	hardening_bonus: float = 0.0
) -> float:
	var skin: float = calculate_skin_barrier(
		target_con,
		mana_skin_density,
		size_mult,
		base_anatomy_thickness,
		tissue_bypass_mult,
		hardening_bonus
	)
	return skin + maxf(0.0, armor_barrier)


## Barrier 3: Muscles & Tendons depth threshold after breaching skin
static func calculate_muscle_tendon_barrier(
	target_con: float,
	size_mult: float = 1.0,
	tissue_bypass_mult: float = NORMAL_TISSUE_BYPASS_MULT,
	hardening_bonus: float = 0.0
) -> float:
	var base_muscle: float = 3.5 + (maxf(0.0, target_con) / 10.0) * 1.5 + maxf(0.0, hardening_bonus) * 0.05
	return base_muscle * maxf(0.01, size_mult) * clampf(tissue_bypass_mult, 0.0, 1.0)


## Barrier 4: Bones, Major Vessels & Vital Organs depth threshold
static func calculate_bone_vessel_barrier(
	size_mult: float = 1.0,
	is_weak_point: bool = false,
	muscle_tendon_barrier: float = 0.0
) -> float:
	var base_deep: float = (6.0 if is_weak_point else 12.0) * maxf(0.01, size_mult)
	return maxf(muscle_tendon_barrier + 1.0, base_deep)


## Excess penetration threshold above barrier_depth required for SLASH Dismemberment
static func calculate_sever_threshold(
	target_con: float,
	bone_density: float = 100.0,
	size_mult: float = 1.0,
	slash_sever_mult: float = 1.0
) -> float:
	var eff_bone: float = maxf(1.0, bone_density) * (1.0 + maxf(0.0, target_con - 10.0) * 0.10)
	return (eff_bone * SEVER_BONE_FACTOR * maxf(0.25, size_mult)) / maxf(0.1, slash_sever_mult)


static func is_in_dead_zone(
	distance_to_target: float,
	min_optimal_range: float,
	half_swording: bool = false,
	can_half_sword: bool = false
) -> bool:
	if distance_to_target < 0.0:
		return false
	if half_swording and can_half_sword:
		return false
	return min_optimal_range > 0.0 and distance_to_target < min_optimal_range


static func calculate_penetration(
	weapon_base_penetration: float,
	attacker_str: float,
	kinetic_mult: float = 1.0,
	aura_pierce_bonus: float = 0.0,
	edge_sharpness: float = 1.0,
	type_pierce_mult: float = 1.0,
	dead_zone_mult: float = 1.0
) -> float:
	var str_scale: float = pow(maxf(0.0, attacker_str) / 10.0, 1.6)
	var base_force: float = (
		maxf(0.0, weapon_base_penetration)
		* str_scale
		* maxf(0.0, kinetic_mult)
		* maxf(0.0, type_pierce_mult)
		* maxf(0.0, dead_zone_mult)
	)
	return (base_force + maxf(0.0, aura_pierce_bonus)) * maxf(0.0, edge_sharpness)


static func calculate_effective_depth(
	penetration: float,
	barrier_depth: float,
	weapon_blade_length: float,
	aura_blade_extension: float = 0.0
) -> float:
	var raw: float = minf(penetration - barrier_depth, maxf(0.0, weapon_blade_length) + maxf(0.0, aura_blade_extension))
	return maxf(0.0, raw)


static func calculate_blunt_impulse(
	weapon_mass_factor: float,
	attacker_str: float,
	kinetic_mult: float = 1.0,
	aura_impact: float = 0.0,
	type_blunt_mult: float = 1.0
) -> float:
	var str_scale: float = pow(maxf(0.0, attacker_str) / 10.0, 2.0)
	var raw_impulse: float = maxf(0.0, weapon_mass_factor) * str_scale * maxf(0.0, kinetic_mult) + maxf(0.0, aura_impact)
	return raw_impulse * maxf(0.0, type_blunt_mult)


static func is_in_vertical_reach(
	attacker_height_z: float,
	target_height_z: float,
	weapon_vertical_reach: float
) -> bool:
	return absf(attacker_height_z - target_height_z) <= maxf(0.0, weapon_vertical_reach)


# ---------------------------------------------------------------------------
# Full 4-Barrier Strike Resolution
# ---------------------------------------------------------------------------

static func resolve(
	attack: AttackParams,
	defense: DefenseParams,
	check_vertical_reach: bool = false,
	emit_log: bool = false
) -> ResolutionResult:
	var result: ResolutionResult = ResolutionResult.new()
	result.is_weak_point = attack.is_weak_point
	result.attack_type = attack.attack_type
	result.half_swording = attack.half_swording and attack.can_half_sword
	result.anti_regen = attack.anti_regen
	result.anti_regen_duration_sec = attack.anti_regen_duration_sec if attack.anti_regen else 0.0

	var aura: AuraBonuses = calculate_aura_bonuses(attack.aura_active, attack.attacker_m_ctrl, attack.aura_burst)
	result.aura_active = aura.active
	result.aura_burst = aura.is_burst
	result.guard_break_forced = aura.is_burst
	result.aura_pierce_bonus = aura.pierce_bonus
	result.aura_blade_extension = aura.blade_extension
	result.aura_impact = aura.impact_bonus
	result.hardening_bonus = maxf(0.0, defense.hardening_bonus)

	result.weak_point_bypass = WEAK_POINT_ARMOR_BYPASS if attack.is_weak_point else NORMAL_ARMOR_BYPASS
	result.tissue_bypass_mult = WEAK_POINT_TISSUE_BYPASS_MULT if attack.is_weak_point else NORMAL_TISSUE_BYPASS_MULT

	result.type_pierce_mult = (
		attack.type_pierce_mult_override
		if attack.type_pierce_mult_override > 0.0
		else get_default_type_pierce_mult(attack.attack_type)
	)
	result.in_dead_zone = is_in_dead_zone(
		attack.distance_to_target,
		attack.min_optimal_range,
		attack.half_swording,
		attack.can_half_sword
	)
	result.dead_zone_mult = DEAD_ZONE_MULT if result.in_dead_zone else 1.0

	result.in_vertical_reach = is_in_vertical_reach(
		attack.attacker_height_z,
		defense.target_height_z,
		attack.weapon_vertical_reach
	)

	# 4 Sequential Tissue Barriers
	result.armor_barrier = calculate_armor_barrier(
		defense.armor_thickness,
		defense.armor_hardness,
		result.weak_point_bypass
	)
	result.skin_barrier = calculate_skin_barrier(
		defense.target_con,
		defense.mana_skin_density,
		defense.size_mult,
		defense.base_anatomy_thickness,
		result.tissue_bypass_mult,
		defense.hardening_bonus
	)
	result.barrier_depth = result.armor_barrier + result.skin_barrier
	result.muscle_tendon_barrier = calculate_muscle_tendon_barrier(
		defense.target_con,
		defense.size_mult,
		result.tissue_bypass_mult,
		defense.hardening_bonus
	)
	result.bone_vessel_barrier = calculate_bone_vessel_barrier(
		defense.size_mult,
		attack.is_weak_point,
		result.muscle_tendon_barrier
	)
	result.sever_threshold = calculate_sever_threshold(
		defense.target_con,
		defense.bone_density,
		defense.size_mult,
		attack.slash_sever_mult
	)

	var effective_blade_len: float = (
		maxf(0.0, attack.weapon_blade_length) * HALF_SWORD_REACH_MULT
		if result.half_swording
		else maxf(0.0, attack.weapon_blade_length)
	)
	result.penetration = calculate_penetration(
		attack.weapon_base_penetration,
		attack.attacker_str,
		attack.kinetic_mult,
		aura.pierce_bonus,
		attack.edge_sharpness,
		result.type_pierce_mult,
		result.dead_zone_mult
	)
	result.max_blade_reach = effective_blade_len + aura.blade_extension
	result.raw_depth = result.penetration - result.barrier_depth

	if check_vertical_reach and not result.in_vertical_reach:
		result.effective_depth = 0.0
		result.penetrated = false
		result.blunt_impulse = 0.0
		result.wall_slam_impulse = 0.0
		result.deepest_barrier_reached = TissueBarrier.NONE
	else:
		result.effective_depth = calculate_effective_depth(
			result.penetration,
			result.barrier_depth,
			effective_blade_len,
			aura.blade_extension
		)
		result.penetrated = result.effective_depth > 0.0

		var blunt_type_mult: float = (
			(BLUNT_ATTACK_IMPULSE_MULT if attack.attack_type == AttackType.BLUNT else 1.0)
			* maxf(0.0, attack.blunt_impulse_mult)
			* (DEAD_ZONE_BLUNT_MULT if result.in_dead_zone else 1.0)
		)
		result.blunt_impulse = calculate_blunt_impulse(
			attack.weapon_mass_factor,
			attack.attacker_str,
			attack.kinetic_mult,
			aura.impact_bonus,
			blunt_type_mult
		)
		result.wall_slam_impulse = result.blunt_impulse

		# Evaluate sequential 4-barrier breach state
		result.armor_breached = result.penetration > result.armor_barrier
		result.skin_breached = result.penetrated
		result.muscle_tendon_breached = result.skin_breached and result.effective_depth >= result.muscle_tendon_barrier
		result.bone_vessel_breached = result.skin_breached and result.effective_depth >= result.bone_vessel_barrier

		if not result.armor_breached:
			result.deepest_barrier_reached = TissueBarrier.NONE
		elif not result.skin_breached:
			result.deepest_barrier_reached = TissueBarrier.ARMOR
		elif not result.muscle_tendon_breached:
			result.deepest_barrier_reached = TissueBarrier.SKIN
		elif not result.bone_vessel_breached:
			result.deepest_barrier_reached = TissueBarrier.MUSCLE_TENDON
		else:
			result.deepest_barrier_reached = TissueBarrier.BONE_VESSEL_ORGAN

		# Tendon tear, arterial rupture, dismemberment, and blade lodging
		if result.skin_breached and attack.attack_type != AttackType.BLUNT:
			if result.muscle_tendon_breached:
				result.tendon_severed = (
					attack.attack_type == AttackType.SLASH
					or result.effective_depth >= result.muscle_tendon_barrier * 1.25
				)
			if result.bone_vessel_breached:
				result.arterial_hit = true

			if attack.attack_type == AttackType.SLASH:
				var zone_severable: bool = SEVERABLE_ZONES.has(defense.zone_name)
				if (
					zone_severable
					and result.bone_vessel_breached
					and result.raw_depth >= result.sever_threshold
					and result.max_blade_reach >= result.bone_vessel_barrier
				):
					result.severed = true

			# Blade lodging: breached armor + skin, halted in dense/hardened muscle before exiting/severing
			if not result.severed and not result.bone_vessel_breached:
				var hardened_trap: bool = defense.hardening_bonus > 0.0
				var dense_muscle_trap: bool = (
					result.muscle_tendon_breached
					and defense.target_con >= LODGE_DENSE_MUSCLE_CON_THRESHOLD
					and not result.aura_active
				)
				if hardened_trap or dense_muscle_trap:
					result.weapon_lodged = true

	if emit_log:
		_emit_resolution_log(result)

	return result


static func resolve_from_sheets(
	attacker_sheet: StatSheet,
	defense_sheet: StatSheet,
	weapon_base_penetration: float,
	weapon_blade_length: float,
	edge_sharpness: float,
	weapon_mass_factor: float,
	aura_active: bool = false,
	is_weak_point: bool = false,
	kinetic_mult: float = 1.0,
	armor_thickness: float = 0.0,
	armor_hardness: float = 0.0,
	target_size_mult: float = 1.0,
	base_anatomy_thickness: float = DEFAULT_BASE_ANATOMY_THICKNESS,
	emit_log: bool = false,
	attack_type: AttackType = AttackType.STANDARD,
	hardening_bonus: float = 0.0,
	aura_burst: bool = false,
	zone_name: StringName = &""
) -> ResolutionResult:
	var attack: AttackParams = AttackParams.new()
	attack.attacker_str = attacker_sheet.get_stat(StatSheet.Stat.STR)
	attack.attacker_m_ctrl = attacker_sheet.get_stat(StatSheet.Stat.M_CTRL) if attacker_sheet.mana_awakened else 0.0
	attack.weapon_base_penetration = weapon_base_penetration
	attack.weapon_blade_length = weapon_blade_length
	attack.edge_sharpness = edge_sharpness
	attack.weapon_mass_factor = weapon_mass_factor
	attack.kinetic_mult = kinetic_mult
	attack.aura_active = aura_active
	attack.aura_burst = aura_burst
	attack.is_weak_point = is_weak_point
	attack.attack_type = attack_type

	var defense: DefenseParams = DefenseParams.new()
	defense.target_con = defense_sheet.get_stat(StatSheet.Stat.CON)
	defense.mana_skin_density = defense_sheet.get_mana_skin_density()
	defense.hardening_bonus = hardening_bonus
	defense.size_mult = target_size_mult
	defense.base_anatomy_thickness = base_anatomy_thickness
	defense.armor_thickness = armor_thickness
	defense.armor_hardness = armor_hardness
	defense.zone_name = zone_name

	return resolve(attack, defense, false, emit_log)


# ---------------------------------------------------------------------------
# Pure Blade Clash Resolver (STR, CTRL, Durability & Aura, GDD 7.2 & 12.2)
# ---------------------------------------------------------------------------

static func resolve_blade_clash(
	a: ClashParams,
	b: ClashParams,
	apply_weapon_damage: bool = true,
	emit_event: bool = false
) -> ClashResult:
	var res: ClashResult = ClashResult.new()
	if a == null or b == null:
		return res

	var aura_a: AuraBonuses = calculate_aura_bonuses(a.aura_active, a.m_ctrl, false)
	var aura_b: AuraBonuses = calculate_aura_bonuses(b.aura_active, b.m_ctrl, false)

	res.str_score_a = pow(maxf(1.0, a.strength) / 10.0, 2.0) * (1.0 + maxf(0.0, a.weapon_mass) * 0.05) + aura_a.impact_bonus * 0.05
	res.str_score_b = pow(maxf(1.0, b.strength) / 10.0, 2.0) * (1.0 + maxf(0.0, b.weapon_mass) * 0.05) + aura_b.impact_bonus * 0.05

	# 1. Strength dominance -> stagger & knockback
	if res.str_score_a >= res.str_score_b * CLASH_STR_STAGGER_RATIO:
		res.winner = 1
		var ratio_ab: float = res.str_score_a / maxf(0.01, res.str_score_b)
		res.stagger_b_sec = clampf(0.6 + (ratio_ab - 1.0) * 0.35, 0.6, 1.4)
		res.knockback_b = clampf(80.0 * ratio_ab, 80.0, 320.0)
	elif res.str_score_b >= res.str_score_a * CLASH_STR_STAGGER_RATIO:
		res.winner = 2
		var ratio_ba: float = res.str_score_b / maxf(0.01, res.str_score_a)
		res.stagger_a_sec = clampf(0.6 + (ratio_ba - 1.0) * 0.35, 0.6, 1.4)
		res.knockback_a = clampf(80.0 * ratio_ba, 80.0, 320.0)
	else:
		res.winner = 0
		res.knockback_a = 45.0
		res.knockback_b = 45.0

	# 2. Control deflection -> redirects opponent's blade aside, opening counter window
	if a.control >= maxf(1.0, b.control) * CLASH_CTRL_DEFLECT_RATIO:
		res.ctrl_deflect_winner = 1
		res.counter_window_sec = CLASH_COUNTER_WINDOW_SEC
		res.stagger_b_sec = maxf(res.stagger_b_sec, 0.75)
	elif b.control >= maxf(1.0, a.control) * CLASH_CTRL_DEFLECT_RATIO:
		res.ctrl_deflect_winner = 2
		res.counter_window_sec = CLASH_COUNTER_WINDOW_SEC
		res.stagger_a_sec = maxf(res.stagger_a_sec, 0.75)

	# 3. Durability & Aura mismatch -> non-Aura blade chips heavily or snaps against Aura blade
	var dur_a: float = a.weapon.durability if a.weapon != null else a.weapon_durability
	var dur_b: float = b.weapon.durability if b.weapon != null else b.weapon_durability

	if aura_a.active and not aura_b.active:
		var scale_a: float = 1.0 + maxf(0.0, a.m_ctrl / 25.0)
		res.weapon_b_sharpness_loss = CLASH_AURA_VS_PLAIN_SHARPNESS_LOSS * scale_a
		res.weapon_b_durability_loss = CLASH_AURA_VS_PLAIN_DURABILITY_LOSS * scale_a
		res.weapon_b_broken = (dur_b - res.weapon_b_durability_loss) <= 0.0
	elif aura_b.active and not aura_a.active:
		var scale_b: float = 1.0 + maxf(0.0, b.m_ctrl / 25.0)
		res.weapon_a_sharpness_loss = CLASH_AURA_VS_PLAIN_SHARPNESS_LOSS * scale_b
		res.weapon_a_durability_loss = CLASH_AURA_VS_PLAIN_DURABILITY_LOSS * scale_b
		res.weapon_a_broken = (dur_a - res.weapon_a_durability_loss) <= 0.0
	elif not aura_a.active and not aura_b.active:
		res.weapon_a_sharpness_loss = 0.03
		res.weapon_b_sharpness_loss = 0.03
		res.weapon_a_durability_loss = 3.0 + maxf(0.0, b.weapon_mass) * 0.25
		res.weapon_b_durability_loss = 3.0 + maxf(0.0, a.weapon_mass) * 0.25
		res.weapon_a_broken = (dur_a - res.weapon_a_durability_loss) <= 0.0
		res.weapon_b_broken = (dur_b - res.weapon_b_durability_loss) <= 0.0

	if apply_weapon_damage:
		if a.weapon != null and not aura_a.active:
			if res.weapon_a_sharpness_loss > 0.0:
				a.weapon.edge_sharpness = maxf(0.15, a.weapon.edge_sharpness - res.weapon_a_sharpness_loss)
			if res.weapon_a_durability_loss > 0.0:
				a.weapon.apply_durability_damage(res.weapon_a_durability_loss, 0.0, false)
			res.weapon_a_broken = a.weapon.is_broken()
		if b.weapon != null and not aura_b.active:
			if res.weapon_b_sharpness_loss > 0.0:
				b.weapon.edge_sharpness = maxf(0.15, b.weapon.edge_sharpness - res.weapon_b_sharpness_loss)
			if res.weapon_b_durability_loss > 0.0:
				b.weapon.apply_durability_damage(res.weapon_b_durability_loss, 0.0, false)
			res.weapon_b_broken = b.weapon.is_broken()

	if emit_event:
		_emit_blade_clash_event(res)

	return res


static func _emit_resolution_log(result: ResolutionResult) -> void:
	var main_loop: MainLoop = Engine.get_main_loop()
	if main_loop is SceneTree:
		var tree: SceneTree = main_loop as SceneTree
		var bus: Node = tree.root.get_node_or_null("EventBus")
		if bus != null and bus.has_method("publish_penetration_log"):
			bus.call("publish_penetration_log", result.to_dict())


static func _emit_blade_clash_event(result: ClashResult) -> void:
	var main_loop: MainLoop = Engine.get_main_loop()
	if main_loop is SceneTree:
		var tree: SceneTree = main_loop as SceneTree
		var bus: Node = tree.root.get_node_or_null("EventBus")
		if bus != null and bus.has_method("publish_blade_clash"):
			bus.call("publish_blade_clash", result.to_dict())
