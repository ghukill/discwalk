extends SceneTree
## Screenshot of the throw HUD with a disc set up (needs a display):
##   godot --path . --resolution 1600x900 --script res://tools/hud_shots.gd -- <out_dir>
## Saves hud.png (full frame) and hud_corner.png (just the instrument block),
## plus a strip of five setups (hud_strip.png): flat, hyzer, nose up, forehand
## anhyzer with spin unlocked, and a steep hyzer.

var _main: Node
var _out := "/tmp/hud_shots"
var _f := 0
const SETUPS := [  # nose, roll, hand, spin locked, disc index
	[0.0, 0.0, 1.0, true, 2], [0.0, 20.0, 1.0, true, 0], [6.0, 20.0, 1.0, false, 1],
	[-6.0, -15.0, -1.0, true, 2], [10.0, 40.0, -1.0, false, 3]]
var _corners: Array = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and not args[0].begins_with("--"):
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _corner(img: Image) -> Image:
	var hud: Control = _main.thrower.throw_hud
	var k: float = root.content_scale_factor
	var r := Rect2i(Vector2i(hud.get_global_rect().position * k) - Vector2i(8, 8),
		Vector2i(hud.size * k) + Vector2i(16, 16))
	return img.get_region(r.intersection(Rect2i(Vector2i.ZERO, img.get_size())))


func _process(_d: float) -> bool:
	_f += 1
	var s = _main.thrower.setup
	var head: Node3D = _main.get_node("Player/Head")
	if _f == 5:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		head.rotation.x = deg_to_rad(8)
	var i := (_f - 20) / 10
	if _f >= 20 and (_f - 20) % 10 == 0 and i < SETUPS.size():
		var sh: Array = SETUPS[i]
		s.nose = sh[0]
		s.roll = sh[1]
		s.hand = sh[2]
		s.spin_locked = sh[3]
		s.disc_index = sh[4]
		if not sh[3]:
			s.spin = 60.0
	if _f >= 20 and (_f - 20) % 10 == 6 and i < SETUPS.size():
		var img := root.get_viewport().get_texture().get_image()
		if i == 1:
			img.save_png(_out + "/hud.png")
			_corner(img).save_png(_out + "/hud_corner.png")
		_corners.append(_corner(img))
	if _f > 20 + 10 * SETUPS.size():
		var w := 0
		for c in _corners:
			w += c.get_width()
		var strip := Image.create(w, _corners[0].get_height(), false, _corners[0].get_format())
		var x := 0
		for c in _corners:
			strip.blit_rect(c, Rect2i(Vector2i.ZERO, c.get_size()), Vector2i(x, 0))
			x += c.get_width()
		strip.save_png(_out + "/hud_strip.png")
		print("SHOT ", _out)
		return true
	return false
