extends SceneTree
## Screenshots of the throw panel and the follow cam (needs a display).
##
##   godot --path . --resolution 1280x720 --script res://tools/flight_shots.gd -- <out_dir>
##
## 1 panel:   throw panel open, looking out from spawn.
## 2 follow:  VIEW (V) half a second into the flight.
## 3 late:    follow cam a few seconds in (watch the fade).
## 4 ground:  follow cam during ground play, just after landing.
## 5 back:    view handed back to the walker once the disc stopped.

var _main: Node
var _out := "/tmp/flight_shots"
var _frames := 0
var _disc: Node
var _landed_frame := -1


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and not args[0].begins_with("--"):
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _grab(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out, name]
	img.save_png(path)
	print("SHOT ", path)


func _process(_delta: float) -> bool:
	_frames += 1
	var thrower = _main.thrower
	var player: CharacterBody3D = _main.get_node("Player")
	if _frames == 10:
		thrower.panel.toggle()
		player.get_node("Head").rotation.x = deg_to_rad(12)   # launch angle = view
	if _frames == 40:
		_grab("1_panel")
		thrower.set_view(true)
		_disc = thrower.throw_disc(thrower.panel.params())
		thrower.panel.toggle()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _frames == 70:
		_grab("2_follow")
	if _frames == 220:
		_grab("3_late")
	if is_instance_valid(_disc) and _landed_frame < 0 and not _disc.flying:
		_landed_frame = _frames
	if _landed_frame > 0 and _frames == _landed_frame + 12:
		_grab("4_ground")
	if is_instance_valid(_disc) and _disc.resting and not thrower.follow_cam.active() \
			and _frames > _landed_frame + 20:
		_grab("5_back")
		print("REST carry %.1f m, rest %.1f m, landed on %s" % [_disc.flight_dist, _disc.distance(), _disc.landed_by])
		quit(0)
		return true
	if _frames > 60 * 40:
		quit(1)
		return true
	return false
