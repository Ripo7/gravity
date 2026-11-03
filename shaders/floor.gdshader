shader_type spatial;
// Light polished-concrete floor: 4 m slabs with seams, each slab a slightly
// different tone, soft mottling, and a faint 1 m scribe line for scale.

uniform vec3 base : source_color = vec3(0.74, 0.73, 0.71);
uniform vec3 seam : source_color = vec3(0.56, 0.56, 0.56);
uniform float slab = 4.0;
uniform float seam_width = 0.025;

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

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	vec2 cell = floor(p / slab);
	float tone = 0.9 + 0.14 * hash2(cell);
	float mottle = noise2(p * 0.7) * 0.6 + noise2(p * 3.1) * 0.4;
	vec3 col = base * tone * (0.88 + 0.16 * mottle);

	vec2 fw = fwidth(p) * 1.2;
	vec2 g = abs(fract(p / slab + 0.5) - 0.5) * slab;
	vec2 a = 1.0 - smoothstep(vec2(seam_width), vec2(seam_width) + fw, g);
	float s = max(a.x, a.y);
	vec2 g1 = abs(fract(p + 0.5) - 0.5);
	vec2 a1 = 1.0 - smoothstep(vec2(0.006), vec2(0.006) + fw, g1);
	float s1 = 0.0 * max(a1.x, a1.y);
	float fade = clamp(1.0 - length(fw) * 3.0, 0.0, 1.0);
	col = mix(col, seam, max(s, s1) * fade);

	ALBEDO = col;
	ROUGHNESS = 0.55 + 0.3 * mottle;
	SPECULAR = 0.4;
}
