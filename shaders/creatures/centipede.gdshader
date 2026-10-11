shader_type spatial;
render_mode diffuse_burley;
// Giant centipede (see tools/blender/build_props.py centipede()). COLOR.a = part id / 16:
// 0 body, 1 walking legs, 2 antennae, 3 ultimate legs, 4 forcipules. Animation runs by position along
// the body (x), so no per-leg ids are needed:
//   - the body sways in a wave travelling back from the head as it runs,
//   - the legs step in a metachronal wave (each pair a little after the one in front), left and
//     right in opposite phase,
//   - the venom claws snap shut when it strikes; dead, it curls up with its legs drawn in.
// INSTANCE_CUSTOM: x = gait phase, y = 1 striking / 2 dead, z = clock, w = how much it is moving.

#include "res://shaders/terrain/ground_h.gdshaderinc"

void vertex() {
	float part = floor(COLOR.a * 16.0 + 0.5);
	float gait = INSTANCE_CUSTOM.x;
	float state = INSTANCE_CUSTOM.y;
	float t = INSTANCE_CUSTOM.z;
	float mv = INSTANCE_CUSTOM.w;
	vec3 v = VERTEX;
	float side = v.z < 0.0 ? -1.0 : 1.0;
	bool dead = state > 1.5;
	if (part == 1.0 && !dead) {
		// legs: reach out from the body (0 at the hip, 1 at the foot)
		float reach = clamp((abs(v.z) - 1.0) / 2.4, 0.0, 1.0);
		float ph = gait * 2.0 - v.x * 0.9 + (side > 0.0 ? PI : 0.0);
		v.x += sin(ph) * 0.55 * reach * mv;
		v.y += max(0.0, cos(ph)) * 0.45 * reach * mv;
	}
	if (part == 2.0) {
		float k = clamp((v.x - 19.7) / 7.5, 0.0, 1.0);
		v.z += sin(t * 3.1 + side * 1.3) * 0.5 * k;
		v.y += sin(t * 2.3 + side) * 0.3 * k;
	}
	if (part == 4.0) {
		float k = clamp((v.x - 18.6) / 1.8, 0.0, 1.0);
		float open = state > 0.5 && !dead ? 0.15 : 0.55;      // wide open, snapping shut on a strike
		v.z += side * open * k;
	}
	if (dead) {
		// curled on its side in a loose C, legs folded up
		float bend = v.x * 0.07;
		vec3 c = vec3(v.x, v.y, v.z);
		v.x = sin(bend) * (14.0 + c.z) ;
		v.z = (14.0 + c.z) * cos(bend) - 14.0;
		if (part == 1.0) { v.y += (abs(c.z) - 1.0) * 0.5; }
	} else {
		// the body wave, passed down from the head
		float sway = sin(v.x * 0.26 - gait * 1.2) * 0.9 * mv + sin(v.x * 0.15 + t * 0.6) * 0.25;
		v.z += sway;
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
