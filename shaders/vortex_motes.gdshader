shader_type spatial;
render_mode skip_vertex_transform, unshaded, cull_disabled, shadows_disabled, depth_draw_never;
// Specks of dust a black hole draws in: each comes in from around the edge
// of the storm and winds in along a spiral, faster and faster, glowing as it
// nears the core, then starts again on a new path. All the motion is worked
// out here: the motes cost no script time. Per mote (one MultiMesh
// instance, a camera-facing quad): INSTANCE_CUSTOM holds four random numbers.

uniform float now = 0.0;       // seconds since the hole opened
uniform float radius = 5.0;    // where the motes come from
uniform float core = 0.9;      // where they vanish
uniform float amount = 1.0;    // share of the motes that show (it opens: 0 -> 1)
uniform float collapse = 0.0;  // it closes: the whole swirl is drawn into the core
uniform vec3 dust : source_color = vec3(0.5, 0.45, 0.4);
uniform vec3 hot : source_color = vec3(0.85, 0.65, 1.0);

varying vec4 col;

float hash(float n) {
	return fract(sin(n * 12.9898 + 4.1414) * 43758.5453);
}

// Where a mote on a path from radius `r0`, angle `a0`, height `h0` is
// when it has come `u` of the way in (0 .. 1).
vec3 path(float r0, float a0, float h0, float u) {
	// Slow at first, then rushing in, winding faster as it nears the core.
	float k = pow(u, 1.7);
	float r = mix(r0, core * 0.85, k) * (1.0 - collapse * collapse);
	float a = a0 - 6.2832 * (0.3 * u + 1.1 * k * k);
	return vec3(cos(a) * r, h0 * (1.0 - k), sin(a) * r);
}

void vertex() {
	vec4 rnd = INSTANCE_CUSTOM;
	float life = mix(1.1, 2.1, rnd.x);
	float t = now + rnd.y * life;  // staggered, so they never come in waves
	float cycle = floor(t / life);
	float u = fract(t / life);  // 0 comes in .. 1 swallowed
	float seed = hash(rnd.z * 91.7 + cycle * 17.3);
	float seed2 = hash(rnd.w * 53.1 + cycle * 7.9);
	float r0 = radius * mix(0.7, 1.25, seed);
	float a0 = seed2 * 6.2832;
	float h0 = (seed - 0.5) * 2.6 * (r0 / radius);
	float k = pow(u, 1.7);
	vec3 here = (VIEW_MATRIX * MODEL_MATRIX * vec4(path(r0, a0, h0, u), 1.0)).xyz;
	vec3 back = (VIEW_MATRIX * MODEL_MATRIX * vec4(path(r0, a0, h0, max(u - 0.05, 0.0)), 1.0)).xyz;
	// A streak along the way it moves: it reads as a swirl, not as dots.
	vec2 trail = here.xy - back.xy;
	float len = length(trail);
	vec2 along = len > 1e-4 ? trail / len : vec2(1.0, 0.0);
	vec2 across = vec2(-along.y, along.x);
	float size = mix(0.3, 0.12, k) * (0.6 + 0.8 * rnd.w);
	// Never thinner than about two pixels: far away the swirl still reads.
	float pixel = 2.0 * max(-here.z, 0.1) / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	size = max(size, pixel * 2.0);
	vec2 offset = along * VERTEX.x * (size + len * 1.5) + across * VERTEX.y * size;
	VERTEX = here + vec3(offset - along * len * 0.75, 0.0);
	float shown = step(rnd.z, amount);
	float a_in = smoothstep(0.0, 0.15, u) * (1.0 - smoothstep(0.88, 1.0, u));
	col = vec4(mix(dust, hot * 1.8, k * k), a_in * shown * mix(0.7, 1.0, k));
}

void fragment() {
	vec2 c = (UV - 0.5) * 2.0;
	ALBEDO = col.rgb;
	ALPHA = col.a * (1.0 - smoothstep(0.3, 1.0, length(c * vec2(0.8, 1.0))));
}
