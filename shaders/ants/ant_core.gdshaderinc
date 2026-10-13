// The ant's body animation (everything but the surface colour), shared by ant.gdshader and the selection
// outline (ant_outline.gdshader, which defines OUTLINE). See ant.gdshader for the INSTANCE_CUSTOM layout.
#ifdef OUTLINE
uniform float outline_w = 0.045;
#endif
// Ant body animation on the GPU. Each vertex carries a body-part id in COLOR.a (see ant_model3d.gd);
// each instance carries in INSTANCE_CUSTOM:
//   x = gait phase (radians, advanced by distance walked)
//   y = activity code (id + 100 if full) + 128 x the code being left; fraction = how much of the old pose
//       still shows (ant_model3d.gd act_y: poses ease into one another instead of snapping)
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
//             16 following a trail: antennae held low, tapping the ground left and right in turn;
//             17 a queen taking her new egg: gaster curled forward under the body, head bowed to meet it.
// Carrying (8): head raised, mandibles closed on the load, antennae held forward over it.
// 19 hauling prey with nestmates: head low, mandibles clamped on it, leaning back as it pulls.
// 18 thrown on its back (the view rolls the body): legs flailing in the air, antennae waving, until it rights itself.
// Walking, the head and gaster sway a little with each step and the gaster is carried clear of the ground.
// y >= 100: the crop is full of honeydew (gaster swollen, pale membranes showing between the plates).

uniform float rim_amount = 0.35;
// where the feet find the ground: 0 a flat floor at the instance origin, 1 the nest's soil (the voxel volume),
// 2 the outworld floor (ground_h). Each walking foot is set down on the real surface under it.
uniform int ground_mode = 0;
uniform sampler3D vol : filter_linear;      // nest: soil density per voxel (as shaders/terrain/soil.gdshader)
uniform vec3 vol_size = vec3(64.0, 72.0, 64.0);
// Shadows cost a pass (or several) per light: true = shadows follow the animated pose (close up), false = they
// keep the rest pose (zoomed out, where a shadow is a few pixels) - the views set it with the level of detail.
uniform bool shadow_pose = true;
#include "res://shaders/terrain/ground_h.gdshaderinc"
// outworld: litter lying on the ground (pebbles, moss, twigs, leaves), height above it per point
// (scripts/view/outworld/prop_heights.gd), so feet are set down on top of it too
uniform sampler2D prop_tex : filter_linear;
uniform vec2 prop_size = vec2(1.0);
uniform bool has_props = false;
uniform vec3 limb_gain = vec3(1.0);   // appendages are lighter than the body: amber-orange in L. niger queens
varying float stretch;
varying float limb;
varying float gband;              // gaster: 1 on the stretched membranes between the plates (a full crop)
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
		float dprev = texture(vol, (fw + upw * prev + 0.5) / vol_size).r;
		for (int i = 1; i < 10; i++) {
			float s = 1.4 - 0.3 * float(i);
			float d = texture(vol, (fw + upw * s + 0.5) / vol_size).r;
			if (d >= 0.5) {
				// where the density crosses 0.5 between the two samples: the same surface the soil mesh shows
				return mix(prev, s, clamp((0.5 - dprev) / max(d - dprev, 0.001), 0.0, 1.0));
			}
			prev = s;
			dprev = d;
		}
		return -1.4;
	} else if (ground_mode == 2) {
		float top = has_props ? texture(prop_tex, fw.xz / prop_size).r : 0.0;
		return ground_h(fw.xz) + top - fw.y;
	}
	return 0.0;
}

// Grooming runs through a cycle of ~13 s, each step easing into the next: the antennae drawn through the combs
// on the forelegs (half of it), a foreleg drawn through the mouthparts (a quarter), the gaster wiped with a hind
// leg (a quarter). x, y, z = how much of each is going on now.
vec3 groom_phase(float t) {
	float gp = fract(t * 0.075);
	float wm = smoothstep(0.45, 0.55, gp) * (1.0 - smoothstep(0.7, 0.8, gp));
	float wh = smoothstep(0.7, 0.8, gp) * (1.0 - smoothstep(0.92, 1.0, gp));
	return vec3(1.0 - wm - wh, wm, wh);
}

// Each step works one side at a time: how much the side `side` is being worked now, 0..1, eased in and out
// so the head and legs pass smoothly from one side to the other (`rate` = side changes per second / 2).
float groom_side(float t, float side, float rate) {
	float ph = fract(t * rate + (side > 0.0 ? 0.5 : 0.0));
	return smoothstep(0.0, 0.12, ph) * (1.0 - smoothstep(0.38, 0.5, ph));
}

// The antenna on `side` being drawn through its foreleg's comb (left, then right, ~2.3 s each).
float groom_w(float t, float side) {
	return groom_side(t, side, 0.22) * groom_phase(t).x;
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
	if (act == 17.0) nod = -0.55;                           // head bowed under to the gaster tip
	if (act == 8.0) nod = 0.2 + 0.03 * sin(gait * 2.0);     // carrying: head up, the load held clear of the ground
	if (act == 19.0) nod = -0.14 + 0.04 * sin(t * 5.0);     // hauling: tugging at the item
	float turn = 0.05 * sin(gait) * mv;
	if (act == 15.0) { turn = 0.32 * sin(t * 1.4); nod = 0.06 + 0.05 * sin(t * 0.9); }
	if (act == 4.0) {
		// grooming: head bowed and turned to the side being cleaned; lower still, nibbling, to clean a foreleg
		vec3 g = groom_phase(t);
		float mr = (groom_side(t, 1.0, 0.3) - groom_side(t, -1.0, 0.3)) * g.y;
		float hr = (groom_side(t, 1.0, 0.25) - groom_side(t, -1.0, 0.25)) * g.z;
		nod = -0.3 * g.x + (-0.42 + 0.06 * sin(t * 6.0)) * g.y - 0.05 * g.z;
		turn = 0.22 * (groom_w(t, 1.0) - groom_w(t, -1.0)) + 0.12 * mr + 0.08 * hr;
	}
	return vec2(nod, turn);
}

// The body's pose for one activity code (act + 100 if the crop is full): the vertex V (normal NR) of body
// part `part` moved for that activity. Called twice while easing from one activity into the next.
vec3 pose(float code, float part, float uvx, vec3 V, inout vec3 NR, mat4 M, float gait, float t, float cw, bool probe, out float stretch_out) {
	float full = code >= 99.5 ? 1.0 : 0.0;
	float act = code - full * 100.0;
	stretch_out = 0.0;
	float mv = cw;
	// curling the gaster under the body, an ant first rises on its legs so the gaster clears the floor
	float hlift = act == 17.0 ? 0.65 * K : (act == 13.0 ? 0.35 * K : 0.0);
	mat3 R = mat3(1.0);
	vec3 piv = vec3(0.0);

	float sscale = floor(cw) / 100.0;
	if (sscale < 0.01) {
		sscale = 1.0;
	} else {
		mv = fract(cw);
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
		bool posed = act == 11.0 || act == 12.0 || act == 18.0 || (front && (act == 2.0 || act == 9.0));
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
			lift = -0.4;                                      // legs pushed down: standing tall
		}
		if (act == 18.0) {                                    // on its back: legs clawing at the air for a hold
			sw = 0.45 * sin(t * 13.0 + li * 2.1 + side * 1.3);
			lift = 0.55 + 0.45 * sin(t * 11.0 + li * 1.7 + side);
		}
		if (act == 12.0) {                                    // callow: legs pressed to the body, slowly unfolding
			float fold = 1.0 - clamp(t / 3.0, 0.0, 1.0);
			sw = mix(sw, 0.35 * (1.0 - li), fold) + 0.12 * sin(t * 5.0 + li * 1.7) * fold;
			lift = mix(lift, 1.25, fold);
		}
		float tuck = act == 12.0 ? 1.0 - 0.6 * (1.0 - clamp(t / 3.0, 0.0, 1.0)) : 1.0;   // folded legs drawn in to the body
		float hipx = li < 0.5 ? 0.85 : (li < 1.5 ? 0.2 : -0.4);
		piv = vec3(hipx, 0.85, 0.42 * side) * K;
		R = rot_y(sw * side) * rot_x(-lift * side) * tuck;
		float seg = floor(uvx + 0.5);
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
			if (act == 13.0) {
				dx += 0.12 * K * (1.0 - li) + 0.05 * K * sin(t * 13.0 + li * 2.0 + side);   // braced, tugging
			}
			vec3 T = F + vec3(dx, 0.0, 0.0);
			// set the foot down on the real ground under it (rough nest floors, the slope outside)
			if (ground_mode != 0 && probe && abs(M[1].y) > 0.5 * length(M[1].xyz)) {   // (not for shadows, not on the glass)
				vec3 upw = normalize(M[1].xyz);
				float sc = length(M[1].xyz);
				vec3 fw = (M * vec4(T, 1.0)).xyz;
				T.y += clamp(ground_dy(fw, upw) / sc, -0.36, 0.6);     // (up a steep chamber edge the foot climbs with it)
			}
			T.y += up - hlift;                               // (the body is raised by hlift below)
			bool cleaning = false;
			if (act == 4.0 && front) {
				// grooming: one front leg at a time draws its antenna through the comb on the leg —
				// the foot comes up in front of the face and strokes out along the antenna
				float gw = groom_w(t, side);
				if (gw > 0.0) {
					float k = 0.5 + 0.5 * sin(t * 7.0);
					T = mix(T, vec3(2.7 + 0.6 * k, 1.05 - 0.2 * k, 0.45 * side) * K, gw);
					cleaning = true;
				}
				// ...and, later in the cycle, the foreleg itself is drawn in and out through the mouthparts
				float gm = groom_side(t, side, 0.3) * groom_phase(t).y;
				if (gm > 0.0) {
					float k2 = 0.5 + 0.5 * sin(t * 6.0);
					T = mix(T, vec3(2.5 + 0.3 * k2, 0.8, 0.3 * side) * K, gm);
					cleaning = true;
				}
			}
			if (act == 4.0 && li > 1.5) {
				// a hind leg wipes down the side of the gaster, front to back, one side then the other
				float gh = groom_side(t, side, 0.25) * groom_phase(t).z;
				if (gh > 0.0) {
					float k3 = 0.5 + 0.5 * sin(t * 5.0);
					T = mix(T, vec3(-1.3 - 1.1 * k3, 0.78 + 0.12 * k3, 0.78 * side) * K, gh);
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
			vec3 p = H + yaw(V - H, th);
			vec3 nn = yaw(NR, th);
			if (seg > 3.5) {
				p = A2 + (p - Ay);
			} else if (seg > 2.5) {
				p = N2 + rot_axis(p - Ny, ax, ang.y);
				nn = rot_axis(nn, ax, ang.y);
			} else if (seg > 1.5) {
				p = Cy + rot_axis(p - Cy, ax, ang.x);
				nn = rot_axis(nn, ax, ang.x);
			}
			V = p;
			NR = nn;
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
			sp = 1.5; amp = 0.12; droop = -0.15;             // the side being cleaned: see below
		}
		if (act == 2.0) { sp = 4.0; amp = 0.2; droop = -0.35; }
		if (act == 7.0) { sp = 4.0; amp = 0.1; droop = 0.06; }       // licking: held forward over the brood, tips tapping it (the head is bowed)
		if (act == 9.0) { sp = 9.0; amp = 0.35; droop = -0.45; }     // stroking the aphid's back
		if (act == 10.0) { sp = 3.0; amp = 0.12; droop = -0.4; }
		if (act == 11.0) { sp = 0.0; amp = 0.0; droop = 0.5; }
		if (act == 13.0) { sp = 9.0; amp = 0.2; droop = 0.35; }       // swept back, out of the way
		if (act == 14.0) { sp = 14.0; amp = 0.3; droop = 0.15; }      // held forward, flicking
		if (act == 12.0) { sp = 3.0; amp = 0.15; droop = -0.9 * (1.0 - clamp(t / 3.0, 0.0, 1.0)); }
		if (act == 15.0) { sp = 1.4; amp = 0.45; droop = 0.18; }      // scanning: raised, slow, wide
		if (act == 8.0) { sp = 3.2; amp = 0.16; droop = 0.12; }       // carrying: held forward over the load
		if (act == 18.0) { sp = 12.0; amp = 0.4; droop = 0.3; }       // on its back: waving
		if (act == 19.0) { sp = 5.0; amp = 0.15; droop = -0.25; }     // hauling: low over the item
		if (act == 16.0) {                                            // on a trail: low, tapping in turn
			sp = 7.0; amp = 0.14;
			droop = -0.32 - 0.22 * max(0.0, sin(t * 7.0 + (side > 0.0 ? PI : 0.0)));
		}
		float a1 = sin(t * sp + side * 1.3) * amp;
		float a2 = cos(t * sp * 0.73 + side) * amp * 0.6;
		if (act == 4.0) {
			// the antenna being cleaned is drawn down through the leg's comb (angles mixed, not speeds,
			// so it never whips round as one side hands over to the other)
			float gw = groom_w(t, side);
			a1 = mix(a1, sin(t * 7.0 + side * 1.3) * 0.06, gw);
			a2 = mix(a2, cos(t * 5.1 + side) * 0.036, gw);
			droop = mix(droop, -0.75 + 0.12 * sin(t * 7.0), gw);
		}
		// the antenna turns at its socket, and is carried by the head as it nods and turns
		mat3 Ra = rot_y(a1 * side) * rot_z(a2 + droop);
		vec2 hp = head_pose(act, t, gait, mv);
		mat3 Rh = rot_y(hp.y) * rot_z(hp.x);
		vec3 hpiv = vec3(1.35, 1.15, 0.0) * K;
		vec3 v1 = piv + Ra * (V - piv);
		V = hpiv + Rh * (v1 - hpiv);
		NR = Rh * (Ra * NR);
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
			float side = V.z > 0.0 ? 1.0 : -1.0;
			float open = 0.04;
			if (act == 2.0) open = 0.35 + 0.35 * sin(t * 12.0);
			if (act == 6.0) open = 0.45;
			if (act == 7.0) open = 0.2 + 0.15 * sin(t * 6.0);
			if (act == 10.0) open = 0.3;
			if (act == 13.0) open = 0.25 + 0.2 * max(0.0, sin(t * 11.0));
			if (act == 14.0) open = 0.6;
			if (act == 8.0) open = 0.3;                        // gripping the load (open round it, tips on its sides)
			if (act == 19.0) open = 0.12;
			if (act == 4.0) open = 0.04 + (0.2 + 0.15 * sin(t * 6.0)) * groom_phase(t).y;    // working over a foreleg
			vec3 mp = vec3(2.85, 0.9, 0.3 * side) * K;
			V = mp + rot_y(open * side) * (V - mp);
			NR = rot_y(open * side) * NR;
		}
	} else if (part == 10.0) {
		// gaster: slow breathing pulse; the queen curls hers down to lay. rot_z(+) swings the tip down and
		// forward under the body, rot_z(-) raises it
		piv = vec3(-0.9, 1.05, 0.0) * K;
		float curl = act == 5.0 ? 0.35 + 0.08 * sin(t * 2.0) : 0.0;
		if (act == 13.0) curl = 0.8 + 0.08 * sin(t * 7.0);   // tip brought forward between the legs to spray
		if (act == 14.0) curl = -0.12;                         // alarmed: gaster raised
		if (act == 17.0) curl = 0.62 + 0.04 * sin(t * 2.0);  // tip brought forward under the body
		// carried clear of the ground and swaying against the head as the tripods alternate
		if (act != 5.0 && act != 11.0 && act != 13.0 && act != 17.0) {
			curl += 0.1 + 0.025 * sin(gait * 2.0) * mv;
			R = rot_y(-0.045 * sin(gait) * mv);
		}
		if (act == 4.0) {
			// bent round toward the hind leg wiping it
			R = R * rot_y(0.14 * (groom_side(t, 1.0, 0.25) - groom_side(t, -1.0, 0.25)) * groom_phase(t).z);
		}
		float b = 1.0 + 0.018 * sin(t * 1.6);
		vec3 sc = vec3(b) * (1.0 + full * vec3(0.22, 0.3, 0.32));
		R = R * rot_z(curl) * mat3(vec3(sc.x, 0, 0), vec3(0, sc.y, 0), vec3(0, 0, sc.z));
		stretch_out = full;
	}
	V = piv + R * (V - piv);
	NR = normalize(R * NR);
	// whole body: nose down while digging, front up while grooming
	float pitch = act == 2.0 ? -0.12 : (act == 4.0 ? 0.06 * groom_phase(t).x : (act == 10.0 ? -0.1 : (act == 13.0 ? -0.06 : (act == 17.0 ? -0.1 : (act == 19.0 ? 0.05 : 0.0)))));
	V = rot_z(pitch) * V;
	NR = rot_z(pitch) * NR;
	V.y += hlift;
	return V;
}

void vertex() {
	float part = floor(COLOR.a * 16.0 + 0.5);
	if (!IN_SHADOW_PASS || shadow_pose) {
	limb = (part >= 2.0 && part <= 9.0) || part == 11.0 ? 1.0 : 0.0;
	// y: code + 128 x the code being left, fraction = how much of the old pose still shows
	float y = INSTANCE_CUSTOM.y + 0.0005;
	float whole = floor(y);
	float left = y - whole - 0.0005;
	float code = mod(whole, 128.0);
	float prev = floor(whole / 128.0);
	vec3 n1 = NORMAL;
	float s1;
	gband = smoothstep(0.78, 0.98, 0.5 + 0.5 * sin(VERTEX.x / K * 6.5 + 1.2));   // rest-pose bands along the gaster
	vec3 v1 = pose(code, part, UV.x, VERTEX, n1, MODEL_MATRIX, INSTANCE_CUSTOM.x, INSTANCE_CUSTOM.z, INSTANCE_CUSTOM.w, !IN_SHADOW_PASS, s1);
	stretch = s1;
	if (left > 0.002 && prev != code && !IN_SHADOW_PASS) {      // (a shadow skips the easing)
		vec3 n0 = NORMAL;
		float s0;
		vec3 v0 = pose(prev, part, UV.x, VERTEX, n0, MODEL_MATRIX, INSTANCE_CUSTOM.x, INSTANCE_CUSTOM.z, INSTANCE_CUSTOM.w, true, s0);
		v1 = mix(v1, v0, left);
		n1 = normalize(mix(n1, n0, left) + vec3(0.0, 1e-4, 0.0));
		stretch = mix(s1, s0, left);
	}
	VERTEX = v1;
	NORMAL = n1;
#ifdef OUTLINE
	VERTEX += normalize(n1) * outline_w;      // the selection outline: the body grown out a little, seen from inside
#endif
	}
}

