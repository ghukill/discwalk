extends Control
## The throw HUD: one small, warm, old-cockpit instrument block in the lower
## right (see docs/THROW-HUD.md and the sketch in docs/mockups/).
##
##   ┌──────────────────────────────┐
##   │  ( disc )✋   ▮ ▯            │  disc tilt (nose + hyzer), hand,
##   │  dd2 · nose +0 · hyzer 10    │  velocity bar, spin bar (dotted = locked)
##   │  (hdg) (hzn)   o Chase view  │
##   │                o Goto        │
##   │                o Paths       │
##   └──────────────────────────────┘
##
## Everything here only shows state; the keys live in throw_setup.gd and
## thrower.gd. The disc is drawn as a real 3D circle projected from slightly
## behind and above, so hyzer drops an edge and nose up opens the ellipse
## (nose is drawn exaggerated so small angles still read).

const Dials := preload("res://scripts/dials.gd")
const Lamps := preload("res://scripts/lamps.gd")

const W := 300.0
const H := 244.0
const PAD := 14.0
const DISC_R := 46.0                 ## Instrument circle radius.
const BAR_W := 16.0
const BAR_H := 80.0
const CAM_ELEV := 20.0               ## Deg: we look at the disc from a bit above.
const NOSE_GAIN := 1.8               ## Nose drawn this many times steeper.

## One colour per disc in the HUD so Tab visibly changes something.
const DISC_COLORS := [Color(1.0, 0.45, 0.7), Color(0.55, 0.85, 0.4), Color(0.36, 0.62, 1.0), Color(1.0, 0.75, 0.3)]

const BG := Color(0.09, 0.075, 0.06, 0.72)
const BRASS := Color(0.66, 0.53, 0.33, 0.6)
const INK := Color(1.0, 0.9, 0.74, 0.92)
const DIM := Color(1.0, 0.88, 0.7, 0.45)
const AMBER := Color(1.0, 0.66, 0.26)

var setup: Node                      ## throw_setup.gd
var camera: Camera3D
var dials: Control
var lamps: Control
var font: Font
var emoji: Font                      ## For ✋, if the system has a colour emoji font.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if font == null:
		font = ThemeDB.fallback_font
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Apple Color Emoji", "Noto Color Emoji", "Segoe UI Emoji", "Twemoji"])
	if sf.has_char(0x270B):
		emoji = sf
	custom_minimum_size = Vector2(W, H)
	size = custom_minimum_size

	dials = Control.new()
	dials.set_script(Dials)
	dials.name = "Dials"
	dials.camera = camera
	dials.radius = 30.0
	dials.font = font
	dials.position = Vector2(PAD, H - PAD - 30.0 * 2 - 4)
	add_child(dials)

	lamps = Control.new()
	lamps.set_script(Lamps)
	lamps.name = "Lamps"
	lamps.font = font
	lamps.position = Vector2(W - PAD - 118.0, H - PAD - 66.0 - 2)
	add_child(lamps)


func _process(_d: float) -> void:
	queue_redraw()


func _draw() -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = BG
	box.set_corner_radius_all(10)
	box.border_color = BRASS
	box.set_border_width_all(1)
	box.shadow_color = Color(0, 0, 0, 0.25)
	box.shadow_size = 6
	draw_style_box(box, Rect2(Vector2.ZERO, size))
	if setup == null:
		return
	var c := Vector2(PAD + DISC_R + 10.0, PAD + DISC_R)
	_draw_disc_instrument(c)
	_draw_bars(Vector2(c.x + DISC_R + 40.0, PAD + 2.0))
	# One line under the instrument: disc, nose, hyzer.
	var d = setup.disc()
	var name: String = d.id if d != null else "-"
	var r: float = setup.roll
	var tilt := "flat" if absf(r) < 0.5 else ("hyzer %d°" % int(round(absf(r))) if r > 0 else "anhyzer %d°" % int(round(absf(r))))
	var y := PAD + DISC_R * 2 + 38.0
	_text(Vector2(PAD, y), name, 13, AMBER)
	var nw := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	_text(Vector2(PAD + nw + 8, y), "nose %+.1f°   %s" % [setup.nose, tilt], 12, INK)
	draw_line(Vector2(PAD, y + 9), Vector2(W - PAD, y + 9), Color(BRASS, 0.35), 1.0)


func _text(at: Vector2, s: String, fs: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var x := at.x
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * 0.5
	draw_string(font, Vector2(x + 1, at.y + 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.45))
	draw_string(font, Vector2(x, at.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## Instrument face + the tilted disc + the hand.
func _draw_disc_instrument(c: Vector2) -> void:
	draw_circle(c, DISC_R, Color(0.05, 0.045, 0.04, 0.85))
	# Faint level reference: a horizon line and a centre tick.
	draw_line(c + Vector2(-DISC_R + 6, 0), c + Vector2(DISC_R - 6, 0), Color(INK, 0.12), 1.0, true)
	draw_line(c + Vector2(0, -DISC_R + 4), c + Vector2(0, -DISC_R + 10), Color(INK, 0.3), 1.0, true)
	_draw_disc(c, DISC_R * 0.68)
	draw_arc(c, DISC_R, 0, TAU, 64, Color(0.05, 0.045, 0.04, 0.95), 3.0, true)
	draw_arc(c, DISC_R + 1.5, 0, TAU, 64, BRASS, 1.2, true)
	# Hand: right of the circle = backhand, left = forehand.
	var side: float = 1.0 if setup.hand > 0 else -1.0
	var hp := c + Vector2(side * (DISC_R + 2.0), DISC_R * 0.35)
	if emoji != null:
		var fs := 22
		var w := emoji.get_string_size("✋", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(emoji, hp + Vector2(-w * 0.5, fs * 0.35), "✋", HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	else:
		_draw_hand(hp, side)
	_text(c + Vector2(side * (DISC_R + 2.0), DISC_R * 0.35 + 22), "BH" if setup.hand > 0 else "FH", 10, DIM, HORIZONTAL_ALIGNMENT_CENTER)


## A plain little mitten, in case there's no emoji font.
func _draw_hand(at: Vector2, side: float) -> void:
	var col := Color(1.0, 0.8, 0.55)
	draw_rect(Rect2(at + Vector2(-6, -4), Vector2(12, 12)), col)
	for i in 4:
		draw_rect(Rect2(at + Vector2(-6 + i * 3.1, -12), Vector2(2.4, 9)), col)
	draw_rect(Rect2(at + Vector2(-side * 10 - 2, -2), Vector2(5, 3)) if side > 0 else Rect2(at + Vector2(7, -2), Vector2(5, 3)), col)


## Project the disc: a circle in its own plane, seen orthographically from
## behind and CAM_ELEV degrees above. Screen x = right, screen y = down.
func _draw_disc(c: Vector2, r: float) -> void:
	var col: Color = DISC_COLORS[setup.disc_index % DISC_COLORS.size()]
	# Disc frame: forward (away from us) = -Z, right = +X, up = +Y.
	var n := Vector3.UP
	n = n.rotated(Vector3.RIGHT, deg_to_rad(setup.nose * NOSE_GAIN))       # nose up: leading edge rises
	var tilt := -deg_to_rad(setup.visual_tilt())                       # + visual tilt drops the left edge
	n = n.rotated(Vector3.FORWARD, tilt)
	var basis_u := Vector3.RIGHT.rotated(Vector3.FORWARD, tilt)
	var basis_v := n.cross(basis_u).normalized()     # points backward-ish (toward us)
	# Camera: looking forward and down by CAM_ELEV.
	var e := deg_to_rad(CAM_ELEV)
	var cam_up := Vector3(0, cos(e), sin(e))         # screen-up in world
	var to_cam := Vector3(0, sin(e), cos(e))         # from disc toward the camera
	var proj := func(p: Vector3) -> Vector2:
		return c + Vector2(p.x, -p.dot(cam_up)) * r
	var top_seen := n.dot(to_cam) >= 0.0
	var thick := 0.11
	var top := PackedVector2Array()
	var bot := PackedVector2Array()
	var steps := 48
	for i in steps:
		var a := TAU * i / steps
		var p := basis_u * cos(a) + basis_v * sin(a)
		top.append(proj.call(p))
		bot.append(proj.call(p - n * thick))
	# Rim: the band between the two faces (draw the far face, then quads).
	var hidden_face := bot if top_seen else top
	var far_face := top if top_seen else bot
	var rim := col.darkened(0.45)
	draw_colored_polygon(hidden_face, rim)
	for i in steps:
		var j := (i + 1) % steps
		var q := PackedVector2Array([top[i], top[j], bot[j], bot[i]])
		if absf((q[1] - q[0]).cross(q[3] - q[0])) > 0.01:
			draw_colored_polygon(q, rim)
	# Visible face: top bright, underside darker.
	var face := col if top_seen else col.darkened(0.3)
	draw_colored_polygon(far_face, face)
	draw_polyline(far_face + PackedVector2Array([far_face[0]]), col.lightened(0.25), 1.2, true)
	# Inner ring + a dot on the leading edge (away from us) so nose reads.
	var inner := PackedVector2Array()
	var off := Vector3.ZERO if top_seen else -n * thick
	for i in steps + 1:
		var a := TAU * i / steps
		inner.append(proj.call(basis_u * cos(a) * 0.62 + basis_v * sin(a) * 0.62 + off))
	draw_polyline(inner, Color(1, 1, 1, 0.22), 1.0, true)
	var lead: Vector2 = proj.call(-basis_v * 0.85 + off)
	draw_circle(lead, 2.6, Color(1, 1, 1, 0.85))


## Velocity bar and spin bar, side by side, filling from the bottom.
func _draw_bars(at: Vector2) -> void:
	var specs := [
		["speed", "SPD", "%.1f" % setup.speed, "m/s", false],
		["spin", "SPIN", "%d" % int(setup.spin * 60.0 / TAU), "rpm", setup.spin_locked],
	]
	for i in specs.size():
		var s: Array = specs[i]
		var x: float = at.x + i * (BAR_W + 44.0)
		var rect := Rect2(Vector2(x, at.y), Vector2(BAR_W, BAR_H))
		var rng: Array = setup.RANGES[s[0]]
		var f: float = inverse_lerp(rng[0], rng[1], setup.get(s[0]))
		var locked: bool = s[4]
		draw_rect(rect, Color(0.05, 0.045, 0.04, 0.85))
		var fill := Rect2(Vector2(x, at.y + BAR_H * (1.0 - f)), Vector2(BAR_W, BAR_H * f))
		draw_rect(fill, Color(AMBER, 0.28 if locked else 0.85))
		# Ticks every 10% along the right edge.
		for k in range(1, 10):
			var ty := at.y + BAR_H * k / 10.0
			draw_line(Vector2(x + BAR_W - (6 if k == 5 else 3), ty), Vector2(x + BAR_W, ty), Color(INK, 0.35), 1.0)
		# Needle at the current value.
		var ny := at.y + BAR_H * (1.0 - f)
		draw_line(Vector2(x - 3, ny), Vector2(x + BAR_W + 3, ny), Color(1, 0.9, 0.7, 0.45 if locked else 1.0), 2.0)
		if locked:
			_dashed_rect(rect, BRASS)
		else:
			draw_rect(rect, BRASS, false, 1.2)
		var cx := x + BAR_W * 0.5
		_text(Vector2(cx, at.y + BAR_H + 13), s[1], 10, DIM, HORIZONTAL_ALIGNMENT_CENTER)
		_text(Vector2(cx, at.y + BAR_H + 26), s[2], 12, DIM if locked else INK, HORIZONTAL_ALIGNMENT_CENTER)
		if locked:
			_text(Vector2(cx, at.y - 4), "lock X", 9, DIM, HORIZONTAL_ALIGNMENT_CENTER)


func _dashed_rect(r: Rect2, col: Color) -> void:
	var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]
	for i in 4:
		draw_dashed_line(pts[i], pts[i + 1], col, 1.2, 3.0)
