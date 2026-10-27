shader_type spatial;
// The soil in a keeper's tank, seen through its glass - the same in the Home's room (view/home/home_kit._tank) and in
// the foraging box in the game (view/outworld/parts/outworld_scene._build_soil_edge): as deep as the nest's block
// (view/common/tank_spec.gd), in the nest card's layers (loam, then clay, then sand lower down: game/nest_card.gd), and
// on the long faces the colony's real nest, where it lies along the box (nest_tex: its side view, written with each
// save). [Inference, drawn for the keeper to see: the nest is dug under its entrance, not against the glass; its side
// view is put on the glass where it lies along the box, as through the soil.]
// Coordinates: the mesh's own (opos), mpu metres to one of its units.

uniform float mpu = 1.0;
uniform float soil_top = 0.0;          // where the nest's top is (the ground), mesh units
uniform float nest_x0 = 0.0;           // the nest's block along x, mesh units
uniform float nest_w = 1.0;
uniform float nest_h = 1.0;
uniform sampler2D nest_tex : filter_linear;
uniform bool has_tex = false;
uniform sampler2D top_tex : filter_linear_mipmap, source_color;   // the foraging floor from above (the Home: outworld_card.gd)
uniform bool has_top = false;
uniform vec2 top_size = vec2(1.0);       // the soil's top, mesh units (x, z)
uniform float seed = 0.0;
uniform float hilite = 0.0;            // the pointer is on its tank (the Home)

varying vec3 opos;
varying vec3 onrm;

float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) {
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
	vec3 m = opos * mpu;                                  // metres
	float along = abs(onrm.x) > 0.5 ? m.z : m.x;
	float depth = (soil_top - opos.y) * mpu;              // metres below the ground
	// the nest card's soil (its voxels are 1.5 mm: clay from 11-17 down, sand from 37-45)
	vec3 loam = vec3(0.3, 0.2, 0.12);
	vec3 clay = vec3(0.55, 0.34, 0.2);
	vec3 sand = vec3(0.72, 0.59, 0.4);
	vec3 c = mix(loam, clay, clamp((depth - 0.0165) / 0.009, 0.0, 1.0));
	c = mix(c, sand, clamp((depth - 0.0555) / 0.012, 0.0, 1.0));
	vec2 p = vec2(along, m.y) * 60.0 + seed;
	float n = vn(p) * 0.5 + vn(p * 2.3) * 0.3 + vn(p * 7.0) * 0.2;
	c *= 0.78 + 0.36 * n;
	c *= 0.86 + 0.28 * h2(floor(vec2(along, m.y) * 1300.0));     // grains
	if (has_tex && abs(onrm.z) > 0.5) {
		float u = (opos.x - nest_x0) / nest_w;
		float v = (soil_top - opos.y) / nest_h;
		if (u >= 0.0 && u <= 1.0 && v >= 0.0 && v <= 1.0) {
			vec3 t = texture(nest_tex, vec2(u, v)).rgb;
			c = t * (0.9 + 0.2 * h2(floor(vec2(along, m.y) * 1300.0)));
		}
	}
	if (onrm.y > 0.5) {
		// the top: the foraging floor's dry, darker crumb (the game draws its own ground there)
		vec2 q = m.xz * 60.0 + seed;
		float k = vn(q) * 0.5 + vn(q * 2.3) * 0.3 + vn(q * 7.0) * 0.2;
		c = mix(vec3(0.13, 0.09, 0.06), vec3(0.3, 0.21, 0.13), k) * (0.8 + 0.4 * h2(floor(m.xz * 1300.0)));
		if (has_top) {
			c = texture(top_tex, opos.xz / top_size + 0.5).rgb * 0.7;      // (it is lit again here: a picture already lit)
		}
	}
	ALBEDO = c * 0.8;
	ROUGHNESS = 0.95;
	EMISSION = vec3(0.12, 0.08, 0.03) * hilite;
}
