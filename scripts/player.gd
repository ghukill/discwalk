extends CharacterBody3D
## First-person walker. WASD / arrows to move, mouse to look, Shift to stroll
## faster, Space to hop. Esc frees the mouse; click to grab it again.

@export var walk_speed := 4.0
@export var sprint_speed := 7.5
@export var jump_velocity := 5.0
@export var acceleration := 10.0
@export var mouse_sensitivity := 0.0025
@export var bob_amount := 0.04
@export var bob_frequency := 1.8

@onready var head: Node3D = $Head

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _bob_time := 0.0
var _head_base_y := 0.0


func _ready() -> void:
	_ensure_input_actions()
	_head_base_y = head.position.y
	# 1-block steps on the smooth collision heightmap are exactly 45 degrees;
	# allow a little more so they are walkable. 2-block steps stay walls.
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.6
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-88), deg_to_rad(88))
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	var k := clampf(acceleration * delta, 0.0, 1.0)
	velocity.x = lerpf(velocity.x, dir.x * speed, k)
	velocity.z = lerpf(velocity.z, dir.z * speed, k)

	move_and_slide()
	_head_bob(delta)

	if global_position.y < -30.0:
		respawn(get_parent().get_node("Terrain").spawn_point())


func respawn(at: Vector3) -> void:
	global_position = at
	velocity = Vector3.ZERO


## Gentle walking bob, because strolling should feel like strolling.
func _head_bob(delta: float) -> void:
	var flat_speed := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and flat_speed > 0.5:
		_bob_time += delta * flat_speed * bob_frequency
	else:
		_bob_time = lerpf(_bob_time, round(_bob_time / PI) * PI, clampf(delta * 6.0, 0.0, 1.0))
	head.position.y = _head_base_y + sin(_bob_time) * bob_amount


static func _ensure_input_actions() -> void:
	var bindings := {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE],
		"sprint": [KEY_SHIFT],
		"new_world": [KEY_N],
		"fetch": [KEY_F],
		"throw_1": [KEY_1, KEY_KP_1], "throw_2": [KEY_2, KEY_KP_2],
		"throw_3": [KEY_3, KEY_KP_3], "throw_4": [KEY_4, KEY_KP_4],
		"throw_5": [KEY_5, KEY_KP_5], "throw_6": [KEY_6, KEY_KP_6],
		"throw_7": [KEY_7, KEY_KP_7], "throw_8": [KEY_8, KEY_KP_8],
		"throw_9": [KEY_9, KEY_KP_9], "throw_10": [KEY_0, KEY_KP_0],
	}
	for action in bindings:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key in bindings[action]:
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
