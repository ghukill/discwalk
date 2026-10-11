extends Control
## Overhead map (M): a second camera looking straight down at the real
## world, rendered into a SubViewport, with markers for you, the basket and
## your last throw drawn on top.
##
## It renders the actual world rather than a drawn plan, by sharing the main
## World3D with a second orthogonal camera. That costs a render pass, so the
## SubViewport only updates while the map is open.
##
## The camera frames you AND the basket, widening to fit when the hole is
## long, because the thing you most want from a map here is the line between
## the two -- discs fade a long way over 60 m and it is hard to judge from
## the ground.

const SPAN_MIN := 70.0          ## Smallest area shown, top to bottom (m).
const SPAN_PAD := 1.45          ## Fit you and the basket with this much slack.
const CAM_HEIGHT := 600.0       ## Above everything. Orthogonal, so this only
                                ## decides what lies in front of the camera.
const RES := 900                ## SubViewport resolution (square).
const PANEL_FRAC := 0.82        ## Fraction of the shorter screen edge.

const COLOR_FRAME := Color(0.08, 0.07, 0.05, 0.92)
const COLOR_PLAYER := Color(1.0, 0.98, 0.92, 0.95)
const COLOR_BASKET := Color(1.0, 0.78, 0.18, 1.0)
const COLOR_DISC := Color(1.0, 0.42, 0.15, 1.0)
const COLOR_LINE := Color(1.0, 0.86, 0.35, 0.33)

var terrain: Node3D
var player: Node3D
var thrower: Node               ## For the last throw and the hole.

var _vp: SubViewport
var _cam: Camera3D
var _tex: TextureRect
var _frame: Panel
var _overlay: Control
var _label: Label
var _rect := Rect2()            ## Where the map image sits on screen.


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	_vp = SubViewport.new()
	_vp.size = Vector2i(RES, RES)
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	# Share the main world instead of building a scene of our own, so the
	# map shows the real terrain, trees and water with no extra bookkeeping.
	# The World3D has to be handed over explicitly: a SubViewport sitting
	# under a CanvasLayer does not inherit it, and the map comes out as an
	# empty blue square.
	_vp.own_world_3d = false
	add_child(_vp)
	_vp.world_3d = get_viewport().world_3d

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = SPAN_MIN
	_cam.rotation = Vector3(-PI * 0.5, 0.0, 0.0)      # straight down
	_cam.near = 0.5
	_cam.far = CAM_HEIGHT * 2.0
	# Visual layer 1 only: leaves the clouds out (clouds.gd puts them on 2).
	# Otherwise the map is a picture of the weather.
	_cam.cull_mask = 1
	# The camera needs its own environment, because the world's has distance
	# fog (density 0.0028) and from up here the ground is ~585 m away: about
	# 19% of it survives the fog, so the map came out as a flat pale-blue
	# square. No fog, a plain backdrop, and enough ambient to read the
	# shadowed sides of hills.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.11, 0.10)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.78, 0.74)
	env.ambient_light_energy = 0.75
	env.fog_enabled = false
	_cam.environment = env
	_vp.add_child(_cam)
	_cam.current = true

	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_FRAME
	style.border_color = Color(1.0, 0.80, 0.30, 0.75)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(0)
	_frame = Panel.new()
	_frame.add_theme_stylebox_override("panel", style)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)

	_tex = TextureRect.new()
	_tex.texture = _vp.get_texture()
	_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex.stretch_mode = TextureRect.STRETCH_SCALE
	_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tex)

	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	_overlay.draw.connect(_draw_markers)

	_label = Label.new()
	_label.add_theme_color_override("font_color", Color(1.0, 0.90, 0.68, 0.95))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_label.add_theme_font_size_override("font_size", 14)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)


func is_open() -> bool:
	return visible


## Where the map image sits on screen (tests ask).
func panel_rect() -> Rect2:
	return _rect


func toggle() -> void:
	set_open(not visible)


func set_open(on: bool) -> void:
	visible = on
	# Only pay for the extra render pass while the map is actually up.
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on \
		else SubViewport.UPDATE_DISABLED


func _process(_delta: float) -> void:
	if not visible or player == null:
		return
	_layout()
	_aim_camera()
	_overlay.queue_redraw()


## Square panel, centred, sized off the shorter screen edge.
func _layout() -> void:
	var vp := get_viewport_rect().size
	var side := minf(vp.x, vp.y) * PANEL_FRAC
	var at := (vp - Vector2(side, side)) * 0.5
	_rect = Rect2(at, Vector2(side, side))
	_tex.position = at
	_tex.size = _rect.size
	_frame.position = at - Vector2(2, 2)
	_frame.size = _rect.size + Vector2(4, 4)
	# Below the panel: above it would land on the key help, which runs six
	# lines down the top left.
	_label.position = Vector2(at.x, at.y + side + 5)
	_label.size = Vector2(side, 20)


## Frame the player and the basket together, widening for a long hole.
func _aim_camera() -> void:
	var a := player.global_position
	var centre := Vector2(a.x, a.z)
	var span := SPAN_MIN
	var b := _basket()
	if b != null:
		var bp: Vector3 = b.global_position
		centre = (Vector2(a.x, a.z) + Vector2(bp.x, bp.z)) * 0.5
		span = maxf(SPAN_MIN,
			Vector2(a.x - bp.x, a.z - bp.z).length() * SPAN_PAD)
	_cam.size = span
	_cam.global_position = Vector3(centre.x, CAM_HEIGHT, centre.y)
	var hole = _hole()
	if hole != null and b != null:
		_label.text = "Map  ·  hole %.0f m  ·  stroke %d  ·  M closes" % [
			hole.distance_from(player.global_position), hole.strokes]
	else:
		_label.text = "Map  ·  M closes"


func _basket() -> Node3D:
	if terrain != null and terrain.basket != null:
		return terrain.basket
	return null


func _hole() -> Node:
	if thrower != null and thrower.hole != null:
		return thrower.hole
	return null


## World point -> a position inside the map panel on screen.
func map_pos(p: Vector3) -> Vector2:
	var v := _cam.unproject_position(p)
	return _rect.position + v / float(RES) * _rect.size


## The way you are facing, as a unit vector in map space.
##
## Taken by projecting a point a few metres ahead of the player and
## subtracting, rather than converting the yaw by hand. Deriving it from
## rotation.y means picking the right sign for the camera's downward flip,
## and getting that wrong gives a mirrored compass that looks entirely
## plausible until you follow it.
func heading_on_map() -> Vector2:
	if player == null:
		return Vector2.UP
	var pp: Vector3 = player.global_position
	var fwd := -player.global_transform.basis.z
	var flat := Vector3(fwd.x, 0.0, fwd.z)
	flat = flat.normalized() if flat.length() > 0.01 else Vector3.FORWARD
	var d := map_pos(pp + flat * 4.0) - map_pos(pp)
	return d.normalized() if d.length() > 0.001 else Vector2.UP


func _draw_markers() -> void:
	if player == null:
		return
	var b := _basket()
	var pp: Vector3 = player.global_position
	var here := map_pos(pp)

	# The line you are trying to throw down.
	if b != null:
		_overlay.draw_line(here, map_pos(b.global_position), COLOR_LINE, 2.0)

	# Where the last throw came to rest.
	var last = thrower._last if thrower != null else null
	if is_instance_valid(last) and last.resting and not last.in_basket:
		var d := map_pos(last.global_position)
		_overlay.draw_circle(d, 5.0, COLOR_DISC)
		_overlay.draw_arc(d, 5.0, 0.0, TAU, 16, Color(0, 0, 0, 0.6), 1.5)

	if b != null:
		var bm := map_pos(b.global_position)
		_overlay.draw_circle(bm, 7.0, COLOR_BASKET)
		_overlay.draw_arc(bm, 11.0, 0.0, TAU, 24, COLOR_BASKET, 2.0)

	# You, as an arrow pointing the way you are looking.
	var dir := heading_on_map()
	var side := Vector2(-dir.y, dir.x)
	var tri := PackedVector2Array([
		here + dir * 11.0, here - dir * 6.0 + side * 7.0, here - dir * 6.0 - side * 7.0])
	_overlay.draw_colored_polygon(tri, COLOR_PLAYER)
	_overlay.draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]),
		Color(0, 0, 0, 0.7), 1.5)
