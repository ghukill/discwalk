extends SceneTree
## Screenshots of flight paths (needs a display): three throws (dd2 hyzer,
## cd1 flat, cd5 anhyzer) seen from behind the tee and from the side, then
## P mid-fall and just after.
##
##   godot --path . --resolution 1280x720 --script res://tools/paths_shots.gd -- <out_dir>

var _main: Node
var _out := "/tmp/paths_shots"
var _f := 0
var _discs: Array = []
var _done := false
const THROWS := [[24.0, 12.0, 10.0, "dd2"], [18.0, 8.0, 0.0, "cd1"], [20.0, 10.0, -10.0, "cd5"]]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and not args[0].begins_with("--"):
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_d: float) -> bool:
	_f += 1
	if _done:
		return false
	var th = _main.thrower
	var k := [10, 70, 130].find(_f)
	if k >= 0:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		var s: Array = THROWS[k]
		var p: Dictionary = th.panel.params()
		p.speed = s[0]
		p.pitch = s[1]
		p.roll = s[2]
		p.spin = 5.2 * s[0]
		for m in th.disc_models:
			if m.id == s[3]:
				p.disc = m
		_discs.append(th.throw_disc(p))
	if _f > 140 and _discs.all(func(d) -> bool: return is_instance_valid(d) and d.resting):
		_done = true
		_shoot()
	if _f > 60 * 40:
		quit(1)
	return false


func _grab(name: String) -> void:
	var path := "%s/%s.png" % [_out, name]
	root.get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path)


func _shoot() -> void:
	var th = _main.thrower
	var t = _main.get_node("Terrain")
	var start: Vector3 = _discs[0].start
	var end: Vector3 = _discs[0].global_position
	var mid := (start + end) / 2.0
	var dir := ((end - start) * Vector3(1, 0, 1)).normalized()
	var side := dir.cross(Vector3.UP)
	var cam := Camera3D.new()
	cam.far = 500
	cam.fov = 70
	root.add_child(cam)
	cam.current = true
	cam.global_position = start - dir * 5.0 + Vector3(0, 4, 0)
	cam.look_at(mid + Vector3(0, 1, 0), Vector3.UP)
	await _frames(15)
	_grab("1_behind")
	var cp := mid + side * 30.0
	cp.y = maxf(t.height_at(cp.x, cp.z), mid.y) + 5.0
	cam.global_position = cp
	cam.look_at(mid + Vector3(0, 2, 0), Vector3.UP)
	await _frames(15)
	_grab("2_side")
	cam.global_position = start - dir * 3.0 + side * 2.0 + Vector3(0, 2.5, 0)
	cam.look_at(start + dir * 12.0 + Vector3(0, 1.5, 0), Vector3.UP)
	await _frames(10)
	_grab("3_close")
	th.paths.clear(true)                      # P
	await _frames(40)
	_grab("4_falling")
	await _frames(55)
	_grab("5_poof")
	await _frames(120)
	_grab("6_gone")
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame
