extends SceneTree
## Headless check that the title menu works from a controller (menu.gd):
## the D-pad moves the focus and A picks Free Play / Course Play; up on the
## course row, right steps the course; A opens Controls and B comes back
## with the focus on Controls.
##
##   godot --headless --path . --script res://tools/menu_test.gd [-- --block-size=1]

var _main: Node
var _menu: CanvasLayer
var _f := 0
var _step := 0
var _checks: Array = []


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _check(name: String, ok: bool) -> void:
	_checks.append([name, ok])


func _btn(b: JoyButton, down: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _press(b: JoyButton) -> void:
	_btn(b, true)
	_btn(b, false)


func _focus() -> Control:
	return root.gui_get_focus_owner()


func _process(_dt: float) -> bool:
	_f += 1
	if _f > 60 * 30:
		_check("timed out at step %d" % _step, false)
		return _report()
	if _f < 5:
		return false
	match _step:
		0:   # title menu, as at launch: A on Free Play starts it
			_menu = _main.menu
			_main.mode = ""
			_menu.open(false, false, true)
			_check("title menu focuses Free Play", _focus() == _menu._free)
			_press(JOY_BUTTON_A)
			_check("A picks Free Play", _main.mode == "free" and not _menu.visible)
			_check("game unpaused", not paused)
			_step += 1
		1:
			_menu.open(false, false, true)
			_step += 1
		2:   # D-pad down to Course Play, A starts the round (a frame after opening:
			# focus neighbours need the laid-out buttons)
			_press(JOY_BUTTON_DPAD_DOWN)
			_check("D-pad down focuses Course Play", _focus() == _menu._course)
			_press(JOY_BUTTON_A)
			_check("A picks Course Play", _main.mode == "course" and not _menu.visible)
			_step += 1
		3:
			_menu.open(false, false, true)
			_step += 1
		4:   # up to the course row (Free Play's above it on the title screen)
			_press(JOY_BUTTON_DPAD_UP)
			_check("D-pad up focuses the course row", _focus() == _menu._place)
			var was: int = _menu.pick
			_press(JOY_BUTTON_DPAD_RIGHT)
			_check("D-pad right steps the course", _menu.pick == posmod(was + 1, _menu.places.size()))
			_press(JOY_BUTTON_DPAD_LEFT)
			_check("D-pad left steps it back", _menu.pick == was)
			_menu._ctl.grab_focus()
			_press(JOY_BUTTON_A)
			_check("A on Controls shows the controls", _menu._controls.visible)
			_press(JOY_BUTTON_B)
			_check("B closes the controls", not _menu._controls.visible and _menu.visible)
			_check("focus back on Controls", _focus() == _menu._ctl)
			_press(JOY_BUTTON_DPAD_UP)
			_check("D-pad moves again after Controls", _focus() != null and _focus() != _menu._ctl)
			_step += 1
		5:
			_menu.close()
			return _report()
	return false


func _report() -> bool:
	var ok := true
	for c in _checks:
		print("MENU %-60s %s" % [c[0], "ok" if c[1] else "FAIL"])
		ok = ok and c[1]
	print("MENU %s" % ("PASS" if ok else "FAIL"))
	return true
