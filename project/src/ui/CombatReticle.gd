class_name CombatReticle
extends Node2D
## Procedural world-space Combat Reticle (Stage B, zero external assets).
## Adapts shape/color to SLASH / THRUST / BLUNT, tightens on Half-swording,
## shows an orange Dead Zone warning when an enemy is inside min_optimal_range,
## and locks onto weak points with a crimson-gold reticle when INT>=300 or highlight is enabled.

const COLOR_SLASH: Color = Color("#F5F7FA")
const COLOR_THRUST: Color = Color("#FF6B6B")
const COLOR_BLUNT: Color = Color("#A29BFE")
const COLOR_DEAD_ZONE: Color = Color("#FF7F11")
const COLOR_WEAK_POINT_LOCK: Color = Color("#FFD166")
const COLOR_WEAK_POINT_CORE: Color = Color("#FF3B3B")

var last_state: Dictionary = {
	"visible": false,
	"attack_type": PenetrationResolver.AttackType.SLASH,
	"half_swording": false,
	"in_dead_zone": false,
	"weak_point_locked": false,
	"weak_point_pos": Vector2.ZERO,
	"dead_zone_target_pos": Vector2.ZERO,
	"reticle_pos": Vector2.ZERO,
	"stealth_backstab_ready": false,
	"stealth_takedown_ready": false,
	"stealth_hint_text": "",
}

var stealth_hint_label: Label = null
var _pulse_time: float = 0.0


func _ready() -> void:
	z_as_relative = false
	z_index = 900
	stealth_hint_label = get_node_or_null("StealthHintLabel") as Label
	if stealth_hint_label == null:
		stealth_hint_label = Label.new()
		stealth_hint_label.name = "StealthHintLabel"
		add_child(stealth_hint_label)
	stealth_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stealth_hint_label.custom_minimum_size = Vector2(120.0, 0.0)
	stealth_hint_label.position = Vector2(-60.0, 11.0)
	stealth_hint_label.add_theme_font_size_override("font_size", 6)
	stealth_hint_label.add_theme_color_override("font_color", Color("#74EBD5"))
	stealth_hint_label.add_theme_color_override("font_outline_color", Color(0.05, 0.06, 0.09, 0.95))
	stealth_hint_label.add_theme_constant_override("outline_size", 2)
	stealth_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stealth_hint_label.focus_mode = Control.FOCUS_NONE
	stealth_hint_label.visible = false


func _process(delta: float) -> void:
	_pulse_time += delta
	var player: PlayerController = _find_player()
	if player == null or not player.is_alive():
		last_state["visible"] = false
		visible = false
		return
	visible = true
	var aim_pos: Vector2 = player.get_global_mouse_position() if DisplayServer.get_name() != "headless" else player.aim_world_pos
	evaluate_reticle_state(player, aim_pos)
	queue_redraw()


## Pure-ish deterministic state evaluator for both live rendering and unit testing.
func evaluate_reticle_state(player: PlayerController, aim_world: Vector2) -> Dictionary:
	var state: Dictionary = {
		"visible": false,
		"attack_type": PenetrationResolver.AttackType.SLASH,
		"half_swording": false,
		"in_dead_zone": false,
		"weak_point_locked": false,
		"weak_point_pos": Vector2.ZERO,
		"dead_zone_target_pos": Vector2.ZERO,
		"reticle_pos": aim_world,
		"stealth_backstab_ready": false,
		"stealth_takedown_ready": false,
		"stealth_hint_text": "",
	}
	if player == null or not is_instance_valid(player) or not player.is_alive() or player.stat_sheet == null:
		last_state = state
		if stealth_hint_label != null:
			stealth_hint_label.visible = false
		return state

	var arena: TestArena = _find_arena()

	var active_wpn: WeaponData = player.get_active_weapon()
	var atk_type: PenetrationResolver.AttackType = player.current_attack_type
	if active_wpn != null and active_wpn.is_unarmed:
		atk_type = PenetrationResolver.AttackType.BLUNT
	var hs: bool = player.half_swording and active_wpn != null and active_wpn.can_half_sword

	state["visible"] = true
	state["attack_type"] = atk_type
	state["half_swording"] = hs

	var player_floor: int = player.get_floor_level()
	var player_z: float = player.get_height_z()
	var v_reach: float = active_wpn.vertical_reach if active_wpn != null else 0.6

	# 1. Dead Zone proximity check (long weapon without Half-swording)
	if active_wpn != null and active_wpn.min_optimal_range > 0.0 and not hs and is_inside_tree():
		var best_dz_dist: float = INF
		for n: Node in get_tree().get_nodes_in_group(&"enemies"):
			if not (n is CombatActor):
				continue
			var enemy: CombatActor = n as CombatActor
			if not enemy.is_alive() or enemy.get_floor_level() != player_floor:
				continue
			if absf(player_z - enemy.get_height_z()) > v_reach:
				continue
			var center_dist: float = player.global_position.distance_to(enemy.global_position)
			var surf_dist: float = maxf(0.0, center_dist - player.get_body_collision_radius() - enemy.get_body_collision_radius())
			if surf_dist < active_wpn.min_optimal_range and surf_dist < best_dz_dist:
				best_dz_dist = surf_dist
				state["in_dead_zone"] = true
				state["dead_zone_target_pos"] = enemy.get_combat_origin()

	# 2. Weak-Point Lock check (when INT>=300 auto-highlight or Debug weak-point highlight is active)
	var wp_visible: bool = player.stat_sheet.can_auto_highlight_weak_points() or (EventBus != null and EventBus.debug_highlight_weak_points)
	if wp_visible and is_inside_tree():
		var aim_tol: float = WeaponRaySweeper.get_aim_tolerance_px(player.stat_sheet, atk_type, hs)
		if player.counter_window_timer > 0.0:
			aim_tol += 6.0
		var best_wp_dist: float = INF
		for n: Node in get_tree().get_nodes_in_group(&"hitbox_zones"):
			if not (n is HitboxZone):
				continue
			var hz: HitboxZone = n as HitboxZone
			if hz.owner_actor == null or hz.owner_actor == player or not is_instance_valid(hz.owner_actor):
				continue
			if hz.anatomy != null and hz.anatomy.is_dead:
				continue
			if hz.get_floor_level() != player_floor:
				continue
			if absf(player_z - hz.get_height_z()) > v_reach:
				continue
			var zone_tol: float = aim_tol
			if hz.owner_actor is CombatActor and (hz.owner_actor as CombatActor).is_vulnerable_to_stealth_backstab(player):
				zone_tol *= player.get_stealth_backstab_aim_mult(arena)
			for wp_world: Vector2 in hz.get_world_weak_points():
				var d: float = aim_world.distance_to(wp_world)
				if d <= zone_tol and d <= best_wp_dist:
					best_wp_dist = d
					state["weak_point_locked"] = true
					state["weak_point_pos"] = wp_world

	# 3. Stealth Backstab / Takedown hover hint when aiming at an unaware enemy's back
	if is_inside_tree():
		for n: Node in get_tree().get_nodes_in_group(&"enemies"):
			if not (n is CombatActor):
				continue
			var enemy: CombatActor = n as CombatActor
			if not enemy.is_alive() or enemy.get_floor_level() != player_floor:
				continue
			if enemy.anatomy != null and enemy.anatomy.is_unconscious:
				continue
			if aim_world.distance_to(enemy.get_combat_origin()) <= 26.0 * enemy.actor_size_mult:
				if enemy.is_vulnerable_to_stealth_backstab(player):
					state["stealth_backstab_ready"] = true
					if player.can_perform_stealth_takedown(enemy):
						state["stealth_takedown_ready"] = true
					break
		var bs_ready: bool = bool(state["stealth_backstab_ready"])
		var td_ready: bool = bool(state["stealth_takedown_ready"])
		if td_ready and bs_ready:
			state["stealth_hint_text"] = "BACKSTAB | Q: KO"
		elif td_ready:
			state["stealth_hint_text"] = "Q: KO"
		elif bs_ready:
			state["stealth_hint_text"] = "BACKSTAB"

	if stealth_hint_label != null:
		var hint_txt: String = String(state["stealth_hint_text"])
		stealth_hint_label.visible = not hint_txt.is_empty()
		if stealth_hint_label.visible:
			stealth_hint_label.text = hint_txt
			stealth_hint_label.add_theme_color_override(
				"font_color",
				Color("#74EBD5") if bool(state["stealth_takedown_ready"]) else Color("#FFD166")
			)

	global_position = aim_world
	last_state = state
	return state


func _draw() -> void:
	if not bool(last_state.get("visible", false)):
		return
	var atk_type: PenetrationResolver.AttackType = int(last_state.get("attack_type", PenetrationResolver.AttackType.SLASH)) as PenetrationResolver.AttackType
	var hs: bool = bool(last_state.get("half_swording", false))
	var in_dz: bool = bool(last_state.get("in_dead_zone", false))
	var wp_locked: bool = bool(last_state.get("weak_point_locked", false))

	var base_r: float = 5.5 if hs else 8.5
	var col: Color = COLOR_SLASH
	if atk_type == PenetrationResolver.AttackType.THRUST:
		col = COLOR_THRUST
	elif atk_type == PenetrationResolver.AttackType.BLUNT:
		col = COLOR_BLUNT
	if wp_locked:
		col = COLOR_WEAK_POINT_LOCK

	# Core shape per attack mode
	match atk_type:
		PenetrationResolver.AttackType.THRUST:
			# Crisp diamond + needle ticks
			var pts: PackedVector2Array = PackedVector2Array([
				Vector2(0.0, -base_r),
				Vector2(base_r, 0.0),
				Vector2(0.0, base_r),
				Vector2(-base_r, 0.0),
				Vector2(0.0, -base_r),
			])
			draw_polyline(pts, col, 1.3)
			draw_circle(Vector2.ZERO, 1.4, COLOR_WEAK_POINT_CORE if wp_locked else col)
		PenetrationResolver.AttackType.BLUNT:
			# Bold octagon / impact ring
			draw_arc(Vector2.ZERO, base_r, 0.0, TAU, 8, col, 1.6)
			draw_line(Vector2(-3.0, 0.0), Vector2(3.0, 0.0), col, 1.2)
			draw_line(Vector2(0.0, -3.0), Vector2(0.0, 3.0), col, 1.2)
		_:
			# SLASH: twin curved arc brackets
			draw_arc(Vector2.ZERO, base_r, -0.75, 0.75, 8, col, 1.4)
			draw_arc(Vector2.ZERO, base_r, PI - 0.75, PI + 0.75, 8, col, 1.4)
			draw_circle(Vector2.ZERO, 1.2, col)

	# Dead Zone pulsing orange warning halo
	if in_dz:
		var pulse_r: float = base_r + 3.5 + sin(_pulse_time * 10.0) * 1.2
		draw_arc(Vector2.ZERO, pulse_r, 0.0, TAU, 16, COLOR_DEAD_ZONE, 1.4)
		for k: int in range(4):
			var a: float = PI * 0.25 + float(k) * PI * 0.5
			var d: Vector2 = Vector2.from_angle(a)
			draw_line(d * (pulse_r - 1.5), d * (pulse_r + 2.5), COLOR_DEAD_ZONE, 1.5)

	# Weak-Point Lock crimson-gold snap reticle on exact weak point
	if wp_locked:
		var wp_local: Vector2 = to_local(last_state["weak_point_pos"] as Vector2)
		var lock_r: float = 4.5 + sin(_pulse_time * 14.0) * 0.7
		var lock_pts: PackedVector2Array = PackedVector2Array([
			wp_local + Vector2(0.0, -lock_r),
			wp_local + Vector2(lock_r, 0.0),
			wp_local + Vector2(0.0, lock_r),
			wp_local + Vector2(-lock_r, 0.0),
			wp_local + Vector2(0.0, -lock_r),
		])
		draw_polyline(lock_pts, COLOR_WEAK_POINT_LOCK, 1.6)
		draw_circle(wp_local, 1.8, COLOR_WEAK_POINT_CORE)


func _find_player() -> PlayerController:
	if not is_inside_tree():
		return null
	for n: Node in get_tree().get_nodes_in_group(&"player"):
		if n is PlayerController:
			return n as PlayerController
	return null


func _find_arena() -> TestArena:
	if not is_inside_tree():
		return null
	for n: Node in get_tree().get_nodes_in_group(&"test_arena"):
		if n is TestArena:
			return n as TestArena
	return null
