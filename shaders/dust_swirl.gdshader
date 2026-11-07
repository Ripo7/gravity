shader_type spatial;
// The body of a black hole's storm: a disc of dust whose spiral arms wind
// into the core, darker and clumpy at the edge, glowing violet near the core.
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;

uniform vec3 dust : source_color = vec3(0.58, 0.52, 0.46);
uniform vec3 violet : source_color = vec3(0.55, 0.24, 1.0);
uniform float inner = 0.18;     // the core's edge, in disc radius units
uniform float intensity = 1.0;
uniform float turn = 0.0;       // how far it has turned (radians)

varying vec2 p;

float hash(vec2 q) {
	return fract(sin(dot(q, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 q) {
	vec2 i = floor(q);
	vec2 f = fract(q);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

vec2 turned(vec2 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(v.x * c - v.y * s, v.x * s + v.y * c);
}

void vertex() {
	p = VERTEX.xz * 2.0;  // unit disc (CylinderMesh radius 0.5)
}

void fragment() {
	float r = length(p);
	if (r > 1.0 || r < inner * 0.7) {
		discard;
	}
	float a = atan(p.y, p.x);
	// Three arms on a log spiral: as it turns they seem to flow inward.
	float arms = sin(a * 3.0 + log(r) * 6.5 + turn * 3.0);
	float band = smoothstep(-0.35, 0.85, arms);
	// Clumps carried round with the arms (no seam: noise in a turning frame).
	float clump = noise(turned(p, turn) * 5.0) * 0.65 + noise(turned(p, turn * 1.8) * 11.0) * 0.35;
	float t = clamp((r - inner) / (1.0 - inner), 0.0, 1.0);
	float edge = smoothstep(1.0, 0.65, r) * smoothstep(0.0, 0.08, t);
	float dens = band * (0.3 + 0.95 * clump) * edge;
	float hot = pow(1.0 - t, 3.0);
	ALBEDO = mix(dust * (0.75 + 0.35 * clump), violet * 1.6, hot);
	ALPHA = clamp(dens * intensity * (0.7 + 0.5 * hot), 0.0, 0.85);
}
