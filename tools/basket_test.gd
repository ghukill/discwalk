extends SceneTree
## Headless basket check: geometry, siting, catching and stroke counting.
##
##   godot --headless --path . --script res://tools/basket_test.gd [-- --block-size=1]

const Basket := preload("res://scripts/basket.gd")
const DISC_MASS := 0.175             ## disc.gd sets this on every thrown disc.

var _main: Node
var _frames := 0
var _ok := true
var _ran := {}                       ## Test functions that reached their end.

## Every test function that must run to completion. A GDScript error aborts
## only the function it happens in, so without this a broken test would skip
## all its checks and the run would still report PASS.
const MUST_RUN := ["geometry", "chains"]


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 5:
		return false
	_test_geometry()
	_test_chains()
	for name: String in MUST_RUN:
		if not _ran.has(name):
			print("BASKET %-22s BAD  (aborted before finishing)" % name)
			_ok = false
	print("BASKET " + ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)
	return true


func _check(name: String, cond: bool, detail := "") -> void:
	print("BASKET %-22s %s%s" % [name, "ok" if cond else "BAD",
		("  " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _done(name: String) -> void:
	_ran[name] = true


## The basket exists, stands on the ground, and is the right size.
func _test_geometry() -> void:
	var t = _main.get_node("Terrain")
	var b = t.basket
	_check("exists", b != null)
	if b == null:
		return
	var ground: float = t.height_at(b.global_position.x, b.global_position.z)
	_check("stands on ground", absf(b.global_position.y - ground) < 0.3,
		"basket y=%.2f ground=%.2f" % [b.global_position.y, ground])
	_check("band height", absf(b.BAND_Y - 1.32) < 0.001)
	_check("tray across", absf(b.TARGET_RADIUS * 2.0 - 0.635) < 0.001)
	_check("has colliders", b.get_node_or_null("Pole") != null
		and b.get_node_or_null("Tray") != null)
	_check("nothing holed yet", b.holed == null)
	_done("geometry")


## March a disc through the basket the way disc.gd does: one sweep per
## physics tick, with gravity, until it is caught or drops clear. Testing a
## single tick would be meaningless -- a disc spends several ticks crossing
## the chains, and that contact time is exactly what separates a putt from a
## drive.
func _fly(from: Vector3, v0: Vector3, ticks := 90) -> Dictionary:
	var b = _main.get_node("Terrain").basket
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


## The chain model. A putt must die in the chains; a drive must punch through.
func _test_chains() -> void:
	var t = _main.get_node("Terrain")
	var b = t.basket
	if b == null:
		return
	var c: Vector3 = b.global_position
	var entry := c + Vector3(-0.6, Basket.CHAIN_BOTTOM + 0.25, 0)

	var putt := _fly(entry, Vector3(8.0, 0, 0))
	_check("putt caught", putt.caught,
		"exit %.2f m/s after %d ticks" % [putt.speed, putt.ticks])
	_check("putt touched chains", putt.hits.has("chains"))

	var drive := _fly(entry, Vector3(25.0, 0, 0))
	_check("drive punches through", not drive.caught and drive.speed > 12.0,
		"exit %.2f m/s" % drive.speed)
	_check("drive touched chains", drive.hits.has("chains"))

	# Over the top: a few ticks is plenty to clear the basket at 25 m/s.
	var over := _fly(c + Vector3(-0.6, Basket.BAND_Y + 0.40, 0), Vector3(25.0, 0, 0), 10)
	_check("clean miss over the top", not over.caught and over.hits.is_empty(),
		"hits=%s" % [over.hits.keys()])

	# Already inside the cage and barely moving: caught.
	var dropped := _fly(c + Vector3(0, Basket.TRAY_FLOOR_Y + 0.15, 0), Vector3(0.5, 0, 0), 5)
	_check("slow disc in cage caught", dropped.caught)

	# Broad phase: a disc out in the world must come back untouched.
	var far := c + Vector3(40.0, 1.0, 0)
	var away: Dictionary = b.sweep(far, far + Vector3(25.0, 0, 0) / 60.0,
		Vector3(25.0, 0, 0), DISC_MASS, 1.0 / 60.0)
	_check("far disc untouched", away.hit == "" and away.v == Vector3(25.0, 0, 0))
	_done("chains")
