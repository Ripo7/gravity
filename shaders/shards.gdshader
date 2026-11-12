shader_type spatial;
// Every shard of a Structure, in one draw call. The mesh holds the shards
// where they stood when the building was whole; each vertex knows its shard,
// a small texture says which rigid body the shard belongs to now, and another
// gives where that body is. So a wall standing, a slab falling in one piece
// and a thousand loose shards are all moved here, on the graphics card.
// The grid is laid on the shards where they stood, so it is whole across a
// standing wall and stays glued to each piece as it tumbles.

uniform sampler2D slot_of : filter_nearest, repeat_disable;  // per shard: its body (-1 hidden)
uniform sampler2D bodies : filter_nearest, repeat_disable;   // per body: where it is (2 texels)
uniform sampler2D grid : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float squares_per_metre = 0.25;
uniform vec3 core : source_color = vec3(0.36, 0.36, 0.39);  // the inside of a wall

varying vec3 stood;    // where this point was in the whole building
varying vec3 facing;   // and which way its face looked
varying float inside;  // 1 on a face made by the break

vec3 turn(vec4 q, vec3 v) {
	return v + 2.0 * cross(q.xyz, cross(q.xyz, v) + q.w * v);
}

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void vertex() {
	stood = VERTEX;
	facing = NORMAL;
	inside = UV.y;
	int id = int(UV.x + 0.5);
	int w = textureSize(slot_of, 0).x;
	float slot = texelFetch(slot_of, ivec2(id % w, id / w), 0).r;
	if (slot < -0.5) {
		VERTEX = vec3(0.0);
	} else {
		int t = int(slot + 0.5) * 2;
		int bw = textureSize(bodies, 0).x;
		vec4 at = texelFetch(bodies, ivec2(t % bw, t / bw), 0);
		vec4 q = texelFetch(bodies, ivec2((t + 1) % bw, (t + 1) / bw), 0);
		VERTEX = at.xyz + turn(q, VERTEX);
		NORMAL = turn(q, NORMAL);
	}
}

void fragment() {
	vec3 n = abs(facing);
	vec2 uv = n.y > n.x && n.y > n.z ? stood.xz : (n.x > n.z ? stood.zy : stood.xy);
	vec3 face = texture(grid, uv * squares_per_metre).rgb * COLOR.rgb;
	// Broken faces: plain and darker, with a coarse grain.
	float grain = hash(floor(stood * 18.0));
	vec3 broken = core * COLOR.rgb * (0.85 + 0.3 * grain);
	ALBEDO = mix(face, broken, inside);
	ROUGHNESS = 0.92;
	SPECULAR = 0.15;
}
