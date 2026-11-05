shader_type spatial;
// Every block and piece of debris, all materials, in one draw call.
// Per-instance COLOR: r = shade, g = unused,
// b = random seed, a = violet glow from the power.
// INSTANCE_CUSTOM.r = finish * 5 + material kind + damage * 0.9 (cracks); .gba = where it was
// hit, in the block's unit space + 1 (0 = never hit): cracks spread from there.
// Patterns are procedural in the block's own space (scaled to metres), so
// they stay put on moving debris and need no textures.

uniform vec3 violet : source_color = vec3(0.55, 0.24, 1.0);
uniform vec3 violet_deep : source_color = vec3(0.32, 0.08, 0.78);
uniform float glow_strength = 0.9;
// Debris and chips: the unit box (subdivided once) is cut into an
// irregular faceted chunk, different for every piece.
uniform bool chunky = false;
// Shard shapes from the library: xyz = vertex, w = 1 on the block's outer
// surface, 0 on a fresh fracture face.
uniform sampler2D shard_shapes : filter_nearest;

uniform vec3 concrete : source_color = vec3(0.78, 0.76, 0.72);
uniform vec3 wood : source_color = vec3(0.84, 0.75, 0.62);
uniform vec3 wood_dark : source_color = vec3(0.68, 0.56, 0.43);
uniform vec3 metal : source_color = vec3(0.62, 0.66, 0.72);
uniform vec3 ice : source_color = vec3(0.035, 0.03, 0.06);
uniform vec3 glass : source_color = vec3(0.16, 0.2, 0.26);
uniform vec3 glass_sky : source_color = vec3(0.98, 0.8, 0.64);
// Warm light behind some windows (the city is lived in).
uniform vec3 window_light : source_color = vec3(1.0, 0.68, 0.38);
uniform float window_lit_share = 0.16;
uniform float window_glow = 0.8;


varying vec3 local_pos;   // metres, centred on the block
varying vec3 half_size;   // metres
varying vec3 local_normal;
varying float shade;
varying float material_id;
varying float finish;
varying vec3 world_p;
varying float seed;
varying float tint;
varying float damage;
varying vec3 hit_at;  // metres in block space; x > 90 when never hit
varying float world_y;
varying float outer;  // 0 on fresh fracture faces

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
	// How many coordinates sit on the cube's surface: 3 corner, 2 edge,
	// 1 face (works for any grid the cube is split into).
	float k = step(0.49, abs(v.x)) + step(0.49, abs(v.y)) + step(0.49, abs(v.z));
	vec3 h = vec3(hash(v * 7.13 + s * 31.7), hash(v * 3.71 + s * 17.3 + 5.0), hash(v * 5.27 + s * 11.9 + 9.0));
	float pull = k > 2.5 ? 0.16 + 0.34 * h.x : (k > 1.5 ? 0.03 + 0.17 * h.y : 0.02 * h.z);
	vec3 o = v * (1.0 - pull);
	o += (h - 0.5) * 0.1 * step(1.5, k);
	return clamp(o, vec3(-0.5), vec3(0.5));
}

// Distance-faded line: 1 on a line of width w at the integer crossings of
// x, fading out when the lines get finer than a pixel (no shimmer).
float grid_line(float x, float w) {
	float fw = fwidth(x);
	float d = abs(fract(x + 0.5) - 0.5);
	float l = 1.0 - smoothstep(w - fw, w + fw, d);
	return l * clamp(1.0 - fw * 3.0, 0.0, 1.0);
}

// Hexagonal infill pattern: 1 on the cell walls, 0 inside the cells.
float hex_wall(vec2 p) {
	vec2 r = vec2(1.0, 1.7320508);
	vec2 h = r * 0.5;
	vec2 a = mod(p, r) - h;
	vec2 b = mod(p - h, r) - h;
	vec2 g = dot(a, a) < dot(b, b) ? a : b;
	vec2 gg = abs(g);
	float d = max(dot(gg, normalize(vec2(1.0, 1.7320508))), gg.x);
	return smoothstep(0.38, 0.45, d);
}

// Courses of blocks: x = along the wall, y = up. Returns the joint mask
// (1 in the mortar) and writes a per-block id.
float courses(vec2 uv, vec2 size, float stagger, float joint, out vec2 id) {
	float row = floor(uv.y / size.y);
	float shift = stagger > 0.0 ? fract(row * 0.5) * 2.0 * stagger : hash(vec3(row, 3.1, 7.7)) * size.x;
	float col = floor((uv.x + shift) / size.x);
	id = vec2(col, row);
	float jx = grid_line((uv.x + shift) / size.x, joint / size.x);
	float jy = grid_line(uv.y / size.y, joint / size.y);
	return max(jx, jy);
}

void apply_finish(int f, vec2 uv, vec3 p, inout vec3 albedo, inout float rough, inout float metallic) {
	vec2 id;
	if (f == 1) {
		// Medieval ashlar: rough courses of uneven stones, dark mortar.
		float j = courses(uv, vec2(0.78, 0.42), 0.0, 0.022, id);
		float tone = 0.82 + 0.3 * hash(vec3(id, 1.3));
		vec3 stone = mix(vec3(0.66, 0.6, 0.5), vec3(0.58, 0.55, 0.5), hash(vec3(id, 9.1)));
		albedo = mix(stone * tone * (0.85 + 0.25 * fbm(p * 2.5)), vec3(0.36, 0.33, 0.3), j);
		rough = 0.95;
	} else if (f == 2) {
		// Brick in running bond, light mortar.
		float j = courses(uv, vec2(0.23, 0.075), 0.5, 0.011, id);
		vec3 brick = vec3(0.6, 0.3, 0.21) * (0.8 + 0.35 * hash(vec3(id, 2.7)));
		float far = clamp(fwidth(uv.y) * 25.0, 0.0, 1.0);
		albedo = mix(mix(brick, vec3(0.76, 0.71, 0.64), j), vec3(0.62, 0.38, 0.29), far);
		rough = 0.9;
	} else if (f == 3) {
		// Printed travertine: perfectly regular strata, a few long pores.
		float strata = grid_line(uv.y / 0.06, 0.08);
		float band = fbm(vec3(p.x * 0.3, p.y * 2.0, p.z * 0.3));
		float pores = step(0.8, noise(vec3(p.x * 4.0, p.y * 28.0, p.z * 4.0))) * 0.18;
		albedo = vec3(0.88, 0.8, 0.66) * (0.9 + 0.14 * band) * (1.0 - strata * 0.1 - pores);
		rough = 0.8;
	} else if (f == 4) {
		// Printed marble: white with soft grey veins, satin.
		float w = fbm(p * 0.9) * 5.0;
		float vein = 1.0 - smoothstep(0.0, 0.06, abs(sin(p.x * 1.3 + p.y * 0.7 + w)));
		float strata = grid_line(uv.y / 0.06, 0.06);
		albedo = vec3(0.93, 0.91, 0.87) * (1.0 - vein * 0.22 - strata * 0.05);
		rough = 0.35;
	} else if (f >= 5 && f <= 8) {
		// Render over brick: a plaster colour, mottled, worn through in
		// patches near the ground and corners.
		vec3 col = f == 5 ? vec3(0.88, 0.66, 0.38) : (f == 6 ? vec3(0.86, 0.6, 0.52) : (f == 7 ? vec3(0.74, 0.43, 0.29) : vec3(0.93, 0.86, 0.7)));
		float mottle = fbm(p * 0.7);
		vec3 plaster = col * (0.86 + 0.2 * mottle);
		float worn = smoothstep(0.66, 0.72, fbm(p * 0.9 + 11.0));
		float j = courses(uv, vec2(0.23, 0.075), 0.5, 0.011, id);
		vec3 brick = mix(vec3(0.58, 0.3, 0.21) * (0.8 + 0.3 * hash(vec3(id, 5.0))), vec3(0.7, 0.66, 0.6), j);
		albedo = mix(plaster, brick, worn);
		rough = 0.88;
	} else if (f == 9) {
		// Terracotta tiles: rounded rows, each tile its own shade.
		float row = floor(uv.y / 0.2);
		float u = uv.x / 0.22 + fract(row * 0.5);
		float curve = 0.75 + 0.25 * sin(fract(u) * 3.14159);
		float lip = grid_line(uv.y / 0.2, 0.06);
		vec3 tile = vec3(0.74, 0.38, 0.23) * (0.8 + 0.35 * hash(vec3(floor(u), row, 4.0)));
		albedo = tile * curve * (1.0 - lip * 0.35);
		rough = 0.85;
	} else if (f == 10) {
		// Printed composite: charcoal with a fine woven sheen.
		float weave = 0.5 + 0.5 * sin((uv.x + uv.y) * 90.0) * sin((uv.x - uv.y) * 90.0);
		albedo = vec3(0.12, 0.12, 0.13) * (0.9 + 0.2 * weave);
		rough = 0.45;
		metallic = 0.25;
	} else if (f == 11) {
		// Painted shutters: green louvres, paint flaking to the wood.
		float louvre = grid_line(uv.y / 0.07, 0.12);
		vec3 paintc = vec3(0.24, 0.4, 0.31) * (0.9 + 0.15 * fbm(p * 0.6));
		float flake = smoothstep(0.68, 0.74, fbm(p * 1.6 + 2.0));
		albedo = mix(paintc, albedo, flake) * (1.0 - louvre * 0.3);
		rough = 0.75;
		metallic = 0.0;
	} else if (f == 12) {
		// Copper gone green, darker where rain runs down, bronze showing.
		float streak = noise(vec3(p.x * 6.0, p.y * 0.4, p.z * 6.0));
		vec3 green = vec3(0.36, 0.6, 0.52) * (0.85 + 0.2 * fbm(p * 1.2));
		albedo = mix(green, vec3(0.42, 0.3, 0.18), smoothstep(0.7, 0.85, streak) * 0.6);
		rough = 0.7;
		metallic = 0.2;
	}
}

void vertex() {
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	// Material in the integer part of the first custom float, damage in
	// its fraction (see Materials.custom).
	float packed = floor(INSTANCE_CUSTOM.r + 0.001);
	material_id = mod(packed, 5.0);
	finish = floor(packed / 5.0 + 0.001);
	seed = COLOR.b;
	outer = 1.0;
	if (chunky) {
		// Debris: a shard shape from the library (one texture row per
		// shard, one texel per vertex), or a plain chunk cut from the cube.
		int shard = int(INSTANCE_CUSTOM.g + 0.5) - 1;
		if (shard >= 0) {
			vec4 t = texelFetch(shard_shapes, ivec2(VERTEX_ID, shard), 0);
			VERTEX = t.xyz;
			outer = t.w;
			if (material_id > 1.5 && material_id < 2.5) {
				// Metal does not shatter, it bends: curve the length of the
				// piece (pattern x is its grain) by a seeded amount.
				float len = max(scale.x, 0.01);
				float x = VERTEX.x * len;
				float bend = (hash(vec3(seed * 17.0, 3.1, 7.7)) - 0.5) * 0.5;
				VERTEX.y += bend * x * x / (0.5 * len) / max(scale.y, 0.01);
			}
		} else {
			VERTEX = chunk(VERTEX, seed);
		}
	}
	local_pos = VERTEX * scale;
	half_size = scale * 0.5;
	local_normal = NORMAL;
	shade = COLOR.r;
	tint = COLOR.a;
	damage = clamp(fract(INSTANCE_CUSTOM.r + 0.001) / 0.9, 0.0, 1.0);
	vec3 h = INSTANCE_CUSTOM.gba;
	hit_at = (!chunky && (h.x + h.y + h.z) > 0.0) ? (h - 1.0) * scale : vec3(99.0);
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
	world_p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
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
	vec3 lit_window = vec3(0.0);
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
		// Some flats have the lights on: a warm room glow, brighter low in
		// the pane, with a curtain on one side; it fades where the sky
		// reflection takes over.
		float h = fract(seed * 91.7);
		if (h < window_lit_share && !chunky) {
			vec2 uv = face.x > 0.5 ? local_pos.zy / max(half_size.zy, vec2(0.05)) : local_pos.xy / max(half_size.xy, vec2(0.05));
			float room = 0.65 + 0.35 * (1.0 - smoothstep(-0.6, 0.9, uv.y));
			float curtain = smoothstep(0.2, 0.35, abs(uv.x - (fract(seed * 13.1) - 0.5)));
			vec3 lamp = window_light * mix(0.75, 1.15, fract(seed * 37.3));
			lit_window = lamp * room * mix(0.45, 1.0, curtain) * (1.0 - fres * 0.7) * window_glow;
			albedo *= 0.35;
		}
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

	// Finishes (Materials.Finish): what the printers copied. Static blocks
	// use world space so courses and joints run on across blocks; debris
	// uses its own space so the pattern stays on the piece.
	int fin = int(finish + 0.5);
	vec3 q = chunky ? local_pos + seed * 7.0 : world_p;
	vec2 fuv = face.y > 0.5 ? q.xz : vec2(face.x > 0.5 ? q.z : q.x, q.y);
	if (fin > 0) {
		apply_finish(fin, fuv, p, albedo, rough, metallic);
	}

	// Fresh fracture faces: the inside of the material, never weathered.
	if (chunky && outer < 0.99) {
		float inner = 1.0 - smoothstep(0.2, 0.8, outer);
		vec3 fresh = albedo;
		int fin_in = int(finish + 0.5);
		if (fin_in == 3 || fin_in == 4 || fin_in == 10) {
			// Printed stone is not solid: a honeycomb infill of stone walls
			// around dark composite cells, the future hiding inside.
			vec2 uv = (face.x > 0.5 ? local_pos.yz : (face.y > 0.5 ? local_pos.xz : local_pos.xy)) * 9.0;
			float wall = hex_wall(uv);
			vec3 stone = fin_in == 4 ? vec3(0.9, 0.88, 0.84) : vec3(0.84, 0.76, 0.62);
			fresh = mix(vec3(0.07, 0.07, 0.08), stone, wall);
			rough = mix(0.5, 0.95, wall);
		} else if (fin_in == 2 || (fin_in >= 5 && fin_in <= 8)) {
			// Brick (also under the plaster): raw red clay.
			fresh = vec3(0.62, 0.3, 0.2) * (0.85 + 0.25 * noise(p * 12.0));
			rough = 0.95;
		} else if (material_id < 0.5) {
			// Concrete and stone: lighter, with dark grit and pores.
			float grit = step(0.72, noise(p * 22.0)) * 0.25 + step(0.88, noise(p * 47.0)) * 0.2;
			vec3 inner_col = fin_in == 1 ? vec3(0.74, 0.68, 0.58) : concrete * 1.08;
			fresh = inner_col * (1.0 - grit);
			rough = 0.98;
		} else if (material_id < 1.5) {
			// Wood: pale raw fibres.
			fresh = mix(wood * 1.12, vec3(0.93, 0.86, 0.7), 0.35) * (0.9 + 0.2 * noise(p * vec3(40.0, 3.0, 40.0)));
			rough = 0.9;
		} else if (material_id < 2.5) {
			// Metal: bright torn steel.
			fresh = metal * 1.15;
			rough = 0.22;
			metallic = 0.9;
		}
		albedo = mix(albedo, fresh, inner);
	}

	// Weathering, all procedural (no textures, no extra passes):
	// - dust settles on upward faces, lighter and warmer, patchy;
	// - grime streaks run down vertical faces from their top edge;
	// - each block is darker near its bottom and on its underside, which
	//   reads as ambient occlusion wherever blocks meet slabs and floors.
	if (material_id < 2.5 && !chunky) {
		vec3 n = local_normal;
		if (n.y > 0.5) {
			float patches = smoothstep(0.35, 0.75, fbm(p * 0.9));
			albedo = mix(albedo, vec3(0.86, 0.83, 0.77), patches * 0.35);
		} else if (abs(n.y) < 0.5) {
			float from_top = half_size.y - local_pos.y;
			float streak = noise(vec3((local_pos.x + local_pos.z) * 7.0, local_pos.y * 0.35, seed * 9.0));
			float grime = smoothstep(0.55, 0.9, streak) * (1.0 - smoothstep(0.0, 1.6, from_top));
			albedo *= 1.0 - grime * 0.18;
			float from_bottom = local_pos.y + half_size.y;
			albedo *= mix(0.8, 1.0, smoothstep(0.0, 0.45, from_bottom));
		} else {
			albedo *= 0.8;  // undersides (ceilings) catch less light
		}
	}

	// Soft darkening near block edges: reads as a bevel / contact shadow.
	vec3 d = half_size - abs(local_pos);
	float edge_dist = 10.0;
	if (face.x < 0.5) { edge_dist = min(edge_dist, d.x); }
	if (face.y < 0.5) { edge_dist = min(edge_dist, d.y); }
	if (face.z < 0.5) { edge_dist = min(edge_dist, d.z); }
	float edge = chunky ? 0.0 : 1.0 - smoothstep(0.0, 0.05, edge_dist);
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
	EMISSION = violet * t * t * t * glow_strength + lit_window * (1.0 - t);
}
