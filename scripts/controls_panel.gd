extends PanelContainer
## The controls overlay: ? shows and hides it, and the game menu (Esc, or
## the controller's Menu button) has it under Controls. Keyboard and
## controller side by side; the full write-up is docs/CONTROLS.md, so keep
## the two in step.

const KEY_COLOR := Color(1, 0.85, 0.7)       ## Same warm tone as the status line.
const PAD_COLOR := Color(0.7, 0.85, 1)
const HEAD_COLOR := Color(1, 1, 1, 0.55)

# [section, [[action, keyboard, controller], ...]]. "" = not on that device.
const LEFT := [
	["Walk and look", [
		["walk", "WASD", "left stick"],
		["look / aim", "mouse", "right stick"],
		["faster", "Shift (hold)", "View (toggle run)"],
		["hop", "Space", "A"],
		["crouch / stand (toggle)", "Tab", "X"],
		["menu (frees the mouse)", "Esc", "Menu"],
	]],
	["Set up the throw", [
		["nose up / down", "↑ ↓", "D-pad ↑ ↓"],
		["tilt (hyzer / anhyzer)", "← →", "D-pad ← →"],
		["release speed", "Shift + ↑ ↓", "RB + D-pad ↑ ↓"],
		["spin (when unlocked)", "Shift + ← →", "RB + D-pad ← →"],
		["next / previous disc", "E / Q", "LB + D-pad → ←"],
		["backhand ↔ forehand", "H", "LB (tap)"],
		["reset to flat", "R", "LB + D-pad ↑"],
		["spin lock", "X", "LB + D-pad ↓"],
	]],
]
const RIGHT := [
	["Throw", [
		["throw the disc", "click / Enter", "B"],
		["throw a cube", "right click", "RB + B"],
		["launch yourself", "L", "Y"],
		["collect", "C", "LB + X"],
	]],
	["Toggles", [
		["chase view", "V", "right stick click"],
		["goto", "G", "left stick click"],
		["paths + beams", "P", "Share"],
		["shot circle", "O", "LB + Y"],
		["aim arc (where this throw lands)", "T", ""],
		["basket beam: next / previous", "B / Shift+B", ""],
	]],
	["Course Play", [
		["hole overview", "M", "LB + B"],
		["skip a walk (to the tee, to your disc)", "move / throw", "move / throw"],
	]],
	["World and display", [
		["controls (this)", "?", "menu → Controls"],
		["speed in mph / m/s", "I", ""],
		["hide / show HUD", "U", ""],
		["HUD smaller / bigger", "- / =", ""],
		["clouds", "K", ""],
		["new course", "N", ""],
	]],
]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.06, 0.08, 0.82)
	bg.set_corner_radius_all(8)
	bg.set_content_margin_all(18)
	add_theme_stylebox_override("panel", bg)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	add_child(outer)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 36)
	outer.add_child(cols)
	cols.add_child(_column(LEFT))
	cols.add_child(_column(RIGHT))
	var foot := _label("? (or Esc in the menu) to close  ·  full list: docs/CONTROLS.md", HEAD_COLOR, 12)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(foot)


## One grid per column, so keys and buttons line up across its sections.
func _column(sections: Array) -> Control:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 2)
	_row(grid, ["", "KEYBOARD", "CONTROLLER"], [HEAD_COLOR, HEAD_COLOR, HEAD_COLOR], 12)
	for s in sections:
		for i in 3:
			grid.add_child(_spacer(6))
		_row(grid, [s[0].to_upper(), "", ""], [HEAD_COLOR, HEAD_COLOR, HEAD_COLOR], 12)
		for r in s[1]:
			_row(grid, [r[0], r[1] if r[1] != "" else "—", r[2] if r[2] != "" else "—"],
				[Color(1, 1, 1, 0.9), KEY_COLOR if r[1] != "" else HEAD_COLOR,
				PAD_COLOR if r[2] != "" else HEAD_COLOR], 14)
	return grid


func _row(grid: GridContainer, texts: Array, colors: Array, size: int) -> void:
	for i in 3:
		grid.add_child(_label(texts[i], colors[i], size))


func _label(text: String, color: Color, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	return l


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
