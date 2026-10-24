extends SceneTree
## Finding the basket: the beam and the screen-edge arrow, and the one
## selection they share.
##
##   godot --headless --path . --script res://tools/finder_test.gd -- --block-size=1

const MUST_RUN := ["select", "free", "course", "arrow", "beam"]

var _main: Node
var _f := 0
var _started := false
var _ok := true
var _ran := {}


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_d: float) -> bool:
	_f += 1
	if _f > 5 and not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	await _test_select()
	await _test_free()
	await _test_course()
	await _test_arrow()
	await _test_beam()
	for name: String in MUST_RUN:
		if not _ran.has(name):
			print("FINDER %-38s BAD  (aborted before finishing)" % name)
			_ok = false
	print("FINDER " + ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)


func _check(name: String, cond: bool, detail := "") -> void:
	print("FINDER %-38s %s%s" % [name, "ok" if cond else "BAD",
		("  " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _done(n: String) -> void:
	_ran[n] = true


func _finder():
	return _main.thrower.basket_finder


func _test_select() -> void:
	var f = _finder()
	_check("the finder exists", f != null)
	if f == null:
		_done("select")
		return
	_check("it found the baskets", f.count() > 0, "%d baskets" % f.count())
	_check("something is selected", f.selected() != null)
	# The beam and the arrow must be about the SAME basket, always: that is
	# the whole point of one selection.
	var b = f.selected()
	var p = f.target_point()
	_check("the arrow's target is the selected basket",
		p != null and b != null
		and Vector2(p.x - b.global_position.x, p.z - b.global_position.z).length() < 0.01)
	_done("select")


## Free Play: B walks through the baskets, Shift+B walks back, and it wraps.
func _test_free() -> void:
	var f = _finder()
	var th = _main.thrower
	if f == null or f.count() < 2:
		_check("at least two baskets to cycle", false)
		_done("free")
		return
	_main.course_round.stop()                # Free Play rules
	await process_frame
	var n: int = f.count()
	var first = f.selected()
	th.cycle_basket(1)
	var second = f.selected()
	_check("B picks a different basket", second != first,
		"basket %d of %d" % [f.number(), n])
	th.cycle_basket(-1)
	_check("Shift+B comes back", f.selected() == first, "basket %d" % f.number())
	# All the way round and we are home again.
	for i in n:
		th.cycle_basket(1)
	_check("it wraps all the way round", f.selected() == first,
		"%d steps of %d baskets" % [n, n])
	_done("free")


## Course Play: the hole decides, and B must not override it.
func _test_course() -> void:
	var f = _finder()
	var th = _main.thrower
	if f == null:
		_done("course")
		return
	var cr = _main.course_round
	if cr.holes().is_empty():
		_check("a course with holes to play", false)
		_done("course")
		return
	cr.start()
	await process_frame
	var want = cr.current().basket
	_check("in Course Play the beam is on the hole you are playing",
		f.selected() == want, "hole %d" % cr.current().n)
	var before = f.selected()
	th.cycle_basket(1)
	_check("B does not override the hole", f.selected() == before)
	cr.stop()
	await process_frame
	_done("course")


## The arrow: hidden when you can see the basket, shown when you cannot, and
## pointing the right way round when it is behind you.
func _test_arrow() -> void:
	var f = _finder()
	var th = _main.thrower
	var player: CharacterBody3D = _main.get_node("Player")
	var cam: Camera3D = _main.get_node("Player/Head/Camera3D")
	if f == null or f.selected() == null:
		_done("arrow")
		return
	_main.course_round.stop()
	await process_frame
	var b: Node3D = f.selected()
	# Stand back from it and look straight at it.
	var at: Vector3 = b.global_position + Vector3(0.0, 0.0, 25.0)
	at.y = _main.get_node("Terrain").height_at(at.x, at.z)
	player.global_position = at
	for i in 8:
		await process_frame
	var to: Vector3 = b.global_position - cam.global_position
	var face := atan2(-to.x, -to.z)
	player.rotation.y = face
	cam.rotation.x = 0.0
	await process_frame
	await process_frame
	_check("no arrow while the basket is in view", f._arrow_dir() == Vector2.ZERO)

	player.rotation.y = face + PI
	await process_frame
	await process_frame
	var back: Vector2 = f._arrow_dir()
	_check("an arrow once it is behind you", back != Vector2.ZERO,
		"(%.2f, %.2f)" % [back.x, back.y])
	# Turned round, the arrow must point horizontally -- "turn", not "above
	# you" -- because unproject mirrors points behind the camera.
	_check("behind you it points sideways, not up", absf(back.y) < 0.01,
		"y = %.3f" % back.y)

	# 65 degrees, not 90: at exactly 90 the basket is level with the camera
	# plane, which is the one angle where the projection is degenerate. 65 is
	# comfortably off screen (the view is 80 degrees) and comfortably in front.
	player.rotation.y = face + deg_to_rad(65.0)
	await process_frame
	await process_frame
	var left: Vector2 = f._arrow_dir()
	player.rotation.y = face - deg_to_rad(65.0)
	await process_frame
	await process_frame
	var right: Vector2 = f._arrow_dir()
	_check("it points opposite ways when you turn opposite ways",
		left != Vector2.ZERO and right != Vector2.ZERO and left.dot(right) < -0.5,
		"dot %.2f" % left.dot(right))

	th.set_paths(false)
	await process_frame
	_check("P hides the arrow", f._arrow_dir() == Vector2.ZERO)
	th.set_paths(true)
	await process_frame
	_done("arrow")


## The beam: over the selected basket, faded out close up, wider far away.
func _test_beam() -> void:
	var f = _finder()
	var th = _main.thrower
	var player: CharacterBody3D = _main.get_node("Player")
	var terrain = _main.get_node("Terrain")
	if f == null or f.selected() == null:
		_done("beam")
		return
	_main.course_round.stop()
	await process_frame
	var b: Node3D = f.selected()
	var beam: MeshInstance3D = f.get_node("Beam")
	# Far off: visible, and scaled up so it is still readable.
	var far: Vector3 = b.global_position + Vector3(0.0, 0.0, 70.0)
	far.y = terrain.height_at(far.x, far.z)
	player.global_position = far
	for i in 8:
		await process_frame
	_check("the beam stands over the basket",
		Vector2(beam.global_position.x - b.global_position.x,
			beam.global_position.z - b.global_position.z).length() < 0.01)
	_check("visible from a tee", beam.visible)
	var far_scale: float = beam.scale.x
	_check("widened for distance", far_scale > 1.5, "x%.2f at 70 m" % far_scale)

	# Up close: faded away, so it is not a stripe across what you are putting at.
	var near: Vector3 = b.global_position + Vector3(0.0, 0.0, 3.0)
	near.y = terrain.height_at(near.x, near.z)
	player.global_position = near
	for i in 8:
		await process_frame
	_check("faded out when you walk up", not beam.visible)

	player.global_position = far
	for i in 8:
		await process_frame
	th.set_paths(false)
	await process_frame
	_check("P puts the beam out", not beam.visible)
	th.set_paths(true)
	for i in 3:
		await process_frame
	_check("P brings it back", beam.visible)
	_done("beam")
