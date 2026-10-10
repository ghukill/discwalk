extends Node3D
## Flight paths: every real disc throw leaves a trail of little voxel cubes
## hanging in the air where it flew, plus smaller, dimmer cubes along its
## skips and rolls on the ground. Each throw gets its own colour. Paths stay
## until you press P or roll a new world. P lets them go gently: every cube
## drifts down out of the air, tumbling a little, and goes *poof* (swells,
## pales and fades) when it reaches the ground or the water. Blocks (the
## orange cannon) don't leave paths.
##
## Cubes have no collision (walk through them) and each path is one
## MultiMeshInstance3D, so even hundreds of throws are cheap.

const AIR_SIZE := 0.08               ## Cube edge in flight (m).
const GROUND_SIZE := 0.05            ## Cube edge on the ground (m).
const AIR_SPACING := 0.5             ## A cube every this many metres flown.
const GROUND_SPACING := 0.25         ## ... and rolled (slower, so closer).
const GROUND_DIM := 0.5              ## Ground cubes: colour darkened by this.
const START_CAPACITY := 256
const FALL_GRAVITY := 3.5            ## m/s^2: a gentle drift, not a drop.
const FALL_DELAY_MAX := 0.6          ## Cubes let go at slightly different times (s).
const POOF_TIME := 0.35              ## Swell + fade on landing (s).
const POOF_SWELL := 1.8              ## Grows to this many times its size.

var _paths: Array = []               ## {disc, mmi, color, last, count, air, ground, points, colors}
var _hue := 0.07                     ## Next colour (golden-ratio hue walk).
var _box: BoxMesh
var _material: StandardMaterial3D
var _fade_material: StandardMaterial3D
var _falling: Array = []             ## {mmi, n, pos, vel, delay, size, color, axis, angle, spin, ground, poof}
var _rng := RandomNumberGenerator.new()
var terrain: Node3D                  ## For where "the ground" is when cubes fall.


func _ready() -> void:
	top_level = true
	_box = BoxMesh.new()
	_box.size = Vector3.ONE           # scaled per instance
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.vertex_color_is_srgb = true   # true colours (not washed out)
	_material.disable_fog = true            # stay vivid far down the fairway
	_box.material = _material
	_fade_material = _material.duplicate()
	_fade_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rng.randomize()


## A fresh colour for the next throw: bright, and far from the last few.
func next_color() -> Color:
	var c := Color.from_hsv(_hue, 0.85, 1.0)
	_hue = fposmod(_hue + 0.618034, 1.0)
	return c


## Starts recording `disc` (a flying_disc.gd) in `color`.
func track(disc: Node3D, color: Color) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _box
	mm.instance_count = START_CAPACITY
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	var path := {"disc": disc, "mmi": mmi, "color": color, "count": 0,
		"air": 0, "ground": 0, "last": disc.global_position,
		"points": PackedVector3Array(), "sizes": PackedFloat32Array(), "colors": PackedColorArray()}
	_paths.append(path)
	_add(path, disc.global_position, true)


## How many paths there are (including any still being drawn).
func count() -> int:
	return _paths.size()


## Removes every path. gently = true (P): the cubes fall and poof. false
## (new world): they just vanish, since the ground under them is gone.
func clear(gently := false) -> void:
	for p in _paths:
		if gently and p.count > 0:
			_let_go(p)
		else:
			p.mmi.queue_free()
	_paths.clear()
	if not gently:
		for f in _falling:
			f.mmi.queue_free()
		_falling.clear()


## Cubes still falling or poofing (0 when the show's over).
func fading() -> int:
	var n := 0
	for f in _falling:
		n += f.n
	return n


func _let_go(p: Dictionary) -> void:
	var n: int = p.count
	var f := {"mmi": p.mmi, "n": n, "pos": p.points.duplicate(), "size": p.sizes,
		"color": p.colors, "vel": PackedVector3Array(), "delay": PackedFloat32Array(),
		"axis": PackedVector3Array(), "angle": PackedFloat32Array(), "spin": PackedFloat32Array(),
		"ground": PackedFloat32Array(), "poof": PackedFloat32Array(), "left": n}
	f.vel.resize(n)
	f.delay.resize(n)
	f.axis.resize(n)
	f.angle.resize(n)
	f.spin.resize(n)
	f.ground.resize(n)
	f.poof.resize(n)
	for i in n:
		var at: Vector3 = f.pos[i]
		# A breath of sideways drift, like leaves.
		f.vel[i] = Vector3(_rng.randf_range(-0.4, 0.4), _rng.randf_range(0.0, 0.6), _rng.randf_range(-0.4, 0.4))
		f.delay[i] = _rng.randf() * FALL_DELAY_MAX
		f.axis[i] = Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()
		f.spin[i] = _rng.randf_range(1.5, 5.0)
		f.ground[i] = _floor_at(at)
		f.poof[i] = -1.0                       # not poofing yet
	p.mmi.material_override = _fade_material
	_falling.append(f)


## Where a falling cube stops: the ground, or the water surface over a lake.
func _floor_at(at: Vector3) -> float:
	if terrain == null:
		return at.y - 50.0
	var y: float = terrain.height_at(at.x, at.z)
	for lake: Dictionary in terrain.lakes:
		if Vector2(at.x, at.z).distance_to(lake.center) < lake.radius:
			y = maxf(y, lake.water_y)
	return minf(y, at.y)


func _process(delta: float) -> void:
	for f in _falling:
		_fall_step(f, delta)
	for i in range(_falling.size() - 1, -1, -1):
		if _falling[i].left <= 0:
			_falling[i].mmi.queue_free()
			_falling.remove_at(i)


func _fall_step(f: Dictionary, dt: float) -> void:
	var mm: MultiMesh = f.mmi.multimesh
	for i in f.n:
		var poof: float = f.poof[i]
		if poof >= POOF_TIME:
			continue                                # long gone
		var size: float = f.size[i]
		var c: Color = f.color[i]
		var at: Vector3 = f.pos[i]
		if poof >= 0.0:
			poof += dt
			f.poof[i] = poof
			var k := clampf(poof / POOF_TIME, 0.0, 1.0)
			if k >= 1.0:
				f.left -= 1
				mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), at))
				continue
			var e := 1.0 - (1.0 - k) * (1.0 - k)    # ease out
			var basis := Basis(f.axis[i], f.angle[i]).scaled(Vector3.ONE * size * lerpf(1.0, POOF_SWELL, e))
			mm.set_instance_transform(i, Transform3D(basis, at))
			mm.set_instance_color(i, Color(c.lerp(Color.WHITE, 0.6 * e), 1.0 - e))
			continue
		if f.delay[i] > 0.0:
			f.delay[i] -= dt
			continue
		var v: Vector3 = f.vel[i]
		v.y -= FALL_GRAVITY * dt
		v *= 1.0 - 0.6 * dt                         # air: keeps it floaty
		at += v * dt
		f.vel[i] = v
		f.angle[i] += f.spin[i] * dt
		var ground: float = f.ground[i] + size * 0.5
		if at.y <= ground:
			at.y = ground
			f.poof[i] = 0.0
		f.pos[i] = at
		mm.set_instance_transform(i, Transform3D(Basis(f.axis[i], f.angle[i]).scaled(Vector3.ONE * size), at))


func _physics_process(_delta: float) -> void:
	for p in _paths:
		var d = p.disc
		if d == null:
			continue
		if not is_instance_valid(d) or d.resting or d.collecting:
			p.disc = null                 # done: the path stays, recording stops
			continue
		var pos: Vector3 = d.global_position
		var air: bool = d.flying
		var spacing := AIR_SPACING if air else GROUND_SPACING
		var gap: float = pos.distance_to(p.last)
		if gap < spacing:
			continue
		# Fill in evenly if it moved more than one spacing this tick.
		var steps := int(gap / spacing)
		var from: Vector3 = p.last
		for i in range(1, steps + 1):
			_add(p, from.lerp(pos, float(i) * spacing / gap), air)


func _add(p: Dictionary, at: Vector3, air: bool) -> void:
	var size := AIR_SIZE if air else GROUND_SIZE
	var c: Color = p.color if air else p.color.darkened(GROUND_DIM)
	p.points.append(at)
	p.sizes.append(size)
	p.colors.append(c)
	var mm: MultiMesh = p.mmi.multimesh
	var n: int = p.count
	if n >= mm.instance_count:
		_grow(p)
	_put(mm, n, at, size, c)
	p.count = n + 1
	mm.visible_instance_count = p.count
	p.last = at
	if air:
		p.air += 1
	else:
		p.ground += 1


static func _put(mm: MultiMesh, i: int, at: Vector3, size: float, c: Color) -> void:
	mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * size), at))
	mm.set_instance_color(i, c)


## MultiMesh can't grow in place: resize (which wipes it) and refill from the
## path's own copy of its points.
static func _grow(p: Dictionary) -> void:
	var mm: MultiMesh = p.mmi.multimesh
	var n: int = p.count
	mm.visible_instance_count = -1
	mm.instance_count = maxi(n * 2, START_CAPACITY)
	for i in n:
		_put(mm, i, p.points[i], p.sizes[i], p.colors[i])
	mm.visible_instance_count = n
