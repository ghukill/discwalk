extends SceneTree
## Headless basket check: the nine baskets, where they stand, the chain model,
## and what a hit does (that disc rolls home, confetti flies, then clears).
##
##   godot --headless --path . --script res://tools/basket_test.gd [-- --block-size=1]

const Basket := preload("res://scripts/basket.gd")
const DISC_MASS := 0.175             ## disc.gd sets this on every thrown disc.

var _main: Node
var _frames := 0
var _ok := true
var _ran := {}                       ## Test functions that reached their end.

## Every test that must run to completion. A GDScript error aborts only the
## function it happens in, so without this a broken test would skip all its
## checks and the run would still report PASS.
const MUST_RUN := ["geometry", "siting", "chains", "hit_collider", "hit_chains", "confetti"]

# The live hit tests run across frames, timed in real seconds (headless runs
# frames as fast as it can, so frame counts aren't time).
var _stage := 0
var _t0 := 0
var _cube: Node
var _flyer: Node
var _other: Node
var _target: Node3D
var _hits := []                      ## [disc, basket, part] from thrower-side signals.


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 5:
		return false
	if _stage == 0:
		_test_geometry()
		_test_siting()
		_test_chains()
		_start_hits()
		_stage = 1
		_t0 = Time.get_ticks_msec()
		return false
	if _stage == 1:
		if Time.get_ticks_msec() - _t0 < 2000:
			return false
		_check_hits()
		_stage = 2
		_t0 = Time.get_ticks_msec()
		return false
	if _stage == 2:
		var left := _confetti_left()
		if left > 0 and Time.get_ticks_msec() - _t0 < 20000:
			return false
		_check("confetti clears itself", left == 0,
			"%d bursts left after %.1f s" % [left, (Time.get_ticks_msec() - _t0) / 1000.0])
		_done("confetti")
	for name: String in MUST_RUN:
		if not _ran.has(name):
			print("BASKET %-26s BAD  (aborted before finishing)" % name)
			_ok = false
	print("BASKET " + ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)
	return true


func _check(name: String, cond: bool, detail := "") -> void:
	print("BASKET %-26s %s%s" % [name, "ok" if cond else "BAD",
		("  " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _done(name: String) -> void:
	_ran[name] = true


## Nine baskets, each standing on the ground, regulation-ish and voxel-built.
func _test_geometry() -> void:
	var t = _main.get_node("Terrain")
	_check("nine baskets", t.baskets.size() == 9, "%d" % t.baskets.size())
	if t.baskets.is_empty():
		return
	var worst := 0.0
	for b in t.baskets:
		var ground: float = t.height_at(b.global_position.x, b.global_position.z)
		worst = maxf(worst, absf(b.global_position.y - ground))
	_check("all stand on ground", worst < 0.3, "worst %.2f m off" % worst)
	_check("band height", absf(Basket.BAND_Y - 1.32) < 0.001)
	_check("tray across", absf(Basket.TARGET_RADIUS * 2.0 - 0.635) < 0.001)
	var b0 = t.baskets[0]
	_check("has colliders", b0.get_node_or_null("Pole") != null
		and b0.get_node_or_null("Tray") != null)
	var cells: Dictionary = Basket.cells()
	var top := 0
	var across := 0
	for k: Vector3i in cells:
		top = maxi(top, k.y)
		across = maxi(across, absi(k.x))
	_check("voxel basket", cells.size() > 300 and cells.size() < 4000,
		"%d voxels of %.0f cm" % [cells.size(), Basket.VOXEL * 100.0])
	_check("voxel height ~1.4 m", absf((top + 1) * Basket.VOXEL - 1.40) < 0.1,
		"%.2f m" % ((top + 1) * Basket.VOXEL))
	_check("voxel width ~0.65 m", absf((across + 1) * 2 * Basket.VOXEL - 0.65) < 0.1,
		"%.2f m" % ((across + 1) * 2 * Basket.VOXEL))
	_done("geometry")


## Spread out, clear of spawn and lakes, and the same nine every time.
func _test_siting() -> void:
	var t = _main.get_node("Terrain")
	var field = t.basket_field
	var spawn: Vector3 = t.spawn_point()
	var min_gap := 1e9
	var near_spawn := 1e9
	var lake := 1e9
	for i in t.baskets.size():
		var a: Vector3 = t.baskets[i].global_position
		near_spawn = minf(near_spawn, Vector2(a.x - spawn.x, a.z - spawn.z).length())
		lake = minf(lake, t.lake_edge_distance(a.x, a.z))
		for j in range(i + 1, t.baskets.size()):
			var b: Vector3 = t.baskets[j].global_position
			min_gap = minf(min_gap, Vector2(a.x - b.x, a.z - b.z).length())
	_check("well spread", min_gap >= 40.0,
		"closest pair %.0f m (fitted at %.0f m)" % [min_gap, field.spacing_used])
	_check("clear of spawn", near_spawn >= field.spawn_clear, "nearest %.0f m" % near_spawn)
	_check("out of lakes", lake >= field.lake_clear, "nearest lake edge %.1f m" % lake)
	var again: Array = field.pick_sites()
	var same: bool = again.size() == t.baskets.size()
	for i in mini(again.size(), t.baskets.size()):
		var p: Vector3 = t.baskets[i].global_position
		same = same and Vector2(again[i].x - p.x, again[i].z - p.z).length() < 0.01
	_check("same seed, same sites", same)
	_done("siting")


## March a disc through a basket the way disc.gd does: one sweep per physics
## tick, with gravity, until it is caught or drops clear. A disc spends
## several ticks crossing the chains, and that contact time is exactly what
## separates a putt from a drive.
func _fly(b: Node3D, from: Vector3, v0: Vector3, ticks := 90) -> Dictionary:
	var p := from
	var v := v0
	var dt := 1.0 / 60.0
	var hits := {}
	for i in ticks:
		v.y -= 9.8 * dt
		var res: Dictionary = b.sweep(p, p + v * dt, v, DISC_MASS, dt)
		v = res.v
		if res.hit != "":
			hits[res.hit] = true
		if res.caught:
			return {"caught": true, "speed": v.length(), "ticks": i + 1, "hits": hits}
		p += v * dt
		if p.y < b.global_position.y - 1.0:
			break
	return {"caught": false, "speed": v.length(), "ticks": ticks, "hits": hits}


## Henry's chain model, kept for when holes and scoring arrive: a putt must
## die in the chains; a drive must punch through.
func _test_chains() -> void:
	var t = _main.get_node("Terrain")
	if t.baskets.is_empty():
		return
	var b: Node3D = t.baskets[0]
	var c: Vector3 = b.global_position
	var entry := c + Vector3(-0.6, Basket.CHAIN_BOTTOM + 0.25, 0)

	var putt := _fly(b, entry, Vector3(8.0, 0, 0))
	_check("putt caught", putt.caught,
		"exit %.2f m/s after %d ticks" % [putt.speed, putt.ticks])
	_check("putt touched chains", putt.hits.has("chains"))

	var drive := _fly(b, entry, Vector3(25.0, 0, 0))
	_check("drive punches through", not drive.caught and drive.speed > 12.0,
		"exit %.2f m/s" % drive.speed)

	var over := _fly(b, c + Vector3(-0.6, Basket.BAND_Y + 0.40, 0), Vector3(25.0, 0, 0), 10)
	_check("clean miss over the top", not over.caught and over.hits.is_empty(),
		"hits=%s" % [over.hits.keys()])

	var far := c + Vector3(40.0, 1.0, 0)
	var away: Dictionary = b.sweep(far, far + Vector3(25.0, 0, 0) / 60.0,
		Vector3(25.0, 0, 0), DISC_MASS, 1.0 / 60.0)
	_check("far disc untouched", away.hit == "" and away.v == Vector3(25.0, 0, 0))
	_done("chains")


## Live: a cube low into the pole (a real collider), a flying disc into the
## chains (the swept path), and a bystander disc lying nearby that must NOT
## be collected.
func _start_hits() -> void:
	var t = _main.get_node("Terrain")
	var th = _main.thrower
	if t.baskets.is_empty():
		return
	th.max_discs = 20
	_target = t.baskets[0]
	var c := _target.global_position
	# Stand the walker 6 m south of the basket.
	_main.player.global_position = c + Vector3(0, 1.0, 6.0)

	_other = th.throw_cube(1.0)
	_other.launch(c + Vector3(3.0, 0.5, 3.0), Vector3.ZERO, Vector3.ZERO)

	_cube = th.throw_cube(1.0)
	# Low, under the tray: only the pole collider can stop it.
	_cube.launch(c + Vector3(-2.0, 0.3, 0.0), Vector3(9.0, 1.5, 0.0), Vector3.ZERO)

	_flyer = th.throw_disc(th.setup.params())
	_flyer.launch_disc(c + Vector3(0.0, 1.05, -3.0), Vector3(0.0, 0.5, 10.0),
		Vector3.UP, 50.0, 1.0)

	for d in [_cube, _flyer, _other]:
		d.hit_basket.connect(func(dd, bb, part) -> void: _hits.append([dd, bb, part]))


func _check_hits() -> void:
	var by := {}
	for h in _hits:
		by[h[0]] = h
	var cube_hit: bool = by.has(_cube)
	_check("cube hits a basket", cube_hit,
		("part=%s" % by[_cube][2]) if cube_hit else "no hit")
	_check("cube is going home", not is_instance_valid(_cube) or _cube.collecting
		or _cube.struck != null)
	_done("hit_collider")
	var fly_hit: bool = by.has(_flyer)
	_check("disc hits a basket", fly_hit,
		("part=%s" % by[_flyer][2]) if fly_hit else "no hit")
	_check("disc is going home", is_instance_valid(_flyer) and _flyer.collecting
		or not is_instance_valid(_flyer))
	_check("bystander left alone", is_instance_valid(_other) and not _other.collecting
		and _other.struck == null)
	_check("basket counted hits", _target.hits >= 1, "%d" % _target.hits)
	_check("confetti flying", _confetti_left() > 0, "%d bursts" % _confetti_left())
	_done("hit_chains")


func _confetti_left() -> int:
	var n := 0
	for ch in get_nodes_in_group("confetti"):
		if not ch.is_queued_for_deletion():
			n += 1
	return n
