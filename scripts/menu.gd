extends CanvasLayer
## The game menu: on launch (the title screen), and Esc / controller Menu in
## game. The world is already built behind it, and the game is paused while
## it's open.
##
##   1  Free Play      walk around and sling discs
##   2  Course Play    play a round of disc golf
##      Controls       the controls overlay (controls_panel.gd)
##      Quit
##
## In game there's also Resume (Esc again does the same). Picking a mode
## starts it over; if that would throw away a round in progress, the button
## asks once more first. Mouse, keys (arrows, Enter, 1, 2) and controller
## (D-pad, A, B) all work.

const ControlsPanel := preload("res://scripts/controls_panel.gd")

signal chosen(mode)                  ## "free" or "course"
signal resumed

const INK := Color(1.0, 0.9, 0.74, 0.95)
const DIM := Color(1.0, 0.88, 0.7, 0.5)
const AMBER := Color(1.0, 0.66, 0.26)
const BRASS := Color(0.66, 0.53, 0.33, 0.7)

var in_game := false                 ## false = title screen (no Resume).
var round_on := false                ## A round is in progress: confirm before dropping it.
var has_holes := true                ## Course Play needs a course with holes.

var _panel: PanelContainer
var _controls: PanelContainer
var _resume: Button
var _free: Button
var _course: Button
var _course_note: Label
var _confirm := ""                   ## Mode waiting for a second press.


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.03, 0.04, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	_panel = PanelContainer.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.09, 0.075, 0.06, 0.92)
	bg.border_color = BRASS
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(12)
	bg.set_content_margin_all(28)
	bg.shadow_color = Color(0, 0, 0, 0.35)
	bg.shadow_size = 10
	_panel.add_theme_stylebox_override("panel", bg)
	add_child(_panel)
	_centre(_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.custom_minimum_size = Vector2(380, 0)
	_panel.add_child(col)
	col.add_child(_label("discwalk", 44, AMBER))
	col.add_child(_label("walk the hills, sling some discs", 14, DIM))
	col.add_child(_gap(10))
	_resume = _button("Resume", "", col)
	_resume.pressed.connect(_on_resume)
	_free = _button("1   Free Play", "walk around and sling discs", col)
	_free.pressed.connect(_pick.bind("free"))
	_course = _button("2   Course Play", "play a round of disc golf", col)
	_course.pressed.connect(_pick.bind("course"))
	_course_note = _label("", 12, DIM)
	col.add_child(_course_note)
	var ctl := _button("Controls", "", col)
	ctl.pressed.connect(_show_controls.bind(true))
	var quit := _button("Quit", "", col)
	quit.pressed.connect(func(): get_tree().quit())

	_controls = ControlsPanel.new()
	_controls.visible = false
	add_child(_controls)
	_centre(_controls)
	visible = false


func _centre(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BOTH


func open(game: bool, round_in_progress: bool, holes: bool) -> void:
	in_game = game
	round_on = round_in_progress
	has_holes = holes
	_confirm = ""
	_resume.visible = in_game
	_course.disabled = not has_holes
	_course_note.text = "" if has_holes else "(this course has no holes)"
	_course_note.visible = not has_holes
	_relabel()
	_show_controls(false)
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	(_resume if in_game else _free).grab_focus()


func close() -> void:
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var back := event.is_action_pressed("menu") or event.is_action_pressed("ui_cancel")
	if back and _controls.visible:
		_show_controls(false)
	elif back and in_game:
		_on_resume()
	elif event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_1 or event.physical_keycode == KEY_1):
		_pick("free")
	elif event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_2 or event.physical_keycode == KEY_2) and has_holes:
		_pick("course")
	else:
		return
	get_viewport().set_input_as_handled()


func _on_resume() -> void:
	close()
	resumed.emit()


func _pick(mode: String) -> void:
	if round_on and _confirm != mode:
		_confirm = mode
		_relabel()
		return
	close()
	chosen.emit(mode)


func _relabel() -> void:
	_free.text = "1   Free Play"
	_course.text = "2   Course Play"
	if _confirm == "free":
		_free.text = "Drop this round?  Press again"
	elif _confirm == "course":
		_course.text = "Start the round over?  Press again"


func _show_controls(on: bool) -> void:
	_controls.visible = on
	_panel.visible = not on


func _button(text: String, sub: String, parent: Control) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 44)
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_focus_color", Color(1, 1, 1))
	b.add_theme_color_override("font_disabled_color", Color(INK, 0.35))
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var box := StyleBoxFlat.new()
		box.set_corner_radius_all(6)
		box.content_margin_left = 16
		box.content_margin_right = 16
		box.bg_color = Color(0.16, 0.13, 0.1, 0.9)
		if st == "hover" or st == "focus":
			box.bg_color = Color(0.32, 0.22, 0.12, 0.95)
			box.border_color = AMBER
			box.set_border_width_all(1)
		elif st == "pressed":
			box.bg_color = Color(0.45, 0.3, 0.14, 0.95)
		elif st == "disabled":
			box.bg_color = Color(0.12, 0.1, 0.08, 0.6)
		b.add_theme_stylebox_override(st, box)
	parent.add_child(b)
	if sub != "":
		var l := _label(sub, 12, DIM)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		var m := MarginContainer.new()
		m.add_theme_constant_override("margin_left", 16)
		m.add_theme_constant_override("margin_top", -6)
		m.add_child(l)
		parent.add_child(m)
	return b


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
