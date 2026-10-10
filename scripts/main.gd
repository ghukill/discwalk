extends Node3D
## Wires the world together: spawns the walker, shows the HUD, sets up disc
## throwing, and lets you press N to roll a brand-new world.

const THROWER_SCRIPT := preload("res://scripts/thrower.gd")
const DIALS_SCRIPT := preload("res://scripts/dials.gd")
const CLOUDS_SCRIPT := preload("res://scripts/clouds.gd")
const LAMPS_SCRIPT := preload("res://scripts/lamps.gd")

@onready var terrain: Node3D = $Terrain
@onready var player: CharacterBody3D = $Player
@onready var hud: Label = $HUD/Help

var thrower: Node
var clouds: Node3D


func _ready() -> void:
	# Children are ready first, so the terrain has already generated.
	clouds = Node3D.new()
	clouds.set_script(CLOUDS_SCRIPT)
	clouds.name = "Clouds"
	add_child(clouds)
	if "--no-clouds" in OS.get_cmdline_user_args():
		clouds.visible = false
	clouds.generate(terrain.world_seed, terrain.world_size, terrain.flora.canopy_top())
	_setup_throwing()
	_place_player()
	_update_hud()


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

	var corner := Label.new()
	corner.name = "ThrowStatus"
	corner.add_theme_color_override("font_color", Color(1, 0.85, 0.7, 0.95))
	corner.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	corner.add_theme_constant_override("shadow_offset_x", 1)
	corner.add_theme_constant_override("shadow_offset_y", 1)
	corner.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	corner.offset_left = -260
	corner.offset_right = -16
	corner.offset_top = 12
	corner.offset_bottom = 36
	corner.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	$HUD.add_child(corner)

	thrower = Node.new()
	thrower.set_script(THROWER_SCRIPT)
	thrower.name = "Thrower"
	thrower.terrain = terrain
	thrower.player = player
	thrower.camera = $Player/Head/Camera3D
	thrower.label = status
	thrower.status_label = corner
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

	# Warm toggle lamps (VIEW, WARP, PATH), top right under the power line.
	var lamps := Control.new()
	lamps.set_script(LAMPS_SCRIPT)
	lamps.name = "Lamps"
	lamps.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	lamps.offset_left = -200
	lamps.offset_right = -16
	lamps.offset_top = 40
	lamps.offset_bottom = 76
	$HUD.add_child(lamps)
	thrower.lamps = lamps
	thrower._update_lamps()

	# Heading + horizon dials, top right under the lamps.
	var dials := Control.new()
	dials.set_script(DIALS_SCRIPT)
	dials.name = "Dials"
	dials.camera = $Player/Head/Camera3D
	dials.offset_source = thrower.panel.launch_offset
	dials.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	dials.offset_left = -200
	dials.offset_right = -16
	dials.offset_top = 84
	dials.offset_bottom = 192
	$HUD.add_child(dials)
	thrower.dials = dials


func _input(event: InputEvent) -> void:
	# Debug: run with `-- --debug-keys` to log every key event to stdout.
	if event is InputEventKey and "--debug-keys" in OS.get_cmdline_user_args():
		var k := event as InputEventKey
		print("KEY pressed=%s keycode=%s physical=%s unicode=%s" % [
			k.pressed, OS.get_keycode_string(k.keycode),
			OS.get_keycode_string(k.physical_keycode), k.unicode])


func _unhandled_input(event: InputEvent) -> void:
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
	hud.text = "discwalk  ·  seed %d\nWASD walk · mouse look · Shift stroll faster · Space hop\nN new world · K clouds · Esc free mouse" % terrain.world_seed
