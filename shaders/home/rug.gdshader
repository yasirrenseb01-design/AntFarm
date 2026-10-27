shader_type spatial;
// The Home's rug (the keeper, 2026-10-27: more detail): a woven wool rug - a border of bands with a running zigzag, a
// field with rows of small diamonds round a large centre medallion, the wool's pile and a little wear in the middle.
// UV over the top face (0..1 both ways).

uniform vec3 red : source_color = vec3(0.5, 0.17, 0.12);
uniform vec3 cream : source_color = vec3(0.86, 0.72, 0.5);
uniform vec3 navy : source_color = vec3(0.14, 0.18, 0.28);
uniform vec3 gold : source_color = vec3(0.78, 0.55, 0.24);
uniform vec2 size = vec2(1.6, 1.1);          // metres

float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y); }

void fragment() {
	vec2 m = UV * size;                          // metres from a corner
	vec2 e = min(m, size - m);                   // to the nearest edges
	float d = min(e.x, e.y);
	vec3 c = red;
	if (d < 0.03) {
		c = navy;
	} else if (d < 0.05) {
		c = cream;
	} else if (d < 0.13) {
		// the border's zigzag along it
		float along = (e.x < e.y) ? m.y : m.x;
		float z = abs(fract(along * 9.0) - 0.5) * 2.0;
		float band = (d - 0.05) / 0.08;
		c = abs(band - z) < 0.22 ? gold : navy;
	} else if (d < 0.15) {
		c = cream;
	} else {
		vec2 p = m - size * 0.5;
		float md = abs(p.x) / 0.32 + abs(p.y) / 0.22;          // the medallion, a diamond
		if (md < 1.0) {
			c = md < 0.25 ? gold : (md < 0.45 ? navy : (md < 0.55 ? cream : (md < 0.9 ? red * 0.8 : navy)));
		} else {
			// rows of small diamonds in the field
			vec2 q = fract(p * vec2(7.0, 7.0)) - 0.5;
			float sd = abs(q.x) + abs(q.y);
			c = sd < 0.16 ? cream : (sd < 0.22 ? navy : red);
		}
	}
	// the wool: pile, fibre speckle and a slightly worn middle
	float pile = vn(UV * vec2(260.0, 180.0)) * 0.5 + vn(UV * vec2(600.0, 420.0)) * 0.5;
	c *= 0.82 + 0.3 * pile;
	c = mix(c, c * 1.08 + 0.03, smoothstep(0.5, 0.0, length((UV - 0.5) * vec2(1.6, 1.0))) * 0.35);
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}
