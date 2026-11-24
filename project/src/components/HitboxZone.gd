class_name HitboxZone
extends Area2D
## Anatomical Area2D hitbox on Layer 13 (HitboxZones) (GDD Sections 7.1, 12.2, 12.6, 14.3).
## Links a physical body region to its owner's AnatomyComponent, armor barrier parameters,
## and local 1-px virtual weak-point offsets.

@export var zone_name: StringName = AnatomyComponent.ZONE_CHEST
@export var armor_thickness: float = 0.0
@export var armor_hardness: float = 0.0
@export var armor_cushion_mult: float = 1.0
@export var weak_point_offsets: Array[Vector2] = []
@export var show_weak_points: bool = false
@export var weak_point_draw_radius: float = 3.0

var owner_actor: Node2D = null
var anatomy: AnatomyComponent = null
var verticality: VerticalityComponent = null
var stat_sheet: StatSheet = null
var base_anatomy_thickness: float = PenetrationResolver.DEFAULT_BASE_ANATOMY_THICKNESS
var size_mult: float = 1.0


func _ready() -> void:
	collision_layer = FloorLayerManager.BIT_HITBOX_ZONES
	collision_mask = 0
	monitoring = false
	monitorable = true
	if owner_actor == null and get_parent() is Node2D:
		owner_actor = get_parent() as Node2D


static func calculate_armor_cushion_mult(p_thickness: float, p_hardness: float) -> float:
	var armor_score: float = maxf(0.0, p_thickness) * maxf(0.0, p_hardness)
	if armor_score <= 0.0:
		return 1.0
	return 1.0 + clampf(sqrt(armor_score) * 0.035, 0.0, 1.25)


func setup(
	p_owner_actor: Node2D,
	p_anatomy: AnatomyComponent,
	p_verticality: VerticalityComponent,
	p_stat_sheet: StatSheet,
	p_zone_name: StringName,
	p_shape: Shape2D,
	p_local_pos: Vector2 = Vector2.ZERO,
	p_weak_points: Array[Vector2] = [],
	p_armor_thickness: float = 0.0,
	p_armor_hardness: float = 0.0,
	p_size_mult: float = 1.0,
	p_base_anatomy_thickness: float = PenetrationResolver.DEFAULT_BASE_ANATOMY_THICKNESS
) -> void:
	owner_actor = p_owner_actor
	anatomy = p_anatomy
	verticality = p_verticality
	stat_sheet = p_stat_sheet
	zone_name = p_zone_name
	position = p_local_pos
	weak_point_offsets = p_weak_points.duplicate()
	armor_thickness = p_armor_thickness
	armor_hardness = p_armor_hardness
	armor_cushion_mult = calculate_armor_cushion_mult(p_armor_thickness, p_armor_hardness)
	size_mult = p_size_mult
	base_anatomy_thickness = p_base_anatomy_thickness

	collision_layer = FloorLayerManager.BIT_HITBOX_ZONES
	collision_mask = 0
	monitoring = false
	monitorable = true

	var col: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if col == null:
		col = CollisionShape2D.new()
		col.name = "CollisionShape2D"
		add_child(col)
	col.shape = p_shape
	queue_redraw()


func set_active(enabled: bool) -> void:
	monitorable = enabled
	var col: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if col != null:
		col.disabled = not enabled
	visible = enabled


func set_weak_points_visible(visible_flag: bool, radius_px: float = 3.0) -> void:
	show_weak_points = visible_flag
	weak_point_draw_radius = radius_px
	queue_redraw()


func _draw() -> void:
	if not show_weak_points or weak_point_offsets.is_empty():
		return
	# When mounted under VerticalityComponent.hitbox_root, this Area2D is already shifted by -height_z * 45.0.
	# Only apply a manual Y shift if used standalone directly under the unshifted root actor.
	var visual_y_shift: float = 0.0
	if verticality != null and (verticality.hitbox_root == null or get_parent() != verticality.hitbox_root):
		visual_y_shift = -verticality.height_z * VerticalityComponent.VISUAL_Y_OFFSET_PER_Z
	for offset: Vector2 in weak_point_offsets:
		var draw_pos: Vector2 = Vector2(offset.x, offset.y + visual_y_shift)
		draw_circle(draw_pos, weak_point_draw_radius, Color(1.0, 0.15, 0.15, 0.45))
		draw_arc(draw_pos, weak_point_draw_radius, 0.0, TAU, 16, Color(1.0, 0.2, 0.2, 0.95), 1.0)


func get_floor_level() -> int:
	return verticality.floor_level if verticality != null else 0


func get_height_z() -> float:
	return verticality.height_z if verticality != null else 0.0


func get_world_weak_points() -> Array[Vector2]:
	var pts: Array[Vector2] = []
	var visual_y_shift: float = 0.0
	if verticality != null and (verticality.hitbox_root == null or get_parent() != verticality.hitbox_root):
		visual_y_shift = -verticality.height_z * VerticalityComponent.VISUAL_Y_OFFSET_PER_Z
	for offset: Vector2 in weak_point_offsets:
		pts.append(to_global(Vector2(offset.x, offset.y + visual_y_shift)))
	return pts


func build_defense_params() -> PenetrationResolver.DefenseParams:
	var def: PenetrationResolver.DefenseParams = PenetrationResolver.DefenseParams.new()
	def.target_con = stat_sheet.get_stat(StatSheet.Stat.CON) if stat_sheet != null else 10.0
	def.mana_skin_density = stat_sheet.get_mana_skin_density() if stat_sheet != null else 0.0
	def.size_mult = size_mult
	def.base_anatomy_thickness = base_anatomy_thickness
	def.bone_density = anatomy.base_bone_density if anatomy != null else 100.0
	def.armor_thickness = armor_thickness
	def.armor_hardness = armor_hardness
	def.target_height_z = get_height_z()
	def.zone_name = zone_name
	return def
