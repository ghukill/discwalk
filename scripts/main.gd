extends Node3D
## Wires the world together: spawns the walker, shows the HUD, sets up disc
## throwing, and lets you press N to roll a brand-new world.

const THROWER_SCRIPT := preload("res://scripts/thrower.gd")
const CLOUDS_SCRIPT := preload("res://scripts/clouds.gd")

@onready var terrain: Node3D = $Terrain
@onready var player: CharacterBody3D = $Player
@onready var hud: Label = $HUD/Help

var thrower: Node
var clouds: Node3D
var ui_scale := 1.0                  ## On top of the screen's own scale (- / = keys, --ui-scale=).

const UI_SCALE_MIN := 0.6
const UI_SCALE_MAX := 3.0
const UI_REF_HEIGHT := 900.0         ## Window height (px) where the overlay is 1x.


func _ready() -> void:
	# Children are ready first, so the terrain has already generated.
	clouds = Node3D.new()
	clouds.set_script(CLOUDS_SCRIPT)
	clouds.name = "Clouds"
	add_child(clouds)
	if "--no-clouds" in OS.get_cmdline_user_args():
		clouds.visible = false
	clouds.generate(terrain.world_seed, terrain.world_size, terrain.flora.canopy_top())
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ui-scale="):
			ui_scale = clampf(a.get_slice("=", 1).to_float(), UI_SCALE_MIN, UI_SCALE_MAX)
	_apply_ui_scale()
	get_tree().root.size_changed.connect(_apply_ui_scale)
	_setup_throwing()
	_place_player()
	_update_hud()


## All the 2D overlay (HUD, labels, crosshair) grows with the window: 1x up
## to UI_REF_HEIGHT pixels tall, then in proportion (so fullscreen on a
## Retina Mac isn't tiny), times ui_scale (- / = keys, --ui-scale=).
func _apply_ui_scale() -> void:
	var h := float(get_tree().root.size.y)     # window height in real pixels
	get_tree().root.content_scale_factor = maxf(1.0, h / UI_REF_HEIGHT) * ui_scale


func set_ui_scale(v: float) -> void:
	ui_scale = clampf(snappedf(v, 0.05), UI_SCALE_MIN, UI_SCALE_MAX)
	_apply_ui_scale()
	thrower._note("HUD size %d%%" % int(round(ui_scale * 100)), 1.0)


## Crosshair, a throw-status line, and the thrower itself.
func _setup_throwing() -> void:
	var cross := Label.new()
	cross.name = "Crosshair"
	cross.text = "+"
	cross.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	cross.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	cross.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	cross.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cross.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	$HUD.add_child(cross)

	var status := Label.new()
	status.name = "Throw"
	status.add_theme_color_override("font_color", Color(1, 0.85, 0.7, 0.95))
	status.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	status.add_theme_constant_override("shadow_offset_x", 1)
	status.add_theme_constant_override("shadow_offset_y", 1)
	status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	status.offset_left = 16
	status.offset_top = -64
	status.offset_bottom = -12
	status.offset_right = 900
	status.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	$HUD.add_child(status)

	thrower = Node.new()
	thrower.set_script(THROWER_SCRIPT)
	thrower.name = "Thrower"
	thrower.terrain = terrain
	thrower.player = player
	thrower.camera = $Player/Head/Camera3D
	thrower.label = status
	thrower.hud = $HUD
	add_child(thrower)

	# Launch angle readout, small and faint, just under the crosshair.
	var launch := Label.new()
	launch.name = "LaunchAngle"
	launch.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	launch.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	launch.add_theme_font_size_override("font_size", 12)
	launch.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	launch.offset_left = -60
	launch.offset_right = 60
	launch.offset_top = 14
	launch.offset_bottom = 32
	launch.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	$HUD.add_child(launch)
	thrower.launch_label = launch

	# Warp flag, small, top centre; and a soft flash on arrival.
	var flash := ColorRect.new()
	flash.name = "WarpFlash"
	flash.color = Color(0.92, 0.96, 1.0, 0.0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	$HUD.add_child(flash)
	$HUD.move_child(flash, 0)
	thrower.warp_flash = flash
	var warp := Label.new()
	warp.name = "Warp"
	warp.visible = false
	warp.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0))
	warp.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	warp.add_theme_constant_override("shadow_offset_x", 1)
	warp.add_theme_constant_override("shadow_offset_y", 1)
	warp.add_theme_font_size_override("font_size", 15)
	warp.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	warp.offset_left = -220
	warp.offset_right = 220
	warp.offset_top = 10
	warp.offset_bottom = 34
	warp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	$HUD.add_child(warp)
	thrower.warp_label = warp

	thrower._update_lamps()


func _input(event: InputEvent) -> void:
	# Debug: run with `-- --debug-keys` to log every key event to stdout.
	if event is InputEventKey and "--debug-keys" in OS.get_cmdline_user_args():
		var k := event as InputEventKey
		print("KEY pressed=%s keycode=%s physical=%s unicode=%s" % [
			k.pressed, OS.get_keycode_string(k.keycode),
			OS.get_keycode_string(k.physical_keycode), k.unicode])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_bigger") or event.is_action_pressed("ui_smaller"):
		set_ui_scale(ui_scale + (0.1 if event.is_action_pressed("ui_bigger") else -0.1))
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("clouds"):
		clouds.visible = not clouds.visible
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("new_world"):
		terrain.world_seed = randi() % 100000
		thrower.clear()
		terrain.generate()
		clouds.generate(terrain.world_seed, terrain.world_size, terrain.flora.canopy_top())
		_place_player()
		_update_hud()


func _place_player() -> void:
	player.respawn(terrain.spawn_point())


func _update_hud() -> void:
	hud.text = ("discwalk  ·  seed %d\n"
		+ "WASD walk · mouse look/aim · Shift faster · Space hop\n"
		+ "↑↓ nose · ←→ hyzer · Shift+↑↓ speed · Shift+←→ spin · X spin lock\n"
		+ "R flat · H hand · Tab disc · click/Enter throw · right-click cube\n"
		+ "V chase · G goto · L launch · P paths · C collect · U HUD\n"
		+ "N new world · K clouds · -/= HUD size · Esc free mouse") % terrain.world_seed
