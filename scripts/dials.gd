extends Control
## Two small airplane-style instruments, side by side in the throw HUD:
##
## - Heading: a compass card that turns under a fixed lubber mark, with
##   N / E / S / W and the heading in degrees. North is -Z (the way you face
##   in a fresh world), east is +X. When there is wind (wind.gd) a pale blue
##   arrow lies across the dial, pointing the way the air is going, so it
##   reads against your own heading at a glance: pointing down the dial is in
##   your face, pointing up is at your back. It breathes with the gusts.
## - Horizon: an attitude indicator. The sky/ground split moves with how far
##   you look up or down, with a pitch ladder every 10 degrees. Where you look
##   is your launch angle, so the readout is the angle a disc would leave at.
##
## Under the pair, one line of small print: the wind you feel, in the unit the
## speed bar is in, and how it sits against your throw ("11 mph head L→R").
##
## All drawn with _draw (no textures).

const GAP := 10.0
const PITCH_PX_PER_R := 0.045        ## Horizon dial: pixels per degree, per px of radius.
const WIND_INK := Color(0.66, 0.88, 1.0)   ## Cool, so it is not the heading.
const WIND_LINE := 22.0              ## Room under the dials for the wind readout (px).

var camera: Camera3D
var wind: RefCounted                 ## wind.gd, or null (no arrow, no line).
var setup: Node                      ## throw_setup.gd: its speed unit is the wind's too.
var radius := 32.0                   ## Dial radius (px).
var font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if font == null:
		font = ThemeDB.fallback_font
	custom_minimum_size = Vector2(radius * 4 + GAP, radius * 2 + WIND_LINE)


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
	_draw_wind_line(Vector2(r * 2.0 + GAP * 0.5, r * 2.0 + WIND_LINE - 4.0))


## Where the wind arrow points on the dial (rad, screen angle; 0 = right,
## -PI/2 = up = the way you face), or NAN when it is calm. Tests read it.
func wind_arrow_angle() -> float:
	if wind == null or wind.is_calm():
		return NAN
	var w: Vector3 = wind.head()
	var to := fposmod(rad_to_deg(atan2(w.x, -w.z)), 360.0)   # bearing it blows TOWARD
	return deg_to_rad(to - heading()) - PI / 2.0


## The line under the dials: "wind 11 mph head L→R", or a dim "calm".
func wind_readout() -> String:
	if wind == null or wind.is_calm():
		return "calm"
	var w: Vector3 = wind.head()
	var f := -camera.global_transform.basis.z
	var rel: String = wind.relative_name(w, Vector3(f.x, 0.0, f.z))
	var speed := "%.1f m/s" % w.length()
	if setup != null:
		speed = "%s %s" % [setup.speed_str(w.length()), setup.unit_name()]
	return speed if rel == "" else "%s  %s" % [speed, rel]


func _draw_wind_line(at: Vector2) -> void:
	if wind == null:
		return
	if wind.is_calm():
		_text(at, "wind calm", 9, Color(1.0, 0.88, 0.7, 0.4))
	else:
		_text(at, "wind " + wind_readout(), 10, Color(WIND_INK, 0.95))


## The wind on the heading dial: an arrow lying across it, pointing the way
## the air is going. Its ends stand outside the bezel, head downwind and
## feathers upwind, with only a faint shaft across the card between them, so
## the letters and the heading stay readable through it. Brighter and bolder
## the harder it blows, so a gust is something you see arrive.
func _draw_wind_arrow(c: Vector2, r: float) -> void:
	var a := wind_arrow_angle()
	if is_nan(a):
		return
	var dir := Vector2(cos(a), sin(a))
	var side := Vector2(-dir.y, dir.x)
	var k := clampf(wind.head().length() / 9.0, 0.0, 1.0)      # 20 mph = full strength
	var col := Color(WIND_INK, lerpf(0.7, 1.0, k))
	var grow := lerpf(0.8, 1.2, k)
	draw_line(c - dir * r, c + dir * r, Color(WIND_INK, lerpf(0.16, 0.34, k)), 1.0, true)
	var base := c + dir * (r + 2.5)
	draw_colored_polygon(PackedVector2Array([base + dir * 6.5 * grow,
		base + side * 3.6 * grow, base - side * 3.6 * grow]), col)
	var tail := c - dir * (r + 2.5)
	for i in 2:
		var at := tail - dir * (1.0 + i * 3.0)
		draw_line(at, at - dir * 3.0 + side * 3.2 * grow, col, 1.3, true)
		draw_line(at, at - dir * 3.0 - side * 3.2 * grow, col, 1.3, true)


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
	_draw_wind_arrow(c, r)
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
