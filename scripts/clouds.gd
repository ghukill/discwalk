extends Node3D
## Fluffy voxel clouds drifting slowly, high above the world.
##
## A dozen or so clouds, each a little heap of chunky 2 m blocks: a few
## overlapping squashed blobs on a flat-ish base, so they read as cumulus
## puffs. White on top, a touch of blue-grey underneath. They drift with
## `drift` (m/s, horizontal) and wrap around a box a bit larger than the world,
## so they slide in from one edge and out the other. They cast faint moving
## shadows (when they're within the sun's shadow range).
##
## Deterministic from the world seed; rebuilt with each new world.
## K toggles them (thrower/main), `enabled` starts true.

const CELL := 2.0                    ## Cloud block size (m).
const TOP := Color(1.0, 1.0, 1.0)
const SIDE := Color(0.93, 0.95, 0.98)
const UNDER := Color(0.78, 0.82, 0.88)

@export var count := 11
@export var height_min := 70.0       ## Cloud base altitude range (m).
@export var height_max := 95.0
@export var drift := Vector2(1.1, 0.35)   ## m/s. The future wind can drive this.
@export var margin := 120.0          ## Wrap box extends this far past the world.

var world_size := 256.0
var _clouds: Array[MeshInstance3D] = []
var _material: StandardMaterial3D


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 1.0
	_material.metallic_specular = 0.0
	# Mostly lit by the sky: never goes dark grey on the shady side.
	_material.emission_enabled = true
	_material.emission = Color(0.55, 0.58, 0.62)
	_material.emission_energy_multiplier = 0.35


## (Re)build every cloud from `seed`.
func generate(seed: int, size_m: float) -> void:
	world_size = size_m
	for c in _clouds:
		c.queue_free()
	_clouds.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed * 7919 + 17)
	for i in count:
		var mi := MeshInstance3D.new()
		mi.mesh = _cloud_mesh(rng)
		mi.material_override = _material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.position = Vector3(
			rng.randf_range(-margin, world_size + margin),
			rng.randf_range(height_min, height_max),
			rng.randf_range(-margin, world_size + margin))
		add_child(mi)
		_clouds.append(mi)


func _process(delta: float) -> void:
	var lo := -margin
	var span := world_size + margin * 2.0
	for c in _clouds:
		var p := c.position
		p.x = lo + fposmod(p.x + drift.x * delta - lo, span)
		p.z = lo + fposmod(p.z + drift.y * delta - lo, span)
		c.position = p


## One cloud: 3-6 squashed blobs on a voxel grid, bottom flattened, then only
## the exposed block faces are meshed.
func _cloud_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var cells := {}
	var blobs := rng.randi_range(3, 6)
	var length := rng.randf_range(14.0, 30.0)          # m, along x
	var width := length * rng.randf_range(0.45, 0.8)    # m, along z
	for b in blobs:
		var c := Vector3(rng.randf_range(-length, length) * 0.5, 0.0,
			rng.randf_range(-width, width) * 0.5)
		# Middle blobs are bigger and taller: a heap, not a slab.
		var central := 1.0 - clampf(absf(c.x) / (length * 0.5 + 0.01), 0.0, 1.0)
		var rx := rng.randf_range(6.0, 10.0) * (0.7 + 0.5 * central)
		var rz := rx * rng.randf_range(0.6, 0.9)
		var ry := rng.randf_range(4.0, 6.5) * (0.6 + 0.6 * central)
		for ix in range(floori((c.x - rx) / CELL), ceili((c.x + rx) / CELL) + 1):
			for iz in range(floori((c.z - rz) / CELL), ceili((c.z + rz) / CELL) + 1):
				for iy in range(0, ceili(ry / CELL) + 1):
					var p := Vector3((ix + 0.5) * CELL, (iy + 0.5) * CELL, (iz + 0.5) * CELL)
					var d := Vector3((p.x - c.x) / rx, p.y / ry, (p.z - c.z) / rz)
					# A little noise on the surface so edges aren't perfect.
					if d.length() < 1.0 + rng.randf_range(-0.12, 0.08):
						cells[Vector3i(ix, iy, iz)] = true
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dirs := [Vector3i.UP, Vector3i.DOWN, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]
	for cell: Vector3i in cells:
		for d: Vector3i in dirs:
			if cells.has(cell + d):
				continue
			_face(st, cell, d)
	return st.commit()


func _face(st: SurfaceTool, cell: Vector3i, d: Vector3i) -> void:
	var n := Vector3(d)
	var centre := (Vector3(cell) + Vector3(0.5, 0.5, 0.5)) * CELL + n * CELL * 0.5
	var u := Vector3.RIGHT if absf(n.x) < 0.5 else Vector3.BACK
	var v := n.cross(u)
	u *= CELL * 0.5
	v *= CELL * 0.5
	var a := centre - u - v
	var b := centre + u - v
	var c := centre + u + v
	var e := centre - u + v
	var col := TOP if d == Vector3i.UP else (UNDER if d == Vector3i.DOWN else SIDE)
	# Sides shade toward the base, so each puff has a soft belly.
	if d != Vector3i.UP and d != Vector3i.DOWN and cell.y == 0:
		col = SIDE.lerp(UNDER, 0.5)
	st.set_color(col)
	st.set_normal(n)
	# Front face points along n (clockwise winding seen from outside).
	var tri := [a, c, b, a, e, c] if u.cross(v).dot(n) > 0.0 else [a, b, c, a, c, e]
	for p in tri:
		st.add_vertex(p)
