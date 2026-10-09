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
	var s: float = t.world_size
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
	# A tree to admire, and a flowery meadow patch.
	var flora = t.flora
	var oak: Dictionary = flora.trees[0]
	for tr in flora.trees:
		if tr.kind == "giant" or (tr.kind == "big" and oak.kind != "giant"):
			oak = tr
			if tr.kind == "giant":
				break
	var op := Vector3((oak.pos.x + 0.5) * t.block_size, 0, (oak.pos.y + 0.5) * t.block_size)
	var oak_eye := op + Vector3(oak.crown * 2.2, 0, oak.crown * 1.4)
	oak_eye.y = t.height_at(oak_eye.x, oak_eye.z) + 0.05
	op.y = oak_eye.y + 1.0
	var meadow := _flowery_spot(t)
	var portraits := _form_portraits(t)
	_views = [
		{"name": "oak", "pos": oak_eye, "look": op, "pitch": 0.12},
		{"name": "meadow", "pos": meadow[0], "look": meadow[1], "pitch": -0.32},
		{"name": "spawn_eye", "pos": spawn + Vector3(0, -0.95, 0), "look": lc, "pitch": -0.05},
		{"name": "lakeshore", "pos": shore, "look": lc, "pitch": -0.25},
		{"name": "overview", "pos": Vector3(s * 0.12, 60, s * 0.12), "look": Vector3(s * 0.55, 0, s * 0.55), "pitch": -0.55},
	]
	_views.append_array(portraits)


## Finds the densest meadow-flower spot; returns [eye position, look target].
func _flowery_spot(t) -> Array:
	var best := Vector3(t.world_size / 2.0, 0, t.world_size / 2.0)
	var best_n := -1
	var grid := {}
	for mmi in t.flora.get_node("Flowers").get_children():
		if mmi.name.begins_with("trillium") or mmi.name.begins_with("marsh") or mmi.name.begins_with("blue"):
			continue
		var mm: MultiMesh = mmi.multimesh
		for k in mm.instance_count:
			var p: Vector3 = mm.get_instance_transform(k).origin
			var key := Vector2i(int(p.x / 8), int(p.z / 8))
			grid[key] = grid.get(key, 0) + 1
			if grid[key] > best_n:
				best_n = grid[key]
				best = Vector3(key.x * 8 + 4, 0, key.y * 8 + 4)
	var eye := best + Vector3(-5, 0, -5)
	eye.y = t.height_at(eye.x, eye.z) + 0.05
	best.y = eye.y
	return [eye, best]


## One "portrait" per oak form: the most open-standing example of each form,
## seen from a few crown-widths away.
func _form_portraits(t) -> Array:
	var bs: float = t.block_size
	var out := []
	var rank := {"giant": 3, "big": 2, "medium": 1, "sapling": 0}
	for form in ["spreading", "tall", "forked", "leaning", "sapling"]:
		var best = null
		var best_score := -1e9
		for tr in t.flora.trees:
			if tr.form != form:
				continue
			var p := Vector2((tr.pos.x + 0.5) * bs, (tr.pos.y + 0.5) * bs)
			var crowd := 0.0
			for o in t.flora.trees:
				var d := p.distance_to(Vector2((o.pos.x + 0.5) * bs, (o.pos.y + 0.5) * bs))
				if d > 0.1 and d < 16.0:
					crowd += 1.0
			var score: float = rank[tr.kind] * 3.0 - crowd
			if score > best_score:
				best_score = score
				best = tr
		if best == null:
			continue
		var c := Vector3((best.pos.x + 0.5) * bs, 0, (best.pos.y + 0.5) * bs)
		var dist: float = best.crown * 2.4 + 5.0
		# Look from whichever of 8 directions has the fewest trees in the way.
		var eye := c
		var fewest := 1 << 30
		for k in 8:
			var a := TAU * k / 8.0
			var e := c + Vector3(cos(a), 0, sin(a)) * dist
			if e.x < 8 or e.z < 8 or e.x > t.world_size - 8 or e.z > t.world_size - 8:
				continue
			if t.lake_edge_distance(e.x, e.z) < 2.0:
				continue
			var blockers := 0
			for o in t.flora.trees:
				var op := Vector3((o.pos.x + 0.5) * bs, 0, (o.pos.y + 0.5) * bs)
				if op.distance_to(c) < 0.5:
					continue
				# distance from o to the eye->tree segment
				var seg: Vector3 = c - e
				var u := clampf((op - e).dot(seg) / seg.length_squared(), 0.0, 1.0)
				if (e + seg * u).distance_to(op) < float(o.crown) * 0.9:
					blockers += 1
			if blockers < fewest:
				fewest = blockers
				eye = e
		eye.y = t.height_at(eye.x, eye.z) + 0.05
		var look := c
		look.y = eye.y + 1.0
		out.append({"name": "form_" + form, "pos": eye, "look": look,
			"pitch": clampf(atan2(best.crown * 0.9, dist), 0.05, 0.45)})
	return out
