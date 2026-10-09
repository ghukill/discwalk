extends "res://scripts/disc.gd"
## A real flying disc (step 2). Same body as the block (trees, lakes, beams,
## fetch, collect all come from disc.gd), but:
##
## - It's flat: a 21 cm x 3 cm cylinder collider, drawn as a little pixel
##   circle of voxels.
## - While airborne it flies: every physics tick DiscModel works out lift,
##   drag and the gyroscopic roll (turn/fade) from the disc's tilt, and this
##   script keeps the body's orientation glued to that tilt. Spin is just a
##   number (rad/s) fed to the roll maths; the mesh spins for show only.
## - On first contact with anything (ground, trunk, bark, leaves, water) the
##   aerodynamics switch off for good and ordinary physics takes over: skips,
##   rolls, flips. The disc keeps a little real spin so it can roll on edge.

const DiscModel := preload("res://scripts/disc_model.gd")

const RADIUS := 0.105
const THICK := 0.03
const PIXELS := 7                    ## Pixel-circle grid (PIXELS x PIXELS).
const VISUAL_SPIN_MAX := 14.0        ## rad/s shown on screen (real spin strobes).
const LANDED_SPIN_MAX := 25.0        ## rad/s handed to the physics on landing.

var model: RefCounted                ## DiscModel
var normal := Vector3.UP             ## Top face direction while flying.
var omega := 0.0                     ## Spin (rad/s).
var hand := 1.0                      ## +1 RH backhand, -1 RH forehand.
var wind := Vector3.ZERO             ## m/s (static for now).
var flying := false                  ## Aerodynamics on.
var speed0 := 0.0
var flight_time := 0.0
var landed_by := ""                  ## What ended the flight.
var flight_dist := 0.0               ## Carry: flat distance at first contact (m).

var _spin_node: Node3D
var _spin_angle := 0.0
var _hits0 := 0


## Release from `pos` with velocity `vel`, top face `n`, spin `spin_rate`.
func launch_disc(pos: Vector3, vel: Vector3, n: Vector3, spin_rate: float,
		handedness := 1.0) -> void:
	start = pos
	normal = n.normalized()
	omega = spin_rate
	hand = handedness
	speed0 = vel.length()
	flying = true
	flight_time = 0.0
	_set_flight_physics()
	global_transform = Transform3D(_flight_basis(vel), pos)
	linear_velocity = vel
	angular_velocity = Vector3.ZERO
	_hits0 = bark_hits


func _ready() -> void:
	super._ready()
	if flying:                       # launched before entering the tree
		_set_flight_physics()


func _set_flight_physics() -> void:
	# Air drag comes from the model: replace (don't add to) the project's
	# default damping while flying.
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.3
	can_sleep = false


func _make_shape() -> Shape3D:
	var c := CylinderShape3D.new()
	c.radius = RADIUS
	c.height = THICK
	return c


## A pixel circle: PIXELS x PIXELS cells of THICK-tall blocks, a darker rim
## and one off-centre stamp so you can see it spin.
func _build_visual() -> void:
	_spin_node = Node3D.new()
	add_child(_spin_node)
	var cell := RADIUS * 2.0 / PIXELS
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := (PIXELS - 1) / 2.0
	for ix in PIXELS:
		for iz in PIXELS:
			var dx := ix - c
			var dz := iz - c
			var r := sqrt(dx * dx + dz * dz)
			if r > c + 0.6:
				continue
			var col := color
			if r > c - 0.5:
				col = color.darkened(0.3)             # rim
			elif ix == PIXELS - 2 and iz == int(c):
				col = Color(1, 1, 1)                  # stamp
			_add_box(st, Vector3(dx * cell, 0, dz * cell), Vector3(cell, THICK, cell), col)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var sm := StandardMaterial3D.new()
	sm.vertex_color_use_as_albedo = true
	sm.emission_enabled = true
	sm.emission = color
	sm.emission_energy_multiplier = 0.35
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED   # thin + tiny: never lose a face
	mi.material_override = sm
	_spin_node.add_child(mi)


static func _add_box(st: SurfaceTool, at: Vector3, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var faces := [
		[Vector3.UP, Vector3.RIGHT, Vector3.BACK], [Vector3.DOWN, Vector3.RIGHT, Vector3.FORWARD],
		[Vector3.RIGHT, Vector3.BACK, Vector3.UP], [Vector3.LEFT, Vector3.FORWARD, Vector3.UP],
		[Vector3.BACK, Vector3.LEFT, Vector3.UP], [Vector3.FORWARD, Vector3.RIGHT, Vector3.UP],
	]
	st.set_color(col)
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var o := at + n * h
		var uu := u * h
		var vv := v * h
		var a := o - uu - vv
		var b := o + uu - vv
		var cc := o + uu + vv
		var d := o - uu + vv
		# Wind each face so its front points along n (Godot treats clockwise
		# as front), flipping when u x v points the other way.
		var tri := [a, cc, b, a, d, cc] if u.cross(v).dot(n) < 0.0 else [a, b, cc, a, cc, d]
		st.set_normal(n)
		for p in tri:
			st.add_vertex(p)


## Body orientation for a disc with top `normal`, its local -Z along the
## airflow (keeps the frame steady; the disc is round, so yaw is cosmetic).
func _flight_basis(v: Vector3) -> Basis:
	var y := normal
	var f := v - y * v.dot(y)
	if f.length() < 1e-4:
		f = y.cross(Vector3.RIGHT) if absf(y.x) < 0.9 else y.cross(Vector3.BACK)
	var z := -f.normalized()
	var x := y.cross(z).normalized()
	return Basis(x, y, z)


func apply_aero(state: PhysicsDirectBodyState3D, v: Vector3) -> Vector3:
	if not flying:
		return v
	var dt := state.step
	if state.get_contact_count() > 0:
		_land("ground" if bark_hits == _hits0 else "trunk", state)
		return v
	if bark_hits > _hits0:
		_land("bark", state)
		return v
	if leaf_cells > 0:
		_land("leaves", state)
		return v
	if splashed:
		_land("water", state)
		return v
	var r: Array = model.step(v - wind, normal, omega, hand, dt)
	v += r[0] * dt
	normal = r[1]
	flight_time += dt
	var xf := state.transform
	xf.basis = _flight_basis(v)
	state.transform = xf
	state.angular_velocity = Vector3.ZERO
	return v


## Flight over: hand the disc to ordinary physics, keeping some real spin.
func _land(by: String, state: PhysicsDirectBodyState3D) -> void:
	flying = false
	landed_by = by
	flight_dist = distance()
	linear_damp_mode = RigidBody3D.DAMP_MODE_COMBINE
	linear_damp = 0.05
	can_sleep = true
	# Clockwise from above for a RH backhand = negative about the top face.
	state.angular_velocity = normal * -hand * minf(omega, LANDED_SPIN_MAX)


func start_collect(target: Node3D) -> void:
	flying = false
	super.start_collect(target)


func _process(delta: float) -> void:
	if flying and _spin_node != null:
		_spin_angle -= hand * minf(omega, VISUAL_SPIN_MAX) * delta
		_spin_node.rotation.y = _spin_angle


func _physics_process(delta: float) -> void:
	if flying:
		# Never call it resting mid-air (e.g. at the top of a lob).
		if global_position.y < -30.0:
			queue_free()
		return
	super._physics_process(delta)
