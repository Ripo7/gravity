shader_type spatial;
// Blocks and debris. Per-instance COLOR: rgb = shade of white, a = violet glow.

uniform vec3 violet : source_color = vec3(0.55, 0.24, 1.0);
uniform vec3 violet_deep : source_color = vec3(0.32, 0.08, 0.78);
uniform float glow_strength = 0.9;
uniform float roughness_value = 0.85;

varying float tint;

void vertex() {
	tint = COLOR.a;
}

void fragment() {
	float t = clamp(tint, 0.0, 1.0);
	ALBEDO = mix(COLOR.rgb, violet_deep, t * 0.9);
	ROUGHNESS = roughness_value;
	EMISSION = violet * t * t * t * glow_strength;
}
