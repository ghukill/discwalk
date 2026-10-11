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

## Flight models (see docs/DISC-FLIGHT-PLAN.md):
##   "hummel"      Hummel (2003) moments: pitch, roll and spin-down, each with
##                 its damping term, and gyroscopic precession at M / (I_z r).
##                 Spin bleeds off in flight. The game default.
##   "shotshaper"  The shotshaper approximation the game started with:
##                 constant spin, no damping, roll at M / (omega (I_z - I_xy)).
##                 Kept for A/B (--flight=shotshaper) and so tools/flight_test.gd
##                 can still check us against shotshaper's own flights.
const FLIGHTS := ["hummel", "shotshaper"]

## Hummel's damping coefficients, from his long-flight fit (flight f2302:
## thesis Table 3-2 and simulate_flight.m). They are DIMENSIONAL: each
## multiplies a rate in rad/s, then q A d like the other moments:
##   roll   R = C_Rp p           q A d   (wobble damping)
##   pitch  M = (C_M(a) + C_Mq q) q A d  (C_M(a) comes from the disc table)
##   spin   N = C_Nr r           q A d   (spin down)
## They were measured on a 175 g Frisbee, not a golf disc, so a disc JSON may
## override them ("CMq", "CRp", "CNr"). Hummel's 4th rate term, C_Rr (roll
## moment from spin), is left out: his value and its scaling disagree with
## Potts & Crowther's, and our CFD tables have no roll-moment data.
const HUMMEL_CMQ := -1.44e-2
const HUMMEL_CRP := -1.25e-2
const HUMMEL_CNR := -3.41e-5

var id := ""
var label := ""
var source := ""
var license := ""
var diameter := 0.211                ## m
var area := 0.0                      ## m^2
var mass := 0.175                    ## kg
var i_xy := 0.0                      ## moment of inertia across the disc (kg m^2)
var i_z := 0.0                       ## moment of inertia about the spin axis (kg m^2)
var flight := "hummel"               ## One of FLIGHTS.
var c_mq := HUMMEL_CMQ               ## Pitch damping (per rad/s).
var c_rp := HUMMEL_CRP               ## Roll damping (per rad/s).
var c_nr := HUMMEL_CNR               ## Spin down (per rad/s).

var _alpha := PackedFloat32Array()   ## deg, ascending, covers -90..90
var _cl := PackedFloat32Array()
var _cd := PackedFloat32Array()
var _cm := PackedFloat32Array()


## Loads one disc from JSON: {id, label, source, license, diameter, J_xy, J_z,
## alpha[], Cl[], Cd[], Cm[]} plus optional Hummel overrides {CMq, CRp, CNr}.
## J_* are inertia per unit mass (m^2).
static func load_json(path: String, disc_mass := 0.175, flight_model := "hummel") -> RefCounted:
	assert(flight_model in FLIGHTS, "unknown flight model %s" % flight_model)
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
	m.flight = flight_model
	m.c_mq = float(d.get("CMq", HUMMEL_CMQ))
	m.c_rp = float(d.get("CRp", HUMMEL_CRP))
	m.c_nr = float(d.get("CNr", HUMMEL_CNR))
	m._alpha = PackedFloat32Array(d.alpha)
	m._cl = PackedFloat32Array(d.Cl)
	m._cd = PackedFloat32Array(d.Cd)
	m._cm = PackedFloat32Array(d.Cm)
	assert(m._alpha.size() == m._cl.size() and m._cl.size() == m._cd.size()
		and m._cd.size() == m._cm.size(), "disc %s: table lengths differ" % path)
	return m


## Every disc under res://data/discs/*/*.json, sorted by id.
static func load_all(flight_model := "hummel") -> Array:
	var out: Array = []
	for sub in DirAccess.get_directories_at(DATA_DIR):
		var dir := DATA_DIR.path_join(sub)
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".json"):
				out.append(load_json(dir.path_join(f), 0.175, flight_model))
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


## The flight model from the command line: `-- --flight=shotshaper` (default
## hummel).
static func flight_from_args() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--flight="):
			var f := a.get_slice("=", 1)
			if f in FLIGHTS:
				return f
			push_warning("unknown --flight=%s (use %s)" % [f, ", ".join(FLIGHTS)])
	return "hummel"


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
## and fade (see _attitude_hummel and _attitude_shotshaper).
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
	var new_omega := omega
	if vpl > 1e-4 and omega > 0.1:
		var qad := q * area * diameter
		if flight == "hummel":
			new_n = _attitude_hummel(n, vp / vpl, c.z, qad, -hand * omega, dt)
		else:
			new_n = _attitude_shotshaper(n, vp / vpl, c.z * qad, omega, hand, dt)
	if flight == "hummel":
		# Spin down: I_z dr/dt = C_Nr r qAd, so spin decays exponentially,
		# faster at high speed (qAd goes as v^2): ~7 %/s at 24 m/s.
		new_omega = omega * exp(c_nr * q * area * diameter * dt / i_z)
	return [force / mass, new_n, alpha, new_omega]


## Hummel (2003) attitude, quasi-steady. His Euler equations (thesis Appendix B)
## for a disc with angular momentum H = I_z r n and a cross-axis rate w (x̂ = roll
## component p, ŷ = pitch component q) are
##   I_xy dw/dt + I_z r (w x n) = M_perp.
## The I_xy dw/dt part is wobble (nutation): it spins around at ~2r, about
## 200 rad/s, and Hummel's damping kills it in ~0.25 s. Dropping it leaves the
## steady precession, M_perp = I_z r (w x n), with w x n = p ŷ - q x̂:
##   x̂ (roll):   C_Rp p qAd           = -I_z r q
##   ŷ (pitch):  (C_M + C_Mq q) qAd   =  I_z r p
## Two linear equations for p and q, solved exactly below. Without damping
## this is p = M / (I_z r): a gyroscope's precession. Roll damping adds a small
## pitch rate q (the nose drifts as the disc turns/fades); pitch damping slows
## the roll a little. Matches a full 6-DOF integration (wobble and all) to ~1%;
## see tools/discs/hummel_reference.py.
##   x   unit airflow direction in the disc plane (Hummel's roll axis)
##   cm  pitching-moment coefficient at this angle of attack
##   r   signed spin about n (rad/s): -omega for a RH backhand (clockwise)
func _attitude_hummel(n: Vector3, x: Vector3, cm: float, qad: float, r: float,
		dt: float) -> Vector3:
	var y := x.cross(n)                         # Hummel's pitch axis (to the right)
	var h := i_z * r
	var qad2 := qad * qad
	var q_rate := -(c_rp * cm * qad2) / (h * h + c_rp * c_mq * qad2)
	var p_rate := (cm + c_mq * q_rate) * qad / h
	var w := x * p_rate + y * q_rate
	var wl := w.length()
	if wl < 1e-9:
		return n
	return n.rotated(w / wl, wl * dt).normalized()


## shotshaper's attitude: roll about the airflow at M / (omega (I_z - I_xy)),
## spin constant. (A real gyroscope precesses at M / (I_z omega), about half
## as fast for a flat disc; this is the one thing the Hummel model changes
## besides the damping terms.)
func _attitude_shotshaper(n: Vector3, x: Vector3, moment: float, omega: float,
		hand: float, dt: float) -> Vector3:
	var roll_rate := moment / (omega * (i_z - i_xy))
	return n.rotated(x, -roll_rate * dt * hand).normalized()
