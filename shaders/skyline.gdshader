shader_type spatial;
// The city around the playable district: painted towers with a grid of
// windows, some lit, melting into the haze. COLOR = facade colour,
// COLOR.a = random seed. One draw call, no textures.

uniform vec3 glass : source_color = vec3(0.24, 0.27, 0.34);
uniform vec3 lamp : source_color = vec3(1.0, 0.7, 0.42);
uniform float lit_share = 0.22;
uniform float floor_h = 3.2;
uniform float bay_w = 2.6;

varying vec3 world_pos;
varying vec3 world_normal;
varying vec4 tint;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	tint = COLOR;
}

void fragment() {
	vec3 col = tint.rgb;
	vec3 emit = vec3(0.0);
	if (abs(world_normal.y) < 0.5) {
		// Along the face: x or z, whichever the face spans.
		float u = abs(world_normal.x) > 0.5 ? world_pos.z : world_pos.x;
		vec2 cell = vec2(floor(u / bay_w), floor(world_pos.y / floor_h));
		vec2 f = vec2(fract(u / bay_w), fract(world_pos.y / floor_h));
		float win = step(0.18, f.x) * step(f.x, 0.82) * step(0.3, f.y) * step(f.y, 0.85);
		// No windows on the ground floor band, a few blind bays.
		win *= step(0.5, cell.y) * step(0.12, hash(vec3(cell, tint.a * 31.0)));
		float h = hash(vec3(cell * 1.7, tint.a * 57.0 + 3.0));
		col = mix(col, glass, win * 0.85);
		emit = lamp * win * step(h, lit_share) * (0.6 + 0.6 * fract(h * 41.0));
	} else {
		col *= 0.85;
	}
	ALBEDO = col;
	ROUGHNESS = 0.9;
	EMISSION = emit;
}
