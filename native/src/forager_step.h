// ForagerStep (PART 0.14 step 0.5): the foragers' walk of one simulation tick (sim_foragers._step_ant and the loop over
// `outside` in simulation.step) in C++ - the very sums of the GDScript, in the same order, with the same draws of the
// colony's random generator (its PCG32 reproduced here: rng_probe). An ant whose tick takes a rare turn (at the nest,
// at food it picks up, an enemy near, defending, carrying soil or a corpse, back from beyond the plot) is handed back
// whole to the GDScript: run() stops before it with nothing of its tick done, and the caller steps it and runs on.
#pragma once
#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <vector>

namespace godot {

class ForagerStep : public RefCounted {
	GDCLASS(ForagerStep, RefCounted)

protected:
	static void _bind_methods();

public:
	struct Food {
		bool read = false;
		int64_t type = 0;
		double amt = 0.0;
		bool rotten = false;
		Vector2 pos;
		double r = 0.0;
	};
	struct Pcg {
		uint64_t st = 0;
		uint32_t next();
		uint32_t bounded(uint32_t bound);
		float randf();
		float randf_range(float from, float to);
		int64_t randi_range(int64_t from, int64_t to);
	};
	struct Dep {
		int field = -1;           // 0 home, 1 food; -1: none
		int64_t cell = 0;
		double amount = 0.0;
	};

	// the tick's values (begin)
	Object *sim = nullptr;
	Ref<RandomNumberGenerator> rng;
	Object *home = nullptr;
	Object *food = nullptr;
	Object *alarm = nullptr;
	Array foods;
	Array creatures;
	PackedByteArray rock;              // (taken in run(), let go at its end)
	PackedInt32Array food_cell;
	std::vector<Vector2> holes;
	Vector2 world;
	Vector2 nest_pos;
	int64_t gw = 0;
	int64_t n = 1;
	double spd0 = 0.0;
	double noise_k = 1.0;
	bool wild = false;
	bool want_sugar = true;
	bool want_protein = true;
	PackedFloat64Array k;          // the constants (simulation.gd _fwd_consts)
	int64_t steps = 0;

	// during run()
	PackedFloat32Array fval[2];
	PackedFloat64Array fstamp[2];
	double fclock[2] = { 0.0, 0.0 };
	PackedFloat32Array aval;
	PackedFloat64Array astamp;
	double aclock = 0.0;
	std::vector<Food> food_info;
	std::vector<Vector2> creature_pos;
	Pcg pcg;
	const uint8_t *rk = nullptr;          // rock, food_cell, the alarm's values: read only (ptr: never copied)
	const int32_t *fc = nullptr;
	int64_t ncell = 0;
	const float *av = nullptr;
	const double *as = nullptr;
	bool bad = false;                     // an index past an array: the ant is handed back (the GDScript stops on it as it would)

	// sim_surface._encounters (forager_meet.cpp): who stands in each 6 px square this round
	int64_t meet_w = 0;
	int64_t meet_round = 0;
	std::vector<int64_t> meet_at;
	std::vector<int64_t> meet_who;

	bool check(const PackedFloat64Array &p_consts);
	void begin(Object *p_sim, const Array &p_holes, const PackedFloat64Array &p_consts);
	void meet(Object *p_sim, const Array &list);
	Array tasks(const Array &workers, const Array &by_forage, Array outside, const PackedFloat64Array &k);
	Array duty_start(const Array &workers, double duty_h);
	Array metabolism(const Array &workers, const PackedFloat64Array &k, bool founding_w, bool dry, int64_t rng_state);
	int64_t run(const Array &list, int64_t from);
	int64_t get_steps() const { return steps; }
	static PackedFloat64Array rng_probe(int64_t state, const PackedInt32Array &kinds);
	static PackedFloat64Array math_probe(const PackedFloat64Array &in);

	// (forager_step.cpp)
	bool blocked(const Vector2 &p) const;
	const Food &food_at(int64_t fi);
	Vector2 home_at(const Vector2 &p) const;
	double read_field(int f, int64_t i) const;
	void deposit(const Dep &d);
	int walk(const Variant &ant);
};

} // namespace godot
