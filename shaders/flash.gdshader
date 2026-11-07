shader_type spatial;
// A glow: brightest at its middle, fading out to nothing at its edge.
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled, blend_add;

uniform vec3 tint : source_color = vec3(0.85, 0.65, 1.0);
uniform float intensity = 1.0;

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = tint * pow(facing, 3.0) * intensity * 1.4;
}
