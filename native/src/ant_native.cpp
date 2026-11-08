#include "ant_native.h"
#include <godot_cpp/core/class_db.hpp>
#include <cmath>

using namespace godot;

void AntNative::_bind_methods() {
	ClassDB::bind_static_method("AntNative", D_METHOD("density_at", "soft", "dims", "p"), &AntNative::density_at);
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
