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
const DistanceCourse := preload("res://scripts/distance_course.gd")
const BASKETS_SCRIPT := preload("res://scripts/baskets.gd")
const Course := preload("res://scripts/course.gd")
const CourseFile := preload("res://scripts/course_file.gd")

@export var world_seed: int = 1848
## "glacial" (generated from the seed), "distance" (the flat distance
## course, scripts/distance_course.gd) or "course" (a course from a file:
## course_id + layout_name, see course_file.gd). Override with
## `-- --world=distance` or `-- --course=<id> [--layout=<name>]`.
@export_enum("glacial", "distance", "course") var world_kind: String = "glacial"
@export var course_id := ""                ## world_kind "course": its folder name (or path).
@export var layout_name := ""              ## ...and which layout ("" = the first).
## Edge length of one voxel in metres. 0.25 (default) is the detailed look;
## 0.5 or 1.0 (the original chunky look) build much faster and use less
## memory. Override at launch with `-- --block-size=1`. See docs/CONFIG.md.
@export_range(0.25, 2.0, 0.25) var block_size: float = 0.25
## World length along x / z (m). Snapped to whole chunks on generate().
@export var world_x: float = 256.0
@export var world_z: float = 256.0
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
const COLOR_CHALK := Color(0.92, 0.92, 0.86)
const COLOR_PAINT := Color(0.95, 0.80, 0.22)
const COLOR_TEE := Color(0.60, 0.60, 0.58)
const COLOR_WATER := Color(0.22, 0.45, 0.62, 0.78)

var size_x: int = 0                        ## World size in blocks along x.
var size_z: int = 0                        ## World size in blocks along z.
var chunks_x: int = 0                      ## Chunks along x (derived).
var chunks_z: int = 0                      ## Chunks along z (derived).
var chunk_size: int = 32                   ## Blocks per chunk side (derived).
var heights := PackedInt32Array()          ## Top surface of each column, in blocks.
var lakes: Array[Dictionary] = []          ## {center: Vector2 (m), radius: m, water_y: m}

var flora: Node3D                          ## Oaks + wildflowers (scripts/flora.gd).
var baskets: Array = []                    ## The world's baskets (scripts/basket.gd), via baskets.gd.
var basket_field: Node3D                   ## scripts/baskets.gd: sites and owns them.
## The course: one hole per basket, in playing order (scripts/course.gd):
## {n, tee, yaw, pad_yaw, length, basket_at, basket}. Empty on the distance
## course or with --no-baskets.
var holes: Array[Dictionary] = []
## `-- --no-baskets` (or false here) builds the world without any.
var baskets_on := true
## Optional hand-placed trees for tools (see tools/tree_gallery.gd):
## [{x: m, z: m, kind, form, crown?}]. Empty = normal generated placement.
var flora_preset: Array = []
## A course from a file (world_kind "course"): course_file.gd read(), the
## layout being built, and where the world's corner sits in course metres
## (world position = course position - course_origin).
var course: Dictionary = {}
var course_layout: Dictionary = {}
var course_origin := Vector2.ZERO
var _block_size_set := false               ## --block-size= given: it beats the layout's.
var _cmdline_done := false                 ## Flags apply once: after that the menu picks.
var _saved := {}                           ## Settings a course (or the distance field) changed, to put back.

var _shore := PackedByteArray()            ## 1 = sandy shore / lake bed.
var _paint := PackedByteArray()            ## Painted top kind per column (0 = none).
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

	if not _cmdline_done:
		_apply_cmdline_overrides()
		_cmdline_done = true
	for k in _saved:                       # undo the last course's size and blocks
		set(k, _saved[k])
	_saved.clear()
	course_origin = Vector2.ZERO
	if world_kind == "distance":
		_saved = {"world_x": world_x, "world_z": world_z}
		world_x = DistanceCourse.WORLD_X
		world_z = DistanceCourse.WORLD_Z
	if world_kind == "course" and not _open_course():
		world_kind = "glacial"
	chunk_size = clampi(int(round(chunk_metres / block_size)), 8, 1024)
	chunks_x = maxi(1, int(round(world_x / (block_size * chunk_size))))
	chunks_z = maxi(1, int(round(world_z / (block_size * chunk_size))))
	size_x = chunks_x * chunk_size
	size_z = chunks_z * chunk_size
	if world_kind == "course":
		# Whole chunks may come out a little bigger than the bounds: grow
		# them evenly round the middle.
		var b: Rect2 = course_layout.bounds
		course_origin = (b.get_center() - Vector2(size_x, size_z) * block_size / 2.0).snappedf(block_size)
	world_x = size_x * block_size
	world_z = size_z * block_size
	_rng.seed = world_seed

	var t0 := Time.get_ticks_msec()
	var hf: PackedFloat32Array
	if world_kind == "distance":
		lakes.clear()
		hf = DistanceCourse.heights(self)
	elif world_kind == "course":
		hf = _course_heights()
		_level_tees(hf)
		_course_lakes(hf)
	else:
		hf = _base_heights()
		_carve_kettles(hf)
	_quantize(hf)
	_fill_lakes()
	if world_kind == "distance":
		_paint = DistanceCourse.paint(self)
	else:
		_paint.resize(size_x * size_z)
		_paint.fill(0)
	# Trees, then baskets and tees (which steer clear of the trees), then the
	# ground meshes (so the painted tee pads are in them), then flowers (kept
	# off the pads).
	var t1 := Time.get_ticks_msec()
	flora = Node3D.new()
	flora.set_script(FLORA_SCRIPT)
	flora.name = "Flora"
	flora.preset_trees = _course_trees() if world_kind == "course" else flora_preset
	flora.bare = world_kind == "distance"
	flora.fixed_trees = world_kind == "course"
	flora.defer_flowers = true
	add_child(flora)
	flora.build(self)
	var t2 := Time.get_ticks_msec()
	basket_field = Node3D.new()
	basket_field.set_script(BASKETS_SCRIPT)
	basket_field.name = "Baskets"
	if not baskets_on:
		basket_field.count = 0
	add_child(basket_field)
	basket_field.build(self)
	baskets = basket_field.baskets
	holes = basket_field.holes
	Course.paint(self, _paint, holes)
	var basket_ms := Time.get_ticks_msec() - t2
	_build_chunks()
	_build_water()
	_build_collision()
	var t3 := Time.get_ticks_msec()
	flora.scatter_flowers()
	var flora_ms := (t2 - t1) + (Time.get_ticks_msec() - t3)
	var flowers := 0
	for n in flora.flower_counts.values():
		flowers += n
	var what := "%s world seed %d" % [world_kind, world_seed]
	if world_kind == "course":
		what = "course %s: %s" % [course.name, course_layout.name]
	print("discwalk: %s (block %.2fm, %dx%d columns) generated in %d ms (%d lakes; flora %d ms: %d oaks, %d flowers; %d holes %d ms)" % [
		what, block_size, size_x, size_z, Time.get_ticks_msec() - t0, lakes.size(),
		flora_ms, flora.trees.size(), flowers, holes.size(), basket_ms])
	generated.emit()


## `--block-size=1` / `--world=distance` (after `--` on the command line)
## override the exports.
func _apply_cmdline_overrides() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--no-baskets":
			baskets_on = false
		if arg.begins_with("--world="):
			world_kind = arg.get_slice("=", 1)
		if arg.begins_with("--course="):
			world_kind = "course"
			course_id = arg.get_slice("=", 1)
		if arg.begins_with("--layout="):
			layout_name = arg.get_slice("=", 1)
		if arg.begins_with("--block-size="):
			var v := arg.get_slice("=", 1).to_float()
			if v >= 0.125 and v <= 4.0:
				block_size = v
				_block_size_set = true


## Surface height (m) of the column containing world position (x, z) in metres.
func height_at(x: float, z: float) -> float:
	return col_height(col_x(x), col_z(z)) * block_size


## Grid column index for a world x / z coordinate (m), clamped to the world.
func col_x(m: float) -> int:
	return clampi(int(floor(m / block_size)), 0, size_x - 1)


func col_z(m: float) -> int:
	return clampi(int(floor(m / block_size)), 0, size_z - 1)


## Top of column (ix, iz), in blocks.
func col_height(ix: int, iz: int) -> int:
	return heights[clampi(iz, 0, size_z - 1) * size_x + clampi(ix, 0, size_x - 1)]


## True if grid column (ix, iz) is inside the world.
func in_grid(ix: int, iz: int) -> bool:
	return ix >= 0 and iz >= 0 and ix < size_x and iz < size_z


## True if column (ix, iz) has a painted top (tee pad, number, chalk...).
func painted(ix: int, iz: int) -> bool:
	return in_grid(ix, iz) and _paint[iz * size_x + ix] != 0


## True for sandy shore / lake-bed columns (grid indices).
func is_shore(x: int, z: int) -> bool:
	if not in_grid(x, z):
		return false
	return _shore[z * size_x + x] == 1


## True if the top of column (ix, iz) sits below a lake's waterline.
func is_underwater(x: int, z: int) -> bool:
	return _is_underwater(x, z, heights[z * size_x + x])


## Distance (m) from world point (x, z) to the nearest lake's edge
## (negative = inside a lake).
func lake_edge_distance(x: float, z: float) -> float:
	var best := 1e9
	var p := Vector2(x, z)
	for lake in lakes:
		best = minf(best, p.distance_to(lake.center) - lake.radius)
	return best


## Where the walker starts (m): middle of the world, a metre above ground
## (on a course from a file: behind its first tee, once there are holes).
func spawn_point() -> Vector3:
	if world_kind == "distance":
		return DistanceCourse.spawn(self)
	if world_kind == "course" and not holes.is_empty():
		var h: Dictionary = holes[0]
		var p: Vector3 = h.tee - Vector3(-sin(h.pad_yaw), 0, -cos(h.pad_yaw)) * 3.0
		return Vector3(p.x, height_at(p.x, p.z) + 1.0, p.z)
	var cx := world_x / 2.0
	var cz := world_z / 2.0
	return Vector3(cx, height_at(cx, cz) + 1.0, cz)


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
	hf.resize(size_x * size_z)
	var bs := block_size
	for z in size_z:
		for x in size_x:
			var mx := x * bs
			var mz := z * bs
			var h := base_height
			h += hill_height * hills.get_noise_2d(mx, mz)
			h += hill_height * 0.6 * swells.get_noise_2d(mx, mz)
			# Moraine: the world's edge rises into a ridge.
			var edge := float(mini(mini(x, z), mini(size_x - 1 - x, size_z - 1 - z))) * bs
			if edge < moraine_width:
				var t := 1.0 - edge / moraine_width
				h += moraine_height * t * t
			hf[z * size_x + x] = h   # metres
	return hf


func _carve_kettles(hf: PackedFloat32Array) -> void:
	lakes.clear()
	var centre := Vector2(world_x, world_z) / 2.0
	var margin := moraine_width + 4.0
	for i in lake_count:
		for attempt in 60:
			var r := _rng.randf_range(lake_radius_min, lake_radius_max)
			var c := Vector2(
				_rng.randf_range(margin + r, world_x - margin - r),
				_rng.randf_range(margin + r, world_z - margin - r))
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
	var x1 := mini(size_x - 1, int((c.x + r) / bs) + 1)
	var z0 := maxi(0, int((c.y - r) / bs) - 1)
	var z1 := mini(size_z - 1, int((c.y + r) / bs) + 1)
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var d := Vector2((x + 0.5) * bs, (z + 0.5) * bs).distance_to(c)
			if d < r:
				var t := d / r
				hf[z * size_x + x] -= lake_depth * (1.0 - t * t)


## Metres -> whole blocks.
func _quantize(hf: PackedFloat32Array) -> void:
	heights.resize(size_x * size_z)
	for i in hf.size():
		heights[i] = maxi(1, int(round(hf[i] / block_size)))


## Water fills each kettle up to just below the lowest point of its rim.
func _fill_lakes() -> void:
	_shore.resize(size_x * size_z)
	_shore.fill(0)
	for lake in lakes:
		var c: Vector2 = lake.center
		var r: float = lake.radius
		var bs := block_size
		if not lake.get("fixed", false):
			var rim := 1e9
			for step in 48:
				var a := TAU * step / 48.0
				var p := c + Vector2(cos(a), sin(a)) * r * 0.92
				rim = minf(rim, height_at(p.x, p.y))
			lake.water_y = rim - 0.35 * bs
		# Sandy beach + muddy bed for anything at or below the waterline + 1 block.
		var pad := int(2.0 / bs) + 1
		for z in range(maxi(0, int((c.y - r) / bs) - pad), mini(size_z, int((c.y + r) / bs) + pad)):
			for x in range(maxi(0, int((c.x - r) / bs) - pad), mini(size_x, int((c.x + r) / bs) + pad)):
				if Vector2((x + 0.5) * bs, (z + 0.5) * bs).distance_to(c) < r * 1.08:
					if heights[z * size_x + x] * bs <= lake.water_y + bs:
						_shore[z * size_x + x] = 1


# --- courses from files (course_file.gd) -------------------------------------

## The ground sits this high (m) over the world's floor at the course's
## height_min, so a course's edge is a cliff at least this tall.
const COURSE_FLOOR := 4.0
const TEE_FLAT := 2.5     ## Ground is level this far round a course tee (m)...
const TEE_EASE := 5.0     ## ...and back to the heightmap by here.


## Reads course_id's course.json and picks the layout. False (and a warning)
## if it won't do; then generate() falls back to a glacial world.
func _open_course() -> bool:
	var dir := CourseFile.find(course_id)
	if dir == "":
		push_warning("discwalk: no course %s (looked in %s)" % [course_id, CourseFile.search_dirs()])
		return false
	course = CourseFile.read(dir)
	for w in course.warnings:
		push_warning("course %s: %s" % [course_id, w])
	if not course.errors.is_empty():
		for e in course.errors:
			push_error("course %s: %s" % [course_id, e])
		return false
	course_layout = CourseFile.layout(course, layout_name)
	if course_layout.is_empty():
		push_warning("discwalk: course %s has no layout %s; using %s" % [course_id, layout_name,
			course.layouts[0].name])
		course_layout = course.layouts[0]
	_saved = {"block_size": block_size, "world_x": world_x, "world_z": world_z}
	if course_layout.block_size > 0.0 and not _block_size_set:
		block_size = course_layout.block_size
	world_x = course_layout.bounds.size.x
	world_z = course_layout.bounds.size.y
	return true


## Course metres -> world metres, and back.
func to_world(p: Vector2) -> Vector2:
	return p - course_origin


func to_course(p: Vector2) -> Vector2:
	return p + course_origin


## Course height (the heightmap's metres) -> world height (m).
func course_y(h: float) -> float:
	return (h - course.terrain.height_min) * course.terrain.vertical_scale + COURSE_FLOOR


## The heightmap, sampled (bilinear) at every column's centre. Outside the
## map, its edge carries on. No heightmap: flat.
func _course_heights() -> PackedFloat32Array:
	var hf := PackedFloat32Array()
	hf.resize(size_x * size_z)
	hf.fill(COURSE_FLOOR)
	var tr: Dictionary = course.terrain
	if tr.heightmap == "":
		return hf
	var map := CourseFile.heightmap(course.dir.path_join(tr.heightmap))
	if map.is_empty():
		push_error("course %s: can't read %s" % [course_id, tr.heightmap])
		return hf
	var w: int = map.w
	var h: int = map.h
	var v: PackedFloat32Array = map.v
	var span: float = (tr.height_max - tr.height_min) * tr.vertical_scale
	# Map pixel (i, j) covers course metres [i, i+1) * size / map size.
	var kx: float = w / course.size.x
	var kz: float = h / course.size.y
	for iz in size_z:
		var fz := clampf((course_origin.y + (iz + 0.5) * block_size) * kz - 0.5, 0.0, h - 1.0)
		var j0 := mini(int(fz), h - 2) if h > 1 else 0
		var tz := fz - j0
		var j1 := mini(j0 + 1, h - 1)
		for ix in size_x:
			var fx := clampf((course_origin.x + (ix + 0.5) * block_size) * kx - 0.5, 0.0, w - 1.0)
			var i0 := mini(int(fx), w - 2) if w > 1 else 0
			var tx := fx - i0
			var i1 := mini(i0 + 1, w - 1)
			var top := lerpf(v[j0 * w + i0], v[j0 * w + i1], tx)
			var bottom := lerpf(v[j1 * w + i0], v[j1 * w + i1], tx)
			hf[iz * size_x + ix] = COURSE_FLOOR + lerpf(top, bottom, tz) * span
	return hf


## Levels the ground round each of the layout's tees, like a built tee pad:
## flat to TEE_FLAT m at the tee's own height, easing back into the slope
## by TEE_EASE m.
func _level_tees(hf: PackedFloat32Array) -> void:
	for h: Dictionary in course.holes:
		if not h.n in course_layout.holes:
			continue
		var c := to_world(h.tee)
		var ix0 := clampi(col_x(c.x), 0, size_x - 1)
		var iz0 := clampi(col_z(c.y), 0, size_z - 1)
		var y := hf[iz0 * size_x + ix0]
		for iz in range(maxi(0, col_z(c.y - TEE_EASE)), mini(size_z, col_z(c.y + TEE_EASE) + 1)):
			for ix in range(maxi(0, col_x(c.x - TEE_EASE)), mini(size_x, col_x(c.x + TEE_EASE) + 1)):
				var d := Vector2((ix + 0.5) * block_size, (iz + 0.5) * block_size).distance_to(c)
				var k := smoothstep(TEE_EASE, TEE_FLAT, d)
				var i := iz * size_x + ix
				hf[i] = lerpf(hf[i], y, k)


## The course's water, as lakes (in world metres). A level fixes the
## waterline; without one it fills to just under the rim, like a kettle.
## Ground under a fixed level is pressed a little deeper, so rounding to
## whole blocks can't leave a pond dry (lidar gives a pond's flat top).
func _course_lakes(hf: PackedFloat32Array) -> void:
	lakes.clear()
	var area := Rect2(Vector2.ZERO, Vector2(world_x, world_z))
	for w: Dictionary in course.water:
		var c := to_world(w.at)
		if not area.grow(w.radius).has_point(c):
			continue
		var lake := {"center": c, "radius": w.radius, "water_y": 0.0}
		if not is_nan(w.level):
			lake.water_y = course_y(w.level)
			lake.fixed = true
			var bed: float = lake.water_y - 0.6 * block_size - 0.3
			for iz in range(maxi(0, col_z(c.y - w.radius)), mini(size_z, col_z(c.y + w.radius) + 1)):
				for ix in range(maxi(0, col_x(c.x - w.radius)), mini(size_x, col_x(c.x + w.radius) + 1)):
					var i := iz * size_x + ix
					if hf[i] < lake.water_y and Vector2((ix + 0.5) * block_size, (iz + 0.5) * block_size) \
							.distance_to(c) < w.radius:
						hf[i] = minf(hf[i], bed)
		lakes.append(lake)


## The course's trees in this layout (world metres), as flora presets. Not
## in the water, and not off the edge.
func _course_trees() -> Array:
	var out := []
	for t: Dictionary in course.trees:
		var p := to_world(t.at)
		if p.x < 1.0 or p.y < 1.0 or p.x > world_x - 1.0 or p.y > world_z - 1.0:
			continue
		var ix := col_x(p.x)
		var iz := col_z(p.y)
		if is_underwater(ix, iz) or _on_a_hole(t.at, t.crown):
			continue
		out.append({"x": p.x, "z": p.y, "kind": t.kind, "form": t.form, "crown": t.crown})
	return out


## True if a tree at course point p would hang over a tee pad of the layout
## or stand on a basket (the aerial-photo guesses often put one there).
func _on_a_hole(p: Vector2, crown: float) -> bool:
	for h: Dictionary in course.holes:
		if h.n in course_layout.holes and (p.distance_to(h.tee) < crown * 1.8 + 2.0
				or p.distance_to(h.basket) < 2.0):
			return true
	return false


# --- meshing -----------------------------------------------------------------
# Greedy meshing (see scripts/voxel_mesh.gd): coplanar faces of the same kind
# are merged into big rectangles. Vertex colours carry the base colour plus a
# jitter strength in alpha; shaders/voxel.gdshader adds per-block variation.

func _build_chunks() -> void:
	var holder := Node3D.new()
	holder.name = "Chunks"
	add_child(holder)
	for cz in chunks_z:
		for cx in chunks_x:
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
			var h := heights[z * size_x + x]
			row.append(VoxelMesh.face(x - ox, h * 8 + _top_kind(x, z, h)))
		rows[z - oz] = row
	var rects := VoxelMesh.merge_rows(rows)
	for r in range(0, rects.size(), 5):
		var h := rects[r + 4] >> 3
		VoxelMesh.add_quad(verts, normals, colors,
			Vector3(ox + rects[r], h, oz + rects[r + 1]),
			Vector3(rects[r + 2] - rects[r], 0, 0), Vector3(0, 0, rects[r + 3] - rects[r + 1]),
			Vector3.UP, _top_color(h, rects[r + 4] & 7))

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
				var h := heights[z * size_x + x]
				var nx := x + dx
				var nz := z + dz
				var nh := 0
				if in_grid(nx, nz):
					nh = heights[nz * size_x + nx]
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
	var shore := _shore[z * size_x + x] == 1
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


## Top kinds: 0 grass, 1 sand, 2 mud (underwater shore); painted markings
## 3 chalk, 4 yellow, 5 tee pad (scripts/distance_course.gd, scripts/course.gd).
func _top_kind(x: int, z: int, h: int) -> int:
	var paint := _paint[z * size_x + x]
	if paint:
		return paint
	if _shore[z * size_x + x] == 1:
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
	elif kind == 3:
		c = COLOR_CHALK
		c.a = 0.05
	elif kind == 4:
		c = COLOR_PAINT
		c.a = 0.05
	elif kind == 5:
		c = COLOR_TEE
		c.a = 0.10
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

## One water surface over every underwater column: a quad per run of
## columns along x under the same lake, at that lake's waterline. Follows the
## voxel shore exactly, stops at the world's edge, and covers each column
## once where lakes overlap (the first lake that floods it wins).
func _build_water() -> void:
	var holder := Node3D.new()
	holder.name = "Lakes"
	add_child(holder)
	if lakes.is_empty():
		return
	# Which lake floods each column (-1: none), scanning only round the lakes.
	var bs := block_size
	var owner := PackedInt32Array()
	owner.resize(size_x * size_z)
	owner.fill(-1)
	var x0 := size_x
	var x1 := 0
	var z0 := size_z
	var z1 := 0
	for i in lakes.size():
		var lake: Dictionary = lakes[i]
		var c: Vector2 = lake.center
		var r: float = lake.radius
		var lx0 := maxi(0, col_x(c.x - r))
		var lx1 := mini(size_x - 1, col_x(c.x + r))
		var lz0 := maxi(0, col_z(c.y - r))
		var lz1 := mini(size_z - 1, col_z(c.y + r))
		x0 = mini(x0, lx0)
		x1 = maxi(x1, lx1)
		z0 = mini(z0, lz0)
		z1 = maxi(z1, lz1)
		for z in range(lz0, lz1 + 1):
			for x in range(lx0, lx1 + 1):
				var k := z * size_x + x
				if owner[k] < 0 and heights[k] * bs < lake.water_y \
						and Vector2((x + 0.5) * bs, (z + 0.5) * bs).distance_to(c) < r:
					owner[k] = i
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	for z in range(z0, z1 + 1):
		var run_lake := -1
		var run_x := 0
		for x in range(x0, x1 + 2):
			var l := owner[z * size_x + x] if x <= x1 else -1
			if l == run_lake:
				continue
			if run_lake >= 0:
				var y: float = lakes[run_lake].water_y
				var n := verts.size()
				verts.append_array([Vector3(run_x * bs, y, z * bs), Vector3(x * bs, y, z * bs),
					Vector3(x * bs, y, (z + 1) * bs), Vector3(run_x * bs, y, (z + 1) * bs)])
				idx.append_array([n, n + 1, n + 2, n, n + 2, n + 3])
			run_lake = l
			run_x = x
	if verts.is_empty():
		return
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = mesh
	mi.material_override = _water_material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mi)


func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	add_child(body)

	# Built in block units (one sample per column) and uniformly scaled to
	# metres, so slopes keep the same angle at every block size.
	var shape := HeightMapShape3D.new()
	shape.map_width = size_x
	shape.map_depth = size_z
	var data := PackedFloat32Array()
	data.resize(size_x * size_z)
	for i in heights.size():
		data[i] = heights[i]
	shape.map_data = data

	var cs := CollisionShape3D.new()
	cs.shape = shape
	# Heightmap points sit at block centres (x + 0.5, z + 0.5).
	cs.position = Vector3(size_x / 2.0, 0.0, size_z / 2.0) * block_size
	cs.scale = Vector3.ONE * block_size
	body.add_child(cs)

	# Invisible walls just inside the moraine so nobody walks off the world.
	var wall_h := 200.0
	var t := 2.0
	var inset := 3.0
	var wx := world_x
	var wz := world_z
	var walls := [
		[Vector3(wx / 2.0, 0, inset - t / 2), Vector3(wx, wall_h, t)],
		[Vector3(wx / 2.0, 0, wz - inset + t / 2), Vector3(wx, wall_h, t)],
		[Vector3(inset - t / 2, 0, wz / 2.0), Vector3(t, wall_h, wz)],
		[Vector3(wx - inset + t / 2, 0, wz / 2.0), Vector3(t, wall_h, wz)],
	]
	for w in walls:
		var box := BoxShape3D.new()
		box.size = w[1]
		var wcs := CollisionShape3D.new()
		wcs.shape = box
		wcs.position = w[0]
		body.add_child(wcs)
