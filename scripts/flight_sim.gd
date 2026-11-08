extends RefCounted
## Runs a throw forward through the real flight model, without any physics
## bodies, and solves for the launch angle that puts the disc on a target.
##
## One copy of the simulation, used by both the aim arc (aim_arc.gd, which
## draws it) and the putt assist (thrower.gd, which searches it). Two copies
## would drift, and then the line you are shown would stop being the line you
## get, which is worse than having no line at all.
##
## It mirrors flying_disc.apply_aero exactly: aero acceleration from
## DiscModel.step plus gravity, no damping (a disc turns its damping off while
## flying), stepping at the physics tick.

const STEP_DT := 1.0 / 60.0          ## The tick the disc really flies at.
const MAX_STEPS := 900               ## ~15 s, longer than any throw.
const FLOOR_Y := -40.0               ## Give up: off the edge of the world.


static func gravity() -> float:
	return float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))


## Fly it. Returns every point from the release to the first ground contact.
## `terrain` may be null, in which case it only stops at MAX_STEPS or FLOOR_Y.
static func fly(model, origin: Vector3, vel: Vector3, normal: Vector3, omega: float,
		hand: float, terrain, max_steps := MAX_STEPS) -> PackedVector3Array:
	var out := PackedVector3Array()
	if model == null:
		return out
	var g := gravity()
	var v := vel
	var n := normal
	var w := omega
	var p := origin
	out.append(p)
	for i in max_steps:
		var r: Array = model.step(v, n, w, hand, STEP_DT)
		v += r[0] * STEP_DT
		n = r[1]
		w = r[3]
		v.y -= g * STEP_DT
		p += v * STEP_DT
		out.append(p)
		if p.y < FLOOR_Y:
			break
		if terrain != null and p.y <= terrain.height_at(p.x, p.z):
			break
	return out


## Fly the throw described by `s` (a throw_setup-shaped dictionary:
## {disc, speed, nose, roll, spin, hand}) at launch angle `pitch`, heading
## `fwd`, from `origin`.
static func fly_throw(s: Dictionary, origin: Vector3, fwd: Vector3, pitch: float,
		terrain, max_steps := MAX_STEPS) -> PackedVector3Array:
	var model = s.disc
	if model == null:
		return PackedVector3Array()
	var ls: Array = model.launch_state(fwd, s.speed, pitch, s.nose, s.roll, s.hand)
	return fly(model, origin, ls[0], ls[1], s.spin, s.hand, terrain, max_steps)


## How high the flight passes the target, in metres: + means it goes OVER.
##
## Measured where the path first reaches the target's horizontal distance, so
## it answers "at the moment it gets there, is it above or below?" -- which is
## the question an aim is trying to settle. INF if it never gets that far.
static func height_error(path: PackedVector3Array, origin: Vector3, target: Vector3) -> float:
	var want := Vector2(target.x - origin.x, target.z - origin.z).length()
	if want < 0.01 or path.size() < 2:
		return INF
	var run := 0.0
	for i in range(1, path.size()):
		var a: Vector3 = path[i - 1]
		var b: Vector3 = path[i]
		var seg := Vector2(b.x - a.x, b.z - a.z).length()
		if run + seg >= want:
			var f: float = 1.0 if seg < 1e-6 else (want - run) / seg
			return a.y + (b.y - a.y) * f - target.y
		run += seg
	return INF                        # fell short: never reached the target


## The launch angle (deg) that drops the disc on `target`.
##
## A scan, then bisection, rather than plain bisection on the whole band,
## because the height error is NOT monotonic in pitch. Sweeping the angle up
## from flat, the disc first falls short of the target (no answer at all),
## then reaches it but underneath, then passes over it, and then -- thrown
## nearly straight up -- stops travelling far enough forward and falls short
## again. So the curve reads short / below / above / short, and the answer is
## the below-to-above crossing. Bisecting the raw band instead probes the top
## of it first, finds a lob that lands at its own feet, and concludes the
## target is unreachable: that is exactly what it did, and it put the assist
## to sleep for every putt past about 5 m.
##
## There is no formula to invert here -- lift and drag come from the disc's
## table -- so it has to be searched.
##
## Returns `fallback` if nothing reaches the target: running out of arm never
## silently becomes a flat throw.
static func solve_pitch(s: Dictionary, origin: Vector3, fwd: Vector3, target: Vector3,
		terrain, fallback: float, lo := -45.0, hi := 60.0, scan := 2.0) -> float:
	var want := Vector2(target.x - origin.x, target.z - origin.z).length()
	if want < 0.01:
		return fallback
	# Only simulate as far as the target: a budget in ticks for the straight
	# line plus plenty of slack for a lofted, slower path. Without this the
	# scan runs the full 15 s for every candidate.
	var speed: float = maxf(float(s.speed), 1.0)
	var budget := int(clampf(want / speed / STEP_DT * 4.0 + 30.0, 60.0, float(MAX_STEPS)))
	var best_below := INF               # pitch of the last sample passing under
	var e_below := 0.0
	var first_finite := INF
	var e_first := 0.0
	var a := lo
	while a <= hi + 0.001:
		var e := height_error(fly_throw(s, origin, fwd, a, terrain, budget), origin, target)
		if is_finite(e):
			if not is_finite(first_finite):
				first_finite = a
				e_first = e
			if e < 0.0:
				best_below = a
				e_below = e
			elif is_finite(best_below):
				# Bracketed: under at best_below, over at a.
				return _bisect(s, origin, fwd, target, terrain, budget, best_below, a)
		a += scan
	if not is_finite(first_finite):
		return fallback                 # cannot get there at this speed
	if e_first >= 0.0:
		return first_finite             # even the flattest throw clears it
	return fallback                     # reaches, but never high enough


## Narrow a bracket that goes from under the target to over it.
static func _bisect(s: Dictionary, origin: Vector3, fwd: Vector3, target: Vector3,
		terrain, budget: int, lo: float, hi: float, iters := 12) -> float:
	for i in iters:
		var mid := (lo + hi) * 0.5
		var e := height_error(fly_throw(s, origin, fwd, mid, terrain, budget), origin, target)
		if not is_finite(e) or e < 0.0:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5
