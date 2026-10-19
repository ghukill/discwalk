extends SceneTree
## Headless check of the throw setup keys and HUD (docs/THROW-HUD.md):
## arrows tilt, Shift+arrows set speed/spin, X locks spin, R resets, H flips
## the hand, E / Q cycle discs, settings carry over between throws,
## Enter / left click throw a disc, right click throws a cube at the same
## speed, U hides the HUD, and the arrows no longer walk.
##
##   godot --headless --path . --script res://tools/hud_test.gd [-- --block-size=1]

var _main: Node
var _f := 0
var _checks: Array = []


func _initialize() -> void:
	Engine.max_fps = 60                  # held keys repeat in real time
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _key(k: Key, shift := false, pressed := true) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.shift_pressed = shift
	e.pressed = pressed
	Input.parse_input_event(e)


func _tap(k: Key, shift := false) -> void:
	_key(k, shift, true)
	Input.flush_buffered_events()
	_key(k, shift, false)
	Input.flush_buffered_events()


func _click(button: MouseButton) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = true
	Input.parse_input_event(e)
	Input.flush_buffered_events()
	var u := e.duplicate()
	u.pressed = false
	Input.parse_input_event(u)
	Input.flush_buffered_events()


func _check(name: String, ok: bool) -> void:
	_checks.append([name, ok])


func _process(_d: float) -> bool:
	_f += 1
	if _f < 5:
		return false
	var th = _main.thrower
	th.assume_captured = true            # headless: no real mouse capture
	th.goto_walk = false
	var s = th.setup
	var pl: CharacterBody3D = _main.get_node("Player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _f in [6, 7, 9, 10, 12, 13, 15, 16, 18, 19]:
		return false
	if _f == 5:
		_check("starts: moraine, flat, %.0f mph, spin locked, backhand" % s.speed_mph(),
			s.disc().id == "moraine" and s.nose == 0.0 and s.roll == 0.0
			and roundf(s.speed_mph()) == 54.0 and s.spin_locked and s.hand == 1.0)
		# Arrows: polled in throw_setup._process, so hold one frame each.
		_key(KEY_UP)
		return false
	if _f == 8:
		_key(KEY_UP, false, false)
		_key(KEY_LEFT)
		return false
	if _f == 11:
		_key(KEY_LEFT, false, false)
		_check("↑ nose +0.5 (%.1f), ← hyzer +1 for a backhand (%.0f)" % [s.nose, s.roll], s.nose == 0.5 and s.roll == 1.0)
		_key(KEY_SHIFT)
		_key(KEY_UP, true)
		return false
	if _f == 14:
		_key(KEY_UP, true, false)
		_key(KEY_RIGHT, true)
		return false
	if _f == 17:
		_key(KEY_RIGHT, true, false)
		_key(KEY_SHIFT, false, false)
		# One step is 1 mph now, and spin tracks the m/s underneath it.
		_check("Shift+↑ speed +1 mph (%.0f), spin follows while locked (%.1f); Shift+→ ignored while locked" % [
			s.speed_mph(), s.spin],
			is_equal_approx(s.speed_mph(), 55.0) and is_equal_approx(s.spin, 5.2 * s.speed))
		_tap(KEY_X)
		_key(KEY_SHIFT)
		_key(KEY_RIGHT, true)
		return false
	if _f == 20:
		_key(KEY_RIGHT, true, false)
		_key(KEY_SHIFT, false, false)
		_check("X unlocks, Shift+→ spin up a step (%.1f)" % s.spin,
			not s.spin_locked and s.spin > 5.2 * s.speed and s.spin <= 5.2 * s.speed + 3.0)
		# Hold ↓ for 1.5 s: repeats and ramps.
		_key(KEY_DOWN)
		return false
	if _f > 20 and _f < 110:
		return false
	if _f == 110:
		_key(KEY_DOWN, false, false)
		_check("holding ↓ repeats down to the -10° stop (%.1f)" % s.nose, s.nose == -10.0)
		var p0 := pl.global_position
		_key(KEY_UP)
		set_meta("p0", p0)
		return false
	if _f > 110 and _f < 130:
		return false
	if _f == 130:
		_key(KEY_UP, false, false)
		var p0: Vector3 = get_meta("p0")
		var moved := Vector2(pl.global_position.x - p0.x, pl.global_position.z - p0.z).length()
		_check("arrows don't walk any more (moved %.2f m)" % moved, moved < 0.05)
		_tap(KEY_R)
		_check("R resets to flat", s.nose == 0.0 and s.roll == 0.0 and not s.spin_locked)
		_tap(KEY_H)
		_check("H: forehand", s.hand == -1.0)
		_check_nose_cue()
		# I switches the readout only: the stored m/s must not budge, and the
		# arrow step must follow the unit on screen.
		var ms0: float = s.speed
		var mph_txt: String = s.speed_str(s.speed) + " " + s.unit_name()
		_tap(KEY_I)
		var metric: String = s.speed_str(s.speed) + " " + s.unit_name()
		_check("I switches mph -> m/s without changing the throw (%s -> %s)" % [
			mph_txt, metric],
			not s.mph and s.unit_name() == "m/s" and is_equal_approx(s.speed, ms0)
			and is_equal_approx(s.range_of("speed")[2], s.SPEED_STEP_MS))
		_tap(KEY_I)
		_check("I switches back to mph (%s)" % (s.speed_str(s.speed) + " " + s.unit_name()),
			s.mph and s.unit_name() == "mph" and is_equal_approx(s.speed, ms0)
			and is_equal_approx(s.range_of("speed")[2], s.SPEED_STEP_MPH / s.MPH_PER_MS))
		_key(KEY_LEFT)
		return false
	if _f in [131, 132]:
		return false
	if _f == 133:
		_key(KEY_LEFT, false, false)
		_check("forehand: ← drops the left edge = anhyzer (%.0f)" % s.roll, s.roll == -1.0 and s.visual_tilt() == 1.0)
		var i0: int = s.disc_index
		_tap(KEY_E)
		var i1: int = s.disc_index
		_tap(KEY_Q)
		_check("E next disc, Q back", i1 == posmod(i0 + 1, s.discs.size()) and s.disc_index == i0)
		# Throws carry the setup and keep it.
		var n0: int = th.discs.size()
		_tap(KEY_ENTER)
		var d = th._last
		_check("Enter throws a disc with the setup (forehand, %s)" % [d.model.id if d != null and "model" in d else "?"],
			th.discs.size() == n0 + 1 and "model" in d and d.hand == -1.0 and d.model == s.disc())
		_click(MOUSE_BUTTON_LEFT)
		_check("left click throws a disc", th.discs.size() == n0 + 2 and "model" in th._last)
		_click(MOUSE_BUTTON_RIGHT)
		var cube = th._last
		var v: float = (cube.linear_velocity - pl.velocity).length()
		_check("right click throws a cube at the disc speed (%.0f mph)" % (v * s.MPH_PER_MS),
			not ("model" in cube) and absf(v - s.speed) < 0.6)
		_check("setup carries over after throwing", s.roll == -1.0 and s.hand == -1.0
			and not s.spin_locked and is_equal_approx(s.speed_mph(), 55.0))
		_tap(KEY_U)
		var hidden: bool = not th.throw_hud.visible
		_tap(KEY_U)
		_check("U hides and shows the HUD", hidden and th.throw_hud.visible)
		_tap(KEY_G)
		var g_on: bool = th.warp_on
		_tap(KEY_G)
		_check("G toggles goto", g_on and not th.warp_on)
		var bad := 0
		for ch in _checks:
			print("%s  %s" % ["ok  " if ch[1] else "FAIL", ch[0]])
			if not ch[1]:
				bad += 1
		print("HUD %s (%d/%d)" % ["PASS" if bad == 0 else "FAIL", _checks.size() - bad, _checks.size()])
		return true
	return false


## Which way the nose reads on the HUD disc. Checked here rather than by eye
## because it has been wrong twice, both times in a way that looked right on
## review: flat has to be flat, nose up has to go up, nose down has to go down.
func _check_nose_cue() -> void:
	var Hud := load("res://scripts/throw_hud.gd")
	var flat: float = Hud.lead_offset(0.0, 0.0)
	var up: float = Hud.lead_offset(10.0, 0.0)
	var down: float = Hud.lead_offset(-10.0, 0.0)
	# Screen y is DOWN, so up the screen is more negative.
	_check("nose 0 draws flat (lead %.3f, want 0)" % flat, absf(flat) < 0.01)
	_check("nose +10 tips the leading edge UP (%.3f)" % up, up < -0.05)
	_check("nose -10 tips it DOWN (%.3f)" % down, down > 0.05)
	_check("nose is symmetric about flat (%.3f vs %.3f)" % [up, down],
		absf(up + down) < 0.01)
	# Monotonic the whole way across the range, so there is no second nose
	# angle that looks like any other.
	var prev := 1e9
	var mono := true
	for i in 21:
		var nose := -10.0 + i
		var y: float = Hud.lead_offset(nose, 0.0)
		if y >= prev:
			mono = false
		prev = y
	_check("nose reads one way all the way across -10..+10", mono)
	# Nose up shows the lit top face, nose down the dark underside: the second
	# cue a player reads, and it must agree with the first.
	_check("nose up shows the top face, nose down the underside",
		Hud.disc_frame(10.0, 0.0).y.dot(Hud.to_cam()) > 0.0
		and Hud.disc_frame(-10.0, 0.0).y.dot(Hud.to_cam()) < 0.0)
