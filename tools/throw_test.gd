extends SceneTree
## Headless disc-throw check: throws at a few powers across open ground, one
## straight into an oak, one into a lake, and reports where each came to rest.
##
##   godot --headless --path . --script res://tools/throw_test.gd [-- --block-size=0.5]

var _main: Node
var _frames := 0
var _plan: Array = []
var _discs: Array = []


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 5:
		_launch_all()
	if _frames < 5 + 60 * 25 and not _all_rested():
		return false
	var ok := true
	for i in _discs.size():
		var d = _discs[i]
		var name: String = _plan[i].name
		if not is_instance_valid(d):
			print("THROW %-10s lost (fell out of world)" % name)
			ok = false
			continue
		print("THROW %-10s power=%2d dist=%5.1f m peak=%4.1f m rest=%s bark=%d leaves=%d splash=%s" % [
			name, d.power, d.distance(), d.max_height, d.resting, d.bark_hits, d.leaf_cells, d.splashed])
		ok = ok and d.resting
	var tree_d = _discs[_plan.size() - 2]
	var lake_d = _discs[_plan.size() - 1]
	ok = ok and is_instance_valid(tree_d) and (tree_d.bark_hits > 0 or tree_d.leaf_cells > 0)
	ok = ok and is_instance_valid(lake_d) and lake_d.splashed
	print("THROW " + ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
	return true


func _all_rested() -> bool:
	if _discs.is_empty():
		return false
	for d in _discs:
		if is_instance_valid(d) and not d.resting:
			return false
	return true


func _launch_all() -> void:
	var t = _main.get_node("Terrain")
	var thrower = _main.thrower
	var bs: float = t.block_size
	var spawn: Vector3 = t.spawn_point()
	# Open-ground throws from spawn, spread around the compass at 15 deg up.
	for k in 4:
		var p: int = [2, 5, 8, 10][k]
		var a := TAU * k / 4.0
		_plan.append({"name": "open_p%d" % p, "power": p, "from": spawn + Vector3(0, 0.6, 0),
			"dir": Vector3(cos(a) * cos(0.26), sin(0.26), sin(a) * cos(0.26))})
	# Straight at the biggest oak's crown from 12 m away.
	var oak: Dictionary = t.flora.trees[0]
	for tr in t.flora.trees:
		if tr.crown > oak.crown:
			oak = tr
	var oc := Vector3((oak.pos.x + 0.5) * bs, 0, (oak.pos.y + 0.5) * bs)
	oc.y = t.height_at(oc.x, oc.z) + 2.0
	# Stand 12 m away on whichever side is lowest/most open, aim at the trunk.
	var from := oc + Vector3(12, 0, 0)
	var best := 1e9
	for k in 8:
		var a := TAU * k / 8.0
		var f := oc + Vector3(cos(a), 0, sin(a)) * 12.0
		f.y = t.height_at(f.x, f.z) + 1.6
		var score: float = absf(f.y - oc.y) + (100.0 if t.lake_edge_distance(f.x, f.z) < 1.0 else 0.0)
		if score < best:
			best = score
			from = f
	_plan.append({"name": "into_oak", "power": 6, "from": from, "dir": (oc - from).normalized()})
	# Lob into the middle of a lake.
	var lake: Dictionary = t.lakes[0]
	var lc := Vector3(lake.center.x, lake.water_y, lake.center.y)
	var lf := lc + Vector3(lake.radius + 4.0, 0, 0)
	lf.y = t.height_at(lf.x, lf.z) + 1.6
	var flat := (lc - lf)
	var dist := Vector2(flat.x, flat.z).length()
	_plan.append({"name": "into_lake", "power": 0, "from": lf,
		"dir": (Vector3(flat.x, 0, flat.z).normalized() + Vector3(0, 1, 0)).normalized(),
		"speed": sqrt(9.8 * dist)})
	for pl in _plan:
		var d = thrower.throw(maxi(pl.power, 1))
		var speed: float = pl.get("speed", pl.power * thrower.speed_per_level)
		d.launch(pl.from, pl.dir * speed, Vector3(3, 5, 2))
		_discs.append(d)
	thrower.max_discs = 100
