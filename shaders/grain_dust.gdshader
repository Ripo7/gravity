shader_type spatial;
render_mode skip_vertex_transform, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// The fine dust of a black hole's cloud: soft camera-facing puffs that
// orbit with the grains (same law, grain_orbit.gdshaderinc) and spread out
// and fade when the hole closes. Same instance layout as the grains; the
// basis scale is the puff's radius.

#include "res://shaders/grain_orbit.gdshaderinc"

uniform float opacity = 0.32;

varying vec3 dust_col;
varying float alpha;
varying vec2 quad;

void vertex() {
	float scale;
	float core;
	vec3 p = orbit(MODEL_MATRIX[3].xyz, INSTANCE_CUSTOM.x, INSTANCE_CUSTOM.y, INSTANCE_CUSTOM.z, INSTANCE_CUSTOM.w, scale, core);
	float size = length(MODEL_MATRIX[0].xyz);
	// Born small, it swells as the grains grind; once flung it billows out.
	float age = max(now - INSTANCE_CUSTOM.x, 0.0);
	float grow = 0.35 + 0.65 * (1.0 - exp(-1.5 * age));
	if (released > 0.0) {
		grow *= 1.0 + 2.5 * (1.0 - scale);
	}
	dust_col = COLOR.rgb;
	alpha = opacity * scale * (0.6 + 0.4 * core);
	quad = VERTEX.xy * 2.0;
	vec3 view = (VIEW_MATRIX * vec4(p, 1.0)).xyz;
	VERTEX = view + vec3(VERTEX.xy * size * grow * 2.0, 0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	float d = length(quad);
	float soft = 1.0 - smoothstep(0.2, 1.0, d);
	ALBEDO = dust_col;
	ALPHA = alpha * soft * soft;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
