class_name TestArena
extends Node2D
## Graybox Two-Story Test Arena controller (GDD Sections 12.6, 12.7, 14.1, 14.3, 14.5, v0.2).
## Uses strictly TileMapLayer nodes across Floor0 and Floor1, procedural TileSet (zero PNGs),
## roof/floor visibility transitions, stairs Area2D with 0.4s cooldown, destructible walls/floor,
## SafeBarrierZone (dashed blue guard perimeter resetting mob aggro), per-floor AStarGrid2D updates,
## FloorSupport fall resolution, 3 test enemies (Rank 1 / Troll Berserker / Rank 6 Guard),
## and procedural decals/particles (blood puddles, blood trails, severed limbs, sparks, noise tracker).

signal wall_damaged(floor_level: int, cell: Vector2i, material_type: String, remaining_durability: float, max_durability: float)
signal wall_destroyed(floor_level: int, cell: Vector2i, material_type: String)
signal floor_broken(floor_level: int, cell: Vector2i)
signal entity_used_stairs(entity: Node, from_floor: int, to_floor: int)
signal entity_fell_through_floor(entity: Node, from_floor: int, to_floor: int, fall_report: Dictionary)
signal entity_entered_safe_zone(entity: Node)

const ARENA_WIDTH_TILES: int = 26
const ARENA_HEIGHT_TILES: int = 16
const TILE_SIZE: int = ProceduralTileSetBuilder.TILE_SIZE

const BUILDING_RECT: Rect2i = Rect2i(14, 2, 10, 12)
const BUILDING_INTERIOR_RECT: Rect2i = Rect2i(15, 3, 8, 10)
const STAIRS_RECT: Rect2i = Rect2i(16, 4, 2, 2)
const BREAKABLE_FLOOR_RECT: Rect2i = Rect2i(18, 7, 3, 3)
const SAFE_ZONE_RECT: Rect2i = Rect2i(1, 1, 3, 3)
const STEALTH_COVER_RECTS: Array[Rect2i] = [
	Rect2i(4, 5, 2, 2),
	Rect2i(11, 2, 2, 2),
	Rect2i(2, 12, 3, 2),
]
const COLOR_STEALTH_COVER_FILL: Color = Color(0.08, 0.24, 0.14, 0.54)
const COLOR_STEALTH_COVER_CANOPY: Color = Color(0.11, 0.34, 0.19, 0.34)
const COLOR_STEALTH_COVER_BORDER: Color = Color(0.18, 0.50, 0.28, 0.55)


## Procedural expanding acoustic wave ring drawn on the arena floor for noise distractions (T).
class NoiseRippleDrawer extends Node2D:
	var radius_px: float = 6.0:
		set(v):
			radius_px = v
			queue_redraw()
	var ring_color: Color = Color(0.95, 0.88, 0.45, 0.85)
	var line_width: float = 1.8

	func _draw() -> void:
		draw_arc(Vector2.ZERO, radius_px, 0.0, TAU, 28, ring_color, line_width)
		if radius_px > 10.0:
			var inner_col: Color = Color(ring_color.r, ring_color.g, ring_color.b, ring_color.a * 0.45)
			draw_arc(Vector2.ZERO, radius_px * 0.62, 0.0, TAU, 20, inner_col, 1.1)


## Single-draw-call 3/4 Top-Down wall cast-shadow & top-parapet depth overlay per floor.
class WallDepthOverlay extends Node2D:
	var shadow_rects: Array[Rect2] = []
	var crown_entries: Array[Dictionary] = []

	func _draw() -> void:
		for r: Rect2 in shadow_rects:
			draw_rect(r, Color(0.0, 0.0, 0.0, 0.30), true)
			var tail: Rect2 = Rect2(Vector2(r.position.x, r.end.y), Vector2(r.size.x, 3.0))
			draw_rect(tail, Color(0.0, 0.0, 0.0, 0.14), true)
		for item: Dictionary in crown_entries:
			var cr: Rect2 = item["rect"] as Rect2
			var col: Color = item["color"] as Color
			var hi: Color = item["hi"] as Color
			var rim: Color = item["rim"] as Color
			draw_rect(cr, col, true)
			draw_rect(Rect2(cr.position, Vector2(cr.size.x, 1.0)), rim, true)
			draw_rect(Rect2(cr.position + Vector2(0.0, 1.0), Vector2(cr.size.x, 1.0)), hi, true)
			draw_rect(Rect2(Vector2(cr.position.x, cr.end.y - 1.0), Vector2(cr.size.x, 1.0)), hi, true)

const WOOD_WALL_CELLS: Array[Vector2i] = [Vector2i(9, 2), Vector2i(9, 3), Vector2i(9, 4)]
const BRICK_WALL_CELLS: Array[Vector2i] = [Vector2i(9, 6), Vector2i(9, 7), Vector2i(9, 8)]
const STONE_WALL_CELLS: Array[Vector2i] = [Vector2i(9, 10), Vector2i(9, 11), Vector2i(9, 12)]

const LOW_FENCE_CELLS_FLOOR0: Array[Vector2i] = [
	Vector2i(6, 3), Vector2i(6, 4), Vector2i(6, 5), Vector2i(6, 6),
	Vector2i(3, 10), Vector2i(4, 10), Vector2i(5, 10),
]

const STAIRS_COOLDOWN_SEC: float = 0.4
const VISIBILITY_FADE_DURATION: float = 0.22
const FLOOR0_DIMMED_COLOR: Color = Color(0.45, 0.45, 0.50, 1.0)
const FLOOR0_BRIGHT_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const AMBIENT_COLOR_DAY: Color = Color(1.0, 1.0, 1.0, 1.0)
const AMBIENT_COLOR_NIGHT: Color = Color(0.58, 0.66, 0.86, 1.0)
const AMBIENT_COLOR_BLOOD_MOON_DAY: Color = Color(0.95, 0.72, 0.72, 1.0)
const AMBIENT_COLOR_BLOOD_MOON_NIGHT: Color = Color(0.84, 0.40, 0.44, 1.0)

const RANK1_SCENE_PATH: String = "res://scenes/rank1_swordsman.tscn"
const TROLL_SCENE_PATH: String = "res://scenes/troll_berserker.tscn"
const RANK6_SCENE_PATH: String = "res://scenes/rank6_guard.tscn"
const RANK1_SPAWN_POS: Vector2 = Vector2(240.0, 80.0)
const TROLL_SPAWN_POS: Vector2 = Vector2(384.0, 240.0)
const RANK6_SPAWN_POS: Vector2 = Vector2(384.0, 416.0)

const MAX_BLOOD_DECALS: int = 80
const MAX_SEVERED_LIMBS: int = 24
const BLOOD_TRAIL_MAX_AGE_SEC: float = 20.0
const NOISE_MAX_AGE_SEC: float = 3.5
const CROSS_FLOOR_NOISE_ATTENUATION: float = 0.55

@onready var floor0_container: Node2D = $Floor0
@onready var floor0_floor_layer: TileMapLayer = $Floor0/FloorLayer
@onready var floor0_wall_layer: TileMapLayer = $Floor0/WallLayer
@onready var building_interior_trigger: Area2D = $Floor0/BuildingInteriorTrigger
@onready var building_interior_shape: CollisionShape2D = $Floor0/BuildingInteriorTrigger/CollisionShape2D
@onready var safe_barrier_zone: Area2D = $Floor0/SafeBarrierZone
@onready var safe_barrier_shape: CollisionShape2D = $Floor0/SafeBarrierZone/CollisionShape2D

@onready var floor1_container: Node2D = $Floor1
@onready var floor1_floor_layer: TileMapLayer = $Floor1/FloorLayer
@onready var floor1_wall_layer: TileMapLayer = $Floor1/WallLayer
@onready var floor1_roof_layer: TileMapLayer = $Floor1/RoofLayer
@onready var floor1_support_zone: Area2D = $Floor1/FloorSupportZone
@onready var floor1_support_shape: CollisionShape2D = $Floor1/FloorSupportZone/CollisionShape2D

@onready var stairs_area: Area2D = $StairsArea
@onready var stairs_shape: CollisionShape2D = $StairsArea/CollisionShape2D
@onready var decals_container: Node2D = $Decals
@onready var effects_container: Node2D = $Effects
@onready var entities_container: Node2D = $Entities

var shared_atlas_texture: ImageTexture = null
var floor0_tileset: TileSet = null
var floor1_tileset: TileSet = null

var focus_entity: Node2D = null

var _nav_grids: Dictionary[int, AStarGrid2D] = {}
var _wall_durability: Dictionary = {}
var _floor_durability: Dictionary = {}
var _stairs_cooldowns: Dictionary[int, float] = {}
var _entities_in_building_trigger: Array[Node] = []
var _entities_in_stairs_area: Array[Node] = []
var _entities_in_safe_zone: Array[Node] = []
var stealth_cover_zones: Array[Area2D] = []
var _entities_in_stealth_cover: Dictionary[int, int] = {}
var _tracked_entities: Array[Node] = []

## Decals, severed limbs, dropped weapons, blood trails & acoustic sensory events (GDD 7.4, 14.3)
var blood_decal_nodes: Array[Node2D] = []
var severed_limb_nodes: Array[Node2D] = []
var dropped_weapon_pickups: Array[Dictionary] = []
var blood_trail_points: Array[Dictionary] = []
var recent_noises: Array[Dictionary] = []
var active_spark_count: int = 0
var active_noise_ripple_count: int = 0
var active_floating_callout_count: int = 0
var last_floating_callout_text: String = ""
var _structure_crack_overlays: Dictionary = {}
var audio_manager: ProceduralAudioManager = null
var combat_reticle: CombatReticle = null
var ambient_modulate: CanvasModulate = null
var floor0_wall_shadows: WallDepthOverlay = null
var floor1_wall_shadows: WallDepthOverlay = null
var floor0_wall_crowns: WallDepthOverlay = null
var floor1_wall_crowns: WallDepthOverlay = null

var _visibility_tween: Tween = null
var _viewer_floor: int = 0
var _viewer_inside_building: bool = false
var enemies_ai_enabled: bool = true


func _ready() -> void:
	add_to_group(&"test_arena")
	_setup_procedural_tilesets()
	_configure_layer_z_indices()
	_build_arena_geometry()
	_configure_triggers_and_areas()
	_build_safe_zone_visual()
	_setup_stealth_cover_zones()
	_sync_floor_layer_manager()
	_rebuild_all_nav_grids()
	_setup_procedural_audio()
	_setup_combat_reticle()
	_setup_ambient_lighting()
	_connect_signals()
	_register_initial_entities()
	update_floor_visibility(_viewer_floor, _viewer_inside_building, true)
	update_ambient_lighting()
	print("[TestArena] Initialized 2-story graybox arena (%dx%d tiles, TileMapLayer, procedural 32x32 atlas, entities=%d)." % [
		ARENA_WIDTH_TILES,
		ARENA_HEIGHT_TILES,
		entities_container.get_child_count(),
	])


func _process(_delta: float) -> void:
	update_ambient_lighting()


func _setup_ambient_lighting() -> void:
	ambient_modulate = get_node_or_null("AmbientModulate") as CanvasModulate
	if ambient_modulate == null:
		ambient_modulate = CanvasModulate.new()
		ambient_modulate.name = "AmbientModulate"
		add_child(ambient_modulate)
	ambient_modulate.color = compute_target_ambient_color()


func compute_target_ambient_color() -> Color:
	if WorldCalendar == null:
		return AMBIENT_COLOR_DAY
	var is_night_now: bool = WorldCalendar.is_night()
	if WorldCalendar.is_blood_moon():
		return AMBIENT_COLOR_BLOOD_MOON_NIGHT if is_night_now else AMBIENT_COLOR_BLOOD_MOON_DAY
	return AMBIENT_COLOR_NIGHT if is_night_now else AMBIENT_COLOR_DAY


func update_ambient_lighting() -> Color:
	var target: Color = compute_target_ambient_color()
	if ambient_modulate != null and ambient_modulate.color != target:
		ambient_modulate.color = target
	return target


func _setup_procedural_audio() -> void:
	audio_manager = get_node_or_null("ProceduralAudioManager") as ProceduralAudioManager
	if audio_manager == null:
		audio_manager = ProceduralAudioManager.new()
		audio_manager.name = "ProceduralAudioManager"
		add_child(audio_manager)


func _setup_combat_reticle() -> void:
	combat_reticle = get_node_or_null("CombatReticle") as CombatReticle
	if combat_reticle == null:
		combat_reticle = CombatReticle.new()
		combat_reticle.name = "CombatReticle"
		add_child(combat_reticle)


func _exit_tree() -> void:
	_disconnect_event_bus()


func _register_initial_entities() -> void:
	if entities_container == null:
		return
	for child: Node in entities_container.get_children():
		register_entity(child, child.is_in_group(&"player"))


func respawn_test_dummies() -> Array[Node]:
	var spawned: Array[Node] = []
	if entities_container == null:
		return spawned

	var to_remove: Array[Node] = []
	for child: Node in entities_container.get_children():
		if child.is_in_group(&"enemies"):
			to_remove.append(child)
	for old_enemy: Node in to_remove:
		unregister_entity(old_enemy)
		entities_container.remove_child(old_enemy)
		old_enemy.queue_free()

	var spawn_specs: Array[Dictionary] = [
		{"path": RANK1_SCENE_PATH, "name": "Rank1Swordsman", "pos": RANK1_SPAWN_POS},
		{"path": TROLL_SCENE_PATH, "name": "TrollBerserker", "pos": TROLL_SPAWN_POS},
		{"path": RANK6_SCENE_PATH, "name": "Rank6Guard", "pos": RANK6_SPAWN_POS},
	]
	for spec: Dictionary in spawn_specs:
		var packed: PackedScene = load(String(spec["path"])) as PackedScene
		if packed == null:
			continue
		var enemy_node: Node2D = packed.instantiate() as Node2D
		if enemy_node == null:
			continue
		enemy_node.name = String(spec["name"])
		enemy_node.position = spec["pos"] as Vector2
		if enemy_node is EnemyDummy:
			(enemy_node as EnemyDummy).ai_enabled = enemies_ai_enabled
		entities_container.add_child(enemy_node)
		register_entity(enemy_node, false)
		spawned.append(enemy_node)

	print("[TestArena] Respawned test dummies (Rank 1 Swordsman, Troll Berserker & Rank 6 Guard).")
	return spawned


func reset_arena_geometry_and_decals() -> void:
	for bnode: Node2D in blood_decal_nodes:
		if is_instance_valid(bnode):
			bnode.queue_free()
	blood_decal_nodes.clear()
	for lnode: Node2D in severed_limb_nodes:
		if is_instance_valid(lnode):
			lnode.queue_free()
	severed_limb_nodes.clear()
	for pdict: Dictionary in dropped_weapon_pickups:
		var pnode: Variant = pdict.get("node", null)
		if pnode is Node and is_instance_valid(pnode as Node):
			(pnode as Node).queue_free()
	dropped_weapon_pickups.clear()
	for crack_node: Variant in _structure_crack_overlays.values():
		if crack_node is Node and is_instance_valid(crack_node as Node):
			(crack_node as Node).queue_free()
	_structure_crack_overlays.clear()
	blood_trail_points.clear()
	recent_noises.clear()
	if decals_container != null:
		for c: Node in decals_container.get_children():
			c.queue_free()
	if effects_container != null:
		for c: Node in effects_container.get_children():
			c.queue_free()
	active_spark_count = 0
	active_noise_ripple_count = 0
	active_floating_callout_count = 0
	last_floating_callout_text = ""

	_build_arena_geometry()
	_sync_floor_layer_manager()
	_rebuild_all_nav_grids()
	if SimulationClock != null:
		SimulationClock.clear_all_aggro()
		SimulationClock.set_tempo_mode(SimulationClock.TempoMode.PEACEFUL, true, "arena_reset")


func reset_arena_and_respawn() -> Array[Node]:
	reset_arena_geometry_and_decals()
	return respawn_test_dummies()


func reset_all_enemy_aggro(cooldown_sec: float = 2.0) -> void:
	if entities_container == null:
		return
	for child: Node in entities_container.get_children():
		if child is EnemyDummy:
			(child as EnemyDummy).reset_aggro(cooldown_sec)


func set_all_enemies_ai_enabled(enabled: bool) -> void:
	enemies_ai_enabled = enabled
	if entities_container == null:
		return
	for child: Node in entities_container.get_children():
		if child is EnemyDummy:
			var e: EnemyDummy = child as EnemyDummy
			e.ai_enabled = enabled
			if not enabled:
				e.reset_aggro(0.5)


func _physics_process(delta: float) -> void:
	var expired_ids: Array[int] = []
	for entity_id: int in _stairs_cooldowns.keys():
		var remaining: float = _stairs_cooldowns[entity_id] - delta
		if remaining <= 0.0:
			expired_ids.append(entity_id)
		else:
			_stairs_cooldowns[entity_id] = remaining
	for entity_id: int in expired_ids:
		_stairs_cooldowns.erase(entity_id)

	var w_delta: float = SimulationClock.get_world_delta(delta) if SimulationClock != null else delta
	_tick_sensory_records(w_delta)

	check_floor_support_for_all_entities()


func _tick_sensory_records(world_delta: float) -> void:
	if world_delta <= 0.0:
		return
	for i: int in range(recent_noises.size() - 1, -1, -1):
		var rec: Dictionary = recent_noises[i]
		rec["age"] = float(rec.get("age", 0.0)) + world_delta
		if float(rec["age"]) > NOISE_MAX_AGE_SEC:
			recent_noises.remove_at(i)
	for i: int in range(blood_trail_points.size() - 1, -1, -1):
		var rec: Dictionary = blood_trail_points[i]
		rec["age"] = float(rec.get("age", 0.0)) + world_delta
		if float(rec["age"]) > BLOOD_TRAIL_MAX_AGE_SEC:
			blood_trail_points.remove_at(i)


# ---------------------------------------------------------------------------
# Initialization: Procedural TileSets, Geometry, Triggers & Safe Zone Visual
# ---------------------------------------------------------------------------

func _setup_procedural_tilesets() -> void:
	shared_atlas_texture = ProceduralTileSetBuilder.build_atlas_texture()
	floor0_tileset = ProceduralTileSetBuilder.build_tileset_for_floor(0, shared_atlas_texture)
	floor1_tileset = ProceduralTileSetBuilder.build_tileset_for_floor(1, shared_atlas_texture)

	floor0_floor_layer.tile_set = floor0_tileset
	floor0_wall_layer.tile_set = floor0_tileset

	floor1_floor_layer.tile_set = floor1_tileset
	floor1_wall_layer.tile_set = floor1_tileset
	floor1_roof_layer.tile_set = floor1_tileset

	for layer: TileMapLayer in [floor0_floor_layer, floor0_wall_layer, floor1_floor_layer, floor1_wall_layer, floor1_roof_layer]:
		layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _configure_layer_z_indices() -> void:
	floor0_container.z_index = 0
	floor0_floor_layer.z_as_relative = false
	floor0_floor_layer.z_index = -10
	floor0_wall_layer.z_as_relative = false
	floor0_wall_layer.z_index = -5

	floor1_container.z_index = 0
	floor1_floor_layer.z_as_relative = false
	floor1_floor_layer.z_index = 90
	floor1_wall_layer.z_as_relative = false
	floor1_wall_layer.z_index = 95
	floor1_roof_layer.z_as_relative = false
	floor1_roof_layer.z_index = 200


func _build_arena_geometry() -> void:
	floor0_floor_layer.clear()
	floor0_wall_layer.clear()
	floor1_floor_layer.clear()
	floor1_wall_layer.clear()
	floor1_roof_layer.clear()
	_wall_durability = {0: {}, 1: {}}
	_floor_durability = {0: {}, 1: {}}

	# 1. Floor 0 base floor & indestructible outer perimeter
	for x: int in range(ARENA_WIDTH_TILES):
		for y: int in range(ARENA_HEIGHT_TILES):
			var cell: Vector2i = Vector2i(x, y)
			floor0_floor_layer.set_cell(cell, 0, ProceduralTileSetBuilder.TILE_FLOOR_0)
			if x == 0 or y == 0 or x == ARENA_WIDTH_TILES - 1 or y == ARENA_HEIGHT_TILES - 1:
				_place_wall_tile(0, cell, ProceduralTileSetBuilder.TILE_WALL_INDESTRUCTIBLE)

	# 2. Floor 0 low obstacle fences (flyable at height_z >= 1.0)
	for cell: Vector2i in LOW_FENCE_CELLS_FLOOR0:
		_place_wall_tile(0, cell, ProceduralTileSetBuilder.TILE_LOW_OBSTACLE)

	# 3. Three separate destructible test walls on Floor 0: Wood (>=15), Brick (>=40), Stone (>=90)
	for cell: Vector2i in WOOD_WALL_CELLS:
		_place_wall_tile(0, cell, ProceduralTileSetBuilder.TILE_WALL_WOOD)
	for cell: Vector2i in BRICK_WALL_CELLS:
		_place_wall_tile(0, cell, ProceduralTileSetBuilder.TILE_WALL_BRICK)
	for cell: Vector2i in STONE_WALL_CELLS:
		_place_wall_tile(0, cell, ProceduralTileSetBuilder.TILE_WALL_STONE)

	# 4. Two-story building on right side (BUILDING_RECT)
	for x: int in range(BUILDING_RECT.position.x, BUILDING_RECT.end.x):
		for y: int in range(BUILDING_RECT.position.y, BUILDING_RECT.end.y):
			var cell: Vector2i = Vector2i(x, y)
			var is_perimeter: bool = (
				x == BUILDING_RECT.position.x
				or x == BUILDING_RECT.end.x - 1
				or y == BUILDING_RECT.position.y
				or y == BUILDING_RECT.end.y - 1
			)
			var is_west_doorway: bool = (x == BUILDING_RECT.position.x and (y == 7 or y == 8))

			if is_perimeter and not is_west_doorway:
				_place_wall_tile(0, cell, ProceduralTileSetBuilder.TILE_WALL_STONE)

			if BREAKABLE_FLOOR_RECT.has_point(cell):
				_place_floor_tile(1, cell, ProceduralTileSetBuilder.TILE_FLOOR_1_BREAKABLE)
			else:
				_place_floor_tile(1, cell, ProceduralTileSetBuilder.TILE_FLOOR_1)

			if is_perimeter:
				if is_west_doorway:
					_place_wall_tile(1, cell, ProceduralTileSetBuilder.TILE_LOW_OBSTACLE)
				else:
					_place_wall_tile(1, cell, ProceduralTileSetBuilder.TILE_WALL_STONE)

			floor1_roof_layer.set_cell(cell, 0, ProceduralTileSetBuilder.TILE_ROOF)

	# 5. Stairs connecting Floor 0 <-> Floor +1
	for x: int in range(STAIRS_RECT.position.x, STAIRS_RECT.end.x):
		for y: int in range(STAIRS_RECT.position.y, STAIRS_RECT.end.y):
			var stair_cell: Vector2i = Vector2i(x, y)
			floor0_floor_layer.set_cell(stair_cell, 0, ProceduralTileSetBuilder.TILE_STAIRS)
			floor1_floor_layer.set_cell(stair_cell, 0, ProceduralTileSetBuilder.TILE_STAIRS)

	floor0_wall_layer.update_internals()
	floor1_wall_layer.update_internals()
	_rebuild_34_wall_overlays()


func _ensure_34_wall_overlay_nodes() -> void:
	if floor0_container != null:
		floor0_wall_shadows = floor0_container.get_node_or_null("WallShadows0") as WallDepthOverlay
		if floor0_wall_shadows == null:
			floor0_wall_shadows = WallDepthOverlay.new()
			floor0_wall_shadows.name = "WallShadows0"
			floor0_container.add_child(floor0_wall_shadows)
		floor0_wall_shadows.z_as_relative = false
		floor0_wall_shadows.z_index = -8

		floor0_wall_crowns = floor0_container.get_node_or_null("WallCrowns0") as WallDepthOverlay
		if floor0_wall_crowns == null:
			floor0_wall_crowns = WallDepthOverlay.new()
			floor0_wall_crowns.name = "WallCrowns0"
			floor0_container.add_child(floor0_wall_crowns)
		floor0_wall_crowns.z_as_relative = false
		floor0_wall_crowns.z_index = 1

	if floor1_container != null:
		floor1_wall_shadows = floor1_container.get_node_or_null("WallShadows1") as WallDepthOverlay
		if floor1_wall_shadows == null:
			floor1_wall_shadows = WallDepthOverlay.new()
			floor1_wall_shadows.name = "WallShadows1"
			floor1_container.add_child(floor1_wall_shadows)
		floor1_wall_shadows.z_as_relative = false
		floor1_wall_shadows.z_index = 92

		floor1_wall_crowns = floor1_container.get_node_or_null("WallCrowns1") as WallDepthOverlay
		if floor1_wall_crowns == null:
			floor1_wall_crowns = WallDepthOverlay.new()
			floor1_wall_crowns.name = "WallCrowns1"
			floor1_container.add_child(floor1_wall_crowns)
		floor1_wall_crowns.z_as_relative = false
		floor1_wall_crowns.z_index = 101


func _is_high_wall_cell(floor_level: int, cell: Vector2i) -> String:
	var wl: TileMapLayer = get_wall_layer(floor_level)
	if wl == null:
		return ""
	var td: TileData = wl.get_cell_tile_data(cell)
	if td == null:
		return ""
	var mat: String = String(td.get_custom_data(ProceduralTileSetBuilder.DATA_MATERIAL_TYPE))
	if mat == "wood" or mat == "brick" or mat == "stone" or mat == "indestructible":
		return mat
	return ""


func _get_wall_cap_palette(mat: String) -> Dictionary:
	match mat:
		"wood":
			var b: Color = ProceduralTileSetBuilder.COLOR_WALL_WOOD
			return {"color": b.lightened(0.18), "hi": b.lightened(0.32), "rim": b.darkened(0.22)}
		"brick":
			var b: Color = ProceduralTileSetBuilder.COLOR_WALL_BRICK
			return {"color": b.lightened(0.20), "hi": b.lightened(0.32), "rim": b.darkened(0.28)}
		"stone":
			var b: Color = ProceduralTileSetBuilder.COLOR_WALL_STONE
			return {"color": b.lightened(0.20), "hi": b.lightened(0.32), "rim": b.darkened(0.32)}
		_:
			return {"color": Color("#2E333E"), "hi": Color("#636D82"), "rim": Color("#4B5364")}


func _rebuild_34_wall_overlays() -> void:
	_ensure_34_wall_overlay_nodes()
	_rebuild_34_wall_overlay_for_floor(0, floor0_wall_shadows, floor0_wall_crowns)
	_rebuild_34_wall_overlay_for_floor(1, floor1_wall_shadows, floor1_wall_crowns)


func _rebuild_34_wall_overlay_for_floor(
	floor_level: int,
	shadow_ov: WallDepthOverlay,
	crown_ov: WallDepthOverlay
) -> void:
	if shadow_ov == null or crown_ov == null:
		return
	shadow_ov.shadow_rects.clear()
	crown_ov.crown_entries.clear()
	var wl: TileMapLayer = get_wall_layer(floor_level)
	if wl == null:
		shadow_ov.queue_redraw()
		crown_ov.queue_redraw()
		return

	var ts: float = float(TILE_SIZE)
	for cell: Vector2i in wl.get_used_cells():
		var mat: String = _is_high_wall_cell(floor_level, cell)
		if mat.is_empty():
			continue
		var world_tl: Vector2 = Vector2(float(cell.x) * ts, float(cell.y) * ts)
		# Cast south drop shadow onto floor below this high wall when south cell is open
		if cell.y + 1 < ARENA_HEIGHT_TILES and _is_high_wall_cell(floor_level, Vector2i(cell.x, cell.y + 1)).is_empty():
			shadow_ov.shadow_rects.append(Rect2(Vector2(world_tl.x, world_tl.y + ts), Vector2(ts, 6.0)))
		# Top parapet lip overlap (7 px) for 3/4 depth behind south walls without occluding heads/flying actors
		if cell.y > 0 and _is_high_wall_cell(floor_level, Vector2i(cell.x, cell.y - 1)).is_empty():
			var pal: Dictionary = _get_wall_cap_palette(mat)
			crown_ov.crown_entries.append({
				"rect": Rect2(world_tl, Vector2(ts, 7.0)),
				"color": pal["color"],
				"hi": pal["hi"],
				"rim": pal["rim"],
			})

	shadow_ov.queue_redraw()
	crown_ov.queue_redraw()


func _place_wall_tile(floor_level: int, cell: Vector2i, atlas_coords: Vector2i) -> void:
	var layer: TileMapLayer = get_wall_layer(floor_level)
	if layer == null:
		return
	layer.set_cell(cell, 0, atlas_coords)
	var td: TileData = layer.get_cell_tile_data(cell)
	if td != null and bool(td.get_custom_data(ProceduralTileSetBuilder.DATA_DESTRUCTIBLE)):
		var dur: float = float(td.get_custom_data(ProceduralTileSetBuilder.DATA_DURABILITY))
		var floor_map: Dictionary = _wall_durability[floor_level]
		floor_map[cell] = dur


func _place_floor_tile(floor_level: int, cell: Vector2i, atlas_coords: Vector2i) -> void:
	var layer: TileMapLayer = get_floor_layer(floor_level)
	if layer == null:
		return
	layer.set_cell(cell, 0, atlas_coords)
	var td: TileData = layer.get_cell_tile_data(cell)
	if td != null and bool(td.get_custom_data(ProceduralTileSetBuilder.DATA_BREAKABLE_FLOOR)):
		var dur: float = float(td.get_custom_data(ProceduralTileSetBuilder.DATA_DURABILITY))
		var floor_map: Dictionary = _floor_durability[floor_level]
		floor_map[cell] = dur


func _configure_triggers_and_areas() -> void:
	var flm: Node = _get_floor_manager()
	var slot0_actors: int = int(flm.call("get_actors_bit", 0)) if flm != null else (1 << 2)
	var slot1_actors: int = int(flm.call("get_actors_bit", 1)) if flm != null else (1 << 5)

	_configure_area_rect(building_interior_trigger, building_interior_shape, BUILDING_INTERIOR_RECT)
	building_interior_trigger.collision_layer = FloorLayerManager.BIT_TRIGGERS_STEALTH
	building_interior_trigger.collision_mask = slot0_actors

	if safe_barrier_zone != null and safe_barrier_shape != null:
		_configure_area_rect(safe_barrier_zone, safe_barrier_shape, SAFE_ZONE_RECT)
		safe_barrier_zone.collision_layer = FloorLayerManager.BIT_TRIGGERS_STEALTH
		safe_barrier_zone.collision_mask = slot0_actors

	_configure_area_rect(floor1_support_zone, floor1_support_shape, BUILDING_RECT)
	floor1_support_zone.collision_layer = FloorLayerManager.BIT_FLOOR_SUPPORT
	floor1_support_zone.collision_mask = slot1_actors

	_configure_area_rect(stairs_area, stairs_shape, STAIRS_RECT)
	stairs_area.collision_layer = FloorLayerManager.BIT_INTERACTABLES
	stairs_area.collision_mask = slot0_actors | slot1_actors

	for cover_area: Area2D in stealth_cover_zones:
		if is_instance_valid(cover_area):
			cover_area.collision_layer = FloorLayerManager.BIT_TRIGGERS_STEALTH
			cover_area.collision_mask = slot0_actors


func _setup_stealth_cover_zones() -> void:
	if floor0_container == null:
		return
	var existing: Node = floor0_container.get_node_or_null("StealthCoverZones")
	if existing != null:
		existing.queue_free()
	stealth_cover_zones.clear()
	_entities_in_stealth_cover.clear()

	var holder: Node2D = Node2D.new()
	holder.name = "StealthCoverZones"
	floor0_container.add_child(holder)

	var flm: Node = _get_floor_manager()
	var slot0_actors: int = int(flm.call("get_actors_bit", 0)) if flm != null else (1 << 2)

	for idx: int in range(STEALTH_COVER_RECTS.size()):
		var rect_i: Rect2i = STEALTH_COVER_RECTS[idx]
		var area: Area2D = Area2D.new()
		area.name = "StealthCoverZone_%d" % idx
		area.collision_layer = FloorLayerManager.BIT_TRIGGERS_STEALTH
		area.collision_mask = slot0_actors
		area.monitoring = true
		area.monitorable = true

		var shape_node: CollisionShape2D = CollisionShape2D.new()
		shape_node.name = "CollisionShape2D"
		area.add_child(shape_node)
		_configure_area_rect(area, shape_node, rect_i)

		var half_w: float = float(rect_i.size.x * TILE_SIZE) * 0.5
		var half_h: float = float(rect_i.size.y * TILE_SIZE) * 0.5

		# Ground shadow & leafy undergrowth base above floor (-10), below actors (0)
		var base_vis: Node2D = Node2D.new()
		base_vis.name = "CoverBaseVisual"
		base_vis.z_as_relative = false
		base_vis.z_index = -3
		area.add_child(base_vis)

		var bush_shadow: Polygon2D = Polygon2D.new()
		bush_shadow.color = Color(0.0, 0.0, 0.0, 0.30)
		bush_shadow.polygon = PackedVector2Array([
			Vector2(-half_w + 1.0, -half_h + 6.0),
			Vector2(half_w - 1.0, -half_h + 6.0),
			Vector2(half_w + 2.0, half_h + 2.0),
			Vector2(-half_w + 1.0, half_h + 3.0),
		])
		base_vis.add_child(bush_shadow)

		var fill: Polygon2D = Polygon2D.new()
		fill.color = COLOR_STEALTH_COVER_FILL
		fill.polygon = PackedVector2Array([
			Vector2(-half_w + 3.0, -half_h + 3.0),
			Vector2(half_w - 3.0, -half_h + 3.0),
			Vector2(half_w - 1.0, half_h - 2.0),
			Vector2(-half_w + 2.0, half_h - 1.0),
		])
		base_vis.add_child(fill)

		var border: Line2D = Line2D.new()
		border.width = 1.4
		border.default_color = COLOR_STEALTH_COVER_BORDER
		border.closed = true
		border.points = fill.polygon
		base_vis.add_child(border)

		# Volumetric 3/4 bush crowns just above crouching actors (translucent foliage clusters)
		var canopy_vis: Node2D = Node2D.new()
		canopy_vis.name = "CoverCanopyVisual"
		canopy_vis.z_as_relative = false
		canopy_vis.z_index = 4
		area.add_child(canopy_vis)

		var tuft_offsets: Array[Vector2] = [
			Vector2(-half_w * 0.44, -half_h * 0.36),
			Vector2(half_w * 0.40, -half_h * 0.28),
			Vector2(0.0, -half_h * 0.05),
			Vector2(-half_w * 0.28, half_h * 0.30),
			Vector2(half_w * 0.32, half_h * 0.34),
		]
		for t_idx: int in range(tuft_offsets.size()):
			var t_off: Vector2 = tuft_offsets[t_idx]
			var mound_root: Node2D = Node2D.new()
			mound_root.position = t_off
			canopy_vis.add_child(mound_root)

			# Lower shaded 3/4 bush body
			var bush_low: Polygon2D = Polygon2D.new()
			bush_low.color = Color(0.06, 0.22, 0.12, 0.56)
			bush_low.polygon = PackedVector2Array([
				Vector2(-12.0, 1.0),
				Vector2(-8.0, -7.0),
				Vector2(0.0, -9.0),
				Vector2(9.0, -6.0),
				Vector2(12.0, 2.0),
				Vector2(7.0, 9.0),
				Vector2(-7.0, 9.0),
			])
			mound_root.add_child(bush_low)

			# Mid leafy crown shifted up slightly for 3/4 volume
			var bush_mid: Polygon2D = Polygon2D.new()
			bush_mid.color = Color(0.12, 0.38, 0.21, 0.54)
			bush_mid.polygon = PackedVector2Array([
				Vector2(-10.0, -2.0),
				Vector2(-4.0, -10.0),
				Vector2(5.0, -9.0),
				Vector2(10.0, -1.0),
				Vector2(5.0, 5.0),
				Vector2(-6.0, 5.0),
			])
			mound_root.add_child(bush_mid)

			# Top-lit leaf highlight cluster
			var bush_hi: Polygon2D = Polygon2D.new()
			bush_hi.color = Color(0.24, 0.56, 0.30, 0.48)
			bush_hi.polygon = PackedVector2Array([
				Vector2(-6.0, -6.0),
				Vector2(-1.0, -10.5),
				Vector2(5.0, -8.5),
				Vector2(2.0, -3.5),
				Vector2(-4.0, -3.0),
			])
			mound_root.add_child(bush_hi)

			var bush_rim: Line2D = Line2D.new()
			bush_rim.points = bush_low.polygon
			bush_rim.closed = true
			bush_rim.width = 1.0
			bush_rim.default_color = Color(0.04, 0.14, 0.08, 0.55)
			mound_root.add_child(bush_rim)

		area.body_entered.connect(_on_stealth_cover_body_entered)
		area.body_exited.connect(_on_stealth_cover_body_exited)
		holder.add_child(area)
		stealth_cover_zones.append(area)


func _on_stealth_cover_body_entered(body: Node) -> void:
	if body == null or not is_instance_valid(body):
		return
	var id: int = body.get_instance_id()
	_entities_in_stealth_cover[id] = int(_entities_in_stealth_cover.get(id, 0)) + 1
	if body is CombatActor:
		(body as CombatActor)._refresh_status_tint()


func _on_stealth_cover_body_exited(body: Node) -> void:
	if body == null or not is_instance_valid(body):
		return
	var id: int = body.get_instance_id()
	var cnt: int = int(_entities_in_stealth_cover.get(id, 0)) - 1
	if cnt <= 0:
		_entities_in_stealth_cover.erase(id)
	else:
		_entities_in_stealth_cover[id] = cnt
	if body is CombatActor:
		(body as CombatActor)._refresh_status_tint()


func _build_safe_zone_visual() -> void:
	if safe_barrier_zone == null:
		return
	var existing: Node = safe_barrier_zone.get_node_or_null("SafeZoneVisual")
	if existing != null:
		existing.queue_free()

	var vis: Node2D = Node2D.new()
	vis.name = "SafeZoneVisual"
	vis.z_as_relative = false
	vis.z_index = -4
	safe_barrier_zone.add_child(vis)

	var half_w: float = float(SAFE_ZONE_RECT.size.x * TILE_SIZE) * 0.5
	var half_h: float = float(SAFE_ZONE_RECT.size.y * TILE_SIZE) * 0.5

	var fill: Polygon2D = Polygon2D.new()
	fill.color = ProceduralTileSetBuilder.COLOR_SAFE_BARRIER_FILL
	fill.polygon = PackedVector2Array([
		Vector2(-half_w, -half_h),
		Vector2(half_w, -half_h),
		Vector2(half_w, half_h),
		Vector2(-half_w, half_h),
	])
	vis.add_child(fill)

	# Procedural dashed blue perimeter (GDD 14.3)
	var edges: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(-half_w, -half_h), Vector2(half_w, -half_h)]),
		PackedVector2Array([Vector2(half_w, -half_h), Vector2(half_w, half_h)]),
		PackedVector2Array([Vector2(half_w, half_h), Vector2(-half_w, half_h)]),
		PackedVector2Array([Vector2(-half_w, half_h), Vector2(-half_w, -half_h)]),
	]
	for edge: PackedVector2Array in edges:
		var a: Vector2 = edge[0]
		var b: Vector2 = edge[1]
		var length: float = a.distance_to(b)
		var dir: Vector2 = (b - a).normalized()
		var pos: float = 0.0
		while pos < length:
			var dash_end: float = minf(pos + 6.0, length)
			var dash_line: Line2D = Line2D.new()
			dash_line.width = 2.0
			dash_line.default_color = ProceduralTileSetBuilder.COLOR_SAFE_BARRIER_BORDER
			dash_line.points = PackedVector2Array([a + dir * pos, a + dir * dash_end])
			vis.add_child(dash_line)
			pos += 11.0

	var lbl: Label = Label.new()
	lbl.text = "SAFE ZONE"
	lbl.add_theme_font_size_override("font_size", 8)
	lbl.add_theme_color_override("font_color", Color("#74B9FF"))
	lbl.position = Vector2(-24.0, -6.0)
	vis.add_child(lbl)


func _configure_area_rect(area: Area2D, shape_node: CollisionShape2D, tile_rect: Rect2i) -> void:
	var size_px: Vector2 = Vector2(float(tile_rect.size.x * TILE_SIZE), float(tile_rect.size.y * TILE_SIZE))
	var center_px: Vector2 = Vector2(float(tile_rect.position.x * TILE_SIZE), float(tile_rect.position.y * TILE_SIZE)) + size_px * 0.5
	area.position = center_px
	var rect_shape: RectangleShape2D = RectangleShape2D.new()
	rect_shape.size = size_px
	shape_node.shape = rect_shape


func _sync_floor_layer_manager() -> void:
	var flm: Node = _get_floor_manager()
	if flm == null:
		return
	flm.call("reset", 0)
	flm.call("sync_from_tile_map_layer", 0, floor0_floor_layer)
	flm.call("sync_from_tile_map_layer", 1, floor1_floor_layer)


func _connect_signals() -> void:
	var flm: Node = _get_floor_manager()
	if flm != null and flm.has_signal("active_window_changed"):
		var cb: Callable = Callable(self, "_on_active_window_changed")
		if not flm.is_connected("active_window_changed", cb):
			flm.connect("active_window_changed", cb)

	if not building_interior_trigger.body_entered.is_connected(_on_building_interior_body_entered):
		building_interior_trigger.body_entered.connect(_on_building_interior_body_entered)
	if not building_interior_trigger.body_exited.is_connected(_on_building_interior_body_exited):
		building_interior_trigger.body_exited.connect(_on_building_interior_body_exited)
	if safe_barrier_zone != null:
		if not safe_barrier_zone.body_entered.is_connected(_on_safe_zone_body_entered):
			safe_barrier_zone.body_entered.connect(_on_safe_zone_body_entered)
		if not safe_barrier_zone.body_exited.is_connected(_on_safe_zone_body_exited):
			safe_barrier_zone.body_exited.connect(_on_safe_zone_body_exited)
	if not stairs_area.body_entered.is_connected(_on_stairs_body_entered):
		stairs_area.body_entered.connect(_on_stairs_body_entered)
	if not stairs_area.body_exited.is_connected(_on_stairs_body_exited):
		stairs_area.body_exited.connect(_on_stairs_body_exited)

	_connect_event_bus()


func _connect_event_bus() -> void:
	if EventBus == null:
		return
	if not EventBus.limb_severed.is_connected(_on_eventbus_limb_severed):
		EventBus.limb_severed.connect(_on_eventbus_limb_severed)
	if not EventBus.blood_effect_requested.is_connected(_on_eventbus_blood_requested):
		EventBus.blood_effect_requested.connect(_on_eventbus_blood_requested)
	if not EventBus.spark_effect_requested.is_connected(_on_eventbus_sparks_requested):
		EventBus.spark_effect_requested.connect(_on_eventbus_sparks_requested)
	if not EventBus.noise_emitted.is_connected(_on_eventbus_noise_emitted):
		EventBus.noise_emitted.connect(_on_eventbus_noise_emitted)
	if not EventBus.wall_slammed.is_connected(_on_eventbus_wall_slammed):
		EventBus.wall_slammed.connect(_on_eventbus_wall_slammed)
	if not EventBus.floor_changed.is_connected(_on_eventbus_floor_changed):
		EventBus.floor_changed.connect(_on_eventbus_floor_changed)
	if not EventBus.combat_outcome_logged.is_connected(_on_eventbus_combat_outcome_logged):
		EventBus.combat_outcome_logged.connect(_on_eventbus_combat_outcome_logged)
	if not EventBus.blade_clashed.is_connected(_on_eventbus_blade_clashed):
		EventBus.blade_clashed.connect(_on_eventbus_blade_clashed)
	if not EventBus.hour_changed.is_connected(_on_eventbus_hour_changed):
		EventBus.hour_changed.connect(_on_eventbus_hour_changed)
	if not EventBus.day_passed.is_connected(_on_eventbus_day_passed):
		EventBus.day_passed.connect(_on_eventbus_day_passed)
	if not EventBus.blood_moon_changed.is_connected(_on_eventbus_blood_moon_changed):
		EventBus.blood_moon_changed.connect(_on_eventbus_blood_moon_changed)


func _disconnect_event_bus() -> void:
	if EventBus == null:
		return
	if EventBus.limb_severed.is_connected(_on_eventbus_limb_severed):
		EventBus.limb_severed.disconnect(_on_eventbus_limb_severed)
	if EventBus.blood_effect_requested.is_connected(_on_eventbus_blood_requested):
		EventBus.blood_effect_requested.disconnect(_on_eventbus_blood_requested)
	if EventBus.spark_effect_requested.is_connected(_on_eventbus_sparks_requested):
		EventBus.spark_effect_requested.disconnect(_on_eventbus_sparks_requested)
	if EventBus.noise_emitted.is_connected(_on_eventbus_noise_emitted):
		EventBus.noise_emitted.disconnect(_on_eventbus_noise_emitted)
	if EventBus.wall_slammed.is_connected(_on_eventbus_wall_slammed):
		EventBus.wall_slammed.disconnect(_on_eventbus_wall_slammed)
	if EventBus.floor_changed.is_connected(_on_eventbus_floor_changed):
		EventBus.floor_changed.disconnect(_on_eventbus_floor_changed)
	if EventBus.combat_outcome_logged.is_connected(_on_eventbus_combat_outcome_logged):
		EventBus.combat_outcome_logged.disconnect(_on_eventbus_combat_outcome_logged)
	if EventBus.blade_clashed.is_connected(_on_eventbus_blade_clashed):
		EventBus.blade_clashed.disconnect(_on_eventbus_blade_clashed)
	if EventBus.hour_changed.is_connected(_on_eventbus_hour_changed):
		EventBus.hour_changed.disconnect(_on_eventbus_hour_changed)
	if EventBus.day_passed.is_connected(_on_eventbus_day_passed):
		EventBus.day_passed.disconnect(_on_eventbus_day_passed)
	if EventBus.blood_moon_changed.is_connected(_on_eventbus_blood_moon_changed):
		EventBus.blood_moon_changed.disconnect(_on_eventbus_blood_moon_changed)


func _on_eventbus_hour_changed(_new_hour: int) -> void:
	update_ambient_lighting()


func _on_eventbus_day_passed(_total_days: int) -> void:
	update_ambient_lighting()


func _on_eventbus_blood_moon_changed(_is_blood_moon: bool) -> void:
	update_ambient_lighting()


func _on_active_window_changed(_focus_floor: int, _min_floor: int, _max_floor: int) -> void:
	ProceduralTileSetBuilder.update_tileset_floor_layers(floor0_tileset, 0)
	ProceduralTileSetBuilder.update_tileset_floor_layers(floor1_tileset, 1)
	_configure_triggers_and_areas()


# ---------------------------------------------------------------------------
# Procedural Decals, Severed Limbs, Sparks & Sensory Queries (GDD 7.4, 14.3)
# ---------------------------------------------------------------------------

func _on_eventbus_limb_severed(entity: Node, zone: StringName, attacker: Node) -> void:
	if entity == null or not is_instance_valid(entity) or not (entity is Node2D):
		return
	var ent_2d: Node2D = entity as Node2D
	var vc: VerticalityComponent = _find_verticality_component(entity)
	var fl: int = vc.floor_level if vc != null else 0
	var limb_col: Color = Color("#C0392B")
	if entity is CombatActor:
		limb_col = (entity as CombatActor).actor_body_color.darkened(0.18)
	var fly_dir: Vector2 = Vector2.RIGHT
	if attacker is Node2D:
		fly_dir = (ent_2d.global_position - (attacker as Node2D).global_position).normalized()
	if fly_dir.length_squared() <= 0.001:
		fly_dir = Vector2(1.0, 0.3).normalized()
	spawn_severed_limb(ent_2d.global_position, fl, zone, limb_col, fly_dir)


func _on_eventbus_blood_requested(world_pos: Vector2, floor_level: int, direction: Vector2, amount: float, is_trail: bool) -> void:
	spawn_blood_decal(world_pos, floor_level, direction, amount, is_trail)


func _on_eventbus_sparks_requested(world_pos: Vector2, floor_level: int, height_z: float, color: Color, count: int) -> void:
	spawn_sparks(world_pos, floor_level, height_z, color, count)


func _on_eventbus_noise_emitted(world_pos: Vector2, floor_level: int, radius_px: float, source: Node) -> void:
	record_noise(world_pos, floor_level, radius_px, source)


func _on_eventbus_wall_slammed(entity: Node, cell: Vector2i, _impulse: float, wall_broken: bool) -> void:
	var vc: VerticalityComponent = _find_verticality_component(entity)
	var fl: int = vc.floor_level if vc != null else 0
	var pos: Vector2 = cell_to_world_center(cell)
	spawn_sparks(pos, fl, 0.0, Color("#FFD166") if not wall_broken else Color("#FF9F43"), 10 if wall_broken else 6)
	spawn_floating_callout(
		pos,
		fl,
		0.0,
		"WALL BREAK!" if wall_broken else "WALL SLAM!",
		Color("#FF9F43") if wall_broken else Color("#FFD166")
	)
	record_noise(pos, fl, 280.0 if wall_broken else 190.0, entity)
	if EventBus != null:
		EventBus.request_camera_shake(6.0 if wall_broken else 4.0, 0.20)


func _on_eventbus_combat_outcome_logged(outcome_data: Dictionary) -> void:
	var raw_outcome: String = String(outcome_data.get("outcome", ""))
	if raw_outcome.is_empty():
		return
	var target_var: Variant = outcome_data.get("target", null)
	var attacker_var: Variant = outcome_data.get("attacker", null)
	var anchor_node: Node2D = null
	if target_var is Node2D and is_instance_valid(target_var as Node2D):
		anchor_node = target_var as Node2D
	elif attacker_var is Node2D and is_instance_valid(attacker_var as Node2D):
		anchor_node = attacker_var as Node2D
	if anchor_node == null:
		return

	var vc: VerticalityComponent = _find_verticality_component(anchor_node)
	var fl: int = vc.floor_level if vc != null else 0
	var hz: float = vc.height_z if vc != null else 0.0
	var pos: Vector2 = anchor_node.global_position
	var is_wp: bool = bool(outcome_data.get("is_weak_point", false))
	var is_severed: bool = bool(outcome_data.get("severed", false))
	var is_lodged: bool = bool(outcome_data.get("lodged", false))

	var text: String = ""
	var col: Color = Color("#FFE875")
	if raw_outcome == "parried":
		text = "PARRY!"
		col = Color("#74EBD5")
	elif raw_outcome == "guard_break_hit":
		text = "GUARD BREAK!"
		col = Color("#FF6B6B")
	elif raw_outcome == "dismembered" or is_severed:
		text = "SEVERED!"
		col = Color("#FF3838")
	elif raw_outcome == "hardening_lodged" or raw_outcome == "weapon_lodged" or is_lodged:
		text = "LODGED!"
		col = Color("#FFA502")
	elif raw_outcome == "hardening_bounce":
		text = "BOUNCE!"
		col = Color("#A8E6CF")
	elif raw_outcome == "out_of_vertical_reach":
		text = "OUT OF REACH [F]"
		col = Color("#FF7979")
	elif raw_outcome == "imperceptible_speed_fatal":
		text = "IMPERCEPTIBLE!"
		col = Color("#FF4757")
	elif raw_outcome == "unarmed_block_cut":
		text = "HAND CUT!"
		col = Color("#FF6B6B")
	elif raw_outcome == "dodged":
		text = "DODGE"
		col = Color("#A3D9E8")
	elif raw_outcome == "stealth_takedown":
		text = "TAKEDOWN!"
		col = Color("#74EBD5")
	elif raw_outcome == "stealth_takedown_resisted":
		text = "RESISTED!"
		col = Color("#FF6B6B")
	elif raw_outcome == "penetrated" and is_wp:
		text = "BACKSTAB!" if bool(outcome_data.get("is_stealth_backstab", false)) else "WEAK-POINT!"
		col = Color("#FFD166")
	elif raw_outcome == "penetrated" and bool(outcome_data.get("is_counter", false)):
		text = "COUNTER!"
		col = Color("#70A1FF")

	if not text.is_empty():
		spawn_floating_callout(pos, fl, hz, text, col)


func _on_eventbus_blade_clashed(clash_data: Dictionary) -> void:
	var pos: Vector2 = Vector2.ZERO
	var has_pos: bool = false
	var pos_var: Variant = clash_data.get("position", null)
	if pos_var is Vector2:
		pos = pos_var as Vector2
		has_pos = true
	var fl: int = int(clash_data.get("floor_level", 0))
	var hz: float = float(clash_data.get("height_z", 0.0))
	if not has_pos:
		var a_var: Variant = clash_data.get("actor_a", null)
		var b_var: Variant = clash_data.get("actor_b", null)
		if a_var is Node2D and is_instance_valid(a_var as Node2D) and b_var is Node2D and is_instance_valid(b_var as Node2D):
			pos = ((a_var as Node2D).global_position + (b_var as Node2D).global_position) * 0.5
			var vc: VerticalityComponent = _find_verticality_component(a_var as Node)
			if vc != null:
				fl = vc.floor_level
				hz = vc.height_z
			has_pos = true
		elif a_var is Node2D and is_instance_valid(a_var as Node2D):
			pos = (a_var as Node2D).global_position
			has_pos = true
	if not has_pos:
		pos = focus_entity.global_position if (focus_entity != null and is_instance_valid(focus_entity)) else cell_to_world_center(Vector2i(10, 6))
	var broken: bool = bool(clash_data.get("weapon_a_broken", false)) or bool(clash_data.get("weapon_b_broken", false))
	spawn_floating_callout(
		pos,
		fl,
		hz,
		"CLASH! BREAK" if broken else "CLASH!",
		Color("#FF9F43") if broken else Color("#FFE875")
	)


## Spawns a physical severed limb Polygon2D + dark blood puddle on floor_level * 100 (GDD 14.3).
func spawn_severed_limb(
	world_pos: Vector2,
	floor_level: int,
	zone_name: StringName,
	limb_color: Color = Color("#A88B73"),
	impulse_dir: Vector2 = Vector2.RIGHT
) -> Node2D:
	if decals_container == null:
		return null

	var limb: Polygon2D = Polygon2D.new()
	limb.name = "Severed_%s" % String(zone_name)
	limb.color = limb_color
	limb.z_as_relative = false
	limb.z_index = floor_level * 100
	limb.set_meta(&"zone_name", zone_name)
	limb.set_meta(&"floor_level", floor_level)

	if zone_name == AnatomyComponent.ZONE_NECK or zone_name == AnatomyComponent.ZONE_HEAD:
		limb.polygon = PackedVector2Array([
			Vector2(-5.2, -4.8), Vector2(5.2, -4.8),
			Vector2(6.0, 0.0), Vector2(4.6, 5.2),
			Vector2(-4.6, 5.2), Vector2(-6.0, 0.0),
		])
		var cap: Polygon2D = Polygon2D.new()
		cap.color = limb_color.darkened(0.32)
		cap.polygon = PackedVector2Array([
			Vector2(-5.4, -1.0), Vector2(-4.8, -5.0),
			Vector2(4.8, -5.0), Vector2(5.4, -1.0),
		])
		limb.add_child(cap)
		var neck_cut: Polygon2D = Polygon2D.new()
		neck_cut.color = Color("#9B111E")
		neck_cut.polygon = PackedVector2Array([
			Vector2(-2.6, 3.6), Vector2(2.6, 3.6),
			Vector2(2.0, 5.8), Vector2(-2.0, 5.8),
		])
		limb.add_child(neck_cut)
	elif zone_name == AnatomyComponent.ZONE_WINGS:
		limb.color = Color("#D2E0EC")
		limb.polygon = PackedVector2Array([
			Vector2(-9.0, -2.0), Vector2(2.0, -6.0),
			Vector2(10.0, -1.0), Vector2(5.0, 4.5),
			Vector2(-8.0, 3.0),
		])
	else:
		limb.polygon = PackedVector2Array([
			Vector2(-6.2, -2.4), Vector2(5.8, -2.2),
			Vector2(6.2, 2.2), Vector2(-6.2, 2.4),
		])
		var cut_end: Polygon2D = Polygon2D.new()
		cut_end.color = Color("#A8121E")
		cut_end.polygon = PackedVector2Array([
			Vector2(-6.6, -2.3), Vector2(-4.2, -2.1),
			Vector2(-4.2, 2.1), Vector2(-6.6, 2.3),
		])
		limb.add_child(cut_end)
		var end_cap: Polygon2D = Polygon2D.new()
		end_cap.color = Color("#3D2D24")
		end_cap.polygon = PackedVector2Array([
			Vector2(2.2, -2.4), Vector2(6.8, -2.4),
			Vector2(7.4, 2.4), Vector2(2.2, 2.4),
		])
		limb.add_child(end_cap)

	var limb_out: Line2D = Line2D.new()
	limb_out.points = limb.polygon
	limb_out.closed = true
	limb_out.width = 1.0
	limb_out.default_color = Color("#14161E")
	limb.add_child(limb_out)

	var dir: Vector2 = impulse_dir.normalized() if impulse_dir.length_squared() > 0.001 else Vector2.RIGHT
	limb.position = world_pos
	limb.rotation = dir.angle()
	decals_container.add_child(limb)
	severed_limb_nodes.append(limb)
	_apply_floor_visibility_to_node(limb, floor_level)

	var landing_pos: Vector2 = world_pos + dir * 20.0
	if is_inside_tree():
		var tw: Tween = limb.create_tween()
		tw.set_parallel(true)
		tw.tween_property(limb, "position", landing_pos, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(limb, "rotation", limb.rotation + 2.4, 0.22)
	else:
		limb.position = landing_pos

	# Spawn blood pool beneath sever point and landing spot
	spawn_blood_decal(world_pos, floor_level, dir, 2.0, false)
	spawn_blood_decal(landing_pos, floor_level, dir, 1.5, true)

	while severed_limb_nodes.size() > MAX_SEVERED_LIMBS:
		var old_limb: Node2D = severed_limb_nodes.pop_front() as Node2D
		if is_instance_valid(old_limb):
			old_limb.queue_free()

	return limb


func spawn_blood_decal(
	world_pos: Vector2,
	floor_level: int,
	direction: Vector2 = Vector2.RIGHT,
	amount: float = 1.0,
	is_trail: bool = false
) -> Node2D:
	if decals_container == null:
		return null

	var puddle: Polygon2D = Polygon2D.new()
	puddle.z_as_relative = false
	puddle.z_index = floor_level * 100
	puddle.color = Color(0.50, 0.04, 0.06, 0.72 if is_trail else 0.85)
	var radius: float = clampf((3.2 if is_trail else 6.0) * clampf(amount, 0.5, 2.5), 2.5, 16.0)
	var pts: PackedVector2Array = PackedVector2Array()
	var segs: int = 8
	pts.resize(segs)
	for i: int in range(segs):
		var a: float = TAU * float(i) / float(segs)
		var jitter: float = 0.80 + 0.35 * absf(sin(float(i) * 2.3 + world_pos.x * 0.1))
		pts[i] = Vector2(cos(a) * radius * jitter, sin(a) * radius * 0.78 * jitter)
	puddle.polygon = pts
	puddle.position = world_pos
	puddle.set_meta(&"floor_level", floor_level)
	decals_container.add_child(puddle)
	blood_decal_nodes.append(puddle)
	_apply_floor_visibility_to_node(puddle, floor_level)

	blood_trail_points.append({
		"pos": world_pos,
		"floor": floor_level,
		"age": 0.0,
		"node": puddle,
	})

	# Directional blood spray particles on active impacts
	if not is_trail and effects_container != null and is_inside_tree():
		var dir: Vector2 = direction.normalized() if direction.length_squared() > 0.001 else Vector2.RIGHT
		var drops: int = clampi(int(roundf(4.0 * amount)), 3, 10)
		for i: int in range(drops):
			var drop: Polygon2D = Polygon2D.new()
			drop.z_as_relative = false
			drop.z_index = floor_level * 100 + 4
			drop.color = Color("#B8141C")
			drop.polygon = PackedVector2Array([Vector2(-2.0, -1.0), Vector2(2.5, 0.0), Vector2(-2.0, 1.0)])
			var spread: float = (float(i) / float(maxi(1, drops - 1)) - 0.5) * 0.95
			var vdir: Vector2 = dir.rotated(spread)
			drop.position = world_pos
			drop.rotation = vdir.angle()
			effects_container.add_child(drop)
			var dist_px: float = 12.0 + float(i % 4) * 7.0
			var tw: Tween = drop.create_tween()
			tw.set_parallel(true)
			tw.tween_property(drop, "position", world_pos + vdir * dist_px, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(drop, "modulate:a", 0.0, 0.20)
			tw.chain().tween_callback(drop.queue_free)

	while blood_decal_nodes.size() > MAX_BLOOD_DECALS:
		var old_d: Node2D = blood_decal_nodes.pop_front() as Node2D
		if is_instance_valid(old_d):
			old_d.queue_free()

	return puddle


func spawn_sparks(
	world_pos: Vector2,
	floor_level: int,
	height_z: float = 0.0,
	color: Color = Color("#FFE875"),
	count: int = 6
) -> void:
	if effects_container == null or not is_inside_tree():
		return
	var spark_z: int = floor_level * 100 + int(height_z * 10.0) + 5
	var n_sparks: int = clampi(count, 2, 14)
	for i: int in range(n_sparks):
		var tri: Polygon2D = Polygon2D.new()
		tri.z_as_relative = false
		tri.z_index = spark_z
		tri.color = color if (i % 2 == 0) else Color("#FFFFFF")
		tri.polygon = PackedVector2Array([Vector2(-2.5, -1.2), Vector2(4.0, 0.0), Vector2(-2.5, 1.2)])
		var ang: float = TAU * float(i) / float(n_sparks) + 0.25
		var dir: Vector2 = Vector2.from_angle(ang)
		tri.position = world_pos
		tri.rotation = ang
		effects_container.add_child(tri)
		active_spark_count += 1
		tri.tree_exiting.connect(_on_spark_exiting, CONNECT_ONE_SHOT)
		var dist_px: float = 14.0 + float((i * 7) % 14)
		var tw: Tween = tri.create_tween()
		tw.set_parallel(true)
		tw.tween_property(tri, "position", world_pos + dir * dist_px, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(tri, "modulate:a", 0.0, 0.18)
		tw.chain().tween_callback(tri.queue_free)


func _on_spark_exiting() -> void:
	active_spark_count = maxi(0, active_spark_count - 1)


## Spawns a short tweened world-space combat impact callout (PARRY!, CLASH!, WEAK-POINT!, etc.).
## Tween is bound directly to the Label node so tearing down the arena never leaks ObjectDB refs.
func spawn_floating_callout(
	world_pos: Vector2,
	floor_level: int,
	height_z: float = 0.0,
	text: String = "",
	color: Color = Color("#FFE875")
) -> Label:
	if text.is_empty() or effects_container == null or not is_inside_tree():
		return null
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.custom_minimum_size = Vector2(96.0, 0.0)
	lbl.add_theme_font_size_override("font_size", 7)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.08, 0.95))
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.focus_mode = Control.FOCUS_NONE
	lbl.z_as_relative = false
	lbl.z_index = floor_level * 100 + int(height_z * 10.0) + 30
	var start_pos: Vector2 = world_pos + Vector2(-48.0, -24.0 - height_z * 12.0)
	lbl.position = start_pos
	lbl.set_meta(&"floor_level", floor_level)
	effects_container.add_child(lbl)
	active_floating_callout_count += 1
	last_floating_callout_text = text
	lbl.tree_exiting.connect(_on_floating_callout_exiting, CONNECT_ONE_SHOT)

	var tw: Tween = lbl.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position", start_pos + Vector2(0.0, -18.0), 0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(lbl.queue_free)
	return lbl


func _on_floating_callout_exiting() -> void:
	active_floating_callout_count = maxi(0, active_floating_callout_count - 1)


## Spawns a short expanding acoustic ripple ring on the floor (e.g., stone distraction T).
func spawn_noise_ripple(
	world_pos: Vector2,
	floor_level: int,
	radius_px: float = 170.0,
	color: Color = Color(0.95, 0.88, 0.45, 0.85)
) -> Node2D:
	if effects_container == null or not is_inside_tree():
		return null
	var ripple: NoiseRippleDrawer = NoiseRippleDrawer.new()
	ripple.name = "NoiseRipple"
	ripple.position = world_pos
	ripple.radius_px = 4.0
	ripple.ring_color = color
	ripple.z_as_relative = false
	ripple.z_index = floor_level * 100 - 1
	ripple.set_meta(&"floor_level", floor_level)
	effects_container.add_child(ripple)
	active_noise_ripple_count += 1
	ripple.tree_exiting.connect(_on_noise_ripple_exiting, CONNECT_ONE_SHOT)

	var max_visual_r: float = clampf(radius_px * 0.35, 22.0, 66.0)
	var tw: Tween = ripple.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ripple, "radius_px", max_visual_r, 0.50).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(ripple, "modulate:a", 0.0, 0.52).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(ripple.queue_free)
	return ripple


func _on_noise_ripple_exiting() -> void:
	active_noise_ripple_count = maxi(0, active_noise_ripple_count - 1)


func record_noise(world_pos: Vector2, floor_level: int, radius_px: float, source: Node = null) -> void:
	if radius_px <= 0.0:
		return
	recent_noises.append({
		"pos": world_pos,
		"floor": floor_level,
		"radius": radius_px,
		"age": 0.0,
		"source": source,
	})
	if recent_noises.size() > 32:
		recent_noises.pop_front()


func find_loudest_noise_for(listener_pos: Vector2, listener_floor: int, ignore_source: Node = null) -> Dictionary:
	var best: Dictionary = {}
	var best_score: float = 0.0
	for rec: Dictionary in recent_noises:
		if rec.get("source", null) == ignore_source:
			continue
		var n_floor: int = int(rec.get("floor", 0))
		var floor_diff: int = absi(listener_floor - n_floor)
		if floor_diff > 1:
			continue
		var eff_radius: float = float(rec.get("radius", 0.0)) * (CROSS_FLOOR_NOISE_ATTENUATION if floor_diff == 1 else 1.0)
		var dist: float = listener_pos.distance_to(rec["pos"] as Vector2)
		if dist <= eff_radius:
			var score: float = eff_radius - dist
			if score > best_score:
				best_score = score
				best = rec
	return best


func find_recent_blood_trail(origin_pos: Vector2, floor_level: int, smell_radius_px: float) -> Dictionary:
	var best: Dictionary = {}
	var best_age: float = INF
	for rec: Dictionary in blood_trail_points:
		if int(rec.get("floor", 0)) != floor_level:
			continue
		var pos: Vector2 = rec["pos"] as Vector2
		if origin_pos.distance_to(pos) <= smell_radius_px:
			var age: float = float(rec.get("age", INF))
			if age < best_age:
				best_age = age
				best = rec
	return best


# ---------------------------------------------------------------------------
# Safe Zone Queries (GDD 14.3)
# ---------------------------------------------------------------------------

func is_position_in_safe_zone(world_pos: Vector2, floor_level: int = 0) -> bool:
	if floor_level != 0:
		return false
	return SAFE_ZONE_RECT.has_point(world_to_cell(world_pos))


func is_entity_in_safe_zone(entity: Node) -> bool:
	if entity == null or not is_instance_valid(entity):
		return false
	if entity is Node2D:
		var vc: VerticalityComponent = _find_verticality_component(entity)
		var fl: int = vc.floor_level if vc != null else 0
		var in_rect: bool = is_position_in_safe_zone((entity as Node2D).global_position, fl)
		if not in_rect and _entities_in_safe_zone.has(entity):
			_entities_in_safe_zone.erase(entity)
		return in_rect
	return _entities_in_safe_zone.has(entity)


func notify_entity_entered_safe_zone(entity: Node) -> void:
	if entity == null or not is_instance_valid(entity):
		return
	if not _entities_in_safe_zone.has(entity):
		_entities_in_safe_zone.append(entity)
	if entities_container != null:
		for child: Node in entities_container.get_children():
			if child is EnemyDummy:
				(child as EnemyDummy).on_target_entered_safe_zone(entity)
	entity_entered_safe_zone.emit(entity)


# ---------------------------------------------------------------------------
# Stealth Cover Zones (Layer 18 Triggers_Stealth) & Visibility Factor
# ---------------------------------------------------------------------------

func is_position_in_stealth_cover(world_pos: Vector2, floor_level: int = 0) -> bool:
	if floor_level != 0:
		return false
	var cell: Vector2i = world_to_cell(world_pos)
	for rect_i: Rect2i in STEALTH_COVER_RECTS:
		if rect_i.has_point(cell):
			return true
	return false


func is_entity_in_stealth_cover(entity: Node) -> bool:
	if entity == null or not is_instance_valid(entity) or not (entity is Node2D):
		return false
	var vc: VerticalityComponent = _find_verticality_component(entity)
	var fl: int = vc.floor_level if vc != null else 0
	var hz: float = vc.height_z if vc != null else 0.0
	if fl != 0 or hz >= FloorLayerManager.LOW_OBSTACLE_CLEARANCE_Z:
		return false
	return is_position_in_stealth_cover((entity as Node2D).global_position, fl)


## Computes effective visual detection multiplier for `actor` (standing=1.0, crouch=0.58, crouch+cover=0.25),
## scaling with actor_size_mult (larger bodies harder to hide) and WorldCalendar.is_night().
func get_stealth_visibility_factor(actor: CombatActor) -> float:
	if actor == null or not is_instance_valid(actor):
		return 1.0
	var in_cover: bool = is_entity_in_stealth_cover(actor)
	var low_profile: bool = actor.is_crouching or actor.is_prone()
	var base: float = 1.0
	if low_profile and in_cover:
		base = 0.25
	elif low_profile:
		base = 0.58
	elif in_cover:
		base = 0.78
	var size_mult: float = clampf(pow(maxf(0.5, actor.actor_size_mult), 0.75), 0.65, 1.85)
	var night_mult: float = 1.0
	if WorldCalendar != null and WorldCalendar.is_night() and not WorldCalendar.is_blood_moon():
		night_mult = 0.78
	return clampf(base * size_mult * night_mult, 0.12, 1.85)


# ---------------------------------------------------------------------------
# Navigation Grids (Per-Floor AStarGrid2D)
# ---------------------------------------------------------------------------

func _rebuild_all_nav_grids() -> void:
	_nav_grids.clear()
	_nav_grids[0] = _build_nav_grid_for_floor(0)
	_nav_grids[1] = _build_nav_grid_for_floor(1)


func _build_nav_grid_for_floor(floor_level: int) -> AStarGrid2D:
	var grid: AStarGrid2D = AStarGrid2D.new()
	grid.region = Rect2i(0, 0, ARENA_WIDTH_TILES, ARENA_HEIGHT_TILES)
	grid.cell_size = Vector2(float(TILE_SIZE), float(TILE_SIZE))
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()

	for x: int in range(ARENA_WIDTH_TILES):
		for y: int in range(ARENA_HEIGHT_TILES):
			var cell: Vector2i = Vector2i(x, y)
			grid.set_point_solid(cell, not _compute_cell_walkable(floor_level, cell))
	return grid


func _compute_cell_walkable(floor_level: int, cell: Vector2i) -> bool:
	var flm: Node = _get_floor_manager()
	if flm != null and not bool(flm.call("has_floor_at", floor_level, cell)):
		return false
	return not is_wall_solid_at(floor_level, cell)


func is_cell_walkable(floor_level: int, cell: Vector2i) -> bool:
	if not _nav_grids.has(floor_level):
		return false
	var grid: AStarGrid2D = _nav_grids[floor_level]
	if not grid.is_in_boundsv(cell):
		return false
	return not grid.is_point_solid(cell)


func get_nav_grid(floor_level: int) -> AStarGrid2D:
	return _nav_grids.get(floor_level, null)


func get_stairs_center() -> Vector2:
	var min_c: Vector2 = cell_to_world_center(STAIRS_RECT.position)
	var max_c: Vector2 = cell_to_world_center(STAIRS_RECT.end - Vector2i(1, 1))
	return (min_c + max_c) * 0.5


func _nearest_walkable_cell(grid: AStarGrid2D, cell: Vector2i) -> Vector2i:
	var clamped: Vector2i = Vector2i(
		clampi(cell.x, grid.region.position.x, grid.region.end.x - 1),
		clampi(cell.y, grid.region.position.y, grid.region.end.y - 1)
	)
	if not grid.is_point_solid(clamped):
		return clamped
	var best: Vector2i = clamped
	var best_d2: int = 999999
	for r: int in range(1, 3):
		for dx: int in range(-r, r + 1):
			for dy: int in range(-r, r + 1):
				var cand: Vector2i = clamped + Vector2i(dx, dy)
				if grid.is_in_boundsv(cand) and not grid.is_point_solid(cand):
					var d2: int = dx * dx + dy * dy
					if d2 < best_d2:
						best_d2 = d2
						best = cand
		if best_d2 < 999999:
			break
	return best


## Computes a walkable AStarGrid2D world path on `floor_level`, steering cleanly around walls & LOW_OBSTACLE fences.
func find_nav_path(floor_level: int, from_world: Vector2, to_world: Vector2) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	var grid: AStarGrid2D = get_nav_grid(floor_level)
	if grid == null:
		out.append(to_world)
		return out
	var start_cell: Vector2i = _nearest_walkable_cell(grid, world_to_cell(from_world))
	var end_cell: Vector2i = _nearest_walkable_cell(grid, world_to_cell(to_world))
	if start_cell == end_cell:
		out.append(to_world)
		return out
	var id_path: Array[Vector2i] = grid.get_id_path(start_cell, end_cell)
	if id_path.is_empty():
		return out
	for i: int in range(id_path.size()):
		if i == 0 and id_path.size() > 1:
			continue
		out.append(cell_to_world_center(id_path[i]))
	return out


## Spawns a physical interactive weapon pickup dropped via disarm / tendon tear / dismemberment.
func spawn_dropped_weapon(weapon: WeaponData, world_pos: Vector2, floor_level: int) -> Node2D:
	if weapon == null or weapon.is_unarmed or decals_container == null:
		return null
	var pickup: Node2D = Node2D.new()
	pickup.name = "Dropped_%s" % String(weapon.weapon_id)
	pickup.z_as_relative = false
	pickup.z_index = floor_level * 100 + 2

	var blen: float = clampf(weapon.blade_length * 0.55, 8.0, 22.0)
	var bw: float = clampf(weapon.blade_width_px * 0.5, 1.5, 4.0)
	var is_hammer: bool = weapon.weapon_id == &"warhammer" or weapon.damage_mode == WeaponData.DamageMode.BLUNT_ONLY

	var w_shadow: Polygon2D = Polygon2D.new()
	w_shadow.color = Color(0.0, 0.0, 0.0, 0.32)
	w_shadow.position = Vector2(0.0, 2.2)
	w_shadow.polygon = PackedVector2Array([
		Vector2(-blen * 0.55, -bw * 1.0),
		Vector2(blen * 0.78, -bw * 0.8),
		Vector2(blen * 0.78, bw * 0.9),
		Vector2(-blen * 0.55, bw * 1.0),
	])
	pickup.add_child(w_shadow)

	var blade: Polygon2D = Polygon2D.new()
	if is_hammer:
		var haft: Polygon2D = Polygon2D.new()
		haft.color = Color("#6C492C")
		haft.polygon = PackedVector2Array([
			Vector2(-blen * 0.55, -1.4),
			Vector2(blen * 0.65, -1.4),
			Vector2(blen * 0.65, 1.4),
			Vector2(-blen * 0.55, 1.4),
		])
		pickup.add_child(haft)
		blade.polygon = PackedVector2Array([
			Vector2(blen * 0.35, -bw * 1.4),
			Vector2(blen * 0.78, -bw * 1.4),
			Vector2(blen * 0.78, bw * 1.3),
			Vector2(blen * 0.35, bw * 1.3),
		])
	else:
		blade.polygon = PackedVector2Array([
			Vector2(-blen * 0.4, -bw),
			Vector2(blen * 0.6, -bw * 0.7),
			Vector2(blen * 0.85, 0.0),
			Vector2(blen * 0.6, bw * 0.7),
			Vector2(-blen * 0.4, bw),
		])
	blade.color = weapon.blade_color
	pickup.add_child(blade)
	var b_out: Line2D = Line2D.new()
	b_out.points = blade.polygon
	b_out.closed = true
	b_out.width = 0.9
	b_out.default_color = Color("#14161E")
	pickup.add_child(b_out)

	if not is_hammer:
		var hilt: Polygon2D = Polygon2D.new()
		hilt.polygon = PackedVector2Array([
			Vector2(-blen * 0.55, -bw * 1.5),
			Vector2(-blen * 0.35, -bw * 1.5),
			Vector2(-blen * 0.35, bw * 1.5),
			Vector2(-blen * 0.55, bw * 1.5),
		])
		hilt.color = Color("#A89268")
		pickup.add_child(hilt)
		var grip: Polygon2D = Polygon2D.new()
		grip.polygon = PackedVector2Array([
			Vector2(-blen * 0.82, -1.2),
			Vector2(-blen * 0.50, -1.2),
			Vector2(-blen * 0.50, 1.2),
			Vector2(-blen * 0.82, 1.2),
		])
		grip.color = Color("#5D3C24")
		pickup.add_child(grip)

	var drop_offset: Vector2 = Vector2(12.0, 8.0)
	var landing_pos: Vector2 = world_pos + drop_offset
	pickup.position = world_pos
	pickup.rotation = 0.45
	pickup.set_meta(&"floor_level", floor_level)
	decals_container.add_child(pickup)
	_apply_floor_visibility_to_node(pickup, floor_level)

	if is_inside_tree():
		var tw: Tween = pickup.create_tween()
		tw.set_parallel(true)
		tw.tween_property(pickup, "position", landing_pos, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(pickup, "rotation", 1.15, 0.18)
	else:
		pickup.position = landing_pos

	dropped_weapon_pickups.append({
		"node": pickup,
		"weapon": weapon,
		"floor": floor_level,
		"pos": landing_pos,
	})
	return pickup


func find_nearest_dropped_weapon(pos: Vector2, floor_level: int, max_radius: float = 120.0) -> Dictionary:
	return find_nearest_dropped_weapon_info(pos, floor_level, max_radius)


func find_nearest_dropped_weapon_info(world_pos: Vector2, floor_level: int, max_dist_px: float = 42.0) -> Dictionary:
	var best_idx: int = -1
	var best_dist: float = max_dist_px
	var best_pos: Vector2 = Vector2.ZERO
	for i: int in range(dropped_weapon_pickups.size()):
		var entry: Dictionary = dropped_weapon_pickups[i]
		if int(entry.get("floor", 0)) != floor_level:
			continue
		var pnode: Variant = entry.get("node", null)
		var pos: Vector2 = (pnode as Node2D).global_position if (pnode is Node2D and is_instance_valid(pnode as Node2D)) else (entry.get("pos", Vector2.ZERO) as Vector2)
		var d: float = world_pos.distance_to(pos)
		if d <= best_dist:
			best_dist = d
			best_idx = i
			best_pos = pos
	if best_idx < 0:
		return {"found": false, "weapon": null, "pos": Vector2.ZERO, "dist": INF}
	var chosen: Dictionary = dropped_weapon_pickups[best_idx]
	return {
		"found": true,
		"weapon": chosen.get("weapon", null) as WeaponData,
		"pos": best_pos,
		"dist": best_dist,
	}


func try_pickup_nearest_weapon(world_pos: Vector2, floor_level: int, max_dist_px: float = 42.0) -> WeaponData:
	var best_idx: int = -1
	var best_dist: float = max_dist_px
	for i: int in range(dropped_weapon_pickups.size()):
		var entry: Dictionary = dropped_weapon_pickups[i]
		if int(entry.get("floor", 0)) != floor_level:
			continue
		var pnode: Variant = entry.get("node", null)
		var pos: Vector2 = (pnode as Node2D).global_position if (pnode is Node2D and is_instance_valid(pnode as Node2D)) else (entry.get("pos", Vector2.ZERO) as Vector2)
		var d: float = world_pos.distance_to(pos)
		if d <= best_dist:
			best_dist = d
			best_idx = i
	if best_idx < 0:
		return null
	var chosen: Dictionary = dropped_weapon_pickups[best_idx]
	dropped_weapon_pickups.remove_at(best_idx)
	var node_ref: Variant = chosen.get("node", null)
	if node_ref is Node and is_instance_valid(node_ref as Node):
		(node_ref as Node).queue_free()
	return chosen.get("weapon", null) as WeaponData


func _update_nav_cell(floor_level: int, cell: Vector2i) -> void:
	if not _nav_grids.has(floor_level):
		return
	var grid: AStarGrid2D = _nav_grids[floor_level]
	if grid.is_in_boundsv(cell):
		grid.set_point_solid(cell, not _compute_cell_walkable(floor_level, cell))


# ---------------------------------------------------------------------------
# Layer & Tile Queries
# ---------------------------------------------------------------------------

func get_floor_layer(floor_level: int) -> TileMapLayer:
	match floor_level:
		0:
			return floor0_floor_layer
		1:
			return floor1_floor_layer
		_:
			return null


func get_wall_layer(floor_level: int) -> TileMapLayer:
	match floor_level:
		0:
			return floor0_wall_layer
		1:
			return floor1_wall_layer
		_:
			return null


func get_roof_layer() -> TileMapLayer:
	return floor1_roof_layer


func world_to_cell(world_pos: Vector2) -> Vector2i:
	return Vector2i(floori(world_pos.x / float(TILE_SIZE)), floori(world_pos.y / float(TILE_SIZE)))


func cell_to_world_center(cell: Vector2i) -> Vector2:
	return Vector2((float(cell.x) + 0.5) * float(TILE_SIZE), (float(cell.y) + 0.5) * float(TILE_SIZE))


func is_wall_solid_at(floor_level: int, cell: Vector2i) -> bool:
	var wall_layer: TileMapLayer = get_wall_layer(floor_level)
	if wall_layer == null:
		return false
	var td: TileData = wall_layer.get_cell_tile_data(cell)
	if td == null:
		return false
	var mat: String = String(td.get_custom_data(ProceduralTileSetBuilder.DATA_MATERIAL_TYPE))
	return mat != "" and mat != "debris"


# ---------------------------------------------------------------------------
# Destructible Walls & Breakable Upper Floors (GDD 12.7, 14.2, 14.5)
# ---------------------------------------------------------------------------

func get_wall_durability(floor_level: int, cell: Vector2i) -> float:
	var floor_dur_map: Dictionary = _wall_durability.get(floor_level, {})
	if floor_dur_map.has(cell):
		return float(floor_dur_map[cell])
	var wall_layer: TileMapLayer = get_wall_layer(floor_level)
	if wall_layer == null:
		return 0.0
	var td: TileData = wall_layer.get_cell_tile_data(cell)
	if td == null:
		return 0.0
	var mat: String = String(td.get_custom_data(ProceduralTileSetBuilder.DATA_MATERIAL_TYPE))
	if mat == "" or mat == "debris":
		return 0.0
	return float(td.get_custom_data(ProceduralTileSetBuilder.DATA_DURABILITY))


func get_floor_durability(floor_level: int, cell: Vector2i) -> float:
	var floor_dur_map: Dictionary = _floor_durability.get(floor_level, {})
	if floor_dur_map.has(cell):
		return float(floor_dur_map[cell])
	var floor_layer: TileMapLayer = get_floor_layer(floor_level)
	if floor_layer == null:
		return 0.0
	var td: TileData = floor_layer.get_cell_tile_data(cell)
	if td == null or not bool(td.get_custom_data(ProceduralTileSetBuilder.DATA_BREAKABLE_FLOOR)):
		return 0.0
	return float(td.get_custom_data(ProceduralTileSetBuilder.DATA_DURABILITY))


func _structure_crack_key(floor_level: int, cell: Vector2i, is_floor: bool) -> String:
	return "%s_%d_%d_%d" % ["flr" if is_floor else "wll", floor_level, cell.x, cell.y]


func _clear_structure_crack_overlay(floor_level: int, cell: Vector2i, is_floor: bool) -> void:
	var key: String = _structure_crack_key(floor_level, cell, is_floor)
	if _structure_crack_overlays.has(key):
		var old_node: Variant = _structure_crack_overlays[key]
		if old_node is Node and is_instance_valid(old_node as Node):
			(old_node as Node).queue_free()
		_structure_crack_overlays.erase(key)


func _update_structure_crack_overlay(
	floor_level: int,
	cell: Vector2i,
	is_floor: bool,
	remaining_dur: float,
	max_dur: float
) -> void:
	if decals_container == null or max_dur <= 0.0:
		return
	var damage_ratio: float = clampf(1.0 - remaining_dur / max_dur, 0.0, 1.0)
	if damage_ratio <= 0.01:
		_clear_structure_crack_overlay(floor_level, cell, is_floor)
		return

	var key: String = _structure_crack_key(floor_level, cell, is_floor)
	var holder: Node2D = _structure_crack_overlays.get(key, null) as Node2D
	if holder == null or not is_instance_valid(holder):
		holder = Node2D.new()
		holder.name = "Crack_%s" % key
		holder.z_as_relative = false
		holder.z_index = (floor_level * 100 - 8) if is_floor else (floor_level * 100 - 4)
		holder.position = cell_to_world_center(cell)
		holder.set_meta(&"floor_level", floor_level)
		decals_container.add_child(holder)
		_structure_crack_overlays[key] = holder
	else:
		for child: Node in holder.get_children():
			child.queue_free()

	var crack_col: Color = Color(0.10, 0.08, 0.08, clampf(0.45 + damage_ratio * 0.48, 0.45, 0.95))
	var crack_segments: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(-9.0, -7.0), Vector2(-1.0, -1.0), Vector2(6.0, 4.0)]),
		PackedVector2Array([Vector2(8.0, -8.0), Vector2(1.0, 0.0), Vector2(-7.0, 9.0)]),
		PackedVector2Array([Vector2(-2.0, -11.0), Vector2(0.0, 1.0), Vector2(4.0, 11.0)]),
	]
	var visible_cracks: int = 1 if damage_ratio < 0.38 else (2 if damage_ratio < 0.72 else 3)
	for i: int in range(visible_cracks):
		var line: Line2D = Line2D.new()
		line.width = 1.5 if damage_ratio < 0.65 else 2.0
		line.default_color = crack_col
		line.points = crack_segments[i]
		holder.add_child(line)
	_apply_floor_visibility_to_node(holder, floor_level)


func try_damage_wall_at(
	floor_level: int,
	cell: Vector2i,
	attacker_str: float,
	damage_amount: float = -1.0,
	aura_active: bool = false
) -> Dictionary:
	var result: Dictionary = {
		"hit": false,
		"damaged": false,
		"destroyed": false,
		"material_type": "",
		"required_str": 0.0,
		"remaining_durability": 0.0,
		"max_durability": 0.0,
		"weapon_wear": false,
	}
	var wall_layer: TileMapLayer = get_wall_layer(floor_level)
	if wall_layer == null:
		return result
	var td: TileData = wall_layer.get_cell_tile_data(cell)
	if td == null:
		return result

	var mat: String = String(td.get_custom_data(ProceduralTileSetBuilder.DATA_MATERIAL_TYPE))
	if mat == "debris" or mat == "":
		return result

	result["hit"] = true
	result["material_type"] = mat
	var destructible: bool = bool(td.get_custom_data(ProceduralTileSetBuilder.DATA_DESTRUCTIBLE))
	var threshold: float = float(td.get_custom_data(ProceduralTileSetBuilder.DATA_WALL_THRESHOLD))
	var max_dur: float = float(td.get_custom_data(ProceduralTileSetBuilder.DATA_DURABILITY))
	result["required_str"] = threshold
	result["max_durability"] = max_dur

	if not destructible or attacker_str < threshold:
		result["weapon_wear"] = not aura_active
		result["remaining_durability"] = get_wall_durability(floor_level, cell)
		return result

	if not _wall_durability.has(floor_level):
		_wall_durability[floor_level] = {}
	var floor_dur_map: Dictionary = _wall_durability[floor_level]
	var cur_dur: float = float(floor_dur_map.get(cell, max_dur))
	if damage_amount < 0.0:
		cur_dur = 0.0
	else:
		cur_dur = maxf(0.0, cur_dur - maxf(0.0, damage_amount))

	var w_center: Vector2 = cell_to_world_center(cell)
	if cur_dur <= 0.0:
		floor_dur_map.erase(cell)
		_clear_structure_crack_overlay(floor_level, cell, false)
		wall_layer.set_cell(cell, 0, ProceduralTileSetBuilder.TILE_DEBRIS)
		wall_layer.update_internals()
		_rebuild_34_wall_overlays()
		_update_nav_cell(floor_level, cell)
		result["damaged"] = true
		result["destroyed"] = true
		result["remaining_durability"] = 0.0
		record_noise(w_center, floor_level, 260.0, null)
		spawn_sparks(w_center, floor_level, 0.0, Color("#D9A066"), 8)
		if EventBus != null:
			EventBus.request_camera_shake(4.5, 0.18)
			EventBus.request_sfx(ProceduralAudioManager.CUE_WALL_BREAK, 1.15, 1.0)
		wall_destroyed.emit(floor_level, cell, mat)
	else:
		floor_dur_map[cell] = cur_dur
		result["damaged"] = true
		result["remaining_durability"] = cur_dur
		_update_structure_crack_overlay(floor_level, cell, false, cur_dur, max_dur)
		record_noise(w_center, floor_level, 140.0, null)
		spawn_sparks(w_center, floor_level, 0.0, Color("#E5C07B"), 4)
		if EventBus != null:
			EventBus.request_camera_shake(1.8, 0.09)
			EventBus.request_sfx(ProceduralAudioManager.CUE_BONE_CRUNCH, 0.72, 1.18)
		wall_damaged.emit(floor_level, cell, mat, cur_dur, max_dur)

	return result


func try_break_floor_at(
	floor_level: int,
	cell: Vector2i,
	attacker_str: float,
	aura_active: bool = false,
	damage_amount: float = -1.0
) -> Dictionary:
	var result: Dictionary = {
		"hit": false,
		"damaged": false,
		"broken": false,
		"required_str": 0.0,
		"remaining_durability": 0.0,
		"max_durability": 0.0,
		"weapon_wear": false,
		"fallen_entities": [],
	}
	var floor_layer: TileMapLayer = get_floor_layer(floor_level)
	if floor_layer == null:
		return result
	var td: TileData = floor_layer.get_cell_tile_data(cell)
	if td == null:
		return result

	var is_breakable: bool = bool(td.get_custom_data(ProceduralTileSetBuilder.DATA_BREAKABLE_FLOOR))
	if not is_breakable:
		return result

	result["hit"] = true
	var threshold: float = float(td.get_custom_data(ProceduralTileSetBuilder.DATA_WALL_THRESHOLD))
	var max_dur: float = float(td.get_custom_data(ProceduralTileSetBuilder.DATA_DURABILITY))
	result["required_str"] = threshold
	result["max_durability"] = max_dur
	if attacker_str < threshold:
		result["weapon_wear"] = not aura_active
		result["remaining_durability"] = get_floor_durability(floor_level, cell)
		return result

	if not _floor_durability.has(floor_level):
		_floor_durability[floor_level] = {}
	var floor_dur_map: Dictionary = _floor_durability[floor_level]
	var cur_dur: float = float(floor_dur_map.get(cell, max_dur))
	if damage_amount < 0.0:
		cur_dur = 0.0
	else:
		cur_dur = maxf(0.0, cur_dur - maxf(0.0, damage_amount))

	var f_center: Vector2 = cell_to_world_center(cell)
	if cur_dur > 0.0:
		floor_dur_map[cell] = cur_dur
		result["damaged"] = true
		result["remaining_durability"] = cur_dur
		_update_structure_crack_overlay(floor_level, cell, true, cur_dur, max_dur)
		record_noise(f_center, floor_level, 140.0, null)
		spawn_sparks(f_center, floor_level, 0.0, Color("#D9A066"), 4)
		if EventBus != null:
			EventBus.request_camera_shake(1.8, 0.09)
			EventBus.request_sfx(ProceduralAudioManager.CUE_BONE_CRUNCH, 0.72, 1.15)
		return result

	floor_layer.set_cell(cell, 0, ProceduralTileSetBuilder.TILE_FLOOR_HOLE)
	floor_dur_map.erase(cell)
	_clear_structure_crack_overlay(floor_level, cell, true)

	var flm: Node = _get_floor_manager()
	if flm != null:
		flm.call("break_floor_at", floor_level, cell)

	_update_nav_cell(floor_level, cell)
	result["damaged"] = true
	result["broken"] = true
	result["remaining_durability"] = 0.0
	record_noise(f_center, floor_level, 280.0, null)
	spawn_sparks(f_center, floor_level, 0.0, Color("#D9A066"), 8)
	if EventBus != null:
		EventBus.request_camera_shake(4.5, 0.18)
	floor_broken.emit(floor_level, cell)

	var fallen: Array[Node] = check_floor_support_for_all_entities()
	result["fallen_entities"] = fallen
	return result


# ---------------------------------------------------------------------------
# Entity Tracking, Stairs (0 <-> +1, 0.4s Cooldown) & FloorSupport Falls
# ---------------------------------------------------------------------------

func register_entity(entity: Node, as_focus: bool = false) -> void:
	if entity == null:
		return
	if not _tracked_entities.has(entity):
		_tracked_entities.append(entity)
	if as_focus and entity is Node2D:
		focus_entity = entity as Node2D
		var vc: VerticalityComponent = _find_verticality_component(entity)
		if vc != null:
			vc.is_focus_entity = true
			if not vc.floor_level_changed.is_connected(_on_focus_entity_floor_changed):
				vc.floor_level_changed.connect(_on_focus_entity_floor_changed)
			var inside: bool = _is_entity_inside_building_cells(focus_entity)
			update_floor_visibility(vc.floor_level, inside, true)
	elif entity is CanvasItem:
		var vc_ent: VerticalityComponent = _find_verticality_component(entity)
		_apply_floor_visibility_to_node(entity as CanvasItem, vc_ent.floor_level if vc_ent != null else 0)


func unregister_entity(entity: Node) -> void:
	_tracked_entities.erase(entity)
	_entities_in_building_trigger.erase(entity)
	_entities_in_stairs_area.erase(entity)
	_entities_in_safe_zone.erase(entity)
	if focus_entity == entity:
		focus_entity = null


func is_entity_on_stairs(entity: Node) -> bool:
	if entity == null or not is_instance_valid(entity):
		return false
	if entity is Node2D:
		var cell: Vector2i = world_to_cell((entity as Node2D).global_position)
		var in_stairs: bool = STAIRS_RECT.has_point(cell)
		if not in_stairs and _entities_in_stairs_area.has(entity):
			_entities_in_stairs_area.erase(entity)
		return in_stairs
	return _entities_in_stairs_area.has(entity)


func try_use_stairs(entity: Node) -> bool:
	if entity == null or not is_instance_valid(entity):
		return false
	var anatomy: AnatomyComponent = _find_anatomy_component(entity)
	if anatomy != null and (anatomy.is_dead or anatomy.is_unconscious):
		return false
	if not is_entity_on_stairs(entity):
		return false
	var entity_id: int = entity.get_instance_id()
	if _stairs_cooldowns.has(entity_id):
		return false

	var vc: VerticalityComponent = _find_verticality_component(entity)
	if vc == null:
		return false

	var old_floor: int = vc.floor_level
	var target_floor: int = 1 if old_floor == 0 else 0
	_stairs_cooldowns[entity_id] = STAIRS_COOLDOWN_SEC
	vc.set_floor_level(target_floor)
	entity_used_stairs.emit(entity, old_floor, target_floor)

	if entity == focus_entity:
		update_floor_visibility(target_floor, _is_entity_inside_building_cells(focus_entity), false)
	return true


func handle_antitunnel_areas(entity: Node, areas: Array[Area2D]) -> void:
	if entity == null or not is_instance_valid(entity) or areas.is_empty():
		return
	var vc: VerticalityComponent = _find_verticality_component(entity)
	var entity_floor: int = vc.floor_level if vc != null else 0
	for area: Area2D in areas:
		if area == null or not is_instance_valid(area):
			continue
		if area == floor1_support_zone and entity_floor >= 1:
			check_entity_floor_support(entity)
		elif area == building_interior_trigger and entity == focus_entity and entity_floor == 0 and entity is Node2D:
			update_floor_visibility(0, _is_entity_inside_building_cells(entity as Node2D), false)
		elif area == safe_barrier_zone and entity_floor == 0:
			notify_entity_entered_safe_zone(entity)
		elif area == stairs_area and not _entities_in_stairs_area.has(entity):
			if entity is Node2D and STAIRS_RECT.has_point(world_to_cell((entity as Node2D).global_position)):
				_entities_in_stairs_area.append(entity)


func check_floor_support_for_all_entities() -> Array[Node]:
	var candidates: Array[Node] = []
	for e: Node in _tracked_entities:
		if is_instance_valid(e) and not candidates.has(e):
			candidates.append(e)
	if entities_container != null:
		for child: Node in entities_container.get_children():
			if is_instance_valid(child) and not candidates.has(child):
				candidates.append(child)
	if floor1_support_zone != null and floor1_support_zone.is_inside_tree():
		for body: Node2D in floor1_support_zone.get_overlapping_bodies():
			if is_instance_valid(body) and not candidates.has(body):
				candidates.append(body)

	var fallen_list: Array[Node] = []
	for entity: Node in candidates:
		var fall_info: Dictionary = check_entity_floor_support(entity)
		if bool(fall_info.get("fell", false)):
			fallen_list.append(entity)
	return fallen_list


func check_entity_floor_support(entity: Node) -> Dictionary:
	var result: Dictionary = {
		"fell": false,
		"from_floor": 0,
		"to_floor": 0,
		"fall_report": {},
	}
	if entity == null or not is_instance_valid(entity) or not (entity is Node2D):
		return result

	var vc: VerticalityComponent = _find_verticality_component(entity)
	if vc == null or vc.floor_level <= 0:
		return result

	var flm: Node = _get_floor_manager()
	if flm == null:
		return result

	var cell: Vector2i = world_to_cell((entity as Node2D).global_position)
	if not bool(flm.call("should_entity_fall", vc.floor_level, cell, vc.height_z)):
		return result

	var from_floor: int = vc.floor_level
	var to_floor: int = from_floor - 1
	vc.set_floor_level(to_floor)

	var fall_report: Dictionary = {}
	var anatomy: AnatomyComponent = _find_anatomy_component(entity)
	if anatomy != null:
		fall_report = anatomy.apply_fall_damage(1)

	result["fell"] = true
	result["from_floor"] = from_floor
	result["to_floor"] = to_floor
	result["fall_report"] = fall_report

	if entity == focus_entity:
		update_floor_visibility(to_floor, _is_entity_inside_building_cells(focus_entity), false)

	entity_fell_through_floor.emit(entity, from_floor, to_floor, fall_report)
	return result


# ---------------------------------------------------------------------------
# Dynamic Roof & Floor Visibility (GDD Section 12.6 & 14.1)
# ---------------------------------------------------------------------------

func update_floor_visibility(viewer_floor: int, viewer_inside_building: bool, instant: bool = false) -> void:
	_viewer_floor = viewer_floor
	_viewer_inside_building = viewer_inside_building

	var target_floor0_color: Color = FLOOR0_BRIGHT_COLOR
	var target_floor1_alpha: float = 1.0
	var target_roof_alpha: float = 1.0

	if viewer_floor >= 1:
		target_floor0_color = FLOOR0_DIMMED_COLOR
		target_floor1_alpha = 1.0
		target_roof_alpha = 0.0
	elif viewer_inside_building:
		target_floor0_color = FLOOR0_BRIGHT_COLOR
		target_floor1_alpha = 0.0
		target_roof_alpha = 0.0
	else:
		target_floor0_color = FLOOR0_BRIGHT_COLOR
		target_floor1_alpha = 1.0
		target_roof_alpha = 1.0

	if _visibility_tween != null and _visibility_tween.is_valid():
		_visibility_tween.kill()

	if instant or not is_inside_tree():
		floor0_container.modulate = target_floor0_color
		floor1_floor_layer.modulate.a = target_floor1_alpha
		floor1_wall_layer.modulate.a = target_floor1_alpha
		floor1_roof_layer.modulate.a = target_roof_alpha
		if floor1_wall_shadows != null:
			floor1_wall_shadows.modulate.a = target_floor1_alpha
		if floor1_wall_crowns != null:
			floor1_wall_crowns.modulate.a = target_floor1_alpha
		_sync_entities_and_decals_floor_visibility()
		return

	_visibility_tween = create_tween()
	_visibility_tween.set_parallel(true)
	_visibility_tween.tween_property(floor0_container, "modulate", target_floor0_color, VISIBILITY_FADE_DURATION)
	_visibility_tween.tween_property(floor1_floor_layer, "modulate:a", target_floor1_alpha, VISIBILITY_FADE_DURATION)
	_visibility_tween.tween_property(floor1_wall_layer, "modulate:a", target_floor1_alpha, VISIBILITY_FADE_DURATION)
	_visibility_tween.tween_property(floor1_roof_layer, "modulate:a", target_roof_alpha, VISIBILITY_FADE_DURATION)
	if floor1_wall_shadows != null:
		_visibility_tween.tween_property(floor1_wall_shadows, "modulate:a", target_floor1_alpha, VISIBILITY_FADE_DURATION)
	if floor1_wall_crowns != null:
		_visibility_tween.tween_property(floor1_wall_crowns, "modulate:a", target_floor1_alpha, VISIBILITY_FADE_DURATION)
	_sync_entities_and_decals_floor_visibility()


## Hides entities/decals on upper floors (> viewer_floor) when viewer is on Floor 0,
## and dims lower-floor entities/decals (< viewer_floor) when viewer is on Floor +1
## so Floor 0 remains clearly visible (dimmed) in the yard and through broken floor holes.
func _apply_floor_visibility_to_node(node: CanvasItem, node_floor: int) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node == focus_entity:
		node.visible = true
		node.modulate = FLOOR0_BRIGHT_COLOR
		return
	if node_floor > _viewer_floor:
		node.visible = false
		node.modulate = FLOOR0_BRIGHT_COLOR
	elif node_floor < _viewer_floor:
		node.visible = true
		node.modulate = FLOOR0_DIMMED_COLOR
	else:
		node.visible = true
		node.modulate = FLOOR0_BRIGHT_COLOR


func _sync_entities_and_decals_floor_visibility() -> void:
	var seen: Dictionary[int, bool] = {}
	if entities_container != null:
		for child: Node in entities_container.get_children():
			if child is CanvasItem and is_instance_valid(child):
				seen[child.get_instance_id()] = true
				var vc: VerticalityComponent = _find_verticality_component(child)
				var ent_fl: int = vc.floor_level if vc != null else 0
				_apply_floor_visibility_to_node(child as CanvasItem, ent_fl)
	for ent: Node in _tracked_entities:
		if ent is CanvasItem and is_instance_valid(ent) and not seen.has(ent.get_instance_id()):
			var vc: VerticalityComponent = _find_verticality_component(ent)
			var ent_fl: int = vc.floor_level if vc != null else 0
			_apply_floor_visibility_to_node(ent as CanvasItem, ent_fl)
	if decals_container != null:
		for dchild: Node in decals_container.get_children():
			if dchild is CanvasItem and is_instance_valid(dchild):
				var dfl: int = int(dchild.get_meta(&"floor_level", 0))
				_apply_floor_visibility_to_node(dchild as CanvasItem, dfl)


func _on_eventbus_floor_changed(_entity: Node, _old_floor: int, _new_floor: int) -> void:
	_sync_entities_and_decals_floor_visibility()


func _on_building_interior_body_entered(body: Node2D) -> void:
	if not _entities_in_building_trigger.has(body):
		_entities_in_building_trigger.append(body)
	var vc: VerticalityComponent = _find_verticality_component(body)
	var body_floor: int = vc.floor_level if vc != null else 0
	if body == focus_entity or focus_entity == null:
		if body_floor == 0:
			update_floor_visibility(0, true, false)


func _on_building_interior_body_exited(body: Node2D) -> void:
	_entities_in_building_trigger.erase(body)
	var vc: VerticalityComponent = _find_verticality_component(body)
	var body_floor: int = vc.floor_level if vc != null else 0
	if body == focus_entity or focus_entity == null:
		if body_floor == 0:
			update_floor_visibility(0, false, false)


func _on_safe_zone_body_entered(body: Node2D) -> void:
	notify_entity_entered_safe_zone(body)


func _on_safe_zone_body_exited(body: Node2D) -> void:
	_entities_in_safe_zone.erase(body)


func _on_stairs_body_entered(body: Node2D) -> void:
	if not _entities_in_stairs_area.has(body):
		_entities_in_stairs_area.append(body)


func _on_stairs_body_exited(body: Node2D) -> void:
	_entities_in_stairs_area.erase(body)


func _on_focus_entity_floor_changed(_old_floor: int, new_floor: int) -> void:
	if focus_entity == null:
		return
	update_floor_visibility(new_floor, _is_entity_inside_building_cells(focus_entity), false)


func _is_entity_inside_building_cells(entity: Node2D) -> bool:
	if entity == null:
		return false
	return BUILDING_INTERIOR_RECT.has_point(world_to_cell(entity.global_position))


# ---------------------------------------------------------------------------
# Component Discovery Helpers (No Hardcoded Entity Coupling)
# ---------------------------------------------------------------------------

static func _find_verticality_component(entity: Node) -> VerticalityComponent:
	if entity is VerticalityComponent:
		return entity as VerticalityComponent
	for child: Node in entity.get_children():
		if child is VerticalityComponent:
			return child as VerticalityComponent
	return null


static func _find_anatomy_component(entity: Node) -> AnatomyComponent:
	if entity is AnatomyComponent:
		return entity as AnatomyComponent
	for child: Node in entity.get_children():
		if child is AnatomyComponent:
			return child as AnatomyComponent
	return null


func _get_floor_manager() -> Node:
	if is_inside_tree() and get_tree().root != null:
		return get_tree().root.get_node_or_null("FloorLayerManager")
	var main_loop: MainLoop = Engine.get_main_loop()
	if main_loop is SceneTree:
		var tree: SceneTree = main_loop as SceneTree
		if tree.root != null:
			return tree.root.get_node_or_null("FloorLayerManager")
	return null
