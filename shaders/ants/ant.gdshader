shader_type spatial;
render_mode diffuse_burley;
// Ant body animation on the GPU. Each vertex carries a body-part id in COLOR.a (see ant_model3d.gd);
// each instance carries in INSTANCE_CUSTOM:
//   x = gait phase (radians, advanced by distance walked)   y = activity id
//   z = animation clock (seconds, per ant)                   w = how much it is walking (0..1)
// Activities: 0 walk/idle, 1 rest, 2 dig, 3 antennate, 4 groom, 5 lay eggs (queen),
//             6 trophallaxis (mouth-to-mouth feeding), 7 tend brood / attend queen, 8 carry,
//             9 milk aphids, 10 drink, 11 dead (on its back, legs curled),
//             12 just eclosed (legs and antennae unfold over the first seconds; z counts from 0),
//             13 fighting: clamped on with the mandibles, gaster curled forward under the body spraying
//                formic acid, legs braced; 14 alarmed: running in with mandibles agape, antennae forward.
// y >= 100: the crop is full of honeydew (gaster swollen, pale membranes showing between the plates).

uniform float rim_amount = 0.35;
uniform vec3 limb_gain = vec3(1.0);   // appendages are lighter than the body: amber-orange in L. niger queens
varying float stretch;
varying float limb;
const float K = 0.34;   // model design units -> mesh units

mat3 rot_x(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(1, 0, 0), vec3(0, c, s), vec3(0, -s, c)); }
mat3 rot_y(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(c, 0, -s), vec3(0, 1, 0), vec3(s, 0, c)); }
mat3 rot_z(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(c, s, 0), vec3(-s, c, 0), vec3(0, 0, 1)); }

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

	if (part >= 4.0 && part <= 9.0) {
		// legs: alternating tripods (front+hind of one side with the middle of the other)
		float li = floor((part - 4.0) / 2.0);
		float side = mod(part - 4.0, 2.0) < 0.5 ? -1.0 : 1.0;
		float grp = ((mod(li, 2.0) < 0.5) == (side < 0.0)) ? 0.0 : PI;
		float ph = gait + grp;
		float sw = sin(ph) * 0.42 * mv;
		float lift = max(0.0, cos(ph)) * 0.32 * mv;
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
	} else if (part == 2.0 || part == 3.0) {
		// antennae: constant exploratory sweeping; drumming when meeting a nestmate
		float side = part == 2.0 ? -1.0 : 1.0;
		piv = vec3(2.7, 1.45, 0.38 * side) * K;
		float sp = 2.2;
		float amp = 0.25;
		float droop = 0.0;
		if (act == 3.0 || act == 6.0) { sp = 11.0; amp = 0.4; droop = -0.15; }
		if (act == 1.0) { sp = 0.7; amp = 0.1; droop = -0.2; }
		if (act == 4.0) { sp = 7.0; amp = 0.25; droop = -0.55; }
		if (act == 2.0 || act == 7.0) { sp = 4.0; amp = 0.2; droop = -0.35; }
		if (act == 9.0) { sp = 9.0; amp = 0.35; droop = -0.45; }     // stroking the aphid's back
		if (act == 10.0) { sp = 3.0; amp = 0.12; droop = -0.4; }
		if (act == 11.0) { sp = 0.0; amp = 0.0; droop = 0.5; }
		if (act == 13.0) { sp = 9.0; amp = 0.2; droop = 0.35; }       // swept back, out of the way
		if (act == 14.0) { sp = 14.0; amp = 0.3; droop = 0.15; }      // held forward, flicking
		if (act == 12.0) { sp = 3.0; amp = 0.15; droop = -0.9 * (1.0 - clamp(t / 3.0, 0.0, 1.0)); }
		float a1 = sin(t * sp + side * 1.3) * amp;
		float a2 = cos(t * sp * 0.73 + side) * amp * 0.6;
		R = rot_y(a1 * side) * rot_z(a2 + droop);
	} else if (part == 1.0 || part == 11.0) {
		// head on the neck joint
		piv = vec3(1.35, 1.15, 0.0) * K;
		float nod = 0.0;
		if (act == 2.0) nod = -0.35 + 0.25 * sin(t * 10.0);     // biting into the soil
		if (act == 7.0) nod = -0.28 + 0.12 * sin(t * 4.0);      // licking brood / the queen
		if (act == 6.0) nod = -0.05 + 0.06 * sin(t * 3.0);      // passing a droplet mouth to mouth
		if (act == 1.0) nod = 0.03 * sin(t * 0.7);
		if (act == 4.0) nod = 0.2;
		if (act == 9.0) nod = -0.2 + 0.05 * sin(t * 3.0);
		if (act == 10.0) nod = -0.4 + 0.05 * sin(t * 4.0);     // lapping at the drop
		if (act == 13.0) nod = -0.3 + 0.12 * sin(t * 11.0);    // worrying at the grip
		if (act == 14.0) nod = 0.12;
		R = rot_z(nod);
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
		float b = 1.0 + 0.018 * sin(t * 1.6);
		vec3 sc = vec3(b) * (1.0 + full * vec3(0.22, 0.3, 0.32));
		R = rot_z(curl) * mat3(vec3(sc.x, 0, 0), vec3(0, sc.y, 0), vec3(0, 0, sc.z));
		stretch = full;
	}
	VERTEX = piv + R * (VERTEX - piv);
	NORMAL = normalize(R * NORMAL);
	// whole body: nose down while digging, front up while grooming
	float pitch = act == 2.0 ? -0.12 : (act == 4.0 ? 0.18 : (act == 10.0 ? -0.1 : (act == 13.0 ? 0.12 : 0.0)));
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
