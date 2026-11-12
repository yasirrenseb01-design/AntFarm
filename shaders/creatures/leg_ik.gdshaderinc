// Jointed legs for the creatures (v0.12.33; docs/roadmap/PLAN_CREATURES.md). A leg is three stiff pieces - UV.x says
// which a vertex belongs to: 1 coxa + femur, 2 tibia, 3 tarsus - and the joints at rest come from the model's .json
// (written by tools/blender/props/<kind>.py, handed over by outworld_view): nothing about the legs is written twice.
//   - the femur swings level round the hip, its far end (the knee) staying at the height it has at rest: it stays
//     under the body's side margin, wherever the foot is;
//   - the tibia reaches from the knee down to the ankle;
//   - the tarsus lies on the ground at the ankle, kept as it is.
// The ankle is where the walk puts it: on the ground the foot stays where it was set down while the body goes over it
// (back by `stride` over the stance), then it is lifted and carried forward. The same sums as be_knee() in
// tools/blender/props/beetle.py and tools/dev/leg_clip.py.

const int LEGS_MAX = 8;
uniform vec3 hip[LEGS_MAX];
uniform vec3 knee[LEGS_MAX];
uniform vec3 ankle[LEGS_MAX];
uniform vec2 bend[LEGS_MAX];          // which side of the hip-ankle line the knee is bent out to (x, z)
uniform float stride = 3.0;           // how far the body goes in one turn of the gait (model units)
const float LEG_DUTY = 0.62;          // the share of a step the foot is on the ground
const float LEG_LIFT = 0.55;          // how high the ankle is carried forward

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
		a.y += LEG_LIFT * walk * sin(u * PI);
	}
	return a;
}

// The knee of leg i for its ankle at `a` (moved in toward the hip, or out, if the leg cannot reach: a is changed).
vec3 leg_knee(int i, inout vec3 a) {
	vec3 h = hip[i];
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

// A leg's vertex and its normal, with the leg's ankle at `a`. seg: UV.x.
void leg_place(int i, float seg, vec3 a, inout vec3 v, inout vec3 nrm) {
	vec3 k = leg_knee(i, a);
	if (seg < 1.5) {
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
