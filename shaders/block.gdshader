shader_type spatial;
// Every block and piece of debris, all materials, in one draw call.
// Per-instance COLOR: r = shade, g = material (0 / 0.5 / 1, see materials.gd),
// b = random seed, a = violet glow from the power.
// Patterns are procedural in the block's own space (scaled to metres), so
// they stay put on moving debris and need no textures.

uniform vec3 violet : source_color = vec3(0.55, 0.24, 1.0);
uniform vec3 violet_deep : source_color = vec3(0.32, 0.08, 0.78);
uniform float glow_strength = 0.9;

uniform vec3 concrete : source_color = vec3(0.78, 0.76, 0.72);
uniform vec3 wood : source_color = vec3(0.78, 0.58, 0.38);
uniform vec3 wood_dark : source_color = vec3(0.55, 0.36, 0.2);
uniform vec3 metal : source_color = vec3(0.62, 0.66, 0.72);

varying vec3 local_pos;   // metres, centred on the block
varying vec3 half_size;   // metres
varying vec3 local_normal;
varying float shade;
varying float material_id;
varying float seed;
varying float tint;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
				mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
				mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	local_pos = VERTEX * scale;
	half_size = scale * 0.5;
	local_normal = NORMAL;
	shade = COLOR.r;
	material_id = COLOR.g < 0.1 ? 0.0 : (COLOR.g < 0.6 ? 1.0 : 2.0);
	seed = COLOR.b;
	tint = COLOR.a;
}

void fragment() {
	vec3 p = local_pos + seed * 37.0;
	vec3 albedo;
	float rough;
	float metallic = 0.0;

	if (material_id < 0.5) {
		// Concrete: mottled, with small dark pores.
		float m = fbm(p * 2.2);
		float pores = step(0.82, noise(p * 26.0)) * 0.12;
		albedo = concrete * (0.86 + 0.22 * m - pores);
		rough = 0.92;
	} else if (material_id < 1.5) {
		// Wood: grain runs along the block's longest axis.
		vec3 hs = half_size;
		vec3 q = p;
		if (hs.y >= hs.x && hs.y >= hs.z) {
			q = p.yzx;
		} else if (hs.z >= hs.x) {
			q = p.zxy;
		}
		float warp = fbm(vec3(q.x * 0.6, q.y * 3.0, q.z * 3.0)) * 2.5;
		float rings = sin((q.y * 9.0 + q.z * 5.0 + warp) * 6.2831) * 0.5 + 0.5;
		rings = smoothstep(0.2, 0.9, rings);
		float streak = noise(vec3(q.x * 0.8, q.y * 40.0, q.z * 40.0));
		albedo = mix(wood, wood_dark, rings * 0.55 + streak * 0.2);
		rough = 0.75;
	} else {
		// Metal: brushed steel along the longest axis, slight panel tint.
		vec3 hs = half_size;
		float along = hs.x >= hs.z ? p.x : p.z;
		float across = hs.x >= hs.z ? p.z + p.y : p.x + p.y;
		float brush = noise(vec3(along * 1.5, across * 90.0, 0.0));
		albedo = metal * (0.88 + 0.16 * brush + 0.06 * fbm(p * 0.8));
		rough = 0.32 + 0.18 * brush;
		metallic = 0.65;
	}

	// Soft darkening near block edges: reads as a bevel / contact shadow.
	vec3 d = half_size - abs(local_pos);
	vec3 face = abs(local_normal);
	float edge_dist = 10.0;
	if (face.x < 0.5) { edge_dist = min(edge_dist, d.x); }
	if (face.y < 0.5) { edge_dist = min(edge_dist, d.y); }
	if (face.z < 0.5) { edge_dist = min(edge_dist, d.z); }
	float edge = 1.0 - smoothstep(0.0, 0.05, edge_dist);
	albedo *= 1.0 - edge * 0.22;

	albedo *= shade;
	float t = clamp(tint, 0.0, 1.0);
	ALBEDO = mix(albedo, violet_deep, t * 0.9);
	ROUGHNESS = rough;
	METALLIC = metallic * (1.0 - t);
	EMISSION = violet * t * t * t * glow_strength;
}
