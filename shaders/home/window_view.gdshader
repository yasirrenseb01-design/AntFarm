shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
// What the Home's window looks out on (the keeper, 2026-10-27: mountains and forest), painted in code on two cylinders
// round the house (v0.11.51: flat planes showed their edges from close to the window): "far" - the sky (its colour by the hour, the sun's glow low over the hills, stars at night) and three
// ranges of mountains, paler with distance; "near" - a line of forest (conifers and round crowns) in front of a meadow,
// see-through above the trees. day: 0 night .. 1 full day; dusk: 0 .. 1 the low sun's orange; sun_dir: toward the sun;
// wrap: how many times the pattern goes round (UV.x once round the cylinder).

uniform bool near = false;
uniform float day = 1.0;
uniform float dusk = 0.0;
uniform vec3 sun_dir = vec3(-1.0, 0.5, 0.0);
uniform float wrap = 1.0;
uniform float y0 = 0.0;          // the cylinder's foot and height, in the world (where the picture's v runs 0..1)
uniform float height = 10.0;
varying vec3 wdir;
uniform mat4 to_room = mat4(1.0);  // the world to the room's own metres (the room drawn round a box in the game, scaled)
varying vec3 wpos;

void vertex() {
	wpos = (to_room * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wdir = normalize(wpos - vec3(0.0, 1.5, 0.0));
}

float h1(float n) { return fract(sin(n * 127.1) * 43758.5453); }
float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n1(float x) { float i = floor(x); float f = fract(x); f = f * f * (3.0 - 2.0 * f); return mix(h1(i), h1(i + 1.0), f); }
float ridge(float x, float seed) {
	// (peaks: the noise folded at its middle makes sharp ridges, smooth valleys)
	float a = 1.0 - abs(n1(x + seed) * 2.0 - 1.0);
	float b = 1.0 - abs(n1(x * 2.7 + seed * 2.0) * 2.0 - 1.0);
	return a * 0.6 + b * 0.28 + n1(x * 7.3 + seed * 3.0) * 0.1 + n1(x * 19.0 + seed) * 0.02;
}

uniform mat3 sky_from_room = mat3(1.0);   // the room's directions into the sky's frame (zodiac_stars.to_room, inverse)
uniform vec4 zodiac[96];                  // the zodiac's stars: direction in the room, brightness (0: no more)

float h3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }

// One layer of faint stars: in each cell of a grid over the sky's directions (n across), one star or none (density),
// somewhere inside it, of a random brightness up to bmax; drawn a pixel or so across wherever it is.
float field_stars(vec3 e, float n, float density, float bmax) {
	vec3 g = e * n;
	vec3 cell = floor(g);
	if (h3(cell) > density) { return 0.0; }
	vec3 at = cell + 0.2 + 0.6 * vec3(h3(cell + 1.3), h3(cell + 2.7), h3(cell + 4.1));
	float px = max(length(fwidth(g)), 1e-4);
	float b = bmax * pow(h3(cell + 7.7), 3.0);
	return b * (1.0 - smoothstep(0.0, 1.6 * px, length(g - at)));
}

vec3 sky_at(float v) {
	vec3 top = mix(vec3(0.015, 0.025, 0.07), vec3(0.32, 0.55, 0.85), day);
	vec3 low = mix(vec3(0.04, 0.06, 0.12), vec3(0.72, 0.84, 0.94), day);
	low = mix(low, vec3(0.98, 0.62, 0.36), dusk);
	top = mix(top, vec3(0.42, 0.38, 0.6), dusk * 0.6);
	return mix(low, top, smoothstep(0.35, 1.0, v));
}

void fragment() {
	// (from where it is in the world: the cylinder mesh's own UVs do not run 0..1 up its side)
	vec2 uv = vec2((atan(wpos.z, wpos.x) / 6.2831853 + 0.5) * wrap, (wpos.y - y0) / height);
	vec3 c;
	float a = 1.0;
	if (!near) {
		c = sky_at(uv.y);
		// the sun's glow (by day) and stars (at night)
		float sd = acos(clamp(dot(wdir, normalize(sun_dir)), -1.0, 1.0)) * 1.6;
		c += vec3(1.0, 0.85, 0.6) * (exp(-sd * 9.0) * 0.6 + exp(-sd * 60.0) * 1.5) * smoothstep(0.0, 0.2, day) * (0.4 + dusk);
		// stars (the keeper, 2026-10-27: a repeating pattern, and not over the whole sky): faint ones scattered at random
		// over the sky's sphere in its own frame, three sizes of cell, and the zodiac's bright stars where they are
		// (zodiac_stars.gd), all turning with the hour; fading into the haze toward the horizon
		float night = 1.0 - smoothstep(0.0, 0.25, day);
		if (night > 0.0 && wdir.y > -0.05) {
			vec3 e = sky_from_room * wdir;
			float sum = field_stars(e, 60.0, 0.18, 0.8) + field_stars(e, 130.0, 0.07, 0.4) + field_stars(e, 260.0, 0.025, 0.25);
			for (int i = 0; i < 96; i++) {
				vec4 z = zodiac[i];
				if (z.w <= 0.0) { break; }
				float ang = 1.0 - dot(wdir, z.xyz);           // (about half the angle, squared)
				sum += 1.6 * z.w * exp(-ang / (3.0e-6 * (0.6 + z.w)));
			}
			c += vec3(0.95, 0.97, 1.0) * sum * night * smoothstep(-0.05, 0.25, wdir.y);
		}
		// three ranges, nearer ones lower, darker, less hazy
		for (int i = 0; i < 3; i++) {
			float fi = float(i);
			float base = 0.36 - fi * 0.04;
			float hgt = 0.34 - fi * 0.09;
			float rx = uv.x * (7.0 + fi * 4.0) + fi * 13.7;
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
		float cells = 30.0;
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
			c *= 0.9 + 0.2 * h2(floor(uv * vec2(80.0, 300.0)));
			a = 1.0;
		}
		c *= mix(0.08, 1.0, day);
		c = mix(c, c * vec3(1.2, 0.85, 0.6), dusk * 0.5);
	}
	ALBEDO = c;
	ALPHA = a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
