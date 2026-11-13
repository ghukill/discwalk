extends SceneTree
## Wind (scripts/wind.gd), in three parts.
##
## 1. Model: calm is nothing at all, the set speed is true at head height, it
##    is lighter below and stronger above, "from the west" blows east, gusts
##    stay inside their band, and the golfer's words (head, tail, L→R) come
##    out right.
## 2. Flights: real FlyingDisc bodies over a flat, empty floor in a steady
##    10 mph wind from each side. What every disc golfer knows has to fall out
##    of the lift, drag and moment tables on its own: a headwind lifts a disc
##    and flips it over (ends right, RH backhand) and costs distance; a
##    tailwind pushes it down and makes it more stable (ends left); a
##    crosswind carries it downwind. And the aim arc's simulation
##    (flight_sim.gd) has to land where the body does, wind and all.
## 3. World: F and Z set it, the heading dial and its readout follow, discs
##    are thrown into it, the aim arc bends with it, the streaks and the
##    clouds show it, and calm puts everything back.
##
##   godot --headless --path . --script res://tools/wind_test.gd -- --block-size=1

const FLYING_DISC := preload("res://scripts/flying_disc.gd")
const DiscModel := preload("res://scripts/disc_model.gd")
const FlightSim := preload("res://scripts/flight_sim.gd")
const Wind := preload("res://scripts/wind.gd")

const MUST_RUN := ["model", "flights", "world"]
const MPH := 2.2369363

var _main: Node
var _f := 0
var _started := false
var _ok := true
var _ran := {}


func _process(_d: float) -> bool:
	_f += 1
	if _f > 2 and not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	_test_model()
	await _test_flights()
	await _test_world()
	for name: String in MUST_RUN:
		if not _ran.has(name):
			print("WIND %-46s BAD  (aborted before finishing)" % name)
			_ok = false
	print("WIND " + ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)


func _check(name: String, cond: bool, detail := "") -> void:
	print("WIND %-46s %s%s" % [name, "ok" if cond else "BAD",
		("  " + detail) if detail != "" else ""])
	_ok = _ok and cond


func _key(k: Key, shift := false, pressed := true) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.shift_pressed = shift
	e.pressed = pressed
	Input.parse_input_event(e)


func _tap(k: Key, shift := false) -> void:
	if shift:
		_key(KEY_SHIFT, true, true)
		Input.flush_buffered_events()
	_key(k, shift, true)
	Input.flush_buffered_events()
	_key(k, shift, false)
	Input.flush_buffered_events()
	if shift:
		_key(KEY_SHIFT, false, false)
		Input.flush_buffered_events()


func _steady(mph: float, from: float) -> RefCounted:
	var w := Wind.new()
	w.gustiness = 0.0
	w.from_deg = from
	w.set_speed_mph(mph)
	return w


# ---------------------------------------------------------------- 1. model

func _test_model() -> void:
	var w := Wind.new()
	_check("starts calm", w.is_calm() and w.at_height(5.0) == Vector3.ZERO and w.head() == Vector3.ZERO)

	w = _steady(10.0, 270.0)
	var h: Vector3 = w.head()
	_check("10 mph from the west blows east at head height",
		absf(h.length() * MPH - 10.0) < 0.01 and h.normalized().dot(Vector3.RIGHT) > 0.999,
		"%.2f mph toward %s" % [h.length() * MPH, h.normalized()])
	_check("from the north blows south (+Z)", _steady(10.0, 0.0).head().normalized().dot(Vector3.BACK) > 0.999)
	_check("bearing_from undoes to_dir",
		absf(Wind.bearing_from(Wind.to_dir(135.0)) - 135.0) < 0.001
		and absf(Wind.bearing_from(Wind.to_dir(315.0)) - 315.0) < 0.001)

	var lo: float = Wind.profile(0.5)
	var hi: float = Wind.profile(10.0)
	_check("lighter near the ground, stronger aloft",
		Wind.profile(0.02) == 0.0 and lo < 0.7 and absf(Wind.profile(Wind.REF_HEIGHT) - 1.0) < 1e-6
		and hi > 1.35 and hi < 1.55 and Wind.profile(1000.0) == Wind.profile(Wind.TOP),
		"x%.2f at 0.5 m, x1 at %.0f m, x%.2f at 10 m" % [lo, Wind.REF_HEIGHT, hi])
	_check("the profile scales the wind you feel",
		w.at_height(10.0).is_equal_approx(w.head() * hi))

	# Gusts: a minute of it, sampled at the physics tick.
	w = Wind.new()
	w.gustiness = 0.2
	w.set_speed_mph(10.0)
	var smin := INF
	var smax := 0.0
	var swing := 0.0
	var mean := 0.0
	var steps := 60 * 60
	var jump := 0.0
	var prev: Vector3 = w.head()
	for i in steps:
		w.advance(1.0 / 60.0)
		var g: Vector3 = w.head()
		var sp: float = g.length() * MPH
		smin = minf(smin, sp)
		smax = maxf(smax, sp)
		mean += sp / steps
		swing = maxf(swing, rad_to_deg(g.angle_to(w.mean_dir())))
		jump = maxf(jump, (g - prev).length())
		prev = g
	_check("gusts breathe inside their band",
		smin >= 7.99 and smax <= 12.01 and smax - smin > 2.0 and absf(mean - 10.0) < 0.5
		and swing > 4.0 and swing <= 10.01,
		"%.1f..%.1f mph (mean %.1f), swinging up to %.1f deg" % [smin, smax, mean, swing])
	_check("gusts are smooth (no jumps between ticks)", jump < 0.05, "max step %.3f m/s" % jump)
	var a := Wind.new()
	var b := Wind.new()
	for x: RefCounted in [a, b]:
		x.set_speed_mph(12.0)
		x.advance(7.3)
	_check("same clock, same gust", a.head() == b.head())

	var fwd := Vector3.FORWARD               # throwing north (-Z)
	var names := [
		Wind.relative_name(Wind.to_dir(0.0), fwd), Wind.relative_name(Wind.to_dir(180.0), fwd),
		Wind.relative_name(Wind.to_dir(270.0), fwd), Wind.relative_name(Wind.to_dir(90.0), fwd),
		Wind.relative_name(Wind.to_dir(315.0), fwd), Wind.relative_name(Wind.to_dir(135.0), fwd)]
	_check("head / tail / L→R / R→L, and the quarters",
		names == ["head", "tail", "L→R", "R→L", "head L→R", "tail R→L"], str(names))

	w = Wind.new()
	var seen := []
	for i in Wind.PRESETS.size():
		w.cycle(1)
		seen.append(w.strength_name())
	w.cycle(-1)
	_check("F steps light .. gale and back round to calm (and Shift+F back)",
		seen == ["light", "breezy", "windy", "strong", "gale", "calm"] and w.strength_name() == "gale",
		str(seen))
	w = Wind.new()
	_check("--wind=12@90 parses; nonsense does not",
		w.parse("12@90") and absf(w.speed * MPH - 12.0) < 1e-4 and w.from_deg == 90.0
		and w.from_name() == "east" and not Wind.new().parse("gale") and not Wind.new().parse("5@x"))
	_ran["model"] = true


# -------------------------------------------------------------- 2. flights

func _test_flights() -> void:
	var models := {}
	for m in DiscModel.load_all():
		models[m.id] = m
	var lab := Node3D.new()
	root.add_child(lab)
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6000, 1, 2000)
	cs.shape = box
	cs.position = Vector3(1500, -0.5, 0)
	floor_body.add_child(cs)
	lab.add_child(floor_body)
	var stub := Node3D.new()
	stub.set_script(_stub_terrain_script())
	lab.add_child(stub)

	# Thrown north (-Z), so a headwind comes from the north. RH backhand
	# Moraine, 24 m/s, 10 deg up, 10 deg of hyzer: the stock hyzer flip.
	var cases := [
		{"name": "calm", "wind": null},
		{"name": "head", "wind": _steady(10.0, 0.0)},
		{"name": "tail", "wind": _steady(10.0, 180.0)},
		{"name": "L→R", "wind": _steady(10.0, 270.0)},
		{"name": "R→L", "wind": _steady(10.0, 90.0)},
	]
	var model = models["moraine"]
	var speed := 24.0
	var spin: float = DiscModel.auto_spin(speed)
	for i in cases.size():
		var c: Dictionary = cases[i]
		var d: RigidBody3D = RigidBody3D.new()
		d.set_script(FLYING_DISC)
		d.terrain = stub
		d.model = model
		d.wind = c.wind
		lab.add_child(d)
		var origin := Vector3(i * 300.0, 1.3, 0)
		var ls: Array = DiscModel.launch_state(Vector3.FORWARD, speed, 10.0, 0.0, 10.0, 1.0)
		d.launch_disc(origin, ls[0], ls[1], spin, 1.0)
		d.collision_layer = 2
		d.collision_mask = 1
		c.disc = d
		c.origin = origin
		c.sim = FlightSim.fly(model, origin, ls[0], ls[1], spin, 1.0, stub, FlightSim.MAX_STEPS, c.wind)
	# Note where each one first comes down, the tick its flight ends.
	var ticks := 0
	while ticks < 60 * 25 and cases.any(func(c) -> bool: return not c.has("at")):
		await physics_frame
		ticks += 1
		for c: Dictionary in cases:
			if not c.has("at") and not c.disc.flying:
				c.at = c.disc.global_position
	var by := {}
	var worst := 0.0
	for c: Dictionary in cases:
		var d = c.disc
		var o: Vector3 = c.origin
		var at: Vector3 = c.get("at", d.global_position)
		c.carry = o.z - at.z
		c.left = o.x - at.x
		c.peak = d.max_height
		var end: Vector3 = c.sim[c.sim.size() - 1]
		c.miss = Vector2(end.x - at.x, end.z - at.z).length()
		worst = maxf(worst, c.miss)
		by[c.name] = c
		print("WIND   %-5s carry %5.1f m  left %+6.1f m  peak %4.1f m  %.1f s   (arc lands %.2f m away)" % [
			c.name, c.carry, c.left, c.peak, d.flight_time, c.miss])
	_check("every throw came down", cases.all(func(c) -> bool: return not c.disc.flying))
	_check("a headwind flips it over and costs distance",
		by.head.left < by.calm.left - 8.0 and by.head.carry < by.calm.carry - 10.0,
		"%+.1f m of drift, %.0f m shorter" % [by.head.left - by.calm.left, by.calm.carry - by.head.carry])
	_check("a headwind lifts it, a tailwind pushes it down",
		by.head.peak > by.calm.peak + 0.5 and by.tail.peak < by.calm.peak - 1.0,
		"peak %.1f / %.1f / %.1f m (head / calm / tail)" % [by.head.peak, by.calm.peak, by.tail.peak])
	_check("a tailwind makes it more stable (finishes further left)",
		by.tail.left > by.calm.left + 3.0, "%+.1f m" % (by.tail.left - by.calm.left))
	_check("a crosswind carries it downwind",
		by["L→R"].left < by.calm.left - 10.0 and by["R→L"].left > by.calm.left + 5.0,
		"L→R %+.1f m, R→L %+.1f m" % [by["L→R"].left - by.calm.left, by["R→L"].left - by.calm.left])
	# Hyzer shows the wind the top of the disc from the left and the underside
	# from the right, so R→L gets under it and L→R presses it down.
	_check("wind under a hyzer lifts it, wind on top presses it down",
		by["R→L"].peak > by.calm.peak + 0.5 and by["L→R"].peak < by.calm.peak - 0.5,
		"peak %.1f (R→L) / %.1f (calm) / %.1f (L→R) m" % [by["R→L"].peak, by.calm.peak, by["L→R"].peak])
	# The body's landing is read a tick or two late and off its rim, not its
	# centre: about 0.8 m of this is there in still air too.
	_check("the arc's simulation lands where the disc does, in any wind", worst < 2.5,
		"worst %.2f m" % worst)
	lab.queue_free()
	await process_frame
	_ran["flights"] = true


# ---------------------------------------------------------------- 3. world

func _test_world() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	for i in 8:
		await process_frame
	var th = _main.thrower
	var wind: RefCounted = th.wind
	var fx = _main.wind_fx
	var dials = th.dials
	var clouds = _main.clouds
	var player: CharacterBody3D = _main.get_node("Player")
	var calm_drift: Vector2 = clouds.drift
	th.assume_captured = true
	_check("one wind: the thrower's is main's, and it starts calm",
		wind != null and wind == _main.wind and wind.is_calm() and dials.wind == wind
		and dials.wind_readout() == "calm" and is_nan(dials.wind_arrow_angle())
		and th.wind_text() == "calm" and fx.streak_count() == 0)

	_tap(KEY_F)
	await process_frame
	var light: bool = wind.strength_name() == "light" and absf(wind.speed * MPH - 5.0) < 0.01
	_tap(KEY_F)
	await process_frame
	var breezy: bool = wind.strength_name() == "breezy"
	_tap(KEY_F, true)
	await process_frame
	_check("F: calm -> light -> breezy, Shift+F back to light",
		light and breezy and wind.strength_name() == "light")
	wind.set_from(270.0)
	_tap(KEY_Z)
	await process_frame
	var turned: bool = wind.from_deg == 315.0 and wind.from_name() == "north-west"
	_tap(KEY_Z, true)
	_tap(KEY_Z, true)
	await process_frame
	_check("Z turns it 45 deg clockwise, Shift+Z back the other way",
		turned and wind.from_deg == 225.0, "from %.0f" % wind.from_deg)

	# A steady 10 mph from the west, read off the dial while facing north,
	# then east.
	wind.set_gustiness(0.0)
	wind.set_from(270.0)
	wind.set_speed_mph(10.0)
	player.rotation.y = 0.0
	_main.get_node("Player/Head").rotation.x = 0.0
	for i in 3:
		await process_frame
	var north: String = dials.wind_readout()
	var north_arrow: float = dials.wind_arrow_angle()
	player.rotation.y = -PI / 2.0
	for i in 3:
		await process_frame
	var east: String = dials.wind_readout()
	var east_arrow: float = dials.wind_arrow_angle()
	_check("the dial reads it against your heading",
		north == "10 mph  L→R" and absf(angle_difference(north_arrow, 0.0)) < 0.02
		and east == "10 mph  tail" and absf(angle_difference(east_arrow, -PI / 2.0)) < 0.02,
		"facing north: \"%s\", arrow %.0f deg; facing east: \"%s\", arrow %.0f deg" % [
			north, rad_to_deg(north_arrow), east, rad_to_deg(east_arrow)])
	th.setup.toggle_units()
	var metric: String = dials.wind_readout()
	th.setup.toggle_units()
	_check("... in the unit the speed bar is in", metric == "4.5 m/s  tail", "\"%s\"" % metric)

	# The aim arc bends with it.
	player.rotation.y = 0.0
	_main.get_node("Player/Head").rotation.x = deg_to_rad(10.0)
	for i in 3:
		await process_frame
	th.aim_min = 1e9                       # plain view-pitch throws: no target to chase
	var with_wind: PackedVector3Array = th.aim_arc.simulate()
	wind.set_speed_mph(0.0)
	var still: PackedVector3Array = th.aim_arc.simulate()
	wind.set_speed_mph(10.0)
	var bend: float = with_wind[with_wind.size() - 1].x - still[still.size() - 1].x
	_check("the aim arc bends downwind", bend > 5.0, "%.1f m east of the calm arc" % bend)

	# Discs fly in it. Cubes do not carry it.
	var d = th.throw_disc(th.setup.params())
	var cube = th.throw_cube()
	_check("a thrown disc flies in the thrower's wind (a cube does not)",
		d.wind == wind and not ("wind" in cube))
	_check("the throw remembers its wind for the result line", th._throw_wind == "10 mph L→R",
		"\"%s\"" % th._throw_wind)

	# Looks: streaks in the air, clouds on the move.
	for i in 90:
		await process_frame
	var drift: Vector2 = clouds.drift
	_check("streaks drift round you and the clouds go with the wind",
		fx.streak_count() > 20 and drift.normalized().dot(Vector2(1, 0)) > 0.999
		and drift.length() > calm_drift.length() * 2.0,
		"%d streaks, clouds at %.1f m/s east" % [fx.streak_count(), drift.length()])
	wind.set_speed_mph(0.0)
	for i in 120:
		await process_frame
	_check("calm again: no streaks, clouds back on their own drift",
		fx.streak_count() == 0 and clouds.drift == calm_drift and dials.wind_readout() == "calm")
	_ran["world"] = true


## Minimal stand-in for terrain.gd: no trees, no lakes, no basket.
func _stub_terrain_script() -> GDScript:
	var s := GDScript.new()
	s.source_code = """extends Node3D
var block_size := 1.0
var lakes: Array = []
var baskets: Array = []
var flora := Flora.new()
func height_at(_x: float, _z: float) -> float:
	return 0.0
class Flora:
	func voxel_at(_c: Vector3i) -> int:
		return 0
"""
	s.reload()
	return s
