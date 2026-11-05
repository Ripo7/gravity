shader_type spatial;
render_mode skip_vertex_transform;
// Grains of a black hole's cloud: what the storm ground down. All their
// motion is worked out here from the moment each grain was caught, so a
// grain costs no script time at all. Per grain (one MultiMesh instance):
//   transform origin   where it was caught; basis scale = its size
//   COLOR.rgb          colour of the crushed material
//   INSTANCE_CUSTOM    x: time caught, y: its lane (orbit radius),
//                      z: its layer of the disc (-1..1), w: random

#include "res://shaders/grain_orbit.gdshaderinc"

varying vec3 grain_col;
varying float glow;

mat3 turn(vec3 axis, float a) {
	float c = cos(a);
	float s = sin(a);
	float t = 1.0 - c;
	vec3 u = axis;
	return mat3(
		vec3(t * u.x * u.x + c, t * u.x * u.y + s * u.z, t * u.x * u.z - s * u.y),
		vec3(t * u.x * u.y - s * u.z, t * u.y * u.y + c, t * u.y * u.z + s * u.x),
		vec3(t * u.x * u.z + s * u.y, t * u.y * u.z - s * u.x, t * u.z * u.z + c));
}

void vertex() {
	float rnd = INSTANCE_CUSTOM.w;
	float scale;
	float core;
	vec3 p = orbit(MODEL_MATRIX[3].xyz, INSTANCE_CUSTOM.x, INSTANCE_CUSTOM.y, INSTANCE_CUSTOM.z, rnd, scale, core);
	glow = core;
	grain_col = COLOR.rgb;
	float size = length(MODEL_MATRIX[0].xyz);
	// Never smaller than about a pixel and a half: far away the grains still
	// read as a swirl of specks instead of vanishing.
	float depth = max(-(VIEW_MATRIX * vec4(p, 1.0)).z, 0.1);
	float pixel = 2.0 * depth / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	size = max(size, pixel * 1.6);
	// Each grain tumbles, and none is a cube.
	vec3 axis = normalize(vec3(fract(rnd * 3.1) - 0.5, fract(rnd * 5.7) - 0.5, fract(rnd * 9.3) - 0.5) + 1e-3);
	mat3 rot = turn(axis, now * (5.0 + 12.0 * fract(rnd * 11.0)) + rnd * 6.28);
	vec3 shape = vec3(1.0, 0.45 + 0.5 * fract(rnd * 2.3), 0.6 + 0.5 * fract(rnd * 4.1));
	vec3 world = p + rot * (VERTEX * shape) * size * scale;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(rot * normalize(NORMAL / shape), 0.0)).xyz);
}

void fragment() {
	ALBEDO = grain_col;
	ROUGHNESS = 0.92;
	SPECULAR = 0.3;
	// Near the core the grains catch the hole's violet light.
	EMISSION = violet * glow * glow * 0.6;
}
