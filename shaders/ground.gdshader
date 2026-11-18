shader_type spatial;
// The ground of the bench: one colour, with a line every metre and a
// heavier one every five. On a bare ground they are what shows how fast and
// how far the brute goes. Computed for each pixel: there is no picture.

uniform vec3 colour : source_color = vec3(0.42, 0.43, 0.45);
uniform vec3 ink : source_color = vec3(0.3, 0.31, 0.33);

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// How much of this pixel the lines laid `every` m apart, `wide` m wide,
// cover (0 to 1). A line thinner than a pixel is drawn a pixel wide and
// that much fainter, and the lines fade out once a pixel holds a good part
// of a square, so nothing flickers from far.
float lines(vec2 at, float every, float wide) {
	vec2 near = abs(fract(at / every + 0.5) - 0.5) * every;
	vec2 pixel = max(fwidth(at), vec2(0.0001));
	vec2 half_wide = max(vec2(wide * 0.5), pixel * 0.5);
	vec2 drawn = 1.0 - smoothstep(half_wide, half_wide + pixel, near);
	drawn *= min(vec2(wide) / pixel, vec2(1.0));
	drawn *= 1.0 - smoothstep(vec2(every * 0.15), vec2(every * 0.4), pixel);
	return max(drawn.x, drawn.y);
}

void fragment() {
	float drawn = max(lines(world.xz, 1.0, 0.03) * 0.55, lines(world.xz, 5.0, 0.07));
	ALBEDO = mix(colour, ink, drawn);
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
