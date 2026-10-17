extends Node3D
## A disc golf basket: pole, tray, top band and chains, built from little
## 5 cm voxels. Nine of them stand in every glacial world (baskets.gd).
##
## Hitting one: touch the CHAINS, or end up inside the cage (dropped into the
## tray), and the disc is "struck". It starts the ordinary collect roll home
## (that disc only) and the basket throws a shower of confetti. The top band,
## pole and tray just bounce it off, as a real basket would. No holes, no
## scoring yet.
##
## What touches what:
## - Pole and tray are ordinary collision shapes, so a disc clangs off the
##   post and clatters out of the tray on its own.
## - The chains and the top band are NOT physics bodies. They are too thin:
##   a 0.21 m disc at 25 m/s would tunnel straight through. Instead, each
##   physics tick disc.gd hands its swept path to sweep(), which marches it
##   through the chain volume and drains speed. Same trick flora.gd uses for
##   leaves, and for the same reason.
## - The chains absorb a BOUNDED FORCE, not a fixed fraction (Henry's chain
##   model, feature/henry/baskets). A fraction would take the same share of
##   speed at any speed, so tuning it to stop a putt would also stop a drive.
##   A force limit makes contact time decide: a putt dawdles through over
##   several ticks and is wrung out, a drive is past in one and keeps most of
##   its speed. sweep() still reports a proper "caught" for the day holes and
##   scoring arrive; today any chain touch counts.
##
## Sizes are PDGA-ish and in METRES (from Henry's branch), independent of
## terrain.block_size. The look is voxels like everything else, but at
## VOXEL = 5 cm rather than the ground's 25 cm: at ground size the 0.635 m
## tray would be two and a half blocks across, which destroys the shape.

signal hit(basket, disc, part)       ## A counted hit: part is chains or cage.

const Confetti := preload("res://scripts/confetti.gd")

const BAND_Y := 1.32            ## Top band height (m).
const TRAY_RIM_Y := 0.66        ## Tray rim height (m).
const TRAY_FLOOR_Y := 0.49      ## Tray floor height (m).
const TARGET_RADIUS := 0.3175   ## Tray / band radius (m): 0.635 m across.
const CHAIN_RADIUS := 0.30      ## Chain curtain radius (m).
const CHAIN_TOP := 1.30         ## Chains hang from just under the band (m).
const CHAIN_BOTTOM := 0.75      ## ...down to just over the tray rim (m).
const POLE_RADIUS := 0.05
const CHAIN_COUNT := 12         ## Outer chains (plus half as many inner).

const VOXEL := 0.05             ## Basket voxel edge (m).

## A scoring disc is held in the chains this long before it rolls home
## (thrower.gd), and the basket glows for the same beat.
const HOLD_TIME := 1.0
const GLOW_COLOR := Color(1.0, 0.82, 0.35)

const COLOR_STEEL := Color(0.62, 0.64, 0.66)
const COLOR_STEEL_DARK := Color(0.42, 0.44, 0.47)
const COLOR_CHAIN := Color(0.80, 0.82, 0.84)
const COLOR_CHAIN_DARK := Color(0.60, 0.62, 0.65)
const COLOR_BAND := Color(0.98, 0.78, 0.10)   ## Safety yellow, easy to pick out.

## Fraction of speed the chains keep per metre of curtain. Deliberately
## brutal: the ratio is not what separates a putt from a drive, the force
## limit below is. Left in because it rounds off the very slow arrivals.
@export var chain_drag_per_metre := 0.01
## The hardest the chains can push back, in newtons. THIS is the knob that
## makes putting feel different from driving.
@export var chain_max_force := 28.0
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
## Confetti cubes per hit.
@export var confetti_count := 280
## Glow: each hit adds a level, up to glow_max, held for HOLD_TIME after the
## latest hit, then fading over glow_fade s. Emission + a small gold light
## (so the ground lights up too, for when you can't see the top).
@export var glow_max := 3.0
@export var glow_fade := 0.6
@export var glow_energy := 0.7         ## Emission per level.
@export var glow_light := 1.6          ## Light energy per level.

var terrain: Node3D
var hits := 0                   ## Times struck this world (tests, curiosity).

var _rng := RandomNumberGenerator.new()
var _mat: StandardMaterial3D
var _light: OmniLight3D
var _glow := 0.0                ## Target level (hits stacked).
var _glow_shown := 0.0          ## Smoothed toward _glow.
var _glow_hold := 0.0

static var _mesh: ArrayMesh     ## Built once, shared by every basket.


func _ready() -> void:
	_build_visual()
	_build_colliders()
	_rng.randomize()
	set_process(false)          # only while glowing


## Stand the basket on the ground under `at` (x/z used, y from the terrain).
func place(at: Vector3) -> void:
	var y := at.y
	if terrain != null:
		y = terrain.height_at(at.x, at.z)
	position = Vector3(at.x, y, at.z)


## A disc touched us. disc.gd calls this once per disc; it fires `hit` (the
## thrower starts that disc's collect) and throws the confetti.
func struck(disc: Node, part: String) -> void:
	hits += 1
	hit.emit(self, disc, part)
	celebrate()
	glow()


## Light up: one more level (up to glow_max), held for HOLD_TIME.
func glow() -> void:
	_glow = minf(maxf(_glow, 0.0) + 1.0, glow_max)
	_glow_hold = HOLD_TIME
	if _light == null:
		_light = OmniLight3D.new()
		_light.name = "Glow"
		_light.light_color = GLOW_COLOR
		_light.omni_range = 4.0
		_light.shadow_enabled = false
		_light.position.y = (BAND_Y + TRAY_RIM_Y) * 0.5
		add_child(_light)
	_mat.emission_enabled = true
	_light.visible = true
	set_process(true)


## Current glow level, 0 when dark (tests).
func glow_level() -> float:
	return _glow_shown


func _process(delta: float) -> void:
	if _glow_hold > 0.0:
		_glow_hold -= delta
	else:
		_glow = maxf(_glow - delta * glow_max / glow_fade, 0.0)
	_glow_shown = move_toward(_glow_shown, _glow, delta * 12.0)
	_mat.emission_energy_multiplier = _glow_shown * glow_energy
	_light.light_energy = _glow_shown * glow_light
	if _glow <= 0.0 and _glow_shown <= 0.0:
		_mat.emission_enabled = false
		_light.visible = false
		set_process(false)


## Confetti! Bursts up and out of the cage, flutters down, bounces, fades.
func celebrate() -> Node3D:
	var c := Node3D.new()
	c.set_script(Confetti)
	c.name = "Confetti"
	c.add_to_group("confetti")
	c.terrain = terrain
	c.count = confetti_count
	add_child(c)
	c.burst(global_position + Vector3(0, (BAND_Y + TRAY_RIM_Y) * 0.5, 0))
	return c


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
	# chains have already wrung out on its way down. It's on HORIZONTAL speed:
	# the tray arrests a falling disc by itself; what the chains have to kill
	# is the forward run.
	var end_local := p1 - c
	var end_r := Vector2(end_local.x, end_local.z).length()
	var flat := Vector2(vv.x, vv.z).length()
	if end_r <= CHAIN_RADIUS and end_local.y >= TRAY_FLOOR_Y \
			and end_local.y <= BAND_Y and flat <= catch_speed:
		out.caught = true
		out.hit = "cage"
	out.v = vv
	return out


# --- building ----------------------------------------------------------------

func _build_visual() -> void:
	if _mesh == null:
		_mesh = build_mesh()
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = _mesh
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true      # colours are written in sRGB, like the rest
	m.metallic = 0.2
	m.roughness = 0.6
	m.emission = GLOW_COLOR            # off until a hit (glow())
	mi.material_override = m
	_mat = m
	add_child(mi)


## The basket as voxel cells: Vector3i (in VOXEL units; cell i spans
## [i, i+1) * VOXEL, so the pole's 2 x 2 cells straddle x = z = 0) -> Color.
static func cells() -> Dictionary:
	var out := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var top := int(round(BAND_Y / VOXEL)) + 1               # cap above the band
	# Pole: 2 x 2 cells, ground to just above the band.
	for y in top + 1:
		for x in [-1, 0]:
			for z in [-1, 0]:
				out[Vector3i(x, y, z)] = COLOR_STEEL_DARK
	var span := int(ceil(TARGET_RADIUS / VOXEL)) + 1
	# Tray: a shallow bowl, floor at TRAY_FLOOR_Y flaring out to the rim.
	var y0 := int(floor(TRAY_FLOOR_Y / VOXEL))
	var y1 := int(floor(TRAY_RIM_Y / VOXEL)) - 1
	for y in range(y0, y1 + 1):
		var t := float(y - y0) / maxf(1.0, float(y1 - y0))
		var r_out := lerpf(TARGET_RADIUS * 0.72, TARGET_RADIUS, t)
		for x in range(-span, span):
			for z in range(-span, span):
				var r := _cell_r(x, z)
				if r > r_out:
					continue
				var wall := r > r_out - VOXEL * 1.05
				if y == y0 or wall:
					var col := COLOR_STEEL
					if y == y1 and wall:
						col = COLOR_BAND                     # painted tray rim
					out[Vector3i(x, y, z)] = col
	# Top band: a two-cell-tall yellow ring around BAND_Y.
	var yb := int(floor(BAND_Y / VOXEL))
	for y in [yb - 1, yb]:
		for x in range(-span, span):
			for z in range(-span, span):
				var r := _cell_r(x, z)
				if r <= TARGET_RADIUS and r > TARGET_RADIUS - VOXEL * 1.05:
					out[Vector3i(x, y, z)] = COLOR_BAND
	# Lid spokes: four arms from the pole cap out to the band.
	for a in 4:
		var d := Vector2.from_angle(TAU * a / 4.0 + PI / 4.0)
		var steps := int(TARGET_RADIUS / VOXEL * 2.0)
		for s in steps:
			var p := d * (s * 0.5 * VOXEL)
			out[Vector3i(int(floor(p.x / VOXEL)), top, int(floor(p.y / VOXEL)))] = COLOR_STEEL_DARK
	# Chains: an outer curtain and a sparser inner one, hanging from under the
	# band to just over the tray. Links alternate light and dark.
	var c0 := int(floor(CHAIN_BOTTOM / VOXEL))
	var c1 := yb - 2
	for ring in [[CHAIN_COUNT, CHAIN_RADIUS * 0.85, 0.0], [CHAIN_COUNT / 2, CHAIN_RADIUS * 0.45, 0.5]]:
		var n: int = ring[0]
		for i in n:
			var a: float = TAU * (i + ring[2]) / n
			var x := int(floor(cos(a) * ring[1] / VOXEL))
			var z := int(floor(sin(a) * ring[1] / VOXEL))
			for y in range(c0, c1 + 1):
				var key := Vector3i(x, y, z)
				if not out.has(key):
					out[key] = COLOR_CHAIN if (y + i) % 2 == 0 else COLOR_CHAIN_DARK
	# A little per-voxel shade so the blocks read as blocks.
	for k: Vector3i in out:
		out[k] = (out[k] as Color).darkened(rng.randf() * 0.12)
	return out


## Horizontal distance (in metres) from the pole to the centre of cell (x, z).
static func _cell_r(x: int, z: int) -> float:
	return Vector2((x + 0.5) * VOXEL, (z + 0.5) * VOXEL).length()


## One mesh with only the faces you can see (no face between two voxels).
static func build_mesh() -> ArrayMesh:
	var cs := cells()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dirs := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
		Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
	for k: Vector3i in cs:
		var col: Color = cs[k]
		var centre := (Vector3(k) + Vector3.ONE * 0.5) * VOXEL
		for d: Vector3i in dirs:
			if cs.has(k + d):
				continue
			_face(st, centre, Vector3(d), col)
	return st.commit()


static func _face(st: SurfaceTool, centre: Vector3, n: Vector3, col: Color) -> void:
	var u := Vector3(n.y, n.z, n.x)          # any axis perpendicular to n
	var v := n.cross(u)
	var h := VOXEL * 0.5
	var o := centre + n * h
	var a := o - u * h - v * h
	var b := o + u * h - v * h
	var c := o + u * h + v * h
	var d := o - u * h + v * h
	st.set_color(col)
	st.set_normal(n)
	# Godot treats clockwise triangles (seen from the front) as front faces;
	# same winding rule as flying_disc.gd's _add_box.
	var tri := [a, c, b, a, d, c] if u.cross(v).dot(n) < 0.0 else [a, b, c, a, c, d]
	for p in tri:
		st.add_vertex(p)


## Pole and tray are real static bodies. Chains and band are swept (see sweep).
## Both carry a "basket" meta so you can tell what a disc bumped into; neither
## counts as a hit (bouncing off the bottom of the tray is not a basket).
func _build_colliders() -> void:
	var pole := StaticBody3D.new()
	pole.name = "Pole"
	pole.set_meta("basket", self)
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
	tray.set_meta("basket", self)
	var ts := CollisionShape3D.new()
	var tc := CylinderShape3D.new()
	tc.radius = TARGET_RADIUS
	tc.height = TRAY_RIM_Y - TRAY_FLOOR_Y
	ts.shape = tc
	ts.position.y = (TRAY_RIM_Y + TRAY_FLOOR_Y) * 0.5
	tray.add_child(ts)
	add_child(tray)
