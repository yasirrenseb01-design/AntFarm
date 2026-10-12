shader_type spatial;
render_mode diffuse_burley;
// Stone centipede, Lithobius forficatus (see tools/blender/props/centipede.py). COLOR.a = part id / 16:
// 0 body, 1 walking legs, 2 antennae, 3 ultimate legs, 4 forcipules. Animation runs by position along
// the body (x), so no per-leg ids are needed:
//   - the body sways in a wave travelling back from the head as it runs,
//   - the legs step in a metachronal wave (each pair a little after the one in front), left and
//     right in opposite phase,
//   - the venom claws snap shut when it strikes; dead, it curls up with its legs drawn in.
// INSTANCE_CUSTOM: x = gait phase, y = 1 striking / 2 dead, z = clock, w = how much it is moving, + 2 while ants
// hold it down: then it writhes (a fast wave down the body, the whole body coiling one way and the other) and its
// legs thrash; striking, the head lunges. outworld_creatures.gd _writhe_offset() moves the ants on it in step.

#include "res://shaders/terrain/ground_h.gdshaderinc"

// from the model (tools/blender/props/centipede.py)
const float ANT_X = 9.2;        // antenna bases
const float ANT_LEN = 5.6;
const float FANG_X = 8.6;       // forcipule bases
const float LEG_IN = 0.8;       // where the legs leave the body (|z|)
const float LEG_REACH = 1.9;

void vertex() {
	float part = floor(COLOR.a * 16.0 + 0.5);
	float gait = INSTANCE_CUSTOM.x;
	float state = INSTANCE_CUSTOM.y;
	float t = INSTANCE_CUSTOM.z;
	float held = INSTANCE_CUSTOM.w > 1.5 ? 1.0 : 0.0;
	float mv = INSTANCE_CUSTOM.w - 2.0 * held;
	vec3 v = VERTEX;
	float side = v.z < 0.0 ? -1.0 : 1.0;
	bool dead = state > 1.5;
	if (part == 1.0 && !dead) {
		// legs: reach out from the body (0 at the hip, 1 at the foot)
		float reach = clamp((abs(v.z) - LEG_IN) / LEG_REACH, 0.0, 1.0);
		float ph = gait * 2.4 + t * 9.0 * held - v.x * 1.5 + (side > 0.0 ? PI : 0.0);    // a quick metachronal wave
		float lm = max(mv, held);                                    // held down, the legs thrash
		v.x += sin(ph) * 0.4 * reach * lm;
		v.y += max(0.0, cos(ph)) * 0.32 * reach * lm;
	}
	if (part == 2.0) {
		float k = clamp((v.x - ANT_X) / ANT_LEN, 0.0, 1.0);
		v.z += sin(t * 3.1 + side * 1.3) * 0.5 * k;
		v.y += sin(t * 2.3 + side) * 0.3 * k;
	}
	if (part == 4.0) {
		float k = clamp((v.x - FANG_X) / 1.0, 0.0, 1.0);
		float open = state > 0.5 && !dead ? 0.08 : 0.3;      // wide open, snapping shut on a strike
		v.z += side * open * k;
	}
	if (dead) {
		// curled on its side in a loose C, legs folded up
		float bend = v.x * 0.16;
		vec3 c = vec3(v.x, v.y, v.z);
		v.x = sin(bend) * (6.0 + c.z) ;
		v.z = (6.0 + c.z) * cos(bend) - 6.0;
		if (part == 1.0) { v.y += (abs(c.z) - 1.0) * 0.5; }
	} else {
		// the body wave, passed down from the head
		float sway = sin(v.x * 0.5 - gait * 1.4) * 0.45 * mv + sin(v.x * 0.3 + t * 0.6) * 0.12;
		sway += held * (sin(v.x * 0.55 - t * 6.0) * 0.6 + sin(t * 1.7) * 0.012 * (v.x - 2.0) * (v.x - 2.0));
		v.z += sway;
		if (state > 0.5) {
			// striking: the front of the body lunges forward and back at the ant it bites
			float k = clamp((v.x - 5.0) / 4.0, 0.0, 1.0);
			v.x += k * 0.6 * (0.5 + 0.5 * sin(t * 12.0));
		}
	}
	VERTEX = v;
	VERTEX = follow_ground(VERTEX, MODEL_MATRIX);     // every part of the body stands on the floor under it
}

void fragment() {
	ALBEDO = pow(COLOR.rgb, vec3(2.2));     // vertex colours are authored in sRGB
	ROUGHNESS = 0.35;
	SPECULAR = 0.6;                          // glossy plates
	RIM = 0.3;
	RIM_TINT = 0.5;
}
