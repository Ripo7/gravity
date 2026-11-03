shader_type spatial;
// Gravitational lens: a sphere that bends whatever is behind it toward its
// centre, with a dark core and a violet rim. Used for the pull and the
// shockwave.
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float strength = 0.06;
uniform float core = 0.0;            // 0..1 darkness of the centre
uniform float rim = 1.0;             // violet edge intensity
uniform float alpha_scale = 1.0;
uniform vec3 violet : source_color = vec3(0.55, 0.24, 1.0);
uniform vec3 deep : source_color = vec3(0.12, 0.02, 0.28);

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	// Pull samples outward near the rim: looks like light bending inward.
	vec2 n = NORMAL.xy;
	vec2 offset = n * strength * pow(facing, 0.6) * (1.0 - facing) * 4.0;
	offset.y = -offset.y;
	vec3 bent = texture(screen_tex, SCREEN_UV + offset).rgb;
	// The screen copy is sRGB here; ALBEDO expects linear.
	bent = pow(bent, vec3(2.2));
	float centre = smoothstep(0.55, 0.95, facing) * core;
	vec3 col = mix(bent, deep, centre);
	float edge = pow(1.0 - facing, 3.0);
	col += violet * edge * rim;
	ALBEDO = col;
	ALPHA = smoothstep(0.0, 0.2, facing) * alpha_scale;
}
