extends SceneTree
## Screenshots of VIEW + WARP (needs a display): both lamps on, a throw, the
## view chasing it (warp lamp breathing in the corner), then the view after
## arriving.
##
##   godot --path . --resolution 1280x720 --script res://tools/warp_shots.gd -- <out_dir>

var _main: Node
var _out := "/tmp/warp_shots"
var _f := 0
var _d: Node
var _arrived := -1


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and not args[0].begins_with("--"):
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_dt: float) -> bool:
	_f += 1
	var th = _main.thrower
	if _f == 10:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_main.get_node("Player/Head").rotation.x = deg_to_rad(12)
		th.set_view(true)
		th.set_warp(true)
		_d = th.throw_disc(th.panel.params())
	if _f == 100:
		_grab("1_waiting")
	if _arrived < 0 and _f > 20 and not th.warp_pending():
		_arrived = _f
	if _arrived > 0 and _f == _arrived + 8:
		_grab("2_arrived")
		quit()
	if _f > 60 * 40:
		quit(1)
	return false


func _grab(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, name])
	print("SHOT ", name)
