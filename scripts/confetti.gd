extends Node3D
## A one-shot shower of little multicoloured voxels: bursts up and out,
## tumbles and flutters down, bounces on the ground (or floats on a lake),
## then each piece shrinks away and the whole thing frees itself.
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
@export var speed_up := Vector2(4.0, 8.5)    ## Initial upward speed range (m/s).
@export var speed_out := Vector2(0.5, 3.5)   ## Initial sideways speed range (m/s).
@export var gravity := 9.8
@export var drag := 1.4                ## Air drag (1/s): confetti floats down.
@export var flutter := 1.6             ## Sideways wobble once falling (m/s^2).
@export var bounce := 0.35             ## Upward speed kept on a ground bounce.
@export var life := Vector2(3.2, 5.0)  ## Seconds each piece lives.
@export var fade_time := 0.8           ## Shrinks away over its last this-many s.

var terrain: Node3D

var _mm: MultiMesh
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _axis := PackedVector3Array()
var _spin := PackedFloat32Array()      ## rad/s
var _angle := PackedFloat32Array()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _phase := PackedFloat32Array()
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
		_life[i] = _rng.randf_range(life.x, life.y)
		_phase[i] = _rng.randf() * TAU
		_mm.set_instance_color(i, PALETTE[_rng.randi() % PALETTE.size()])
	_alive = count
	_draw()


## Seconds the longest-lived piece has left (tests).
func remaining() -> float:
	var r := 0.0
	for i in _age.size():
		r = maxf(r, _life[i] - _age[i])
	return r


func _process(delta: float) -> void:
	if _mm == null:
		return
	var dt := minf(delta, 0.05)
	_alive = 0
	for i in count:
		if _age[i] >= _life[i]:
			continue
		_alive += 1
		_age[i] += dt
		var v := _vel[i]
		v.y -= gravity * dt
		v *= exp(-drag * dt)
		if v.y < 0.0:                  # fluttering down: a lazy side-to-side
			var w := _age[i] * 6.0 + _phase[i]
			v.x += cos(w) * flutter * dt
			v.z += sin(w * 0.8) * flutter * dt
		var p := _pos[i] + v * dt
		var floor_y := _ground(p) + size * 0.5
		if p.y < floor_y:
			p.y = floor_y
			if v.y < -0.6:
				v.y = -v.y * bounce
				v.x *= 0.6
				v.z *= 0.6
			else:
				v = Vector3(v.x * 0.8, 0.0, v.z * 0.8)
				_spin[i] *= 0.9
		_pos[i] = p
		_vel[i] = v
		_angle[i] += _spin[i] * dt
	_draw()
	if _alive == 0:
		queue_free()


func _draw() -> void:
	for i in count:
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
