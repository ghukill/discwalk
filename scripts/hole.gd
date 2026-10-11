extends Node
## One playable hole: a tee, a basket, and a stroke count.
##
## This script knows the rules and nothing about physics. basket.gd knows
## about chains and nothing about strokes. Delete this file and you still
## have a basket to throw at.
##
## Rules, deliberately minimal (docs/superpowers/specs/2026-10-11-baskets-design.md):
## - every disc throw while the hole is unfinished is one stroke
## - cube throws (right click) count for nothing
## - no penalties, no out of bounds: a disc in a lake is just a bad lie
## - holing out completes the hole; later throws do not count
##
## Known and accepted: nothing stops you walking up to the basket and
## dropping a disc in for a 1. Enforcing a tee throw is rule surface this
## version does not want.

signal holed_out(strokes)

const DIST_MIN := 60.0            ## Tee to basket, metres.
const DIST_MAX := 120.0
const TRUNK_CLEAR := 2.0          ## Keep the basket this far off a trunk.
const CANDIDATES := 400

var strokes := 0
var complete := false
var tee := Vector3.ZERO
var basket: Node3D


## Pick a basket spot for `terrain` from its seed. Always returns somewhere:
## a world with a mediocre hole beats a world with none.
static func site(terrain: Node3D) -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(terrain.world_seed * 104729 + 31)
	var tee_at: Vector3 = terrain.spawn_point()
	var edge: float = terrain.moraine_width + 8.0
	var best := Vector3.ZERO
	var best_score := -1e9
	for i in CANDIDATES:
		var a := rng.randf() * TAU
		var d := rng.randf_range(DIST_MIN, DIST_MAX)
		var x := tee_at.x + cos(a) * d
		var z := tee_at.z + sin(a) * d
		if x < edge or z < edge \
				or x > terrain.world_size - edge or z > terrain.world_size - edge:
			continue
		var score := _score(terrain, x, z, tee_at, d)
		if score > best_score:
			best_score = score
			best = Vector3(x, terrain.height_at(x, z), z)
	if best_score <= -1e8:
		# Nothing passed. Take the least bad spot straight up the middle.
		var fx: float = clampf(tee_at.x, edge, terrain.world_size - edge)
		var fz: float = clampf(tee_at.z - 70.0, edge, terrain.world_size - edge)
		return Vector3(fx, terrain.height_at(fx, fz), fz)
	return best


## Higher is better; -1e9 means illegal.
static func _score(terrain: Node3D, x: float, z: float, tee_at: Vector3,
		d: float) -> float:
	var ix: int = terrain.col_of(x)
	var iz: int = terrain.col_of(z)
	if terrain.is_underwater(ix, iz) or terrain.is_shore(ix, iz):
		return -1e9
	if terrain.lake_edge_distance(x, z) < 2.0:
		return -1e9
	# Flat enough to stand a basket on: no more than one block of fall to any
	# of the four neighbouring columns.
	var h: int = terrain.col_height(ix, iz)
	for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if absi(terrain.col_height(ix + o.x, iz + o.y) - h) > 1:
			return -1e9
	var bs: float = terrain.block_size
	var oaks := 0
	for tr: Dictionary in terrain.flora.trees:
		var tx: float = (tr.pos.x + 0.5) * bs
		var tz: float = (tr.pos.y + 0.5) * bs
		var gap := Vector2(tx - x, tz - z).length()
		if gap < TRUNK_CLEAR + tr.crown * 0.25:
			return -1e9               # basket inside a trunk or its skirt
		# Oaks roughly between tee and basket make the shot interesting.
		if gap < d and Vector2(tx - tee_at.x, tz - tee_at.z).length() < d:
			oaks += 1
	# Prefer mid-range distance, and a handful of oaks in the way.
	var mid := 1.0 - absf(d - (DIST_MIN + DIST_MAX) * 0.5) / ((DIST_MAX - DIST_MIN) * 0.5)
	return mid * 10.0 + minf(oaks, 12) * 1.5


## Begin a hole: tee here, basket there, nothing scored yet.
func start(tee_at: Vector3, basket_at: Vector3) -> void:
	tee = tee_at
	strokes = 0
	complete = false
	if basket != null:
		basket.release()
		basket.place(basket_at)


func count_stroke() -> void:
	if complete:
		return
	strokes += 1


func distance_from(p: Vector3) -> float:
	if basket == null:
		return 0.0
	return Vector2(p.x - basket.global_position.x, p.z - basket.global_position.z).length()
