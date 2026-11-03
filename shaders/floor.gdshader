shader_type spatial;
// White floor with a faint 2 m grid so speed and distance read clearly.

uniform vec3 base : source_color = vec3(0.86, 0.86, 0.88);
uniform vec3 line : source_color = vec3(0.78, 0.79, 0.83);
uniform float cell = 2.0;
uniform float width = 0.02;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 g = abs(fract(world_pos.xz / cell + 0.5) - 0.5) * cell;
	vec2 fw = fwidth(world_pos.xz) * 1.5;
	vec2 a = 1.0 - smoothstep(vec2(width), vec2(width) + fw, g);
	float l = max(a.x, a.y);
	// Lines fade with distance to avoid moire.
	float fade = clamp(1.0 - length(fw) * 4.0, 0.0, 1.0);
	ALBEDO = mix(base, line, l * fade);
	ROUGHNESS = 0.9;
}
