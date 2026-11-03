shader_type spatial;
// Blocks and debris. Per-instance COLOR: rgb = shade of white, a = violet glow.

uniform vec3 violet : source_color = vec3(0.55, 0.24, 1.0);
uniform float glow_strength = 2.2;
uniform float roughness_value = 0.85;

varying float tint;

void vertex() {
	tint = COLOR.a;
}

void fragment() {
	float t = clamp(tint, 0.0, 1.0);
	ALBEDO = mix(COLOR.rgb, violet, t * 0.85);
	ROUGHNESS = roughness_value;
	EMISSION = violet * t * t * glow_strength;
}
