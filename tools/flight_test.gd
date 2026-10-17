extends SceneTree
## Headless disc-flight check, in three parts.
##
## 1. Lab: real FlyingDisc bodies thrown over a flat, empty floor (no trees,
##    no lakes), compared with a full 6-DOF integration of Hummel's equations,
##    wobble and all (tools/discs/hummel_reference.py), within 5% carry and
##    2.5 m drift. That checks the game's quasi-steady shortcut and catches any
##    change to the maths or the disc tables (rerun the script if you change
##    them on purpose).
## 2. Character: each disc behaves like the real disc its data comes from
##    (docs/PHYSICS.md): the overstable Erratic fades even thrown anhyzer, the
##    understable Till turns over flat, the Moraine hyzer-flips long, the
##    Kettle putter flies short and straight at putting speed, a forehand
##    mirrors a backhand, more hyzer bends further left, spin bleeds off.
## 3. World: a throw from spawn in the generated world flies, lands and rests.
##
##   godot --headless --path . --script res://tools/flight_test.gd

const FLYING_DISC := preload("res://scripts/flying_disc.gd")
const DiscModel := preload("res://scripts/disc_model.gd")

## [disc, speed, spin, pitch, nose, roll] -> full 6-DOF Hummel [carry, drift left]
## (released 1.3 m up, flight ends when it gets back to y = 0; RH backhand).
## From tools/discs/hummel_reference.py.
const REFERENCE := [
	[["moraine", 24.0, 124.8, 10.0, 0.0, 10.0], [93.9, -4.2]],   # spin 125 -> 105
	[["moraine", 24.0, 124.8, 10.0, 0.0, 0.0], [72.0, -19.8]],   # spin 125 -> 106
	[["erratic", 24.0, 124.8, 10.0, 0.0, 0.0], [60.5, 12.5]],   # spin 125 -> 110
	[["till", 23.0, 119.6, 10.0, 0.0, 25.0], [69.0, -3.6]],   # spin 120 -> 105
	[["outwash", 23.0, 119.6, 10.0, 0.0, 15.0], [86.0, -6.5]],   # spin 120 -> 102
	[["esker", 19.0, 98.8, 10.0, 0.0, 10.0], [52.8, -6.1]],   # spin 99 -> 91
	[["drumlin", 19.0, 98.8, 10.0, 0.0, 10.0], [48.1, 7.5]],   # spin 99 -> 92
	[["kettle", 16.0, 83.2, 10.0, 0.0, 0.0], [36.9, -3.1]],   # spin 83 -> 79
]

var _models := {}
var _lab: Node3D
var _cases: Array = []               # {name, disc, ref?, check?}
var _frames := 0
var _main: Node
var _world_disc: Node
var _follow_seen := 0                # frames the follow cam was live + near the disc
var _follow_far := 0.0               # worst cam-to-disc distance while following
var _rest_frame := -1
var _warp_waiting := false


func _initialize() -> void:
	for m in DiscModel.load_all():
		_models[m.id] = m
	_lab = Node3D.new()
	root.add_child(_lab)
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6000, 1, 1000)
	cs.shape = box
	cs.position = Vector3(1500, -0.5, 0)
	floor_body.add_child(cs)
	_lab.add_child(floor_body)
	var stub := Node3D.new()
	stub.set_script(_stub_terrain_script())
	_lab.add_child(stub)

	# Lab throws go along -Z; "left" is -X.
	for i in REFERENCE.size():
		var r: Array = REFERENCE[i]
		_cases.append({"name": "ref%d_%s" % [i, r[0][0]], "args": r[0], "ref": r[1], "hand": 1.0})
	# [name, disc, speed, pitch, nose, roll, hand]; spin = auto (5.2 x speed)
	for c in [
			["moraine_bh", "moraine", 24.0, 10.0, 0.0, 0.0, 1.0],
			["moraine_fh", "moraine", 24.0, 10.0, 0.0, 0.0, -1.0],
			["erratic_anhyzer", "erratic", 24.0, 10.0, 0.0, -10.0, 1.0],
			["till_flat", "till", 23.0, 10.0, 0.0, 0.0, 1.0],
			["outwash_flat", "outwash", 23.0, 10.0, 0.0, 0.0, 1.0],
			["outwash_hyzer20", "outwash", 23.0, 10.0, 0.0, 20.0, 1.0],
			["kettle_24", "kettle", 24.0, 10.0, 0.0, 10.0, 1.0]]:
		_cases.append({"name": c[0], "args": [c[1], c[2], DiscModel.auto_spin(c[2]), c[3], c[4], c[5]],
			"hand": c[6]})
	for i in _cases.size():
		var c: Dictionary = _cases[i]
		var a: Array = c.args
		var d: RigidBody3D = RigidBody3D.new()
		d.set_script(FLYING_DISC)
		d.terrain = stub
		d.model = _models[a[0]]
		_lab.add_child(d)
		# Spread the throws sideways so they never meet.
		var origin := Vector3(i * 200.0, 1.3, 0)
		var ls := DiscModel.launch_state(Vector3.FORWARD, a[1], a[3], a[4], a[5], c.hand)
		d.launch_disc(origin, ls[0], ls[1], a[2], c.hand)
		# No collision between lab discs.
		d.collision_layer = 2
		d.collision_mask = 1
		c.disc = d
		c.x0 = origin.x
		c.done = false


func _process(_delta: float) -> bool:
	_frames += 1
	for c in _cases:
		if c.done:
			continue
		var d = c.disc
		if not is_instance_valid(d):
			c.done = true
			c.carry = 0.0
			c.left = 0.0
			c.t = 0.0
			c.landed_by = "lost"
			c.omega = 0.0
			continue
		if not d.flying:
			c.done = true
			c.carry = -d.global_position.z
			c.left = c.x0 - d.global_position.x
			c.t = d.flight_time
			c.landed_by = d.landed_by
			c.omega = d.omega
	var lab_done := _cases.all(func(c) -> bool: return c.done)
	if lab_done and _main == null:
		_lab.queue_free()
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		_frames = 0
	if _main != null and _frames == 5:
		var thrower = _main.thrower
		thrower.goto_walk = false                  # put there at once (the check is the camera)
		var p := {"disc": _models["outwash"], "speed": 20.0, "pitch": 12.0, "nose": 0.0,
			"roll": 10.0, "spin": DiscModel.auto_spin(20.0)}
		_world_disc = thrower.throw_disc(p)
		thrower.set_view(true)                     # V lamp on mid-flight
	if _main != null and _frames == 8:
		_main.thrower.set_warp(true)               # Z lamp on while it's flying
	if _main != null and _frames == 12:              # flag is up while it flies
		_warp_waiting = _main.thrower.warp_pending() and _main.thrower.lamps.pulse_warp
	if _main != null and _frames > 20 and is_instance_valid(_world_disc) \
			and not _world_disc.resting and _main.thrower.follow_cam.active():
		var fc: Camera3D = _main.thrower.follow_cam
		_follow_far = maxf(_follow_far, fc.global_position.distance_to(_world_disc.global_position))
		if fc.current:
			_follow_seen += 1
	if _main != null and _frames > 5 and _rest_frame < 0 \
			and (_frames > 60 * 30 or _world_disc.resting):
		_rest_frame = _frames
	if _rest_frame > 0 and _frames >= _rest_frame + 3:   # let the cam hand back
		_report()
		return true
	if _frames > 60 * 60:
		print("FLIGHT FAIL (timeout)")
		quit(1)
		return true
	return false


func _report() -> void:
	var ok := true
	var by := {}
	for c in _cases:
		by[c.name] = c
		var line := "FLIGHT %-12s carry=%5.1f m  left=%6.1f m  t=%.2f s  (%s)" % [
			c.name, c.carry, c.left, c.t, c.landed_by]
		line += "  spin %3.0f -> %3.0f" % [c.args[2], c.omega]
		if c.has("ref"):
			var good: bool = absf(c.carry - c.ref[0]) <= 0.05 * c.ref[0] and absf(c.left - c.ref[1]) <= 2.5
			line += "  6-DOF: carry=%5.1f left=%6.1f  %s" % [c.ref[0], c.ref[1], "ok" if good else "BAD"]
			ok = ok and good
		print(line)
	var checks := [
		["Erratic (overstable) fades left even thrown 10 deg anhyzer (%.1f m)" % by.erratic_anhyzer.left,
			by.erratic_anhyzer.left > 0.0],
		["Till (understable) turns over thrown flat at 23 m/s (%.1f m)" % by.till_flat.left,
			by.till_flat.left < -5.0],
		["Moraine hyzer-flips long: 10 deg hyzer at 24 m/s carries %.1f m, ends %.1f m off line" % [
			by.ref0_moraine.carry, by.ref0_moraine.left],
			by.ref0_moraine.carry > 85.0 and absf(by.ref0_moraine.left) < 10.0],
		["Kettle putter at 16 m/s: short and straight (%.1f m, %.1f m off line)" % [
			by.ref7_kettle.carry, by.ref7_kettle.left],
			by.ref7_kettle.carry > 30.0 and by.ref7_kettle.carry < 45.0 and absf(by.ref7_kettle.left) < 6.0],
		["a driver out-carries the putter at 24 m/s (%.1f vs %.1f m)" % [by.ref0_moraine.carry, by.kettle_24.carry],
			by.ref0_moraine.carry > by.kettle_24.carry + 15.0],
		["forehand mirrors backhand", absf(by.moraine_fh.left + by.moraine_bh.left) < 1.0],
		# Hyzer also shortens the flight, so compare the bend as an angle.
		["more hyzer bends further left (angle)",
			by.outwash_hyzer20.left / by.outwash_hyzer20.carry > by.outwash_flat.left / by.outwash_flat.carry + 0.05],
		# Hummel spin down: ~15% over a long flight (~1-7 %/s, faster when fast).
		["spin bleeds off in flight (Moraine 125 -> %.0f rad/s)" % by.moraine_bh.omega,
			by.moraine_bh.omega < 0.95 * 124.8 and by.moraine_bh.omega > 0.75 * 124.8],
	]
	var wd = _world_disc
	var world_ok: bool = is_instance_valid(wd) and wd.resting and wd.flight_dist > 15.0
	if is_instance_valid(wd):
		checks.append(["world throw flies, lands, rests (carry %.1f m, rest %.1f m, landed on %s)" % [
			wd.flight_dist, wd.distance(), wd.landed_by], world_ok])
	else:
		checks.append(["world throw exists", false])
	var fc: Camera3D = _main.thrower.follow_cam
	var back_home: bool = not fc.active() and _main.get_node("Player/Head/Camera3D").current
	var paths = _main.thrower.paths
	var pd: Dictionary = paths._paths[0] if paths.count() > 0 else {}
	var air: int = pd.get("air", 0)
	var ground: int = pd.get("ground", 0)
	var expect_air := int((wd.flight_dist - paths.START_GAP) / paths.AIR_SPACING) if is_instance_valid(wd) else 0
	checks.append(["path: %d air cubes (expect ~%d), %d ground cubes, colour = disc colour" % [
		air, expect_air, ground],
		paths.count() == 1 and air >= expect_air * 0.9 and ground > 0 \
		and is_instance_valid(wd) and pd.color == wd.color])
	var first_gap := 1e9
	if pd.has("points") and not pd.points.is_empty():
		first_gap = pd.points[0].distance_to(pd.start)
	checks.append(["path starts near the throw (first cube %.2f m)" % first_gap,
		first_gap >= paths.START_GAP and first_gap <= 1.25])
	_main.thrower.set_view(false)                       # the rest of these throws:
	_main.thrower.set_warp(false)                       # no camera, no warping
	var block = _main.thrower.throw(5)
	checks.append(["blocks leave no path", paths.count() == 1 and is_instance_valid(block)])
	var th = _main.thrower
	th.set_paths(false)                                 # P: off
	var falling: int = paths.fading()
	for i in 200:                                       # 10 s of falling, 20 fps
		paths._process(0.05)
	checks.append(["P off: %d cubes fall + poof, then gone (%d left)" % [falling, paths.fading()],
		paths.count() == 0 and falling == air + ground and paths.fading() == 0 \
		])
	th.throw_disc(th.setup.params())
	checks.append(["paths off: a new throw leaves no path", paths.count() == 0])
	th.set_paths(true)                                  # P again
	th.throw_disc(th.setup.params())
	checks.append(["paths back on (P): next throw leaves a path",
		th.paths_on and paths.count() == 1])
	var pl: Node3D = _main.get_node("Player")
	var gap := Vector2(pl.global_position.x - wd.global_position.x, pl.global_position.z - wd.global_position.z).length() if is_instance_valid(wd) else 1e9
	checks.append(["goto (G on mid-flight): waits (lamp breathing), then lands you %.1f m from the rested disc" % gap,
		_warp_waiting and not _main.thrower.warp_pending() and gap < 2.5])
	# Launch angle = where you look (no pitch in the params, no offset).
	var head: Node3D = _main.get_node("Player/Head")
	var angles := []
	for look in [12.0, -5.0, 30.0]:
		head.rotation.x = deg_to_rad(look)
		var d = th.throw_disc(th.setup.params())
		var v: Vector3 = d.linear_velocity - _main.get_node("Player").velocity * Vector3(1, 0, 1)
		angles.append(rad_to_deg(atan2(v.y, Vector2(v.x, v.z).length())))
	head.rotation.x = 0.0
	checks.append(["launch angle = view (12, -5, 30 -> %.1f, %.1f, %.1f)" % angles,
		absf(angles[0] - 12.0) < 0.5 and absf(angles[1] + 5.0) < 0.5 and absf(angles[2] - 30.0) < 0.5])
	checks.append(["view (V on mid-flight) chases the disc (%d frames, max %.1f m away), hands back at rest" % [
		_follow_seen, _follow_far], _follow_seen > 60 and _follow_far < 8.0 and back_home])
	for ch in checks:
		print("FLIGHT check %-70s %s" % [ch[0], "ok" if ch[1] else "BAD"])
		ok = ok and ch[1]
	print("FLIGHT " + ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)


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
