extends SceneTree
## One view of a course, from anywhere to anywhere, in course metres. The
## preview shoots tees and baskets; this is for everything in between -- the
## wall of trees you have to throw round, a ditch, the car park -- and for
## standing where a photograph was taken so the two can be held side by side.
## Needs a display/GPU.
##
##   godot --path . --resolution 1280x720 --script res://tools/course_spot.gd \
##       -- <out.png> --course=<id> --from=<x>,<z> --to=<x>,<z> [--layout=<name>]
##       [--eye=1.7] [--aim=1.0] [--block-size=1]
##
## --eye and --aim are heights in metres over the ground at each end.

const CourseFile := preload("res://scripts/course_file.gd")

var _main: Node
var _out := "user://spot.png"
var _from := Vector2.ZERO
var _to := Vector2.ONE
var _eye := 1.7
var _aim := 1.0
var _frames := 0


func _initialize() -> void:
	var course := "morley-field"
	var layout := ""
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_out = a
		elif a.begins_with("--course="):
			course = a.get_slice("=", 1)
		elif a.begins_with("--layout="):
			layout = a.get_slice("=", 1)
		elif a.begins_with("--from="):
			_from = _xz(a.get_slice("=", 1))
		elif a.begins_with("--to="):
			_to = _xz(a.get_slice("=", 1))
		elif a.begins_with("--eye="):
			_eye = a.get_slice("=", 1).to_float()
		elif a.begins_with("--aim="):
			_aim = a.get_slice("=", 1).to_float()
	_main = load("res://scenes/main.tscn").instantiate()
	var t: Node3D = _main.get_node("Terrain")
	t.world_kind = "course"
	t.course_id = CourseFile.find(course)
	if layout != "":
		t.layout_name = layout
	root.add_child(_main)


static func _xz(s: String) -> Vector2:
	var p := s.split(",")
	return Vector2(p[0].to_float(), p[1].to_float()) if p.size() > 1 else Vector2.ZERO


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 40:
		return false
	var t: Node3D = _main.get_node("Terrain")
	var a: Vector2 = t.to_world(_from)
	var b: Vector2 = t.to_world(_to)
	var eye := Vector3(a.x, t.height_at(a.x, a.y) + _eye, a.y)
	var look := Vector3(b.x, t.height_at(b.x, b.y) + _aim, b.y)
	var player: CharacterBody3D = _main.get_node("Player")
	player.set_physics_process(false)
	player.global_position = eye - Vector3(0, 1.6, 0)
	player.rotation = Vector3.ZERO
	_main.get_node("Player/Head").rotation = Vector3.ZERO
	_main.get_node("Player/Head/Camera3D").look_at(look, Vector3.UP)
	if _frames < 44:          # a few frames for the camera to settle
		return false
	root.get_viewport().get_texture().get_image().save_png(_out)
	print("SHOT ", _out)
	quit(0)
	return true
