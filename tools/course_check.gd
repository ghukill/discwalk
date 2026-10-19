extends SceneTree
## Checks a course from a file (docs/COURSE_FORMAT.md): reads course.json,
## then builds each layout and looks at every hole. Exits 1 on any problem.
## Headless; made for whoever (or whatever) is writing the course.
##
##   godot --headless --path . --script res://tools/course_check.gd -- <id or folder> [--layout=<name>] [--block-size=1]
##
## The build uses 1 m blocks unless you pass --block-size= (it's checking
## where things are, not how they look). Per hole it reports the length and
## the ground under the tee and basket, and complains about:
##   - a tee or basket in the water, or on a slope (> 0.6 m across the pad)
##   - a tree trunk within 2 m of a basket (the game drops those, and trees
##     hanging over a tee pad, so this means the dropping broke)
##   - leaves over the tee pad, or a wall of leaves in the first 10 m off it
## Prints "CHECK PASS" or "CHECK FAIL".

const CourseFile := preload("res://scripts/course_file.gd")
const TERRAIN := preload("res://scripts/terrain.gd")

var _problems := 0
var _todo: Array[Dictionary] = []      ## Layouts still to build.
var _dir := ""
var _bs := 1.0
var _t: Node3D                         ## The terrain being checked.


func _initialize() -> void:
	var id := ""
	var only := ""
	var bs := 1.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--layout="):
			only = a.get_slice("=", 1)
		elif a.begins_with("--block-size="):
			bs = a.get_slice("=", 1).to_float()
		elif not a.begins_with("--"):
			id = a
	var dir := CourseFile.find(id)
	if dir == "":
		print("CHECK no course %s (looked in %s)" % [id, CourseFile.search_dirs()])
		quit(1)
		return
	var c := CourseFile.read(dir)
	print("CHECK %s (%s): %d x %d m, %d holes, %d trees, %d water, %d layouts" % [
		c.name, dir, c.size.x, c.size.y, c.holes.size(), c.trees.size(), c.water.size(), c.layouts.size()])
	for w in c.warnings:
		print("  warning: ", w)
	for e in c.errors:
		_problem(e)
	if not c.errors.is_empty():
		return
	if c.terrain.heightmap != "":
		var map := CourseFile.heightmap(dir.path_join(c.terrain.heightmap))
		if map.is_empty():
			_problem("can't read the heightmap %s" % c.terrain.heightmap)
		else:
			print("  heightmap %d x %d px = %.2f x %.2f m per px" % [map.w, map.h,
				c.size.x / map.w, c.size.y / map.h])
	for l: Dictionary in c.layouts:
		if only == "" or l.slug == CourseFile.slug(only):
			_todo.append(l)
	_dir = dir
	_bs = bs


## One layout per frame: add a terrain (it builds in _ready), check it next frame.
func _process(_delta: float) -> bool:
	if _t != null:
		_check_layout(_t, _todo.pop_front())
		root.remove_child(_t)
		_t.free()
		_t = null
	if _todo.is_empty():
		_finish()
		return true
	_t = Node3D.new()
	_t.set_script(TERRAIN)
	_t.world_kind = "course"
	_t.course_id = _dir
	_t.layout_name = _todo[0].name
	_t.block_size = _bs
	_t.set("_block_size_set", true)
	root.add_child(_t)
	return false


func _check_layout(t: Node3D, l: Dictionary) -> void:
	var b: Rect2 = l.bounds
	print("\n  layout %s: bounds %s .. %s (%d x %d m), %d holes, %d trees built" % [
		l.name, b.position, b.end, b.size.x, b.size.y, t.holes.size(), t.flora.trees.size()])
	if t.holes.size() != l.holes.size():
		_problem("layout %s: %d holes listed but %d built" % [l.name, l.holes.size(), t.holes.size()])
	for h: Dictionary in t.holes:
		_check_hole(t, h)


func _check_hole(t: Node3D, h: Dictionary) -> void:
	var tee := Vector2(h.tee.x, h.tee.z)
	var bk := Vector2(h.basket_at.x, h.basket_at.z)
	var line := "    hole %2d: %3.0f m  tee ground %.1f m  basket ground %.1f m (%+.1f)" % [
		h.n, h.length, h.tee.y, h.basket_at.y, h.basket_at.y - h.tee.y]
	var notes := []
	for p in [["tee", tee], ["basket", bk]]:
		var ix: int = t.col_x(p[1].x)
		var iz: int = t.col_z(p[1].y)
		if t.is_underwater(ix, iz):
			notes.append("%s is in the water" % p[0])
	# Pad slope, the way course.gd judges a generated tee.
	var fwd := Vector2(-sin(h.pad_yaw), -cos(h.pad_yaw))
	var right := Vector2(-fwd.y, fwd.x)
	var lo := 1e9
	var hi := -1e9
	for u in [-1.0, 0.0, 1.0]:
		for v in [-1.75, 0.0, 1.75]:
			var p: Vector2 = tee + right * u + fwd * v
			lo = minf(lo, t.height_at(p.x, p.y))
			hi = maxf(hi, t.height_at(p.x, p.y))
	if hi - lo > maxf(0.6, t.block_size):
		notes.append("tee pad rises %.1f m" % (hi - lo))
	var bs: float = t.block_size
	for tree: Dictionary in t.flora.trees:
		var tp := Vector2((tree.pos.x + 0.5) * bs, (tree.pos.y + 0.5) * bs)
		if tp.distance_to(bk) < 2.0:
			notes.append("a trunk %.1f m from the basket" % tp.distance_to(bk))
	# Leaves over the pad, then a clear-ish start down the fairway.
	var flora: Node3D = t.flora
	var over := 0
	var ground: float = t.height_at(tee.x, tee.y)
	for v in [-1.5, 0.0, 1.5]:
		var p: Vector2 = tee + fwd * v
		for up in [1.0, 2.0]:
			if flora.voxel_at(Vector3i(t.col_x(p.x), int(floor((ground + up) / bs)), t.col_z(p.y))) != 0:
				over += 1
	if over > 0:
		notes.append("leaves/bark over the tee pad")
	var blocked := 0
	for s in range(2, 12):
		var p: Vector2 = tee + fwd * s
		var g: float = t.height_at(p.x, p.y)
		if flora.voxel_at(Vector3i(t.col_x(p.x), int(floor((g + 1.5) / bs)), t.col_z(p.y))) != 0:
			blocked += 1
	if blocked >= 4:
		notes.append("the first 10 m off the tee are mostly leaves")
	print(line)
	for n in notes:
		_problem("hole %d: %s" % [h.n, n])


func _problem(text: String) -> void:
	_problems += 1
	print("  PROBLEM: ", text)


func _finish() -> void:
	print("\nCHECK " + ("PASS" if _problems == 0 else "FAIL (%d problems)" % _problems))
	quit(0 if _problems == 0 else 1)
