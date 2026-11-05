// Shared by the grains and the dust of a black hole's cloud: where an
// orbiting particle is, worked out from the moment it was caught.

uniform vec3 center;
uniform float now;
uniform float released = -1.0;  // time the hole closed (< 0 while it spins)
uniform float radius = 5.0;
uniform vec2 spin = vec2(9.0, 4.5);  // rad/s at the core, at the radius
uniform float max_speed = 22.0;
uniform vec2 burst = vec2(16.0, 10.0);  // fling speed near the core, at the edge
uniform float lift = 4.0;
uniform float fade_time = 1.2;
uniform vec3 violet : source_color = vec3(0.55, 0.24, 1.0);

// Position of a particle caught at `start` at time `born`, on its `lane`
// (orbit radius) and `layer` of the disc (-1..1). Also returns how much it
// has faded (1 = whole) and how close to the core it is (for the glow).
vec3 orbit(vec3 start, float born, float lane, float layer, float rnd, out float scale, out float core) {
	vec3 off = start - center;
	float r0 = max(length(off.xz), 0.05);
	float a0 = atan(off.z, off.x);
	float t = max((released > 0.0 ? released : now) - born, 0.0);
	float k = 1.0 - exp(-2.5 * t);
	float r = mix(r0, lane, k);
	float r_avg = max(mix(r0, lane, k * 0.6), 0.3);
	float omega = min(mix(spin.x, spin.y, clamp(r_avg / radius, 0.0, 1.0)), max_speed / r_avg);
	float a = a0 - omega * t;
	float layer_y = center.y + layer * (0.8 + 3.0 * clamp(lane / radius, 0.0, 1.0));
	float y = mix(start.y, layer_y, 1.0 - exp(-4.0 * t));
	vec3 p = vec3(center.x + cos(a) * r, y, center.z + sin(a) * r);
	scale = 1.0;
	core = 1.0 - clamp(r / radius, 0.0, 1.0);
	if (released > 0.0) {
		// The hole closed: flung out with some of the swirl, falling, and
		// slowing fast in the air.
		float tr = max(now - released, 0.0);
		vec3 out_dir = vec3(cos(a), 0.0, sin(a));
		vec3 swirl = vec3(sin(a), 0.0, -cos(a)) * omega * r * 0.25;
		float sp = mix(burst.x, burst.y, clamp(r / radius, 0.0, 1.0)) * (0.6 + 0.6 * rnd);
		vec3 v = out_dir * sp + swirl + vec3(0.0, lift + (y - center.y) * 1.5, 0.0);
		float drag = 1.8;
		p += v * (1.0 - exp(-drag * tr)) / drag + vec3(0.0, -6.0, 0.0) * tr * tr;
		scale = 1.0 - smoothstep(fade_time * 0.3, fade_time, tr);
		core *= scale;
	}
	return p;
}
