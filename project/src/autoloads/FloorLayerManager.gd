extends Node
## FloorLayerManager Autoload (GDD Sections 12.6, 12.7, 14.5).
## Maps any discrete floor_level into a 4-slot active physics window (12 solid bits + 6 shared bits = 18 bits).
## Tracks floor tile integrity for falling through broken upper floors (has_floor_at).

signal active_window_changed(focus_floor: int, min_floor: int, max_floor: int)

const SLOT_COUNT: int = 4
const LAYERS_PER_SLOT: int = 3
const WINDOW_BELOW_FOCUS: int = 1
const WINDOW_ABOVE_FOCUS: int = 2

const SLOT_OFFSET_HIGH_WALLS: int = 0
const SLOT_OFFSET_LOW_OBSTACLES: int = 1
const SLOT_OFFSET_ACTORS: int = 2

# Shared 1-based layer numbers (Layers 13..18 in project.godot)
const LAYER_HITBOX_ZONES: int = 13
const LAYER_PROJECTILES: int = 14
const LAYER_INTERACTABLES: int = 15
const LAYER_MIND_DOMAINS: int = 16
const LAYER_FLOOR_SUPPORT: int = 17
const LAYER_TRIGGERS_STEALTH: int = 18

# Shared collision bitmasks (bits 12..17)
const BIT_HITBOX_ZONES: int = 1 << (LAYER_HITBOX_ZONES - 1)
const BIT_PROJECTILES: int = 1 << (LAYER_PROJECTILES - 1)
const BIT_INTERACTABLES: int = 1 << (LAYER_INTERACTABLES - 1)
const BIT_MIND_DOMAINS: int = 1 << (LAYER_MIND_DOMAINS - 1)
const BIT_FLOOR_SUPPORT: int = 1 << (LAYER_FLOOR_SUPPORT - 1)
const BIT_TRIGGERS_STEALTH: int = 1 << (LAYER_TRIGGERS_STEALTH - 1)

const ALL_USED_LAYERS_MASK: int = (1 << 18) - 1

const TILE_SIZE_PX: int = 32
const LOW_OBSTACLE_CLEARANCE_Z: float = 1.0
const FLOOR_FALL_MAX_Z: float = 0.1

var focus_floor: int = 0

## floor_level (int) -> Dictionary[Vector2i, bool] (true = intact floor tile)
var _floor_cells: Dictionary = {}


func reset(p_focus_floor: int = 0) -> void:
	focus_floor = p_focus_floor
	_floor_cells.clear()


# ---------------------------------------------------------------------------
# 4-Slot Active Window Mapping (18-bit Physics Architecture)
# ---------------------------------------------------------------------------

func set_focus_floor(new_focus_floor: int) -> void:
	if focus_floor == new_focus_floor:
		return
	focus_floor = new_focus_floor
	active_window_changed.emit(focus_floor, get_window_min_floor(), get_window_max_floor())


func get_window_min_floor() -> int:
	return focus_floor - WINDOW_BELOW_FOCUS


func get_window_max_floor() -> int:
	return focus_floor + WINDOW_ABOVE_FOCUS


func is_floor_active(floor_level: int) -> bool:
	return floor_level >= get_window_min_floor() and floor_level <= get_window_max_floor()


## Returns slot index 0..3 for any floor inside the active window, or -1 if outside the active window.
## Uses posmod(floor_level, 4) so consecutive 4 floors always occupy 4 unique slots without mass-remapping on stairs.
func get_slot_for_floor(floor_level: int) -> int:
	if not is_floor_active(floor_level):
		return -1
	return posmod(floor_level, SLOT_COUNT)


func get_high_walls_layer_number(floor_level: int) -> int:
	var slot: int = get_slot_for_floor(floor_level)
	if slot < 0:
		return 0
	return slot * LAYERS_PER_SLOT + SLOT_OFFSET_HIGH_WALLS + 1


func get_low_obstacles_layer_number(floor_level: int) -> int:
	var slot: int = get_slot_for_floor(floor_level)
	if slot < 0:
		return 0
	return slot * LAYERS_PER_SLOT + SLOT_OFFSET_LOW_OBSTACLES + 1


func get_actors_layer_number(floor_level: int) -> int:
	var slot: int = get_slot_for_floor(floor_level)
	if slot < 0:
		return 0
	return slot * LAYERS_PER_SLOT + SLOT_OFFSET_ACTORS + 1


func get_high_walls_bit(floor_level: int) -> int:
	var layer_num: int = get_high_walls_layer_number(floor_level)
	return (1 << (layer_num - 1)) if layer_num > 0 else 0


func get_low_obstacles_bit(floor_level: int) -> int:
	var layer_num: int = get_low_obstacles_layer_number(floor_level)
	return (1 << (layer_num - 1)) if layer_num > 0 else 0


func get_actors_bit(floor_level: int) -> int:
	var layer_num: int = get_actors_layer_number(floor_level)
	return (1 << (layer_num - 1)) if layer_num > 0 else 0


func get_actor_collision_layer(floor_level: int) -> int:
	return get_actors_bit(floor_level)


## Returns the physics collision_mask for an actor at (floor_level, height_z).
## When flying (height_z >= low_obstacle_clearance_z), LowObstacles bit is disabled while HighWalls stays active.
func get_actor_collision_mask(
	floor_level: int,
	height_z: float = 0.0,
	collide_with_actors: bool = true,
	low_obstacle_clearance_z: float = LOW_OBSTACLE_CLEARANCE_Z
) -> int:
	if not is_floor_active(floor_level):
		return 0
	var mask: int = get_high_walls_bit(floor_level)
	if height_z < low_obstacle_clearance_z:
		mask |= get_low_obstacles_bit(floor_level)
	if collide_with_actors:
		mask |= get_actors_bit(floor_level)
	return mask


func get_solid_world_mask(floor_level: int, include_low_obstacles: bool = true) -> int:
	if not is_floor_active(floor_level):
		return 0
	var mask: int = get_high_walls_bit(floor_level)
	if include_low_obstacles:
		mask |= get_low_obstacles_bit(floor_level)
	return mask


## Visual sorting helper (GDD Section 14.3): z_index = floor_level * 100 + int(height_z * 10)
func get_visual_z_index(floor_level: int, height_z: float = 0.0) -> int:
	return floor_level * 100 + int(height_z * 10.0)


func get_shadow_z_index(floor_level: int) -> int:
	return floor_level * 100


func world_to_cell(world_pos: Vector2, tile_size: int = TILE_SIZE_PX) -> Vector2i:
	var ts: float = float(maxi(1, tile_size))
	return Vector2i(floori(world_pos.x / ts), floori(world_pos.y / ts))


# ---------------------------------------------------------------------------
# Floor Integrity Storage & Fall Support Checks (GDD 12.7, 14.5)
# ---------------------------------------------------------------------------

func set_floor_at(floor_level: int, cell: Vector2i, intact: bool) -> void:
	if not _floor_cells.has(floor_level):
		_floor_cells[floor_level] = {}
	var floor_map: Dictionary = _floor_cells[floor_level]
	if intact:
		floor_map[cell] = true
	else:
		floor_map.erase(cell)


func register_floor_cells(floor_level: int, cells: Array[Vector2i]) -> void:
	if not _floor_cells.has(floor_level):
		_floor_cells[floor_level] = {}
	var floor_map: Dictionary = _floor_cells[floor_level]
	for cell: Vector2i in cells:
		floor_map[cell] = true


func register_floor_rect(floor_level: int, rect: Rect2i) -> void:
	if not _floor_cells.has(floor_level):
		_floor_cells[floor_level] = {}
	var floor_map: Dictionary = _floor_cells[floor_level]
	for x: int in range(rect.position.x, rect.end.x):
		for y: int in range(rect.position.y, rect.end.y):
			floor_map[Vector2i(x, y)] = true


func sync_from_tile_map_layer(floor_level: int, tile_map_layer: TileMapLayer) -> void:
	clear_floor_data(floor_level)
	if tile_map_layer == null:
		return
	var used_cells: Array[Vector2i] = tile_map_layer.get_used_cells()
	register_floor_cells(floor_level, used_cells)


func break_floor_at(floor_level: int, cell: Vector2i) -> bool:
	if not has_floor_at(floor_level, cell):
		return false
	var floor_map: Dictionary = _floor_cells[floor_level]
	floor_map.erase(cell)
	var bus: Node = _get_event_bus()
	if bus != null:
		bus.emit_signal("floor_tile_broken", floor_level, cell)
	return true


func has_floor_at(floor_level: int, cell: Vector2i) -> bool:
	if not _floor_cells.has(floor_level):
		return false
	var floor_map: Dictionary = _floor_cells[floor_level]
	return bool(floor_map.get(cell, false))


func should_entity_fall(floor_level: int, cell: Vector2i, height_z: float) -> bool:
	if height_z > FLOOR_FALL_MAX_Z:
		return false
	return not has_floor_at(floor_level, cell)


func clear_floor_data(floor_level: int) -> void:
	_floor_cells.erase(floor_level)


func clear_all_floors() -> void:
	_floor_cells.clear()


func _get_event_bus() -> Node:
	var root: Node = get_tree().root if is_inside_tree() else null
	if root != null:
		return root.get_node_or_null("EventBus")
	return null
