// ForagerStep's random generator (the engine's RandomPCG reproduced) and the two probes the test compares with the
// engine's own: rng_probe (the draws) and math_probe (the sums). See forager_step.h.
#include "forager_step.h"
#include "forager_k.h"
#include <godot_cpp/core/math.hpp>
#include <cmath>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

// the engine's own (UtilityFunctions: what GDScript's cos, sin, exp and pow call)
static double e_cos(double x) { return UtilityFunctions::cos(x); }
static double e_sin(double x) { return UtilityFunctions::sin(x); }
static double e_exp(double x) { return UtilityFunctions::exp(x); }
static double e_pow(double x, double y) { return UtilityFunctions::pow(x, y); }
static double e_atan2(double y, double x) { return UtilityFunctions::atan2(y, x); }

const forager_k::Crt &forager_k::crt() {
	static const Crt c = { e_cos, e_sin, e_exp, e_pow, e_atan2 };
	return c;
}

// ---------------------------------------------------------------- the engine's RandomPCG (core/math/random_pcg.h)
static const uint64_t PCG_INC = (1442695040888963407ULL << 1u) | 1u;     // (PCG_DEFAULT_INC_64, as pcg32_srandom_r sets it)

uint32_t ForagerStep::Pcg::next() {
	const uint64_t old = st;
	st = old * 6364136223846793005ULL + PCG_INC;
	const uint32_t xs = (uint32_t)(((old >> 18u) ^ old) >> 27u);
	const uint32_t rot = (uint32_t)(old >> 59u);
	return (xs >> rot) | (xs << ((-rot) & 31u));
}

uint32_t ForagerStep::Pcg::bounded(uint32_t bound) {
	const uint32_t threshold = (uint32_t)(-bound) % bound;
	for (;;) {
		const uint32_t r = next();
		if (r >= threshold) {
			return r % bound;
		}
	}
}

float ForagerStep::Pcg::randf() {
	const uint32_t proto = next();
	if (proto == 0) {
		return 0.0f;
	}
	return std::ldexp((float)(next() | 0x80000001u), -32 - __builtin_clz(proto));
}

float ForagerStep::Pcg::randf_range(float from, float to) {
	return randf() * (to - from) + from;
}

int64_t ForagerStep::Pcg::randi_range(int64_t from, int64_t to) {
	const int32_t f = (int32_t)from, t = (int32_t)to;
	if (f == t) {
		return f;
	}
	return (int64_t)((int32_t)bounded((uint32_t)std::abs(f - t) + 1u) + (f < t ? f : t));
}

// kinds: 0 randf, 1 randf_range(-0.16, 0.16), 2 randi_range(10, 30), 3 randi_range(90, 220), 4 randi (the raw draw);
// the values drawn from `state` one after another, then the state left (tests/native_sim_test.gd draws the same in GDScript)
PackedFloat64Array ForagerStep::rng_probe(int64_t state, const PackedInt32Array &kinds) {
	Pcg p;
	p.st = (uint64_t)state;
	PackedFloat64Array out;
	for (int64_t i = 0; i < kinds.size(); i++) {
		switch (kinds[i]) {
			case 0: out.append(p.randf()); break;
			case 1: out.append(p.randf_range((float)-0.16, (float)0.16)); break;
			case 2: out.append((double)p.randi_range(10, 30)); break;
			case 3: out.append((double)p.randi_range(90, 220)); break;
			default: out.append((double)p.next()); break;
		}
	}
	out.append((double)(int64_t)p.st);
	return out;
}

// the sums the walk uses, on given numbers (tests/native_sim_test.gd does them in GDScript and compares every bit):
// for each pair (a, b): cos a, sin a, exp a, pow(a, b), wrapf(a, -PI, PI), Vector2(a, b).angle() (Crt::angle),
// Vector2(a, b).normalized() * 6.0, Vector2(a, b).lerp(Vector2(b, a), 0.5), Vector2(a, b) + Vector2(cos a, sin a) * b
PackedFloat64Array ForagerStep::math_probe(const PackedFloat64Array &in) {
	PackedFloat64Array out;
	const forager_k::Crt &m = forager_k::crt();
	for (int64_t i = 0; i + 1 < in.size(); i += 2) {
		const double a = in[i], b = in[i + 1];
		out.append(m.cos(a));
		out.append(m.sin(a));
		out.append(m.exp(a));
		out.append(m.pow(a, b));
		out.append(Math::wrapf(a, -forager_k::PI_D, forager_k::PI_D));
		out.append((double)m.angle(Vector2((real_t)a, (real_t)b)));
		const Vector2 nz = Vector2((real_t)a, (real_t)b).normalized() * (real_t)6.0;
		out.append((double)nz.x);
		out.append((double)nz.y);
		const Vector2 lp = Vector2((real_t)a, (real_t)b).lerp(Vector2((real_t)b, (real_t)a), (real_t)0.5);
		out.append((double)lp.x);
		out.append((double)lp.y);
		const Vector2 st = Vector2((real_t)a, (real_t)b) + Vector2((real_t)m.cos(a), (real_t)m.sin(a)) * (real_t)b;
		out.append((double)st.x);
		out.append((double)st.y);
	}
	return out;
}
