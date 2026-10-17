extends Node3D
## The nine baskets of a glacial world, sited from the world seed, and the
## course they make (course.gd: playing order and a tee pad for each).
##
## terrain.gd builds this after the flora (so baskets can steer clear of
## trees), and throws it away with everything else on a new world. The
## distance course gets none.
##
## Siting is dart throwing: shuffle a few hundred candidate spots, keep each
## one that is a good place for a basket and at least `spacing` metres from
## every basket kept so far. If nine won't fit at that spacing, ease it off a
## little and try again. That spreads them across the whole world without
## the stiff grid look, and the same seed always gives the same nine.
##
## A good place: on the playable ground (off the moraine), clear of the
## spawn, out of lakes and off their shores, on fairly level ground, and
## with no tree trunk, branch or leaf in the space the basket stands in.

const BASKET_SCRIPT := preload("res://scripts/basket.gd")
const FLORA := preload("res://scripts/flora.gd")
const Course := preload("res://scripts/course.gd")

@export var count := 9
@export var spacing := 65.0            ## Wanted gap between baskets (m).
@export var spacing_min := 18.0        ## ...but never squeeze them closer than this.
@export var candidates := 700
@export var spawn_clear := 25.0        ## Keep this far from where you start (m).
@export var lake_clear := 4.0          ## ...and this far from any lake's edge.
@export var edge_clear := 8.0          ## ...and this far in from the moraine.
@export var max_slope := 0.5           ## Ground rise (m) allowed across 2 m.

var terrain: Node3D
var baskets: Array = []                ## basket.gd nodes, in hole order.
var holes: Array[Dictionary] = []      ## The course: course.gd plan() + "basket" (the node).
var spacing_used := 0.0                ## The spacing the nine actually fitted at.


func build(t: Node3D) -> void:
	terrain = t
	for b in baskets:
		if is_instance_valid(b):
			b.queue_free()
	baskets.clear()
	# The course (course.gd) puts them in playing order and finds each a tee;
	# Basket<n> is hole n.
	holes = Course.plan(terrain, pick_sites())
	for h in holes:
		var b := Node3D.new()
		b.set_script(BASKET_SCRIPT)
		b.name = "Basket%d" % h.n
		b.terrain = terrain
		add_child(b)
		b.place(h.basket_at)
		baskets.append(b)
		h.basket = b


## Where the baskets go (m, on the ground). Deterministic for a given seed.
func pick_sites() -> Array[Vector3]:
	var out: Array[Vector3] = []
	if terrain == null or terrain.world_kind != "glacial" or count <= 0:
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([terrain.world_seed, "baskets"])
	var lo: float = terrain.moraine_width + edge_clear
	var pts: Array[Vector2] = []
	for i in candidates:
		var p := Vector2(rng.randf_range(lo, terrain.world_x - lo),
			rng.randf_range(lo, terrain.world_z - lo))
		if good_spot(p):
			pts.append(p)
	var gap := spacing
	while gap >= spacing_min:
		var kept: Array[Vector2] = []
		for p in pts:
			var ok := true
			for q in kept:
				if p.distance_to(q) < gap:
					ok = false
					break
			if ok:
				kept.append(p)
				if kept.size() == count:
					break
		if kept.size() == count or gap * 0.9 < spacing_min:
			spacing_used = gap
			for p in kept:
				out.append(Vector3(p.x, terrain.height_at(p.x, p.y), p.y))
			return out
		gap *= 0.9
	return out


## True if a basket could stand at world point p (m).
func good_spot(p: Vector2) -> bool:
	var spawn: Vector3 = terrain.spawn_point()
	if p.distance_to(Vector2(spawn.x, spawn.z)) < spawn_clear:
		return false
	if terrain.lake_edge_distance(p.x, p.y) < lake_clear:
		return false
	var bs: float = terrain.block_size
	var ix: int = terrain.col_x(p.x)
	var iz: int = terrain.col_z(p.y)
	if terrain.is_shore(ix, iz) or terrain.is_underwater(ix, iz):
		return false
	# Fairly level: the ground within 1 m stays within max_slope of the middle.
	var h0: float = terrain.height_at(p.x, p.y)
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		if absf(terrain.height_at(p.x + d.x, p.y + d.y) - h0) > max_slope:
			return false
	# Nothing of a tree inside the basket's space (0.5 m around, 1.6 m up),
	# and not hard against a trunk.
	var flora: Node3D = terrain.flora
	if flora == null:
		return true
	for tree: Dictionary in flora.trees:
		var tp := Vector2((tree.pos.x + 0.5) * bs, (tree.pos.y + 0.5) * bs)
		if tp.distance_to(p) < 2.5:
			return false
	var r := int(ceil(0.5 / bs))
	var y0 := int(floor(h0 / bs))
	var y1 := int(ceil((h0 + 1.6) / bs))
	for y in range(y0, y1 + 1):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if flora.voxel_at(Vector3i(ix + dx, y, iz + dz)) != 0:
					return false
	return true
