shader_type spatial;
// Rubble heaps (RubbleField): a grid of 8 m tiles whose vertices are lifted
// to the rubble's height there (a texture of heights, a point a metre);
// where there is none the surface hides under the floor. The stones and the
// gravel are drawn here, cells of two sizes lit and shaded one by one, in
// the colour of what broke (a second texture, mixed as it piled up).

uniform sampler2D heights : filter_nearest;
uniform sampler2D colors : source_color, filter_linear;
// Origin (x, z) of the grid, metres between points, points along a side.
uniform vec4 field = vec4(-52.0, -52.0, 1.0, 105.0);
uniform float empty = -0.3;
uniform float thin = 0.004;
uniform vec3 dust : source_color = vec3(0.8, 0.76, 0.7);

varying vec3 world_p;
varying float depth;

float h_at(ivec2 g) {
	g = clamp(g, ivec2(0), ivec2(int(field.w) - 1));
	return texelFetch(heights, g, 0).r;
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	ivec2 g = ivec2(round((w.xz - field.xy) / field.z));
	float h = h_at(g);
	float l = max(h_at(g - ivec2(1, 0)), 0.0);
	float r = max(h_at(g + ivec2(1, 0)), 0.0);
	float d = max(h_at(g - ivec2(0, 1)), 0.0);
	float u = max(h_at(g + ivec2(0, 1)), 0.0);
	VERTEX.y = h >= thin ? h : empty;
	NORMAL = normalize(vec3(l - r, 2.0 * field.z, d - u));
	world_p = vec3(w.x, VERTEX.y, w.z);
	depth = max(h, 0.0);
}

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash2(i).x;
	float b = hash2(i + vec2(1.0, 0.0)).x;
	float c = hash2(i + vec2(0.0, 1.0)).x;
	float d = hash2(i + vec2(1.0, 1.0)).x;
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// The stone nearest to p in a jittered grid: distance to its middle (x), to
// the next stone's (y), its random id (z); `to_mid` the way to its middle.
vec3 stones(vec2 p, out vec2 to_mid) {
	vec2 n = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	float id = 0.0;
	to_mid = vec2(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 r = g + hash2(n + g) - f;
			float d = dot(r, r);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				to_mid = r;
				id = hash2(n + g + 17.0).x;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return vec3(sqrt(d1), sqrt(d2), id);
}

void fragment() {
	vec3 base = texture(colors, ((world_p.xz - field.xy) / field.z + 0.5) / field.w).rgb;
	// On a slope the pattern rides on the height too, so it does not stretch.
	vec2 p = world_p.xz + vec2(world_p.y * 0.55, -world_p.y * 0.45);
	// Patches of big stones and of smaller rubble.
	float big_here = smoothstep(0.3, 0.7, noise2(p * 0.35 + 5.1));
	vec2 to_big;
	vec2 to_small;
	vec3 big = stones(p * 1.9, to_big);
	vec3 small = stones(p * 5.2 + 3.7, to_small);
	vec3 st = big_here > 0.5 ? big : small;
	vec2 to_mid = (big_here > 0.5 ? to_big : to_small);
	// The gaps between stones (where the next stone is about as near) hold
	// shadow; the stones themselves are flat-ish, each its own shade.
	float gap = 1.0 - smoothstep(0.0, big_here > 0.5 ? 0.12 : 0.09, st.y - st.x);
	vec3 col = base * (0.74 + 0.42 * st.z) * (0.92 + 0.16 * noise2(p * 9.0));
	col = mix(col, dust, step(0.88, st.z) * 0.4);  // a dusty stone now and then
	col *= 1.0 - gap * 0.5;
	// The thin edge of a heap: grit and dust over the paving.
	float grit = 1.0 - smoothstep(0.2, 0.7, small.x);
	col = mix(dust * 0.78 * (0.85 + 0.3 * grit), col, smoothstep(thin, 0.18, depth));
	// Each stone bulges a little: its normal leans away from its middle.
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec2 lean = -to_mid * (big_here > 0.5 ? 0.7 : 0.45) * (1.0 - gap);
	n = normalize(n + vec3(lean.x, 0.0, lean.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ALBEDO = col;
	ROUGHNESS = 0.96;
	SPECULAR = 0.3;
	AO = 1.0 - gap * 0.45;
	AO_LIGHT_AFFECT = 0.25;
}
