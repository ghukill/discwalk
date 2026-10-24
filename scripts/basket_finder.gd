extends Node3D
## Finding the basket: a tall beam standing over the one you are playing, and
## a small arrow at the edge of the screen pointing the way whenever it is off
## screen. Both follow ONE selection, so the thing the arrow points at is
## always the thing with the beam on it.
##
## Which basket that is depends on how you are playing:
## - Course Play: the hole you are on. Nothing to choose, and nine beams
##   standing over nine baskets would just be nine beams.
## - Free Play: whichever you picked, cycled with B (Shift+B goes back). There
##   is no "next hole" in Free Play, so the choice has to be yours.
##
## The beam is sized to be READ, not to be to scale: it widens with distance
## so it stays the same apparent thickness from a tee as from ten paces (a
## 0.45 m beam at 90 m is about one pixel), and it fades out as you walk up,
## because no_depth_test makes it draw over the basket and the last thing you
## want when putting is a stripe across the target.

const BEAM_WIDTH := 0.45        ## Beam thickness at arm's length (m).
const BEAM_HEIGHT := 40.0       ## Tall enough to clear the oaks.
const BEAM_ALPHA := 0.5
const BEAM_FADE_NEAR := 9.0     ## Gone by this close (m) ...
const BEAM_FADE_FAR := 30.0     ## ... and fully there from this far.
const BEAM_APPARENT := 0.018    ## Wanted apparent width, as a fraction of range.
const BEAM_MAX_SCALE := 4.5     ## Don't let it become a wall.
const COLOR_BAND := Color(0.98, 0.78, 0.10)   ## The basket's own safety yellow.

const ARROW_MARGIN := 44.0      ## Inset from the screen edge (px).
const ARROW_SIZE := 21.0

var terrain: Node3D
var camera: Camera3D
var course_round: Node          ## null, or Course Play (course_round.gd).
var hud: CanvasLayer            ## Where the arrow is drawn.

var enabled := true             ## Follows the Paths/beams lamp (P).
var index := 0                  ## Free Play: which basket is picked.

var _beam: MeshInstance3D
var _beam_mat: StandardMaterial3D
var _arrow: Control


func _ready() -> void:
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.albedo_color = Color(COLOR_BAND, BEAM_ALPHA)
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.disable_fog = true           # or it dissolves at the range it is for
	_beam_mat.no_depth_test = true         # visible through a hill you are behind
	var bm := BoxMesh.new()
	bm.size = Vector3(BEAM_WIDTH, BEAM_HEIGHT, BEAM_WIDTH)
	bm.material = _beam_mat
	_beam = MeshInstance3D.new()
	_beam.name = "Beam"
	_beam.mesh = bm
	_beam.top_level = true
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)

	_arrow = Control.new()
	_arrow.name = "BasketArrow"
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_arrow.draw.connect(_draw_arrow)
	if hud != null:
		hud.add_child(_arrow)


## The basket the beam and the arrow are both about, or null.
func selected() -> Node3D:
	if course_round != null and course_round.active:
		var c: Dictionary = course_round.current()
		if c.is_empty() or not is_instance_valid(c.basket):
			return null                    # between holes, or the round is done
		return c.basket
	var bs: Array = _baskets()
	if bs.is_empty():
		return null
	index = wrapi(index, 0, bs.size())
	return bs[index]


## Free Play: pick the next basket (step -1 for the previous one). Does
## nothing in Course Play, where the hole decides.
func cycle(step: int) -> void:
	if course_round != null and course_round.active:
		return
	var bs: Array = _baskets()
	if bs.is_empty():
		return
	index = wrapi(index + step, 0, bs.size())


## Which one of the nine it is, for a note on screen (1-based), or 0.
func number() -> int:
	var bs: Array = _baskets()
	if bs.is_empty() or (course_round != null and course_round.active):
		return 0
	return wrapi(index, 0, bs.size()) + 1


func count() -> int:
	return _baskets().size()


func set_enabled(on: bool) -> void:
	enabled = on
	_beam.visible = false
	if _arrow != null:
		_arrow.queue_redraw()


## Is the arrow on screen right now (tests)?
func showing() -> bool:
	return _arrow != null and _arrow.visible and _arrow_dir() != Vector2.ZERO


func _baskets() -> Array:
	if terrain == null or not ("baskets" in terrain):
		return []
	var out: Array = []
	for b in terrain.baskets:
		if is_instance_valid(b):
			out.append(b)
	return out


## The point both the beam and the arrow aim at: the chains.
func target_point():
	var b := selected()
	if b == null:
		return null
	return b.global_position + Vector3(0.0, (b.CHAIN_BOTTOM + b.BAND_Y) * 0.5, 0.0)


func _process(_delta: float) -> void:
	var b := selected()
	if not enabled or b == null or camera == null:
		_beam.visible = false
		if _arrow != null:
			_arrow.queue_redraw()
		return
	var at: Vector3 = b.global_position
	_beam.global_position = at + Vector3(0.0, BEAM_HEIGHT * 0.5, 0.0)
	var d: float = camera.global_position.distance_to(at)
	# Fade in with distance: close up the beam is in the way, and you can see
	# the basket perfectly well anyway.
	var t := clampf((d - BEAM_FADE_NEAR) / (BEAM_FADE_FAR - BEAM_FADE_NEAR), 0.0, 1.0)
	_beam_mat.albedo_color = Color(COLOR_BAND, BEAM_ALPHA * t)
	_beam.visible = t > 0.01
	# Constant apparent width, so it reads the same from any range.
	var s := clampf(d * BEAM_APPARENT / BEAM_WIDTH, 1.0, BEAM_MAX_SCALE)
	_beam.scale = Vector3(s, 1.0, s)
	_arrow.queue_redraw()


## Which way the arrow points, or ZERO when the basket is on screen.
##
## Worked out in the CAMERA's own axes -- how far right and how far up the
## basket is from where we are looking -- rather than from unproject_position.
## Projection is unusable exactly where this matters: a point level with the
## camera plane (the basket straight out to your side) sits at infinity, so
## the screen position explodes and is_position_behind flips either way. An
## arrow built on that agreed with itself at 90 degrees left and 90 degrees
## right, pointing the same way for both. Camera axes are well behaved all the
## way round.
##
## Behind you, only the left/right sense means anything -- "turn round", not
## "it is above you" -- so the vertical part is dropped rather than kept.
func _arrow_dir() -> Vector2:
	var p = target_point()
	if p == null or camera == null or not enabled:
		return Vector2.ZERO
	var b := camera.global_transform.basis
	var to: Vector3 = p - camera.global_position
	var right := to.dot(b.x)
	var up := to.dot(b.y)
	var fwd := to.dot(-b.z)
	if fwd <= 0.0:
		# Behind: turn whichever way is shorter, and never nothing.
		return Vector2(-1.0 if right < 0.0 else 1.0, 0.0)
	# In front: it is only worth an arrow if it is off the screen.
	var vp := _arrow.get_viewport_rect().size
	var sp: Vector2 = camera.unproject_position(p)
	if _inset(vp).has_point(sp):
		return Vector2.ZERO               # you can see it: no arrow
	var dir := Vector2(right, -up)        # screen y points down
	return dir.normalized() if dir.length() > 1e-5 else Vector2.RIGHT


## The screen minus a margin. Clamped to a fraction of the SHORTER edge: a
## fixed 44 px inset inverts the rectangle on a tiny viewport (headless runs
## at 64x64), and an inverted rect contains nothing, so the arrow would be
## stuck on for ever.
func _inset(vp: Vector2) -> Rect2:
	var m := minf(ARROW_MARGIN, minf(vp.x, vp.y) * 0.22)
	return Rect2(Vector2(m, m), vp - Vector2(m, m) * 2.0)


func _draw_arrow() -> void:
	var d := _arrow_dir()
	if d == Vector2.ZERO:
		return
	var vp := _arrow.get_viewport_rect().size
	var inset := _inset(vp)
	var centre := vp * 0.5
	# Walk out from the middle until we touch the inset edge.
	var half := inset.size * 0.5
	var tx: float = INF if absf(d.x) < 1e-4 else half.x / absf(d.x)
	var ty: float = INF if absf(d.y) < 1e-4 else half.y / absf(d.y)
	var at := centre + d * minf(tx, ty)
	var side := Vector2(-d.y, d.x)
	var tri := PackedVector2Array([
		at + d * ARROW_SIZE * 0.6,
		at - d * ARROW_SIZE * 0.4 + side * ARROW_SIZE * 0.45,
		at - d * ARROW_SIZE * 0.4 - side * ARROW_SIZE * 0.45])
	_arrow.draw_colored_polygon(tri, Color(COLOR_BAND, 0.9))
	_arrow.draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]),
		Color(0, 0, 0, 0.55), 1.5, true)
