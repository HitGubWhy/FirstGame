class_name CombatActor
extends CharacterBody2D
## Base combat entity with procedural 2D Top-Down visuals, StatSheet, AnatomyComponent,
## VerticalityComponent, WeaponRaySweeper, HitboxZones, physics sub-stepping (<=16 px),
## Windup/Active/Recovery combat FSM (SLASH/THRUST/BLUNT + Feint + Half-swording + Aura Burst),
## 3 defense styles (Deflect/Block, Micro-Sidestep during Windup, Hardening + LodgedWeapon),
## Clinch (Shove/Sweep Prone/Throw), Blade Clash, Knockback, and Wall Slam.
## Strictly follows GDD Sections 2.3, 7.1-7.4, 12.1-12.6, 14.3, 14.4, and 14.5 (v0.2).

signal weapon_changed(weapon: WeaponData)
signal weapon_disarmed(weapon: WeaponData, reason: StringName)
signal aura_toggled(active: bool)
signal aura_burst_triggered()
signal half_sword_toggled(active: bool)
signal feint_executed()
signal hardening_activated(bonus: float)
signal sidestep_started(direction: Vector2)
signal parry_succeeded(attacker: CombatActor)
signal attack_started(weapon: WeaponData)
signal hit_landed(target: CombatActor, zone_name: StringName, resolution: PenetrationResolver.ResolutionResult)
signal blade_clashed_with(other: CombatActor, result: PenetrationResolver.ClashResult)
signal clinch_performed(action_type: StringName, target: CombatActor)
signal wall_slam_occurred(cell: Vector2i, impulse: float, wall_broken: bool)
signal flight_status_message(message: String)
signal crouch_toggled(crouching: bool)
signal stealth_takedown_performed(target: CombatActor, succeeded: bool)

enum CombatState {
	IDLE = 0,
	WINDUP = 1,
	ACTIVE = 2,
	RECOVERY = 3,
	STAGGERED = 4,
}

enum VisualStyle {
	PLAYER_ADVENTURER = 0,
	RANK_1_SWORDSMAN = 1,
	TROLL_BERSERKER = 2,
	RANK_6_GUARD = 3,
}

const BASE_RUN_SPEED_PX: float = 220.0
const MAX_SUBSTEP_PX: float = 16.0
const MAX_SUBSTEP_ITERATIONS: int = 128
const PARRY_WINDOW_SEC: float = 0.18
const DEFAULT_STAGGER_SEC: float = 0.9
const WALL_RAM_MIN_SPEED_PX: float = 380.0

const BASE_DASH_SPEED_PX: float = 520.0
const BASE_DASH_DURATION_SEC: float = 0.14
const BASE_DASH_COOLDOWN_SEC: float = 0.75
const BASE_DASH_STAMINA_COST: float = 20.0

const BASE_SIDESTEP_SPEED_PX: float = 340.0
const BASE_SIDESTEP_DURATION_SEC: float = 0.09
const BASE_SIDESTEP_COOLDOWN_SEC: float = 0.35
const BASE_SIDESTEP_STAMINA_COST: float = 10.0

const HARDENING_DURATION_SEC: float = 0.55
const HARDENING_COOLDOWN_SEC: float = 1.60
const HARDENING_STA_COST: float = 18.0
const HARDENING_MP_COST: float = 12.0

const FEINT_STA_COST: float = 8.0
const CLINCH_RANGE_PX: float = 26.0
const CLINCH_MAX_SURFACE_GAP_PX: float = 12.0
const CLINCH_STA_COST: float = 14.0
const CLINCH_THROW_BASE_IMPULSE: float = 50.0
const PRONE_RECOVERY_DURATION_SEC: float = 2.0
const APPROACH_MOMENTUM_WINDOW_SEC: float = 0.30

const WALL_SLAM_IMPULSE_DIVISOR: float = 15.0
const WALL_SLAM_MIN_IMPULSE: float = 35.0
const COUNTER_WINDUP_MULT: float = 0.50
const COUNTER_PENETRATION_MULT: float = 1.35
const BLOCK_FRONT_HALF_ANGLE_DEG: float = 75.0
const PARRY_FRONT_HALF_ANGLE_DEG: float = 110.0
const STEALTH_BACKSTAB_AIM_BONUS_MULT: float = 1.35
const STEALTH_CROUCH_BACKSTAB_AIM_BONUS_MULT: float = 1.60
const CROUCH_BASE_SPEED_MULT: float = 0.52
const CROUCH_MAX_SPEED_MULT: float = 0.72
const CROUCH_VISUAL_SCALE: float = 0.84
const CROUCH_STEP_NOISE_PX: float = 15.0
const CROUCH_SILENT_AGI_THRESHOLD: float = 30.0
const CROUCH_ROLL_NOISE_PX: float = 25.0
const STEALTH_DAGGER_HIT_NOISE_PX: float = 55.0
const STEALTH_TAKEDOWN_NOISE_PX: float = 40.0
const STEALTH_TAKEDOWN_SURPRISE_BONUS: float = 1.45
const STEALTH_TAKEDOWN_STA_COST: float = 14.0
const BUSH_RUSTLE_NOISE_PX: float = 75.0
const BUSH_RUSTLE_INTERVAL_SEC: float = 0.60
const UNARMED_BLOCK_SHARP_PEN_MULT: float = 0.85
const UNARMED_BLOCK_ARM_BARRIER_MULT: float = 0.50

const MANA_FLIGHT_MP_PER_SEC: float = 2.5
const MANA_FLIGHT_DASH_MP_COST: float = 4.0
const WING_FLIGHT_STA_PER_SEC: float = 6.0
const WING_FLIGHT_DASH_STA_EXTRA: float = 6.0
const WING_CRIPPLED_SPEED_MULT: float = 0.65
const WING_CRIPPLED_MAX_ALTITUDE: float = VerticalityComponent.HEIGHT_LOW_FLIGHT

const FACING_BACK_SIN_THRESHOLD: float = -0.35
const HITFLASH_DURATION_SEC: float = 0.065

@export var actor_display_name: String = "Actor"
@export var actor_body_color: Color = Color("#3B9EE8")
@export var visual_style: VisualStyle = VisualStyle.PLAYER_ADVENTURER
@export var actor_size_mult: float = 1.0
@export var actor_base_anatomy_thickness: float = PenetrationResolver.DEFAULT_BASE_ANATOMY_THICKNESS
@export var actor_bone_density: float = 100.0
@export var enable_instinct_dodge: bool = false

var stat_sheet: StatSheet = null
var anatomy: AnatomyComponent = null
var verticality: VerticalityComponent = null
var sweeper: WeaponRaySweeper = null

var body_visual: Node2D = null
var visual_rig: Node2D = null
var hitbox_root: Node2D = null
var body_polygon: Polygon2D = null
var limb_polygons: Dictionary[StringName, Polygon2D] = {}
var nose_polygon: Polygon2D = null
var shadow_visual: Polygon2D = null
var weapon_pivot: Node2D = null
var weapon_model_root: Node2D = null
var weapon_detail_root: Node2D = null
var weapon_blade_poly: Polygon2D = null
var weapon_aura_outline: Line2D = null
var block_arc_line: Line2D = null
var mana_flight_ring: Line2D = null
var mana_flight_inner_ring: Line2D = null
var wing_visual_root: Node2D = null
var wing_left_poly: Polygon2D = null
var wing_right_poly: Polygon2D = null
var slash_trail_line: Line2D = null
var _slash_trail_tween: Tween = null
var body_collision_shape: CollisionShape2D = null

# Modular 3/4 Top-Down sub-nodes (nested inside visual_rig for easy v0.5 Sprite2D swap)
var cape_back_node: Node2D = null
var torso_front_details: Node2D = null
var torso_back_details: Node2D = null
var head_front_details: Node2D = null
var head_back_details: Node2D = null
var stumps_root: Node2D = null
var stump_nodes: Dictionary[StringName, Node2D] = {}
var lodged_weapons_root: Node2D = null
var _lodged_weapon_visuals: Dictionary[StringName, Array] = {}
var _limb_base_positions: Dictionary[StringName, Vector2] = {}
var _limb_hand_nodes: Dictionary[StringName, Node2D] = {}

# Procedural 3/4 animation state (driven strictly by action_delta / SimulationClock)
var is_facing_back: bool = false
var is_facing_left: bool = false
var walk_cycle_phase: float = 0.0
var wing_flap_phase: float = 0.0
var anim_time: float = 0.0
var _walk_blend: float = 0.0
var _squash_scale: Vector2 = Vector2.ONE
var _hitflash_timer: float = 0.0
var _hitflash_color: Color = Color(2.3, 2.3, 2.3, 1.0)
var _current_blade_angle: float = 0.0
var _windup_total_visual_sec: float = 0.25

var has_wings: bool = false
var last_flight_feedback: String = ""
var _last_hitbox_armor_thickness: float = 0.0
var _last_hitbox_armor_hardness: float = 0.0
var _last_hitbox_weak_points: Dictionary = {}

var _blood_trail_timer: float = 0.0
var _last_blood_trail_pos: Vector2 = Vector2.ZERO
var _footstep_noise_timer: float = 0.0

var hitbox_zones: Array[HitboxZone] = []
var equipped_weapon: WeaponData = null
var unarmed_weapon: WeaponData = null
var _initial_weapon_backup: WeaponData = null

var current_stamina: float = 150.0
var current_mp: float = 0.0
var current_sp: float = 100.0
var max_poise: float = 70.0
var current_poise: float = 70.0

var aura_active: bool = false
var current_attack_aura_burst: bool = false
var current_attack_is_counter: bool = false
var anti_regen_strikes_enabled: bool = false
var half_swording: bool = false
var is_blocking: bool = false
var parry_window_timer: float = 0.0

var hardening_timer: float = 0.0
var hardening_cooldown_timer: float = 0.0
var hardening_bonus_value: float = 0.0

var counter_window_timer: float = 0.0
var prone_timer: float = 0.0
var is_crouching: bool = false
var _crouch_visual_scale: float = 1.0
var _bush_rustle_timer: float = 0.0

var combat_state: CombatState = CombatState.IDLE
var current_attack_type: PenetrationResolver.AttackType = PenetrationResolver.AttackType.SLASH
var state_timer: float = 0.0
var attack_windup_override: float = -1.0
var attack_active_override: float = -1.0
var attack_recovery_override: float = -1.0

var aim_angle: float = 0.0
var aim_world_pos: Vector2 = Vector2.ZERO
var swing_center_angle: float = 0.0
var swing_start_angle: float = 0.0
var swing_end_angle: float = 0.0
var swing_duration: float = 0.12
var swing_elapsed: float = 0.0

var dash_timer: float = 0.0
var dash_cooldown_timer: float = 0.0
var dash_direction: Vector2 = Vector2.RIGHT

var sidestep_timer: float = 0.0
var sidestep_cooldown_timer: float = 0.0
var sidestep_direction: Vector2 = Vector2.ZERO

var knockback_velocity: Vector2 = Vector2.ZERO
var knockback_impulse: float = 0.0
var knockback_timer: float = 0.0
var knockback_source: CombatActor = null
var last_wall_slam_report: Dictionary = {}
var last_blade_clash_result: PenetrationResolver.ClashResult = null

var current_move_velocity: Vector2 = Vector2.ZERO
var _recent_move_velocity: Vector2 = Vector2.ZERO
var _recent_move_was_dash: bool = false
var _recent_move_timer: float = 0.0
var _attack_launch_velocity: Vector2 = Vector2.ZERO
var _attack_launch_was_dash: bool = false
var last_antitunnel_areas: Array[Area2D] = []

var _core_initialized: bool = false


func _ready() -> void:
	_ensure_core_components()


func _ensure_core_components() -> void:
	if _core_initialized:
		return
	_core_initialized = true

	if stat_sheet == null:
		stat_sheet = StatSheet.new(StatSheet.DEFAULT_HUMAN_RACIAL_CAP)
	if unarmed_weapon == null:
		unarmed_weapon = WeaponData.create_unarmed_fist()

	anatomy = get_node_or_null("AnatomyComponent") as AnatomyComponent
	if anatomy == null:
		anatomy = AnatomyComponent.new()
		anatomy.name = "AnatomyComponent"
		add_child(anatomy)
	anatomy.setup(stat_sheet, actor_size_mult, actor_bone_density, self)
	if not anatomy.died.is_connected(_on_anatomy_died):
		anatomy.died.connect(_on_anatomy_died)
	if not anatomy.knocked_out.is_connected(_on_anatomy_knocked_out):
		anatomy.knocked_out.connect(_on_anatomy_knocked_out)
	if not anatomy.recovered_consciousness.is_connected(_on_anatomy_recovered):
		anatomy.recovered_consciousness.connect(_on_anatomy_recovered)
	if not anatomy.limb_severed.is_connected(_on_anatomy_limb_severed):
		anatomy.limb_severed.connect(_on_anatomy_limb_severed)
	if not anatomy.limb_regrown.is_connected(_on_anatomy_limb_regrown):
		anatomy.limb_regrown.connect(_on_anatomy_limb_regrown)
	if not anatomy.weapon_dropped.is_connected(_on_anatomy_weapon_dropped):
		anatomy.weapon_dropped.connect(_on_anatomy_weapon_dropped)
	if not anatomy.weapon_lodged.is_connected(_on_anatomy_weapon_lodged):
		anatomy.weapon_lodged.connect(_on_anatomy_weapon_lodged)
	if not anatomy.weapon_dislodged.is_connected(_on_anatomy_weapon_dislodged):
		anatomy.weapon_dislodged.connect(_on_anatomy_weapon_dislodged)

	sweeper = get_node_or_null("WeaponRaySweeper") as WeaponRaySweeper
	if sweeper == null:
		sweeper = WeaponRaySweeper.new()
		sweeper.name = "WeaponRaySweeper"
		add_child(sweeper)

	_build_procedural_visuals()
	_ensure_body_collider()

	hitbox_root = get_node_or_null("HitboxRoot") as Node2D
	if hitbox_root == null:
		hitbox_root = Node2D.new()
		hitbox_root.name = "HitboxRoot"
		add_child(hitbox_root)

	verticality = get_node_or_null("VerticalityComponent") as VerticalityComponent
	if verticality == null:
		verticality = VerticalityComponent.new()
		verticality.name = "VerticalityComponent"
		add_child(verticality)
	verticality.setup(body_visual, shadow_visual, self, verticality.floor_level, verticality.height_z, hitbox_root)
	if not verticality.height_z_changed.is_connected(_on_verticality_height_z_changed):
		verticality.height_z_changed.connect(_on_verticality_height_z_changed)
	if not verticality.flight_mode_changed.is_connected(_on_verticality_flight_mode_changed):
		verticality.flight_mode_changed.connect(_on_verticality_flight_mode_changed)

	refill_resources()
	_sync_flight_stat_tags_and_visuals()


func refill_resources() -> void:
	if stat_sheet == null:
		return
	current_stamina = stat_sheet.get_max_stamina()
	current_mp = stat_sheet.get_max_mp()
	current_sp = stat_sheet.get_sp_cap()
	max_poise = 50.0 + stat_sheet.get_stat(StatSheet.Stat.CON) * 2.0
	current_poise = max_poise
	if anatomy != null:
		anatomy.refill_regen_resources()


# ---------------------------------------------------------------------------
# Procedural 3/4 Top-Down Modular Visuals (Zero External Assets, GDD 14.3, art_style_and_pipeline.md)
# ---------------------------------------------------------------------------

func rebuild_procedural_visuals() -> void:
	_build_procedural_visuals()
	_sync_flight_stat_tags_and_visuals()
	refresh_weapon_visual()
	_apply_procedural_pose()


func _build_procedural_visuals() -> void:
	var s: float = actor_size_mult
	var is_troll: bool = visual_style == VisualStyle.TROLL_BERSERKER
	var is_guard: bool = visual_style == VisualStyle.RANK_6_GUARD
	var outline_col: Color = Color("#14161E")
	var half_size: float = 12.0 * s

	# Ground contact shadow oval (stays strictly at Shadow.position = Vector2.ZERO for VerticalityComponent)
	shadow_visual = get_node_or_null("Shadow") as Polygon2D
	if shadow_visual == null:
		shadow_visual = Polygon2D.new()
		shadow_visual.name = "Shadow"
		add_child(shadow_visual)
	shadow_visual.color = Color(0.0, 0.0, 0.0, 0.44)
	var shadow_rx: float = (12.0 if is_troll else 10.2) * s
	var shadow_ry: float = (5.2 if is_troll else 4.4) * s
	shadow_visual.polygon = _create_offset_ellipse_polygon(Vector2(0.0, 14.2 * s), shadow_rx, shadow_ry, 18)

	# BodyVisual root (position, scale & z_index owned exclusively by VerticalityComponent!)
	body_visual = get_node_or_null("BodyVisual") as Node2D
	if body_visual == null:
		body_visual = Node2D.new()
		body_visual.name = "BodyVisual"
		add_child(body_visual)
	body_visual.rotation = 0.0

	# Ensure obsolete top-down NosePoly is never present
	var old_nose: Node = body_visual.get_node_or_null("NosePoly")
	if old_nose != null:
		old_nose.queue_free()
	nose_polygon = null

	# Clean rebuild of internal VisualRig container (all procedural bob/lean/squash/hitflash lives here!)
	var existing_rig: Node = body_visual.get_node_or_null("VisualRig")
	if existing_rig != null:
		body_visual.remove_child(existing_rig)
		existing_rig.queue_free()
	visual_rig = Node2D.new()
	visual_rig.name = "VisualRig"
	body_visual.add_child(visual_rig)

	# 1. Back cloak / cape / dorsal fur pelt (z flips behind/in-front on Front/Back view)
	cape_back_node = Node2D.new()
	cape_back_node.name = "CapeBack"
	cape_back_node.z_index = -1
	visual_rig.add_child(cape_back_node)
	_populate_cape_visuals(cape_back_node, s, outline_col)

	# 2. Legs (Limb_LeftLeg, Limb_RightLeg) — hip-pivoted for 3/4 elliptical walking gait
	limb_polygons.clear()
	_limb_base_positions.clear()
	_limb_hand_nodes.clear()

	var leg_x: float = (4.8 if is_troll else 3.6) * s
	var leg_y: float = 5.8 * s
	var leg_w: float = (2.8 if is_troll else 2.2) * s
	var leg_h: float = 9.4 * s
	var leg_col: Color = _get_style_leg_color()
	var boot_col: Color = _get_style_boot_color()

	for leg_spec: Dictionary in [
		{"zone": AnatomyComponent.ZONE_LEFT_LEG, "pos": Vector2(-leg_x, leg_y), "side": -1.0},
		{"zone": AnatomyComponent.ZONE_RIGHT_LEG, "pos": Vector2(leg_x, leg_y), "side": 1.0},
	]:
		var zkey: StringName = leg_spec["zone"] as StringName
		var lpos: Vector2 = leg_spec["pos"] as Vector2
		var side_sign: float = float(leg_spec["side"])
		var lpoly: Polygon2D = Polygon2D.new()
		lpoly.name = "Limb_%s" % String(zkey)
		lpoly.z_index = 0
		lpoly.position = lpos
		lpoly.color = leg_col
		lpoly.polygon = PackedVector2Array([
			Vector2(-leg_w, 0.0),
			Vector2(leg_w, 0.0),
			Vector2(leg_w * 0.92, leg_h * 0.62),
			Vector2(-leg_w * 0.92, leg_h * 0.62),
		])
		visual_rig.add_child(lpoly)
		_add_outline(lpoly, lpoly.polygon, outline_col, 1.05 * s)

		# 3/4 boot / armored greave / clawed troll foot
		var boot: Polygon2D = Polygon2D.new()
		boot.name = "BootPoly"
		boot.color = boot_col
		var toe_out: float = side_sign * (0.9 if is_troll else 0.7) * s
		boot.polygon = PackedVector2Array([
			Vector2(-leg_w * 0.98, leg_h * 0.54),
			Vector2(leg_w * 0.98, leg_h * 0.54),
			Vector2(leg_w * 1.15 + maxf(0.0, toe_out), leg_h),
			Vector2(-leg_w * 1.15 + minf(0.0, toe_out), leg_h),
		])
		lpoly.add_child(boot)
		_add_outline(boot, boot.polygon, outline_col, 1.05 * s)

		if is_guard:
			var knee: Polygon2D = Polygon2D.new()
			knee.color = Color("#B8C5D8")
			knee.polygon = PackedVector2Array([
				Vector2(-leg_w * 0.75, leg_h * 0.36),
				Vector2(leg_w * 0.75, leg_h * 0.36),
				Vector2(leg_w * 0.55, leg_h * 0.56),
				Vector2(-leg_w * 0.55, leg_h * 0.56),
			])
			lpoly.add_child(knee)
		elif is_troll:
			# Three dark troll foot claws
			for c_idx: int in [-1, 0, 1]:
				var cx: float = float(c_idx) * 1.4 * s
				var claw: Polygon2D = Polygon2D.new()
				claw.color = Color("#201B16")
				claw.polygon = PackedVector2Array([
					Vector2(cx - 0.5 * s, leg_h - 0.5 * s),
					Vector2(cx + 0.5 * s, leg_h - 0.5 * s),
					Vector2(cx, leg_h + 1.4 * s),
				])
				lpoly.add_child(claw)

		limb_polygons[zkey] = lpoly
		_limb_base_positions[zkey] = lpos

	# 3. Bloody amputation stumps (hidden until limb is severed)
	stumps_root = Node2D.new()
	stumps_root.name = "StumpsRoot"
	stumps_root.z_index = 1
	visual_rig.add_child(stumps_root)
	stump_nodes.clear()
	var sh_x: float = (10.2 if is_troll else (8.6 if is_guard else 7.8)) * s
	var sh_y: float = (-4.4 if is_troll else -3.6) * s
	var stump_specs: Dictionary = {
		AnatomyComponent.ZONE_HEAD: Vector2(0.0, -7.8 * s),
		AnatomyComponent.ZONE_LEFT_ARM: Vector2(-sh_x * 0.85, sh_y + 1.0 * s),
		AnatomyComponent.ZONE_RIGHT_ARM: Vector2(sh_x * 0.85, sh_y + 1.0 * s),
		AnatomyComponent.ZONE_LEFT_LEG: Vector2(-leg_x, leg_y + 1.2 * s),
		AnatomyComponent.ZONE_RIGHT_LEG: Vector2(leg_x, leg_y + 1.2 * s),
	}
	for skey: StringName in stump_specs.keys():
		var stump_n: Node2D = _create_bloody_stump_node("Stump_%s" % String(skey), stump_specs[skey] as Vector2, s)
		stump_n.visible = false
		stumps_root.add_child(stump_n)
		stump_nodes[skey] = stump_n

	# 4. Torso (BodyPoly) + Neck + Front / Back detail layers
	body_polygon = Polygon2D.new()
	body_polygon.name = "BodyPoly"
	body_polygon.z_index = 1
	body_polygon.color = _get_style_torso_color()
	var torso_top_w: float = (10.6 if is_troll else (8.6 if is_guard else 7.6)) * s
	var torso_bot_w: float = (8.2 if is_troll else (7.6 if is_guard else 6.8)) * s
	var torso_top_y: float = (-6.8 if is_troll else -6.0) * s
	var torso_bot_y: float = 7.4 * s
	body_polygon.polygon = PackedVector2Array([
		Vector2(-torso_top_w, torso_top_y + 1.5 * s),
		Vector2(-torso_top_w * 0.65, torso_top_y),
		Vector2(torso_top_w * 0.65, torso_top_y),
		Vector2(torso_top_w, torso_top_y + 1.5 * s),
		Vector2(torso_bot_w, torso_bot_y),
		Vector2(-torso_bot_w, torso_bot_y),
	])
	visual_rig.add_child(body_polygon)

	# Neck column
	var neck_poly: Polygon2D = Polygon2D.new()
	neck_poly.name = "NeckPoly"
	neck_poly.z_index = -1
	neck_poly.color = Color("#5A6270") if is_guard else _get_style_skin_color().darkened(0.10)
	var nw: float = (3.4 if is_troll else 2.4) * s
	neck_poly.polygon = PackedVector2Array([
		Vector2(-nw, -9.2 * s),
		Vector2(nw, -9.2 * s),
		Vector2(nw * 1.15, torso_top_y + 1.0 * s),
		Vector2(-nw * 1.15, torso_top_y + 1.0 * s),
	])
	body_polygon.add_child(neck_poly)
	_add_outline(body_polygon, body_polygon.polygon, outline_col, 1.2 * s)

	torso_front_details = Node2D.new()
	torso_front_details.name = "TorsoFrontDetails"
	body_polygon.add_child(torso_front_details)
	_populate_torso_front_details(torso_front_details, s, torso_top_w, torso_bot_w, torso_top_y, torso_bot_y, outline_col)

	torso_back_details = Node2D.new()
	torso_back_details.name = "TorsoBackDetails"
	torso_back_details.visible = false
	body_polygon.add_child(torso_back_details)
	_populate_torso_back_details(torso_back_details, s, torso_top_w, torso_bot_w, torso_top_y, torso_bot_y, outline_col)

	# 5. Head (Limb_Head) + Front (eyes/visor/tusks/helmet) & Back (hair/nape/plume) detail layers
	var head_base_pos: Vector2 = Vector2(0.0, (-8.8 if is_troll else -8.2) * s)
	var head_poly: Polygon2D = Polygon2D.new()
	head_poly.name = "Limb_%s" % String(AnatomyComponent.ZONE_HEAD)
	head_poly.z_index = 2
	head_poly.position = head_base_pos
	head_poly.color = Color("#748094") if is_guard else _get_style_skin_color()
	var hrx: float = (6.2 if is_troll else (6.0 if is_guard else 5.4)) * s
	var hry: float = (5.4 if is_troll else (5.8 if is_guard else 5.2)) * s
	head_poly.polygon = _create_offset_ellipse_polygon(Vector2(0.0, -hry * 0.85), hrx, hry, 14)
	visual_rig.add_child(head_poly)
	_add_outline(head_poly, head_poly.polygon, outline_col, 1.15 * s)

	head_front_details = Node2D.new()
	head_front_details.name = "HeadFrontDetails"
	head_poly.add_child(head_front_details)
	_populate_head_front_details(head_front_details, s, hrx, hry, outline_col)

	head_back_details = Node2D.new()
	head_back_details.name = "HeadBackDetails"
	head_back_details.visible = false
	head_poly.add_child(head_back_details)
	_populate_head_back_details(head_back_details, s, hrx, hry, outline_col)

	limb_polygons[AnatomyComponent.ZONE_HEAD] = head_poly
	_limb_base_positions[AnatomyComponent.ZONE_HEAD] = head_base_pos

	# 6. Arms (Limb_LeftArm, Limb_RightArm) — shoulder/pauldron + articulated hand/gauntlet
	var arm_col: Color = _get_style_arm_color()
	var hand_col: Color = _get_style_hand_color()
	var arm_w: float = (3.0 if is_troll else 2.2) * s
	var arm_len: float = (7.4 if is_troll else 6.4) * s
	for arm_spec: Dictionary in [
		{"zone": AnatomyComponent.ZONE_LEFT_ARM, "pos": Vector2(-sh_x, sh_y), "z": 2, "side": -1.0},
		{"zone": AnatomyComponent.ZONE_RIGHT_ARM, "pos": Vector2(sh_x, sh_y), "z": 3, "side": 1.0},
	]:
		var zkey: StringName = arm_spec["zone"] as StringName
		var apos: Vector2 = arm_spec["pos"] as Vector2
		var side_sign: float = float(arm_spec["side"])
		var apoly: Polygon2D = Polygon2D.new()
		apoly.name = "Limb_%s" % String(zkey)
		apoly.z_index = int(arm_spec["z"])
		apoly.position = apos
		apoly.color = arm_col
		apoly.polygon = PackedVector2Array([
			Vector2(-arm_w, -1.6 * s),
			Vector2(arm_w, -1.6 * s),
			Vector2(arm_w * 0.85, arm_len),
			Vector2(-arm_w * 0.85, arm_len),
		])
		visual_rig.add_child(apoly)
		_add_outline(apoly, apoly.polygon, outline_col, 1.05 * s)

		# Heavy layered shoulder pauldron for Rank 6 Guard or leather shoulder cap for Swordsman/Player
		if is_guard:
			var pauldron: Polygon2D = Polygon2D.new()
			pauldron.name = "Pauldron"
			pauldron.color = Color("#9BA8BC")
			pauldron.polygon = PackedVector2Array([
				Vector2(-arm_w * 1.45, -2.8 * s),
				Vector2(arm_w * 1.45, -2.8 * s),
				Vector2(arm_w * 1.65 + maxf(0.0, side_sign * 1.5 * s), 2.4 * s),
				Vector2(-arm_w * 1.65 + minf(0.0, side_sign * 1.5 * s), 2.4 * s),
			])
			apoly.add_child(pauldron)
			_add_outline(pauldron, pauldron.polygon, outline_col, 1.0 * s)
			var trim: Polygon2D = Polygon2D.new()
			trim.color = Color("#F1C40F")
			trim.polygon = PackedVector2Array([
				Vector2(-arm_w * 1.35, 1.2 * s),
				Vector2(arm_w * 1.35, 1.2 * s),
				Vector2(arm_w * 1.35, 2.3 * s),
				Vector2(-arm_w * 1.35, 2.3 * s),
			])
			apoly.add_child(trim)
		elif visual_style == VisualStyle.RANK_1_SWORDSMAN:
			var pad: Polygon2D = Polygon2D.new()
			pad.color = Color("#7E8794")
			pad.polygon = _create_offset_ellipse_polygon(Vector2(0.0, -0.8 * s), arm_w * 1.25, 2.2 * s, 8)
			apoly.add_child(pad)
			_add_outline(pad, pad.polygon, outline_col, 0.9 * s)
		elif is_troll:
			var wrist_wrap: Polygon2D = Polygon2D.new()
			wrist_wrap.color = Color("#5A422E")
			wrist_wrap.polygon = PackedVector2Array([
				Vector2(-arm_w * 0.95, arm_len * 0.55),
				Vector2(arm_w * 0.95, arm_len * 0.55),
				Vector2(arm_w * 0.92, arm_len * 0.88),
				Vector2(-arm_w * 0.92, arm_len * 0.88),
			])
			apoly.add_child(wrist_wrap)

		# Hand / Gauntlet node (reaches smoothly toward weapon hilt or mid-blade during Half-swording)
		var hand_node: Node2D = Node2D.new()
		hand_node.name = "HandNode"
		hand_node.position = Vector2(0.0, arm_len + 0.8 * s)
		apoly.add_child(hand_node)
		var hand_poly: Polygon2D = Polygon2D.new()
		hand_poly.name = "HandPoly"
		hand_poly.color = hand_col
		var hr: float = (2.6 if is_troll else 2.1) * s
		hand_poly.polygon = _create_ellipse_polygon(hr, hr * 0.92, 8)
		hand_node.add_child(hand_poly)
		_add_outline(hand_poly, hand_poly.polygon, outline_col, 0.95 * s)

		limb_polygons[zkey] = apoly
		_limb_base_positions[zkey] = apos
		_limb_hand_nodes[zkey] = hand_node

	# 7. LodgedWeapon visual container (moves & bobs with VisualRig)
	lodged_weapons_root = Node2D.new()
	lodged_weapons_root.name = "LodgedWeaponsRoot"
	lodged_weapons_root.z_index = 4
	visual_rig.add_child(lodged_weapons_root)
	_lodged_weapon_visuals.clear()

	# 8. WeaponPivot (DIRECT child of BodyVisual! Keeps exact position contract for THRUST tests)
	weapon_pivot = body_visual.get_node_or_null("WeaponPivot") as Node2D
	if weapon_pivot == null:
		weapon_pivot = Node2D.new()
		weapon_pivot.name = "WeaponPivot"
		body_visual.add_child(weapon_pivot)
	else:
		for child: Node in weapon_pivot.get_children():
			weapon_pivot.remove_child(child)
			child.queue_free()
	weapon_pivot.position = Vector2.ZERO
	weapon_pivot.z_index = 3

	weapon_model_root = Node2D.new()
	weapon_model_root.name = "WeaponModelRoot"
	weapon_pivot.add_child(weapon_model_root)

	weapon_blade_poly = Polygon2D.new()
	weapon_blade_poly.name = "BladePoly"
	weapon_model_root.add_child(weapon_blade_poly)

	weapon_detail_root = Node2D.new()
	weapon_detail_root.name = "WeaponDetailRoot"
	weapon_model_root.add_child(weapon_detail_root)

	weapon_aura_outline = Line2D.new()
	weapon_aura_outline.name = "AuraOutline"
	weapon_aura_outline.width = 2.0
	weapon_aura_outline.closed = true
	weapon_aura_outline.default_color = Color("#4FD8FF")
	weapon_aura_outline.visible = false
	weapon_model_root.add_child(weapon_aura_outline)

	# 9. SlashTrail (DIRECT child of BodyVisual)
	slash_trail_line = body_visual.get_node_or_null("SlashTrail") as Line2D
	if slash_trail_line == null:
		slash_trail_line = Line2D.new()
		slash_trail_line.name = "SlashTrail"
		body_visual.add_child(slash_trail_line)
	slash_trail_line.z_index = 5
	slash_trail_line.width = 4.0
	slash_trail_line.default_color = Color(1.0, 1.0, 1.0, 0.0)
	slash_trail_line.visible = false

	# 10. BlockArc (DIRECT child of BodyVisual)
	block_arc_line = body_visual.get_node_or_null("BlockArc") as Line2D
	if block_arc_line == null:
		block_arc_line = Line2D.new()
		block_arc_line.name = "BlockArc"
		body_visual.add_child(block_arc_line)
	var arc_pts: PackedVector2Array = PackedVector2Array()
	var arc_segs: int = 16
	var half_rad: float = deg_to_rad(BLOCK_FRONT_HALF_ANGLE_DEG)
	var arc_r: float = half_size + 5.0 * s
	arc_pts.resize(arc_segs + 1)
	for i: int in range(arc_segs + 1):
		var a: float = lerpf(-half_rad, half_rad, float(i) / float(arc_segs))
		arc_pts[i] = Vector2.from_angle(a) * arc_r
	block_arc_line.points = arc_pts
	block_arc_line.z_index = 6
	block_arc_line.width = 2.6
	block_arc_line.antialiased = true
	block_arc_line.default_color = Color(0.55, 0.82, 1.0, 0.58)
	block_arc_line.visible = false

	# 11. ManaFlightRing (DIRECT child of BodyVisual, positioned cleanly below feet at +14.5*s)
	mana_flight_ring = body_visual.get_node_or_null("ManaFlightRing") as Line2D
	if mana_flight_ring == null:
		mana_flight_ring = Line2D.new()
		mana_flight_ring.name = "ManaFlightRing"
		body_visual.add_child(mana_flight_ring)
	else:
		for child: Node in mana_flight_ring.get_children():
			mana_flight_ring.remove_child(child)
			child.queue_free()
	var ring_rx: float = (16.0 if is_guard else 14.5) * s
	var ring_ry: float = (7.2 if is_guard else 6.6) * s
	mana_flight_ring.points = _create_ellipse_polygon(ring_rx, ring_ry, 24)
	mana_flight_ring.position = Vector2(0.0, 14.5 * s)
	mana_flight_ring.closed = true
	mana_flight_ring.width = 2.2
	mana_flight_ring.antialiased = true
	mana_flight_ring.z_index = -3
	mana_flight_ring.default_color = Color(0.56, 0.44, 1.0, 0.82) if is_guard else Color(0.32, 0.85, 1.0, 0.80)
	mana_flight_ring.visible = false

	mana_flight_inner_ring = Line2D.new()
	mana_flight_inner_ring.name = "InnerRunicRing"
	mana_flight_inner_ring.points = _create_ellipse_polygon(ring_rx * 0.68, ring_ry * 0.68, 16)
	mana_flight_inner_ring.closed = true
	mana_flight_inner_ring.width = 1.2
	mana_flight_inner_ring.default_color = Color(0.84, 0.72, 1.0, 0.55) if is_guard else Color(0.75, 0.96, 1.0, 0.55)
	mana_flight_ring.add_child(mana_flight_inner_ring)

	# 12. WingVisualRoot (DIRECT child of BodyVisual, behind torso in front view, in front of back in rear view)
	wing_visual_root = body_visual.get_node_or_null("WingVisualRoot") as Node2D
	if wing_visual_root == null:
		wing_visual_root = Node2D.new()
		wing_visual_root.name = "WingVisualRoot"
		body_visual.add_child(wing_visual_root)
	else:
		for child: Node in wing_visual_root.get_children():
			wing_visual_root.remove_child(child)
			child.queue_free()
	wing_visual_root.z_index = -2
	wing_visual_root.position = Vector2(0.0, -3.5 * s)
	wing_visual_root.visible = false

	var wing_col: Color = Color("#D8E6F2")
	var wing_inner_col: Color = Color("#A8C0D6")
	wing_left_poly = Polygon2D.new()
	wing_left_poly.name = "WingLeft"
	wing_left_poly.color = wing_col
	wing_left_poly.position = Vector2(-4.0 * s, 0.0)
	wing_left_poly.polygon = PackedVector2Array([
		Vector2(0.0, -2.5 * s),
		Vector2(-10.0 * s, -12.5 * s),
		Vector2(-19.5 * s, -9.0 * s),
		Vector2(-16.5 * s, -1.5 * s),
		Vector2(-13.5 * s, 4.0 * s),
		Vector2(-7.5 * s, 6.2 * s),
		Vector2(0.0, 3.0 * s),
	])
	wing_visual_root.add_child(wing_left_poly)
	_add_outline(wing_left_poly, wing_left_poly.polygon, outline_col, 1.0 * s)
	var wl_inner: Polygon2D = Polygon2D.new()
	wl_inner.color = wing_inner_col
	wl_inner.polygon = PackedVector2Array([
		Vector2(-1.5 * s, -1.0 * s),
		Vector2(-13.5 * s, -7.0 * s),
		Vector2(-11.0 * s, 1.5 * s),
		Vector2(-1.5 * s, 1.8 * s),
	])
	wing_left_poly.add_child(wl_inner)

	wing_right_poly = Polygon2D.new()
	wing_right_poly.name = "WingRight"
	wing_right_poly.color = wing_col
	wing_right_poly.position = Vector2(4.0 * s, 0.0)
	wing_right_poly.polygon = PackedVector2Array([
		Vector2(0.0, -2.5 * s),
		Vector2(10.0 * s, -12.5 * s),
		Vector2(19.5 * s, -9.0 * s),
		Vector2(16.5 * s, -1.5 * s),
		Vector2(13.5 * s, 4.0 * s),
		Vector2(7.5 * s, 6.2 * s),
		Vector2(0.0, 3.0 * s),
	])
	wing_visual_root.add_child(wing_right_poly)
	_add_outline(wing_right_poly, wing_right_poly.polygon, outline_col, 1.0 * s)
	var wr_inner: Polygon2D = Polygon2D.new()
	wr_inner.color = wing_inner_col
	wr_inner.polygon = PackedVector2Array([
		Vector2(1.5 * s, -1.0 * s),
		Vector2(13.5 * s, -7.0 * s),
		Vector2(11.0 * s, 1.5 * s),
		Vector2(1.5 * s, 1.8 * s),
	])
	wing_right_poly.add_child(wr_inner)

	_apply_procedural_pose()


func _add_outline(parent_node: Node2D, pts: PackedVector2Array, col: Color, width_px: float = 1.1) -> Line2D:
	var line: Line2D = Line2D.new()
	line.points = pts
	line.closed = true
	line.width = width_px
	line.default_color = col
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.antialiased = false
	parent_node.add_child(line)
	return line


func _create_bloody_stump_node(node_name: String, local_pos: Vector2, s: float) -> Node2D:
	var stump: Node2D = Node2D.new()
	stump.name = node_name
	stump.position = local_pos

	var base_wound: Polygon2D = Polygon2D.new()
	base_wound.color = Color("#7A0B14")
	base_wound.polygon = _create_ellipse_polygon(2.8 * s, 2.3 * s, 8)
	stump.add_child(base_wound)

	var blood_rim: Polygon2D = Polygon2D.new()
	blood_rim.color = Color("#D61C28")
	blood_rim.polygon = PackedVector2Array([
		Vector2(-2.0 * s, 0.2 * s),
		Vector2(2.0 * s, 0.2 * s),
		Vector2(1.3 * s, 3.2 * s),
		Vector2(-0.4 * s, 2.4 * s),
		Vector2(-1.6 * s, 3.5 * s),
	])
	stump.add_child(blood_rim)

	var bone_dot: Polygon2D = Polygon2D.new()
	bone_dot.color = Color("#EDE4D0")
	bone_dot.polygon = _create_ellipse_polygon(1.0 * s, 0.85 * s, 6)
	stump.add_child(bone_dot)
	return stump


func _get_style_skin_color() -> Color:
	match visual_style:
		VisualStyle.TROLL_BERSERKER:
			return Color("#4E8A4E")
		VisualStyle.RANK_1_SWORDSMAN:
			return Color("#DFB48C")
		VisualStyle.RANK_6_GUARD:
			return Color("#8C98AC")
		_:
			return Color("#E8C39E")


func _get_style_torso_color() -> Color:
	match visual_style:
		VisualStyle.RANK_1_SWORDSMAN:
			return Color("#D6722E")
		VisualStyle.TROLL_BERSERKER:
			return Color("#4E8A4E")
		VisualStyle.RANK_6_GUARD:
			return Color("#6B3782")
		_:
			return actor_body_color


func _get_style_leg_color() -> Color:
	match visual_style:
		VisualStyle.RANK_1_SWORDSMAN:
			return Color("#4C3F37")
		VisualStyle.TROLL_BERSERKER:
			return Color("#3F733F")
		VisualStyle.RANK_6_GUARD:
			return Color("#5A6272")
		_:
			return Color("#2A3B52")


func _get_style_boot_color() -> Color:
	match visual_style:
		VisualStyle.RANK_1_SWORDSMAN:
			return Color("#4A301F")
		VisualStyle.TROLL_BERSERKER:
			return Color("#356135")
		VisualStyle.RANK_6_GUARD:
			return Color("#8794A8")
		_:
			return Color("#3B2B22")


func _get_style_arm_color() -> Color:
	match visual_style:
		VisualStyle.RANK_1_SWORDSMAN:
			return Color("#BD6024")
		VisualStyle.TROLL_BERSERKER:
			return Color("#498249")
		VisualStyle.RANK_6_GUARD:
			return Color("#6A7488")
		_:
			return actor_body_color.darkened(0.14)


func _get_style_hand_color() -> Color:
	match visual_style:
		VisualStyle.RANK_1_SWORDSMAN:
			return Color("#5B3C26")
		VisualStyle.TROLL_BERSERKER:
			return Color("#3D6E3D")
		VisualStyle.RANK_6_GUARD:
			return Color("#A4B0C4")
		_:
			return Color("#8C96A6")


func _populate_cape_visuals(root: Node2D, s: float, outline_col: Color) -> void:
	match visual_style:
		VisualStyle.PLAYER_ADVENTURER:
			var cloak: Polygon2D = Polygon2D.new()
			cloak.color = Color("#1E4673")
			cloak.polygon = PackedVector2Array([
				Vector2(-7.2 * s, -5.5 * s),
				Vector2(7.2 * s, -5.5 * s),
				Vector2(9.2 * s, 10.6 * s),
				Vector2(0.0, 12.2 * s),
				Vector2(-9.2 * s, 10.6 * s),
			])
			root.add_child(cloak)
			_add_outline(cloak, cloak.polygon, outline_col, 1.0 * s)
			var hem: Polygon2D = Polygon2D.new()
			hem.color = Color("#5CA4E0")
			hem.polygon = PackedVector2Array([
				Vector2(-8.8 * s, 9.2 * s),
				Vector2(8.8 * s, 9.2 * s),
				Vector2(9.0 * s, 10.6 * s),
				Vector2(0.0, 12.0 * s),
				Vector2(-9.0 * s, 10.6 * s),
			])
			root.add_child(hem)

		VisualStyle.RANK_1_SWORDSMAN:
			var scarf: Polygon2D = Polygon2D.new()
			scarf.color = Color("#873B1A")
			scarf.polygon = PackedVector2Array([
				Vector2(-7.4 * s, -5.6 * s),
				Vector2(7.4 * s, -5.6 * s),
				Vector2(8.0 * s, 5.2 * s),
				Vector2(2.4 * s, 3.8 * s),
				Vector2(-1.6 * s, 6.2 * s),
				Vector2(-7.8 * s, 4.4 * s),
			])
			root.add_child(scarf)
			_add_outline(scarf, scarf.polygon, outline_col, 1.0 * s)

		VisualStyle.TROLL_BERSERKER:
			var pelt: Polygon2D = Polygon2D.new()
			pelt.color = Color("#3F2F24")
			pelt.polygon = PackedVector2Array([
				Vector2(-10.5 * s, -6.5 * s),
				Vector2(10.5 * s, -6.5 * s),
				Vector2(11.4 * s, 3.5 * s),
				Vector2(6.0 * s, 5.5 * s),
				Vector2(0.0, 3.2 * s),
				Vector2(-5.5 * s, 5.8 * s),
				Vector2(-11.2 * s, 3.2 * s),
			])
			root.add_child(pelt)
			_add_outline(pelt, pelt.polygon, outline_col, 1.05 * s)

		VisualStyle.RANK_6_GUARD:
			var cape: Polygon2D = Polygon2D.new()
			cape.color = Color("#462058")
			cape.polygon = PackedVector2Array([
				Vector2(-8.6 * s, -5.8 * s),
				Vector2(8.6 * s, -5.8 * s),
				Vector2(11.0 * s, 11.8 * s),
				Vector2(0.0, 13.6 * s),
				Vector2(-11.0 * s, 11.8 * s),
			])
			root.add_child(cape)
			_add_outline(cape, cape.polygon, outline_col, 1.1 * s)
			var gold_trim: Polygon2D = Polygon2D.new()
			gold_trim.color = Color("#D4AC0D")
			gold_trim.polygon = PackedVector2Array([
				Vector2(-10.6 * s, 10.2 * s),
				Vector2(10.6 * s, 10.2 * s),
				Vector2(10.9 * s, 11.7 * s),
				Vector2(0.0, 13.4 * s),
				Vector2(-10.9 * s, 11.7 * s),
			])
			root.add_child(gold_trim)


func _populate_torso_front_details(
	root: Node2D,
	s: float,
	top_w: float,
	bot_w: float,
	top_y: float,
	bot_y: float,
	outline_col: Color
) -> void:
	match visual_style:
		VisualStyle.PLAYER_ADVENTURER:
			# Tunic V-neck undershirt + diagonal leather baldric + belt & brass buckle
			var collar: Polygon2D = Polygon2D.new()
			collar.color = Color("#DDE4EE")
			collar.polygon = PackedVector2Array([
				Vector2(-2.6 * s, top_y),
				Vector2(2.6 * s, top_y),
				Vector2(0.0, top_y + 3.4 * s),
			])
			root.add_child(collar)

			var strap: Polygon2D = Polygon2D.new()
			strap.color = Color("#633E22")
			strap.polygon = PackedVector2Array([
				Vector2(-top_w * 0.72, top_y + 0.6 * s),
				Vector2(-top_w * 0.42, top_y + 0.6 * s),
				Vector2(bot_w * 0.85, bot_y - 3.0 * s),
				Vector2(bot_w * 0.55, bot_y - 3.0 * s),
			])
			root.add_child(strap)

			var belt: Polygon2D = Polygon2D.new()
			belt.color = Color("#4B2E1A")
			belt.polygon = PackedVector2Array([
				Vector2(-bot_w - 0.2 * s, bot_y - 3.4 * s),
				Vector2(bot_w + 0.2 * s, bot_y - 3.4 * s),
				Vector2(bot_w + 0.2 * s, bot_y - 1.1 * s),
				Vector2(-bot_w - 0.2 * s, bot_y - 1.1 * s),
			])
			root.add_child(belt)

			var buckle: Polygon2D = Polygon2D.new()
			buckle.color = Color("#E8BF52")
			buckle.polygon = PackedVector2Array([
				Vector2(-1.6 * s, bot_y - 3.5 * s),
				Vector2(1.6 * s, bot_y - 3.5 * s),
				Vector2(1.6 * s, bot_y - 1.0 * s),
				Vector2(-1.6 * s, bot_y - 1.0 * s),
			])
			root.add_child(buckle)

		VisualStyle.RANK_1_SWORDSMAN:
			# Padded gambeson seams + iron brigandine chest plate + leather belt
			var plate: Polygon2D = Polygon2D.new()
			plate.color = Color("#737C8A")
			plate.polygon = PackedVector2Array([
				Vector2(-top_w * 0.68, top_y + 1.4 * s),
				Vector2(top_w * 0.68, top_y + 1.4 * s),
				Vector2(bot_w * 0.62, bot_y - 4.0 * s),
				Vector2(-bot_w * 0.62, bot_y - 4.0 * s),
			])
			root.add_child(plate)
			_add_outline(plate, plate.polygon, outline_col, 0.85 * s)

			var belt: Polygon2D = Polygon2D.new()
			belt.color = Color("#4A301D")
			belt.polygon = PackedVector2Array([
				Vector2(-bot_w, bot_y - 3.3 * s),
				Vector2(bot_w, bot_y - 3.3 * s),
				Vector2(bot_w, bot_y - 1.0 * s),
				Vector2(-bot_w, bot_y - 1.0 * s),
			])
			root.add_child(belt)

			var clasp: Polygon2D = Polygon2D.new()
			clasp.color = Color("#B5C0CE")
			clasp.polygon = PackedVector2Array([
				Vector2(-1.4 * s, bot_y - 3.3 * s),
				Vector2(1.4 * s, bot_y - 3.3 * s),
				Vector2(1.4 * s, bot_y - 1.0 * s),
				Vector2(-1.4 * s, bot_y - 1.0 * s),
			])
			root.add_child(clasp)

		VisualStyle.TROLL_BERSERKER:
			# Broad muscular chest highlights + fur sash + ragged hide loincloth + bone spikes
			var pec_l: Polygon2D = Polygon2D.new()
			pec_l.color = Color("#63A463")
			pec_l.polygon = _create_offset_ellipse_polygon(Vector2(-3.8 * s, -2.0 * s), 3.6 * s, 2.5 * s, 8)
			root.add_child(pec_l)
			var pec_r: Polygon2D = Polygon2D.new()
			pec_r.color = Color("#63A463")
			pec_r.polygon = _create_offset_ellipse_polygon(Vector2(3.8 * s, -2.0 * s), 3.6 * s, 2.5 * s, 8)
			root.add_child(pec_r)

			var fur_sash: Polygon2D = Polygon2D.new()
			fur_sash.color = Color("#5A402C")
			fur_sash.polygon = PackedVector2Array([
				Vector2(-top_w * 0.78, top_y + 1.0 * s),
				Vector2(-top_w * 0.40, top_y + 0.5 * s),
				Vector2(bot_w * 0.90, bot_y - 2.6 * s),
				Vector2(bot_w * 0.42, bot_y - 2.0 * s),
			])
			root.add_child(fur_sash)
			_add_outline(fur_sash, fur_sash.polygon, outline_col, 0.85 * s)

			# Bone fangs on sash
			for bx: float in [-3.5, 0.5, 4.2]:
				var fang: Polygon2D = Polygon2D.new()
				fang.color = Color("#EFE7CE")
				fang.polygon = PackedVector2Array([
					Vector2((bx - 0.7) * s, (-2.8 + bx * 0.45) * s),
					Vector2((bx + 0.7) * s, (-2.8 + bx * 0.45) * s),
					Vector2(bx * s, (-0.3 + bx * 0.45) * s),
				])
				root.add_child(fang)

			var loincloth: Polygon2D = Polygon2D.new()
			loincloth.color = Color("#4E3726")
			loincloth.polygon = PackedVector2Array([
				Vector2(-bot_w * 0.95, bot_y - 3.0 * s),
				Vector2(bot_w * 0.95, bot_y - 3.0 * s),
				Vector2(bot_w * 0.70, bot_y + 2.8 * s),
				Vector2(1.4 * s, bot_y + 1.4 * s),
				Vector2(-1.6 * s, bot_y + 3.2 * s),
				Vector2(-bot_w * 0.75, bot_y + 2.2 * s),
			])
			root.add_child(loincloth)
			_add_outline(loincloth, loincloth.polygon, outline_col, 0.9 * s)

		VisualStyle.RANK_6_GUARD:
			# Beveled heavy steel breastplate + gold filigree crest + armored waist tassets
			var breastplate: Polygon2D = Polygon2D.new()
			breastplate.color = Color("#8D99AE")
			breastplate.polygon = PackedVector2Array([
				Vector2(-top_w * 0.82, top_y + 0.8 * s),
				Vector2(top_w * 0.82, top_y + 0.8 * s),
				Vector2(bot_w * 0.78, bot_y - 3.2 * s),
				Vector2(0.0, bot_y - 1.6 * s),
				Vector2(-bot_w * 0.78, bot_y - 3.2 * s),
			])
			root.add_child(breastplate)
			_add_outline(breastplate, breastplate.polygon, outline_col, 0.95 * s)

			var plate_hi: Polygon2D = Polygon2D.new()
			plate_hi.color = Color("#C2CEE0")
			plate_hi.polygon = PackedVector2Array([
				Vector2(-top_w * 0.62, top_y + 1.4 * s),
				Vector2(top_w * 0.20, top_y + 1.4 * s),
				Vector2(0.0, top_y + 4.4 * s),
				Vector2(-top_w * 0.50, top_y + 4.2 * s),
			])
			root.add_child(plate_hi)

			var emblem: Polygon2D = Polygon2D.new()
			emblem.color = Color("#F1C40F")
			emblem.polygon = PackedVector2Array([
				Vector2(0.0, top_y + 2.2 * s),
				Vector2(2.4 * s, top_y + 5.2 * s),
				Vector2(0.0, top_y + 8.4 * s),
				Vector2(-2.4 * s, top_y + 5.2 * s),
			])
			root.add_child(emblem)

			var tasset: Polygon2D = Polygon2D.new()
			tasset.color = Color("#6B3782")
			tasset.polygon = PackedVector2Array([
				Vector2(-bot_w * 0.72, bot_y - 2.0 * s),
				Vector2(bot_w * 0.72, bot_y - 2.0 * s),
				Vector2(bot_w * 0.56, bot_y + 2.6 * s),
				Vector2(0.0, bot_y + 3.4 * s),
				Vector2(-bot_w * 0.56, bot_y + 2.6 * s),
			])
			root.add_child(tasset)
			_add_outline(tasset, tasset.polygon, outline_col, 0.85 * s)


func _populate_torso_back_details(
	root: Node2D,
	s: float,
	top_w: float,
	bot_w: float,
	top_y: float,
	bot_y: float,
	outline_col: Color
) -> void:
	match visual_style:
		VisualStyle.TROLL_BERSERKER:
			# Hunched spinal ridge + back muscle shade
			var spine: Polygon2D = Polygon2D.new()
			spine.color = Color("#345E34")
			spine.polygon = PackedVector2Array([
				Vector2(-2.2 * s, top_y + 1.2 * s),
				Vector2(2.2 * s, top_y + 1.2 * s),
				Vector2(1.4 * s, bot_y - 1.4 * s),
				Vector2(-1.4 * s, bot_y - 1.4 * s),
			])
			root.add_child(spine)
		VisualStyle.RANK_6_GUARD:
			var backplate: Polygon2D = Polygon2D.new()
			backplate.color = Color("#7C889C")
			backplate.polygon = PackedVector2Array([
				Vector2(-top_w * 0.76, top_y + 1.0 * s),
				Vector2(top_w * 0.76, top_y + 1.0 * s),
				Vector2(bot_w * 0.72, bot_y - 2.6 * s),
				Vector2(-bot_w * 0.72, bot_y - 2.6 * s),
			])
			root.add_child(backplate)
			_add_outline(backplate, backplate.polygon, outline_col, 0.85 * s)
			var gold_spine: Polygon2D = Polygon2D.new()
			gold_spine.color = Color("#F1C40F")
			gold_spine.polygon = PackedVector2Array([
				Vector2(-1.0 * s, top_y + 1.5 * s),
				Vector2(1.0 * s, top_y + 1.5 * s),
				Vector2(1.0 * s, bot_y - 3.0 * s),
				Vector2(-1.0 * s, bot_y - 3.0 * s),
			])
			root.add_child(gold_spine)
		_:
			# Back harness strap & waist belt
			var strap: Polygon2D = Polygon2D.new()
			strap.color = Color("#4B2E1A")
			strap.polygon = PackedVector2Array([
				Vector2(-bot_w, bot_y - 3.2 * s),
				Vector2(bot_w, bot_y - 3.2 * s),
				Vector2(bot_w, bot_y - 1.1 * s),
				Vector2(-bot_w, bot_y - 1.1 * s),
			])
			root.add_child(strap)


func _populate_head_front_details(root: Node2D, s: float, hrx: float, hry: float, outline_col: Color) -> void:
	var cy: float = -hry * 0.85
	match visual_style:
		VisualStyle.PLAYER_ADVENTURER:
			# Dark hair bangs/crown + crisp 3/4 eyes slightly shifted toward facing side (+X)
			var hair: Polygon2D = Polygon2D.new()
			hair.color = Color("#2C2420")
			hair.polygon = PackedVector2Array([
				Vector2(-hrx * 1.05, cy - 0.4 * s),
				Vector2(-hrx * 0.92, cy - hry * 0.88),
				Vector2(-hrx * 0.20, cy - hry * 1.18),
				Vector2(hrx * 0.65, cy - hry * 1.02),
				Vector2(hrx * 1.05, cy - 0.9 * s),
				Vector2(hrx * 0.45, cy - 2.3 * s),
				Vector2(-hrx * 0.15, cy - 1.3 * s),
				Vector2(-hrx * 0.72, cy - 2.0 * s),
			])
			root.add_child(hair)
			_add_outline(hair, hair.polygon, outline_col, 0.9 * s)

			for ex: float in [-1.4, 2.3]:
				var eye: Polygon2D = Polygon2D.new()
				eye.color = Color("#141824")
				eye.polygon = PackedVector2Array([
					Vector2((ex - 0.85) * s, cy - 0.4 * s),
					Vector2((ex + 0.85) * s, cy - 0.4 * s),
					Vector2((ex + 0.85) * s, cy + 1.5 * s),
					Vector2((ex - 0.85) * s, cy + 1.5 * s),
				])
				root.add_child(eye)
				var glint: Polygon2D = Polygon2D.new()
				glint.color = Color("#F5F8FC")
				glint.polygon = PackedVector2Array([
					Vector2((ex - 0.35) * s, cy - 0.2 * s),
					Vector2((ex + 0.35) * s, cy - 0.2 * s),
					Vector2((ex + 0.35) * s, cy + 0.45 * s),
					Vector2((ex - 0.35) * s, cy + 0.45 * s),
				])
				root.add_child(glint)

		VisualStyle.RANK_1_SWORDSMAN:
			# Open steel mercenary helmet + bright steel rim + stern eyes
			var helm: Polygon2D = Polygon2D.new()
			helm.color = Color("#7A8492")
			helm.polygon = PackedVector2Array([
				Vector2(-hrx * 1.12, cy - 0.6 * s),
				Vector2(-hrx * 0.96, cy - hry * 0.95),
				Vector2(0.0, cy - hry * 1.24),
				Vector2(hrx * 0.96, cy - hry * 0.95),
				Vector2(hrx * 1.12, cy - 0.6 * s),
				Vector2(hrx * 0.55, cy - 1.6 * s),
				Vector2(-hrx * 0.55, cy - 1.6 * s),
			])
			root.add_child(helm)
			_add_outline(helm, helm.polygon, outline_col, 1.0 * s)

			var rim: Polygon2D = Polygon2D.new()
			rim.color = Color("#BEC8D6")
			rim.polygon = PackedVector2Array([
				Vector2(-hrx * 0.72, cy - hry * 0.75),
				Vector2(hrx * 0.30, cy - hry * 0.96),
				Vector2(hrx * 0.30, cy - hry * 0.55),
				Vector2(-hrx * 0.72, cy - hry * 0.40),
			])
			root.add_child(rim)

			for ex: float in [-1.5, 2.2]:
				var eye: Polygon2D = Polygon2D.new()
				eye.color = Color("#181A22")
				eye.polygon = PackedVector2Array([
					Vector2((ex - 0.8) * s, cy + 0.1 * s),
					Vector2((ex + 0.8) * s, cy + 0.1 * s),
					Vector2((ex + 0.8) * s, cy + 1.6 * s),
					Vector2((ex - 0.8) * s, cy + 1.6 * s),
				])
				root.add_child(eye)

		VisualStyle.TROLL_BERSERKER:
			# Pointed ears, shaggy dark mane, heavy brow, fierce amber eyes & ivory tusks!
			for eside: float in [-1.0, 1.0]:
				var ear: Polygon2D = Polygon2D.new()
				ear.color = Color("#467F46")
				ear.polygon = PackedVector2Array([
					Vector2(eside * hrx * 0.85, cy - 1.2 * s),
					Vector2(eside * (hrx + 3.2 * s), cy - 2.6 * s),
					Vector2(eside * hrx * 0.92, cy + 1.0 * s),
				])
				root.add_child(ear)
				_add_outline(ear, ear.polygon, outline_col, 0.9 * s)

			var mane: Polygon2D = Polygon2D.new()
			mane.color = Color("#261E19")
			mane.polygon = PackedVector2Array([
				Vector2(-hrx * 1.05, cy - 1.8 * s),
				Vector2(-hrx * 0.72, cy - hry * 1.28),
				Vector2(-1.2 * s, cy - hry * 1.08),
				Vector2(1.4 * s, cy - hry * 1.32),
				Vector2(hrx * 0.80, cy - hry * 1.05),
				Vector2(hrx * 1.05, cy - 1.6 * s),
			])
			root.add_child(mane)
			_add_outline(mane, mane.polygon, outline_col, 0.9 * s)

			var brow: Polygon2D = Polygon2D.new()
			brow.color = Color("#345E34")
			brow.polygon = PackedVector2Array([
				Vector2(-hrx * 0.82, cy - 1.7 * s),
				Vector2(hrx * 0.86, cy - 1.7 * s),
				Vector2(hrx * 0.78, cy - 0.2 * s),
				Vector2(0.4 * s, cy + 0.5 * s),
				Vector2(-hrx * 0.78, cy - 0.2 * s),
			])
			root.add_child(brow)

			for ex: float in [-1.8, 2.5]:
				var eye: Polygon2D = Polygon2D.new()
				eye.color = Color("#FF6B2B")
				eye.polygon = PackedVector2Array([
					Vector2((ex - 1.0) * s, cy - 0.2 * s),
					Vector2((ex + 1.0) * s, cy - 0.2 * s),
					Vector2((ex + 0.8) * s, cy + 1.2 * s),
					Vector2((ex - 0.8) * s, cy + 1.2 * s),
				])
				root.add_child(eye)

			var mouth: Polygon2D = Polygon2D.new()
			mouth.color = Color("#261214")
			mouth.polygon = PackedVector2Array([
				Vector2(-3.2 * s, cy + 2.4 * s),
				Vector2(3.8 * s, cy + 2.4 * s),
				Vector2(3.0 * s, cy + 4.0 * s),
				Vector2(-2.6 * s, cy + 4.0 * s),
			])
			root.add_child(mouth)

			# Prominent curved ivory tusks
			for tx: float in [-2.6, 3.1]:
				var tusk: Polygon2D = Polygon2D.new()
				tusk.color = Color("#F5EDD4")
				tusk.polygon = PackedVector2Array([
					Vector2((tx - 0.9) * s, cy + 3.6 * s),
					Vector2((tx + 0.9) * s, cy + 3.6 * s),
					Vector2((tx + (0.4 if tx > 0.0 else -0.4)) * s, cy + 0.3 * s),
				])
				root.add_child(tusk)
				_add_outline(tusk, tusk.polygon, outline_col, 0.75 * s)

		VisualStyle.RANK_6_GUARD:
			# Visored steel greathelm + gold trim + glowing arcane visor eyes + royal plume!
			var plume: Polygon2D = Polygon2D.new()
			plume.color = Color("#9B59B6")
			plume.polygon = PackedVector2Array([
				Vector2(-1.2 * s, cy - hry * 0.95),
				Vector2(1.4 * s, cy - hry * 1.48),
				Vector2(-4.4 * s, cy - hry * 1.65),
				Vector2(-7.8 * s, cy - hry * 1.15),
				Vector2(-4.0 * s, cy - hry * 0.85),
			])
			root.add_child(plume)
			_add_outline(plume, plume.polygon, outline_col, 0.9 * s)

			var faceplate: Polygon2D = Polygon2D.new()
			faceplate.color = Color("#98A6BA")
			faceplate.polygon = PackedVector2Array([
				Vector2(-hrx * 0.86, cy - hry * 0.75),
				Vector2(hrx * 0.88, cy - hry * 0.75),
				Vector2(hrx * 0.92, cy + hry * 0.55),
				Vector2(0.6 * s, cy + hry * 0.96),
				Vector2(-hrx * 0.82, cy + hry * 0.55),
			])
			root.add_child(faceplate)
			_add_outline(faceplate, faceplate.polygon, outline_col, 0.95 * s)

			var visor: Polygon2D = Polygon2D.new()
			visor.color = Color("#11131C")
			visor.polygon = PackedVector2Array([
				Vector2(-hrx * 0.68, cy - 0.8 * s),
				Vector2(hrx * 0.78, cy - 0.8 * s),
				Vector2(hrx * 0.70, cy + 1.3 * s),
				Vector2(1.2 * s, cy + 1.3 * s),
				Vector2(1.2 * s, cy + 3.6 * s),
				Vector2(-0.4 * s, cy + 3.6 * s),
				Vector2(-0.4 * s, cy + 1.3 * s),
				Vector2(-hrx * 0.60, cy + 1.3 * s),
			])
			root.add_child(visor)

			# Glowing cyan-arcane eyes inside visor slit
			for gx: float in [-1.8, 2.4]:
				var glow_eye: Polygon2D = Polygon2D.new()
				glow_eye.color = Color("#5CE1FF")
				glow_eye.polygon = PackedVector2Array([
					Vector2((gx - 1.1) * s, cy - 0.35 * s),
					Vector2((gx + 1.1) * s, cy - 0.35 * s),
					Vector2((gx + 0.9) * s, cy + 0.85 * s),
					Vector2((gx - 0.9) * s, cy + 0.85 * s),
				])
				root.add_child(glow_eye)

			var crown_band: Polygon2D = Polygon2D.new()
			crown_band.color = Color("#F1C40F")
			crown_band.polygon = PackedVector2Array([
				Vector2(-hrx * 0.86, cy - hry * 0.52),
				Vector2(hrx * 0.88, cy - hry * 0.52),
				Vector2(hrx * 0.88, cy - hry * 0.25),
				Vector2(-hrx * 0.86, cy - hry * 0.25),
			])
			root.add_child(crown_band)


func _populate_head_back_details(root: Node2D, s: float, hrx: float, hry: float, outline_col: Color) -> void:
	var cy: float = -hry * 0.85
	match visual_style:
		VisualStyle.PLAYER_ADVENTURER:
			var back_hair: Polygon2D = Polygon2D.new()
			back_hair.color = Color("#2C2420")
			back_hair.polygon = _create_offset_ellipse_polygon(Vector2(0.0, cy - 0.4 * s), hrx * 1.02, hry * 1.02, 12)
			root.add_child(back_hair)
			_add_outline(back_hair, back_hair.polygon, outline_col, 0.95 * s)

		VisualStyle.RANK_1_SWORDSMAN:
			var helm_back: Polygon2D = Polygon2D.new()
			helm_back.color = Color("#6D7786")
			helm_back.polygon = PackedVector2Array([
				Vector2(-hrx * 1.06, cy + 1.4 * s),
				Vector2(-hrx * 0.98, cy - hry * 0.92),
				Vector2(0.0, cy - hry * 1.22),
				Vector2(hrx * 0.98, cy - hry * 0.92),
				Vector2(hrx * 1.06, cy + 1.4 * s),
			])
			root.add_child(helm_back)
			_add_outline(helm_back, helm_back.polygon, outline_col, 0.95 * s)

		VisualStyle.TROLL_BERSERKER:
			for eside: float in [-1.0, 1.0]:
				var ear: Polygon2D = Polygon2D.new()
				ear.color = Color("#3F733F")
				ear.polygon = PackedVector2Array([
					Vector2(eside * hrx * 0.85, cy - 1.2 * s),
					Vector2(eside * (hrx + 3.2 * s), cy - 2.6 * s),
					Vector2(eside * hrx * 0.92, cy + 1.0 * s),
				])
				root.add_child(ear)
				_add_outline(ear, ear.polygon, outline_col, 0.9 * s)
			var back_mane: Polygon2D = Polygon2D.new()
			back_mane.color = Color("#241C17")
			back_mane.polygon = PackedVector2Array([
				Vector2(-hrx * 1.02, cy + 3.0 * s),
				Vector2(-hrx * 0.96, cy - hry * 1.15),
				Vector2(0.0, cy - hry * 1.30),
				Vector2(hrx * 0.96, cy - hry * 1.15),
				Vector2(hrx * 1.02, cy + 3.0 * s),
				Vector2(2.6 * s, cy + 4.4 * s),
				Vector2(-2.2 * s, cy + 4.6 * s),
			])
			root.add_child(back_mane)
			_add_outline(back_mane, back_mane.polygon, outline_col, 0.95 * s)

		VisualStyle.RANK_6_GUARD:
			var helm_back: Polygon2D = Polygon2D.new()
			helm_back.color = Color("#748094")
			helm_back.polygon = _create_offset_ellipse_polygon(Vector2(0.0, cy), hrx * 0.98, hry * 0.98, 12)
			root.add_child(helm_back)
			_add_outline(helm_back, helm_back.polygon, outline_col, 0.95 * s)
			var gold_ridge: Polygon2D = Polygon2D.new()
			gold_ridge.color = Color("#F1C40F")
			gold_ridge.polygon = PackedVector2Array([
				Vector2(-1.0 * s, cy - hry * 0.95),
				Vector2(1.0 * s, cy - hry * 0.95),
				Vector2(1.0 * s, cy + hry * 0.80),
				Vector2(-1.0 * s, cy + hry * 0.80),
			])
			root.add_child(gold_ridge)
			var plume: Polygon2D = Polygon2D.new()
			plume.color = Color("#9B59B6")
			plume.polygon = PackedVector2Array([
				Vector2(-2.0 * s, cy - hry * 1.38),
				Vector2(2.0 * s, cy - hry * 1.38),
				Vector2(2.8 * s, cy + 0.5 * s),
				Vector2(0.0, cy + 2.4 * s),
				Vector2(-2.8 * s, cy + 0.5 * s),
			])
			root.add_child(plume)
			_add_outline(plume, plume.polygon, outline_col, 0.9 * s)


func _ensure_body_collider() -> void:
	body_collision_shape = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if body_collision_shape == null:
		body_collision_shape = CollisionShape2D.new()
		body_collision_shape.name = "CollisionShape2D"
		add_child(body_collision_shape)
	if body_collision_shape.shape == null:
		var circle: CircleShape2D = CircleShape2D.new()
		circle.radius = 10.0 * actor_size_mult
		body_collision_shape.shape = circle


func refresh_weapon_visual() -> void:
	if weapon_blade_poly == null or weapon_aura_outline == null:
		return
	if weapon_detail_root != null:
		for child: Node in weapon_detail_root.get_children():
			weapon_detail_root.remove_child(child)
			child.queue_free()

	if equipped_weapon == null or equipped_weapon.is_unarmed:
		weapon_blade_poly.visible = false
		weapon_aura_outline.visible = false
		return

	weapon_blade_poly.visible = true
	var m_ctrl: float = stat_sheet.get_stat(StatSheet.Stat.M_CTRL) if (stat_sheet != null and stat_sheet.mana_awakened) else 0.0
	var aura: PenetrationResolver.AuraBonuses = PenetrationResolver.calculate_aura_bonuses(aura_active, m_ctrl, current_attack_aura_burst)
	var base_len: float = equipped_weapon.get_effective_blade_length(half_swording)
	var visual_len: float = base_len + aura.blade_extension
	var hilt: float = equipped_weapon.hilt_offset_px
	var half_w: float = maxf(1.4, equipped_weapon.blade_width_px * 0.5)
	var broken: bool = equipped_weapon.is_broken()
	var is_hammer: bool = equipped_weapon.weapon_id == &"warhammer" or equipped_weapon.damage_mode == WeaponData.DamageMode.BLUNT_ONLY
	var is_troll_club: bool = equipped_weapon.display_name.contains("Troll") or equipped_weapon.display_name.contains("Cleaver")
	var outline_col: Color = Color("#14161E")

	var blade_pts: PackedVector2Array
	var aura_pts: PackedVector2Array
	var pad: float = 2.4 if current_attack_aura_burst else 1.5

	if broken:
		var stub_len: float = maxf(6.0, visual_len * 0.38)
		blade_pts = PackedVector2Array([
			Vector2(hilt, -half_w * 0.85),
			Vector2(hilt + stub_len, -half_w * 0.7),
			Vector2(hilt + stub_len - 2.0, -0.4),
			Vector2(hilt + stub_len + 1.5, half_w * 0.65),
			Vector2(hilt, half_w * 0.85),
		])
		aura_pts = blade_pts
	elif is_troll_club:
		# Jagged heavy iron-banded cleaver-club (asymmetric chopping edge on -Y so scale.y=-1 keeps it upright!)
		var head_start: float = hilt + visual_len * 0.42
		var head_end: float = hilt + visual_len + 2.5
		blade_pts = PackedVector2Array([
			Vector2(hilt - 3.0, -2.0),
			Vector2(head_start, -2.4),
			Vector2(head_start + 3.0, -half_w * 1.45),
			Vector2(head_end - 2.0, -half_w * 1.65),
			Vector2(head_end, -half_w * 0.4),
			Vector2(head_end - 1.5, half_w * 0.72),
			Vector2(head_start, half_w * 0.58),
			Vector2(hilt - 3.0, 2.0),
		])
		aura_pts = PackedVector2Array([
			Vector2(head_start - pad, -half_w * 1.45 - pad),
			Vector2(head_end + pad, -half_w * 1.65 - pad),
			Vector2(head_end + pad + 1.5, -half_w * 0.3),
			Vector2(head_end + pad, half_w * 0.75 + pad),
			Vector2(head_start - pad, half_w * 0.65 + pad),
		])
	elif is_hammer:
		# Long warhammer haft + flanged heavy steel hammer head + upper crow's beak spike
		var head_x0: float = hilt + visual_len * 0.70
		var head_x1: float = hilt + visual_len + 2.0
		blade_pts = PackedVector2Array([
			Vector2(head_x0, -half_w * 1.45),
			Vector2(head_x1, -half_w * 1.45),
			Vector2(head_x1 + 1.5, -half_w * 0.9),
			Vector2(head_x1 + 1.5, half_w * 0.9),
			Vector2(head_x1, half_w * 1.25),
			Vector2(head_x0, half_w * 1.10),
		])
		aura_pts = PackedVector2Array([
			Vector2(head_x0 - pad, -half_w * 1.55 - pad),
			Vector2(head_x1 + pad, -half_w * 1.55 - pad),
			Vector2(head_x1 + pad + 2.0, 0.0),
			Vector2(head_x1 + pad, half_w * 1.35 + pad),
			Vector2(head_x0 - pad, half_w * 1.20 + pad),
		])
	else:
		# Tapered broadsword / greatsword / dagger blade
		blade_pts = PackedVector2Array([
			Vector2(hilt, -half_w),
			Vector2(hilt + visual_len, -half_w * 0.62),
			Vector2(hilt + visual_len + 3.5, 0.0),
			Vector2(hilt + visual_len, half_w * 0.62),
			Vector2(hilt, half_w),
		])
		aura_pts = PackedVector2Array([
			Vector2(hilt - pad, -half_w - pad),
			Vector2(hilt + visual_len + pad, -half_w * 0.62 - pad),
			Vector2(hilt + visual_len + 5.0, 0.0),
			Vector2(hilt + visual_len + pad, half_w * 0.62 + pad),
			Vector2(hilt - pad, half_w + pad),
		])

	weapon_blade_poly.polygon = blade_pts
	weapon_blade_poly.color = Color("#5A5A60") if broken else equipped_weapon.blade_color

	# Populate rich weapon hilt / crossguard / haft / specular highlight details
	if weapon_detail_root != null:
		_add_outline(weapon_detail_root, blade_pts, outline_col, 1.0)
		if is_hammer and not is_troll_club:
			# Wooden polearm haft + top beak spike + steel face shine
			var haft: Polygon2D = Polygon2D.new()
			haft.z_index = -1
			haft.color = Color("#6C492C")
			haft.polygon = PackedVector2Array([
				Vector2(hilt - 6.0, -1.8),
				Vector2(hilt + visual_len * 0.85, -1.8),
				Vector2(hilt + visual_len * 0.85, 1.8),
				Vector2(hilt - 6.0, 1.8),
			])
			weapon_detail_root.add_child(haft)
			_add_outline(weapon_detail_root, haft.polygon, outline_col, 0.9)

			var beak: Polygon2D = Polygon2D.new()
			beak.color = Color("#9BA6B8")
			var bx: float = hilt + visual_len * 0.82
			beak.polygon = PackedVector2Array([
				Vector2(bx - 2.2, -half_w * 1.35),
				Vector2(bx + 2.2, -half_w * 1.35),
				Vector2(bx - 0.5, -half_w * 2.15),
			])
			weapon_detail_root.add_child(beak)
			_add_outline(weapon_detail_root, beak.polygon, outline_col, 0.85)
		elif is_troll_club:
			# Iron bands & crude spikes on club
			var band: Polygon2D = Polygon2D.new()
			band.color = Color("#3D424D")
			var b_x: float = hilt + visual_len * 0.68
			band.polygon = PackedVector2Array([
				Vector2(b_x - 1.5, -half_w * 1.45),
				Vector2(b_x + 1.5, -half_w * 1.45),
				Vector2(b_x + 1.5, half_w * 0.65),
				Vector2(b_x - 1.5, half_w * 0.65),
			])
			weapon_detail_root.add_child(band)
		else:
			# Specular top-edge highlight + wrapped grip + sculpted crossguard + pommel
			var hi: Polygon2D = Polygon2D.new()
			hi.color = weapon_blade_poly.color.lightened(0.28)
			hi.polygon = PackedVector2Array([
				Vector2(hilt + 1.0, -half_w * 0.85),
				Vector2(hilt + visual_len * 0.92, -half_w * 0.50),
				Vector2(hilt + visual_len * 0.92, -0.35),
				Vector2(hilt + 1.0, -0.35),
			])
			weapon_detail_root.add_child(hi)

			var grip_len: float = 8.5 if equipped_weapon.can_half_sword else 5.2
			var grip: Polygon2D = Polygon2D.new()
			grip.color = Color("#5D3C24")
			grip.polygon = PackedVector2Array([
				Vector2(hilt - grip_len, -1.5),
				Vector2(hilt, -1.5),
				Vector2(hilt, 1.5),
				Vector2(hilt - grip_len, 1.5),
			])
			weapon_detail_root.add_child(grip)
			_add_outline(weapon_detail_root, grip.polygon, outline_col, 0.85)

			var guard_half: float = clampf(half_w * 2.1, 3.6, 7.6)
			var guard: Polygon2D = Polygon2D.new()
			guard.color = Color("#D4AF37") if visual_style == VisualStyle.RANK_6_GUARD else Color("#A89268")
			guard.polygon = PackedVector2Array([
				Vector2(hilt - 1.4, -guard_half),
				Vector2(hilt + 1.4, -guard_half * 0.85),
				Vector2(hilt + 1.4, guard_half * 0.85),
				Vector2(hilt - 1.4, guard_half),
			])
			weapon_detail_root.add_child(guard)
			_add_outline(weapon_detail_root, guard.polygon, outline_col, 0.85)

			var pommel: Polygon2D = Polygon2D.new()
			pommel.color = guard.color
			pommel.polygon = _create_offset_ellipse_polygon(Vector2(hilt - grip_len - 1.2, 0.0), 1.9, 1.9, 6)
			weapon_detail_root.add_child(pommel)

	weapon_aura_outline.visible = aura.active
	if aura.active:
		weapon_aura_outline.points = aura_pts
		if current_attack_aura_burst:
			weapon_aura_outline.default_color = Color("#FFF066")
		else:
			weapon_aura_outline.default_color = Color("#4FD8FF") if m_ctrl < 50.0 else Color("#FFD166")


func _create_octagon_polygon(r: float) -> PackedVector2Array:
	var c: float = r * 0.42
	return PackedVector2Array([
		Vector2(-r + c, -r),
		Vector2(r - c, -r),
		Vector2(r, -r + c),
		Vector2(r, r - c),
		Vector2(r - c, r),
		Vector2(-r + c, r),
		Vector2(-r, r - c),
		Vector2(-r, -r + c),
	])


func _create_ellipse_polygon(rx: float, ry: float, segments: int) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	pts.resize(segments)
	for i: int in range(segments):
		var a: float = TAU * float(i) / float(segments)
		pts[i] = Vector2(cos(a) * rx, sin(a) * ry)
	return pts


func _create_offset_ellipse_polygon(center: Vector2, rx: float, ry: float, segments: int) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	pts.resize(segments)
	for i: int in range(segments):
		var a: float = TAU * float(i) / float(segments)
		pts[i] = center + Vector2(cos(a) * rx, sin(a) * ry)
	return pts


# ---------------------------------------------------------------------------
# Anatomical HitboxZones Builder
# ---------------------------------------------------------------------------

func rebuild_hitbox_zones(
	armor_thickness: float = 0.0,
	armor_hardness: float = 0.0,
	weak_points_by_zone: Dictionary = {}
) -> void:
	_last_hitbox_armor_thickness = armor_thickness
	_last_hitbox_armor_hardness = armor_hardness
	_last_hitbox_weak_points = weak_points_by_zone.duplicate(true)
	for hz: HitboxZone in hitbox_zones:
		if is_instance_valid(hz):
			hz.queue_free()
	hitbox_zones.clear()

	var s: float = actor_size_mult
	var head_shape: CircleShape2D = CircleShape2D.new()
	head_shape.radius = 5.5 * s
	_add_hitbox_zone(AnatomyComponent.ZONE_HEAD, head_shape, Vector2(0.0, -8.0 * s), _extract_wp_array(weak_points_by_zone, AnatomyComponent.ZONE_HEAD), armor_thickness, armor_hardness)

	var neck_shape: RectangleShape2D = RectangleShape2D.new()
	neck_shape.size = Vector2(6.0 * s, 3.0 * s)
	_add_hitbox_zone(AnatomyComponent.ZONE_NECK, neck_shape, Vector2(0.0, -3.5 * s), _extract_wp_array(weak_points_by_zone, AnatomyComponent.ZONE_NECK), armor_thickness, armor_hardness)

	var chest_shape: CircleShape2D = CircleShape2D.new()
	chest_shape.radius = 7.5 * s
	_add_hitbox_zone(AnatomyComponent.ZONE_CHEST, chest_shape, Vector2(0.0, 1.0 * s), _extract_wp_array(weak_points_by_zone, AnatomyComponent.ZONE_CHEST), armor_thickness, armor_hardness)

	var stomach_shape: RectangleShape2D = RectangleShape2D.new()
	stomach_shape.size = Vector2(10.0 * s, 5.0 * s)
	_add_hitbox_zone(AnatomyComponent.ZONE_STOMACH, stomach_shape, Vector2(0.0, 7.5 * s), _extract_wp_array(weak_points_by_zone, AnatomyComponent.ZONE_STOMACH), armor_thickness, armor_hardness)

	var left_arm_shape: RectangleShape2D = RectangleShape2D.new()
	left_arm_shape.size = Vector2(4.0 * s, 9.0 * s)
	_add_hitbox_zone(AnatomyComponent.ZONE_LEFT_ARM, left_arm_shape, Vector2(-9.0 * s, 2.0 * s), _extract_wp_array(weak_points_by_zone, AnatomyComponent.ZONE_LEFT_ARM), armor_thickness, armor_hardness)

	var right_arm_shape: RectangleShape2D = RectangleShape2D.new()
	right_arm_shape.size = Vector2(4.0 * s, 9.0 * s)
	_add_hitbox_zone(AnatomyComponent.ZONE_RIGHT_ARM, right_arm_shape, Vector2(9.0 * s, 2.0 * s), _extract_wp_array(weak_points_by_zone, AnatomyComponent.ZONE_RIGHT_ARM), armor_thickness, armor_hardness)

	var left_leg_shape: RectangleShape2D = RectangleShape2D.new()
	left_leg_shape.size = Vector2(4.5 * s, 7.0 * s)
	_add_hitbox_zone(AnatomyComponent.ZONE_LEFT_LEG, left_leg_shape, Vector2(-4.0 * s, 11.5 * s), _extract_wp_array(weak_points_by_zone, AnatomyComponent.ZONE_LEFT_LEG), armor_thickness, armor_hardness)

	var right_leg_shape: RectangleShape2D = RectangleShape2D.new()
	right_leg_shape.size = Vector2(4.5 * s, 7.0 * s)
	_add_hitbox_zone(AnatomyComponent.ZONE_RIGHT_LEG, right_leg_shape, Vector2(4.0 * s, 11.5 * s), _extract_wp_array(weak_points_by_zone, AnatomyComponent.ZONE_RIGHT_LEG), armor_thickness, armor_hardness)

	if has_wings:
		_ensure_wings_hitbox_zone()

	if verticality != null:
		verticality.sync_visuals()


func _ensure_wings_hitbox_zone() -> HitboxZone:
	var existing: HitboxZone = _find_hitbox_zone_by_name(AnatomyComponent.ZONE_WINGS)
	if existing != null:
		return existing
	var s: float = actor_size_mult
	var wings_shape: RectangleShape2D = RectangleShape2D.new()
	wings_shape.size = Vector2(24.0 * s, 10.0 * s)
	return _add_hitbox_zone(
		AnatomyComponent.ZONE_WINGS,
		wings_shape,
		Vector2(0.0, 0.0),
		_extract_wp_array(_last_hitbox_weak_points, AnatomyComponent.ZONE_WINGS),
		0.0,
		0.0
	)


func set_has_wings(enabled: bool) -> bool:
	has_wings = enabled
	if enabled:
		if anatomy != null:
			anatomy.add_optional_zone(AnatomyComponent.ZONE_WINGS)
		_ensure_wings_hitbox_zone()
	else:
		if get_flight_mode() == VerticalityComponent.FlightMode.WING_FLIGHT:
			land_from_flight(false, "wings_removed")
		for i: int in range(hitbox_zones.size() - 1, -1, -1):
			var hz: HitboxZone = hitbox_zones[i]
			if is_instance_valid(hz) and hz.zone_name == AnatomyComponent.ZONE_WINGS:
				hitbox_zones.remove_at(i)
				hz.queue_free()
		if anatomy != null:
			anatomy.remove_optional_zone(AnatomyComponent.ZONE_WINGS)
	_sync_flight_stat_tags_and_visuals()
	return has_wings


func _extract_wp_array(dict: Dictionary, zone_key: StringName) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if not dict.has(zone_key):
		return out
	var raw: Variant = dict[zone_key]
	if raw is Array:
		for item: Variant in (raw as Array):
			if item is Vector2:
				out.append(item as Vector2)
	return out


func _add_hitbox_zone(
	zone_name: StringName,
	shape: Shape2D,
	local_pos: Vector2,
	weak_points: Array[Vector2],
	armor_thickness: float,
	armor_hardness: float
) -> HitboxZone:
	var hz: HitboxZone = HitboxZone.new()
	hz.name = "Hitbox_%s" % String(zone_name)
	var parent_node: Node = hitbox_root if hitbox_root != null else self
	parent_node.add_child(hz)
	hz.add_to_group(&"hitbox_zones")
	var zone_local_wps: Array[Vector2] = []
	for wp: Vector2 in weak_points:
		zone_local_wps.append(wp - local_pos)
	hz.setup(
		self,
		anatomy,
		verticality,
		stat_sheet,
		zone_name,
		shape,
		local_pos,
		zone_local_wps,
		armor_thickness,
		armor_hardness,
		actor_size_mult,
		actor_base_anatomy_thickness
	)
	hitbox_zones.append(hz)
	return hz


# ---------------------------------------------------------------------------
# Equipment, Half-Swording, Aura & Aura Burst, State Queries
# ---------------------------------------------------------------------------

func get_active_weapon() -> WeaponData:
	if equipped_weapon != null:
		return equipped_weapon
	if unarmed_weapon == null:
		unarmed_weapon = WeaponData.create_unarmed_fist()
	return unarmed_weapon


func is_unarmed() -> bool:
	return equipped_weapon == null or equipped_weapon.is_unarmed


func get_usable_arm_count() -> int:
	if anatomy == null:
		return 2
	var count: int = 0
	for arm_zone: StringName in AnatomyComponent.ARM_ZONES:
		if not anatomy.is_limb_severed(arm_zone):
			count += 1
	return count


func has_both_arms_severed() -> bool:
	return get_usable_arm_count() == 0


func can_accept_weapon() -> bool:
	return not has_both_arms_severed() and (equipped_weapon == null or equipped_weapon.is_unarmed)


func save_initial_weapon_backup() -> void:
	if equipped_weapon != null and not equipped_weapon.is_unarmed:
		var copy: WeaponData = equipped_weapon.create_runtime_copy()
		copy.edge_sharpness = copy.max_edge_sharpness
		copy.durability = copy.max_durability
		_initial_weapon_backup = copy


func equip_weapon_template(template: WeaponData) -> WeaponData:
	if template == null:
		return null
	equipped_weapon = template.create_runtime_copy()
	if _initial_weapon_backup == null and not equipped_weapon.is_unarmed:
		save_initial_weapon_backup()
	if (not equipped_weapon.can_half_sword or get_usable_arm_count() < 2) and half_swording:
		half_swording = false
		half_sword_toggled.emit(false)
	refresh_weapon_visual()
	_apply_procedural_pose()
	weapon_changed.emit(get_active_weapon())
	return equipped_weapon


func equip_weapon_instance(weapon_instance: WeaponData) -> void:
	equipped_weapon = weapon_instance
	if _initial_weapon_backup == null and equipped_weapon != null and not equipped_weapon.is_unarmed:
		save_initial_weapon_backup()
	if (equipped_weapon == null or not equipped_weapon.can_half_sword or get_usable_arm_count() < 2) and half_swording:
		half_swording = false
		half_sword_toggled.emit(false)
	refresh_weapon_visual()
	_apply_procedural_pose()
	weapon_changed.emit(get_active_weapon())


## Disarms the active weapon (tendon tear / arm severing / manual drop), clearing the hand
## so the actor falls back to Unarmed (Fists) and spawning an interactive pickup on TestArena.
func disarm_active_weapon(spawn_on_floor: bool = true, reason: StringName = &"disarm") -> WeaponData:
	if equipped_weapon == null or equipped_weapon.is_unarmed:
		return null
	if _initial_weapon_backup == null:
		save_initial_weapon_backup()
	var dropped: WeaponData = equipped_weapon
	equipped_weapon = null
	if half_swording:
		half_swording = false
		half_sword_toggled.emit(false)
	if sweeper != null and sweeper.is_swing_active():
		sweeper.end_swing()
	refresh_weapon_visual()
	_apply_procedural_pose()
	weapon_changed.emit(get_active_weapon())
	weapon_disarmed.emit(dropped, reason)
	if spawn_on_floor:
		var arena: TestArena = _find_arena()
		if arena != null:
			arena.spawn_dropped_weapon(dropped, global_position, get_floor_level())
	return dropped


## Called when the actor's active blade lodges inside a target's tissue (LodgedWeapon):
## genuinely removes the weapon from the attacker's hand without deleting it.
func disarm_weapon_into_target(lodged_weapon: WeaponData) -> bool:
	if lodged_weapon == null or lodged_weapon.is_unarmed:
		return false
	if equipped_weapon != lodged_weapon:
		return false
	if _initial_weapon_backup == null:
		save_initial_weapon_backup()
	equipped_weapon = null
	if half_swording:
		half_swording = false
		half_sword_toggled.emit(false)
	refresh_weapon_visual()
	_apply_procedural_pose()
	weapon_changed.emit(get_active_weapon())
	weapon_disarmed.emit(lodged_weapon, &"lodged")
	return true


## Receives a recovered weapon (extracted LodgedWeapon or floor pickup).
## Never deletes a weapon into the void: if hands are full or severed, drops it onto TestArena.
func receive_recovered_weapon(weapon: WeaponData) -> bool:
	if weapon == null or weapon.is_unarmed:
		return false
	if has_both_arms_severed() or (equipped_weapon != null and not equipped_weapon.is_unarmed):
		var arena: TestArena = _find_arena()
		if arena != null:
			arena.spawn_dropped_weapon(weapon, global_position, get_floor_level())
		return false
	equip_weapon_instance(weapon)
	return true


func try_pickup_dropped_weapon(max_dist_px: float = 42.0) -> WeaponData:
	if not is_alive() or not can_accept_weapon():
		return null
	var arena: TestArena = _find_arena()
	if arena == null:
		return null
	var picked: WeaponData = arena.try_pickup_nearest_weapon(global_position, get_floor_level(), max_dist_px)
	if picked != null:
		receive_recovered_weapon(picked)
	return picked


func toggle_half_swording() -> bool:
	if equipped_weapon == null or not equipped_weapon.can_half_sword or get_usable_arm_count() < 2:
		if half_swording:
			half_swording = false
			half_sword_toggled.emit(false)
		refresh_weapon_visual()
		return false
	half_swording = not half_swording
	refresh_weapon_visual()
	_apply_procedural_pose()
	half_sword_toggled.emit(half_swording)
	return half_swording


func set_half_swording(enabled: bool) -> bool:
	if enabled and (equipped_weapon == null or not equipped_weapon.can_half_sword or get_usable_arm_count() < 2):
		if half_swording:
			half_swording = false
			half_sword_toggled.emit(false)
		refresh_weapon_visual()
		_apply_procedural_pose()
		return false
	if half_swording != enabled:
		half_swording = enabled
		refresh_weapon_visual()
		_apply_procedural_pose()
		half_sword_toggled.emit(half_swording)
	return half_swording


func toggle_aura() -> bool:
	return set_aura_active(not aura_active)


func set_aura_active(enabled: bool) -> bool:
	if enabled:
		if stat_sheet == null or not stat_sheet.mana_awakened:
			aura_active = false
			refresh_weapon_visual()
			return false
		if stat_sheet.get_stat(StatSheet.Stat.M_CTRL) < PenetrationResolver.AURA_MIN_M_CTRL:
			aura_active = false
			refresh_weapon_visual()
			return false
		if current_mp <= 0.0:
			aura_active = false
			refresh_weapon_visual()
			return false
	aura_active = enabled
	refresh_weapon_visual()
	if aura_active:
		var a_bus: Node = _get_event_bus()
		if a_bus != null and a_bus.has_method("request_sfx"):
			a_bus.call("request_sfx", ProceduralAudioManager.CUE_AURA_BURST, 0.72, 0.92)
	aura_toggled.emit(aura_active)
	return aura_active


## R key dual behavior (GDD 7.2, 12.2, 14.5):
## - During WINDUP or ACTIVE strike: triggers Aura Burst (extra MP, 1.8x impact/pierce, guard break).
## - Outside strike: toggles sustained Aura ON/OFF.
func handle_aura_or_burst_input() -> Dictionary:
	if combat_state == CombatState.WINDUP or combat_state == CombatState.ACTIVE:
		var ok: bool = try_trigger_aura_burst()
		return {"action": "aura_burst", "success": ok}
	var now_on: bool = toggle_aura()
	return {"action": "toggle_aura", "active": now_on}


func try_trigger_aura_burst() -> bool:
	if not is_alive() or stat_sheet == null or not stat_sheet.mana_awakened:
		return false
	if combat_state != CombatState.WINDUP and combat_state != CombatState.ACTIVE:
		return false
	if current_attack_aura_burst:
		return false
	if stat_sheet.get_stat(StatSheet.Stat.M_CTRL) < PenetrationResolver.AURA_MIN_M_CTRL:
		return false
	var mp_cost: float = PenetrationResolver.AURA_BURST_MP_COST * stat_sheet.get_mp_cost_mult()
	if current_mp < mp_cost:
		return false
	current_mp = maxf(0.0, current_mp - mp_cost)
	current_attack_aura_burst = true
	refresh_weapon_visual()
	var ab_bus: Node = _get_event_bus()
	if ab_bus != null and ab_bus.has_method("request_sfx"):
		ab_bus.call("request_sfx", ProceduralAudioManager.CUE_AURA_BURST, 1.25, 1.15)
	aura_burst_triggered.emit()
	return true


func is_alive() -> bool:
	return anatomy != null and not anatomy.is_dead


func is_prone() -> bool:
	# While airborne, severed/injured legs do NOT immobilize or knock the actor prone!
	if verticality != null and verticality.is_flying():
		return prone_timer > 0.0
	return prone_timer > 0.0 or (anatomy != null and anatomy.is_prone)


func is_flying() -> bool:
	return verticality != null and verticality.is_flying()


func get_flight_mode() -> VerticalityComponent.FlightMode:
	return verticality.flight_mode if verticality != null else VerticalityComponent.FlightMode.NONE


func get_preferred_flight_mode() -> VerticalityComponent.PreferredFlightMode:
	return verticality.preferred_flight_mode if verticality != null else VerticalityComponent.PreferredFlightMode.AUTO


func set_preferred_flight_mode(pref: VerticalityComponent.PreferredFlightMode) -> void:
	if verticality != null:
		verticality.preferred_flight_mode = pref


func can_use_mana_flight() -> bool:
	return (
		stat_sheet != null
		and stat_sheet.mana_awakened
		and stat_sheet.get_stat(StatSheet.Stat.M_CTRL) >= 1.0
		and current_mp > 0.0
	)


func can_use_wing_flight() -> bool:
	return (
		has_wings
		and anatomy != null
		and anatomy.has_zone(AnatomyComponent.ZONE_WINGS)
		and not anatomy.is_limb_severed(AnatomyComponent.ZONE_WINGS)
		and current_stamina > 0.0
	)


func is_wings_crippled() -> bool:
	return (
		has_wings
		and anatomy != null
		and anatomy.has_zone(AnatomyComponent.ZONE_WINGS)
		and anatomy.get_limb_status(AnatomyComponent.ZONE_WINGS) == AnatomyComponent.LimbStatus.CRIPPLED
	)


func get_flight_speed_mult() -> float:
	if is_flying() and get_flight_mode() == VerticalityComponent.FlightMode.WING_FLIGHT and is_wings_crippled():
		return WING_CRIPPLED_SPEED_MULT
	return 1.0


func resolve_available_flight_mode() -> VerticalityComponent.FlightMode:
	var pref: VerticalityComponent.PreferredFlightMode = get_preferred_flight_mode()
	match pref:
		VerticalityComponent.PreferredFlightMode.MANA:
			return VerticalityComponent.FlightMode.MANA_FLIGHT if can_use_mana_flight() else VerticalityComponent.FlightMode.NONE
		VerticalityComponent.PreferredFlightMode.WINGS:
			return VerticalityComponent.FlightMode.WING_FLIGHT if can_use_wing_flight() else VerticalityComponent.FlightMode.NONE
		_:
			if can_use_wing_flight():
				return VerticalityComponent.FlightMode.WING_FLIGHT
			if can_use_mana_flight():
				return VerticalityComponent.FlightMode.MANA_FLIGHT
			return VerticalityComponent.FlightMode.NONE


## Activates MANA_FLIGHT or WING_FLIGHT (or lands on NONE).
## Intentionally permits takeoff even while grounded with a severed leg (`anatomy.is_prone == true`).
func set_flight_mode(
	mode: VerticalityComponent.FlightMode,
	target_altitude: float = VerticalityComponent.HEIGHT_HIGH_FLIGHT
) -> bool:
	if verticality == null:
		return false
	if mode == VerticalityComponent.FlightMode.NONE:
		land_from_flight(false, "manual_land")
		return true
	if not is_alive() or (anatomy != null and anatomy.is_unconscious) or combat_state == CombatState.STAGGERED or prone_timer > 0.0:
		return false
	if mode == VerticalityComponent.FlightMode.MANA_FLIGHT and not can_use_mana_flight():
		return false
	if mode == VerticalityComponent.FlightMode.WING_FLIGHT and not can_use_wing_flight():
		return false

	var eff_alt: float = maxf(VerticalityComponent.LOW_OBSTACLE_CLEARANCE_Z, target_altitude)
	if mode == VerticalityComponent.FlightMode.WING_FLIGHT and is_wings_crippled():
		eff_alt = minf(eff_alt, WING_CRIPPLED_MAX_ALTITUDE)
	if is_crouching:
		set_crouch(false)
	verticality.set_flight_mode(mode)
	verticality.set_height_z(eff_alt)
	_sync_flight_stat_tags_and_visuals()
	return true


func try_toggle_flight(flight_altitude: float = VerticalityComponent.HEIGHT_HIGH_FLIGHT) -> Dictionary:
	if verticality == null or not is_alive():
		return {"success": false, "flying": false, "mode": VerticalityComponent.FlightMode.NONE, "message": ""}
	if verticality.is_flying():
		land_from_flight(false, "manual_land")
		return {
			"success": true,
			"flying": false,
			"mode": VerticalityComponent.FlightMode.NONE,
			"message": "Посадка",
		}
	if (anatomy != null and anatomy.is_unconscious) or combat_state == CombatState.STAGGERED or prone_timer > 0.0:
		return {
			"success": false,
			"flying": false,
			"mode": VerticalityComponent.FlightMode.NONE,
			"message": "Нельзя взлететь в этом состоянии",
		}
	var chosen: VerticalityComponent.FlightMode = resolve_available_flight_mode()
	if chosen == VerticalityComponent.FlightMode.NONE:
		var pref: VerticalityComponent.PreferredFlightMode = get_preferred_flight_mode()
		var msg: String = "Нужна пробуждённая мана или крылья [F1]"
		if pref == VerticalityComponent.PreferredFlightMode.MANA:
			msg = "Полёт на мане недоступен: нужна пробуждённая мана и MP [F1]"
		elif pref == VerticalityComponent.PreferredFlightMode.WINGS:
			msg = "Полёт на крыльях недоступен: нужны целые крылья и STA [F1]"
		last_flight_feedback = msg
		flight_status_message.emit(msg)
		return {
			"success": false,
			"flying": false,
			"mode": VerticalityComponent.FlightMode.NONE,
			"message": msg,
		}
	var ok: bool = set_flight_mode(chosen, flight_altitude)
	var mode_label: String = "Полёт на крыльях" if chosen == VerticalityComponent.FlightMode.WING_FLIGHT else "Полёт на мане"
	last_flight_feedback = mode_label if ok else ""
	return {
		"success": ok,
		"flying": ok,
		"mode": chosen if ok else VerticalityComponent.FlightMode.NONE,
		"message": mode_label if ok else "",
	}


func land_from_flight(apply_fall: bool = false, reason: String = "") -> Dictionary:
	var prev_z: float = get_height_z()
	var prev_mode: VerticalityComponent.FlightMode = get_flight_mode()
	if verticality != null:
		verticality.set_flight_mode(VerticalityComponent.FlightMode.NONE)
		verticality.set_height_z(VerticalityComponent.HEIGHT_GROUND)
	_sync_flight_stat_tags_and_visuals()
	var fall_report: Dictionary = {}
	if apply_fall and anatomy != null and is_alive():
		fall_report = anatomy.apply_fall_damage(1)
	if not reason.is_empty() and apply_fall:
		last_flight_feedback = "Падение (%s)!" % reason
		flight_status_message.emit(last_flight_feedback)
	return {
		"fell": apply_fall,
		"prev_z": prev_z,
		"prev_mode": prev_mode,
		"reason": reason,
		"fall_report": fall_report,
	}


func _on_verticality_height_z_changed(_old_z: float, _new_z: float) -> void:
	_sync_flight_stat_tags_and_visuals()


func _on_verticality_flight_mode_changed(_old_mode: int, _new_mode: int) -> void:
	_sync_flight_stat_tags_and_visuals()


func _sync_flight_stat_tags_and_visuals() -> void:
	var airborne: bool = verticality != null and verticality.is_flying()
	if stat_sheet != null:
		if airborne:
			stat_sheet.add_ignored_tag(StatSheet.TAG_LEG_LOCOMOTION)
		else:
			stat_sheet.remove_ignored_tag(StatSheet.TAG_LEG_LOCOMOTION)
	if not airborne and anatomy != null and anatomy.has_severed_leg():
		anatomy._recompute_limb_flags()
	_update_flight_visuals()
	_refresh_status_tint()


func _update_flight_visuals() -> void:
	var alive_now: bool = is_alive()
	var airborne: bool = verticality != null and verticality.is_flying()
	var fmode: VerticalityComponent.FlightMode = get_flight_mode()
	var s: float = actor_size_mult

	if mana_flight_ring != null:
		mana_flight_ring.visible = alive_now and airborne and fmode == VerticalityComponent.FlightMode.MANA_FLIGHT
		if mana_flight_ring.visible:
			var pulse: float = 1.0 + sin(anim_time * 5.2) * 0.06
			mana_flight_ring.scale = Vector2(pulse, pulse)
			if mana_flight_inner_ring != null:
				mana_flight_inner_ring.rotation = anim_time * 1.4

	if wing_visual_root != null:
		var wings_intact_or_crippled: bool = has_wings and (anatomy == null or not anatomy.is_limb_severed(AnatomyComponent.ZONE_WINGS))
		wing_visual_root.visible = alive_now and wings_intact_or_crippled
		wing_visual_root.z_index = 4 if is_facing_back else -2
		var rig_off: Vector2 = visual_rig.position if visual_rig != null else Vector2.ZERO
		wing_visual_root.position = Vector2(rig_off.x, -3.5 * s + rig_off.y)
		if wing_visual_root.visible and wing_left_poly != null and wing_right_poly != null:
			var crippled: bool = is_wings_crippled()
			var wcol: Color = Color("#B59E9E") if crippled else Color("#D8E6F2")
			wing_left_poly.color = wcol
			wing_right_poly.color = wcol
			if airborne and fmode == VerticalityComponent.FlightMode.WING_FLIGHT:
				if crippled:
					var shiver: float = sin(wing_flap_phase * 2.4) * deg_to_rad(8.0)
					wing_left_poly.scale = Vector2(1.12, 0.94)
					wing_right_poly.scale = Vector2(1.06, 0.88)
					wing_left_poly.rotation = deg_to_rad(-8.0) + shiver
					wing_right_poly.rotation = deg_to_rad(28.0) - shiver * 0.6
				else:
					# Keep scale.x strictly > 1.2 (1.28..1.48) during healthy WING_FLIGHT
					var flap_sx: float = 1.38 + cos(wing_flap_phase) * 0.10
					var flap_sy: float = 1.14 + sin(wing_flap_phase) * 0.08
					var flap_rot: float = sin(wing_flap_phase) * deg_to_rad(22.0)
					wing_left_poly.scale = Vector2(flap_sx, flap_sy)
					wing_right_poly.scale = Vector2(flap_sx, flap_sy)
					wing_left_poly.rotation = deg_to_rad(-16.0) + flap_rot
					wing_right_poly.rotation = deg_to_rad(16.0) - flap_rot
			else:
				var breath: float = sin(anim_time * 2.4) * deg_to_rad(2.5)
				wing_left_poly.scale = Vector2(0.72, 0.84)
				wing_right_poly.scale = Vector2(0.72, 0.84)
				wing_left_poly.rotation = deg_to_rad(24.0) + breath
				wing_right_poly.rotation = deg_to_rad(-24.0) - breath


func is_hardening_active() -> bool:
	return hardening_timer > 0.0 and is_alive() and not anatomy.is_unconscious


func can_act() -> bool:
	return is_alive() and not anatomy.is_unconscious and not is_prone() and combat_state != CombatState.STAGGERED


func get_floor_level() -> int:
	return verticality.floor_level if verticality != null else 0


func get_height_z() -> float:
	return verticality.height_z if verticality != null else 0.0


func get_combat_origin() -> Vector2:
	if body_visual != null:
		return body_visual.global_position
	return global_position + Vector2(0.0, -get_height_z() * VerticalityComponent.VISUAL_Y_OFFSET_PER_Z)


func get_body_collision_radius() -> float:
	if body_collision_shape != null and body_collision_shape.shape is CircleShape2D:
		return (body_collision_shape.shape as CircleShape2D).radius
	return 8.0 * actor_size_mult


## Overridden by EnemyDummy to report PATROL (1.0x) state cleanly.
func is_patrolling() -> bool:
	return false


## Effective real-world SPD rating accounting for TempoMode, speed_regulator, tp_penalty_mult & PATROL.
func get_effective_world_spd() -> float:
	if stat_sheet == null:
		return StatSheet.HUMAN_REFERENCE
	var raw_spd: float = stat_sheet.get_stat(StatSheet.Stat.SPD)
	if is_patrolling():
		return minf(raw_spd, StatSheet.HUMAN_REFERENCE)
	if SimulationClock == null:
		return raw_spd
	if SimulationClock.is_peaceful():
		return minf(raw_spd, StatSheet.HUMAN_REFERENCE)
	if is_in_group(&"player"):
		return maxf(0.2, raw_spd * SimulationClock.speed_regulator * SimulationClock.get_tp_penalty_mult())
	return raw_spd


func is_in_parry_window() -> bool:
	return parry_window_timer > 0.0 and is_alive() and not anatomy.is_unconscious and not is_prone()


## Computes current active weapon segment in combat-space for geometric Blade Clash detection.
func get_current_blade_segment() -> PackedVector2Array:
	if is_unarmed():
		return PackedVector2Array()
	if sweeper != null:
		var seg: PackedVector2Array = sweeper.get_active_blade_segment()
		if seg.size() == 2:
			return seg
	if equipped_weapon == null or combat_state != CombatState.ACTIVE:
		return PackedVector2Array()
	var origin: Vector2 = get_combat_origin()
	var angle: float = weapon_pivot.rotation if weapon_pivot != null else swing_center_angle
	var m_ctrl: float = stat_sheet.get_stat(StatSheet.Stat.M_CTRL) if (stat_sheet != null and stat_sheet.mana_awakened) else 0.0
	var aura: PenetrationResolver.AuraBonuses = PenetrationResolver.calculate_aura_bonuses(aura_active, m_ctrl, current_attack_aura_burst)
	var eff_len: float = equipped_weapon.get_effective_blade_length(half_swording) + aura.blade_extension
	var dir: Vector2 = Vector2.from_angle(angle)
	var seg_start: Vector2 = origin + dir * (equipped_weapon.hilt_offset_px * 0.25)
	var seg_end: Vector2 = origin + dir * (equipped_weapon.hilt_offset_px + eff_len)
	return PackedVector2Array([seg_start, seg_end])


# ---------------------------------------------------------------------------
# Subjective / Action Combat Status Timers (Never Frozen 50x at TP=500!)
# ---------------------------------------------------------------------------

func tick_combat_status_timers(action_delta: float, raw_delta: float = -1.0) -> void:
	if not is_alive():
		return
	var status_dt: float = action_delta
	if raw_delta > 0.0:
		# Anchor active defense windows, cooldowns & Prone recovery near subjective action pace
		# so TP=500 (world_time_scale=0.02) never stretches 2s Prone to 100 real seconds!
		status_dt = clampf(action_delta, raw_delta * 0.5, raw_delta * 2.5)
	if status_dt <= 0.0:
		return

	if hardening_timer > 0.0:
		hardening_timer = maxf(0.0, hardening_timer - status_dt)
		if hardening_timer <= 0.0:
			hardening_bonus_value = 0.0
			_refresh_status_tint()
	if hardening_cooldown_timer > 0.0:
		hardening_cooldown_timer = maxf(0.0, hardening_cooldown_timer - status_dt)
	if counter_window_timer > 0.0:
		counter_window_timer = maxf(0.0, counter_window_timer - status_dt)
	if prone_timer > 0.0:
		prone_timer = maxf(0.0, prone_timer - status_dt)
		if prone_timer <= 0.0 and anatomy != null:
			var leg_missing: bool = anatomy.is_limb_severed(AnatomyComponent.ZONE_LEFT_LEG) or anatomy.is_limb_severed(AnatomyComponent.ZONE_RIGHT_LEG)
			if not leg_missing:
				anatomy.is_prone = false
				_refresh_status_tint()
	if _recent_move_timer > 0.0:
		_recent_move_timer = maxf(0.0, _recent_move_timer - status_dt)
		if _recent_move_timer <= 0.0:
			_recent_move_velocity = Vector2.ZERO
			_recent_move_was_dash = false


# ---------------------------------------------------------------------------
# Physiology & Resource Tick (Strictly SimulationClock.world_delta!)
# ---------------------------------------------------------------------------

func tick_physiology(world_delta: float, is_moving: bool = false) -> void:
	if world_delta <= 0.0 or not is_alive():
		return

	if anatomy != null:
		var regen_pool: Dictionary = {
			"stamina": current_stamina,
			"mp": current_mp,
		}
		anatomy.tick(world_delta, regen_pool)
		current_stamina = float(regen_pool.get("stamina", current_stamina))
		current_mp = float(regen_pool.get("mp", current_mp))
		if anatomy.is_dead:
			return
		# Periodic blood trail drops for wounded bleeding actors (tracked by SEARCH AI, GDD 7.4, 14.3)
		if anatomy.get_total_bleed_rate() > 0.5:
			_blood_trail_timer += world_delta
			if _blood_trail_timer >= 0.90 or (is_moving and global_position.distance_to(_last_blood_trail_pos) >= 18.0):
				_blood_trail_timer = 0.0
				_last_blood_trail_pos = global_position
				var bus: Node = _get_event_bus()
				if bus != null and bus.has_method("request_blood"):
					bus.call("request_blood", global_position, get_floor_level(), Vector2.ZERO, 0.85, true)

	if stat_sheet == null:
		return

	# Active FlightMode upkeep (runs strictly on SimulationClock.world_delta!)
	var active_fmode: VerticalityComponent.FlightMode = get_flight_mode() if is_flying() else VerticalityComponent.FlightMode.NONE
	var suppress_sta_regen: bool = false
	var suppress_mp_regen: bool = false

	if active_fmode == VerticalityComponent.FlightMode.WING_FLIGHT:
		suppress_sta_regen = true
		if not has_wings or anatomy == null or anatomy.is_limb_severed(AnatomyComponent.ZONE_WINGS):
			land_from_flight(true, "wings_severed")
			active_fmode = VerticalityComponent.FlightMode.NONE
		else:
			if is_wings_crippled() and get_height_z() > WING_CRIPPLED_MAX_ALTITUDE:
				verticality.set_height_z(WING_CRIPPLED_MAX_ALTITUDE)
			var wing_sta_rate: float = WING_FLIGHT_STA_PER_SEC * (1.25 if is_moving else 1.0)
			var wing_sta_drain: float = stat_sheet.get_effective_stamina_cost(wing_sta_rate, true) * world_delta
			current_stamina = maxf(0.0, current_stamina - wing_sta_drain)
			if current_stamina <= 0.0:
				var fall_dmg_on_sta: bool = get_height_z() >= VerticalityComponent.LOW_OBSTACLE_CLEARANCE_Z
				land_from_flight(fall_dmg_on_sta, "stamina_depleted")
				active_fmode = VerticalityComponent.FlightMode.NONE
	elif active_fmode == VerticalityComponent.FlightMode.MANA_FLIGHT:
		suppress_mp_regen = true
		if not stat_sheet.mana_awakened or stat_sheet.get_stat(StatSheet.Stat.M_CTRL) < 1.0:
			land_from_flight(anatomy != null and anatomy.is_unconscious and get_height_z() >= VerticalityComponent.LOW_OBSTACLE_CLEARANCE_Z, "mana_unavailable")
			active_fmode = VerticalityComponent.FlightMode.NONE
		else:
			var mana_flight_drain: float = MANA_FLIGHT_MP_PER_SEC * stat_sheet.get_mp_cost_mult() * world_delta
			current_mp = maxf(0.0, current_mp - mana_flight_drain)
			if current_mp <= 0.0:
				var fall_dmg_on_mp: bool = anatomy != null and anatomy.is_unconscious and get_height_z() >= VerticalityComponent.LOW_OBSTACLE_CLEARANCE_Z
				land_from_flight(fall_dmg_on_mp, "mp_depleted")
				active_fmode = VerticalityComponent.FlightMode.NONE

	# Stamina regeneration (GDD 3.2 #6; suppressed while actively flapping wings in WING_FLIGHT)
	var max_sta: float = stat_sheet.get_max_stamina()
	if not suppress_sta_regen and not is_blocking and combat_state == CombatState.IDLE and dash_timer <= 0.0 and sidestep_timer <= 0.0:
		current_stamina = minf(max_sta, current_stamina + stat_sheet.get_stamina_regen_per_sec(is_moving) * world_delta)
	else:
		current_stamina = minf(max_sta, current_stamina)

	# MP regeneration & Aura upkeep (GDD 3.2 #9, 12.2: 2.0 MP/sec by world_delta)
	var max_mp: float = stat_sheet.get_max_mp()
	if stat_sheet.mana_awakened and max_mp > 0.0:
		if not suppress_mp_regen:
			current_mp = minf(max_mp, current_mp + stat_sheet.get_mp_regen_per_sec(false) * world_delta)
		else:
			current_mp = minf(max_mp, current_mp)
		if aura_active:
			var drain: float = PenetrationResolver.AURA_MP_PER_SEC * stat_sheet.get_mp_cost_mult() * world_delta
			current_mp = maxf(0.0, current_mp - drain)
			if current_mp <= 0.0:
				set_aura_active(false)
				if active_fmode == VerticalityComponent.FlightMode.MANA_FLIGHT:
					land_from_flight(anatomy != null and anatomy.is_unconscious and get_height_z() >= VerticalityComponent.LOW_OBSTACLE_CLEARANCE_Z, "mp_depleted")
	else:
		current_mp = 0.0
		if aura_active:
			set_aura_active(false)

	# Poise recovery
	max_poise = 50.0 + stat_sheet.get_stat(StatSheet.Stat.CON) * 2.0
	if combat_state != CombatState.STAGGERED:
		current_poise = minf(max_poise, current_poise + 20.0 * world_delta)


# ---------------------------------------------------------------------------
# 3 Attack Types (SLASH / THRUST / BLUNT), Feint (C), 3 Defenses & Clinch
# ---------------------------------------------------------------------------

func start_primary_attack(target_aim_world: Vector2) -> bool:
	return start_attack(target_aim_world, PenetrationResolver.AttackType.SLASH)


func start_attack(
	target_aim_world: Vector2,
	attack_type: PenetrationResolver.AttackType = PenetrationResolver.AttackType.SLASH
) -> bool:
	if not can_act() or combat_state != CombatState.IDLE or has_both_arms_severed():
		return false

	var active_wpn: WeaponData = get_active_weapon()
	if active_wpn == null:
		return false

	var resolved_type: PenetrationResolver.AttackType = (
		PenetrationResolver.AttackType.BLUNT if active_wpn.is_unarmed else attack_type
	)

	var sta_cost: float = stat_sheet.get_effective_stamina_cost(active_wpn.stamina_cost, true)
	if current_stamina < sta_cost:
		return false

	current_stamina = maxf(0.0, current_stamina - sta_cost)
	if is_in_group(&"player") and SimulationClock != null:
		SimulationClock.notify_player_attack()

	# Active Aura spends MP per swing as well as passive upkeep so M_CTRL=10 Aura is never free
	if aura_active and stat_sheet != null and stat_sheet.mana_awakened:
		var swing_mp: float = PenetrationResolver.AURA_MP_PER_SWING * stat_sheet.get_mp_cost_mult()
		if current_mp >= swing_mp:
			current_mp = maxf(0.0, current_mp - swing_mp)
		else:
			current_mp = 0.0
			set_aura_active(false)

	# Preserve approach / lunge inertia for both Player and charging AI enemies into blade contact
	if current_move_velocity.length_squared() >= _recent_move_velocity.length_squared():
		_attack_launch_velocity = current_move_velocity
		_attack_launch_was_dash = dash_timer > 0.0
	elif _recent_move_timer > 0.0:
		_attack_launch_velocity = _recent_move_velocity
		_attack_launch_was_dash = _recent_move_was_dash
	else:
		_attack_launch_velocity = Vector2.ZERO
		_attack_launch_was_dash = false

	# Consume Blade Clash CTRL counter-window for 2x faster Windup + guard-bypassing precise counterattack!
	current_attack_is_counter = counter_window_timer > 0.0
	if current_attack_is_counter:
		counter_window_timer = 0.0

	is_blocking = false
	parry_window_timer = 0.0
	current_attack_type = resolved_type
	current_attack_aura_burst = false

	aim_world_pos = target_aim_world
	aim_angle = (target_aim_world - get_combat_origin()).angle()
	swing_center_angle = aim_angle

	var base_windup: float = attack_windup_override if (attack_windup_override > 0.0 and not active_wpn.is_unarmed) else active_wpn.windup_sec
	match resolved_type:
		PenetrationResolver.AttackType.THRUST:
			swing_start_angle = aim_angle
			swing_end_angle = aim_angle
			state_timer = base_windup * 0.85
		PenetrationResolver.AttackType.BLUNT:
			var half_blunt: float = deg_to_rad(active_wpn.swing_arc_deg * 0.65) * 0.5
			swing_start_angle = swing_center_angle - half_blunt
			swing_end_angle = swing_center_angle + half_blunt
			state_timer = base_windup * 1.05
		_:
			var half_arc: float = deg_to_rad(active_wpn.swing_arc_deg) * 0.5
			swing_start_angle = swing_center_angle - half_arc
			swing_end_angle = swing_center_angle + half_arc
			state_timer = base_windup

	if current_attack_is_counter:
		state_timer *= COUNTER_WINDUP_MULT

	combat_state = CombatState.WINDUP
	_windup_total_visual_sec = maxf(0.05, state_timer)
	swing_elapsed = 0.0
	trigger_squash(Vector2(1.06, 0.94))
	_update_visual_facing(swing_start_angle)
	var sw_bus: Node = _get_event_bus()
	if sw_bus != null and sw_bus.has_method("request_sfx"):
		var pitch_by_mass: float = clampf(1.25 - active_wpn.mass_factor * 0.014, 0.72, 1.28)
		sw_bus.call("request_sfx", ProceduralAudioManager.CUE_SWING_WHOOSH, 0.85, pitch_by_mass)
	attack_started.emit(active_wpn)
	return true


## Feint (C, GDD 7.4, 14.5): immediately cancels WINDUP for a small STA cost; speed depends on CTRL.
func try_feint_cancel() -> bool:
	if not is_alive() or combat_state != CombatState.WINDUP:
		return false
	var sta_cost: float = stat_sheet.get_effective_stamina_cost(FEINT_STA_COST, true)
	if current_stamina < sta_cost:
		return false
	current_stamina = maxf(0.0, current_stamina - sta_cost)
	current_attack_aura_burst = false
	current_attack_is_counter = false
	var ctrl_val: float = stat_sheet.get_stat(StatSheet.Stat.CTRL)
	var cancel_recovery: float = clampf(0.16 - maxf(0.0, ctrl_val - 10.0) * 0.003, 0.02, 0.16)
	combat_state = CombatState.RECOVERY
	state_timer = cancel_recovery
	refresh_weapon_visual()
	feint_executed.emit()
	return true


## Defense Style 2 (Space, GDD 7.4, 14.5):
## - During WINDUP: Micro-Sidestep without cancelling own attack!
## - Outside WINDUP: Full Dash / Roll.
func start_sidestep_or_dash(direction: Vector2) -> StringName:
	if combat_state == CombatState.WINDUP:
		if start_sidestep(direction):
			return &"sidestep"
		return &""
	if start_dash(direction):
		return &"dash"
	return &""


func start_sidestep(direction: Vector2) -> bool:
	if not can_act() or combat_state != CombatState.WINDUP:
		return false
	if sidestep_cooldown_timer > 0.0 or sidestep_timer > 0.0:
		return false
	var agi_val: float = stat_sheet.get_stat(StatSheet.Stat.AGI)
	if agi_val <= 0.0:
		return false
	var sta_cost: float = stat_sheet.get_effective_stamina_cost(BASE_SIDESTEP_STAMINA_COST, false)
	if current_stamina < sta_cost:
		return false
	current_stamina = maxf(0.0, current_stamina - sta_cost)
	sidestep_direction = direction.normalized() if direction.length_squared() > 0.001 else Vector2.from_angle(aim_angle + PI * 0.5)
	sidestep_timer = BASE_SIDESTEP_DURATION_SEC
	sidestep_cooldown_timer = BASE_SIDESTEP_COOLDOWN_SEC * stat_sheet.get_dash_cooldown_mult()
	trigger_squash(Vector2(1.15, 0.87))
	# Critically: combat_state stays WINDUP and state_timer is NOT interrupted!
	sidestep_started.emit(sidestep_direction)
	return true


func start_dash(direction: Vector2) -> bool:
	if not can_act() or dash_cooldown_timer > 0.0 or dash_timer > 0.0:
		return false
	var agi_val: float = stat_sheet.get_stat(StatSheet.Stat.AGI)
	if agi_val <= 0.0:
		return false

	var base_dash_sta: float = BASE_DASH_STAMINA_COST
	var flying_now: bool = is_flying()
	var fmode: VerticalityComponent.FlightMode = get_flight_mode()
	if flying_now and fmode == VerticalityComponent.FlightMode.WING_FLIGHT:
		base_dash_sta += WING_FLIGHT_DASH_STA_EXTRA
	var sta_cost: float = stat_sheet.get_effective_stamina_cost(base_dash_sta, false)
	if current_stamina < sta_cost:
		return false
	current_stamina = maxf(0.0, current_stamina - sta_cost)
	if flying_now and fmode == VerticalityComponent.FlightMode.MANA_FLIGHT and stat_sheet.mana_awakened:
		var mp_dash_cost: float = MANA_FLIGHT_DASH_MP_COST * stat_sheet.get_mp_cost_mult()
		current_mp = maxf(0.0, current_mp - mp_dash_cost)

	dash_direction = direction.normalized() if direction.length_squared() > 0.001 else Vector2.from_angle(aim_angle)
	dash_timer = BASE_DASH_DURATION_SEC
	dash_cooldown_timer = BASE_DASH_COOLDOWN_SEC * stat_sheet.get_dash_cooldown_mult()
	trigger_squash(Vector2(1.18, 0.84))
	return true


## Defense Style 3 (H, GDD 7.4, 14.5): brief muscle/mana-skin hardening to bounce or lodge enemy blades!
func activate_hardening() -> bool:
	if not can_act() or hardening_cooldown_timer > 0.0 or hardening_timer > 0.0:
		return false
	var sta_cost: float = stat_sheet.get_effective_stamina_cost(HARDENING_STA_COST, false)
	if current_stamina < sta_cost:
		return false
	current_stamina = maxf(0.0, current_stamina - sta_cost)

	var bonus: float = 25.0 + stat_sheet.get_stat(StatSheet.Stat.CON) * 1.5 + stat_sheet.get_stat(StatSheet.Stat.STR) * 0.5
	if stat_sheet.mana_awakened:
		var mp_cost: float = HARDENING_MP_COST * stat_sheet.get_mp_cost_mult()
		if current_mp >= mp_cost:
			current_mp = maxf(0.0, current_mp - mp_cost)
			bonus += stat_sheet.get_mana_skin_density() * 0.75 + stat_sheet.get_stat(StatSheet.Stat.M_CTRL) * 2.0

	hardening_bonus_value = bonus
	hardening_timer = HARDENING_DURATION_SEC
	hardening_cooldown_timer = HARDENING_COOLDOWN_SEC
	_refresh_status_tint()
	hardening_activated.emit(bonus)
	return true


func trigger_block_pressed() -> void:
	if not can_act() or combat_state != CombatState.IDLE or has_both_arms_severed():
		return
	is_blocking = true
	parry_window_timer = PARRY_WINDOW_SEC
	_update_visual_facing(aim_angle)


func set_block_held(held: bool) -> void:
	if not can_act() or combat_state != CombatState.IDLE or has_both_arms_severed():
		is_blocking = false
		_update_block_arc_visual()
		_apply_procedural_pose()
		return
	var changed: bool = is_blocking != held
	is_blocking = held
	if changed:
		_update_visual_facing(aim_angle)
	else:
		_update_block_arc_visual()


func tick_parry_window_subjective(raw_delta: float) -> void:
	if parry_window_timer > 0.0:
		parry_window_timer = maxf(0.0, parry_window_timer - raw_delta)
	_update_block_arc_visual()


## Returns true if `attacker` stands within +/- half_angle_deg in front of this actor's `aim_angle`.
func is_attack_within_front_arc(attacker: CombatActor, half_angle_deg: float = BLOCK_FRONT_HALF_ANGLE_DEG) -> bool:
	if attacker == null:
		return true
	var to_atk: Vector2 = attacker.global_position - global_position
	if to_atk.length_squared() <= 1e-4:
		return true
	var ang_diff: float = absf(angle_difference(aim_angle, to_atk.angle()))
	return ang_diff <= deg_to_rad(half_angle_deg)


## Stealth crouch stance (Ctrl): lowers movement speed, suppresses footsteps, hides behind LOW_OBSTACLE,
## and unlocks stealth takedown (Q) & 1.60x backstab precision. Refused while flying/KO/prone/dead.
func toggle_crouch() -> bool:
	return set_crouch(not is_crouching)


func set_crouch(enabled: bool) -> bool:
	if enabled:
		if (
			not is_alive()
			or (anatomy != null and anatomy.is_unconscious)
			or is_prone()
			or is_flying()
			or get_height_z() >= VerticalityComponent.LOW_OBSTACLE_CLEARANCE_Z
		):
			if is_crouching:
				is_crouching = false
				_apply_crouch_visual_immediate()
				_refresh_status_tint()
				crouch_toggled.emit(false)
			return false
	if is_crouching != enabled:
		is_crouching = enabled
		if is_crouching:
			_bush_rustle_timer = 0.0
		if DisplayServer.get_name() == "headless":
			_apply_crouch_visual_immediate()
		_refresh_status_tint()
		crouch_toggled.emit(is_crouching)
	return is_crouching


func _apply_crouch_visual_immediate() -> void:
	_crouch_visual_scale = CROUCH_VISUAL_SCALE if is_crouching else 1.0
	if verticality != null:
		verticality.visual_stance_scale = _crouch_visual_scale
		verticality.sync_visuals()


func tick_crouch_visual(raw_delta: float) -> void:
	var target_scale: float = CROUCH_VISUAL_SCALE if is_crouching else 1.0
	if not is_equal_approx(_crouch_visual_scale, target_scale):
		var alpha: float = clampf(maxf(0.0, raw_delta) * 14.0, 0.0, 1.0)
		_crouch_visual_scale = lerpf(_crouch_visual_scale, target_scale, alpha)
		if absf(_crouch_visual_scale - target_scale) < 0.005:
			_crouch_visual_scale = target_scale
		if verticality != null:
			verticality.visual_stance_scale = _crouch_visual_scale
			verticality.sync_visuals()


func get_crouch_speed_mult() -> float:
	if not is_crouching:
		return 1.0
	var agi: float = stat_sheet.get_stat(StatSheet.Stat.AGI) if stat_sheet != null else 10.0
	return clampf(CROUCH_BASE_SPEED_MULT + maxf(0.0, agi - 10.0) * 0.002, CROUCH_BASE_SPEED_MULT, CROUCH_MAX_SPEED_MULT)


func get_movement_noise_radius(is_dashing: bool, speed_px: float) -> float:
	if is_crouching:
		if is_dashing:
			return CROUCH_ROLL_NOISE_PX
		if speed_px > 25.0:
			var agi: float = stat_sheet.get_stat(StatSheet.Stat.AGI) if stat_sheet != null else 10.0
			if agi >= CROUCH_SILENT_AGI_THRESHOLD:
				return 0.0
			return CROUCH_STEP_NOISE_PX
		return 0.0
	if is_dashing:
		return 145.0
	if speed_px > 150.0:
		return 90.0
	return 0.0


func is_in_stealth_stance(arena: TestArena = null) -> bool:
	if is_crouching:
		return true
	var resolved: TestArena = arena if arena != null else _find_arena()
	return resolved != null and resolved.is_entity_in_stealth_cover(self)


func get_stealth_backstab_aim_mult(arena: TestArena = null) -> float:
	return STEALTH_CROUCH_BACKSTAB_AIM_BONUS_MULT if is_in_stealth_stance(arena) else STEALTH_BACKSTAB_AIM_BONUS_MULT


func can_instinct_dodge_stealth_ambush(attacker: CombatActor) -> bool:
	if stat_sheet == null or attacker == null or attacker.stat_sheet == null:
		return false
	var my_tp: float = stat_sheet.get_stat(StatSheet.Stat.TP)
	var atk_spd: float = maxf(1.0, attacker.stat_sheet.get_stat(StatSheet.Stat.SPD))
	return (my_tp / atk_spd) >= 2.0


## GDD 7.4 Stealth / Backstab bonus check: attacker is behind the target's vision cone
## while the target is unaware (PATROL) or distracted (SEARCH / not targeting attacker / not blocking).
func is_vulnerable_to_stealth_backstab(attacker: Node) -> bool:
	if attacker == null or not (attacker is Node2D) or not is_alive():
		return false
	var to_atk: Vector2 = (attacker as Node2D).global_position - global_position
	if to_atk.length_squared() <= 1e-4:
		return false
	var vision_half_deg: float = 75.0
	var unaware_or_distracted: bool = true
	if has_method("get_effective_vision_half_angle_deg"):
		vision_half_deg = float(call("get_effective_vision_half_angle_deg"))
	if has_method("is_patrolling"):
		var patrolling: bool = bool(call("is_patrolling"))
		var cur_tgt: Variant = get("current_target")
		var ai_state_val: Variant = get("ai_state")
		var searching: bool = ai_state_val != null and int(ai_state_val) == 2
		unaware_or_distracted = patrolling or searching or (cur_tgt != attacker)
	else:
		unaware_or_distracted = not is_blocking and combat_state == CombatState.IDLE
	if not unaware_or_distracted:
		return false
	var ang_diff: float = absf(angle_difference(aim_angle, to_atk.angle()))
	return ang_diff > deg_to_rad(vision_half_deg)


func set_prone(duration_sec: float = PRONE_RECOVERY_DURATION_SEC) -> void:
	if not is_alive():
		return
	if is_crouching:
		set_crouch(false)
	if sweeper != null and sweeper.is_swing_active():
		sweeper.end_swing()
	combat_state = CombatState.IDLE
	state_timer = 0.0
	is_blocking = false
	parry_window_timer = 0.0
	current_attack_aura_burst = false
	current_attack_is_counter = false
	prone_timer = maxf(prone_timer, duration_sec)
	if anatomy != null:
		anatomy.is_prone = true
	if weapon_pivot != null:
		weapon_pivot.position = Vector2.ZERO
	_update_block_arc_visual()
	_refresh_status_tint()


func apply_stagger(duration_sec: float = DEFAULT_STAGGER_SEC) -> void:
	if not is_alive():
		return
	if is_crouching:
		set_crouch(false)
	if sweeper != null and sweeper.is_swing_active():
		sweeper.end_swing()
	combat_state = CombatState.STAGGERED
	state_timer = maxf(state_timer, duration_sec)
	is_blocking = false
	parry_window_timer = 0.0
	current_attack_aura_burst = false
	current_attack_is_counter = false
	if weapon_pivot != null:
		weapon_pivot.position = Vector2.ZERO
	_update_block_arc_visual()
	refresh_weapon_visual()
	trigger_squash(Vector2(1.14, 0.88))
	_apply_procedural_pose()
	print("[%s] STAGGERED for %.2fs!" % [actor_display_name, duration_sec])


# ---------------------------------------------------------------------------
# Clinch (Shove, Sweep -> Prone, Throw scaled by (STR/10)^2) & Lodged Extraction
# ---------------------------------------------------------------------------

func is_within_clinch_range(target: CombatActor, max_surface_gap_px: float = CLINCH_MAX_SURFACE_GAP_PX) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var center_dist: float = global_position.distance_to(target.global_position)
	var surface_gap: float = center_dist - get_body_collision_radius() - target.get_body_collision_radius()
	return surface_gap <= max_surface_gap_px


func find_clinch_target(max_range_px: float = CLINCH_RANGE_PX) -> CombatActor:
	if not is_inside_tree():
		return null
	var best: CombatActor = null
	var best_dist: float = INF
	for grp: StringName in [&"enemies", &"player"]:
		for n: Node in get_tree().get_nodes_in_group(grp):
			if n == self or not (n is CombatActor):
				continue
			var cand: CombatActor = n as CombatActor
			if not cand.is_alive() or cand.get_floor_level() != get_floor_level():
				continue
			if absf(get_height_z() - cand.get_height_z()) > 0.8:
				continue
			var d: float = global_position.distance_to(cand.global_position)
			var allowed_dist: float = maxf(max_range_px, get_body_collision_radius() + cand.get_body_collision_radius() + CLINCH_MAX_SURFACE_GAP_PX)
			if d <= allowed_dist and d < best_dist:
				best = cand
				best_dist = d
	return best


## Opposed stat contest for Clinch maneuvers (STR/CTRL/size vs target STR/CON/AGI/size + state).
## Compromised targets (STAGGERED / PRONE / KO / after deflect counter window) have heavily reduced resistance.
func evaluate_clinch_contest(target: CombatActor, action_kind: StringName) -> Dictionary:
	if stat_sheet == null or target == null or target.stat_sheet == null:
		return {"succeeded": true, "atk_score": 10.0, "def_score": 10.0}

	var my_str: float = stat_sheet.get_stat(StatSheet.Stat.STR)
	var my_ctrl: float = stat_sheet.get_stat(StatSheet.Stat.CTRL)
	var tgt_str: float = target.stat_sheet.get_stat(StatSheet.Stat.STR)
	var tgt_con: float = target.stat_sheet.get_stat(StatSheet.Stat.CON)
	var tgt_agi: float = target.stat_sheet.get_stat(StatSheet.Stat.AGI)

	var atk_score: float = 0.0
	var def_score: float = 0.0
	match action_kind:
		&"sweep":
			atk_score = (my_str * 0.45 + my_ctrl * 0.55) * maxf(0.5, actor_size_mult)
			def_score = (tgt_con * 0.40 + tgt_agi * 0.40 + tgt_str * 0.20) * maxf(0.5, target.actor_size_mult)
		&"shove":
			atk_score = (my_str * 0.75 + my_ctrl * 0.25) * maxf(0.5, actor_size_mult)
			def_score = (tgt_str * 0.55 + tgt_con * 0.45) * maxf(0.5, target.actor_size_mult)
		_:
			# Throw demands raw leverage & strength relative to defender's mass/STR/CON
			atk_score = (my_str * 0.70 + my_ctrl * 0.30) * maxf(0.5, actor_size_mult)
			def_score = (tgt_str * 0.55 + tgt_con * 0.45) * maxf(0.5, target.actor_size_mult)

	if counter_window_timer > 0.0:
		atk_score *= 1.50

	if (target.anatomy != null and target.anatomy.is_unconscious) or target.is_prone():
		def_score *= 0.25
	elif target.combat_state == CombatState.STAGGERED:
		def_score *= 0.45
	elif target.is_hardening_active():
		def_score *= 1.50

	var succeeded: bool = atk_score >= def_score * 0.85
	return {
		"succeeded": succeeded,
		"atk_score": atk_score,
		"def_score": def_score,
	}


func perform_clinch_shove(target: CombatActor, direction: Vector2 = Vector2.ZERO) -> Dictionary:
	if not can_act() or target == null or not target.is_alive():
		return {"success": false, "reason": "invalid"}
	if has_both_arms_severed():
		return {"success": false, "reason": "no_arms"}
	if not is_within_clinch_range(target):
		return {"success": false, "reason": "out_of_range"}
	var sta_cost: float = stat_sheet.get_effective_stamina_cost(CLINCH_STA_COST * 0.7, true)
	if current_stamina < sta_cost:
		return {"success": false, "reason": "no_stamina"}
	current_stamina = maxf(0.0, current_stamina - sta_cost)
	if is_in_group(&"player") and SimulationClock != null:
		SimulationClock.notify_player_attack()

	var contest: Dictionary = evaluate_clinch_contest(target, &"shove")
	if not bool(contest["succeeded"]):
		return {
			"success": false,
			"reason": "resisted",
			"action": &"shove",
			"atk_score": contest["atk_score"],
			"def_score": contest["def_score"],
		}

	var shove_dir: Vector2 = direction.normalized() if direction.length_squared() > 0.001 else (target.global_position - global_position).normalized()
	if shove_dir.length_squared() <= 0.001:
		shove_dir = Vector2.from_angle(aim_angle)
	var impulse: float = 30.0 * stat_sheet.get_melee_damage_mult()
	target.apply_stagger(0.55)
	target.apply_knockback(shove_dir, impulse, self)
	clinch_performed.emit(&"shove", target)
	return {"success": true, "action": &"shove", "impulse": impulse}


func perform_clinch_sweep(target: CombatActor) -> Dictionary:
	if not can_act() or target == null or not target.is_alive():
		return {"success": false, "reason": "invalid"}
	if has_both_arms_severed():
		return {"success": false, "reason": "no_arms"}
	if not is_within_clinch_range(target):
		return {"success": false, "reason": "out_of_range"}
	var sta_cost: float = stat_sheet.get_effective_stamina_cost(CLINCH_STA_COST, true)
	if current_stamina < sta_cost:
		return {"success": false, "reason": "no_stamina"}
	current_stamina = maxf(0.0, current_stamina - sta_cost)
	if is_in_group(&"player") and SimulationClock != null:
		SimulationClock.notify_player_attack()

	var contest: Dictionary = evaluate_clinch_contest(target, &"sweep")
	if not bool(contest["succeeded"]):
		return {
			"success": false,
			"reason": "resisted",
			"action": &"sweep_prone",
			"atk_score": contest["atk_score"],
			"def_score": contest["def_score"],
		}

	var my_score: float = float(contest["atk_score"])
	var tgt_score: float = float(contest["def_score"])
	var duration: float = clampf(PRONE_RECOVERY_DURATION_SEC * clampf(my_score / maxf(1.0, tgt_score), 0.6, 2.0), 1.2, 3.5)
	target.set_prone(duration)
	if SimulationClock != null:
		SimulationClock.trigger_hitstop(0.04, self, target)
	clinch_performed.emit(&"sweep_prone", target)
	return {"success": true, "action": &"sweep_prone", "prone_duration": duration}


func perform_clinch_throw(target: CombatActor, throw_direction: Vector2 = Vector2.ZERO) -> Dictionary:
	if not can_act() or target == null or not target.is_alive():
		return {"success": false, "reason": "invalid"}
	if has_both_arms_severed():
		return {"success": false, "reason": "no_arms"}
	if not is_within_clinch_range(target):
		return {"success": false, "reason": "out_of_range"}
	var sta_cost: float = stat_sheet.get_effective_stamina_cost(CLINCH_STA_COST * 1.2, true)
	if current_stamina < sta_cost:
		return {"success": false, "reason": "no_stamina"}
	current_stamina = maxf(0.0, current_stamina - sta_cost)
	if is_in_group(&"player") and SimulationClock != null:
		SimulationClock.notify_player_attack()

	var contest: Dictionary = evaluate_clinch_contest(target, &"throw")
	if not bool(contest["succeeded"]):
		return {
			"success": false,
			"reason": "resisted",
			"action": &"throw",
			"atk_score": contest["atk_score"],
			"def_score": contest["def_score"],
		}

	var dir: Vector2 = throw_direction.normalized() if throw_direction.length_squared() > 0.001 else Vector2.from_angle(aim_angle)
	var str_mult: float = stat_sheet.get_melee_damage_mult() # (STR / 10)^2 per GDD 7.3
	var impulse: float = CLINCH_THROW_BASE_IMPULSE * str_mult / maxf(0.5, target.actor_size_mult)
	target.apply_stagger(0.85)
	target.apply_knockback(dir, impulse, self)
	if SimulationClock != null:
		SimulationClock.trigger_hitstop(0.05, self, target)
	clinch_performed.emit(&"throw", target)
	return {"success": true, "action": &"throw", "impulse": impulse, "direction": dir}


func can_perform_stealth_takedown(target: CombatActor) -> bool:
	if not can_act() or not is_crouching or has_both_arms_severed():
		return false
	if target == null or not is_instance_valid(target) or not target.is_alive():
		return false
	if target.anatomy == null or target.anatomy.is_unconscious:
		return false
	if target.get_floor_level() != get_floor_level():
		return false
	if absf(get_height_z() - target.get_height_z()) > 0.8:
		return false
	if not is_within_clinch_range(target, CLINCH_MAX_SURFACE_GAP_PX + 8.0):
		return false
	if target.get("ai_state") != null and int(target.get("ai_state")) == 1:
		return false
	return target.is_vulnerable_to_stealth_backstab(self)


func find_stealth_takedown_target(max_range_px: float = CLINCH_RANGE_PX + 8.0) -> CombatActor:
	if not is_inside_tree() or not is_crouching or not can_act() or has_both_arms_severed():
		return null
	var best: CombatActor = null
	var best_dist: float = INF
	for grp: StringName in [&"enemies"]:
		for n: Node in get_tree().get_nodes_in_group(grp):
			if n == self or not (n is CombatActor):
				continue
			var cand: CombatActor = n as CombatActor
			if not can_perform_stealth_takedown(cand):
				continue
			var d: float = global_position.distance_to(cand.global_position)
			var allowed_dist: float = maxf(max_range_px, get_body_collision_radius() + cand.get_body_collision_radius() + CLINCH_MAX_SURFACE_GAP_PX + 8.0)
			if d <= allowed_dist and d < best_dist:
				best = cand
				best_dist = d
	return best


## Stealth non-lethal choke/knockout (Q while crouched behind PATROL/SEARCH enemy).
## Contests (STR + CTRL) * 0.5 * 1.45 against target CON * size_mult.
func perform_stealth_takedown(target: CombatActor) -> Dictionary:
	if not can_perform_stealth_takedown(target):
		return {"success": false, "reason": "invalid_conditions", "action": &"stealth_takedown"}
	if stat_sheet == null or target.stat_sheet == null:
		return {"success": false, "reason": "no_stats", "action": &"stealth_takedown"}
	var sta_cost: float = stat_sheet.get_effective_stamina_cost(STEALTH_TAKEDOWN_STA_COST, true)
	if current_stamina < sta_cost:
		return {"success": false, "reason": "no_stamina", "action": &"stealth_takedown"}
	current_stamina = maxf(0.0, current_stamina - sta_cost)

	var atk_score: float = (
		stat_sheet.get_stat(StatSheet.Stat.STR) + stat_sheet.get_stat(StatSheet.Stat.CTRL)
	) * 0.5 * STEALTH_TAKEDOWN_SURPRISE_BONUS
	var def_score: float = target.stat_sheet.get_stat(StatSheet.Stat.CON) * maxf(0.5, target.actor_size_mult)
	var bus: Node = _get_event_bus()

	if atk_score >= def_score:
		var advantage: float = clampf((atk_score - def_score) / maxf(1.0, def_score), 0.0, 1.0)
		var ko_duration: float = clampf(25.0 + advantage * 20.0, 25.0, 45.0)
		target.anatomy.apply_stealth_knockout(ko_duration, "stealth_takedown")
		if bus != null and bus.has_method("emit_noise"):
			bus.call("emit_noise", target.global_position, get_floor_level(), STEALTH_TAKEDOWN_NOISE_PX, self)
		target._emit_combat_outcome(self, AnatomyComponent.ZONE_NECK, "stealth_takedown", true, null, true)
		if SimulationClock != null:
			SimulationClock.trigger_hitstop(0.05, self, target)
		stealth_takedown_performed.emit(target, true)
		print("[%s] STEALTH TAKEDOWN -> %s KO for %.1fs (%.1f vs %.1f)!" % [actor_display_name, target.actor_display_name, ko_duration, atk_score, def_score])
		return {
			"success": true,
			"action": &"stealth_takedown",
			"ko_duration": ko_duration,
			"atk_score": atk_score,
			"def_score": def_score,
		}

	# Failed against high-CON target (e.g., Troll / Rank 6 Guard): brief stagger & enters COMBAT!
	target.apply_stagger(0.55)
	if target.has_method("engage_target"):
		target.call("engage_target", self)
	if bus != null and bus.has_method("emit_noise"):
		bus.call("emit_noise", target.global_position, get_floor_level(), 120.0, self)
	target._emit_combat_outcome(self, AnatomyComponent.ZONE_NECK, "stealth_takedown_resisted", false, null, false)
	stealth_takedown_performed.emit(target, false)
	print("[%s] STEALTH TAKEDOWN RESISTED by %s (%.1f vs %.1f)!" % [actor_display_name, target.actor_display_name, atk_score, def_score])
	return {
		"success": false,
		"reason": "resisted",
		"action": &"stealth_takedown",
		"atk_score": atk_score,
		"def_score": def_score,
	}


## Extracts a lodged weapon from own body or from an adjacent target (E / Shift+E, GDD 14.5),
## returning the extracted WeaponData to the extractor (or safely onto TestArena if hands/slots are full).
func try_extract_lodged_weapon(careful: bool = false) -> Dictionary:
	if has_both_arms_severed():
		return {"extracted": false, "weapon": null, "reason": "no_arms"}
	if anatomy != null and anatomy.has_lodged_weapon():
		for zone: StringName in anatomy.get_zone_names():
			if anatomy.has_lodged_weapon(zone):
				var res: Dictionary = anatomy.dislodge_weapon(zone, careful)
				res["target"] = self
				res["zone"] = zone
				res["careful"] = careful
				if bool(res.get("extracted", false)) and res.get("weapon", null) is WeaponData:
					res["returned_to_inventory"] = receive_recovered_weapon(res["weapon"] as WeaponData)
				return res
	if is_inside_tree():
		for grp: StringName in [&"enemies", &"player"]:
			for n: Node in get_tree().get_nodes_in_group(grp):
				if n == self or not (n is CombatActor):
					continue
				var other: CombatActor = n as CombatActor
				if other.get_floor_level() != get_floor_level():
					continue
				if global_position.distance_to(other.global_position) <= 48.0 and other.anatomy != null and other.anatomy.has_lodged_weapon():
					for zone: StringName in other.anatomy.get_zone_names():
						if other.anatomy.has_lodged_weapon(zone):
							var res: Dictionary = other.anatomy.dislodge_weapon(zone, careful)
							res["target"] = other
							res["zone"] = zone
							res["careful"] = careful
							if bool(res.get("extracted", false)) and res.get("weapon", null) is WeaponData:
								res["returned_to_inventory"] = receive_recovered_weapon(res["weapon"] as WeaponData)
							return res
	return {"extracted": false, "weapon": null}


# ---------------------------------------------------------------------------
# Combat FSM Micro-Steps
# ---------------------------------------------------------------------------

func step_combat_fsm(action_delta: float) -> void:
	if action_delta <= 0.0 or not is_alive():
		return

	var micro_steps: Array[float] = SimulationClock.compute_action_micro_steps(action_delta)
	for step_dt: float in micro_steps:
		if not is_alive():
			return
		_step_combat_micro(step_dt)


func _step_combat_micro(step_dt: float) -> void:
	if dash_cooldown_timer > 0.0:
		dash_cooldown_timer = maxf(0.0, dash_cooldown_timer - step_dt)
	if dash_timer > 0.0:
		dash_timer = maxf(0.0, dash_timer - step_dt)
	if sidestep_cooldown_timer > 0.0:
		sidestep_cooldown_timer = maxf(0.0, sidestep_cooldown_timer - step_dt)
	if sidestep_timer > 0.0:
		sidestep_timer = maxf(0.0, sidestep_timer - step_dt)

	match combat_state:
		CombatState.IDLE:
			_update_thrust_pivot_offset(0.0)
			_update_visual_facing(aim_angle)
		CombatState.WINDUP:
			state_timer -= step_dt
			_update_thrust_pivot_offset(0.0)
			_update_visual_facing(swing_start_angle)
			if state_timer <= 0.0:
				var active_wpn: WeaponData = get_active_weapon()
				combat_state = CombatState.ACTIVE
				var base_active: float = attack_active_override if (attack_active_override > 0.0 and not active_wpn.is_unarmed) else active_wpn.active_sec
				swing_duration = base_active * (0.90 if current_attack_type != PenetrationResolver.AttackType.SLASH else 1.0)
				state_timer = swing_duration
				swing_elapsed = 0.0
				if sweeper != null:
					sweeper.begin_swing(swing_start_angle, current_attack_type, half_swording)
				trigger_squash(Vector2(0.91, 1.11))
				_update_thrust_pivot_offset(0.0)
				_spawn_slash_arc_visual()
		CombatState.ACTIVE:
			swing_elapsed += step_dt
			state_timer -= step_dt
			var t: float = clampf(swing_elapsed / maxf(0.001, swing_duration), 0.0, 1.0)
			var cur_blade_angle: float = lerpf(swing_start_angle, swing_end_angle, t)
			_update_visual_facing(cur_blade_angle)
			_update_thrust_pivot_offset(t)
			_perform_weapon_sweep(cur_blade_angle, t)
			if combat_state != CombatState.ACTIVE:
				_update_thrust_pivot_offset(0.0)
				step_procedural_animation(step_dt)
				return
			if state_timer <= 0.0:
				if sweeper != null:
					_dispatch_sweep_events(sweeper.flush_pending_hits())
					sweeper.end_swing()
				if combat_state != CombatState.ACTIVE:
					_update_thrust_pivot_offset(0.0)
					step_procedural_animation(step_dt)
					return
				var rec_wpn: WeaponData = get_active_weapon()
				combat_state = CombatState.RECOVERY
				var base_rec: float = attack_recovery_override if (attack_recovery_override > 0.0 and not rec_wpn.is_unarmed) else rec_wpn.recovery_sec
				state_timer = base_rec * (0.90 if current_attack_type == PenetrationResolver.AttackType.THRUST else 1.0)
				current_attack_aura_burst = false
				current_attack_is_counter = false
				_update_thrust_pivot_offset(0.0)
				refresh_weapon_visual()
		CombatState.RECOVERY:
			state_timer -= step_dt
			_update_thrust_pivot_offset(0.0)
			_update_visual_facing(aim_angle)
			if state_timer <= 0.0:
				combat_state = CombatState.IDLE
				state_timer = 0.0
				_attack_launch_velocity = Vector2.ZERO
				_attack_launch_was_dash = false
		CombatState.STAGGERED:
			state_timer -= step_dt
			_update_thrust_pivot_offset(0.0)
			if state_timer <= 0.0:
				combat_state = CombatState.IDLE
				state_timer = 0.0
				current_poise = max_poise
				_attack_launch_velocity = Vector2.ZERO
				_attack_launch_was_dash = false

	step_procedural_animation(step_dt)


func _perform_weapon_sweep(blade_angle: float, active_progress: float = 1.0) -> void:
	var active_wpn: WeaponData = get_active_weapon()
	if sweeper == null or active_wpn == null or stat_sheet == null:
		return
	var thrust_ext: float = lerpf(0.45, 1.0, active_progress) if current_attack_type == PenetrationResolver.AttackType.THRUST else 1.0
	var events: Array[Dictionary] = sweeper.sweep_to_angle(
		global_position,
		blade_angle,
		active_wpn,
		stat_sheet,
		get_floor_level(),
		get_height_z(),
		aura_active or current_attack_aura_burst,
		aim_world_pos,
		self,
		null,
		true,
		get_combat_origin(),
		current_attack_type,
		half_swording,
		thrust_ext,
		current_attack_is_counter
	)
	_dispatch_sweep_events(events)


func _dispatch_sweep_events(events: Array[Dictionary]) -> void:
	var active_wpn: WeaponData = get_active_weapon()
	if events.is_empty() or active_wpn == null:
		return
	var eff_vel: Vector2 = current_move_velocity
	var eff_dash: bool = dash_timer > 0.0
	if _attack_launch_velocity.length_squared() > eff_vel.length_squared():
		eff_vel = _attack_launch_velocity
		eff_dash = eff_dash or _attack_launch_was_dash
	var aim_dir: Vector2 = Vector2.from_angle(aim_angle)
	var fwd_align: float = 1.0
	if eff_vel.length_squared() > 1.0:
		fwd_align = clampf(eff_vel.normalized().dot(aim_dir), 0.0, 1.0)
	var kin_mult: float = get_kinetic_mult(eff_vel.length(), eff_dash, fwd_align)

	for ev: Dictionary in events:
		var ev_type: String = String(ev.get("type", ""))
		if ev_type == "blade_clash":
			var other_node: Variant = ev.get("other", null)
			if other_node is CombatActor:
				_resolve_midair_blade_clash(other_node as CombatActor)
		elif ev_type == "entity":
			var target_node: Variant = ev.get("target", null)
			var zone: HitboxZone = ev.get("zone", null) as HitboxZone
			var is_wp: bool = bool(ev.get("is_weak_point", false))
			var dist: float = float(ev.get("distance_to_target", -1.0))
			var atk_t: PenetrationResolver.AttackType = int(ev.get("attack_type", current_attack_type)) as PenetrationResolver.AttackType
			var hs: bool = bool(ev.get("half_swording", half_swording))
			var is_backstab: bool = bool(ev.get("is_stealth_backstab", false))
			if target_node is CombatActor and zone != null:
				var use_anti_regen: bool = anti_regen_strikes_enabled
				if not use_anti_regen and is_in_group(&"player") and EventBus != null:
					use_anti_regen = EventBus.debug_anti_regen_attacks
				(target_node as CombatActor).receive_melee_hit(
					self,
					zone,
					active_wpn,
					is_wp,
					kin_mult,
					aura_active,
					atk_t,
					dist,
					hs,
					current_attack_aura_burst,
					use_anti_regen,
					current_attack_is_counter,
					is_backstab
				)
		elif ev_type == "out_of_vertical_reach":
			var target_node: Variant = ev.get("target", null)
			var zone: HitboxZone = ev.get("zone", null) as HitboxZone
			var z_name: StringName = zone.zone_name if zone != null else AnatomyComponent.ZONE_CHEST
			if target_node is CombatActor:
				var tgt: CombatActor = target_node as CombatActor
				var bus: Node = _get_event_bus()
				if bus != null and bus.has_method("publish_combat_outcome"):
					bus.call("publish_combat_outcome", {
						"attacker": self,
						"attacker_name": actor_display_name,
						"target": tgt,
						"target_name": tgt.actor_display_name,
						"zone": z_name,
						"outcome": "out_of_vertical_reach",
						"is_weak_point": false,
						"attacker_height_z": float(ev.get("attacker_height_z", get_height_z())),
						"target_height_z": float(ev.get("target_height_z", tgt.get_height_z())),
						"vertical_reach": float(ev.get("vertical_reach", active_wpn.vertical_reach)),
						"resolution": {},
					})
				print(
					"[Combat] %s -> %s MISSED (OUT OF VERTICAL REACH: z=%.1f vs %.1f, reach=%.1f — press F to Fly!)" % [
						actor_display_name,
						tgt.actor_display_name,
						float(ev.get("attacker_height_z", get_height_z())),
						float(ev.get("target_height_z", tgt.get_height_z())),
						float(ev.get("vertical_reach", active_wpn.vertical_reach)),
					]
				)
		elif ev_type == "wall":
			if bool(ev.get("aura_heavy_hit", false)):
				_spend_aura_heavy_hit_mp()
			var w_res: Dictionary = ev.get("result", {}) as Dictionary
			if bool(w_res.get("destroyed", false)):
				print("[%s] Smashed %s wall at %s!" % [actor_display_name, String(w_res.get("material_type", "")), str(ev.get("cell", Vector2i.ZERO))])
		elif ev_type == "floor":
			var f_res: Dictionary = ev.get("result", {}) as Dictionary
			if bool(f_res.get("broken", false)):
				print("[%s] Broke upper floor at %s!" % [actor_display_name, str(ev.get("cell", Vector2i.ZERO))])


func _resolve_midair_blade_clash(other: CombatActor) -> void:
	if other == null or not other.is_alive() or is_unarmed() or other.is_unarmed():
		return

	var pa: PenetrationResolver.ClashParams = PenetrationResolver.ClashParams.new()
	pa.actor = self
	pa.strength = stat_sheet.get_stat(StatSheet.Stat.STR)
	pa.control = stat_sheet.get_stat(StatSheet.Stat.CTRL)
	pa.aura_active = aura_active or current_attack_aura_burst
	pa.m_ctrl = stat_sheet.get_stat(StatSheet.Stat.M_CTRL) if stat_sheet.mana_awakened else 0.0
	pa.weapon_mass = equipped_weapon.mass_factor
	pa.weapon = equipped_weapon

	var pb: PenetrationResolver.ClashParams = PenetrationResolver.ClashParams.new()
	pb.actor = other
	pb.strength = other.stat_sheet.get_stat(StatSheet.Stat.STR)
	pb.control = other.stat_sheet.get_stat(StatSheet.Stat.CTRL)
	pb.aura_active = other.aura_active or other.current_attack_aura_burst
	pb.m_ctrl = other.stat_sheet.get_stat(StatSheet.Stat.M_CTRL) if other.stat_sheet.mana_awakened else 0.0
	pb.weapon_mass = other.equipped_weapon.mass_factor
	pb.weapon = other.equipped_weapon

	var clash_res: PenetrationResolver.ClashResult = PenetrationResolver.resolve_blade_clash(pa, pb, true, true)
	last_blade_clash_result = clash_res
	other.last_blade_clash_result = clash_res

	var dir_a_to_b: Vector2 = (other.global_position - global_position).normalized()
	if dir_a_to_b.length_squared() <= 0.001:
		dir_a_to_b = Vector2.RIGHT

	if clash_res.stagger_a_sec > 0.0:
		apply_stagger(clash_res.stagger_a_sec)
	else:
		if sweeper != null:
			sweeper.end_swing()
		combat_state = CombatState.RECOVERY
		state_timer = 0.14
	if clash_res.stagger_b_sec > 0.0:
		other.apply_stagger(clash_res.stagger_b_sec)
	else:
		if other.sweeper != null:
			other.sweeper.end_swing()
		other.combat_state = CombatState.RECOVERY
		other.state_timer = 0.14

	if clash_res.knockback_a > 0.0:
		apply_knockback(-dir_a_to_b, clash_res.knockback_a * 0.4, other)
	if clash_res.knockback_b > 0.0:
		other.apply_knockback(dir_a_to_b, clash_res.knockback_b * 0.4, self)

	if clash_res.ctrl_deflect_winner == 1:
		counter_window_timer = clash_res.counter_window_sec
	elif clash_res.ctrl_deflect_winner == 2:
		other.counter_window_timer = clash_res.counter_window_sec

	refresh_weapon_visual()
	other.refresh_weapon_visual()
	if SimulationClock != null:
		SimulationClock.trigger_hitstop(0.05, self, other)
	var clash_mid: Vector2 = (get_combat_origin() + other.get_combat_origin()) * 0.5
	var bus: Node = _get_event_bus()
	if bus != null:
		if bus.has_method("request_sparks"):
			bus.call("request_sparks", clash_mid, get_floor_level(), get_height_z(), Color("#FFF3A1"), 12)
		if bus.has_method("request_camera_shake"):
			bus.call("request_camera_shake", 4.5, 0.18)
		if bus.has_method("emit_noise"):
			bus.call("emit_noise", global_position, get_floor_level(), 210.0, self)

	blade_clashed_with.emit(other, clash_res)
	other.blade_clashed_with.emit(self, clash_res)
	_emit_combat_outcome(other, &"Weapon", "blade_clash", false, null)


func _spawn_slash_arc_visual() -> void:
	var active_wpn: WeaponData = get_active_weapon()
	if slash_trail_line == null or active_wpn == null or not is_inside_tree():
		return
	var m_ctrl: float = stat_sheet.get_stat(StatSheet.Stat.M_CTRL) if (stat_sheet != null and stat_sheet.mana_awakened) else 0.0
	var aura: PenetrationResolver.AuraBonuses = PenetrationResolver.calculate_aura_bonuses(aura_active, m_ctrl, current_attack_aura_burst)
	var arc_radius: float = active_wpn.hilt_offset_px + active_wpn.get_effective_blade_length(half_swording) + aura.blade_extension
	var pts: PackedVector2Array = PackedVector2Array()
	if current_attack_type == PenetrationResolver.AttackType.THRUST:
		var dir: Vector2 = Vector2.from_angle(aim_angle)
		pts = PackedVector2Array([dir * active_wpn.hilt_offset_px, dir * arc_radius])
	else:
		var segs: int = 10
		pts.resize(segs + 1)
		for i: int in range(segs + 1):
			var a: float = lerpf(swing_start_angle, swing_end_angle, float(i) / float(segs))
			pts[i] = Vector2.from_angle(a) * arc_radius
	slash_trail_line.points = pts
	var trail_col: Color = Color(0.95, 0.96, 1.0, 0.65)
	if aura.active:
		trail_col = Color(1.0, 0.92, 0.35, 0.90) if current_attack_aura_burst else Color(0.35, 0.85, 1.0, 0.78)
	elif current_attack_is_counter:
		trail_col = Color(1.0, 0.86, 0.28, 0.88)
	elif current_attack_type == PenetrationResolver.AttackType.THRUST:
		trail_col = Color(1.0, 0.45, 0.45, 0.75)
	elif current_attack_type == PenetrationResolver.AttackType.BLUNT:
		trail_col = Color(0.65, 0.55, 1.0, 0.75)
	slash_trail_line.default_color = trail_col
	slash_trail_line.visible = true
	if _slash_trail_tween != null and _slash_trail_tween.is_valid():
		_slash_trail_tween.kill()
	_slash_trail_tween = create_tween()
	_slash_trail_tween.tween_property(slash_trail_line, "default_color:a", 0.0, 0.14)
	_slash_trail_tween.tween_callback(func() -> void:
		if is_instance_valid(slash_trail_line):
			slash_trail_line.visible = false
	)


func _spend_aura_heavy_hit_mp() -> void:
	if not aura_active or stat_sheet == null:
		return
	var mp_cost: float = PenetrationResolver.AURA_MP_PER_HEAVY_HIT * stat_sheet.get_mp_cost_mult()
	current_mp = maxf(0.0, current_mp - mp_cost)
	if current_mp <= 0.0:
		set_aura_active(false)


func _update_visual_facing(blade_angle: float) -> void:
	_current_blade_angle = blade_angle
	is_facing_back = sin(aim_angle) < FACING_BACK_SIN_THRESHOLD
	is_facing_left = cos(aim_angle) < 0.0

	if weapon_pivot != null:
		if is_blocking and combat_state == CombatState.IDLE:
			var guard_off: float = deg_to_rad(-62.0) if is_facing_left else deg_to_rad(62.0)
			weapon_pivot.rotation = aim_angle + guard_off
		else:
			weapon_pivot.rotation = blade_angle
		weapon_pivot.scale = Vector2(1.0, -1.0 if is_facing_left else 1.0)
		weapon_pivot.z_index = -1 if is_facing_back else 3
		if combat_state != CombatState.ACTIVE:
			weapon_pivot.position = Vector2.ZERO

	_update_block_arc_visual()
	_apply_procedural_pose()


func _update_thrust_pivot_offset(active_progress: float = 0.0) -> void:
	if weapon_pivot == null:
		return
	if combat_state == CombatState.ACTIVE and current_attack_type == PenetrationResolver.AttackType.THRUST:
		var active_wpn: WeaponData = get_active_weapon()
		var base_lunge: float = clampf(active_wpn.blade_length * 0.35, 8.0, 18.0) if active_wpn != null else 10.0
		var thrust_ext: float = lerpf(0.45, 1.0, clampf(active_progress, 0.0, 1.0))
		weapon_pivot.position = Vector2.from_angle(aim_angle) * (base_lunge * thrust_ext)
	else:
		weapon_pivot.position = Vector2.ZERO


func trigger_hitflash(color: Color = Color(2.3, 2.3, 2.3, 1.0), duration_sec: float = HITFLASH_DURATION_SEC) -> void:
	_hitflash_color = color
	_hitflash_timer = maxf(_hitflash_timer, duration_sec)
	if visual_rig != null:
		visual_rig.modulate = _hitflash_color


func trigger_squash(target_scale: Vector2) -> void:
	_squash_scale = target_scale
	if visual_rig != null:
		visual_rig.scale = _squash_scale


func is_visual_limping() -> bool:
	if anatomy == null or is_flying():
		return false
	var l_sev: bool = anatomy.is_limb_severed(AnatomyComponent.ZONE_LEFT_LEG)
	var r_sev: bool = anatomy.is_limb_severed(AnatomyComponent.ZONE_RIGHT_LEG)
	if l_sev and r_sev:
		return false
	var l_inj: bool = l_sev or anatomy.has_fracture(AnatomyComponent.ZONE_LEFT_LEG) or anatomy.has_tendon_tear(AnatomyComponent.ZONE_LEFT_LEG)
	var r_inj: bool = r_sev or anatomy.has_fracture(AnatomyComponent.ZONE_RIGHT_LEG) or anatomy.has_tendon_tear(AnatomyComponent.ZONE_RIGHT_LEG)
	return l_inj or r_inj or anatomy.has_limp


func get_offhand_arm_zone() -> StringName:
	var right_intact: bool = anatomy == null or not anatomy.is_limb_severed(AnatomyComponent.ZONE_RIGHT_ARM)
	var left_intact: bool = anatomy == null or not anatomy.is_limb_severed(AnatomyComponent.ZONE_LEFT_ARM)
	if right_intact and left_intact:
		return AnatomyComponent.ZONE_LEFT_ARM
	return &""


func get_offhand_hand_rig_pos() -> Vector2:
	var off_zone: StringName = get_offhand_arm_zone()
	if off_zone == &"" or not limb_polygons.has(off_zone):
		return Vector2.ZERO
	var arm: Polygon2D = limb_polygons[off_zone]
	var hand: Node2D = _limb_hand_nodes.get(off_zone, null) as Node2D
	if not is_instance_valid(arm):
		return Vector2.ZERO
	if hand != null and is_instance_valid(hand):
		return arm.position + hand.position.rotated(arm.rotation)
	return arm.position


## Advances procedural 3/4 Top-Down walk/limp/flight/wing/combat animations strictly on action_delta (SimulationClock).
func step_procedural_animation(action_delta: float) -> void:
	if action_delta <= 0.0:
		return

	anim_time += action_delta
	var flying_now: bool = is_flying()
	var move_speed: float = current_move_velocity.length()
	var can_step: bool = (
		is_alive()
		and not flying_now
		and not (anatomy != null and anatomy.is_unconscious)
		and not is_prone()
		and move_speed > 8.0
	)
	if can_step:
		var freq: float = clampf(move_speed / 24.0, 3.0, 18.0)
		if is_visual_limping():
			freq *= 0.72
		walk_cycle_phase = fmod(walk_cycle_phase + action_delta * freq, TAU)
		_walk_blend = minf(1.0, _walk_blend + action_delta * 10.0)
	else:
		_walk_blend = maxf(0.0, _walk_blend - action_delta * 9.0)

	if flying_now and get_flight_mode() == VerticalityComponent.FlightMode.WING_FLIGHT:
		var flap_speed: float = 11.5 if move_speed > 20.0 else 7.8
		if is_wings_crippled():
			flap_speed *= 1.35
		wing_flap_phase = fmod(wing_flap_phase + action_delta * flap_speed, TAU)

	# Decay squash & stretch back to (1, 1) on action_delta
	var sq_alpha: float = clampf(action_delta * 16.0, 0.0, 1.0)
	_squash_scale = _squash_scale.lerp(Vector2.ONE, sq_alpha)
	if _squash_scale.distance_to(Vector2.ONE) < 0.004:
		_squash_scale = Vector2.ONE

	# Decay hitflash on action_delta
	if _hitflash_timer > 0.0:
		_hitflash_timer = maxf(0.0, _hitflash_timer - action_delta)
		if visual_rig != null:
			if _hitflash_timer > 0.0:
				var f_t: float = clampf(_hitflash_timer / HITFLASH_DURATION_SEC, 0.0, 1.0)
				visual_rig.modulate = Color.WHITE.lerp(_hitflash_color, f_t)
			else:
				visual_rig.modulate = Color.WHITE

	_apply_procedural_pose()


func _apply_procedural_pose() -> void:
	if visual_rig == null:
		return

	var s: float = actor_size_mult
	var alive_now: bool = is_alive()
	var unconscious_now: bool = anatomy != null and anatomy.is_unconscious
	var flying_now: bool = is_flying()
	var prone_now: bool = is_prone()
	var mirror_x: float = -1.0 if is_facing_left else 1.0

	# 1. Front / Back layering & Left / Right detail mirroring (never rotating BodyVisual!)
	if torso_front_details != null:
		torso_front_details.visible = not is_facing_back
		torso_front_details.scale.x = mirror_x
	if torso_back_details != null:
		torso_back_details.visible = is_facing_back
		torso_back_details.scale.x = mirror_x
	if head_front_details != null:
		head_front_details.visible = not is_facing_back
		head_front_details.scale.x = mirror_x
	if head_back_details != null:
		head_back_details.visible = is_facing_back
		head_back_details.scale.x = mirror_x
	if cape_back_node != null:
		cape_back_node.z_index = 3 if is_facing_back else -1
		cape_back_node.scale.x = 1.0 + sin(anim_time * 3.2) * (0.04 if flying_now else 0.015)

	# 2. Sync bloody amputation stumps with AnatomyComponent
	_sync_stump_visibility()

	# 3. Compute internal VisualRig bob, limp, lean, prone/dead collapse & squash (never touching BodyVisual!)
	var rig_pos: Vector2 = Vector2.ZERO
	var rig_rot: float = 0.0
	var rig_scale: Vector2 = _squash_scale

	var l_leg_sev: bool = anatomy != null and anatomy.is_limb_severed(AnatomyComponent.ZONE_LEFT_LEG)
	var r_leg_sev: bool = anatomy != null and anatomy.is_limb_severed(AnatomyComponent.ZONE_RIGHT_LEG)
	var both_legs_gone: bool = l_leg_sev and r_leg_sev
	var l_leg_inj: bool = anatomy != null and (l_leg_sev or anatomy.has_fracture(AnatomyComponent.ZONE_LEFT_LEG) or anatomy.has_tendon_tear(AnatomyComponent.ZONE_LEFT_LEG))
	var r_leg_inj: bool = anatomy != null and (r_leg_sev or anatomy.has_fracture(AnatomyComponent.ZONE_RIGHT_LEG) or anatomy.has_tendon_tear(AnatomyComponent.ZONE_RIGHT_LEG))
	var limping: bool = is_visual_limping()

	if not alive_now:
		rig_pos = Vector2(0.0, 9.5 * s)
		rig_rot = deg_to_rad(86.0) * mirror_x
		rig_scale = Vector2.ONE
	elif unconscious_now:
		rig_pos = Vector2(0.0, 7.4 * s)
		rig_rot = deg_to_rad(68.0) * mirror_x
		rig_scale = Vector2.ONE
	elif prone_now and not flying_now:
		if both_legs_gone:
			rig_pos = Vector2(0.0, 8.2 * s)
			rig_rot = deg_to_rad(14.0) * mirror_x
		else:
			rig_pos = Vector2(0.0, 7.2 * s)
			rig_rot = deg_to_rad(52.0) * mirror_x
	elif flying_now:
		var hover_bob: float = sin(anim_time * 3.6) * 1.6 * s
		rig_pos = Vector2(0.0, hover_bob)
		rig_rot = clampf(current_move_velocity.x / 260.0, -1.0, 1.0) * 0.14
	else:
		var walk_bob: float = -absf(sin(walk_cycle_phase)) * 1.9 * s * _walk_blend
		var idle_breath: float = sin(anim_time * 2.6) * 0.45 * s * (1.0 - _walk_blend)
		rig_pos.y = walk_bob + idle_breath
		rig_rot = clampf(current_move_velocity.x / 240.0, -1.0, 1.0) * 0.07

		# Noticeable limp dip & asymmetric lean toward injured/severed leg
		if limping:
			var limp_side: float = -1.0 if (l_leg_inj and not r_leg_inj) else (1.0 if (r_leg_inj and not l_leg_inj) else -1.0)
			var limp_wave: float = maxf(0.0, sin(walk_cycle_phase))
			rig_pos.y += (1.1 + limp_wave * 2.6 * _walk_blend) * s
			rig_pos.x += limp_side * (0.9 + limp_wave * 1.2 * _walk_blend) * s
			rig_rot += limp_side * (0.09 + 0.15 * limp_wave * _walk_blend)

		# Combat posture lean & anticipation
		match combat_state:
			CombatState.WINDUP:
				var wind_t: float = 1.0 - clampf(state_timer / maxf(0.05, _windup_total_visual_sec), 0.0, 1.0)
				rig_rot -= cos(aim_angle) * (0.06 + 0.08 * wind_t)
				rig_pos.y += 0.8 * s * wind_t
			CombatState.ACTIVE:
				rig_rot += cos(aim_angle) * 0.13
				rig_pos += Vector2.from_angle(aim_angle) * (1.6 * s)
			CombatState.STAGGERED:
				rig_rot += sin(anim_time * 20.0) * 0.16
				rig_pos.x += sin(anim_time * 20.0) * 1.4 * s

		if is_blocking and combat_state == CombatState.IDLE:
			rig_pos.y += 1.0 * s
			rig_rot -= cos(aim_angle) * 0.05

	visual_rig.position = rig_pos
	visual_rig.rotation = rig_rot
	visual_rig.scale = rig_scale
	if _hitflash_timer <= 0.0:
		visual_rig.modulate = Color.WHITE

	# 4. Head subtle bob / gaze tilt
	var head_poly: Polygon2D = limb_polygons.get(AnatomyComponent.ZONE_HEAD, null)
	if head_poly != null and is_instance_valid(head_poly):
		var h_base: Vector2 = _limb_base_positions.get(AnatomyComponent.ZONE_HEAD, Vector2(0.0, -8.2 * s))
		var h_bob: float = sin(walk_cycle_phase * 2.0) * 0.55 * s * _walk_blend
		head_poly.position = h_base + Vector2(0.0, h_bob)
		head_poly.rotation = -rig_rot * 0.35

	# 5. Legs animation (elliptical stride / limp drag / dangling flight legs)
	_pose_legs(s, flying_now, alive_now and not unconscious_now and not prone_now, l_leg_inj, r_leg_inj)

	# 6. Weapon model anticipation/guard offset (keeps weapon_pivot.position untouched for THRUST contract!)
	_pose_weapon_model(s, alive_now, rig_pos)

	# 7. Articulated Arms & Hands (weapon grip, Half-swording off-hand onto mid-blade, block guard, unarmed punch)
	_pose_arms(s, alive_now and not unconscious_now, flying_now)

	# 8. Sync wings & levitation ring with rig bob
	_update_flight_visuals()


func _sync_stump_visibility() -> void:
	if stump_nodes.is_empty():
		return
	var head_gone: bool = anatomy != null and (anatomy.is_limb_severed(AnatomyComponent.ZONE_HEAD) or anatomy.is_limb_severed(AnatomyComponent.ZONE_NECK))
	for skey: StringName in stump_nodes.keys():
		var st: Node2D = stump_nodes[skey]
		if not is_instance_valid(st):
			continue
		if skey == AnatomyComponent.ZONE_HEAD:
			st.visible = head_gone
		else:
			st.visible = anatomy != null and anatomy.is_limb_severed(skey)


func _pose_legs(s: float, flying_now: bool, upright: bool, l_inj: bool, r_inj: bool) -> void:
	var stride_x: float = 2.6 * s
	var lift_y: float = 3.2 * s
	var leg_zones: Array[StringName] = [AnatomyComponent.ZONE_LEFT_LEG, AnatomyComponent.ZONE_RIGHT_LEG]
	for idx: int in range(leg_zones.size()):
		var zkey: StringName = leg_zones[idx]
		var lpoly: Polygon2D = limb_polygons.get(zkey, null)
		if lpoly == null or not is_instance_valid(lpoly):
			continue
		var base_pos: Vector2 = _limb_base_positions.get(zkey, lpoly.position)
		var phase: float = walk_cycle_phase + (PI if idx == 1 else 0.0)
		var is_injured_leg: bool = l_inj if idx == 0 else r_inj
		if not upright:
			lpoly.position = base_pos
			lpoly.rotation = (-0.22 if idx == 0 else 0.22)
		elif flying_now:
			# Relaxed dangling feet in flight (no stepping cycle!)
			var drag_rot: float = clampf(-current_move_velocity.x / 240.0, -0.35, 0.35)
			var sway: float = sin(anim_time * 3.0 + float(idx) * 1.1) * 0.09
			lpoly.position = base_pos + Vector2(0.0, 1.8 * s)
			lpoly.rotation = drag_rot + sway
		else:
			var stride_mult: float = 0.32 if is_injured_leg else 1.0
			var off_x: float = cos(phase) * stride_x * stride_mult * _walk_blend
			var off_y: float = -maxf(0.0, sin(phase)) * lift_y * stride_mult * _walk_blend
			if is_injured_leg:
				off_y += 0.9 * s
			lpoly.position = base_pos + Vector2(off_x, off_y)
			lpoly.rotation = (sin(phase) * 0.22 * stride_mult * _walk_blend) + ((0.18 if idx == 0 else -0.18) if is_injured_leg else 0.0)


func _pose_weapon_model(s: float, alive_now: bool, rig_pos: Vector2) -> void:
	if weapon_model_root == null or weapon_pivot == null:
		return
	if not alive_now:
		weapon_model_root.position = Vector2.ZERO
		return
	var local_off: Vector2 = Vector2.ZERO
	if is_blocking and combat_state == CombatState.IDLE:
		local_off = Vector2(2.6 * s, -2.2 * s)
	elif combat_state == CombatState.WINDUP:
		var wind_t: float = 1.0 - clampf(state_timer / maxf(0.05, _windup_total_visual_sec), 0.0, 1.0)
		var pullback: float = 6.0 if current_attack_type == PenetrationResolver.AttackType.THRUST else 3.2
		local_off = Vector2(-pullback * s * (0.45 + 0.55 * wind_t), 0.0)
	elif combat_state == CombatState.ACTIVE:
		local_off = Vector2(2.4 * s, 0.0)
	# Mirror slight vertical bob along weapon axis so blade stays synced with hands
	var rig_bob_in_wp: Vector2 = rig_pos.rotated(-weapon_pivot.rotation)
	rig_bob_in_wp.y *= weapon_pivot.scale.y
	weapon_model_root.position = local_off + rig_bob_in_wp


func _pose_arms(s: float, can_pose: bool, flying_now: bool) -> void:
	var left_arm: Polygon2D = limb_polygons.get(AnatomyComponent.ZONE_LEFT_ARM, null)
	var right_arm: Polygon2D = limb_polygons.get(AnatomyComponent.ZONE_RIGHT_ARM, null)
	var left_base: Vector2 = _limb_base_positions.get(AnatomyComponent.ZONE_LEFT_ARM, Vector2(-7.8 * s, -3.6 * s))
	var right_base: Vector2 = _limb_base_positions.get(AnatomyComponent.ZONE_RIGHT_ARM, Vector2(7.8 * s, -3.6 * s))
	var left_hand: Node2D = _limb_hand_nodes.get(AnatomyComponent.ZONE_LEFT_ARM, null) as Node2D
	var right_hand: Node2D = _limb_hand_nodes.get(AnatomyComponent.ZONE_RIGHT_ARM, null) as Node2D
	var default_hand_y: float = (8.2 if visual_style == VisualStyle.TROLL_BERSERKER else 7.2) * s

	var right_intact: bool = anatomy == null or not anatomy.is_limb_severed(AnatomyComponent.ZONE_RIGHT_ARM)
	var left_intact: bool = anatomy == null or not anatomy.is_limb_severed(AnatomyComponent.ZONE_LEFT_ARM)

	if not can_pose:
		if left_arm != null and is_instance_valid(left_arm):
			left_arm.position = left_base
			left_arm.rotation = 0.25
			if left_hand != null:
				left_hand.position = Vector2(0.0, default_hand_y)
		if right_arm != null and is_instance_valid(right_arm):
			right_arm.position = right_base
			right_arm.rotation = -0.25
			if right_hand != null:
				right_hand.position = Vector2(0.0, default_hand_y)
		return

	var has_wpn: bool = equipped_weapon != null and not equipped_weapon.is_unarmed and weapon_pivot != null and weapon_model_root != null
	var primary_is_right: bool = right_intact
	var primary_arm: Polygon2D = right_arm if primary_is_right else left_arm
	var primary_base: Vector2 = right_base if primary_is_right else left_base
	var primary_hand: Node2D = right_hand if primary_is_right else left_hand
	var off_arm: Polygon2D = left_arm if primary_is_right else right_arm
	var off_base: Vector2 = left_base if primary_is_right else right_base
	var off_hand: Node2D = left_hand if primary_is_right else right_hand
	var off_intact: bool = left_intact if primary_is_right else right_intact

	if has_wpn and (right_intact or left_intact):
		var wp_rot: float = weapon_pivot.rotation
		var wp_sy: float = weapon_pivot.scale.y
		var m_off: Vector2 = weapon_model_root.position
		var hilt_x: float = maxf(3.0, equipped_weapon.hilt_offset_px - 2.5)
		var hilt_in_rig: Vector2 = (
			weapon_pivot.position
			+ Vector2(m_off.x + hilt_x, m_off.y * wp_sy).rotated(wp_rot)
			- visual_rig.position
		)
		_aim_arm_to_target(primary_arm, primary_base, primary_hand, hilt_in_rig, default_hand_y, s, 3.2 * s)
		if primary_arm != null and is_instance_valid(primary_arm):
			primary_arm.z_index = -1 if is_facing_back else 3

		if off_intact and off_arm != null and is_instance_valid(off_arm):
			if half_swording and equipped_weapon.can_half_sword:
				# Half-swording (Tab): second hand reaches forward to grip mid-blade!
				var eff_blade: float = equipped_weapon.get_effective_blade_length(true)
				var mid_x: float = equipped_weapon.hilt_offset_px + eff_blade * 0.55
				var mid_in_rig: Vector2 = (
					weapon_pivot.position
					+ Vector2(m_off.x + mid_x, m_off.y * wp_sy).rotated(wp_rot)
					- visual_rig.position
				)
				_aim_arm_to_target(off_arm, off_base, off_hand, mid_in_rig, default_hand_y, s, 5.2 * s)
				off_arm.z_index = -1 if is_facing_back else 3
			elif is_blocking and combat_state == CombatState.IDLE:
				# Braced defensive guard stance across chest
				var guard_pt: Vector2 = Vector2.from_angle(aim_angle) * (6.5 * s) + Vector2(0.0, 0.5 * s)
				_aim_arm_to_target(off_arm, off_base, off_hand, guard_pt, default_hand_y, s, 3.0 * s)
				off_arm.z_index = 3 if not is_facing_back else -1
			elif equipped_weapon.can_half_sword:
				# Two-handed weapon pommel support grip
				var pom_x: float = maxf(1.0, equipped_weapon.hilt_offset_px - 6.5)
				var pom_in_rig: Vector2 = (
					weapon_pivot.position
					+ Vector2(m_off.x + pom_x, m_off.y * wp_sy).rotated(wp_rot)
					- visual_rig.position
				)
				_aim_arm_to_target(off_arm, off_base, off_hand, pom_in_rig, default_hand_y, s, 3.2 * s)
				off_arm.z_index = -1 if is_facing_back else 2
			else:
				# Natural counter-swing on free arm during walk / ready stance
				var swing_rot: float = -sin(walk_cycle_phase) * 0.30 * _walk_blend if not flying_now else 0.18
				off_arm.position = off_base
				off_arm.rotation = swing_rot + (0.14 if primary_is_right else -0.14)
				off_arm.z_index = 2
				if off_hand != null:
					off_hand.position = Vector2(0.0, default_hand_y)
	else:
		# Unarmed combat & locomotion poses
		var aim_dir: Vector2 = Vector2.from_angle(aim_angle)
		for side_idx: int in range(2):
			var arm_n: Polygon2D = left_arm if side_idx == 0 else right_arm
			var base_p: Vector2 = left_base if side_idx == 0 else right_base
			var hand_n: Node2D = left_hand if side_idx == 0 else right_hand
			if arm_n == null or not is_instance_valid(arm_n):
				continue
			if is_blocking and combat_state == CombatState.IDLE:
				var cross_pt: Vector2 = aim_dir * (6.0 * s) + Vector2((-2.0 if side_idx == 0 else 2.0) * s, -1.0 * s)
				_aim_arm_to_target(arm_n, base_p, hand_n, cross_pt, default_hand_y, s, 2.8 * s)
				arm_n.z_index = 3 if not is_facing_back else -1
			elif combat_state == CombatState.WINDUP and side_idx == 1:
				var pull_pt: Vector2 = base_p - aim_dir * (4.5 * s) + Vector2(0.0, 2.5 * s)
				_aim_arm_to_target(arm_n, base_p, hand_n, pull_pt, default_hand_y, s, 2.5 * s)
				arm_n.z_index = 3
			elif combat_state == CombatState.ACTIVE and side_idx == 1:
				var punch_pt: Vector2 = aim_dir * (14.5 * s)
				_aim_arm_to_target(arm_n, base_p, hand_n, punch_pt, default_hand_y, s, 4.5 * s)
				arm_n.z_index = 3
			else:
				var ph: float = walk_cycle_phase + (PI if side_idx == 1 else 0.0)
				arm_n.position = base_p
				arm_n.rotation = (sin(ph) * 0.30 * _walk_blend) if not flying_now else (0.20 if side_idx == 0 else -0.20)
				arm_n.z_index = 2
				if hand_n != null:
					hand_n.position = Vector2(0.0, default_hand_y)


func _aim_arm_to_target(
	arm: Polygon2D,
	base_pos: Vector2,
	hand: Node2D,
	target_in_rig: Vector2,
	default_hand_y: float,
	s: float,
	max_shoulder_shift: float
) -> void:
	if arm == null or not is_instance_valid(arm):
		return
	var delta: Vector2 = target_in_rig - base_pos
	var dist: float = delta.length()
	if dist <= 0.01:
		arm.position = base_pos
		arm.rotation = 0.0
		if hand != null:
			hand.position = Vector2(0.0, default_hand_y)
		return
	var dir: Vector2 = delta / dist
	var shift: float = clampf(dist - default_hand_y, 0.0, max_shoulder_shift)
	arm.position = base_pos + dir * shift
	arm.rotation = dir.angle() - PI * 0.5
	if hand != null and is_instance_valid(hand):
		var reach: float = clampf(dist - shift, 3.6 * s, default_hand_y + 4.8 * s)
		hand.position = Vector2(0.0, reach)


func _get_zone_lodged_anchor(zone: StringName) -> Dictionary:
	var s: float = actor_size_mult
	if limb_polygons.has(zone) and is_instance_valid(limb_polygons[zone]):
		var lpoly: Polygon2D = limb_polygons[zone]
		var local_off: Vector2 = Vector2(0.0, -3.5 * s) if zone == AnatomyComponent.ZONE_HEAD else Vector2(0.0, 3.5 * s)
		return {"parent": lpoly, "pos": local_off}
	var body_off: Vector2 = Vector2(2.2 * s, 0.5 * s)
	match zone:
		AnatomyComponent.ZONE_NECK:
			body_off = Vector2(1.8 * s, -6.8 * s)
		AnatomyComponent.ZONE_STOMACH:
			body_off = Vector2(-2.2 * s, 4.2 * s)
		AnatomyComponent.ZONE_WINGS:
			body_off = Vector2(0.0, -2.5 * s)
	return {"parent": lodged_weapons_root, "pos": body_off}


func _attach_lodged_weapon_visual(zone: StringName, weapon: WeaponData) -> void:
	if visual_rig == null:
		return
	var anchor: Dictionary = _get_zone_lodged_anchor(zone)
	var parent_node: Node2D = anchor.get("parent", lodged_weapons_root) as Node2D
	if parent_node == null or not is_instance_valid(parent_node):
		return
	var s: float = actor_size_mult
	var existing_list: Array = _lodged_weapon_visuals.get(zone, []) as Array
	var stack_idx: int = existing_list.size()

	var node: Node2D = Node2D.new()
	node.name = "LodgedWeapon_%s_%d" % [String(zone), stack_idx]
	node.z_index = 4
	node.position = (anchor.get("pos", Vector2.ZERO) as Vector2) + Vector2(float(stack_idx) * 2.0 * s, float(stack_idx) * -1.5 * s)
	node.rotation = deg_to_rad(-38.0 + float(stack_idx) * 24.0) * (-1.0 if zone == AnatomyComponent.ZONE_LEFT_ARM or zone == AnatomyComponent.ZONE_LEFT_LEG else 1.0)

	# Blood droplet at entry point
	var blood_dot: Polygon2D = Polygon2D.new()
	blood_dot.color = Color("#B5121B")
	blood_dot.polygon = _create_ellipse_polygon(2.2 * s, 1.8 * s, 6)
	node.add_child(blood_dot)

	# Exposed blade section + crossguard + protruding hilt
	var bcol: Color = weapon.blade_color if weapon != null else Color("#C8D0DC")
	var stub_len: float = clampf((weapon.blade_length * 0.35) if weapon != null else 8.0, 5.5, 12.0)
	var blade: Polygon2D = Polygon2D.new()
	blade.color = bcol
	blade.polygon = PackedVector2Array([
		Vector2(0.0, -1.2),
		Vector2(stub_len, -1.7),
		Vector2(stub_len, 1.7),
		Vector2(0.0, 1.2),
	])
	node.add_child(blade)
	_add_outline(blade, blade.polygon, Color("#14161E"), 0.8)

	var guard: Polygon2D = Polygon2D.new()
	guard.color = Color("#A89268")
	guard.polygon = PackedVector2Array([
		Vector2(stub_len - 1.0, -4.2),
		Vector2(stub_len + 1.2, -4.2),
		Vector2(stub_len + 1.2, 4.2),
		Vector2(stub_len - 1.0, 4.2),
	])
	node.add_child(guard)
	_add_outline(guard, guard.polygon, Color("#14161E"), 0.8)

	var hilt: Polygon2D = Polygon2D.new()
	hilt.color = Color("#5D3C24")
	hilt.polygon = PackedVector2Array([
		Vector2(stub_len + 1.2, -1.3),
		Vector2(stub_len + 6.8, -1.3),
		Vector2(stub_len + 6.8, 1.3),
		Vector2(stub_len + 1.2, 1.3),
	])
	node.add_child(hilt)
	_add_outline(hilt, hilt.polygon, Color("#14161E"), 0.75)

	parent_node.add_child(node)
	existing_list.append(node)
	_lodged_weapon_visuals[zone] = existing_list


func _detach_lodged_weapon_visual(zone: StringName) -> void:
	if not _lodged_weapon_visuals.has(zone):
		return
	var list: Array = _lodged_weapon_visuals[zone] as Array
	if not list.is_empty():
		var last_node: Variant = list.pop_back()
		if last_node is Node and is_instance_valid(last_node as Node):
			(last_node as Node).queue_free()
	if list.is_empty():
		_lodged_weapon_visuals.erase(zone)
	else:
		_lodged_weapon_visuals[zone] = list


func _clear_all_lodged_weapon_visuals() -> void:
	for list_var: Variant in _lodged_weapon_visuals.values():
		if list_var is Array:
			for n_var: Variant in (list_var as Array):
				if n_var is Node and is_instance_valid(n_var as Node):
					(n_var as Node).queue_free()
	_lodged_weapon_visuals.clear()


func get_lodged_visual_count(zone: StringName = &"") -> int:
	if zone != &"":
		if not _lodged_weapon_visuals.has(zone):
			return 0
		return (_lodged_weapon_visuals[zone] as Array).size()
	var total: int = 0
	for list_var: Variant in _lodged_weapon_visuals.values():
		if list_var is Array:
			total += (list_var as Array).size()
	return total


func _update_block_arc_visual() -> void:
	if block_arc_line == null:
		return
	var show_arc: bool = is_alive() and combat_state == CombatState.IDLE and (is_blocking or is_in_parry_window())
	block_arc_line.visible = show_arc
	if not show_arc:
		return
	block_arc_line.rotation = aim_angle
	if is_in_parry_window():
		block_arc_line.default_color = Color(1.0, 0.88, 0.35, 0.85)
		block_arc_line.width = 3.0
	elif is_unarmed():
		block_arc_line.default_color = Color(1.0, 0.60, 0.40, 0.48)
		block_arc_line.width = 2.0
	else:
		block_arc_line.default_color = Color(0.55, 0.82, 1.0, 0.58)
		block_arc_line.width = 2.6


func _refresh_status_tint() -> void:
	if body_visual == null or not is_alive():
		return
	body_visual.rotation = 0.0
	if anatomy != null and anatomy.is_unconscious:
		body_visual.modulate = Color(0.7, 0.7, 0.85, 0.85)
	elif is_hardening_active():
		body_visual.modulate = Color(0.75, 0.88, 1.15, 1.0)
	elif is_prone():
		body_visual.modulate = Color(0.85, 0.75, 0.65, 0.92)
	elif is_crouching:
		var arena_c: TestArena = _find_arena()
		var in_cover: bool = arena_c != null and arena_c.is_entity_in_stealth_cover(self)
		body_visual.modulate = Color(0.60, 0.74, 0.66, 0.80) if in_cover else Color(0.76, 0.82, 0.88, 0.90)
	else:
		body_visual.modulate = Color.WHITE
	_apply_procedural_pose()


## Computes balanced kinetic multiplier respecting TempoMode, speed_regulator, tp_penalty_mult & dash state.
## - Walking / running (WASD, not dashing): modest 1.0..1.35x momentum bonus (eliminates WASD 100x-2500x exploit).
## - PEACEFUL / PATROL (effective SPD <= 10): strictly capped <= 1.35x even during dashes.
## - True high-speed dash/charge in COMBAT_OVERDRIVE: scales smoothly up toward (eff_SPD/10)^2.
func get_kinetic_mult(
	action_speed_px_per_sec: float,
	is_dashing: bool = false,
	forward_alignment: float = 1.0
) -> float:
	if stat_sheet == null or action_speed_px_per_sec <= 20.0:
		return 1.0
	var align: float = clampf(forward_alignment, 0.0, 1.0)
	if align <= 0.05:
		return 1.0

	var eff_spd: float = get_effective_world_spd()
	var is_high_speed_charge: bool = is_dashing or action_speed_px_per_sec > BASE_RUN_SPEED_PX * 1.15

	# Normal step / run without dash-charge: strictly bounded to [1.0, 1.35]
	var run_t: float = clampf((action_speed_px_per_sec - 50.0) / (BASE_RUN_SPEED_PX - 50.0), 0.0, 1.0)
	var spd_log_bonus: float = clampf(log(maxf(1.0, eff_spd / StatSheet.HUMAN_REFERENCE)) / log(10.0), 0.0, 1.0)
	var run_mult: float = 1.0 + run_t * (0.15 + 0.20 * spd_log_bonus) * align
	if not is_high_speed_charge:
		return clampf(run_mult, 1.0, 1.35)

	# In PEACEFUL or PATROL (eff_spd <= 10): even a dash stays strictly <= 1.35x
	if eff_spd <= StatSheet.HUMAN_REFERENCE + 1e-4:
		return clampf(1.0 + 0.35 * align, 1.0, 1.35)

	# Real high-speed dash/charge in COMBAT_OVERDRIVE -> scales toward (eff_spd / 10)^2
	var dash_t: float = clampf(
		(action_speed_px_per_sec - BASE_RUN_SPEED_PX) / maxf(1.0, BASE_DASH_SPEED_PX - BASE_RUN_SPEED_PX),
		0.0,
		1.0
	)
	if is_dashing:
		dash_t = maxf(dash_t, 0.25)
	var full_kin: float = maxf(1.35, pow(eff_spd / StatSheet.HUMAN_REFERENCE, 2.0))
	var charge_mult: float = lerpf(run_mult, full_kin, dash_t * align)
	return maxf(1.0, charge_mult)


# ---------------------------------------------------------------------------
# Receiving Melee Hits (Deflect -> Block -> Dodge -> Hardening/Penetration -> Anatomy + Knockback)
# ---------------------------------------------------------------------------

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
	if not is_alive() or attacker == null or zone == null or weapon == null:
		return {"outcome": "ignored"}

	# 1. Deflect / Parry check (0.18s subjective window within front ~220 deg sector -> deflect + stagger attacker)
	if is_in_parry_window() and is_attack_within_front_arc(attacker, PARRY_FRONT_HALF_ANGLE_DEG):
		parry_window_timer = 0.0
		_update_block_arc_visual()
		attacker.apply_stagger(1.1)
		var push_dir: Vector2 = (attacker.global_position - global_position).normalized()
		attacker.move_with_substepping(push_dir * 260.0, 0.08, false, false)
		if SimulationClock != null:
			SimulationClock.trigger_hitstop(0.04, self, attacker)
		var parry_bus: Node = _get_event_bus()
		if parry_bus != null:
			if parry_bus.has_method("request_sparks"):
				parry_bus.call("request_sparks", get_combat_origin(), get_floor_level(), get_height_z(), Color("#FFE875"), 8)
			if parry_bus.has_method("request_camera_shake"):
				parry_bus.call("request_camera_shake", 3.0, 0.14)
			if parry_bus.has_method("emit_noise"):
				parry_bus.call("emit_noise", global_position, get_floor_level(), 170.0, self)
		parry_succeeded.emit(attacker)
		trigger_hitflash(Color(1.9, 1.75, 0.85, 1.0), 0.08)
		trigger_squash(Vector2(1.10, 0.92))
		trigger_screen_flash(Color(1.0, 0.92, 0.45, 0.55), 0.15)
		_emit_combat_outcome(attacker, zone.zone_name, "parried", is_weak_point, null, false)
		print("[%s] PARRIED %s! Attacker staggered." % [actor_display_name, attacker.actor_display_name])
		return {"outcome": "parried"}

	# 2. Directional Active Block check (front +/-75 deg = 150 deg arc; flank/rear, Counter & stealth ambush bypass hold-Block!)
	#    Unarmed passive block against steel/blunt weapons has high STA cost, lower capacity,
	#    and sharp blades bleed-through onto an intact forearm (LeftArm / RightArm) instead of free stopping.
	var attacker_stealthed: bool = attacker.is_in_stealth_stance()
	var stealth_ambush_active: bool = attacker_is_stealth_backstab and attacker_stealthed
	var guard_broken: bool = false
	if (
		is_blocking
		and not attacker_is_counter
		and not stealth_ambush_active
		and current_stamina > 0.0
		and combat_state == CombatState.IDLE
		and is_attack_within_front_arc(attacker, BLOCK_FRONT_HALF_ANGLE_DEG)
	):
		var atk_str: float = attacker.stat_sheet.get_stat(StatSheet.Stat.STR)
		var atk_m_ctrl: float = attacker.stat_sheet.get_stat(StatSheet.Stat.M_CTRL) if attacker.stat_sheet.mana_awakened else 0.0
		var atk_aura_b: PenetrationResolver.AuraBonuses = PenetrationResolver.calculate_aura_bonuses(attacker_aura, atk_m_ctrl, attacker_aura_burst)
		var incoming_impulse: float = PenetrationResolver.calculate_blunt_impulse(weapon.mass_factor, atk_str, kinetic_mult, atk_aura_b.impact_bonus)

		var def_str: float = stat_sheet.get_stat(StatSheet.Stat.STR)
		var unarmed_vs_weapon: bool = is_unarmed() and not weapon.is_unarmed
		var def_weapon_mass: float = 2.0 if unarmed_vs_weapon else (equipped_weapon.mass_factor if equipped_weapon != null else 4.0)
		var block_capacity: float = maxf(25.0, (def_weapon_mass + 12.0) * pow(def_str / 10.0, 2.0) * 1.5)
		var sta_drain: float = stat_sheet.get_effective_stamina_cost(clampf(incoming_impulse * 0.45, 8.0, 120.0), false)
		if unarmed_vs_weapon:
			block_capacity = maxf(12.0, (def_weapon_mass + 8.0) * pow(def_str / 10.0, 2.0) * 0.85)
			sta_drain *= 1.75

		if not atk_aura_b.is_burst and current_stamina >= sta_drain and incoming_impulse <= block_capacity:
			current_stamina -= sta_drain
			if unarmed_vs_weapon and weapon.edge_sharpness > 0.5 and attack_type != PenetrationResolver.AttackType.BLUNT:
				var arm_zone: StringName = _pick_intact_arm_zone()
				var arm_hz: HitboxZone = _find_hitbox_zone_by_name(arm_zone)
				var arm_atk: PenetrationResolver.AttackParams = PenetrationResolver.AttackParams.new()
				arm_atk.attacker_str = atk_str
				arm_atk.attacker_m_ctrl = atk_m_ctrl
				arm_atk.weapon_base_penetration = weapon.base_penetration * UNARMED_BLOCK_SHARP_PEN_MULT * (0.5 if weapon.is_broken() else 1.0)
				arm_atk.weapon_blade_length = weapon.blade_length
				arm_atk.edge_sharpness = 0.2 if weapon.is_broken() else weapon.edge_sharpness
				arm_atk.weapon_mass_factor = weapon.mass_factor
				arm_atk.kinetic_mult = kinetic_mult
				arm_atk.aura_active = attacker_aura
				arm_atk.is_weak_point = false
				arm_atk.attacker_height_z = attacker.get_height_z()
				arm_atk.weapon_vertical_reach = weapon.vertical_reach
				arm_atk.attack_type = PenetrationResolver.AttackType.SLASH
				arm_atk.anti_regen = anti_regen

				var arm_def: PenetrationResolver.DefenseParams = arm_hz.build_defense_params() if arm_hz != null else zone.build_defense_params()
				# Bare forearm guard has lowered tissue/CON & armor barrier when catching a sharp steel edge by hand
				arm_def.base_anatomy_thickness *= UNARMED_BLOCK_ARM_BARRIER_MULT
				arm_def.target_con *= 0.55
				arm_def.armor_thickness *= 0.25
				arm_def.armor_hardness *= 0.25
				var arm_res: PenetrationResolver.ResolutionResult = PenetrationResolver.resolve(arm_atk, arm_def, true, true)
				var arm_cushion: float = arm_hz.armor_cushion_mult if arm_hz != null else 1.0
				var arm_wound: Dictionary = anatomy.apply_penetration_result(arm_zone, arm_res, arm_cushion, attacker, weapon, null)
				if arm_res.penetrated:
					trigger_hitflash(Color(2.3, 1.6, 1.6, 1.0))
					trigger_squash(Vector2(1.14, 0.88))
				var cut_bus: Node = _get_event_bus()
				if cut_bus != null and arm_res.penetrated and cut_bus.has_method("request_blood"):
					var cut_dir: Vector2 = (global_position - attacker.global_position).normalized()
					cut_bus.call("request_blood", global_position, get_floor_level(), cut_dir, 0.8, false)
				_emit_combat_outcome(attacker, arm_zone, "unarmed_block_cut", false, arm_res, false)
				print("[%s] UNARMED BLOCK bled through onto %s (STA -%.1f, depth=%.1f)!" % [actor_display_name, String(arm_zone), sta_drain, arm_res.effective_depth])
				return {
					"outcome": "unarmed_block_cut",
					"stamina_drained": sta_drain,
					"arm_zone": arm_zone,
					"resolution": arm_res,
					"wound_summary": arm_wound,
				}
			var blk_bus: Node = _get_event_bus()
			if blk_bus != null:
				if blk_bus.has_method("request_sparks"):
					blk_bus.call("request_sparks", get_combat_origin(), get_floor_level(), get_height_z(), Color("#F8F9FA"), 5)
				if blk_bus.has_method("emit_noise"):
					blk_bus.call("emit_noise", global_position, get_floor_level(), 140.0, self)
			_emit_combat_outcome(attacker, zone.zone_name, "blocked", is_weak_point, null, false)
			print("[%s] BLOCKED %s (STA -%.1f)." % [actor_display_name, attacker.actor_display_name, sta_drain])
			return {"outcome": "blocked", "stamina_drained": sta_drain}
		else:
			guard_broken = true
			current_stamina = 0.0
			if equipped_weapon != null:
				equipped_weapon.apply_wear(0.08, 0.0, aura_active)
			apply_stagger(0.8)
			print("[%s] GUARD BROKEN by %s!" % [actor_display_name, attacker.actor_display_name])

	# 3. Instinctive Auto-Dodge (AGI, GDD 3.2 #4; skipped while bracing with Hardening, Prone, or surprised by stealth ambush unless TP/SPD >= 2.0)
	var allow_instinct_dodge: bool = not stealth_ambush_active or can_instinct_dodge_stealth_ambush(attacker)
	if enable_instinct_dodge and allow_instinct_dodge and can_act() and not is_hardening_active() and stat_sheet != null:
		var dodge_chance: float = stat_sheet.get_instinct_dodge_chance(attacker.stat_sheet.get_stat(StatSheet.Stat.SPD))
		if randf() < dodge_chance:
			_emit_combat_outcome(attacker, zone.zone_name, "dodged", is_weak_point, null)
			print("[%s] Instinctively dodged %s (AGI chance %.1f%%)!" % [actor_display_name, attacker.actor_display_name, dodge_chance * 100.0])
			return {"outcome": "dodged"}

	# 4. Layered 4-Barrier PenetrationResolver calculation (GDD 12.2)
	var atk_params: PenetrationResolver.AttackParams = PenetrationResolver.AttackParams.new()
	atk_params.attacker_str = attacker.stat_sheet.get_stat(StatSheet.Stat.STR)
	atk_params.attacker_m_ctrl = attacker.stat_sheet.get_stat(StatSheet.Stat.M_CTRL) if attacker.stat_sheet.mana_awakened else 0.0
	atk_params.weapon_base_penetration = weapon.base_penetration * (0.5 if weapon.is_broken() else 1.0) * (COUNTER_PENETRATION_MULT if attacker_is_counter else 1.0)
	atk_params.weapon_blade_length = weapon.blade_length
	atk_params.edge_sharpness = 0.2 if weapon.is_broken() else weapon.edge_sharpness
	atk_params.weapon_mass_factor = weapon.mass_factor
	atk_params.kinetic_mult = kinetic_mult
	atk_params.aura_active = attacker_aura
	atk_params.aura_burst = attacker_aura_burst
	atk_params.is_weak_point = is_weak_point
	atk_params.attacker_height_z = attacker.get_height_z()
	atk_params.weapon_vertical_reach = weapon.vertical_reach
	atk_params.attack_type = attack_type
	if attack_type != PenetrationResolver.AttackType.STANDARD:
		atk_params.type_pierce_mult_override = weapon.get_type_pierce_mult(attack_type)
		atk_params.slash_sever_mult = weapon.slash_sever_mult
		atk_params.blunt_impulse_mult = weapon.blunt_impulse_mult
	atk_params.distance_to_target = distance_to_target
	atk_params.min_optimal_range = weapon.min_optimal_range
	atk_params.can_half_sword = weapon.can_half_sword
	atk_params.half_swording = attacker_half_swording
	atk_params.anti_regen = anti_regen

	var def_params: PenetrationResolver.DefenseParams = zone.build_defense_params()
	var hardened_hit: bool = is_hardening_active()
	if hardened_hit:
		def_params.hardening_bonus = hardening_bonus_value

	var res: PenetrationResolver.ResolutionResult = PenetrationResolver.resolve(atk_params, def_params, true, true)

	# Weapon dulling if stopped by hard barrier without Aura
	if not res.penetrated and (res.armor_barrier > 0.0 or res.barrier_depth >= 100.0 or hardened_hit):
		weapon.apply_wear(0.08 if hardened_hit else 0.06, attacker.stat_sheet.get_extra_weapon_wear_mult(), attacker_aura or attacker_aura_burst)
	if (attacker_aura or attacker_aura_burst) and (res.armor_barrier > 0.0 or res.barrier_depth >= 100.0):
		attacker._spend_aura_heavy_hit_mp()

	# Hardening bounce: non-penetrating hit rebounds off hardened tissues and staggers attacker!
	if hardened_hit and not res.penetrated:
		trigger_hitflash(Color(1.2, 1.7, 2.3, 1.0), 0.08)
		trigger_squash(Vector2(1.12, 0.90))
		attacker.apply_stagger(0.75)
		if SimulationClock != null:
			SimulationClock.trigger_hitstop(0.04, self, attacker)
		var hb_bus: Node = _get_event_bus()
		if hb_bus != null:
			if hb_bus.has_method("request_sparks"):
				hb_bus.call("request_sparks", get_combat_origin(), get_floor_level(), get_height_z(), Color("#74B9FF"), 8)
			if hb_bus.has_method("request_camera_shake"):
				hb_bus.call("request_camera_shake", 3.2, 0.14)
	elif not res.penetrated and res.armor_barrier > 0.0:
		var ab_bus: Node = _get_event_bus()
		if ab_bus != null and ab_bus.has_method("request_sparks"):
			ab_bus.call("request_sparks", get_combat_origin(), get_floor_level(), get_height_z(), Color("#FFD166"), 5)

	# 5. Apply 4-layer Damage-to-Wound through AnatomyComponent (and EventBus.damage_pipeline)
	var wound_summary: Dictionary = anatomy.apply_penetration_result(
		zone.zone_name,
		res,
		zone.armor_cushion_mult,
		attacker,
		weapon,
		equipped_weapon
	)
	if res.penetrated or bool(wound_summary.get("fractured", false)) or res.blunt_impulse > 15.0:
		trigger_hitflash(Color(2.35, 2.15, 2.15, 1.0))
		trigger_squash(Vector2(1.18, 0.84))
	elif res.armor_barrier > 0.0:
		trigger_squash(Vector2(1.08, 0.94))

	# Hardening / dense muscle lodged blade genuinely disarms attacker into target's tissue & staggers!
	if bool(wound_summary.get("weapon_lodged", false)):
		attacker.disarm_weapon_into_target(weapon)
		attacker.apply_stagger(0.65)
		if SimulationClock != null:
			SimulationClock.trigger_hitstop(0.05, self, attacker)

	# 6. Physical Knockback & Wall Slam eligibility on heavy/blunt/Aura Burst hits
	var hit_dir: Vector2 = (global_position - attacker.global_position).normalized()
	if hit_dir.length_squared() <= 0.001:
		hit_dir = Vector2.from_angle(attacker.aim_angle)
	var caused_knockback: bool = false
	if res.wall_slam_impulse >= WALL_SLAM_MIN_IMPULSE and (attack_type == PenetrationResolver.AttackType.BLUNT or res.aura_burst or bool(wound_summary.get("fractured", false))):
		apply_knockback(hit_dir, res.wall_slam_impulse, attacker)
		caused_knockback = true

	# Hitstop, Blood Spray & Camera Shake on penetrating / critical impact
	var fx_bus: Node = _get_event_bus()
	if fx_bus != null:
		if res.penetrated and fx_bus.has_method("request_blood"):
			fx_bus.call("request_blood", global_position, get_floor_level(), hit_dir, clampf(res.effective_depth / 12.0, 0.7, 2.2), false)
		if fx_bus.has_method("emit_noise"):
			var hit_noise_r: float = 160.0 if res.penetrated else 120.0
			if stealth_ambush_active and not caused_knockback:
				hit_noise_r = STEALTH_DAGGER_HIT_NOISE_PX if (weapon.weapon_id == &"dagger" or weapon.mass_factor <= 6.0) else 85.0
			fx_bus.call("emit_noise", global_position, get_floor_level(), hit_noise_r, attacker)
		if (res.severed or res.aura_burst or bool(wound_summary.get("fractured", false)) or (res.is_weak_point and res.penetrated)) and fx_bus.has_method("request_camera_shake"):
			fx_bus.call("request_camera_shake", 4.8 if (res.severed or res.aura_burst) else 2.8, 0.16)
	if SimulationClock != null and (res.severed or bool(wound_summary.get("fractured", false)) or res.aura_burst or (res.is_weak_point and res.penetrated)):
		var hs_dur: float = 0.06 if (res.severed or res.aura_burst) else 0.04
		SimulationClock.trigger_hitstop(hs_dur, attacker, self)

	# 7. Poise & Stagger
	if is_alive():
		var poise_dmg: float = weapon.poise_damage * (1.5 if is_weak_point else 1.0) * (1.5 if res.aura_burst else 1.0)
		current_poise = maxf(0.0, current_poise - poise_dmg)
		if current_poise <= 0.0:
			apply_stagger(0.8)

	attacker.hit_landed.emit(self, zone.zone_name, res)
	var outcome_label: String = "penetrated" if res.penetrated else "no_penetration"
	if guard_broken:
		outcome_label = "guard_break_hit"
	elif res.severed:
		outcome_label = "dismembered"
	elif bool(wound_summary.get("weapon_lodged", false)):
		outcome_label = "hardening_lodged" if hardened_hit else "weapon_lodged"
	elif hardened_hit and not res.penetrated:
		outcome_label = "hardening_bounce"

	_emit_combat_outcome(attacker, zone.zone_name, outcome_label, is_weak_point, res, attacker_is_stealth_backstab)
	print(
		"[Combat] %s -> %s [%s%s] pen=%.1f vs bar=%.1f => depth=%.1f, blunt=%.1f | blood=%.0f%%, shock=%.0f%%" % [
			attacker.actor_display_name,
			actor_display_name,
			String(zone.zone_name),
			" WEAK-POINT" if is_weak_point else "",
			res.penetration,
			res.barrier_depth,
			res.effective_depth,
			res.blunt_impulse,
			anatomy.get_blood_ratio() * 100.0,
			anatomy.shock_level,
		]
	)
	return {
		"outcome": outcome_label,
		"resolution": res,
		"wound_summary": wound_summary,
		"is_stealth_backstab": attacker_is_stealth_backstab,
	}


func _pick_intact_arm_zone() -> StringName:
	if anatomy != null:
		if not anatomy.is_limb_severed(AnatomyComponent.ZONE_LEFT_ARM):
			return AnatomyComponent.ZONE_LEFT_ARM
		if not anatomy.is_limb_severed(AnatomyComponent.ZONE_RIGHT_ARM):
			return AnatomyComponent.ZONE_RIGHT_ARM
	return AnatomyComponent.ZONE_LEFT_ARM


func _find_hitbox_zone_by_name(z_name: StringName) -> HitboxZone:
	for hz: HitboxZone in hitbox_zones:
		if is_instance_valid(hz) and hz.zone_name == z_name:
			return hz
	return null


func revive_and_heal_all() -> void:
	if anatomy != null:
		anatomy.reset_anatomy()
	combat_state = CombatState.IDLE
	state_timer = 0.0
	is_blocking = false
	parry_window_timer = 0.0
	current_attack_aura_burst = false
	current_attack_is_counter = false
	hardening_timer = 0.0
	hardening_cooldown_timer = 0.0
	hardening_bonus_value = 0.0
	prone_timer = 0.0
	counter_window_timer = 0.0
	is_crouching = false
	_crouch_visual_scale = 1.0
	_bush_rustle_timer = 0.0
	if verticality != null:
		verticality.visual_stance_scale = 1.0
	knockback_velocity = Vector2.ZERO
	knockback_impulse = 0.0
	knockback_timer = 0.0
	_recent_move_velocity = Vector2.ZERO
	_recent_move_was_dash = false
	_recent_move_timer = 0.0
	_attack_launch_velocity = Vector2.ZERO
	_attack_launch_was_dash = false
	if body_visual != null:
		body_visual.modulate = Color.WHITE
		body_visual.rotation = 0.0
	if visual_rig != null:
		visual_rig.position = Vector2.ZERO
		visual_rig.rotation = 0.0
		visual_rig.scale = Vector2.ONE
		visual_rig.modulate = Color.WHITE
	_squash_scale = Vector2.ONE
	_hitflash_timer = 0.0
	walk_cycle_phase = 0.0
	_walk_blend = 0.0
	_clear_all_lodged_weapon_visuals()
	if weapon_pivot != null:
		weapon_pivot.position = Vector2.ZERO
	_update_block_arc_visual()
	for lpoly: Polygon2D in limb_polygons.values():
		if is_instance_valid(lpoly):
			lpoly.visible = true
			lpoly.scale = Vector2.ONE
	for stump_n: Node2D in stump_nodes.values():
		if is_instance_valid(stump_n):
			stump_n.visible = false
	for hz: HitboxZone in hitbox_zones:
		if is_instance_valid(hz):
			hz.set_active(true)
	if verticality != null:
		verticality.sync_all()
	if equipped_weapon == null and _initial_weapon_backup != null:
		equipped_weapon = _initial_weapon_backup.create_runtime_copy()
	if equipped_weapon != null:
		equipped_weapon.edge_sharpness = equipped_weapon.max_edge_sharpness
		equipped_weapon.durability = equipped_weapon.max_durability
	if has_wings:
		if anatomy != null:
			anatomy.add_optional_zone(AnatomyComponent.ZONE_WINGS)
		_ensure_wings_hitbox_zone()
	refresh_weapon_visual()
	refill_resources()
	_sync_flight_stat_tags_and_visuals()
	_apply_procedural_pose()


func _emit_combat_outcome(
	attacker: CombatActor,
	zone_name: StringName,
	outcome: String,
	is_weak_point: bool,
	res: PenetrationResolver.ResolutionResult,
	is_stealth_backstab: bool = false
) -> void:
	var bus: Node = _get_event_bus()
	if bus == null or not bus.has_method("publish_combat_outcome"):
		return
	var payload: Dictionary = {
		"attacker": attacker,
		"attacker_name": attacker.actor_display_name if attacker != null else "",
		"target": self,
		"target_name": actor_display_name,
		"zone": zone_name,
		"outcome": outcome,
		"is_weak_point": is_weak_point,
		"is_stealth_backstab": is_stealth_backstab,
		"resolution": res.to_dict() if res != null else {},
	}
	bus.call("publish_combat_outcome", payload)


func _get_event_bus() -> Node:
	if is_inside_tree() and get_tree().root != null:
		return get_tree().root.get_node_or_null("EventBus")
	return null


func trigger_screen_flash(_color: Color, _duration: float = 0.15) -> void:
	pass


# ---------------------------------------------------------------------------
# Physical Knockback, Wall Slam & Breakable Floor Drop (GDD 7.3, 14.5)
# ---------------------------------------------------------------------------

func apply_knockback(direction: Vector2, impulse: float, source: CombatActor = null) -> void:
	if impulse <= 0.0:
		return
	var dir: Vector2 = direction.normalized()
	if dir.length_squared() <= 0.001:
		dir = Vector2.RIGHT
	var speed: float = clampf(180.0 + sqrt(impulse) * 26.0, 180.0, 1800.0) / maxf(0.5, actor_size_mult)
	var dur: float = clampf(0.14 + log(1.0 + impulse / 60.0) * 0.08, 0.14, 0.45)
	knockback_velocity = dir * speed
	knockback_impulse = impulse
	knockback_timer = dur
	knockback_source = source
	if not is_alive() and FloorLayerManager != null:
		collision_mask = FloorLayerManager.get_high_walls_bit(get_floor_level())


func step_knockback(dt: float) -> Dictionary:
	var report: Dictionary = {
		"moved_px": 0.0,
		"wall_slammed": false,
		"wall_broken": false,
		"wall_cell": Vector2i.ZERO,
		"fell_through_floor": false,
	}
	if knockback_timer <= 0.0 or dt <= 0.0 or knockback_velocity.length_squared() <= 1e-4:
		return report

	var step_time: float = minf(dt, knockback_timer)
	knockback_timer = maxf(0.0, knockback_timer - step_time)

	var start_pos: Vector2 = global_position
	var remaining: Vector2 = knockback_velocity * step_time
	var iterations: int = 0
	var arena: TestArena = _find_arena()

	while remaining.length() > 0.001 and iterations < MAX_SUBSTEP_ITERATIONS:
		iterations += 1
		var step: Vector2 = remaining
		if step.length() > MAX_SUBSTEP_PX:
			step = step.normalized() * MAX_SUBSTEP_PX

		var collision: KinematicCollision2D = move_and_collide(step)
		if collision != null:
			var collider_obj: Object = collision.get_collider()
			if collider_obj is TileMapLayer and arena != null:
				var wall_cell: Vector2i = arena.world_to_cell(collision.get_position() - collision.get_normal() * 2.0)
				var slam_impulse: float = knockback_impulse
				var wall_force: float = slam_impulse / WALL_SLAM_IMPULSE_DIVISOR

				# Wall Slam trauma bypasses front armor & shield (hits spine/back and occiput!)
				if anatomy != null and is_alive() and slam_impulse >= WALL_SLAM_MIN_IMPULSE:
					anatomy.apply_blunt_hit(AnatomyComponent.ZONE_CHEST, slam_impulse, 1.0, 1.0, true)
					if slam_impulse > anatomy.get_effective_bone_density() * 1.2:
						anatomy.apply_blunt_hit(AnatomyComponent.ZONE_HEAD, slam_impulse * 0.75, 1.0, 0.5, true)
					apply_stagger(0.9)

				var wall_dmg: float = maxf(10.0, slam_impulse * 0.12)
				var wall_res: Dictionary = arena.try_damage_wall_at(get_floor_level(), wall_cell, wall_force, wall_dmg, false)
				var wall_broken: bool = bool(wall_res.get("destroyed", false))
				report["wall_slammed"] = true
				report["wall_broken"] = bool(report["wall_broken"]) or wall_broken
				report["wall_cell"] = wall_cell
				last_wall_slam_report = report.duplicate()

				if SimulationClock != null:
					SimulationClock.trigger_hitstop(0.05, knockback_source, self)
				var bus: Node = _get_event_bus()
				if bus != null and bus.has_method("publish_wall_slam"):
					bus.call("publish_wall_slam", self, wall_cell, slam_impulse, wall_broken)
				wall_slam_occurred.emit(wall_cell, slam_impulse, wall_broken)

				var leftover: Vector2 = collision.get_remainder()
				var tail: Vector2 = remaining - step
				if wall_broken:
					# Body smashes straight through wall into next room with reduced momentum
					knockback_velocity *= 0.65
					knockback_impulse *= 0.60
					remaining = (leftover + tail) * 0.65
				else:
					knockback_timer = 0.0
					knockback_velocity = Vector2.ZERO
					knockback_impulse = 0.0
					break
			else:
				remaining = (collision.get_remainder() + (remaining - step)).slide(collision.get_normal())
		else:
			remaining -= step

		# Upper-floor drop check: breakable floor smash on heavy slam OR falling into an open hole
		if arena != null and get_floor_level() >= 1:
			var before_floor: int = get_floor_level()
			var cur_cell: Vector2i = arena.world_to_cell(global_position)
			var floor_force: float = knockback_impulse / WALL_SLAM_IMPULSE_DIVISOR
			if floor_force >= 15.0:
				var floor_dmg: float = maxf(10.0, knockback_impulse * 0.12)
				arena.try_break_floor_at(before_floor, cur_cell, floor_force, false, floor_dmg)
			var fell_now: bool = get_floor_level() < before_floor
			if not fell_now:
				var fall_info: Dictionary = arena.check_entity_floor_support(self)
				fell_now = bool(fall_info.get("fell", false))
			if fell_now:
				report["fell_through_floor"] = true
				knockback_timer = 0.0
				knockback_velocity = Vector2.ZERO
				break

	if knockback_timer <= 0.0:
		knockback_velocity = Vector2.ZERO
		knockback_impulse = 0.0
		knockback_source = null
		if not is_alive():
			collision_mask = 0

	report["moved_px"] = start_pos.distance_to(global_position)
	return report


# ---------------------------------------------------------------------------
# Physics Sub-stepping (<= 16 px per step) + Anti-Tunneling Area2D Sweep (GDD 12.1)
# ---------------------------------------------------------------------------

func move_with_substepping(vel: Vector2, action_delta: float, is_dashing: bool = false, allow_wall_ramming: bool = true) -> void:
	current_move_velocity = vel
	if vel.length_squared() > 100.0:
		_recent_move_velocity = vel
		_recent_move_was_dash = is_dashing
		_recent_move_timer = APPROACH_MOMENTUM_WINDOW_SEC
	if action_delta <= 0.0 or vel.length_squared() <= 1e-6:
		return

	var remaining: Vector2 = vel * action_delta
	var iterations: int = 0
	var arena: TestArena = _find_arena()
	var world_2d: World2D = get_world_2d()
	var space_state: PhysicsDirectSpaceState2D = world_2d.direct_space_state if world_2d != null else null
	var area_mask: int = (
		FloorLayerManager.BIT_INTERACTABLES
		| FloorLayerManager.BIT_TRIGGERS_STEALTH
		| FloorLayerManager.BIT_FLOOR_SUPPORT
		| FloorLayerManager.BIT_MIND_DOMAINS
	)
	last_antitunnel_areas.clear()

	while remaining.length() > 0.001 and iterations < MAX_SUBSTEP_ITERATIONS:
		iterations += 1
		var step: Vector2 = remaining
		if step.length() > MAX_SUBSTEP_PX:
			step = step.normalized() * MAX_SUBSTEP_PX

		var prev_pos: Vector2 = global_position
		var collision: KinematicCollision2D = move_and_collide(step)

		if space_state != null and prev_pos.distance_squared_to(global_position) > 0.01:
			var ray_q: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(prev_pos, global_position, area_mask)
			ray_q.collide_with_areas = true
			ray_q.collide_with_bodies = false
			var ray_hit: Dictionary = space_state.intersect_ray(ray_q)
			if not ray_hit.is_empty():
				var area_obj: Object = ray_hit.get("collider", null)
				if area_obj is Area2D and not last_antitunnel_areas.has(area_obj as Area2D):
					last_antitunnel_areas.append(area_obj as Area2D)

		if collision != null:
			# High-speed / dash ramming through destructible walls (GDD 12.1, 14.5)
			# Strictly disabled in PEACEFUL TempoMode, and respects speed_regulator & tp_penalty_mult!
			var rammed_through: bool = false
			var tempo_allows_ram: bool = SimulationClock == null or SimulationClock.is_wall_ramming_allowed()
			var reg_mult: float = 1.0
			if is_in_group(&"player") and SimulationClock != null:
				reg_mult = SimulationClock.speed_regulator * SimulationClock.get_tp_penalty_mult()
			var world_speed_est: float = vel.length() * (stat_sheet.get_move_speed_mult() if stat_sheet != null else 1.0) * reg_mult
			if allow_wall_ramming and tempo_allows_ram and arena != null and (world_speed_est >= WALL_RAM_MIN_SPEED_PX or is_dashing):
				var collider_obj: Object = collision.get_collider()
				if collider_obj is TileMapLayer:
					var wall_cell: Vector2i = arena.world_to_cell(collision.get_position() - collision.get_normal() * 2.0)
					var ram_str: float = stat_sheet.get_stat(StatSheet.Stat.STR)
					var ram_speed_mult: float = clampf(world_speed_est / WALL_RAM_MIN_SPEED_PX, 1.0, 4.0)
					var ram_dmg: float = ram_str * 0.85 * ram_speed_mult * (1.5 if aura_active else 1.0)
					var ram_res: Dictionary = arena.try_damage_wall_at(
						get_floor_level(),
						wall_cell,
						ram_str,
						ram_dmg,
						aura_active
					)
					if bool(ram_res.get("destroyed", false)):
						rammed_through = true
						print("[%s] Rammed through %s wall at %s!" % [actor_display_name, String(ram_res.get("material_type", "")), str(wall_cell)])

			var leftover_step: Vector2 = collision.get_remainder()
			var unconsumed_tail: Vector2 = remaining - step
			if rammed_through:
				remaining = leftover_step + unconsumed_tail
			else:
				remaining = (leftover_step + unconsumed_tail).slide(collision.get_normal())
		else:
			remaining -= step

		if arena != null and get_floor_level() >= 1:
			var fall_info: Dictionary = arena.check_entity_floor_support(self)
			if bool(fall_info.get("fell", false)):
				break

	if arena != null and not last_antitunnel_areas.is_empty():
		arena.handle_antitunnel_areas(self, last_antitunnel_areas)

	# Footstep / dash / stealth roll acoustic signal for enemy hearing sensory checks (GDD 7.4)
	var move_speed_px: float = vel.length()
	var step_noise_r: float = get_movement_noise_radius(is_dashing, move_speed_px)
	if step_noise_r > 0.0:
		_footstep_noise_timer += action_delta
		if is_dashing or _footstep_noise_timer >= 0.45:
			_footstep_noise_timer = 0.0
			var n_bus: Node = _get_event_bus()
			if n_bus != null and n_bus.has_method("emit_noise"):
				n_bus.call("emit_noise", global_position, get_floor_level(), step_noise_r, self)

	# Standing rapid run through StealthCoverZone bushes emits light rustling every 0.6s (suppressed in crouch!)
	if arena != null and not is_crouching and not is_flying() and move_speed_px > 150.0 and arena.is_entity_in_stealth_cover(self):
		_bush_rustle_timer += action_delta
		if _bush_rustle_timer >= BUSH_RUSTLE_INTERVAL_SEC:
			_bush_rustle_timer = 0.0
			var b_bus: Node = _get_event_bus()
			if b_bus != null and b_bus.has_method("emit_noise"):
				b_bus.call("emit_noise", global_position, get_floor_level(), BUSH_RUSTLE_NOISE_PX, self)
	else:
		_bush_rustle_timer = 0.0


# ---------------------------------------------------------------------------
# Anatomy Callbacks & Helpers
# ---------------------------------------------------------------------------

func _on_anatomy_died(cause: String, zone: StringName) -> void:
	if is_crouching:
		set_crouch(false)
	if sweeper != null and sweeper.is_swing_active():
		sweeper.end_swing()
	combat_state = CombatState.IDLE
	is_blocking = false
	parry_window_timer = 0.0
	current_attack_aura_burst = false
	current_attack_is_counter = false
	hardening_timer = 0.0
	hardening_bonus_value = 0.0
	set_aura_active(false)
	if verticality != null and verticality.is_flying():
		land_from_flight(false, "died")
	if weapon_pivot != null:
		weapon_pivot.position = Vector2.ZERO
	_update_block_arc_visual()
	_update_flight_visuals()
	if body_visual != null:
		body_visual.modulate = Color(0.45, 0.32, 0.32, 0.72)
		body_visual.rotation = 0.0
	_apply_procedural_pose()
	for hz: HitboxZone in hitbox_zones:
		if is_instance_valid(hz):
			hz.set_active(false)
	collision_layer = 0
	# Keep wall collision bit briefly if corpse is flying from a fatal blunt/Wall Slam knockback!
	if knockback_timer > 0.0 and FloorLayerManager != null:
		collision_mask = FloorLayerManager.get_high_walls_bit(get_floor_level())
	else:
		collision_mask = 0
	print("[%s] DIED (cause=%s, zone=%s)." % [actor_display_name, cause, String(zone)])


func _on_anatomy_knocked_out(reason: String, duration_sec: float) -> void:
	if is_crouching:
		set_crouch(false)
	if sweeper != null and sweeper.is_swing_active():
		sweeper.end_swing()
	combat_state = CombatState.IDLE
	is_blocking = false
	parry_window_timer = 0.0
	current_attack_aura_burst = false
	current_attack_is_counter = false
	if weapon_pivot != null:
		weapon_pivot.position = Vector2.ZERO
	_update_block_arc_visual()
	if verticality != null and verticality.is_flying() and get_flight_mode() != VerticalityComponent.FlightMode.NONE:
		land_from_flight(get_height_z() >= VerticalityComponent.LOW_OBSTACLE_CLEARANCE_Z, "knocked_out")
	if body_visual != null:
		body_visual.modulate = Color(0.7, 0.7, 0.85, 0.85)
		body_visual.rotation = 0.0
	_apply_procedural_pose()
	print("[%s] KNOCKED OUT (reason=%s, duration=%.1fs)." % [actor_display_name, reason, duration_sec])


func _on_anatomy_recovered() -> void:
	_refresh_status_tint()
	print("[%s] Recovered consciousness." % actor_display_name)


func _on_anatomy_weapon_dropped(zone: StringName, _weapon_ref: WeaponData) -> void:
	var dropped: WeaponData = disarm_active_weapon(true, &"tendon_or_sever")
	if dropped != null:
		print("[%s] Dropped %s after %s trauma! (Fell back to Unarmed)" % [actor_display_name, dropped.display_name, String(zone)])


func _on_anatomy_weapon_lodged(zone: StringName, weapon: WeaponData, _attacker: Node) -> void:
	_attach_lodged_weapon_visual(zone, weapon)


func _on_anatomy_weapon_dislodged(zone: StringName, _weapon: WeaponData) -> void:
	_detach_lodged_weapon_visual(zone)


func _on_anatomy_limb_severed(zone: StringName, _attacker: Node) -> void:
	if limb_polygons.has(zone) and is_instance_valid(limb_polygons[zone]):
		limb_polygons[zone].visible = false
	if stump_nodes.has(zone) and is_instance_valid(stump_nodes[zone]):
		stump_nodes[zone].visible = true
	if zone == AnatomyComponent.ZONE_NECK:
		if limb_polygons.has(AnatomyComponent.ZONE_HEAD) and is_instance_valid(limb_polygons[AnatomyComponent.ZONE_HEAD]):
			limb_polygons[AnatomyComponent.ZONE_HEAD].visible = false
		if stump_nodes.has(AnatomyComponent.ZONE_HEAD) and is_instance_valid(stump_nodes[AnatomyComponent.ZONE_HEAD]):
			stump_nodes[AnatomyComponent.ZONE_HEAD].visible = true
	if zone == AnatomyComponent.ZONE_WINGS:
		if wing_visual_root != null:
			wing_visual_root.visible = false
		if is_flying() and get_flight_mode() == VerticalityComponent.FlightMode.WING_FLIGHT:
			land_from_flight(true, "wings_severed")
	if AnatomyComponent.ARM_ZONES.has(zone):
		if get_usable_arm_count() < 2 and half_swording:
			half_swording = false
			half_sword_toggled.emit(false)
			refresh_weapon_visual()
		if has_both_arms_severed():
			is_blocking = false
			parry_window_timer = 0.0
			if sweeper != null and sweeper.is_swing_active():
				sweeper.end_swing()
			if combat_state == CombatState.WINDUP or combat_state == CombatState.ACTIVE:
				combat_state = CombatState.IDLE
				state_timer = 0.0
	_sync_flight_stat_tags_and_visuals()
	_apply_procedural_pose()
	var bus: Node = _get_event_bus()
	if bus != null and bus.has_method("request_camera_shake"):
		bus.call("request_camera_shake", 5.5, 0.22)


func _on_anatomy_limb_regrown(zone: StringName) -> void:
	if limb_polygons.has(zone) and is_instance_valid(limb_polygons[zone]):
		var lpoly: Polygon2D = limb_polygons[zone]
		lpoly.visible = true
		if is_inside_tree() and DisplayServer.get_name() != "headless":
			lpoly.scale = Vector2(0.15, 0.15)
			var tw: Tween = lpoly.create_tween()
			tw.tween_property(lpoly, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			lpoly.scale = Vector2.ONE
	if stump_nodes.has(zone) and is_instance_valid(stump_nodes[zone]):
		stump_nodes[zone].visible = false
	if zone == AnatomyComponent.ZONE_NECK:
		if limb_polygons.has(AnatomyComponent.ZONE_HEAD) and is_instance_valid(limb_polygons[AnatomyComponent.ZONE_HEAD]):
			limb_polygons[AnatomyComponent.ZONE_HEAD].visible = true
			limb_polygons[AnatomyComponent.ZONE_HEAD].scale = Vector2.ONE
		if stump_nodes.has(AnatomyComponent.ZONE_HEAD) and is_instance_valid(stump_nodes[AnatomyComponent.ZONE_HEAD]):
			stump_nodes[AnatomyComponent.ZONE_HEAD].visible = false
	if zone == AnatomyComponent.ZONE_WINGS:
		_update_flight_visuals()
	_sync_flight_stat_tags_and_visuals()
	_apply_procedural_pose()
	print("[%s] Regrew severed %s!" % [actor_display_name, String(zone)])


func _find_arena() -> TestArena:
	if not is_inside_tree():
		return null
	var arenas: Array[Node] = get_tree().get_nodes_in_group(&"test_arena")
	for n: Node in arenas:
		if n is TestArena:
			return n as TestArena
	return null
