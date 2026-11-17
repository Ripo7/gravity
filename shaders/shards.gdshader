shader_type spatial;
// Every shard of a Structure, in one draw call. The mesh holds the shards
// where they stood when the building was whole; each vertex knows its shard,
// a small texture says which rigid body the shard belongs to now, and another
// gives where that body is. So a wall standing, a slab falling in one piece
// and a thousand loose shards are all moved here, on the graphics card.
// The grid is laid on the shards where they stood, so it is whole across a
// standing wall and stays glued to each piece as it tumbles.
// A face made by the cut is only drawn once the shard on its other side has
// gone its own way: while the two are still together it is inside the wall.
// Such a face is not flat (its middle is pushed in or out): it is lit facet
// by facet, like broken stone.
// What a box is dressed as (its look, kept in the alpha of its colour) says
// what goes on its faces: the test ground's grid, its paint alone, or a
// wall modelled and baked in Blender (tools/blender/facades.py), one tile
// to a bay of a floor, with its relief as a normal map.

uniform sampler2D slot_of : filter_nearest, repeat_disable;  // per shard: its body (-1 hidden)
uniform sampler2D bodies : filter_nearest, repeat_disable;   // per body: where it is (2 texels)
uniform sampler2D grid : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float squares_per_metre = 0.25;
uniform vec3 core : source_color = vec3(0.46, 0.45, 0.45);  // the inside of a wall
// The tiles of the walls, a layer each: column * 4 + row of the pictures.
uniform sampler2DArray facade : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray facade_relief : hint_normal, filter_linear_mipmap, repeat_enable;

varying vec3 stood;    // where this point was in the whole building
varying vec3 facing;   // and which way its face looked
varying float inside;  // 1 on a face made by the break
varying vec4 skin;     // on a wall: bays across, floors up, how many of each
varying float look;    // what the box is dressed as (ShardMesh.Look)

vec3 turn(vec4 q, vec3 v) {
	return v + 2.0 * cross(q.xyz, cross(q.xyz, v) + q.w * v);
}

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

// Soft blotches, a metre or so across: paint is never even.
float blotch(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float low = mix(mix(hash(i), hash(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(hash(i + vec3(0.0, 1.0, 0.0)), hash(i + vec3(1.0, 1.0, 0.0)), f.x), f.y);
	float high = mix(mix(hash(i + vec3(0.0, 0.0, 1.0)), hash(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(hash(i + vec3(0.0, 1.0, 1.0)), hash(i + vec3(1.0, 1.0, 1.0)), f.x), f.y);
	return mix(low, high, f.z);
}

void vertex() {
	stood = VERTEX;
	facing = NORMAL;
	inside = UV.y > 0.5 ? 1.0 : 0.0;
	skin = CUSTOM0;
	look = floor((1.0 - COLOR.a) * 5.0 + 0.5);
	// Which way a wall's picture runs: across, and up.
	vec3 across = abs(NORMAL.y) < 0.5 ? normalize(cross(vec3(0.0, 1.0, 0.0), NORMAL)) : vec3(1.0, 0.0, 0.0);
	TANGENT = across;
	BINORMAL = cross(NORMAL, across);
	int id = int(UV.x + 0.5);
	int w = textureSize(slot_of, 0).x;
	float slot = texelFetch(slot_of, ivec2(id % w, id / w), 0).r;
	bool hidden = slot < -0.5;
	if (!hidden && UV.y > 0.5) {
		int other = int(UV.y - 0.5);
		hidden = abs(texelFetch(slot_of, ivec2(other % w, other / w), 0).r - slot) < 0.5;
	}
	if (hidden) {
		VERTEX = vec3(0.0);
	} else {
		int t = int(slot + 0.5) * 2;
		int bw = textureSize(bodies, 0).x;
		vec4 at = texelFetch(bodies, ivec2(t % bw, t / bw), 0);
		vec4 q = texelFetch(bodies, ivec2((t + 1) % bw, (t + 1) / bw), 0);
		VERTEX = at.xyz + turn(q, VERTEX);
		NORMAL = turn(q, NORMAL);
		TANGENT = turn(q, TANGENT);
		BINORMAL = turn(q, BINORMAL);
	}
}

void fragment() {
	vec3 n = abs(facing);
	bool flat_top = n.y > n.x && n.y > n.z;
	vec2 uv = flat_top ? stood.xz : (n.x > n.z ? stood.zy : stood.xy);
	int kind = int(look + 0.5);
	bool built = kind >= 1 && kind <= 3;
	vec3 paint = COLOR.rgb;
	if (kind != 0) {
		paint *= 0.92 + 0.16 * blotch(stood * 1.3);
	}
	if (kind == 3) {
		paint *= 0.8;  // glass is deeper than paint
	}
	vec3 face = paint;
	vec3 relief = vec3(0.5, 0.5, 1.0);
	float raised = 0.0;
	if (kind == 0) {
		face = texture(grid, uv * squares_per_metre).rgb * paint;
	} else if (built && !flat_top) {
		// A wall: which tile for this bay of this floor. One door to a
		// house; shops and lobbies all along; the top floor under its cornice.
		// (The count of bays comes a hair off a whole number from one pixel
		// to the next: its half is not floored as it is, or the door of a
		// house with an even count would be in two bays at once.)
		float row = 1.0;
		if (skin.y < 1.0) {
			row = (kind > 1 || abs(floor(skin.x) - floor(skin.z * 0.5 + 0.25)) < 0.5) ? 0.0 : 1.0;
		} else if (skin.y > skin.w - 1.0) {
			row = 2.0;
		}
		vec3 at = vec3(fract(skin.x), 1.0 - fract(skin.y), float(kind - 1) * 4.0 + row);
		vec4 tile = textureGrad(facade, at, dFdx(skin.xy), dFdy(skin.xy));
		face = tile.rgb * mix(vec3(1.0), paint, tile.a);
		// Darker towards the ground it stood on: it sits there, shadow or not.
		face *= mix(0.68, 1.0, smoothstep(0.0, 0.45, stood.y));
		relief = textureGrad(facade_relief, at, dFdx(skin.xy), dFdy(skin.xy)).rgb;
		raised = 1.0;
	} else if (built) {
		face = texture(facade, vec3(stood.xz * 2.0, 15.0)).rgb * mix(vec3(1.0), paint, 0.3);
	} else if (kind == 4) {
		vec4 tile = texture(facade, vec3(uv * 2.5, 12.0));
		face = flat_top ? tile.rgb * paint : paint * 0.75;
	}
	// Broken faces: bricks in a house or an office, concrete in a tower; else
	// plain and darker, with a coarse grain and a finer one.
	float grain = hash(floor(stood * 14.0)) * 0.6 + hash(floor(stood * 47.0)) * 0.4;
	vec3 broken = core * COLOR.rgb * (0.78 + 0.4 * grain);
	if (built) {
		broken = texture(facade, vec3(uv * 5.0, kind == 3 ? 14.0 : 13.0)).rgb;
		broken *= (kind == 3 ? 0.6 : 0.95) + 0.15 * grain;
	}
	ALBEDO = mix(face, broken, inside);
	// Each facet of a broken face faces its own way (worked out from the
	// surface itself, and turned towards the eye).
	vec3 facet = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	facet = dot(facet, VERTEX) > 0.0 ? -facet : facet;
	NORMAL = normalize(mix(NORMAL, facet, step(0.5, inside)));
	if (kind != 0) {
		// Less light from below than from the sky: what faces down or
		// sideways is darker, which gives rubble its shape without a shadow.
		float skyward = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y;
		ALBEDO *= mix(0.7, 1.0, clamp(skyward * 0.5 + 0.5, 0.0, 1.0));
	}
	NORMAL_MAP = relief;
	NORMAL_MAP_DEPTH = raised * (1.0 - step(0.5, inside));
	ROUGHNESS = 0.92;
	SPECULAR = 0.15;
}
