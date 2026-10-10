extends Camera3D
## Follow cam (V): a chase camera that trails a disc (or block) through its
## flight and ground play, then hands the view back to the walker once the
## disc has fully stopped (its `resting` flag: still for 0.6 s). V again, or
## the disc disappearing (collected, cleared, fell out of the world), also
## hands back early.
##
## The camera floats `back` metres behind and `up` metres above the disc,
## behind its direction of travel (horizontal). While it's barely moving
## (rolling to a stop) the heading is held so the view doesn't spin. Position
## and aim are smoothed so landings and skips don't jerk the view.

signal ended

@export var back := 1.8               ## m behind the disc.
@export var up := 0.5                 ## m above the disc.
@export var lead := 4.0               ## Look this far ahead of the disc (m).
@export var follow_rate := 14.0       ## Position smoothing (1/s).
@export var aim_rate := 8.0           ## Aim smoothing (1/s).

var terrain: Node3D
var player_camera: Camera3D
var target: Node3D = null
var _heading := Vector3.FORWARD
var _aim := Vector3.ZERO


func _ready() -> void:
	top_level = true
	fov = 72.0
	far = 500.0
	current = false


func active() -> bool:
	return target != null


## Starts following `disc`. Returns false if there's nothing worth following.
func follow(disc: Node3D) -> bool:
	if not is_instance_valid(disc) or disc.resting:
		return false
	target = disc
	var v: Vector3 = disc.linear_velocity * Vector3(1, 0, 1)
	_heading = v.normalized() if v.length() > 0.5 else _flat(-player_camera.global_transform.basis.z)
	# Start where the walker's eyes are and swoop in.
	global_transform = player_camera.global_transform
	_aim = disc.global_position
	current = true
	return true


func stop() -> void:
	if target == null:
		return
	target = null
	current = false
	player_camera.current = true
	ended.emit()


func _process(delta: float) -> void:
	if target == null:
		return
	if not is_instance_valid(target) or target.resting:
		stop()
		return
	var p: Vector3 = target.global_position
	var v: Vector3 = target.linear_velocity
	var vh := v * Vector3(1, 0, 1)
	if vh.length() > 1.0:
		_heading = _heading.slerp(vh.normalized(), clampf(delta * 4.0, 0.0, 1.0)).normalized()
	var want := p - _heading * back + Vector3.UP * up
	if terrain != null:
		want.y = maxf(want.y, terrain.height_at(want.x, want.z) + 0.6)
	global_position = global_position.lerp(want, clampf(delta * follow_rate, 0.0, 1.0))
	var look := p + _heading * lead * clampf(vh.length() / 15.0, 0.15, 1.0)
	_aim = _aim.lerp(look, clampf(delta * aim_rate, 0.0, 1.0))
	if global_position.distance_to(_aim) > 0.05:
		look_at(_aim, Vector3.UP)


static func _flat(v: Vector3) -> Vector3:
	v.y = 0.0
	return v.normalized() if v.length() > 0.01 else Vector3.FORWARD
