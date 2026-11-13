shader_type spatial;
render_mode diffuse_burley;
// Wolf spider (tools/blender/props/spider.py): COLOR.a = part id / 16 (0 body, 1-4 left legs front to back, 5-8 right
// legs, 9/10 left/right pedipalps, 11/12 left/right chelicerae - v0.13.4). Legs: jointed, their knees bent upward, the
// feet set down and left where they are while the body goes over them, in alternating fours (leg_ik.gdshaderinc; UV.x =
// the leg's piece; the joints come from wolf_spider.json). UV.x 9 on the body: the eyes (glossy).
// INSTANCE_CUSTOM: x = gait phase (one turn = a stride of ground covered), y = 0..1 how far into a strike (the two front
// pairs reared up to grab; eased in and out by the view) / 2 dead (legs drawn in, knees up) / 3 + 0..1 on its back, alive,
// kicking that hard (the view turns it over) / 5 feeding on prey held before its fangs (palps and front legs round it,
// the chelicerae working) / 6 shaking a bitten ant (enemies/spider_prey.gd), z = clock, w = how much it is walking
// (+2 held: its body twists - v0.13.3).
const float WAIST_X = -0.4;      // tools/blender/props/spider.py: the abdomen from x -6.6 to the waist at -0.4
const vec3 PALP_BASE = vec3(3.85, 1.75, 0.72);    // spider.py SP_PALP_BASE (one side)
const vec3 CHEL_TOP = vec3(4.3, 2.35, 0.36);      // spider.py SP_CHEL_TOP (one side)
const vec3 NECK = vec3(1.6, 1.9, 0.0);            // the front of the carapace swings about here when it shakes prey

varying float gloss;
varying vec3 obj;

#include "res://shaders/terrain/ground_h.gdshaderinc"
#include "res://shaders/creatures/leg_ik.gdshaderinc"
#include "res://shaders/creatures/props_h.gdshaderinc"

mat3 rot_x(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(1, 0, 0), vec3(0, c, s), vec3(0, -s, c)); }
mat3 rot_y(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(c, 0, -s), vec3(0, 1, 0), vec3(s, 0, c)); }
mat3 rot_z(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(c, s, 0), vec3(-s, c, 0), vec3(0, 0, 1)); }

void vertex() {
	float part = floor(COLOR.a * 16.0 + 0.5);
	float gait = INSTANCE_CUSTOM.x;
	float state = INSTANCE_CUSTOM.y;
	float t = INSTANCE_CUSTOM.z;
	float held = INSTANCE_CUSTOM.w > 1.5 ? 1.0 : 0.0;
	float mv = min(INSTANCE_CUSTOM.w - 2.0 * held, 1.0);
	float strike = state <= 1.0 ? state : 0.0;
	bool dead = state > 1.5 && state < 2.5;
	bool back = state > 2.5 && state < 4.5;
	bool feed = state > 4.5 && state < 5.5;
	bool shake = state > 5.5;
	float kick = back ? state - 3.0 : 0.0;
	float agit = max(held, max(strike, back ? 0.4 + kick : 0.0));     // how much it struggles
	gloss = (part == 0.0 && UV.x > 8.5) ? 1.0 : 0.0;
	obj = VERTEX;
	if (part >= 1.0 && part <= 8.0) {
		int i = int(part) - 1;
		float li = mod(part - 1.0, 4.0);
		float side = part < 4.5 ? -1.0 : 1.0;
		// alternating fours: L1 R2 L3 R4 against R1 L2 R3 L4
		float grp = mod(li + (side < 0.0 ? 0.0 : 1.0), 2.0) * 0.5;
		vec3 a = leg_ankle(i, gait / TAU + grp, 1.0);      // (standing still the legs stay as they were in the step)
		if (strike > 0.0 && li < 1.5) {
			// rearing: the two front pairs lifted off the ground and reaching forward (eased: strike is 0..1)
			a = mix(a, ankle[i] + vec3(0.6, 2.8 + 0.5 * sin(t * 8.0 + li), -0.8 * side), smoothstep(0.0, 1.0, strike));
		}
		if (dead || back) {
			// dead: the feet drawn in beside the body, the knees standing up over it
			vec2 o = normalize(ankle[i].xz - hip[i].xz);
			float near = abs(length(knee[i] - hip[i]) - length(ankle[i] - knee[i])) + 2.5;      // (tools/dev/leg_clip.py: nearer, the femur stands into the carapace)
			a = vec3(hip[i].x + o.x * near, 0.3, hip[i].z + o.y * near);
			if (back) {
				// on its back, kicking at the sky - spread out round it, not bunched over the belly (v0.13.6)
				a = leg_kick(i, vec3(hip[i].x + o.x * (near + 2.2), -1.0, hip[i].z + o.y * (near + 2.2)), kick * 1.3, t);
			}
		}
		leg_place_up(i, UV.x, a, VERTEX, NORMAL, MODEL_MATRIX[1].y < 0.0 ? -1.0 : 1.0);     // (a body on its back: its knees bent toward the sky)
	} else {
		if (part == 9.0 || part == 10.0) {
			// the pedipalps: feeling the ground as it goes; raised and reaching with a strike; closed on prey
			float side = part == 9.0 ? -1.0 : 1.0;
			vec3 piv = vec3(PALP_BASE.xy, PALP_BASE.z * side);
			float lift = 0.12 * sin(t * 2.4 + side * 1.3) * (0.3 + mv) + strike * 0.45;
			float inward = 0.0;
			if (feed || shake) {
				lift = 0.25 + 0.08 * sin(t * 6.0 + side);
				inward = 0.32;
			}
			mat3 R = rot_y(inward * side) * rot_z(lift);
			VERTEX = piv + R * (VERTEX - piv);
			NORMAL = R * NORMAL;
		} else if (part == 11.0 || part == 12.0) {
			// the chelicerae: apart a little with a strike; working in turn, side to side, as it feeds
			float side = part == 11.0 ? -1.0 : 1.0;
			vec3 piv = vec3(CHEL_TOP.xy, CHEL_TOP.z * side);
			float open = strike * 0.2;
			float fwd = 0.0;
			if (feed) {
				open = 0.1 + 0.12 * max(0.0, sin(t * 5.0 + side * 1.6));
				fwd = 0.18;
			}
			if (shake) {
				open = 0.05;
				fwd = 0.25;
			}
			mat3 R = rot_z(fwd) * rot_x(-open * side);
			VERTEX = piv + R * (VERTEX - piv);
			NORMAL = R * NORMAL;
		}
		VERTEX.y += 0.06 * sin(gait * 2.0) * mv;    // body bobs with the stride
		if (VERTEX.x < WAIST_X) {
			// the abdomen swings on its waist as it struggles (side to side, a little up and down)
			vec3 piv = vec3(WAIST_X, 1.8, 0.0);
			mat3 R = rot_z(agit * 0.09 * sin(t * 3.7 + 1.0)) * rot_y(agit * (0.16 * sin(t * 5.3) + 0.06 * sin(t * 11.0)));
			VERTEX = piv + R * (VERTEX - piv);
			NORMAL = R * NORMAL;
		} else {
			// the carapace and fangs: a short dip and lift with each lunge
			VERTEX.y += agit * 0.12 * sin(t * 7.0) * clamp((VERTEX.x - 1.0) / 4.0, 0.0, 1.0);
			if (feed) {
				VERTEX.y -= 0.12 * clamp((VERTEX.x - 1.0) / 4.0, 0.0, 1.0);     // head bowed over the meal
			}
			if (shake && VERTEX.x > NECK.x) {
				mat3 R = rot_y(0.14 * sin(t * 19.0));                           // the front shaken from side to side
				VERTEX = NECK + R * (VERTEX - NECK);
				NORMAL = R * NORMAL;
			}
		}
	}
	if (dead && INSTANCE_CUSTOM.x > 0.5) {
		// a carcass (outworld_props): the abdomen torn off at the waist and lying askew, two legs pulled off beside it
		// (v0.13.7, the keeper: "when it dies let it come apart a little - the legs, the abdomen")
		if (part == 0.0 && obj.x < WAIST_X) {
			vec3 piv = vec3(WAIST_X, 1.8, 0.0);
			mat3 R = rot_y(0.5) * rot_z(-0.12);
			VERTEX = piv + R * (VERTEX - piv) + vec3(-1.2, -0.15, 0.7);
			NORMAL = R * NORMAL;
		}
		if (part == 2.0 || part == 7.0) {
			VERTEX += vec3(0.9, 0.0, (part == 2.0 ? -1.0 : 1.0) * 2.6);
		}
	}
	VERTEX = follow_ground_soft(VERTEX, MODEL_MATRIX);     // every part of the body stands on the floor under it
	VERTEX = on_props(VERTEX, MODEL_MATRIX, (part >= 1.0 && part <= 8.0) ? 1.0 : 0.0, obj.y, 5.0);    // and over the litter
}

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

void fragment() {
	vec3 base = pow(COLOR.rgb, vec3(2.2));    // vertex colours are authored in sRGB
	if (gloss > 0.5) {
		// the eyes: black glass, a hard highlight
		ALBEDO = base;
		ROUGHNESS = 0.06;
		SPECULAR = 1.0;
		CLEARCOAT = 1.0;
		CLEARCOAT_ROUGHNESS = 0.02;
	} else {
		// fur: fine light and dark hairs, mostly along the body (cells long in x), a grey sheen at grazing angles
		vec3 q = obj * vec3(34.0, 80.0, 80.0);
		float h = hash3(floor(q));
		float h2 = hash3(floor(q * 1.7 + 3.1));
		ALBEDO = base * (0.78 + 0.34 * h) * (0.9 + 0.2 * h2);
		ROUGHNESS = 0.9;
		SPECULAR = 0.25;
		RIM = 0.55;
		RIM_TINT = 0.85;
	}
}
