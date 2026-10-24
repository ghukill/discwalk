extends SceneTree
## Headless check of courses and Course Play (course.gd, course_round.gd):
##
##  course:   nine holes in order, Basket<n> is hole n, tees a hole's length
##            from their basket, painted, level, dry, clear of other baskets
##  tee:      Course Play starts on hole 1's tee facing down it, GOTO and
##            the shot circle on
##  stroke:   a disc counts, a cube doesn't
##  goto:     you're walked over (not put there), end up a step behind the
##            disc facing the basket (left / right and up / down), the disc
##            is picked up, circle on the lie; a move key skips the walk
##  on foot:  goto off, the lie gets a ring, no disc throw till you're in it
##            (circle on), stepping in picks the disc up; G on walks you there
##  circle:   walking can't take you past 1 m; off = free; on again = back
##            round the lie
##  basket:   another hole's basket doesn't finish the hole; this one does,
##            then "Walking to next hole...", walking toward the next tee,
##            and a move key skips you onto it (strokes back to 0)
##  overview: M flies the camera up over the hole and back
##  end:      holing the last hole ends the round
##  free:     Free Play turns it all off (goto walks you over facing down
##            the throw again)
##
##   godot --headless --path . --script res://tools/course_test.gd [-- --block-size=0.5]

const Course := preload("res://scripts/course.gd")

var _main: Node
var _t: Node3D
var _th
var _pl: CharacterBody3D
var _r
var _checks: Array = []


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _check(name: String, ok: bool, msg := "") -> void:
	_checks.append(ok)
	print("COURSE %-34s %s  %s" % [name, "ok" if ok else "BAD", msg])


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _run() -> void:
	await _frames(3)
	_t = _main.get_node("Terrain")
	_th = _main.thrower
	_pl = _main.get_node("Player")
	_r = _main.course_round
	_test_course()
	await _test_play()
	await _test_free()
	var ok := not _checks.has(false)
	print("COURSE %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)


func _test_course() -> void:
	var holes: Array = _t.holes
	_check("nine holes", holes.size() == 9, "%d" % holes.size())
	var order := true
	var lengths := true
	var painted := true
	var level := true
	var dry := true
	var clear := true
	var worst_rise := 0.0
	for i in holes.size():
		var h: Dictionary = holes[i]
		order = order and h.n == i + 1 and h.basket.name == "Basket%d" % (i + 1)
		lengths = lengths and h.length >= Course.LENGTH.x - 0.01 and h.length <= Course.LENGTH.y + 0.01
		var c: Vector3 = h.tee
		painted = painted and _t.painted(_t.col_x(c.x), _t.col_z(c.z))
		dry = dry and _t.lake_edge_distance(c.x, c.z) >= Course.LAKE_CLEAR
		var fwd := Vector3(-sin(h.pad_yaw), 0, -cos(h.pad_yaw))
		var hs: Array = []
		for v in [-1.4, 0.0, 1.4]:
			var p: Vector3 = c + fwd * v
			hs.append(_t.height_at(p.x, p.z))
		worst_rise = maxf(worst_rise, hs.max() - hs.min())
		for b in _t.baskets:
			clear = clear and _flat(b.global_position, c) >= Course.BASKET_CLEAR
		# Facing points within the jitter of the basket.
		var to_b: Vector3 = h.basket.global_position - c
		var off := absf(angle_difference(atan2(-to_b.x, -to_b.z), h.yaw))
		lengths = lengths and off <= deg_to_rad(Course.AIM_JITTER + 1.0)
	level = worst_rise <= Course.MAX_RISE
	_check("in order, Basket<n> = hole n", order)
	_check("lengths in range, facing basket", lengths)
	_check("tee pads painted", painted)
	_check("tee pads level", level, "worst rise %.2f m" % worst_rise)
	_check("tee pads dry", dry)
	_check("tee pads clear of baskets", clear)


## A controller button tap (press + release).
func _pad(button: JoyButton) -> void:
	for down in [true, false]:
		var ev := InputEventJoypadButton.new()
		ev.button_index = button
		ev.pressed = down
		Input.parse_input_event(ev)


func _disc_params() -> Dictionary:
	var p: Dictionary = _th.setup.params()
	p.speed = 12.0
	p.pitch = 8.0
	return p


## Waits until a throw has stopped (or ~20 s).
func _await_rest(d) -> bool:
	for i in 60 * 20:
		await physics_frame
		if not is_instance_valid(d) or d.resting:
			return is_instance_valid(d)
	return false


## Throw away from the basket (so test throws never hole out by accident).
func _turn_away(h: Dictionary) -> void:
	_pl.face(h.basket.global_position)
	_pl.rotation.y += PI
	_pl.get_node("Head").rotation.x = 0.0


## An action press + release, through the input queue like a real key.
func _tap(action: String) -> void:
	for down in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = down
		Input.parse_input_event(ev)


## Waits until the goto after the last throw has happened (or ~20 s).
func _await_goto(warps0: int) -> bool:
	for i in 60 * 20:
		await physics_frame
		if _th.warps > warps0:
			return true
	return false


func _test_play() -> void:
	_main.start_mode("course")
	await _frames(2)
	var h1: Dictionary = _t.holes[0]
	var on_tee := _flat(_pl.global_position, h1.tee) < 2.0
	var facing := absf(angle_difference(_pl.rotation.y, h1.yaw)) < 0.01
	_check("course play: on hole 1 tee", on_tee and facing and _r.state == "tee")
	_check("goto + circle on", _th.warp_on and _th.circle_on)

	# A cube is a toy, a disc is a stroke.
	_th.throw_cube(5.0)
	await _frames(2)
	_check("cube doesn't count", _r.strokes == 0)
	_th.clear()
	var warps0: int = _th.warps
	var d = _th.throw_disc(_disc_params())
	_check("disc counts", _r.strokes == 1 and _r.state == "playing")
	await _await_rest(d)
	await _frames(3)
	var p0 := _pl.global_position
	await _frames(30)
	var stepped := _flat(_pl.global_position, p0)
	_check("goto walks you over", _th.going() and _pl.walking and stepped > 1.5 and stepped < 5.0,
		"%.1f m in 0.5 s" % stepped)
	var went: bool = await _await_goto(warps0)
	await _frames(40)                   # the turn to the basket
	var bk: Vector3 = h1.basket.global_position
	var to_b := bk - _pl.global_position
	var yaw_ok := absf(angle_difference(_pl.rotation.y, atan2(-to_b.x, -to_b.z))) < 0.02
	var cam: Camera3D = _pl.get_node("Head/Camera3D")
	var look := -cam.global_transform.basis.z
	var want := (bk + Vector3(0, _r.AIM_HEIGHT, 0) - cam.global_position).normalized()
	_check("goto faces the basket", went and yaw_ok and look.dot(want) > 0.999,
		"look·want %.4f" % look.dot(want))
	_check("disc picked up", went and not is_instance_valid(d) or (is_instance_valid(d) and d.is_queued_for_deletion()))
	var lie: Vector3 = _th.lie()
	_check("circle on the lie", _th.has_lie() and _th.circle.visible and _flat(_pl.global_position, lie) <= 1.0,
		"%.2f m from the lie" % _flat(_pl.global_position, lie))

	# Walk forward for 2 s: held inside the circle.
	Input.action_press("move_forward")
	await _frames(120)
	var held: float = _flat(_pl.global_position, lie)
	_check("circle holds you", held <= 1.02, "%.2f m from the lie" % held)
	_th.set_circle(false)
	await _frames(90)
	var free: float = _flat(_pl.global_position, lie)
	_check("circle off: free", free > 3.0, "%.1f m" % free)
	Input.action_release("move_forward")
	_th.set_circle(true)
	await _frames(2)
	_check("circle on again: back round the lie", _flat(_pl.global_position, lie) <= 1.02)

	# A move key skips the walk: you're put there.
	_turn_away(h1)
	warps0 = _th.warps
	var d5 = _th.throw_disc(_disc_params())
	await _await_rest(d5)
	await _frames(10)
	var walking5: bool = _th.going()
	_tap("move_forward")
	await _frames(2)
	_check("move skips the goto walk", walking5 and _th.warps == warps0 + 1 and not _th.going()
		and _th.lie_reached() and _flat(_pl.global_position, _th.lie()) <= 1.0)
	await _frames(5)

	# Goto off: walk there yourself.
	_th.set_warp(false)
	_turn_away(h1)
	var n_discs: int = _th.discs.size()
	var d6 = _th.throw_disc(_disc_params())
	await _await_rest(d6)
	await _frames(3)
	var lie6: Vector3 = _th.lie()
	_check("goto off: lie marked", _th.has_lie() and not _th.lie_reached() and _th.marker.visible
		and not _th.circle.visible and _pl.tether_radius == 0.0 and _flat(lie6, d6.global_position) < 0.1,
		"lie %s reached %s marker %s circle %s tether %.1f off %.2f m splashed %s" % [_th.has_lie(), _th.lie_reached(),
		_th.marker.visible, _th.circle.visible, _pl.tether_radius, _flat(lie6, d6.global_position), d6.splashed])
	var s6: int = _r.strokes
	_tap("throw_disc")
	await _frames(3)
	_check("no throw till you're there", _r.strokes == s6 and _th.discs.size() == n_discs + 1)
	var to6 := lie6 - _pl.global_position
	to6.y = 0.0
	_pl.respawn(lie6 - to6.normalized() * 3.0)
	_pl.face(lie6 + Vector3(0, 1.6, 0))
	Input.action_press("move_forward")
	var in6 := false
	for i in 120:
		await physics_frame
		if _th.lie_reached():
			in6 = true
			break
	Input.action_release("move_forward")
	await _frames(30)
	var gone6: bool = not is_instance_valid(d6) or d6.is_queued_for_deletion()
	_check("walk in: picked up, held", in6 and gone6 and _th.circle.visible and not _th.marker.visible
		and _flat(_pl.global_position, lie6) <= 1.02)

	# ...and G on with your disc out there walks you to it.
	_turn_away(h1)
	var d7 = _th.throw_disc(_disc_params())
	await _await_rest(d7)
	await _frames(3)
	warps0 = _th.warps
	_th.set_warp(true)
	var going7: bool = _th.going()
	went = await _await_goto(warps0)
	_check("G on: walks you to it", going7 and went and _th.lie_reached()
		and (not is_instance_valid(d7) or d7.is_queued_for_deletion()))
	await _frames(40)

	# Overview: the camera goes up, then comes back.
	_r.set_overview(true)
	await _frames(int(60 * (_r.OVERVIEW_TIME + 0.3)))
	var ov: Camera3D = _r._ov_cam
	var up: bool = ov.current and ov.global_position.y > _pl.global_position.y + 25.0 and _pl.frozen
	_check("overview flies up", up, "camera %.0f m above you" % (ov.global_position.y - _pl.global_position.y))
	_r.set_overview(false)
	await _frames(int(60 * (_r.OVERVIEW_TIME + 0.3)))
	_check("overview flies back", cam.current and not _pl.frozen and not _th.locked)

	# Controller: LB + B is the overview (not a throw), LB + Y the circle (not launch).
	Input.action_press("setup_disc")
	var n0: int = _th.discs.size()
	_pad(JOY_BUTTON_B)
	await _frames(2)
	_check("pad LB + B: overview, no throw", _r.view == "hole" and _th.discs.size() == n0)
	_pad(JOY_BUTTON_B)
	await _frames(2)
	_check("pad LB + B again: course map", _r.view == "map" and _r._map_marks != null
		and _r._map_marks.get_child_count() == 3 * _t.holes.size() + 1)
	_pad(JOY_BUTTON_B)
	await _frames(int(60 * (_r.MAP_TIME + 0.3)))
	_check("pad LB + B a third time: back down", not _r.overview and _r._map_marks == null
		and cam.current and not _pl.frozen and not _th.locked)
	var c0: bool = _th.circle_on
	_pad(JOY_BUTTON_Y)
	await _frames(2)
	_check("pad LB + Y: shot circle", _th.circle_on != c0 and not _r.overview)
	_pad(JOY_BUTTON_Y)
	Input.action_release("setup_disc")
	await _frames(2)

	# Another hole's basket: just for fun.
	var d2 = _th.throw_disc(_disc_params())
	var s0: int = _r.strokes
	_th._on_basket_hit(d2, _t.holes[4].basket, "chains")
	await _frames(2)
	_check("other basket doesn't finish", _r.state == "playing" and _r.hole == 0 and _r.strokes == s0)
	_th.clear()

	# This hole's basket: hole out, walk, skip.
	var d3 = _th.throw_disc(_disc_params())
	var strokes: int = _r.strokes
	_th._on_basket_hit(d3, h1.basket, "chains")
	await _frames(2)
	_check("holed out", _r.state == "holed" and _r.scores == [strokes] and _th.locked)
	await _frames(int(60 * (_r.OUT_PAUSE + 0.4)))
	var tee2: Vector3 = _r.tee_spot(_t.holes[1])
	var gap0 := _flat(_pl.global_position, tee2)
	_check("walking to next hole", _r.state == "walking" and _pl.walking
		and _main.get_node("HUD/Banner").text == "Walking to next hole...")
	await _frames(180)
	var gap1 := _flat(_pl.global_position, tee2)
	_check("...and getting there", gap1 < gap0 - 5.0, "%.0f m -> %.0f m" % [gap0, gap1])
	var ev := InputEventAction.new()
	ev.action = "move_forward"
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(3)
	var ev_up := InputEventAction.new()
	ev_up.action = "move_forward"
	ev_up.pressed = false
	Input.parse_input_event(ev_up)
	_check("move skips onto hole 2 tee", _r.hole == 1 and _r.state == "tee" and _r.strokes == 0
		and _flat(_pl.global_position, tee2) < 1.0 and not _th.locked)

	# Jump to the last hole and hole it: round over.
	_r._to_tee(_t.holes.size() - 1)
	var d4 = _th.throw_disc(_disc_params())
	_th._on_basket_hit(d4, _t.holes[-1].basket, "chains")
	await _frames(int(60 * (_r.OUT_PAUSE + 0.4)))
	_check("last hole ends the round", _r.state == "done" and not _th.locked and _r.goto_aim() == null)


func _test_free() -> void:
	_main.start_mode("free")
	await _frames(2)
	_check("free play: rules off", not _r.active and not _th.warp_on and not _th.circle_on
		and _th.course_round == null)
	_th.set_warp(true)
	var warps0: int = _th.warps
	var d = _th.throw_disc(_disc_params())
	var went: bool = await _await_goto(warps0)
	await _frames(40)                   # the turn down the throw
	var faced := false
	if went and is_instance_valid(d):
		var dir := Vector3(d.global_position.x - d.start.x, 0, d.global_position.z - d.start.z).normalized()
		faced = absf(angle_difference(_pl.rotation.y, atan2(-dir.x, -dir.z))) < 0.02
	_check("free goto faces down the throw", went and faced and is_instance_valid(d))
	_th.set_warp(false)
