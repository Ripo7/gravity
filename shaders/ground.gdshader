shader_type spatial;
// The ground of the city: one colour, darker where something stands on it
// and a little around, read from a picture of the city seen from above
// (City.ground_shade). It is what makes the buildings sit on the ground
// when the sun casts no shadow, and costs one look-up.

uniform vec3 colour : source_color = vec3(0.25);
uniform sampler2D shade : filter_linear, repeat_disable;
uniform vec4 area;  // the corner of the picture on the ground (x, z), then its size
uniform float deep = 0.62;

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float dark = texture(shade, (world.xz - area.xy) / area.zw).r;
	ALBEDO = colour * (1.0 - deep * dark);
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
