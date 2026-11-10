#include "ant_native.h"
#include <godot_cpp/core/class_db.hpp>
#include <cmath>
#include <vector>
#include <godot_cpp/variant/vector3i.hpp>

using namespace godot;

void AntNative::_bind_methods() {
	ClassDB::bind_static_method("AntNative", D_METHOD("density_at", "soft", "dims", "p"), &AntNative::density_at);
	ClassDB::bind_static_method("AntNative", D_METHOD("soft_build", "rho", "box"), &AntNative::soft_build);
	ClassDB::bind_static_method("AntNative", D_METHOD("chunk_sample", "rho", "box", "k", "ch"), &AntNative::chunk_sample);
	ClassDB::bind_static_method("AntNative", D_METHOD("field_from", "rho", "box", "starts"), &AntNative::field_from);
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
