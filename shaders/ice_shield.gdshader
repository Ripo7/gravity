shader_type spatial;
// Black ice shield: glassy near-black slab with violet veins, a soft violet
// edge glow, and cracks that spread as it takes hits.

uniform vec3 ice : source_color = vec3(0.03, 0.025, 0.05);
uniform vec3 violet : source_color = vec3(0.55, 0.24, 1.0);
uniform float damage = 0.0;
uniform float flash = 0.0;
uniform vec3 size = vec3(4.0, 3.0, 0.7);

varying vec3 lp;

vec2 hash22(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

float edge(vec2 x) {
	vec2 n = floor(x);
	vec2 f = fract(x);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 r = g + hash22(n + g) - f;
			float d = dot(r, r);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	return sqrt(d2) - sqrt(d1);
}

void vertex() {
	lp = VERTEX * size;
}

void fragment() {
	vec2 uv = lp.xy;
	float veins = 1.0 - smoothstep(0.0, 0.04, edge(uv * 1.4));
	float cracks = (1.0 - smoothstep(0.0, 0.02 + 0.03 * damage, edge(uv * 3.5 + 7.0))) * step(0.15, damage);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = ice;
	ROUGHNESS = 0.06;
	METALLIC = 0.4;
	SPECULAR = 0.9;
	EMISSION = violet * (veins * 0.35 + fres * 0.6 + cracks * (0.6 + damage) + flash * 1.5);
	ALPHA = clamp(0.62 + fres * 0.35 + veins * 0.2 + cracks * 0.3 + damage * 0.15, 0.0, 1.0);
}
