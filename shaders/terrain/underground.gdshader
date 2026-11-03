shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, fog_disabled;
// The nest view's surroundings (the keeper, 2026-11-03: "the background of the nest view - let it look underground, it
// floats too much"): a big sphere round the block, seen from inside. Below the ground's level the soil runs on round
// the block in its own layers - loam, clay, sand, as soil.gdshader colours them - dimmer and darker with distance and
// depth, with a coarse grain; above it the dim room. Only a backdrop: nothing is in it.

uniform float top_y = 72.0;          // the ground's level (voxels)
uniform float clay_top = 14.0;       // where the clay and the sand start, below the top (voxels)
uniform float sand_top = 41.0;
uniform vec3 sky = vec3(0.0035, 0.0026, 0.002);   // (linear: the room's dark, as the view's background colour was)

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void fragment() {
	// the ground's level is the block's top, as far out as the sphere; the soil's layers below it squeezed toward the
	// level (the sphere is ~17 blocks out: the bands as they would look that far off, not stretched over its whole side)
	float depth = (top_y - wpos.y) * 0.12;
	vec3 c = sky;
	if (depth > 0.0) {
		vec3 p = wpos * 0.12;
		float wob = (noise(p * 0.08) - 0.5) * 6.0;
		vec3 loam = vec3(0.30, 0.20, 0.12);
		vec3 clay = vec3(0.62, 0.38, 0.22);
		vec3 sand = vec3(0.80, 0.66, 0.45);
		vec3 s = mix(loam, clay, smoothstep(clay_top - 3.0, clay_top + 3.0, depth + wob));
		s = mix(s, sand, smoothstep(sand_top - 4.0, sand_top + 4.0, depth + wob));
		// grain: clods and pebbles
		float g = noise(p * 0.45) * 0.6 + noise(p * 1.7) * 0.4;
		s *= 0.75 + 0.5 * g;
		// dim (the light colours are linear: these are dark): the room's light hardly reaches it, less so deeper down
		c = s * 0.06 * exp(-max(depth - 30.0, 0.0) / 90.0);
		// the ground's edge: a darker line of turf at the level
		c = mix(c, vec3(0.012, 0.014, 0.008), smoothstep(1.5, 0.0, depth));
	}
	ALBEDO = c;
}
