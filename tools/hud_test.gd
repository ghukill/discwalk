extends SceneTree
## Headless check of the throw setup keys and HUD (docs/THROW-HUD.md):
## arrows tilt, Shift+arrows set speed/spin, X locks spin, R resets, H flips
## the hand, Tab / Shift+Tab cycle discs, settings carry over between throws,
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
	var s = th.setup
	var pl: CharacterBody3D = _main.get_node("Player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _f in [6, 7, 9, 10, 12, 13, 15, 16, 18, 19]:
		return false
	if _f == 5:
		_check("starts: dd2, flat, 24 m/s, spin locked, backhand",
			s.disc().id == "dd2" and s.nose == 0.0 and s.roll == 0.0 and s.speed == 24.0 and s.spin_locked and s.hand == 1.0)
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
		_check("Shift+↑ speed +0.5 (%.1f), spin follows while locked (%.1f); Shift+→ ignored while locked" % [s.speed, s.spin],
			s.speed == 24.5 and is_equal_approx(s.spin, 5.2 * 24.5))
		_tap(KEY_X)
		_key(KEY_SHIFT)
		_key(KEY_RIGHT, true)
		return false
	if _f == 20:
		_key(KEY_RIGHT, true, false)
		_key(KEY_SHIFT, false, false)
		_check("X unlocks, Shift+→ spin up a step (%.1f)" % s.spin, not s.spin_locked and s.spin > 5.2 * 24.5 and s.spin <= 5.2 * 24.5 + 3.0)
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
		_key(KEY_LEFT)
		return false
	if _f in [131, 132]:
		return false
	if _f == 133:
		_key(KEY_LEFT, false, false)
		_check("forehand: ← drops the left edge = anhyzer (%.0f)" % s.roll, s.roll == -1.0 and s.visual_tilt() == 1.0)
		var i0: int = s.disc_index
		_tap(KEY_TAB)
		var i1: int = s.disc_index
		_tap(KEY_TAB, true)
		_check("Tab next disc, Shift+Tab back", i1 == posmod(i0 + 1, s.discs.size()) and s.disc_index == i0)
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
		_check("right click throws a cube at the disc speed (%.1f m/s)" % v,
			not ("model" in cube) and absf(v - s.speed) < 0.6)
		_check("setup carries over after throwing", s.roll == -1.0 and s.hand == -1.0 and not s.spin_locked and s.speed == 24.5)
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
