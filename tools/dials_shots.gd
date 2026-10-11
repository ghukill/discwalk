extends SceneTree
## Screenshots of the heading/horizon dials and launch readout (needs a display).
##
##   godot --path . --resolution 1280x720 --script res://tools/dials_shots.gd -- <out_dir>
##
## Looks level, up 15 deg, down 10 deg, then throws at +15 to
## check the disc really leaves at the view angle.

var _main: Node
var _out := "/tmp/dials_shots"
var _f := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and not args[0].begins_with("--"):
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_d: float) -> bool:
	_f += 1
	var head: Node3D = _main.get_node("Player/Head")
	var pl: Node3D = _main.get_node("Player")
	var th = _main.thrower
	if _f == 5:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		pl.rotation.y = deg_to_rad(-40)          # heading ~040
		head.rotation.x = 0.0
	if _f == 25:
		_grab("1_level")
		head.rotation.x = deg_to_rad(15)
	if _f == 45:
		_grab("2_up15")
		head.rotation.x = deg_to_rad(-10)
	if _f == 65:
		_grab("3_down10")
		head.rotation.x = deg_to_rad(15)
	if _f == 70:
		var d = th.throw_disc(th.setup.params())
		var v: Vector3 = d.linear_velocity
		var ang := rad_to_deg(atan2(v.y, Vector2(v.x, v.z).length()))
		print("DIALS launch angle at view +15: %.1f deg (readout %s)" % [ang, th.launch_label.text])
	if _f == 80:
		quit()
	return false


func _grab(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_out, name])
	img.get_region(Rect2i(img.get_width() - 340, img.get_height() - 270, 340, 270)).save_png("%s/%s_corner.png" % [_out, name])
	print("SHOT ", name)
