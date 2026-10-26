shader_type spatial;
// Wood for the Home room (game/home.gd): boards along x (or z, along_z) of plank_w wide and plank_l long, each its own
// shade, with grain, a few knots and a dark seam between them; plank_w large = one board (the desk top). Object space, so
// a moved piece keeps its grain.

uniform vec3 tint_a : source_color = vec3(0.42, 0.27, 0.15);
uniform vec3 tint_b : source_color = vec3(0.58, 0.40, 0.24);
uniform float plank_w = 0.14;
uniform float plank_l = 1.2;
uniform bool along_z = false;
uniform float grain = 60.0;
uniform float rough = 0.55;
uniform float gloss_seams = 0.0;
uniform float hilite = 0.0;               // the pointer is on it (a tank's base)

varying vec3 opos;
varying vec3 onrm;

float h1(float n) { return fract(sin(n * 127.1) * 43758.5453); }
float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	opos = VERTEX;
	onrm = NORMAL;
}

void fragment() {
	// along the board (u), across it (v): the top face uses x/z, the sides fall back to x/y or z/y
	vec3 n = abs(onrm);
	vec2 p = along_z ? opos.zx : opos.xz;
	float side = 0.0;
	if (n.y < 0.5) {
		p = n.x > n.z ? vec2(opos.z, opos.y) : vec2(opos.x, opos.y);
		side = 1.0;
	}
	float row = plank_w < 5.0 ? floor(p.y / plank_w) : 0.0;        // (a single board: one shade all over)
	float off = h1(row) * plank_l;
	float col = plank_w < 5.0 ? floor((p.x + off) / plank_l) : 0.0;
	float id = h1(row * 31.0 + col * 7.0);
	vec2 q = vec2(p.x + off, p.y);
	// grain: long wavy lines, stretched along the board
	float w = vnoise(vec2(q.x * 2.0, q.y * grain * 0.15 + id * 9.0));
	float g = sin((q.y * grain + w * 6.0 + id * 20.0) * 3.1416);
	g = smoothstep(-0.2, 1.0, g) * 0.5 + vnoise(q * vec2(3.0, 90.0)) * 0.5;
	// a knot now and then
	vec2 kc = vec2((col + 0.3 + 0.4 * h1(id * 13.0)) * plank_l, (row + 0.5) * plank_w);
	float kd = length((q - kc) * vec2(1.0, 2.5));
	float knot = (h1(id * 5.0) > 0.7) ? smoothstep(0.03, 0.0, kd) : 0.0;
	vec3 c = mix(tint_a, tint_b, 0.35 + 0.4 * id + 0.25 * g);
	c = mix(c, tint_a * 0.55, knot * 0.8);
	// seams between boards (none on a single board)
	float sv = fract(p.y / plank_w);
	float su = fract((p.x + off) / plank_l);
	float seam = 0.0;
	if (plank_w < 5.0 && side < 0.5) {
		seam = max(1.0 - smoothstep(0.0, 0.025, min(sv, 1.0 - sv)), 1.0 - smoothstep(0.0, 0.004, min(su, 1.0 - su)));
	}
	c *= 1.0 - seam * 0.55;
	ALBEDO = c;
	ROUGHNESS = mix(rough, rough + 0.25, seam + g * 0.2);
	SPECULAR = 0.4;
	EMISSION = vec3(1.0, 0.7, 0.35) * hilite * 0.06;
}
