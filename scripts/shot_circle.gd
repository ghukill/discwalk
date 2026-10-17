extends MultiMeshInstance3D
## A faint ring of little flat squares lying on the ground: the shot-circle
## around your lie (thrower.gd), and the big markers on the tee and basket in
## the hole overview (course_round.gd). Blocky, like everything else: squares, not
## a smooth line, each sitting on the voxel top under it.

var terrain: Node3D
var radius := 1.0                   ## Ring radius (m).
var square := 0.08                  ## Edge of one square (m).
var gap := 2.0                      ## Squares every gap x square around the ring.
var color := Color(1.0, 1.0, 1.0, 0.22)
var on_top := false                 ## Drawn through trees (the overview's markers).


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 0.02, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.no_depth_test = on_top
	if on_top:
		mat.render_priority = 1
	box.material = mat
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = box
	visible = false


## Lay the ring round `center` (m) and show it.
func show_at(center: Vector3) -> void:
	var n := maxi(8, int(TAU * radius / (square * gap)))
	multimesh.instance_count = n
	for i in n:
		var a := TAU * i / n
		var x := center.x + cos(a) * radius
		var z := center.z + sin(a) * radius
		var y: float = center.y if terrain == null else terrain.height_at(x, z)
		var basis := Basis(Vector3.UP, -a).scaled(Vector3(square, 1.0, square))
		multimesh.set_instance_transform(i, Transform3D(basis, Vector3(x, y + 0.012, z)))
	visible = true
