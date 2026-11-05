shader_type spatial;
// The power ball: bright violet core, white-hot centre, soft fresnel glow.
render_mode unshaded, cull_back, shadows_disabled;

uniform vec3 violet : source_color = vec3(0.55, 0.24, 1.0);
uniform vec3 hot : source_color = vec3(0.92, 0.82, 1.0);

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float swirl = 0.5 + 0.5 * sin(TIME * 9.0 + (NORMAL.x + NORMAL.y) * 8.0);
	vec3 col = mix(violet * 1.4, hot * 1.6, pow(facing, 3.0) * (0.75 + 0.25 * swirl));
	ALBEDO = col;
}
