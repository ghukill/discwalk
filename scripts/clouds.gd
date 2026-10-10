extends Node3D
## Fluffy voxel clouds drifting slowly, high above the world.
##
## A dozen or so clouds, each a little heap of chunky 2 m blocks: a few
## overlapping round blobs (bellies rounded too, a bit flatter than the tops)
## so they read as comically fluffy puffs. White on top, a touch of
## blue-grey underneath.
##
## Altitudes: the `low_count` lowest are small, dreamy puffs drifting just
## ~20-30 m over the tallest treetop; the rest step up evenly (with jitter)
## from there to `height_max`. They drift with
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
@export var low_count := 3           ## Low, close, smaller puffs.
@export var low_above_trees := Vector2(18.0, 30.0)   ## m over the canopy top.
@export var low_scale := 0.6         ## Low puffs are this size.
@export var height_max := 110.0      ## The highest cloud's altitude (m).
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


## (Re)build every cloud from `seed`. `canopy` = top of the tallest tree (m).
func generate(seed: int, size_m: float, canopy := 40.0) -> void:
	world_size = size_m
	for c in _clouds:
		c.queue_free()
	_clouds.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed * 7919 + 17)
	var low_top := canopy + low_above_trees.y
	for i in count:
		var low := i < low_count
		var y: float
		if low:
			y = canopy + rng.randf_range(low_above_trees.x, low_above_trees.y)
		else:
			# Evenly stepped from just above the low puffs to height_max.
			var k := float(i - low_count + 1) / float(maxi(count - low_count, 1))
			y = lerpf(low_top + 8.0, height_max, k) + rng.randf_range(-4.0, 4.0)
		var mi := MeshInstance3D.new()
		mi.mesh = _cloud_mesh(rng, low_scale if low else 1.0)
		mi.material_override = _material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		# Low puffs start over the world (so you meet them early); the rest anywhere.
		var spread := 0.0 if low else margin
		mi.position = Vector3(
			rng.randf_range(-spread, world_size + spread), y,
			rng.randf_range(-spread, world_size + spread))
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


## One cloud: 3-6 round blobs on a voxel grid (rounded bellies, a little
## flatter than the tops), then only the exposed block faces are meshed.
func _cloud_mesh(rng: RandomNumberGenerator, scale := 1.0) -> ArrayMesh:
	var cells := {}
	var blobs := rng.randi_range(3, 6)
	var length := rng.randf_range(14.0, 30.0) * scale   # m, along x
	var width := length * rng.randf_range(0.45, 0.8)    # m, along z
	for b in blobs:
		var c := Vector3(rng.randf_range(-length, length) * 0.5, 0.0,
			rng.randf_range(-width, width) * 0.5)
		# Middle blobs are bigger and taller: a heap, not a slab.
		var central := 1.0 - clampf(absf(c.x) / (length * 0.5 + 0.01), 0.0, 1.0)
		var rx := rng.randf_range(6.0, 10.0) * (0.7 + 0.5 * central) * scale
		var rz := rx * rng.randf_range(0.7, 0.95)
		var ry := rng.randf_range(4.5, 7.0) * (0.6 + 0.6 * central) * scale
		var ry_down := ry * 0.6                          # rounded belly, a bit flatter
		c.y = rng.randf_range(-0.5, 1.5) * scale         # puffs at slightly different heights
		for ix in range(floori((c.x - rx) / CELL), ceili((c.x + rx) / CELL) + 1):
			for iz in range(floori((c.z - rz) / CELL), ceili((c.z + rz) / CELL) + 1):
				for iy in range(floori((c.y - ry_down) / CELL), ceili((c.y + ry) / CELL) + 1):
					var p := Vector3((ix + 0.5) * CELL, (iy + 0.5) * CELL, (iz + 0.5) * CELL)
					var dy := p.y - c.y
					var d := Vector3((p.x - c.x) / rx, dy / (ry if dy > 0.0 else ry_down), (p.z - c.z) / rz)
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
	# Sides shade toward the belly.
	if d != Vector3i.UP and d != Vector3i.DOWN and cell.y < 0:
		col = SIDE.lerp(UNDER, 0.5)
	st.set_color(col)
	st.set_normal(n)
	# Front face points along n (clockwise winding seen from outside).
	var tri := [a, c, b, a, e, c] if u.cross(v).dot(n) > 0.0 else [a, b, c, a, c, e]
	for p in tri:
		st.add_vertex(p)
