extends RigidBody3D
## A thrown "disc". For now it's a small bright block shot out of a cannon
## (you); real disc flight comes later (see apply_aero()).
##
## What touches what:
## - Ground and tree trunks: ordinary Godot physics. The terrain heightmap and
##   trunk boxes are collision shapes, so the block bounces, tumbles and rolls
##   down hills on its own.
## - Branches and leaves are NOT physics bodies (there are millions of tree
##   voxels). Instead, each physics tick this script marches the disc's path
##   through the tree voxel grid: bark bounces it back, leaves bleed off speed
##   and knock it about ("tree kick"), so a disc can get swallowed by a crown.
## - Lakes: water drags it to a crawl and floats it at the surface.
## - Collecting (C): the disc turns into a rolling ball and rolls home to
##   you, starting at a quarter of walking pace and building speed. It's
##   still a physics body, so trunks, steep ledges and lakes get in its way;
##   only momentum gets it up a step.

signal came_to_rest(disc)
signal collected(disc)

const FLORA := preload("res://scripts/flora.gd")

const SIZE := 0.22                   ## Block edge (m). About a disc's thickness x3.
const COLOR := Color(1.0, 0.36, 0.1) ## Safety orange, easy to spot.

## Fraction of speed kept per metre of leaves flown through.
@export var leaf_keep_per_metre := 0.72
## Bounciness when hitting bark (fraction of speed kept along the hit axis).
@export var bark_bounce := 0.4
## Collecting: starting speed (m/s, a quarter of walking pace) ...
@export var collect_speed0 := 1.0
## ... speed target grows as speed0 + a*t + b*t^2 (passes sprint speed after ~3.5 s) ...
@export var collect_ramp := Vector2(0.6, 0.35)
@export var collect_max_speed := 25.0
## ... but it can only push itself this hard (m/s^2): enough to roll up the
## 45-degree one-block steps you can walk up, but 2-block cliffs (63 deg+) stop
## it unless it has built up the momentum to roll over them.
@export var collect_accel := 14.0
@export var collect_timeout := 40.0     ## Give up (and rest) after this long.

var terrain: Node3D
var color := COLOR                   ## Body + beam colour.
var power := 0
var start := Vector3.ZERO            ## Release point (m).
var bark_hits := 0
var leaf_cells := 0                  ## Leaf voxels flown through.
var splashed := false
var resting := false
var max_height := 0.0                ## Peak height above release (m).
var collecting := false
var collect_target: Node3D
var _collect_t := 0.0
var _shape: CollisionShape3D

var beam_on := true                  ## Show the rest beacon (toggled with B).
var _still := 0.0
var _in_water := false
var _beacon: MeshInstance3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	mass = 0.175                     # a 175 g disc
	continuous_cd = true             # fast + small: don't tunnel through the ground
	can_sleep = true
	linear_damp = 0.05               # a whisper of air drag
	angular_damp = 0.3
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.35
	mat.friction = 0.7
	physics_material_override = mat
	# Report touches, so a smack against a trunk collider counts as a bark hit.
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)

	_shape = CollisionShape3D.new()
	_shape.shape = _make_shape()
	add_child(_shape)
	_build_visual()
	_rng.randomize()


## Collision shape while flying/resting. Subclasses (flying_disc.gd) override.
func _make_shape() -> Shape3D:
	return _box_shape()


## What it looks like. Subclasses (flying_disc.gd) override.
func _build_visual() -> void:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * SIZE
	var sm := StandardMaterial3D.new()
	sm.albedo_color = COLOR
	sm.emission_enabled = true
	sm.emission = COLOR
	sm.emission_energy_multiplier = 0.6
	bm.material = sm
	mesh.mesh = bm
	add_child(mesh)


## Release from `pos` with velocity `vel` (m/s) and a tumbling spin.
func launch(pos: Vector3, vel: Vector3, spin: Vector3) -> void:
	start = pos
	global_position = pos
	linear_velocity = vel
	angular_velocity = spin


func distance() -> float:
	return Vector2(global_position.x - start.x, global_position.z - start.z).length()


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if terrain == null or terrain.flora == null:
		return
	var v := state.linear_velocity
	var v0 := v
	var p := state.transform.origin
	var dt := state.step
	var bs: float = terrain.block_size

	# March this tick's path through the tree voxel grid in half-block steps.
	var travel := v.length() * dt
	if travel > 0.0001:
		var steps := ceili(travel / (bs * 0.4))
		var prev := _cell(p, bs)
		var leaves := 0
		for i in range(1, steps + 1):
			var q := p + v * dt * (float(i) / steps)
			var c := _cell(q, bs)
			if c == prev:
				continue
			var kind: int = terrain.flora.voxel_at(c)
			if kind == FLORA.BARK:
				# Bounce off whichever face(s) we crossed into, back from where we were.
				for axis in 3:
					if c[axis] != prev[axis]:
						v[axis] = -v[axis] * bark_bounce
				v *= 0.85
				# Put it back where it was just before entering the bark.
				var xf := state.transform
				xf.origin = p + v0 * dt * (float(i - 1) / steps)
				state.transform = xf
				bark_hits += 1
				break
			elif kind == FLORA.LEAF:
				leaves += 1
			prev = c
		if leaves > 0:
			leaf_cells += leaves
			var metres := leaves * bs
			var speed := v.length()
			v *= pow(leaf_keep_per_metre, metres)
			# Leaves knock it about a little.
			v += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.5, 0.5),
				_rng.randf_range(-1, 1)) * speed * 0.06 * minf(metres, 2.0)

	# Water: heavy drag, then float up to the surface.
	_in_water = false
	for lake: Dictionary in terrain.lakes:
		if p.y < lake.water_y + 0.05 \
				and Vector2(p.x, p.z).distance_to(lake.center) < lake.radius:
			if not splashed:
				splashed = true
				v *= 0.35
			v *= pow(0.15, dt)
			v.y += (9.8 + 4.0 * clampf(lake.water_y - p.y, 0.0, 1.0) * 4.0) * dt
			v.y *= pow(0.02, dt)      # settle the bobbing quickly
			_in_water = true
			break

	v = _rescue_if_under(state, v, p, bs)
	if collecting:
		v = _roll_home(state, v, p, dt)
	v = apply_aero(state, v)
	state.linear_velocity = v
	max_height = maxf(max_height, p.y - start.y)


## Safety net: very rarely (about 1 throw in 50 at fine block sizes, after
## a slow tumble out of a tree) the physics squeezes a thin disc through the
## ground collider. If we're clearly below the ground, pop back up onto it.
var rescues := 0
func _rescue_if_under(state: PhysicsDirectBodyState3D, v: Vector3, p: Vector3, bs: float) -> Vector3:
	if p.y > terrain.height_at(p.x, p.z) - bs - 0.3:
		return v                                   # fine (or on a slope's smooth collider)
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, p.y + 60.0, p.z), Vector3(p.x, p.y - 1.0, p.z))
	q.exclude = [get_rid()]
	q.collide_with_areas = false
	var hit := state.get_space_state().intersect_ray(q)
	if hit.is_empty() or hit.position.y < p.y + 0.15:
		return v                                   # nothing above us: not under ground
	var xf := state.transform
	xf.origin = hit.position + Vector3.UP * 0.15
	state.transform = xf
	state.angular_velocity = Vector3.ZERO
	rescues += 1
	return Vector3.ZERO


## Start rolling home to `target` (the player).
func start_collect(target: Node3D) -> void:
	collecting = true
	collect_target = target
	_collect_t = 0.0
	resting = false
	_still = 0.0
	if _beacon != null:
		_beacon.queue_free()
		_beacon = null
	can_sleep = false
	sleeping = false
	var ball := SphereShape3D.new()      # rolls like a ball, still looks like a block
	ball.radius = SIZE * 0.5
	_shape.shape = ball


func _stop_collect() -> void:
	collecting = false
	can_sleep = true
	_shape.shape = _make_shape()


## Steers the horizontal velocity toward the player, with a speed target that
## keeps growing and a limited push, then spins the ball to match.
func _roll_home(state: PhysicsDirectBodyState3D, v: Vector3, p: Vector3, dt: float) -> Vector3:
	if not is_instance_valid(collect_target):
		_stop_collect.call_deferred()
		return v
	var goal := collect_target.global_position + Vector3(0, 0.9, 0)
	var to := goal - p
	if to.length() < 1.0:
		_arrive.call_deferred()
		return v
	_collect_t += dt
	if _collect_t > collect_timeout:
		_stop_collect.call_deferred()
		return v
	var t := _collect_t
	var cap := minf(collect_speed0 + collect_ramp.x * t + collect_ramp.y * t * t, collect_max_speed)
	var flat := Vector3(to.x, 0, to.z)
	var want := flat.normalized() * cap if flat.length() > 0.01 else Vector3.ZERO
	var vh := Vector3(v.x, 0, v.z)
	var dv := want - vh
	var max_dv := collect_accel * dt
	if dv.length() > max_dv:
		dv = dv.normalized() * max_dv
	v += dv
	state.angular_velocity = Vector3.UP.cross(Vector3(v.x, 0, v.z)) / (SIZE * 0.5)
	return v


func _arrive() -> void:
	if not collecting:
		return
	collecting = false
	collected.emit(self)
	queue_free()


func _box_shape() -> BoxShape3D:
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * SIZE
	return box


func _on_body_entered(body: Node) -> void:
	if body.name == "Trunks":
		bark_hits += 1


## Future home of disc flight physics (lift, drag, gyroscopic fade). Today a
## block is just a cannonball, so this does nothing.
func apply_aero(_state: PhysicsDirectBodyState3D, v: Vector3) -> Vector3:
	return v


func _physics_process(delta: float) -> void:
	if global_position.y < -30.0:
		queue_free()
		return
	if resting or collecting:
		return
	var moving := linear_velocity.length()
	if _in_water:
		# Floating: bobbing up and down doesn't count, only drifting.
		moving = Vector2(linear_velocity.x, linear_velocity.z).length()
	if moving < 0.15 or sleeping:
		_still += delta
		if _still > 0.6:
			_come_to_rest()
	else:
		_still = 0.0


func _come_to_rest() -> void:
	resting = true
	# A tall, faint orange beam so you can find your disc from afar.
	_beacon = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.06, 8.0, 0.06)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(color, 0.35)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.material = sm
	_beacon.mesh = bm
	_beacon.top_level = true
	_beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beacon)
	_beacon.global_position = global_position + Vector3(0, 4.0, 0)
	_beacon.visible = beam_on
	came_to_rest.emit(self)


func set_beam(on: bool) -> void:
	beam_on = on
	if _beacon != null:
		_beacon.visible = on


static func _cell(p: Vector3, bs: float) -> Vector3i:
	return Vector3i(floori(p.x / bs), floori(p.y / bs), floori(p.z / bs))
