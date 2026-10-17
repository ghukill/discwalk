extends SceneTree
## Screenshots of Course Play (needs a real display/GPU).
##
##   godot --path . --resolution 1280x720 --script res://tools/course_shots.gd -- /tmp/shots [--block-size=1]
##
## Shots: hole 1 from its tee (HUD on), the tee pad from above, the shot
## circle after a goto, the hole overview, and the menu.

var _main: Node
var _out := "/tmp/shots"
var _step := 0
var _t0 := 0
var _frames := 0
var _cam: Camera3D


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
		_main.start_mode("course")
		_t0 = Time.get_ticks_msec()
	if _frames < 3:
		return false
	var el := Time.get_ticks_msec() - _t0
	var t = _main.get_node("Terrain")
	var th = _main.thrower
	var r = _main.course_round
	match _step:
		0:
			if el > 2500:
				_grab("course_tee")
				var h: Dictionary = t.holes[0]
				_cam = Camera3D.new()
				root.add_child(_cam)
				_cam.global_position = h.tee + Vector3(3.0, 6.0, 3.0)
				_cam.look_at(h.tee, Vector3.UP)
				_cam.make_current()
				_next()
		1:
			if el > 600:
				_grab("course_tee_pad")
				_cam.queue_free()
				_main.get_node("Player/Head/Camera3D").make_current()
				var p: Dictionary = th.setup.params()
				p.speed = 14.0
				p.pitch = 8.0
				th.throw_disc(p)
				_next()
		2:
			if th.has_lie() and el > 800:
				_grab("course_goto_circle")
				var head: Node3D = _main.get_node("Player/Head")
				head.rotation.x = deg_to_rad(-55)
				_next()
		3:
			if el > 400:
				_grab("course_circle_down")
				r.set_overview(true)
				_next()
		4:
			if el > 2200:
				_grab("course_overview")
				r.set_overview(false)
				_next()
		5:
			if el > 1800:
				_main.menu.open(true, true, true)
				_next()
		6:
			if el > 400:
				_grab("course_menu")
				quit(0)
				return true
	return false


func _next() -> void:
	_step += 1
	_t0 = Time.get_ticks_msec()


func _grab(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out, name]
	img.save_png(path)
	print("SHOT ", path)
