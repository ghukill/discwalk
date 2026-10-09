shader_type spatial;
// Shading for greedy-meshed voxels (terrain + trees).
//
// A merged quad can cover many blocks, so per-block colour variation is done
// here instead of in the vertex colours:
//   COLOR.rgb = base colour (sRGB), COLOR.a = jitter strength (0..1).
// Each pixel finds the block it belongs to (step half a block back along the
// face normal, then floor), hashes that block's integer coordinates, and
// darkens the base colour by hash * strength. Mesh vertices are in block
// units (the MeshInstance is scaled to metres), so this works at any
// block size.

varying vec3 cell_pos;

void vertex() {
	cell_pos = VERTEX - NORMAL * 0.5;
}

float block_hash(vec3 p) {
	ivec3 c = ivec3(floor(p));
	uint h = (uint(c.x) * 73856093u) ^ (uint(c.y) * 19349663u) ^ (uint(c.z) * 83492791u);
	h ^= h >> 13u;
	h *= 1274126177u;
	h ^= h >> 16u;
	return float(h & 1023u) / 1023.0;
}

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

void fragment() {
	float j = block_hash(cell_pos);
	vec3 c = COLOR.rgb * (1.0 - j * COLOR.a);
	ALBEDO = srgb_to_linear(c);
	ROUGHNESS = 1.0;
}
