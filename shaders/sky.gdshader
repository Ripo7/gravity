shader_type sky;
// Late afternoon over the square: deep blue overhead, a pale band at the
// horizon that warms toward the sun, the sun's glow and disc, and a field of
// cumulus baked in Blender (tools/make_sky.py) lit by the same sun, laid over
// it and fading into the haze near the horizon. Static (no TIME): the light
// it gives the scene is worked out once.

uniform vec3 zenith : source_color = vec3(0.17, 0.34, 0.66);
uniform vec3 horizon : source_color = vec3(0.7, 0.79, 0.87);
uniform vec3 horizon_sun : source_color = vec3(1.0, 0.72, 0.46);
uniform vec3 ground : source_color = vec3(0.52, 0.48, 0.45);
// How fast the blue deepens above the horizon (lower: thinner pale band).
uniform float band = 0.45;
uniform float glow = 0.22;  // the wide halo round the sun
uniform float sun_disc = 0.9996;  // cos of the disc's angular radius
// Clouds: RGB = their light from the bake, A = how much sky they hide;
// equirectangular, upper half of the sky (latitude 0 at the bottom).
uniform sampler2D clouds : source_color, filter_linear, repeat_enable;  // no mipmaps: no seam where the panorama wraps
uniform bool use_clouds = false;
// The bake's light picks between the clouds' shaded and sunlit colours.
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.87, 0.72);
uniform vec3 cloud_shade : source_color = vec3(0.52, 0.58, 0.7);
uniform float cloud_light = 1.0;
uniform float exposure = 1.0;

void sky() {
	vec3 d = EYEDIR;
	vec3 sun = LIGHT0_ENABLED ? LIGHT0_DIRECTION : normalize(vec3(0.775, 0.407, 0.484));
	vec3 sun_col = LIGHT0_ENABLED ? LIGHT0_COLOR * LIGHT0_ENERGY : vec3(1.6, 1.25, 0.95);
	float h = d.y;
	float mu = dot(d, sun);
	// The horizon warms on the sun's side of the sky.
	vec2 flat_d = normalize(d.xz + vec2(1e-5));
	vec2 flat_sun = normalize(sun.xz + vec2(1e-5));
	float toward = clamp(dot(flat_d, flat_sun) * 0.5 + 0.5, 0.0, 1.0);
	vec3 hor = mix(horizon, horizon_sun, toward * toward * toward * 0.85);
	vec3 col = mix(hor, zenith, pow(clamp(h, 0.0, 1.0), band));
	// Below the horizon: the haze over the plain.
	col = h < 0.0 ? mix(hor, ground, clamp(-h * 5.0, 0.0, 1.0)) : col;
	// The sun's glow: a wide warm halo and a tight bright one, then the disc.
	float m = max(mu, 0.0);
	col += sun_col * (pow(m, 6.0) * glow + pow(m, 90.0) * 0.5);
	col += sun_col * smoothstep(sun_disc - 0.00025, sun_disc, mu) * 6.0;
	if (use_clouds && h > 0.0) {
		vec2 uv = vec2(0.5 + atan(d.x, -d.z) / TAU, 1.0 - asin(clamp(h, 0.0, 1.0)) / (PI * 0.5));
		vec4 c = texture(clouds, uv);
		float lit = smoothstep(0.12, 0.8, dot(c.rgb, vec3(0.3, 0.55, 0.15)));
		vec3 cloud = mix(cloud_shade, cloud_lit, lit) * cloud_light;
		// Far clouds sink into the horizon's haze.
		float far = 1.0 - smoothstep(0.02, 0.35, h);
		cloud = mix(cloud, hor * 1.05, far * 0.6);
		// Backlit edges near the sun shine.
		cloud += sun_col * pow(m, 12.0) * 0.35 * (1.0 - c.a);
		col = mix(col, cloud, c.a * smoothstep(0.0, 0.06, h));
	}
	COLOR = col * exposure;
}
