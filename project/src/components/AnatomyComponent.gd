class_name AnatomyComponent
extends Node
## Component-based 4-layer anatomical damage, blood volume, vital organ integrity, shock,
## fractures, arterial bleeding, tendon tears (weapon drop / limp), dismemberment,
## weapon lodging, Anti-Regen suppression, and REG regeneration tick (STA/MP/calories).
## Implements GDD Sections 3.2 #12, 3.4, 12.4, and 14.1 (v0.2). No abstract HP bar exists.

signal blood_changed(current_ml: float, max_ml: float)
signal shock_changed(current_shock: float)
signal organ_damaged(zone: StringName, new_integrity: float)
signal limb_severed(zone: StringName, attacker: Node)
signal limb_regrown(zone: StringName)
signal organ_reconstructed(zone: StringName)
signal weapon_lodged(zone: StringName, weapon: WeaponData, attacker: Node)
signal weapon_dislodged(zone: StringName, weapon: WeaponData)
signal weapon_dropped(zone: StringName, weapon: WeaponData)
signal knocked_out(reason: String, duration_sec: float)
signal recovered_consciousness()
signal died(cause: String, zone: StringName)

enum LimbStatus {
	INTACT = 0,
	CRIPPLED = 1,
	SEVERED = 2,
}

const ZONE_HEAD: StringName = &"Head"
const ZONE_NECK: StringName = &"Neck"
const ZONE_CHEST: StringName = &"Chest"
const ZONE_STOMACH: StringName = &"Stomach"
const ZONE_LEFT_ARM: StringName = &"LeftArm"
const ZONE_RIGHT_ARM: StringName = &"RightArm"
const ZONE_LEFT_LEG: StringName = &"LeftLeg"
const ZONE_RIGHT_LEG: StringName = &"RightLeg"
const ZONE_WINGS: StringName = &"Wings"
const ZONE_TAIL: StringName = &"Tail"

const CORE_ZONES: Array[StringName] = [
	ZONE_HEAD,
	ZONE_NECK,
	ZONE_CHEST,
	ZONE_STOMACH,
	ZONE_LEFT_ARM,
	ZONE_RIGHT_ARM,
	ZONE_LEFT_LEG,
	ZONE_RIGHT_LEG,
]

const VITAL_ZONES: Array[StringName] = [
	ZONE_HEAD,
	ZONE_NECK,
	ZONE_CHEST,
]

const ARM_ZONES: Array[StringName] = [
	ZONE_LEFT_ARM,
	ZONE_RIGHT_ARM,
]

const LEG_ZONES: Array[StringName] = [
	ZONE_LEFT_LEG,
	ZONE_RIGHT_LEG,
]

const BASE_BLOOD_VOLUME_ML: float = 5000.0
const BASE_CALORIES: float = 1000.0
const BLOOD_LOSS_SEVERE_RATIO: float = 0.25
const BLOOD_LOSS_KO_RATIO: float = 0.45
const BLOOD_LOSS_DEATH_RATIO: float = 0.65

const ORGAN_DEPTH_THRESHOLD_NORMAL: float = 12.0
const ORGAN_DEPTH_THRESHOLD_WEAK_POINT: float = 6.0
const ORGAN_DAMAGE_DEPTH_SPAN: float = 15.0
const ORGAN_DAMAGE_DEPTH_SPAN_NORMAL: float = 30.0
const ORGAN_DAMAGE_DEPTH_SPAN_WEAK_POINT: float = 15.0

const BLUNT_SUBFRACTURE_SHOCK_RATIO: float = 0.55
const BLUNT_INTERNAL_BLEED_RATIO: float = 1.50
const BLUNT_ORGAN_CRUSH_RATIO_HEAD: float = 1.80
const BLUNT_ORGAN_CRUSH_RATIO_TORSO: float = 2.00
const BLUNT_MANA_SKIN_DAMP_FACTOR: float = 0.80
const BLUNT_HARDENING_DAMP_FACTOR: float = 2.50

const BLEED_DEPTH_FACTOR: float = 0.45
const FALL_BASE_IMPULSE: float = 120.0

## REG tick calibration (GDD 3.1, 3.2 #12, 3.4 #4, 14.2)
const GAME_SECONDS_PER_HOUR: float = 120.0
const BASE_CLOT_PER_SEC: float = 0.04
const COMBAT_CLOT_MIN_REG: float = 15.0
const BASE_BLOOD_REGEN_PER_SEC: float = 0.8

const SOURCE_SEVERE_BLOOD_LOSS: StringName = &"anatomy_severe_blood_loss"
const SOURCE_WOUND_PREFIX: String = "anatomy_wound_"


class BodyPart extends RefCounted:
	var zone_name: StringName = &""
	var vascular_mult: float = 1.0
	var has_vital_organ: bool = false
	var organ_integrity: float = 100.0

	# 4 anatomical tissue layers (100.0 intact -> 0.0 destroyed)
	var skin_integrity: float = 100.0
	var muscle_tendon_integrity: float = 100.0
	var bone_integrity: float = 100.0
	var vessels_organ_integrity: float = 100.0

	var limb_status: LimbStatus = LimbStatus.INTACT
	var regrowth_progress: float = 0.0
	var anti_regen_timer: float = 0.0

	var wounds: Array[WoundResource] = []
	var lodged_weapons: Array[WeaponData] = []
	var is_fractured: bool = false
	var has_tendon_tear: bool = false
	var has_arterial_bleed: bool = false


@export var size_mult: float = 1.0
@export var base_bone_density: float = 100.0
@export var has_immortal_core: bool = false

var stat_sheet: StatSheet = null
var owner_entity: Node = null

var max_blood_volume: float = BASE_BLOOD_VOLUME_ML
var blood_volume: float = BASE_BLOOD_VOLUME_ML
var shock_level: float = 0.0

# Simplified REG resource pools (STA/MP/calories, GDD 3.2 #12, 14.1 #3, 14.6)
var max_calories: float = BASE_CALORIES
var calories: float = BASE_CALORIES
var standalone_stamina: float = 150.0
var standalone_mp: float = 0.0

var global_anti_regen_timer: float = 0.0
var last_regen_active: bool = false
var last_regen_paused_reason: String = ""

var is_prone: bool = false
var has_limp: bool = false
var is_unconscious: bool = false
var knockout_reason: String = ""
var knockout_timer: float = 0.0
var is_dead: bool = false
var death_cause: String = ""
var fatal_zone: StringName = &""

var body_parts: Dictionary[StringName, BodyPart] = {}

var _wound_counter: int = 0
var _severe_blood_loss_applied: bool = false


func _init(
	p_stat_sheet: StatSheet = null,
	p_size_mult: float = 1.0,
	p_base_bone_density: float = 100.0
) -> void:
	stat_sheet = p_stat_sheet
	size_mult = maxf(0.05, p_size_mult)
	base_bone_density = maxf(1.0, p_base_bone_density)
	reset_anatomy()


func setup(
	p_stat_sheet: StatSheet,
	p_size_mult: float = 1.0,
	p_base_bone_density: float = 100.0,
	p_owner_entity: Node = null
) -> void:
	stat_sheet = p_stat_sheet
	size_mult = maxf(0.05, p_size_mult)
	base_bone_density = maxf(1.0, p_base_bone_density)
	owner_entity = p_owner_entity
	reset_anatomy()


func reset_anatomy() -> void:
	if stat_sheet != null:
		stat_sheet.remove_modifiers_by_source(SOURCE_SEVERE_BLOOD_LOSS)
		for part: BodyPart in body_parts.values():
			for w: WoundResource in part.wounds:
				_remove_wound_modifiers(w)

	body_parts.clear()
	for zone: StringName in CORE_ZONES:
		_create_zone(zone)
	for opt_zone: StringName in _optional_zones:
		if not body_parts.has(opt_zone):
			_create_zone(opt_zone)

	max_blood_volume = BASE_BLOOD_VOLUME_ML * size_mult
	blood_volume = max_blood_volume
	shock_level = 0.0
	max_calories = BASE_CALORIES * size_mult
	calories = max_calories
	refill_regen_resources()

	global_anti_regen_timer = 0.0
	last_regen_active = false
	last_regen_paused_reason = ""

	is_prone = false
	has_limp = false
	is_unconscious = false
	knockout_reason = ""
	knockout_timer = 0.0
	is_dead = false
	death_cause = ""
	fatal_zone = &""
	_severe_blood_loss_applied = false
	_wound_counter = 0


func refill_regen_resources() -> void:
	calories = max_calories
	standalone_stamina = stat_sheet.get_max_stamina() if stat_sheet != null else 150.0
	standalone_mp = stat_sheet.get_max_mp() if stat_sheet != null else 0.0


var _optional_zones: Array[StringName] = []


func add_optional_zone(zone_name: StringName) -> void:
	if not _optional_zones.has(zone_name):
		_optional_zones.append(zone_name)
	if not body_parts.has(zone_name):
		_create_zone(zone_name)


func remove_optional_zone(zone_name: StringName) -> void:
	_optional_zones.erase(zone_name)
	if body_parts.has(zone_name):
		var part: BodyPart = body_parts[zone_name]
		for w: WoundResource in part.wounds:
			_remove_wound_modifiers(w)
		body_parts.erase(zone_name)
		_recompute_limb_flags()


func has_severed_leg() -> bool:
	return is_limb_severed(ZONE_LEFT_LEG) or is_limb_severed(ZONE_RIGHT_LEG)


func _create_zone(zone_name: StringName) -> void:
	var part: BodyPart = BodyPart.new()
	part.zone_name = zone_name
	part.vascular_mult = get_zone_vascular_mult(zone_name)
	part.has_vital_organ = VITAL_ZONES.has(zone_name)
	part.organ_integrity = 100.0 if part.has_vital_organ else 0.0
	part.skin_integrity = 100.0
	part.muscle_tendon_integrity = 100.0
	part.bone_integrity = 100.0
	part.vessels_organ_integrity = 100.0
	part.limb_status = LimbStatus.INTACT
	part.regrowth_progress = 0.0
	part.anti_regen_timer = 0.0
	body_parts[zone_name] = part


# ---------------------------------------------------------------------------
# Pure Section 3.4 #5 Formula Helpers
# ---------------------------------------------------------------------------

static func get_zone_vascular_mult(zone: StringName) -> float:
	match zone:
		ZONE_NECK:
			return 2.0
		ZONE_HEAD:
			return 1.2
		ZONE_CHEST, ZONE_STOMACH:
			return 1.0
		ZONE_LEFT_ARM, ZONE_RIGHT_ARM, ZONE_LEFT_LEG, ZONE_RIGHT_LEG, ZONE_WINGS, ZONE_TAIL:
			return 0.7
		_:
			return 1.0


static func calculate_bleed_rate(
	effective_depth: float,
	zone: StringName,
	bleed_resist_mult: float = 1.0
) -> float:
	if effective_depth <= 0.0:
		return 0.0
	return effective_depth * BLEED_DEPTH_FACTOR * get_zone_vascular_mult(zone) * clampf(bleed_resist_mult, 0.10, 1.0)


static func calculate_organ_depth_threshold(p_size_mult: float, is_weak_point: bool) -> float:
	var base_thresh: float = ORGAN_DEPTH_THRESHOLD_WEAK_POINT if is_weak_point else ORGAN_DEPTH_THRESHOLD_NORMAL
	return base_thresh * maxf(0.05, p_size_mult)


static func calculate_organ_damage_pct(
	effective_depth: float,
	p_size_mult: float,
	is_weak_point: bool
) -> float:
	var safe_size: float = maxf(0.05, p_size_mult)
	var threshold: float = calculate_organ_depth_threshold(safe_size, is_weak_point)
	if effective_depth < threshold:
		return 0.0
	var span: float = ORGAN_DAMAGE_DEPTH_SPAN_WEAK_POINT if is_weak_point else ORGAN_DAMAGE_DEPTH_SPAN_NORMAL
	var raw_pct: float = ((effective_depth - threshold) / (span * safe_size)) * 100.0
	return clampf(raw_pct, 0.0, 100.0)


static func calculate_penetrating_shock(effective_depth: float, con_value: float) -> float:
	if effective_depth <= 0.0:
		return 0.0
	return clampf(effective_depth * 1.2, 2.0, 45.0) * (10.0 / maxf(10.0, con_value))


static func calculate_blunt_shock(blunt_impulse: float, effective_bone_density: float) -> float:
	return clampf((blunt_impulse / maxf(1.0, effective_bone_density)) * 35.0, 5.0, 80.0)


static func calculate_fall_impulse(
	p_size_mult: float,
	agi_value: float,
	floors_fallen: int = 1
) -> float:
	var agi_mult: float = clampf(1.0 - (agi_value - 10.0) * 0.008, 0.25, 1.0)
	return FALL_BASE_IMPULSE * maxf(0.05, p_size_mult) * agi_mult * float(maxi(1, floors_fallen))


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

func has_zone(zone: StringName) -> bool:
	return body_parts.has(zone)


func get_body_part(zone: StringName) -> BodyPart:
	if not body_parts.has(zone):
		return null
	return body_parts[zone]


func get_zone_names() -> Array[StringName]:
	var names: Array[StringName] = []
	for k: StringName in body_parts.keys():
		names.append(k)
	return names


func get_limb_status(zone: StringName) -> LimbStatus:
	if not body_parts.has(zone):
		return LimbStatus.INTACT
	return body_parts[zone].limb_status


func is_limb_severed(zone: StringName) -> bool:
	return get_limb_status(zone) == LimbStatus.SEVERED


func get_layer_integrities(zone: StringName) -> Dictionary:
	if not body_parts.has(zone):
		return {}
	var part: BodyPart = body_parts[zone]
	return {
		"skin": part.skin_integrity,
		"muscle_tendon": part.muscle_tendon_integrity,
		"bone": part.bone_integrity,
		"vessels_organ": part.vessels_organ_integrity,
	}


func get_organ_integrity(zone: StringName) -> float:
	if not body_parts.has(zone):
		return 0.0
	return body_parts[zone].organ_integrity


func get_all_organ_integrities() -> Dictionary[StringName, float]:
	var result: Dictionary[StringName, float] = {}
	for zone: StringName in VITAL_ZONES:
		if body_parts.has(zone):
			result[zone] = body_parts[zone].organ_integrity
	return result


func get_wounds(zone: StringName) -> Array[WoundResource]:
	if not body_parts.has(zone):
		return []
	return body_parts[zone].wounds.duplicate()


func get_all_wounds() -> Array[WoundResource]:
	var all: Array[WoundResource] = []
	for part: BodyPart in body_parts.values():
		for w: WoundResource in part.wounds:
			all.append(w)
	return all


func get_lodged_weapons(zone: StringName) -> Array[WeaponData]:
	if not body_parts.has(zone):
		return []
	return body_parts[zone].lodged_weapons.duplicate()


func has_lodged_weapon(zone: StringName = &"") -> bool:
	if zone != &"":
		return body_parts.has(zone) and not body_parts[zone].lodged_weapons.is_empty()
	for part: BodyPart in body_parts.values():
		if not part.lodged_weapons.is_empty():
			return true
	return false


func has_fracture(zone: StringName) -> bool:
	if not body_parts.has(zone):
		return false
	return body_parts[zone].is_fractured


func has_arterial_bleeding(zone: StringName = &"") -> bool:
	if zone != &"":
		return body_parts.has(zone) and body_parts[zone].has_arterial_bleed
	for part: BodyPart in body_parts.values():
		if part.has_arterial_bleed:
			return true
	return false


func has_tendon_tear(zone: StringName) -> bool:
	if not body_parts.has(zone):
		return false
	return body_parts[zone].has_tendon_tear


func is_anti_regen_active(zone: StringName = &"") -> bool:
	if global_anti_regen_timer > 0.0:
		return true
	if zone == &"":
		for part: BodyPart in body_parts.values():
			if part.anti_regen_timer > 0.0:
				return true
			for w: WoundResource in part.wounds:
				if w.is_anti_regen_active():
					return true
		return false
	if body_parts.has(zone):
		var part: BodyPart = body_parts[zone]
		if part.anti_regen_timer > 0.0:
			return true
		for w: WoundResource in part.wounds:
			if w.is_anti_regen_active():
				return true
	return false


func get_total_bleed_rate() -> float:
	var total: float = 0.0
	for part: BodyPart in body_parts.values():
		for w: WoundResource in part.wounds:
			total += w.get_effective_bleed_rate()
	return total


func get_blood_ratio() -> float:
	return clampf(blood_volume / maxf(1.0, max_blood_volume), 0.0, 1.0)


func get_blood_loss_ratio() -> float:
	return clampf((max_blood_volume - blood_volume) / maxf(1.0, max_blood_volume), 0.0, 1.0)


func is_severe_blood_loss() -> bool:
	return get_blood_loss_ratio() > BLOOD_LOSS_SEVERE_RATIO


func get_effective_bone_density() -> float:
	var mult: float = stat_sheet.get_bone_density_mult() if stat_sheet != null else 1.0
	return base_bone_density * mult


## Total blunt fracture threshold combining CON-scaled bone density, armor cushioning,
## external Mana Skin damping, and active Hardening guard.
func get_blunt_resistance_threshold(
	armor_cushion_mult: float = 1.0,
	hardening_bonus: float = 0.0
) -> float:
	var eff_bone: float = get_effective_bone_density()
	var mana_skin: float = stat_sheet.get_mana_skin_density() if stat_sheet != null else 0.0
	return (
		eff_bone * maxf(0.01, armor_cushion_mult)
		+ maxf(0.0, mana_skin) * BLUNT_MANA_SKIN_DAMP_FACTOR
		+ maxf(0.0, hardening_bonus) * BLUNT_HARDENING_DAMP_FACTOR
	)


# ---------------------------------------------------------------------------
# Damage Application (4-Barrier Damage-to-Wound, GDD Sections 3.4 #5-6, 12.4)
# ---------------------------------------------------------------------------

func apply_penetration_result(
	zone: StringName,
	resolution: PenetrationResolver.ResolutionResult,
	armor_cushion_mult: float = 1.0,
	attacker: Node = null,
	weapon: WeaponData = null,
	target_equipped_weapon: WeaponData = null
) -> Dictionary:
	var summary: Dictionary = {
		"cancelled": false,
		"zone": zone,
		"penetrated": false,
		"bleed_added": 0.0,
		"organ_damage_pct": 0.0,
		"fractured": false,
		"shock_added": 0.0,
		"severed": false,
		"weapon_lodged": false,
		"tendon_torn": false,
		"weapon_dropped": false,
		"causes_limp": false,
		"arterial_bleed": false,
		"anti_regen_applied": false,
		"wounds_created": [],
	}
	if is_dead or resolution == null or not body_parts.has(zone):
		return summary

	var pipeline_ctx: Dictionary = {
		"attacker": attacker,
		"target": _get_owner_entity(),
		"zone": zone,
		"effective_depth": resolution.effective_depth,
		"blunt_impulse": resolution.blunt_impulse,
		"is_weak_point": resolution.is_weak_point,
		"severed": resolution.severed,
		"weapon_lodged": resolution.weapon_lodged,
		"anti_regen": resolution.anti_regen,
		"bleed_mult": 1.0,
		"shock_mult": 1.0,
		"cancelled": false,
	}
	var bus: Node = _get_event_bus()
	if bus != null and bus.has_method("run_damage_pipeline"):
		pipeline_ctx = bus.call("run_damage_pipeline", pipeline_ctx)
	if bool(pipeline_ctx.get("cancelled", false)):
		summary["cancelled"] = true
		return summary

	var eff_depth: float = maxf(0.0, float(pipeline_ctx.get("effective_depth", 0.0)))
	var b_impulse: float = maxf(0.0, float(pipeline_ctx.get("blunt_impulse", 0.0)))
	var is_wp: bool = bool(pipeline_ctx.get("is_weak_point", false))
	var bleed_mult: float = maxf(0.0, float(pipeline_ctx.get("bleed_mult", 1.0)))
	var shock_mult: float = maxf(0.0, float(pipeline_ctx.get("shock_mult", 1.0)))
	var do_sever: bool = bool(pipeline_ctx.get("severed", false))
	var do_lodge: bool = bool(pipeline_ctx.get("weapon_lodged", false))
	var do_anti_regen: bool = bool(pipeline_ctx.get("anti_regen", false))

	# Physical Dismemberment / Severing on SLASH exceeding sever_threshold
	if do_sever and eff_depth > 0.0:
		if do_anti_regen:
			apply_anti_regen(zone, maxf(1.0, resolution.anti_regen_duration_sec), false)
			summary["anti_regen_applied"] = true
		var sev_report: Dictionary = sever_limb(zone, attacker, do_anti_regen, target_equipped_weapon)
		summary["penetrated"] = true
		summary["severed"] = bool(sev_report.get("severed", false))
		summary["arterial_bleed"] = summary["severed"]
		summary["weapon_dropped"] = bool(sev_report.get("weapon_dropped", false))
		summary["bleed_added"] = float(sev_report.get("bleed_added", 0.0))
		summary["shock_added"] = float(sev_report.get("shock_added", 0.0))
		if sev_report.get("wound", null) != null:
			(summary["wounds_created"] as Array).append(sev_report["wound"])
		return summary

	if eff_depth > 0.0:
		if do_anti_regen:
			apply_anti_regen(zone, maxf(1.0, resolution.anti_regen_duration_sec), false)
			summary["anti_regen_applied"] = true
		var part: BodyPart = body_parts[zone]
		_apply_four_layer_damage(part, resolution, eff_depth)

		var pen_report: Dictionary = apply_penetrating_hit(zone, eff_depth, is_wp, bleed_mult, shock_mult)
		summary["penetrated"] = true
		summary["bleed_added"] = float(pen_report.get("bleed_added", 0.0))
		summary["organ_damage_pct"] = float(pen_report.get("organ_damage_pct", 0.0))
		summary["shock_added"] = float(summary["shock_added"]) + float(pen_report.get("shock_added", 0.0))
		var created_w: WoundResource = pen_report.get("wound", null) as WoundResource
		if created_w != null:
			created_w.tissue_layer = int(resolution.deepest_barrier_reached)
			if do_anti_regen:
				created_w.anti_regen = true
				created_w.anti_regen_timer = maxf(1.0, resolution.anti_regen_duration_sec)
			if resolution.arterial_hit:
				created_w.is_arterial = true
				created_w.wound_type = WoundResource.WoundType.ARTERIAL_BLEED
				created_w.display_name = "Arterial Bleed"
				part.has_arterial_bleed = true
				summary["arterial_bleed"] = true
			(summary["wounds_created"] as Array).append(created_w)

		# Tendon tear check (Arms -> grip loss / weapon drop; Legs -> Limp)
		if not is_dead and resolution.tendon_severed and (ARM_ZONES.has(zone) or LEG_ZONES.has(zone)):
			var td_res: Dictionary = apply_tendon_tear(zone, eff_depth, target_equipped_weapon)
			summary["tendon_torn"] = true
			summary["weapon_dropped"] = bool(td_res.get("weapon_dropped", false))
			summary["causes_limp"] = bool(td_res.get("causes_limp", false))
			if td_res.get("wound", null) != null:
				(summary["wounds_created"] as Array).append(td_res["wound"])

		# Blade lodging check (LodgedWeapon — never lodges bare fists)
		if not is_dead and do_lodge and (weapon == null or not weapon.is_unarmed):
			var lodge_w: WoundResource = lodge_weapon(zone, weapon, attacker, eff_depth)
			if lodge_w != null:
				summary["weapon_lodged"] = true
				(summary["wounds_created"] as Array).append(lodge_w)

	if not is_dead and b_impulse > 0.0:
		var blunt_report: Dictionary = apply_blunt_hit(zone, b_impulse, armor_cushion_mult, shock_mult, true, resolution.hardening_bonus)
		summary["fractured"] = bool(blunt_report.get("fractured", false))
		summary["shock_added"] = float(summary["shock_added"]) + float(blunt_report.get("shock_added", 0.0))
		summary["organ_damage_pct"] = float(summary["organ_damage_pct"]) + float(blunt_report.get("organ_damage_pct", 0.0))
		summary["bleed_added"] = float(summary["bleed_added"]) + float(blunt_report.get("internal_bleed_added", 0.0))
		if do_anti_regen and bool(summary["fractured"]) and not bool(summary["anti_regen_applied"]):
			apply_anti_regen(zone, maxf(1.0, resolution.anti_regen_duration_sec), false)
			summary["anti_regen_applied"] = true
		if blunt_report.get("wound", null) != null:
			(summary["wounds_created"] as Array).append(blunt_report["wound"])
		if blunt_report.get("internal_wound", null) != null:
			(summary["wounds_created"] as Array).append(blunt_report["internal_wound"])

	return summary


func _apply_four_layer_damage(
	part: BodyPart,
	resolution: PenetrationResolver.ResolutionResult,
	eff_depth: float
) -> void:
	if part.limb_status == LimbStatus.SEVERED:
		return
	var scale: float = clampf(eff_depth / (15.0 * maxf(0.25, size_mult)), 0.05, 1.0)
	if resolution.skin_breached:
		part.skin_integrity = clampf(part.skin_integrity - (20.0 + 45.0 * scale), 0.0, 100.0)
	if resolution.muscle_tendon_breached:
		part.muscle_tendon_integrity = clampf(part.muscle_tendon_integrity - (25.0 + 50.0 * scale), 0.0, 100.0)
	if resolution.bone_vessel_breached:
		part.vessels_organ_integrity = clampf(part.vessels_organ_integrity - (30.0 + 50.0 * scale), 0.0, 100.0)
		part.bone_integrity = clampf(part.bone_integrity - (15.0 + 35.0 * scale), 0.0, 100.0)


func apply_penetrating_hit(
	zone: StringName,
	effective_depth: float,
	is_weak_point: bool = false,
	extra_bleed_mult: float = 1.0,
	extra_shock_mult: float = 1.0
) -> Dictionary:
	var report: Dictionary = {
		"zone": zone,
		"bleed_added": 0.0,
		"organ_damage_pct": 0.0,
		"shock_added": 0.0,
		"wound": null,
	}
	if is_dead or effective_depth <= 0.0 or not body_parts.has(zone):
		return report

	var con_val: float = stat_sheet.get_stat(StatSheet.Stat.CON) if stat_sheet != null else 10.0
	var bleed_resist: float = stat_sheet.get_bleed_resist_mult() if stat_sheet != null else 1.0

	var bleed_rate: float = calculate_bleed_rate(effective_depth, zone, bleed_resist) * maxf(0.0, extra_bleed_mult)
	var shock_gain: float = calculate_penetrating_shock(effective_depth, con_val) * maxf(0.0, extra_shock_mult)

	var wound: WoundResource = WoundResource.new()
	wound.body_zone = zone
	wound.severity = effective_depth
	wound.bleed_rate_ml_per_sec = bleed_rate
	wound.initial_shock = shock_gain

	var part: BodyPart = body_parts[zone]
	if effective_depth < 3.0:
		wound.wound_id = &"scratch"
		wound.display_name = "Scratch"
		wound.wound_type = WoundResource.WoundType.SCRATCH
		wound.tissue_layer = int(PenetrationResolver.TissueBarrier.SKIN)
		wound.heal_duration_game_hours = 12.0
		part.skin_integrity = clampf(part.skin_integrity - 15.0, 0.0, 100.0)
	elif effective_depth < 10.0:
		wound.wound_id = &"cut"
		wound.display_name = "Cut"
		wound.wound_type = WoundResource.WoundType.CUT
		wound.tissue_layer = int(PenetrationResolver.TissueBarrier.MUSCLE_TENDON)
		wound.heal_duration_game_hours = 24.0
		part.skin_integrity = clampf(part.skin_integrity - 30.0, 0.0, 100.0)
		part.muscle_tendon_integrity = clampf(part.muscle_tendon_integrity - 20.0, 0.0, 100.0)
	else:
		wound.wound_id = &"deep_wound"
		wound.display_name = "Deep Wound"
		wound.wound_type = WoundResource.WoundType.DEEP_WOUND
		wound.tissue_layer = int(PenetrationResolver.TissueBarrier.BONE_VESSEL_ORGAN)
		wound.heal_duration_game_hours = 72.0
		part.skin_integrity = clampf(part.skin_integrity - 45.0, 0.0, 100.0)
		part.muscle_tendon_integrity = clampf(part.muscle_tendon_integrity - 40.0, 0.0, 100.0)
		_populate_limb_wound_penalties(wound, zone, false)

	add_wound(zone, wound, false)
	_add_shock(shock_gain)

	report["bleed_added"] = bleed_rate
	report["shock_added"] = shock_gain
	report["wound"] = wound

	# Vital organ damage check (Head, Neck, Chest)
	if part.has_vital_organ:
		var organ_dmg: float = calculate_organ_damage_pct(effective_depth, size_mult, is_weak_point)
		if organ_dmg > 0.0:
			part.organ_integrity = clampf(part.organ_integrity - organ_dmg, 0.0, 100.0)
			part.vessels_organ_integrity = part.organ_integrity
			report["organ_damage_pct"] = organ_dmg
			organ_damaged.emit(zone, part.organ_integrity)
			if part.organ_integrity <= 0.0 and not has_immortal_core:
				if not _can_survive_organ_destruction(zone):
					_trigger_death("vital_organ_destroyed", zone)

	if not is_dead:
		_evaluate_thresholds()

	return report


func apply_blunt_hit(
	zone: StringName,
	blunt_impulse: float,
	armor_cushion_mult: float = 1.0,
	extra_shock_mult: float = 1.0,
	apply_shock: bool = true,
	hardening_bonus: float = 0.0
) -> Dictionary:
	var report: Dictionary = {
		"zone": zone,
		"fractured": false,
		"shock_added": 0.0,
		"organ_damage_pct": 0.0,
		"internal_bleed_added": 0.0,
		"wound": null,
		"internal_wound": null,
	}
	if is_dead or blunt_impulse <= 0.0 or not body_parts.has(zone):
		return report

	var threshold: float = get_blunt_resistance_threshold(armor_cushion_mult, hardening_bonus)
	var ratio: float = blunt_impulse / maxf(1.0, threshold)

	# Sub-fracture concussive rattle/bruising when hit carries substantial blunt force
	if blunt_impulse <= threshold:
		if ratio >= BLUNT_SUBFRACTURE_SHOCK_RATIO and apply_shock:
			var rattle_shock: float = clampf((ratio - BLUNT_SUBFRACTURE_SHOCK_RATIO) * 32.0, 2.0, 18.0) * maxf(0.0, extra_shock_mult)
			_add_shock(rattle_shock)
			report["shock_added"] = rattle_shock
			if not is_dead:
				_evaluate_thresholds()
		return report

	var part: BodyPart = body_parts[zone]
	var shock_gain: float = calculate_blunt_shock(blunt_impulse, threshold) * maxf(0.0, extra_shock_mult)
	var wound: WoundResource = WoundResource.new()
	wound.wound_id = &"fracture"
	wound.display_name = "Fracture"
	wound.wound_type = WoundResource.WoundType.FRACTURE
	wound.tissue_layer = int(PenetrationResolver.TissueBarrier.BONE_VESSEL_ORGAN)
	wound.body_zone = zone
	wound.severity = ratio
	wound.bleed_rate_ml_per_sec = 0.0
	wound.initial_shock = shock_gain
	wound.heal_duration_game_hours = 168.0 # 7 game days (GDD 3.4 #4: 5-10 days)
	if LEG_ZONES.has(zone):
		wound.causes_limp = true
	_populate_limb_wound_penalties(wound, zone, true)

	part.bone_integrity = clampf(part.bone_integrity - clampf(wound.severity * 45.0, 35.0, 100.0), 0.0, 100.0)
	if part.limb_status == LimbStatus.INTACT and (ARM_ZONES.has(zone) or LEG_ZONES.has(zone) or zone == ZONE_WINGS):
		part.limb_status = LimbStatus.CRIPPLED

	add_wound(zone, wound, false)
	report["fractured"] = true
	report["wound"] = wound
	if apply_shock:
		_add_shock(shock_gain)
		report["shock_added"] = shock_gain

	# Severe crushing blunt excess (>= 1.5x threshold) on Head/Neck/Chest/Stomach causes
	# Internal Hemorrhage and (>= 1.8x-2.0x) direct crushing damage to vital organs!
	var is_torso_or_head: bool = (
		zone == ZONE_HEAD
		or zone == ZONE_NECK
		or zone == ZONE_CHEST
		or zone == ZONE_STOMACH
	)
	if is_torso_or_head and ratio >= BLUNT_INTERNAL_BLEED_RATIO:
		var bleed_resist: float = stat_sheet.get_bleed_resist_mult() if stat_sheet != null else 1.0
		var internal_rate: float = clampf((ratio - 1.30) * 3.5, 1.5, 18.0) * part.vascular_mult * bleed_resist
		var hem: WoundResource = WoundResource.new()
		hem.wound_id = &"internal_hemorrhage"
		hem.display_name = "Internal Hemorrhage"
		hem.wound_type = WoundResource.WoundType.DEEP_WOUND
		hem.tissue_layer = int(PenetrationResolver.TissueBarrier.BONE_VESSEL_ORGAN)
		hem.body_zone = zone
		hem.severity = ratio * 10.0
		hem.bleed_rate_ml_per_sec = internal_rate
		hem.heal_duration_game_hours = 96.0
		part.vessels_organ_integrity = clampf(part.vessels_organ_integrity - clampf((ratio - 1.30) * 24.0, 10.0, 100.0), 0.0, 100.0)
		add_wound(zone, hem, false)
		report["internal_bleed_added"] = internal_rate
		report["internal_wound"] = hem

	if part.has_vital_organ:
		var crush_ratio_min: float = BLUNT_ORGAN_CRUSH_RATIO_HEAD if zone == ZONE_HEAD else BLUNT_ORGAN_CRUSH_RATIO_TORSO
		if ratio >= crush_ratio_min:
			var crush_slope: float = 60.0 if zone == ZONE_HEAD else (55.0 if zone == ZONE_NECK else 38.0)
			var organ_dmg: float = clampf((ratio - crush_ratio_min) * crush_slope + 12.0, 12.0, 100.0)
			part.organ_integrity = clampf(part.organ_integrity - organ_dmg, 0.0, 100.0)
			part.vessels_organ_integrity = minf(part.vessels_organ_integrity, part.organ_integrity)
			report["organ_damage_pct"] = organ_dmg
			organ_damaged.emit(zone, part.organ_integrity)
			if part.organ_integrity <= 0.0 and not has_immortal_core:
				if not _can_survive_organ_destruction(zone):
					_trigger_death("vital_organ_destroyed", zone)

	_recompute_limb_flags()
	if not is_dead:
		_evaluate_thresholds()

	return report


func apply_fall_damage(floors_fallen: int = 1, armor_cushion_mult: float = 1.0) -> Dictionary:
	var agi_val: float = stat_sheet.get_stat(StatSheet.Stat.AGI) if stat_sheet != null else 10.0
	var impulse: float = calculate_fall_impulse(size_mult, agi_val, floors_fallen)
	var fractured_zones: Array[StringName] = []
	var shock_added: float = 0.0

	var left_res: Dictionary = apply_blunt_hit(ZONE_LEFT_LEG, impulse, armor_cushion_mult, 1.0, true)
	if bool(left_res.get("fractured", false)):
		fractured_zones.append(ZONE_LEFT_LEG)
		shock_added = float(left_res.get("shock_added", 0.0))

	# Apply matching structural fracture check to RightLeg without double-counting the single fall's shock spike
	var right_res: Dictionary = apply_blunt_hit(ZONE_RIGHT_LEG, impulse, armor_cushion_mult, 1.0, false)
	if bool(right_res.get("fractured", false)):
		fractured_zones.append(ZONE_RIGHT_LEG)

	return {
		"fall_impulse": impulse,
		"fractured": not fractured_zones.is_empty(),
		"fractured_zones": fractured_zones,
		"shock_added": shock_added,
	}


# ---------------------------------------------------------------------------
# v0.2 Specialized Trauma: Arterial Bleed, Tendon Tear, Dismemberment,
# Weapon Lodging, and Anti-Regen (GDD Sections 3.4 #6 & 12.4)
# ---------------------------------------------------------------------------

func apply_arterial_bleed(
	zone: StringName,
	base_rate_ml_per_sec: float = 12.0,
	anti_regen: bool = false,
	anti_regen_duration: float = 8.0
) -> WoundResource:
	if is_dead or not body_parts.has(zone):
		return null
	var bleed_resist: float = stat_sheet.get_bleed_resist_mult() if stat_sheet != null else 1.0
	var wound: WoundResource = WoundResource.new()
	wound.wound_id = &"arterial_bleed"
	wound.display_name = "Arterial Bleed"
	wound.wound_type = WoundResource.WoundType.ARTERIAL_BLEED
	wound.tissue_layer = int(PenetrationResolver.TissueBarrier.BONE_VESSEL_ORGAN)
	wound.body_zone = zone
	wound.severity = base_rate_ml_per_sec
	wound.is_arterial = true
	wound.bleed_rate_ml_per_sec = maxf(1.0, base_rate_ml_per_sec) * get_zone_vascular_mult(zone) * bleed_resist
	wound.heal_duration_game_hours = 72.0
	wound.anti_regen = anti_regen
	wound.anti_regen_timer = anti_regen_duration if anti_regen else 0.0

	var part: BodyPart = body_parts[zone]
	part.vessels_organ_integrity = clampf(part.vessels_organ_integrity - 40.0, 0.0, 100.0)
	part.has_arterial_bleed = true
	if anti_regen:
		part.anti_regen_timer = maxf(part.anti_regen_timer, anti_regen_duration)
	return add_wound(zone, wound, false)


func apply_tendon_tear(
	zone: StringName,
	severity: float = 8.0,
	equipped_weapon_ref: WeaponData = null
) -> Dictionary:
	var result: Dictionary = {
		"wound": null,
		"weapon_dropped": false,
		"causes_limp": false,
	}
	if is_dead or not body_parts.has(zone):
		return result

	var part: BodyPart = body_parts[zone]
	var wound: WoundResource = WoundResource.new()
	wound.wound_id = &"tendon_tear"
	wound.display_name = "Tendon Tear"
	wound.wound_type = WoundResource.WoundType.TENDON_TEAR
	wound.tissue_layer = int(PenetrationResolver.TissueBarrier.MUSCLE_TENDON)
	wound.body_zone = zone
	wound.severity = severity
	wound.heal_duration_game_hours = 96.0

	if ARM_ZONES.has(zone):
		wound.causes_grip_loss = true
		wound.stat_penalties[StatSheet.Stat.STR] = 0.65
		wound.stat_penalties[StatSheet.Stat.CTRL] = 0.60
		result["weapon_dropped"] = true
	elif LEG_ZONES.has(zone):
		wound.causes_limp = true
		wound.stat_penalties[StatSheet.Stat.SPD] = 0.55
		wound.stat_penalties[StatSheet.Stat.AGI] = 0.45
		if not wound.stat_penalty_tags.has(StatSheet.TAG_LEG_LOCOMOTION):
			wound.stat_penalty_tags.append(StatSheet.TAG_LEG_LOCOMOTION)
		result["causes_limp"] = true

	part.muscle_tendon_integrity = clampf(part.muscle_tendon_integrity - 45.0, 0.0, 100.0)
	part.has_tendon_tear = true
	if part.limb_status == LimbStatus.INTACT and (ARM_ZONES.has(zone) or LEG_ZONES.has(zone) or zone == ZONE_WINGS):
		part.limb_status = LimbStatus.CRIPPLED

	add_wound(zone, wound, false)
	result["wound"] = wound
	_recompute_limb_flags()

	if bool(result["weapon_dropped"]):
		weapon_dropped.emit(zone, equipped_weapon_ref)
		var bus: Node = _get_event_bus()
		if bus != null:
			bus.emit_signal("weapon_dropped", _get_owner_entity(), zone, equipped_weapon_ref)

	return result


## Physical Dismemberment / Severing of limbs or neck (GDD 3.4 #6, 12.4).
func sever_limb(
	zone: StringName,
	attacker: Node = null,
	anti_regen: bool = false,
	equipped_weapon_ref: WeaponData = null
) -> Dictionary:
	var report: Dictionary = {
		"severed": false,
		"zone": zone,
		"bleed_added": 0.0,
		"shock_added": 0.0,
		"weapon_dropped": false,
		"wound": null,
	}
	if is_dead or not body_parts.has(zone):
		return report
	if not PenetrationResolver.SEVERABLE_ZONES.has(zone):
		return report

	var part: BodyPart = body_parts[zone]
	if part.limb_status == LimbStatus.SEVERED:
		return report

	part.limb_status = LimbStatus.SEVERED
	part.regrowth_progress = 0.0
	part.skin_integrity = 0.0
	part.muscle_tendon_integrity = 0.0
	part.bone_integrity = 0.0
	part.vessels_organ_integrity = 0.0
	part.is_fractured = false
	part.has_arterial_bleed = true

	var con_val: float = stat_sheet.get_stat(StatSheet.Stat.CON) if stat_sheet != null else 10.0
	var bleed_resist: float = stat_sheet.get_bleed_resist_mult() if stat_sheet != null else 1.0
	var bleed_rate: float = 15.0 * part.vascular_mult * bleed_resist
	var shock_gain: float = clampf(55.0 * (10.0 / maxf(10.0, con_val)), 10.0, 75.0)

	var stump: WoundResource = WoundResource.new()
	stump.wound_id = &"severed_stump"
	stump.display_name = "Severed %s" % String(zone)
	stump.wound_type = WoundResource.WoundType.SEVERED_STUMP
	stump.tissue_layer = int(PenetrationResolver.TissueBarrier.BONE_VESSEL_ORGAN)
	stump.body_zone = zone
	stump.severity = 100.0
	stump.is_arterial = true
	stump.bleed_rate_ml_per_sec = bleed_rate
	stump.initial_shock = shock_gain
	stump.heal_duration_game_hours = 99999.0 # Requires REG >= 150 regrowth
	stump.anti_regen = anti_regen
	if anti_regen:
		stump.anti_regen_timer = 10.0
		part.anti_regen_timer = maxf(part.anti_regen_timer, 10.0)

	if LEG_ZONES.has(zone):
		stump.causes_limp = true
		stump.stat_penalties[StatSheet.Stat.SPD] = 0.20
		stump.stat_penalties[StatSheet.Stat.AGI] = 0.20
		if not stump.stat_penalty_tags.has(StatSheet.TAG_LEG_LOCOMOTION):
			stump.stat_penalty_tags.append(StatSheet.TAG_LEG_LOCOMOTION)
		is_prone = true
	elif ARM_ZONES.has(zone):
		stump.causes_grip_loss = true
		stump.stat_penalties[StatSheet.Stat.STR] = 0.55
		stump.stat_penalties[StatSheet.Stat.CTRL] = 0.55
		report["weapon_dropped"] = true

	add_wound(zone, stump, false)
	_add_shock(shock_gain)

	report["severed"] = true
	report["bleed_added"] = bleed_rate
	report["shock_added"] = shock_gain
	report["wound"] = stump

	limb_severed.emit(zone, attacker)
	var bus: Node = _get_event_bus()
	if bus != null:
		bus.emit_signal("limb_severed", _get_owner_entity(), zone, attacker)

	if bool(report["weapon_dropped"]):
		weapon_dropped.emit(zone, equipped_weapon_ref)
		if bus != null:
			bus.emit_signal("weapon_dropped", _get_owner_entity(), zone, equipped_weapon_ref)

	# Decapitation (Neck severed) -> instant death unless immortal core
	if zone == ZONE_NECK:
		part.organ_integrity = 0.0
		organ_damaged.emit(ZONE_NECK, 0.0)
		if not has_immortal_core:
			_trigger_death("decapitation", ZONE_NECK)

	_recompute_limb_flags()
	if not is_dead:
		_evaluate_thresholds()

	return report


## Lodges a blade/weapon into a body part's dense/hardened muscle tissue (GDD 3.4 #6, 12.2).
func lodge_weapon(
	zone: StringName,
	weapon: WeaponData,
	attacker: Node = null,
	depth: float = 6.0
) -> WoundResource:
	if is_dead or not body_parts.has(zone):
		return null
	var part: BodyPart = body_parts[zone]
	var bleed_resist: float = stat_sheet.get_bleed_resist_mult() if stat_sheet != null else 1.0

	var wound: WoundResource = WoundResource.new()
	wound.wound_id = &"lodged_weapon"
	wound.display_name = "Lodged %s" % (weapon.display_name if weapon != null and weapon.display_name != "" else "Blade")
	wound.wound_type = WoundResource.WoundType.LODGED_WEAPON
	wound.tissue_layer = int(PenetrationResolver.TissueBarrier.MUSCLE_TENDON)
	wound.body_zone = zone
	wound.severity = maxf(1.0, depth)
	wound.bleed_rate_ml_per_sec = maxf(1.5, depth * 0.35) * part.vascular_mult * bleed_resist
	wound.heal_duration_game_hours = 99999.0 # Must be extracted first
	wound.lodged_weapon = weapon
	wound.stat_penalties[StatSheet.Stat.SPD] = 0.75
	wound.stat_penalties[StatSheet.Stat.AGI] = 0.75

	if weapon != null:
		part.lodged_weapons.append(weapon)
	add_wound(zone, wound, false)

	weapon_lodged.emit(zone, weapon, attacker)
	var bus: Node = _get_event_bus()
	if bus != null:
		bus.emit_signal("weapon_lodged", _get_owner_entity(), zone, weapon, attacker)
	return wound


## Extracts a lodged weapon from a body part; rough extraction adds rip bleed & shock.
func dislodge_weapon(zone: StringName, careful: bool = false) -> Dictionary:
	var result: Dictionary = {
		"extracted": false,
		"weapon": null,
		"ripped_bleed": 0.0,
		"shock_added": 0.0,
	}
	if not body_parts.has(zone):
		return result
	var part: BodyPart = body_parts[zone]

	var found_idx: int = -1
	for i: int in range(part.wounds.size() - 1, -1, -1):
		if part.wounds[i].wound_type == WoundResource.WoundType.LODGED_WEAPON:
			found_idx = i
			break
	if found_idx < 0:
		return result

	var lodge_w: WoundResource = part.wounds[found_idx]
	var wpn: WeaponData = lodge_w.lodged_weapon
	_remove_wound_modifiers(lodge_w)
	part.wounds.remove_at(found_idx)
	if wpn != null:
		var w_idx: int = part.lodged_weapons.rfind(wpn)
		if w_idx >= 0:
			part.lodged_weapons.remove_at(w_idx)
	elif not part.lodged_weapons.is_empty():
		wpn = part.lodged_weapons.pop_back()

	result["extracted"] = true
	result["weapon"] = wpn

	if not careful and not is_dead:
		var bleed_resist: float = stat_sheet.get_bleed_resist_mult() if stat_sheet != null else 1.0
		var con_val: float = stat_sheet.get_stat(StatSheet.Stat.CON) if stat_sheet != null else 10.0
		var rip_bleed: float = 4.0 * part.vascular_mult * bleed_resist
		var rip_shock: float = clampf(15.0 * (10.0 / maxf(10.0, con_val)), 3.0, 25.0)
		var rip_w: WoundResource = WoundResource.new()
		rip_w.wound_id = &"extraction_tear"
		rip_w.display_name = "Extraction Tear"
		rip_w.wound_type = WoundResource.WoundType.CUT
		rip_w.tissue_layer = int(PenetrationResolver.TissueBarrier.MUSCLE_TENDON)
		rip_w.body_zone = zone
		rip_w.bleed_rate_ml_per_sec = rip_bleed
		rip_w.heal_duration_game_hours = 24.0
		add_wound(zone, rip_w, false)
		_add_shock(rip_shock)
		result["ripped_bleed"] = rip_bleed
		result["shock_added"] = rip_shock

	weapon_dislodged.emit(zone, wpn)
	var bus: Node = _get_event_bus()
	if bus != null:
		bus.emit_signal("weapon_dislodged", _get_owner_entity(), zone, wpn)
	return result


## Applies Anti-Regen suppression (fire burn / suppressing Aura / MindDomain) halting REG.
func apply_anti_regen(zone: StringName, duration_sec: float = 10.0, is_global: bool = false) -> void:
	if duration_sec <= 0.0:
		return
	if is_global or zone == &"":
		global_anti_regen_timer = maxf(global_anti_regen_timer, duration_sec)
	elif body_parts.has(zone):
		var part: BodyPart = body_parts[zone]
		part.anti_regen_timer = maxf(part.anti_regen_timer, duration_sec)
		for w: WoundResource in part.wounds:
			w.anti_regen = true
			w.anti_regen_timer = maxf(w.anti_regen_timer, duration_sec)
	var bus: Node = _get_event_bus()
	if bus != null:
		bus.emit_signal("anti_regen_applied", _get_owner_entity(), zone, duration_sec)


func apply_burn_anti_regen(zone: StringName, duration_sec: float = 12.0) -> WoundResource:
	if is_dead or not body_parts.has(zone):
		return null
	var burn: WoundResource = WoundResource.new()
	burn.wound_id = &"burn_anti_regen"
	burn.display_name = "Seared Burn (Anti-Regen)"
	burn.wound_type = WoundResource.WoundType.BURN
	burn.tissue_layer = int(PenetrationResolver.TissueBarrier.SKIN)
	burn.body_zone = zone
	burn.severity = 5.0
	burn.bleed_rate_ml_per_sec = 0.0
	burn.heal_duration_game_hours = 36.0
	burn.anti_regen = true
	burn.anti_regen_timer = duration_sec
	apply_anti_regen(zone, duration_sec, false)
	return add_wound(zone, burn, false)


# ---------------------------------------------------------------------------
# Wound Management, First Aid & Healing
# ---------------------------------------------------------------------------

func add_wound(zone: StringName, wound_template: WoundResource, duplicate_template: bool = true) -> WoundResource:
	if wound_template == null or not body_parts.has(zone):
		return null
	var wound: WoundResource = wound_template.create_runtime_copy() if duplicate_template else wound_template
	_wound_counter += 1
	wound.body_zone = zone
	wound.runtime_uid = StringName("%s%d" % [SOURCE_WOUND_PREFIX, _wound_counter])

	var part: BodyPart = body_parts[zone]
	part.wounds.append(wound)
	if wound.wound_type == WoundResource.WoundType.FRACTURE:
		part.is_fractured = true
	if wound.wound_type == WoundResource.WoundType.TENDON_TEAR:
		part.has_tendon_tear = true
	if wound.is_arterial:
		part.has_arterial_bleed = true

	_apply_wound_modifiers(wound)

	var bus: Node = _get_event_bus()
	if bus != null:
		bus.emit_signal("wound_inflicted", _get_owner_entity(), zone, wound)
	return wound


func bandage_zone(zone: StringName) -> int:
	if not body_parts.has(zone):
		return 0
	var count: int = 0
	for w: WoundResource in body_parts[zone].wounds:
		if not w.is_bandaged and w.bleed_rate_ml_per_sec > 0.0:
			w.is_bandaged = true
			count += 1
	return count


func splint_zone(zone: StringName) -> int:
	if not body_parts.has(zone):
		return 0
	var count: int = 0
	for w: WoundResource in body_parts[zone].wounds:
		if w.wound_type == WoundResource.WoundType.FRACTURE and not w.is_splinted:
			w.is_splinted = true
			count += 1
	return count


func heal_blood(amount_ml: float, source: StringName = &"") -> float:
	if is_dead or amount_ml <= 0.0:
		return 0.0
	var ctx: Dictionary = {
		"target": _get_owner_entity(),
		"amount_ml": amount_ml,
		"source": source,
		"cancelled": false,
	}
	var bus: Node = _get_event_bus()
	if bus != null and bus.has_method("run_heal_pipeline"):
		ctx = bus.call("run_heal_pipeline", ctx)
	if bool(ctx.get("cancelled", false)):
		return 0.0

	var effective_amount: float = maxf(0.0, float(ctx.get("amount_ml", 0.0)))
	var before: float = blood_volume
	blood_volume = minf(max_blood_volume, blood_volume + effective_amount)
	var restored: float = blood_volume - before
	if restored > 0.0:
		blood_changed.emit(blood_volume, max_blood_volume)
		_evaluate_thresholds()
	return restored


func advance_healing_hours(game_hours: float, regen_mult: float = 1.0) -> int:
	if is_dead or game_hours <= 0.0:
		return 0
	if global_anti_regen_timer > 0.0:
		return 0
	var healed_count: int = 0
	for part: BodyPart in body_parts.values():
		if part.anti_regen_timer > 0.0:
			continue
		for i: int in range(part.wounds.size() - 1, -1, -1):
			var w: WoundResource = part.wounds[i]
			w.advance_healing(game_hours, regen_mult)
			if w.is_healed():
				_remove_wound_modifiers(w)
				part.wounds.remove_at(i)
				healed_count += 1
	_recompute_limb_flags()
	return healed_count


# ---------------------------------------------------------------------------
# Simulation Tick + REG Regeneration Tick (runs strictly on world_delta!)
# ---------------------------------------------------------------------------

## Advances blood loss, shock decay, knockout timers, Anti-Regen timers, and REG tick.
## Optional `resources` dict (`{"stamina": float, "mp": float}`) lets an owning actor
## supply & receive live STA/MP deductions without coupling AnatomyComponent to CombatActor.
func tick(world_delta: float, resources: Dictionary = {}) -> void:
	if is_dead or world_delta <= 0.0:
		return

	# 0. Tick Anti-Regen & arterial pulse timers
	if global_anti_regen_timer > 0.0:
		global_anti_regen_timer = maxf(0.0, global_anti_regen_timer - world_delta)
	for part: BodyPart in body_parts.values():
		if part.anti_regen_timer > 0.0:
			part.anti_regen_timer = maxf(0.0, part.anti_regen_timer - world_delta)
		for w: WoundResource in part.wounds:
			w.tick_timers(world_delta)

	# 1. Blood loss from active bleeding wounds
	var bleed_rate: float = get_total_bleed_rate()
	if bleed_rate > 0.0:
		blood_volume = maxf(0.0, blood_volume - bleed_rate * world_delta)
		blood_changed.emit(blood_volume, max_blood_volume)

	# 2. Traumatic shock decay (reduced by CON & SOUL, GDD 3.4 #3)
	if shock_level > 0.0:
		var con_val: float = stat_sheet.get_stat(StatSheet.Stat.CON) if stat_sheet != null else 10.0
		var soul_val: float = stat_sheet.get_stat(StatSheet.Stat.SOUL) if stat_sheet != null else 10.0
		var decay_rate: float = clampf(1.5 + (con_val / 10.0) * 0.4 + (soul_val / 10.0) * 0.3, 1.5, 10.0)
		shock_level = maxf(0.0, shock_level - decay_rate * world_delta)
		shock_changed.emit(shock_level)

	# 3. Knockout timer countdown (for shock KO)
	if is_unconscious and knockout_timer > 0.0:
		knockout_timer = maxf(0.0, knockout_timer - world_delta)

	# 4. Evaluate lethal blood loss BEFORE regeneration can save a dead entity
	_evaluate_thresholds()
	if is_dead:
		return

	# 5. REG regeneration tick (clot_rate, heal_rate, limb regrowth >=150, organ reconstruction >=400)
	_tick_regeneration(world_delta, resources)

	_recompute_limb_flags()
	_evaluate_thresholds()


func _tick_regeneration(world_delta: float, resources: Dictionary) -> void:
	var reg_val: float = stat_sheet.get_stat(StatSheet.Stat.REG) if stat_sheet != null else StatSheet.HUMAN_REFERENCE
	var clot_rate: float = pow(reg_val / StatSheet.HUMAN_REFERENCE, 1.5)
	var heal_rate: float = pow(reg_val / StatSheet.HUMAN_REFERENCE, 1.8)
	var requires_mp: bool = stat_sheet != null and stat_sheet.uses_magical_regen()
	var can_regrow_limbs: bool = reg_val >= StatSheet.REG_LIMB_REGROW_THRESHOLD
	var can_reconstruct_organs: bool = (
		reg_val >= StatSheet.REG_ORGAN_REGROW_THRESHOLD
		and get_organ_integrity(ZONE_HEAD) > 0.0
		and (stat_sheet == null or stat_sheet.get_stat(StatSheet.Stat.SOUL) > 0.0)
	)

	# Scan active work and check Anti-Regen blockage
	var has_any_work: bool = false
	var has_unblocked_work: bool = false
	var has_limb_regrowth_work: bool = false
	var has_organ_reconstruct_work: bool = false
	var total_bleed: float = get_total_bleed_rate()
	var can_regen_blood: bool = blood_volume < max_blood_volume and (total_bleed <= 0.0 or reg_val >= StatSheet.REG_COMBAT_CLOT_THRESHOLD)
	if can_regen_blood:
		has_any_work = true
		if global_anti_regen_timer <= 0.0:
			has_unblocked_work = true

	for part: BodyPart in body_parts.values():
		var zone_blocked: bool = is_anti_regen_active(part.zone_name)
		if part.limb_status == LimbStatus.SEVERED and can_regrow_limbs and (part.zone_name != ZONE_NECK or has_immortal_core):
			has_any_work = true
			if not zone_blocked:
				has_unblocked_work = true
				has_limb_regrowth_work = true
		if part.has_vital_organ and part.zone_name != ZONE_HEAD and part.organ_integrity < 100.0 and can_reconstruct_organs:
			has_any_work = true
			if not zone_blocked:
				has_unblocked_work = true
				has_organ_reconstruct_work = true
		for w: WoundResource in part.wounds:
			var needs_clot: bool = w.bleed_rate_ml_per_sec > 0.0 and (reg_val >= COMBAT_CLOT_MIN_REG or w.wound_type == WoundResource.WoundType.SCRATCH)
			var needs_heal: bool = not w.is_healed() and w.wound_type != WoundResource.WoundType.LODGED_WEAPON and w.wound_type != WoundResource.WoundType.SEVERED_STUMP
			if needs_clot or needs_heal:
				has_any_work = true
				if not zone_blocked and not w.is_anti_regen_active():
					has_unblocked_work = true
		if part.limb_status != LimbStatus.SEVERED:
			if part.skin_integrity < 100.0 or part.muscle_tendon_integrity < 100.0 or part.bone_integrity < 100.0 or part.vessels_organ_integrity < 100.0:
				has_any_work = true
				if not zone_blocked:
					has_unblocked_work = true

	if not has_any_work:
		last_regen_active = false
		last_regen_paused_reason = ""
		return

	if global_anti_regen_timer > 0.0 or not has_unblocked_work:
		last_regen_active = false
		last_regen_paused_reason = "anti_regen"
		return

	# Read STA / MP from caller resources dict or standalone pools
	var use_external_sta: bool = resources.has("stamina")
	var use_external_mp: bool = resources.has("mp")
	var cur_sta: float = float(resources["stamina"]) if use_external_sta else standalone_stamina
	var cur_mp: float = float(resources["mp"]) if use_external_mp else standalone_mp

	if cur_sta <= 0.0:
		last_regen_active = false
		last_regen_paused_reason = "no_stamina"
		return
	if calories <= 0.0:
		last_regen_active = false
		last_regen_paused_reason = "no_calories"
		return
	if requires_mp and cur_mp <= 0.0:
		last_regen_active = false
		last_regen_paused_reason = "no_mp"
		return

	# Compute resource burn rates per second (GDD 3.2 #12, 14.1 #3)
	var sta_per_sec: float = 0.05
	var cal_per_sec: float = 0.20
	var mp_per_sec: float = 0.0
	if reg_val >= COMBAT_CLOT_MIN_REG:
		var reg_excess: float = maxf(0.0, reg_val - StatSheet.HUMAN_REFERENCE) / StatSheet.HUMAN_REFERENCE
		sta_per_sec = 0.5 + reg_excess * 0.6
		cal_per_sec = 0.5 + reg_excess * 0.5
		if requires_mp:
			mp_per_sec = 0.8 + reg_excess * 0.4
	if has_limb_regrowth_work:
		sta_per_sec += 6.0
		cal_per_sec += 5.0
		if requires_mp:
			mp_per_sec += 5.0
	if has_organ_reconstruct_work:
		sta_per_sec += 10.0
		cal_per_sec += 8.0
		if requires_mp:
			mp_per_sec += 10.0

	var sta_needed: float = sta_per_sec * world_delta
	var cal_needed: float = cal_per_sec * world_delta
	var mp_needed: float = mp_per_sec * world_delta

	# Limit active tick fraction if any pool depletes mid-step
	var frac: float = 1.0
	var depleted_reason: String = ""
	if sta_needed > 0.0 and cur_sta < sta_needed:
		var f_sta: float = cur_sta / sta_needed
		if f_sta < frac:
			frac = f_sta
			depleted_reason = "no_stamina"
	if cal_needed > 0.0 and calories < cal_needed:
		var f_cal: float = calories / cal_needed
		if f_cal < frac:
			frac = f_cal
			depleted_reason = "no_calories"
	if requires_mp and mp_needed > 0.0 and cur_mp < mp_needed:
		var f_mp: float = cur_mp / mp_needed
		if f_mp < frac:
			frac = f_mp
			depleted_reason = "no_mp"

	var eff_dt: float = world_delta * clampf(frac, 0.0, 1.0)
	cur_sta = maxf(0.0, cur_sta - sta_per_sec * eff_dt)
	calories = maxf(0.0, calories - cal_per_sec * eff_dt)
	if requires_mp:
		cur_mp = maxf(0.0, cur_mp - mp_per_sec * eff_dt)

	if use_external_sta:
		resources["stamina"] = cur_sta
	else:
		standalone_stamina = cur_sta
	if use_external_mp:
		resources["mp"] = cur_mp
	else:
		standalone_mp = cur_mp

	last_regen_active = eff_dt > 0.0
	last_regen_paused_reason = depleted_reason

	if eff_dt <= 0.0:
		return

	var game_hours: float = eff_dt / GAME_SECONDS_PER_HOUR

	# Apply REG effects across all unblocked body parts
	for part: BodyPart in body_parts.values():
		if is_anti_regen_active(part.zone_name):
			continue

		# A. Clotting & wound/fracture healing
		for i: int in range(part.wounds.size() - 1, -1, -1):
			var w: WoundResource = part.wounds[i]
			if w.is_anti_regen_active():
				continue
			if w.bleed_rate_ml_per_sec > 0.0:
				if reg_val >= COMBAT_CLOT_MIN_REG:
					w.clot_bleed(BASE_CLOT_PER_SEC * clot_rate * eff_dt)
				elif w.wound_type == WoundResource.WoundType.SCRATCH:
					w.clot_bleed(0.0005 * clot_rate * eff_dt)
			w.advance_healing(game_hours, heal_rate)
			if w.is_healed():
				_remove_wound_modifiers(w)
				part.wounds.remove_at(i)

		# B. Severed limb regrowth (REG >= 150 -> 10..60 s depending on REG & mass/size_mult)
		if part.limb_status == LimbStatus.SEVERED and can_regrow_limbs and (part.zone_name != ZONE_NECK or has_immortal_core):
			var regrow_pct_per_sec: float = clampf((heal_rate / 147.0) * (4.0 / maxf(0.5, size_mult)), 1.67, 10.0)
			part.regrowth_progress = minf(100.0, part.regrowth_progress + regrow_pct_per_sec * eff_dt)
			if part.regrowth_progress >= 100.0:
				_complete_limb_regrowth(part)

		# C. Vital organ reconstruction (REG >= 400 -> 2..10 s if Brain & SOUL intact)
		if part.has_vital_organ and part.zone_name != ZONE_HEAD and part.organ_integrity < 100.0 and can_reconstruct_organs:
			var org_pct_per_sec: float = clampf((heal_rate / 765.0) * 20.0, 10.0, 50.0)
			var was_below: bool = part.organ_integrity < 100.0
			part.organ_integrity = minf(100.0, part.organ_integrity + org_pct_per_sec * eff_dt)
			part.vessels_organ_integrity = part.organ_integrity
			if was_below and part.organ_integrity >= 100.0:
				organ_reconstructed.emit(part.zone_name)
				var bus: Node = _get_event_bus()
				if bus != null:
					bus.emit_signal("organ_reconstructed", _get_owner_entity(), part.zone_name)

		# D. Gradual 4-layer structural tissue recovery on non-severed parts
		if part.limb_status != LimbStatus.SEVERED and part.lodged_weapons.is_empty():
			var layer_gain: float = heal_rate * 0.15 * eff_dt
			part.skin_integrity = minf(100.0, part.skin_integrity + layer_gain)
			part.muscle_tendon_integrity = minf(100.0, part.muscle_tendon_integrity + layer_gain)
			if not part.is_fractured:
				part.bone_integrity = minf(100.0, part.bone_integrity + layer_gain)
			if not part.has_vital_organ:
				part.vessels_organ_integrity = minf(100.0, part.vessels_organ_integrity + layer_gain)

	# E. Blood volume replenishment
	if can_regen_blood and global_anti_regen_timer <= 0.0:
		var blood_gain: float = BASE_BLOOD_REGEN_PER_SEC * clot_rate * eff_dt
		if blood_gain > 0.0:
			heal_blood(blood_gain, &"regeneration")


func _complete_limb_regrowth(part: BodyPart) -> void:
	part.limb_status = LimbStatus.INTACT
	part.regrowth_progress = 0.0
	part.skin_integrity = 100.0
	part.muscle_tendon_integrity = 100.0
	part.bone_integrity = 100.0
	part.vessels_organ_integrity = 100.0
	part.has_arterial_bleed = false
	part.has_tendon_tear = false
	part.is_fractured = false
	for i: int in range(part.wounds.size() - 1, -1, -1):
		var w: WoundResource = part.wounds[i]
		if w.wound_type == WoundResource.WoundType.SEVERED_STUMP:
			_remove_wound_modifiers(w)
			part.wounds.remove_at(i)
	limb_regrown.emit(part.zone_name)
	var bus: Node = _get_event_bus()
	if bus != null:
		bus.emit_signal("limb_regrown", _get_owner_entity(), part.zone_name)


func _can_survive_organ_destruction(zone: StringName) -> bool:
	# Brain destruction is always fatal (unless has_immortal_core checked by caller)
	if zone == ZONE_HEAD:
		return false
	if stat_sheet == null or not stat_sheet.can_reconstruct_organs():
		return false
	if get_organ_integrity(ZONE_HEAD) <= 0.0:
		return false
	if stat_sheet.get_stat(StatSheet.Stat.SOUL) <= 0.0:
		return false
	return not is_anti_regen_active(zone)


func _recompute_limb_flags() -> void:
	var any_limp: bool = false
	var any_leg_severed: bool = false
	for part: BodyPart in body_parts.values():
		var still_fractured: bool = false
		var still_tendon: bool = false
		var still_arterial: bool = false
		for w: WoundResource in part.wounds:
			if w.wound_type == WoundResource.WoundType.FRACTURE:
				still_fractured = true
			if w.wound_type == WoundResource.WoundType.TENDON_TEAR:
				still_tendon = true
			if w.is_arterial and w.bleed_rate_ml_per_sec > 0.0:
				still_arterial = true
			if w.causes_limp:
				any_limp = true
		part.is_fractured = still_fractured
		part.has_tendon_tear = still_tendon
		part.has_arterial_bleed = still_arterial
		if part.limb_status == LimbStatus.CRIPPLED and not still_fractured and not still_tendon:
			part.limb_status = LimbStatus.INTACT
		if part.limb_status == LimbStatus.SEVERED and LEG_ZONES.has(part.zone_name):
			any_leg_severed = true
			any_limp = true
	has_limp = any_limp
	if any_leg_severed:
		is_prone = true


func _add_shock(amount: float) -> void:
	if amount <= 0.0:
		return
	shock_level = clampf(shock_level + amount, 0.0, 100.0)
	shock_changed.emit(shock_level)


func _evaluate_thresholds() -> void:
	if is_dead:
		return

	var loss_ratio: float = get_blood_loss_ratio()

	# Death from exsanguination: >= 65% blood lost (remaining <= 35%)
	if loss_ratio >= BLOOD_LOSS_DEATH_RATIO - 1e-6:
		_trigger_death("exsanguination", &"")
		return

	# Severe blood loss debuff (> 25% blood lost -> SPD, TP, CTRL penalties)
	if loss_ratio > BLOOD_LOSS_SEVERE_RATIO:
		_set_severe_blood_loss_modifiers(true)
	else:
		_set_severe_blood_loss_modifiers(false)

	# Hemorrhagic shock / Knockout (> 45% blood lost)
	if loss_ratio > BLOOD_LOSS_KO_RATIO:
		if not is_unconscious:
			_trigger_knockout("hemorrhagic_shock", -1.0)
		else:
			knockout_reason = "hemorrhagic_shock"
			knockout_timer = -1.0
		return

	# Traumatic shock Knockout (shock_level >= 100%)
	if shock_level >= 100.0 - 1e-6:
		if not is_unconscious:
			var con_val: float = stat_sheet.get_stat(StatSheet.Stat.CON) if stat_sheet != null else 10.0
			var soul_val: float = stat_sheet.get_stat(StatSheet.Stat.SOUL) if stat_sheet != null else 10.0
			var duration: float = clampf(60.0 / (1.0 + maxf(0.0, (con_val + soul_val - 20.0)) * 0.02), 10.0, 60.0)
			_trigger_knockout("traumatic_shock", duration)
		return

	# Recovery from unconsciousness if blood is safe and shock KO timer expired
	if is_unconscious and loss_ratio <= BLOOD_LOSS_KO_RATIO and knockout_timer <= 0.0:
		is_unconscious = false
		knockout_reason = ""
		knockout_timer = 0.0
		recovered_consciousness.emit()
		var bus: Node = _get_event_bus()
		if bus != null:
			bus.emit_signal("entity_recovered_consciousness", _get_owner_entity())


func apply_stealth_knockout(duration_sec: float = 35.0, reason: String = "stealth_takedown") -> bool:
	if is_dead:
		return false
	shock_level = 100.0
	shock_changed.emit(shock_level)
	var dur: float = clampf(duration_sec, 25.0, 45.0)
	if not is_unconscious:
		_trigger_knockout(reason, dur)
	else:
		knockout_reason = reason
		knockout_timer = maxf(knockout_timer, dur)
	return true


func _trigger_knockout(reason: String, duration_sec: float) -> void:
	is_unconscious = true
	knockout_reason = reason
	knockout_timer = duration_sec
	knocked_out.emit(reason, duration_sec)
	var bus: Node = _get_event_bus()
	if bus != null:
		bus.emit_signal("entity_knocked_out", _get_owner_entity(), reason, duration_sec)


func _trigger_death(cause: String, zone: StringName) -> void:
	if is_dead:
		return
	is_dead = true
	death_cause = cause
	fatal_zone = zone
	is_unconscious = false
	died.emit(cause, zone)
	var bus: Node = _get_event_bus()
	if bus != null:
		bus.emit_signal("entity_died", _get_owner_entity(), cause, zone)


func _set_severe_blood_loss_modifiers(active: bool) -> void:
	if stat_sheet == null:
		return
	if active == _severe_blood_loss_applied:
		return
	_severe_blood_loss_applied = active
	if active:
		stat_sheet.add_modifier(StatModifier.create_multiplier(&"severe_blood_loss_spd", StatSheet.Stat.SPD, 0.8, SOURCE_SEVERE_BLOOD_LOSS))
		stat_sheet.add_modifier(StatModifier.create_multiplier(&"severe_blood_loss_tp", StatSheet.Stat.TP, 0.8, SOURCE_SEVERE_BLOOD_LOSS))
		stat_sheet.add_modifier(StatModifier.create_multiplier(&"severe_blood_loss_ctrl", StatSheet.Stat.CTRL, 0.8, SOURCE_SEVERE_BLOOD_LOSS))
	else:
		stat_sheet.remove_modifiers_by_source(SOURCE_SEVERE_BLOOD_LOSS)


func _populate_limb_wound_penalties(wound: WoundResource, zone: StringName, is_fracture: bool) -> void:
	match zone:
		ZONE_LEFT_LEG, ZONE_RIGHT_LEG:
			wound.stat_penalties[StatSheet.Stat.SPD] = 0.55 if is_fracture else 0.85
			wound.stat_penalties[StatSheet.Stat.AGI] = 0.50 if is_fracture else 0.85
			if not wound.stat_penalty_tags.has(StatSheet.TAG_LEG_LOCOMOTION):
				wound.stat_penalty_tags.append(StatSheet.TAG_LEG_LOCOMOTION)
		ZONE_LEFT_ARM, ZONE_RIGHT_ARM:
			wound.stat_penalties[StatSheet.Stat.STR] = 0.70 if is_fracture else 0.90
			wound.stat_penalties[StatSheet.Stat.CTRL] = 0.70 if is_fracture else 0.90
		ZONE_HEAD:
			wound.stat_penalties[StatSheet.Stat.TP] = 0.75 if is_fracture else 0.90
		ZONE_NECK:
			if is_fracture:
				wound.stat_penalties[StatSheet.Stat.TP] = 0.65
				wound.stat_penalties[StatSheet.Stat.CTRL] = 0.70
		ZONE_CHEST:
			if is_fracture:
				wound.stat_penalties[StatSheet.Stat.STA] = 0.70
				wound.stat_penalties[StatSheet.Stat.STR] = 0.80
				wound.stat_penalties[StatSheet.Stat.SPD] = 0.85
		ZONE_STOMACH:
			if is_fracture:
				wound.stat_penalties[StatSheet.Stat.STA] = 0.72
				wound.stat_penalties[StatSheet.Stat.AGI] = 0.75


func _apply_wound_modifiers(wound: WoundResource) -> void:
	if stat_sheet == null or wound.stat_penalties.is_empty():
		return
	var is_leg_zone: bool = LEG_ZONES.has(wound.body_zone)
	for stat_key: int in wound.stat_penalties.keys():
		var mult: float = wound.stat_penalties[stat_key]
		var mod_id: StringName = StringName("%s_%d" % [String(wound.runtime_uid), stat_key])
		var mod_tags: Array[StringName] = wound.stat_penalty_tags.duplicate()
		if is_leg_zone and (stat_key == StatSheet.Stat.SPD or stat_key == StatSheet.Stat.AGI):
			if not mod_tags.has(StatSheet.TAG_LEG_LOCOMOTION):
				mod_tags.append(StatSheet.TAG_LEG_LOCOMOTION)
		stat_sheet.add_modifier(StatModifier.create_multiplier(mod_id, stat_key, mult, wound.runtime_uid, 0, mod_tags))


func _remove_wound_modifiers(wound: WoundResource) -> void:
	if stat_sheet == null or wound.runtime_uid == &"":
		return
	stat_sheet.remove_modifiers_by_source(wound.runtime_uid)


func _get_owner_entity() -> Node:
	if owner_entity != null:
		return owner_entity
	if get_parent() != null:
		return get_parent()
	return self


func _get_event_bus() -> Node:
	if is_inside_tree():
		var root: Node = get_tree().root
		if root != null:
			return root.get_node_or_null("EventBus")
	var main_loop: MainLoop = Engine.get_main_loop()
	if main_loop is SceneTree:
		var tree: SceneTree = main_loop as SceneTree
		if tree.root != null:
			return tree.root.get_node_or_null("EventBus")
	return null
