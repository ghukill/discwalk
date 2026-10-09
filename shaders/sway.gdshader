shader_type spatial;
// Wind sway for small plants (flowers now, grass tufts later).
// Vertices bend more the higher they are above the plant's base (local y=0),
// and each plant gets its own phase from its world position, so a meadow
// ripples instead of marching in lockstep.
render_mode cull_disabled, specular_disabled;

uniform float sway_strength = 0.22;
uniform float sway_speed = 1.6;
uniform vec2 wind_dir = vec2(0.8, 0.6);

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float phase = origin.x * 0.23 + origin.z * 0.19;
	// Slow gusts rolling across the land + a quicker flutter.
	float gust = 0.6 + 0.4 * sin(TIME * 0.35 + origin.x * 0.03 + origin.z * 0.02);
	float s = sin(TIME * sway_speed + phase) * gust + 0.3 * sin(TIME * sway_speed * 2.7 + phase * 1.7);
	float bend = VERTEX.y * VERTEX.y * sway_strength * s;
	// Bend in world wind direction, converted into the instance's local space.
	vec3 world_off = vec3(wind_dir.x, 0.0, wind_dir.y) * bend;
	VERTEX += (inverse(mat3(MODEL_MATRIX)) * world_off);
}

void fragment() {
	// Vertex colours are authored in sRGB; lighting wants linear.
	vec3 c = COLOR.rgb;
	ALBEDO = mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
	ROUGHNESS = 1.0;
}
