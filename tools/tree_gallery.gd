extends SceneTree
## Renders a gallery of oak shapes on flat ground: one row per form, three
## examples each (different sizes and seeds). Handy for
## tuning tree shapes without hunting for them in a generated world.
## Needs a display/GPU.
##
##   godot --path . --script res://tools/tree_gallery.gd -- <out_dir> [--block-size=0.25] [--seed=N]

const ROWS := [
	["spreading", ["giant", "big", "medium"]],
	["tall", ["big", "big", "medium"]],
	["forked", ["giant", "big", "medium"]],
	["leaning", ["big", "medium", "medium"]],
	["sapling", ["sapling", "sapling", "sapling"]],
]
## (The rows are far apart so each view only shows its own row.)
const ROW_GAP := 60.0
const COL_GAP := 22.0

var _main: Node
var _frames := 0
var _out := "user://gallery"
var _views: Array = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and not args[0].begins_with("--"):
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	_main = load("res://scenes/main.tscn").instantiate()
	var t: Node3D = _main.get_node("Terrain")
	for a in args:
		if a.begins_with("--seed="):
			t.world_seed = a.get_slice("=", 1).to_int()
	t.hill_height = 0.0
	t.lake_count = 0
	t.moraine_height = 2.0
	t.world_size = 320.0
	var preset := []
	for r in ROWS.size():
		for c in 3:
			preset.append({"x": 70.0 + c * COL_GAP, "z": 30.0 + r * ROW_GAP,
				"kind": ROWS[r][1][c], "form": ROWS[r][0]})
	t.flora_preset = preset
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		var t = _main.get_node("Terrain")
		var ground: float = t.height_at(100, 100)
		for r in ROWS.size():
			var z := 30.0 + r * ROW_GAP
			_views.append({"name": "%d_%s" % [r, ROWS[r][0]],
				"pos": Vector3(70.0 + COL_GAP, ground + 2.5, z - 27.0),
				"look": Vector3(70.0 + COL_GAP, ground + 5.5, z)})
			# Close-up from under the biggest one, looking up into the limbs.
			_views.append({"name": "%d_%s_under" % [r, ROWS[r][0]],
				"pos": Vector3(70.0 + 5.0, ground + 1.6, z - 6.0),
				"look": Vector3(70.0, ground + 6.0, z)})
	if _frames < 30:
		return false
	var idx := (_frames - 30) / 20
	var phase := (_frames - 30) % 20
	if idx >= _views.size():
		quit(0)
		return true
	var v: Dictionary = _views[idx]
	var player: CharacterBody3D = _main.get_node("Player")
	if phase == 0:
		player.set_physics_process(false)
		player.global_position = v.pos - Vector3(0, 1.6, 0)
		var head: Node3D = player.get_node("Head")
		head.rotation = Vector3.ZERO
		player.rotation = Vector3.ZERO
		player.get_node("Head/Camera3D").look_at(v.look, Vector3.UP)
	elif phase == 19:
		var img := root.get_viewport().get_texture().get_image()
		var path := "%s/%s.png" % [_out, v.name]
		img.save_png(path)
		print("SHOT ", path)
	return false
