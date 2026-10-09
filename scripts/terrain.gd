extends Node3D
## Generates a blocky, voxel-style world: rolling glacial hills, kettle lakes,
## and a raised moraine around the edge.
##
## Heights live in a 2D grid (one column of blocks per cell). Visuals are
## true blocks; collision is a smooth HeightMapShape3D through the block
## centres, so walking glides up 1-block steps like gentle ramps instead of
## needing to jump (2+ block steps are too steep, so they act as walls).
##
## Units: every tunable below is in METRES. `block_size` only decides how
## finely those metres are chopped into blocks, so the same seed gives the
## same landscape at any block size, just chunkier or finer. Internally the
## grid works in whole blocks ("b" suffix / ix, iz names); anything public that
## returns a position returns metres. See docs/ARCHITECTURE.md.

signal generated

const FLORA_SCRIPT := preload("res://scripts/flora.gd")
const VoxelMesh := preload("res://scripts/voxel_mesh.gd")

@export var world_seed: int = 1848
## Edge length of one voxel in metres. 1.0 is the classic look; 0.5 is twice
## as fine (about 4x the triangles). Override at launch with
## `-- --block-size=0.5`. See docs/CONFIG.md.
@export_range(0.25, 2.0, 0.25) var block_size: float = 1.0
@export var world_size: float = 256.0     ## World edge length (m).
@export var chunk_metres: float = 32.0    ## Chunk edge (m); one mesh per chunk.
@export var base_height: float = 14.0
@export var hill_height: float = 9.0
@export var lake_count: int = 7
@export var lake_radius_min: float = 7.0
@export var lake_radius_max: float = 15.0
@export var lake_depth: float = 6.0
@export var spawn_clear_radius: float = 20.0
@export var moraine_width: float = 14.0
@export var moraine_height: float = 12.0

const COLOR_GRASS := Color(0.38, 0.62, 0.28)
const COLOR_GRASS_DRY := Color(0.55, 0.64, 0.32)
const COLOR_GRASS_SIDE := Color(0.42, 0.50, 0.25)
const COLOR_DIRT := Color(0.47, 0.34, 0.22)
const COLOR_STONE := Color(0.50, 0.50, 0.52)
const COLOR_SAND := Color(0.82, 0.76, 0.55)
const COLOR_MUD := Color(0.40, 0.36, 0.28)
const COLOR_WATER := Color(0.22, 0.45, 0.62, 0.78)

var size: int = 0                          ## World size in blocks (per side).
var size_chunks: int = 0                   ## Chunks per side (derived).
var chunk_size: int = 32                   ## Blocks per chunk side (derived).
var heights := PackedInt32Array()          ## Top surface of each column, in blocks.
var lakes: Array[Dictionary] = []          ## {center: Vector2 (m), radius: m, water_y: m}

var flora: Node3D                          ## Oaks + wildflowers (scripts/flora.gd).

var _shore := PackedByteArray()            ## 1 = sandy shore / lake bed.
var _rng := RandomNumberGenerator.new()
var _block_material: ShaderMaterial
var _water_material: StandardMaterial3D


func _ready() -> void:
	_block_material = VoxelMesh.make_material()

	_water_material = StandardMaterial3D.new()
	_water_material.albedo_color = COLOR_WATER
	_water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_water_material.roughness = 0.08
	_water_material.metallic_specular = 0.7

	generate()


## (Re)builds the whole world from world_seed.
func generate() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	_apply_cmdline_overrides()
	chunk_size = clampi(int(round(chunk_metres / block_size)), 8, 1024)
	size_chunks = maxi(1, int(round(world_size / (block_size * chunk_size))))
	size = size_chunks * chunk_size
	_rng.seed = world_seed

	var t0 := Time.get_ticks_msec()
	var hf := _base_heights()
	_carve_kettles(hf)
	_quantize(hf)
	_fill_lakes()
	_build_chunks()
	_build_water()
	_build_collision()
	var t1 := Time.get_ticks_msec()
	flora = Node3D.new()
	flora.set_script(FLORA_SCRIPT)
	flora.name = "Flora"
	add_child(flora)
	flora.build(self)
	var flowers := 0
	for n in flora.flower_counts.values():
		flowers += n
	print("discwalk: world seed %d (block %.2fm, %d^2 columns) generated in %d ms (%d lakes; flora %d ms: %d oaks, %d flowers)" % [
		world_seed, block_size, size, Time.get_ticks_msec() - t0, lakes.size(),
		Time.get_ticks_msec() - t1, flora.trees.size(), flowers])
	generated.emit()


## `--block-size=0.5` (after `--` on the command line) overrides the export.
func _apply_cmdline_overrides() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--block-size="):
			var v := arg.get_slice("=", 1).to_float()
			if v >= 0.125 and v <= 4.0:
				block_size = v


## Surface height (m) of the column containing world position (x, z) in metres.
func height_at(x: float, z: float) -> float:
	return col_height(col_of(x), col_of(z)) * block_size


## Grid column index for a world coordinate (m), clamped to the world.
func col_of(m: float) -> int:
	return clampi(int(floor(m / block_size)), 0, size - 1)


## Top of column (ix, iz), in blocks.
func col_height(ix: int, iz: int) -> int:
	return heights[clampi(iz, 0, size - 1) * size + clampi(ix, 0, size - 1)]


## True for sandy shore / lake-bed columns (grid indices).
func is_shore(x: int, z: int) -> bool:
	if x < 0 or z < 0 or x >= size or z >= size:
		return false
	return _shore[z * size + x] == 1


## True if the top of column (ix, iz) sits below a lake's waterline.
func is_underwater(x: int, z: int) -> bool:
	return _is_underwater(x, z, heights[z * size + x])


## Distance (m) from world point (x, z) to the nearest lake's edge
## (negative = inside a lake).
func lake_edge_distance(x: float, z: float) -> float:
	var best := 1e9
	var p := Vector2(x, z)
	for lake in lakes:
		best = minf(best, p.distance_to(lake.center) - lake.radius)
	return best


## Where the walker starts (m): middle of the world, a metre above ground.
func spawn_point() -> Vector3:
	var c := world_size / 2.0
	return Vector3(c, height_at(c, c) + 1.0, c)


# --- height generation -------------------------------------------------------

func _base_heights() -> PackedFloat32Array:
	var hills := FastNoiseLite.new()
	hills.seed = world_seed
	hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	hills.frequency = 0.011
	hills.fractal_type = FastNoiseLite.FRACTAL_FBM
	hills.fractal_octaves = 4

	# Long, low swells, like drumlins in a till plain.
	var swells := FastNoiseLite.new()
	swells.seed = world_seed + 1
	swells.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	swells.frequency = 0.004

	var hf := PackedFloat32Array()
	hf.resize(size * size)
	var bs := block_size
	for z in size:
		for x in size:
			var mx := x * bs
			var mz := z * bs
			var h := base_height
			h += hill_height * hills.get_noise_2d(mx, mz)
			h += hill_height * 0.6 * swells.get_noise_2d(mx, mz)
			# Moraine: the world's edge rises into a ridge.
			var edge := float(mini(mini(x, z), mini(size - 1 - x, size - 1 - z))) * bs
			if edge < moraine_width:
				var t := 1.0 - edge / moraine_width
				h += moraine_height * t * t
			hf[z * size + x] = h   # metres
	return hf


func _carve_kettles(hf: PackedFloat32Array) -> void:
	lakes.clear()
	var centre := Vector2(world_size, world_size) / 2.0
	var margin := moraine_width + 4.0
	for i in lake_count:
		for attempt in 60:
			var r := _rng.randf_range(lake_radius_min, lake_radius_max)
			var c := Vector2(
				_rng.randf_range(margin + r, world_size - margin - r),
				_rng.randf_range(margin + r, world_size - margin - r))
			if c.distance_to(centre) < spawn_clear_radius + r:
				continue
			var ok := true
			for lake in lakes:
				if c.distance_to(lake.center) < r + lake.radius + 6.0:
					ok = false
					break
			if not ok:
				continue
			lakes.append({"center": c, "radius": r, "water_y": 0.0})
			_carve_bowl(hf, c, r)
			break


## Presses a round bowl (centre c, radius r, metres) into the height field.
func _carve_bowl(hf: PackedFloat32Array, c: Vector2, r: float) -> void:
	var bs := block_size
	var x0 := maxi(0, int((c.x - r) / bs) - 1)
	var x1 := mini(size - 1, int((c.x + r) / bs) + 1)
	var z0 := maxi(0, int((c.y - r) / bs) - 1)
	var z1 := mini(size - 1, int((c.y + r) / bs) + 1)
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var d := Vector2((x + 0.5) * bs, (z + 0.5) * bs).distance_to(c)
			if d < r:
				var t := d / r
				hf[z * size + x] -= lake_depth * (1.0 - t * t)


## Metres -> whole blocks.
func _quantize(hf: PackedFloat32Array) -> void:
	heights.resize(size * size)
	for i in hf.size():
		heights[i] = maxi(1, int(round(hf[i] / block_size)))


## Water fills each kettle up to just below the lowest point of its rim.
func _fill_lakes() -> void:
	_shore.resize(size * size)
	_shore.fill(0)
	for lake in lakes:
		var c: Vector2 = lake.center
		var r: float = lake.radius
		var bs := block_size
		var rim := 1e9
		for step in 48:
			var a := TAU * step / 48.0
			var p := c + Vector2(cos(a), sin(a)) * r * 0.92
			rim = minf(rim, height_at(p.x, p.y))
		lake.water_y = rim - 0.35 * bs
		# Sandy beach + muddy bed for anything at or below the waterline + 1 block.
		var pad := int(2.0 / bs) + 1
		for z in range(maxi(0, int((c.y - r) / bs) - pad), mini(size, int((c.y + r) / bs) + pad)):
			for x in range(maxi(0, int((c.x - r) / bs) - pad), mini(size, int((c.x + r) / bs) + pad)):
				if Vector2((x + 0.5) * bs, (z + 0.5) * bs).distance_to(c) < r * 1.08:
					if heights[z * size + x] * bs <= lake.water_y + bs:
						_shore[z * size + x] = 1


# --- meshing -----------------------------------------------------------------
# Greedy meshing (see scripts/voxel_mesh.gd): coplanar faces of the same kind
# are merged into big rectangles. Vertex colours carry the base colour plus a
# jitter strength in alpha; shaders/voxel.gdshader adds per-block variation.

func _build_chunks() -> void:
	var holder := Node3D.new()
	holder.name = "Chunks"
	add_child(holder)
	for cz in size_chunks:
		for cx in size_chunks:
			var mi := MeshInstance3D.new()
			mi.name = "Chunk_%d_%d" % [cx, cz]
			mi.mesh = _chunk_mesh(cx * chunk_size, cz * chunk_size)
			mi.material_override = _block_material
			# Meshes are built in block units; scaling the node turns them into metres.
			mi.scale = Vector3.ONE * block_size
			holder.add_child(mi)


## Side faces, one entry per direction: [dx, dz, normal].
const _SIDE_DIRS := [
	[1, 0, Vector3.RIGHT], [-1, 0, Vector3.LEFT],
	[0, 1, Vector3.BACK], [0, -1, Vector3.FORWARD],
]


func _chunk_mesh(ox: int, oz: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var cs := chunk_size

	# Tops: one horizontal "slice" per chunk; rows are z, faces run along x.
	# The colour id packs the height in too, so only same-height faces merge.
	var rows := {}
	for z in range(oz, oz + cs):
		var row := []
		for x in range(ox, ox + cs):
			var h := heights[z * size + x]
			row.append(VoxelMesh.face(x - ox, h * 4 + _top_kind(x, z, h)))
		rows[z - oz] = row
	var rects := VoxelMesh.merge_rows(rows)
	for r in range(0, rects.size(), 5):
		var h := rects[r + 4] >> 2
		VoxelMesh.add_quad(verts, normals, colors,
			Vector3(ox + rects[r], h, oz + rects[r + 1]),
			Vector3(rects[r + 2] - rects[r], 0, 0), Vector3(0, 0, rects[r + 3] - rects[r + 1]),
			Vector3.UP, _top_color(h, rects[r + 4] & 3))

	# Sides: for each direction, one vertical slice per column line. Each column
	# contributes its exposed side split into soil-layer segments, which then
	# merge with identical segments of the neighbouring columns.
	for d: Array in _SIDE_DIRS:
		var dx: int = d[0]
		var dz: int = d[1]
		var n: Vector3 = d[2]
		for s in cs:
			rows = {}
			for t in cs:
				var x := ox + (s if dx != 0 else t)
				var z := oz + (t if dx != 0 else s)
				var h := heights[z * size + x]
				var nx := x + dx
				var nz := z + dz
				var nh := 0
				if nx >= 0 and nx < size and nz >= 0 and nz < size:
					nh = heights[nz * size + nx]
				if nh >= h:
					continue
				rows[t] = _side_segments(x, z, h, nh)
			if rows.is_empty():
				continue
			rects = VoxelMesh.merge_rows(rows)
			var plane := s + (1 if dx + dz > 0 else 0)
			for r in range(0, rects.size(), 5):
				var y0 := rects[r]
				var length := rects[r + 4] >> 3
				var t0 := rects[r + 1]
				var span := rects[r + 3] - t0
				var col := _side_color(rects[r + 4] & 7)
				if dx != 0:
					VoxelMesh.add_quad(verts, normals, colors, Vector3(ox + plane, y0, oz + t0),
						Vector3(0, length, 0), Vector3(0, 0, span), n, col)
				else:
					VoxelMesh.add_quad(verts, normals, colors, Vector3(ox + t0, y0, oz + plane),
						Vector3(0, length, 0), Vector3(span, 0, 0), n, col)

	return VoxelMesh.build_mesh(verts, normals, colors)


## Splits the exposed side of a column (blocks nh..h-1) into soil-layer runs,
## appending face(y0, length * 8 + kind) entries for VoxelMesh.merge_rows().
func _side_segments(x: int, z: int, h: int, nh: int) -> Array:
	var row := []
	var shore := _shore[z * size + x] == 1
	var cur := -1
	var start := nh
	for y in range(nh, h):
		var k := _side_kind((h - y) * block_size, shore)
		if k != cur:
			if cur >= 0:
				row.append(VoxelMesh.face(start, (y - start) * 8 + cur))
			cur = k
			start = y
	row.append(VoxelMesh.face(start, (h - start) * 8 + cur))
	return row


## Top kinds: 0 grass, 1 sand, 2 mud (underwater shore).
func _top_kind(x: int, z: int, h: int) -> int:
	if _shore[z * size + x] == 1:
		return 2 if _is_underwater(x, z, h) else 1
	return 0


## Base colour (rgb) + jitter strength (alpha) for a top face.
func _top_color(h: int, kind: int) -> Color:
	var c: Color
	if kind == 1:
		c = COLOR_SAND
		c.a = 0.08
	elif kind == 2:
		c = COLOR_MUD
		c.a = 0.08
	else:
		var dry := clampf((h * block_size - base_height - 4.0) / 10.0, 0.0, 1.0)
		c = COLOR_GRASS.lerp(COLOR_GRASS_DRY, dry)
		c.a = 0.12
	return c


## Side kinds by metres below the surface: ~2m of sand on shores, 1m of grassy
## turf, dirt down to 4m, then stone.  0 sand, 1 turf, 2 dirt, 3 stone.
func _side_kind(depth: float, shore: bool) -> int:
	if shore and depth <= 2.0:
		return 0
	if depth <= 1.0:
		return 1
	if depth <= 4.0:
		return 2
	return 3


func _side_color(kind: int) -> Color:
	var c: Color
	match kind:
		0:
			c = COLOR_SAND.darkened(0.1)
			c.a = 0.08
		1:
			c = COLOR_GRASS_SIDE
			c.a = 0.10
		2:
			c = COLOR_DIRT
			c.a = 0.12
		_:
			c = COLOR_STONE
			c.a = 0.15
	return c


func _is_underwater(x: int, z: int, h: int) -> bool:
	for lake in lakes:
		if Vector2((x + 0.5) * block_size, (z + 0.5) * block_size).distance_to(lake.center) \
				< lake.radius and h * block_size < lake.water_y:
			return true
	return false


# --- water + collision -------------------------------------------------------

func _build_water() -> void:
	var holder := Node3D.new()
	holder.name = "Lakes"
	add_child(holder)
	for i in lakes.size():
		var lake: Dictionary = lakes[i]
		var disc := CylinderMesh.new()
		disc.top_radius = lake.radius * 0.97
		disc.bottom_radius = lake.radius * 0.97
		disc.height = 0.02
		disc.radial_segments = 48
		disc.rings = 1
		var mi := MeshInstance3D.new()
		mi.name = "Lake_%d" % i
		mi.mesh = disc
		mi.material_override = _water_material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(lake.center.x, lake.water_y, lake.center.y)
		holder.add_child(mi)


func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	add_child(body)

	# Built in block units (one sample per column) and uniformly scaled to
	# metres, so slopes keep the same angle at every block size.
	var shape := HeightMapShape3D.new()
	shape.map_width = size
	shape.map_depth = size
	var data := PackedFloat32Array()
	data.resize(size * size)
	for i in heights.size():
		data[i] = heights[i]
	shape.map_data = data

	var cs := CollisionShape3D.new()
	cs.shape = shape
	# Heightmap points sit at block centres (x + 0.5, z + 0.5).
	cs.position = Vector3(size / 2.0, 0.0, size / 2.0) * block_size
	cs.scale = Vector3.ONE * block_size
	body.add_child(cs)

	# Invisible walls just inside the moraine so nobody walks off the world.
	var wall_h := 200.0
	var t := 2.0
	var inset := 3.0
	var ws := world_size
	var walls := [
		[Vector3(ws / 2.0, 0, inset - t / 2), Vector3(ws, wall_h, t)],
		[Vector3(ws / 2.0, 0, ws - inset + t / 2), Vector3(ws, wall_h, t)],
		[Vector3(inset - t / 2, 0, ws / 2.0), Vector3(t, wall_h, ws)],
		[Vector3(ws - inset + t / 2, 0, ws / 2.0), Vector3(t, wall_h, ws)],
	]
	for w in walls:
		var box := BoxShape3D.new()
		box.size = w[1]
		var wcs := CollisionShape3D.new()
		wcs.shape = box
		wcs.position = w[0]
		body.add_child(wcs)
