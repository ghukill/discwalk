extends SceneTree
## Headless basket check: geometry, siting, catching and stroke counting.
##
##   godot --headless --path . --script res://tools/basket_test.gd [-- --block-size=1]

var _main: Node
var _frames := 0
var _ok := true
var _ran := {}                       ## Test functions that reached their end.

## Every test function that must run to completion. A GDScript error aborts
## only the function it happens in, so without this a broken test would skip
## all its checks and the run would still report PASS.
const MUST_RUN := ["geometry"]


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 5:
		return false
	_test_geometry()
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
