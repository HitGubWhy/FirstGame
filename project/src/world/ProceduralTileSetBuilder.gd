class_name ProceduralTileSetBuilder
extends RefCounted
## Programmatically generates a single 32x32 pixel-art atlas ImageTexture (zero external PNGs)
## and constructs per-floor TileSets with HighWalls/LowObstacles physics polygons and custom data.
## Strictly follows GDD Sections 12.6, 12.7, and 14.3.

const TILE_SIZE: int = 32
const ATLAS_COLUMNS: int = 12

# Physics layer indices inside each built TileSet
const PHYSICS_LAYER_HIGH_WALLS: int = 0
const PHYSICS_LAYER_LOW_OBSTACLES: int = 1

# Custom data layer keys
const DATA_MATERIAL_TYPE: String = "material_type"
const DATA_WALL_THRESHOLD: String = "wall_threshold"
const DATA_DURABILITY: String = "durability"
const DATA_DESTRUCTIBLE: String = "destructible"
const DATA_BREAKABLE_FLOOR: String = "breakable_floor"

# Atlas coordinates for all Stage 0 procedural tiles
const TILE_FLOOR_0: Vector2i = Vector2i(0, 0)
const TILE_FLOOR_1: Vector2i = Vector2i(1, 0)
const TILE_FLOOR_1_BREAKABLE: Vector2i = Vector2i(2, 0)
const TILE_FLOOR_HOLE: Vector2i = Vector2i(3, 0)
const TILE_LOW_OBSTACLE: Vector2i = Vector2i(4, 0)
const TILE_WALL_WOOD: Vector2i = Vector2i(5, 0)
const TILE_WALL_BRICK: Vector2i = Vector2i(6, 0)
const TILE_WALL_STONE: Vector2i = Vector2i(7, 0)
const TILE_WALL_INDESTRUCTIBLE: Vector2i = Vector2i(8, 0)
const TILE_STAIRS: Vector2i = Vector2i(9, 0)
const TILE_ROOF: Vector2i = Vector2i(10, 0)
const TILE_DEBRIS: Vector2i = Vector2i(11, 0)

# Exact palette per GDD Section 14.3
const COLOR_FLOOR_0: Color = Color("#2B2D31")
const COLOR_FLOOR_1: Color = Color("#5C4033")
const COLOR_HOLE_RIM: Color = Color(0.05, 0.05, 0.07, 1.0)
const COLOR_LOW_OBSTACLE: Color = Color("#A89060")
const COLOR_WALL_WOOD: Color = Color("#B5804A")
const COLOR_WALL_BRICK: Color = Color("#B55239")
const COLOR_WALL_STONE: Color = Color("#6E737B")
const COLOR_WALL_INDESTRUCTIBLE: Color = Color("#1B1D22")
const COLOR_STAIRS_YELLOW: Color = Color("#E0B83E")
const COLOR_STAIRS_BLUE: Color = Color("#3B78C2")
const COLOR_ROOF: Color = Color(0.227451, 0.247059, 0.294118, 0.85) # #3A3F4B, alpha 0.85
const COLOR_DEBRIS: Color = Color("#555963")
const COLOR_SAFE_BARRIER_BORDER: Color = Color("#3498DB")
const COLOR_SAFE_BARRIER_FILL: Color = Color(0.20, 0.59, 0.86, 0.16)

# Structural STR thresholds (GDD Sections 3.2, 14.1, 14.5)
const STR_THRESHOLD_WOOD: float = 15.0
const STR_THRESHOLD_BREAKABLE_FLOOR: float = 15.0
const STR_THRESHOLD_BRICK: float = 40.0
const STR_THRESHOLD_STONE: float = 90.0
const STR_THRESHOLD_INDESTRUCTIBLE: float = 9999.0


static func build_atlas_image() -> Image:
	var width: int = ATLAS_COLUMNS * TILE_SIZE
	var height: int = TILE_SIZE
	var img: Image = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))

	# 0: Floor 0 (#2B2D31) — 3/4 stone flagstones (center pixel (16,16) stays exact #2B2D31)
	_draw_floor0_flagstones_34(img, TILE_FLOOR_0.x, COLOR_FLOOR_0)

	# 1: Floor +1 (#5C4033) — 3/4 warm timber planks (center pixel (16,16) stays exact #5C4033)
	_draw_floor1_planks_34(img, TILE_FLOOR_1.x, COLOR_FLOOR_1)

	# 2: Floor +1 Breakable (STR >= 15) — cracked/splintered sagging planks with dark gaps
	_draw_breakable_floor_34(img, TILE_FLOOR_1_BREAKABLE.x, COLOR_FLOOR_1)

	# 3: Broken floor hole — transparent center (alpha=0 at 16,16) + 3/4 thick slab rim (opaque at 0,0)
	_draw_hole_tile_34(img, TILE_FLOOR_HOLE.x, COLOR_HOLE_RIM, COLOR_FLOOR_1)

	# 4: Low obstacle / fence (#A89060) — 3/4 wooden posts, cross-rails & ground shadow
	_draw_low_obstacle_fence_34(img, TILE_LOW_OBSTACLE.x, COLOR_LOW_OBSTACLE)

	# 5: Wood wall (STR >= 15) — 3/4 top cap + vertical plank facade + base shadow
	_draw_wood_wall_34(img, TILE_WALL_WOOD.x, COLOR_WALL_WOOD)

	# 6: Brick wall (STR >= 40) — 3/4 coping cap + running-bond terracotta facade + base shadow
	_draw_brick_wall_34(img, TILE_WALL_BRICK.x, COLOR_WALL_BRICK)

	# 7: Stone 1m wall (STR >= 90) — 3/4 parapet cap + cut ashlar stone facade + crack
	_draw_stone_wall_34(img, TILE_WALL_STONE.x, COLOR_WALL_STONE)

	# 8: Indestructible arena perimeter wall — 3/4 obsidian battlements + iron buttresses
	_draw_indestructible_wall_34(img, TILE_WALL_INDESTRUCTIBLE.x, COLOR_WALL_INDESTRUCTIBLE)

	# 9: Stairs — 3/4 perspective steps with side stringers, gold treads & slate-blue risers
	_draw_stairs_tile_34(img, TILE_STAIRS.x, COLOR_STAIRS_YELLOW, COLOR_STAIRS_BLUE)

	# 10: Roof — 3/4 overlapping slate roof shingles (strictly preserving alpha=0.85 at (16,16))
	_draw_roof_shingles_34(img, TILE_ROOF.x, COLOR_ROOF)

	# 11: Debris — transparent background with 3/4 volumetric rubble chunks & cast shadows
	_draw_debris_tile_34(img, TILE_DEBRIS.x, COLOR_DEBRIS)

	return img


static func build_atlas_texture() -> ImageTexture:
	var img: Image = build_atlas_image()
	return ImageTexture.create_from_image(img)


static func build_tileset_for_floor(
	floor_level: int,
	shared_atlas_texture: ImageTexture = null,
	high_walls_bit_override: int = -1,
	low_obstacles_bit_override: int = -1
) -> TileSet:
	var atlas_tex: ImageTexture = shared_atlas_texture if shared_atlas_texture != null else build_atlas_texture()
	var tile_set: TileSet = TileSet.new()
	tile_set.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)

	# Resolve collision layers via FloorLayerManager unless explicitly overridden
	var high_walls_bit: int = high_walls_bit_override
	var low_obstacles_bit: int = low_obstacles_bit_override
	if high_walls_bit < 0 or low_obstacles_bit < 0:
		var bits: Vector2i = _resolve_floor_collision_bits(floor_level)
		if high_walls_bit < 0:
			high_walls_bit = bits.x
		if low_obstacles_bit < 0:
			low_obstacles_bit = bits.y

	# Physics layer 0: HighWalls
	tile_set.add_physics_layer(PHYSICS_LAYER_HIGH_WALLS)
	tile_set.set_physics_layer_collision_layer(PHYSICS_LAYER_HIGH_WALLS, high_walls_bit)
	tile_set.set_physics_layer_collision_mask(PHYSICS_LAYER_HIGH_WALLS, 0)

	# Physics layer 1: LowObstacles
	tile_set.add_physics_layer(PHYSICS_LAYER_LOW_OBSTACLES)
	tile_set.set_physics_layer_collision_layer(PHYSICS_LAYER_LOW_OBSTACLES, low_obstacles_bit)
	tile_set.set_physics_layer_collision_mask(PHYSICS_LAYER_LOW_OBSTACLES, 0)

	# Custom data layers
	_add_custom_data_layer(tile_set, 0, DATA_MATERIAL_TYPE, TYPE_STRING)
	_add_custom_data_layer(tile_set, 1, DATA_WALL_THRESHOLD, TYPE_FLOAT)
	_add_custom_data_layer(tile_set, 2, DATA_DURABILITY, TYPE_FLOAT)
	_add_custom_data_layer(tile_set, 3, DATA_DESTRUCTIBLE, TYPE_BOOL)
	_add_custom_data_layer(tile_set, 4, DATA_BREAKABLE_FLOOR, TYPE_BOOL)

	var atlas: TileSetAtlasSource = TileSetAtlasSource.new()
	atlas.texture = atlas_tex
	atlas.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	tile_set.add_source(atlas, 0)

	var full_poly: PackedVector2Array = _get_full_tile_polygon()

	# Register all tiles with custom metadata & physics polygons
	_register_tile(atlas, TILE_FLOOR_0, "floor_0", 0.0, 0.0, false, false, -1, full_poly)
	_register_tile(atlas, TILE_FLOOR_1, "floor_1", 0.0, 0.0, false, false, -1, full_poly)
	_register_tile(atlas, TILE_FLOOR_1_BREAKABLE, "floor_breakable", STR_THRESHOLD_BREAKABLE_FLOOR, 25.0, true, true, -1, full_poly)
	_register_tile(atlas, TILE_FLOOR_HOLE, "floor_hole", 0.0, 0.0, false, false, -1, full_poly)
	_register_tile(atlas, TILE_LOW_OBSTACLE, "low_obstacle", 0.0, 0.0, false, false, PHYSICS_LAYER_LOW_OBSTACLES, full_poly)
	_register_tile(atlas, TILE_WALL_WOOD, "wood", STR_THRESHOLD_WOOD, 30.0, true, false, PHYSICS_LAYER_HIGH_WALLS, full_poly)
	_register_tile(atlas, TILE_WALL_BRICK, "brick", STR_THRESHOLD_BRICK, 80.0, true, false, PHYSICS_LAYER_HIGH_WALLS, full_poly)
	_register_tile(atlas, TILE_WALL_STONE, "stone", STR_THRESHOLD_STONE, 180.0, true, false, PHYSICS_LAYER_HIGH_WALLS, full_poly)
	_register_tile(atlas, TILE_WALL_INDESTRUCTIBLE, "indestructible", STR_THRESHOLD_INDESTRUCTIBLE, 0.0, false, false, PHYSICS_LAYER_HIGH_WALLS, full_poly)
	_register_tile(atlas, TILE_STAIRS, "stairs", 0.0, 0.0, false, false, -1, full_poly)
	_register_tile(atlas, TILE_ROOF, "roof", 0.0, 0.0, false, false, -1, full_poly)
	_register_tile(atlas, TILE_DEBRIS, "debris", 0.0, 0.0, false, false, -1, full_poly)

	return tile_set


static func update_tileset_floor_layers(tile_set: TileSet, floor_level: int) -> void:
	if tile_set == null or tile_set.get_physics_layers_count() < 2:
		return
	var bits: Vector2i = _resolve_floor_collision_bits(floor_level)
	tile_set.set_physics_layer_collision_layer(PHYSICS_LAYER_HIGH_WALLS, bits.x)
	tile_set.set_physics_layer_collision_layer(PHYSICS_LAYER_LOW_OBSTACLES, bits.y)


static func _resolve_floor_collision_bits(floor_level: int) -> Vector2i:
	var main_loop: MainLoop = Engine.get_main_loop()
	if main_loop is SceneTree:
		var tree: SceneTree = main_loop as SceneTree
		if tree.root != null:
			var flm: Node = tree.root.get_node_or_null("FloorLayerManager")
			if flm != null:
				var hw: int = int(flm.call("get_high_walls_bit", floor_level))
				var lo: int = int(flm.call("get_low_obstacles_bit", floor_level))
				return Vector2i(hw, lo)
	# Deterministic fallback if called outside SceneTree
	var slot: int = posmod(floor_level, 4)
	return Vector2i(1 << (slot * 3), 1 << (slot * 3 + 1))


static func _add_custom_data_layer(tile_set: TileSet, idx: int, layer_name: String, data_type: Variant.Type) -> void:
	tile_set.add_custom_data_layer(idx)
	tile_set.set_custom_data_layer_name(idx, layer_name)
	tile_set.set_custom_data_layer_type(idx, data_type)


static func _register_tile(
	atlas: TileSetAtlasSource,
	coord: Vector2i,
	material_type: String,
	wall_threshold: float,
	durability: float,
	destructible: bool,
	breakable_floor: bool,
	physics_layer_idx: int,
	polygon: PackedVector2Array
) -> void:
	atlas.create_tile(coord)
	var td: TileData = atlas.get_tile_data(coord, 0)
	td.set_custom_data(DATA_MATERIAL_TYPE, material_type)
	td.set_custom_data(DATA_WALL_THRESHOLD, wall_threshold)
	td.set_custom_data(DATA_DURABILITY, durability)
	td.set_custom_data(DATA_DESTRUCTIBLE, destructible)
	td.set_custom_data(DATA_BREAKABLE_FLOOR, breakable_floor)
	if physics_layer_idx >= 0:
		td.add_collision_polygon(physics_layer_idx)
		td.set_collision_polygon_points(physics_layer_idx, 0, polygon)


static func _get_full_tile_polygon() -> PackedVector2Array:
	var half: float = float(TILE_SIZE) * 0.5
	return PackedVector2Array([
		Vector2(-half, -half),
		Vector2(half, -half),
		Vector2(half, half),
		Vector2(-half, half),
	])


# ---------------------------------------------------------------------------
# Procedural 3/4 Top-Down Pixel Drawing Helpers (Zero External Assets)
# ---------------------------------------------------------------------------

static func _fill_rect_tile(img: Image, col: int, x0: int, y0: int, w: int, h: int, color: Color) -> void:
	var ox: int = col * TILE_SIZE
	var rx0: int = clampi(x0, 0, TILE_SIZE)
	var ry0: int = clampi(y0, 0, TILE_SIZE)
	var rx1: int = clampi(x0 + w, 0, TILE_SIZE)
	var ry1: int = clampi(y0 + h, 0, TILE_SIZE)
	for y: int in range(ry0, ry1):
		for x: int in range(rx0, rx1):
			img.set_pixel(ox + x, y, color)


static func _draw_floor0_flagstones_34(img: Image, col: int, base: Color) -> void:
	var ox: int = col * TILE_SIZE
	var grout: Color = base.darkened(0.28)
	var bevel_hi: Color = base.lightened(0.08)
	var shade_lo: Color = base.darkened(0.10)
	for y: int in range(TILE_SIZE):
		for x: int in range(TILE_SIZE):
			var c: Color = base
			var row: int = 0 if y < 15 else 1
			var is_h_seam: bool = (y == 0 or y == 15)
			var is_v_seam: bool = (x == 0) or (row == 0 and x == 16) or (row == 1 and (x == 8 or x == 24))
			if is_h_seam or is_v_seam:
				c = grout
			elif y == 1 or y == 16:
				c = bevel_hi
			elif y == 14 or y == 31:
				c = shade_lo
			elif ((x * 13 + y * 29) % 19) == 0:
				c = base.darkened(0.06)
			elif ((x * 7 + y * 17) % 23) == 0:
				c = base.lightened(0.05)
			img.set_pixel(ox + x, y, c)
	# Preserve exact GDD 14.3 center reference color at (16, 16)
	img.set_pixel(ox + 16, 16, base)


static func _draw_floor1_planks_34(img: Image, col: int, base: Color) -> void:
	var ox: int = col * TILE_SIZE
	var seam: Color = base.darkened(0.34)
	var hi: Color = base.lightened(0.11)
	var mid_dark: Color = base.darkened(0.09)
	var nail: Color = Color("#241913")
	for y: int in range(TILE_SIZE):
		var plank_idx: int = 0 if y < 10 else (1 if y < 21 else 2)
		var joint_x: int = 11 if plank_idx == 0 else (23 if plank_idx == 1 else 6)
		for x: int in range(TILE_SIZE):
			var c: Color = base if (plank_idx % 2 == 1) else base.lightened(0.04)
			if y == 0 or y == 10 or y == 21 or y == 31 or x == 0 or x == 31 or x == joint_x:
				c = seam
			elif y == 1 or y == 11 or y == 22:
				c = hi
			elif y == 9 or y == 20 or y == 30:
				c = mid_dark
			elif (y == 4 or y == 15 or y == 26) and ((x + plank_idx * 5) % 9 == 0):
				c = base.darkened(0.07)
			img.set_pixel(ox + x, y, c)
	# Tiny nail dots beside plank joints
	for np: Vector2i in [
		Vector2i(9, 3), Vector2i(9, 7), Vector2i(13, 3), Vector2i(13, 7),
		Vector2i(21, 13), Vector2i(21, 18), Vector2i(25, 13), Vector2i(25, 18),
		Vector2i(4, 24), Vector2i(4, 28), Vector2i(8, 24), Vector2i(8, 28),
	]:
		img.set_pixel(ox + np.x, np.y, nail)
	img.set_pixel(ox + 16, 16, base)


static func _draw_breakable_floor_34(img: Image, col: int, base: Color) -> void:
	_draw_floor1_planks_34(img, col, base.darkened(0.06))
	var ox: int = col * TILE_SIZE
	var warn_edge: Color = Color("#D4A359")
	var dark_gap: Color = Color("#1B100B")
	# Highlight splintered outline border so breakable planks read clearly
	for i: int in range(TILE_SIZE):
		if i % 3 != 0:
			img.set_pixel(ox + i, 0, warn_edge)
			img.set_pixel(ox + i, TILE_SIZE - 1, warn_edge)
			img.set_pixel(ox, i, warn_edge)
			img.set_pixel(ox + TILE_SIZE - 1, i, warn_edge)
	# Deep jagged 3/4 splinter cracks + pale chipped wood edges
	_draw_crack_pattern(img, col, dark_gap)
	var chipped: Array[Vector2i] = [
		Vector2i(7, 5), Vector2i(8, 6), Vector2i(12, 9), Vector2i(14, 11),
		Vector2i(17, 15), Vector2i(19, 17), Vector2i(22, 21), Vector2i(13, 15),
		Vector2i(11, 18), Vector2i(20, 12), Vector2i(23, 10),
	]
	for p: Vector2i in chipped:
		img.set_pixel(ox + p.x, p.y, warn_edge)
	# Small dark void split in middle plank
	_fill_rect_tile(img, col, 14, 13, 4, 3, dark_gap)
	_fill_rect_tile(img, col, 15, 12, 2, 1, warn_edge)


static func _draw_hole_tile_34(img: Image, col: int, rim_color: Color, wood_base: Color) -> void:
	var ox: int = col * TILE_SIZE
	var slab_top: Color = wood_base.darkened(0.28)
	var slab_face: Color = wood_base.darkened(0.55)
	var splinter: Color = Color("#A88454")
	for y: int in range(TILE_SIZE):
		for x: int in range(TILE_SIZE):
			# Outer 2px dark frame + thicker 3/4 top slab depth (y = 2..5) looking into Floor 0
			if x <= 1 or y <= 1 or x >= TILE_SIZE - 2 or y >= TILE_SIZE - 2:
				img.set_pixel(ox + x, y, rim_color)
			elif y <= 4 and x >= 2 and x <= TILE_SIZE - 3:
				img.set_pixel(ox + x, y, slab_top if y == 2 else slab_face)
			elif y == 5 and (x % 5 == 0 or x % 7 == 0):
				img.set_pixel(ox + x, y, splinter)
			elif (x == 2 or x == TILE_SIZE - 3) and y < 28 and (y % 6 == 2):
				img.set_pixel(ox + x, y, splinter)
	# Ensure exact Suite 9 contracts: center transparent, (0,0) opaque
	img.set_pixel(ox + 16, 16, Color(0.0, 0.0, 0.0, 0.0))
	img.set_pixel(ox + 0, 0, rim_color)


static func _draw_low_obstacle_fence_34(img: Image, col: int, base: Color) -> void:
	var outline: Color = base.darkened(0.62)
	var cap_hi: Color = base.lightened(0.24)
	var face_mid: Color = base
	var face_dark: Color = base.darkened(0.24)
	var rail_hi: Color = base.lightened(0.16)
	var rail_sh: Color = base.darkened(0.32)
	var ground_sh: Color = Color(0.0, 0.0, 0.0, 0.36)

	# Ground cast shadow beneath 3/4 fence
	_fill_rect_tile(img, col, 2, 26, 28, 4, ground_sh)
	_fill_rect_tile(img, col, 4, 30, 24, 1, Color(0.0, 0.0, 0.0, 0.18))

	# Two horizontal cross-rails spanning the tile in 3/4 perspective
	for ry: int in [11, 20]:
		_fill_rect_tile(img, col, 0, ry, TILE_SIZE, 5, outline)
		_fill_rect_tile(img, col, 0, ry + 1, TILE_SIZE, 1, rail_hi)
		_fill_rect_tile(img, col, 0, ry + 2, TILE_SIZE, 1, face_mid)
		_fill_rect_tile(img, col, 0, ry + 3, TILE_SIZE, 1, rail_sh)

	# Two sturdy vertical 3/4 fence posts (left & right) with lit top caps and shaded fronts
	for px: int in [3, 22]:
		_fill_rect_tile(img, col, px, 4, 7, 23, outline)
		# Post top cap (3/4 top surface)
		_fill_rect_tile(img, col, px + 1, 5, 5, 3, cap_hi)
		_fill_rect_tile(img, col, px + 1, 8, 5, 1, outline)
		# Post vertical front face
		_fill_rect_tile(img, col, px + 1, 9, 5, 17, face_mid)
		_fill_rect_tile(img, col, px + 4, 9, 2, 17, face_dark)
		# Nail heads on rails
		_fill_rect_tile(img, col, px + 3, 13, 1, 1, Color("#2D2A28"))
		_fill_rect_tile(img, col, px + 3, 22, 1, 1, Color("#2D2A28"))


static func _draw_wood_wall_34(img: Image, col: int, base: Color) -> void:
	var ox: int = col * TILE_SIZE
	var cap_fill: Color = base.lightened(0.18)
	var cap_hi: Color = base.lightened(0.32)
	var cap_seam: Color = base.darkened(0.22)
	var lip_dark: Color = base.darkened(0.55)
	var front_a: Color = base.darkened(0.18)
	var front_b: Color = base.darkened(0.26)
	var groove: Color = base.darkened(0.46)
	var brace: Color = base.darkened(0.34)
	var ao_base: Color = base.darkened(0.62)

	# Top cap (y = 0..12)
	for y: int in range(0, 13):
		for x: int in range(TILE_SIZE):
			var c: Color = cap_fill
			if y == 0 or x == 0 or x == TILE_SIZE - 1:
				c = cap_seam
			elif y == 1 or y == 11:
				c = cap_hi
			elif y == 12:
				c = cap_fill.lightened(0.08)
			elif x == 8 or x == 16 or x == 24:
				c = cap_seam
			img.set_pixel(ox + x, y, c)

	# Sharp 3/4 cornice overhang shadow crease (y = 13)
	_fill_rect_tile(img, col, 0, 13, TILE_SIZE, 1, lip_dark)

	# Vertical plank front facade (y = 14..29)
	for y: int in range(14, 30):
		for x: int in range(TILE_SIZE):
			var plank: int = floori(float(x) / 8.0)
			var c: Color = front_a if (plank % 2 == 0) else front_b
			if x == 0 or x == 8 or x == 16 or x == 24 or x == TILE_SIZE - 1:
				c = groove
			elif y == 14:
				c = c.darkened(0.14)
			elif y == 20 or y == 21:
				c = brace if y == 20 else brace.darkened(0.18)
			elif y >= 27:
				c = c.darkened(0.16)
			elif ((x * 5 + y * 3) % 13) == 0:
				c = c.darkened(0.08)
			img.set_pixel(ox + x, y, c)
	# Iron nails along horizontal timber brace
	for nx: int in [4, 12, 20, 28]:
		img.set_pixel(ox + nx, 20, Color("#24262E"))

	# Base contact AO shadow (y = 30..31)
	_fill_rect_tile(img, col, 0, 30, TILE_SIZE, 2, ao_base)


static func _draw_brick_wall_34(img: Image, col: int, base: Color) -> void:
	var ox: int = col * TILE_SIZE
	var cap_fill: Color = base.lightened(0.20)
	var cap_hi: Color = base.lightened(0.32)
	var cap_edge: Color = base.darkened(0.28)
	var lip_dark: Color = base.darkened(0.58)
	var mortar: Color = Color("#C4B3A4").darkened(0.34)
	var brick_a: Color = base.darkened(0.16)
	var brick_b: Color = base.darkened(0.24)
	var brick_hi: Color = base.lightened(0.04)
	var ao_base: Color = base.darkened(0.62)

	# Top masonry coping cap (y = 0..11)
	for y: int in range(0, 12):
		for x: int in range(TILE_SIZE):
			var c: Color = cap_fill
			if y == 0 or x == 0 or x == TILE_SIZE - 1:
				c = cap_edge
			elif y == 1 or y == 11:
				c = cap_hi
			elif y == 6 or (y < 6 and x == 16) or (y > 6 and (x == 8 or x == 24)):
				c = mortar
			img.set_pixel(ox + x, y, c)

	# Cornice overhang shadow (y = 12..13)
	_fill_rect_tile(img, col, 0, 12, TILE_SIZE, 1, cap_edge)
	_fill_rect_tile(img, col, 0, 13, TILE_SIZE, 1, lip_dark)

	# Running-bond brick front facade (3 courses: y=14..18, 19..23, 24..29)
	for y: int in range(14, 30):
		var course: int = 0 if y < 19 else (1 if y < 24 else 2)
		var is_h_mortar: bool = (y == 18 or y == 23 or y == 29)
		var is_top_row: bool = (y == 14 or y == 19 or y == 24)
		var v_off: int = 0 if (course % 2 == 0) else 5
		for x: int in range(TILE_SIZE):
			if is_h_mortar or x == 0 or x == TILE_SIZE - 1 or ((x + v_off) % 10 == 0):
				img.set_pixel(ox + x, y, mortar)
			else:
				var brick_id: int = floori(float(x + v_off) / 10.0) + course
				var c: Color = brick_a if (brick_id % 2 == 0) else brick_b
				if is_top_row:
					c = brick_hi if (course > 0) else c.darkened(0.08)
				elif y == 28:
					c = c.darkened(0.16)
				img.set_pixel(ox + x, y, c)

	_fill_rect_tile(img, col, 0, 30, TILE_SIZE, 2, ao_base)


static func _draw_stone_wall_34(img: Image, col: int, base: Color) -> void:
	var ox: int = col * TILE_SIZE
	var cap_fill: Color = base.lightened(0.20)
	var cap_hi: Color = base.lightened(0.32)
	var cap_seam: Color = base.darkened(0.32)
	var lip_dark: Color = base.darkened(0.58)
	var block_a: Color = base.darkened(0.18)
	var block_b: Color = base.darkened(0.28)
	var block_hi: Color = base.darkened(0.06)
	var mortar: Color = base.darkened(0.50)
	var ao_base: Color = base.darkened(0.64)

	# Dressed-stone parapet cap (y = 0..11)
	for y: int in range(0, 12):
		for x: int in range(TILE_SIZE):
			var c: Color = cap_fill
			if y == 0 or x == 0 or x == TILE_SIZE - 1 or x == 16:
				c = cap_seam
			elif y == 1 or y == 11:
				c = cap_hi
			elif ((x * 11 + y * 17) % 23) == 0:
				c = cap_fill.darkened(0.08)
			img.set_pixel(ox + x, y, c)

	_fill_rect_tile(img, col, 0, 12, TILE_SIZE, 1, cap_seam)
	_fill_rect_tile(img, col, 0, 13, TILE_SIZE, 1, lip_dark)

	# Heavy cut ashlar stone blocks on front facade (2 tall courses: y=14..21, 22..29)
	for y: int in range(14, 30):
		var row: int = 0 if y < 22 else 1
		var is_h_joint: bool = (y == 21 or y == 29)
		for x: int in range(TILE_SIZE):
			var vj: bool = (x == 0 or x == TILE_SIZE - 1) or (row == 0 and (x == 12 or x == 24)) or (row == 1 and (x == 6 or x == 19))
			if is_h_joint or vj:
				img.set_pixel(ox + x, y, mortar)
			else:
				var blk: int = (0 if x < 12 else (1 if x < 24 else 2)) if row == 0 else (1 if x < 6 else (0 if x < 19 else 2))
				var c: Color = block_a if (blk % 2 == 0) else block_b
				if y == 22 or (y == 15 and x > 1):
					c = block_hi
				elif y == 14 or y >= 27:
					c = c.darkened(0.14)
				img.set_pixel(ox + x, y, c)

	# Weathering crack on stone facade
	var crack_col: Color = base.darkened(0.62)
	for p: Vector2i in [
		Vector2i(14, 15), Vector2i(15, 16), Vector2i(15, 17), Vector2i(16, 18),
		Vector2i(17, 19), Vector2i(18, 20), Vector2i(17, 23), Vector2i(16, 24),
		Vector2i(15, 25), Vector2i(15, 26), Vector2i(14, 27),
	]:
		img.set_pixel(ox + p.x, p.y, crack_col)

	_fill_rect_tile(img, col, 0, 30, TILE_SIZE, 2, ao_base)


static func _draw_indestructible_wall_34(img: Image, col: int, base: Color) -> void:
	var ox: int = col * TILE_SIZE
	var cap_fill: Color = Color("#2E333E")
	var cap_rim: Color = Color("#4B5364")
	var cap_hi: Color = Color("#636D82")
	var facade: Color = base
	var buttress: Color = Color("#2C313C")
	var buttress_hi: Color = Color("#464E5E")
	var rivet: Color = Color("#7C869C")
	var dark_seam: Color = Color("#0D0E12")

	# Armored obsidian parapet cap (y = 0..12)
	for y: int in range(0, 13):
		for x: int in range(TILE_SIZE):
			var c: Color = cap_fill
			if y == 0 or x == 0 or x == TILE_SIZE - 1:
				c = cap_rim
			elif y == 11:
				c = cap_hi
			elif y == 12:
				c = cap_rim
			elif (y == 3 or y == 8) and (x >= 3 and x <= TILE_SIZE - 4):
				c = Color("#252933")
			img.set_pixel(ox + x, y, c)

	_fill_rect_tile(img, col, 0, 13, TILE_SIZE, 1, dark_seam)

	# Dark obsidian front facade with forged-iron vertical buttresses (y = 14..29)
	for y: int in range(14, 30):
		for x: int in range(TILE_SIZE):
			var c: Color = facade
			if x == 0 or x == TILE_SIZE - 1 or y == 22:
				c = dark_seam
			elif (x >= 5 and x <= 7) or (x >= 24 and x <= 26):
				c = buttress_hi if (x == 5 or x == 24) else buttress
			elif y >= 27:
				c = Color("#242832")
			img.set_pixel(ox + x, y, c)

	# Metallic rivets on buttresses
	for rx: int in [6, 25]:
		for ry: int in [16, 20, 25]:
			img.set_pixel(ox + rx, ry, rivet)

	_fill_rect_tile(img, col, 0, 30, TILE_SIZE, 2, dark_seam)


static func _draw_stairs_tile_34(img: Image, col: int, yellow: Color, blue: Color) -> void:
	var ox: int = col * TILE_SIZE
	var border: Color = blue.darkened(0.55)
	var rail_top: Color = Color("#7A8496")
	var rail_side: Color = Color("#4B5362")
	var crease: Color = blue.darkened(0.52)

	# Base fill & border
	_fill_rect_tile(img, col, 0, 0, TILE_SIZE, TILE_SIZE, border)

	# 5 crisp 3/4 descending steps (tread = gold-yellow, vertical riser = shaded slate-blue)
	for step_i: int in range(5):
		var sy: int = 1 + step_i * 6
		var depth_dim: float = float(step_i) * 0.06
		var tread_hi: Color = yellow.lightened(0.14).darkened(depth_dim)
		var tread_mid: Color = yellow.darkened(depth_dim)
		var riser_col: Color = blue.darkened(0.12 + depth_dim)
		_fill_rect_tile(img, col, 4, sy, 24, 1, tread_hi)
		_fill_rect_tile(img, col, 4, sy + 1, 24, 2, tread_mid)
		_fill_rect_tile(img, col, 4, sy + 3, 24, 2, riser_col)
		_fill_rect_tile(img, col, 4, sy + 5, 24, 1, crease)

	# Side 3/4 balustrade / stone stringers framing the steps
	for rx: int in [0, 28]:
		_fill_rect_tile(img, col, rx, 0, 4, TILE_SIZE, border)
		_fill_rect_tile(img, col, rx + 1, 1, 2, TILE_SIZE - 2, rail_side)
		_fill_rect_tile(img, col, rx + 1, 1, 1, TILE_SIZE - 2, rail_top)

	# Subtle directional chevron hint on middle tread
	for cx: int in range(-3, 4):
		var cy: int = 14 + floori(float(absi(cx)) * 0.5)
		img.set_pixel(ox + 16 + cx, cy, blue.darkened(0.35))


static func _draw_roof_shingles_34(img: Image, col: int, roof_col: Color) -> void:
	var ox: int = col * TILE_SIZE
	var a: float = roof_col.a
	var hi: Color = Color(minf(1.0, roof_col.r * 1.20), minf(1.0, roof_col.g * 1.20), minf(1.0, roof_col.b * 1.20), a)
	var mid: Color = roof_col
	var sh: Color = Color(roof_col.r * 0.72, roof_col.g * 0.72, roof_col.b * 0.72, a)
	var edge: Color = Color(roof_col.r * 0.58, roof_col.g * 0.58, roof_col.b * 0.58, a)

	for y: int in range(TILE_SIZE):
		var row: int = floori(float(y) / 8.0)
		var local_y: int = y % 8
		var stag: int = 0 if (row % 2 == 0) else 4
		for x: int in range(TILE_SIZE):
			var c: Color = mid
			if local_y == 7 or y == 0:
				c = edge
			elif local_y == 6:
				c = sh
			elif local_y == 1:
				c = hi
			elif ((x + stag) % 8) == 0:
				c = sh
			img.set_pixel(ox + x, y, c)
	img.set_pixel(ox + 16, 16, roof_col)


static func _draw_debris_tile_34(img: Image, col: int, rubble_color: Color) -> void:
	var shadow_col: Color = Color(0.0, 0.0, 0.0, 0.34)
	var chunks: Array[Dictionary] = [
		{"rect": Rect2i(3, 6, 5, 4), "col": rubble_color},
		{"rect": Rect2i(17, 5, 6, 4), "col": rubble_color.lightened(0.10)},
		{"rect": Rect2i(10, 14, 5, 4), "col": COLOR_WALL_WOOD.darkened(0.15)},
		{"rect": Rect2i(22, 17, 5, 4), "col": rubble_color.darkened(0.08)},
		{"rect": Rect2i(5, 22, 6, 4), "col": COLOR_WALL_BRICK.darkened(0.15)},
		{"rect": Rect2i(15, 24, 4, 3), "col": rubble_color},
		{"rect": Rect2i(24, 25, 4, 3), "col": COLOR_WALL_WOOD.darkened(0.22)},
	]
	for item: Dictionary in chunks:
		var r: Rect2i = item["rect"] as Rect2i
		var base_c: Color = item["col"] as Color
		var top_c: Color = base_c.lightened(0.20)
		var front_c: Color = base_c.darkened(0.22)
		var out_c: Color = base_c.darkened(0.55)
		# Cast shadow underneath chunk
		_fill_rect_tile(img, col, r.position.x + 1, r.end.y, r.size.x, 2, shadow_col)
		# Chunk outline + 3/4 top cap & front face
		_fill_rect_tile(img, col, r.position.x, r.position.y, r.size.x, r.size.y, out_c)
		if r.size.x > 2 and r.size.y > 2:
			var half_h: int = floori(float(r.size.y) * 0.5)
			var split_y: int = maxi(2, half_h)
			_fill_rect_tile(img, col, r.position.x + 1, r.position.y + 1, r.size.x - 2, maxi(1, half_h - 1), top_c)
			_fill_rect_tile(img, col, r.position.x + 1, r.position.y + split_y, r.size.x - 2, maxi(1, r.size.y - split_y - 1), front_c)


static func _draw_crack_pattern(img: Image, col: int, crack_color: Color) -> void:
	var ox: int = col * TILE_SIZE
	var pts: Array[Vector2i] = [
		Vector2i(6, 5), Vector2i(7, 6), Vector2i(8, 7), Vector2i(9, 8), Vector2i(10, 8),
		Vector2i(11, 9), Vector2i(12, 10), Vector2i(13, 11), Vector2i(14, 12), Vector2i(15, 13),
		Vector2i(16, 14), Vector2i(16, 15), Vector2i(17, 16), Vector2i(18, 17), Vector2i(19, 18),
		Vector2i(20, 19), Vector2i(21, 20), Vector2i(22, 22), Vector2i(23, 23), Vector2i(24, 24),
		# Secondary branch
		Vector2i(15, 14), Vector2i(14, 15), Vector2i(13, 16), Vector2i(12, 18), Vector2i(11, 19),
		Vector2i(10, 20), Vector2i(9, 22), Vector2i(18, 14), Vector2i(19, 13), Vector2i(21, 12),
		Vector2i(22, 11), Vector2i(24, 10),
	]
	for p: Vector2i in pts:
		img.set_pixel(ox + p.x, p.y, crack_color)
