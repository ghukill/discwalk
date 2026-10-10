extends Control
## Warm toggle lamps for the top-right corner, like the little indicator
## lights on an old aircraft panel: VIEW (V), WARP (Z) and PATH (P).
##
## On, a lamp glows warm amber with a soft halo; off, it sits dark brown in
## its bezel. Lamps don't snap: they warm up and cool down over a fraction
## of a second, like a filament. While WARP is armed for a throw that's
## still moving, its lamp breathes gently.
##
## Drawn with _draw (no textures). Right-aligned to the control's width.

const LAMPS := [["view", "VIEW"], ["warp", "WARP"], ["path", "PATH"]]
const R := 6.0                       ## Lens radius (px).
const PITCH := 50.0                  ## Centre-to-centre spacing (px).
const WARM := Color(1.0, 0.66, 0.26) ## Lit lens.
const COLD := Color(0.24, 0.17, 0.11) ## Unlit lens.
const WARM_UP := 9.0                 ## How fast a lamp heats / cools (1/s).

var pulse_warp := false              ## WARP armed: breathe.

var _want := {"view": 0.0, "warp": 0.0, "path": 1.0}
var _glow := {"view": 0.0, "warp": 0.0, "path": 1.0}
var _t := 0.0
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	custom_minimum_size = Vector2(PITCH * LAMPS.size(), 34)


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
	var n := LAMPS.size()
	for i in n:
		var key: String = LAMPS[i][0]
		var c := Vector2(size.x - PITCH * (n - i - 0.5), R + 4.0)
		var g: float = _glow[key]
		if key == "warp" and pulse_warp and g > 0.5:
			g *= 0.86 + 0.14 * sin(_t * 4.0)
		_draw_lamp(c, g)
		var txt: String = LAMPS[i][1]
		var fs := 9
		var w := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var col := Color(1.0, 0.88, 0.7, 0.55 + 0.4 * g)
		draw_string(_font, c + Vector2(-w * 0.5 + 0.5, R + 15.5), txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.5))
		draw_string(_font, c + Vector2(-w * 0.5, R + 15.0), txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _draw_lamp(c: Vector2, g: float) -> void:
	# Halo: a few soft rings, only when lit.
	if g > 0.01:
		for k in 6:
			var rr := R + 1.5 + k * 2.2
			draw_circle(c, rr, Color(WARM, 0.07 * g * (1.0 - k / 6.0)))
	# Bezel: dark ring with a faint brass edge.
	draw_circle(c, R + 2.2, Color(0.05, 0.045, 0.04, 0.8))
	draw_arc(c, R + 2.2, 0, TAU, 32, Color(0.62, 0.5, 0.32, 0.45), 1.0, true)
	# Lens: cold brown -> warm amber, hotter in the middle when lit.
	draw_circle(c, R, COLD.lerp(WARM, g))
	if g > 0.01:
		draw_circle(c, R * 0.55, Color(1.0, 0.9, 0.65, 0.55 * g))
	# A small glint so an unlit lamp still reads as glass.
	draw_circle(c + Vector2(-R * 0.35, -R * 0.4), R * 0.22, Color(1, 1, 1, 0.18 + 0.2 * g))
