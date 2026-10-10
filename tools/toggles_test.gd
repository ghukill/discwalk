extends SceneTree
## Headless check of the VIEW (V) / WARP (Z) toggles and LAUNCH (L), run as a
## string of little scenes, each throwing an orange block from spawn:
##
##  1 view only:  camera chases the throw, you never move, view hands back.
##  2 warp only:  camera stays with you, you end up at the throw.
##  3 both:       chase, then you end up there.
##  4 launch:     both on, L mid-flight: camera let go, you take on the
##                throw's velocity, and no warp at the end.
##  5 L too late: once the throw has stopped, L does nothing.
##  6 L rolling:  a disc skipping/rolling (not flying any more) still counts.
##  7 off mid-flight: V off snaps back now, Z off cancels the warp.
##  8 latest only: a second throw takes over view + warp from the first.
##  9 collect:    C with both on: no camera, no warp.
## Plus: the lamps follow the toggles, and P puts the beams out with the paths.
##
##   godot --headless --path . --script res://tools/toggles_test.gd [-- --block-size=0.5]

var _main: Node
var _th
var _pl: CharacterBody3D
var _cam: Camera3D
var _f := 0                       # frames into the current scene
var _scene := 0
var _d: Node
var _d2: Node
var _home := Vector3.ZERO
var _seen_follow := 0
var _note := {}
var _checks: Array = []
var _fd2


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _check(name: String, ok: bool) -> void:
	_checks.append([name, ok])


func _reset() -> void:
	_th.clear()
	_th.set_view(false)
	_th.set_warp(false)
	_pl.respawn(_home)
	_pl.rotation.y = 0.0
	_pl.get_node("Head").rotation.x = deg_to_rad(20)
	_f = 0
	_seen_follow = 0
	_note = {"warps0": _th.warps}


## A lob from spawn: up 20 degrees at power 5 (20 m/s).
func _lob() -> Node:
	return _th.throw(5)


func _process(_dt: float) -> bool:
	if _th == null:
		_th = _main.thrower
		_pl = _main.get_node("Player")
		_cam = _main.get_node("Player/Head/Camera3D")
		_home = _main.terrain.spawn_point()
		for m in _th.disc_models:
			if m.id == "fd2":
				_fd2 = m
		_scene = 1
		_reset()
		var lamps0: bool = _th.lamps.glow("view") == 0.0 and _th.lamps.glow("warp") == 0.0 \
			and _th.lamps.glow("path") == 1.0
		_check("start: VIEW + WARP off, PATH on (lamps agree)",
			not _th.view_on and not _th.warp_on and _th.paths_on and lamps0)
		return false
	_f += 1
	if _th.follow_cam.active():
		_seen_follow += 1
	var moved := _flat(_pl.global_position - _home)
	match _scene:
		1:  # view only
			if _f == 2:
				_th.set_view(true)
				_d = _lob()
			if _f > 3 and _d.resting and not _th.follow_cam.active():
				_check("1 view only: chased %d frames, you stayed put (%.1f m), view back" % [_seen_follow, moved],
					_seen_follow > 30 and moved < 0.5 and _cam.current and _th.warps == _note.warps0)
				_next()
		2:  # warp only
			if _f == 2:
				_th.set_warp(true)
				_d = _lob()
			if _f > 3 and _d.resting and _f > _note.get("rest", 1e9) + 2:
				var gap := _flat(_pl.global_position - _d.global_position)
				_check("2 warp only: no chase (%d), you ended %.1f m from the throw" % [_seen_follow, gap],
					_seen_follow == 0 and gap < 2.5 and _th.warps == _note.warps0 + 1)
				_next()
			elif _f > 3 and _d.resting and not _note.has("rest"):
				_note.rest = _f
		3:  # both
			if _f == 2:
				_th.set_view(true)
				_th.set_warp(true)
				_d = _lob()
			if _f == 30:
				_note.armed = _th.warp_pending() and _th.lamps.pulse_warp
			if _f > 3 and _d.resting and not _note.has("rest"):
				_note.rest = _f
			if _note.has("rest") and _f > _note.rest + 2:
				var gap := _flat(_pl.global_position - _d.global_position)
				_check("3 view + warp: chased %d frames, warp lamp breathing, then there (%.1f m)" % [_seen_follow, gap],
					_seen_follow > 30 and _note.armed and gap < 2.5 and _cam.current \
					and _th.warps == _note.warps0 + 1 and not _th.lamps.pulse_warp)
				_next()
		4:  # launch overrides
			if _f == 2:
				_th.set_view(true)
				_th.set_warp(true)
				_d = _lob()
			if _f == 20:
				var v0: Vector3 = _d.linear_velocity
				var ok: bool = _th.launch_self()
				_note.launch = ok and _pl.velocity.distance_to(v0) < 0.5 \
					and (_pl.global_position + Vector3(0, 1.6, 0)).distance_to(_d.global_position) < 0.6 \
					and not _th.follow_cam.active() and _cam.current and not _th.warp_pending()
				_note.after = _seen_follow
			if _f > 20 and _d.resting and not _note.has("rest"):
				_note.rest = _f
			if _note.has("rest") and _f > _note.rest + 5:
				_check("4 launch (L) mid-flight: your velocity = the throw's, camera let go, no warp after",
					_note.launch and _seen_follow == _note.after and _th.warps == _note.warps0 \
					and _th.view_on and _th.warp_on)
				_next()
		5:  # L too late
			if _f == 2:
				_d = _lob()
			if _f > 3 and _d.resting:
				var before := _pl.global_position
				var ok: bool = _th.launch_self()
				_check("5 L after the throw stopped does nothing",
					not ok and _pl.global_position.distance_to(before) < 0.01 and not _pl._flung)
				_next()
		6:  # L during ground play (a real disc, skidding after landing)
			if _f == 2:
				_d = _th.throw_disc({"disc": _fd2, "speed": 22.0, "pitch": 8.0, "nose": 0.0,
					"roll": 0.0, "spin": 110.0})
			if _f > 3 and not _d.flying and not _d.resting and _d.linear_velocity.length() > 1.0:
				var ok: bool = _th.launch_self()
				_check("6 L while the disc skids/rolls (not flying) still launches you",
					ok and _pl._flung and _pl.velocity.length() > 1.0)
				_next()
			elif _f > 60 * 20:
				_check("6 L while rolling: never caught it rolling", false)
				_next()
		7:  # toggles off mid-flight
			if _f == 2:
				_th.set_view(true)
				_th.set_warp(true)
				_d = _lob()
			if _f == 15:
				_th.set_view(false)
				_note.v_off = not _th.follow_cam.active() and _cam.current
			if _f == 20:
				_th.set_warp(false)
				_note.z_off = not _th.warp_pending()
			if _f == 25:
				_th.set_view(true)              # back on mid-flight: picks the throw up again
				_note.v_on = _th.follow_cam.active()
				_th.set_view(false)
			if _f > 25 and _d.resting:
				_check("7 off mid-flight: V off -> back to you, Z off -> no warp; V on again -> chase",
					_note.v_off and _note.z_off and _note.v_on and _th.warps == _note.warps0 and moved < 0.5)
				_next()
		8:  # latest throw takes over
			if _f == 2:
				_th.set_view(true)
				_th.set_warp(true)
				_d = _lob()
			if _f == 10:
				_pl.rotation.y = deg_to_rad(90)
				_d2 = _lob()
				_note.switched = _th.follow_cam.target == _d2 and _th._warp_target == _d2
			if _f > 10 and _d.resting and _d2.resting and not _note.has("rest"):
				_note.rest = _f
			if _note.has("rest") and _f > _note.rest + 2:
				var gap := _flat(_pl.global_position - _d2.global_position)
				_check("8 latest throw only: view + warp move to throw 2 (%.1f m from it, %d warp)" % [gap, _th.warps - _note.warps0],
					_note.switched and gap < 2.5 and _th.warps == _note.warps0 + 1)
				_next()
		9:  # collect ignores toggles
			if _f == 2:
				_d = _lob()                      # toggles off: just let it land
			if _f > 3 and _d.resting and not _note.has("c"):
				_th.set_view(true)
				_th.set_warp(true)
				_th.collect()
				_note.c = _f
				_seen_follow = 0
			if _note.has("c") and _f == _note.c + 120:
				_check("9 collect with VIEW + WARP on: no chase, no warp, you stay put",
					_seen_follow == 0 and _th.warps == _note.warps0 and moved < 0.5)
				_next()
		10: # P = paths + beams, lamps agree
			if _f == 2:
				_d = _lob()
			if _f > 3 and _d.resting:
				_th.set_paths(false)
				var beam_off: bool = _d._beacon != null and not _d._beacon.visible
				_th.set_view(true)
				for i in 120:
					_th.lamps._process(1.0 / 60.0)
				var lamps: bool = _th.lamps.glow("path") == 0.0 and _th.lamps.glow("view") == 1.0
				_th.set_paths(true)
				var beam_on: bool = _d._beacon.visible
				_check("10 P: beams out with the paths, back on with them; lamps follow",
					beam_off and beam_on and lamps and _th.panel._paths.button_pressed)
				_report()
				return true
	if _f > 60 * 40:
		_check("scene %d timed out" % _scene, false)
		_next()
	return false


func _next() -> void:
	_scene += 1
	_reset()


func _report() -> void:
	var ok := true
	for c in _checks:
		print("TOGGLES %-90s %s" % [c[0], "ok" if c[1] else "BAD"])
		ok = ok and c[1]
	print("TOGGLES " + ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)


static func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()
