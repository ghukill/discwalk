extends SceneTree
## Headless disc-flight check, in two parts.
##
## 1. Lab: real FlyingDisc bodies thrown over a flat, empty floor (no trees,
##    no lakes), compared with reference flights from shotshaper itself
##    (numbers below, from tools/discs/shotshaper_reference.py). Carry and
##    drift must land within 10% / 4 m: if we change the maths, this catches it.
##    (Only meaningful for the shotshaper tables; our own tables will need
##    their own reference numbers.)
## 2. Character: overstable cd1 thrown flat must fade left, understable cd5
##    must turn right, a forehand must mirror a backhand, and more hyzer must
##    bend further left.
## 3. World: a throw from spawn in the generated world flies, lands and rests.
##
##   godot --headless --path . --script res://tools/flight_test.gd

const FLYING_DISC := preload("res://scripts/flying_disc.gd")
const DiscModel := preload("res://scripts/disc_model.gd")

## [disc, speed, spin, pitch, nose, roll] -> shotshaper [carry, drift left]
## (released 1.3 m up, flight ends when it gets back to y = 0).
const REFERENCE := [
	[["dd2", 24.2, 116.8, 15.5, 0.0, 14.7], [81.9, 4.1]],
	[["dd2", 24.0, 124.8, 10.0, 0.0, 0.0], [62.5, -19.9]],
	[["dd2", 20.0, 104.0, 10.0, 0.0, -15.0], [43.7, -13.1]],
	[["cd1", 20.0, 104.0, 10.0, 0.0, 0.0], [51.0, 11.6]],
	[["cd5", 20.0, 104.0, 10.0, 0.0, 0.0], [67.1, -8.5]],
	[["fd2", 22.0, 114.4, 8.0, 2.0, 5.0], [65.6, 18.4]],
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
	for hand in [1.0, -1.0]:
		for id in ["cd1", "cd5"]:
			_cases.append({"name": "%s_%s" % [id, "bh" if hand > 0 else "fh"],
				"args": [id, 20.0, 104.0, 10.0, 0.0, 0.0], "hand": hand})
	_cases.append({"name": "fd2_hyzer25", "args": ["fd2", 22.0, 114.4, 10.0, 0.0, 25.0], "hand": 1.0})
	_cases.append({"name": "fd2_flat", "args": ["fd2", 22.0, 114.4, 10.0, 0.0, 0.0], "hand": 1.0})
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
			continue
		if not d.flying:
			c.done = true
			c.carry = -d.global_position.z
			c.left = c.x0 - d.global_position.x
			c.t = d.flight_time
			c.landed_by = d.landed_by
	var lab_done := _cases.all(func(c) -> bool: return c.done)
	if lab_done and _main == null:
		_lab.queue_free()
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		_frames = 0
	if _main != null and _frames == 5:
		var thrower = _main.thrower
		var p := {"disc": _models["fd2"], "speed": 20.0, "pitch": 12.0, "nose": 0.0,
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
		if c.has("ref"):
			var good: bool = absf(c.carry - c.ref[0]) <= 0.1 * c.ref[0] and absf(c.left - c.ref[1]) <= 4.0
			line += "  shotshaper: carry=%5.1f left=%6.1f  %s" % [c.ref[0], c.ref[1], "ok" if good else "BAD"]
			ok = ok and good
		print(line)
	var checks := [
		["cd1 backhand fades left", by.cd1_bh.left > 3.0],
		["cd5 backhand turns right", by.cd5_bh.left < -3.0],
		["cd1 forehand mirrors backhand", absf(by.cd1_fh.left + by.cd1_bh.left) < 1.0],
		["cd5 forehand mirrors backhand", absf(by.cd5_fh.left + by.cd5_bh.left) < 1.0],
		# Hyzer also shortens the flight, so compare the bend as an angle.
		["more hyzer bends further left (angle)",
			by.fd2_hyzer25.left / by.fd2_hyzer25.carry > by.fd2_flat.left / by.fd2_flat.carry + 0.05],
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
	var expect_air := int(wd.flight_dist / paths.AIR_SPACING) if is_instance_valid(wd) else 0
	checks.append(["path: %d air cubes (expect ~%d), %d ground cubes, colour = disc colour" % [
		air, expect_air, ground],
		paths.count() == 1 and air >= expect_air * 0.9 and ground > 0 \
		and is_instance_valid(wd) and pd.color == wd.color])
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


## Minimal stand-in for terrain.gd: no trees, no lakes.
func _stub_terrain_script() -> GDScript:
	var s := GDScript.new()
	s.source_code = """extends Node3D
var block_size := 1.0
var lakes: Array = []
var flora := Flora.new()
func height_at(_x: float, _z: float) -> float:
	return 0.0
class Flora:
	func voxel_at(_c: Vector3i) -> int:
		return 0
"""
	s.reload()
	return s
