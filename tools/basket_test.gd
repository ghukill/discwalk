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
const MUST_RUN := ["geometry", "chains", "siting", "strokes", "ace", "arrow", "lie", "map"]


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


var _started := false


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames > 5 and not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	_test_geometry()
	_test_chains()
	_test_siting()
	_test_strokes()
	await _test_ace()
	await _test_arrow()
	await _test_lie()
	await _test_map()
	for name: String in MUST_RUN:
		if not _ran.has(name):
			print("BASKET %-22s BAD  (aborted before finishing)" % name)
			_ok = false
	print("BASKET " + ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)


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

	# A point-blank drive must not stick. How much speed it keeps tracks
	# chain_max_force, so the bar here is "clearly still travelling" rather
	# than a number that has to be edited every time the knob moves.
	var drive := _fly(entry, Vector3(25.0, 0, 0))
	_check("drive punches through", not drive.caught and drive.speed > 5.0,
		"exit %.2f m/s" % drive.speed)
	_check("drive keeps far more than a putt", drive.speed > putt.speed * 2.0,
		"drive %.2f vs putt %.2f m/s" % [drive.speed, putt.speed])
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


## Siting must give a legal basket for any seed, and the same one twice.
func _test_siting() -> void:
	var t = _main.get_node("Terrain")
	var Hole := load("res://scripts/hole.gd")
	var bad := 0
	var first_seed: int = t.world_seed
	var first := Vector3.ZERO
	for i in 20:
		t.world_seed = 1000 + i * 37
		t.generate()
		var at: Vector3 = Hole.site(t)
		if i == 0:
			first = at
		var tee: Vector3 = t.spawn_point()
		var d := Vector2(at.x - tee.x, at.z - tee.z).length()
		var ix: int = t.col_of(at.x)
		var iz: int = t.col_of(at.z)
		var legal: bool = d >= 55.0 and d <= 125.0 \
			and not t.is_underwater(ix, iz) and not t.is_shore(ix, iz) \
			and t.lake_edge_distance(at.x, at.z) > 1.0 \
			and at.x > t.moraine_width + 6.0 and at.x < t.world_size - t.moraine_width - 6.0 \
			and at.z > t.moraine_width + 6.0 and at.z < t.world_size - t.moraine_width - 6.0
		if not legal:
			bad += 1
			print("BASKET   seed %d sited badly at %s (%.1f m out)" % [t.world_seed, at, d])
	_check("siting legal x20", bad == 0, "%d bad" % bad)

	# Deterministic: the same seed must give the same spot.
	t.world_seed = 1000
	t.generate()
	var again: Vector3 = Hole.site(t)
	_check("siting deterministic", again.distance_to(first) < 0.01)

	t.world_seed = first_seed
	t.generate()
	_done("siting")


## Three throws then a hand-fed make: the hole must report 3 strokes, and
## collect must be able to pull the disc back out of the tray.
func _test_strokes() -> void:
	var t = _main.get_node("Terrain")
	var b = t.basket
	var hole = _main.hole
	var thrower = _main.thrower
	if b == null or hole == null:
		_check("hole present", false)
		return
	hole.start(t.spawn_point(), b.global_position)
	_check("starts at zero", hole.strokes == 0 and not hole.complete)

	for i in 3:
		thrower.throw_disc(thrower.setup.params())
	_check("three throws, three strokes", hole.strokes == 3,
		"strokes=%d" % hole.strokes)

	thrower.throw_cube()
	_check("cube is not a stroke", hole.strokes == 3, "strokes=%d" % hole.strokes)

	var last = thrower._last
	b.capture(last)
	_check("make completes the hole", hole.complete and hole.strokes == 3,
		"complete=%s strokes=%d" % [hole.complete, hole.strokes])
	_check("disc parked in tray", b.holed == last and last.in_basket)

	thrower.collect()
	_check("collect frees the disc", b.holed == null and not last.in_basket)
	_done("strokes")


## A throw-in must be possible, or the chains are too strong. The shot needs
## to arrive on line, at chain height, and far enough out to have slowed
## below what the chains can absorb -- 44 m with a touch of loft is that
## shot on this seed. If chain_max_force drops much, this is the first thing
## that breaks, which is the point of testing it.
func _test_ace() -> void:
	var t = _main.get_node("Terrain")
	var b = t.basket
	var th = _main.thrower
	var player: CharacterBody3D = _main.get_node("Player")
	if b == null or _main.hole == null:
		_check("ace: hole present", false)
		return
	th.clear()
	b.release()
	var tee: Vector3 = t.spawn_point()
	_main.hole.start(tee, tee + Vector3(0, 0, -44.0))
	var c: Vector3 = b.global_position
	player.global_position = tee
	var to := (c - tee) * Vector3(1, 0, 1)
	# Aimed off to the right, because the disc fades left over 44 m.
	player.rotation.y = atan2(-to.x, -to.z) + deg_to_rad(9.0)
	await process_frame
	var p: Dictionary = th.setup.params()
	p.speed = 24.0
	p.pitch = 6.0
	p.roll = -8.0
	p.spin = 5.2 * 24.0
	var d = th.throw_disc(p)
	var made := false
	for i in 400:
		await process_frame
		if not is_instance_valid(d):
			break
		if b.holed != null:
			made = true
			break
		if d.resting:
			break
	_check("ace from 44 m is possible", made,
		"strokes=%d" % _main.hole.strokes)
	_done("ace")


## The screen-edge arrow: hidden when you can see the basket, shown when you
## cannot, and pointing the correct way round. That last one matters because
## unproject_position() mirrors points behind the camera, so an arrow that
## forgets to flip them points exactly 180 degrees wrong -- and looks
## perfectly plausible until you follow it.
func _test_arrow() -> void:
	var t = _main.get_node("Terrain")
	var b = t.basket
	var th = _main.thrower
	var arrow = _main.basket_arrow
	var player: CharacterBody3D = _main.get_node("Player")
	if arrow == null or b == null or _main.hole == null:
		_check("arrow present", false)
		return
	th.clear()
	var tee: Vector3 = t.spawn_point()
	_main.hole.start(tee, tee + Vector3(0, 0, -40.0))
	var c: Vector3 = b.global_position
	player.global_position = tee
	var face := atan2(-(c.x - tee.x), -(c.z - tee.z))

	player.rotation.y = face
	await _settle()
	_check("arrow hidden when basket in view", not arrow.showing())

	player.rotation.y = face + PI
	await _settle()
	_check("arrow shown when basket behind you", arrow.showing())

	player.rotation.y = face + PI * 0.5
	await _settle()
	var shown_one: bool = arrow.showing()
	var side_one := cos(arrow.angle())

	player.rotation.y = face - PI * 0.5
	await _settle()
	_check("arrow shown when basket off to the side", shown_one and arrow.showing())
	var side_two := cos(arrow.angle())
	_check("arrow points to opposite sides", side_one * side_two < 0.0,
		"cos(angle) %+.2f then %+.2f" % [side_one, side_two])

	th.set_paths(false)
	await _settle()
	_check("P hides the arrow", not arrow.showing())
	th.set_paths(true)
	await _settle()
	_done("arrow")


## The throwing box: appears behind a rested disc, measured from the
## BASKET and not from the way the disc was flying. Those two differ
## whenever a throw curves, so the test throws a disc that finishes off to
## one side and checks the box went to the basket-relative spot.
func _test_lie() -> void:
	var t = _main.get_node("Terrain")
	var b = t.basket
	var th = _main.thrower
	var marker = th.lie_marker
	var player: CharacterBody3D = _main.get_node("Player")
	if marker == null or b == null:
		_check("lie marker present", false)
		return
	th.clear()
	var tee: Vector3 = t.spawn_point()
	_main.hole.start(tee, tee + Vector3(0, 0, -40.0))
	var c: Vector3 = b.global_position
	player.global_position = tee
	await _settle()
	_check("no box before a throw", not marker.showing())

	# Drop a disc to rest well off to the side of the tee->basket line, so
	# "behind relative to the basket" and "behind relative to travel" give
	# clearly different answers.
	var lie := tee + Vector3(25.0, 0, -20.0)
	lie.y = t.height_at(lie.x, lie.z) + 0.1
	marker.place(lie, c)
	await _settle()
	_check("box appears at a lie", marker.showing())

	# It must sit on the far side of the disc from the basket.
	var box: Vector3 = marker._mesh.mesh.get_aabb().get_center() \
		+ marker._mesh.global_position
	var to_basket := Vector3(c.x - lie.x, 0, c.z - lie.z).normalized()
	var to_box := Vector3(box.x - lie.x, 0, box.z - lie.z).normalized()
	_check("box is on the far side from the basket", to_box.dot(to_basket) < -0.9,
		"dot %.2f" % to_box.dot(to_basket))
	var gap := Vector2(box.x - lie.x, box.z - lie.z).length()
	_check("box is about half a side behind", absf(gap - 0.914 * 0.5) < 0.2,
		"%.2f m" % gap)

	# Roughly 3 ft on a side. The square is rotated to face the basket, so
	# its world-axis AABB is somewhere between the side (axis-aligned) and
	# the diagonal, side * sqrt(2) -- hence the bracket rather than an
	# equality.
	var aabb: AABB = marker._mesh.mesh.get_aabb()
	var side := 0.914
	_check("box is about 3 ft on a side",
		aabb.size.x > side * 0.9 and aabb.size.x < side * 1.45
		and aabb.size.z > side * 0.9 and aabb.size.z < side * 1.45,
		"AABB %.2f x %.2f m (side %.2f, diagonal %.2f)" % [
			aabb.size.x, aabb.size.z, side, side * sqrt(2.0)])

	th.set_paths(false)
	await _settle()
	_check("P hides the box", not marker.showing())
	th.set_paths(true)
	await _settle()
	_check("P brings the box back", marker.showing())
	_done("lie")


## The overhead map (M). The one that really matters is that the compass is
## not mirrored: the map camera looks straight down, which flips an axis, so
## it is easy to end up with a player arrow that points the wrong way and
## still looks completely reasonable.
func _test_map() -> void:
	var t = _main.get_node("Terrain")
	var b = t.basket
	var th = _main.thrower
	var map = _main.map_view
	var player: CharacterBody3D = _main.get_node("Player")
	if map == null or b == null:
		_check("map present", false)
		return
	th.clear()
	var tee: Vector3 = t.spawn_point()
	_main.hole.start(tee, tee + Vector3(0, 0, -60.0))
	var c: Vector3 = b.global_position
	player.global_position = tee

	_check("map starts closed", not map.is_open())
	map.toggle()
	await _settle()
	_check("M opens the map", map.is_open())

	# Face the basket: the player arrow on the map must then point along
	# the on-map line from the player to the basket.
	player.rotation.y = atan2(-(c.x - tee.x), -(c.z - tee.z))
	await _settle()
	var here: Vector2 = map.map_pos(player.global_position)
	var there: Vector2 = map.map_pos(c)
	var to_basket := (there - here).normalized()
	var heading: Vector2 = map.heading_on_map()
	_check("map arrow points at the basket when you face it",
		heading.dot(to_basket) > 0.95,
		"dot %.3f" % heading.dot(to_basket))

	# Turn around: it must reverse, not stay put.
	player.rotation.y += PI
	await _settle()
	var back: Vector2 = map.heading_on_map()
	_check("map arrow reverses when you turn round",
		back.dot(to_basket) < -0.95, "dot %.3f" % back.dot(to_basket))

	# Turning right must swing the arrow clockwise on screen (screen y is
	# down, so a clockwise turn is a positive cross product). This is the
	# check that catches a mirrored map.
	player.rotation.y = atan2(-(c.x - tee.x), -(c.z - tee.z))
	await _settle()
	var before: Vector2 = map.heading_on_map()
	player.rotation.y -= PI * 0.5          # yaw right in Godot's -Z forward
	await _settle()
	var after: Vector2 = map.heading_on_map()
	var cross := before.x * after.y - before.y * after.x
	_check("map is not mirrored (turning right swings it clockwise)",
		cross > 0.5, "cross %.3f" % cross)

	# Both markers have to land inside the drawn panel, or the camera is
	# not framing the hole the way it claims to.
	var panel: Rect2 = map.panel_rect()
	_check("both markers land inside the map panel",
		panel.has_point(here) and panel.has_point(there)
		and here.distance_to(there) > 1.0,
		"player %s basket %s in %s" % [here.round(), there.round(), panel])

	map.toggle()
	await _settle()
	_check("M closes the map", not map.is_open())
	_done("map")


func _settle() -> void:
	await process_frame
	await process_frame
