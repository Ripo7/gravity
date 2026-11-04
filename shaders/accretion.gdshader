shader_type spatial;
// Accretion disc: a hot swirling ring of matter spun around the black hole.
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, blend_add;

uniform vec3 violet : source_color = vec3(0.55, 0.24, 1.0);
uniform vec3 hot : source_color = vec3(0.9, 0.8, 1.0);
uniform float inner = 0.3;   // inner edge, in disc radius units
uniform float intensity = 1.0;
uniform float spin = 6.0;

varying vec2 p;

void vertex() {
	p = VERTEX.xz * 2.0;  // unit disc (CylinderMesh radius 0.5)
}

void fragment() {
	float r = length(p);
	float a = atan(p.y, p.x);
	float t = (r - inner) / (1.0 - inner);
	if (t < 0.0 || r > 1.0) {
		discard;
	}
	// Faster near the centre: the streaks wind into spirals.
	float phase = a * 7.0 + TIME * spin / max(r, 0.2) + r * 18.0;
	float streak = pow(sin(phase) * 0.5 + 0.5, 3.0);
	float fall = pow(1.0 - t, 2.2) * smoothstep(0.0, 0.06, t);
	vec3 col = mix(violet, hot, pow(1.0 - t, 3.0));
	ALBEDO = col * (0.35 + streak) * fall * 2.0 * intensity;
}
