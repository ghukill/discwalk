extends Node3D
## Aim arc (T): where the disc you have set up would actually go, drawn as a
## dotted line of little cubes out to the spot it would first land.
##
## It is the REAL flight model run forward, not a parabola: the same
## DiscModel.step() the disc itself uses each physics tick, with the same
## gravity, so the arc turns and fades exactly as the throw will. Change the
## disc, the speed, the nose or the hyzer and the arc changes with it.
##
## Why it exists: the crosshair tells you a direction, and a thrown disc is a
## projectile, so it always lands below the thing you sighted on. That is
## correct, and real, and it is also invisible until you have thrown a few
## hundred discs. This shows it. Nothing is clamped or assisted -- if the arc
## says the disc lands short, it lands short.
##
## Cubes, like paths.gd, so it looks like the rest of the game, but cooler in
## colour and smaller, because a prediction should not read as a thrown disc.

const FlightSim := preload("res://scripts/flight_sim.gd")

const SPACING := 0.6                 ## A cube every this many metres of flight.
const CUBE := 0.07                   ## Cube edge (m).
const END_CUBE := 0.22               ## The landing marker is bigger.
const MAX_CUBES := 400
const COLOR_ARC := Color(0.62, 0.86, 1.0)    ## Cool, so it is not a path.
const COLOR_END := Color(1.0, 0.95, 0.72)
const ALPHA := 0.5
const START_GAP := 0.9               ## No cubes right under your chin.

var terrain: Node3D
var thrower: Node

var _mmi: MultiMeshInstance3D
var _mat: StandardMaterial3D
var _shown := false
var _points := PackedVector3Array()  ## The arc as last simulated (tests ask).
var _landed := false                 ## ... and whether it reached the ground.


func _ready() -> void:
	top_level = true
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.vertex_color_is_srgb = true
	_mat.disable_fog = true
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = box
	mm.mesh.surface_set_material(0, _mat)
	mm.instance_count = MAX_CUBES
	mm.visible_instance_count = 0
	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "ArcCubes"
	_mmi.multimesh = mm
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mmi)
	visible = false
	set_process(false)


func showing() -> bool:
	return _shown


## The arc as last simulated, and whether it found the ground (tests).
func points() -> PackedVector3Array:
	return _points


func landed() -> bool:
	return _landed


func set_shown(on: bool) -> void:
	_shown = on
	visible = on
	set_process(on)
	if not on:
		_mmi.multimesh.visible_instance_count = 0
	else:
		_refresh()


func toggle() -> void:
	set_shown(not _shown)


func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	if thrower == null or terrain == null or not _shown:
		return
	_points = simulate()
	_landed = _points.size() > 1 and _on_ground(_points[_points.size() - 1])
	_draw_cubes()


## Run the throw you have set up forward through the real flight model.
##
## The simulation itself is flight_sim.gd, shared with the putt assist, so the
## line you are shown is produced by the same code that decides where the disc
## is aimed. If these were separate the drawing could quietly stop matching.
func simulate() -> PackedVector3Array:
	var setup = thrower.setup
	if setup.disc() == null:
		return PackedVector3Array()
	var cam: Camera3D = thrower.camera
	var look: Vector3 = -cam.global_transform.basis.z
	var view_fwd := Vector3(look.x, 0.0, look.z)
	view_fwd = view_fwd.normalized() if view_fwd.length() > 0.01 else Vector3.FORWARD
	var origin: Vector3 = thrower.release(view_fwd)
	var aim: Array = thrower.aim_from(origin, view_fwd)
	var fwd: Vector3 = aim[0]
	origin = thrower.release(fwd)
	return FlightSim.fly_throw(setup.params(), origin, fwd, aim[1], terrain)


func _on_ground(p: Vector3) -> bool:
	return p.y <= terrain.height_at(p.x, p.z)


## Lay cubes along the arc, one every SPACING metres, with a bigger one where
## it lands. Skips the first START_GAP so the trail does not start in your face.
func _draw_cubes() -> void:
	var mm: MultiMesh = _mmi.multimesh
	if _points.size() < 2:
		mm.visible_instance_count = 0
		return
	var n := 0
	var run := 0.0
	var since := 0.0
	for i in range(1, _points.size()):
		var seg: float = _points[i].distance_to(_points[i - 1])
		run += seg
		since += seg
		if run < START_GAP or since < SPACING:
			continue
		since = 0.0
		if n >= MAX_CUBES - 1:
			break
		_put(mm, n, _points[i], CUBE, COLOR_ARC)
		n += 1
	# The landing spot, brighter and bigger: the number you actually want.
	if _landed and n < MAX_CUBES:
		_put(mm, n, _points[_points.size() - 1], END_CUBE, COLOR_END)
		n += 1
	mm.visible_instance_count = n


func _put(mm: MultiMesh, i: int, at: Vector3, size: float, col: Color) -> void:
	mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), at))
	mm.set_instance_color(i, Color(col, ALPHA))
