shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, shadows_disabled;
// The glow round the orb: light added over what is behind, strongest
// towards the middle and gone at the edge of this bigger ball.

uniform vec3 bright : source_color = vec3(0.66, 0.5, 1.0);
uniform float power = 1.0;

varying vec3 round;

void vertex() {
	round = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float facing = clamp(dot(normalize(-VERTEX), round), 0.0, 1.0);
	ALBEDO = bright * pow(facing, 3.0) * 0.55 * power;
}
