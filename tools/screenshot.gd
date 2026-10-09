extends SceneTree
## Renders a few PNG screenshots of the world (needs a real display/GPU).
##
##   godot --path . --script res://tools/screenshot.gd -- <out_dir>

var _main: Node
var _frames := 0
var _shot := 0
var _out := "user://shots"
var _views: Array = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_plan_views()
	if _frames < 30:
		return false
	# Each view: set up, wait 20 frames for physics/shadows, grab.
	var idx := (_frames - 30) / 20
	var phase := (_frames - 30) % 20
	if idx >= _views.size():
		quit(0)
		return true
	var v: Dictionary = _views[idx]
	var player: CharacterBody3D = _main.get_node("Player")
	var cam: Camera3D = player.get_node("Head/Camera3D")
	if phase == 0:
		player.set_physics_process(false)
		player.global_position = v.pos
		player.look_at(Vector3(v.look.x, player.global_position.y, v.look.z), Vector3.UP)
		var head: Node3D = player.get_node("Head")
		head.rotation.x = v.pitch
	elif phase == 19:
		var img := root.get_viewport().get_texture().get_image()
		var path := "%s/%02d_%s.png" % [_out, idx, v.name]
		img.save_png(path)
		print("SHOT ", path)
	return false


func _plan_views() -> void:
	var t = _main.get_node("Terrain")
	var s: float = t.size
	var spawn: Vector3 = t.spawn_point()
	var lake: Dictionary = t.lakes[0]
	var best := 1e9
	for l in t.lakes:
		var d: float = Vector2(spawn.x, spawn.z).distance_to(l.center)
		if d < best:
			best = d
			lake = l
	var lc: Vector3 = Vector3(lake.center.x, lake.water_y, lake.center.y)
	var to_spawn := (Vector3(spawn.x, 0, spawn.z) - Vector3(lc.x, 0, lc.z)).normalized()
	var shore: Vector3 = lc + to_spawn * (lake.radius + 3.0)
	shore.y = t.height_at(shore.x, shore.z) + 0.05
	_views = [
		{"name": "spawn_eye", "pos": spawn + Vector3(0, -0.95, 0), "look": lc, "pitch": -0.05},
		{"name": "lakeshore", "pos": shore, "look": lc, "pitch": -0.25},
		{"name": "overview", "pos": Vector3(s * 0.12, 60, s * 0.12), "look": Vector3(s * 0.55, 0, s * 0.55), "pitch": -0.55},
	]
