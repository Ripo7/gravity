shader_type spatial;
// The orb: loose debris fused into one lumpy ball, held together by the
// same blue air as the shock wave. It is lit facet by facet like the broken
// faces of the shards it is made of, in their colours, and glows along its
// seams and its rim; more while it is still drawing debris in.

uniform vec3 wall : source_color = vec3(0.62, 0.62, 0.65);
uniform vec3 wood : source_color = vec3(0.72, 0.58, 0.42);
uniform vec3 glow : source_color = vec3(0.45, 0.72, 1.0);
uniform float power = 1.0;  // how strongly it glows
uniform float lumps = 0.16;  // how far from round, as a share of its size

varying vec3 at;      // where on the ball (it is 1 across the radius)
varying vec3 round;   // the way the ball faces there, seen from the eye

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(hash(i), hash(i + vec3(1.0, 0.0, 0.0)), f.x);
	float b = mix(hash(i + vec3(0.0, 1.0, 0.0)), hash(i + vec3(1.0, 1.0, 0.0)), f.x);
	float c = mix(hash(i + vec3(0.0, 0.0, 1.0)), hash(i + vec3(1.0, 0.0, 1.0)), f.x);
	float d = mix(hash(i + vec3(0.0, 1.0, 1.0)), hash(i + vec3(1.0, 1.0, 1.0)), f.x);
	return mix(mix(a, b, f.y), mix(c, d, f.y), f.z);
}

void vertex() {
	at = VERTEX;
	round = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	VERTEX += NORMAL * (noise(VERTEX * 2.1 + vec3(3.7)) - 0.5) * 2.0 * lumps;
}

void fragment() {
	vec3 facet = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	facet = dot(facet, VERTEX) > 0.0 ? -facet : facet;
	NORMAL = facet;
	// Patches of the two colours of the house, with the grain of a break.
	float patch = smoothstep(0.58, 0.64, noise(at * 1.9 + vec3(11.0)));
	float grain = hash(floor(at * 7.0)) * 0.6 + hash(floor(at * 19.0)) * 0.4;
	ALBEDO = mix(wall, wood, patch) * (0.55 + 0.4 * grain);
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
	// Seams between what was fused, and the rim.
	float seam = 1.0 - smoothstep(0.0, 0.045, abs(noise(at * 3.3 + vec3(5.0)) - 0.5));
	float rim = pow(1.0 - clamp(dot(normalize(-VERTEX), round), 0.0, 1.0), 2.5);
	EMISSION = glow * (seam * 1.0 + rim * 0.55) * power;
}
