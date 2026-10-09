extends RefCounted
## Shared helpers for building voxel meshes with greedy face merging.
##
## Greedy meshing: instead of one quad per visible block face, neighbouring
## faces that are coplanar, face the same way and share a base colour are
## merged into one bigger rectangle. Flat ground at fine block sizes collapses
## from thousands of quads into a handful.
##
## Per-block colour variation (the subtle "jitter" that makes blocks read as
## blocks) can't be baked into vertex colours any more, because a merged quad
## spans many blocks. Instead the vertex colour carries the BASE colour in rgb
## and the jitter STRENGTH in alpha, and shaders/voxel.gdshader works out
## which block each pixel belongs to and darkens it by a per-block hash.
##
## Merging works on "rows": for one plane (slice) of faces, faces are grouped
## by their v coordinate, and each face is packed into an int as
## (u << 20) | colour_id. merge_rows() first joins runs of adjacent faces along
## u, then stacks identical runs (same u0, u1, colour) on consecutive rows into
## rectangles. It's not the theoretical minimum, but it's close in practice,
## and it's linear in the number of faces.

const U_SHIFT := 20
const CID_MASK := (1 << 20) - 1

const SHADER := preload("res://shaders/voxel.gdshader")


## Packs a face for merge_rows(). u must be < 2048, cid < 2^20.
static func face(u: int, cid: int) -> int:
	return (u << U_SHIFT) | cid


## rows: Dictionary { v (int) -> Array of face(u, cid) ints }.
## Returns a flat PackedInt32Array of rectangles: u0, v0, u1, v1, cid, ...
## (u1 and v1 are exclusive).
static func merge_rows(rows: Dictionary) -> PackedInt32Array:
	var out := PackedInt32Array()
	var vs := rows.keys()
	vs.sort()
	var open := {}                      # Vector3i(u0, u1, cid) -> v0
	var prev_v: int = -1000000000
	for v: int in vs:
		var arr: Array = rows[v]
		arr.sort()
		var cur := {}
		var contiguous: bool = v == prev_v + 1
		var i := 0
		var n: int = arr.size()
		while i < n:
			var f: int = arr[i]
			var u0 := f >> U_SHIFT
			var cid := f & CID_MASK
			var u1 := u0 + 1
			i += 1
			while i < n:
				var g: int = arr[i]
				var gu := g >> U_SHIFT
				if gu < u1:              # duplicate face, skip
					i += 1
					continue
				if gu != u1 or (g & CID_MASK) != cid:
					break
				u1 += 1
				i += 1
			var k := Vector3i(u0, u1, cid)
			if contiguous and open.has(k):
				cur[k] = open[k]
				open.erase(k)
			else:
				cur[k] = v
		for k: Vector3i in open:
			out.append_array([k.x, open[k], k.y, prev_v + 1, k.z])
		open = cur
		prev_v = v
	for k: Vector3i in open:
		out.append_array([k.x, open[k], k.y, prev_v + 1, k.z])
	return out


## Appends one quad (two triangles) with origin o and edges eu, ev, wound so
## it faces along n (Godot treats clockwise triangles as front-facing).
static func add_quad(verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, o: Vector3, eu: Vector3, ev: Vector3, n: Vector3,
		col: Color) -> void:
	if ev.cross(eu).dot(n) < 0.0:
		var t := eu
		eu = ev
		ev = t
	verts.append(o)
	verts.append(o + eu)
	verts.append(o + ev)
	verts.append(o + eu)
	verts.append(o + eu + ev)
	verts.append(o + ev)
	for i in 6:
		normals.append(n)
		colors.append(col)


static func build_mesh(verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Material for greedy voxel meshes (vertex rgb = base sRGB colour,
## alpha = per-block jitter strength).
static func make_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	return m
