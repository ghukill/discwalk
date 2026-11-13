extends SceneTree
## Aiming and the aim arc.
##
## 1. Aim: the disc has to set off toward the thing the crosshair is on, not
##    merely parallel to your line of sight. It leaves your hand 0.3 m below
##    your eye, so copying the camera's pitch used to send it down a parallel
##    line that stayed 0.3 m low for ever.
## 2. Aim arc (T): the preview is the real flight model run forward, so it has
##    to agree with where a disc actually goes.
##
##   godot --headless --path . --script res://tools/aim_test.gd -- --block-size=1

const MUST_RUN := ["aim", "arc", "agree", "putt"]

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
	await _test_aim()
	await _test_arc()
	await _test_agree()
	await _test_putt()
	for name: String in MUST_RUN:
		if not _ran.has(name):
			print("AIM %-34s BAD  (aborted before finishing)" % name)
			_ok = false
	print("AIM " + ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)


func _check(name: String, cond: bool, detail := "") -> void:
	print("AIM %-34s %s%s" % [name, "ok" if cond else "BAD",
		("  " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _done(n: String) -> void:
	_ran[n] = true


## Look at a spot on the ground a known distance away and check the throw is
## aimed AT it, not parallel to the look direction.
func _test_aim() -> void:
	var t = _main.get_node("Terrain")
	var th = _main.thrower
	var player: CharacterBody3D = _main.get_node("Player")
	var cam: Camera3D = _main.get_node("Player/Head/Camera3D")
	# The putt assist off for this one: it lofts the throw so the disc ARRIVES
	# at the target, which is a different promise from the one being checked
	# here (that the aim line points at the target at all). _test_putt covers
	# the assist.
	var assist: float = th.putt_assist_range
	th.putt_assist_range = 0.0
	var tee: Vector3 = t.spawn_point()
	player.global_position = tee
	player.rotation.y = 0.0
	# Look down at the ground about 12 m ahead.
	var mark := Vector3(tee.x, 0.0, tee.z - 12.0)
	mark.y = t.height_at(mark.x, mark.z)
	var eye: Vector3 = cam.global_position
	var to_mark := mark - eye
	var flat := Vector3(to_mark.x, 0.0, to_mark.z).length()
	cam.rotation.x = atan2(to_mark.y, flat)
	await process_frame

	var tgt: Dictionary = th.aim_target()
	_check("the crosshair finds the ground", tgt.hit,
		"%.1f m away" % tgt.dist if tgt.hit else "no hit")
	if not tgt.hit:
		th.putt_assist_range = assist
		_done("aim")
		return
	var view_fwd := Vector3(0, 0, -1)
	var origin: Vector3 = th.release(view_fwd)
	var aim: Array = th.aim_from(origin, view_fwd)
	var pitch: float = aim[1]
	var view_pitch: float = th.launch_angle()
	# Aimed from 0.3 m lower at the same spot, so the throw must be pitched
	# UP relative to the look angle -- that difference is the whole fix.
	_check("release is below the eye", origin.y < eye.y - 0.2,
		"eye %.2f, release %.2f" % [eye.y, origin.y])
	_check("aim is pitched up relative to the look", pitch > view_pitch + 0.2,
		"look %.2f deg, throw %.2f deg" % [view_pitch, pitch])
	# And it must point AT the target: a ray from the release point along the
	# aim should pass through it.
	#
	# Measured against the point aim_target() itself reports, not against a
	# mark worked out from terrain.height_at(). The ray hits the smooth
	# collision mesh, which sits up to a block's smoothing away from the
	# heightmap, so comparing the two drifts with block_size -- it passed at
	# 1 m blocks and missed by 0.24 m at the default 0.25 m.
	var aimed := Vector3(aim[0].x, 0.0, aim[0].z).normalized() * cos(deg_to_rad(pitch))
	aimed.y = sin(deg_to_rad(pitch))
	var along: float = (tgt.at - origin).length()
	var miss: float = (origin + aimed.normalized() * along).distance_to(tgt.at)
	_check("the aim line passes through the target", miss < 0.05,
		"misses by %.3f m" % miss)
	th.putt_assist_range = assist
	_done("aim")


## The arc: off by default, T shows it, it reaches the ground, and it starts
## at the release point.
func _test_arc() -> void:
	var th = _main.thrower
	var arc = th.aim_arc
	_check("arc exists", arc != null)
	if arc == null:
		_done("arc")
		return
	_check("arc starts off", not arc.showing() and arc.mode() == arc.OFF)
	_check("arc lamp off", th.lamps.glow("arc") == 0.0)
	th.set_aim_arc(true)
	await process_frame
	await process_frame
	_check("T shows the arc", arc.showing())
	var pts: PackedVector3Array = arc.points()
	_check("arc has a shape", pts.size() > 20, "%d points" % pts.size())
	_check("arc reaches the ground", arc.landed())
	th.set_aim_arc(false)
	await process_frame
	_check("T hides it again", not arc.showing())
	await _test_arc_cycle(th, arc)
	_done("arc")


## T is three-way: off, the first half of the throw, then the whole thing
## with the landing marked. The middle setting is the one the game is meant
## to be played on, so it has to draw fewer cubes than full and no landing
## marker -- which is the only thing distinguishing it on screen.
func _test_arc_cycle(th, arc) -> void:
	arc.set_mode(arc.OFF)
	await process_frame
	await process_frame

	# Read the two drawn states back to back. The arc is re-simulated every
	# frame from where the camera points, so anything that lets the scene
	# settle between the two measurements compares different throws.
	th.cycle_aim_arc()
	await process_frame
	await process_frame
	var half: int = arc.cubes()
	var half_marked: bool = arc.marked_landing()
	var half_mode: int = arc.mode()
	th.cycle_aim_arc()
	await process_frame
	await process_frame
	var full: int = arc.cubes()
	_check("T once: flight only", half_mode == arc.FLIGHT)
	_check("T twice: the whole arc", arc.mode() == arc.FULL)
	_check("flight only hides the landing marker", not half_marked)
	_check("full marks the landing", arc.marked_landing())
	_check("flight only draws about half as much", half > 2 and half <= full * 0.7,
		"%d cubes of %d" % [half, full])

	# The lamp is three-way too, but it warms like a filament, so give it
	# time: two frames in, a lit one is still dimmer than a half-lit one.
	th.cycle_aim_arc()
	th.cycle_aim_arc()
	for i in 40:
		await process_frame
	var lit: float = th.lamps.glow("arc")
	_check("flight only leaves the lamp half lit", lit > 0.3 and lit < 0.6,
		"%.2f" % lit)
	th.cycle_aim_arc()
	th.cycle_aim_arc()
	await process_frame
	_check("and round to off again", arc.mode() == arc.OFF and not arc.showing())


## The arc has to match reality: throw the disc it is predicting and compare
## where it first lands with where the arc said it would.
func _test_agree() -> void:
	var t = _main.get_node("Terrain")
	var th = _main.thrower
	var player: CharacterBody3D = _main.get_node("Player")
	var cam: Camera3D = _main.get_node("Player/Head/Camera3D")
	var arc = th.aim_arc
	if arc == null:
		_check("arc present for the comparison", false)
		_done("agree")
		return
	th.clear()
	var tee: Vector3 = t.spawn_point()
	player.global_position = tee
	player.rotation.y = 0.0
	cam.rotation.x = deg_to_rad(8.0)
	th.setup.set_value("speed", 20.0)
	th.setup.nose = 0.0
	th.setup.roll = 8.0
	await process_frame
	th.set_aim_arc(true)
	# The arc does not know about trees, so the comparison needs a line with
	# none on it: turn until the predicted flight is clear of every branch
	# and leaf, and if the woods are too thick for that, throw softer and
	# look again. (Which way is clear depends on the world and on how the disc
	# flies, so it is searched for rather than written down.)
	var pts := PackedVector3Array()
	var clear := false
	for speed in [20.0, 16.0, 13.0]:
		th.setup.set_value("speed", speed)
		for step in 24:
			# 0, +15, -15, +30, ...: stay near north if north will do.
			var turn: float = 15.0 * ceilf(step / 2.0) * (1.0 if step % 2 == 1 else -1.0)
			player.rotation.y = deg_to_rad(turn)
			await process_frame
			await process_frame
			pts = arc.points()
			if pts.size() >= 2 and _clear_of_trees(t, pts):
				clear = true
				break
		if clear:
			break
	if pts.size() < 2:
		_check("arc produced a path", false)
		_done("agree")
		return
	_check("found a line with no trees on it", clear)
	var predicted: Vector3 = pts[pts.size() - 1]
	var d = th.throw_disc(th.setup.params())
	var landed := Vector3.ZERO
	var got := false
	for i in 1800:
		await process_frame
		if not is_instance_valid(d):
			break
		if not d.flying and not got:
			landed = d.global_position
			got = true
			break
	th.set_aim_arc(false)
	_check("the disc landed", got)
	if got:
		var miss: float = Vector2(landed.x - predicted.x, landed.z - predicted.z).length()
		var flown: float = Vector2(landed.x - tee.x, landed.z - tee.z).length()
		# A few per cent: the arc steps at a fixed 60 Hz and does not know
		# about trees or the ground collider's smoothing, so it will never be
		# exact. It must not be misleading, which is a different bar.
		_check("arc predicts the landing spot", miss < maxf(2.0, flown * 0.06),
			"predicted %.1f m out, landed %.1f m out (on %s), %.2f m apart" % [
				Vector2(predicted.x - tee.x, predicted.z - tee.z).length(), flown,
				d.landed_by, miss])
	if is_instance_valid(d):
		d.queue_free()
	_done("agree")


## True if no point of `pts` is in a tree voxel, or within MARGIN of one (the
## real flight strays a little from the arc, and it only takes one leaf).
func _clear_of_trees(t: Node3D, pts: PackedVector3Array) -> bool:
	const MARGIN := 0.75
	var bs: float = t.block_size
	var offsets := [Vector3.ZERO, Vector3(MARGIN, 0, 0), Vector3(-MARGIN, 0, 0),
		Vector3(0, MARGIN, 0), Vector3(0, -MARGIN, 0), Vector3(0, 0, MARGIN), Vector3(0, 0, -MARGIN)]
	for p in pts:
		for off: Vector3 in offsets:
			var q: Vector3 = p + off
			if t.flora.voxel_at(Vector3i(floori(q.x / bs), floori(q.y / bs), floori(q.z / bs))) != 0:
				return false
	return true


## The point of the putt assist: aim at the chains from putting range and the
## disc has to ARRIVE there, not a foot or two under.
##
## Checked against aim_target() itself, so the test states the actual promise
## -- "the disc gets to the point the aim is on" -- instead of a height picked
## separately that then has to be kept in step with the aim.
func _test_putt() -> void:
	var t = _main.get_node("Terrain")
	var th = _main.thrower
	var player: CharacterBody3D = _main.get_node("Player")
	var cam: Camera3D = _main.get_node("Player/Head/Camera3D")
	var FlightSim := load("res://scripts/flight_sim.gd")
	var Basket := load("res://scripts/basket.gd")
	if t.baskets.is_empty():
		_check("a basket to putt at", false)
		_done("putt")
		return
	var b: Node3D = t.baskets[0]
	# A putter, because that is what you putt with: a high-speed driver at
	# putting pace is a brick and genuinely cannot reach 10 m.
	for m in th.disc_models:
		if m.id == "kettle":
			th.setup.disc_index = th.disc_models.find(m)
	# [distance, release speed]. Power matched to the putt: this basket sits
	# a metre above the ground around it, and 9 m/s (20 mph) cannot throw a
	# disc 10 m uphill at all -- no launch angle reaches, which is physics,
	# not a bug. The unreachable case is checked on purpose further down.
	# The last one is the soft approach from 56 ft: out past where the assist
	# used to stop, at a speed that only gets there with loft.
	for case in [[4.0, 9.0], [7.0, 10.0], [10.0, 12.0], [17.0, 14.0]]:
		var dist: float = case[0]
		th.clear()
		var at: Vector3 = b.global_position + Vector3(0.0, 0.0, float(dist))
		at.y = t.height_at(at.x, at.z)
		player.global_position = at
		for i in 8:
			await process_frame
		# Aim AFTER the body has settled: placing it and aiming in the same
		# frame leaves the eye somewhere else by the time the ray is cast,
		# and the sight line misses the basket by a third of a metre.
		var band: Vector3 = b.global_position + Vector3(0, Basket.CHAIN_TOP, 0)
		var to_band: Vector3 = band - cam.global_position
		player.rotation.y = atan2(-to_band.x, -to_band.z)
		await process_frame
		to_band = band - cam.global_position
		cam.rotation.x = atan2(to_band.y, Vector2(to_band.x, to_band.z).length())
		await process_frame
		th.setup.set_value("speed", float(case[1]))
		th.setup.nose = 0.0
		th.setup.roll = 0.0
		await process_frame

		var tgt: Dictionary = th.aim_target()
		var on_basket: bool = tgt.hit \
			and Vector2(tgt.at.x - b.global_position.x,
				tgt.at.z - b.global_position.z).length() < 0.01
		_check("from %.0f m the crosshair is on the basket" % dist, on_basket,
			"target %.2f m away%s" % [tgt.dist,
				"" if on_basket else " (not the basket)"])
		if not on_basket:
			continue
		var view_fwd: Vector3 = Vector3(0, 0, -1).rotated(Vector3.UP, player.rotation.y)
		var origin: Vector3 = th.release(view_fwd)
		var aim: Array = th.aim_from(origin, view_fwd)
		# The basket may sit well above or below this spot (it depends on the
		# world), so if this much arm cannot get there, use a little more:
		# the promise is that a throw that CAN arrive does.
		while th._assist_short and th.setup.speed < 24.0:
			th.setup.set_value("speed", th.setup.speed + 2.0)
			await process_frame
			aim = th.aim_from(origin, view_fwd)
		var path: PackedVector3Array = FlightSim.fly_throw(
			th.setup.params(), origin, aim[0], aim[1], t)
		var err: float = FlightSim.height_error(path, origin, tgt.at)
		_check("putt from %.0f m at %.0f m/s arrives where it is aimed" % [dist, th.setup.speed],
			is_finite(err) and absf(err) < 0.2 and th.assist_armed() and not th._assist_short,
			"%+.2f m off the aim point (launch %+.1f deg)" % [err, aim[1]]
			if is_finite(err) else "fell short (launch %+.1f deg)" % aim[1])

		# Too slow to get there: the assist must give up and hand back the
		# straight line, not quietly throw something else.
		if dist >= 10.0:
			th.setup.set_value("speed", 5.0)
			await process_frame
			var weak: Array = th.aim_from(origin, view_fwd)
			var line: float = rad_to_deg(atan2(tgt.at.y - origin.y,
				Vector2(tgt.at.x - origin.x, tgt.at.z - origin.z).length()))
			_check("too soft to arrive: the straight line, and it says so",
				absf(weak[1] - clampf(line, th.launch_min, th.launch_max)) < 0.5
				and th._assist_short,
				"5 m/s at %.0f m: aim %+.2f deg, line %+.2f deg" % [dist, weak[1], line])
	# Beyond the range the assist must be gone: a long throw keeps its arc.
	# Needs something to aim at that really is far off, so turn (and tip the
	# view) until the crosshair lands on ground well past the range; standing
	# 40 m from the basket is no use if a rise 4 m ahead is what you are
	# looking at. And at a speed that could loft it there, or "no assist"
	# proves nothing.
	th.clear()
	th.setup.set_value("speed", 20.0)
	player.global_position = t.spawn_point()
	for i in 8:
		await process_frame
	var tgt2 := {"hit": false, "dist": 0.0}
	for look in [-4.0, -8.0, -2.0, -12.0]:
		for step in 12:
			player.rotation.y = deg_to_rad(30.0 * step)
			cam.rotation.x = deg_to_rad(look)
			await process_frame
			await process_frame
			tgt2 = th.aim_target()
			if tgt2.hit and tgt2.dist > th.putt_assist_fade + 8.0 and tgt2.dist < 120.0:
				break
		if tgt2.hit and tgt2.dist > th.putt_assist_fade + 8.0 and tgt2.dist < 120.0:
			break
	var far: bool = tgt2.hit and tgt2.dist > th.putt_assist_fade + 8.0
	_check("something far off to aim at", far, "%.1f m away" % tgt2.dist)
	if far:
		var vf2: Vector3 = Vector3(0, 0, -1).rotated(Vector3.UP, player.rotation.y)
		var o2: Vector3 = th.release(vf2)
		var a2: Array = th.aim_from(o2, vf2)
		var straight: float = rad_to_deg(atan2(tgt2.at.y - o2.y,
			Vector2(tgt2.at.x - o2.x, tgt2.at.z - o2.z).length()))
		_check("no assist past the range", absf(a2[1] - straight) < 0.05 and not th.assist_armed(),
			"aim %+.2f deg vs straight line %+.2f deg, target %.1f m away" % [a2[1], straight, tgt2.dist])
	_check("assist: all of it inside circle 2, none beyond", th._assist_blend(5.0) == 1.0
		and th._assist_blend(19.0) == 1.0 and th._assist_blend(21.0) == 0.0
		and th._assist_blend(40.0) == 0.0,
		"5 m -> %.2f, 15 m -> %.2f, 40 m -> %.2f" % [
			th._assist_blend(5.0), th._assist_blend(15.0), th._assist_blend(40.0)])
	_done("putt")
