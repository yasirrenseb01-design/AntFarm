// The foragers' constants (as sim_foragers.gd / sim_state.gd / ant.gd have them) and the names ForagerStep reads.
#pragma once
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <cstdint>

namespace forager_k {
using godot::StringName;

// cos, sin, exp, pow: the engine's own, called through it (its build computes some of them on the x87 unit: the
// compiler's here differ in the last bit for ~1% of numbers - tests/native_sim_test.gd math check)
struct Crt {
	double (*cos)(double);
	double (*sin)(double);
	double (*exp)(double);
	double (*pow)(double, double);
	double (*atan2)(double, double);
	// Vector2.angle() as the engine gives it: its atan2 on doubles, made a float (the compiler's atan2f here differs in
	// the last bit for ~0.1% of directions, nearly along an axis most: v0.14.1, an ant heading home straight east)
	godot::real_t angle(const godot::Vector2 &v) const {
		return (godot::real_t)atan2((double)v.y, (double)v.x);
	}
};
const Crt &crt();

// the named constants as the GDScript has them (simulation.gd _fwd_consts sends its own: begin() refuses a mismatch,
// and the GDScript walks the ants itself)
static const double K[] = {
	4,                 // SENSE_EVERY
	1.0 / 5.0,         // INV_CELL
	5.0,               // CELL
	9.0,               // NEST_R
	15,                // ACT_SCAN
	22,                // ACT_AWAY
	20,                // ACT_WALL
	240,               // WALL_TICKS
	0.12,              // WALL_CLIMB_P
	0.45,              // BEYOND_P
	90, 220,           // BEYOND_TICKS
	6.0,               // Field.MAX
	0, 1, 2, 3, 4, 5, 6, 7,   // Ant.IN_NEST SEARCH RETURN HOME UNDERTAKER DEFEND DRAG DUMP
	0, 1, 2,           // Ant.NONE SUGAR PROTEIN
	0, 1, 2, 3, 4,     // Ant.TASK_OUT CALLOW NURSE RESERVE DIG
	0, 8,              // Ant.D_OUT D_DIG
};
static const int NK = sizeof(K) / sizeof(K[0]);
enum { IN_NEST = 0, SEARCH = 1, RETURN = 2, HOME = 3, UNDERTAKER = 4, DEFEND = 5, DRAG = 6, DUMP = 7 };
enum { NONE = 0, SUGAR = 1, PROTEIN = 2 };
static const int64_t TASK_OUT = 0, TASK_CALLOW = 1, TASK_NURSE = 2, TASK_RESERVE = 3, TASK_DIG = 4, D_OUT = 0, D_DIG = 8;
static const int64_t SENSE_EVERY = 4, ACT_SCAN = 15, ACT_AWAY = 22, ACT_WALL = 20, WALL_TICKS = 240;
static const double INV_CELL = 1.0 / 5.0, CELL = 5.0, NEST_R = 9.0, WALL_CLIMB_P = 0.12, BEYOND_P = 0.45, FIELD_MAX = 6.0;
static const int64_t BEYOND_LO = 90, BEYOND_HI = 220;
static const double PI_D = 3.1415926535897932384626433833;

struct Names {
	StringName meet_cd, busy, act, turn_after, ang, trip, state, carry, hurt, phase, pos, id, patience, follow, since,
			slide, dead, val, stamp, clock, type, amt, rotten, r, crop, body_fat, energy, hardiness, age, life, was_dig, task, sort_c, partner, duty, dig_h;
	StringName s_spd, s_noise_k, s_substep, s_wild, s_want_sugar, s_want_protein, s_world, s_gw, s_rock, s_food_cell,
			s_nest_pos, s_foods, s_creatures, s_home, s_food, s_alarm, s_rng;
	Names() :
			meet_cd("meet_cd"), busy("busy"), act("act"), turn_after("turn_after"), ang("ang"), trip("trip"), state("state"),
			carry("carry"), hurt("hurt"), phase("phase"), pos("pos"), id("id"), patience("patience"), follow("follow"),
			since("since"), slide("slide"), dead("dead"), val("val"), stamp("stamp"), clock("clock"), type("type"),
			amt("amt"), rotten("rotten"), r("r"), crop("crop"), body_fat("body_fat"), energy("energy"),
			hardiness("hardiness"), age("age"), life("life"), was_dig("was_dig"), task("task"), sort_c("sort_c"),
			partner("partner"), duty("duty"), dig_h("dig_h"), s_spd("_spd"), s_noise_k("_noise_k"), s_substep("ant_substep"),
			s_wild("_wild"), s_want_sugar("_want_sugar"), s_want_protein("_want_protein"), s_world("WORLD"), s_gw("gw"),
			s_rock("rock"), s_food_cell("food_cell"), s_nest_pos("nest_pos"), s_foods("foods"), s_creatures("creatures"),
			s_home("home"), s_food("food"), s_alarm("alarm"), s_rng("rng") {}
};
const Names &names();


} // namespace forager_k
