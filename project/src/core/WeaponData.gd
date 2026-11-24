class_name WeaponData
extends Resource
## Read-only data-driven weapon template (GDD Sections 7.2, 12.2, 12.5, 14.4, v0.2).
## Always call create_runtime_copy() before equipping an entity so sharpness/durability wear
## never mutates the shared .tres template.

enum DamageMode {
	PIERCE_SLASH = 0,
	SLASH_BLUNT = 1,
	BLUNT_ONLY = 2,
}

@export var weapon_id: StringName = &""
@export var display_name: String = ""
@export var base_penetration: float = 12.0
@export var blade_length: float = 14.0
@export var min_optimal_range: float = 0.0
@export var edge_sharpness: float = 1.0
@export var max_edge_sharpness: float = 1.0
@export var max_durability: float = 100.0
@export var durability: float = 100.0
@export var mass_factor: float = 4.0
@export var vertical_reach: float = 0.6
@export var damage_mode: DamageMode = DamageMode.PIERCE_SLASH

## Attack-type coefficients (GDD 7.2, 12.2, 14.4)
@export var thrust_pierce_mult: float = 1.35
@export var slash_pierce_mult: float = 0.85
@export var blunt_pierce_mult: float = 0.15
@export var slash_sever_mult: float = 1.0
@export var blunt_impulse_mult: float = 1.0
@export var can_half_sword: bool = false
@export var is_unarmed: bool = false

@export var windup_sec: float = 0.18
@export var active_sec: float = 0.12
@export var recovery_sec: float = 0.22
@export var swing_arc_deg: float = 75.0
@export var stamina_cost: float = 12.0
@export var poise_damage: float = 20.0

@export var hilt_offset_px: float = 12.0
@export var blade_width_px: float = 3.0
@export var blade_color: Color = Color("#D8DEE9")


func create_runtime_copy() -> WeaponData:
	return self.duplicate(true) as WeaponData


static func create_unarmed_fist() -> WeaponData:
	var fist: WeaponData = WeaponData.new()
	fist.weapon_id = &"unarmed_fist"
	fist.display_name = "Unarmed (Fists)"
	fist.is_unarmed = true
	fist.damage_mode = DamageMode.BLUNT_ONLY
	fist.base_penetration = 3.0
	fist.blade_length = 10.0
	fist.hilt_offset_px = 4.0
	fist.min_optimal_range = 0.0
	fist.edge_sharpness = 0.25
	fist.max_edge_sharpness = 0.25
	fist.max_durability = 9999.0
	fist.durability = 9999.0
	fist.mass_factor = 3.0
	fist.vertical_reach = 0.5
	fist.thrust_pierce_mult = 0.20
	fist.slash_pierce_mult = 0.15
	fist.blunt_pierce_mult = 0.15
	fist.slash_sever_mult = 0.05
	fist.blunt_impulse_mult = 1.0
	fist.can_half_sword = false
	fist.windup_sec = 0.14
	fist.active_sec = 0.10
	fist.recovery_sec = 0.18
	fist.swing_arc_deg = 60.0
	fist.stamina_cost = 7.0
	fist.poise_damage = 10.0
	fist.blade_width_px = 4.0
	fist.blade_color = Color("#E5C09B")
	return fist


func is_broken() -> bool:
	if is_unarmed:
		return false
	return durability <= 0.0


func get_durability_ratio() -> float:
	if max_durability <= 0.0:
		return 1.0
	return clampf(durability / max_durability, 0.0, 1.0)


func apply_durability_damage(amount: float, extra_wear_mult: float = 0.0, aura_active: bool = false) -> float:
	if is_unarmed or aura_active or amount <= 0.0:
		return 0.0
	var total_loss: float = amount * (1.0 + maxf(0.0, extra_wear_mult))
	var before: float = durability
	durability = maxf(0.0, durability - total_loss)
	return before - durability


## Applies realistic edge dulling / chipping on hard surfaces when Aura is inactive (GDD 7.2, 14.5).
func apply_wear(base_wear: float, extra_wear_mult: float = 0.0, aura_active: bool = false) -> float:
	if is_unarmed or aura_active or base_wear <= 0.0:
		return 0.0
	var total_wear: float = base_wear * (1.0 + maxf(0.0, extra_wear_mult))
	var before: float = edge_sharpness
	edge_sharpness = maxf(0.15, edge_sharpness - total_wear)
	apply_durability_damage(base_wear * 20.0, extra_wear_mult, false)
	return before - edge_sharpness


func get_sharpness_ratio() -> float:
	if max_edge_sharpness <= 0.0:
		return 1.0
	return clampf(edge_sharpness / max_edge_sharpness, 0.0, 1.0)


## Half-swording cuts reach to 55% and removes dead zone (GDD 12.2).
func get_effective_blade_length(half_swording: bool = false) -> float:
	if half_swording and can_half_sword:
		return blade_length * 0.55
	return blade_length


func get_effective_min_optimal_range(half_swording: bool = false) -> float:
	if half_swording and can_half_sword:
		return 0.0
	return maxf(0.0, min_optimal_range)


## Maps PenetrationResolver.AttackType (0=STANDARD, 1=THRUST, 2=SLASH, 3=BLUNT) to pierce multiplier.
func get_type_pierce_mult(attack_type: int) -> float:
	match attack_type:
		1:
			return thrust_pierce_mult
		2:
			return slash_pierce_mult
		3:
			return blunt_pierce_mult
		_:
			return 1.0
