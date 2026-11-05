shader_type canvas_item;
// Soft dark corners; focuses the eye on the centre. Very subtle on purpose.

uniform float strength = 0.2;
uniform float inner = 0.45;
uniform float outer = 1.05;
uniform vec3 tint : source_color = vec3(0.1, 0.08, 0.18);

void fragment() {
	vec2 uv = UV - 0.5;
	uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float d = length(uv) * 1.6;
	COLOR = vec4(tint, smoothstep(inner, outer, d) * strength);
}
