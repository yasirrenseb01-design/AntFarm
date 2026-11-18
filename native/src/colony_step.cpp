// ForagerStep::tasks, ::duty_start, ::metabolism - loops over every worker of the colony tick and the duty round.
// ForagerStep::metabolism: the loop over the workers in sim_colony._metabolism line for line (each eats from its own
// crop, then burns its own fat; lays fat down; goes hungry; dies). The deaths are handed back in order for the GDScript
// to carry out (_kill draws nothing and changes nothing the loop reads after: the same as killing them in the loop).
// k: w_need, keep, fat_each, store_max, fat_room, starve_k, risk, dt, food_eaten, food_in, queen_reserve, toilets_due
// Back: [food_eaten, food_in, queen_reserve, toilets_due, fat_room, c_sum, f_sum, short, rng_state, kills, causes]
// (causes: 0 starve, 1 thirst, 2 old, 3 out). Checked against the GDScript by tests/native_sim_test.gd.
#include "forager_k.h"
#include "forager_step.h"
#include <godot_cpp/variant/packed_int32_array.hpp>

using namespace godot;
using namespace forager_k;

Array ForagerStep::metabolism(const Array &workers, const PackedFloat64Array &k, bool founding_w, bool dry, int64_t rng_state) {
	Array out;
	if (k.size() < 12) {
		return out;
	}
	const Names &nm = names();
	const double w_need = k[0], keep = k[1], fat_each = k[2], store_max = k[3], starve_k = k[5], risk = k[6], dt = k[7];
	double fat_room = k[4], food_eaten = k[8], food_in = k[9], q_reserve = k[10], toilets_due = k[11];
	double c_sum = 0.0, f_sum = 0.0;
	int64_t shorts = 0;
	PackedInt32Array kills, causes;
	Pcg p;
	p.st = (uint64_t)rng_state;
	bool ok = false;
	for (int64_t i = 0; i < workers.size(); i++) {
		Variant a = workers[i];
		double crop = a.get_named(nm.crop, ok);
		double body_fat = a.get_named(nm.body_fat, ok);
		double miss = w_need - crop;
		double ate = w_need;
		bool w_fat = false;
		if (miss <= 0.0) {
			crop -= w_need;
			miss = 0.0;
		} else {
			crop = 0.0;
			const double burn = miss < body_fat ? miss : body_fat;     // (minf)
			body_fat -= burn;
			w_fat = true;
			miss -= burn;
			ate = w_need - miss;
			food_eaten -= miss;
			if ((int64_t)a.get_named(nm.carry, ok) == SUGAR) {
				miss = 0.0;                          // a forager on its way home drinks from its load
			}
			if (miss > 0.0 && founding_w && q_reserve > 0.0) {
				const double give = miss < q_reserve ? miss : q_reserve;
				q_reserve -= give;
				miss -= give;
				food_eaten += give;
				food_in += give;
			}
		}
		const int64_t state = a.get_named(nm.state, ok);
		if (state == IN_NEST) {
			toilets_due += ate;
		}
		if (crop > keep && body_fat < fat_each && fat_room > 0.0) {
			const double x = crop - keep, y = fat_each - body_fat;
			const double xy = x < y ? x : y;
			const double zw = store_max < fat_room ? store_max : fat_room;
			const double store = xy < zw ? xy : zw;
			crop -= store;
			body_fat += store;
			w_fat = true;
			fat_room -= store;
		}
		a.set_named(nm.crop, crop, ok);
		if (w_fat) {
			a.set_named(nm.body_fat, body_fat, ok);
		}
		c_sum += crop;
		f_sum += body_fat;
		const bool empty = miss > 1e-12;
		double energy = a.get_named(nm.energy, ok);
		if (empty) {
			shorts += 1;
			energy -= starve_k * (miss / w_need) / (double)a.get_named(nm.hardiness, ok);
		} else if (dry) {
			energy -= dt / 6.0 / (double)a.get_named(nm.hardiness, ok);
		} else {
			const double e1 = energy + dt;
			energy = 1.0 < e1 ? 1.0 : e1;
		}
		a.set_named(nm.energy, energy, ok);
		if (energy <= 0.0) {
			kills.append((int32_t)i);
			causes.append(empty ? 0 : 1);
		} else if ((double)a.get_named(nm.age, ok) > (double)a.get_named(nm.life, ok)) {
			kills.append((int32_t)i);
			causes.append(2);
		} else if (state != IN_NEST && (double)p.randf() < risk) {
			kills.append((int32_t)i);
			causes.append(3);                     // lost while foraging
		}
	}
	out.append(food_eaten);
	out.append(food_in);
	out.append(q_reserve);
	out.append(toilets_due);
	out.append(fat_room);
	out.append(c_sum);
	out.append(f_sum);
	out.append(shorts);
	out.append((int64_t)p.st);
	out.append(kills);
	out.append(causes);
	return out;
}

// sim_colony._colony's loop over the workers: each one's age and task (TASK_*), the list of those out (appended to
// `outside`, cleared by the caller), and the reserve still inside in _by_forage's order (eagerest foragers last).
// k: aged, callow_days, forager_age. Back: [out_count, callow, nurses, idle].
Array ForagerStep::tasks(const Array &workers, const Array &by_forage, Array outside, const PackedFloat64Array &k) {
	Array out;
	if (k.size() < 3) {
		return out;
	}
	const Names &nm = names();
	const double aged = k[0], callow_d = k[1], forager_age = k[2];
	int64_t out_count = 0, callow = 0, nurses = 0;
	bool ok = false;
	for (int64_t i = 0; i < workers.size(); i++) {
		Variant a = workers[i];
		a.set_named(nm.was_dig, (int64_t)a.get_named(nm.task, ok) == TASK_DIG, ok);
		const double age = (double)a.get_named(nm.age, ok) + aged;
		a.set_named(nm.age, age, ok);
		const int64_t st = a.get_named(nm.state, ok);
		if (st != IN_NEST) {
			out_count += 1;
			outside.append(a);
			a.set_named(nm.task, st == DUMP ? TASK_DIG : TASK_OUT, ok);       // (a digger out with its pellet)
			continue;
		}
		if (age < callow_d) {
			callow += 1;
			a.set_named(nm.task, TASK_CALLOW, ok);
		} else if (age < forager_age * (0.5 + 0.5 * (double)a.get_named(nm.sort_c, ok))) {
			nurses += 1;
			a.set_named(nm.task, TASK_NURSE, ok);
		} else {
			a.set_named(nm.task, TASK_RESERVE, ok);
		}
	}
	Array idle;
	for (int64_t i = 0; i < by_forage.size(); i++) {
		const Variant &a = by_forage[i];
		if ((int64_t)a.get_named(nm.task, ok) == TASK_RESERVE) {
			idle.append(a);
		}
	}
	out.append(out_count);
	out.append(callow);
	out.append(nurses);
	out.append(idle);
	return out;
}

// sim_duties._duties' first two loops: every living worker's partner cleared, its duty D_OUT or (inside) -1, the diggers
// D_DIG with their half hour counted; the workers inside back, in order.
Array ForagerStep::duty_start(const Array &workers, double duty_h) {
	const Names &nm = names();
	Array inside;
	bool ok = false;
	for (int64_t i = 0; i < workers.size(); i++) {
		Variant a = workers[i];
		if ((bool)a.get_named(nm.dead, ok)) {
			continue;
		}
		a.set_named(nm.partner, (int64_t)0, ok);
		if ((int64_t)a.get_named(nm.state, ok) == IN_NEST) {
			inside.append(a);
			a.set_named(nm.duty, (int64_t)-1, ok);
		} else {
			a.set_named(nm.duty, D_OUT, ok);
		}
	}
	for (int64_t i = 0; i < inside.size(); i++) {
		Variant a = inside[i];
		if ((int64_t)a.get_named(nm.task, ok) == TASK_DIG) {
			a.set_named(nm.duty, D_DIG, ok);
			a.set_named(nm.dig_h, (double)a.get_named(nm.dig_h, ok) + duty_h, ok);
		}
	}
	return inside;
}
