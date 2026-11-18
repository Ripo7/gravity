shader_type spatial;
// Everything a Structure is made of, in one draw call. The mesh holds the
// parts (the blocks of what breaks, the rings of what bends) where they
// stood when their piece was built; each vertex knows its part, a small
// texture says which body the part goes with now, and another gives where
// that body is. So a wall standing, a slab falling in one piece, loose
// blocks and a bent post are all moved here, on the graphics card.
// A face made by the cut is only drawn once the block on its other side has
// gone its own way: while the two are together it is inside the piece. Such
// a face is not flat (its middle is pushed in or out): it is lit facet by
// facet, like broken stone.
// A body can also be drawn a little smaller than it is, about its own
// middle: that is how a piece that still stands shows its cracks, each
// block shrunk away from its neighbours, the gaps dark.
// The skin of a piece that bends is stretched between its rings: its faces
// are lit by how they lie now, worked out from the surface itself.

uniform sampler2D slot_of : filter_nearest, repeat_disable;  // per block: its body (-1 hidden)
uniform sampler2D bodies : filter_nearest, repeat_disable;   // per body: where it is (2 texels)
// How light a broken face is beside the paint of its piece, and the inside
// of a crack.
uniform float core = 0.7;
uniform float crack = 0.22;

varying float inside;   // 1 on a face made by the cut
varying float facet;    // 1 on a face lit by how it lies now (a cut, a skin)
varying float cracked;  // 1 on a block that still stands, shrunk

vec3 turn(vec4 q, vec3 v) {
	return v + 2.0 * cross(q.xyz, cross(q.xyz, v) + q.w * v);
}

void vertex() {
	inside = UV.y > 0.5 ? 1.0 : 0.0;
	facet = abs(UV.y) > 0.5 ? 1.0 : 0.0;
	cracked = 0.0;
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
		cracked = at.w < 0.999 ? 1.0 : 0.0;
		VERTEX = at.xyz + turn(q, VERTEX * at.w);
		NORMAL = turn(q, NORMAL);
	}
}

void fragment() {
	ALBEDO = COLOR.rgb * mix(1.0, mix(core, crack, step(0.5, cracked)), step(0.5, inside));
	// Each facet of a broken face, and of a skin, faces its own way (worked
	// out from the surface itself, and turned towards the eye).
	vec3 lies = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	lies = dot(lies, VERTEX) > 0.0 ? -lies : lies;
	NORMAL = normalize(mix(NORMAL, lies, step(0.5, facet)));
	// Less light from below than from the sky: what faces down or sideways
	// is darker, which gives rubble its shape without a shadow.
	float skyward = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y;
	ALBEDO *= mix(0.7, 1.0, clamp(skyward * 0.5 + 0.5, 0.0, 1.0));
	ROUGHNESS = 0.92;
	SPECULAR = 0.15;
}
