extends Node3D
## A 3 ft square on the ground marking where you throw from next: directly
## behind your disc, on the far side from the basket, so you stand in it and
## play down the line at the target.
##
## Informational only. Nothing enforces it and nothing is penalised for
## standing outside it.
##
## The square is built to FOLLOW the ground rather than lie in one flat
## plane, because the till rolls enough that a single quad would sink into
## a rise or hang in the air over a dip. It samples the terrain's heights
## and steps with them. It only reads: the terrain is never modified.

const VoxelMesh := preload("res://scripts/voxel_mesh.gd")

const SIDE := 0.914             ## 3 ft, in metres.
const LIFT := 0.05              ## Hover this far over the ground (m), so the
                                ## square does not z-fight with the surface.
const GRID := 8                 ## Cells per side. Sets how thin the border is.
const COLOR_FILL := Color(1.0, 0.86, 0.35, 0.10)
const COLOR_EDGE := Color(1.0, 0.78, 0.18, 0.75)

var terrain: Node3D
var enabled := true             ## Follows the P toggle with the other markers.

var _mesh: MeshInstance3D
var _placed := false


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh = MeshInstance3D.new()
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.material_override = mat
	_mesh.top_level = true          # built in world space, not relative to us
	add_child(_mesh)
	visible = false


## Mark the throwing box behind `lie`, pointing away from `toward` (the
## basket). Pass the throw's origin as `toward` when there is no basket.
func place(lie: Vector3, toward: Vector3) -> void:
	var away := Vector3(lie.x - toward.x, 0.0, lie.z - toward.z)
	if away.length() < 0.2 or terrain == null:
		clear()                     # on top of the target: nothing useful to mark
		return
	away = away.normalized()
	_build(lie + away * (SIDE * 0.5), away)
	_placed = true
	visible = enabled


func clear() -> void:
	_placed = false
	visible = false


func set_shown(on: bool) -> void:
	enabled = on
	visible = on and _placed


## True when the box is on screen (tests ask).
func showing() -> bool:
	return visible


func _build(centre: Vector3, away: Vector3) -> void:
	var right := Vector3(-away.z, 0.0, away.x)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	# Fixed grid, deliberately finer than the terrain. Tying the cell size
	# to block_size made the border -- one cell wide -- a quarter of the
	# square at 0.25 m blocks, so it read as a solid pad instead of an
	# outline. Oversampling costs 64 tiny quads and keeps the border thin
	# at every block size, while still stepping with the ground.
	var n := GRID
	var step := SIDE / n
	for i in n:
		for j in n:
			var u := (i - n * 0.5) * step
			var v := (j - n * 0.5) * step
			var o := centre + right * u + away * v
			# Sample at the cell's middle: a corner can sit on the far side
			# of a block edge and lift the whole cell a step too high.
			var mid := o + right * (step * 0.5) + away * (step * 0.5)
			o.y = terrain.height_at(mid.x, mid.z) + LIFT
			var edge: bool = i == 0 or j == 0 or i == n - 1 or j == n - 1
			VoxelMesh.add_quad(verts, normals, colors, o, right * step,
				away * step, Vector3.UP, COLOR_EDGE if edge else COLOR_FILL)
	_mesh.mesh = VoxelMesh.build_mesh(verts, normals, colors)
