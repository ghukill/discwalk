extends SceneTree
## Screenshots of the basket (needs a display): close up, from the tee, a
## putt on its way in, and a disc resting in the tray.
##
##   godot --path . --resolution 1280x720 --script res://tools/basket_shots.gd -- <out_dir>

var _main: Node
var _out := "/tmp/basket_shots"
var _f := 0
var _done := false


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
	if _f > 10:
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
	var t = _main.get_node("Terrain")
	var th = _main.thrower
	var b = t.basket
	# Put the hole somewhere open and close by, so the shots are about the
	# basket rather than whatever the seed happened to grow around it.
	var tee: Vector3 = t.spawn_point()
	var at := tee + Vector3(0, 0, -6.0)
	_main.hole.start(tee, at)
	var c: Vector3 = b.global_position

	var cam := Camera3D.new()
	cam.far = 500
	cam.fov = 70
	root.add_child(cam)
	cam.current = true

	cam.global_position = c + Vector3(1.6, 1.5, 1.6)
	cam.look_at(c + Vector3(0, 0.9, 0), Vector3.UP)
	await _frames(15)
	_grab("1_close")

	cam.global_position = tee + Vector3(0, 1.6, 0)
	cam.look_at(c + Vector3(0, 1.0, 0), Vector3.UP)
	await _frames(10)
	_grab("2_from_tee")

	# A putt, caught in flight and then at rest in the tray. throw_disc aims
	# where the PLAYER is facing, so turn them at the basket first.
	# Stand exactly on the tee: the release point is relative to the player,
	# so a stray metre of height turns a made putt into one over the band.
	var player: CharacterBody3D = _main.get_node("Player")
	player.global_position = tee
	var to_basket := (c - tee) * Vector3(1, 0, 1)
	player.rotation.y = atan2(-to_basket.x, -to_basket.z)
	await _frames(2)
	# A 6 m putt at 10 m/s released slightly nose-down goes in: the flight
	# model lofts anything thrown level, so a flat putt sails over the band.
	var p: Dictionary = th.setup.params()
	p.speed = 10.0
	p.pitch = -6.0
	p.roll = 0.0
	p.spin = 5.2 * 10.0
	var disc = th.throw_disc(p)
	cam.global_position = c + Vector3(4.5, 1.4, 2.6)
	cam.look_at(c + Vector3(0, 1.0, 0), Vector3.UP)
	await _frames(8)
	_grab("3_putt")
	await _frames(90)
	_grab("4_in_the_tray")
	print("BASKET_SHOTS holed=%s strokes=%d" % [b.holed != null, _main.hole.strokes])
	quit(0)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
