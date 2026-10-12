shader_type spatial;
render_mode diffuse_burley;
// Ant body animation on the GPU. Each vertex carries a body-part id in COLOR.a (see ant_model3d.gd);
// each instance carries in INSTANCE_CUSTOM:
//   x = gait phase (radians, advanced by distance walked)   y = activity id
//   z = animation clock (seconds, per ant)
//   w = how much it is walking (fraction, 0..1) + stride scale x 100 (whole part; 0 = normal), see
//       ant_model3d.gd gait_w(). Walking legs use inverse kinematics on the joints of the Blender model
//       (UV.x = leg segment: 1 coxa, 2 femur, 3 tibia, 4 tarsus): each foot stays planted on the ground
//       while the body passes over it (alternating tripods), then swings forward; the knee bends to suit.
// Activities: 0 walk/idle, 1 rest, 2 dig, 3 antennate, 4 groom, 5 lay eggs (queen),
//             6 trophallaxis (mouth-to-mouth feeding), 7 tend brood / attend queen, 8 carry,
//             9 milk aphids, 10 drink, 11 dead (on its back, legs curled),
//             12 just eclosed (legs and antennae unfold over the first seconds; z counts from 0),
//             13 fighting: clamped on with the mandibles, gaster curled forward under the body spraying
//                formic acid, legs braced; 14 alarmed: running in with mandibles agape, antennae forward;
//             15 stopped to scan: head and antennae sweep slowly side to side, antennae raised;
//             16 following a trail: antennae held low, tapping the ground left and right in turn.
// Walking, the head and gaster sway a little with each step and the gaster is carried clear of the ground.
// y >= 100: the crop is full of honeydew (gaster swollen, pale membranes showing between the plates).

uniform float rim_amount = 0.35;
// where the feet find the ground: 0 a flat floor at the instance origin, 1 the nest's soil (the voxel volume),
// 2 the outworld floor (ground_h). Each walking foot is set down on the real surface under it.
uniform int ground_mode = 0;
uniform sampler3D vol : filter_linear;      // nest: soil density per voxel (as shaders/terrain/soil.gdshader)
uniform vec3 vol_size = vec3(64.0, 72.0, 64.0);
#include "res://shaders/terrain/ground_h.gdshaderinc"
uniform vec3 limb_gain = vec3(1.0);   // appendages are lighter than the body: amber-orange in L. niger queens
varying float stretch;
varying float limb;
const float K = 0.34;   // model design units -> mesh units

mat3 rot_x(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(1, 0, 0), vec3(0, c, s), vec3(0, -s, c)); }
mat3 rot_y(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(c, 0, -s), vec3(0, 1, 0), vec3(s, 0, c)); }
mat3 rot_z(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(c, s, 0), vec3(-s, c, 0), vec3(0, 0, 1)); }
// rotation about any unit axis (Rodrigues)
vec3 rot_axis(vec3 v, vec3 k, float a) { float c = cos(a); float s = sin(a); return v * c + cross(k, v) * s + k * dot(k, v) * (1.0 - c); }
// turn (x, z) toward z by a, about the vertical
vec3 yaw(vec3 v, float a) { float c = cos(a); float s = sin(a); return vec3(v.x * c - v.z * s, v.y, v.x * s + v.z * c); }

const float STRIDE_A = 1.3;      // ant_model3d.gd STRIDE_A
const float LIFT_H = 0.42;       // how high a swinging foot is raised, design units

// Two-segment leg (femur C->N, tibia N->A) reaching for an ankle target TA, in the vertical plane
// through C and TA. Returns the femur and tibia rotations (about `axis`) for the knee-up solution.
vec2 leg_ik(vec3 C, vec3 N, vec3 A, vec3 TA, out vec3 axis) {
	vec3 d = TA - C;
	vec3 dir = normalize(vec3(d.x, 0.0, d.z) + vec3(1e-4, 0.0, 0.0));
	axis = normalize(cross(dir, vec3(0.0, 1.0, 0.0)));
	vec2 u1 = vec2(dot(N - C, dir), N.y - C.y);
	vec2 r2 = vec2(dot(A - C, dir), A.y - C.y);
	vec2 c2 = vec2(dot(TA - C, dir), TA.y - C.y);
	float l1 = length(u1);
	float l2 = length(r2 - u1);
	float dr = length(r2);
	float dc = clamp(length(c2), abs(l1 - l2) + 1e-4, l1 + l2 - 1e-4);
	float a0 = acos(clamp((l1 * l1 + dr * dr - l2 * l2) / (2.0 * l1 * dr), -1.0, 1.0));
	float a1 = acos(clamp((l1 * l1 + dc * dc - l2 * l2) / (2.0 * l1 * dc), -1.0, 1.0));
	float sgn = sign(r2.x * u1.y - r2.y * u1.x);
	float f = atan(c2.y, c2.x) - atan(r2.y, r2.x) + sgn * (a1 - a0);
	vec2 n2 = vec2(u1.x * cos(f) - u1.y * sin(f), u1.x * sin(f) + u1.y * cos(f));
	vec2 cc = normalize(c2) * dc;
	vec2 tb0 = r2 - u1;
	vec2 tb1 = cc - n2;
	float t = atan(tb1.y, tb1.x) - atan(tb0.y, tb0.x);
	return vec2(f, t);
}

// How far (world units, along the ant's up) the real ground lies from a foot placed at fw: + above, - below.
float ground_dy(vec3 fw, vec3 upw) {
	if (ground_mode == 1) {
		float prev = 1.4;
		for (int i = 0; i < 10; i++) {
			float s = 1.4 - 0.3 * float(i);
			if (texture(vol, (fw + upw * s + 0.5) / vol_size).r >= 0.5) {
				return mix(prev, s, 0.5);     // between the last open sample and the first solid one
			}
			prev = s;
		}
		return -1.4;
	} else if (ground_mode == 2) {
		return ground_h(fw.xz) - fw.y;
	}
	return 0.0;
}

// The head's pose (nod, turn) for an activity — the antennae ride on it.
vec2 head_pose(float act, float t, float gait, float mv) {
	float nod = 0.0;
	if (act == 2.0) nod = -0.35 + 0.25 * sin(t * 10.0);     // biting into the soil
	if (act == 7.0) nod = -0.28 + 0.12 * sin(t * 4.0);      // licking brood / the queen
	if (act == 6.0) nod = -0.05 + 0.06 * sin(t * 3.0);      // passing a droplet mouth to mouth
	if (act == 1.0) nod = 0.03 * sin(t * 0.7);
	if (act == 9.0) nod = -0.2 + 0.05 * sin(t * 3.0);
	if (act == 10.0) nod = -0.4 + 0.05 * sin(t * 4.0);     // lapping at the drop
	if (act == 13.0) nod = -0.3 + 0.12 * sin(t * 11.0);    // worrying at the grip
	if (act == 14.0) nod = 0.12;
	if (act == 16.0) nod = -0.07;                           // nose down to the scent
	float turn = 0.05 * sin(gait) * mv;
	if (act == 15.0) { turn = 0.32 * sin(t * 1.4); nod = 0.06 + 0.05 * sin(t * 0.9); }
	if (act == 4.0) {
		// grooming: head bowed and turned to the side being cleaned
		float gs = fract(t * 0.22) < 0.5 ? -1.0 : 1.0;
		nod = -0.3;
		turn = 0.22 * gs;
	}
	return vec2(nod, turn);
}

void vertex() {
	float part = floor(COLOR.a * 16.0 + 0.5);
	float gait = INSTANCE_CUSTOM.x;
	float code = floor(INSTANCE_CUSTOM.y + 0.5);
	float full = code >= 99.5 ? 1.0 : 0.0;
	float act = code - full * 100.0;
	stretch = 0.0;
	limb = (part >= 2.0 && part <= 9.0) || part == 11.0 ? 1.0 : 0.0;
	float t = INSTANCE_CUSTOM.z;
	float mv = INSTANCE_CUSTOM.w;
	mat3 R = mat3(1.0);
	vec3 piv = vec3(0.0);

	float sscale = floor(INSTANCE_CUSTOM.w) / 100.0;
	if (sscale < 0.01) {
		sscale = 1.0;
	} else {
		mv = fract(INSTANCE_CUSTOM.w);
	}
	if (part >= 4.0 && part <= 9.0) {
		// legs: alternating tripods (front+hind of one side with the middle of the other)
		float li = floor((part - 4.0) / 2.0);
		float side = mod(part - 4.0, 2.0) < 0.5 ? -1.0 : 1.0;
		float grp = ((mod(li, 2.0) < 0.5) == (side < 0.0)) ? 0.0 : PI;
		float ph = gait + grp;
		float sw = sin(ph) * 0.42 * mv;
		float lift = max(0.0, cos(ph)) * 0.32 * mv;
		bool front = li < 0.5;
		bool posed = act == 11.0 || act == 12.0 || act == 13.0 || (front && (act == 2.0 || act == 9.0));
		if (mv < 0.05) {
			sw = 0.04 * sin(t * 0.9 + li * 2.0 + side);      // standing: tiny shifts of weight
		}
		if (act == 4.0 && li < 0.5) {                         // grooming: front legs sweep the antennae
			sw = 0.55 + 0.25 * sin(t * 9.0 + side * 1.6);
			lift = 0.95 + 0.25 * sin(t * 9.0 + side * 1.6);
		}
		if (act == 2.0 && li < 0.5) {                         // digging: front legs rake the soil
			sw = 0.35 * sin(t * 10.0 + side * 1.6);
			lift = 0.25 + 0.25 * cos(t * 10.0 + side * 1.6);
		}
		if (act == 9.0 && li < 0.5) {                         // milking: front legs pat the aphid
			sw = 0.2 + 0.15 * sin(t * 6.0 + side * 2.0);
			lift = 0.3 + 0.2 * max(0.0, sin(t * 6.0 + side * 2.0));
		}
		if (act == 11.0) {                                    // dead: legs folded in over the body
			sw = 0.15 * (li - 1.0);
			lift = -1.1 - 0.15 * li;
		}
		if (act == 13.0) {                                    // braced, pulling back on the grip
			sw = 0.18 * (1.0 - li) + 0.06 * sin(t * 13.0 + li * 2.0 + side);
			lift = -0.15;
		}
		if (act == 12.0) {                                    // callow: legs pressed to the body, slowly unfolding
			float fold = 1.0 - clamp(t / 3.0, 0.0, 1.0);
			sw = mix(sw, 0.35 * (1.0 - li), fold) + 0.12 * sin(t * 5.0 + li * 1.7) * fold;
			lift = mix(lift, 1.25, fold);
		}
		float hipx = li < 0.5 ? 0.85 : (li < 1.5 ? 0.2 : -0.4);
		piv = vec3(hipx, 0.85, 0.42 * side) * K;
		R = rot_y(sw * side) * rot_x(-lift * side);
		float seg = floor(UV.x + 0.5);
		if (!posed && seg > 0.5) {
			// rest joints of this leg (tools/blender/ant/legs.py LEGS), mesh units
			vec3 L = li < 0.5 ? vec3(0.85, 0.75, 1.8) : (li < 1.5 ? vec3(0.2, 0.1, -0.1) : vec3(-0.4, -0.65, -2.2));
			vec3 H = vec3(L.x, 0.85, 0.42 * side) * K;
			vec3 C = vec3(L.x + 0.1, 0.55, 0.85 * side) * K;
			vec3 N = vec3(L.x + L.y, 1.75, 2.05 * side) * K;
			vec3 A = vec3(L.x + L.z * 0.85, 0.35, 2.9 * side) * K;
			vec3 F = vec3(L.x + L.z, 0.0, 3.15 * side) * K;
			// where the foot is: planted and sliding back under the body for the duty part of the
			// cycle, then lifted and swung forward (eased) to its next foothold
			float duty = mix(0.55, 0.42, clamp((sscale - 1.0) / 0.5, 0.0, 1.0));
			float u = fract((gait + grp) / TAU);
			float amp = STRIDE_A * K * sscale * mv;
			float dx;
			float up = 0.0;
			if (u < duty) {
				dx = amp * (1.0 - 2.0 * u / duty);
			} else {
				float w = (u - duty) / (1.0 - duty);
				dx = amp * (-1.0 + 2.0 * w * w * (3.0 - 2.0 * w));
				up = LIFT_H * K * min(sscale, 1.2) * mv * sin(PI * w);
			}
			if (mv < 0.05) {
				dx += 0.03 * K * sin(t * 0.9 + li * 2.0 + side);    // standing: tiny shifts of weight
			}
			vec3 T = F + vec3(dx, 0.0, 0.0);
			// set the foot down on the real ground under it (rough nest floors, the slope outside)
			if (ground_mode != 0) {
				vec3 upw = normalize(MODEL_MATRIX[1].xyz);
				float sc = length(MODEL_MATRIX[1].xyz);
				vec3 fw = (MODEL_MATRIX * vec4(T, 1.0)).xyz;
				T.y += clamp(ground_dy(fw, upw) / sc, -0.32, 0.28);
			}
			T.y += up;
			bool cleaning = false;
			if (act == 4.0 && front) {
				// grooming: one front leg at a time draws its antenna through the comb on the leg —
				// the foot comes up in front of the face and strokes out along the antenna
				float gs = fract(t * 0.22) < 0.5 ? -1.0 : 1.0;
				if (side == gs) {
					float k = 0.5 + 0.5 * sin(t * 7.0);
					T = vec3(2.7 + 0.6 * k, 1.05 - 0.2 * k, 0.45 * side) * K;
					cleaning = true;
				}
			}
			// the coxa swings the whole leg round toward the foothold...
			vec2 v0 = (F - H).xz;
			vec2 v1 = (T - H).xz;
			float th = atan(v0.x * v1.y - v0.y * v1.x, dot(v0, v1));
			vec3 Cy = H + yaw(C - H, th);
			vec3 Ny = H + yaw(N - H, th);
			vec3 Ay = H + yaw(A - H, th);
			vec3 Fy = H + yaw(F - H, th);
			// ...and femur and tibia bend at the knee so the tarsus lies where the foot is
			vec3 TA = T + (Ay - Fy);
			vec3 ax;
			vec2 ang = leg_ik(Cy, Ny, Ay, TA, ax);
			vec3 N2 = Cy + rot_axis(Ny - Cy, ax, ang.x);
			vec3 A2 = N2 + rot_axis(Ay - Ny, ax, ang.y);
			vec3 p = H + yaw(VERTEX - H, th);
			vec3 nn = yaw(NORMAL, th);
			if (seg > 3.5) {
				p = A2 + (p - Ay);
			} else if (seg > 2.5) {
				p = N2 + rot_axis(p - Ny, ax, ang.y);
				nn = rot_axis(nn, ax, ang.y);
			} else if (seg > 1.5) {
				p = Cy + rot_axis(p - Cy, ax, ang.x);
				nn = rot_axis(nn, ax, ang.x);
			}
			VERTEX = p;
			NORMAL = nn;
			R = mat3(1.0);
			piv = vec3(0.0);
		}
	} else if (part == 2.0 || part == 3.0) {
		// antennae: constant exploratory sweeping; drumming when meeting a nestmate
		float side = part == 2.0 ? -1.0 : 1.0;
		piv = vec3(2.7, 1.45, 0.38 * side) * K;
		float sp = 2.6;
		float amp = 0.32;
		float droop = 0.06;                                           // exploring: held up, sweeping wide
		if (act == 3.0 || act == 6.0) { sp = 11.0; amp = 0.4; droop = -0.15; }
		if (act == 1.0) { sp = 0.7; amp = 0.1; droop = -0.2; }
		if (act == 4.0) {
			float gs = fract(t * 0.22) < 0.5 ? -1.0 : 1.0;
			if (side == gs) { sp = 7.0; amp = 0.06; droop = -0.75 + 0.12 * sin(t * 7.0); }    // drawn through the leg
			else { sp = 1.5; amp = 0.12; droop = -0.15; }
		}
		if (act == 2.0 || act == 7.0) { sp = 4.0; amp = 0.2; droop = -0.35; }
		if (act == 9.0) { sp = 9.0; amp = 0.35; droop = -0.45; }     // stroking the aphid's back
		if (act == 10.0) { sp = 3.0; amp = 0.12; droop = -0.4; }
		if (act == 11.0) { sp = 0.0; amp = 0.0; droop = 0.5; }
		if (act == 13.0) { sp = 9.0; amp = 0.2; droop = 0.35; }       // swept back, out of the way
		if (act == 14.0) { sp = 14.0; amp = 0.3; droop = 0.15; }      // held forward, flicking
		if (act == 12.0) { sp = 3.0; amp = 0.15; droop = -0.9 * (1.0 - clamp(t / 3.0, 0.0, 1.0)); }
		if (act == 15.0) { sp = 1.4; amp = 0.45; droop = 0.18; }      // scanning: raised, slow, wide
		if (act == 16.0) {                                            // on a trail: low, tapping in turn
			sp = 7.0; amp = 0.14;
			droop = -0.32 - 0.22 * max(0.0, sin(t * 7.0 + (side > 0.0 ? PI : 0.0)));
		}
		float a1 = sin(t * sp + side * 1.3) * amp;
		float a2 = cos(t * sp * 0.73 + side) * amp * 0.6;
		// the antenna turns at its socket, and is carried by the head as it nods and turns
		mat3 Ra = rot_y(a1 * side) * rot_z(a2 + droop);
		vec2 hp = head_pose(act, t, gait, mv);
		mat3 Rh = rot_y(hp.y) * rot_z(hp.x);
		vec3 hpiv = vec3(1.35, 1.15, 0.0) * K;
		vec3 v1 = piv + Ra * (VERTEX - piv);
		VERTEX = hpiv + Rh * (v1 - hpiv);
		NORMAL = Rh * (Ra * NORMAL);
		R = mat3(1.0);
		piv = vec3(0.0);
	} else if (part == 1.0 || part == 11.0) {
		// head on the neck joint
		piv = vec3(1.35, 1.15, 0.0) * K;
		vec2 hp = head_pose(act, t, gait, mv);
		float nod = hp.x;
		float turn = hp.y;
		R = rot_y(turn) * rot_z(nod);
		if (part == 11.0) {
			float side = VERTEX.z > 0.0 ? 1.0 : -1.0;
			float open = 0.04;
			if (act == 2.0) open = 0.35 + 0.35 * sin(t * 12.0);
			if (act == 6.0) open = 0.45;
			if (act == 7.0) open = 0.2 + 0.15 * sin(t * 6.0);
			if (act == 10.0) open = 0.3;
			if (act == 13.0) open = 0.25 + 0.2 * max(0.0, sin(t * 11.0));
			if (act == 14.0) open = 0.6;
			vec3 mp = vec3(2.85, 0.9, 0.3 * side) * K;
			VERTEX = mp + rot_y(open * side) * (VERTEX - mp);
			NORMAL = rot_y(open * side) * NORMAL;
		}
	} else if (part == 10.0) {
		// gaster: slow breathing pulse; the queen curls hers down to lay
		piv = vec3(-0.9, 1.05, 0.0) * K;
		float curl = act == 5.0 ? -0.35 + 0.08 * sin(t * 2.0) : 0.0;
		if (act == 13.0) curl = -1.05 + 0.1 * sin(t * 7.0);   // tip brought forward between the legs to spray
		if (act == 14.0) curl = 0.12;
		// carried clear of the ground and swaying against the head as the tripods alternate
		if (act != 5.0 && act != 11.0 && act != 13.0) {
			curl += 0.1 + 0.025 * sin(gait * 2.0) * mv;
			R = rot_y(-0.045 * sin(gait) * mv);
		}
		float b = 1.0 + 0.018 * sin(t * 1.6);
		vec3 sc = vec3(b) * (1.0 + full * vec3(0.22, 0.3, 0.32));
		R = R * rot_z(curl) * mat3(vec3(sc.x, 0, 0), vec3(0, sc.y, 0), vec3(0, 0, sc.z));
		stretch = full;
	}
	VERTEX = piv + R * (VERTEX - piv);
	NORMAL = normalize(R * NORMAL);
	// whole body: nose down while digging, front up while grooming
	float pitch = act == 2.0 ? -0.12 : (act == 4.0 ? 0.06 : (act == 10.0 ? -0.1 : (act == 13.0 ? 0.12 : 0.0)));
	VERTEX = rot_z(pitch) * VERTEX;
	NORMAL = rot_z(pitch) * NORMAL;
}

void fragment() {
	// a stretched crop shows amber honeydew through the pale membranes between the plates
	vec3 base = COLOR.rgb * mix(vec3(1.0), limb_gain, limb);
	ALBEDO = mix(base, vec3(0.42, 0.27, 0.1), stretch * 0.55);
	ROUGHNESS = 0.4;
	SPECULAR = 0.55;
	RIM = rim_amount;
	RIM_TINT = 0.6;
}
