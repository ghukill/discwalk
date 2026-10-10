extends SceneTree
## Screenshots of the clouds (needs a display): looking up a little from
## spawn, a wide view across the world, then the same wide view 20 s later
## (they should have drifted ~20 m).
##
##   godot --path . --resolution 1280x720 --script res://tools/clouds_shots.gd -- <out_dir>

var _main: Node
var _out := "/tmp/clouds_shots"
var _f := 0
var _p0 := Vector3.ZERO


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and not args[0].begins_with("--"):
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_d: float) -> bool:
	_f += 1
	var pl: Node3D = _main.get_node("Player")
	var head: Node3D = pl.get_node("Head")
	if _f == 5:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		pl.rotation.y = deg_to_rad(-30)
		head.rotation.x = deg_to_rad(14)
		_p0 = _main.clouds._clouds[0].position
	if _f == 30:
		_grab("1_spawn_up")
		head.rotation.x = deg_to_rad(4)
		pl.rotation.y = deg_to_rad(150)
	if _f == 50:
		_grab("2_spawn_level")
		var cam := Camera3D.new()
		cam.far = 900
		root.add_child(cam)
		cam.current = true
		var s: float = _main.terrain.world_size
		cam.global_position = Vector3(-40, 60, s + 40)
		cam.look_at(Vector3(s * 0.6, 50, s * 0.3), Vector3.UP)
	if _f == 70:
		_grab("3_wide")
		var moved: float = _main.clouds._clouds[0].position.distance_to(_p0)
		print("CLOUDS %d clouds, first moved %.1f m in %.1f s" % [_main.clouds._clouds.size(), moved, _f / 60.0])
		quit()
	return false


func _grab(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, name])
	print("SHOT ", name)
