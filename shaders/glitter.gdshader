// Glass that has burst: small flat bits that fall straight down, lie where
// they land and are gone a moment later. No bodies and no script per bit:
// each is an instance of one multimesh, and where it is drawn is worked
// out here from how long ago the pane burst.
shader_type spatial;
render_mode cull_disabled, world_vertex_coords;

uniform float age = 0.0;  // s since the pane burst
uniform float gravity = 9.8;  // m/s2: as fast as things fall on the bench
uniform float ground = 0.0;  // the height they land at
uniform float lies = 1.2;  // s a bit lies there
uniform float fades = 0.6;  // s it takes to be gone
uniform vec3 tint : source_color = vec3(0.72, 0.88, 0.92);

void vertex() {
	// Four numbers of its own, 0 to 1.
	vec4 own = INSTANCE_CUSTOM;
	vec3 centre = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float drop = max(centre.y - ground, 0.0);
	float lands = sqrt(2.0 * drop / gravity);
	float t = min(age, lands);
	centre.y = max(ground + 0.01 + 0.01 * own.x, centre.y - 0.5 * gravity * t * t);
	// (A little apart as they fall: not thrown.)
	centre.xz += (own.xy - 0.5) * 0.5 * t;
	// Tumbling on the way down; flat on the ground, turned at random.
	float spin = own.z * 6.28318 + t * (4.0 + 6.0 * own.w);
	vec3 a = vec3(cos(spin), sin(spin), 0.0);
	vec3 b = normalize(cross(a, vec3(sin(own.x * 6.28318), 0.3, cos(own.x * 6.28318))));
	if (age >= lands) {
		float yaw = own.z * 6.28318;
		a = vec3(cos(yaw), 0.0, sin(yaw));
		b = vec3(-sin(yaw), 0.0, cos(yaw));
	}
	float size = (0.05 + 0.07 * own.w) * clamp(1.0 - (age - lands - lies) / fades, 0.0, 1.0);
	VERTEX = centre + (a * (UV.x - 0.5) + b * (UV.y - 0.5)) * size;
	NORMAL = normalize(cross(a, b));
}

void fragment() {
	ALBEDO = tint;
	ROUGHNESS = 0.2;
}
