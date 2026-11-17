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

// Per shard: its body (-1 hidden), and the share it has taken of the blows
// it can stand up to.
uniform sampler2D slot_of : filter_nearest, repeat_disable;
uniform sampler2D bodies : filter_nearest, repeat_disable;   // per body: where it is (2 texels)
uniform sampler2D grid : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float squares_per_metre = 0.25;
uniform vec3 core : source_color = vec3(0.46, 0.45, 0.45);  // the inside of a wall
// The tiles of the walls, a layer each: column * 4 + row of the pictures.
uniform sampler2DArray facade : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray facade_relief : hint_normal, filter_linear_mipmap, repeat_enable;

// How thick the walls and the roof of a building are (m): what shows of
// them where it is broken open, before the rooms.
const float WALL = 0.07;

// How many chips to the metre the face of a shard that has taken blows is
// cracked into.
const float CHIPS = 5.5;

varying vec3 stood;    // where this point was in the whole building
varying vec3 facing;   // and which way its face looked
varying float inside;  // 1 on a face made by the break
// On a wall: bays across, floors up, how many of each. On a face made by
// the break: how far inside the box it is from the nearest wall and from
// the top (m), in y how high among the floors, in w how many floors.
varying vec4 skin;
varying float look;    // what the box is dressed as (ShardMesh.Look)
varying float edge;    // on a face of the box: 0 in its middle, 1 on its edge
varying float worn;    // the share of the blows its shard can take, taken

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

// Points scattered one to a square of side 1, and the chips they cut a
// face into: how far `at` is from the edge of its chip (x), and a number
// that chip has of its own (y).
vec2 chip(vec2 at) {
	vec2 square = floor(at);
	float first = 8.0;
	float second = 8.0;
	float own = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 next = square + vec2(float(i), float(j));
			vec2 h = fract(sin(vec2(dot(next, vec2(127.1, 311.7)), dot(next, vec2(269.5, 183.3)))) * 43758.5453);
			vec2 off = next + h - at;
			float d = dot(off, off);
			if (d < first) {
				second = first;
				first = d;
				own = h.x;
			} else if (d < second) {
				second = d;
			}
		}
	}
	return vec2((sqrt(second) - sqrt(first)) * 0.5, own);
}

void vertex() {
	stood = VERTEX;
	facing = NORMAL;
	inside = UV.y > 0.5 ? 1.0 : 0.0;
	edge = UV.y < -0.5 ? 0.0 : 1.0;
	skin = CUSTOM0;
	look = floor((1.0 - COLOR.a) * 5.0 + 0.5);
	// Which way a wall's picture runs: across, and up.
	vec3 across = abs(NORMAL.y) < 0.5 ? normalize(cross(vec3(0.0, 1.0, 0.0), NORMAL)) : vec3(1.0, 0.0, 0.0);
	TANGENT = across;
	BINORMAL = cross(NORMAL, across);
	int id = int(UV.x + 0.5);
	int w = textureSize(slot_of, 0).x;
	vec2 state = texelFetch(slot_of, ivec2(id % w, id / w), 0).rg;
	float slot = state.r;
	worn = state.g;
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
	// What is behind the face of a wall, for where it has come off.
	vec3 behind = broken;
	if (built) {
		broken = texture(facade, vec3(uv * 5.0, kind == 3 ? 14.0 : 13.0)).rgb;
		broken *= (kind == 3 ? 0.6 : 0.95) + 0.15 * grain;
		behind = broken;
		if (inside > 0.5 || worn > 0.0) {
			// That is the thickness of the wall, and of the roof. Behind
			// it a building is not full: a room on each floor, seen from
			// where the wall was (the last tile of its column, baked like
			// the walls), its floor from above, its ceiling from below.
			float along = (n.x > n.z ? stood.z : stood.x) / (kind == 2 ? 0.5 : 0.42);
			vec3 at = vec3(along, 1.0 - fract(skin.y), float(kind - 1) * 4.0 + 3.0);
			vec2 across_x = vec2(dFdx(along), -dFdx(skin.y));
			vec2 across_y = vec2(dFdy(along), -dFdy(skin.y));
			vec4 room = textureGrad(facade, at, across_x, across_y);
			vec3 seen = room.rgb * mix(vec3(1.0), paint, room.a * 0.6);
			if (flat_top) {
				vec3 ground = kind == 1 ? vec3(0.3, 0.17, 0.08) : (kind == 2 ? vec3(0.13, 0.17, 0.25) : vec3(0.09, 0.1, 0.13));
				seen = (facing.y > 0.0 ? ground : vec3(0.42)) * (0.9 + 0.2 * grain);
			}
			if (inside > 0.5) {
				broken = mix(broken, seen, smoothstep(WALL - 0.015, WALL + 0.015, min(skin.x, skin.z)));
			} else if (kind > 1 && !flat_top) {
				behind = seen;
			}
		}
	}
	if (worn > 0.0 && inside < 0.5) {
		// A shard that has taken blows and stands: what it is faced with
		// is cracked into chips, and some have come off, more at each blow,
		// with what the wall is made of showing. Less so towards the edge
		// of the shard: its neighbours took nothing.
		vec2 chipped = chip(uv * CHIPS);
		float blur = max(fwidth(uv.x), fwidth(uv.y)) * CHIPS;
		// (Worn right through, it is a shard that came down: all of it.)
		float reach = mix(smoothstep(0.0, 0.35, 1.0 - edge), 1.0, step(0.99, worn));
		float off = step(chipped.y, (0.67 * worn) * reach);
		float crack = (1.0 - smoothstep(0.02, 0.045 + blur, chipped.x)) * clamp(1.4 - blur * 3.0, 0.0, 1.0);
		// (Faint on what the blow only brushed, plain on what is about to give.)
		float deep_in = clamp(worn * 2.4, 0.0, 1.0);
		face = mix(face, behind * 0.8, off);
		if (kind == 3) {
			// Glass cracks white.
			face = mix(face, vec3(0.85, 0.93, 1.0), 0.7 * crack * reach * (1.0 - off) * deep_in);
		} else {
			face *= 1.0 - 0.7 * crack * reach * deep_in;
		}
		relief = mix(relief, vec3(0.5, 0.5, 1.0), off);
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
