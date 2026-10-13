extends RefCounted
## The distance course (`-- --world=distance`): a dead-flat field for
## measuring throws. A tee pad sits in the middle of the south (high z) edge,
## facing north (-z). Chalk arcs every 10 m spread out from the front of the
## tee, with bolder yellow arcs and big painted numbers every 50 m, and a
## centre line straight down the field.
##
## All the markings are just ground voxel colours (terrain top kinds), so they
## snap to the block grid: chunky at 1 m blocks, finer at 0.25 m.

const WORLD_X := 192.0          ## Field width (m); whole 32 m chunks.
const WORLD_Z := 288.0          ## Field length (m).
const GROUND := 4.0             ## Ground height (m).
const TEE_BACK := 10.0          ## Front of the tee, measured from the south edge (m).
const TEE_SIZE := Vector2(1.5, 3.0)   ## Tee pad width x length (m), behind its front edge.
const ARC_STEP := 10.0          ## Minor arcs (m).
const MAJOR_STEP := 50.0        ## Major arcs + numbers (m).
const LINE_W := 0.3             ## Minor line width (m); never thinner than a block.
const MAJOR_W := 0.6            ## Major line width (m).
const NUMBER_PIXEL := 1.5       ## One pixel of the painted numbers (m).
const NUMBER_OFFSET := 22.0     ## Numbers sit this far either side of the centre line (m).

## Paint = terrain top kinds (see terrain.gd _top_color).
const CHALK := 3
const YELLOW := 4
const TEE := 5

## 3x5 pixel digits, rows top to bottom.
const DIGITS := [
	"111101101101111", "010110010010111", "111001111100111", "111001111001111",
	"101101111001001", "111100111001111", "111100111101111", "111001001001001",
	"111101111101111", "111101111001111",
]


## Front-centre of the tee (m, x / z). Distances are measured from here.
## x sits on a column centre, so the centre line is always painted.
static func tee(t: Node3D) -> Vector2:
	return Vector2((t.col_x(t.world_x / 2.0) + 0.5) * t.block_size, t.world_z - TEE_BACK)


## Where the walker starts (m): on the tee pad, a metre above the ground.
static func spawn(t: Node3D) -> Vector3:
	var p := tee(t) + Vector2(0.0, TEE_SIZE.y * 0.5)
	return Vector3(p.x, t.height_at(p.x, p.y) + 1.0, p.y)


## Flat height field (metres per column).
static func heights(t: Node3D) -> PackedFloat32Array:
	var hf := PackedFloat32Array()
	hf.resize(t.size_x * t.size_z)
	hf.fill(GROUND)
	return hf


## Paint kind per column (0 = plain grass).
static func paint(t: Node3D) -> PackedByteArray:
	var sx: int = t.size_x
	var sz: int = t.size_z
	var bs: float = t.block_size
	var out := PackedByteArray()
	out.resize(sx * sz)
	out.fill(0)
	var o := tee(t)
	var minor := maxf(LINE_W, bs) / 2.0
	var major := maxf(MAJOR_W, bs) / 2.0

	for iz in sz:
		var mz := (iz + 0.5) * bs
		if mz > o.y:
			continue
		for ix in sx:
			var mx := (ix + 0.5) * bs
			var kind := 0
			if absf(mx - o.x) < minor:
				kind = CHALK
			var d := Vector2(mx, mz).distance_to(o)
			var r := roundf(d / ARC_STEP) * ARC_STEP
			if r > 0.0:
				var is_major := is_zero_approx(fmod(r, MAJOR_STEP))
				if absf(d - r) < (major if is_major else minor):
					kind = YELLOW if is_major else CHALK
			if kind:
				out[iz * sx + ix] = kind

	# Numbers on each major arc, either side of the centre line, just past it.
	var r := MAJOR_STEP
	while r < o.y:
		for side in [-1.0, 1.0]:
			var dx: float = side * NUMBER_OFFSET
			if r > NUMBER_OFFSET + 2.0:
				var arc_z := o.y - sqrt(r * r - dx * dx)
				_number(out, t, str(int(r)), Vector2(o.x + dx, arc_z - 2.0))
		r += MAJOR_STEP

	# Tee pad last, so nothing paints over it.
	_rect(out, t, Rect2(o.x - TEE_SIZE.x / 2.0, o.y, TEE_SIZE.x, TEE_SIZE.y), TEE)
	return out


## Paints `text` in yellow, centred on x, its bottom (south) edge at z.
## Reads from the tee: the top of each digit points north.
static func _number(out: PackedByteArray, t: Node3D, text: String, at: Vector2) -> void:
	var px := NUMBER_PIXEL
	var w := (text.length() * 4 - 1) * px
	var x0 := at.x - w / 2.0
	var z0 := at.y - 5.0 * px
	for i in text.length():
		var glyph: String = DIGITS[text.unicode_at(i) - 48]
		for row in 5:
			for col in 3:
				if glyph[row * 3 + col] == "1":
					_rect(out, t, Rect2(x0 + (i * 4 + col) * px, z0 + row * px, px, px), YELLOW)


## Paints every column whose centre falls inside `r` (metres).
static func _rect(out: PackedByteArray, t: Node3D, r: Rect2, kind: int) -> void:
	var bs: float = t.block_size
	for iz in range(maxi(0, floori(r.position.y / bs)), mini(t.size_z, ceili(r.end.y / bs))):
		for ix in range(maxi(0, floori(r.position.x / bs)), mini(t.size_x, ceili(r.end.x / bs))):
			if r.has_point(Vector2((ix + 0.5) * bs, (iz + 0.5) * bs)):
				out[iz * t.size_x + ix] = kind
