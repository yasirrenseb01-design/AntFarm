#include "ant_native.h"
#include <godot_cpp/core/class_db.hpp>
#include <cmath>
#include <cstring>
#include <godot_cpp/variant/string_name.hpp>
#include <vector>
#include <godot_cpp/variant/vector3i.hpp>

using namespace godot;

void AntNative::_bind_methods() {
	ClassDB::bind_static_method("AntNative", D_METHOD("density_at", "soft", "dims", "p"), &AntNative::density_at);
	ClassDB::bind_static_method("AntNative", D_METHOD("soft_build", "rho", "box"), &AntNative::soft_build);
	ClassDB::bind_static_method("AntNative", D_METHOD("chunk_sample", "rho", "box", "k", "ch"), &AntNative::chunk_sample);
	ClassDB::bind_static_method("AntNative", D_METHOD("field_from", "rho", "box", "starts"), &AntNative::field_from);
	ClassDB::bind_static_method("AntNative", D_METHOD("bend_probe", "soft", "dims", "tr", "off", "b", "lowered", "sb", "head_pts", "gaster_pts"), &AntNative::bend_probe);
	ClassDB::bind_static_method("AntNative", D_METHOD("gap_scan", "m", "near", "head", "up", "f", "s", "lag", "on", "offs", "parts", "radii"), &AntNative::gap_scan);
	ClassDB::bind_static_method("AntNative", D_METHOD("settle_find", "m", "start", "near_to", "ctx"), &AntNative::settle_find);
	ClassDB::bind_static_method("AntNative", D_METHOD("body_feels", "soft", "dims", "t", "off", "bend", "lat", "soil_pts", "feel_pts"), &AntNative::body_feels);
	ClassDB::bind_static_method("AntNative", D_METHOD("gap_under", "rho", "box", "xf"), &AntNative::gap_under);
	ClassDB::bind_static_method("AntNative", D_METHOD("soil_hits", "soft", "dims", "t2", "pts", "up", "side"), &AntNative::soil_hits);
}

// dims: [sx, sy, sy0, nx, ny, nz, y_lo] - nest_scene._soft's layout (a ring of one voxel round the block)
static inline double lerpd(double a, double b, double t) {
	return a + (b - a) * t;              // (Math::lerp, as GDScript's lerpf)
}

// n: how many values s holds. Every read is checked against it (v0.12.9): GDScript stops at a bad index with an
// error, C++ would read past the array and could crash the game - a sample outside the array counts as air.
static inline double dens(const float *s, int64_t n, const int32_t *dm, const Vector3 &p) {
	const int64_t x = (int64_t)std::floor((double)p.x);
	const int64_t y = (int64_t)std::floor((double)p.y);
	const int64_t z = (int64_t)std::floor((double)p.z);
	const int64_t sx = dm[0], sy = dm[1], sy0 = dm[2], nx = dm[3], ny = dm[4], nz = dm[5], ylo = dm[6];
	if (x < -1 || y < ylo - 1 || z < -1 || x >= nx || y >= ny || z >= nz) {
		return 0.0;
	}
	const double fx = (double)p.x - (double)x;
	const double fy = (double)p.y - (double)y;
	const double fz = (double)p.z - (double)z;
	const int64_t i = ((z + 1) * sy + (y - sy0 + 1)) * sx + (x + 1);
	if (i < 0 || i + sx * sy + sx + 1 >= n) {
		return 0.0;
	}
	const double d00 = lerpd(s[i], s[i + 1], fx);
	const double d10 = lerpd(s[i + sx], s[i + sx + 1], fx);
	const int64_t j = i + sx * sy;
	const double d01 = lerpd(s[j], s[j + 1], fx);
	const double d11 = lerpd(s[j + sx], s[j + sx + 1], fx);
	return lerpd(lerpd(d00, d10, fy), lerpd(d01, d11, fy), fz);
}

// dims: sx, sy, sy0, nx, ny, nz, y_lo (nest_scene.gd _soft_dims); fewer than 7, or a row size under 1: nothing is read
static inline bool dims_ok(const PackedInt32Array &dims) {
	return dims.size() >= 7 && dims[0] > 0 && dims[1] > 0;
}

double AntNative::density_at(const PackedFloat32Array &soft, const PackedInt32Array &dims, const Vector3 &p) {
	if (!dims_ok(dims)) {
		return 0.0;
	}
	return dens(soft.ptr(), soft.size(), dims.ptr(), p);
}

static inline double signd(double v) {
	return v > 0.0 ? 1.0 : (v < 0.0 ? -1.0 : 0.0);
}

// nest_soil._bent for lat = 0 (the neck and the waist of the body turned as drawn): NECK, WAIST, GASTER_CURL of nest_rest.gd.
static inline Vector3 bent0(const Vector3 &q, const Vector2 &bend) {
	static const Vector2 NECK((real_t)0.46, (real_t)0.39), WAIST((real_t)-0.31, (real_t)0.36);
	if (q.x > NECK.x) {
		const Vector2 h = (Vector2(q.x, q.y) - NECK).rotated(bend.y) + NECK;
		return Vector3(h.x, h.y, q.z);
	}
	if (q.x < WAIST.x) {
		const Vector2 g = (Vector2(q.x, q.y) - WAIST).rotated((real_t)(0.1 - (double)bend.x)) + WAIST;
		return Vector3(g.x, g.y, q.z);
	}
	return q;
}

static inline bool any_in(const float *s, int64_t n, const int32_t *dm, const Transform3D &tr, const Vector3 &off, const PackedVector3Array &pts, const Vector2 &bend) {
	for (int64_t k = 0; k < pts.size(); k++) {
		Vector3 c = tr.xform(bent0(pts[k], bend));
		c.x -= off.x;
		c.z -= off.z;
		if (dens(s, n, dm, c) >= 0.5) {
			return true;
		}
	}
	return false;
}

// nest_soil._soil_bend's four probes of the head's and the gaster's points against the soil: bit 1 head in, 2 gaster in,
// 4 head in when lowered (only asked if it is not in and sb.y > 0), 8 gaster in when lowered (not in and sb.x > 0).
// off: the column and slice the array starts at (nest_scene._soft_off), taken off after the transform as _density_at does.
int64_t AntNative::bend_probe(const PackedFloat32Array &soft, const PackedInt32Array &dims, const Transform3D &tr, const Vector3 &off,
		const Vector2 &b, const Vector2 &lowered, const Vector2 &sb, const PackedVector3Array &head_pts, const PackedVector3Array &gaster_pts) {
	if (!dims_ok(dims)) {
		return 0;
	}
	const float *s = soft.ptr();
	const int64_t n = soft.size();
	const int32_t *dm = dims.ptr();
	int64_t r = 0;
	const bool head_in = any_in(s, n, dm, tr, off, head_pts, b);
	const bool gaster_in = any_in(s, n, dm, tr, off, gaster_pts, b);
	if (head_in) r |= 1;
	if (gaster_in) r |= 2;
	if (!head_in && sb.y > 0.0f && any_in(s, n, dm, tr, off, head_pts, Vector2(b.x, lowered.y))) r |= 4;
	if (!gaster_in && sb.x > 0.0f && any_in(s, n, dm, tr, off, gaster_pts, Vector2(lowered.x, b.y))) r |= 8;
	return r;
}

// Whether two Dictionary values are the one dictionary (GDScript is_same): the handle holds the pointer to it.
static inline bool same_dict(const Dictionary &a, const Dictionary &b) {
	return std::memcmp(a._native_ptr(), b._native_ptr(), 8) == 0;
}
static inline bool same_var(const Variant &v, const Dictionary &d) {
	return v.get_type() == Variant::DICTIONARY && same_dict((Dictionary)v, d);
}
// float(v) of GDScript for an int or a float value (the default if there is none)
static inline double tod(const Variant &v) {
	if (v.get_type() == Variant::INT) {
		return (double)(int64_t)v;
	}
	if (v.get_type() == Variant::FLOAT) {
		return (double)v;
	}
	return 0.0;
}

// nest_contact._gap_ahead's pass over the bodies near its head (the nestmates' bins by the cells round it): how far it may
// walk on before its head touches one (1: free) and which one stops it. parts/radii: CLIMB_PARTS (x, y, z = radius in model
// units); the rest of the function stays in GDScript (it draws random numbers). Returns [k, by] (by null if none).
Array AntNative::gap_scan(const Dictionary &m, const Dictionary &near, const Vector3 &head, const Vector3 &up, const Vector3 &f,
		double s, double lag, const Variant &on, const Array &offs, const PackedVector3Array &parts, const PackedFloat64Array &radii) {
	const StringName K_XF("xf"), K_OVER_ON("over_on"), K_OVER("over");
	const double hr = (double)radii[0] * s;
	const Vector3i key((int32_t)std::floor((double)head.x / 3.0), (int32_t)std::floor((double)head.y / 3.0), (int32_t)std::floor((double)head.z / 3.0));
	double k = 1.0;
	Variant by;
	for (int64_t oi = 0; oi < offs.size(); oi++) {
		const Vector3i kk = key + (Vector3i)offs[oi];
		const Variant bv = near.get(kk, Variant());
		if (bv.get_type() != Variant::ARRAY) {
			continue;
		}
		const Array bin = bv;
		for (int64_t bi = 0; bi < bin.size(); bi++) {
			const Dictionary o = bin[bi];
			if (same_dict(o, m) || !o.has(K_XF) || (on.get_type() == Variant::DICTIONARY && same_dict(o, (Dictionary)on)) ||
					same_var(o.get(K_OVER_ON, Variant()), m) || tod(o.get(K_OVER, 0.0)) > 0.1) {
				continue;
			}
			const Transform3D ox = o[K_XF];
			if (ox.origin.distance_squared_to(head) > 9.0 || (double)ox.basis.get_column(1).normalized().dot(up) < 0.5) {
				continue;
			}
			const double os = (double)ox.basis.get_column(0).length();
			for (int64_t qi = 0; qi < parts.size(); qi++) {
				const Vector3 q = parts[qi];
				Vector3 to = ox.xform(Vector3(q.x, q.y, 0.0f)) - head;
				to -= up * to.dot(up);
				const double ahead = (double)to.dot(f);
				if (ahead < 0.0) {
					continue;
				}
				const double reach = hr + radii[qi] * os + 0.06;
				const double lat = (double)(to - f * (real_t)ahead).length();
				if (lat >= reach) {
					continue;
				}
				const double gap = ahead - std::sqrt(reach * reach - lat * lat) - lag;
				double c = gap / (0.7 * s);
				c = c < 0.0 ? 0.0 : (c > 1.0 ? 1.0 : c);
				if (c < k) {
					k = c;
					by = o;
				}
			}
		}
	}
	Array r;
	r.append(k);
	r.append(by);
	return r;
}

// nest_soil._soil_push's pass over the body's points (bent as drawn): for each in the soil, out along the soil's slope
// and how far. Returns [push, torque, hits].
Array AntNative::soil_hits(const PackedFloat32Array &soft, const PackedInt32Array &dims, const Transform3D &t2,
		const PackedVector3Array &pts, const Vector3 &up, const Vector3 &side) {
	Array r;
	if (!dims_ok(dims)) {
		r.append(Vector3());
		r.append(0.0);
		r.append((int64_t)0);
		return r;
	}
	const float *s = soft.ptr();
	const int64_t n = soft.size();
	const int32_t *dm = dims.ptr();
	Vector3 push;
	double torque = 0.0;
	int64_t hits = 0;
	const Vector3 ex((real_t)0.2, 0, 0), ey(0, (real_t)0.2, 0), ez(0, 0, (real_t)0.2);
	for (int64_t k = 0; k < pts.size(); k++) {
		const Vector3 q = pts[k];
		const Vector3 c = t2.xform(q);
		if (dens(s, n, dm, c) < 0.45) {
			continue;
		}
		Vector3 g((real_t)(dens(s, n, dm, c + ex) - dens(s, n, dm, c - ex)),
				(real_t)(dens(s, n, dm, c + ey) - dens(s, n, dm, c - ey)),
				(real_t)(dens(s, n, dm, c + ez) - dens(s, n, dm, c - ez)));
		Vector3 gp = g - up * g.dot(up);
		if ((double)gp.length_squared() < 0.25 * (double)g.length_squared()) {
			gp = gp + up * g.dot(up) * (real_t)0.5;
		}
		g = gp;
		if ((double)g.length_squared() < 0.000001) {
			continue;
		}
		const Vector3 out = -g.normalized();
		double d = 0.1;
		while (d < 0.7 && dens(s, n, dm, c + out * (real_t)d) >= 0.5) {
			d += 0.1;
		}
		push += out * (real_t)d;
		torque += (double)out.dot(side) * d * signd((double)q.x);
		hits += 1;
	}
	r.append(push);
	r.append(torque);
	r.append(hits);
	return r;
}

// nest_scene._soft_build over the whole block (v0.12.23): the soil's density at every voxel and a ring of one round it,
// as nest_voxels.density sums it (a double, stored as a float). box: x_lo, y_lo, z_lo, nx, ny, nz, AIR. ~1.2 s in GDScript
// for a tank full of soil, the first time the nest was laid out. An empty array back: the box does not fit rho.
PackedFloat32Array AntNative::soft_build(const PackedByteArray &rho, const PackedInt32Array &box) {
	PackedFloat32Array out;
	if (box.size() < 7) {
		return out;
	}
	const int64_t xl = box[0], yl = box[1], zl = box[2], nx = box[3], ny = box[4], nz = box[5], air = box[6];
	const int64_t wx = nx - xl, hy = ny - yl, wz = nz - zl;
	if (wx <= 0 || hy <= 0 || wz <= 0 || rho.size() < wx * hy * wz) {
		return out;
	}
	const int64_t sx = wx + 2, sy = hy + 2, sz = wz + 2;
	out.resize(sx * sy * sz);
	float *o = out.ptrw();
	const uint8_t *r = rho.ptr();
	auto solid = [&](int64_t x, int64_t y, int64_t z) -> double {
		if (x < xl || y < yl || z < zl || x >= nx || y >= ny || z >= nz) {
			return 0.0;
		}
		return r[((z - zl) * hy + y - yl) * wx + x - xl] >= air ? 1.0 : 0.0;
	};
	for (int64_t z = zl - 1; z <= nz; z++) {
		for (int64_t y = yl - 1; y <= ny; y++) {
			const int64_t row = ((z - zl + 1) * sy + (y - yl + 1)) * sx + 1 - xl;
			for (int64_t x = xl - 1; x <= nx; x++) {
				const double n = solid(x - 1, y, z) + solid(x + 1, y, z) + solid(x, y - 1, z) + solid(x, y + 1, z) +
						solid(x, y, z - 1) + solid(x, y, z + 1);
				o[row + x] = (float)(solid(x, y, z) > 0.5 ? 0.4 + 0.1 * n : 0.05 * n);
			}
		}
	}
	return out;
}

// nest_mesher.sample (v0.12.24): chunk k's soil for the mesher, samples o-1 .. o+ch+1 (o = k*ch), each solid or open
// softened with its six neighbours, solid read one voxel further out; outside the box counts as air. The same values in
// the same order (a double, stored as a float). ~1.3 ms a chunk in GDScript on the main thread: a big nest's 441 chunks
// came up over 6 s as the nest view opened. An empty array back: no surface in it, or the box does not fit rho.
PackedFloat32Array AntNative::chunk_sample(const PackedByteArray &rho, const PackedInt32Array &box, const Vector3i &k, int64_t ch) {
	PackedFloat32Array dens;
	if (box.size() < 7 || ch < 1 || ch > 64) {
		return dens;
	}
	const int64_t xl = box[0], yl = box[1], zl = box[2], nx = box[3], ny = box[4], nz = box[5], air = box[6];
	const int64_t wx = nx - xl, hy = ny - yl, wz = nz - zl;
	if (wx <= 0 || hy <= 0 || wz <= 0 || rho.size() < wx * hy * wz) {
		return dens;
	}
	const int64_t S = ch + 3, B = S + 2, B2 = B * B;
	const int64_t ox = (int64_t)k.x * ch, oy = (int64_t)k.y * ch, oz = (int64_t)k.z * ch;
	std::vector<float> solid(B * B * B, 0.0f);
	const uint8_t *r = rho.ptr();
	for (int64_t z = 0; z < B; z++) {
		const int64_t vz = oz + z - 2;
		for (int64_t y = 0; y < B; y++) {
			const int64_t vy = oy + y - 2;
			if (vz < zl || vy < yl || vz >= nz || vy >= ny) {
				continue;
			}
			const int64_t row = (z * B + y) * B;
			const int64_t base = ((vz - zl) * hy + vy - yl) * wx - xl;
			for (int64_t x = 0; x < B; x++) {
				const int64_t vx = ox + x - 2;
				if (vx >= xl && vx < nx && r[base + vx] >= air) {
					solid[row + x] = 1.0f;
				}
			}
		}
	}
	dens.resize(S * S * S);
	float *d = dens.ptrw();
	bool any_air = false, any_solid = false;
	for (int64_t z = 0; z < S; z++) {
		for (int64_t y = 0; y < S; y++) {
			for (int64_t x = 0; x < S; x++) {
				const int64_t i = ((z + 1) * B + (y + 1)) * B + (x + 1);
				const double nb = (double)solid[i - 1] + solid[i + 1] + solid[i - B] + solid[i + B] + solid[i - B2] + solid[i + B2];
				const double v = solid[i] > 0.5f ? 0.4 + 0.1 * nb : 0.05 * nb;
				d[(z * S + y) * S + x] = (float)v;
				if (v >= 0.5) {
					any_solid = true;
				} else {
					any_air = true;
				}
			}
		}
	}
	if (!(any_air && any_solid)) {
		return PackedFloat32Array();
	}
	return dens;
}

// nest_brood._field_from (v0.12.23): steps from the start cells through the open nest, a step on a wall 1, one across
// open air 12 - the same buckets taken in the same order, so the dictionary comes back with the same keys in the same
// order and the same values. ~0.3 s a field in GDScript in a nest of 800; the first opening worked out 24 of them.
// box: x_lo, y_lo, z_lo, nx, ny, nz, AIR. An empty dictionary back: the box does not fit rho, or a start is outside it.
Dictionary AntNative::field_from(const PackedByteArray &rho, const PackedInt32Array &box, const Array &starts) {
	Dictionary f;
	if (box.size() < 7) {
		return f;
	}
	const int64_t xl = box[0], yl = box[1], zl = box[2], nx = box[3], ny = box[4], nz = box[5], air = box[6];
	const int64_t wx = nx - xl, hy = ny - yl, wz = nz - zl;
	if (wx <= 0 || hy <= 0 || wz <= 0 || rho.size() < wx * hy * wz) {
		return f;
	}
	const uint8_t *r = rho.ptr();
	auto inside = [&](int64_t x, int64_t y, int64_t z) {
		return x >= xl && y >= yl && z >= zl && x < nx && y < ny && z < nz;
	};
	auto at = [&](int64_t x, int64_t y, int64_t z) -> int64_t {
		return ((z - zl) * hy + y - yl) * wx + x - xl;
	};
	static const int DX[6] = { 1, -1, 0, 0, 0, 0 }, DY[6] = { 0, 0, 1, -1, 0, 0 }, DZ[6] = { 0, 0, 0, 0, 1, -1 };
	auto walkable = [&](int64_t x, int64_t y, int64_t z) {        // (nest_scene._walkable, of an open cell)
		for (int d = 0; d < 6; d++) {
			const int64_t ax = x + DX[d], ay = y + DY[d], az = z + DZ[d];
			if (ay >= ny) {
				continue;
			}
			if (!inside(ax, ay, az) || r[at(ax, ay, az)] >= air) {
				return true;
			}
		}
		return false;
	};
	const int64_t total = wx * hy * wz;
	std::vector<int64_t> dist(total, -1);
	std::vector<int64_t> order;                                      // (the cells in the order they were first reached)
	std::vector<std::vector<int64_t>> buckets(1);
	for (int64_t i = 0; i < starts.size(); i++) {
		if (starts[i].get_type() != Variant::VECTOR3I) {
			return Dictionary();
		}
		const Vector3i c = starts[i];
		if (!inside(c.x, c.y, c.z)) {
			return Dictionary();
		}
		const int64_t k = at(c.x, c.y, c.z);
		if (dist[k] < 0) {
			order.push_back(k);
		}
		dist[k] = 0;
		buckets[0].push_back(k);
	}
	int64_t left = (int64_t)buckets[0].size();
	for (int64_t cur = 0; left > 0; cur++) {
		if (cur >= (int64_t)buckets.size()) {
			break;
		}
		std::vector<int64_t> b;
		b.swap(buckets[cur]);
		for (const int64_t k : b) {
			left--;
			if (dist[k] != cur) {
				continue;
			}
			const int64_t x = k % wx + xl, y = (k / wx) % hy + yl, z = k / (wx * hy) + zl;
			for (int d = 0; d < 6; d++) {
				const int64_t ax = x + DX[d], ay = y + DY[d], az = z + DZ[d];
				if (!inside(ax, ay, az)) {
					continue;
				}
				const int64_t n = at(ax, ay, az);
				if (r[n] >= air) {
					continue;
				}
				const int64_t nd = cur + (walkable(ax, ay, az) ? 1 : 12);
				if (dist[n] < 0 || nd < dist[n]) {
					if (dist[n] < 0) {
						order.push_back(n);
					}
					dist[n] = nd;
					if (nd >= (int64_t)buckets.size()) {
						buckets.resize(nd + 1);
					}
					buckets[nd].push_back(n);
					left++;
				}
			}
		}
	}
	for (const int64_t k : order) {
		f[Vector3i((int32_t)(k % wx + xl), (int32_t)((k / wx) % hy + yl), (int32_t)(k / (wx * hy) + zl))] = dist[k];
	}
	return f;
}
