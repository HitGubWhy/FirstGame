class_name WeaponRaySweeper
extends Node2D
## Continuous directional weapon geometry sweeper (GDD Sections 7.1, 7.2, 12.2, 14.5, v0.2).
## Supports 3 attack geometries:
##   - SLASH: angular arc subdivided into <= 5 deg micro-steps
##   - THRUST: narrow forward ray with high weak-point precision
##   - BLUNT: compact wide-head impulsive arc
## Also supports Half-swording (0.55x reach, zero min_optimal_range, +50% CTRL weak-point precision),
## HitboxZone Area2D detection, destructible Wall/Floor tiles, and mid-air Blade Clash intersection.

const MAX_ANGULAR_STEP_DEG: float = 5.0
const BASE_PRECISION_RADIUS_PX: float = 3.0
const MAX_PRECISION_RADIUS_PX: float = 6.0
const BASE_AIM_TOLERANCE_PX: float = 12.0

var _swing_active: bool = false
var _last_angle_rad: float = 0.0
var _active_attack_type: PenetrationResolver.AttackType = PenetrationResolver.AttackType.SLASH
var _active_half_swording: bool = false
var active_segment_start: Vector2 = Vector2.ZERO
var active_segment_end: Vector2 = Vector2.ZERO
var active_blade_radius: float = 3.0
var _has_valid_segment: bool = false

var _hit_actor_ids: Dictionary[int, bool] = {}
var _clashed_actor_ids: Dictionary[int, bool] = {}
var _pending_body_hits: Dictionary = {}
var _vertical_miss_actor_ids: Dictionary[int, bool] = {}
var _hit_wall_cells: Dictionary[Vector2i, bool] = {}
var _hit_floor_cells: Dictionary[Vector2i, bool] = {}


func begin_swing(
	start_angle_rad: float,
	attack_type: PenetrationResolver.AttackType = PenetrationResolver.AttackType.SLASH,
	half_swording: bool = false
) -> void:
	_swing_active = true
	_last_angle_rad = start_angle_rad
	_active_attack_type = attack_type
	_active_half_swording = half_swording
	_has_valid_segment = false
	_hit_actor_ids.clear()
	_clashed_actor_ids.clear()
	_pending_body_hits.clear()
	_vertical_miss_actor_ids.clear()
	_hit_wall_cells.clear()
	_hit_floor_cells.clear()


func flush_pending_hits() -> Array[Dictionary]:
	var flushed: Array[Dictionary] = []
	for actor_id_variant: Variant in _pending_body_hits.keys():
		var actor_id: int = int(actor_id_variant)
		if _hit_actor_ids.has(actor_id) or _clashed_actor_ids.has(actor_id):
			continue
		var entry: Dictionary = _pending_body_hits[actor_id] as Dictionary
		var target_node: Variant = entry.get("target", null)
		var zone: Variant = entry.get("zone", null)
		if target_node != null and is_instance_valid(target_node) and zone != null and is_instance_valid(zone):
			_hit_actor_ids[actor_id] = true
			flushed.append(entry)
	_pending_body_hits.clear()
	return flushed


func end_swing() -> void:
	_swing_active = false
	_has_valid_segment = false
	_pending_body_hits.clear()


func is_swing_active() -> bool:
	return _swing_active


func mark_clashed_with(other_actor_id: int) -> void:
	_clashed_actor_ids[other_actor_id] = true
	_hit_actor_ids[other_actor_id] = true
	_pending_body_hits.erase(other_actor_id)


func get_active_blade_segment() -> PackedVector2Array:
	if not _swing_active or not _has_valid_segment:
		return PackedVector2Array()
	return PackedVector2Array([active_segment_start, active_segment_end])


static func distance_point_to_segment(point: Vector2, seg_a: Vector2, seg_b: Vector2) -> float:
	var ab: Vector2 = seg_b - seg_a
	var len_sq: float = ab.length_squared()
	if len_sq <= 1e-8:
		return point.distance_to(seg_a)
	var t: float = clampf((point - seg_a).dot(ab) / len_sq, 0.0, 1.0)
	var closest: Vector2 = seg_a + ab * t
	return point.distance_to(closest)


## Geometric segment-segment intersection test with blade-thickness tolerance for Blade Clash (GDD 12.2).
static func segments_intersect(
	a1: Vector2,
	a2: Vector2,
	b1: Vector2,
	b2: Vector2,
	tolerance_px: float = 3.0
) -> Dictionary:
	var hit_variant: Variant = Geometry2D.segment_intersects_segment(a1, a2, b1, b2)
	if hit_variant != null and hit_variant is Vector2:
		return {
			"intersects": true,
			"point": hit_variant as Vector2,
			"exact": true,
		}
	var tol: float = maxf(0.0, tolerance_px)
	if tol <= 0.0:
		return {"intersects": false, "point": Vector2.ZERO, "exact": false}

	var best_dist: float = INF
	var best_pt: Vector2 = Vector2.ZERO

	var d_a1: float = distance_point_to_segment(a1, b1, b2)
	if d_a1 < best_dist:
		best_dist = d_a1
		best_pt = a1
	var d_a2: float = distance_point_to_segment(a2, b1, b2)
	if d_a2 < best_dist:
		best_dist = d_a2
		best_pt = a2
	var d_b1: float = distance_point_to_segment(b1, a1, a2)
	if d_b1 < best_dist:
		best_dist = d_b1
		best_pt = b1
	var d_b2: float = distance_point_to_segment(b2, a1, a2)
	if d_b2 < best_dist:
		best_dist = d_b2
		best_pt = b2

	if best_dist <= tol:
		return {
			"intersects": true,
			"point": best_pt,
			"exact": false,
		}
	return {"intersects": false, "point": Vector2.ZERO, "exact": false}


static func get_aim_tolerance_px(
	attacker_sheet: StatSheet,
	attack_type: PenetrationResolver.AttackType = PenetrationResolver.AttackType.SLASH,
	half_swording: bool = false
) -> float:
	if attacker_sheet == null:
		return BASE_AIM_TOLERANCE_PX
	var eff_ctrl: float = attacker_sheet.get_stat(StatSheet.Stat.CTRL) * (1.5 if half_swording else 1.0)
	var ctrl_excess: float = maxf(0.0, eff_ctrl - attacker_sheet.get_stat(StatSheet.Stat.STR))
	var tol: float = BASE_AIM_TOLERANCE_PX + ctrl_excess * 0.12
	if attack_type == PenetrationResolver.AttackType.THRUST:
		tol += 2.5
	if half_swording:
		tol += 2.5
	return clampf(tol, 8.0, 28.0)


## Computes weak-point precision_radius with +50% CTRL boost in Half-swording (GDD 12.2).
static func get_effective_precision_radius_px(
	attacker_sheet: StatSheet,
	attack_type: PenetrationResolver.AttackType = PenetrationResolver.AttackType.SLASH,
	half_swording: bool = false
) -> float:
	if attacker_sheet == null:
		return BASE_PRECISION_RADIUS_PX
	var eff_ctrl: float = attacker_sheet.get_stat(StatSheet.Stat.CTRL) * (1.5 if half_swording else 1.0)
	var excess: float = maxf(0.0, eff_ctrl - attacker_sheet.get_stat(StatSheet.Stat.STR))
	var radius: float = BASE_PRECISION_RADIUS_PX + excess * 0.05
	if half_swording:
		radius += 1.0
	if attack_type == PenetrationResolver.AttackType.THRUST:
		radius += 0.5
	return clampf(radius, BASE_PRECISION_RADIUS_PX, MAX_PRECISION_RADIUS_PX)


static func check_weak_point_double_condition(
	weak_point_world: Vector2,
	aim_world_pos: Vector2,
	hilt_pos: Vector2,
	tip_pos: Vector2,
	aim_tolerance_px: float,
	precision_radius_px: float,
	attacker_floor: int,
	target_floor: int,
	attacker_height_z: float,
	target_height_z: float,
	vertical_reach: float
) -> bool:
	if attacker_floor != target_floor:
		return false
	if absf(attacker_height_z - target_height_z) > maxf(0.0, vertical_reach):
		return false
	if aim_world_pos.distance_to(weak_point_world) > aim_tolerance_px:
		return false
	return distance_point_to_segment(weak_point_world, hilt_pos, tip_pos) <= precision_radius_px


static func compute_angular_substeps(start_angle_rad: float, target_angle_rad: float) -> PackedFloat64Array:
	var diff: float = angle_difference(start_angle_rad, target_angle_rad)
	var max_step_rad: float = deg_to_rad(MAX_ANGULAR_STEP_DEG)
	var steps: int = maxi(1, ceili(absf(diff) / max_step_rad))
	var angles: PackedFloat64Array = PackedFloat64Array()
	angles.resize(steps)
	for i: int in range(steps):
		angles[i] = start_angle_rad + diff * (float(i + 1) / float(steps))
	return angles


static func calculate_structural_weapon_damage(
	weapon: WeaponData,
	attacker_str: float,
	attack_type: PenetrationResolver.AttackType,
	aura_bonuses: PenetrationResolver.AuraBonuses
) -> float:
	if weapon == null:
		return 0.0
	var base: float = weapon.mass_factor * 0.65 + weapon.base_penetration * 0.15
	var str_mult: float = pow(maxf(1.0, attacker_str) / StatSheet.HUMAN_REFERENCE, 1.05)
	var type_mult: float = 1.0
	if attack_type == PenetrationResolver.AttackType.BLUNT:
		type_mult = 1.40
	elif attack_type == PenetrationResolver.AttackType.THRUST:
		type_mult = 0.70
	var aura_dmg: float = aura_bonuses.impact_bonus * 0.50 if (aura_bonuses != null and aura_bonuses.active) else 0.0
	return maxf(1.0, base * str_mult * type_mult + aura_dmg)


## Sweeps weapon geometry (SLASH arc <= 5 deg, THRUST narrow ray, BLUNT impulse arc) to target_angle_rad.
## origin_world is the actor's ground/shadow footprint (for walls & floor tiles);
## combat hitboxes & Blade Clash segments are swept in visual elevation space.
## Returns structured events ("blade_clash", "entity", "out_of_vertical_reach", "wall", "floor").
func sweep_to_angle(
	origin_world: Vector2,
	target_angle_rad: float,
	weapon: WeaponData,
	attacker_sheet: StatSheet,
	attacker_floor: int,
	attacker_height_z: float,
	aura_active: bool,
	aim_world_pos: Vector2,
	attacker_node: Node = null,
	arena: TestArena = null,
	allow_floor_break: bool = true,
	origin_combat_override: Vector2 = Vector2(INF, INF),
	attack_type: PenetrationResolver.AttackType = PenetrationResolver.AttackType.SLASH,
	half_swording: bool = false,
	thrust_extension_ratio: float = 1.0,
	is_counter_attack: bool = false
) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not _swing_active or weapon == null or attacker_sheet == null:
		return events

	_active_attack_type = attack_type
	var effective_half_sword: bool = half_swording and weapon.can_half_sword
	_active_half_swording = effective_half_sword

	var world_2d: World2D = get_world_2d()
	if world_2d == null:
		_last_angle_rad = target_angle_rad
		return events

	var space_state: PhysicsDirectSpaceState2D = world_2d.direct_space_state
	var flm: Node = _get_floor_manager()
	var wall_mask: int = int(flm.call("get_high_walls_bit", attacker_floor)) if flm != null else 0
	var attacker_str: float = attacker_sheet.get_stat(StatSheet.Stat.STR)
	var attacker_m_ctrl: float = attacker_sheet.get_stat(StatSheet.Stat.M_CTRL) if attacker_sheet.mana_awakened else 0.0
	var aura_bonuses: PenetrationResolver.AuraBonuses = PenetrationResolver.calculate_aura_bonuses(aura_active, attacker_m_ctrl)

	var base_blade_len: float = weapon.get_effective_blade_length(effective_half_sword)
	if attack_type == PenetrationResolver.AttackType.THRUST:
		base_blade_len *= clampf(thrust_extension_ratio, 0.35, 1.0)
	var effective_reach: float = base_blade_len + aura_bonuses.blade_extension
	var total_tip_dist: float = weapon.hilt_offset_px + effective_reach
	var blade_start_dist: float = weapon.hilt_offset_px * 0.25

	var blade_radius: float = maxf(2.5, weapon.blade_width_px * 0.5)
	if attack_type == PenetrationResolver.AttackType.THRUST:
		blade_radius = maxf(1.8, weapon.blade_width_px * 0.32)
	elif attack_type == PenetrationResolver.AttackType.BLUNT:
		blade_radius = maxf(4.5, weapon.blade_width_px * 0.75)
	active_blade_radius = blade_radius

	var precision_radius: float = get_effective_precision_radius_px(attacker_sheet, attack_type, effective_half_sword)
	var aim_tolerance: float = get_aim_tolerance_px(attacker_sheet, attack_type, effective_half_sword)
	if is_counter_attack:
		precision_radius = minf(MAX_PRECISION_RADIUS_PX + 3.0, precision_radius + 3.0)
		aim_tolerance += 6.0
	var resolved_arena: TestArena = arena if arena != null else _find_arena()

	var origin_combat: Vector2 = origin_combat_override
	if not is_finite(origin_combat.x) or not is_finite(origin_combat.y):
		origin_combat = origin_world + Vector2(0.0, -attacker_height_z * VerticalityComponent.VISUAL_Y_OFFSET_PER_Z)

	var step_angles: PackedFloat64Array
	if attack_type == PenetrationResolver.AttackType.THRUST:
		step_angles = PackedFloat64Array([target_angle_rad])
	else:
		step_angles = compute_angular_substeps(_last_angle_rad, target_angle_rad)

	for step_angle: float in step_angles:
		var dir: Vector2 = Vector2.from_angle(step_angle)
		var tip_ground: Vector2 = origin_world + dir * total_tip_dist
		var active_tip_dist: float = total_tip_dist

		# 1. Wall collision along ground footprint [origin_world, tip_ground]
		if wall_mask != 0:
			var wall_query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(origin_world, tip_ground, wall_mask)
			wall_query.collide_with_bodies = true
			wall_query.collide_with_areas = false
			if attacker_node is CollisionObject2D:
				wall_query.exclude = [(attacker_node as CollisionObject2D).get_rid()]
			var wall_hit: Dictionary = space_state.intersect_ray(wall_query)
			if not wall_hit.is_empty():
				var hit_pos: Vector2 = wall_hit["position"] as Vector2
				var hit_normal: Vector2 = wall_hit["normal"] as Vector2
				active_tip_dist = minf(total_tip_dist, origin_world.distance_to(hit_pos))
				if resolved_arena != null:
					var wall_cell: Vector2i = resolved_arena.world_to_cell(hit_pos - hit_normal * 2.0)
					if not _hit_wall_cells.has(wall_cell):
						_hit_wall_cells[wall_cell] = true
						var wall_dmg: float = calculate_structural_weapon_damage(weapon, attacker_str, attack_type, aura_bonuses)
						var wall_res: Dictionary = resolved_arena.try_damage_wall_at(
							attacker_floor,
							wall_cell,
							attacker_str,
							wall_dmg,
							aura_bonuses.active
						)
						if bool(wall_res.get("hit", false)):
							if bool(wall_res.get("weapon_wear", false)):
								weapon.apply_wear(0.08, attacker_sheet.get_extra_weapon_wear_mult(), aura_bonuses.active)
							events.append({
								"type": "wall",
								"cell": wall_cell,
								"result": wall_res,
								"hit_pos": hit_pos,
								"aura_heavy_hit": aura_bonuses.active,
							})

		var seg_start: Vector2 = origin_combat + dir * minf(blade_start_dist, active_tip_dist)
		var active_tip_combat: Vector2 = origin_combat + dir * active_tip_dist
		active_segment_start = seg_start
		active_segment_end = active_tip_combat
		_has_valid_segment = true

		# 1b. Mid-air Blade Clash check against opposing actors' active blade segments (GDD 7.2, 12.2)
		if is_inside_tree():
			var clash_ev: Dictionary = _check_active_blade_clash(
				seg_start,
				active_tip_combat,
				blade_radius,
				attacker_floor,
				attacker_height_z,
				weapon.vertical_reach,
				attacker_node
			)
			if not clash_ev.is_empty():
				events.append(clash_ev)

		# 2. HitboxZone Area2D intersection using solid convex CapsuleShape2D along [seg_start, active_tip_combat]
		var seg_len: float = seg_start.distance_to(active_tip_combat)
		var cap_shape: CapsuleShape2D = CapsuleShape2D.new()
		cap_shape.radius = blade_radius
		cap_shape.height = maxf(blade_radius * 2.0, seg_len + blade_radius * 2.0)

		var shape_query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
		shape_query.shape = cap_shape
		shape_query.transform = Transform2D(step_angle + PI * 0.5, (seg_start + active_tip_combat) * 0.5)
		shape_query.collision_mask = FloorLayerManager.BIT_HITBOX_ZONES
		shape_query.collide_with_areas = true
		shape_query.collide_with_bodies = false
		var overlaps: Array[Dictionary] = space_state.intersect_shape(shape_query, 32)

		var zones_by_actor: Dictionary = {}
		for hit: Dictionary in overlaps:
			var collider_obj: Object = hit.get("collider", null)
			if not (collider_obj is HitboxZone):
				continue
			var hz: HitboxZone = collider_obj as HitboxZone
			if hz.owner_actor == null or hz.owner_actor == attacker_node:
				continue
			if hz.anatomy != null and hz.anatomy.is_dead:
				continue
			var actor_id: int = hz.owner_actor.get_instance_id()
			if _hit_actor_ids.has(actor_id) or _clashed_actor_ids.has(actor_id):
				continue
			if hz.get_floor_level() != attacker_floor:
				continue
			if absf(attacker_height_z - hz.get_height_z()) > weapon.vertical_reach:
				_record_vertical_miss(events, actor_id, hz.owner_actor, hz, attacker_height_z, hz.get_height_z(), weapon.vertical_reach)
				continue
			if not zones_by_actor.has(actor_id):
				zones_by_actor[actor_id] = []
			(zones_by_actor[actor_id] as Array).append(hz)

		for actor_id_variant: Variant in zones_by_actor.keys():
			var actor_id: int = int(actor_id_variant)
			var actor_zones: Array = zones_by_actor[actor_id]
			var chosen_zone: HitboxZone = null
			var chosen_is_wp: bool = false
			var best_dist: float = INF
			var actor_aiming_at_wp: bool = false

			# GDD 7.4 Stealth / Backstab bonus: +35% standing, +60% (1.60x) when crouched or in StealthCoverZone
			var actor_aim_tol: float = aim_tolerance
			var actor_prec_rad: float = precision_radius
			var is_stealth_backstab: bool = false
			if not actor_zones.is_empty():
				var first_hz: HitboxZone = actor_zones[0] as HitboxZone
				if first_hz != null and first_hz.owner_actor is CombatActor and attacker_node != null:
					is_stealth_backstab = (first_hz.owner_actor as CombatActor).is_vulnerable_to_stealth_backstab(attacker_node)
					if is_stealth_backstab:
						var bs_mult: float = CombatActor.STEALTH_BACKSTAB_AIM_BONUS_MULT
						if attacker_node is CombatActor:
							bs_mult = (attacker_node as CombatActor).get_stealth_backstab_aim_mult(resolved_arena)
						actor_aim_tol *= bs_mult
						actor_prec_rad *= bs_mult

			for z_variant: Variant in actor_zones:
				var hz: HitboxZone = z_variant as HitboxZone
				for wp_world: Vector2 in hz.get_world_weak_points():
					if aim_world_pos.distance_to(wp_world) <= actor_aim_tol:
						actor_aiming_at_wp = true
					var is_wp: bool = check_weak_point_double_condition(
						wp_world,
						aim_world_pos,
						seg_start,
						active_tip_combat,
						actor_aim_tol,
						actor_prec_rad,
						attacker_floor,
						hz.get_floor_level(),
						attacker_height_z,
						hz.get_height_z(),
						weapon.vertical_reach
					)
					if is_wp:
						var wp_dist: float = distance_point_to_segment(wp_world, seg_start, active_tip_combat)
						if not chosen_is_wp or wp_dist < best_dist:
							chosen_zone = hz
							chosen_is_wp = true
							best_dist = wp_dist
				if not chosen_is_wp:
					var aim_dist: float = aim_world_pos.distance_to(hz.global_position)
					var seg_dist: float = distance_point_to_segment(hz.global_position, seg_start, active_tip_combat)
					var score: float = aim_dist * 0.65 + seg_dist * 0.35
					if chosen_zone == null or score < best_dist:
						chosen_zone = hz
						best_dist = score

			if chosen_zone != null:
				if not chosen_is_wp and not actor_aiming_at_wp:
					actor_aiming_at_wp = _is_aiming_near_actor_weak_point(chosen_zone.owner_actor, aim_world_pos, actor_aim_tol)

				var target_body_radius: float = 0.0
				if chosen_zone.owner_actor is CombatActor:
					target_body_radius = (chosen_zone.owner_actor as CombatActor).get_body_collision_radius()
				var target_dist: float = maxf(0.0, origin_world.distance_to(chosen_zone.owner_actor.global_position) - target_body_radius)
				var hit_payload: Dictionary = {
					"type": "entity",
					"target": chosen_zone.owner_actor,
					"zone": chosen_zone,
					"is_weak_point": chosen_is_wp,
					"is_stealth_backstab": is_stealth_backstab,
					"hilt_pos": seg_start,
					"tip_pos": active_tip_combat,
					"distance_to_target": target_dist,
					"attack_type": attack_type,
					"half_swording": effective_half_sword,
					"score": best_dist,
				}
				if chosen_is_wp or not actor_aiming_at_wp:
					_pending_body_hits.erase(actor_id)
					_hit_actor_ids[actor_id] = true
					events.append(hit_payload)
				else:
					if not _pending_body_hits.has(actor_id) or best_dist < float((_pending_body_hits[actor_id] as Dictionary).get("score", INF)):
						_pending_body_hits[actor_id] = hit_payload

		# 2b. Ground-shadow proximity check for out-of-vertical-reach feedback
		if is_inside_tree():
			_check_ground_proximity_vertical_misses(
				events,
				origin_world,
				step_angle,
				active_tip_dist,
				attacker_floor,
				attacker_height_z,
				weapon.vertical_reach,
				attacker_node
			)

		# 3. Breakable upper floor check (GDD 14.5)
		if allow_floor_break and attacker_floor >= 1 and attacker_height_z <= weapon.vertical_reach and _hit_actor_ids.is_empty() and resolved_arena != null:
			var tip_ground_active: Vector2 = origin_world + dir * active_tip_dist
			var floor_cell: Vector2i = resolved_arena.world_to_cell(tip_ground_active)
			if not _hit_floor_cells.has(floor_cell):
				_hit_floor_cells[floor_cell] = true
				var floor_dmg: float = calculate_structural_weapon_damage(weapon, attacker_str, attack_type, aura_bonuses)
				var floor_res: Dictionary = resolved_arena.try_break_floor_at(
					attacker_floor,
					floor_cell,
					attacker_str,
					aura_bonuses.active,
					floor_dmg
				)
				if bool(floor_res.get("hit", false)):
					if bool(floor_res.get("weapon_wear", false)):
						weapon.apply_wear(0.06, attacker_sheet.get_extra_weapon_wear_mult(), aura_bonuses.active)
					events.append({
						"type": "floor",
						"cell": floor_cell,
						"result": floor_res,
					})

	_last_angle_rad = target_angle_rad
	return events


func _check_active_blade_clash(
	seg_start: Vector2,
	seg_end: Vector2,
	blade_radius: float,
	attacker_floor: int,
	attacker_height_z: float,
	vertical_reach: float,
	attacker_node: Node
) -> Dictionary:
	var attacker_id: int = attacker_node.get_instance_id() if attacker_node != null else 0
	var groups_to_check: Array[StringName] = [&"enemies", &"player"]
	for grp: StringName in groups_to_check:
		for n: Node in get_tree().get_nodes_in_group(grp):
			if n == attacker_node or not (n is CombatActor):
				continue
			var other: CombatActor = n as CombatActor
			if not other.is_alive() or other.equipped_weapon == null:
				continue
			if other.combat_state != CombatActor.CombatState.ACTIVE:
				continue
			var other_id: int = other.get_instance_id()
			if _clashed_actor_ids.has(other_id):
				continue
			if other.get_floor_level() != attacker_floor:
				continue
			if absf(attacker_height_z - other.get_height_z()) > maxf(vertical_reach, other.equipped_weapon.vertical_reach):
				continue

			var other_seg: PackedVector2Array = other.get_current_blade_segment()
			if other_seg.size() < 2:
				continue
			var other_radius: float = other.sweeper.active_blade_radius if other.sweeper != null else 3.0
			var hit_info: Dictionary = segments_intersect(
				seg_start,
				seg_end,
				other_seg[0],
				other_seg[1],
				blade_radius + other_radius
			)
			if bool(hit_info.get("intersects", false)):
				mark_clashed_with(other_id)
				if other.sweeper != null and attacker_id != 0:
					other.sweeper.mark_clashed_with(attacker_id)
				return {
					"type": "blade_clash",
					"other": other,
					"clash_point": hit_info.get("point", (seg_start + seg_end) * 0.5),
				}
	return {}


func _is_aiming_near_actor_weak_point(actor: Node, aim_world_pos: Vector2, aim_tolerance: float) -> bool:
	if actor == null or not is_instance_valid(actor) or not (actor is CombatActor):
		return false
	for hz: HitboxZone in (actor as CombatActor).hitbox_zones:
		if not is_instance_valid(hz) or not hz.monitorable:
			continue
		for wp_world: Vector2 in hz.get_world_weak_points():
			if aim_world_pos.distance_to(wp_world) <= aim_tolerance:
				return true
	return false


func _record_vertical_miss(
	events: Array[Dictionary],
	actor_id: int,
	target_actor: Node,
	zone: HitboxZone,
	attacker_z: float,
	target_z: float,
	v_reach: float
) -> void:
	if _hit_actor_ids.has(actor_id) or _vertical_miss_actor_ids.has(actor_id):
		return
	_vertical_miss_actor_ids[actor_id] = true
	events.append({
		"type": "out_of_vertical_reach",
		"target": target_actor,
		"zone": zone,
		"attacker_height_z": attacker_z,
		"target_height_z": target_z,
		"vertical_reach": v_reach,
	})


func _check_ground_proximity_vertical_misses(
	events: Array[Dictionary],
	origin_ground: Vector2,
	step_angle: float,
	active_reach_px: float,
	attacker_floor: int,
	attacker_height_z: float,
	vertical_reach: float,
	attacker_node: Node
) -> void:
	var groups_to_check: Array[StringName] = [&"enemies", &"player"]
	for grp: StringName in groups_to_check:
		for n: Node in get_tree().get_nodes_in_group(grp):
			if n == attacker_node or not (n is CombatActor):
				continue
			var actor: CombatActor = n as CombatActor
			if not actor.is_alive():
				continue
			var actor_id: int = actor.get_instance_id()
			if _hit_actor_ids.has(actor_id) or _vertical_miss_actor_ids.has(actor_id):
				continue
			if actor.get_floor_level() != attacker_floor:
				continue
			if absf(attacker_height_z - actor.get_height_z()) <= vertical_reach:
				continue
			var to_actor: Vector2 = actor.global_position - origin_ground
			var dist: float = to_actor.length()
			if dist > active_reach_px + 18.0:
				continue
			if dist > 4.0 and absf(angle_difference(step_angle, to_actor.angle())) > deg_to_rad(45.0):
				continue
			var fallback_zone: HitboxZone = actor.hitbox_zones[0] if not actor.hitbox_zones.is_empty() else null
			_record_vertical_miss(events, actor_id, actor, fallback_zone, attacker_height_z, actor.get_height_z(), vertical_reach)


func _find_arena() -> TestArena:
	if not is_inside_tree():
		return null
	var arenas: Array[Node] = get_tree().get_nodes_in_group(&"test_arena")
	for n: Node in arenas:
		if n is TestArena:
			return n as TestArena
	return null


func _get_floor_manager() -> Node:
	if is_inside_tree() and get_tree().root != null:
		return get_tree().root.get_node_or_null("FloorLayerManager")
	return null
