shader_type spatial;
// Dust clouds: camera-facing puffs drawn from one noise texture (cheap on
// phones: one texture read per pixel, few big puffs rather than many small
// ones). Lit from above, self-shadowed underneath, and they thin out by
// eroding the noise as they age instead of just fading.
// Instance COLOR = dust colour (rgb) and opacity (a);
// INSTANCE_CUSTOM = (age 0..1, seed, rotation, -).
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 sun_dir = vec3(0.4, 0.85, 0.35);

varying float age;
varying float seed;
varying float rot;
varying vec4 tint;
varying vec3 up_view;

void vertex() {
	// Face the camera, keep the instance's position and scale.
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(scale.x, 0, 0, 0), vec4(0, scale.y, 0, 0), vec4(0, 0, scale.z, 0), vec4(0, 0, 0, 1));
	age = INSTANCE_CUSTOM.x;
	seed = INSTANCE_CUSTOM.y;
	rot = INSTANCE_CUSTOM.z;
	tint = COLOR;
	up_view = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	if (r > 1.0) {
		discard;
	}
	float s = sin(rot);
	float k = cos(rot);
	vec2 q = vec2(c.x * k - c.y * s, c.x * s + c.y * k);
	// Two reads at different scales, drifting slowly as the cloud ages.
	float n1 = texture(noise_tex, q * 0.42 + vec2(seed * 7.3, seed * 3.1) + age * 0.08).r;
	float n2 = texture(noise_tex, q * 0.9 + vec2(seed * 2.9, seed * 5.7) - age * 0.05).r;
	float n = n1 * 0.65 + n2 * 0.35;
	float shape = 1.0 - smoothstep(0.35, 1.0, r);
	float density = shape * (0.45 + n);
	// Erode: as it ages only the thick parts remain, then nothing.
	float cut = 0.15 + age * 0.75;
	float a = smoothstep(cut, cut + 0.35, density);
	// Lit from above: the side toward the sky is brighter, the underside
	// darker, which reads as volume.
	vec2 up2 = normalize(up_view.xy + vec2(0.0001));
	float top = clamp(dot(c, up2) * 0.5 + 0.5, 0.0, 1.0);
	float light = mix(0.58, 1.04, top) * (0.85 + 0.3 * n2);
	ALBEDO = tint.rgb * light;
	ALPHA = a * tint.a;
}
