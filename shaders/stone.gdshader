shader_type spatial;
// Meteor stones from the portal: dark basalt facets with glowing violet
// rune-like veins that dim after the stone lands.

uniform vec3 rock : source_color = vec3(0.1, 0.09, 0.12);
uniform vec3 violet : source_color = vec3(0.55, 0.24, 1.0);
uniform float glow = 1.0;  // 1 while falling, fades after impact
uniform float seed = 0.0;

varying vec3 obj;

vec2 hash22(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

float cell_edge(vec2 x) {
	vec2 n = floor(x);
	vec2 f = fract(x);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 r = g + hash22(n + g) - f;
			float d = dot(r, r);
			if (d < d1) {
				d2 = d1;
				d1 = d;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return sqrt(d2) - sqrt(d1);
}

void vertex() {
	obj = VERTEX;
}

void fragment() {
	vec3 n = abs(NORMAL);
	vec2 uv = obj.xy * 1.3 + obj.zx * 0.7 + seed * 13.0;
	float e = cell_edge(uv * 1.7);
	float vein = 1.0 - smoothstep(0.0, 0.07, e);
	float grain = fract(sin(dot(floor(obj * 9.0), vec3(12.9, 78.2, 37.7))) * 43758.5);
	ALBEDO = rock * (0.85 + 0.3 * grain);
	ROUGHNESS = 0.7;
	SPECULAR = 0.3;
	EMISSION = violet * vein * (0.35 + 1.8 * glow);
}
