shader_type spatial;
// Dust clouds: camera-facing puffs (cheap on phones: few big puffs rather
// than many small ones). Each puff plays a flipbook of a billowing cloud
// built and rendered in Blender (tools/make_smoke.py): the frame follows its
// age, blended with the next. Without the flipbook: one noise texture, lit
// from above and eroded as it ages.
// Instance COLOR = dust colour (rgb) and opacity (a);
// INSTANCE_CUSTOM = (age 0..1, seed, rotation, -).
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
// 8 x 8 frames: R = light on the cloud, A = density.
uniform sampler2D flipbook : filter_linear_mipmap;
uniform bool use_flipbook = false;
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

vec4 flip_frame(vec2 uv, float f) {
	vec2 cell = vec2(mod(f, 8.0), floor(f / 8.0));
	return texture(flipbook, (cell + clamp(uv, 0.002, 0.998)) / 8.0);
}

// The Blender puff: its frame by age, blended with the next. Returns the
// colour and the opacity.
vec4 flipbook_puff(vec2 c, float a_age, float a_seed, float a_rot, vec4 a_tint, vec2 up2) {
	// A little turn and a mirror per puff so no two look alike.
	float s0 = sin(a_rot * 0.2);
	float k0 = cos(a_rot * 0.2);
	vec2 q0 = vec2(c.x * k0 - c.y * s0, c.x * s0 + c.y * k0);
	q0.x *= a_seed > 0.5 ? -1.0 : 1.0;
	vec2 uv = q0 * 0.36 + 0.5;  // the puff fills the quad by mid-life
	float f = clamp(a_age, 0.0, 1.0) * 62.999;
	float f0 = floor(f);
	vec4 v = mix(flip_frame(uv, f0), flip_frame(uv, min(f0 + 1.0, 63.0)), f - f0);
	// Its own light, and the sky side a touch brighter whatever the view.
	float top = clamp(dot(c, up2) * 0.5 + 0.5, 0.0, 1.0);
	// Rendered thin (light gets in): thicken it to read as a cloud.
	float density = clamp(v.a * 1.8, 0.0, 1.0);
	return vec4(a_tint.rgb * (0.35 + 0.8 * v.r) * mix(0.8, 1.06, top), density * a_tint.a);
}

// Without the flipbook: two noise reads, eroded as the cloud ages.
vec4 noise_puff(vec2 c, float a_age, float a_seed, float a_rot, vec4 a_tint, vec2 up2) {
	float r = length(c);
	float s = sin(a_rot);
	float k = cos(a_rot);
	vec2 q = vec2(c.x * k - c.y * s, c.x * s + c.y * k);
	// Two reads at different scales, drifting slowly as the cloud ages.
	float n1 = texture(noise_tex, q * 0.42 + vec2(a_seed * 7.3, a_seed * 3.1) + a_age * 0.08).r;
	float n2 = texture(noise_tex, q * 0.9 + vec2(a_seed * 2.9, a_seed * 5.7) - a_age * 0.05).r;
	float n = n1 * 0.65 + n2 * 0.35;
	float shape = 1.0 - smoothstep(0.35, 1.0, r);
	float density = shape * (0.45 + n);
	// Erode: as it ages only the thick parts remain, then nothing.
	float cut = 0.15 + a_age * 0.75;
	float a = smoothstep(cut, cut + 0.35, density);
	// Lit from above: the side toward the sky is brighter, the underside
	// darker, which reads as volume.
	float top = clamp(dot(c, up2) * 0.5 + 0.5, 0.0, 1.0);
	float light = mix(0.58, 1.04, top) * (0.85 + 0.3 * n2);
	return vec4(a_tint.rgb * light, a * a_tint.a);
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	if (length(c) > 1.0) {
		discard;
	}
	vec2 up2 = normalize(up_view.xy + vec2(0.0001));
	vec4 puff = use_flipbook ? flipbook_puff(c, age, seed, rot, tint, up2) : noise_puff(c, age, seed, rot, tint, up2);
	ALBEDO = puff.rgb;
	ALPHA = puff.a;
}
