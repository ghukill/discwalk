extends PanelContainer
## Lower-right throw panel (T to show/hide). Plain sliders for the release:
## disc, speed, launch angle, nose angle, hyzer/anhyzer and spin, plus a
## Throw button. You aim by looking; the panel decides everything else.
## Opening it frees the mouse; closing it grabs the mouse again.

signal throw_requested(params: Dictionary)

var discs: Array = []                ## DiscModel list (scripts/disc_model.gd)

var _disc: OptionButton
var _sliders := {}                   ## name -> HSlider
var _values := {}                    ## name -> Label
var _auto_spin: CheckBox

const ROWS := [
	# name, label, min, max, step, default, unit
	["speed", "Speed", 5.0, 35.0, 0.5, 24.0, "m/s"],
	["pitch", "Launch angle", -10.0, 45.0, 0.5, 12.0, "°"],
	["nose", "Nose", -10.0, 10.0, 0.5, 0.0, "°"],
	["roll", "Hyzer / anhyzer", -40.0, 40.0, 1.0, 10.0, "°"],
	["spin", "Spin", 20.0, 200.0, 1.0, 125.0, "rad/s"],
]


func _ready() -> void:
	visible = false
	add_to_group("mouse_ui")
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.09, 0.08, 0.78)
	bg.set_corner_radius_all(6)
	bg.set_content_margin_all(12)
	add_theme_stylebox_override("panel", bg)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var title := Label.new()
	title.text = "Throw a disc  (RH backhand · aim with your view · T to close)"
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.7))
	box.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	box.add_child(grid)

	grid.add_child(_label("Disc"))
	_disc = OptionButton.new()
	_disc.focus_mode = Control.FOCUS_NONE
	for i in discs.size():
		var d = discs[i]
		_disc.add_item("%s  (%s)" % [d.label, d.id], i)
	for i in discs.size():
		if discs[i].id == "dd2":                  # a distance driver to start
			_disc.selected = i
	_disc.custom_minimum_size.x = 260
	grid.add_child(_disc)
	grid.add_child(Control.new())

	for row in ROWS:
		var name: String = row[0]
		grid.add_child(_label(row[1]))
		var s := HSlider.new()
		s.min_value = row[2]
		s.max_value = row[3]
		s.step = row[4]
		s.value = row[5]
		s.custom_minimum_size = Vector2(260, 20)
		s.focus_mode = Control.FOCUS_NONE         # keys stay with the walker
		s.value_changed.connect(func(_v: float) -> void: _refresh())
		grid.add_child(s)
		_sliders[name] = s
		var v := _label("")
		v.custom_minimum_size.x = 90
		grid.add_child(v)
		_values[name] = v

	_auto_spin = CheckBox.new()
	_auto_spin.text = "auto spin (from speed)"
	_auto_spin.button_pressed = true
	_auto_spin.focus_mode = Control.FOCUS_NONE
	_auto_spin.toggled.connect(func(_on: bool) -> void: _refresh())
	box.add_child(_auto_spin)

	var go := Button.new()
	go.text = "Throw"
	go.focus_mode = Control.FOCUS_NONE
	go.custom_minimum_size.y = 34
	go.pressed.connect(func() -> void: throw_requested.emit(params()))
	box.add_child(go)
	_refresh()


func toggle() -> void:
	visible = not visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED


## Current settings: {disc, speed, pitch, nose, roll, spin}.
func params() -> Dictionary:
	var p := {"disc": discs[_disc.selected] if not discs.is_empty() else null}
	for name in _sliders:
		p[name] = _sliders[name].value
	if _auto_spin.button_pressed:
		p.spin = load("res://scripts/disc_model.gd").auto_spin(p.speed)
	return p


func _refresh() -> void:
	var auto := _auto_spin != null and _auto_spin.button_pressed
	if auto:
		_sliders.spin.set_value_no_signal(load("res://scripts/disc_model.gd").auto_spin(_sliders.speed.value))
	_sliders.spin.editable = not auto
	for row in ROWS:
		var name: String = row[0]
		var v: float = _sliders[name].value
		var txt := "%.1f %s" % [v, row[6]] if row[4] < 1.0 else "%d %s" % [int(v), row[6]]
		if name == "roll":
			txt = "%d° %s" % [absi(int(v)), "hyzer" if v > 0 else ("anhyzer" if v < 0 else "flat")]
		elif name == "spin":
			txt = "%d rpm" % int(v * 60.0 / TAU)
		_values[name].text = txt


static func _label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_color_override("font_color", Color(0.95, 0.95, 0.92))
	return l
