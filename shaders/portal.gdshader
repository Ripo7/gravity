shader_type spatial;
// The horizontal portal the stones fall through: a dark swirling eye with a
// bright violet rim. Drawn on a flat disc, visible from below.
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;

uniform vec3 violet : source_color = vec3(0.55, 0.24, 1.0);
uniform vec3 deep : source_color = vec3(0.05, 0.0, 0.12);
uniform float open = 1.0;

varying vec2 p;

void vertex() {
	p = VERTEX.xz;  // unit disc
}

void fragment() {
	float r = length(p) * 2.0;  // 0 centre, 1 rim (CylinderMesh radius 0.5)
	float a = atan(p.y, p.x);
	float swirl = sin(a * 5.0 + r * 9.0 - TIME * 4.0) * 0.5 + 0.5;
	float rim = smoothstep(0.75, 0.97, r) * (1.0 - smoothstep(0.97, 1.0, r));
	vec3 col = mix(deep, violet * 0.6, swirl * r * r);
	col += violet * 2.2 * rim;
	ALBEDO = col;
	ALPHA = (1.0 - smoothstep(0.98, 1.0, r)) * open;
}
