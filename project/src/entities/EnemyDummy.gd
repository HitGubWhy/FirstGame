class_name EnemyDummy
extends CombatActor
## Stage 0 v0.2 Test Enemy supporting 3 presets (GDD Sections 2.3, 7.4, 12.1, 14.1, 14.3, 14.4):
##   0: Rank 1 Swordsman (12 stats=10, alternates SLASH/THRUST + Feints)
##   1: Rank 6 Armored Hovering Guard (12 stats=100, REG=60, height_z=1.5, armor 20x15, Imperceptible Speed)
##   2: Rank 4 Troll Berserker (STR/CON=45, SPD/TP=25, REG=160, size_mult=1.3, light hide, blade lodging & limb regrowth)
## Implements PATROL (1.0x) -> COMBAT (full enemy.SPD + active_aggro_ids) -> SEARCH (4.0s by LOS/noise/blood) -> PATROL,
## SafeBarrierZone aggro reset, and INT + TP Intention Reading visual telegraphs (solid vs dashed feint arc).

signal imperceptible_strike_triggered(target: CombatActor, zone_name: StringName)
signal ai_state_changed(old_state: int, new_state: int)

enum EnemyPreset {
	RANK_1_SWORDSMAN = 0,
	RANK_6_GUARD = 1,
	TROLL_BERSERKER = 2,
}

enum AIState {
	PATROL = 0,
	COMBAT = 1,
	SEARCH = 2,
}

const DAGGER_TEMPLATE_PATH: String = "res://data/dagger.tres"
const GREATSWORD_TEMPLATE_PATH: String = "res://data/greatsword.tres"
const WARHAMMER_TEMPLATE_PATH: String = "res://data/warhammer.tres"

const SEARCH_DURATION_SEC: float = 4.0
const GUARD_HOVER_Z: float = 1.5
const GUARD_DIVE_RATE_PER_SEC: float = 3.2
const STAIRS_PURSUIT_RADIUS_PX: float = 140.0
const WEAPON_RETRIEVE_RADIUS_PX: float = 120.0
const WEAPON_RETRIEVE_PICKUP_DIST_PX: float = 40.0
const WEAPON_RETRIEVE_MAX_CHASE_SEC: float = 3.5
const WEAPON_RETRIEVE_RETRY_COOLDOWN_SEC: float = 2.0
const LODGED_EXTRACT_COOLDOWN_SEC: float = 3.0
const NIGHT_VISION_RADIUS_MULT: float = 0.72
const NIGHT_VISION_CONE_MULT: float = 0.85
const BLOOD_MOON_VISION_RADIUS_MULT: float = 1.25
const BLOOD_MOON_VISION_CONE_MULT: float = 1.15
const BLOOD_MOON_LEASH_MULT: float = 1.20
const PROXIMITY_SENSE_STANDING_PX: float = 45.0
const PROXIMITY_SENSE_CROUCH_PX: float = 16.0
const INSTANT_SPOT_DIST_PX: float = 75.0
const SUSPICION_SEARCH_THRESHOLD: float = 0.35
const SUSPICION_DECAY_PER_SEC: float = 0.24
const COLOR_TELEGRAPH_THRUST: Color = Color("#FF3B3B")
const COLOR_TELEGRAPH_SLASH: Color = Color("#FF9500")
const COLOR_TELEGRAPH_BLUNT: Color = Color("#7B61FF")
const COLOR_TELEGRAPH_UNREADABLE: Color = Color(0.75, 0.75, 0.80, 0.48)


## Procedural arc & arrow windup telegraph drawn around the enemy based on observer INT + TP.
class TelegraphDrawer extends Node2D:
	var show_telegraph: bool = false
	var draw_color: Color = Color("#FF9500")
	var dashed: bool = false
	var center_angle: float = 0.0
	var arc_span_rad: float = 1.2
	var radius_px: float = 22.0
	var is_thrust_arrow: bool = false

	func _draw() -> void:
		if not show_telegraph:
			return
		if is_thrust_arrow:
			var dir: Vector2 = Vector2.from_angle(center_angle)
			var start_p: Vector2 = dir * (radius_px * 0.55)
			var end_p: Vector2 = dir * (radius_px + 14.0)
			if dashed:
				var segs: int = 5
				for i: int in range(0, segs, 2):
					var p0: Vector2 = start_p.lerp(end_p, float(i) / float(segs))
					var p1: Vector2 = start_p.lerp(end_p, float(mini(segs, i + 1)) / float(segs))
					draw_line(p0, p1, draw_color, 2.0)
			else:
				draw_line(start_p, end_p, draw_color, 2.2)
			var perp: Vector2 = Vector2(-dir.y, dir.x)
			draw_line(end_p, end_p - dir * 5.0 + perp * 3.5, draw_color, 2.0)
			draw_line(end_p, end_p - dir * 5.0 - perp * 3.5, draw_color, 2.0)
			return

		var start_a: float = center_angle - arc_span_rad * 0.5
		var end_a: float = center_angle + arc_span_rad * 0.5
		if dashed:
			var chunks: int = 8
			for i: int in range(0, chunks, 2):
				var a0: float = lerpf(start_a, end_a, float(i) / float(chunks))
				var a1: float = lerpf(start_a, end_a, float(mini(chunks, i + 1)) / float(chunks))
				draw_arc(Vector2.ZERO, radius_px, a0, a1, 5, draw_color, 2.2)
		else:
			draw_arc(Vector2.ZERO, radius_px, start_a, end_a, 14, draw_color, 2.4)
		var tip_dir: Vector2 = Vector2.from_angle(center_angle)
		draw_circle(tip_dir * radius_px, 2.2, draw_color)


## Lightweight world-space Blood & Shock micro-bars above enemy head (only visible in combat or when wounded/KO/prone).
class StatusOverlayDrawer extends Node2D:
	var show_bars: bool = false
	var blood_ratio: float = 1.0
	var shock_ratio: float = 0.0
	var y_offset: float = -18.0
	var bar_width: float = 22.0

	func _draw() -> void:
		if not show_bars:
			return
		var half_w: float = bar_width * 0.5
		var bg_rect: Rect2 = Rect2(Vector2(-half_w - 1.0, y_offset - 1.0), Vector2(bar_width + 2.0, 6.5))
		draw_rect(bg_rect, Color(0.05, 0.06, 0.09, 0.85), true)
		var bld_w: float = bar_width * clampf(blood_ratio, 0.0, 1.0)
		if bld_w > 0.2:
			draw_rect(Rect2(Vector2(-half_w, y_offset), Vector2(bld_w, 2.2)), Color("#E74C3C"), true)
		var shk_w: float = bar_width * clampf(shock_ratio, 0.0, 1.0)
		if shk_w > 0.2:
			draw_rect(Rect2(Vector2(-half_w, y_offset + 2.8), Vector2(shk_w, 1.7)), Color("#F39C12"), true)


## Translucent floor-level vision cone sector rendered during stealth / suspicion (z_index = floor * 100 - 2).
class VisionConeDrawer extends Node2D:
	var show_cone: bool = false
	var center_angle: float = 0.0
	var half_angle_rad: float = deg_to_rad(75.0)
	var radius_px: float = 150.0
	var fill_color: Color = Color(1.0, 0.90, 0.35, 0.13)
	var edge_color: Color = Color(1.0, 0.90, 0.35, 0.32)

	func _draw() -> void:
		if not show_cone or radius_px <= 2.0:
			return
		var steps: int = 18
		var pts: PackedVector2Array = PackedVector2Array()
		pts.append(Vector2.ZERO)
		var start_a: float = center_angle - half_angle_rad
		var end_a: float = center_angle + half_angle_rad
		for i: int in range(steps + 1):
			var a: float = lerpf(start_a, end_a, float(i) / float(steps))
			pts.append(Vector2.from_angle(a) * radius_px)
		draw_colored_polygon(pts, fill_color)
		draw_line(Vector2.ZERO, pts[1], edge_color, 1.1)
		draw_line(Vector2.ZERO, pts[pts.size() - 1], edge_color, 1.1)
		draw_arc(Vector2.ZERO, radius_px, start_a, end_a, steps, edge_color, 1.2)


@export var preset: EnemyPreset = EnemyPreset.RANK_1_SWORDSMAN
@export var patrol_distance_px: float = 48.0
@export var aggro_radius_px: float = 150.0
@export var leash_radius_px: float = 320.0
@export var dash_strike_reach_px: float = 110.0
@export var vision_half_angle_deg: float = 75.0
@export var smell_radius_px: float = 160.0
@export var ai_enabled: bool = true
@export var ai_profile: EnemyAIProfile = null

var ai_brain: CombatBrain = null
var ai_state: AIState = AIState.PATROL
var spawn_origin: Vector2 = Vector2.ZERO
var patrol_dir: float = 1.0
var attack_cooldown_timer: float = 0.0
var imperceptible_cooldown_timer: float = 0.0
var search_timer: float = 0.0
var search_target_pos: Vector2 = Vector2.ZERO
var last_known_target_pos: Vector2 = Vector2.ZERO
var current_target: CombatActor = null
var vertical_aggro_tolerance: float = 1.2
var suspicion_level: float = 0.0
var _known_downed_ally_ids: Dictionary[int, bool] = {}

# Navigation (AStarGrid2D), stairs pursuit & reactive tactical AI state
var _nav_path: PackedVector2Array = PackedVector2Array()
var _nav_path_index: int = 0
var _nav_repath_timer: float = 0.0
var _nav_last_goal: Vector2 = Vector2(INF, INF)
var _pursuing_stairs_to_floor: int = -999
var _recent_hits_taken: int = 0
var _recent_hits_decay_timer: float = 0.0
var _reactive_block_cooldown: float = 0.0
var _ai_block_hold_timer: float = 0.0
var _clinch_ai_cooldown: float = 0.0
var _weapon_retrieve_cooldown: float = 0.0
var _weapon_retrieve_active_timer: float = 0.0
var _lodged_extract_cooldown: float = 0.0

# Attack pattern & feint state for INT + TP Intention Reading
var _attack_cycle_index: int = 0
var planned_feint_active: bool = false
var _windup_total_duration: float = 0.40
var telegraph_drawer: TelegraphDrawer = null
var vision_cone_drawer: VisionConeDrawer = null
var status_overlay_drawer: StatusOverlayDrawer = null
var status_overlay_label: Label = null
var last_world_status: Dictionary = {
	"visible": false,
	"ai_marker": "PATROL",
	"status_tags": [],
	"label_text": "",
	"bars_visible": false,
	"blood_ratio": 1.0,
	"shock_ratio": 0.0,
}
var last_telegraph_state: Dictionary = {
	"visible": false,
	"readable": false,
	"feint_detected": false,
	"dashed": false,
	"color": COLOR_TELEGRAPH_UNREADABLE,
	"attack_type": PenetrationResolver.AttackType.SLASH,
}


func _ready() -> void:
	_configure_preset_before_ready()
	super._ready()
	add_to_group(&"enemies")
	spawn_origin = global_position
	_apply_preset_after_ready()
	_ensure_ai_brain()
	_connect_event_bus_safe()
	_setup_telegraph_drawer()
	_setup_vision_cone_drawer()
	_setup_status_overlay()
	update_vision_cone_visual()
	update_world_status_overlay()


func _exit_tree() -> void:
	_disconnect_event_bus_safe()
	_unregister_aggro_safe()


func _create_default_profile_for_preset() -> EnemyAIProfile:
	match preset:
		EnemyPreset.TROLL_BERSERKER:
			return EnemyAIProfile.create_berserker_profile()
		EnemyPreset.RANK_6_GUARD:
			return EnemyAIProfile.create_guardian_profile()
		_:
			return EnemyAIProfile.create_duelist_profile()


func _ensure_ai_brain() -> void:
	if ai_profile == null:
		ai_profile = _create_default_profile_for_preset()
	if ai_brain == null:
		ai_brain = BrainFactory.create_brain(ai_profile)


func set_ai_profile(new_profile: EnemyAIProfile) -> CombatBrain:
	ai_profile = new_profile.create_runtime_copy() if new_profile != null else _create_default_profile_for_preset()
	ai_brain = BrainFactory.create_brain(ai_profile)
	return ai_brain


func _connect_event_bus_safe() -> void:
	var bus: Node = _get_event_bus()
	if bus != null and bus.has_signal("combat_outcome_logged"):
		var cb: Callable = Callable(self, "_on_combat_outcome_logged")
		if not bus.is_connected("combat_outcome_logged", cb):
			bus.connect("combat_outcome_logged", cb)


func _disconnect_event_bus_safe() -> void:
	var main_loop: MainLoop = Engine.get_main_loop()
	if main_loop is SceneTree:
		var tree: SceneTree = main_loop as SceneTree
		if tree.root != null:
			var bus: Node = tree.root.get_node_or_null("EventBus")
			if bus != null and bus.has_signal("combat_outcome_logged"):
				var cb: Callable = Callable(self, "_on_combat_outcome_logged")
				if bus.is_connected("combat_outcome_logged", cb):
					bus.disconnect("combat_outcome_logged", cb)


func _on_combat_outcome_logged(outcome_data: Dictionary) -> void:
	if ai_brain == null or not is_alive():
		return
	if outcome_data.get("attacker", null) != self:
		return
	var out_str: String = String(outcome_data.get("outcome", ""))
	if out_str == "parried":
		ai_brain.on_attack_defended_by_target(true)
	elif out_str == "blocked" or out_str == "unarmed_block_cut":
		ai_brain.on_attack_defended_by_target(false)


func _setup_telegraph_drawer() -> void:
	if body_visual == null:
		return
	telegraph_drawer = body_visual.get_node_or_null("TelegraphDrawer") as TelegraphDrawer
	if telegraph_drawer == null:
		telegraph_drawer = TelegraphDrawer.new()
		telegraph_drawer.name = "TelegraphDrawer"
		body_visual.add_child(telegraph_drawer)
	telegraph_drawer.radius_px = 20.0 * actor_size_mult
	telegraph_drawer.z_index = 7


func _setup_vision_cone_drawer() -> void:
	vision_cone_drawer = get_node_or_null("VisionConeDrawer") as VisionConeDrawer
	if vision_cone_drawer == null:
		vision_cone_drawer = VisionConeDrawer.new()
		vision_cone_drawer.name = "VisionConeDrawer"
		add_child(vision_cone_drawer)
	vision_cone_drawer.z_as_relative = false
	vision_cone_drawer.z_index = get_floor_level() * 100 - 2


func update_vision_cone_visual() -> bool:
	if vision_cone_drawer == null:
		return false
	var fl: int = get_floor_level()
	vision_cone_drawer.z_as_relative = false
	vision_cone_drawer.z_index = fl * 100 - 2

	if not is_alive() or (anatomy != null and anatomy.is_unconscious):
		vision_cone_drawer.show_cone = false
		vision_cone_drawer.queue_redraw()
		return false

	var player: CombatActor = _find_player_actor()
	var arena: TestArena = _find_arena()
	var player_same_floor: bool = player != null and player.is_alive() and player.get_floor_level() == fl
	var player_sneaking: bool = player_same_floor and (
		player.is_crouching
		or player.is_prone()
		or (arena != null and arena.is_entity_in_stealth_cover(player))
	)
	var eff_r: float = get_effective_aggro_radius_px()
	var show_now: bool = player_sneaking or (player_same_floor and suspicion_level > 0.01)
	if not show_now and player_same_floor and ai_state != AIState.COMBAT and player.is_crouching:
		show_now = global_position.distance_to(player.global_position) <= eff_r + 120.0

	vision_cone_drawer.show_cone = show_now
	vision_cone_drawer.center_angle = aim_angle
	vision_cone_drawer.half_angle_rad = deg_to_rad(get_effective_vision_half_angle_deg())
	vision_cone_drawer.radius_px = eff_r

	if ai_state == AIState.COMBAT:
		vision_cone_drawer.fill_color = Color(1.0, 0.24, 0.24, 0.16)
		vision_cone_drawer.edge_color = Color(1.0, 0.35, 0.35, 0.38)
	else:
		var t: float = clampf(suspicion_level, 0.0, 1.0)
		var base_col: Color = Color(1.0, 0.90, 0.35, 1.0).lerp(Color(1.0, 0.48, 0.12, 1.0), t)
		vision_cone_drawer.fill_color = Color(base_col.r, base_col.g, base_col.b, lerpf(0.11, 0.22, t))
		vision_cone_drawer.edge_color = Color(base_col.r, base_col.g, base_col.b, lerpf(0.28, 0.48, t))

	vision_cone_drawer.queue_redraw()
	return show_now


func _setup_status_overlay() -> void:
	if body_visual == null:
		return
	var top_y: float = -23.0 * actor_size_mult - 3.0
	status_overlay_drawer = body_visual.get_node_or_null("StatusOverlayDrawer") as StatusOverlayDrawer
	if status_overlay_drawer == null:
		status_overlay_drawer = StatusOverlayDrawer.new()
		status_overlay_drawer.name = "StatusOverlayDrawer"
		body_visual.add_child(status_overlay_drawer)
	status_overlay_drawer.y_offset = top_y
	status_overlay_drawer.bar_width = clampf(20.0 * actor_size_mult, 18.0, 28.0)
	status_overlay_drawer.z_index = 8

	status_overlay_label = body_visual.get_node_or_null("StatusOverlayLabel") as Label
	if status_overlay_label == null:
		status_overlay_label = Label.new()
		status_overlay_label.name = "StatusOverlayLabel"
		body_visual.add_child(status_overlay_label)
	status_overlay_label.z_index = 8
	status_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_overlay_label.custom_minimum_size = Vector2(96.0, 0.0)
	status_overlay_label.position = Vector2(-48.0, top_y - 12.0)
	status_overlay_label.add_theme_font_size_override("font_size", 6)
	status_overlay_label.add_theme_color_override("font_outline_color", Color(0.05, 0.06, 0.09, 0.92))
	status_overlay_label.add_theme_constant_override("outline_size", 1)
	status_overlay_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_overlay_label.focus_mode = Control.FOCUS_NONE


func get_world_status_snapshot() -> Dictionary:
	return last_world_status.duplicate(true)


func update_world_status_overlay() -> Dictionary:
	if not is_alive():
		last_world_status = {
			"visible": false,
			"ai_marker": "",
			"status_tags": [],
			"label_text": "",
			"bars_visible": false,
			"blood_ratio": 0.0,
			"shock_ratio": 0.0,
		}
		if status_overlay_drawer != null:
			status_overlay_drawer.show_bars = false
			status_overlay_drawer.queue_redraw()
		if status_overlay_label != null:
			status_overlay_label.visible = false
		return last_world_status

	var ai_marker: String = "PATROL"
	var label_color: Color = Color(0.75, 0.80, 0.88, 0.48)
	if ai_state == AIState.COMBAT:
		ai_marker = "!"
		label_color = Color("#FF5252")
	elif ai_state == AIState.SEARCH:
		ai_marker = ("? %d%%" % int(round(suspicion_level * 100.0))) if suspicion_level > 0.01 else "?"
		label_color = Color("#FFB142")
	elif suspicion_level >= 0.05:
		ai_marker = "? %d%%" % int(round(suspicion_level * 100.0))
		label_color = Color("#FFE066")

	var tags: Array[String] = []
	if anatomy != null and anatomy.is_unconscious:
		tags.append("KO")
	if is_prone():
		tags.append("PRONE")
	if combat_state == CombatState.STAGGERED:
		tags.append("STAGGER")
	if is_hardening_active():
		tags.append("HARD")

	var blood_ratio: float = anatomy.get_blood_ratio() if anatomy != null else 1.0
	var shock_ratio: float = clampf(anatomy.shock_level / 100.0, 0.0, 1.0) if anatomy != null else 0.0
	var is_wounded: bool = (blood_ratio < 0.999) or (shock_ratio > 0.01) or (anatomy != null and not anatomy.get_all_wounds().is_empty())
	var show_bars: bool = (ai_state != AIState.PATROL) or is_wounded or not tags.is_empty()

	var parts: PackedStringArray = PackedStringArray([ai_marker])
	for t: String in tags:
		parts.append(t)
	var label_text: String = " ".join(parts)

	if not tags.is_empty():
		if tags.has("KO") or tags.has("PRONE"):
			label_color = Color("#FFD166")
		elif tags.has("STAGGER"):
			label_color = Color("#FF9F43")
		elif tags.has("HARD"):
			label_color = Color("#A8E6CF")

	last_world_status = {
		"visible": true,
		"ai_marker": ai_marker,
		"status_tags": tags,
		"label_text": label_text,
		"bars_visible": show_bars,
		"blood_ratio": blood_ratio,
		"shock_ratio": shock_ratio,
	}

	if status_overlay_drawer != null:
		status_overlay_drawer.show_bars = show_bars
		status_overlay_drawer.blood_ratio = blood_ratio
		status_overlay_drawer.shock_ratio = shock_ratio
		status_overlay_drawer.queue_redraw()
	if status_overlay_label != null:
		status_overlay_label.visible = true
		status_overlay_label.text = label_text
		status_overlay_label.add_theme_color_override("font_color", label_color)
	return last_world_status


func get_ai_state_name() -> StringName:
	match ai_state:
		AIState.PATROL:
			return &"PATROL"
		AIState.COMBAT:
			return &"COMBAT"
		AIState.SEARCH:
			return &"SEARCH"
		_:
			return &"UNKNOWN"


func _set_ai_state(new_state: AIState) -> void:
	if ai_state == new_state:
		return
	var old_state: AIState = ai_state
	ai_state = new_state
	if new_state == AIState.COMBAT:
		_register_aggro_safe()
	elif new_state == AIState.PATROL:
		_unregister_aggro_safe()
	ai_state_changed.emit(old_state, new_state)


func _register_aggro_safe() -> void:
	if SimulationClock != null:
		SimulationClock.register_aggro(get_instance_id())


func _unregister_aggro_safe() -> void:
	var main_loop: MainLoop = Engine.get_main_loop()
	if main_loop is SceneTree:
		var tree: SceneTree = main_loop as SceneTree
		if tree.root != null:
			var clock: Node = tree.root.get_node_or_null("SimulationClock")
			if clock != null and clock.has_method("unregister_aggro"):
				clock.call("unregister_aggro", get_instance_id())


func _on_anatomy_died(cause: String, zone: StringName) -> void:
	_set_ai_state(AIState.PATROL)
	_unregister_aggro_safe()
	suspicion_level = 0.0
	planned_feint_active = false
	if telegraph_drawer != null:
		telegraph_drawer.show_telegraph = false
		telegraph_drawer.queue_redraw()
	if vision_cone_drawer != null:
		vision_cone_drawer.show_cone = false
		vision_cone_drawer.queue_redraw()
	super._on_anatomy_died(cause, zone)


func _on_anatomy_knocked_out(reason: String, duration_sec: float) -> void:
	planned_feint_active = false
	if ai_state != AIState.PATROL:
		_set_ai_state(AIState.PATROL)
	_unregister_aggro_safe()
	suspicion_level = 0.0
	if telegraph_drawer != null:
		telegraph_drawer.show_telegraph = false
		telegraph_drawer.queue_redraw()
	if vision_cone_drawer != null:
		vision_cone_drawer.show_cone = false
		vision_cone_drawer.queue_redraw()
	super._on_anatomy_knocked_out(reason, duration_sec)


func _configure_preset_before_ready() -> void:
	match preset:
		EnemyPreset.RANK_1_SWORDSMAN:
			actor_display_name = "Rank1_Swordsman"
			actor_body_color = Color("#E8833A") # Orange per GDD 14.3
			visual_style = VisualStyle.RANK_1_SWORDSMAN
			actor_size_mult = 1.0
			actor_base_anatomy_thickness = 2.0
			actor_bone_density = 100.0
			vertical_aggro_tolerance = 1.2
			enable_instinct_dodge = false
			stat_sheet = StatSheet.new(StatSheet.DEFAULT_HUMAN_RACIAL_CAP, StatSheet.RacePreset.HUMAN)
			stat_sheet.set_all_base_stats(10.0, false)

		EnemyPreset.RANK_6_GUARD:
			actor_display_name = "Rank6_Guard"
			actor_body_color = Color("#8E44AD") # Purple per GDD 14.3
			visual_style = VisualStyle.RANK_6_GUARD
			actor_size_mult = 1.0
			actor_base_anatomy_thickness = 2.0
			actor_bone_density = 100.0
			vertical_aggro_tolerance = 2.5
			enable_instinct_dodge = false
			# Rank 6 Guard (GDD 14.4): 12 stats=100 (REG=60), active External Circulation (+12 -> 88 base = 100 eff)
			stat_sheet = StatSheet.new(StatSheet.DEFAULT_HUMAN_RACIAL_CAP, StatSheet.RacePreset.HUMAN)
			stat_sheet.awaken_mana(100.0, 100.0)
			stat_sheet.set_all_base_stats(100.0, true)
			stat_sheet.set_base_stat(StatSheet.Stat.REG, 60.0)
			for circ_stat: int in StatSheet.CIRCULATION_STATS:
				stat_sheet.set_base_stat(circ_stat, 88.0)

		EnemyPreset.TROLL_BERSERKER:
			actor_display_name = "Troll_Berserker"
			actor_body_color = Color("#4E8A4E") # Mossy Troll Green
			visual_style = VisualStyle.TROLL_BERSERKER
			actor_size_mult = 1.3
			actor_base_anatomy_thickness = 2.0
			actor_bone_density = 120.0
			vertical_aggro_tolerance = 1.4
			enable_instinct_dodge = false
			# Rank 4 Troll Berserker (GDD 14.4): STR/CON=45, SPD/TP=25, REG=160, size_mult=1.3
			# M_CTRL=10 keeps circ_stat_bonus == 0 so exact effective STR/CON=45 & SPD/TP=25!
			stat_sheet = StatSheet.new(StatSheet.DEFAULT_HUMAN_RACIAL_CAP, StatSheet.RacePreset.TROLL)
			stat_sheet.awaken_mana(60.0, 10.0)
			stat_sheet.set_base_stat(StatSheet.Stat.STR, 45.0)
			stat_sheet.set_base_stat(StatSheet.Stat.CTRL, 35.0)
			stat_sheet.set_base_stat(StatSheet.Stat.SPD, 25.0)
			stat_sheet.set_base_stat(StatSheet.Stat.AGI, 20.0)
			stat_sheet.set_base_stat(StatSheet.Stat.CON, 45.0)
			stat_sheet.set_base_stat(StatSheet.Stat.STA, 80.0)
			stat_sheet.set_base_stat(StatSheet.Stat.TP, 25.0)
			stat_sheet.set_base_stat(StatSheet.Stat.INT, 10.0)
			stat_sheet.set_base_stat(StatSheet.Stat.MP_CAP, 60.0)
			stat_sheet.set_base_stat(StatSheet.Stat.M_CTRL, 10.0)
			stat_sheet.set_base_stat(StatSheet.Stat.SOUL, 25.0)
			stat_sheet.set_base_stat(StatSheet.Stat.REG, 160.0)


func _apply_preset_after_ready() -> void:
	match preset:
		EnemyPreset.RANK_1_SWORDSMAN:
			verticality.set_floor_level(0)
			verticality.set_height_z(0.0)
			attack_windup_override = 0.45
			attack_active_override = 0.15
			attack_recovery_override = 0.40
			var sword_tpl: WeaponData = load(DAGGER_TEMPLATE_PATH) as WeaponData
			if sword_tpl != null:
				var w: WeaponData = equip_weapon_template(sword_tpl)
				w.display_name = "Short Sword"
				w.blade_length = 20.0
				w.windup_sec = 0.45
				w.active_sec = 0.15
				w.recovery_sec = 0.40
				save_initial_weapon_backup()
				refresh_weapon_visual()
			rebuild_hitbox_zones(0.0, 0.0, {
				AnatomyComponent.ZONE_HEAD: [Vector2(0.0, -6.0)],
				AnatomyComponent.ZONE_CHEST: [Vector2(2.0, 2.0)],
			})

		EnemyPreset.RANK_6_GUARD:
			verticality.set_floor_level(0)
			verticality.preferred_flight_mode = VerticalityComponent.PreferredFlightMode.MANA
			verticality.set_flight_mode(VerticalityComponent.FlightMode.MANA_FLIGHT)
			verticality.set_height_z(GUARD_HOVER_Z) # Hovering at z = 1.5 via MANA_FLIGHT (GDD 14.4)
			attack_windup_override = 0.40
			attack_active_override = 0.16
			attack_recovery_override = 0.36
			var gs_tpl: WeaponData = load(GREATSWORD_TEMPLATE_PATH) as WeaponData
			if gs_tpl != null:
				equip_weapon_template(gs_tpl)
				save_initial_weapon_backup()
			rebuild_hitbox_zones(20.0, 15.0, {
				AnatomyComponent.ZONE_CHEST: [Vector2(0.0, 0.0)],
				AnatomyComponent.ZONE_HEAD: [Vector2(0.0, -6.0)],
			})

		EnemyPreset.TROLL_BERSERKER:
			verticality.set_floor_level(0)
			verticality.set_height_z(0.0)
			attack_windup_override = 0.48
			attack_active_override = 0.18
			attack_recovery_override = 0.42
			var wh_tpl: WeaponData = load(WARHAMMER_TEMPLATE_PATH) as WeaponData
			if wh_tpl != null:
				var club: WeaponData = equip_weapon_template(wh_tpl)
				club.display_name = "Troll Cleaver-Club"
				club.base_penetration = 20.0
				club.mass_factor = 32.0
				save_initial_weapon_backup()
				refresh_weapon_visual()
			# Light tough hide (no metal armor, armor_barrier = 6.0) + vital weak points
			rebuild_hitbox_zones(3.0, 2.0, {
				AnatomyComponent.ZONE_HEAD: [Vector2(0.0, -8.0 * actor_size_mult)],
				AnatomyComponent.ZONE_NECK: [Vector2(0.0, -3.5 * actor_size_mult)],
				AnatomyComponent.ZONE_CHEST: [Vector2(0.0, 1.0 * actor_size_mult)],
			})

	refill_resources()
	if preset == EnemyPreset.RANK_6_GUARD:
		set_flight_mode(VerticalityComponent.FlightMode.MANA_FLIGHT, GUARD_HOVER_Z)
	_apply_procedural_pose()


func _process(delta: float) -> void:
	tick_parry_window_subjective(delta)
	tick_crouch_visual(delta)
	update_telegraph_visual(_find_player_stat_sheet())
	update_vision_cone_visual()
	update_world_status_overlay()


func revive_and_heal_all() -> void:
	super.revive_and_heal_all()
	suspicion_level = 0.0
	_known_downed_ally_ids.clear()
	_recent_hits_taken = 0
	_recent_hits_decay_timer = 0.0
	_reactive_block_cooldown = 0.0
	_ai_block_hold_timer = 0.0
	_clinch_ai_cooldown = 0.0
	_weapon_retrieve_cooldown = 0.0
	_weapon_retrieve_active_timer = 0.0
	_lodged_extract_cooldown = 0.0
	_nav_path.clear()
	_nav_path_index = 0
	_nav_repath_timer = 0.0
	_pursuing_stairs_to_floor = -999
	if ai_brain != null:
		ai_brain.reset()
	set_aura_active(false)
	set_half_swording(false)
	if verticality != null:
		if preset == EnemyPreset.RANK_6_GUARD:
			set_flight_mode(VerticalityComponent.FlightMode.MANA_FLIGHT, GUARD_HOVER_Z)
		else:
			verticality.set_height_z(0.0)


func get_current_nav_path() -> PackedVector2Array:
	return _nav_path


func is_patrolling() -> bool:
	return ai_state == AIState.PATROL


func _physics_process(delta: float) -> void:
	var w_delta: float = SimulationClock.get_world_delta(delta)
	var enemy_spd: float = stat_sheet.get_stat(StatSheet.Stat.SPD)
	# In PATROL, enemy moves & perceives at 1.0x (eff_SPD = min(SPD, 10)); in COMBAT/SEARCH, full SPD!
	var enemy_action_dt: float = SimulationClock.get_enemy_action_delta(delta, enemy_spd, ai_state == AIState.PATROL, get_instance_id())

	if knockback_timer > 0.0:
		step_knockback(w_delta)

	if imperceptible_cooldown_timer > 0.0:
		imperceptible_cooldown_timer = maxf(0.0, imperceptible_cooldown_timer - w_delta)

	tick_combat_status_timers(enemy_action_dt, delta)

	var move_vel: Vector2 = Vector2.ZERO
	if ai_enabled and can_act() and enemy_action_dt > 0.0:
		move_vel = step_ai_tick(enemy_action_dt, w_delta)

	if enemy_action_dt > 0.0 and is_alive():
		move_with_substepping(move_vel, enemy_action_dt, dash_timer > 0.0, ai_state == AIState.COMBAT)
		step_combat_fsm(enemy_action_dt)
		_process_planned_feint()

	# Physiology, bleeding & REG tick strictly on SimulationClock.world_delta!
	tick_physiology(w_delta, move_vel.length_squared() > 1.0)


func _process_planned_feint() -> void:
	if not planned_feint_active or combat_state != CombatState.WINDUP:
		return
	# Cancel at ~55% through windup so observer sees the dashed feint telegraph first!
	if state_timer <= _windup_total_duration * 0.45:
		planned_feint_active = false
		if try_feint_cancel():
			if ai_brain != null:
				ai_brain.queued_followup = ai_brain._on_feint_resolved(self, current_target, false)
			attack_cooldown_timer = 0.0


func _set_ai_block_hold(hold_sec: float, cooldown_sec: float) -> void:
	_ai_block_hold_timer = maxf(0.0, hold_sec)
	_reactive_block_cooldown = maxf(_reactive_block_cooldown, cooldown_sec)


func _on_ai_clinch_executed(clinch_cd: float, atk_cd: float) -> void:
	_clinch_ai_cooldown = maxf(0.0, clinch_cd)
	attack_cooldown_timer = maxf(attack_cooldown_timer, atk_cd)
	_attack_cycle_index += 1


func _on_ai_attack_started(is_planned_feint: bool) -> void:
	_attack_cycle_index += 1
	planned_feint_active = is_planned_feint
	_windup_total_duration = maxf(0.05, state_timer)
	attack_cooldown_timer = 0.45 if (WorldCalendar != null and WorldCalendar.is_blood_moon()) else 0.55


func _get_active_evasion_velocity() -> Vector2:
	if sidestep_timer > 0.0 and sidestep_direction.length_squared() > 0.001:
		var side_speed: float = BASE_SIDESTEP_SPEED_PX * (1.0 + maxf(0.0, stat_sheet.get_stat(StatSheet.Stat.AGI) - 10.0) * 0.015)
		return sidestep_direction * side_speed
	if dash_timer > 0.0 and dash_direction.length_squared() > 0.001:
		return dash_direction * BASE_DASH_SPEED_PX * stat_sheet.get_dash_mult()
	return Vector2.ZERO


func receive_melee_hit(
	attacker: CombatActor,
	zone: HitboxZone,
	weapon: WeaponData,
	is_weak_point: bool,
	kinetic_mult: float = 1.0,
	attacker_aura: bool = false,
	attack_type: PenetrationResolver.AttackType = PenetrationResolver.AttackType.STANDARD,
	distance_to_target: float = -1.0,
	attacker_half_swording: bool = false,
	attacker_aura_burst: bool = false,
	anti_regen: bool = false,
	attacker_is_counter: bool = false,
	attacker_is_stealth_backstab: bool = false
) -> Dictionary:
	if attacker != null and attacker != self and is_alive():
		var arena: TestArena = _find_arena()
		if arena == null or not arena.is_entity_in_safe_zone(attacker):
			engage_target(attacker)
	var res: Dictionary = super.receive_melee_hit(
		attacker,
		zone,
		weapon,
		is_weak_point,
		kinetic_mult,
		attacker_aura,
		attack_type,
		distance_to_target,
		attacker_half_swording,
		attacker_aura_burst,
		anti_regen,
		attacker_is_counter,
		attacker_is_stealth_backstab
	)
	var out_str: String = String(res.get("outcome", ""))
	if is_alive() and out_str != "ignored" and out_str != "parried" and out_str != "dodged":
		_recent_hits_taken += 1
		_recent_hits_decay_timer = 5.0
		if ai_brain != null:
			ai_brain.on_hit_received(1.0)
	return res


func engage_target(target: CombatActor) -> void:
	if target == null or not target.is_alive() or not is_alive():
		return
	current_target = target
	last_known_target_pos = target.global_position
	search_target_pos = target.global_position
	search_timer = SEARCH_DURATION_SEC
	suspicion_level = 1.0
	_pursuing_stairs_to_floor = -999
	_set_ai_state(AIState.COMBAT)


func reset_aggro(cooldown_sec: float = 2.0) -> void:
	current_target = null
	search_timer = 0.0
	suspicion_level = 0.0
	_known_downed_ally_ids.clear()
	planned_feint_active = false
	_pursuing_stairs_to_floor = -999
	_nav_path.clear()
	_nav_path_index = 0
	_ai_block_hold_timer = 0.0
	_weapon_retrieve_active_timer = 0.0
	if ai_brain != null:
		ai_brain.reset()
	set_block_held(false)
	set_aura_active(false)
	set_half_swording(false)
	_set_ai_state(AIState.PATROL)
	_unregister_aggro_safe()
	attack_cooldown_timer = maxf(attack_cooldown_timer, 0.5)
	imperceptible_cooldown_timer = maxf(imperceptible_cooldown_timer, cooldown_sec)


## Called by TestArena when a player enters the SafeBarrierZone (GDD 14.3).
func on_target_entered_safe_zone(entity: Node) -> void:
	if entity == null:
		return
	if entity == current_target or ai_state != AIState.PATROL:
		reset_aggro(1.5)


# ---------------------------------------------------------------------------
# AI State Machine: PATROL (1.0x) -> COMBAT -> SEARCH (4.0s) -> PATROL (1.0x)
# Delegates active combat to modular Utility AI (EnemyAIProfile + CombatMemory + CombatBrain).
# ---------------------------------------------------------------------------

func step_ai_tick(action_dt: float, world_dt: float) -> Vector2:
	_ensure_ai_brain()

	if attack_cooldown_timer > 0.0:
		attack_cooldown_timer = maxf(0.0, attack_cooldown_timer - action_dt)
	if _reactive_block_cooldown > 0.0:
		_reactive_block_cooldown = maxf(0.0, _reactive_block_cooldown - action_dt)
	if _clinch_ai_cooldown > 0.0:
		_clinch_ai_cooldown = maxf(0.0, _clinch_ai_cooldown - action_dt)
	if _weapon_retrieve_cooldown > 0.0:
		_weapon_retrieve_cooldown = maxf(0.0, _weapon_retrieve_cooldown - maxf(action_dt, world_dt))
	if _lodged_extract_cooldown > 0.0:
		_lodged_extract_cooldown = maxf(0.0, _lodged_extract_cooldown - maxf(action_dt, world_dt))
	if _nav_repath_timer > 0.0:
		_nav_repath_timer = maxf(0.0, _nav_repath_timer - maxf(action_dt, world_dt))
	if _recent_hits_decay_timer > 0.0:
		_recent_hits_decay_timer = maxf(0.0, _recent_hits_decay_timer - maxf(action_dt, world_dt))
		if _recent_hits_decay_timer <= 0.0:
			_recent_hits_taken = 0
	if _ai_block_hold_timer > 0.0:
		_ai_block_hold_timer = maxf(0.0, _ai_block_hold_timer - action_dt)
		set_block_held(_ai_block_hold_timer > 0.0)

	var arena: TestArena = _find_arena()

	# Mid-swing active tactics (Sidestep during WINDUP, Smart Reactive Feint, Aura Burst) + memory observe
	if combat_state != CombatState.IDLE:
		if (
			ai_state == AIState.COMBAT
			and current_target != null
			and is_instance_valid(current_target)
			and current_target.is_alive()
		):
			if combat_state == CombatState.WINDUP or combat_state == CombatState.ACTIVE:
				ai_brain.tick_active_attack_tactics(self, current_target, arena, action_dt, world_dt)
			else:
				ai_brain.memory.observe(self, current_target, action_dt, world_dt)
		return _get_active_evasion_velocity()

	# Drop aggro immediately if current target died or entered SafeBarrierZone
	if current_target != null:
		if not is_instance_valid(current_target) or not current_target.is_alive():
			reset_aggro(0.5)
		elif arena != null and arena.is_entity_in_safe_zone(current_target):
			reset_aggro(1.0)

	match ai_state:
		AIState.PATROL:
			# Deactivate combat stances & let hovering Rank 6 Guard ascend back to z=1.5
			if aura_active:
				set_aura_active(false)
			if half_swording:
				set_half_swording(false)
			if is_blocking:
				set_block_held(false)
			if preset == EnemyPreset.RANK_6_GUARD and verticality != null and can_use_mana_flight() and not is_equal_approx(get_height_z(), GUARD_HOVER_Z):
				var next_z: float = move_toward(get_height_z(), GUARD_HOVER_Z, 2.0 * maxf(action_dt, world_dt))
				if next_z >= VerticalityComponent.LOW_OBSTACLE_CLEARANCE_Z:
					verticality.set_flight_mode(VerticalityComponent.FlightMode.MANA_FLIGHT)
				verticality.set_height_z(next_z)

			# 1. Check direct sight / stealth suspicion / downed-ally discovery
			var perc: Dictionary = _evaluate_visual_perception(arena, maxf(action_dt, world_dt))
			var spotted: CombatActor = perc.get("spotted", null) as CombatActor
			if spotted != null:
				engage_target(spotted)
				return Vector2.ZERO
			if bool(perc.get("enter_search", false)):
				_pursuing_stairs_to_floor = -999
				search_target_pos = perc.get("suspicious_pos", global_position) as Vector2
				search_timer = SEARCH_DURATION_SEC
				_set_ai_state(AIState.SEARCH)
				return Vector2.ZERO

			# 2. Check hearing (noise circles) & smell (blood trail) -> enter SEARCH
			if arena != null:
				var noise_clue: Dictionary = arena.find_loudest_noise_for(global_position, get_floor_level(), self)
				if not noise_clue.is_empty():
					var src: Variant = noise_clue.get("source", null)
					if src == null or not (src is Node) or not arena.is_entity_in_safe_zone(src as Node):
						var n_floor: int = int(noise_clue.get("floor", get_floor_level()))
						var n_pos: Vector2 = noise_clue["pos"] as Vector2
						if n_floor != get_floor_level() and n_pos.distance_to(arena.get_stairs_center()) <= STAIRS_PURSUIT_RADIUS_PX:
							_pursuing_stairs_to_floor = n_floor
							search_target_pos = arena.get_stairs_center()
						else:
							_pursuing_stairs_to_floor = -999
							search_target_pos = n_pos
						search_timer = SEARCH_DURATION_SEC
						_set_ai_state(AIState.SEARCH)
						return Vector2.ZERO
				var blood_clue: Dictionary = arena.find_recent_blood_trail(global_position, get_floor_level(), smell_radius_px)
				if not blood_clue.is_empty():
					_pursuing_stairs_to_floor = -999
					search_target_pos = blood_clue["pos"] as Vector2
					search_timer = SEARCH_DURATION_SEC
					_set_ai_state(AIState.SEARCH)
					return Vector2.ZERO

			var offset_x: float = global_position.x - spawn_origin.x
			if offset_x >= patrol_distance_px:
				patrol_dir = -1.0
			elif offset_x <= -patrol_distance_px:
				patrol_dir = 1.0
			aim_angle = 0.0 if patrol_dir > 0.0 else PI
			aim_world_pos = get_combat_origin() + Vector2.from_angle(aim_angle) * 32.0
			return Vector2(patrol_dir * BASE_RUN_SPEED_PX * 0.35, 0.0)

		AIState.COMBAT:
			if current_target == null:
				_set_ai_state(AIState.PATROL)
				return Vector2.ZERO

			if not can_see_target(current_target, arena):
				# Lost LOS, changed floor, flew high, or broke leash -> enter SEARCH (4.0s)
				if (
					arena != null
					and current_target.get_floor_level() != get_floor_level()
					and last_known_target_pos.distance_to(arena.get_stairs_center()) <= STAIRS_PURSUIT_RADIUS_PX
				):
					_pursuing_stairs_to_floor = current_target.get_floor_level()
					search_target_pos = arena.get_stairs_center()
				else:
					_pursuing_stairs_to_floor = -999
					search_target_pos = last_known_target_pos
				search_timer = SEARCH_DURATION_SEC
				_nav_path.clear()
				_set_ai_state(AIState.SEARCH)
				return Vector2.ZERO

			last_known_target_pos = current_target.global_position
			var to_target: Vector2 = current_target.global_position - global_position
			var dist: float = to_target.length()
			aim_world_pos = current_target.get_combat_origin()
			aim_angle = (aim_world_pos - get_combat_origin()).angle()

			# Keep executing active evasive dash cleanly while continuing target observation
			if dash_timer > 0.0 or sidestep_timer > 0.0:
				ai_brain.memory.observe(self, current_target, action_dt, world_dt)
				return _get_active_evasion_velocity()

			# Rank 6+ strict Imperceptible Speed check
			if preset == EnemyPreset.RANK_6_GUARD and imperceptible_cooldown_timer <= 0.0 and dist <= dash_strike_reach_px:
				var imp_res: Dictionary = try_imperceptible_speed_strike(current_target)
				if bool(imp_res.get("triggered", false)):
					imperceptible_cooldown_timer = 1.5
					return Vector2.ZERO

			if _ai_block_hold_timer > 0.0:
				ai_brain.memory.observe(self, current_target, action_dt, world_dt)
				return Vector2.ZERO

			# If a blade is lodged in own body and we have brief spacing/cooldown, pull it out (3.0s cd)
			if attack_cooldown_timer > 0.0 and not is_within_clinch_range(current_target):
				if _try_ai_extract_lodged_weapon():
					return Vector2.ZERO

			# If disarmed & outside clinch range, briefly steer toward nearby dropped weapon (<=120px) and pick it up!
			if is_unarmed() and not has_both_arms_severed() and not is_within_clinch_range(current_target):
				var retr: Dictionary = _try_step_weapon_retrieval(arena, action_dt)
				if bool(retr.get("active", false)):
					return retr.get("velocity", Vector2.ZERO) as Vector2

			var brain_vel: Vector2 = ai_brain.tick_combat(self, current_target, arena, action_dt, world_dt)
			if dash_timer > 0.0 or sidestep_timer > 0.0:
				return _get_active_evasion_velocity()
			return brain_vel

		AIState.SEARCH:
			# Re-acquire via honest suspicion / instant detection if player is visible
			var re_perc: Dictionary = _evaluate_visual_perception(arena, maxf(action_dt, world_dt))
			var re_spotted: CombatActor = re_perc.get("spotted", null) as CombatActor
			if re_spotted != null:
				engage_target(re_spotted)
				return Vector2.ZERO
			if bool(re_perc.get("saw_target", false)):
				_pursuing_stairs_to_floor = -999
				search_target_pos = re_perc.get("suspicious_pos", search_target_pos) as Vector2
				search_timer = maxf(search_timer, 2.5)

			# While searching (out of immediate clash), pull out any lodged blade or pick up nearby dropped weapon
			if _try_ai_extract_lodged_weapon():
				return Vector2.ZERO
			if is_unarmed() and not has_both_arms_severed():
				var retr_search: Dictionary = _try_step_weapon_retrieval(arena, action_dt)
				if bool(retr_search.get("active", false)):
					return retr_search.get("velocity", Vector2.ZERO) as Vector2

			# Update search destination from fresh noise or fresh blood trails (GDD 2.3, 7.4)
			if arena != null:
				var noise_clue: Dictionary = arena.find_loudest_noise_for(global_position, get_floor_level(), self)
				if not noise_clue.is_empty():
					var src: Variant = noise_clue.get("source", null)
					if src == null or not (src is Node) or not arena.is_entity_in_safe_zone(src as Node):
						var n_floor: int = int(noise_clue.get("floor", get_floor_level()))
						var n_pos: Vector2 = noise_clue["pos"] as Vector2
						if n_floor != get_floor_level() and n_pos.distance_to(arena.get_stairs_center()) <= STAIRS_PURSUIT_RADIUS_PX:
							_pursuing_stairs_to_floor = n_floor
							search_target_pos = arena.get_stairs_center()
						elif n_floor == get_floor_level():
							_pursuing_stairs_to_floor = -999
							search_target_pos = n_pos
						if float(noise_clue.get("age", 10.0)) < 0.5:
							search_timer = maxf(search_timer, 2.0)
				var blood_clue: Dictionary = arena.find_recent_blood_trail(global_position, get_floor_level(), smell_radius_px)
				if not blood_clue.is_empty():
					var b_pos: Vector2 = blood_clue["pos"] as Vector2
					if b_pos.distance_to(search_target_pos) > 10.0:
						search_target_pos = b_pos
					if float(blood_clue.get("age", 10.0)) < 1.5:
						search_timer = maxf(search_timer, 1.5)

			# If pursuing target across stairs, transition floor upon reaching stairs_area!
			if (
				arena != null
				and _pursuing_stairs_to_floor != -999
				and _pursuing_stairs_to_floor != get_floor_level()
			):
				search_target_pos = arena.get_stairs_center()
				if arena.is_entity_on_stairs(self):
					if arena.try_use_stairs(self):
						_pursuing_stairs_to_floor = -999
						_nav_path.clear()
						search_timer = maxf(search_timer, 2.5)
						if current_target != null and is_instance_valid(current_target) and can_see_target(current_target, arena):
							engage_target(current_target)
						return Vector2.ZERO

			search_timer = maxf(0.0, search_timer - maxf(0.0, world_dt))
			if search_timer <= 0.0:
				# Escaped cleanly -> back to PATROL (1.0x), clear suspicion & release active_aggro_ids!
				current_target = null
				suspicion_level = 0.0
				_pursuing_stairs_to_floor = -999
				_nav_path.clear()
				_set_ai_state(AIState.PATROL)
				return Vector2.ZERO

			var to_clue: Vector2 = search_target_pos - global_position
			if to_clue.length() > 10.0:
				var nav_dir: Vector2 = _compute_nav_steering_dir(search_target_pos, arena, action_dt)
				if nav_dir.length_squared() > 0.001:
					aim_angle = nav_dir.angle()
					aim_world_pos = get_combat_origin() + nav_dir * 32.0
					return nav_dir * BASE_RUN_SPEED_PX * 0.52
			return Vector2.ZERO

	return Vector2.ZERO


func _compute_nav_steering_dir(goal_pos: Vector2, arena: TestArena, _dt: float) -> Vector2:
	var direct: Vector2 = goal_pos - global_position
	if direct.length_squared() <= 1.0:
		return Vector2.ZERO
	if arena == null or _has_clear_walk_path(goal_pos):
		_nav_path.clear()
		_nav_path_index = 0
		return direct.normalized()

	var need_repath: bool = (
		_nav_path.is_empty()
		or _nav_path_index >= _nav_path.size()
		or _nav_repath_timer <= 0.0
		or _nav_last_goal.distance_to(goal_pos) > 24.0
	)
	if need_repath:
		_nav_path = arena.find_nav_path(get_floor_level(), global_position, goal_pos)
		_nav_path_index = 0
		_nav_repath_timer = 0.25
		_nav_last_goal = goal_pos

	while _nav_path_index < _nav_path.size() - 1 and global_position.distance_to(_nav_path[_nav_path_index]) <= 12.0:
		_nav_path_index += 1

	if _nav_path_index < _nav_path.size():
		var to_wp: Vector2 = _nav_path[_nav_path_index] - global_position
		if to_wp.length_squared() > 1.0:
			return to_wp.normalized()
	return direct.normalized()


func _has_clear_walk_path(target_pos: Vector2) -> bool:
	var world_2d: World2D = get_world_2d()
	if world_2d == null:
		return true
	var include_low: bool = get_height_z() < FloorLayerManager.LOW_OBSTACLE_CLEARANCE_Z
	var mask: int = FloorLayerManager.get_solid_world_mask(get_floor_level(), include_low)
	if mask == 0:
		return true
	var dir: Vector2 = target_pos - global_position
	if dir.length_squared() <= 1.0:
		return true
	var perp: Vector2 = Vector2(-dir.y, dir.x).normalized() * (get_body_collision_radius() * 0.75)
	var offsets: Array[Vector2] = [Vector2.ZERO, perp, -perp]
	for off: Vector2 in offsets:
		var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(global_position + off, target_pos + off, mask)
		query.collide_with_bodies = true
		query.collide_with_areas = false
		query.exclude = [get_rid()]
		var hit: Dictionary = world_2d.direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			return false
	return true


func _start_preset_attack(target_origin: Vector2) -> void:
	_attack_cycle_index += 1
	var atk_type: PenetrationResolver.AttackType = PenetrationResolver.AttackType.SLASH
	planned_feint_active = false

	match preset:
		EnemyPreset.RANK_1_SWORDSMAN:
			# Alternates SLASH / THRUST and executes simple Feints every 3rd strike (GDD 14.4)
			if _attack_cycle_index % 2 == 0:
				atk_type = PenetrationResolver.AttackType.THRUST
			else:
				atk_type = PenetrationResolver.AttackType.SLASH
			planned_feint_active = (_attack_cycle_index % 3 == 0)
		EnemyPreset.TROLL_BERSERKER:
			# Heavy BLUNT & SLASH cleaves
			atk_type = PenetrationResolver.AttackType.BLUNT if (_attack_cycle_index % 2 == 1) else PenetrationResolver.AttackType.SLASH
		EnemyPreset.RANK_6_GUARD:
			# Full tactical mix (SLASH / THRUST / BLUNT) + feints
			var mod_idx: int = _attack_cycle_index % 3
			if mod_idx == 1:
				atk_type = PenetrationResolver.AttackType.SLASH
			elif mod_idx == 2:
				atk_type = PenetrationResolver.AttackType.THRUST
			else:
				atk_type = PenetrationResolver.AttackType.BLUNT
			planned_feint_active = (_attack_cycle_index % 4 == 0)

	if start_attack(target_origin, atk_type):
		_windup_total_duration = maxf(0.05, state_timer)


func _try_step_weapon_retrieval(arena: TestArena, action_dt: float) -> Dictionary:
	if arena == null or _weapon_retrieve_cooldown > 0.0 or not is_unarmed() or has_both_arms_severed():
		_weapon_retrieve_active_timer = 0.0
		return {"active": false, "velocity": Vector2.ZERO, "picked": false}
	var drop_info: Dictionary = arena.find_nearest_dropped_weapon(global_position, get_floor_level(), WEAPON_RETRIEVE_RADIUS_PX)
	if not bool(drop_info.get("found", false)):
		_weapon_retrieve_active_timer = 0.0
		return {"active": false, "velocity": Vector2.ZERO, "picked": false}
	var drop_pos: Vector2 = drop_info.get("pos", Vector2.ZERO) as Vector2
	var dist: float = float(drop_info.get("dist", INF))
	if dist <= WEAPON_RETRIEVE_PICKUP_DIST_PX:
		var picked: WeaponData = try_pickup_dropped_weapon(WEAPON_RETRIEVE_PICKUP_DIST_PX + 4.0)
		_weapon_retrieve_active_timer = 0.0
		_weapon_retrieve_cooldown = 0.50 if picked != null else WEAPON_RETRIEVE_RETRY_COOLDOWN_SEC
		return {"active": picked != null, "velocity": Vector2.ZERO, "picked": picked != null}
	# Check clear path or navigable AStar route before committing
	var can_reach: bool = _has_clear_walk_path(drop_pos)
	if not can_reach:
		var nav_test: PackedVector2Array = arena.find_nav_path(get_floor_level(), global_position, drop_pos)
		can_reach = not nav_test.is_empty()
	if not can_reach:
		_weapon_retrieve_cooldown = WEAPON_RETRIEVE_RETRY_COOLDOWN_SEC
		_weapon_retrieve_active_timer = 0.0
		return {"active": false, "velocity": Vector2.ZERO, "picked": false}
	_weapon_retrieve_active_timer += action_dt
	if _weapon_retrieve_active_timer >= WEAPON_RETRIEVE_MAX_CHASE_SEC:
		_weapon_retrieve_cooldown = WEAPON_RETRIEVE_RETRY_COOLDOWN_SEC
		_weapon_retrieve_active_timer = 0.0
		return {"active": false, "velocity": Vector2.ZERO, "picked": false}
	var steer_dir: Vector2 = _compute_nav_steering_dir(drop_pos, arena, action_dt)
	if steer_dir.length_squared() <= 0.001:
		return {"active": false, "velocity": Vector2.ZERO, "picked": false}
	aim_angle = steer_dir.angle()
	aim_world_pos = get_combat_origin() + steer_dir * 32.0
	return {"active": true, "velocity": steer_dir * BASE_RUN_SPEED_PX * 0.90, "picked": false}


func _try_ai_extract_lodged_weapon() -> bool:
	if _lodged_extract_cooldown > 0.0 or combat_state != CombatState.IDLE or has_both_arms_severed():
		return false
	if anatomy == null or not anatomy.has_lodged_weapon():
		return false
	_lodged_extract_cooldown = LODGED_EXTRACT_COOLDOWN_SEC
	var ext: Dictionary = try_extract_lodged_weapon(false)
	if bool(ext.get("extracted", false)):
		attack_cooldown_timer = maxf(attack_cooldown_timer, 0.35)
		return true
	return false


func get_effective_aggro_radius_px() -> float:
	if WorldCalendar == null:
		return aggro_radius_px
	if WorldCalendar.is_blood_moon():
		return aggro_radius_px * BLOOD_MOON_VISION_RADIUS_MULT
	if WorldCalendar.is_night():
		return aggro_radius_px * NIGHT_VISION_RADIUS_MULT
	return aggro_radius_px


func get_effective_vision_half_angle_deg() -> float:
	if WorldCalendar == null:
		return vision_half_angle_deg
	if WorldCalendar.is_blood_moon():
		return minf(135.0, vision_half_angle_deg * BLOOD_MOON_VISION_CONE_MULT)
	if WorldCalendar.is_night():
		return vision_half_angle_deg * NIGHT_VISION_CONE_MULT
	return vision_half_angle_deg


func get_effective_leash_radius_px() -> float:
	if WorldCalendar != null and WorldCalendar.is_blood_moon():
		return leash_radius_px * BLOOD_MOON_LEASH_MULT
	return leash_radius_px


func can_see_target(target: CombatActor, arena: TestArena = null) -> bool:
	if target == null or not is_instance_valid(target) or not target.is_alive():
		return false
	if target.get_floor_level() != get_floor_level():
		return false
	if absf(get_height_z() - target.get_height_z()) > vertical_aggro_tolerance:
		return false
	if arena != null and arena.is_entity_in_safe_zone(target):
		return false
	var dist: float = global_position.distance_to(target.global_position)
	if dist > get_effective_leash_radius_px():
		return false
	return _has_clear_vision_los(target)


## Vision line-of-sight check respecting LOW_OBSTACLE cover:
## If target is crouched/prone AND observer is grounded (height_z < 1.0), low fences/barriers hide the target!
## Hovering/flying observers (height_z >= 1.0) see cleanly over LOW_OBSTACLE.
func _has_clear_vision_los(target: CombatActor) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var world_2d: World2D = get_world_2d()
	if world_2d == null:
		return true
	var include_low_obstacles: bool = (
		(target.is_crouching or target.is_prone())
		and get_height_z() < FloorLayerManager.LOW_OBSTACLE_CLEARANCE_Z
	)
	var mask: int = FloorLayerManager.get_solid_world_mask(get_floor_level(), include_low_obstacles)
	if mask == 0:
		return true
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(global_position, target.global_position, mask)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [get_rid()]
	var hit: Dictionary = world_2d.direct_space_state.intersect_ray(query)
	return hit.is_empty()


func _scan_for_visible_player(arena: TestArena) -> CombatActor:
	if not is_inside_tree():
		return null
	var eff_aggro_r: float = get_effective_aggro_radius_px()
	var eff_vision_half_rad: float = deg_to_rad(get_effective_vision_half_angle_deg())
	for n: Node in get_tree().get_nodes_in_group(&"player"):
		if not (n is CombatActor):
			continue
		var cand: CombatActor = n as CombatActor
		if not cand.is_alive() or cand.get_floor_level() != get_floor_level():
			continue
		if absf(get_height_z() - cand.get_height_z()) > vertical_aggro_tolerance:
			continue
		if arena != null and arena.is_entity_in_safe_zone(cand):
			continue
		var to_cand: Vector2 = cand.global_position - global_position
		var dist: float = to_cand.length()
		if dist > eff_aggro_r:
			continue
		var prox_r: float = PROXIMITY_SENSE_CROUCH_PX if (cand.is_crouching or cand.is_prone()) else PROXIMITY_SENSE_STANDING_PX
		if dist > prox_r:
			var ang_diff: float = absf(angle_difference(aim_angle, to_cand.angle()))
			if ang_diff > eff_vision_half_rad:
				continue
		if _has_clear_vision_los(cand):
			return cand
	return null


func _scan_for_downed_ally(arena: TestArena) -> CombatActor:
	if not is_inside_tree():
		return null
	var eff_aggro_r: float = get_effective_aggro_radius_px()
	var eff_vision_half_rad: float = deg_to_rad(get_effective_vision_half_angle_deg())
	for n: Node in get_tree().get_nodes_in_group(&"enemies"):
		if n == self or not (n is CombatActor):
			continue
		var ally: CombatActor = n as CombatActor
		if ally.get_floor_level() != get_floor_level():
			continue
		var is_downed: bool = (not ally.is_alive()) or (ally.anatomy != null and ally.anatomy.is_unconscious)
		if not is_downed:
			continue
		if _known_downed_ally_ids.has(ally.get_instance_id()):
			continue
		var to_ally: Vector2 = ally.global_position - global_position
		var dist: float = to_ally.length()
		if dist > eff_aggro_r:
			continue
		if dist > PROXIMITY_SENSE_STANDING_PX:
			var ang_diff: float = absf(angle_difference(aim_angle, to_ally.angle()))
			if ang_diff > eff_vision_half_rad:
				continue
		if _has_clear_line_of_attack(ally.global_position):
			if arena == null or not arena.is_entity_in_safe_zone(ally):
				return ally
	return null


## Evaluates honest stealth vision & suspicion_level (0.0 .. 1.0):
## - Standing open target within <=75px (or center of cone during Day/Blood Moon) -> instant 1.0 aggro.
## - Crouched / StealthCoverZone / cone-edge / Night -> gradual suspicion (>=0.35 SEARCH, >=1.0 COMBAT).
## - Spotting a freshly KO'd/dead ally in cone also raises suspicion & triggers SEARCH.
func _evaluate_visual_perception(arena: TestArena, dt: float) -> Dictionary:
	var result: Dictionary = {
		"spotted": null,
		"saw_target": false,
		"enter_search": false,
		"suspicious_pos": Vector2.ZERO,
	}
	if not is_inside_tree():
		return result

	var cand: CombatActor = _scan_for_visible_player(arena)
	if cand == null:
		suspicion_level = maxf(0.0, suspicion_level - SUSPICION_DECAY_PER_SEC * maxf(0.0, dt))
		var downed_ally: CombatActor = _scan_for_downed_ally(arena)
		if downed_ally != null:
			_known_downed_ally_ids[downed_ally.get_instance_id()] = true
			suspicion_level = maxf(suspicion_level, 0.55)
			result["enter_search"] = true
			result["suspicious_pos"] = downed_ally.global_position
		return result

	result["saw_target"] = true
	result["suspicious_pos"] = cand.global_position

	var to_cand: Vector2 = cand.global_position - global_position
	var dist: float = to_cand.length()
	var eff_aggro_r: float = maxf(1.0, get_effective_aggro_radius_px())
	var eff_vision_half_rad: float = maxf(0.05, deg_to_rad(get_effective_vision_half_angle_deg()))
	var ang_diff: float = absf(angle_difference(aim_angle, to_cand.angle()))
	var prox_r: float = PROXIMITY_SENSE_CROUCH_PX if (cand.is_crouching or cand.is_prone()) else PROXIMITY_SENSE_STANDING_PX

	var in_cover: bool = arena != null and arena.is_entity_in_stealth_cover(cand)
	var is_stealth_target: bool = cand.is_crouching or cand.is_prone() or in_cover
	var is_night_dim: bool = WorldCalendar != null and WorldCalendar.is_night() and not WorldCalendar.is_blood_moon()
	var is_cone_edge: bool = dist > prox_r and ang_diff > eff_vision_half_rad * 0.55
	var instant_spot: bool = (not is_stealth_target) and (dist <= INSTANT_SPOT_DIST_PX or (not is_cone_edge and not is_night_dim))

	if instant_spot:
		suspicion_level = 1.0
		result["spotted"] = cand
		return result

	# Gradual suspicion growth scaled by visibility, distance, angle, player AGI & enemy INT+TP
	var vis_factor: float = arena.get_stealth_visibility_factor(cand) if arena != null else (0.58 if cand.is_crouching else 1.0)
	var dist_factor: float = clampf(1.35 - (dist / eff_aggro_r) * 0.85, 0.30, 1.35)
	var ang_factor: float = 1.0 if dist <= prox_r else clampf(1.15 - (ang_diff / eff_vision_half_rad) * 0.60, 0.40, 1.15)
	var player_agi: float = cand.stat_sheet.get_stat(StatSheet.Stat.AGI) if cand.stat_sheet != null else 10.0
	var agi_stealth_mult: float = 1.0 / (1.0 + maxf(0.0, player_agi - 10.0) * 0.012)
	var my_int: float = stat_sheet.get_stat(StatSheet.Stat.INT) if stat_sheet != null else 10.0
	var my_tp: float = stat_sheet.get_stat(StatSheet.Stat.TP) if stat_sheet != null else 10.0
	var perception_mult: float = 1.0 + maxf(0.0, (my_int + my_tp) * 0.5 - 10.0) * 0.012

	var fill_rate: float = 0.85 * vis_factor * dist_factor * ang_factor * agi_stealth_mult * perception_mult
	suspicion_level = clampf(suspicion_level + fill_rate * maxf(0.016, dt), 0.0, 1.0)

	if suspicion_level >= 1.0:
		result["spotted"] = cand
	elif suspicion_level >= SUSPICION_SEARCH_THRESHOLD:
		result["enter_search"] = true
	return result


func _find_player_actor() -> CombatActor:
	if not is_inside_tree():
		return null
	for n: Node in get_tree().get_nodes_in_group(&"player"):
		if n is CombatActor:
			return n as CombatActor
	return null


# ---------------------------------------------------------------------------
# Intention Reading Visual Telegraphs (INT + TP, GDD Sections 7.4 & 14.3)
# ---------------------------------------------------------------------------

static func get_attack_type_telegraph_color(attack_type: PenetrationResolver.AttackType) -> Color:
	match attack_type:
		PenetrationResolver.AttackType.THRUST:
			return COLOR_TELEGRAPH_THRUST
		PenetrationResolver.AttackType.BLUNT:
			return COLOR_TELEGRAPH_BLUNT
		_:
			return COLOR_TELEGRAPH_SLASH


## Evaluates whether an observing player with `observer_sheet` can read attack type (color)
## and feint intent (dashed telegraph) against an attacker with `attacker_spd` (GDD 7.4, 14.3).
static func compute_telegraph_readability(
	observer_sheet: StatSheet,
	attacker_spd: float,
	attack_type: PenetrationResolver.AttackType,
	is_feint: bool
) -> Dictionary:
	var obs_int: float = observer_sheet.get_stat(StatSheet.Stat.INT) if observer_sheet != null else 10.0
	var obs_tp: float = observer_sheet.get_stat(StatSheet.Stat.TP) if observer_sheet != null else 10.0
	var tp_ratio: float = obs_tp / maxf(1.0, attacker_spd)

	var readable_type: bool = obs_int >= 10.0 and tp_ratio >= 0.25
	var readable_feint: bool = obs_int >= 15.0 and tp_ratio >= 0.40
	var color: Color = get_attack_type_telegraph_color(attack_type) if readable_type else COLOR_TELEGRAPH_UNREADABLE
	return {
		"readable": readable_type,
		"feint_detected": is_feint and readable_feint,
		"dashed": is_feint and readable_feint,
		"color": color,
		"attack_type": attack_type,
		"highlight_weak_points": observer_sheet != null and observer_sheet.can_auto_highlight_weak_points(),
	}


func update_telegraph_visual(observer_sheet: StatSheet = null) -> Dictionary:
	var showing: bool = is_alive() and combat_state == CombatState.WINDUP
	var info: Dictionary = compute_telegraph_readability(
		observer_sheet,
		stat_sheet.get_stat(StatSheet.Stat.SPD) if stat_sheet != null else 10.0,
		current_attack_type,
		planned_feint_active
	)
	info["visible"] = showing
	last_telegraph_state = info

	if telegraph_drawer != null:
		var active_wpn: WeaponData = get_active_weapon()
		telegraph_drawer.show_telegraph = showing
		telegraph_drawer.draw_color = info["color"] as Color
		telegraph_drawer.dashed = bool(info["dashed"])
		telegraph_drawer.center_angle = swing_center_angle
		telegraph_drawer.is_thrust_arrow = (current_attack_type == PenetrationResolver.AttackType.THRUST)
		telegraph_drawer.arc_span_rad = deg_to_rad(active_wpn.swing_arc_deg if active_wpn != null else 75.0)
		telegraph_drawer.queue_redraw()
	return info


func _find_player_stat_sheet() -> StatSheet:
	if not is_inside_tree():
		return null
	for n: Node in get_tree().get_nodes_in_group(&"player"):
		if n is CombatActor:
			return (n as CombatActor).stat_sheet
	return null


# ---------------------------------------------------------------------------
# Strict 3-Condition "Imperceptible Speed" Execution (GDD Section 12.1)
# ---------------------------------------------------------------------------

func try_imperceptible_speed_strike(target: CombatActor, dodge_roll_override: float = -1.0) -> Dictionary:
	var result: Dictionary = {
		"triggered": false,
		"reason": "",
		"zone": &"",
		"organ_damage_pct": 0.0,
	}
	var active_wpn: WeaponData = get_active_weapon()
	if not is_alive() or target == null or not target.is_alive() or active_wpn == null or has_both_arms_severed():
		result["reason"] = "invalid_actor"
		return result

	var dist: float = global_position.distance_to(target.global_position)
	if dist > dash_strike_reach_px:
		result["reason"] = "out_of_dash_reach"
		return result
	if get_floor_level() != target.get_floor_level():
		result["reason"] = "different_floor"
		return result
	if absf(get_height_z() - target.get_height_z()) > active_wpn.vertical_reach:
		result["reason"] = "out_of_vertical_reach"
		return result

	if not _has_clear_line_of_attack(target.global_position):
		result["reason"] = "blocked_by_wall"
		return result

	var enemy_spd: float = stat_sheet.get_stat(StatSheet.Stat.SPD)
	var target_tp: float = target.stat_sheet.get_stat(StatSheet.Stat.TP)
	if not SimulationClock.is_imperceptible_speed(enemy_spd, target_tp):
		result["reason"] = "speed_ratio_below_10x"
		return result

	var front_parry: bool = target.is_in_parry_window() and target.is_attack_within_front_arc(self, PARRY_FRONT_HALF_ANGLE_DEG)
	var front_block: bool = target.is_blocking and target.is_attack_within_front_arc(self, BLOCK_FRONT_HALF_ANGLE_DEG)
	if front_parry or front_block or target.is_hardening_active():
		result["reason"] = "defended_by_block_or_parry"
		return result

	var dodge_chance: float = target.stat_sheet.get_instinct_dodge_chance(enemy_spd)
	var roll: float = dodge_roll_override if dodge_roll_override >= 0.0 else randf()
	if roll < dodge_chance:
		result["reason"] = "instinctively_dodged"
		return result

	var vital_zone: HitboxZone = _pick_target_vital_zone(target)
	if vital_zone == null:
		result["reason"] = "no_vital_zone"
		return result

	var atk_params: PenetrationResolver.AttackParams = PenetrationResolver.AttackParams.new()
	atk_params.attacker_str = stat_sheet.get_stat(StatSheet.Stat.STR)
	atk_params.attacker_m_ctrl = stat_sheet.get_stat(StatSheet.Stat.M_CTRL) if stat_sheet.mana_awakened else 0.0
	atk_params.weapon_base_penetration = active_wpn.base_penetration
	atk_params.weapon_blade_length = active_wpn.blade_length
	atk_params.edge_sharpness = active_wpn.edge_sharpness
	atk_params.weapon_mass_factor = active_wpn.mass_factor
	atk_params.kinetic_mult = stat_sheet.get_kinetic_damage_mult()
	atk_params.aura_active = aura_active
	atk_params.is_weak_point = true
	atk_params.attacker_height_z = get_height_z()
	atk_params.weapon_vertical_reach = active_wpn.vertical_reach

	var def_params: PenetrationResolver.DefenseParams = vital_zone.build_defense_params()
	var res: PenetrationResolver.ResolutionResult = PenetrationResolver.resolve(atk_params, def_params, true, true)
	var expected_organ_dmg: float = AnatomyComponent.calculate_organ_damage_pct(res.effective_depth, target.actor_size_mult, true)

	if not res.penetrated or expected_organ_dmg < target.anatomy.get_organ_integrity(vital_zone.zone_name):
		result["reason"] = "not_guaranteed_lethal"
		return result

	target.trigger_screen_flash(Color(1.0, 0.12, 0.12, 0.85), 0.15)
	target.anatomy.apply_penetration_result(vital_zone.zone_name, res, vital_zone.armor_cushion_mult, self)
	target._emit_combat_outcome(self, vital_zone.zone_name, "imperceptible_speed_fatal", true, res)

	result["triggered"] = true
	result["reason"] = "imperceptible_lethal_strike"
	result["zone"] = vital_zone.zone_name
	result["organ_damage_pct"] = expected_organ_dmg
	imperceptible_strike_triggered.emit(target, vital_zone.zone_name)
	print(
		"[ImperceptibleSpeed] %s (SPD=%.0f) vs %s (TP=%.0f): 0.15s slash flash -> fatal %s trauma (depth=%.1f)!" % [
			actor_display_name,
			enemy_spd,
			target.actor_display_name,
			target_tp,
			String(vital_zone.zone_name),
			res.effective_depth,
		]
	)
	return result


func _has_clear_line_of_attack(target_pos: Vector2) -> bool:
	var world_2d: World2D = get_world_2d()
	if world_2d == null:
		return true
	var wall_mask: int = FloorLayerManager.get_high_walls_bit(get_floor_level())
	if wall_mask == 0:
		return true
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(global_position, target_pos, wall_mask)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [get_rid()]
	var hit: Dictionary = world_2d.direct_space_state.intersect_ray(query)
	return hit.is_empty()


func _pick_target_vital_zone(target: CombatActor) -> HitboxZone:
	for preferred: StringName in [AnatomyComponent.ZONE_NECK, AnatomyComponent.ZONE_CHEST, AnatomyComponent.ZONE_HEAD]:
		for hz: HitboxZone in target.hitbox_zones:
			if is_instance_valid(hz) and hz.zone_name == preferred:
				return hz
	return null
