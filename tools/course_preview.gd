extends SceneTree
## Pictures of a course from a file, to check it by eye: a map from straight
## above (tees blue, baskets red, numbered), the view from every tee, and
## every basket from seven metres short of it.
## Needs a display/GPU.
##
##   godot --path . --resolution 1280x720 --script res://tools/course_preview.gd -- <out_dir> --course=<id> [--layout=<name>] [--block-size=1]
##
## Writes <out_dir>/map.png, <out_dir>/tee_<n>.png and <out_dir>/basket_<n>.png. --block-size=1 builds
## quickest; leave it off to see the layout's own block size.

var _main: Node
var _out := "user://course_preview"
var _frames := 0
var _shots: Array = []              ## [name, camera transform, orthographic size (0 = perspective)]
var _cam: Camera3D
var _marks: Node3D


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
		_setup()
	if _frames < 12:
		return false
	var i := (_frames - 12) / 4
	if i >= _shots.size():
		quit(0)
		return true
	var s: Array = _shots[i]
	if (_frames - 12) % 4 == 0:
		_marks.visible = s[0] == "map"
		_main.get_node("WorldEnvironment").environment.fog_enabled = s[0] != "map"
		_cam.global_transform = s[1]
		_cam.projection = Camera3D.PROJECTION_ORTHOGONAL if s[2] > 0.0 else Camera3D.PROJECTION_PERSPECTIVE
		_cam.size = s[2] if s[2] > 0.0 else 1.0
	elif (_frames - 12) % 4 == 3:
		var path := "%s/%s.png" % [_out, s[0]]
		root.get_viewport().get_texture().get_image().save_png(path)
		print("SHOT ", path)
	return false


func _setup() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var t: Node3D = _main.get_node("Terrain")
	if t.world_kind != "course":
		push_error("course_preview: pass --course=<id>")
		quit(1)
		return
	_main.get_node("HUD").visible = false
	_main.clouds.visible = false
	_main.get_node("Player").visible = false
	_main.get_node("Player").set_physics_process(false)
	_cam = Camera3D.new()
	_cam.far = 3000.0
	root.add_child(_cam)
	_cam.make_current()

	# Big markers for the map: a disc and a number over every tee and basket.
	_marks = Node3D.new()
	root.add_child(_marks)
	var span := maxf(t.world_x, t.world_z)
	for h: Dictionary in t.holes:
		_mark(h.tee, Color(0.25, 0.6, 1.0), str(h.n), span)
		_mark(h.basket_at, Color(1.0, 0.25, 0.2), "", span)

	var aspect := float(root.size.x) / float(root.size.y)
	var top := 400.0
	var c := Vector3(t.world_x / 2.0, top, t.world_z / 2.0)
	var map := Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.FORWARD), c)
	_shots.append(["map", map, maxf(t.world_z, t.world_x / aspect) * 1.02])
	for h: Dictionary in t.holes:
		var fwd := Vector3(-sin(h.yaw), 0, -cos(h.yaw))
		var eye: Vector3 = h.tee - fwd * 1.5 + Vector3(0, 1.7, 0)
		var look: Vector3 = h.basket_at + Vector3(0, 1.0, 0)
		if h.basket_at.distance_to(h.tee) > 1.0 and absf(fwd.dot((look - eye).normalized())) < 0.5:
			look = eye + fwd * 20.0          # a dogleg: look down the fairway
		_shots.append(["tee_%d" % h.n, Transform3D(Basis.looking_at(look - eye, Vector3.UP), eye), 0.0])
		# And the basket from a few paces short of it, on the line of play:
		# the shot you take walking up to it, and the one a photograph of the
		# real hole is nearly always taken from.
		var to: Vector3 = h.basket_at - h.tee
		to.y = 0.0
		if to.length() > 9.0:
			var up: Vector3 = h.basket_at - to.normalized() * 7.0 + Vector3(0, 1.7, 0)
			var at: Vector3 = h.basket_at + Vector3(0, 0.9, 0)
			_shots.append(["basket_%d" % h.n,
				Transform3D(Basis.looking_at(at - up, Vector3.UP), up), 0.0])


func _mark(at: Vector3, color: Color, text: String, span: float) -> void:
	var r := span / 160.0
	var disc := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material = mat
	disc.mesh = m
	disc.position = at + Vector3(0, 60.0, 0)
	_marks.add_child(disc)
	if text != "":
		var l := Label3D.new()
		l.text = text
		l.pixel_size = span / 900.0
		l.font_size = 48
		l.outline_size = 12
		l.modulate = Color.WHITE
		l.rotation_degrees = Vector3(-90, 0, 0)
		l.position = at + Vector3(r * 2.4, 61.0, -r * 1.6)
		_marks.add_child(l)
