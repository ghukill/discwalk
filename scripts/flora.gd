extends Node3D
## Oaks and wildflowers, grown from the terrain's seed.
##
## Oaks: each tree is "grown" voxel by voxel: a stout trunk, 2-4 crooked limbs
## reaching outward, and a broad crown of squashed, noise-eaten leaf blobs.
## Trees cluster into groves with open meadows between (Michigan oak openings),
## plus the odd giant lone oak out in a field. Tree voxels are meshed per chunk
## with hidden faces culled, just like the terrain. Trunks are solid; crowns
## are walk-through.
##
## Flowers: small voxel-built plants drawn with MultiMesh (thousands are cheap)
## and a wind-sway shader. Species follow habitat: iris + marsh marigold by the
## water, trillium in oak shade, and patches of black-eyed Susan, coneflower,
## lupine and butterfly weed out in the meadows.
##
## Units: sizes and distances are in metres; voxels live on the terrain's block
## grid (Vector3i keys in blocks) and the tree meshes are scaled by
## terrain.block_size. So a smaller block size gives the same oak, built from
## more, smaller blocks. Flower density is per square metre, so the meadow
## doesn't get 4x busier at half-size blocks.

const SWAY_SHADER := preload("res://shaders/sway.gdshader")
const VoxelMesh := preload("res://scripts/voxel_mesh.gd")

const BARK := 1
const LEAF := 2

const COLOR_BARK := Color(0.34, 0.25, 0.17)
const COLOR_LEAF := Color(0.22, 0.42, 0.16)
const COLOR_LEAF_ALT := Color(0.33, 0.47, 0.17)   ## Some oaks are a touch yellower.
const COLOR_STEM := Color(0.27, 0.45, 0.18)

## Flower species. habitat: "shore", "shade" or "meadow".
const SPECIES := {
	"black_eyed_susan": {"habitat": "meadow"},
	"coneflower": {"habitat": "meadow"},
	"lupine": {"habitat": "meadow"},
	"butterfly_weed": {"habitat": "meadow"},
	"blue_flag_iris": {"habitat": "shore"},
	"marsh_marigold": {"habitat": "shore"},
	"trillium": {"habitat": "shade"},
}
const MEADOW_SPECIES := ["black_eyed_susan", "coneflower", "lupine", "butterfly_weed"]

@export var grove_spacing: float = 6.0       ## Candidate grid for tree placement (m).
@export var region_size: int = 64            ## Flower MultiMesh batching (m), for culling.
@export var flower_view_distance: float = 110.0

var terrain: Node3D
var trees: Array[Dictionary] = []            ## {pos: Vector2i (column), kind, crown (m), collider}
var flower_counts := {}                      ## species -> count
var voxel_count := 0
var timings := {}                            ## Build step -> ms (for the smoke test).

var _vox := {}                               ## Vector3i -> BARK/LEAF
var _vox_color := {}                         ## Vector3i -> base Color (alpha = jitter strength)
var _shade := PackedByteArray()              ## 1 = column under an oak crown.
var _trunk_cols := PackedByteArray()         ## 1 = column has a trunk at ground level.
var _rng := RandomNumberGenerator.new()
var _leaf_noise := FastNoiseLite.new()
var _bark_material: ShaderMaterial
var _sway_material: ShaderMaterial
var _bs := 1.0                               ## terrain.block_size, cached.


func build(t: Node3D) -> void:
	terrain = t
	_bs = terrain.block_size
	var size: int = terrain.size
	_rng.seed = terrain.world_seed * 7919 + 17
	_leaf_noise.seed = terrain.world_seed + 99
	_leaf_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_leaf_noise.frequency = 0.35
	_shade.resize(size * size)
	_shade.fill(0)
	_trunk_cols.resize(size * size)
	_trunk_cols.fill(0)

	_bark_material = VoxelMesh.make_material()
	_sway_material = ShaderMaterial.new()
	_sway_material.shader = SWAY_SHADER

	var t0 := Time.get_ticks_msec()
	_place_trees()
	var t1 := Time.get_ticks_msec()
	_build_tree_meshes()
	var t2 := Time.get_ticks_msec()
	_scatter_flowers()
	timings["place"] = t1 - t0
	timings["trees"] = t2 - t1
	timings["flowers"] = Time.get_ticks_msec() - t2


# --- tree placement ----------------------------------------------------------

func _place_trees() -> void:
	var size: int = terrain.size
	var groves := FastNoiseLite.new()
	groves.seed = terrain.world_seed + 42
	groves.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	groves.frequency = 0.010
	groves.fractal_octaves = 2

	var spawn: Vector3 = terrain.spawn_point()
	var placed: Array[Dictionary] = []
	var cells := int(terrain.world_size / grove_spacing)
	for gz in cells:
		for gx in cells:
			# Candidate spot in metres, then snapped to a grid column.
			var mx := float(int((gx + _rng.randf_range(0.1, 0.9)) * grove_spacing))
			var mz := float(int((gz + _rng.randf_range(0.1, 0.9)) * grove_spacing))
			var x: int = terrain.col_of(mx)
			var z: int = terrain.col_of(mz)
			var g := groves.get_noise_2d(mx, mz)   # ~[-1, 1]; high = grove
			var kind := ""
			if g > 0.12:
				# Inside a grove: dense-ish, mostly medium/big oaks.
				if _rng.randf() > 0.72:
					continue
				var r := _rng.randf()
				kind = "big" if r < 0.35 else ("medium" if r < 0.85 else "sapling")
			elif g > -0.05:
				# Grove edge: sparse, younger trees.
				if _rng.randf() > 0.25:
					continue
				kind = "sapling" if _rng.randf() < 0.55 else "medium"
			else:
				# Open meadow: the rare giant lone oak.
				if _rng.randf() > 0.012:
					continue
				kind = "giant"
			var crown: float = {"giant": 7.0, "big": 5.0, "medium": 3.6, "sapling": 1.8}[kind]
			if not _can_grow(x, z, kind, crown, spawn, placed):
				# Giants are picky; let them fall back to a big oak.
				continue
			var tree := {"pos": Vector2i(x, z), "kind": kind, "crown": crown}
			placed.append(tree)
	trees = placed


## x, z are grid columns; crown and all distances are metres.
func _can_grow(x: int, z: int, kind: String, crown: float, spawn: Vector3,
		placed: Array[Dictionary]) -> bool:
	var size: int = terrain.size
	var m := _col_centre(x, z)
	var edge := minf(minf(m.x, m.y), minf(terrain.world_size - m.x, terrain.world_size - m.y))
	if edge < 6.0:
		return false
	if m.distance_to(Vector2(spawn.x, spawn.z)) < 7.0 + crown:
		return false
	if terrain.lake_edge_distance(m.x, m.y) < 2.5 + crown * 0.4:
		return false
	# Not on steep ground: within 2 m around the trunk, ground stays within 2 m.
	var reach := maxi(1, int(round(2.0 / _bs)))
	var h0: int = terrain.heights[z * size + x]
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var nx := clampi(x + dx, 0, size - 1)
			var nz := clampi(z + dz, 0, size - 1)
			if terrain.is_shore(nx, nz) \
					or absi(terrain.heights[nz * size + nx] - h0) * _bs > 2.0:
				return false
	for other in placed:
		var d: float = m.distance_to(_col_centre(other.pos.x, other.pos.y))
		if d < (crown + float(other.crown)) * 0.62:
			return false
	return true


## Centre of grid column (ix, iz) in metres.
func _col_centre(ix: int, iz: int) -> Vector2:
	return Vector2((ix + 0.5) * _bs, (iz + 0.5) * _bs)


## Metres -> whole blocks (at least 1).
func _blocks(metres: float) -> int:
	return maxi(1, int(round(metres / _bs)))


# --- growing an oak ----------------------------------------------------------

func _grow_tree(tree: Dictionary, index: int) -> void:
	var size: int = terrain.size
	var rng := RandomNumberGenerator.new()
	rng.seed = terrain.world_seed * 104729 + index * 7 + 3
	var kind: String = tree.kind
	var p: Vector2i = tree.pos
	var crown: float = tree.crown * rng.randf_range(0.9, 1.12)

	# Trunk height (m) and width (m): 2 m wide for big/giant oaks, 1 m otherwise.
	var trunk_m: int = {"giant": rng.randi_range(5, 6), "big": rng.randi_range(4, 5),
		"medium": rng.randi_range(3, 4), "sapling": rng.randi_range(2, 3)}[kind]
	var thick := kind == "giant" or kind == "big"
	var leaf_base := COLOR_LEAF.lerp(COLOR_LEAF_ALT, rng.randf() * rng.randf())
	var foot_n := _blocks(2.0 if thick else 1.0)       # trunk footprint, blocks per side

	# Trunk: each footprint column grows from its own ground up to a shared top.
	var foot: Array[Vector2i] = []
	for fz in foot_n:
		for fx in foot_n:
			foot.append(Vector2i(clampi(p.x + fx, 0, size - 1), clampi(p.y + fz, 0, size - 1)))
	var ground := 1 << 30
	for f in foot:
		ground = mini(ground, terrain.heights[f.y * size + f.x])
	var top := ground + _blocks(trunk_m)
	for f in foot:
		_trunk_cols[f.y * size + f.x] = 1
		for y in range(terrain.heights[f.y * size + f.x], top + 1):
			_set_bark(Vector3i(f.x, y, f.y))
	# From here on, positions are in BLOCK units (converted back for the collider).
	var centre := Vector3(p.x + foot_n / 2.0, top + 0.5, p.y + foot_n / 2.0)
	var collider_h := float(top - ground + 1) * _bs
	tree["collider"] = {
		"pos": Vector3(centre.x * _bs, ground * _bs + collider_h / 2.0, centre.z * _bs),
		"size": Vector3(foot_n * _bs, collider_h, foot_n * _bs)}
	crown /= _bs   # metres -> blocks for the crown/limb geometry below

	# Central crown blob, sitting on top of the trunk.
	var blobs: Array = [[centre + Vector3(0, crown * 0.35, 0), crown * 0.72]]

	# Limbs: crooked bark lines reaching outward and up, each ending in a blob.
	var limbs: int = {"giant": rng.randi_range(4, 5), "big": rng.randi_range(3, 4),
		"medium": rng.randi_range(2, 3), "sapling": 0}[kind]
	var az0 := rng.randf() * TAU
	for i in limbs:
		var az := az0 + TAU * i / limbs + rng.randf_range(-0.4, 0.4)
		var elev := deg_to_rad(rng.randf_range(28.0, 50.0))
		var length := crown * rng.randf_range(0.7, 0.95)
		var dir := Vector3(cos(az) * cos(elev), sin(elev), sin(az) * cos(elev))
		var drop_m := rng.randi_range(0, mini(2, trunk_m - 2))   # limbs start up to 2 m down
		var pos := centre - Vector3(0, drop_m / _bs, 0)
		var step := 0.5 / _bs                                   # half a metre, in blocks
		var steps := int(length / step)
		var limb_n := _blocks(1.0)                              # limbs ~1 m thick
		for s in steps:
			# Wander a little so limbs look crooked, not ruler-straight.
			dir = (dir + Vector3(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.08, 0.1),
				rng.randf_range(-0.12, 0.12))).normalized()
			pos += dir * step
			# Taper towards the tip when blocks are fine enough to show it.
			var n := maxi(1, int(round(limb_n * lerpf(1.0, 0.5, float(s) / steps))))
			_bark_cube(pos, n)
			if thick and s < steps / 2:
				_bark_cube(pos - Vector3(0, limb_n, 0), n)
		blobs.append([pos + Vector3(0, 0.6 / _bs, 0), crown * rng.randf_range(0.5, 0.66)])

	# Leaves: squashed ellipsoids (wider than tall) with noisy, bitten edges.
	for b in blobs:
		_leaf_blob(b[0], b[1], leaf_base, rng)


## Stamps an n x n x n cube of bark around p (block units).
func _bark_cube(p: Vector3, n: int) -> void:
	var o := Vector3i(floori(p.x - (n - 1) / 2.0), floori(p.y - (n - 1) / 2.0), floori(p.z - (n - 1) / 2.0))
	for dy in n:
		for dz in n:
			for dx in n:
				_set_bark(o + Vector3i(dx, dy, dz))


## Leaf blob centred at c with radius r, both in block units.
func _leaf_blob(c: Vector3, r: float, base: Color, rng: RandomNumberGenerator) -> void:
	var size: int = terrain.size
	var ry := r * 0.62
	for y in range(floori(c.y - ry) - 1, ceili(c.y + ry) + 2):
		for z in range(floori(c.z - r) - 1, ceili(c.z + r) + 2):
			for x in range(floori(c.x - r) - 1, ceili(c.x + r) + 2):
				if x < 1 or z < 1 or x >= size - 1 or z >= size - 1:
					continue
				var dx := (x + 0.5 - c.x) / r
				var dy := (y + 0.5 - c.y) / ry
				var dz := (z + 0.5 - c.z) / r
				var d := dx * dx + dy * dy + dz * dz
				# Edge test: d > 0.78 + noise * 0.45, noise in [-1, 1]. Only sample
				# the (slow) noise in the band where it can change the answer.
				if d > 1.23:
					continue
				if d > 0.33:
					# Noise sampled in metres, so the "bites" are the same size at any block size.
					var n := _leaf_noise.get_noise_3d(x * _bs, y * _bs, z * _bs)
					if d > 0.78 + n * 0.45:
						continue
				var key := Vector3i(x, y, z)
				if _vox.get(key, 0) == BARK:
					continue
				if y < terrain.heights[z * size + x]:
					continue
				_vox[key] = LEAF
				# Lighter on top, darker underneath (in 5 bands so faces can merge);
				# per-leaf jitter comes from the voxel shader.
				var shade := snappedf(clampf(0.5 - dy * 0.5, 0.0, 1.0), 0.25)
				var col := base.darkened(shade * 0.28).lightened(0.06 if dy > 0.4 else 0.0)
				col.a = 0.14
				_vox_color[key] = col
				_shade[z * size + x] = 1


func _set_bark(key: Vector3i) -> void:
	_vox[key] = BARK
	var col := COLOR_BARK
	col.a = 0.25
	_vox_color[key] = col


# --- tree meshing + collision ------------------------------------------------

func _build_tree_meshes() -> void:
	var t0 := Time.get_ticks_msec()
	for i in trees.size():
		_grow_tree(trees[i], i)
	voxel_count = _vox.size()
	timings["grow"] = Time.get_ticks_msec() - t0

	# Bucket voxels by terrain chunk so each chunk gets one tree mesh.
	var cs: int = terrain.chunk_size
	var buckets := {}
	for key in _vox:
		var ck := Vector2i(key.x / cs, key.z / cs)
		if not buckets.has(ck):
			buckets[ck] = []
		buckets[ck].append(key)

	var holder := Node3D.new()
	holder.name = "Trees"
	add_child(holder)
	for ck: Vector2i in buckets:
		var mesh := _tree_chunk_mesh(buckets[ck], ck.x * cs, ck.y * cs)
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Trees_%d_%d" % [ck.x, ck.y]
		mi.mesh = mesh
		mi.material_override = _bark_material
		mi.scale = Vector3.ONE * _bs   # block units -> metres
		holder.add_child(mi)

	# Solid trunks (crowns stay walk-through, for now).
	var body := StaticBody3D.new()
	body.name = "Trunks"
	add_child(body)
	for tree in trees:
		var box := BoxShape3D.new()
		box.size = tree.collider.size
		var shape := CollisionShape3D.new()
		shape.shape = box
		shape.position = tree.collider.pos
		body.add_child(shape)


## The six face directions: [neighbour offset, normal axis, u axis, v axis,
## colour darkening]. Undersides are darker, sides a little darker.
const _TREE_DIRS := [
	[Vector3i(1, 0, 0), 0, 1, 2, 0.08], [Vector3i(-1, 0, 0), 0, 1, 2, 0.08],
	[Vector3i(0, 1, 0), 1, 0, 2, 0.0], [Vector3i(0, -1, 0), 1, 0, 2, 0.25],
	[Vector3i(0, 0, 1), 2, 0, 1, 0.08], [Vector3i(0, 0, -1), 2, 0, 1, 0.08],
]


## Greedy-meshes one chunk's tree voxels. Visible faces are grouped by
## direction and plane, then merged with VoxelMesh.merge_rows().
func _tree_chunk_mesh(keys: Array, ox: int, oz: int) -> ArrayMesh:
	var size: int = terrain.size
	var palette := {}            # Color -> cid
	var colours: Array[Color] = []
	# planes[dir] = { plane -> { v -> Array of face(u, cid) } }
	var planes := [{}, {}, {}, {}, {}, {}]
	var origin := Vector3i(ox, 0, oz)
	for key: Vector3i in keys:
		var col: Color = _vox_color[key]
		var cid: int = palette.get(col, -1)
		if cid < 0:
			cid = colours.size()
			palette[col] = cid
			colours.append(col)
		var local := key - origin
		for di in 6:
			var d: Array = _TREE_DIRS[di]
			var nb: Vector3i = key + d[0]
			if _vox.has(nb):
				continue
			# Hidden inside the ground?
			if nb.x >= 0 and nb.z >= 0 and nb.x < size and nb.z < size \
					and nb.y < terrain.heights[nb.z * size + nb.x]:
				continue
			var a: int = d[1]
			var plane: int = local[a] + (1 if d[0][a] > 0 else 0)
			var v: int = local[d[3]]
			var by_v: Dictionary = planes[di].get(plane, {})
			if by_v.is_empty():
				planes[di][plane] = by_v
			if not by_v.has(v):
				by_v[v] = []
			by_v[v].append(VoxelMesh.face(local[d[2]], cid))

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var cols := PackedColorArray()
	for di in 6:
		var d: Array = _TREE_DIRS[di]
		var n := Vector3(d[0])
		var a: int = d[1]
		var ua: int = d[2]
		var va: int = d[3]
		var dark: float = d[4]
		for plane: int in planes[di]:
			var rects := VoxelMesh.merge_rows(planes[di][plane])
			for r in range(0, rects.size(), 5):
				var o := Vector3.ZERO
				o[a] = plane
				o[ua] = rects[r]
				o[va] = rects[r + 1]
				var eu := Vector3.ZERO
				eu[ua] = rects[r + 2] - rects[r]
				var ev := Vector3.ZERO
				ev[va] = rects[r + 3] - rects[r + 1]
				var col: Color = colours[rects[r + 4]]
				var face_col := col.darkened(dark)
				face_col.a = col.a
				VoxelMesh.add_quad(verts, normals, cols, o + Vector3(origin), eu, ev, n, face_col)
	if verts.is_empty():
		return null
	return VoxelMesh.build_mesh(verts, normals, cols)


## Same winding rule as the terrain: v x u == normal.
func _quad(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray,
		o: Vector3, u: Vector3, v: Vector3, n: Vector3, col: Color) -> void:
	# Pick the winding so the face points along n.
	if v.cross(u).dot(n) < 0.0:
		var t := u
		u = v
		v = t
	verts.append(o)
	verts.append(o + u)
	verts.append(o + v)
	verts.append(o + u)
	verts.append(o + u + v)
	verts.append(o + v)
	for i in 6:
		normals.append(n)
		colors.append(col)


# --- flowers -----------------------------------------------------------------

func _scatter_flowers() -> void:
	var size: int = terrain.size
	var clumps := FastNoiseLite.new()
	clumps.seed = terrain.world_seed + 7
	clumps.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	clumps.frequency = 0.07
	var patches := FastNoiseLite.new()        # Which meadow species owns a patch.
	patches.seed = terrain.world_seed + 8
	patches.noise_type = FastNoiseLite.TYPE_CELLULAR
	patches.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	patches.frequency = 0.035

	var meshes := {}
	for sp in SPECIES:
		meshes[sp] = _flower_mesh(sp)
	# region -> species -> Array[Transform3D]
	var batches := {}
	flower_counts.clear()
	var spawn: Vector3 = terrain.spawn_point()
	var area := _bs * _bs          # m^2 per column
	var margin := maxi(1, int(4.0 / _bs))

	# No habitat accepts a roll above this, so most columns bail out early.
	var max_roll := 0.61
	for z in range(margin, size - margin):
		for x in range(margin, size - margin):
			var roll := _hash(x, 7, z) / area
			if roll >= max_roll:
				continue
			var i := z * size + x
			if _trunk_cols[i] == 1 or terrain.is_underwater(x, z):
				continue
			var h: int = terrain.heights[i]
			if _vox.has(Vector3i(x, h, z)):
				continue
			var m := _col_centre(x, z)
			var c: float = clumps.get_noise_2d(m.x, m.y)
			# Densities are "per square metre": `roll` is scaled by the column area
			# above, so smaller columns pass less often.
			var sp := ""
			var edge_d: float = terrain.lake_edge_distance(m.x, m.y)
			if edge_d > -1.5 and edge_d < 3.5:
				# Lakeshore: iris right at the water, marigold in the wet mud/sand.
				if roll < 0.10 + maxf(c, 0.0) * 0.35:
					sp = "blue_flag_iris" if _hash(x, 11, z) < 0.55 else "marsh_marigold"
			elif terrain.is_shore(x, z):
				continue
			elif _shade[i] == 1:
				if roll < 0.05 + maxf(c, 0.0) * 0.18:
					sp = "trillium"
			else:
				# Meadow: clumps of one species per patch.
				# Dense clumps where the clump noise is high, plus a light sprinkle.
				var density := clampf((c + 0.05) * 0.75, 0.0, 0.6) + 0.006
				if roll < density:
					# Cellular noise gives each patch one value; hash it to a species.
					var cell := int(absf(patches.get_noise_2d(m.x, m.y)) * 9973.0)
					sp = MEADOW_SPECIES[cell % MEADOW_SPECIES.size()]
					# ...with the odd stray from another species mixed in.
					if _hash(x, 29, z) < 0.12:
						sp = MEADOW_SPECIES[int(_hash(x, 31, z) * 3.99)]
			if sp == "":
				continue
			if m.distance_to(Vector2(spawn.x, spawn.z)) < 1.5:
				continue
			var yaw := _hash(x, 13, z) * TAU
			var s := 1.05 + _hash(x, 17, z) * 0.5
			var basis := Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s))
			var pos := Vector3((x + 0.2 + _hash(x, 19, z) * 0.6) * _bs, h * _bs,
				(z + 0.2 + _hash(x, 23, z) * 0.6) * _bs)
			var region := Vector2i(int(pos.x) / region_size, int(pos.z) / region_size)
			if not batches.has(region):
				batches[region] = {}
			if not batches[region].has(sp):
				batches[region][sp] = []
			batches[region][sp].append(Transform3D(basis, pos))
			flower_counts[sp] = flower_counts.get(sp, 0) + 1

	var holder := Node3D.new()
	holder.name = "Flowers"
	add_child(holder)
	for region in batches:
		for sp in batches[region]:
			var xforms: Array = batches[region][sp]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = meshes[sp]
			mm.instance_count = xforms.size()
			for k in xforms.size():
				mm.set_instance_transform(k, xforms[k])
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "%s_%d_%d" % [sp, region.x, region.y]
			mmi.multimesh = mm
			mmi.material_override = _sway_material
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = flower_view_distance
			mmi.visibility_range_end_margin = 10.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			holder.add_child(mmi)


## Little voxel plants, built from boxes around the origin (base at y=0).
func _flower_mesh(sp: String) -> ArrayMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	match sp:
		"black_eyed_susan":
			_box(v, n, c, Vector3(0, 0.25, 0), Vector3(0.04, 0.5, 0.04), COLOR_STEM)
			_box(v, n, c, Vector3(0.05, 0.12, 0), Vector3(0.12, 0.03, 0.05), COLOR_STEM)
			_box(v, n, c, Vector3(0, 0.52, 0), Vector3(0.24, 0.04, 0.24), Color(0.98, 0.76, 0.10))
			_box(v, n, c, Vector3(0, 0.56, 0), Vector3(0.09, 0.07, 0.09), Color(0.24, 0.13, 0.06))
		"coneflower":
			_box(v, n, c, Vector3(0, 0.3, 0), Vector3(0.04, 0.6, 0.04), COLOR_STEM)
			_box(v, n, c, Vector3(-0.05, 0.18, 0), Vector3(0.12, 0.03, 0.05), COLOR_STEM)
			_box(v, n, c, Vector3(0, 0.61, 0), Vector3(0.26, 0.03, 0.26), Color(0.80, 0.42, 0.72))
			_box(v, n, c, Vector3(0, 0.67, 0), Vector3(0.11, 0.11, 0.11), Color(0.55, 0.28, 0.10))
		"lupine":
			_box(v, n, c, Vector3(0, 0.08, 0), Vector3(0.22, 0.05, 0.22), COLOR_STEM)
			_box(v, n, c, Vector3(0, 0.25, 0), Vector3(0.04, 0.4, 0.04), COLOR_STEM)
			for k in 5:
				var w := 0.13 - k * 0.018
				var col := Color(0.38, 0.40, 0.86).lerp(Color(0.62, 0.55, 0.95), k / 4.0)
				_box(v, n, c, Vector3(0, 0.36 + k * 0.08, 0), Vector3(w, 0.07, w), col)
		"butterfly_weed":
			_box(v, n, c, Vector3(0, 0.18, 0), Vector3(0.05, 0.36, 0.05), COLOR_STEM)
			_box(v, n, c, Vector3(0.06, 0.2, 0.02), Vector3(0.12, 0.03, 0.05), COLOR_STEM)
			var orange := Color(0.98, 0.50, 0.08)
			_box(v, n, c, Vector3(0, 0.38, 0), Vector3(0.14, 0.06, 0.14), orange)
			_box(v, n, c, Vector3(0.1, 0.35, 0.06), Vector3(0.1, 0.05, 0.1), orange.darkened(0.08))
			_box(v, n, c, Vector3(-0.08, 0.34, -0.07), Vector3(0.1, 0.05, 0.1), orange.lightened(0.08))
		"blue_flag_iris":
			# Tall sword leaves + a violet-blue bloom.
			_box(v, n, c, Vector3(0.05, 0.35, 0), Vector3(0.03, 0.7, 0.08), COLOR_STEM)
			_box(v, n, c, Vector3(-0.05, 0.3, 0.03), Vector3(0.03, 0.6, 0.08), COLOR_STEM.darkened(0.1))
			_box(v, n, c, Vector3(0, 0.38, -0.05), Vector3(0.08, 0.76, 0.03), COLOR_STEM.lightened(0.05))
			_box(v, n, c, Vector3(0, 0.8, 0), Vector3(0.16, 0.12, 0.16), Color(0.36, 0.36, 0.82))
			_box(v, n, c, Vector3(0, 0.86, 0), Vector3(0.07, 0.06, 0.07), Color(0.95, 0.85, 0.30))
		"marsh_marigold":
			_box(v, n, c, Vector3(0, 0.05, 0), Vector3(0.3, 0.1, 0.3), Color(0.20, 0.44, 0.16))
			var yel := Color(1.0, 0.85, 0.12)
			_box(v, n, c, Vector3(0.07, 0.14, 0.05), Vector3(0.09, 0.06, 0.09), yel)
			_box(v, n, c, Vector3(-0.08, 0.13, 0.02), Vector3(0.09, 0.06, 0.09), yel)
			_box(v, n, c, Vector3(0, 0.15, -0.08), Vector3(0.09, 0.06, 0.09), yel)
		"trillium":
			_box(v, n, c, Vector3(0, 0.12, 0), Vector3(0.03, 0.24, 0.03), COLOR_STEM)
			_box(v, n, c, Vector3(0, 0.2, 0), Vector3(0.3, 0.02, 0.3), Color(0.18, 0.38, 0.14))
			var white := Color(0.96, 0.96, 0.92)
			for k in 3:
				var a := TAU * k / 3.0
				_box(v, n, c, Vector3(cos(a) * 0.06, 0.26, sin(a) * 0.06),
					Vector3(0.08, 0.03, 0.08), white)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_COLOR] = c
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _box(v: PackedVector3Array, n: PackedVector3Array, c: PackedColorArray,
		centre: Vector3, sz: Vector3, col: Color) -> void:
	var h := sz / 2.0
	var o := centre - h
	_quad(v, n, c, o + Vector3(sz.x, 0, 0), Vector3(0, 0, sz.z), Vector3(0, sz.y, 0), Vector3.RIGHT, col.darkened(0.08))
	_quad(v, n, c, o, Vector3(0, sz.y, 0), Vector3(0, 0, sz.z), Vector3.LEFT, col.darkened(0.08))
	_quad(v, n, c, o + Vector3(0, sz.y, 0), Vector3(sz.x, 0, 0), Vector3(0, 0, sz.z), Vector3.UP, col)
	_quad(v, n, c, o, Vector3(0, 0, sz.z), Vector3(sz.x, 0, 0), Vector3.DOWN, col.darkened(0.3))
	_quad(v, n, c, o + Vector3(0, 0, sz.z), Vector3(0, sz.y, 0), Vector3(sz.x, 0, 0), Vector3.BACK, col.darkened(0.04))
	_quad(v, n, c, o, Vector3(sz.x, 0, 0), Vector3(0, sz.y, 0), Vector3.FORWARD, col.darkened(0.12))


## Cheap deterministic hash in [0, 1].
func _hash(x: int, y: int, z: int) -> float:
	var h := (x * 73856093) ^ (y * 19349663) ^ (z * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	return float((h >> 8) & 0xFFFF) / 65535.0
