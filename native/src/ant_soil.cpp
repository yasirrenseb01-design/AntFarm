// AntNative: the rest of nest_soil._soil_push in C++ (v0.12.29) - the very sums of the GDScript (its float a double, the
// engine's vectors floats): the body's and the antennae's points against the soil (_body_touches, _feels) and how far the
// floor is under a body (nest_feet._gap_under, the feet's own map of the floor).
#include "ant_native.h"
#include <cmath>

using namespace godot;

namespace {

// nest_soil._density_at over nest_scene._soft (dims: sx, sy, sy0, nx, ny, nz, y_lo; p counted from the array's start)
inline double lerpd(double a, double b, double t) {
	return a + (b - a) * t;
}

double dens2(const float *s, int64_t n, const int32_t *dm, const Vector3 &p) {
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

// nest_soil._yaw_at: q turned about the vertical through x = px by the shader's rot_y(a)
Vector3 yaw_at(const Vector3 &q, double px, double a) {
	if (std::fabs(a) < 0.001) {
		return q;
	}
	const double dx = (double)q.x - px;
	return Vector3((real_t)(px + std::cos(a) * dx + std::sin(a) * (double)q.z), q.y, (real_t)(-std::sin(a) * dx + std::cos(a) * (double)q.z));
}

// nest_soil._bent (NECK, WAIST, GASTER_CURL of nest_rest.gd)
Vector3 bent(const Vector3 &q, const Vector2 &bend, double lat) {
	static const Vector2 NECK((real_t)0.46, (real_t)0.39), WAIST((real_t)-0.31, (real_t)0.36);
	if (q.x > NECK.x) {
		const Vector2 h = (Vector2(q.x, q.y) - NECK).rotated(bend.y) + NECK;
		return yaw_at(Vector3(h.x, h.y, q.z), (double)NECK.x, lat);
	}
	if (q.x < WAIST.x) {
		const Vector2 g = (Vector2(q.x, q.y) - WAIST).rotated((real_t)(0.1 - (double)bend.x)) + WAIST;
		return yaw_at(Vector3(g.x, g.y, q.z), (double)WAIST.x, -0.8 * lat);
	}
	return q;
}

bool touches(const float *s, int64_t n, const int32_t *dm, const Transform3D &t, const Vector3 &off, const PackedVector3Array &pts,
		const Vector2 &bend, double lat) {
	for (int64_t k = 0; k < pts.size(); k++) {
		Vector3 c = t.xform(bent(pts[k], bend, lat));
		c.x -= off.x;
		c.z -= off.z;
		if (dens2(s, n, dm, c) >= 0.45) {
			return true;
		}
	}
	return false;
}

} // namespace

// _body_touches(t, bend, lat) or _feels(t, bend, lat): any of the body's points (soil_pts) or the antennae's (feel_pts),
// bent as drawn, in the soil with the body at t. off: nest_scene._soft_off, taken off after the transform.
bool AntNative::body_feels(const PackedFloat32Array &soft, const PackedInt32Array &dims, const Transform3D &t, const Vector3 &off,
		const Vector2 &bend, double lat, const PackedVector3Array &soil_pts, const PackedVector3Array &feel_pts) {
	if (dims.size() < 7 || dims[0] <= 0 || dims[1] <= 0) {
		return false;
	}
	const float *s = soft.ptr();
	const int64_t n = soft.size();
	const int32_t *dm = dims.ptr();
	return touches(s, n, dm, t, off, soil_pts, bend, lat) || touches(s, n, dm, t, off, feel_pts, bend, lat);
}

// nest_feet._gap_under: how far below the body the floor is (along its up, up to 1.5), from the feet's map of the floor
// (rho, read as nest_feet._foot_at reads it). box: x_lo, y_lo, z_lo, nx, ny, nz. A box that does not fit rho: 1.5.
double AntNative::gap_under(const PackedByteArray &rho, const PackedInt32Array &box, const Transform3D &xf) {
	if (box.size() < 6) {
		return 1.5;
	}
	const int64_t xl = box[0], yl = box[1], zl = box[2], nx = box[3], ny = box[4], nz = box[5];
	if (nx <= xl || ny <= yl || nz <= zl || rho.size() < (nx - xl) * (ny - yl) * (nz - zl)) {
		return 1.5;
	}
	const uint8_t *r = rho.ptr();
	auto clampi = [](int64_t v, int64_t lo, int64_t hi) -> int64_t { return v < lo ? lo : (v > hi ? hi : v); };
	auto foot_at = [&](const Vector3 &p) -> double {
		const int64_t x0 = (int64_t)std::floor((double)p.x);
		const int64_t y0 = (int64_t)std::floor((double)p.y);
		const int64_t z0 = (int64_t)std::floor((double)p.z);
		const double fx = (double)p.x - (double)x0;
		const double fy = (double)p.y - (double)y0;
		const double fz = (double)p.z - (double)z0;
		double v = 0.0;
		for (int dz = 0; dz < 2; dz++) {
			const int64_t z = clampi(z0 + dz, zl, nz - 1);
			const double wz = dz == 1 ? fz : 1.0 - fz;
			for (int dy = 0; dy < 2; dy++) {
				const int64_t y = clampi(y0 + dy, yl, ny - 1);
				const double wy = (dy == 1 ? fy : 1.0 - fy) * wz;
				const int64_t row = ((z - zl) * (ny - yl) + y - yl) * (nx - xl) - xl;
				v += wy * ((1.0 - fx) * (double)r[row + clampi(x0, xl, nx - 1)] + fx * (double)r[row + clampi(x0 + 1, xl, nx - 1)]);
			}
		}
		return v / 255.0;
	};
	const Vector3 up = xf.basis.get_column(1).normalized();
	const Vector3 fw = xf.origin;
	double prev = 0.5;
	double dprev = foot_at(fw + up * (real_t)prev);
	if (dprev >= 0.5) {
		return 0.0;
	}
	for (int i = 1; i < 9; i++) {
		const double s = 0.5 - 0.25 * (double)i;
		const double d = foot_at(fw + up * (real_t)s);
		if (d >= 0.5) {
			const double dd = d - dprev;
			double t = (0.5 - dprev) / (dd > 0.001 ? dd : 0.001);                  // (maxf, clampf: the engine's MAX and CLAMP)
			t = t < 0.0 ? 0.0 : (t > 1.0 ? 1.0 : t);
			const double g = -lerpd(prev, s, t);
			return 0.0 > g ? 0.0 : g;
		}
		prev = s;
		dprev = d;
	}
	return 1.5;
}
