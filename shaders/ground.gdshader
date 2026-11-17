shader_type spatial;
// The ground of the city: the road and what is painted on it, the
// pavements, the lawns, the square, the fields around. All of it is worked
// out from where the blocks and the streets are (City.columns and
// City.rows), not read from a picture: it stays sharp from any distance
// and takes no memory. One material for the floor and for the slabs the
// blocks stand on (what is above the floor is a slab).
//
// Everything stands darker where something is on the ground and a little
// around, read from a small picture of the city seen from above
// (City.ground_shade): it is what makes the buildings sit on the ground
// when the sun casts no shadow.

// A slab reaches LEDGE m past its block, into the street; nothing is built
// within WALK m of the edge of a block (City.PAVEMENT).
const float LEDGE = 0.25;
const float WALK = 0.35;

uniform sampler2D shade : filter_linear, repeat_disable;
uniform vec4 area;  // the corner of the picture on the ground (x, z), then its size
uniform float deep = 0.62;
// The blocks: for the k-th along x, where it starts and how long it is (x,
// y); the same along z (z, w). Those there are none of: far away.
uniform vec4 blocks[4];
// The streets between them: the middle and half the width of the k-th that
// runs along z (x, y), of the k-th that runs along x (z, w).
uniform vec4 streets[3];
// What each block is (City's kinds): row k, one a column.
uniform vec4 districts[4];
// How far from its middle (the middle of the world) the ring on the square
// is.
uniform float ring = 2.5;

uniform vec3 asphalt : source_color = vec3(0.25, 0.24, 0.25);
uniform vec3 paint : source_color = vec3(0.86, 0.86, 0.8);
uniform vec3 paving : source_color = vec3(0.52, 0.5, 0.46);
uniform vec3 kerb : source_color = vec3(0.68, 0.67, 0.63);
uniform vec3 plaza : source_color = vec3(0.62, 0.57, 0.49);
uniform vec3 lawn : source_color = vec3(0.4, 0.58, 0.27);
uniform vec3 fields : source_color = vec3(0.37, 0.5, 0.27);
uniform vec3 crops : source_color = vec3(0.56, 0.55, 0.3);

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// How much of a pixel `blur` m across is within `reach` m of a line, `off`
// m from it (a line thinner than the pixel fades, it does not flicker).
float within(float off, float reach, float blur) {
	return clamp((reach - abs(off)) / blur + 0.5, 0.0, min(1.0, 2.0 * reach / blur));
}

// How much of a pixel is past an edge, `off` m beyond it.
float past(float off, float blur) {
	return clamp(off / blur + 0.5, 0.0, 1.0);
}

// Bars, one every `period` m, `share` of it wide: how much of a pixel `at`
// m along they cover (their mean, from far enough for a pixel to hold
// several).
float bars(float at, float period, float share, float blur) {
	float off = abs(fract(at / period) - 0.5) * period;
	float cover = clamp((share * period * 0.5 - off) / blur + 0.5, 0.0, 1.0);
	return mix(cover, share, clamp(blur / period * 2.0 - 0.5, 0.0, 1.0));
}

// The paint on a street: `across` m from its middle (it is `half` m wide
// each side, between the blocks), `clear` m past the nearest street that
// crosses it (negative: in the crossing), `run` m along it.
float marks(float across, float half, float clear, float run, float blur_across, float blur_run) {
	float edge = half - LEDGE;  // the kerb
	float open = step(0.4, clear);
	// Dashes down the middle, and a line along the cars parked at each kerb.
	float dashes = within(across, 0.02, blur_across) * bars(run, 0.6, 0.5, blur_run);
	float bays = within(abs(across) - edge + 0.42, 0.011, blur_across);
	// Where it meets another street, bars across it for those on foot.
	float zebra = bars(across, 0.2, 0.55, blur_across) * within(clear + 0.07, 0.15, blur_run);
	zebra *= step(abs(across), edge - 0.07);
	return max(max(dashes, bays) * open, zebra);
}

// Joints between slabs `size` m across.
float joints(vec2 at, float size, vec2 blur) {
	vec2 off = abs(fract(at / size) - 0.5) * size;
	vec2 line = clamp((off - size * 0.5 + 0.012) / blur + 0.5, vec2(0.0), min(vec2(1.0), 0.024 / blur));
	return max(line.x, line.y) * clamp(1.5 - max(blur.x, blur.y) / size * 3.0, 0.0, 1.0);
}

// Darker and lighter patches, for what grows.
float patches(vec2 at) {
	vec2 turned = vec2(at.x * 0.8 + at.y * 0.6, at.y * 0.8 - at.x * 0.6);
	return sin(turned.x * 1.9 + sin(turned.y * 1.3) * 1.6) * sin(turned.y * 2.3 + sin(at.x * 1.1) * 1.4);
}

// The fields round the city: plots, each sown with something of its own.
vec3 plots(vec2 at) {
	vec2 plot = floor(at / vec2(13.0, 8.0) + 0.5);
	float sown = fract(sin(dot(plot, vec2(12.9898, 78.233))) * 43758.5453);
	return mix(fields, crops, step(0.6, sown) * 0.6) * (0.92 + 0.16 * fract(sown * 7.0));
}

void fragment() {
	vec2 at = world.xz;
	vec2 blur = max(fwidth(at), vec2(0.0005));
	float soft = max(blur.x, blur.y);
	// Along x and along z: how far inside a block (negative: outside), in
	// which one, and how far from the middle of the nearest street, with
	// half its width.
	vec2 into = vec2(-1000.0);
	vec2 which = vec2(0.0);
	vec2 off = vec2(1000.0);
	vec2 half = vec2(0.0);
	for (int k = 0; k < 4; k++) {
		vec2 from = blocks[k].xz;
		vec2 inside = min(at - from, from + blocks[k].yw - at);
		which = mix(which, vec2(float(k)), step(into, inside));
		into = max(into, inside);
	}
	for (int k = 0; k < 3; k++) {
		vec2 away = at - streets[k].xz;
		vec2 nearer = step(abs(away), abs(off));
		off = mix(off, away, nearer);
		half = mix(half, streets[k].yw, nearer);
	}
	vec3 tone;
	if (world.y > 0.001) {
		// On a slab: paving stones, and inside the pavement what its
		// district puts there.
		float inside = min(into.x, into.y);
		float kind = districts[int(which.y + 0.5)][int(which.x + 0.5)];
		tone = paving * (1.0 - 0.22 * joints(at, 0.25, blur));
		if (kind < 0.5) {
			// The square: wide slabs of two stones, and a ring round the
			// middle.
			vec2 slab = floor(at / 0.75);
			float other = mod(slab.x + slab.y, 2.0) * clamp(1.5 - soft / 0.25, 0.0, 1.0);
			tone = plaza * (1.0 - 0.07 * other) * (1.0 - 0.2 * joints(at, 0.75, blur));
			tone = mix(tone, kerb, within(length(at) - ring, 0.05, soft));
		} else if (kind > 1.5) {
			// Houses and parks: a lawn inside the pavement.
			vec3 grown = lawn * (1.0 + 0.06 * patches(at * 1.7));
			tone = mix(tone, grown, past(inside - WALK, soft));
		}
		tone = mix(kerb, tone, past(inside + LEDGE - 0.06, soft));
	} else {
		// On the floor: a street, or the fields round the city.
		vec2 road = vec2(past(half.x - LEDGE - abs(off.x), blur.x), past(half.y - LEDGE - abs(off.y), blur.y));
		float painted = marks(off.x, half.x, abs(off.y) - half.y, at.y, blur.x, blur.y) * road.x;
		painted = max(painted, marks(off.y, half.y, abs(off.x) - half.x, at.x, blur.y, blur.x) * road.y);
		// (Along a kerb the road is a little darker: the gutter.)
		float gutter = within(min(into.x, into.y) + LEDGE + 0.03, 0.03, soft);
		tone = mix(asphalt * (1.0 - 0.25 * gutter), paint, painted * 0.9);
		tone = mix(plots(at), tone, max(road.x, road.y));
	}
	float dark = texture(shade, (at - area.xy) / area.zw).r;
	ALBEDO = tone * (1.0 - deep * dark);
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
