extends Control
## A small arrow pinned to the edge of the screen, pointing the way to the
## basket whenever the basket is off screen.
##
## The finder beam in basket.gd solves "where is it, out there somewhere";
## this solves "which way do I turn". They are complementary: the beam is
## useless when the basket is behind you, and the arrow is clutter once you
## can see the target, so the arrow hides itself as soon as the basket is
## comfortably in view.
##
## Rides the same P toggle as the beam and the flight paths, so turning the
## markers off for a screenshot turns this off too.

const MARGIN := 44.0            ## Keep the arrow this far inside the edge (px).
const SIZE := 21.0
const COLOR_FILL := Color(0.95, 0.76, 0.28, 0.92)
const COLOR_EDGE := Color(0.15, 0.10, 0.02, 0.55)

var camera: Camera3D
var target: Node3D              ## The basket.
var enabled := true             ## Follows the basket's beam (P).

var _at := Vector2.ZERO
var _angle := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## True when the arrow is currently being shown (tests ask).
func showing() -> bool:
	return visible


## Which way the arrow points, in radians, screen space (0 = right).
func angle() -> float:
	return _angle


func _process(_delta: float) -> void:
	var was := visible
	visible = false
	if not enabled or camera == null or not is_instance_valid(target):
		if was:
			queue_redraw()
		return
	var vp := get_viewport_rect().size
	var centre := vp * 0.5
	# Aim at the band, not the base: that is the part you are throwing at.
	var p: Vector3 = target.global_position + Vector3(0, 1.0, 0)
	var behind := camera.is_position_behind(p)
	var sp := camera.unproject_position(p)
	# unproject_position mirrors points that are behind the camera, so the
	# direction has to be flipped back or the arrow points exactly wrong.
	var dir := sp - centre
	if behind:
		# Behind you, the only useful instruction is "turn". Drop the
		# vertical component so the arrow always sends you left or right --
		# a target dead astern has almost no horizontal offset, so left to
		# itself the arrow points straight up, which reads as "above you".
		dir = Vector2(-dir.x, 0.0)
		if absf(dir.x) < 0.001:
			dir.x = 1.0
	if dir.length() < 0.001:
		dir = Vector2.UP
	# Never let the margin eat the whole screen. The HUD's content scale
	# shrinks the logical viewport, so a big --ui-scale or a small window
	# can leave less than 2 * MARGIN to work with -- and a negative-size
	# inset means has_point() is always false and the arrow sticks on
	# forever.
	var m := minf(MARGIN, minf(vp.x, vp.y) * 0.22)
	var inset := Rect2(Vector2(m, m), vp - Vector2(m, m) * 2.0)
	if not behind and inset.has_point(sp):
		return                   # you can already see it; stay out of the way
	# Push out from the centre until we meet the inset rectangle.
	var d := dir.normalized()
	var hx := (inset.size.x * 0.5) / maxf(absf(d.x), 0.0001)
	var hy := (inset.size.y * 0.5) / maxf(absf(d.y), 0.0001)
	_at = centre + d * minf(hx, hy)
	_angle = d.angle()
	visible = true
	queue_redraw()


func _draw() -> void:
	var d := Vector2.RIGHT.rotated(_angle)
	var n := Vector2(-d.y, d.x)
	var tip := _at + d * SIZE
	var a := _at - d * SIZE * 0.6 + n * SIZE * 0.72
	var b := _at - d * SIZE * 0.6 - n * SIZE * 0.72
	var tri := PackedVector2Array([tip, a, b])
	draw_colored_polygon(tri, COLOR_FILL)
	draw_polyline(PackedVector2Array([tip, a, b, tip]), COLOR_EDGE, 1.5)
