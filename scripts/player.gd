extends CharacterBody3D
## First-person walker. WASD to move (arrows set up the throw now), mouse to
## look, Shift to stroll faster, Space to hop, Tab to crouch / stand. Esc
## frees the mouse; click to grab it again.
## Controller: left stick walks, right stick looks, View toggles running,
## A hops, X crouches (LB + X is collect, so X alone only). docs/CONTROLS.md.

@export var walk_speed := 4.0
@export var sprint_speed := 7.5
@export var jump_velocity := 5.0
@export var crouch_speed := 2.0         ## Crouched walking (run or Shift don't help).
@export var crouch_height := 1.1        ## Capsule height crouched (standing: the scene's).
@export var crouch_drop := 0.65         ## Eyes go down this much.
@export var acceleration := 10.0
@export var mouse_sensitivity := 0.0025
@export var stick_look_speed := 3.0    ## Right stick, fully pushed (rad/s).
@export var bob_amount := 0.04
@export var bob_frequency := 1.8

@onready var head: Node3D = $Head

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _bob_time := 0.0
var _flung := false              ## Carrying momentum from a launch (L).
var _fling_t := 0.0
var _head_base_y := 0.0
var _run_on := false             ## Controller View button: run until pressed again.
var crouch_on := false           ## Wanted (Tab / X toggles it).
var crouched := false            ## Actually down. Lags crouch_on when there's no headroom.
var _crouch_k := 0.0             ## Eyes: 0 standing .. 1 crouched (eased).
var _capsule: CapsuleShape3D
var _shape: CollisionShape3D
var _stand_height := 1.8

## Shot-circle (thrower.gd): with a radius > 0 you can't walk further than
## that (flat) from tether_center. You slide round the edge instead.
var tether_center := Vector3.ZERO
var tether_radius := 0.0
## Course Play's "walking to the next hole" (course_round.gd): while set, the walker
## heads for walk_to itself (your keys don't move it; looking still works)
## and walk_done fires on arrival. walk_stuck fires if it stops getting
## anywhere (a cliff, a trunk).
signal walk_done
signal walk_stuck
var walking := false
var walk_to := Vector3.ZERO
var walk_speed_auto := 5.0
var _walk_route: Array[Vector3] = []
var _walk_check := Vector3.ZERO
var _walk_check_t := 0.0
var _look_t := 10.0              ## Seconds since you last looked around.
## Hole overview (course_round.gd): the walker stands still and ignores look input.
var frozen := false


func _ready() -> void:
	_ensure_input_actions()
	_head_base_y = head.position.y
	_shape = $CollisionShape3D
	_capsule = (_shape.shape as CapsuleShape3D).duplicate()
	_shape.shape = _capsule
	_stand_height = _capsule.height
	# 1-block steps on the smooth collision heightmap are exactly 45 degrees;
	# allow a little more so they are walkable. 2-block steps stay walls.
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.6
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if frozen:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look_t = 0.0
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-88), deg_to_rad(88))
	elif event.is_action_pressed("run_toggle"):
		_run_on = not _run_on
	elif event.is_action_pressed("crouch") and not _lb_chord(event):
		set_crouch(not crouch_on)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
			and not _mouse_ui_open():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## True while a panel that needs the mouse (group "mouse_ui") is showing.
func _mouse_ui_open() -> bool:
	for n in get_tree().get_nodes_in_group("mouse_ui"):
		if n is CanvasItem and n.visible:
			return true
	return false


## Right stick look, squared so small pushes aim finely.
func _process(delta: float) -> void:
	_look_t += delta
	if frozen:
		return
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look == Vector2.ZERO:
		return
	_look_t = 0.0
	look *= look.length() * stick_look_speed * delta
	rotate_y(-look.x)
	head.rotate_x(-look.y)
	head.rotation.x = clampf(head.rotation.x, deg_to_rad(-88), deg_to_rad(88))


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_action_just_pressed("jump"):
		# From a crouch: stand up and hop, if there's room to. If not, no
		# hop, and you stay as you were (still waiting to stand, or not).
		var wanted := crouch_on
		crouch_on = false
		_update_crouch()
		if crouched:
			crouch_on = wanted
		else:
			velocity.y = jump_velocity
	_update_crouch()

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if frozen:
		input = Vector2.ZERO
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	var speed := sprint_speed if _run_on or Input.is_action_pressed("sprint") else walk_speed
	if crouched:
		speed = crouch_speed
	if walking:
		dir = _walk_dir(delta)
		speed = walk_speed_auto
	if _flung:
		# Riding a disc's momentum: keep it until we land, with a touch of
		# air control (and the same whisper of drag the disc has).
		_fling_t += delta
		if _fling_t > 0.2 and is_on_floor():
			_flung = false
		velocity.x += dir.x * speed * 1.5 * delta
		velocity.z += dir.z * speed * 1.5 * delta
		velocity *= 1.0 - 0.05 * delta
	if not _flung:
		var k := clampf(acceleration * delta, 0.0, 1.0)
		velocity.x = lerpf(velocity.x, dir.x * speed, k)
		velocity.z = lerpf(velocity.z, dir.z * speed, k)

	move_and_slide()
	_hold_tether()
	if walking and is_on_floor() and is_on_wall():
		velocity.y = jump_velocity        # hop up a step that's in the way
	_head_bob(delta)

	if global_position.y < -30.0:
		respawn(get_parent().get_node("Terrain").spawn_point())


## Shot-circle: pull back inside the tether and drop any outward speed, so
## you slide along the edge.
func _hold_tether() -> void:
	if tether_radius <= 0.0:
		return
	var off := Vector2(global_position.x - tether_center.x, global_position.z - tether_center.z)
	var d := off.length()
	if d <= tether_radius:
		return
	var n := off / d
	global_position.x = tether_center.x + n.x * tether_radius
	global_position.z = tether_center.z + n.y * tether_radius
	var out := velocity.x * n.x + velocity.z * n.y
	if out > 0.0:
		velocity.x -= n.x * out
		velocity.z -= n.y * out


func set_tether(center: Vector3, radius: float) -> void:
	tether_center = center
	tether_radius = radius


func clear_tether() -> void:
	tether_radius = 0.0


## Walk yourself to `to` (m) along `route` (waypoints before it, if any).
func walk(to: Vector3, route: Array[Vector3] = []) -> void:
	walk_to = to
	_walk_route = route.duplicate()
	_walk_route.append(to)
	walking = true
	_walk_check = global_position
	_walk_check_t = 0.0
	set_crouch(false)


func stop_walk() -> void:
	walking = false
	_walk_route.clear()


## Flat direction to the next waypoint; turns you to face the way you're
## going unless you've looked around in the last second or so.
func _walk_dir(delta: float) -> Vector3:
	while _walk_route.size() > 1 and _flat_to(_walk_route[0]).length() < 2.0:
		_walk_route.pop_front()
	var to := _flat_to(_walk_route[0])
	if _walk_route.size() == 1 and to.length() < 0.4:
		walking = false
		_walk_route.clear()
		walk_done.emit()
		return Vector3.ZERO
	# Stuck: barely moved in the last 1.5 s.
	_walk_check_t += delta
	if _walk_check_t > 1.5:
		var moved := _flat_to(_walk_check).length()
		_walk_check = global_position
		_walk_check_t = 0.0
		if moved < 0.75:
			walking = false
			_walk_route.clear()
			walk_stuck.emit()
			return Vector3.ZERO
	var dir := Vector3(to.x, 0, to.y).normalized()
	if _look_t > 1.2:
		var want := atan2(-dir.x, -dir.z)
		rotation.y = lerp_angle(rotation.y, want, clampf(delta * 2.5, 0.0, 1.0))
		head.rotation.x = lerpf(head.rotation.x, 0.0, clampf(delta * 2.0, 0.0, 1.0))
	# Slow down for the last couple of metres.
	return dir * clampf(to.length() / 2.0, 0.25, 1.0)


func _flat_to(p: Vector3) -> Vector2:
	return Vector2(p.x - global_position.x, p.z - global_position.z)


## Turn (left/right and up/down) so your eyes look straight at `target`.
func face(target: Vector3) -> void:
	var d := target - global_position
	rotation.y = atan2(-d.x, -d.z)
	var eye := head.global_position
	var e := target - eye
	var flat := Vector2(e.x, e.z).length()
	head.rotation.x = clampf(atan2(e.y, flat), deg_to_rad(-88), deg_to_rad(88))


## `yaw` (radians, 0 = facing -z) turns the walker too; NAN keeps the facing.
func respawn(at: Vector3, yaw := NAN) -> void:
	global_position = at
	if not is_nan(yaw):
		rotation.y = yaw
		head.rotation.x = 0.0
	velocity = Vector3.ZERO
	_flung = false
	walking = false
	_walk_route.clear()
	set_crouch(false)


## Tab / X: crouch or stand. Standing waits for headroom (under a canopy or an
## overhang you stay down until you walk out, then stand on your own).
func set_crouch(on: bool) -> void:
	crouch_on = on
	_update_crouch()


## The LB + X chord is collect (thrower.gd), not crouch.
static func _lb_chord(event: InputEvent) -> bool:
	return event is InputEventJoypadButton and Input.is_action_pressed("setup_disc")


## Brings the capsule in line with crouch_on: down at once, up only if the
## standing capsule fits. Feet stay put either way.
func _update_crouch() -> void:
	if crouch_on == crouched:
		return
	if not crouch_on and _capsule != null:
		var rise := _stand_height - crouch_height
		if test_move(global_transform, Vector3(0, rise, 0)):
			return                          # no headroom yet
	crouched = crouch_on
	if _capsule != null:
		_capsule.height = crouch_height if crouched else _stand_height
		_shape.position.y = _capsule.height * 0.5


## Teleport to `at` already moving at `vel` (m/s); momentum is kept until
## you land. Used by launching yourself (L) with a disc that's still moving.
func fling(at: Vector3, vel: Vector3) -> void:
	global_position = at
	velocity = vel
	_flung = true
	_fling_t = 0.0
	set_crouch(false)
	clear_tether()


## Gentle walking bob, because strolling should feel like strolling.
func _head_bob(delta: float) -> void:
	var flat_speed := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and flat_speed > 0.5:
		_bob_time += delta * flat_speed * bob_frequency
	else:
		_bob_time = lerpf(_bob_time, round(_bob_time / PI) * PI, clampf(delta * 6.0, 0.0, 1.0))
	_crouch_k = move_toward(_crouch_k, 1.0 if crouched else 0.0, delta * 6.0)
	var ease_k := smoothstep(0.0, 1.0, _crouch_k)
	head.position.y = _head_base_y - crouch_drop * ease_k + sin(_bob_time) * bob_amount


static func _ensure_input_actions() -> void:
	var bindings := {
		"move_forward": [KEY_W],
		"move_back": [KEY_S],
		"move_left": [KEY_A],
		"move_right": [KEY_D],
		"jump": [KEY_SPACE],
		"crouch": [KEY_TAB],             # toggle
		"sprint": [KEY_SHIFT],
		"new_world": [KEY_N],
		"launch": [KEY_L],
		"collect": [KEY_C],
		"view": [KEY_V],
		"warp": [KEY_G],                 # "goto" in the HUD
		"paths": [KEY_P],
		"hud": [KEY_U],
		"clouds": [KEY_K],
		"controls": [KEY_SLASH],         # ? (Shift+/): the controls overlay
		"menu": [KEY_ESCAPE],            # the game menu (also frees the mouse)
		"circle": [KEY_O],               # shot-circle
		"overview": [KEY_M],             # hole overview (Course Play)
		# Throw setup (throw_setup.gd). Shift + up/down = speed, + left/right = spin.
		"tilt_up": [KEY_UP],
		"tilt_down": [KEY_DOWN],
		"tilt_left": [KEY_LEFT],
		"tilt_right": [KEY_RIGHT],
		"throw_disc": [KEY_ENTER, KEY_KP_ENTER],
		"prev_disc": [KEY_Q],
		"next_disc": [KEY_E],
		"spin_lock": [KEY_X],
		"reset_flat": [KEY_R],
		"hand": [KEY_H],
		"ui_bigger": [KEY_EQUAL, KEY_KP_ADD],
		"ui_smaller": [KEY_MINUS, KEY_KP_SUBTRACT],
	}
	# Xbox-style controller (docs/CONTROLS.md). Buttons join the keyboard
	# actions; sticks are [axis, direction]. Clicking a stick toggles what it
	# steers: left (walking) = GOTO, right (looking) = chase view.
	# Shoulder pages: RB held turns the D-pad to speed/spin and B to a cube;
	# LB held turns the D-pad to disc/reset/spin lock and X to collect, and LB
	# tapped flips the hand (throw_setup.gd). Where a button sits on two
	# actions, the handlers check the shoulder (thrower.gd, player.gd).
	var pad := {
		"move_forward": [[JOY_AXIS_LEFT_Y, -1.0]],
		"move_back": [[JOY_AXIS_LEFT_Y, 1.0]],
		"move_left": [[JOY_AXIS_LEFT_X, -1.0]],
		"move_right": [[JOY_AXIS_LEFT_X, 1.0]],
		"look_up": [[JOY_AXIS_RIGHT_Y, -1.0]],
		"look_down": [[JOY_AXIS_RIGHT_Y, 1.0]],
		"look_left": [[JOY_AXIS_RIGHT_X, -1.0]],
		"look_right": [[JOY_AXIS_RIGHT_X, 1.0]],
		"tilt_up": [JOY_BUTTON_DPAD_UP],
		"tilt_down": [JOY_BUTTON_DPAD_DOWN],
		"tilt_left": [JOY_BUTTON_DPAD_LEFT],
		"tilt_right": [JOY_BUTTON_DPAD_RIGHT],
		"setup_alt": [JOY_BUTTON_RIGHT_SHOULDER],   # held: D-pad = speed/spin, B = cube
		"setup_disc": [JOY_BUTTON_LEFT_SHOULDER],   # held: D-pad = disc/reset/spin lock, X = collect; tapped: hand
		"jump": [JOY_BUTTON_A],
		"throw_disc": [JOY_BUTTON_B],               # RB + B: cube instead
		"throw_cube": [JOY_BUTTON_B],
		"crouch": [JOY_BUTTON_X],                   # LB + X: collect instead
		"collect": [JOY_BUTTON_X],
		"launch": [JOY_BUTTON_Y],                   # LB + Y: shot-circle instead
		"circle": [JOY_BUTTON_Y],
		"overview": [JOY_BUTTON_B],                 # LB + B: hole overview (B alone throws)
		"paths": [JOY_BUTTON_MISC1],                # Share: the discs share where they went
		"warp": [JOY_BUTTON_LEFT_STICK],
		"view": [JOY_BUTTON_RIGHT_STICK],
		"run_toggle": [JOY_BUTTON_BACK],
		"menu": [JOY_BUTTON_START],                 # Menu: the game menu
	}
	for action in bindings.keys() + pad.keys():
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.2)
		for key in bindings.get(action, []):
			# Physical keycode: layout-independent (WASD stays put on AZERTY etc.).
			var phys := InputEventKey.new()
			phys.physical_keycode = key
			InputMap.action_add_event(action, phys)
			# Logical keycode too: remote/injected input (VNC, Screen Sharing)
			# often arrives without a physical scancode, so physical-only
			# bindings silently ignore it.
			var logical := InputEventKey.new()
			logical.keycode = key
			InputMap.action_add_event(action, logical)
		for b in pad.get(action, []):
			var ev: InputEvent
			if b is Array:
				ev = InputEventJoypadMotion.new()
				ev.axis = b[0]
				ev.axis_value = b[1]
			else:
				ev = InputEventJoypadButton.new()
				ev.button_index = b
			ev.device = -1   # any controller
			InputMap.action_add_event(action, ev)
