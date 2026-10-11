extends RefCounted
## Aerodynamics of one disc model: lift, drag and pitching moment as functions
## of angle of attack, plus the gyroscopic roll that turns the pitching moment
## into turn and fade. See docs/DISC-FLIGHT-PLAN.md.
##
## The model is written from the published equations (Hummel 2003; Crowther &
## Potts; shotshaper's write-up) in plain vector form; no simulator code is
## copied. Only the COEFFICIENT TABLES come from elsewhere, and they live in
## data files under res://data/discs/<source>/<id>.json, so swapping in our own
## tables later is just new JSON (see data/discs/README.md).
##
## Conventions (Godot world axes, Y up):
##   normal  unit vector out of the disc's top face
##   alpha   angle of attack (deg): positive when the air hits the underside
##   omega   spin rate (rad/s), always >= 0
##   hand    +1 = right-hand backhand (clockwise seen from above),
##           -1 = right-hand forehand (mirror image: turn and fade swap sides)

const AIR_DENSITY := 1.225           ## kg/m^3
const DATA_DIR := "res://data/discs"

## Spin-damping coefficient C_zd (Hummel 2003 form: M_z = q S d (d/2V) C_zd w).
## Negative = spin bleeds off in flight. 0 = constant spin (the shotshaper
## behaviour, which the reference flights in tools/flight_test.gd assume).
## PLACEHOLDER value, tuned by feel: not yet taken from Hummel's thesis. At
## 20 m/s it gives ~10%/s spin loss (about 0.1 / s).
const C_ZD_HUMMEL := -0.014

var id := ""
var label := ""
var source := ""
var license := ""
var diameter := 0.211                ## m
var area := 0.0                      ## m^2
var mass := 0.175                    ## kg
var i_xy := 0.0                      ## moment of inertia across the disc (kg m^2)
var i_z := 0.0                       ## moment of inertia about the spin axis (kg m^2)
var c_zd := 0.0                      ## spin-damping coefficient (see C_ZD_HUMMEL)

var _alpha := PackedFloat32Array()   ## deg, ascending, covers -90..90
var _cl := PackedFloat32Array()
var _cd := PackedFloat32Array()
var _cm := PackedFloat32Array()


## Loads one disc from JSON: {id, label, source, license, diameter, J_xy, J_z,
## alpha[], Cl[], Cd[], Cm[]}. J_* are inertia per unit mass (m^2).
static func load_json(path: String, disc_mass := 0.175, c_zd_default := 0.0) -> RefCounted:
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
	m.c_zd = float(d.get("C_zd", c_zd_default))
	m._alpha = PackedFloat32Array(d.alpha)
	m._cl = PackedFloat32Array(d.Cl)
	m._cd = PackedFloat32Array(d.Cd)
	m._cm = PackedFloat32Array(d.Cm)
	assert(m._alpha.size() == m._cl.size() and m._cl.size() == m._cd.size()
		and m._cd.size() == m._cm.size(), "disc %s: table lengths differ" % path)
	return m


## Every disc under res://data/discs/*/*.json, sorted by id.
## c_zd_default applies to discs whose JSON has no "C_zd" key.
static func load_all(c_zd_default := 0.0) -> Array:
	var out: Array = []
	for sub in DirAccess.get_directories_at(DATA_DIR):
		var dir := DATA_DIR.path_join(sub)
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".json"):
				out.append(load_json(dir.path_join(f), 0.175, c_zd_default))
	out.sort_custom(func(a, b) -> bool: return a.id < b.id)
	return out


## Spin from release speed: about 5.2 rad/s per m/s (shotshaper's empirical
## fit to measured throws). A 24 m/s drive spins ~125 rad/s (~1200 rpm).
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


## Spin after `dt` seconds of flight at air speed `speed` (m/s). Hummel's
## spin-damping moment is proportional to omega, so spin decays exponentially,
## faster at higher speed: d(omega)/dt = -k omega with
## k = -rho V S d^2 C_zd / (4 I_z). Roll rate (in step) still goes as 1/omega,
## so a slower spin turns and fades more later in the flight.
func spin_after(speed: float, omega: float, dt: float) -> float:
	if c_zd == 0.0 or omega <= 0.0:
		return omega
	var k := -AIR_DENSITY * speed * area * diameter * diameter * c_zd / (4.0 * i_z)
	return omega * exp(-k * dt)


## One tick of flight.
##   v      velocity relative to the AIR (subtract wind first), m/s
##   n      disc normal
## Returns [aero_accel: Vector3 (no gravity), new_normal: Vector3, alpha_deg: float].
##
## Lift acts perpendicular to the airflow, in the plane of the airflow and the
## normal; drag acts against the airflow. The pitching moment M is not applied
## as a torque: a fast-spinning disc precesses instead, rolling about its line
## of flight at M / (omega * (I_z - I_xy)). That slow roll is turn and fade.
func step(v: Vector3, n: Vector3, omega: float, hand: float, dt: float) -> Array:
	var speed := v.length()
	if speed < 0.01:
		return [Vector3.ZERO, n, 0.0]
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
	if vpl > 1e-4 and omega > 0.1:
		var moment := q * area * diameter * c.z
		var roll_rate := moment / (omega * (i_z - i_xy))
		new_n = n.rotated(vp / vpl, -roll_rate * dt * hand).normalized()
	return [force / mass, new_n, alpha]
