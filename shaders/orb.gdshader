shader_type spatial;
render_mode unshaded, shadows_disabled;
// The orb: a ball of magic that swallows debris. A dark heart, streams of
// light winding round it towards the poles it drains into, and a bright
// rim. It lights itself: nothing here depends on the sun.

uniform vec3 deep : source_color = vec3(0.07, 0.03, 0.2);
uniform vec3 bright : source_color = vec3(0.66, 0.5, 1.0);
uniform float power = 1.0;  // more when it has just swallowed something

varying vec3 at;      // where on the ball (1 across the radius)
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
}

void fragment() {
	// The streams turn round the ball, faster towards its poles.
	float turn = TIME * 2.2 + at.y * 3.0;
	vec3 p = vec3(at.x * cos(turn) - at.z * sin(turn), at.y * 1.6, at.x * sin(turn) + at.z * cos(turn));
	float streams = noise(p * 2.6 + vec3(0.0, -TIME * 0.9, 0.0)) * 0.65 + noise(p * 6.5 + vec3(TIME * 0.6)) * 0.35;
	streams = smoothstep(0.48, 0.74, streams);
	float rim = pow(1.0 - clamp(dot(normalize(-VERTEX), round), 0.0, 1.0), 2.2);
	vec3 colour = mix(deep, bright, streams * 0.85);
	colour += bright * rim * 1.3 + vec3(1.0) * pow(rim, 5.0) * 0.6;
	ALBEDO = colour * power;
}
