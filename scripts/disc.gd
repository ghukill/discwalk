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

signal came_to_rest(disc)

const FLORA := preload("res://scripts/flora.gd")

const SIZE := 0.22                   ## Block edge (m). About a disc's thickness x3.
const COLOR := Color(1.0, 0.36, 0.1) ## Safety orange, easy to spot.

## Fraction of speed kept per metre of leaves flown through.
@export var leaf_keep_per_metre := 0.72
## Bounciness when hitting bark (fraction of speed kept along the hit axis).
@export var bark_bounce := 0.4

var terrain: Node3D
var power := 0
var start := Vector3.ZERO            ## Release point (m).
var bark_hits := 0
var leaf_cells := 0                  ## Leaf voxels flown through.
var splashed := false
var resting := false
var max_height := 0.0                ## Peak height above release (m).

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

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * SIZE
	shape.shape = box
	add_child(shape)

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
	_rng.randomize()


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

	v = apply_aero(state, v)
	state.linear_velocity = v
	max_height = maxf(max_height, p.y - start.y)


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
	if resting:
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
	sm.albedo_color = Color(COLOR, 0.35)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.material = sm
	_beacon.mesh = bm
	_beacon.top_level = true
	_beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beacon)
	_beacon.global_position = global_position + Vector3(0, 4.0, 0)
	came_to_rest.emit(self)


static func _cell(p: Vector3, bs: float) -> Vector3i:
	return Vector3i(floori(p.x / bs), floori(p.y / bs), floori(p.z / bs))
