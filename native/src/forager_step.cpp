// ForagerStep: see forager_step.h. Every line below is a line of sim_foragers.gd (_step_ant, _steer, _turn_toward,
// _home_at), sim_base.gd (blocked), pheromone_field.gd (read_i, deposit_i) or simulation.gd (the loop over `outside`):
// GDScript's float is a double and the engine's Vector2 holds floats - kept so here (and -ffp-contract=off: SConstruct),
// so every number comes out to the last bit as the GDScript's (tests/native_sim_test.gd runs both and compares).
#include "forager_step.h"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <cmath>

using namespace godot;

#include "forager_k.h"

using namespace forager_k;

const forager_k::Names &forager_k::names() {
	static Names *nm = new Names();          // (made at the first tick, after the engine is up)
	return *nm;
}

void ForagerStep::_bind_methods() {
	ClassDB::bind_method(D_METHOD("begin", "sim", "holes", "consts"), &ForagerStep::begin);
	ClassDB::bind_method(D_METHOD("run", "list", "from"), &ForagerStep::run);
	ClassDB::bind_method(D_METHOD("meet", "sim", "list"), &ForagerStep::meet);
	ClassDB::bind_method(D_METHOD("tasks", "workers", "by_forage", "outside", "k"), &ForagerStep::tasks);
	ClassDB::bind_method(D_METHOD("duty_start", "workers", "duty_h"), &ForagerStep::duty_start);
	ClassDB::bind_method(D_METHOD("check", "consts"), &ForagerStep::check);
	ClassDB::bind_method(D_METHOD("metabolism", "workers", "k", "founding_w", "dry", "rng_state"), &ForagerStep::metabolism);
	ClassDB::bind_method(D_METHOD("get_steps"), &ForagerStep::get_steps);
	ClassDB::bind_static_method("ForagerStep", D_METHOD("rng_probe", "state", "kinds"), &ForagerStep::rng_probe);
	ClassDB::bind_static_method("ForagerStep", D_METHOD("math_probe", "in"), &ForagerStep::math_probe);
}

// The GDScript's constants against these (simulation.gd _fwd_consts): false - the GDScript does it all.
bool ForagerStep::check(const PackedFloat64Array &p_consts) {
	if (p_consts.size() != NK) {
		return false;
	}
	for (int i = 0; i < NK; i++) {
		if (p_consts[i] != K[i]) {
			return false;
		}
	}
	return true;
}

// ---------------------------------------------------------------- the tick's values

void ForagerStep::begin(Object *p_sim, const Array &p_holes, const PackedFloat64Array &p_consts) {
	const Names &nm = names();
	sim = nullptr;
	steps = 0;
	if (p_sim == nullptr || p_consts.size() != NK) {
		return;
	}
	for (int i = 0; i < NK; i++) {
		if (p_consts[i] != K[i]) {
			return;                       // (a constant changed in the GDScript and not here: run() hands every ant back)
		}
	}
	sim = p_sim;
	rng = sim->get(nm.s_rng);
	home = sim->get(nm.s_home);
	food = sim->get(nm.s_food);
	alarm = sim->get(nm.s_alarm);
	foods = sim->get(nm.s_foods);
	creatures = sim->get(nm.s_creatures);
	world = sim->get(nm.s_world);
	nest_pos = sim->get(nm.s_nest_pos);
	gw = sim->get(nm.s_gw);
	n = sim->get(nm.s_substep);
	if (n < 1) {
		n = 1;
	}
	spd0 = sim->get(nm.s_spd);
	noise_k = sim->get(nm.s_noise_k);
	wild = sim->get(nm.s_wild);
	want_sugar = sim->get(nm.s_want_sugar);
	want_protein = sim->get(nm.s_want_protein);
	holes.clear();
	for (int64_t i = 0; i < p_holes.size(); i++) {
		holes.push_back(p_holes[i]);
	}
	if (rng.is_null() || home == nullptr || food == nullptr || alarm == nullptr || gw <= 0 || holes.empty()) {
		sim = nullptr;
	}
}

// ---------------------------------------------------------------- helpers (the GDScript functions of the same names)

bool ForagerStep::blocked(const Vector2 &p) const {
	if ((double)p.x < 3.0 || (double)p.y < 3.0 || (double)p.x > (double)world.x - 3.0 || (double)p.y > (double)world.y - 3.0) {
		return true;
	}
	// rock[home.index(p.x, p.y)] == 1  (index: cx = int(x / cs), cy = int(y / cs), -1 past the far edges)
	const int64_t cx = (int64_t)((double)p.x / CELL);
	const int64_t cy = (int64_t)((double)p.y / CELL);
	const int64_t gh = ncell / gw;
	int64_t i = (cx >= gw || cy >= gh) ? -1 : cy * gw + cx;
	if (i < 0) {
		i += ncell;                        // (GDScript reads index -1 as the last)
	}
	return i >= 0 && i < ncell && rk[i] == 1;
}

const ForagerStep::Food &ForagerStep::food_at(int64_t fi) {
	Food &f = food_info[fi];
	if (!f.read) {
		const Names &nm = names();
		const Dictionary d = foods[fi];
		f.read = true;
		f.type = d[nm.type];
		f.amt = d[nm.amt];
		f.rotten = d[nm.rotten];
		f.pos = d[nm.pos];
		f.r = d[nm.r];
	}
	return f;
}

Vector2 ForagerStep::home_at(const Vector2 &p) const {
	if (holes.size() == 1) {
		return nest_pos;
	}
	Vector2 best = nest_pos;
	for (const Vector2 &h : holes) {
		if (p.distance_squared_to(h) < p.distance_squared_to(best)) {
			best = h;
		}
	}
	return best;
}

double ForagerStep::read_field(int f, int64_t i) const {
	const Crt &M = crt();
	const double v = fval[f].ptr()[i];
	if (v <= 0.0) {
		return 0.0;
	}
	return v * M.exp(fclock[f] - fstamp[f].ptr()[i]);
}

void ForagerStep::deposit(const Dep &d) {
	if (d.field < 0) {
		return;
	}
	const Crt &M = crt();
	float *val = fval[d.field].ptrw();
	double *stamp = fstamp[d.field].ptrw();
	double v = val[d.cell];
	if (v > 0.0) {
		v *= M.exp(fclock[d.field] - stamp[d.cell]);
	}
	const double w = v + d.amount;
	val[d.cell] = (float)(FIELD_MAX < w ? FIELD_MAX : w);           // (minf: MIN(a, b))
	stamp[d.cell] = fclock[d.field];
}
