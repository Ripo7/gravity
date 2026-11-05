shader_type spatial;
// Black hole halo: a sphere around the opaque core. Bends whatever is
// behind it around the core (gravitational lens) and glows violet at the
// photon ring, right at the edge of the black ball.
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float core_ratio = 0.42;     // core radius / halo radius
uniform float strength = 0.09;
uniform float glow = 1.0;
uniform vec3 violet : source_color = vec3(0.55, 0.24, 1.0);
uniform vec3 hot : source_color = vec3(0.85, 0.7, 1.0);

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	// Projected distance from the centre, 0 centre .. 1 silhouette.
	float rho = sqrt(1.0 - facing * facing);
	float above = max(rho - core_ratio, 0.0) / (1.0 - core_ratio);
	// Light bends inward: sample farther out, strongest near the core.
	vec2 n = normalize(NORMAL.xy + vec2(1e-4));
	float bend = strength * pow(1.0 - above, 3.0);
	vec2 offset = n * bend;
	offset.y = -offset.y;
	vec3 bent = pow(texture(screen_tex, SCREEN_UV + offset).rgb, vec3(2.2));
	// Photon ring hugging the ball, then a soft violet haze.
	float ring = exp(-pow(above * 9.0, 2.0));
	float haze = pow(1.0 - above, 4.0) * 0.35;
	float swirl = 0.75 + 0.25 * sin(atan(n.y, n.x) * 3.0 + TIME * 9.0);
	vec3 col = bent * (1.0 - 0.5 * pow(1.0 - above, 2.0));
	col += hot * ring * 1.3 * glow * swirl + violet * haze * glow;
	ALBEDO = col;
	// Inside the core silhouette the opaque black ball shows through.
	float outside = smoothstep(core_ratio - 0.01, core_ratio + 0.01, rho);
	ALPHA = smoothstep(1.0, 0.8, rho) * outside;
}
