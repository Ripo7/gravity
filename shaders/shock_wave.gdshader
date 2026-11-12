shader_type spatial;
// A shock wave: a thin shell of bent air with a bright rim, growing (a blast)
// or shrinking (an implosion), seen from outside. Or only a cap of it around
// a direction, seen from behind by whoever blasted it (the shock wave power):
// then just a ring of light round its edge and a faint veil, no bending (it
// would fill the screen, too costly on phones).
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float fade = 1.0;        // 1 when it starts, 0 when gone
uniform float strength = 0.035;  // how far it bends what is behind it
uniform vec3 tint : source_color = vec3(0.85, 0.65, 1.0);
uniform float glow = 0.8;
uniform vec3 cone_dir = vec3(0.0, 0.0, -1.0);  // local
uniform float cone_cos = -2.0;   // below -1: the whole sphere

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	if (cone_cos > -1.5) {
		float c = dot(normalize(lp), cone_dir);
		float inside = smoothstep(cone_cos - 0.015, cone_cos + 0.015, c);
		float ring = inside * (1.0 - smoothstep(0.0, 0.1, c - cone_cos));
		ALBEDO = tint * (1.0 + ring * glow);
		ALPHA = clamp((ring * 0.75 + inside * 0.05) * fade, 0.0, 1.0);
	} else {
		if (!FRONT_FACING) {
			discard;
		}
		float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		// Seen edge-on at its silhouette: brightest and most bent there.
		float rim = pow(1.0 - facing, 2.5);
		float body = 0.1 + 0.9 * rim;
		vec2 n = normalize(NORMAL.xy + vec2(1e-4));
		n.y = -n.y;
		vec3 bent = pow(texture(screen_tex, SCREEN_UV - n * strength * body * fade).rgb, vec3(2.2));
		ALBEDO = bent + tint * rim * glow * fade;
		ALPHA = clamp(body * fade * 1.4, 0.0, 1.0);
	}
}
