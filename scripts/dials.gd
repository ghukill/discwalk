extends Control
## Two small airplane-style instruments for the top-right corner:
##
## - Heading (H): a compass card that turns under a fixed lubber mark, with
##   N / E / S / W and the heading in degrees. North is -Z (the way you face
##   in a fresh world), east is +X.
## - Horizon (J): an attitude indicator. The sky/ground split moves with how
##   far you look up or down, with a pitch ladder every 10 degrees. The little
##   orange chevron is where a disc would leave: your view plus the panel's
##   launch offset (it sits on the centre wings when the offset is 0).
##
## Both are drawn with _draw (no textures), faint, and toggle independently.

const SIZE := 84.0                   ## Dial diameter (px).
const GAP := 10.0
const ALPHA := 0.55                  ## Overall faintness.
const PITCH_PX := 1.6                ## Horizon dial: pixels per degree.

var camera: Camera3D
var offset_source: Callable          ## () -> float: launch offset (deg).
var show_heading := true
var show_horizon := true

var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	custom_minimum_size = Vector2(SIZE * 2 + GAP, SIZE + 16)


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
	# Right-aligned: horizon dial in the corner, heading dial to its left.
	var r := SIZE * 0.5
	var right := Vector2(size.x - r, r)
	var left := Vector2(size.x - r * 3.0 - GAP, r)
	if show_horizon:
		_draw_horizon(right, r)
	if show_heading:
		_draw_heading(left if show_horizon else right, r)


func _col(c: Color, a := 1.0) -> Color:
	return Color(c, c.a * a * ALPHA)


func _text(at: Vector2, s: String, fs: int, c: Color) -> void:
	var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_font, at - Vector2(w * 0.5, -fs * 0.35), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)


func _draw_heading(c: Vector2, r: float) -> void:
	var white := Color(1, 1, 1)
	draw_circle(c, r, _col(Color(0.05, 0.07, 0.06, 0.75)))
	draw_arc(c, r - 0.5, 0, TAU, 48, _col(white, 0.7), 1.2, true)
	var h := heading()
	# Card: rotate so the current heading is at the top.
	for deg in range(0, 360, 10):
		var a := deg_to_rad(deg - h) - PI / 2.0
		var dir := Vector2(cos(a), sin(a))
		var long := deg % 30 == 0
		draw_line(c + dir * (r - (7.0 if long else 4.0)), c + dir * (r - 1.5),
			_col(white, 0.9 if long else 0.5), 1.0, true)
	for item in [[0, "N"], [90, "E"], [180, "S"], [270, "W"]]:
		var a := deg_to_rad(item[0] - h) - PI / 2.0
		var col := Color(1, 0.55, 0.35) if item[0] == 0 else white
		_text(c + Vector2(cos(a), sin(a)) * (r - 15.0), item[1], 11, _col(col))
	# Lubber mark (fixed, top) and readout.
	var t := c + Vector2(0, -r + 1)
	draw_colored_polygon(PackedVector2Array([t, t + Vector2(-4, -6), t + Vector2(4, -6)]), _col(Color(1, 0.75, 0.3)))
	_text(c, "%03d°" % (int(round(h)) % 360), 12, _col(white))
	_text(c + Vector2(0, r + 9), "heading", 9, _col(white, 0.6))


func _draw_horizon(c: Vector2, r: float) -> void:
	var white := Color(1, 1, 1)
	var sky := Color(0.35, 0.55, 0.8, 0.85)
	var ground := Color(0.45, 0.36, 0.22, 0.85)
	var p := view_pitch()
	var circle := PackedVector2Array()
	for i in 48:
		var a := TAU * i / 48.0
		circle.append(c + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(circle, _col(sky))
	# Ground: the part of the circle below the (moving) horizon line.
	var hy := c.y + p * PITCH_PX
	var below := PackedVector2Array([Vector2(c.x - r - 2, hy), Vector2(c.x + r + 2, hy),
		Vector2(c.x + r + 2, c.y + r + 2), Vector2(c.x - r - 2, c.y + r + 2)])
	for poly in Geometry2D.intersect_polygons(circle, below):
		draw_colored_polygon(poly, _col(ground))
	# Horizon line and pitch ladder (every 10 deg, clipped to the dial).
	for deg in range(-90, 91, 10):
		var y := c.y + (p - deg) * PITCH_PX
		if absf(y - c.y) > r - 4.0:
			continue
		var half := r * (0.9 if deg == 0 else (0.32 if deg % 20 == 0 else 0.2))
		half = minf(half, sqrt(maxf(r * r - (y - c.y) * (y - c.y), 0.0)) - 2.0)
		draw_line(Vector2(c.x - half, y), Vector2(c.x + half, y), _col(white, 0.9 if deg == 0 else 0.55), 1.0, true)
		if deg != 0 and deg % 20 == 0:
			_text(Vector2(c.x + half + 9, y), str(absi(deg)), 8, _col(white, 0.6))
	draw_arc(c, r - 0.5, 0, TAU, 48, _col(white, 0.7), 1.2, true)
	# Fixed wings (where you look).
	var wing := Color(1, 0.85, 0.3)
	draw_line(c + Vector2(-18, 0), c + Vector2(-6, 0), _col(wing), 2.0, true)
	draw_line(c + Vector2(6, 0), c + Vector2(18, 0), _col(wing), 2.0, true)
	draw_circle(c, 1.8, _col(wing))
	# Launch chevron: view + offset.
	var off: float = offset_source.call() if offset_source.is_valid() else 0.0
	var ly := clampf(c.y - off * PITCH_PX, c.y - r + 6, c.y + r - 6)
	var lx := c.x + 24.0
	draw_colored_polygon(PackedVector2Array([Vector2(lx - 6, ly), Vector2(lx, ly - 4), Vector2(lx, ly + 4)]),
		_col(Color(1, 0.5, 0.15)))
	_text(c + Vector2(0, r - 12), "%+d°" % int(round(p)), 11, _col(white))
	_text(c + Vector2(0, r + 9), "horizon", 9, _col(white, 0.6))
