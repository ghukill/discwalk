extends RefCounted
## Lays a course out over a glacial world's baskets: which order to play
## them in, and a tee pad for each one. baskets.gd sites the baskets, then
## calls plan(); terrain.gd paints the tees (paint()) before it meshes the
## ground, so the pads are just coloured voxel tops, like the distance
## course's markings.
##
## Order: nearest neighbour from the spawn, so each hole starts near where
## the last one ended and you never trek across the whole map.
##
## Tees: for each basket, look back toward where you're coming from (the last
## basket, or the spawn for hole 1) and walk out a hole's length. If that
## spot is no good (water, a slope, a tree, too close to another basket),
## swing the bearing a little either way and try shorter or longer, until
## something fits. The tee faces the basket, give or take a random few
## degrees, so the basket isn't always dead ahead.
##
## A painted pad has to follow the block grid, so it is drawn turned to the
## nearest of 8 compass directions (diagonals stair-step, which reads fine).
## The way you face on the tee is still the exact angle.

const TEE_SIZE := Vector2(1.5, 3.0)    ## Pad width x length (m).
const LENGTH := Vector2(40.0, 150.0)   ## Hole length range, tee front to basket (m).
const AIM_JITTER := 25.0               ## Tee facing: up to this far off the basket (deg).
const BASKET_CLEAR := 6.0              ## Tee pad keeps this far from every basket (m).
const TEE_CLEAR := 12.0                ## ...and from every other tee.
const EDGE_CLEAR := 6.0                ## ...and in from the moraine.
const LAKE_CLEAR := 3.0                ## ...and from any lake edge.
const MAX_RISE := 0.6                  ## Ground rise allowed across the pad (m).
const HEADROOM := 2.6                  ## No tree voxels this high over the pad (m).
const FAIRWAY := 15.0                  ## Off the tee, this far is clear of trees (m)...
const FAIRWAY_W := 1.5                 ## ...this wide either side of the line.
const NUMBER_PIXEL := 0.25             ## One pixel of the painted hole number (m).

## Paint kinds (terrain.gd _top_color).
const PAINT_NUMBER := 4
const PAINT_TEE := 5

## 3x5 pixel digits, rows top to bottom (same as distance_course.gd).
const DIGITS := [
	"111101101101111", "010110010010111", "111001111100111", "111001111001111",
	"101101111001001", "111100111001111", "111100111101111", "111001001001001",
	"111101111101111", "111101111001111",
]


## Turns basket sites into holes, in playing order:
## [{n, basket_at: Vector3, tee: Vector3 (pad centre, on the ground),
##   yaw: facing on the tee (rad, 0 = -z), pad_yaw: yaw snapped to 45°,
##   length: tee front to basket (m)}]. A basket no tee fits is left out.
static func plan(t: Node3D, sites: Array[Vector3]) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([t.world_seed, "course"])
	var spawn: Vector3 = t.spawn_point()
	var from := Vector2(spawn.x, spawn.z)
	var left: Array[Vector3] = sites.duplicate()
	var holes: Array[Dictionary] = []
	while not left.is_empty():
		var best := 0
		for i in left.size():
			if _flat(left[i]).distance_to(from) < _flat(left[best]).distance_to(from):
				best = i
		var b: Vector3 = left.pop_at(best)
		var hole := _tee_for(t, rng, _flat(b), from, sites, holes)
		if hole.is_empty():
			continue                   # no room for a tee: drop the basket
		hole.n = holes.size() + 1
		hole.basket_at = b
		holes.append(hole)
		from = _flat(b)
	return holes


static func _tee_for(t: Node3D, rng: RandomNumberGenerator, b: Vector2, from: Vector2,
		sites: Array[Vector3], holes: Array[Dictionary]) -> Dictionary:
	var back := from - b
	var gap := back.length()
	back = back.normalized() if gap > 1.0 else Vector2(0, 1)
	# A hole's length, but not (much) past where you're coming from.
	var want := rng.randf_range(LENGTH.x, LENGTH.y)
	want = clampf(minf(want, gap - 8.0), LENGTH.x, LENGTH.y)
	var jitter := deg_to_rad(rng.randf_range(-AIM_JITTER, AIM_JITTER))
	for swing in [0, 15, -15, 30, -30, 45, -45, 60, -60, 90, -90, 120, -120, 150, -150, 180]:
		for dl in [0.0, -10.0, 10.0, -20.0, 20.0, -30.0, 30.0, 45.0, 60.0]:
			var length: float = clampf(want + dl, LENGTH.x, LENGTH.y)
			var dir := back.rotated(deg_to_rad(swing))
			# `length` is to the pad's front edge; the centre is half a pad back.
			var c := b + dir * (length + TEE_SIZE.y * 0.5)
			var to_b := b - c
			var yaw := atan2(-to_b.x, -to_b.y) + jitter
			var pad_yaw := snappedf(yaw, PI / 4.0)
			if _tee_ok(t, c, pad_yaw, sites, holes):
				return {"tee": Vector3(c.x, t.height_at(c.x, c.y), c.y), "yaw": yaw,
					"pad_yaw": pad_yaw, "length": length}
	return {}


## True if a pad centred on c (m), turned to pad_yaw, can go here.
static func _tee_ok(t: Node3D, c: Vector2, pad_yaw: float, sites: Array[Vector3],
		holes: Array[Dictionary]) -> bool:
	var lo: float = t.moraine_width + EDGE_CLEAR
	if c.x < lo or c.y < lo or c.x > t.world_x - lo or c.y > t.world_z - lo:
		return false
	for s in sites:
		if _flat(s).distance_to(c) < BASKET_CLEAR:
			return false
	for h in holes:
		if _flat(h.tee).distance_to(c) < TEE_CLEAR:
			return false
	# Corners, edge midpoints and centre: dry, off the shore, fairly level.
	var fwd := _fwd(pad_yaw)
	var right := Vector2(-fwd.y, fwd.x)
	var hw := TEE_SIZE.x * 0.5 + 0.25
	var hl := TEE_SIZE.y * 0.5 + 0.25
	var lo_h := 1e9
	var hi_h := -1e9
	for u in [-hw, 0.0, hw]:
		for v in [-hl, 0.0, hl]:
			var p: Vector2 = c + right * u + fwd * v
			if t.lake_edge_distance(p.x, p.y) < LAKE_CLEAR:
				return false
			var ix: int = t.col_x(p.x)
			var iz: int = t.col_z(p.y)
			if t.is_shore(ix, iz):
				return false
			var h: float = t.height_at(p.x, p.y)
			lo_h = minf(lo_h, h)
			hi_h = maxf(hi_h, h)
	if hi_h - lo_h > MAX_RISE:
		return false
	# Trees: not hard against a trunk, and nothing overhead.
	var flora: Node3D = t.flora
	if flora == null:
		return true
	var bs: float = t.block_size
	for tree: Dictionary in flora.trees:
		var tp := Vector2((tree.pos.x + 0.5) * bs, (tree.pos.y + 0.5) * bs)
		if tp.distance_to(c) < 3.0:
			return false
	var y0 := int(floor(lo_h / bs))
	var y1 := int(ceil((hi_h + HEADROOM) / bs))
	var r := int(ceil((hl + 0.25) / bs))
	var cx: int = t.col_x(c.x)
	var cz: int = t.col_z(c.y)
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			for y in range(y0, y1 + 1, 2):
				if flora.voxel_at(Vector3i(cx + dx, y, cz + dz)) != 0:
					return false
	# A clear start down the fairway: no leaves or bark at throwing height
	# for the first stretch toward the basket.
	var front := c + fwd * TEE_SIZE.y * 0.5
	var s := 1.0
	while s <= FAIRWAY:
		for w in [-FAIRWAY_W, 0.0, FAIRWAY_W]:
			var p: Vector2 = front + fwd * s + right * w
			var g: float = t.height_at(p.x, p.y)
			for up in [0.8, 1.6, 2.4, 3.2]:
				if flora.voxel_at(Vector3i(t.col_x(p.x), int(floor((g + up) / bs)), t.col_z(p.y))) != 0:
					return false
		s += 1.0
	return true


## Paints every hole's tee pad, and its number beside the pad (reading from
## the tee), into `out` (one paint kind per column).
static func paint(t: Node3D, out: PackedByteArray, holes: Array) -> void:
	for h: Dictionary in holes:
		var c := _flat(h.tee)
		var fwd := _fwd(h.pad_yaw)
		var pad := func(_u: float, _v: float) -> int: return PAINT_TEE
		_paint_local(t, out, c, fwd, Rect2(-TEE_SIZE.x * 0.5, -TEE_SIZE.y * 0.5, TEE_SIZE.x, TEE_SIZE.y), pad)
		# The number: on the right of the pad, its top toward the basket. It
		# sits square to the grid (the nearest 90°): turned 45° it's mush.
		fwd = _fwd(snappedf(h.pad_yaw, PI / 2.0))
		var text := str(h.n)
		var px := maxf(NUMBER_PIXEL, t.block_size)
		var w := (text.length() * 4 - 1) * px
		var u0 := TEE_SIZE.x * 0.5 + maxf(0.5, px)
		var v_top := TEE_SIZE.y * 0.5
		var r := Rect2(u0, v_top - 5.0 * px, w, 5.0 * px)
		var digit := func(u: float, v: float) -> int:
			var col := int((u - u0) / px)
			var row := int((v_top - v) / px)
			if col % 4 == 3 or row < 0 or row > 4:
				return 0
			var glyph: String = DIGITS[text.unicode_at(int(col / 4.0)) - 48]
			return PAINT_NUMBER if glyph[row * 3 + col % 4] == "1" else 0
		_paint_local(t, out, c, fwd, r, digit)


## Paints the columns whose centres fall in `r`, a rect in pad space (u to
## the right, v forward, metres from c), with whatever kind(u, v) says.
static func _paint_local(t: Node3D, out: PackedByteArray, c: Vector2, fwd: Vector2, r: Rect2,
		kind: Callable) -> void:
	var right := Vector2(-fwd.y, fwd.x)
	var bs: float = t.block_size
	var reach := maxf(r.position.length(), r.end.length())
	reach = maxf(reach, maxf(Vector2(r.position.x, r.end.y).length(), Vector2(r.end.x, r.position.y).length()))
	for iz in range(maxi(0, floori((c.y - reach) / bs)), mini(t.size_z, ceili((c.y + reach) / bs))):
		for ix in range(maxi(0, floori((c.x - reach) / bs)), mini(t.size_x, ceili((c.x + reach) / bs))):
			var d := Vector2((ix + 0.5) * bs, (iz + 0.5) * bs) - c
			var u := d.dot(right)
			var v := d.dot(fwd)
			if u >= r.position.x and u < r.end.x and v >= r.position.y and v < r.end.y:
				var k: int = kind.call(u, v)
				if k:
					out[iz * t.size_x + ix] = k


## Waypoints for walking from -> to (m): round any lake the straight line
## would cross. Course Play's walk to the next tee, and goto's walk to your
## disc (thrower.gd).
static func route(t: Node3D, from: Vector3, to: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var a := Vector2(from.x, from.z)
	var b := Vector2(to.x, to.z)
	var lakes: Array = t.lakes.duplicate()
	var nearer := func(l1, l2): return a.distance_to(l1.center) < a.distance_to(l2.center)
	lakes.sort_custom(nearer)
	for lake in lakes:
		var c: Vector2 = lake.center
		var r: float = lake.radius + 4.0
		var q := Geometry2D.get_closest_point_to_segment(c, a, b)
		if q.distance_to(c) >= r:
			continue
		var side := q - c
		if side.length() < 0.1:
			side = (b - a).orthogonal()
		var w := c + side.normalized() * r
		out.append(Vector3(w.x, t.height_at(w.x, w.y), w.y))
		a = w
	return out


## Flat forward (x, z) for a yaw (0 = -z, like a Node3D's rotation.y).
static func _fwd(yaw: float) -> Vector2:
	return Vector2(-sin(yaw), -cos(yaw))


static func _flat(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)
