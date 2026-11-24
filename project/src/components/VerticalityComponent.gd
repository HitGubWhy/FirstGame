class_name VerticalityComponent
extends Node
## Manages discrete floor_level and continuous virtual flight/jump altitude (height_z).
## Updates sprite vertical offset, scale, ground shadow (z = 0), z_index sorting, and
## parent CharacterBody2D collision layers/masks dynamically via FloorLayerManager (GDD 12.6, 14.3).

signal floor_level_changed(old_floor: int, new_floor: int)
signal height_z_changed(old_z: float, new_z: float)
signal flight_mode_changed(old_mode: int, new_mode: int)

enum FlightMode {
	NONE = 0,
	MANA_FLIGHT = 1,
	WING_FLIGHT = 2,
}

enum PreferredFlightMode {
	AUTO = 0,
	MANA = 1,
	WINGS = 2,
}

const HEIGHT_GROUND: float = 0.0
const HEIGHT_LOW_FLIGHT: float = 1.0
const HEIGHT_HIGH_FLIGHT: float = 1.5
const VISUAL_Y_OFFSET_PER_Z: float = 45.0
const VISUAL_SCALE_PER_Z: float = 0.15
const LOW_OBSTACLE_CLEARANCE_Z: float = 1.0

@export var floor_level: int = 0:
	set(value):
		var old_floor: int = floor_level
		floor_level = value
		if is_focus_entity:
			var flm: Node = _get_floor_manager()
			if flm != null and flm.has_method("set_focus_floor"):
				flm.call("set_focus_floor", floor_level)
		sync_all()
		if _initialized and old_floor != floor_level:
			floor_level_changed.emit(old_floor, floor_level)
			var bus: Node = _get_event_bus()
			if bus != null:
				bus.emit_signal("floor_changed", _get_owner_entity(), old_floor, floor_level)

@export var height_z: float = 0.0:
	set(value):
		var clamped_z: float = clampf(value, 0.0, maxf(0.0, max_height_z))
		var old_z: float = height_z
		height_z = clamped_z
		if height_z < LOW_OBSTACLE_CLEARANCE_Z and flight_mode != FlightMode.NONE:
			var old_mode: FlightMode = flight_mode
			flight_mode = FlightMode.NONE
			if _initialized:
				flight_mode_changed.emit(old_mode, flight_mode)
		sync_all()
		if _initialized and not is_equal_approx(old_z, height_z):
			height_z_changed.emit(old_z, height_z)

@export var max_height_z: float = 4.0
@export var collide_with_actors: bool = true
@export var is_focus_entity: bool = false
var flight_mode: FlightMode = FlightMode.NONE
var preferred_flight_mode: PreferredFlightMode = PreferredFlightMode.AUTO

@export var body_visual_path: NodePath = NodePath()
@export var shadow_visual_path: NodePath = NodePath()
@export var base_visual_offset: Vector2 = Vector2.ZERO
@export var base_visual_scale: Vector2 = Vector2.ONE
@export var base_shadow_offset: Vector2 = Vector2.ZERO
var visual_stance_scale: float = 1.0

var body_visual: Node2D = null
var shadow_visual: Node2D = null
var hitbox_root: Node2D = null
var target_collision_body: CollisionObject2D = null

var _initialized: bool = false


func _ready() -> void:
	if body_visual == null and not body_visual_path.is_empty():
		body_visual = get_node_or_null(body_visual_path) as Node2D
	if shadow_visual == null and not shadow_visual_path.is_empty():
		shadow_visual = get_node_or_null(shadow_visual_path) as Node2D
	if target_collision_body == null and get_parent() is CollisionObject2D:
		target_collision_body = get_parent() as CollisionObject2D

	var flm: Node = _get_floor_manager()
	if flm != null and flm.has_signal("active_window_changed"):
		var cb: Callable = Callable(self, "_on_active_window_changed")
		if not flm.is_connected("active_window_changed", cb):
			flm.connect("active_window_changed", cb)

	_initialized = true
	sync_all()


func setup(
	p_body_visual: Node2D,
	p_shadow_visual: Node2D = null,
	p_collision_body: CollisionObject2D = null,
	p_floor_level: int = 0,
	p_height_z: float = 0.0,
	p_hitbox_root: Node2D = null
) -> void:
	body_visual = p_body_visual
	shadow_visual = p_shadow_visual
	hitbox_root = p_hitbox_root
	target_collision_body = p_collision_body
	floor_level = p_floor_level
	height_z = p_height_z
	sync_all()


func set_floor_level(new_floor: int) -> void:
	floor_level = new_floor


func set_height_z(new_z: float) -> void:
	height_z = new_z


func set_flight_mode(new_mode: FlightMode) -> void:
	if flight_mode == new_mode:
		return
	var old_mode: FlightMode = flight_mode
	flight_mode = new_mode
	if _initialized:
		flight_mode_changed.emit(old_mode, flight_mode)


static func get_flight_mode_name(mode: FlightMode) -> String:
	match mode:
		FlightMode.MANA_FLIGHT:
			return "MANA"
		FlightMode.WING_FLIGHT:
			return "WINGS"
		_:
			return "NONE"


static func get_preferred_flight_mode_name(pref: PreferredFlightMode) -> String:
	match pref:
		PreferredFlightMode.MANA:
			return "Мана"
		PreferredFlightMode.WINGS:
			return "Крылья"
		_:
			return "Авто"


func toggle_flight(flight_altitude: float = HEIGHT_HIGH_FLIGHT) -> float:
	if height_z >= LOW_OBSTACLE_CLEARANCE_Z:
		set_height_z(HEIGHT_GROUND)
	else:
		set_height_z(flight_altitude)
	return height_z


func is_flying() -> bool:
	return height_z >= LOW_OBSTACLE_CLEARANCE_Z


func is_grounded() -> bool:
	return height_z <= 0.1


func can_reach_vertical(other_height_z: float, vertical_reach: float) -> bool:
	return absf(height_z - other_height_z) <= maxf(0.0, vertical_reach)


func get_visual_z_index() -> int:
	return floor_level * 100 + int(height_z * 10.0)


func get_shadow_z_index() -> int:
	return floor_level * 100


func sync_all() -> void:
	sync_visuals()
	sync_collisions()


func sync_visuals() -> void:
	var target_body_z: int = get_visual_z_index()
	var target_shadow_z: int = get_shadow_z_index()

	var parent_2d: Node2D = get_parent() as Node2D
	if parent_2d != null:
		parent_2d.z_index = target_body_z

	if body_visual != null:
		body_visual.position = Vector2(
			base_visual_offset.x,
			base_visual_offset.y - height_z * VISUAL_Y_OFFSET_PER_Z
		)
		var scale_mult: float = 1.0 + height_z * VISUAL_SCALE_PER_Z
		body_visual.scale = base_visual_scale * scale_mult * visual_stance_scale
		body_visual.z_as_relative = false
		body_visual.z_index = target_body_z

	if hitbox_root != null:
		hitbox_root.position = Vector2(
			base_visual_offset.x,
			base_visual_offset.y - height_z * VISUAL_Y_OFFSET_PER_Z
		)
		var hb_scale: float = 1.0 + height_z * VISUAL_SCALE_PER_Z
		hitbox_root.scale = base_visual_scale * hb_scale
		hitbox_root.z_as_relative = false
		hitbox_root.z_index = target_body_z + 2

	if shadow_visual != null:
		shadow_visual.position = base_shadow_offset
		shadow_visual.z_as_relative = false
		shadow_visual.z_index = target_shadow_z


func sync_collisions() -> void:
	var body: CollisionObject2D = _resolve_collision_body()
	if body == null:
		return
	var flm: Node = _get_floor_manager()
	if flm == null:
		return
	body.collision_layer = int(flm.call("get_actor_collision_layer", floor_level))
	body.collision_mask = int(flm.call(
		"get_actor_collision_mask",
		floor_level,
		height_z,
		collide_with_actors,
		LOW_OBSTACLE_CLEARANCE_Z
	))


func _on_active_window_changed(_focus_floor: int, _min_floor: int, _max_floor: int) -> void:
	sync_collisions()


func _resolve_collision_body() -> CollisionObject2D:
	if target_collision_body != null:
		return target_collision_body
	var parent: Node = get_parent()
	if parent is CollisionObject2D:
		return parent as CollisionObject2D
	return null


func _get_owner_entity() -> Node:
	var parent: Node = get_parent()
	return parent if parent != null else self


func _get_floor_manager() -> Node:
	if is_inside_tree() and get_tree().root != null:
		return get_tree().root.get_node_or_null("FloorLayerManager")
	var main_loop: MainLoop = Engine.get_main_loop()
	if main_loop is SceneTree:
		var tree: SceneTree = main_loop as SceneTree
		if tree.root != null:
			return tree.root.get_node_or_null("FloorLayerManager")
	return null


func _get_event_bus() -> Node:
	if is_inside_tree() and get_tree().root != null:
		return get_tree().root.get_node_or_null("EventBus")
	var main_loop: MainLoop = Engine.get_main_loop()
	if main_loop is SceneTree:
		var tree: SceneTree = main_loop as SceneTree
		if tree.root != null:
			return tree.root.get_node_or_null("EventBus")
	return null
