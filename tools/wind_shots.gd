extends SceneTree
## Screenshots of the wind (needs a display):
##   godot --path . --resolution 1600x900 --script res://tools/wind_shots.gd -- <out_dir> [--block-size=1]
## Saves wind_strip.png (the HUD block in five winds: calm, a light tailwind,
## 10 mph left to right, a 20 mph headwind, a gale on the quarter),
## wind_hud.png (one of them, large) and wind_streaks.png (the whole frame in
## a 20 mph crosswind, streaks and all).

var _main: Node
var _out := "/tmp/wind_shots"
var _f := 0
const WINDS := [  # mph, from (deg); you face north
	[0.0, 270.0], [5.0, 180.0], [10.0, 270.0], [20.0, 0.0], [30.0, 45.0]]
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
	var wind: RefCounted = _main.thrower.wind
	if _f == 5:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		wind.set_gustiness(0.0)
		_main.get_node("Player").rotation.y = 0.0
		_main.get_node("Player/Head").rotation.x = deg_to_rad(6)
	var i := (_f - 20) / 10
	if _f >= 20 and (_f - 20) % 10 == 0 and i < WINDS.size():
		wind.set_from(WINDS[i][1])
		wind.set_speed_mph(WINDS[i][0])
	if _f >= 20 and (_f - 20) % 10 == 6 and i < WINDS.size():
		var img := root.get_viewport().get_texture().get_image()
		if i == 2:
			_corner(img).save_png(_out + "/wind_hud.png")
		_corners.append(_corner(img))
	var after := 20 + 10 * WINDS.size()
	if _f == after:
		wind.set_from(270.0)
		wind.set_speed_mph(20.0)
	if _f == after + 150:                      # streaks have faded in and spread out
		root.get_viewport().get_texture().get_image().save_png(_out + "/wind_streaks.png")
		var w := 0
		for c in _corners:
			w += c.get_width()
		var strip := Image.create(w, _corners[0].get_height(), false, _corners[0].get_format())
		var x := 0
		for c in _corners:
			strip.blit_rect(c, Rect2i(Vector2i.ZERO, c.get_size()), Vector2i(x, 0))
			x += c.get_width()
		strip.save_png(_out + "/wind_strip.png")
		print("SHOT ", _out)
		return true
	return false
