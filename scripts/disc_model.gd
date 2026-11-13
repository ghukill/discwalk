extends RefCounted
## Aerodynamics of one disc model: lift, drag and pitching moment as functions
## of angle of attack, plus the gyroscopic roll that turns the pitching moment
## into turn and fade. The why of every equation and number: docs/PHYSICS.md.
##
## The equations are Hummel's (2003), written in plain vector form. The disc
## tables live in res://data/discs/<source>/<id>.json; ours are built from
## Kamaruddin's (2011) wind-tunnel data by tools/discs/build_tables.py.
##
## Conventions (Godot world axes, Y up):
##   normal  unit vector out of the disc's top face
##   alpha   angle of attack (deg): positive when the air hits the underside
##   omega   spin rate (rad/s), always >= 0
##   hand    +1 = right-hand backhand (clockwise seen from above),
##           -1 = right-hand forehand (mirror image: turn and fade swap sides)

const AIR_DENSITY := 1.225           ## kg/m^3
const DATA_DIR := "res://data/discs"

## Rate damping and spin down. The FORM is Hummel's (2003, eq. 2.8): three
## moments that grow with the disc's own turning rates,
##   roll   R = C_lp p^      q A d     (resists the roll rate p)
##   pitch  M = (C_M(a) + C_mq q^) q A d   (C_M(a) comes from the disc table)
##   spin   N = C_nr r^      q A d     (spin down)
## but with the rates NON-DIMENSIONAL, as in any flight-dynamics text:
## p^ = p d / 2V and likewise for q and r. That matters. A rate derivative
## measures how much the turning changes the local airflow angle (p y / V), so
## its moment grows with V, not with V^2. Hummel's published numbers are
## per rad/s, fitted to a 27 cm Frisbee at 13.5 m/s; used as they stand at
## 24-36 m/s on a 21 cm golf disc they come out about ten times too strong
## (docs/PHYSICS.md, "Damping").
##
## The values: strip theory gives C_lp = C_mq = -C_La / 8 for a round wing
## (C_La = lift slope per radian, measured for each disc: about -0.3), and
## build_tables.py writes that into each disc JSON ("Clp", "Cmq"). Spin down
## is Hummel's long-flight fit made non-dimensional at his flight speed
## ("Cnr"); a skin-friction estimate lands on the same number.
##
## Hummel's 4th rate term, C_Rr (roll moment from spin), is left out: his
## flight-fitted value and Potts & Crowther's wind-tunnel table disagree even
## in sign (thesis Table 3-2), and both are for a Frisbee.
const SPIN_DOWN := -3.4e-3           ## C_nr, per (r d / 2V).
const STRIP_DAMPING := 1.0 / 8.0     ## C_lp = C_mq = -C_La x this.

var id := ""
var label := ""
var source := ""
var license := ""
var diameter := 0.211                ## m
var area := 0.0                      ## m^2
var mass := 0.175                    ## kg
var i_xy := 0.0                      ## moment of inertia across the disc (kg m^2)
var i_z := 0.0                       ## moment of inertia about the spin axis (kg m^2)
var order := 0                       ## Sort key (putter -> drivers).
var kind := ""                       ## putter / midrange / distance driver ...
var stability := ""                  ## straight / stable / overstable / understable ...
var inspired_by := ""                ## The real disc whose data this is.
var c_mq := -0.3                     ## Pitch damping, per (q d / 2V).
var c_lp := -0.3                     ## Roll damping, per (p d / 2V).
var c_nr := SPIN_DOWN                ## Spin down, per (r d / 2V).

var _alpha := PackedFloat32Array()   ## deg, ascending, covers -90..90
var _cl := PackedFloat32Array()
var _cd := PackedFloat32Array()
var _cm := PackedFloat32Array()


## Loads one disc from JSON: {id, label, source, license, diameter, J_xy, J_z,
## alpha[], Cl[], Cd[], Cm[]} plus optional rate derivatives {Clp, Cmq, Cnr}
## (non-dimensional; without them the damping comes from the lift slope).
## J_* are inertia per unit mass (m^2). Optional: order, kind, stability,
## inspired_by.
static func load_json(path: String, disc_mass := 0.175) -> RefCounted:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var m = load("res://scripts/disc_model.gd").new()
	m.id = d.get("id", path.get_file().get_basename())
	m.label = d.get("label", m.id)
	m.source = d.get("source", "")
	m.license = d.get("license", "")
	m.diameter = d.diameter
	m.area = PI * m.diameter * m.diameter / 4.0
	m.mass = disc_mass
	m.i_xy = disc_mass * float(d.J_xy)
	m.i_z = disc_mass * float(d.J_z)
	m.order = int(d.get("order", 0))
	m.kind = d.get("kind", "")
	m.stability = d.get("stability", "")
	m.inspired_by = d.get("inspired_by", "")
	m._alpha = PackedFloat32Array(d.alpha)
	m._cl = PackedFloat32Array(d.Cl)
	m._cd = PackedFloat32Array(d.Cd)
	m._cm = PackedFloat32Array(d.Cm)
	assert(m._alpha.size() == m._cl.size() and m._cl.size() == m._cd.size()
		and m._cd.size() == m._cm.size(), "disc %s: table lengths differ" % path)
	var strip: float = -m.lift_slope() * STRIP_DAMPING
	m.c_lp = float(d.get("Clp", strip))
	m.c_mq = float(d.get("Cmq", strip))
	m.c_nr = float(d.get("Cnr", SPIN_DOWN))
	return m


## Lift slope C_La (per radian) over 0..5 deg, where every disc's lift is a
## straight line.
func lift_slope() -> float:
	return (coeffs(5.0).x - coeffs(0.0).x) / deg_to_rad(5.0)


## Every disc under res://data/discs/*/*.json, sorted by order, then id.
static func load_all() -> Array:
	var out: Array = []
	for sub in DirAccess.get_directories_at(DATA_DIR):
		var dir := DATA_DIR.path_join(sub)
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".json"):
				out.append(load_json(dir.path_join(f)))
	out.sort_custom(func(a, b) -> bool: return a.id < b.id if a.order == b.order else a.order < b.order)
	return out


## Spin from release speed: about 5.2 rad/s per m/s, a linear fit to measured
## throws (from Giljarhus et al. 2022 / shotshaper's notes; see docs/PHYSICS.md).
## A 24 m/s drive spins ~125 rad/s (~1200 rpm).
static func auto_spin(speed: float) -> float:
	return 5.2 * speed


## Initial velocity and disc normal for a throw.
##   fwd    flat aim direction (unit, y = 0)
##   pitch  launch angle above horizontal (deg)
##   nose   extra nose-up of the disc relative to its flight path (deg)
##   roll   hyzer (+) / anhyzer (-) (deg)
## Returns [velocity: Vector3, normal: Vector3].
static func launch_state(fwd: Vector3, speed: float, pitch: float, nose: float,
		roll: float, hand := 1.0) -> Array:
	var p := deg_to_rad(pitch)
	var right := fwd.cross(Vector3.UP).normalized()
	var vel := (fwd * cos(p) + Vector3.UP * sin(p)) * speed
	# Tip the disc back with the launch angle, plus any extra nose-up ...
	var n := Vector3.UP.rotated(right, p + deg_to_rad(nose))
	# ... then bank it about the flight path. Hyzer drops the side the disc
	# will fade toward: the left for a RH backhand, the right for a forehand.
	n = n.rotated(vel.normalized(), -deg_to_rad(roll) * hand)
	return [vel, n.normalized()]


## Lift, drag and moment coefficients at angle of attack `a` (deg). Tables
## cover -90..90; beyond that a flat disc is (nearly) symmetric, so flying
## upside-down mirrors the table: C(a) = -C(+-180 - a) for lift and moment,
## +C for drag.
func coeffs(a: float) -> Vector3:
	a = wrapf(a, -180.0, 180.0)
	var s := 1.0
	if a > 90.0:
		a = 180.0 - a
		s = -1.0
	elif a < -90.0:
		a = -180.0 - a
		s = -1.0
	var i := _alpha.bsearch(a)                  # first index with _alpha[i] >= a
	i = clampi(i, 1, _alpha.size() - 1)
	var t := clampf((a - _alpha[i - 1]) / (_alpha[i] - _alpha[i - 1]), 0.0, 1.0)
	return Vector3(
		s * lerpf(_cl[i - 1], _cl[i], t),
		lerpf(_cd[i - 1], _cd[i], t),
		s * lerpf(_cm[i - 1], _cm[i], t))


## One tick of flight.
##   v      velocity relative to the AIR (subtract wind first), m/s
##   n      disc normal
##   omega  spin (rad/s, >= 0)
## Returns [aero_accel: Vector3 (no gravity), new_normal: Vector3, alpha_deg: float,
##          new_omega: float].
##
## Lift acts perpendicular to the airflow, in the plane of the airflow and the
## normal; drag acts against the airflow. The moments are not applied as a
## torque: a fast-spinning disc precesses instead, and that slow roll is turn
## and fade (see _attitude).
func step(v: Vector3, n: Vector3, omega: float, hand: float, dt: float) -> Array:
	var speed := v.length()
	if speed < 0.01:
		return [Vector3.ZERO, n, 0.0, omega]
	var vh := v / speed
	var vn := v.dot(n)
	var vp := v - n * vn                        # airflow along the disc plane
	var vpl := vp.length()
	var alpha := rad_to_deg(atan2(-vn, vpl))
	var c := coeffs(alpha)
	var q := 0.5 * AIR_DENSITY * speed * speed
	var lift_dir := n - vh * n.dot(vh)
	lift_dir = lift_dir.normalized() if lift_dir.length() > 1e-6 else Vector3.ZERO
	var force := (lift_dir * c.x - vh * c.y) * q * area
	var new_n := n
	var qad := q * area * diameter
	var rate := diameter / (2.0 * speed)        # makes a rate non-dimensional: p d / 2V
	if vpl > 1e-4 and omega > 0.1:
		new_n = _attitude(n, vp / vpl, c.z, qad, -hand * omega, rate, dt)
	# Spin down: I_z dr/dt = C_nr (r d / 2V) qAd, so spin decays exponentially,
	# a little faster at speed (it goes as V): ~3 %/s at 24 m/s.
	var new_omega := omega * exp(c_nr * rate * qad * dt / i_z)
	return [force / mass, new_n, alpha, new_omega]


## Hummel (2003) attitude, quasi-steady. His Euler equations (thesis Appendix B)
## for a disc with angular momentum H = I_z r n and a cross-axis rate w (x̂ = roll
## component p, ŷ = pitch component q) are
##   I_xy dw/dt + I_z r (w x n) = M_perp.
## The I_xy dw/dt part is wobble (nutation): it spins around at ~2r, about
## 200 rad/s, and the damping kills it in a fraction of a second. Dropping it
## leaves the steady precession, M_perp = I_z r (w x n), with w x n = p ŷ - q x̂:
##   x̂ (roll):   C_lp p k qAd           = -I_z r q
##   ŷ (pitch):  (C_M + C_mq q k) qAd   =  I_z r p        (k = d / 2V)
## Two linear equations for p and q, solved exactly below. Without damping
## this is p = M / (I_z r): a gyroscope's precession. Roll damping adds a small
## pitch rate q (the nose drifts a little as the disc turns/fades); pitch
## damping slows the roll a little. Both are a few percent of the roll rate.
## Matches a full 6-DOF integration (wobble and all) to a few percent; see
## tools/discs/hummel_reference.py.
##   x     unit airflow direction in the disc plane (Hummel's roll axis)
##   cm    pitching-moment coefficient at this angle of attack
##   r     signed spin about n (rad/s): -omega for a RH backhand (clockwise)
##   rate  d / 2V: turns a rate in rad/s into its non-dimensional form
func _attitude(n: Vector3, x: Vector3, cm: float, qad: float, r: float,
		rate: float, dt: float) -> Vector3:
	var y := x.cross(n)                         # Hummel's pitch axis (to the right)
	var h := i_z * r
	var roll_damp := c_lp * rate * qad          # N m per rad/s of roll rate
	var pitch_damp := c_mq * rate * qad
	var q_rate := -(roll_damp * cm * qad) / (h * h + roll_damp * pitch_damp)
	var p_rate := (cm * qad + pitch_damp * q_rate) / h
	var w := x * p_rate + y * q_rate
	var wl := w.length()
	if wl < 1e-9:
		return n
	return n.rotated(w / wl, wl * dt).normalized()
