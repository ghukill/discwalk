extends Control
## Warm toggle lamps, like the little indicator lights on an old aircraft
## panel: Chase view (V), Goto (G) and Paths (P), stacked in the throw HUD.
##
## On, a lamp glows warm amber with a soft halo; off, it sits dark brown in
## its bezel. Lamps don't snap: they warm up and cool down over a fraction
## of a second, like a filament. While Goto is armed for a throw that's
## still moving, its lamp breathes gently.
##
## Drawn with _draw (no textures).

const LAMPS := [["view", "Chase view", "V"], ["warp", "Goto", "G"], ["path", "Paths", "P"]]
const R := 6.0                       ## Lens radius (px).
const PITCH := 22.0                  ## Row spacing (px).
const FONT_SIZE := 12
const WARM := Color(1.0, 0.66, 0.26) ## Lit lens.
const COLD := Color(0.24, 0.17, 0.11) ## Unlit lens.
const WARM_UP := 9.0                 ## How fast a lamp heats / cools (1/s).

var pulse_warp := false              ## Goto armed: breathe.
var font: Font

var _want := {"view": 0.0, "warp": 0.0, "path": 1.0}
var _glow := {"view": 0.0, "warp": 0.0, "path": 1.0}
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if font == null:
		font = ThemeDB.fallback_font
	custom_minimum_size = Vector2(120, PITCH * LAMPS.size())


func set_lamps(view: bool, warp: bool, path: bool) -> void:
	_want.view = 1.0 if view else 0.0
	_want.warp = 1.0 if warp else 0.0
	_want.path = 1.0 if path else 0.0


## How lit a lamp is right now (0..1); handy for tests.
func glow(lamp: String) -> float:
	return _glow[lamp]


func _process(delta: float) -> void:
	_t += delta
	for k in _glow:
		_glow[k] = move_toward(_glow[k], _want[k], delta * WARM_UP)
	queue_redraw()


func _draw() -> void:
	for i in LAMPS.size():
		var key: String = LAMPS[i][0]
		var c := Vector2(R + 3.0, PITCH * (i + 0.5))
		var g: float = _glow[key]
		if key == "warp" and pulse_warp and g > 0.5:
			g *= 0.86 + 0.14 * sin(_t * 4.0)
		_draw_lamp(c, g)
		var at := c + Vector2(R + 9.0, FONT_SIZE * 0.36)
		var col := Color(1.0, 0.86, 0.64, 0.5 + 0.45 * g)
		draw_string(font, at, LAMPS[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, col)
		var w := font.get_string_size(LAMPS[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		draw_string(font, at + Vector2(w + 6.0, 0), LAMPS[i][2], HORIZONTAL_ALIGNMENT_LEFT, -1,
			FONT_SIZE - 2, Color(0.85, 0.7, 0.5, 0.5))


func _draw_lamp(c: Vector2, g: float) -> void:
	# Halo: a few soft rings, only when lit.
	if g > 0.01:
		for k in 6:
			var rr := R + 1.5 + k * 2.0
			draw_circle(c, rr, Color(WARM, 0.07 * g * (1.0 - k / 6.0)))
	# Bezel: dark ring with a faint brass edge.
	draw_circle(c, R + 2.2, Color(0.05, 0.045, 0.04, 0.9))
	draw_arc(c, R + 2.2, 0, TAU, 32, Color(0.62, 0.5, 0.32, 0.5), 1.0, true)
	# Lens: cold brown -> warm amber, hotter in the middle when lit.
	draw_circle(c, R, COLD.lerp(WARM, g))
	if g > 0.01:
		draw_circle(c, R * 0.55, Color(1.0, 0.9, 0.65, 0.55 * g))
	# A small glint so an unlit lamp still reads as glass.
	draw_circle(c + Vector2(-R * 0.35, -R * 0.4), R * 0.22, Color(1, 1, 1, 0.18 + 0.2 * g))
