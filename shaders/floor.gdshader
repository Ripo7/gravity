shader_type spatial;
// Imperial paving: 2 m slabs of warm marble, each its own tone, laid in
// 8 m squares framed by travertine bands with a thin bronze inlay. Lines
// fade with distance (no shimmer on phones).

uniform vec3 marble : source_color = vec3(0.86, 0.82, 0.75);
uniform vec3 band : source_color = vec3(0.74, 0.66, 0.54);
uniform vec3 bronze : source_color = vec3(0.72, 0.52, 0.26);
uniform vec3 joint : source_color = vec3(0.58, 0.55, 0.5);

varying vec3 world_pos;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1, 0)), f.x), mix(hash2(i + vec2(0, 1)), hash2(i + vec2(1, 1)), f.x), f.y);
}

// 1 on lines of half-width w (in cell units) at the integers of x and y.
float lines(vec2 x, float w) {
	vec2 fw = fwidth(x);
	vec2 d = abs(fract(x + 0.5) - 0.5);
	vec2 l = 1.0 - smoothstep(vec2(w) - fw, vec2(w) + fw, d);
	return max(l.x, l.y) * clamp(1.0 - length(fw) * 2.0, 0.0, 1.0);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	vec2 slab = floor(p / 2.0);
	float tone = 0.9 + 0.14 * hash2(slab);
	float vein = noise2(p * 0.6 + slab * 3.1) * 0.6 + noise2(p * 2.3) * 0.4;
	vec3 col = marble * tone * (0.9 + 0.12 * vein);
	// Travertine bands round each 8 m square, a bronze line in their middle.
	vec2 sq = abs(fract(p / 8.0 + 0.5) - 0.5) * 8.0;  // metres from the band centre
	float in_band = 1.0 - smoothstep(0.38, 0.42, min(sq.x, sq.y));
	col = mix(col, band * (0.92 + 0.1 * noise2(p * 1.7)), in_band);
	float inlay = lines(p / 8.0, 0.006);
	col = mix(col, bronze, inlay);
	// Joints between slabs (not across the bands).
	float j = lines(p / 2.0, 0.008) * (1.0 - in_band);
	col = mix(col, joint, j * 0.7);
	ALBEDO = col;
	ROUGHNESS = mix(0.45 + 0.25 * vein, 0.3, inlay);
	METALLIC = inlay * 0.8;
	SPECULAR = 0.45;
}
