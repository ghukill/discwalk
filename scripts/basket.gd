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

const BEAM_WIDTH := 0.45        ## Finder beam thickness (m). Readable at 120 m.
const BEAM_HEIGHT := 40.0       ## Finder beam height (m): above the tallest oaks.
const BEAM_ALPHA := 0.5
## The beam draws through trees and hills, which is the point of it -- but
## that also means it would paint straight over the basket once you walk up.
## So it fades out as you close, the way flight paths do: gone by NEAR, full
## strength past FAR. By the time you are putting, the target is unobscured.
const BEAM_FADE_NEAR := 9.0
const BEAM_FADE_FAR := 30.0
## A fixed-width beam shrinks with distance, which is backwards: it gets
## thinnest exactly when you most need to find it. Instead the beam widens
## with range to hold a roughly constant size on screen -- about this many
## radians across, whether the basket is 30 m or 120 m away.
const BEAM_APPARENT := 0.018
const BEAM_MAX_SCALE := 4.5

const COLOR_STEEL := Color(0.62, 0.64, 0.66)
const COLOR_CHAIN := Color(0.78, 0.80, 0.82)
const COLOR_BAND := Color(0.80, 0.62, 0.22)   ## A warm band, easy to pick out.

## Fraction of speed the chains keep per metre of curtain. Deliberately
## brutal: the ratio is not what separates a putt from a drive, the force
## limit below is. Left in because it rounds off the very slow arrivals.
@export var chain_drag_per_metre := 0.01
## The hardest the chains can push back, in newtons. THIS is the knob that
## makes putting feel different from driving. A force limit (rather than a
## fixed share of speed, or a budget for the whole pass) means the disc's
## CONTACT TIME decides how much it loses: a putt dawdles through the
## curtain over several physics ticks and gets wrung out, while a drive is
## past in one and keeps nearly everything. That is what a real basket does.
@export var chain_max_force := 80.0
## Random sideways rattle, as a fraction of the speed absorbed.
@export var chain_kick := 0.08
## Share of absorbed speed redirected downward, so a dying disc drops in.
@export var chain_down_bias := 0.35
## Speed kept along the hit axis when the top band is clipped.
@export var band_bounce := 0.35
## Horizontal speed (m/s) at or under which the cage keeps the disc.
@export var catch_speed := 2.5
## March resolution through the chain volume (m).
@export var sweep_step := 0.05

var terrain: Node3D
var holed: Node = null          ## The disc parked in the tray, or null.
var beam_on := true             ## Tall finder beam, on the P toggle.

var _beacon: MeshInstance3D
var _beam_mat: StandardMaterial3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_build_visual()
	_build_colliders()
	_rng.randomize()


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


## Fade the finder beam out as the camera closes, so it stops hiding the
## thing it is pointing at.
func _process(_delta: float) -> void:
	if _beacon == null or _beam_mat == null or not beam_on:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var d := Vector2(cam.global_position.x - global_position.x,
		cam.global_position.z - global_position.z).length()
	var t := clampf((d - BEAM_FADE_NEAR) / (BEAM_FADE_FAR - BEAM_FADE_NEAR), 0.0, 1.0)
	_beam_mat.albedo_color = Color(COLOR_BAND, BEAM_ALPHA * t)
	_beacon.visible = t > 0.01
	var s := clampf(d * BEAM_APPARENT / BEAM_WIDTH, 1.0, BEAM_MAX_SCALE)
	_beacon.scale = Vector3(s, 1.0, s)


# --- chains ------------------------------------------------------------------

## Resolve one physics tick's swept path p0 -> p1 for a disc of `mass` kg,
## travelling over `dt` seconds. Returns
##   {"v": Vector3, "caught": bool, "hit": String}
## where hit is one of "", "chains", "band", "cage". Cheap to call for discs
## nowhere near us, which is almost all of them.
func sweep(p0: Vector3, p1: Vector3, v: Vector3, mass: float, dt: float) -> Dictionary:
	var out := {"v": v, "caught": false, "hit": ""}
	var c := global_position

	# Broad phase: a cylinder a bit bigger than the basket, swept by how far
	# we travel this tick. Discs out in the world cost two length checks.
	var seg := p1 - p0
	var dist := seg.length()
	if dist < 1e-6:
		return out
	var mid := (p0 + p1) * 0.5
	var reach := dist * 0.5 + CHAIN_RADIUS + 0.2
	if Vector2(mid.x - c.x, mid.z - c.z).length_squared() > reach * reach:
		return out
	if maxf(p0.y, p1.y) < c.y + TRAY_FLOOR_Y - 0.2 \
			or minf(p0.y, p1.y) > c.y + BAND_Y + 0.2:
		return out

	var vv := v
	var steps := maxi(1, ceili(dist / sweep_step))
	var step_m := dist / steps
	var chain_metres := 0.0
	var prev_y := p0.y - c.y
	for i in range(1, steps + 1):
		var local := p0 + seg * (float(i) / steps) - c
		var r := Vector2(local.x, local.z).length()
		# Top band: a thin ring. Crossing its plane out near the rim clangs;
		# crossing it further in is a disc dropping into the cage.
		if r <= TARGET_RADIUS + 0.04 and r >= TARGET_RADIUS - 0.10:
			if (prev_y - BAND_Y) * (local.y - BAND_Y) <= 0.0:
				vv.y = -vv.y * band_bounce
				vv.x *= 0.6
				vv.z *= 0.6
				out.v = vv
				out.hit = "band"
				return out
		if r <= CHAIN_RADIUS and local.y >= CHAIN_BOTTOM and local.y <= CHAIN_TOP:
			chain_metres += step_m
		prev_y = local.y

	if chain_metres > 0.0:
		out.hit = "chains"
		var speed := vv.length()
		var dv := minf(speed * (1.0 - pow(chain_drag_per_metre, chain_metres)),
			chain_max_force * dt / maxf(mass, 0.001))
		dv = minf(dv, speed)
		if speed > 1e-5:
			vv -= vv.normalized() * dv
		vv += Vector3(_rng.randf_range(-1.0, 1.0), 0.0,
			_rng.randf_range(-1.0, 1.0)) * dv * chain_kick
		vv.y -= dv * chain_down_bias

	# Catch test. Runs whether or not chains were touched, and reaches down to
	# the tray floor, so a disc lobbed straight in counts and so does one the
	# chains have already wrung out on its way down.
	#
	# The test is on HORIZONTAL speed, not total: the tray is a physical
	# bucket, so it arrests a falling disc by itself. What the chains have to
	# kill is the disc's forward run. Testing total speed would mean the
	# harder the chains knock a disc downward, the less likely it is to count
	# as caught, which is backwards.
	var end_local := p1 - c
	var end_r := Vector2(end_local.x, end_local.z).length()
	var flat := Vector2(vv.x, vv.z).length()
	if end_r <= CHAIN_RADIUS and end_local.y >= TRAY_FLOOR_Y \
			and end_local.y <= BAND_Y and flat <= catch_speed:
		out.caught = true
		out.hit = "cage"
	out.v = vv
	return out


## Park a caught disc in the tray and hold it there.
func capture(disc: Node) -> void:
	if holed == disc or not is_instance_valid(disc):
		return
	holed = disc
	disc.in_basket = true
	disc.set_beam(false)
	disc.global_position = global_position + Vector3(0, TRAY_FLOOR_Y + 0.10, 0)
	disc.linear_velocity = Vector3.ZERO
	disc.angular_velocity = Vector3.ZERO
	disc.freeze = true
	caught.emit(disc)


## Let go of whatever is in the tray (collect, new world, a fresh hole).
func release() -> void:
	if holed != null and is_instance_valid(holed):
		holed.in_basket = false
		holed.freeze = false
	holed = null


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

	# Tray: a rim hoop, a floor, and slats between them. A capped cylinder
	# would read as a closed lid, which is exactly wrong -- the disc has to
	# look like it can drop in.
	var rim := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = TARGET_RADIUS - 0.025
	rm.outer_radius = TARGET_RADIUS
	rm.rings = 16
	rm.material = steel
	rim.mesh = rm
	rim.position.y = TRAY_RIM_Y
	add_child(rim)

	var floor_disc := MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = TARGET_RADIUS * 0.72
	fm.bottom_radius = TARGET_RADIUS * 0.62
	fm.height = 0.03
	fm.radial_segments = 14
	fm.material = steel
	floor_disc.mesh = fm
	floor_disc.position.y = TRAY_FLOOR_Y
	add_child(floor_disc)

	for i in 10:
		var a := TAU * i / 10.0
		var slat := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.018, TRAY_RIM_Y - TRAY_FLOOR_Y, 0.018)
		sm.material = steel
		slat.mesh = sm
		slat.position = Vector3(cos(a) * TARGET_RADIUS * 0.88,
			(TRAY_RIM_Y + TRAY_FLOOR_Y) * 0.5, sin(a) * TARGET_RADIUS * 0.88)
		add_child(slat)

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

	# Finder beam. Holes are sited 60-120 m out, often behind oaks, so this
	# has to read from right across the world: much fatter and taller than
	# the thin bar over a resting disc, and solid enough to show against a
	# bright sky.
	_beacon = MeshInstance3D.new()
	var beam := BoxMesh.new()
	beam.size = Vector3(BEAM_WIDTH, BEAM_HEIGHT, BEAM_WIDTH)
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.albedo_color = Color(COLOR_BAND, BEAM_ALPHA)
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Draw through trees and hills: a beam you lose behind a trunk is no use
	# for finding anything. _process() fades it as you close, so it does not
	# end up painting over the basket itself.
	_beam_mat.no_depth_test = true
	_beam_mat.render_priority = 1
	beam.material = _beam_mat
	_beacon.mesh = beam
	_beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beacon.position.y = BEAM_HEIGHT * 0.5
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
