extends SceneTree
## Screenshots of a basket and its confetti (needs a real display/GPU).
##
##   DISPLAY=:0 godot --path . --resolution 1280x720 --script res://tools/basket_shots.gd -- /tmp/shots [--block-size=1]
##
## Shots: a close-up, the basket from putting distance, and a confetti burst
## caught mid-air and again as it lands.

var _main: Node
var _out := "/tmp/shots"
var _cam: Camera3D
var _b: Node3D
var _t0 := 0
var _step := 0
var _frames := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_out = a
	DirAccess.make_dir_recursive_absolute(_out)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 3:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_main.get_node("HUD").visible = false
		var t = _main.get_node("Terrain")
		_b = t.baskets[0]
		_main.player.global_position = _b.global_position + Vector3(0, 1, 30)
		_cam = Camera3D.new()
		_cam.fov = 60.0
		root.add_child(_cam)
		_cam.make_current()
		_view(Vector3(1.6, 1.15, 1.9), Vector3(0, 0.85, 0))
		_t0 = Time.get_ticks_msec()
	if _frames < 3:
		return false
	var el := Time.get_ticks_msec() - _t0
	match _step:
		0:
			if el > 1500:
				_grab("basket_close")
				_view(Vector3(4.5, 1.6, 7.5), Vector3(0, 0.8, 0))
				_next()
		1:
			if el > 800:
				_grab("basket_putt")
				_view(Vector3(3.0, 1.5, 5.5), Vector3(0, 1.6, 0))
				_b.celebrate()
				_next()
		2:
			if el > 450:
				_grab("confetti_burst")
				_next()
		3:
			if el > 1500:
				_grab("confetti_falling")
				_next()
		4:
			if el > 1300:
				_view(Vector3(2.2, 1.3, 3.2), Vector3(0, 0.2, 0))
				_next()
		5:
			if el > 300:
				_grab("confetti_landed")
				quit(0)
				return true
	return false


func _next() -> void:
	_step += 1
	_t0 = Time.get_ticks_msec()


## Camera at `eye` looking at `at`, both relative to the basket's foot.
func _view(eye: Vector3, at: Vector3) -> void:
	var c := _b.global_position
	_cam.global_position = c + eye
	_cam.look_at(c + at, Vector3.UP)


func _grab(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out, name]
	img.save_png(path)
	print("SHOT ", path)
