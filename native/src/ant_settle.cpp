// AntNative.settle_find: nest_rest._settle_on's search for a free spot to rest in C++ (v0.12.28) - the very steps and
// sums of the GDScript (its float is a double, the engine's vectors floats), and the engine's own sort for the candidates
// (Array.sort_custom is SortArray: ties come out in the same order).
#include "ant_native.h"
#include <godot_cpp/templates/hash_map.hpp>
#include <godot_cpp/templates/local_vector.hpp>
#include <godot_cpp/templates/sort_array.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/vector3i.hpp>
#include <cmath>
#include <cstring>

using namespace godot;

namespace {

const Vector3i DIRS[6] = { Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1) };
const double ROOM_FREE = 1.7;

struct Nest {
	const uint8_t *rho = nullptr;
	int64_t n = 0;
	int64_t xl = 0, yl = 0, zl = 0, nx = 0, ny = 0, nz = 0, air = 128;
	bool inside(const Vector3i &c) const {
		return c.x >= xl && c.y >= yl && c.z >= zl && c.x < nx && c.y < ny && c.z < nz;
	}
	// rho at c (inside the box); past the array's end: soil (never read past it)
	int64_t at(const Vector3i &c) const {
		const int64_t i = ((c.z - zl) * (ny - yl) + c.y - yl) * (nx - xl) + c.x - xl;
		return (i >= 0 && i < n) ? (int64_t)rho[i] : air;
	}
	bool is_open(const Vector3i &c) const { return inside(c) && at(c) < air; }
	// nest_scene._walkable
	bool walkable(const Vector3i &c) const {
		if (!is_open(c)) {
			return false;
		}
		for (int k = 0; k < 6; k++) {
			const Vector3i nb = c + DIRS[k];
			if (nb.y >= ny) {
				continue;
			}
			if (nb.x < xl || nb.y < yl || nb.z < zl || nb.x >= nx || nb.z >= nz) {
				return true;
			}
			if (at(nb) >= air) {
				return true;
			}
		}
		return false;
	}
	// nest_scene._holds
	bool holds(const Vector3i &c) const {
		if (inside(c)) {
			return !is_open(c);
		}
		return c.y < ny;
	}
	// nest_scene._up_at
	Vector3 up_at(const Vector3i &c) const {
		Vector3 u, first;
		for (int k = 0; k < 6; k++) {
			if (holds(c + DIRS[k])) {
				u -= Vector3(DIRS[k]);
				if (first == Vector3()) {
					first = -Vector3(DIRS[k]);
				}
			}
		}
		if ((double)u.length_squared() > 0.01) {
			return u.normalized();
		}
		return first != Vector3() ? first : Vector3(0, 1, 0);
	}
};

inline bool same_dict(const Dictionary &a, const Dictionary &b) {
	return std::memcmp(a._native_ptr(), b._native_ptr(), 8) == 0;
}

// the engine's MIN, MAX (GDScript minf, maxf)
inline double mind(double a, double b) {
	return a < b ? a : b;
}
inline double maxd(double a, double b) {
	return a > b ? a : b;
}

inline double clampd(double v, double lo, double hi) {
	return v < lo ? lo : (v > hi ? hi : v);
}

struct Cand {
	double s;
	Vector3i c;
};
struct CandLess {
	bool operator()(const Cand &a, const Cand &b) const { return a.s < b.s; }
};

struct V3iHash {
	static uint32_t hash(const Vector3i &v) {
		uint32_t h = hash_murmur3_one_32((uint32_t)v.x);
		h = hash_murmur3_one_32((uint32_t)v.y, h);
		return hash_fmix32(hash_murmur3_one_32((uint32_t)v.z, h));
	}
};

} // namespace

// ctx: [rho, box (x_lo, y_lo, z_lo, nx, ny, nz, AIR), queen cells, queen drawn, queen head, queen tail, QUEEN_R,
//       _fit_cache, brood wide, _mate_cells, _near_bins, the view (its _cell_fits for a cell not in the cache)]
// Returns [found, best cell, path] - found false: no room anywhere near; path empty: it stays where it is.
Array AntNative::settle_find(const Dictionary &m, const Vector3i &start, const Vector3 &near_to, const Array &ctx) {
	Array r;
	r.append(false);
	r.append(start);
	r.append(Array());
	if (ctx.size() < 12) {
		return r;
	}
	const PackedByteArray rho = ctx[0];
	const PackedInt32Array box = ctx[1];
	if (box.size() < 7) {
		return r;
	}
	Nest nest;
	nest.rho = rho.ptr();
	nest.n = rho.size();
	nest.xl = box[0];
	nest.yl = box[1];
	nest.zl = box[2];
	nest.nx = box[3];
	nest.ny = box[4];
	nest.nz = box[5];
	nest.air = box[6];
	const Dictionary queen_cells = ctx[2];
	const bool queen_drawn = ctx[3];
	const Vector3 qa = ctx[4];
	const Vector3 qb = ctx[5];
	const double queen_r = ctx[6];
	Dictionary fit_cache = ctx[7];
	const Dictionary brood_wide = ctx[8];
	const Dictionary mate_cells = ctx[9];
	const Dictionary near_bins = ctx[10];
	Variant view = ctx[11];      // (called through the Variant: a GDScript object, no C++ binding of its own)
	const StringName K_D0("d0"), K_D1("d1"), K_FITS("_cell_fits");
	const Vector3 INF3(INFINITY, INFINITY, INFINITY);
	const bool has_near = !(near_to == INF3);

	// nest_rest._cell_ok
	auto cell_ok = [&](const Vector3i &c) -> bool {
		if (!nest.walkable(c) || queen_cells.has(c)) {
			return false;
		}
		if (queen_drawn) {
			// nest_brood._queen_gap
			const Vector3 p(c);
			const double t = clampd((double)(p - qa).dot(qb - qa) / maxd((double)(qb - qa).length_squared(), 0.001), 0.0, 1.0);
			if ((double)p.distance_to(qa.lerp(qb, (real_t)t)) - queen_r < 1.35) {
				return false;
			}
		}
		const Variant v = fit_cache.get(c, Variant());
		if (v.get_type() == Variant::BOOL) {
			return (bool)v;
		}
		if (view.get_type() != Variant::OBJECT) {
			return false;
		}
		return (bool)view.call(K_FITS, c);       // (works it out and keeps it in _fit_cache)
	};
	// the score lambda of _settle_on
	auto score = [&](const Vector3i &c, int64_t depth) -> double {
		const Vector3 u = nest.up_at(c);
		const double where = (double)u.y > 0.85 ? 0.0 : ((double)u.y > -0.3 ? 2.5 : 5.0);
		return (double)depth * 0.6 + where + (has_near ? (double)Vector3(c).distance_to(near_to) : 0.0);
	};
	// nest_rest._cell_room
	auto cell_room = [&](const Vector3i &c) -> double {
		double room = ROOM_FREE * ROOM_FREE;
		for (int dx = -1; dx <= 1; dx++) {
			for (int dy = -1; dy <= 1; dy++) {
				for (int dz = -1; dz <= 1; dz++) {
					const Variant o = mate_cells.get(c + Vector3i(dx, dy, dz), Variant());
					if (o.get_type() != Variant::NIL && !(o.get_type() == Variant::DICTIONARY && same_dict((Dictionary)o, m))) {
						room = mind(room, (double)(dx * dx + dy * dy + dz * dz));
					}
				}
			}
		}
		if (room == 0.0) {
			return 0.0;
		}
		const Vector3 p = Vector3(c) + Vector3(0, (real_t)-0.4, 0);
		const int64_t bx0 = (int64_t)std::floor(((double)p.x - 2.0) / 3.0), bx1 = (int64_t)std::floor(((double)p.x + 2.0) / 3.0);
		const int64_t by0 = (int64_t)std::floor(((double)p.y - 2.0) / 3.0), by1 = (int64_t)std::floor(((double)p.y + 2.0) / 3.0);
		const int64_t bz0 = (int64_t)std::floor(((double)p.z - 2.0) / 3.0), bz1 = (int64_t)std::floor(((double)p.z + 2.0) / 3.0);
		for (int64_t bx = bx0; bx <= bx1; bx++) {
			for (int64_t by = by0; by <= by1; by++) {
				for (int64_t bz = bz0; bz <= bz1; bz++) {
					const Variant bv = near_bins.get(Vector3i((int32_t)bx, (int32_t)by, (int32_t)bz), Variant());
					if (bv.get_type() != Variant::ARRAY) {
						continue;
					}
					const Array bin = bv;
					for (int64_t i = 0; i < bin.size(); i++) {
						const Dictionary o = bin[i];
						if (!same_dict(o, m) && o.has(K_D0)) {
							const Vector3 d0 = o[K_D0];
							const Vector3 d1 = o[K_D1];
							room = mind(room, mind((double)d0.distance_squared_to(p), (double)d1.distance_squared_to(p)));
						}
					}
				}
			}
		}
		return std::sqrt(room);
	};

	HashMap<Vector3i, Vector3i, V3iHash> parent;
	parent.insert(start, start);
	LocalVector<Cand> cands;
	if (cell_ok(start) && !brood_wide.has(start)) {
		cands.push_back(Cand{ score(start, 0) - 0.3, start });
	}
	LocalVector<Vector3i> frontier;
	frontier.push_back(start);
	bool floor_seen = false;
	for (int64_t depth = 1; depth < 11; depth++) {
		if (depth > 7 && floor_seen) {
			break;
		}
		LocalVector<Vector3i> next;
		for (uint32_t fi = 0; fi < frontier.size(); fi++) {
			const Vector3i c = frontier[fi];
			for (int k = 0; k < 6; k++) {
				const Vector3i n = c + DIRS[k];
				if (parent.has(n) || !nest.walkable(n) || queen_cells.has(n)) {
					continue;
				}
				parent.insert(n, c);
				next.push_back(n);
				if (cell_ok(n) && !brood_wide.has(n)) {
					const double sc = score(n, depth);
					cands.push_back(Cand{ sc, n });
					floor_seen = floor_seen || sc - (double)depth * 0.6 < 2.0;
				}
			}
		}
		frontier = next;
	}
	if (cands.size() > 1) {
		SortArray<Cand, CandLess> sorter;
		sorter.sort(cands.ptr(), cands.size());
	}
	Vector3i best(-9999, 0, 0);
	Vector3i roomy = start;
	double roomy_r = -1.0;
	const int64_t lim = cands.size() < 60 ? (int64_t)cands.size() : 60;
	for (int64_t k = 0; k < lim; k++) {
		const Vector3i c = cands[k].c;
		const double room = cell_room(c);
		if (room >= ROOM_FREE) {
			best = c;
			break;
		}
		if (room - (double)k * 0.01 > roomy_r + (c != start ? 0.3 : 0.0)) {
			roomy_r = room - (double)k * 0.01;
			roomy = c;
		}
	}
	if (best.x == -9999) {
		if (roomy_r < 0.5) {
			return r;                                // no room anywhere near
		}
		best = roomy;
	}
	r[0] = true;
	r[1] = best;
	if (best == start) {
		return r;
	}
	Array path;
	Vector3i c = best;
	while (c != start) {
		path.push_front(c);
		c = parent[c];
	}
	r[2] = path;
	return r;
}
