shader_type spatial;
render_mode diffuse_burley;
// Stone centipede, Lithobius forficatus (see tools/blender/props/centipede.py). COLOR.a = part id / 16:
// 0 body, 1 walking legs, 2 antennae, 3 ultimate legs, 4 forcipules.
//   - the body sways in a wave travelling back from the head as it runs;
//   - the 30 walking legs are jointed (leg_ik.gdshaderinc; the joints come from centipede.json): UV.x = 4 x the leg's
//     number + its piece (1 coxa + femur, 2 tibia, 3 tip), the legs numbered pair by pair from the head, left then right.
//     They step in a wave down the body (each pair a little after the one in front), left and right in opposite phase,
//     and a foot set down stays where it is: the body's wave and its lunge move the hip, not the foot;
//   - the venom claws snap shut when it strikes; dead, it curls up with its legs drawn in.
// INSTANCE_CUSTOM: x = gait phase (one turn = a stride of ground covered; held down the legs work on the spot), y = 1
// striking / 2 dead, z = clock, w = how much it is moving, + 2 while ants hold it down: then it writhes (a fast wave down
// the body, the whole body coiling one way and the other); striking, the head lunges.
// outworld_creatures.gd _writhe_offset() moves the ants on it in step.

#define LEGS_MAX 30
#include "res://shaders/terrain/ground_h.gdshaderinc"
#include "res://shaders/creatures/leg_ik.gdshaderinc"

// from the model (tools/blender/props/centipede.py)
const float ANT_X = 9.2;        // antenna bases
const float ANT_LEN = 5.6;
const float FANG_X = 8.6;       // forcipule bases
const float PAIR_LAG = 0.14;    // how much of a step each pair of legs is behind the one in front

// how far the body is to one side at x: the running wave, and the writhing while it is held down
float body_sway(float x, float gait, float t, float mv, float held) {
	float sway = sin(x * 0.5 - gait * 1.4) * 0.45 * mv + sin(x * 0.3 + t * 0.6) * 0.12;
	return sway + held * (sin(x * 0.55 - t * 6.0) * 0.6 + sin(t * 1.7) * 0.012 * (x - 2.0) * (x - 2.0));
}

// how far the front of the body is thrown forward at x while it strikes
float body_lunge(float x, float t) {
	return clamp((x - 5.0) / 4.0, 0.0, 1.0) * 0.6 * (0.5 + 0.5 * sin(t * 12.0));
}

void vertex() {
	float part = floor(COLOR.a * 16.0 + 0.5);
	float gait = INSTANCE_CUSTOM.x;
	float state = INSTANCE_CUSTOM.y;
	float t = INSTANCE_CUSTOM.z;
	float held = INSTANCE_CUSTOM.w > 1.5 ? 1.0 : 0.0;
	float mv = INSTANCE_CUSTOM.w - 2.0 * held;
	vec3 v = VERTEX;
	float side = v.z < 0.0 ? -1.0 : 1.0;
	bool dead = state > 1.5 && state < 2.5;
	bool back = state > 2.5;               // on its back alive (v0.13.3): it writhes, its legs working at the sky
	if (back) {
		held = 1.0;
		state = 0.0;
	}
	bool on_back = MODEL_MATRIX[1].y < 0.0;
	bool leg = part == 1.0 && (!dead || on_back);
	if (leg) {
		int i = int(floor(UV.x / 4.0 + 0.01));
		float seg = UV.x - 4.0 * float(i);
		float pair = floor(float(i) / 2.0);
		vec3 a = leg_ankle(i, gait / TAU - pair * PAIR_LAG + (mod(float(i), 2.0) > 0.5 ? 0.5 : 0.0), 1.0);
		if (dead) {
			a = vec3(ankle[i].x, -1.2, ankle[i].z * 0.75);     // a dead one on its back: the legs stiff in the air (curled with it below)
		}
		// (the foot stays; the hip goes with the body's wave and lunge: the leg is placed from the hip as it is now)
		vec3 off = vec3(state > 0.5 ? body_lunge(hip[i].x, t) : 0.0, 0.0, body_sway(hip[i].x, gait, t, mv, held));
		a -= off;
		leg_place_up(i, seg, a, v, NORMAL, MODEL_MATRIX[1].y < 0.0 ? -1.0 : 1.0);     // (a body on its back: its knees bent toward the sky)
		v += off;
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
		float curl = v.x * 0.16;
		vec3 c = vec3(v.x, v.y, v.z);
		v.x = sin(curl) * (6.0 + c.z) ;
		v.z = (6.0 + c.z) * cos(curl) - 6.0;
		if (part == 1.0) { v.y += (abs(c.z) - 1.0) * 0.15; }      // (0.5 until v0.12.35: the jointed legs stand higher already)
	} else if (!leg) {
		v.z += body_sway(v.x, gait, t, mv, held);
		if (state > 0.5) {
			v.x += body_lunge(v.x, t);      // striking: the front of the body lunges forward and back at the ant it bites
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
