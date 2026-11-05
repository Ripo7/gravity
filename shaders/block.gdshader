shader_type spatial;
// Every block and piece of debris, all materials, in one draw call.
// Per-instance COLOR: r = shade, g = unused,
// b = random seed, a = violet glow from the power.
// INSTANCE_CUSTOM.r = material kind + damage * 0.9 (cracks); .gba = where it was
// hit, in the block's unit space + 1 (0 = never hit): cracks spread from there.
// Patterns are procedural in the block's own space (scaled to metres), so
// they stay put on moving debris and need no textures.

uniform vec3 violet : source_color = vec3(0.55, 0.24, 1.0);
uniform vec3 violet_deep : source_color = vec3(0.32, 0.08, 0.78);
uniform float glow_strength = 0.9;
// Debris and chips: the unit box (subdivided once) is cut into an
// irregular faceted chunk, different for every piece.
uniform bool chunky = false;

uniform vec3 concrete : source_color = vec3(0.78, 0.76, 0.72);
uniform vec3 wood : source_color = vec3(0.84, 0.75, 0.62);
uniform vec3 wood_dark : source_color = vec3(0.68, 0.56, 0.43);
uniform vec3 metal : source_color = vec3(0.62, 0.66, 0.72);
uniform vec3 ice : source_color = vec3(0.035, 0.03, 0.06);
uniform vec3 glass : source_color = vec3(0.16, 0.2, 0.26);
uniform vec3 glass_sky : source_color = vec3(0.78, 0.85, 0.95);

varying vec3 local_pos;   // metres, centred on the block
varying vec3 half_size;   // metres
varying vec3 local_normal;
varying float shade;
varying float material_id;
varying float seed;
varying float tint;
varying float damage;
varying vec3 hit_at;  // metres in block space; x > 90 when never hit
varying float world_y;

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

// Cuts the corners and bends the edges of the unit box inward, by amounts
// that depend on the vertex position and the piece's seed. Shared corners
// move together, so the chunk stays closed; nothing grows past the box, so
// it never pokes through what it rests on.
vec3 chunk(vec3 v, float s) {
	vec3 a = abs(v) * 2.0;
	float k = a.x + a.y + a.z;  // 3 corner, 2 edge middle, 1 face centre
	vec3 h = vec3(hash(v * 7.13 + s * 31.7), hash(v * 3.71 + s * 17.3 + 5.0), hash(v * 5.27 + s * 11.9 + 9.0));
	float pull = k > 2.5 ? 0.16 + 0.34 * h.x : (k > 1.5 ? 0.03 + 0.17 * h.y : 0.02 * h.z);
	vec3 o = v * (1.0 - pull);
	o += (h - 0.5) * 0.1 * step(1.5, k);
	return clamp(o, vec3(-0.5), vec3(0.5));
}

void vertex() {
	if (chunky) {
		VERTEX = chunk(VERTEX, COLOR.b);
	}
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	local_pos = VERTEX * scale;
	half_size = scale * 0.5;
	local_normal = NORMAL;
	shade = COLOR.r;
	// Undo the sRGB->linear conversion applied to instance colours.
	// Material in the integer part of the first custom float, damage in
	// its fraction (see Materials.custom).
	material_id = floor(INSTANCE_CUSTOM.r + 0.001);
	seed = COLOR.b;
	tint = COLOR.a;
	damage = clamp(fract(INSTANCE_CUSTOM.r + 0.001) / 0.9, 0.0, 1.0);
	vec3 h = INSTANCE_CUSTOM.gba;
	hit_at = (h.x + h.y + h.z) > 0.0 ? (h - 1.0) * scale : vec3(99.0);
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

vec2 hash22(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// Distance to the nearest Voronoi cell edge, and that cell's random id.
vec2 voronoi_edge(vec2 x) {
	vec2 n = floor(x);
	vec2 f = fract(x);
	vec2 mg;
	vec2 mr;
	float md = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = hash22(n + g);
			vec2 r = g + o - f;
			float d = dot(r, r);
			if (d < md) {
				md = d;
				mr = r;
				mg = g;
			}
		}
	}
	md = 8.0;
	for (int j = -2; j <= 2; j++) {
		for (int i = -2; i <= 2; i++) {
			vec2 g = mg + vec2(float(i), float(j));
			vec2 o = hash22(n + g);
			vec2 r = g + o - f;
			if (dot(mr - r, mr - r) > 0.00001) {
				md = min(md, dot(0.5 * (mr + r), normalize(r - mr)));
			}
		}
	}
	return vec2(md, hash22(n + mg).x);
}

void fragment() {
	if (chunky) {
		// Flat facets: the face normal from screen-space derivatives.
		vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
		NORMAL = dot(n, VIEW) < 0.0 ? -n : n;
	}
	vec3 p = local_pos + seed * 37.0;
	vec3 albedo;
	vec3 face = abs(local_normal);
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
	} else if (material_id > 3.5) {
		// Window glass: dark, smooth, the sky reflected at grazing angles
		// and a soft vertical sheen. Opaque, so it costs nothing extra.
		float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
		float sheen = smoothstep(0.2, 0.9, fract(local_pos.y * 0.35 + local_pos.x * 0.12 + seed));
		albedo = mix(glass, glass_sky, clamp(fres * 0.85 + sheen * 0.12, 0.0, 1.0));
		rough = 0.04;
		metallic = 0.1;
	} else if (material_id > 2.5) {
		// Black ice: glassy near-black with faint violet veins inside.
		vec2 e = voronoi_edge((face.x > 0.5 ? local_pos.yz : (face.y > 0.5 ? local_pos.xz : local_pos.xy)) * 1.6 + seed * 7.0);
		float vein = 1.0 - smoothstep(0.0, 0.05, e.x);
		albedo = ice + violet * vein * 0.18;
		rough = 0.08 + 0.1 * fbm(p * 1.5);
		metallic = 0.35;
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
	float edge_dist = 10.0;
	if (face.x < 0.5) { edge_dist = min(edge_dist, d.x); }
	if (face.y < 0.5) { edge_dist = min(edge_dist, d.y); }
	if (face.z < 0.5) { edge_dist = min(edge_dist, d.z); }
	float edge = 1.0 - smoothstep(0.0, 0.05, edge_dist);
	albedo *= 1.0 - edge * 0.22;

	// Cracks: they start where the block was hit and spread out across it
	// as damage grows; the surface around the hit is chipped and darker.
	if (damage > 0.02) {
		vec2 uv = face.x > 0.5 ? local_pos.yz : (face.y > 0.5 ? local_pos.xz : local_pos.xy);
		vec2 e = voronoi_edge(uv * 3.2 + seed * 11.0);
		float shown;
		float near = 0.0;
		if (hit_at.x < 90.0) {
			float d = distance(local_pos, hit_at);
			float reach = damage * (0.6 + 2.2 * length(half_size)) * (0.75 + 0.5 * noise(local_pos * 3.0 + seed));
			// Not every cell edge cracks: a few long lines, more with damage.
			shown = (1.0 - smoothstep(reach * 0.85, reach, d)) * step(e.y, 0.25 + 0.75 * damage);
			near = (1.0 - smoothstep(0.0, 0.25 + damage * 0.5, d)) * damage;
		} else {
			shown = step(e.y, damage * 1.3);
		}
		float w = 0.01 + 0.035 * damage;
		float crack = (1.0 - smoothstep(w * 0.5, w, e.x)) * shown;
		albedo *= 1.0 - crack * 0.7;
		albedo *= 1.0 - near * (0.25 + 0.2 * noise(local_pos * 18.0));
	}

	// Cheap contact shadow where blocks meet the ground.
	albedo *= mix(0.72, 1.0, smoothstep(0.0, 0.6, world_y));

	albedo *= shade;
	float t = clamp(tint, 0.0, 1.0);
	ALBEDO = mix(albedo, violet_deep, t * 0.9);
	ROUGHNESS = rough;
	METALLIC = metallic * (1.0 - t);
	EMISSION = violet * t * t * t * glow_strength;
}
