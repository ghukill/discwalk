extends Node3D
## A one-shot shower of little multicoloured voxels: bursts up and out,
## tumbles and flutters down, bounces on the ground (or floats on a lake),
## and stays there. Once every piece has settled it stops updating, so a
## landed burst costs only its draw. Set `linger` off to have each piece
## shrink away instead and the whole thing free itself.
##
## Collect (C) gathers it too: collect() whooshes every piece up into the
## air (~30 ft), then it soars over to the walker on a swaying curve and
## vanishes as it reaches you. Only the newest MAX_LINGERING bursts
## stay on the ground; an older one fades away when a new one lands.
##
## Visual only: no physics bodies. All the pieces live in one MultiMesh and
## are moved by hand every frame, so a few hundred cost next to nothing.

const PALETTE := [
	Color(0.95, 0.20, 0.25),   # red
	Color(1.00, 0.55, 0.10),   # orange
	Color(1.00, 0.88, 0.15),   # yellow
	Color(0.30, 0.85, 0.30),   # green
	Color(0.15, 0.80, 0.90),   # cyan
	Color(0.25, 0.45, 1.00),   # blue
	Color(0.65, 0.35, 0.95),   # purple
	Color(1.00, 0.40, 0.75),   # pink
	Color(1.00, 1.00, 1.00),   # white
]

@export var count := 280
@export var size := 0.045              ## Cube edge (m).
## Initial upward speed range (m/s): tops out ~8.5 to ~15 m up, about the
## height of a medium to big oak.
@export var speed_up := Vector2(15.0, 21.0)
@export var speed_out := Vector2(1.0, 4.0)   ## Initial sideways speed range (m/s).
@export var gravity := 9.8
## Air drag (1/s). Low on the way up so it shoots high; high once it starts
## falling (the paper "opens"), so it drifts down at under 2 m/s.
@export var drag_up := 0.35
@export var drag_down := 5.5
@export var flutter := 4.0             ## Sideways wobble once falling (m/s^2).
@export var bounce := 0.35             ## Upward speed kept on a ground bounce.
@export var linger := true             ## Stay on the ground (else fade out).
@export var life := Vector2(10.0, 14.0)  ## Seconds each piece lives (linger off).
@export var fade_time := 1.2           ## Shrinks away over its last this-many s.

## Bursts allowed to lie on the ground at once; past this the oldest fades.
## Generous on purpose: a landed burst costs next to nothing (it stops
## updating), so this is only a backstop for a very long session.
const MAX_LINGERING := 100

@export var opacity := 0.8             ## Always a little see-through.
@export var home_stagger := 0.8        ## Collect: pieces lift off over this many s ...
@export var home_rise := Vector2(7.5, 10.5)  ## ... whoosh up this high (m) ...
@export var rise_speed := 6.0          ## ... at about this speed (m/s) ...
@export var home_speed := Vector2(4.0, 20.0) ## ... then soar from this to this (m/s) ...
@export var home_ramp := 5.0           ## ... gaining this much per second ...
@export var home_turn := 1.8           ## ... turning toward you this eagerly (1/s) ...
@export var home_sway := 5.0           ## ... swaying side to side (m/s^2).

var terrain: Node3D

static var _bursts: Array = []         ## Lingering bursts, oldest first.

var _mm: MultiMesh
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _axis := PackedVector3Array()
var _spin := PackedFloat32Array()      ## rad/s
var _angle := PackedFloat32Array()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _phase := PackedFloat32Array()
var _settled := PackedByteArray()      ## 1 once a piece has come to rest.
var _floor := PackedFloat32Array()     ## Cached ground height under a piece ...
var _floor_at := PackedVector2Array()  ## ... and where it was looked up.
var _home: Node3D = null               ## Collecting: fly to this.
var _home_t := 0.0
var _apex := PackedVector3Array()      ## Collect: where each piece whooshes up to.
var _soaring := PackedByteArray()      ## Collect: 1 once past its apex.
var _alive := 0
var _rng := RandomNumberGenerator.new()


## Throw the confetti from world point `at`.
func burst(at: Vector3) -> void:
	_rng.randomize()
	top_level = true                   # don't ride along with the parent
	global_transform = Transform3D.IDENTITY
	var box := BoxMesh.new()
	box.size = Vector3.ONE * size
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true      # palette is sRGB: keep it saturated
	m.roughness = 0.6
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 1, 1, opacity)   # times the vertex colour
	box.material = m
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = box
	_mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	for arr in [_pos, _vel, _axis]:
		arr.resize(count)
	for arr in [_spin, _angle, _age, _life, _phase]:
		arr.resize(count)
	_settled.resize(count)
	_settled.fill(0)
	_floor.resize(count)
	_floor_at.resize(count)
	_floor_at.fill(Vector2(INF, INF))
	for i in count:
		var a := _rng.randf() * TAU
		var out := _rng.randf_range(speed_out.x, speed_out.y)
		_pos[i] = at + Vector3(_rng.randf_range(-0.2, 0.2), _rng.randf_range(-0.15, 0.15),
			_rng.randf_range(-0.2, 0.2))
		_vel[i] = Vector3(cos(a) * out, _rng.randf_range(speed_up.x, speed_up.y), sin(a) * out)
		_axis[i] = Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1),
			_rng.randf_range(-1, 1)).normalized()
		_spin[i] = _rng.randf_range(4.0, 14.0)
		_angle[i] = _rng.randf() * TAU
		_age[i] = 0.0
		_life[i] = _rng.randf_range(life.x, life.y) if not linger else INF
		_phase[i] = _rng.randf() * TAU
		_mm.set_instance_color(i, PALETTE[_rng.randi() % PALETTE.size()])
	_alive = count
	_draw()
	if linger:
		_bursts.append(self)
		tree_exiting.connect(func() -> void: _bursts.erase(self))
		while _bursts.size() > MAX_LINGERING:
			_bursts.pop_front().fade_out()


## Collect: every piece flies straight to `target` (the walker) and vanishes
## when it gets there; the burst frees itself once the last one is in.
func collect(target: Node3D) -> void:
	if _mm == null or not is_instance_valid(target):
		return
	_home = target
	_home_t = 0.0
	_bursts.erase(self)
	_apex.resize(count)
	_soaring.resize(count)
	_soaring.fill(0)
	for i in count:
		_settled[i] = 0
		_phase[i] = _rng.randf() * home_stagger       # lift-off delay
		_apex[i] = _pos[i] + Vector3(_rng.randf_range(-3.0, 3.0),
			_rng.randf_range(home_rise.x, home_rise.y), _rng.randf_range(-3.0, 3.0))
		_vel[i] = Vector3(0, _rng.randf_range(1.0, 2.0), 0)
	set_process(true)


## Shrink every piece away over the next second or two, then free.
func fade_out() -> void:
	_bursts.erase(self)
	for i in count:
		if _age[i] < _life[i]:
			_life[i] = _age[i] + fade_time + _rng.randf() * 0.8
	set_process(true)

## True once every piece has landed and stopped (linger: it stays put).
func settled() -> bool:
	return _mm != null and not is_processing()


## Seconds the longest-lived piece has left (tests). INF while lingering.
func remaining() -> float:
	var r := 0.0
	for i in _age.size():
		r = maxf(r, _life[i] - _age[i])
	return r


func _process(delta: float) -> void:
	if _mm == null:
		return
	var dt := minf(delta, 0.05)
	if _home != null and not is_instance_valid(_home):
		_home = null                       # walker gone: just let it fall
	if _home != null:
		_fly_home(dt)
		return
	_alive = 0
	var moving := 0
	for i in count:
		if _age[i] >= _life[i]:
			continue
		_alive += 1
		if _settled[i] and _life[i] == INF:
			continue
		moving += 1
		_age[i] += dt
		if _settled[i]:                    # fading where it lies
			_draw_one(i)
			continue
		var v := _vel[i]
		v.y -= gravity * dt
		v *= exp(-(drag_up if v.y > 0.0 else drag_down) * dt)
		if v.y < 0.0:                  # fluttering down: a lazy side-to-side
			var w := _age[i] * 6.0 + _phase[i]
			v.x += cos(w) * flutter * dt
			v.z += sin(w * 0.8) * flutter * dt
		var p := _pos[i] + v * dt
		# The ground lookup (terrain + every lake) is the costly part, and a
		# piece drifts slowly: only look again after it's moved 0.2 m.
		var xz := Vector2(p.x, p.z)
		if xz.distance_squared_to(_floor_at[i]) > 0.04:
			_floor[i] = _ground(p) + size * 0.5
			_floor_at[i] = xz
		var floor_y := _floor[i]
		if p.y < floor_y:
			p.y = floor_y
			if v.y < -0.6:
				v.y = -v.y * bounce
				v.x *= 0.6
				v.z *= 0.6
			else:
				v = Vector3(v.x * 0.8, 0.0, v.z * 0.8)
				_spin[i] *= 0.9
				# Flutter keeps nudging it ~0.2 m/s along the ground, so
				# don't wait for zero: once it's down to a slide, it lies.
				if linger and v.length() < 0.3:
					v = Vector3.ZERO
					_settled[i] = 1
		_pos[i] = p
		_vel[i] = v
		_angle[i] += _spin[i] * dt
		_draw_one(i)
	if _alive == 0:
		queue_free()
	elif moving == 0:
		set_process(false)                 # all landed: nothing left to move


## Collect: whoosh up to the apex, then soar over to the walker's chest,
## swaying, picking up speed, turning in harder as it closes.
func _fly_home(dt: float) -> void:
	_home_t += dt
	var goal := _home.global_position + Vector3(0, 1.1, 0)
	_alive = 0
	for i in count:
		if _age[i] >= _life[i]:
			continue
		_alive += 1
		_age[i] += dt
		var p := _pos[i]
		var v := _vel[i]
		var w := _home_t * 2.2 + i * 0.37   # this piece's sway
		var sway := Vector3(cos(w), 0.35 * sin(w * 1.3), sin(w * 0.9)) * home_sway * dt
		if not _soaring[i]:
			if _home_t < _phase[i]:
				continue                   # still waiting its turn
			var up := _apex[i] - p
			var du := up.length()
			# Ease into the top: slow as it nears the apex, like a lofted leaf.
			var want := up / maxf(du, 0.01) * rise_speed * clampf(du / 3.0, 0.35, 1.0)
			v = v.lerp(want, clampf(dt * 2.5, 0.0, 1.0)) + sway
			if du < 1.2:
				_soaring[i] = 1
				_phase[i] = _home_t        # soar start
		else:
			var to := goal - p
			var d := to.length()
			var speed := minf(home_speed.x + home_ramp * (_home_t - _phase[i]), home_speed.y)
			if d < 3.0:
				# Last few metres: straight in, no orbiting.
				p = p.move_toward(goal, maxf(speed, 6.0) * dt)
				v = (goal - p).normalized() * speed
				if p.distance_to(goal) < 0.3:
					_life[i] = _age[i]     # in: gone
				_pos[i] = p
				_vel[i] = v
				_draw_one(i)
				continue
			var turn := home_turn + 6.0 / (d + 1.0)
			v = v.lerp(to / d * speed, clampf(dt * turn, 0.0, 1.0)) + sway * clampf(d / 15.0, 0.0, 1.0)
		_pos[i] = p + v * dt
		_vel[i] = v
		_angle[i] += _spin[i] * dt * 0.5   # lazy tumble
		_draw_one(i)
	if _alive == 0:
		queue_free()


func _draw() -> void:
	for i in count:
		_draw_one(i)


func _draw_one(i: int) -> void:
	var s := clampf((_life[i] - _age[i]) / fade_time, 0.0, 1.0)
	var b := Basis(_axis[i], _angle[i]).scaled(Vector3.ONE * maxf(s, 0.001))
	_mm.set_instance_transform(i, Transform3D(b, _pos[i]))


## Where a piece stops falling: the ground, or the surface of a lake.
func _ground(p: Vector3) -> float:
	if terrain == null:
		return -INF
	var g: float = terrain.height_at(p.x, p.z)
	for lake: Dictionary in terrain.lakes:
		if Vector2(p.x, p.z).distance_to(lake.center) < lake.radius:
			g = maxf(g, lake.water_y)
	return g
