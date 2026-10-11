extends Node
## Throwing discs (and orange cubes). Keys (docs/THROW-HUD.md):
##
##   Left click / Enter   throw the disc you've set up (throw_setup.gd: arrows,
##                        Shift+arrows, X, R, H, Tab), where you're looking:
##                        left/right is the direction, up/down the launch angle
##   Right click          throw an orange cube at the same release speed (the
##                        original cannon, kept for fun and physics testing)
##
## Two toggles (warm lamps in the HUD, both start off) decide what happens
## with every throw, discs and cubes alike:
##   V        CHASE VIEW: the camera chases each throw through its flight and
##            ground play, then snaps back to you (you never moved) once it
##            fully stops. Off mid-flight = back to you now.
##   G        GOTO: once each throw fully stops, you're moved to it, standing
##            behind it facing down the fairway. Off mid-flight = no goto.
##            Chase + Goto: watch the flight, then end up there.
## And one quick action:
##   L        LAUNCH: while your last throw is still moving (flying, skipping
##            or rolling), you take on its position and velocity and fly on
##            with it until you land. For that throw only, chase and goto
##            stand down. Does nothing once it has stopped.
##
##   P        PATHS lamp: flight paths + rest beams on/off (starts on). On:
##            every disc throw leaves a path (bright cubes in the air,
##            dimmer for skips and rolls) and resting discs get a beam. Off:
##            paths drift down and go poof, beams go out, new throws leave
##            none.
##   U        hide / show the throw HUD
##   C        collect: every disc rolls home to you, building up speed
##            (ignores chase and goto)
##
## (In code "warp" is the old name for goto.)

const DISC_SCRIPT := preload("res://scripts/disc.gd")
const FLYING_DISC_SCRIPT := preload("res://scripts/flying_disc.gd")
const DiscModel := preload("res://scripts/disc_model.gd")
const ThrowSetup := preload("res://scripts/throw_setup.gd")
const ThrowHud := preload("res://scripts/throw_hud.gd")
const FollowCam := preload("res://scripts/follow_cam.gd")
const Paths := preload("res://scripts/paths.gd")

@export var speed_per_level := 4.0      ## Old block power levels (tests): m/s per level.
@export var max_discs := 12          ## Older discs are cleared away.

var terrain: Node3D
var player: CharacterBody3D
var camera: Camera3D
var label: Label
var hud: CanvasLayer                     ## Where the throw HUD goes.
var setup: Node                          ## The throw you've set up (throw_setup.gd).
var throw_hud: Control                   ## Lower-right instrument block (throw_hud.gd).
var follow_cam: Camera3D
var paths: Node3D
var disc_models: Array = []

var paths_on := true                     ## Paths + rest beams (P).
var view_on := false                     ## VIEW toggle (V).
var warp_on := false                     ## GOTO toggle (G).
var lamps: Control                       ## Warm lamps in the HUD (lamps.gd).
var launch_label: Label                  ## Under the crosshair: "launch 12°".
var warp_label: Label                    ## Top centre: brief notes ("warped 42 m").
var warp_flash: ColorRect                ## Soft white fade when you arrive.
var _warp_target: Node = null            ## Throw we'll warp to when it stops.
var _launched: Node = null               ## Throw you launched with (L): no view/warp.
var warps := 0                           ## Warps so far (tests count them).
var _warp_t := 0.0
var _warp_note := ""                     ## Brief "warp cancelled" etc.
var _warp_note_t := 0.0
var dials: Control                       ## Heading + horizon, in the HUD (dials.gd).
@export var launch_min := -45.0          ## Launch angle limits (deg).
@export var launch_max := 85.0
var discs: Array = []
var assume_captured := false             ## Tests: treat the mouse as captured (headless can't).
var _last: Node = null
var _flying_text := ""
var _result_text := ""
var _collected := 0


func _ready() -> void:
	disc_models = DiscModel.load_all()
	setup = ThrowSetup.new()
	setup.name = "ThrowSetup"
	setup.discs = disc_models
	add_child(setup)
	throw_hud = Control.new()
	throw_hud.set_script(ThrowHud)
	throw_hud.name = "ThrowHud"
	throw_hud.setup = setup
	throw_hud.camera = camera
	if hud != null:
		hud.add_child(throw_hud)
		throw_hud.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		throw_hud.position = Vector2.ZERO
		throw_hud.offset_left = -throw_hud.size.x - 16
		throw_hud.offset_top = -throw_hud.size.y - 16
		throw_hud.offset_right = -16
		throw_hud.offset_bottom = -16
		dials = throw_hud.dials
		lamps = throw_hud.lamps
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
	var captured := assume_captured or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event.is_action_pressed("launch"):
		launch_self()
	elif event.is_action_pressed("warp"):
		set_warp(not warp_on)
	elif event.is_action_pressed("paths"):
		set_paths(not paths_on)
	elif event.is_action_pressed("view"):
		set_view(not view_on)
	elif event.is_action_pressed("hud"):
		set_hud(not hud_shown())
	elif event.is_action_pressed("collect"):
		collect()
	elif event.is_action_pressed("throw_disc") and not event.is_echo():
		throw_disc(setup.params())
	elif event is InputEventMouseButton and event.pressed and captured \
			and event.button_index == MOUSE_BUTTON_LEFT:
		throw_disc(setup.params())
	elif event is InputEventMouseButton and event.pressed and captured \
			and event.button_index == MOUSE_BUTTON_RIGHT:
		throw_cube()
	else:
		return
	get_viewport().set_input_as_handled()


func hud_shown() -> bool:
	return throw_hud != null and throw_hud.visible


## U: hide / show the throw HUD and the key help, top left (the launch
## readout under the crosshair stays).
func set_hud(on: bool) -> void:
	if throw_hud != null:
		throw_hud.visible = on
	if hud != null and hud.has_node("Help"):
		hud.get_node("Help").visible = on


## Fires an orange cube from just in front of the camera at `speed` m/s
## (default: the release speed you've set up for discs).
func throw_cube(speed := -1.0) -> Node:
	if speed < 0.0:
		speed = setup.speed
	var fwd := -camera.global_transform.basis.z
	var origin := camera.global_position + fwd * 0.5
	var disc: RigidBody3D = RigidBody3D.new()
	disc.set_script(DISC_SCRIPT)
	disc.name = "Disc"
	disc.terrain = terrain
	disc.power = int(round(speed / speed_per_level))
	disc.beam_on = paths_on
	get_parent().add_child(disc)
	disc.add_collision_exception_with(player)   # don't bonk yourself
	var vel := fwd * speed + player.velocity
	var spin := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 8.0
	disc.launch(origin, vel, spin)
	_track(disc)
	return disc


## Old block-power API (tests): level 1..10 at speed_per_level m/s each.
func throw(level: int) -> Node:
	return throw_cube(level * speed_per_level)


## Launch angle (deg) for a throw right now: where you're looking, up or down.
func launch_angle() -> float:
	var look := -camera.global_transform.basis.z
	var view := rad_to_deg(asin(clampf(look.y, -1.0, 1.0)))
	return clampf(view, launch_min, launch_max)


## Throws a real flying disc. p: {disc, speed, nose, roll, spin, hand?}.
## Direction is where you're looking (left/right AND up/down); p.pitch, if
## given, overrides the angle (tests use it).
func throw_disc(p: Dictionary) -> Node:
	var look := -camera.global_transform.basis.z
	var fwd := Vector3(look.x, 0, look.z)
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var hand: float = p.get("hand", 1.0)
	var pitch: float = p.pitch if p.has("pitch") else launch_angle()
	var ls := DiscModel.launch_state(fwd, p.speed, pitch, p.nose, p.roll, hand)
	# Release about shoulder height, a little ahead of you.
	var origin := player.global_position + Vector3(0, 1.3, 0) + fwd * 0.6
	var disc: RigidBody3D = RigidBody3D.new()
	disc.set_script(FLYING_DISC_SCRIPT)
	disc.name = "FlyingDisc"
	disc.terrain = terrain
	disc.model = p.disc
	disc.color = paths.next_color()      # disc, beam and path share a colour
	disc.beam_on = paths_on
	get_parent().add_child(disc)
	disc.add_collision_exception_with(player)
	disc.launch_disc(origin, ls[0] + Vector3(player.velocity.x, 0, player.velocity.z), ls[1], p.spin, hand)
	if paths_on:
		paths.track(disc, disc.color)
	_track(disc)
	return disc


## Bookkeeping shared by blocks and discs: this is now the last throw, and
## the VIEW / WARP toggles pick it up (only the latest throw counts).
func _track(disc: Node) -> void:
	disc.came_to_rest.connect(_on_rest)
	disc.tree_exited.connect(func() -> void: discs.erase(disc))
	discs.append(disc)
	_last = disc
	_launched = null
	_collected = 0
	while discs.size() > max_discs:
		var old: Node = discs.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	_result_text = ""
	_warp_target = disc if warp_on else null
	if view_on:
		follow_cam.follow(disc)
	elif follow_cam.active():
		follow_cam.stop()               # was still watching an older throw


## Sends every disc rolling home to the player. Ignores VIEW and WARP: the
## camera stays with you and nobody warps anywhere.
func collect() -> void:
	follow_cam.stop()
	_warp_target = null
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


## P: flight paths and rest beams together. Off: every
## existing path falls and poofs and the beams go out. On: beams come back
## on resting discs and the next throws leave paths again.
func set_paths(on: bool) -> void:
	paths_on = on
	if not on:
		paths.clear(true)
	for d in discs:
		if is_instance_valid(d):
			d.set_beam(on)
	_update_lamps()
	_update_label()


## True while the last throw is still going (flying, skipping, rolling).
func _moving(d: Node) -> bool:
	return is_instance_valid(d) and not d.resting and not d.collecting


## V: VIEW toggle. On mid-flight picks up the throw already in the air
## (unless you launched with it); off mid-flight snaps back to you now.
func set_view(on: bool) -> void:
	view_on = on
	if on:
		if _moving(_last) and _last != _launched:
			follow_cam.follow(_last)
	else:
		follow_cam.stop()
	_update_lamps()
	_update_label()


## G: GOTO toggle. On mid-flight applies to the throw already in the air
## (unless you launched with it); off mid-flight cancels that warp.
func set_warp(on: bool) -> void:
	warp_on = on
	if on:
		if _moving(_last) and _last != _launched:
			_warp_target = _last
			_warp_t = 0.0
	else:
		_warp_target = null
	_update_lamps()


## L: launch yourself with your last throw, while it's still moving (in the
## air, skipping or rolling). Your eyes go where it is and you take on its
## exact velocity, flying on with it until you land. For that throw only,
## VIEW lets go of the camera and WARP stands down. Does nothing once the
## throw has stopped.
func launch_self() -> bool:
	if not _moving(_last):
		return false
	var at: Vector3 = _last.global_position - Vector3(0, 1.6, 0)    # eyes at the disc
	at.y = maxf(at.y, terrain.height_at(at.x, at.z) + 0.1)
	player.fling(at, _last.linear_velocity)
	_launched = _last
	if follow_cam.active():
		follow_cam.stop()
	_warp_target = null
	return true


func warp_pending() -> bool:
	return _warp_target != null


## Stand just behind the disc, facing the way it was thrown (ready for the
## next shot). A disc floating in a lake puts you on the nearest shore.
func _do_warp() -> void:
	var d = _warp_target
	_warp_target = null
	if not is_instance_valid(d):
		return
	var p: Vector3 = d.global_position
	var dir := Vector3(p.x - d.start.x, 0, p.z - d.start.z)
	dir = dir.normalized() if dir.length() > 0.5 else _flat_forward()
	var at := p - dir * 1.2
	if terrain.lake_edge_distance(at.x, at.z) < 1.0:
		# Walk back toward the throw until we're on dry land.
		for i in 200:
			at -= dir * 0.5
			if terrain.lake_edge_distance(at.x, at.z) >= 1.0:
				break
	at.y = terrain.height_at(at.x, at.z) + 0.2
	if not d.splashed:
		at.y = maxf(at.y, p.y - 0.5)
	player.respawn(at)
	player.rotation.y = atan2(-dir.x, -dir.z)
	warps += 1
	if warp_flash != null:
		warp_flash.color.a = 0.55
	_note("goto %.0f m" % Vector2(at.x - d.start.x, at.z - d.start.z).length(), 1.2)


func _flat_forward() -> Vector3:
	var f := -camera.global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.01 else Vector3.FORWARD


func _note(text: String, secs := 1.5) -> void:
	_warp_note = text
	_warp_note_t = secs


func _update_warp(delta: float) -> void:
	if _warp_target != null:
		if not is_instance_valid(_warp_target) or _warp_target.collecting:
			_warp_target = null
			_note("goto cancelled (disc gone)")
		elif _warp_target.resting:
			_do_warp()
		else:
			_warp_t += delta
	if warp_flash != null and warp_flash.color.a > 0.0:
		warp_flash.color.a = maxf(warp_flash.color.a - delta * 1.6, 0.0)
	if lamps != null:
		lamps.pulse_warp = _warp_target != null     # GOTO lamp breathes while armed
	if warp_label == null:
		return
	if _warp_note_t > 0.0:
		_warp_note_t -= delta
		warp_label.text = _warp_note
		warp_label.modulate.a = clampf(_warp_note_t / 0.5, 0.0, 0.9)
		warp_label.visible = true
	else:
		warp_label.visible = false


func clear() -> void:
	_warp_target = null
	follow_cam.stop()
	paths.clear()
	for d in discs:
		if is_instance_valid(d):
			d.queue_free()
	discs.clear()
	_last = null
	_launched = null
	_result_text = ""
	_collected = 0
	_update_label()


func _update_lamps() -> void:
	if lamps != null:
		lamps.set_lamps(view_on, warp_on, paths_on)


func _process(_delta: float) -> void:
	_update_warp(_delta)
	var following: bool = follow_cam != null and follow_cam.active()
	if launch_label != null:
		launch_label.visible = not following
		launch_label.text = "launch %+d°" % int(round(launch_angle()))
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
	_result_text = "last cube: %.1f m (peak %.1f m)%s" % [
		disc.distance(), disc.max_height,
		("  ·  " + ", ".join(notes)) if notes.size() > 0 else ""]


func _update_label() -> void:
	if label == null:
		return
	var lines := []
	if follow_cam != null and follow_cam.active():
		lines.append("watching your throw  ·  L launch with it  ·  V chase off")
	if _flying_text != "":
		lines.append(_flying_text)
	elif _result_text != "":
		lines.append(_result_text)
	label.text = "\n".join(lines)
