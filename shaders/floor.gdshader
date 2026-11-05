shader_type spatial;
// The square round the palace: pietra serena flagstones in running bond,
// travertine bands every 12 m, a travertine kerb round each building and
// round the square. Beyond the square, a bare plain of beaten earth that
// fades into the haze. Joints fade with distance (no shimmer on phones).

uniform vec3 stone : source_color = vec3(0.56, 0.54, 0.5);
uniform vec3 travertine : source_color = vec3(0.8, 0.74, 0.62);
uniform vec3 joint : source_color = vec3(0.32, 0.3, 0.28);
uniform vec3 earth : source_color = vec3(0.56, 0.5, 0.43);
// Set by GameWorld from the level: the square's half size (Arena.inner),
// where the band grid starts (the palace portal) and the building
// footprints (min x, min z, max x, max z).
uniform float square_half = 1e6;
uniform vec2 grid_origin = vec2(0.0);
uniform vec4 plinths[4];
uniform int plinth_count = 0;

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

// 1 within w metres of a line, d the distance to it; fw is the pixel size.
float near(float d, float w, float fw) {
	return 1.0 - smoothstep(w - fw, w + fw, d);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float fw = length(fwidth(p));  // metres per pixel
	float detail = clamp(1.0 - fw * 10.0, 0.0, 1.0);  // joints fade out far away
	float big = noise2(p * 0.045) * 0.6 + noise2(p * 0.21) * 0.4;  // weathering

	// Flagstones of 1.2 x 0.6 m, every other row shifted by half a stone.
	vec2 q = p / vec2(1.2, 0.6);
	float row = floor(q.y);
	q.x += 0.5 * mod(row, 2.0);
	vec2 cell = floor(q);
	vec2 f = fract(q);
	vec2 to_edge = min(f, 1.0 - f) * vec2(1.2, 0.6);
	float j = near(min(to_edge.x, to_edge.y), 0.008, fw) * detail;
	vec3 col = stone * (0.84 + 0.2 * hash2(cell)) * (0.92 + 0.14 * noise2(p * 3.1));
	col = mix(col, joint, j * 0.75);

	// Travertine: bands every 12 m, kerbs round the buildings and the square.
	vec2 g = abs(fract((p - grid_origin) / 12.0 + 0.5) - 0.5) * 12.0;
	float trav = near(min(g.x, g.y), 0.28, fw);
	for (int i = 0; i < 4; i++) {
		if (i >= plinth_count) {
			break;
		}
		vec2 out_of = max(plinths[i].xy - p, p - plinths[i].zw);
		trav = max(trav, near(max(out_of.x, out_of.y), 1.5, fw));
	}
	float edge = max(abs(p.x), abs(p.y)) - square_half;  // metres outside the square
	trav = max(trav, 1.0 - smoothstep(-1.4 - fw, -1.4 + fw, -edge));
	vec2 tf = abs(fract(p * vec2(1.0, 1.5) + 0.5) - 0.5) / vec2(1.0, 1.5);
	float tj = near(min(tf.x, tf.y), 0.006, fw) * detail;
	vec3 tcol = travertine * (0.9 + 0.12 * hash2(floor(p * vec2(1.0, 1.5)) + 7.0));
	tcol *= 0.93 + 0.1 * noise2(p * 1.9);
	col = mix(col, mix(tcol, joint, tj * 0.5), trav);

	// The plain beyond, a little darker right under the kerb.
	float plain = smoothstep(-fw, fw, edge);
	vec3 dirt = earth * (0.8 + 0.3 * big) * (0.94 + 0.1 * noise2(p * 2.7));
	dirt *= mix(0.78, 1.0, smoothstep(0.0, 0.8, edge));
	col = mix(col, dirt, plain);

	ALBEDO = col * (0.93 + 0.1 * big);
	ROUGHNESS = mix(mix(0.74, 0.62, trav), 0.95, plain);
	SPECULAR = 0.35;
}
