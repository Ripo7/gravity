shader_type spatial;
// Birds: one small mesh (a body and two wings) for every bird, one draw
// call. Wing vertices carry UV.x = -1 / +1 (left / right wing tip weight);
// the shader flaps them. INSTANCE_CUSTOM = (flap phase, flap rate,
// flap amount, wing span 0..1 where small = folded). COLOR = plumage.

render_mode cull_disabled;

varying vec3 plumage;

void vertex() {
	float wing = UV.x;  // -1 left, +1 right, 0 body
	float phase = INSTANCE_CUSTOM.x + TIME * INSTANCE_CUSTOM.y;
	float angle = sin(phase) * INSTANCE_CUSTOM.z;
	if (abs(wing) > 0.01) {
		VERTEX.x *= INSTANCE_CUSTOM.w;
		VERTEX.z = mix(VERTEX.z, VERTEX.z * 0.6 + 0.05, 1.0 - INSTANCE_CUSTOM.w);
		// Rotate the wing about the body's long axis (z), tip moves most.
		float a = angle * sign(wing);
		float x = VERTEX.x;
		float y = VERTEX.y;
		VERTEX.x = x * cos(a) - y * sin(a);
		VERTEX.y = x * sin(a) + y * cos(a);
	}
	plumage = COLOR.rgb;
}

void fragment() {
	ALBEDO = plumage;
	ROUGHNESS = 0.9;
}
