extends Node
## Throwing discs.
##
##   T        show/hide the throw panel (lower right): pick a disc, set speed,
##            launch angle, nose, hyzer/anhyzer, spin, press Throw. A real
##            flying disc (flying_disc.gd) leaves along where you're looking.
##   1-9, 0   set power 1..10 (0 = 10) for the orange blocks
##   click    fire an orange block at the current power (step 1, kept as-is)
##   F        fetch: teleport to your last disc. If it's still flying, you
##            take over its speed and direction and fly on with it.
##   V        follow cam: chase your last disc until it fully stops (V again
##            to come back early)
##   P        paths on/off (starts on). On: every disc throw leaves a path,
##            bright cubes in the air, dimmer ones for skips and rolls. Off:
##            existing paths drift down and go poof, and new throws leave
##            none until you turn them back on. Also a checkbox in the panel.
##   B        toggle the beams of light over resting discs
##   C        collect: every disc rolls home to you, building up speed
##
## Power p launches at p x speed_per_level m/s (default 4 m/s per level, so
## 0 = 40 m/s, about a strong disc golf drive). Aim is your view direction.

const DISC_SCRIPT := preload("res://scripts/disc.gd")
const FLYING_DISC_SCRIPT := preload("res://scripts/flying_disc.gd")
const DiscModel := preload("res://scripts/disc_model.gd")
const ThrowPanel := preload("res://scripts/throw_panel.gd")
const FollowCam := preload("res://scripts/follow_cam.gd")
const Paths := preload("res://scripts/paths.gd")

@export var speed_per_level := 4.0
@export var max_discs := 12          ## Older discs are cleared away.

var terrain: Node3D
var player: CharacterBody3D
var camera: Camera3D
var label: Label
var status_label: Label                  ## Upper-right: power + beams.
var hud: CanvasLayer                     ## Where the throw panel goes.
var panel: PanelContainer
var follow_cam: Camera3D
var paths: Node3D
var disc_models: Array = []

var power := 5
var beams := true
var paths_on := true                     ## New disc throws leave a path.
var discs: Array = []
var _last: Node = null
var _flying_text := ""
var _result_text := ""
var _collected := 0


func _ready() -> void:
	disc_models = DiscModel.load_all()
	panel = ThrowPanel.new()
	panel.name = "ThrowPanel"
	panel.discs = disc_models
	panel.throw_requested.connect(func(p: Dictionary) -> void: throw_disc(p))
	panel.paths_toggled.connect(func(on: bool) -> void: set_paths(on))
	if hud != null:
		hud.add_child(panel)
	follow_cam = FollowCam.new()
	follow_cam.name = "FollowCam"
	follow_cam.terrain = terrain
	follow_cam.player_camera = camera
	add_child(follow_cam)
	follow_cam.ended.connect(_update_label)
	paths = Paths.new()
	paths.name = "Paths"
	paths.terrain = terrain
	add_child(paths)
	_update_label()


func _unhandled_input(event: InputEvent) -> void:
	for level in range(1, 11):
		if event.is_action_pressed("throw_%d" % level):
			power = level
			_update_label()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("fetch"):
		fetch()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("clear_paths"):
		set_paths(not paths_on)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("follow_cam"):
		toggle_follow()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("throw_panel"):
		if panel.is_inside_tree():
			panel.toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("collect"):
		collect()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("beams"):
		set_beams(not beams)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		throw(power)
		get_viewport().set_input_as_handled()


## Launches a disc from just in front of the camera.
func throw(level: int) -> Node:
	var fwd := -camera.global_transform.basis.z
	var origin := camera.global_position + fwd * 0.5
	var disc: RigidBody3D = RigidBody3D.new()
	disc.set_script(DISC_SCRIPT)
	disc.name = "Disc"
	disc.terrain = terrain
	disc.power = level
	disc.beam_on = beams
	get_parent().add_child(disc)
	disc.add_collision_exception_with(player)   # don't bonk yourself
	var vel := fwd * level * speed_per_level + player.velocity
	var spin := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 8.0
	disc.launch(origin, vel, spin)
	disc.came_to_rest.connect(_on_rest)
	disc.tree_exited.connect(func() -> void: discs.erase(disc))
	discs.append(disc)
	_last = disc
	_collected = 0
	while discs.size() > max_discs:
		var old: Node = discs.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	_result_text = ""
	return disc


## Throws a real flying disc. p: {disc, speed, pitch, nose, roll, spin,
## hand?}; aim is the flat direction you're looking.
func throw_disc(p: Dictionary) -> Node:
	var look := -camera.global_transform.basis.z
	var fwd := Vector3(look.x, 0, look.z)
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var hand: float = p.get("hand", 1.0)
	var ls := DiscModel.launch_state(fwd, p.speed, p.pitch, p.nose, p.roll, hand)
	# Release about shoulder height, a little ahead of you.
	var origin := player.global_position + Vector3(0, 1.3, 0) + fwd * 0.6
	var disc: RigidBody3D = RigidBody3D.new()
	disc.set_script(FLYING_DISC_SCRIPT)
	disc.name = "FlyingDisc"
	disc.terrain = terrain
	disc.model = p.disc
	disc.color = paths.next_color()      # disc, beam and path share a colour
	disc.beam_on = beams
	get_parent().add_child(disc)
	disc.add_collision_exception_with(player)
	disc.launch_disc(origin, ls[0] + Vector3(player.velocity.x, 0, player.velocity.z), ls[1], p.spin, hand)
	if paths_on:
		paths.track(disc, disc.color)
	disc.came_to_rest.connect(_on_rest)
	disc.tree_exited.connect(func() -> void: discs.erase(disc))
	discs.append(disc)
	_last = disc
	_collected = 0
	while discs.size() > max_discs:
		var old: Node = discs.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	_result_text = ""
	return disc


## Sends every disc rolling home to the player.
func collect() -> void:
	var n := 0
	for d in discs:
		if is_instance_valid(d) and not d.collecting:
			d.start_collect(player)
			if not d.collected.is_connected(_on_collected):
				d.collected.connect(_on_collected)
			n += 1
	if n > 0:
		_collected = 0
		_result_text = ""


func _on_collected(_disc: Node) -> void:
	_collected += 1
	_result_text = "collected %d disc%s" % [_collected, "" if _collected == 1 else "s"]


## Turns every disc's beam of light on or off (and future ones too).
## P / panel checkbox. Turning paths off lets every existing path fall and
## poof; turning them on just means the next throws leave paths again.
func set_paths(on: bool) -> void:
	paths_on = on
	if not on:
		paths.clear(true)
	panel.set_paths_shown(on)
	_update_label()


func set_beams(on: bool) -> void:
	beams = on
	for d in discs:
		if is_instance_valid(d):
			d.set_beam(on)
	_update_label()


## Teleports the walker to the last disc. A resting disc: stand beside it,
## facing the same way. A flying disc: your eyes go where it is and you
## inherit its velocity, so you fly on alongside it until you land.
## V: chase the last disc, or come back if already chasing.
func toggle_follow() -> void:
	if follow_cam.active():
		follow_cam.stop()
	elif is_instance_valid(_last):
		follow_cam.follow(_last)


func fetch() -> void:
	if not is_instance_valid(_last):
		return
	var p: Vector3 = _last.global_position
	if not _last.resting:
		var at := p - Vector3(0, 1.6, 0)                     # eyes at the disc
		at.y = maxf(at.y, terrain.height_at(at.x, at.z) + 0.1)
		player.fling(at, _last.linear_velocity)
		return
	var back := Vector3(camera.global_transform.basis.z.x, 0, camera.global_transform.basis.z.z)
	back = back.normalized() if back.length() > 0.01 else Vector3.BACK
	var at := p + back * 1.2
	at.y = maxf(terrain.height_at(at.x, at.z), p.y) + 0.2
	player.respawn(at)


func clear() -> void:
	follow_cam.stop()
	paths.clear()
	for d in discs:
		if is_instance_valid(d):
			d.queue_free()
	discs.clear()
	_last = null
	_result_text = ""
	_collected = 0
	_update_label()


func _process(_delta: float) -> void:
	var rolling := 0
	for d in discs:
		if is_instance_valid(d) and d.collecting:
			rolling += 1
	if rolling > 0:
		_flying_text = "collecting: %d rolling home…%s" % [rolling,
			("  (%d in)" % _collected) if _collected > 0 else ""]
	elif is_instance_valid(_last) and "flying" in _last and _last.flying:
		_flying_text = "disc in flight: %.1f m  ·  %.0f m/s" % [_last.distance(), _last.linear_velocity.length()]
	elif is_instance_valid(_last) and not _last.resting:
		_flying_text = "in flight: %.1f m" % _last.distance()
	else:
		_flying_text = ""
	_update_label()


func _on_rest(disc: Node) -> void:
	if disc != _last or _collected > 0:
		return
	var notes := []
	if disc.bark_hits > 0:
		notes.append("hit bark x%d" % disc.bark_hits)
	if disc.leaf_cells > 0:
		notes.append("through leaves")
	if disc.splashed:
		notes.append("splash!")
	if "model" in disc:
		_result_text = "last disc (%s): carry %.1f m, rest %.1f m, peak %.1f m, %.1f s in the air%s" % [
			disc.model.id, disc.flight_dist, disc.distance(), disc.max_height, disc.flight_time,
			("  ·  " + ", ".join(notes)) if notes.size() > 0 else ""]
		return
	_result_text = "last throw: %.1f m at power %d (peak %.1f m)%s" % [
		disc.distance(), disc.power, disc.max_height,
		("  ·  " + ", ".join(notes)) if notes.size() > 0 else ""]


func _update_label() -> void:
	if label == null:
		return
	if status_label != null:
		status_label.text = "Velocity: %d  (%d m/s)\nBeams: %s\nPaths: %s" % [
			power, int(power * speed_per_level), "on" if beams else "off",
			"on" if paths_on else "off"]
	var lines := ["T throw panel  ·  1-9, 0 block power  ·  click block  ·  V follow cam  ·  P paths on/off  ·  F fetch  ·  C collect  ·  B beams"]
	if follow_cam != null and follow_cam.active():
		lines[0] = "following your disc  ·  V to come back"
	if _flying_text != "":
		lines.append(_flying_text)
	elif _result_text != "":
		lines.append(_result_text)
	label.text = "\n".join(lines)
