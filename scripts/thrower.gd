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
##   G        GOTO: once each throw fully stops, you're walked over to it
##            (a brisk jog, round lakes), ending up just behind it facing
##            down the fairway. Any move or throw key skips the walk and puts
##            you there. Off mid-flight = no goto; off mid-walk = you stop
##            where you are. Chase + Goto: watch the flight, then go there.
##            (`-- --goto=warp`: put there at once, the old way.)
## And one quick action:
##   L        LAUNCH: while your last throw is still moving (flying, skipping
##            or rolling), you take on its position and velocity and fly on
##            with it until you land. For that throw only, chase and goto
##            stand down. Does nothing once it has stopped.
##
##   O        SHOT CIRCLE lamp (starts off; on in Course Play): once you're at
##            your lie (where the throw stopped), you can't walk more than
##            1 m from it (a faint ring on the ground shows it). Off: free
##            to roam. On again: back round the same lie. A throw with goto
##            off lets go of it.
##   P        PATHS lamp: flight paths + rest beams on/off (starts on). On:
##            every disc throw leaves a path (bright cubes in the air,
##            dimmer for skips and rolls) and resting discs get a beam. Off:
##            paths drift down and go poof, beams go out, new throws leave
##            none.
##   U        hide / show the throw HUD
##   C        collect: every disc rolls home to you, building up speed,
##            and basket confetti flies in (ignores chase and goto)
##
## Controller (docs/CONTROLS.md): B throws the disc, RB + B a cube; Y is L,
## LB + Y the shot circle; LB + X is collect (X alone crouches, player.gd).
##
## Course Play (course_round.gd) hooks in through `course_round`: it decides where
## a goto puts you (facing the basket) and hears about throws, gotos and
## basket hits through the signals below. In Course Play your lie is kept
## with goto off too: the disc stops, a ring marks where it lies, and you
## walk there yourself. Stepping into the ring is arriving (the disc is
## picked up, the circle holds you). With the circle on you can't throw a
## disc until you've got there; G on meanwhile walks you there.
##
## (In code "warp" is the old name for goto.)

const DISC_SCRIPT := preload("res://scripts/disc.gd")
const FLYING_DISC_SCRIPT := preload("res://scripts/flying_disc.gd")
const DiscModel := preload("res://scripts/disc_model.gd")
const ThrowSetup := preload("res://scripts/throw_setup.gd")
const FlightSim := preload("res://scripts/flight_sim.gd")
const ThrowHud := preload("res://scripts/throw_hud.gd")
const FollowCam := preload("res://scripts/follow_cam.gd")
const Paths := preload("res://scripts/paths.gd")
const ShotCircle := preload("res://scripts/shot_circle.gd")
const Course := preload("res://scripts/course.gd")

signal thrown(disc)                      ## A real disc left your hand (not a cube).
signal warped(disc, lie)                 ## Goto got you to a throw; lie = where it lies (m).
signal reached(disc, lie)                ## You're at your lie (by goto, or walking in yourself).
signal basket_scored(disc, basket)       ## A throw counted in a basket.

const CIRCLE_RADIUS := 1.0               ## Shot-circle (m).
const GOTO_SPEED := 7.0                  ## Goto's walk to your disc (m/s).

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
var circle_on := false                   ## SHOT CIRCLE toggle (O).
var circle: MultiMeshInstance3D          ## The ring on the ground (shot_circle.gd).
var course_round: Node = null            ## course_round.gd, when Course Play is on.
var locked := false                      ## No throwing (walking to the next tee, overview).
var goto_walk := true                    ## Goto walks you there (false: put there at once).
var _lie := Vector3.ZERO                 ## Where your last throw lies: the shot-circle's centre.
var _has_lie := false
var _lie_reached := true                 ## You've got to it (the circle only holds you then).
var _lie_disc = null                     ## The disc lying there (untyped: may be freed).
var _goto := {}                          ## Where to stand for it: _goto_spot().
var _going := false                      ## Goto is walking you there now.
var marker: MultiMeshInstance3D          ## Course Play: ring on a lie you haven't reached yet.
var lamps: Control                       ## Warm lamps in the HUD (lamps.gd).
var aim_arc: Node3D                      ## Aim arc preview (T, aim_arc.gd).
var basket_finder: Node3D                ## Beam + arrow to the basket (basket_finder.gd).
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
## How far down your line of sight to look for what you are aiming AT.
@export var aim_reach := 300.0
## Closer than this and we do not aim at the target: at arm's length the
## direction to it swings wildly with small head movements.
@export var aim_min := 2.0
## PUTT ASSIST. Inside this range, the launch angle is solved so the disc
## ARRIVES at what the crosshair is on, instead of merely setting off at it.
##
## A thrown disc is a projectile, so it always falls below the line you
## sighted down, and at putting speed it falls a long way: lift goes as speed
## squared, so a 9 m/s putter makes about a seventh of a 24 m/s drive's and is
## closer to free fall. A real player answers that with a nose-up release they
## have built by feel over thousands of putts. With a mouse there is no such
## feel, so putting at a basket you are pointing straight at missed low every
## time, which reads as the game being broken rather than as a skill.
##
## Deliberately limited to putting range. Solving the angle at any distance
## would land every drive on the pin and delete distance control, which is
## most of the game. Set the range to 0 to turn the assist off entirely.
@export var putt_assist_range := 12.0
## ... and it eases off to nothing by this far out, so there is no cliff
## between an assisted putt and an unassisted approach.
@export var putt_assist_fade := 20.0
## How much wider than the basket's own mouth the crosshair may pass and still
## count as aiming at it. The test is against the CATCH VOLUME -- the cylinder
## the chains hang in -- rather than a sphere round a point, because that is
## the shape that actually takes a disc. A point plus a radius was far too
## fussy: aiming at the top band already reads as a quarter of a metre "off"
## the chain centre before you have moved at all.
@export var aim_basket_margin := 0.12
var discs: Array = []
var assume_captured := false             ## Tests: treat the mouse as captured (headless can't).
var _last: Node = null
var _flying_text := ""
var _result_text := ""
var _collected := 0
var basket_hits := 0                 ## Baskets hit this session (just for fun).


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
	circle = ShotCircle.new()
	circle.name = "ShotCircle"
	circle.terrain = terrain
	circle.radius = CIRCLE_RADIUS
	add_child(circle)
	marker = ShotCircle.new()
	marker.name = "LieMarker"
	marker.terrain = terrain
	marker.radius = CIRCLE_RADIUS
	marker.square = 0.18
	marker.gap = 1.6
	marker.color = Color(1.0, 1.0, 1.0, 0.5)
	add_child(marker)
	if player != null:
		player.walk_done.connect(_on_walk_end.bind(false))
		player.walk_stuck.connect(_on_walk_end.bind(true))
	_update_label()


func _unhandled_input(event: InputEvent) -> void:
	var captured := assume_captured or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event.is_action_pressed("launch") and not _pad_shoulder(event, "setup_disc"):
		launch_self()
	elif event.is_action_pressed("circle") and _pad_page(event, "setup_disc"):
		set_circle(not circle_on)
	elif event.is_action_pressed("warp"):
		set_warp(not warp_on)
	elif event.is_action_pressed("paths"):
		set_paths(not paths_on)
	elif event.is_action_pressed("aim_arc"):
		set_aim_arc(not aim_arc_on())
	elif event.is_action_pressed("next_basket"):
		cycle_basket(-1 if Input.is_key_pressed(KEY_SHIFT) else 1)
	elif event.is_action_pressed("view"):
		set_view(not view_on)
	elif event.is_action_pressed("hud"):
		set_hud(not hud_shown())
	elif event.is_action_pressed("collect") and _pad_page(event, "setup_disc"):
		collect()
	elif _going and _skips_walk(event, captured):
		_finish_goto(true)              # there now (no throw this press)
	elif locked:
		return                          # no throws now (course_round.gd may skip the walk)
	elif event.is_action_pressed("throw_cube") and _pad_page(event, "setup_alt"):
		throw_cube()
	elif event.is_action_pressed("throw_disc") and not event.is_echo() \
			and not _pad_shoulder(event, "setup_alt") and not _pad_shoulder(event, "setup_disc"):
		_throw_from_input()
	elif event is InputEventMouseButton and event.pressed and captured \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_throw_from_input()
	elif event is InputEventMouseButton and event.pressed and captured \
			and event.button_index == MOUSE_BUTTON_RIGHT:
		throw_cube()
	else:
		return
	get_viewport().set_input_as_handled()


## Any move, hop or throw ends goto's walk (you're put there).
func _skips_walk(event: InputEvent, captured: bool) -> bool:
	for a in ["move_forward", "move_back", "move_left", "move_right", "jump", "throw_disc"]:
		if event.is_action_pressed(a):
			return true
	return event is InputEventMouseButton and event.pressed and captured


## A disc throw from the keys / mouse / pad: in Course Play with the circle
## on, only once you've got to your lie.
func _throw_from_input() -> void:
	if must_walk():
		_note("walk to your disc first (the ring)", 1.5)
		return
	throw_disc(setup.params())


## True while Course Play holds your next disc throw until you reach your lie.
func must_walk() -> bool:
	return circle_on and _has_lie and not _lie_reached and _in_hole()


func _in_hole() -> bool:
	return course_round != null and course_round.in_hole()


func hud_shown() -> bool:
	return throw_hud != null and throw_hud.visible


## U: hide / show the throw HUD and the "? for controls" hint, top left (the launch
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


## What you are looking at: the first thing your line of sight hits, within
## aim_reach. {hit: bool, at: Vector3, dist: float}.
##
## The crosshair is a ray from your EYE, but the disc leaves from `release()`,
## 0.3 m lower and 0.6 m further forward. Copying only the camera's pitch to
## the throw sends the disc along a line PARALLEL to the one you sighted
## down, so it flew that 0.3 m low forever and never converged -- which is
## why a drive looked low off the tee even before gravity did anything.
## Aiming from the release point AT this target removes that offset at every
## distance. What is left is the ballistic arc, which is real disc golf.
func aim_target() -> Dictionary:
	var out := {"hit": false, "at": Vector3.ZERO, "dist": 0.0}
	if camera == null:
		return out
	var from := camera.global_position
	var look := -camera.global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + look * aim_reach)
	# Not ourselves (the ray starts inside our own capsule), and not the discs
	# already lying about -- snapping the aim onto a disc at your feet would
	# be worse than not aiming at all.
	var skip: Array = [player.get_rid()]
	for d in discs:
		if is_instance_valid(d):
			skip.append(d.get_rid())
	q.exclude = skip
	q.collide_with_areas = false
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		out.hit = true
		out.at = hit.position
		out.dist = from.distance_to(hit.position)
		# The pole and the tray ARE solid, and basket.gd marks them, so a ray
		# that stops on one is still a ray aimed at that basket -- aim at its
		# chains, not at the bit of metal we happened to touch. Without this
		# the basket blocks itself: the pole is the nearest solid thing, so
		# the "something in front wins" rule below threw the basket away.
		var col = hit.get("collider")
		if col != null and col.has_meta("basket"):
			var b = col.get_meta("basket")
			if is_instance_valid(b):
				out.at = Vector3(b.global_position.x,
					b.global_position.y + (b.CHAIN_BOTTOM + b.BAND_Y) * 0.5,
					b.global_position.z)
				return out
	return _aim_at_basket(out, from, look)


## Let the crosshair land on a basket.
##
## A basket catches with its chains and its cage, and NEITHER is a collision
## body -- they are too thin, so disc.gd sweeps them instead (basket.gd).
## That means a ray aimed dead at the chains goes straight through and hits
## the hill behind, and "aim at the basket" silently became "aim at whatever
## is behind the basket". So the baskets are checked by hand here, and the
## target is the middle of the chain window: the centre of the volume that
## can actually catch a disc.
func _aim_at_basket(best: Dictionary, from: Vector3, look: Vector3) -> Dictionary:
	if terrain == null or not ("baskets" in terrain):
		return best
	for b: Node3D in terrain.baskets:
		if not is_instance_valid(b):
			continue
		# The catch volume: the cylinder the chains hang in, from the bottom
		# of the chains up to the band.
		var axis: Vector3 = b.global_position
		var lo: float = axis.y + b.CHAIN_BOTTOM
		var hi: float = axis.y + b.BAND_Y
		var r: float = b.TARGET_RADIUS + aim_basket_margin
		# Closest approach to the basket's axis, in plan view.
		var d2 := Vector2(look.x, look.z)
		if d2.length() < 1e-4:
			continue                    # looking straight up or down
		var dir2 := d2.normalized()
		var to2 := Vector2(axis.x - from.x, axis.z - from.z)
		var along2 := to2.dot(dir2)
		if along2 <= 0.0:
			continue                    # behind us
		if (dir2 * along2 - to2).length() > r:
			continue                    # the sight line passes outside it
		# How far along the 3D ray that is, and how high the ray is there:
		# it has to be between the chains and the band to count.
		var along: float = along2 / d2.length()
		if along <= aim_min or along > aim_reach:
			continue
		var y: float = from.y + look.y * along
		if y < lo or y > hi:
			continue                    # over the top, or below the tray
		# Something solid in front of the basket wins: you cannot putt
		# through a tree just because the basket lines up behind it.
		if best.hit and best.dist <= along:
			continue
		# Aim at the middle of the window: the most room on every side for
		# the disc to actually be caught.
		best = {"hit": true, "dist": along,
			"at": Vector3(axis.x, (lo + hi) * 0.5, axis.z)}
	return best


## Where the disc leaves your hand: about shoulder height, a little ahead.
func release(fwd: Vector3) -> Vector3:
	return player.global_position + Vector3(0, 1.3, 0) + fwd * 0.6


## The throw direction: horizontal heading and launch pitch (deg), aimed from
## the release point at whatever you are looking at. Falls back to the view
## pitch when you are aiming at open sky, or at something almost touching you.
##
## Inside putt_assist_range the pitch is SOLVED so the disc arrives at the
## target rather than setting off towards it (see putt_assist_range above),
## blending back to the straight line by putt_assist_fade.
func aim_from(origin: Vector3, view_fwd: Vector3) -> Array:
	var t := aim_target()
	if not t.hit or t.dist < aim_min:
		return [view_fwd, launch_angle()]
	var to: Vector3 = t.at - origin
	var flat := Vector3(to.x, 0.0, to.z)
	if flat.length() < 0.01:
		return [view_fwd, launch_angle()]
	var straight := clampf(rad_to_deg(atan2(to.y, flat.length())), launch_min, launch_max)
	var fwd := flat.normalized()
	var k := _assist_blend(flat.length())
	if k <= 0.0 or setup == null or setup.disc() == null:
		return [fwd, straight]
	var solved: float = FlightSim.solve_pitch(setup.params(), origin, fwd, t.at,
		terrain, straight)
	return [fwd, clampf(lerpf(straight, solved, k), launch_min, launch_max)]


## How much of the putt assist applies at this range: all of it inside
## putt_assist_range, none beyond putt_assist_fade, eased across the gap.
func _assist_blend(dist: float) -> float:
	if putt_assist_range <= 0.0:
		return 0.0
	if dist <= putt_assist_range:
		return 1.0
	if dist >= putt_assist_fade or putt_assist_fade <= putt_assist_range:
		return 0.0
	var f := (dist - putt_assist_range) / (putt_assist_fade - putt_assist_range)
	return 1.0 - smoothstep(0.0, 1.0, f)


## Throws a real flying disc. p: {disc, speed, nose, roll, spin, hand?}.
## Direction is where you're looking (left/right AND up/down); p.pitch, if
## given, overrides the angle (tests use it).
func throw_disc(p: Dictionary) -> Node:
	var look := -camera.global_transform.basis.z
	var view_fwd := Vector3(look.x, 0, look.z)
	view_fwd = view_fwd.normalized() if view_fwd.length() > 0.01 else Vector3.FORWARD
	var hand: float = p.get("hand", 1.0)
	# The release point uses the view heading, then the aim is worked out from
	# there: the 0.6 m step forward barely turns it, and this keeps it simple.
	var origin := release(view_fwd)
	var fwd := view_fwd
	var pitch: float = 0.0
	if p.has("pitch"):
		pitch = p.pitch                 # tests and probes set the angle outright
	else:
		var aim: Array = aim_from(origin, view_fwd)
		fwd = aim[0]
		pitch = aim[1]
		origin = release(fwd)
	var ls := DiscModel.launch_state(fwd, p.speed, pitch, p.nose, p.roll, hand)
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
	thrown.emit(disc)
	return disc


## Bookkeeping shared by blocks and discs: this is now the last throw, and
## the VIEW / WARP toggles pick it up (only the latest throw counts).
func _track(disc: Node) -> void:
	disc.came_to_rest.connect(_on_rest)
	disc.hit_basket.connect(_on_basket_hit)
	disc.tree_exited.connect(_on_gone.bind(disc))
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
	if not warp_on:
		release_lie()                   # no goto to move the circle on: let go
	if view_on:
		follow_cam.follow(disc)
	elif follow_cam.active():
		follow_cam.stop()               # was still watching an older throw


## Just the discs roll home (the confetti stays where it fell). Course Play
## does this when you hole out.
func collect_discs() -> void:
	for d in discs:
		if is_instance_valid(d) and not d.collecting:
			_send_home(d)


## Sends every disc rolling home to the player, and calls in all the basket
## confetti too (it flies straight at you). Ignores VIEW and WARP: the
## camera stays with you and nobody warps anywhere.
func collect() -> void:
	follow_cam.stop()
	for c in get_tree().get_nodes_in_group("confetti"):
		c.collect(player)
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


## A disc hit a basket: confetti and glow are the basket's job; ours is to
## hold the disc in the chains for a beat (so it reads as in, not bounced
## out), then send it rolling home, exactly like C does for all of them.
func _on_basket_hit(disc: Node, basket: Node, part: String) -> void:
	if not is_instance_valid(disc) or disc.collecting:
		return
	disc.hold()
	get_tree().create_timer(basket.HOLD_TIME).timeout.connect(_send_home.bind(disc))
	basket_hits += 1
	if _warp_target == disc:
		_warp_target = null             # it's in: no goto to it
	_note("BASKET!  (%s)" % part, 2.0)
	basket_scored.emit(disc, basket)


## Untyped: the disc may have been freed (or collected by C) meanwhile.
func _send_home(disc) -> void:
	if not is_instance_valid(disc) or disc.collecting:
		return
	disc.start_collect(player)
	if not disc.collected.is_connected(_on_collected):
		disc.collected.connect(_on_collected)


## A throw left the tree (collected home, fell off the world, cleared
## away): forget it, so nothing holds on to a freed disc.
func _on_gone(disc: Node) -> void:
	discs.erase(disc)
	if _last == disc:
		_last = null
	if _launched == disc:
		_launched = null
	if _warp_target == disc:
		_warp_target = null


func _on_collected(_disc: Node) -> void:
	_collected += 1
	_result_text = "collected %d disc%s" % [_collected, "" if _collected == 1 else "s"]


## Controller buttons that share two actions pick by shoulder: true unless
## this is a pad button pressed without `shoulder` held (keys always pass).
func _pad_page(event: InputEvent, shoulder: String) -> bool:
	return not (event is InputEventJoypadButton) or Input.is_action_pressed(shoulder)


## True for a pad button pressed while `shoulder` is held.
func _pad_shoulder(event: InputEvent, shoulder: String) -> bool:
	return event is InputEventJoypadButton and Input.is_action_pressed(shoulder)


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
	# The basket beam is a beam, and P already means "paths + beams", so it
	# goes with them. Say the word if you would rather find the basket with
	# the paths turned off.
	if basket_finder != null:
		basket_finder.set_enabled(on)
	_update_lamps()
	_update_label()


## True while the last throw is still going (flying, skipping, rolling).
## Untyped: a freed disc can't be passed into a typed Node parameter.
func _moving(d) -> bool:
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
		elif _has_lie and not _lie_reached and not _going and not _goto.is_empty():
			_start_goto_walk()          # your disc is out there: take you to it
	else:
		_warp_target = null
		if _going:
			_going = false
			player.stop_walk()          # stop where you are
			if not _in_hole():
				release_lie()           # (Course Play: the ring stays, walk on yourself)
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
	release_lie()
	return true


## O: SHOT CIRCLE toggle. On: once you're at your lie, you're held within
## CIRCLE_RADIUS of it (not of where you stand now). Off: free.
func set_circle(on: bool) -> void:
	circle_on = on
	_apply_circle()
	_update_lamps()


## You're at a lie at `at`: the shot-circle goes round it from now on (if
## it's on).
func set_lie(at: Vector3) -> void:
	_lie = at
	_has_lie = true
	_lie_reached = true
	_lie_disc = null
	_apply_circle()


## Your throw stopped here (g: _goto_spot()), but you're not there yet.
func _mark_lie(g: Dictionary) -> void:
	_goto = g
	_lie = g.lie
	_has_lie = true
	_lie_reached = false
	_lie_disc = g.disc
	_apply_circle()


## You've got to your lie (goto, or walking into the ring yourself).
func _reach_lie() -> void:
	if not _has_lie or _lie_reached:
		return
	_lie_reached = true
	_apply_circle()
	reached.emit(_lie_disc, _lie)


## No lie any more (a new tee, a launch, a throw without goto): no circle,
## and no walk to it.
func release_lie() -> void:
	_has_lie = false
	_lie_reached = true
	_lie_disc = null
	_goto = {}
	if _going:
		_going = false
		player.stop_walk()
	_apply_circle()


func has_lie() -> bool:
	return _has_lie


## True once you've got to your lie (also when there's none).
func lie_reached() -> bool:
	return _lie_reached


## True while goto is walking you to your disc.
func going() -> bool:
	return _going


func lie() -> Vector3:
	return _lie


func _apply_circle() -> void:
	if circle_on and _has_lie and _lie_reached:
		player.set_tether(_lie, CIRCLE_RADIUS)
		if circle != null:
			circle.show_at(_lie)
	else:
		player.clear_tether()
		if circle != null:
			circle.visible = false
	if marker != null:
		if _has_lie and not _lie_reached and _in_hole():
			marker.show_at(_lie)
		else:
			marker.visible = false


func warp_pending() -> bool:
	return _warp_target != null


## Goto: your throw has stopped. Mark its lie and walk you over (or put
## you there at once: goto_walk off, or it's right here).
func _do_warp() -> void:
	var d = _warp_target
	_warp_target = null
	if not is_instance_valid(d):
		return
	_mark_lie(_goto_spot(d))
	if goto_walk and _flat_dist(player.global_position, _goto.at) > 0.5:
		_start_goto_walk()
	else:
		_finish_goto(true)


func _start_goto_walk() -> void:
	_going = true
	var to: Vector3 = _goto.at
	player.walk(to, Course.route(terrain, player.global_position, to), GOTO_SPEED)


## Arrived (walked all the way), or skipped / stuck (then put there).
func _on_walk_end(stuck: bool) -> void:
	if _going:
		_finish_goto(stuck)


## You're at the spot: face down the fairway (or the basket), and you're at
## your lie. `put`: jump you there (with a soft flash) and turn at once.
func _finish_goto(put: bool) -> void:
	_going = false
	var g := _goto
	if g.is_empty():
		return
	var at: Vector3 = g.at
	var dir: Vector3 = g.dir
	if put:
		player.respawn(at)
		player.rotation.y = atan2(-dir.x, -dir.z)
		if warp_flash != null:
			warp_flash.color.a = 0.55
	else:
		player.stop_walk()
	var look: Vector3 = player.head.global_position + dir * 10.0
	if g.aim != null:
		look = g.aim
	if put:
		if g.aim != null:
			player.face(look)
	else:
		player.face(look, 0.45)
	warps += 1
	_note("goto %.0f m" % g.dist, 1.2)
	_reach_lie()
	warped.emit(g.disc, g.lie)


## Where to stand for a throw that's stopped: just behind it, facing the way
## it was thrown (Course Play: facing the basket, course_round.goto_aim()).
## A disc floating in a lake puts you on the nearest shore.
## {disc, at: where you stand, dir: flat facing, aim: Vector3 or null,
##  lie: the shot-circle's centre, dist: how far the throw went (m)}.
func _goto_spot(d) -> Dictionary:
	var p: Vector3 = d.global_position
	var dir := Vector3(p.x - d.start.x, 0, p.z - d.start.z)
	dir = dir.normalized() if dir.length() > 0.5 else _flat_forward()
	var aim = null                      # Vector3 to look at, or null
	if course_round != null:
		aim = course_round.goto_aim()
	if aim != null:
		var to_aim := Vector3(aim.x - p.x, 0, aim.z - p.z)
		if to_aim.length() > 0.5:
			dir = to_aim.normalized()
	# Inside the shot-circle if it's on (or will be): just a step back.
	var back := 0.5 if circle_on or aim != null else 1.2
	var at := p - dir * back
	if d.splashed:
		# In the water: walk back toward the throw until we're on dry land.
		for i in 200:
			if terrain.lake_edge_distance(at.x, at.z) >= 1.0:
				break
			at -= dir * 0.5
	elif terrain.lake_edge_distance(at.x, at.z) < 1.0:
		# On the shore: step out from the water instead (walking back could
		# cross the lake to the far side).
		at = _off_shore(at)
	at.y = terrain.height_at(at.x, at.z) + 0.2
	if not d.splashed:
		at.y = maxf(at.y, p.y - 0.5)
	# The lie: where the disc stopped. In or by a lake, where you stand
	# ashore instead (so the circle doesn't hold you in the water).
	var ashore: bool = d.splashed or Vector2(at.x - p.x, at.z - p.z).length() > CIRCLE_RADIUS
	var lie_at := at if ashore else Vector3(p.x, terrain.height_at(p.x, p.z), p.z)
	return {"disc": d, "at": at, "dir": dir, "aim": aim, "lie": lie_at,
		"dist": Vector2(at.x - d.start.x, at.z - d.start.z).length()}


## `at` pushed straight out of the nearest lake to 1 m past its edge.
func _off_shore(at: Vector3) -> Vector3:
	var best := 1e9
	var out := at
	for lake in terrain.lakes:
		var c: Vector2 = lake.center
		var off := Vector2(at.x, at.z) - c
		var edge: float = off.length() - lake.radius
		if edge < best:
			best = edge
			var n := off.normalized() if off.length() > 0.01 else Vector2(1, 0)
			var q: Vector2 = c + n * (lake.radius + 1.0)
			out = Vector3(q.x, at.y, q.y)
	return out


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _flat_forward() -> Vector3:
	var f := -camera.global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.01 else Vector3.FORWARD


func _note(text: String, secs := 1.5) -> void:
	_warp_note = text
	_warp_note_t = secs


func _update_warp(delta: float) -> void:
	if _going and not player.walking:
		_going = false                  # put somewhere else meanwhile (a new tee, N)
	if _going:
		_warp_note = "walking to your disc  ·  %.0f m  ·  move to skip" % _flat_dist(player.global_position, _goto.at)
		_warp_note_t = maxf(_warp_note_t, 0.6)
	elif _has_lie and not _lie_reached and _flat_dist(player.global_position, _lie) <= CIRCLE_RADIUS:
		_reach_lie()                    # walked into the ring yourself
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
		lamps.pulse_warp = _warp_target != null or _going     # GOTO lamp breathes while armed / walking
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
	release_lie()
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


## B: in Free Play, move the beam and the arrow to another basket. In Course
## Play the hole decides, so this says so rather than doing nothing silently.
func cycle_basket(step: int) -> void:
	if basket_finder == null:
		return
	if course_round != null and course_round.active:
		_note("the beam follows the hole you are playing", 1.2)
		return
	basket_finder.cycle(step)
	var n: int = basket_finder.number()
	if n > 0:
		_note("basket %d of %d" % [n, basket_finder.count()], 1.2)


## The aim arc (T): is the preview showing?
func aim_arc_on() -> bool:
	return aim_arc != null and aim_arc.showing()


func set_aim_arc(on: bool) -> void:
	if aim_arc == null:
		return
	aim_arc.set_shown(on)
	_update_lamps()
	_note("aim arc %s" % ("on" if on else "off"), 1.0)


func _update_lamps() -> void:
	if lamps != null:
		lamps.set_lamps(view_on, warp_on, paths_on, circle_on,
			aim_arc != null and aim_arc.showing())


func _process(_delta: float) -> void:
	_update_warp(_delta)
	var following: bool = follow_cam != null and follow_cam.active()
	var rolling := 0
	for d in discs:
		if is_instance_valid(d) and d.collecting:
			rolling += 1
	if rolling > 0:
		_flying_text = "collecting: %d rolling home…%s" % [rolling,
			("  (%d in)" % _collected) if _collected > 0 else ""]
	elif is_instance_valid(_last) and "flying" in _last and _last.flying:
		# Whatever unit the HUD is set to (I toggles), so the two agree.
		_flying_text = "disc in flight: %.1f m  ·  %s %s" % [
			_last.distance(), setup.speed_str(_last.linear_velocity.length()),
			setup.unit_name()]
	elif is_instance_valid(_last) and not _last.resting:
		_flying_text = "in flight: %.1f m" % _last.distance()
	else:
		_flying_text = ""
	_update_label()


func _on_rest(disc: Node) -> void:
	if disc != _last or _collected > 0:
		return
	# Course Play, goto off: your disc lies there, go and get it.
	if not warp_on and _warp_target == null and disc != _launched and "model" in disc \
			and not disc.collecting and _in_hole():
		_mark_lie(_goto_spot(disc))
	var notes := []
	if disc.bark_hits > 0:
		notes.append("hit bark x%d" % disc.bark_hits)
	if disc.leaf_cells > 0:
		notes.append("through leaves")
	if disc.splashed:
		notes.append("splash!")
	if "model" in disc:
		_result_text = "last disc (%s): carry %.1f m, rest %.1f m, peak %.1f m, %.1f s in the air%s" % [
			disc.model.label, disc.flight_dist, disc.distance(), disc.max_height, disc.flight_time,
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
