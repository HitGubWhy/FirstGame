class_name WoundResource
extends Resource
## Data-driven wound template and runtime copy (GDD Sections 3.4, 12.4, 12.5, v0.2).
## Templates (.tres) are read-only; always call create_runtime_copy() before mutating at runtime.

enum WoundType {
	SCRATCH = 0,
	CUT = 1,
	DEEP_WOUND = 2,
	FRACTURE = 3,
	BURN = 4,
	INFECTION = 5,
	LODGED_PROJECTILE = 6,
	BRUISE = 7,
	ARTERIAL_BLEED = 8,
	TENDON_TEAR = 9,
	LODGED_WEAPON = 10,
	SEVERED_STUMP = 11,
}

@export var wound_id: StringName = &""
@export var display_name: String = ""
@export var wound_type: WoundType = WoundType.CUT
@export var body_zone: StringName = &""
## Maps to PenetrationResolver.TissueBarrier (2=Skin, 3=Muscle/Tendon, 4=Bone/Vessels/Organ).
@export var tissue_layer: int = 2
@export var severity: float = 1.0
@export var bleed_rate_ml_per_sec: float = 0.0
@export var is_arterial: bool = false
@export var arterial_pulse_phase: float = 0.0
@export var initial_shock: float = 0.0
@export var heal_duration_game_hours: float = 24.0
@export var heal_progress_hours: float = 0.0
@export var is_bandaged: bool = false
@export var is_splinted: bool = false
@export var is_infected: bool = false
@export var anti_regen: bool = false
@export var anti_regen_timer: float = 0.0
@export var causes_limp: bool = false
@export var causes_grip_loss: bool = false
@export var lodged_weapon: WeaponData = null
## Maps StatSheet.Stat (int) -> multiplicative penalty factor (e.g. 0.5 for -50% SPD on fractured leg).
@export var stat_penalties: Dictionary[int, float] = {}
## Optional StatModifier tags attached to this wound's stat penalties (e.g. StatSheet.TAG_LEG_LOCOMOTION).
@export var stat_penalty_tags: Array[StringName] = []

## Unique runtime instance key assigned when attached to an AnatomyComponent.
var runtime_uid: StringName = &""


func create_runtime_copy() -> WoundResource:
	var copy: WoundResource = self.duplicate(true) as WoundResource
	return copy


func is_anti_regen_active() -> bool:
	return anti_regen or anti_regen_timer > 0.0


func tick_timers(world_delta: float) -> void:
	if world_delta <= 0.0:
		return
	if is_arterial and bleed_rate_ml_per_sec > 0.0:
		arterial_pulse_phase = fmod(arterial_pulse_phase + world_delta * 4.5, TAU)
	if anti_regen_timer > 0.0:
		anti_regen_timer = maxf(0.0, anti_regen_timer - world_delta)
		if anti_regen_timer <= 0.0:
			anti_regen = false


func get_effective_bleed_rate() -> float:
	if bleed_rate_ml_per_sec <= 0.0:
		return 0.0
	var rate: float = bleed_rate_ml_per_sec
	if is_arterial:
		# Pulsing accelerated arterial blood loss (1.25x..1.60x)
		rate *= 1.25 + 0.35 * absf(sin(arterial_pulse_phase))
	if is_bandaged:
		if wound_type == WoundType.LODGED_PROJECTILE or wound_type == WoundType.LODGED_WEAPON:
			return rate * 0.25
		if is_arterial:
			return rate * 0.35
		return 0.0
	return rate


func clot_bleed(amount_ml_per_sec: float) -> float:
	if amount_ml_per_sec <= 0.0 or bleed_rate_ml_per_sec <= 0.0 or is_anti_regen_active():
		return 0.0
	var before: float = bleed_rate_ml_per_sec
	bleed_rate_ml_per_sec = maxf(0.0, bleed_rate_ml_per_sec - amount_ml_per_sec)
	return before - bleed_rate_ml_per_sec


func advance_healing(game_hours: float, regen_mult: float = 1.0) -> void:
	if game_hours <= 0.0 or is_healed():
		return
	if is_anti_regen_active():
		return
	if wound_type == WoundType.LODGED_WEAPON or wound_type == WoundType.SEVERED_STUMP:
		return
	# Fractures heal very slowly without a splint for mortals (GDD 3.4 #4),
	# whereas high supernatural REG (>=20x heal_rate) knits bones actively.
	var care_mult: float = 1.0
	if wound_type == WoundType.FRACTURE:
		care_mult = 1.0 if (is_splinted or regen_mult >= 20.0) else 0.25
	elif is_bandaged:
		care_mult = 1.35
	if is_infected:
		care_mult *= 0.25
	heal_progress_hours = minf(heal_duration_game_hours, heal_progress_hours + game_hours * maxf(0.0, regen_mult) * care_mult)


func is_healed() -> bool:
	if wound_type == WoundType.LODGED_WEAPON or wound_type == WoundType.SEVERED_STUMP:
		return false
	return heal_duration_game_hours > 0.0 and heal_progress_hours >= heal_duration_game_hours


func get_heal_ratio() -> float:
	if heal_duration_game_hours <= 0.0:
		return 1.0
	return clampf(heal_progress_hours / heal_duration_game_hours, 0.0, 1.0)
