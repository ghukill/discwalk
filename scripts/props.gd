extends Node3D
## Course furniture: the benches by the tees and the pro shop by the first.
##
## Built from voxels like everything else, by the same trick basket.gd uses --
## a dictionary of cell -> colour, then only the faces with nothing next to
## them -- but at their own voxel size. A bench's slats need 5 cm cells; a
## 11 m building at 5 cm would be a quarter of a million of them, so it gets
## 25 cm. Each kind's mesh is built once and shared by every instance.
##
## Placed from course.json:
##
##   "props": [
##     {"kind": "clubhouse", "at": [150, 398], "yaw": 180},
##     {"kind": "bench", "at": [168, 372], "yaw": 20, "color": "teal"}
##   ]
##
## `at` is [x, z] in course metres, `yaw` degrees clockwise from facing -Z.
## They sit on the ground wherever that is, so they follow the terrain.

const VOXEL := {"bench": 0.05, "clubhouse": 0.25}

# Bench: a 6 ft park bench, slatted seat and back on a dark frame.
const BENCH_LEN := 1.83
const BENCH_DEEP := 0.62
const SEAT_Y := 0.45
const BACK_Y := 0.92
const COLOR_BENCH := {
	"teal": Color(0.16, 0.60, 0.58),
	"white": Color(0.86, 0.87, 0.84),
}
const COLOR_FRAME := Color(0.16, 0.18, 0.18)

# Clubhouse: a low stuccoed shed with a shallow gable and deep eaves, a
# counter across the front and a black shade sail stretched out over it.
const SHOP_W := 11.0
const SHOP_D := 8.0
const SHOP_EAVE := 2.8
const SHOP_RIDGE := 4.6
const COLOR_WALL := Color(0.78, 0.74, 0.64)      ## Tan stucco.
const COLOR_ROOF := Color(0.29, 0.26, 0.24)      ## Dark shingle.
const COLOR_TRIM := Color(0.62, 0.57, 0.48)
const COLOR_COUNTER := Color(0.45, 0.33, 0.21)   ## The wooden serving counter.
const COLOR_SHADE := Color(0.11, 0.11, 0.12)     ## The shade sail.
const COLOR_DARK := Color(0.08, 0.09, 0.10)      ## Inside, seen through the front.

static var _meshes := {}                         ## "kind|variant" -> ArrayMesh

var terrain: Node3D


## Build every prop a course asks for. `props` is course.foliage-style data
## from course_file.gd: [{kind, at: Vector2, yaw, color}].
func build(course_props: Array) -> void:
	for p: Dictionary in course_props:
		var kind: String = p.kind
		if not VOXEL.has(kind):
			continue
		var node := make(kind, p.get("color", "teal"))
		if node == null:
			continue
		# course metres -> world metres: a layout builds only the part of the
		# course its holes need, so the two differ by terrain.course_origin.
		var at: Vector2 = terrain.to_world(p.at)
		node.position = Vector3(at.x, terrain.height_at(at.x, at.y), at.y)
		node.rotation.y = deg_to_rad(float(p.get("yaw", 0.0)))
		add_child(node)


## One prop: its mesh (shared) and a collider or two, so discs bounce off it.
func make(kind: String, variant := "teal") -> Node3D:
	var key := "%s|%s" % [kind, variant]
	if not _meshes.has(key):
		var cells: Dictionary = _cells_bench(variant) if kind == "bench" else _cells_clubhouse()
		_meshes[key] = _mesh(cells, VOXEL[kind])
	var root := Node3D.new()
	root.name = kind.capitalize()
	# The cells are built from a corner, but a prop should stand ON the point
	# the course names, so everything is shifted back by half its footprint.
	var off := _centre(kind)
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[key]
	mi.position = off
	root.add_child(mi)
	for box in (_hit_bench() if kind == "bench" else _hit_clubhouse()):
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = box[1]
		cs.shape = shape
		cs.position = box[0] + off
		body.add_child(cs)
		root.add_child(body)
	return root


## Half the footprint, so `at` is the middle of the prop and not a corner.
static func _centre(kind: String) -> Vector3:
	if kind == "bench":
		return Vector3(-BENCH_LEN * 0.5, 0.0, -BENCH_DEEP * 0.5)
	return Vector3(-SHOP_W * 0.5, 0.0, -SHOP_D * 0.5)


## Only the faces with nothing next to them, same as the basket.
static func _mesh(cells: Dictionary, voxel: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dirs := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
		Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
	for k: Vector3i in cells:
		var col: Color = cells[k]
		var centre := (Vector3(k) + Vector3.ONE * 0.5) * voxel
		for d: Vector3i in dirs:
			if cells.has(k + d):
				continue
			_face(st, centre, Vector3(d), col, voxel)
	st.generate_normals()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	st.set_material(m)
	return st.commit()


static func _face(st: SurfaceTool, centre: Vector3, n: Vector3, col: Color, voxel: float) -> void:
	var u := Vector3(n.y, n.z, n.x)
	var v := n.cross(u)
	var h := voxel * 0.5
	var c := centre + n * h
	var quad := [c - u * h - v * h, c + u * h - v * h, c + u * h + v * h, c - u * h + v * h]
	st.set_color(col)
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_normal(n)
		st.add_vertex(quad[i])


## x runs along the bench, z across it, y up; the origin is a back corner.
static func _cells_bench(variant: String) -> Dictionary:
	var c := {}
	var paint: Color = COLOR_BENCH.get(variant, COLOR_BENCH.teal)
	var vx: float = VOXEL.bench
	var nx := int(BENCH_LEN / vx)
	var seat := int(SEAT_Y / vx)
	# Seat: three slats across the depth, with a gap between each.
	var slats := [[1, 3], [5, 7], [9, 11]]
	for s in slats:
		for z in range(s[0], s[1]):
			for x in range(nx):
				c[Vector3i(x, seat, z)] = paint
	# Back: four slats, leaning back a little as they rise.
	var back := [[0, 2], [3, 5], [6, 8]]
	var bz := int(BENCH_DEEP / vx) - 1
	for i in back.size():
		var s: Array = back[i]
		for y in range(s[0], s[1]):
			var yy := seat + 3 + y
			for x in range(nx):
				c[Vector3i(x, yy, bz - int(y / 4))] = paint
	# Frame: legs, arms and the bar under the seat, at both ends.
	for ex in [0, nx - 1]:
		for y in range(0, seat):
			c[Vector3i(ex, y, 2)] = COLOR_FRAME
			c[Vector3i(ex, y, bz - 2)] = COLOR_FRAME
		for z in range(1, bz):
			c[Vector3i(ex, seat - 1, z)] = COLOR_FRAME
		# Arm rest, from the back down to the front of the seat.
		for z in range(2, bz):
			c[Vector3i(ex, seat + 5, z)] = COLOR_FRAME
		for y in range(seat, seat + 5):
			c[Vector3i(ex, y, 3)] = COLOR_FRAME
	return c


## The pro shop. x across the front, z back into the building.
static func _cells_clubhouse() -> Dictionary:
	var c := {}
	var vx: float = VOXEL.clubhouse
	var nx := int(SHOP_W / vx)
	var nz := int(SHOP_D / vx)
	var eave := int(SHOP_EAVE / vx)
	var ridge := int(SHOP_RIDGE / vx)
	# Walls: a hollow box, open across the middle of the front (the counter).
	var door_lo := int(nx * 0.22)
	var door_hi := int(nx * 0.78)
	for y in range(0, eave):
		for x in range(nx):
			for z in range(nz):
				var edge: bool = x == 0 or x == nx - 1 or z == 0 or z == nz - 1
				if not edge:
					continue
				# The front wall is open above the counter, between the posts.
				if z == 0 and x > door_lo and x < door_hi and y > int(1.1 / vx):
					c[Vector3i(x, y, z)] = COLOR_DARK
					continue
				c[Vector3i(x, y, z)] = COLOR_WALL
	# The wooden counter across that opening.
	for x in range(door_lo, door_hi + 1):
		for y in range(int(0.8 / vx), int(1.1 / vx)):
			c[Vector3i(x, y, 0)] = COLOR_COUNTER
	# Gable roof: the ridge runs across the front (x), so the gable faces you.
	var over := int(0.6 / vx)                    # eaves overhang this far
	for z in range(-over, nz + over):
		for x in range(-over, nx + over):
			# Height falls from the ridge in the middle of z to the eaves.
			var t := absf(float(z) - (nz - 1) * 0.5) / maxf((nz - 1) * 0.5, 1.0)
			var y := int(round(lerpf(float(ridge), float(eave), minf(t, 1.0))))
			c[Vector3i(x, y, z)] = COLOR_ROOF
			c[Vector3i(x, y - 1, z)] = COLOR_TRIM if (z < 0 or z >= nz) else COLOR_ROOF
			# Fill the gable ends in under the slope so it is not see-through.
			if x == 0 or x == nx - 1:
				for yy in range(eave, y):
					c[Vector3i(x, yy, z)] = COLOR_WALL
	# The shade sail: a flat dark panel out over the front, on two posts.
	var sail := int(2.6 / vx)
	for z in range(-int(4.0 / vx), 0):
		for x in range(door_lo - 2, door_hi + 3):
			c[Vector3i(x, sail, z)] = COLOR_SHADE
	for px in [door_lo - 2, door_hi + 2]:
		for y in range(0, sail):
			c[Vector3i(px, y, -int(4.0 / vx) + 1)] = COLOR_FRAME
	return c


## Colliders, as a few boxes rather than per voxel: [centre, size].
static func _hit_bench() -> Array:
	return [[Vector3(BENCH_LEN * 0.5, SEAT_Y * 0.5, BENCH_DEEP * 0.5),
			Vector3(BENCH_LEN, SEAT_Y + 0.1, BENCH_DEEP)],
		[Vector3(BENCH_LEN * 0.5, (SEAT_Y + BACK_Y) * 0.5, BENCH_DEEP - 0.1),
			Vector3(BENCH_LEN, BACK_Y - SEAT_Y, 0.2)]]


static func _hit_clubhouse() -> Array:
	return [[Vector3(SHOP_W * 0.5, SHOP_RIDGE * 0.5, SHOP_D * 0.5),
		Vector3(SHOP_W, SHOP_RIDGE, SHOP_D)]]
