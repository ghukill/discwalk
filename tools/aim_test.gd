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
	_check("arc starts off", not arc.showing())
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
	_done("arc")


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
	await process_frame
	await process_frame
	var pts: PackedVector3Array = arc.points()
	if pts.size() < 2:
		_check("arc produced a path", false)
		_done("agree")
		return
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
			"predicted %.1f m out, landed %.1f m out, %.2f m apart" % [
				Vector2(predicted.x - tee.x, predicted.z - tee.z).length(), flown, miss])
	if is_instance_valid(d):
		d.queue_free()
	_done("agree")


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
	for case in [[4.0, 9.0], [7.0, 10.0], [10.0, 12.0]]:
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
		var path: PackedVector3Array = FlightSim.fly_throw(
			th.setup.params(), origin, aim[0], aim[1], t)
		var err: float = FlightSim.height_error(path, origin, tgt.at)
		_check("putt from %.0f m at %.0f m/s arrives where it is aimed" % [dist, case[1]],
			is_finite(err) and absf(err) < 0.2,
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
			_check("out of range falls back to the straight line",
				absf(weak[1] - clampf(line, th.launch_min, th.launch_max)) < 0.5,
				"5 m/s at %.0f m: aim %+.2f deg, line %+.2f deg" % [dist, weak[1], line])
	# Beyond the fade the assist must be gone: a long throw keeps its arc.
	th.clear()
	var at2: Vector3 = b.global_position + Vector3(0.0, 0.0, 40.0)
	at2.y = t.height_at(at2.x, at2.z)
	player.global_position = at2
	for i in 8:
		await process_frame
	var band2: Vector3 = b.global_position + Vector3(0, Basket.CHAIN_TOP, 0)
	var to2: Vector3 = band2 - cam.global_position
	player.rotation.y = atan2(-to2.x, -to2.z)
	await process_frame
	to2 = band2 - cam.global_position
	cam.rotation.x = atan2(to2.y, Vector2(to2.x, to2.z).length())
	await process_frame
	var vf2: Vector3 = Vector3(0, 0, -1).rotated(Vector3.UP, player.rotation.y)
	var o2: Vector3 = th.release(vf2)
	var a2: Array = th.aim_from(o2, vf2)
	var tgt2: Dictionary = th.aim_target()
	var straight: float = rad_to_deg(atan2(tgt2.at.y - o2.y,
		Vector2(tgt2.at.x - o2.x, tgt2.at.z - o2.z).length())) if tgt2.hit else a2[1]
	_check("no assist out at 40 m", absf(a2[1] - straight) < 0.5,
		"aim %+.2f deg vs straight line %+.2f deg" % [a2[1], straight])
	_check("assist blend: 1 near, 0 far", th._assist_blend(5.0) == 1.0
		and th._assist_blend(40.0) == 0.0,
		"5 m -> %.2f, 15 m -> %.2f, 40 m -> %.2f" % [
			th._assist_blend(5.0), th._assist_blend(15.0), th._assist_blend(40.0)])
	_done("putt")
