extends Node3D
## A disc golf basket: pole, tray, top band and chains.
##
## What touches what:
## - Pole and tray are ordinary collision shapes, so a disc clangs off the
##   post and clatters out of the tray on its own.
## - The chains and the top band are NOT physics bodies. They are too thin:
##   a 0.22 m disc at 25 m/s would tunnel straight through. Instead, each
##   physics tick disc.gd hands its swept path to sweep(), which marches it
##   through the chain volume and drains speed. Same trick flora.gd uses for
##   leaves, and for the same reason.
## - The chains absorb a BOUNDED IMPULSE, not a fixed fraction. That is the
##   whole design: a fraction would take the same share of speed at any
##   speed, so tuning it to stop a putt would also stop a drive and every
##   shot would go in. A momentum budget stops a putt dead and lets a drive
##   punch through, which is what a real basket does.
##
## Sizes are PDGA-ish and in METRES, independent of terrain.block_size. The
## basket is built from smooth primitives rather than voxels on purpose: at a
## 0.25 m block size the 0.635 m tray would be two and a half blocks across,
## which destroys the shape. Manufactured steel reading smooth against a grown
## voxel world is the right look anyway.

signal caught(disc)

const BAND_Y := 1.32            ## Top band height (m).
const TRAY_RIM_Y := 0.66        ## Tray rim height (m).
const TRAY_FLOOR_Y := 0.49      ## Tray floor height (m).
const TARGET_RADIUS := 0.3175   ## Tray / band radius (m): 0.635 m across.
const CHAIN_RADIUS := 0.30      ## Chain curtain radius (m).
const CHAIN_TOP := 1.30         ## Chains hang from just under the band (m).
const CHAIN_BOTTOM := 0.75      ## ...down to just over the tray rim (m).
const POLE_RADIUS := 0.05
const CHAIN_COUNT := 12

const COLOR_STEEL := Color(0.62, 0.64, 0.66)
const COLOR_CHAIN := Color(0.78, 0.80, 0.82)
const COLOR_BAND := Color(0.80, 0.62, 0.22)   ## A warm band, easy to pick out.

var terrain: Node3D
var holed: Node = null          ## The disc parked in the tray, or null.
var beam_on := true             ## Tall finder beam, on the P toggle.

var _beacon: MeshInstance3D


func _ready() -> void:
	_build_visual()
	_build_colliders()


## Stand the basket on the ground under `at` (x/z used, y from the terrain).
func place(at: Vector3) -> void:
	var y := at.y
	if terrain != null:
		y = terrain.height_at(at.x, at.z)
	global_position = Vector3(at.x, y, at.z)


func set_beam(on: bool) -> void:
	beam_on = on
	if _beacon != null:
		_beacon.visible = on


# --- building ----------------------------------------------------------------

func _build_visual() -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = COLOR_STEEL
	steel.metallic = 0.6
	steel.roughness = 0.45

	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = POLE_RADIUS
	pm.bottom_radius = POLE_RADIUS
	pm.height = BAND_Y
	pm.radial_segments = 10
	pm.material = steel
	pole.mesh = pm
	pole.position.y = BAND_Y * 0.5
	add_child(pole)

	var band_mat := StandardMaterial3D.new()
	band_mat.albedo_color = COLOR_BAND
	band_mat.metallic = 0.5
	band_mat.roughness = 0.4
	var band := MeshInstance3D.new()
	var bm := TorusMesh.new()
	bm.inner_radius = TARGET_RADIUS - 0.03
	bm.outer_radius = TARGET_RADIUS
	bm.rings = 18
	bm.material = band_mat
	band.mesh = bm
	band.position.y = BAND_Y
	add_child(band)

	# Tray: a shallow open cylinder. Cheap next to the oaks, and it reads as a
	# cage from any distance you can actually putt from.
	var tray := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = TARGET_RADIUS
	tm.bottom_radius = TARGET_RADIUS * 0.7
	tm.height = TRAY_RIM_Y - TRAY_FLOOR_Y
	tm.radial_segments = 14
	tm.material = steel
	tray.mesh = tm
	tray.position.y = (TRAY_RIM_Y + TRAY_FLOOR_Y) * 0.5
	add_child(tray)

	var chain_mat := StandardMaterial3D.new()
	chain_mat.albedo_color = COLOR_CHAIN
	chain_mat.metallic = 0.7
	chain_mat.roughness = 0.35
	for i in CHAIN_COUNT:
		var a := TAU * i / CHAIN_COUNT
		var bar := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(0.012, CHAIN_TOP - CHAIN_BOTTOM, 0.012)
		cm.material = chain_mat
		bar.mesh = cm
		bar.position = Vector3(cos(a) * CHAIN_RADIUS * 0.85,
			(CHAIN_TOP + CHAIN_BOTTOM) * 0.5, sin(a) * CHAIN_RADIUS * 0.85)
		add_child(bar)

	_beacon = MeshInstance3D.new()
	var beam := BoxMesh.new()
	beam.size = Vector3(0.08, 12.0, 0.08)
	var beam_mat := StandardMaterial3D.new()
	beam_mat.albedo_color = Color(COLOR_BAND, 0.30)
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam.material = beam_mat
	_beacon.mesh = beam
	_beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beacon.position.y = 6.0
	_beacon.visible = beam_on
	add_child(_beacon)


## Pole and tray are real static bodies. Chains and band are swept (see sweep).
func _build_colliders() -> void:
	var pole := StaticBody3D.new()
	pole.name = "Pole"
	var ps := CollisionShape3D.new()
	var pc := CylinderShape3D.new()
	pc.radius = POLE_RADIUS
	pc.height = BAND_Y
	ps.shape = pc
	ps.position.y = BAND_Y * 0.5
	pole.add_child(ps)
	add_child(pole)

	var tray := StaticBody3D.new()
	tray.name = "Tray"
	var ts := CollisionShape3D.new()
	var tc := CylinderShape3D.new()
	tc.radius = TARGET_RADIUS
	tc.height = TRAY_RIM_Y - TRAY_FLOOR_Y
	ts.shape = tc
	ts.position.y = (TRAY_RIM_Y + TRAY_FLOOR_Y) * 0.5
	tray.add_child(ts)
	add_child(tray)
