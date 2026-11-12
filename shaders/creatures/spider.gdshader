shader_type spatial;
render_mode diffuse_burley;
// Wolf spider (tools/blender/props/spider.py): COLOR.a = part id / 16 (0 body, 1-4 left legs front to back, 5-8 right
// legs). Legs: jointed, their knees bent upward, the feet set down and left where they are while the body goes over
// them, in alternating fours (leg_ik.gdshaderinc; UV.x = the leg's piece; the joints come from wolf_spider.json).
// INSTANCE_CUSTOM: x = gait phase (one turn = a stride of ground covered), y = 1 while striking (the two front pairs
// reared up to grab) / 2 dead (legs drawn in, knees up), z = clock, w = how much it is walking (+2 held: unused here).

#include "res://shaders/terrain/ground_h.gdshaderinc"
#include "res://shaders/creatures/leg_ik.gdshaderinc"

void vertex() {
	float part = floor(COLOR.a * 16.0 + 0.5);
	float gait = INSTANCE_CUSTOM.x;
	float strike = INSTANCE_CUSTOM.y;
	float t = INSTANCE_CUSTOM.z;
	float mv = min(INSTANCE_CUSTOM.w, 1.0);
	if (part >= 1.0) {
		int i = int(part) - 1;
		float li = mod(part - 1.0, 4.0);
		float side = part < 4.5 ? -1.0 : 1.0;
		// alternating fours: L1 R2 L3 R4 against R1 L2 R3 L4
		float grp = mod(li + (side < 0.0 ? 0.0 : 1.0), 2.0) * 0.5;
		vec3 a = leg_ankle(i, gait / TAU + grp, 1.0);      // (standing still the legs stay as they were in the step)
		if (strike > 0.5 && strike < 1.5 && li < 1.5) {
			// rearing: the two front pairs lifted off the ground and reaching forward
			a = ankle[i] + vec3(0.6, 2.8 + 0.5 * sin(t * 8.0 + li), -0.8 * side);
		}
		if (strike > 1.5) {
			// dead: the feet drawn in beside the body, the knees standing up over it
			vec2 o = normalize(ankle[i].xz - hip[i].xz);
			float near = abs(length(knee[i] - hip[i]) - length(ankle[i] - knee[i])) + 2.5;      // (tools/dev/leg_clip.py: nearer, the femur stands into the carapace)
			a = vec3(hip[i].x + o.x * near, 0.3, hip[i].z + o.y * near);
		}
		leg_place(i, UV.x, a, VERTEX, NORMAL);
	} else {
		VERTEX.y += 0.06 * sin(gait * 2.0) * mv;    // body bobs with the stride
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
