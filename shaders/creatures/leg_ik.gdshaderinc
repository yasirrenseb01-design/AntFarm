// Jointed legs for the creatures (v0.12.33; docs/roadmap/PLAN_CREATURES.md). A leg is three stiff pieces - UV.x says
// which a vertex belongs to: 1 coxa + femur, 2 tibia, 3 tarsus - and the joints at rest come from the model's .json
// (written by tools/blender/props/<kind>.py, handed over by outworld_view): nothing about the legs is written twice.
//   - knee_up 0 (the ground beetle): the femur swings level round the hip, its far end (the knee) staying at the
//     height it has at rest - it stays under the body's side margin, wherever the foot is;
//     knee_up 1 (the wolf spider): the knee is bent upward, in the upright plane through hip and ankle - the femur
//     always leans out from the body over its foot, higher the nearer the foot comes;
//   - the tibia reaches from the knee down to the ankle;
//   - the tarsus lies on the ground at the ankle, kept as it is.
// The ankle is where the walk puts it: on the ground the foot stays where it was set down while the body goes over it
// (back by `stride` over the stance), then it is lifted and carried forward. The same sums as be_knee() in
// tools/blender/props/beetle.py and tools/dev/leg_clip.py.

#ifndef LEGS_MAX
#define LEGS_MAX 8
#endif
uniform vec3 hip[LEGS_MAX];
uniform vec3 knee[LEGS_MAX];
uniform vec3 ankle[LEGS_MAX];
uniform vec2 bend[LEGS_MAX];          // which side of the hip-ankle line the knee is bent out to (x, z)
uniform float knee_up = 0.0;
uniform float stride = 3.0;           // how far the body goes in one turn of the gait (model units)
const float LEG_DUTY = 0.62;          // the share of a step the foot is on the ground
uniform float leg_lift = 0.55;        // how high the ankle is carried forward (the model's .json "lift")

// v turned as a is turned onto b (both any length; not for opposite ones)
vec3 leg_turn(vec3 v, vec3 a, vec3 b) {
	a = normalize(a);
	b = normalize(b);
	vec3 c = cross(a, b);
	float d = dot(a, b);
	return v * d + cross(c, v) + c * dot(c, v) / (1.0 + d);
}

// Where the ankle of leg i is `turn` of the way through its step (0..1: on the ground first, then carried forward);
// walk 0..1: how much of the step is taken.
vec3 leg_ankle(int i, float turn, float walk) {
	vec3 a = ankle[i];
	float p = fract(turn);
	if (p < LEG_DUTY) {
		a.x += stride * walk * (0.5 - p / LEG_DUTY);
	} else {
		float u = (p - LEG_DUTY) / (1.0 - LEG_DUTY);
		a.x += stride * walk * (-0.5 + u * u * (3.0 - 2.0 * u));
		a.y += leg_lift * walk * sin(u * PI);
	}
	return a;
}

// The knee of leg i for its ankle at `a` (moved in toward the hip, or out, if the leg cannot reach: a is changed).
// up_sign: which way a knee_up knee is bent - 1 up from the body, -1 the other way (on its back: v0.13.3, the knees
// toward the sky, not into the ground).
vec3 leg_knee_up(int i, inout vec3 a, float up_sign) {
	vec3 h = hip[i];
	if (knee_up > 0.5) {
		float l1 = length(knee[i] - h);
		float l2s = length(ankle[i] - knee[i]);
		vec3 d = a - h;
		float dist = max(length(d), 0.001);
		d /= dist;
		float far = clamp(dist, abs(l1 - l2s) + 0.01, l1 + l2s - 0.01);
		a = h + d * far;
		float al = (l1 * l1 - l2s * l2s + far * far) / (2.0 * far);
		float up = sqrt(max(0.0, l1 * l1 - al * al));
		vec3 nn = vec3(0.0, up_sign, 0.0) - d * d.y * up_sign;
		nn = length(nn) > 0.001 ? normalize(nn) : vec3(1.0, 0.0, 0.0);
		return h + d * al + nn * up;
	}
	float ky = knee[i].y;
	float r1 = length(knee[i].xz - h.xz);
	float l2 = length(ankle[i] - knee[i]);
	float r2 = sqrt(max(0.01, l2 * l2 - (ky - a.y) * (ky - a.y)));
	vec2 u = a.xz - h.xz;
	float rho = max(length(u), 0.001);
	u /= rho;
	float reach = clamp(rho, abs(r1 - r2) + 0.01, r1 + r2 - 0.01);
	a.xz = h.xz + u * reach;
	float along = (r1 * r1 - r2 * r2 + reach * reach) / (2.0 * reach);
	float off = sqrt(max(0.0, r1 * r1 - along * along));
	vec2 n = vec2(u.y, -u.x);
	if (dot(n, bend[i]) < 0.0) {
		n = -n;
	}
	vec2 k = h.xz + u * along + n * off;
	return vec3(k.x, ky, k.y);
}

vec3 leg_knee(int i, inout vec3 a) {
	return leg_knee_up(i, a, 1.0);
}

// A leg's vertex and its normal, with the leg's ankle at `a`. seg: UV.x. up_sign: as leg_knee_up.
void leg_place_up(int i, float seg, vec3 a, inout vec3 v, inout vec3 nrm, float up_sign) {
	vec3 k = leg_knee_up(i, a, up_sign);
	if (seg < 1.5 && knee_up > 0.5) {
		vec3 was3 = knee[i] - hip[i];
		vec3 now3 = k - hip[i];
		v = hip[i] + leg_turn(v - hip[i], was3, now3);
		nrm = leg_turn(nrm, was3, now3);
	} else if (seg < 1.5) {
		vec2 was = normalize(knee[i].xz - hip[i].xz);
		vec2 now = normalize(k.xz - hip[i].xz);
		float c = dot(was, now);
		float s = was.x * now.y - was.y * now.x;
		vec3 d = v - hip[i];
		v = hip[i] + vec3(d.x * c - d.z * s, d.y, d.x * s + d.z * c);
		nrm = vec3(nrm.x * c - nrm.z * s, nrm.y, nrm.x * s + nrm.z * c);
	} else if (seg < 2.5) {
		vec3 was = ankle[i] - knee[i];
		vec3 now = a - k;
		v = k + leg_turn(v - knee[i], was, now);
		nrm = leg_turn(nrm, was, now);
	} else {
		v += a - ankle[i];
	}
}


void leg_place(int i, float seg, vec3 a, inout vec3 v, inout vec3 nrm) {
	leg_place_up(i, seg, a, v, nrm, 1.0);
}


// On its back (v0.13.3): the ankle of leg i kicking in the air over the belly - `base` its pose there, `kick` 0..1
// how hard (fading in its death throes), t the clock. Below the body in the model is up in the world then.
vec3 leg_kick(int i, vec3 base, float kick, float t) {
	float fi = float(i);
	return base + kick * vec3(0.9 * sin(t * 9.0 + fi * 1.7), -1.4 * abs(sin(t * 6.5 + fi * 2.1)), 0.7 * cos(t * 8.0 + fi * 2.3));
}
