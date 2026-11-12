shader_type spatial;
render_mode diffuse_burley;
// Wolf spider (tools/blender/props/spider.py): COLOR.a = part id / 16 (0 body, 1-4 left legs front to back, 5-8 right
// legs). Legs: jointed, their knees bent upward, the feet set down and left where they are while the body goes over
// them, in alternating fours (leg_ik.gdshaderinc; UV.x = the leg's piece; the joints come from wolf_spider.json).
// INSTANCE_CUSTOM: x = gait phase (one turn = a stride of ground covered), y = 0..1 how far into a strike (the two front
// pairs reared up to grab; eased in and out by the view) / 2 dead (legs drawn in, knees up) / 3 + 0..1 on its back, alive,
// kicking that hard (the view turns it over), z = clock, w = how much it is walking (+2 held: its body twists - v0.13.3).
const float WAIST_X = -0.4;      // tools/blender/props/spider.py: the abdomen from x -6.6 to the waist at -0.4

#include "res://shaders/terrain/ground_h.gdshaderinc"
#include "res://shaders/creatures/leg_ik.gdshaderinc"

void vertex() {
	float part = floor(COLOR.a * 16.0 + 0.5);
	float gait = INSTANCE_CUSTOM.x;
	float strike = INSTANCE_CUSTOM.y;
	float t = INSTANCE_CUSTOM.z;
	float held = INSTANCE_CUSTOM.w > 1.5 ? 1.0 : 0.0;
	float mv = min(INSTANCE_CUSTOM.w - 2.0 * held, 1.0);
	bool back = strike > 2.5;
	float kick = back ? strike - 3.0 : 0.0;
	float agit = max(held, max(clamp(strike, 0.0, 1.0), back ? 0.4 + kick : 0.0));     // how much it struggles
	if (part >= 1.0) {
		int i = int(part) - 1;
		float li = mod(part - 1.0, 4.0);
		float side = part < 4.5 ? -1.0 : 1.0;
		// alternating fours: L1 R2 L3 R4 against R1 L2 R3 L4
		float grp = mod(li + (side < 0.0 ? 0.0 : 1.0), 2.0) * 0.5;
		vec3 a = leg_ankle(i, gait / TAU + grp, 1.0);      // (standing still the legs stay as they were in the step)
		if (strike > 0.0 && strike <= 1.0 && li < 1.5) {
			// rearing: the two front pairs lifted off the ground and reaching forward (eased: strike is 0..1)
			a = mix(a, ankle[i] + vec3(0.6, 2.8 + 0.5 * sin(t * 8.0 + li), -0.8 * side), smoothstep(0.0, 1.0, strike));
		}
		if (strike > 1.5) {
			// dead: the feet drawn in beside the body, the knees standing up over it
			vec2 o = normalize(ankle[i].xz - hip[i].xz);
			float near = abs(length(knee[i] - hip[i]) - length(ankle[i] - knee[i])) + 2.5;      // (tools/dev/leg_clip.py: nearer, the femur stands into the carapace)
			a = vec3(hip[i].x + o.x * near, 0.3, hip[i].z + o.y * near);
			if (back) {
				a = leg_kick(i, a + vec3(0.0, -0.8, 0.0), kick, t);    // on its back, kicking at the sky
			}
		}
		leg_place_up(i, UV.x, a, VERTEX, NORMAL, MODEL_MATRIX[1].y < 0.0 ? -1.0 : 1.0);     // (a body on its back: its knees bent toward the sky)
	} else {
		VERTEX.y += 0.06 * sin(gait * 2.0) * mv;    // body bobs with the stride
		if (VERTEX.x < WAIST_X) {
			// the abdomen swings on its waist as it struggles (side to side, a little up and down)
			vec3 piv = vec3(WAIST_X, 1.8, 0.0);
			float yaw = agit * (0.16 * sin(t * 5.3) + 0.06 * sin(t * 11.0));
			float pitch = agit * 0.09 * sin(t * 3.7 + 1.0);
			vec3 d = VERTEX - piv;
			float c = cos(yaw);
			float s = sin(yaw);
			d = vec3(d.x * c - d.z * s, d.y, d.x * s + d.z * c);
			float cp = cos(pitch);
			float sp = sin(pitch);
			d = vec3(d.x * cp - d.y * sp, d.x * sp + d.y * cp, d.z);
			VERTEX = piv + d;
		} else {
			// the carapace and fangs: a short dip and lift with each lunge
			VERTEX.y += agit * 0.12 * sin(t * 7.0) * clamp((VERTEX.x - 1.0) / 4.0, 0.0, 1.0);
		}
	}
	VERTEX = follow_ground(VERTEX, MODEL_MATRIX);     // every part of the body stands on the floor under it
}

void fragment() {
	ALBEDO = pow(COLOR.rgb, vec3(2.2));    // vertex colours are authored in sRGB
	ROUGHNESS = 0.85;
	SPECULAR = 0.3;
	RIM = 0.4;
	RIM_TINT = 0.7;
}
