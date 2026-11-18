// ForagerStep::meet: sim_surface._encounters line for line - two foragers meeting head-on stop for a moment and drum
// each other with their antennae. Who stands in each 6 px square this round is kept here (a square holds an ant while
// meet_at[it] is this round's number), as the GDScript keeps its own: only this round's entries are ever read, so the
// two give the same pairs and the same draws (tests/native_sim_test.gd).
#include "forager_k.h"
#include "forager_step.h"
#include <godot_cpp/core/math.hpp>
#include <map>
#include <utility>

using namespace godot;
using namespace forager_k;

void ForagerStep::meet(Object *p_sim, const Array &list) {
	if (p_sim == nullptr) {
		return;
	}
	const Names &nm = names();
	const Crt &M = crt();
	Ref<RandomNumberGenerator> g = p_sim->get(nm.s_rng);
	const Vector2 wd = p_sim->get(nm.s_world);
	if (g.is_null()) {
		return;
	}
	const int64_t mw = (int64_t)((double)wd.x / 6.0) + 2;
	const int64_t mh = (int64_t)((double)wd.y / 6.0) + 2;
	if (meet_w != mw || (int64_t)meet_at.size() != mw * mh) {
		meet_w = mw;
		meet_at.assign(mw * mh, -1);
		meet_who.assign(mw * mh, -1);
		meet_round = 0;
	}
	meet_round += 1;
	const int64_t rd = meet_round;
	std::map<std::pair<int64_t, int64_t>, int64_t> far;           // (off the box: square -> index in list)
	Pcg p;
	p.st = (uint64_t)g->get_state();
	bool ok = false;
	for (int64_t i = 0; i < list.size(); i++) {
		Variant a = list[i];
		if (a.get_type() != Variant::OBJECT) {
			continue;
		}
		if ((int64_t)a.get_named(nm.busy, ok) > 0 || (int64_t)a.get_named(nm.meet_cd, ok) > 0) {
			continue;
		}
		const int64_t st = a.get_named(nm.state, ok);
		if (st == IN_NEST || st == DEFEND || st == DRAG) {
			continue;
		}
		const Vector2 apos = a.get_named(nm.pos, ok);
		const int64_t kx = (int64_t)((double)apos.x / 6.0);
		const int64_t ky = (int64_t)((double)apos.y / 6.0);
		int64_t oi = -1;
		const int64_t k = ky * mw + kx;
		const bool on = kx >= 0 && ky >= 0 && kx < mw && ky < mh;
		if (on) {
			if (meet_at[k] == rd) {
				oi = meet_who[k];
			}
		} else {
			auto it = far.find({ kx, ky });
			if (it != far.end()) {
				oi = it->second;
			}
		}
		if (oi < 0) {
			if (on) {
				meet_at[k] = rd;
				meet_who[k] = i;
			} else {
				far[{ kx, ky }] = i;
			}
			continue;
		}
		Variant o = list[oi];
		const Vector2 opos = o.get_named(nm.pos, ok);
		if ((int64_t)o.get_named(nm.busy, ok) > 0 || (double)apos.distance_squared_to(opos) > 16.0) {
			continue;
		}
		const double aang = a.get_named(nm.ang, ok), oang = o.get_named(nm.ang, ok);
		if (std::abs(Math::wrapf(aang - oang, -PI_D, PI_D)) < 2.0) {
			continue;                              // walking the same way: no greeting
		}
		const int64_t secs = p.randi_range(12, 30);
		Variant *pair[2][2] = { { &a, &o }, { &o, &a } };
		for (int j = 0; j < 2; j++) {
			Variant &x = *pair[j][0];
			const Vector2 xp = x.get_named(nm.pos, ok), yp = pair[j][1]->get_named(nm.pos, ok);
			x.set_named(nm.busy, secs, ok);
			x.set_named(nm.act, (int64_t)3, ok);
			x.set_named(nm.ang, (double)M.angle(yp - xp), ok);
			x.set_named(nm.meet_cd, p.randi_range(240, 600), ok);
		}
		if (on) {
			meet_at[k] = -1;
		} else {
			far.erase({ kx, ky });
		}
	}
	g->set_state(p.st);
	// (meet_who: an index into this round's list - an older round's never read, its square's round is old)
}
