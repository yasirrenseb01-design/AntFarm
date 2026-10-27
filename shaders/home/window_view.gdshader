shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
// What the Home's window looks out on (the keeper, 2026-10-27: mountains and forest), painted in code on two planes
// outside it: "far" - the sky (its colour by the hour, the sun's glow low over the hills, stars at night) and three
// ranges of mountains, paler with distance; "near" - a line of forest (conifers and round crowns) in front of a meadow,
// see-through above the trees. day: 0 night .. 1 full day; dusk: 0 .. 1 the low sun's orange; sun_u: where the sun is
// across the view (0..1).

uniform bool near = false;
uniform float day = 1.0;
uniform float dusk = 0.0;
uniform float sun_u = 0.5;
uniform float sun_v = 0.6;

float h1(float n) { return fract(sin(n * 127.1) * 43758.5453); }
float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n1(float x) { float i = floor(x); float f = fract(x); f = f * f * (3.0 - 2.0 * f); return mix(h1(i), h1(i + 1.0), f); }
float ridge(float x, float seed) {
	return n1(x * 1.0 + seed) * 0.55 + n1(x * 2.3 + seed * 2.0) * 0.28 + n1(x * 6.1 + seed * 3.0) * 0.12 + n1(x * 15.0 + seed) * 0.05;
}

vec3 sky_at(float v) {
	vec3 top = mix(vec3(0.015, 0.025, 0.07), vec3(0.32, 0.55, 0.85), day);
	vec3 low = mix(vec3(0.04, 0.06, 0.12), vec3(0.72, 0.84, 0.94), day);
	low = mix(low, vec3(0.98, 0.62, 0.36), dusk);
	top = mix(top, vec3(0.42, 0.38, 0.6), dusk * 0.6);
	return mix(low, top, smoothstep(0.35, 1.0, v));
}

void fragment() {
	vec2 uv = vec2(UV.x, 1.0 - UV.y);           // v up
	vec3 c;
	float a = 1.0;
	if (!near) {
		c = sky_at(uv.y);
		// the sun's glow (by day) and stars (at night)
		float sd = length((uv - vec2(sun_u, sun_v)) * vec2(2.0, 1.0));
		c += vec3(1.0, 0.85, 0.6) * (exp(-sd * 9.0) * 0.6 + exp(-sd * 60.0) * 1.5) * smoothstep(0.0, 0.2, day) * (0.4 + dusk);
		float st = step(0.997, h2(floor(uv * vec2(900.0, 450.0))));
		c += vec3(st) * (1.0 - smoothstep(0.0, 0.25, day)) * smoothstep(0.45, 0.7, uv.y) * 0.8;
		// three ranges, nearer ones lower, darker, less hazy
		for (int i = 0; i < 3; i++) {
			float fi = float(i);
			float base = 0.36 - fi * 0.04;
			float hgt = 0.34 - fi * 0.09;
			float rx = uv.x * (2.5 + fi * 1.6) + fi * 13.7;
			float top = base + hgt * ridge(rx, fi * 7.1);
			if (uv.y < top) {
				vec3 rock = i == 0 ? vec3(0.42, 0.48, 0.6) : (i == 1 ? vec3(0.27, 0.36, 0.38) : vec3(0.15, 0.27, 0.17));
				rock *= 0.85 + 0.15 * n1(rx * 20.0 + uv.y * 30.0);
				// snow on the far range's peaks
				if (i == 0) { rock = mix(rock, vec3(0.92, 0.94, 0.97), smoothstep(top - 0.035, top - 0.005, uv.y) * smoothstep(0.58, 0.64, top)); }
				float haze = 0.45 - fi * 0.19;
				c = mix(rock, sky_at(0.3), haze);
				c *= mix(0.12, 1.0, day);
				c = mix(c, c * vec3(1.15, 0.8, 0.6), dusk * 0.6);
			}
		}
	} else {
		// the forest's edge: a row of trees on a ridge, a meadow in front
		float ground = 0.22 + 0.05 * n1(uv.x * 3.0);
		a = 0.0;
		c = vec3(0.0);
		float cells = 90.0;
		for (int k = -1; k <= 1; k++) {
			float cell = floor(uv.x * cells) + float(k);
			float id = h1(cell * 3.17);
			float cx = (cell + 0.3 + 0.4 * h1(cell * 7.1)) / cells;
			float ht = 0.12 + 0.16 * id;
			float base = 0.2 + 0.05 * n1(cx * 3.0);
			float w = (0.6 + 0.6 * h1(cell * 5.3)) / cells;
			float dy = (uv.y - base) / ht;
			if (dy > 0.0 && dy < 1.0) {
				bool conifer = h1(cell * 11.0) > 0.35;
				float half_w = conifer ? w * (1.0 - dy) * (0.85 + 0.15 * sin(dy * 40.0 + id * 9.0)) : w * 1.3 * sqrt(max(0.0, 1.0 - pow(dy * 2.0 - 1.1, 2.0)));
				if (abs(uv.x - cx) < half_w || (dy < 0.12 && abs(uv.x - cx) < w * 0.12)) {
					vec3 g = conifer ? vec3(0.1, 0.2, 0.12) : vec3(0.17, 0.3, 0.13);
					g *= 0.75 + 0.5 * n1(uv.y * 60.0 + id * 30.0) * (0.6 + 0.4 * (uv.x - cx) / max(half_w, 1e-4));
					c = g;
					a = 1.0;
				}
			}
		}
		if (uv.y < ground) {
			c = mix(vec3(0.3, 0.45, 0.18), vec3(0.42, 0.56, 0.24), n1(uv.x * 30.0 + uv.y * 80.0));
			c *= 0.9 + 0.2 * h2(floor(uv * 300.0));
			a = 1.0;
		}
		c *= mix(0.08, 1.0, day);
		c = mix(c, c * vec3(1.2, 0.85, 0.6), dusk * 0.5);
	}
	ALBEDO = c;
	ALPHA = a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
