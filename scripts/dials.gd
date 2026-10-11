extends Control
## Two small airplane-style instruments, side by side in the throw HUD:
##
## - Heading: a compass card that turns under a fixed lubber mark, with
##   N / E / S / W and the heading in degrees. North is -Z (the way you face
##   in a fresh world), east is +X.
## - Horizon: an attitude indicator. The sky/ground split moves with how far
##   you look up or down, with a pitch ladder every 10 degrees. Where you look
##   is your launch angle, so the readout is the angle a disc would leave at.
##
## Both are drawn with _draw (no textures).

const GAP := 10.0
const PITCH_PX_PER_R := 0.045        ## Horizon dial: pixels per degree, per px of radius.

var camera: Camera3D
var radius := 32.0                   ## Dial radius (px).
var font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if font == null:
		font = ThemeDB.fallback_font
	custom_minimum_size = Vector2(radius * 4 + GAP, radius * 2 + 14)


func _process(_d: float) -> void:
	queue_redraw()


## Degrees, 0..360, clockwise from north (-Z).
func heading() -> float:
	var f := -camera.global_transform.basis.z
	return fposmod(rad_to_deg(atan2(f.x, -f.z)), 360.0)


## Degrees above (+) / below (-) the horizon you're looking.
func view_pitch() -> float:
	var f := -camera.global_transform.basis.z
	return rad_to_deg(asin(clampf(f.y, -1.0, 1.0)))


func _draw() -> void:
	if camera == null:
		return
	var r := radius
	_draw_heading(Vector2(r, r), r)
	_draw_horizon(Vector2(r * 3.0 + GAP, r), r)


func _text(at: Vector2, s: String, fs: int, c: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, at - Vector2(w * 0.5, -fs * 0.35), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)


func _bezel(c: Vector2, r: float) -> void:
	draw_arc(c, r, 0, TAU, 48, Color(0.05, 0.045, 0.04, 0.9), 3.0, true)
	draw_arc(c, r + 1.5, 0, TAU, 48, Color(0.62, 0.5, 0.32, 0.55), 1.0, true)


func _draw_heading(c: Vector2, r: float) -> void:
	var ink := Color(1.0, 0.93, 0.82, 0.9)
	draw_circle(c, r, Color(0.07, 0.065, 0.055, 0.9))
	var h := heading()
	# Card: rotate so the current heading is at the top.
	for deg in range(0, 360, 10):
		var a := deg_to_rad(deg - h) - PI / 2.0
		var dir := Vector2(cos(a), sin(a))
		var long := deg % 30 == 0
		draw_line(c + dir * (r - (r * 0.2 if long else r * 0.11)), c + dir * (r - 2.0),
			Color(ink, 0.85 if long else 0.4), 1.0, true)
	for item in [[0, "N"], [90, "E"], [180, "S"], [270, "W"]]:
		var a := deg_to_rad(item[0] - h) - PI / 2.0
		var col := Color(1, 0.6, 0.35) if item[0] == 0 else ink
		_text(c + Vector2(cos(a), sin(a)) * (r * 0.74), item[1], 10, col)
	# Lubber mark (fixed, top) and readout.
	var t := c + Vector2(0, -r + 2)
	draw_colored_polygon(PackedVector2Array([t + Vector2(0, 6), t + Vector2(-4, 0), t + Vector2(4, 0)]),
		Color(1, 0.7, 0.3))
	_text(c, "%03d" % (int(round(h)) % 360), 9, ink)
	_bezel(c, r)


func _draw_horizon(c: Vector2, r: float) -> void:
	var ink := Color(1.0, 0.95, 0.88, 0.9)
	var sky := Color(0.3, 0.45, 0.62, 0.9)
	var ground := Color(0.42, 0.31, 0.18, 0.9)
	var px := PITCH_PX_PER_R * r
	var p := view_pitch()
	var circle := PackedVector2Array()
	for i in 48:
		var a := TAU * i / 48.0
		circle.append(c + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(circle, sky)
	# Ground: the part of the circle below the (moving) horizon line.
	var hy := c.y + p * px
	var below := PackedVector2Array([Vector2(c.x - r - 2, hy), Vector2(c.x + r + 2, hy),
		Vector2(c.x + r + 2, c.y + r + 2), Vector2(c.x - r - 2, c.y + r + 2)])
	for poly in Geometry2D.intersect_polygons(circle, below):
		draw_colored_polygon(poly, ground)
	# Horizon line and pitch ladder (every 10 deg, clipped to the dial).
	for deg in range(-90, 91, 10):
		var y := c.y + (p - deg) * px
		if absf(y - c.y) > r - 4.0:
			continue
		var half := r * (0.9 if deg == 0 else (0.32 if deg % 20 == 0 else 0.2))
		half = minf(half, sqrt(maxf(r * r - (y - c.y) * (y - c.y), 0.0)) - 2.0)
		draw_line(Vector2(c.x - half, y), Vector2(c.x + half, y), Color(ink, 0.9 if deg == 0 else 0.5), 1.0, true)
	# Fixed wings (where you look = where the disc leaves).
	var wing := Color(1, 0.72, 0.3)
	draw_line(c + Vector2(-r * 0.55, 0), c + Vector2(-r * 0.18, 0), wing, 2.0, true)
	draw_line(c + Vector2(r * 0.18, 0), c + Vector2(r * 0.55, 0), wing, 2.0, true)
	draw_circle(c, 1.8, wing)
	_text(c + Vector2(0, r * 0.55), "%+d°" % int(round(p)), 11, ink)
	_bezel(c, r)
