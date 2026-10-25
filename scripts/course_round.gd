extends Node
## Course Play: a round of disc golf over the course's holes (course.gd).
##
## Free Play and Course Play stand on the same course with the same tees and
## baskets. This is what Course Play adds:
##   - You start on hole 1's tee pad, facing down it. GOTO and the shot
##     circle start on (both still toggle, for friendly play).
##   - Every disc you throw is a stroke (cubes and launches are toys and
##     don't count).
##   - A goto walks you to your disc and stands you a step behind it facing
##     the basket (left / right and up / down). Goto off, you walk there
##     yourself: a ring marks the lie, and stepping into it picks the disc
##     up (with the shot circle on, no throwing a disc until you have).
##   - A disc in THIS hole's basket holes out: the confetti flies, then
##     "Walking to next hole..." and you're walked to the next tee. Moving
##     or throwing skips the walk. Another hole's basket is just for fun.
##   - M (controller LB + B): the hole overview. The camera flies up until
##     tee, basket, you (and your lie) are all in view, with big rings on each; M again
##     flies back down.
## After the last hole: "Round complete!" and you roam free.

const ShotCircle := preload("res://scripts/shot_circle.gd")
const Course := preload("res://scripts/course.gd")

signal finished(strokes)

const OUT_PAUSE := 2.4               ## Holed out: this long before the walk starts (s).
const AIM_HEIGHT := 1.0              ## Face this high up the basket (the chains).
const OVERVIEW_TIME := 1.1           ## Fly up / down (s).
const OVERVIEW_PITCH := 58.0         ## Overview looks this far down (deg).

var terrain: Node3D
var player: CharacterBody3D
var thrower: Node
var camera: Camera3D                 ## The walker's own camera.
var clouds: Node3D
var environment: Environment         ## Fog thins out in the overview.
var label: Label                     ## Top left: hole, distance, strokes.
var banner: Label                    ## Middle: "Walking to next hole..." etc.

var active := false
var state := ""                      ## tee, playing, holed, walking, done
var hole := 0                        ## Index into holes (0 = hole 1).
var strokes := 0                     ## This hole.
var total := 0                       ## This round.
var scores: Array[int] = []          ## Strokes per finished hole.

var overview := false
var _ov_cam: Camera3D
var _ov_rings: Array = []
var _ov_tween: Tween
var _ov_clouds := true
var _ov_fog := 0.0
var _banner_t := 0.0


func _ready() -> void:
	_ov_cam = Camera3D.new()
	_ov_cam.name = "OverviewCam"
	_ov_cam.far = 1200.0
	add_child(_ov_cam)
	var looks := [[Color(1.0, 1.0, 1.0, 0.95), 4.0], [Color(1.0, 0.82, 0.2, 0.95), 4.0],
		[Color(0.55, 0.85, 1.0, 0.95), 2.5], [Color(1.0, 0.55, 0.85, 0.95), 2.5]]   # tee, basket, you, lie
	for l in looks:
		var r := ShotCircle.new()
		r.terrain = terrain
		r.color = l[0]
		r.radius = l[1]
		r.square = 0.7
		r.gap = 1.5
		r.on_top = true                 # seen through the canopy from above
		add_child(r)
		_ov_rings.append(r)
	player.walk_done.connect(_arrive)
	player.walk_stuck.connect(_arrive)
	thrower.thrown.connect(_on_thrown)
	thrower.reached.connect(_on_reached)
	thrower.basket_scored.connect(_on_scored)


func holes() -> Array:
	return terrain.holes


func current() -> Dictionary:
	return holes()[hole] if active and hole < holes().size() else {}


## A fresh round from hole 1 (also after N rolls a new course).
func start() -> void:
	_end_overview(true)
	player.stop_walk()
	active = not holes().is_empty()
	if not active:
		stop()
		return
	thrower.course_round = self
	hole = 0
	total = 0
	scores.clear()
	thrower.set_warp(true)
	thrower.set_circle(true)
	_to_tee(0)
	_show_banner("Hole %d" % holes()[0].n, 2.0)


## Back to Free Play rules (the course stays, nothing is enforced).
func stop() -> void:
	_end_overview(true)
	if state == "walking":
		player.stop_walk()
	active = false
	state = ""
	thrower.course_round = null
	thrower.locked = false
	if label != null:
		label.visible = false


## True while you're playing a hole (on its tee or out on it).
func in_hole() -> bool:
	return active and (state == "tee" or state == "playing")


## Where a goto should face: the current basket's chains, while you're
## playing a hole (null otherwise, and the goto faces down the throw).
func goto_aim():
	if not active or not (state == "tee" or state == "playing"):
		return null
	return current().basket.global_position + Vector3(0, AIM_HEIGHT, 0)


## Where you stand on a tee (m): near the back of the pad, on the ground.
func tee_spot(h: Dictionary) -> Vector3:
	var fwd := Vector3(-sin(h.pad_yaw), 0, -cos(h.pad_yaw))
	var p: Vector3 = h.tee - fwd * 0.9
	return Vector3(p.x, terrain.height_at(p.x, p.z) + 0.2, p.z)


func _to_tee(i: int) -> void:
	hole = i
	strokes = 0
	state = "tee"
	var h: Dictionary = holes()[i]
	thrower.clear()                     # last hole's discs and paths go
	player.respawn(tee_spot(h), h.yaw)
	thrower.locked = false


func _on_thrown(disc: Node) -> void:
	if not active or not (state == "tee" or state == "playing"):
		return
	if not ("model" in disc):
		return
	strokes += 1
	total += 1
	state = "playing"


## Course Play picks your disc up when you get to it (goto or on foot):
## it's back in your hand for the next throw. Untyped: may be freed.
func _on_reached(disc, _lie: Vector3) -> void:
	if in_hole() and is_instance_valid(disc):
		disc.queue_free()


func _on_scored(disc: Node, basket: Node) -> void:
	if not active or state != "playing" or not ("model" in disc):
		return
	if basket != current().basket:
		return
	state = "holed"
	thrower.locked = true
	thrower.release_lie()
	scores.append(strokes)
	var n: int = current().n
	_show_banner("Hole %d in %d!" % [n, strokes] if strokes > 1 else "Hole %d: ACE!" % n, OUT_PAUSE)
	get_tree().create_timer(OUT_PAUSE).timeout.connect(_after_hole_out)


func _after_hole_out() -> void:
	if not active or state != "holed":
		return
	thrower.collect_discs()
	if hole + 1 >= holes().size():
		state = "done"
		thrower.locked = false
		_show_banner("Round complete!  %d holes in %d strokes" % [holes().size(), total], 6.0)
		finished.emit(total)
		return
	state = "walking"
	_show_banner("Walking to next hole...", 1e9)
	var to := tee_spot(holes()[hole + 1])
	player.walk(to, Course.route(terrain, player.global_position, to))


## On the next tee: either walked all the way, or skipped / stuck (then
## you're just put there, with a soft flash).
func _arrive() -> void:
	if not active or state != "walking":
		return
	player.stop_walk()
	if thrower.warp_flash != null:
		thrower.warp_flash.color.a = 0.4
	_to_tee(hole + 1)
	_show_banner("Hole %d" % holes()[hole].n, 2.0)


## Straight to another hole's tee, without playing the ones in between.
## Meant for building a course: you are editing hole 11 and you want to be
## standing on it, not three holes back. It wraps, so ] off the last hole
## puts you on the first.
##
## What it does NOT do is invent a score. Strokes on the hole you leave are
## dropped and nothing is recorded for the holes you step over, so the card
## ends up with fewer entries than holes -- which is the truth about a round
## you skipped through.
func jump_to(i: int) -> void:
	if not active or holes().is_empty():
		return
	_end_overview(true)
	if state == "walking":
		player.stop_walk()
	var n := holes().size()
	_to_tee(((i % n) + n) % n)
	_show_banner("Hole %d" % holes()[hole].n, 1.6)


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event.is_action_pressed("hole_next"):
		jump_to(hole + 1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("hole_prev"):
		jump_to(hole - 1)
		get_viewport().set_input_as_handled()
		return
	if state == "walking" and _skips_walk(event):
		_arrive()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("overview") and _pad_lb(event):
		set_overview(not overview)
		get_viewport().set_input_as_handled()


## Any move, hop or throw ends the walk (you're put on the tee).
func _skips_walk(event: InputEvent) -> bool:
	for a in ["move_forward", "move_back", "move_left", "move_right", "jump", "throw_disc"]:
		if event.is_action_pressed(a):
			return true
	return event is InputEventMouseButton and event.pressed \
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


## Keys always; a pad's B only with LB held (B alone throws).
func _pad_lb(event: InputEvent) -> bool:
	return not (event is InputEventJoypadButton) or Input.is_action_pressed("setup_disc")


# --- hole overview -----------------------------------------------------------

## Fly the camera up over the hole (tee, basket and you in view), or back.
func set_overview(on: bool) -> void:
	if on == overview:
		return
	if on:
		if not (state == "tee" or state == "playing"):
			return
		if thrower.follow_cam.active():
			thrower._note("overview: wait for the throw to stop", 1.5)
			return
		_start_overview()
	else:
		_end_overview(false)


func _start_overview() -> void:
	overview = true
	player.frozen = true
	thrower.locked = true
	var h := current()
	var tee: Vector3 = h.tee
	var bk: Vector3 = h.basket.global_position
	var me := player.global_position
	_ov_rings[0].show_at(tee)
	_ov_rings[1].show_at(bk)
	_ov_rings[2].show_at(me)
	var pts := [tee, bk, me]
	var lie: Vector3 = thrower.lie()
	if thrower.has_lie() and Vector2(lie.x - me.x, lie.z - me.z).length() > 2.0:
		_ov_rings[3].show_at(lie)       # still to walk to
		pts.append(lie)
	if clouds != null:
		_ov_clouds = clouds.visible
		clouds.visible = false
	if environment != null:
		_ov_fog = environment.fog_density
		create_tween().tween_property(environment, "fog_density", _ov_fog * 0.2, OVERVIEW_TIME)
	# Basket at the top of the screen: look along tee -> basket, down a lot.
	var along := Vector3(bk.x - tee.x, 0, bk.z - tee.z)
	along = along.normalized() if along.length() > 1.0 else Vector3.FORWARD
	var side := along.cross(Vector3.UP)
	var mid := Vector3.ZERO
	for p in pts:
		mid += p
	mid /= pts.size()
	var half_l := 0.0
	var half_w := 0.0
	for p in pts:
		half_l = maxf(half_l, absf((p - mid).dot(along)))
		half_w = maxf(half_w, absf((p - mid).dot(side)))
	var fov := deg_to_rad(_ov_cam.fov)
	var aspect := 16.0 / 9.0
	var vp := get_viewport()
	if vp != null and vp.get_visible_rect().size.y > 0:
		aspect = vp.get_visible_rect().size.x / vp.get_visible_rect().size.y
	# Fit the long way into the (tilted) height, the wide way into the width.
	# (The near end looms larger in a tilted view, hence the extra 30%.)
	var need_l := 1.3 * (half_l + 15.0) * sin(deg_to_rad(OVERVIEW_PITCH)) / tan(fov * 0.5)
	var need_w := 1.15 * (half_w + 15.0) / (tan(fov * 0.5) * aspect)
	var dist := maxf(maxf(need_l, need_w), 30.0)
	var pitch := deg_to_rad(OVERVIEW_PITCH)
	var look := (along * cos(pitch) + Vector3.DOWN * sin(pitch)).normalized()
	var to := Transform3D(Basis.looking_at(look, Vector3.UP), mid - look * dist)
	_ov_cam.global_transform = camera.global_transform
	_ov_cam.fov = camera.fov
	_ov_cam.current = true
	_fly(to, 75.0)


func _end_overview(now: bool) -> void:
	if not overview:
		return
	overview = false
	for r in _ov_rings:
		r.visible = false
	if clouds != null:
		clouds.visible = _ov_clouds
	if environment != null:
		if now:
			environment.fog_density = _ov_fog
		else:
			create_tween().tween_property(environment, "fog_density", _ov_fog, OVERVIEW_TIME)
	if now:
		_back_down()
		return
	_fly(camera.global_transform, camera.fov, _back_down)


func _back_down() -> void:
	if _ov_tween != null:
		_ov_tween.kill()
	camera.current = true
	player.frozen = false
	if state == "tee" or state == "playing":
		thrower.locked = false


func _fly(to: Transform3D, fov: float, then := Callable()) -> void:
	if _ov_tween != null:
		_ov_tween.kill()
	_ov_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_ov_tween.tween_property(_ov_cam, "global_transform", to, OVERVIEW_TIME)
	_ov_tween.tween_property(_ov_cam, "fov", fov, OVERVIEW_TIME)
	if then.is_valid():
		_ov_tween.chain().tween_callback(then)


# --- HUD ---------------------------------------------------------------------

func _show_banner(text: String, secs: float) -> void:
	if banner == null:
		return
	banner.text = text
	_banner_t = secs


func _process(delta: float) -> void:
	if banner != null:
		_banner_t -= delta
		banner.visible = _banner_t > 0.0 and banner.text != ""
		banner.modulate.a = clampf(_banner_t / 0.6, 0.0, 1.0)
	if label == null:
		return
	label.visible = active
	if not active:
		return
	if state == "done":
		label.text = "Round complete  ·  %d strokes" % total
		return
	var h := current()
	var bk: Vector3 = h.basket.global_position
	var me := player.global_position
	var d := Vector2(bk.x - me.x, bk.z - me.z).length()
	# Hole numbers are the course's: a back nine runs 10 / 18 .. 18 / 18.
	var last: int = holes().back().n
	label.text = "Hole %d / %d  ·  %.0f m  ·  Strokes %d  ·  Total %d" % [
		h.n, last, d, strokes, total]
	if state == "walking":
		label.text = "Hole %d / %d  ·  walking to the tee  ·  Total %d" % [
			holes()[hole + 1].n, last, total]
