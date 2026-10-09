extends SceneTree
## Screenshots of the throw panel and a disc in flight (needs a display).
##
##   godot --path . --resolution 1280x720 --script res://tools/flight_shots.gd -- <out_dir>
##
## 1 panel: throw panel open, looking out from spawn.
## 2 chase: a camera trailing the disc mid-flight.
## 3 side:  a camera off to the side watching it fade.
## 4 rest:  the disc lying where it landed.

const DiscModel := preload("res://scripts/disc_model.gd")

var _main: Node
var _out := "/tmp/flight_shots"
var _frames := 0
var _disc: Node
var _cam: Camera3D
var _side_from := Vector3.ZERO


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and not args[0].begins_with("--"):
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _grab(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out, name]
	img.save_png(path)
	print("SHOT ", path)


func _process(_delta: float) -> bool:
	_frames += 1
	var thrower = _main.thrower
	var player: CharacterBody3D = _main.get_node("Player")
	if _frames == 10:
		thrower.panel.toggle()
		player.get_node("Head").rotation.x = deg_to_rad(4)
	if _frames == 40:
		_grab("1_panel")
		var p: Dictionary = thrower.panel.params()
		_disc = thrower.throw_disc(p)
		thrower.panel.toggle()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_cam = Camera3D.new()
		_cam.fov = 70
		_cam.far = 500
		root.add_child(_cam)
		_cam.current = true
		var fwd: Vector3 = _disc.linear_velocity * Vector3(1, 0, 1)
		_side_from = _disc.global_position + fwd.normalized() * 30.0 \
			+ fwd.normalized().cross(Vector3.UP) * 22.0 + Vector3(0, 4, 0)
	if _frames > 40 and _frames < 100 and is_instance_valid(_disc):
		var v: Vector3 = _disc.linear_velocity
		var back := -(v * Vector3(1, 0, 1)).normalized()
		_cam.global_position = _disc.global_position + back * 2.2 + Vector3(0, 0.55, 0)
		_cam.look_at(_disc.global_position + Vector3(0, 0.1, 0) - back * 6.0, Vector3.UP)
	if _frames == 70:
		_grab("2_chase")
	if _frames >= 100 and _frames < 400 and is_instance_valid(_disc):
		_cam.global_position = _side_from
		_cam.look_at(_disc.global_position, Vector3.UP)
	if _frames == 150:
		_grab("3_side")
	if is_instance_valid(_disc) and _disc.resting and _frames > 150:
		var p: Vector3 = _disc.global_position
		_cam.global_position = p + Vector3(0.7, 0.6, 0.7)
		_cam.look_at(p, Vector3.UP)
		if _frames % 10 == 0:
			_grab("4_rest")
			print("REST carry %.1f m, rest %.1f m, landed on %s" % [_disc.flight_dist, _disc.distance(), _disc.landed_by])
			quit(0)
			return true
	if _frames > 60 * 40:
		quit(1)
		return true
	return false
