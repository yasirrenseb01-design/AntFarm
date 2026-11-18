// ForagerStep::run and ::walk: simulation.step's loop over `outside` and sim_foragers._step_ant, line for line
// (see forager_step.h, forager_step.cpp for the helpers).
#include "forager_step.h"
#include "forager_k.h"
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <cmath>

using namespace godot;
using namespace forager_k;

static inline double mxd(double a, double b) {
	return a > b ? a : b;                  // (maxf: MAX(a, b))
}
static inline double mnd(double a, double b) {
	return a < b ? a : b;                  // (minf: MIN(a, b))
}

// The ants of `list` from `from` on, as simulation.step's loop does them, up to the first one it hands back to the
// GDScript (its index; list.size() when all are done). The pheromone fields' arrays are taken from them for the run
// (so writing copies nothing) and given back, with the random generator's state, before it returns.
int64_t ForagerStep::run(const Array &list, int64_t from) {
	const int64_t m = list.size();
	if (sim == nullptr) {
		return from < m ? from : m;
	}
	const Names &nm = names();
	Object *fo[2] = { home, food };
	for (int f = 0; f < 2; f++) {
		fval[f] = fo[f]->get(nm.val);
		fstamp[f] = fo[f]->get(nm.stamp);
		fclock[f] = fo[f]->get(nm.clock);
		fo[f]->set(nm.val, PackedFloat32Array());
		fo[f]->set(nm.stamp, PackedFloat64Array());
	}
	aval = alarm->get(nm.val);
	astamp = alarm->get(nm.stamp);
	aclock = alarm->get(nm.clock);
	rock = sim->get(nm.s_rock);
	food_cell = sim->get(nm.s_food_cell);
	rk = rock.ptr();
	fc = food_cell.ptr();
	av = aval.ptr();
	as = astamp.ptr();
	ncell = rock.size();
	const bool sizes_ok = food_cell.size() == ncell && aval.size() == ncell && astamp.size() == ncell &&
			fval[0].size() == ncell && fstamp[0].size() == ncell && fval[1].size() == ncell && fstamp[1].size() == ncell;
	food_info.assign(foods.size(), Food());
	creature_pos.clear();
	for (int64_t c = 0; c < creatures.size(); c++) {
		const Dictionary d = creatures[c];
		creature_pos.push_back(d[nm.pos]);
	}
	pcg.st = (uint64_t)rng->get_state();
	int64_t i = from;
	if (sizes_ok) {
		for (; i < m; i++) {
			const Variant &a = list[i];
			if (a.get_type() != Variant::OBJECT) {
				break;
			}
			const int r = walk(a);
			if (r == 1) {
				break;
			}
			if (r == 0) {
				steps++;
			}
		}
	}
	rng->set_state(pcg.st);
	for (int f = 0; f < 2; f++) {
		fo[f]->set(nm.val, fval[f]);
		fo[f]->set(nm.stamp, fstamp[f]);
		fval[f] = PackedFloat32Array();
		fstamp[f] = PackedFloat64Array();
	}
	aval = PackedFloat32Array();
	astamp = PackedFloat64Array();
	rock = PackedByteArray();
	food_cell = PackedInt32Array();
	rk = nullptr;
	fc = nullptr;
	av = nullptr;
	as = nullptr;
	return i;
}

// One ant's tick: 0 walked (all of it done here), 1 handed back (nothing of its tick done: no field set, no draw taken),
// 2 not walked this tick (in the nest, hauling, dead) - simulation.step's loop body and sim_foragers._step_ant.
int ForagerStep::walk(const Variant &ant) {
	const Names &nm = names();
	const Crt &M = crt();
	// (its fields read and written through the Variant: ~25% less than through Object::get/set - access_probe)
	Variant a = ant;
	bool ok = false;
	auto G = [&](const StringName &k) -> Variant {
		return a.get_named(k, ok);
	};
	auto S = [&](const StringName &k, const Variant &x) {
		a.set_named(k, x, ok);
	};
	const int64_t st0 = G(nm.state);
	if (st0 == DRAG || st0 == IN_NEST) {
		return 2;
	}
	if ((bool)G(nm.dead)) {
		return 2;
	}
	if (st0 != SEARCH && st0 != RETURN && st0 != HOME) {
		return 1;                                  // (defending, carrying soil or a corpse: the GDScript's)
	}
	const uint64_t rng0 = pcg.st;
	bad = false;
	Vector2 pos = G(nm.pos);
	bool w_pos = false;
	if ((double)pos.x < 3.0 || (double)pos.y < 3.0 || (double)pos.x > (double)world.x - 3.0 || (double)pos.y > (double)world.y - 3.0) {
		pos = pos.clamp(Vector2(4, 4), world - Vector2(4, 4));     // (let go of an enemy at the edge: simulation.step)
		w_pos = true;
	}
	// what this tick changes (written at the end, only those that changed)
	int64_t meet_cd = G(nm.meet_cd), busy = G(nm.busy), act = 0, trip = 0, since = 0, follow = 0, state = st0;
	bool turn_after = false;
	double ang = 0.0, phase = 0.0, slide = 0.0;
	bool w_meet = false, w_busy = false, w_act = false, w_ta = false, w_ang = false, w_trip = false, w_phase = false,
		 w_since = false, w_state = false, w_follow = false, w_slide = false;
	Dep dep;
	auto commit = [&]() -> int {
		if (w_meet) S(nm.meet_cd, meet_cd);
		if (w_busy) S(nm.busy, busy);
		if (w_act) S(nm.act, act);
		if (w_ta) S(nm.turn_after, turn_after);
		if (w_ang) S(nm.ang, ang);
		if (w_trip) S(nm.trip, trip);
		if (w_phase) S(nm.phase, phase);
		if (w_since) S(nm.since, since);
		if (w_state) S(nm.state, state);
		if (w_follow) S(nm.follow, follow);
		if (w_slide) S(nm.slide, slide);
		if (w_pos) S(nm.pos, pos);
		deposit(dep);
		return 0;
	};
	auto back = [&]() -> int {
		pcg.st = rng0;
		return 1;
	};
	if (meet_cd > 0) {
		meet_cd -= n;
		w_meet = true;
	}
	if (busy > 0) {
		busy -= n;
		w_busy = true;
		if (busy <= 0) {
			act = G(nm.act);
			if (act == ACT_AWAY) {
				return back();                     // (_back_from_beyond: the GDScript's)
			}
			act = 0;
			w_act = true;
			turn_after = G(nm.turn_after);
			if (turn_after) {
				turn_after = false;
				w_ta = true;
				ang = (double)G(nm.ang) + PI_D;    // loaded up: turn round and head home
				w_ang = true;
			}
		}
		return commit();
	}
	trip = (int64_t)G(nm.trip) + n;
	w_trip = true;
	// stop-and-go: a searching ant halts every few seconds to sweep its head and antennae
	if (state == SEARCH || state == HOME) {
		const double stop_p = state == SEARCH ? 0.004 : 0.0012;
		if ((double)pcg.randf() < stop_p * (double)n) {
			busy = pcg.randi_range(10, 30);
			act = ACT_SCAN;
			w_busy = w_act = true;
			return commit();
		}
	}
	double spd = spd0;
	const int64_t carry = G(nm.carry);
	if (carry >= PROTEIN) {
		spd *= 0.7;
	}
	const double hurt = G(nm.hurt);
	if (hurt > 0.0) {
		spd *= 1.0 - 0.35 * hurt;
	}
	phase = (double)G(nm.phase) + spd * 0.95;
	w_phase = true;
	const int64_t ci = (int64_t)((double)pos.y * INV_CELL) * gw + (int64_t)((double)pos.x * INV_CELL);
	if (ci < 0 || ci >= ncell) {
		return back();
	}
	if (rk[ci] == 2) {
		spd *= 0.6;                                // clambering over a small stone
	}
	const int64_t sense_p = SENSE_EVERY > n ? SENSE_EVERY : n;
	const int64_t drop_p = 2 > n ? 2 : n;
	const int64_t aid = G(nm.id);
	const bool sense_now = ((trip + aid) % sense_p) < n;
	const bool drop_now = ((trip + aid) % drop_p) < n;
	if (sense_now && !creature_pos.empty()) {
		for (const Vector2 &cp : creature_pos) {
			if ((double)pos.distance_squared_to(cp) < 900.0) {
				return back();                     // (an enemy close by: the alarm, the fight)
			}
		}
		if (carry == NONE) {
			const double v = av[ci];
			if ((v <= 0.0 ? 0.0 : v * M.exp(aclock - as[ci])) > 0.6) {
				return back();
			}
		}
	}
	ang = G(nm.ang);
	w_ang = true;
	follow = G(nm.follow);
	// _turn_toward
	auto turn_toward = [&](const Vector2 &target, double kt) {
		if (follow > 0) {
			// edging around an obstacle: only turn back toward the goal once the straight way is clear
			const Vector2 probe = pos + (target - pos).normalized() * (real_t)6.0;
			if (blocked(probe) || blocked(pos.lerp(probe, (real_t)0.5))) {
				return;
			}
			follow = 0;
			w_follow = true;
		}
		const double kk = 1.0 - M.pow(1.0 - kt, (double)n);
		ang += Math::wrapf((double)M.angle(target - pos) - ang, -PI_D, PI_D) * kk;
	};
	// _steer
	auto steer = [&](int f, int64_t period) {
		if (follow > 0) {
			return;
		}
		const double px = pos.x, py = pos.y, wx = world.x, wy = world.y;
		const float *val = fval[f].ptr();
		const double *stamp = fstamp[f].ptr();
		auto smp = [&](double an) -> double {
			const double x = px + M.cos(an) * 10.0;
			const double y = py + M.sin(an) * 10.0;
			if (x >= 0.0 && y >= 0.0 && x < wx && y < wy) {
				const int64_t i = (int64_t)(y * INV_CELL) * gw + (int64_t)(x * INV_CELL);
				if (i < 0 || i >= ncell) {
					bad = true;
					return -1.0;
				}
				if (rk[i] != 1) {
					const double v = val[i];
					return v <= 0.0 ? 0.0 : v * M.exp(fclock[f] - stamp[i]);
				}
			}
			return -1.0;
		};
		const double l = smp(ang - 0.55);
		const double c = smp(ang);
		const double r = smp(ang + 0.55);
		if (mxd(l, mxd(c, r)) < 0.03 || (c >= l && c >= r)) {
			return;
		}
		const double turn = mnd(1.0, 0.45 * (double)period / (double)SENSE_EVERY);
		ang += l > r ? -turn : turn;
	};
	if (state == SEARCH) {
		if (drop_now) {
			dep = { 0, ci, 0.5 * (double)drop_p * mxd(0.05, 1.0 - (double)trip / 4000.0) };
		}
		const int64_t fi = fc[ci];
		bool near = false;
		if (fi >= 0) {
			if (fi >= (int64_t)food_info.size()) {
				return back();
			}
			const Food &f = food_at(fi);
			// foragers switch to what the colony lacks: a sugar-full colony ignores sugar, and so on
			const bool wanted = f.type == SUGAR ? want_sugar : want_protein;
			if (wanted && f.amt >= 1.0 && !f.rotten) {
				if ((double)pos.distance_squared_to(f.pos) < M.pow(f.r + 2.0 + spd, 2.0)) {
					return back();                 // (at it: picked up or taken hold of - _pick_up, _start_drag)
				}
				near = true;
				turn_toward(f.pos, 0.15);
			}
		}
		if (!near && sense_now) {
			steer(1, sense_p);
		}
		const int64_t patience = G(nm.patience);
		if (trip > patience) {
			state = HOME;
			w_state = true;
		}
	} else {
		since = (int64_t)G(nm.since) + n;
		w_since = true;
		if (drop_now && (carry == SUGAR || carry == PROTEIN)) {
			dep = { 1, ci, 1.2 * (double)drop_p * mxd(0.05, 1.0 - (double)since / 3000.0) };
		}
		const Vector2 hp = home_at(pos);
		const double d2 = pos.distance_squared_to(hp);
		if (d2 < NEST_R * NEST_R) {
			return back();                         // (home: _arrive)
		}
		if (d2 < 6400.0) {
			turn_toward(hp, 0.2);
		} else {
			if (sense_now) {
				steer(0, sense_p);
			}
			turn_toward(hp, 0.03);                 // path integration keeps them oriented
		}
	}
	if (bad) {
		return back();
	}
	ang = ang + (double)pcg.randf_range((float)-0.16, (float)0.16) * noise_k;
	if (follow > 0) {
		follow -= n;
		w_follow = true;
	}
	Vector2 np = pos + Vector2((real_t)M.cos(ang), (real_t)M.sin(ang)) * (real_t)spd;
	const bool glass = (double)np.x < 3.0 || (double)np.y < 3.0 || (double)np.x > (double)world.x - 3.0 || (double)np.y > (double)world.y - 3.0;
	if (state == SEARCH && wild && glass && (double)pcg.randf() < BEYOND_P) {
		busy = pcg.randi_range(BEYOND_LO, BEYOND_HI);   // out past the plot's edge for a while
		act = ACT_AWAY;
		w_busy = w_act = true;
		return commit();
	}
	if (state == SEARCH && !wild && glass && (double)pcg.randf() < WALL_CLIMB_P) {
		busy = WALL_TICKS;                         // up the glass
		act = ACT_WALL;
		turn_after = true;
		w_busy = w_act = w_ta = true;
		return commit();
	}
	bool hit = glass;
	if (!glass) {
		const int64_t ni = (int64_t)((double)np.y / CELL) * gw + (int64_t)((double)np.x / CELL);
		if (ni < 0 || ni >= ncell) {
			return back();
		}
		hit = rk[ni] == 1;
	}
	if (hit) {
		follow = 24;
		w_follow = true;
		// follow the edge of the obstacle: try headings swinging toward the ant's chosen side
		static const double TURNS[4] = { 0.5, 1.0, 1.6, 2.3 };
		slide = G(nm.slide);
		const double sides[2] = { slide, -slide };
		bool found = false;
		for (int t = 0; t < 4 && !found; t++) {
			for (int s = 0; s < 2; s++) {
				const double ta = ang + TURNS[t] * sides[s];
				const Vector2 q = pos + Vector2((real_t)M.cos(ta), (real_t)M.sin(ta)) * (real_t)spd;
				if (!blocked(q)) {
					ang = ta;
					np = q;
					found = true;
					break;
				}
			}
		}
		if (!found) {
			ang += PI_D;
			slide = -slide;
			w_slide = true;
			return commit();
		}
		if ((double)pcg.randf() < 0.01) {
			slide = -slide;
			w_slide = true;
		}
	}
	pos = np;
	w_pos = true;
	return commit();
}
