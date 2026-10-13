extends SceneTree
## Headless check of the controller pages and crouching (docs/CONTROLS.md):
## B throws a disc and RB + B a cube; X crouches and LB + X collects (no
## crouch, no hand flip); LB tapped flips the hand, LB + D-pad ↑ resets to
## flat and ↓ toggles spin lock; Tab crouches too; crouched walking is slow;
## A from a crouch stands you up and hops; under a roof you stay down until
## it's gone; Q / E pick the disc.
##
##   godot --headless --path . --script res://tools/controls_test.gd [-- --block-size=1]

var _main: Node
var _pl: CharacterBody3D
var _th: Node
var _s: Node
var _f := 0
var _step := 0
var _wait := 0
var _note := {}
var _roof: StaticBody3D
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


func _key(k: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = k
		e.keycode = k
		e.pressed = down
		Input.parse_input_event(e)
		Input.flush_buffered_events()


func _process(_dt: float) -> bool:
	_f += 1
	if _f == 1:
		_pl = _main.player
		_th = _main.thrower
		_s = _th.setup
		_th.assume_captured = true
	if _wait > 0:
		_wait -= 1
		return false
	if _f > 60 * 60:
		_check("timed out at step %d" % _step, false)
		return _report()
	match _step:
		0:   # let the walker land
			if _f > 30 and _pl.is_on_floor():
				_step += 1
		1:   # B = disc, RB + B = cube
			var n0: int = _th.discs.size()
			_press(JOY_BUTTON_B)
			var d1 = _th._last
			_btn(JOY_BUTTON_RIGHT_SHOULDER, true)
			_press(JOY_BUTTON_B)
			_btn(JOY_BUTTON_RIGHT_SHOULDER, false)
			var d2 = _th._last
			_check("B throws a disc, RB + B a cube",
				_th.discs.size() == n0 + 2 and "flying" in d1 and not ("flying" in d2))
			_step += 1
			_wait = 240                   # let them land before collecting
		2:   # LB tap = hand; LB + ↑ = flat; LB + ↓ = spin lock; Q / E = disc
			var h0: float = _s.hand
			_press(JOY_BUTTON_LEFT_SHOULDER)
			var flipped: bool = _s.hand == -h0
			_s.roll = 12.0
			_s.nose = 3.0
			var lock0: bool = _s.spin_locked
			_btn(JOY_BUTTON_LEFT_SHOULDER, true)
			_note.lb = [flipped, lock0]
			_btn(JOY_BUTTON_DPAD_UP, true)
			_step += 1
			_wait = 2
		3:
			_btn(JOY_BUTTON_DPAD_UP, false)
			_btn(JOY_BUTTON_DPAD_DOWN, true)
			_step += 1
			_wait = 2
		4:
			_btn(JOY_BUTTON_DPAD_DOWN, false)
			var h1: float = _s.hand
			_btn(JOY_BUTTON_LEFT_SHOULDER, false)
			_check("LB tap flips the hand", _note.lb[0])
			_check("LB + ↑ resets to flat, LB + ↓ toggles spin lock, no hand flip after",
				_s.roll == 0.0 and _s.nose == 0.0 and _s.spin_locked != _note.lb[1] and _s.hand == h1)
			_s.spin_locked = _note.lb[1]
			var i0: int = _s.disc_index
			_key(KEY_E)
			var i1: int = _s.disc_index
			_key(KEY_Q)
			_check("E next disc, Q back", i1 == posmod(i0 + 1, _s.discs.size()) and _s.disc_index == i0)
			_step += 1
		5:   # LB + X = collect, not crouch, no hand flip
			var h0: float = _s.hand
			_btn(JOY_BUTTON_LEFT_SHOULDER, true)
			_press(JOY_BUTTON_X)
			_btn(JOY_BUTTON_LEFT_SHOULDER, false)
			var collecting := false
			for d in _th.discs:
				if is_instance_valid(d) and d.collecting:
					collecting = true
			_check("LB + X collects (no crouch, no hand flip)",
				collecting and not _pl.crouch_on and _s.hand == h0)
			_step += 1
		6:   # X = crouch: lower capsule and eyes, slow walk
			_press(JOY_BUTTON_X)
			_note.cap = _pl._capsule.height
			Input.action_press("move_forward")
			_step += 1
			_wait = 90
		7:
			var v := Vector2(_pl.velocity.x, _pl.velocity.z).length()
			Input.action_release("move_forward")
			_check("X crouches: capsule %.2f m, eyes %.2f m, walking %.1f m/s" % [_note.cap, _pl.head.position.y, v],
				_pl.crouched and is_equal_approx(_note.cap, _pl.crouch_height)
				and _pl.head.position.y < 1.1 and v < _pl.crouch_speed + 0.2 and v > 1.0)
			_press(JOY_BUTTON_X)
			_check("X again stands up", not _pl.crouched and is_equal_approx(_pl._capsule.height, 1.8))
			_step += 1
			_wait = 30
		8:   # Tab = crouch too; A from a crouch stands and hops
			_key(KEY_TAB)
			var down: bool = _pl.crouched
			_press(JOY_BUTTON_A)
			_note.tab_down = down
			_step += 1
			_wait = 3
		9:
			_check("Tab crouches; A from a crouch stands up and hops (vy %.1f)" % _pl.velocity.y,
				_note.tab_down and not _pl.crouched and _pl.velocity.y > 1.0)
			_step += 1
			_wait = 90
		10:  # under a roof: stay down, stand once it's gone
			if not _pl.is_on_floor():
				return false
			_pl.set_crouch(true)
			_roof = StaticBody3D.new()
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(3, 0.2, 3)
			shape.shape = box
			_roof.add_child(shape)
			_main.add_child(_roof)
			_roof.global_position = _pl.global_position + Vector3(0, 1.4, 0)
			_step += 1
			_wait = 3
		11:  # A under the roof: no hop, still down
			_press(JOY_BUTTON_A)
			_step += 1
			_wait = 3
		12:
			_note.a = _pl.crouched and _pl.crouch_on and _pl.velocity.y < 0.5
			_key(KEY_TAB)                 # stand, please: no room yet
			_step += 1
			_wait = 3
		13:
			_note.tab = _pl.crouched and not _pl.crouch_on
			_roof.queue_free()
			_step += 1
			_wait = 5
		14:
			_check("under a roof: A doesn't hop, Tab off waits, roof gone = you stand",
				_note.a and _note.tab and not _pl.crouched)
			_step += 1
		_:
			return _report()
	return false


func _report() -> bool:
	var ok := true
	for c in _checks:
		print("CONTROLS %-90s %s" % [c[0], "ok" if c[1] else "FAIL"])
		ok = ok and c[1]
	print("CONTROLS %s" % ("PASS" if ok else "FAIL"))
	return true
