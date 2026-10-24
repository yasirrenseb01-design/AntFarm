extends RefCounted
## Dev (--feet, with --seq, nest view): where each drawn ant's six feet really are, worked out as the shader works
## them out (shaders/ants/ant_core.gdshaderinc pose(): the stepping cycle, the foot set down on the soil under it,
## the two-segment leg reaching for it) - and whether a planted foot stands on the soil, hangs in the air, is down
## in the soil, or is in an egg, larva or cocoon. Only walking legs (not those posed for an activity: digging,
## grooming, milking, dead, just out of the cocoon) and only planted feet (a swinging foot is meant to be in the air).
##   air:   the soil under the tip is more than AIR_GAP below it, and it is on nothing else (brood, an ant's back)
##   soil:  the tip is more than SUNK below the soil surface
##   brood: the tip is more than SUNK inside an egg, larva or cocoon

const BodyCheck := preload("res://scripts/dev/body_check.gd")
const SwayCheck := preload("res://scripts/dev/sway_check.gd")
const K := 0.34              # model design units -> mesh units (the shader's K)
const STRIDE_A := 1.3
const AIR_GAP := 0.15        # world units (~0.2 mm)
const SUNK := 0.12


## The shader's leg_ik(): [knee, ankle] of the two-segment leg reaching for the ankle target TA in 3D.
static func _leg_ik(C: Vector3, N: Vector3, A: Vector3, TA: Vector3, outw: Vector3) -> Array:
	var l1 := (N - C).length()
	var l2 := (A - N).length()
	var D := TA - C
	var dl := maxf(D.length(), 1e-5)
	var n := D / dl
	var d := clampf(dl, absf(l1 - l2) + 1e-4, l1 + l2 - 1e-4)
	var k0 := N - C
	var pk := k0 - n * k0.dot(n)
	if pk.length() < 0.2 * l1:
		pk += (Vector3.UP + 0.5 * outw) * 0.17 * l1
		pk -= n * pk.dot(n)
	pk = pk.normalized()
	var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	return [C + n * a + pk * sqrt(maxf(l1 * l1 - a * a, 0.0)), C + n * d]


static func _yaw(v: Vector3, a: float) -> Vector3:
	return Vector3(v.x * cos(a) - v.z * sin(a), v.y, v.x * sin(a) + v.z * cos(a))


static func _rot_axis(v: Vector3, k: Vector3, a: float) -> Vector3:
	return v * cos(a) + k.cross(v) * sin(a) + k * k.dot(v) * (1.0 - cos(a))


## The soil volume as the shader samples it (texture(vol): rho / 255, trilinear, voxel centres on the integers).
static var _ik_cases := 0
static var _sd_dbg := false
static var rho := PackedByteArray()        # what the feet stand on (nest_scene._foot_rho: the soil and the brood)


static func _vol(nest, p: Vector3) -> float:
	var x0 := floori(p.x)
	var y0 := floori(p.y)
	var z0 := floori(p.z)
	var fx := p.x - x0
	var fy := p.y - y0
	var fz := p.z - z0
	var v := 0.0
	for dz in 2:
		for dy in 2:
			for dx in 2:
				var w := (fx if dx == 1 else 1.0 - fx) * (fy if dy == 1 else 1.0 - fy) * (fz if dz == 1 else 1.0 - fz)
				var c := Vector3i(clampi(x0 + dx, 0, nest.nx - 1), clampi(y0 + dy, nest.y_lo, nest.ny - 1), clampi(z0 + dz, 0, nest.nz - 1))
				v += w * float(rho[nest.idx(c)]) / 255.0
	return v


## The shader's ground_dy() (nest): how far along up the soil surface is from fw (+ above it, - below).
static func _ground_dy(nest, fw: Vector3, upw: Vector3) -> float:
	var prev := 0.5
	var dprev := _vol(nest, fw + upw * prev)
	if dprev >= 0.5:
		for i in range(1, 4):
			var s := 0.5 + 0.25 * i
			var d := _vol(nest, fw + upw * s)
			if d < 0.5:
				return lerpf(prev, s, clampf((dprev - 0.5) / maxf(dprev - d, 0.001), 0.0, 1.0))
			prev = s
			dprev = d
		return 1.4
	for i in range(1, 8):
		var s := 0.5 - 0.25 * i
		var d := _vol(nest, fw + upw * s)
		if d >= 0.5:
			return lerpf(prev, s, clampf((0.5 - dprev) / maxf(d - dprev, 0.001), 0.0, 1.0))
		prev = s
		dprev = d
	return -1.4


## The shader's stride_t(): the stride's foothold for a step of dx and a signed share of turning.
static func _stride_t(F: Vector3, dx: float, tws: float, fmode: float) -> Vector3:
	var tw := absf(tws)
	var tg := Vector2(F.z, -F.x).normalized() * (-1.0 if tws < 0.0 else 1.0)
	var T := F + Vector3(dx * (1.0 - tw) + tg.x * dx * tw, 0.0, tg.y * dx * tw)
	if fmode > 0.5 and fmode < 1.5:
		T.z *= 0.42
		T.y -= 0.35 * K * clampf(absf(T.z) / (0.8 * K), 0.0, 1.0)
	return T


## The shader's set_down(): [T set down on the soil, where it was found (0 under it, 1-3 nearer the body, 10 + j the
## brood search), T before its height was set, how far it was raised or lowered (world units)].
static func _set_down(nest, T: Vector3, M: Transform3D, H: Vector3, C: Vector3, dAF: Vector3, lmax: float, fmode: float) -> Array:
	var reach := 0.5 + 0.1 * (fmode - 1.0) if fmode > 1.5 else 0.5
	var upw := M.basis.y.normalized()
	var sc := M.basis.y.length()
	var br := 0
	var gd := _ground_dy(nest, M * T, upw)
	var hd0 := Vector2((T + dAF - C).x, (T + dAF - C).z).length()
	var r0 := minf(reach, sqrt(maxf(lmax * lmax - hd0 * hd0, 0.0)) + dAF.y - C.y)
	if gd < -r0 * sc or gd > 0.6 * sc:
		var fprev := 0.0
		var gprev := gd
		var found := false
		var Tb := T
		var gb := gd
		for k in range(1, 5):              # (at an edge, set down nearer the body where it reaches; last right under the hip)
			var fk := 0.28 * k if k < 4 else 1.0
			var Tk := T
			Tk.x = lerpf(T.x, H.x, fk)
			Tk.z = lerpf(T.z, H.z, fk)
			var hdk := Vector2((Tk + dAF - C).x, (Tk + dAF - C).z).length()
			var rk := minf(reach, sqrt(maxf(lmax * lmax - hdk * hdk, 0.0)) + dAF.y - C.y)
			var gk := _ground_dy(nest, M * Tk, upw)
			if _sd_dbg:
				print("      k %d fk %.2f gk %.2f rk %.2f (sc %.2f) at %s  vol %.2f" % [k, fk, gk, rk, sc, M * Tk, _vol(nest, M * Tk)])
			if gk >= -rk * sc and gk <= 0.6 * sc:
				var bound := -rk * sc if gprev < -rk * sc else 0.6 * sc
				var ff := lerpf(fprev, fk, clampf((bound - gprev) / (gk - gprev), 0.0, 1.0))
				T.x = lerpf(T.x, H.x, ff)
				T.z = lerpf(T.z, H.z, ff)
				gd = _ground_dy(nest, M * T, upw)
				br = k
				found = true
				break
			if gk > 0.0 and gk < gb:
				Tb = Tk
				gb = gk
			fprev = fk
			gprev = gk
			if k == 4 and fmode > 1.5:
				for j in 18:
					var sh := 0.45 * float(1 + (j % 6) / 2) * (1.0 if j % 2 == 0 else -1.0)
					var fi := 0.4 if j < 6 else (0.75 if j < 12 else 1.0)
					var Tj := T
					Tj.x = lerpf(T.x, H.x, fi) + sh * K * 3.0
					Tj.z = lerpf(T.z, H.z, fi)
					var hdj := Vector2((Tj + dAF - C).x, (Tj + dAF - C).z).length()
					var rj := minf(reach, sqrt(maxf(lmax * lmax - hdj * hdj, 0.0)) + dAF.y - C.y)
					var gj := _ground_dy(nest, M * Tj, upw)
					if gj >= -rj * sc and gj <= 0.6 * sc:
						T = Tj
						gd = gj
						br = 10 + j
						found = true
						break
		if not found and gd > 0.6 * sc and gb < gd:
			T = Tb
			gd = gb
			br = 5
	var Ts := T
	var hy := 0.0
	if gd > -1.35 or absf(M.basis.y.y) > 0.5 * sc:
		hy = clampf(gd / sc, -reach, 1.0)
		T.y += hy
	return [T, br, Ts, hy * sc]


static func _rec_xf(rec: PackedFloat32Array, k: int) -> Transform3D:
	return Transform3D(Basis(Vector3(rec[k], rec[k + 4], rec[k + 8]), Vector3(rec[k + 1], rec[k + 5], rec[k + 9]),
		Vector3(rec[k + 2], rec[k + 6], rec[k + 10])), Vector3(rec[k + 3], rec[k + 7], rec[k + 11]))


## The six feet of one drawn ant: [[world tip, planted?, leg index, how far the leg misses its foothold, foothold,
## coxa, info for why it jumped], ...] (empty when its legs are posed). rec: its row of the shader's feet_tex (where its
## tripods were set down: nest_bodies._feet_rec), or empty.
static func feet(nest, M: Transform3D, cus: Color, rec := PackedFloat32Array(), debug := false) -> Array:
	var y := cus.g
	var code := fmod(floorf(y + 0.0005), 128.0)
	var act := code - (100.0 if code >= 99.5 else 0.0)
	var bc := floorf(cus.r / 512.0)
	var gait := cus.r - bc * 512.0
	var cz := cus.b
	var fmode := floorf(cz / 16384.0)
	cz -= fmode * 16384.0
	var on_back := 1.0 if fmode == 1.0 else 0.0
	var reach := 0.5 + 0.1 * (fmode - 1.0) if fmode > 1.5 else 0.5
	var lc := floorf(cz / 600.0)
	var t := cz - lc * 600.0
	var cw := cus.a
	var tcode := floorf(cw / 1000.0)
	var tw := fmod(tcode, 17.0) / 16.0
	var tdir := -1.0 if tcode >= 17.0 else 1.0
	cw -= tcode * 1000.0
	var sscale := floorf(cw) / 100.0
	var mv := cw
	if sscale < 0.01:
		sscale = 1.0
	else:
		mv = cw - floorf(cw)
	if act in [11.0, 12.0, 18.0, 13.0, 4.0]:
		return []                               # (legs posed for the whole activity)
	var hlift := 0.65 * K if act == 17.0 else 0.0
	var out := []
	var upw := M.basis.y.normalized()
	var sc := M.basis.y.length()
	for part in range(4, 10):
		var li := floorf((part - 4) / 2.0)
		var side := -1.0 if fmod(part - 4, 2.0) < 0.5 else 1.0
		var grp := 0.0 if ((fmod(li, 2.0) < 0.5) == (side < 0.0)) else PI
		var front := li < 0.5
		if front and (act == 2.0 or act == 9.0):
			continue                                # (front legs digging or patting an aphid)
		var L := Vector3(0.85, 0.75, 1.8) if li < 0.5 else (Vector3(0.2, 0.1, -0.1) if li < 1.5 else Vector3(-0.4, -0.65, -2.2))
		var H := Vector3(L.x, 0.85, 0.42 * side) * K
		var C := Vector3(L.x + 0.1, 0.55, 0.85 * side) * K
		var N := Vector3(L.x + L.y, 1.75, 2.05 * side) * K
		var A := Vector3(L.x + L.z * 0.85, 0.35, 2.9 * side) * K
		var F := Vector3(L.x + L.z, 0.0, 3.15 * side) * K
		var duty := lerpf(0.55, 0.42, clampf((sscale - 1.0) / 0.5, 0.0, 1.0))
		var u := fposmod((gait + grp) / TAU, 1.0)
		var amp := STRIDE_A * K * sscale * mv
		var lmax := 0.97 * ((N - C).length() + (A - N).length())
		var dAF := A - F
		var up := 0.0
		var planted := false
		var T := Vector3.ZERO
		var T0 := Vector3.ZERO
		var tb := Vector3.ZERO
		var ts := Vector3.ZERO
		var br := 0
		var hy := 0.0
		var lo := Vector3.INF
		var lu := upw
		var g := 0 if grp < 0.5 else 16
		if rec.size() >= 32 and rec[g + 15] >= -0.5:
			# (the shader's remembered feet: set down from the body as it was when they landed)
			var Ml := _rec_xf(rec, g)
			lo = Ml.origin
			lu = Ml.basis.y.normalized()
			var Tl := _stride_t(F, rec[g + 12], rec[g + 13], rec[g + 14])
			T0 = Tl
			tb = Ml * Tl
			ts = tb
			if not (rec[g + 14] > 0.5 and rec[g + 14] < 1.5):
				var sd := _set_down(nest, Tl, Ml, H, C, dAF, lmax, rec[g + 14])
				Tl = sd[0]
				br = sd[1]
				ts = Ml * (sd[2] as Vector3)
				hy = sd[3]
			var Pw := Ml * Tl
			planted = rec[g + 15] < 0.5
			if not planted:
				var w := clampf(rec[g + 15] - 1.0, 0.0, 1.0)
				var T1 := _stride_t(F, amp, tw * tdir, fmode)
				if on_back < 0.5:
					T1 = _set_down(nest, T1, M, H, C, dAF, lmax, fmode)[0]
				Pw = Pw.lerp(M * T1, w * w * (3.0 - 2.0 * w))
				up = 0.42 * K * minf(sscale, 1.2) * mv * sin(PI * w)
			T = M.affine_inverse() * Pw
		else:
			var dx := 0.0
			planted = u < duty or mv < 0.05
			if u < duty:
				dx = amp * (1.0 - 2.0 * u / duty)
			else:
				var w := (u - duty) / (1.0 - duty)
				dx = amp * (-1.0 + 2.0 * w * w * (3.0 - 2.0 * w))
				up = 0.42 * K * minf(sscale, 1.2) * mv * sin(PI * w)
			if mv < 0.05:
				dx += 0.03 * K * sin(t * 0.9 + li * 2.0 + side)
			T = _stride_t(F, dx, tw * tdir, fmode)
			T0 = T
			tb = M * T
			ts = tb
			if on_back < 0.5:
				var sd := _set_down(nest, T, M, H, C, dAF, lmax, fmode)
				T = sd[0]
				br = sd[1]
				ts = M * (sd[2] as Vector3)
				hy = sd[3]
		T.y += up - hlift
		var v0 := Vector2((F - H).x, (F - H).z)
		var v1 := Vector2((T - H).x, (T - H).z)
		var th := atan2(v0.x * v1.y - v0.y * v1.x, v0.dot(v1))
		var Cy := H + _yaw(C - H, th)
		var Ny := H + _yaw(N - H, th)
		var Ay := H + _yaw(A - H, th)
		var Fy := H + _yaw(F - H, th)
		var TA := T + (Ay - Fy)
		var ik := _leg_ik(Cy, Ny, Ay, TA, Vector3(Fy.x - H.x, 0.0, Fy.z - H.z).normalized())
		var A2: Vector3 = ik[1]
		var tip := A2 + (Fy - Ay)
		if planted and OS.has_environment("IKCASES") and _ik_cases < 3000 and (tip - T).length() > 0.02:
			_ik_cases += 1        # (dev: the planted feet the leg misses, for trying other leg solutions offline)
			print("IKCASE %d %d %.4f %.4f %.4f %.4f" % [li, side, T.x / K, T.y / K, T.z / K, (tip - T).length() / K])
		if debug:
			print("    leg %d%s planted %s upy %.2f fmode %d reach %.2f  T %s  tipErr %.3f  gd_tip %.2f" % [li, "R" if side > 0 else "L", planted, M.basis.y.y / sc, fmode, reach,
				M * T, (A2 - TA).length(), _ground_dy(nest, M * tip, upw)])
		var info := {"u": u, "mv": mv, "ss": sscale, "tw": tw * tdir, "fm": fmode, "act": act, "br": br, "tb": tb, "ts": ts,
			"hy": hy, "err": M.basis * (tip - T), "M": M, "tl": T0, "lo": lo, "lu": lu}
		out.append([M * tip, planted, int(li), (tip - T).length(), M * T, M * Cy, info])
	return out


## One frame: every drawn worker's planted feet sorted into on the soil / in the air / in the soil / in the brood.
static func measure(nv, tally: Dictionary) -> void:
	var nest = nv.nest
	rho = nv._foot_rho if not nv._foot_rho.is_empty() else nest.rho
	var brood := []
	for mm in [nv._larva_mm, nv._pupa_mm]:
		for i in mm.instance_count:
			var x: Transform3D = mm.get_instance_transform(i)
			brood.append([BodyCheck._larva_spheres(x) if mm == nv._larva_mm else BodyCheck._cocoon_spheres(x), x.origin])
	var mm: MultiMesh = nv._ant_mm
	tally.frames_f = int(tally.get("frames_f", 0)) + 1
	tally.dt_sum = float(tally.get("dt_sum", 0.0)) + nv.get_process_delta_time()    # (a jump a frame is longer at a lower frame rate)
	SwayCheck.measure(nv, tally)          # (steps, bobbing, swaying: dev/sway_check.gd)
	tally.prev = tally.get("prev_next", {})
	tally.prev_next = {}
	var bodies := []
	for i in mm.instance_count:
		var X := mm.get_instance_transform(i)
		bodies.append([BodyCheck._ant_spheres(X), X.origin])
	for i in mm.instance_count:
		var M := mm.get_instance_transform(i)
		if not nv._shown(M):
			continue
		var dbg: bool = tally.has("debug") and int(tally.get("dbg_n", 0)) < 4 and int(tally.get("frames_f", 0)) == 3
		if dbg:
			tally.dbg_n = int(tally.get("dbg_n", 0)) + 1
			print("  ant at %s up %s scale %.2f custom %s" % [M.origin, M.basis.y.normalized(), M.basis.y.length(), mm.get_instance_custom_data(i)])
		if tally.has("debug") and int(floorf(mm.get_instance_custom_data(i).b / 16384.0)) == 5 and int(tally.get("dbg5", 0)) < 12 and int(tally.get("frames_f", 0)) == 5:
			tally.dbg5 = int(tally.get("dbg5", 0)) + 1
			for mt in nv._mates + nv._dig_vis.values():
				if mt.has("xf") and (mt.xf as Transform3D).origin.distance_to(M.origin) < 0.01:
					print("  M5 over %.2f clr %.2f fgap %.2f freach %.2f role %s up %s" % [float(mt.get("over", 0.0)), float(mt.get("clr", 0.0)), float(mt.get("floor_gap", -1.0)),
						float(mt.get("freach", 0.0)), mt.get("role", "dig"), M.basis.y.normalized()])
		var fs := feet(nest, M, mm.get_instance_custom_data(i), _rec(nv, i), dbg)
		var upw := M.basis.y.normalized()
		# jitter: a planted foot stays where it is in the world while the body walks over it - from one frame to the
		# next it may slide a little with the stride, not jump (only when measured every frame: --seq-every=1)
		var key := "%d" % i
		var prev: Array = (tally.get("prev", {}) as Dictionary).get(key, [])
		if prev.size() == fs.size() and (prev.is_empty() or (prev[0][3] as Vector3).distance_to(M.origin) < 0.5):    # (the same ant: not one that came on screen in its place)
			for k in fs.size():
				if fs[k][1] and prev[k][1]:
					var jump: float = (fs[k][0] as Vector3).distance_to(prev[k][0])
					var dvert := absf(((fs[k][0] as Vector3) - (prev[k][0] as Vector3)).dot(upw))
					var vprev: float = prev[k][4]
					tally.vib_n = int(tally.get("vib_n", 0)) + 1
					var bodyv := absf(((M.origin - (prev[k][3] as Vector3))).dot(upw))
					var bk := "body still" if bodyv < 0.01 else ("body bobbing" if bodyv < 0.05 else "body moving up/down")
					tally["vn:" + bk] = int(tally.get("vn:" + bk, 0)) + 1
					if dvert > 0.03:
						tally.vib = int(tally.get("vib", 0)) + 1
						tally["vb:" + bk] = int(tally.get("vb:" + bk, 0)) + 1
					var sgn_now := signf(((fs[k][0] as Vector3) - (prev[k][0] as Vector3)).dot(upw))
					if dvert > 0.02 and absf(vprev) > 0.02 and signf(vprev) != sgn_now:
						tally.flick = int(tally.get("flick", 0)) + 1      # (up then down, or down then up: a flicker)
					fs[k].append(((fs[k][0] as Vector3) - (prev[k][0] as Vector3)).dot(upw))    # (this frame's move along up, for the next)
					tally.jit_n = int(tally.get("jit_n", 0)) + 1
					var fm := int(floorf(mm.get_instance_custom_data(i).b / 16384.0))
					tally["jn:%d" % fm] = int(tally.get("jn:%d" % fm, 0)) + 1
					if jump > 0.12 and tally.has("debug") and int(tally.get("dbg_j", 0)) < 14:
						tally.dbg_j = int(tally.get("dbg_j", 0)) + 1
						print("  JUMP mode %d leg %d by %.2f  body moved %.3f  up %s  old %s new %s" % [fm, fs[k][2], jump, (prev[k][3] as Vector3).distance_to(M.origin),
							upw, prev[k][0], fs[k][0]])
					if jump > 0.12:
						var cause := _jump_cause(prev[k][5], fs[k][6], (prev[k][3] as Vector3).distance_to(M.origin))
						tally["jc:" + cause] = int(tally.get("jc:" + cause, 0)) + 1
						if cause.begins_with("stride: the body moved sideways") or cause.begins_with("stride: the body moved backwards"):
							var who := "not a nestmate (a digger?)"
							for mt in nv._mates:
								if mt.has("xf") and (mt.xf as Transform3D).origin.distance_to(M.origin) < 0.01:
									var vel: Vector3 = mt.get("vel", Vector3.ZERO)
									var off := rad_to_deg((M.basis.x.normalized()).angle_to(vel)) if vel.length() > 0.05 else -1.0
									who = "role %s, %s, heading off its motion %s" % [mt.get("role", "?"), "facing something" if mt.has("face") and mt.face != Vector3.INF else "not facing",
										"(still)" if off < 0.0 else "%d-%d deg" % [int(off / 30.0) * 30, int(off / 30.0) * 30 + 30]]
							tally["side:" + who] = int(tally.get("side:" + who, 0)) + 1
						tally.jit = int(tally.get("jit", 0)) + 1
						tally["j:%d" % fm] = int(tally.get("j:%d" % fm, 0)) + 1
		var cur := []
		for f in fs:
			cur.append([f[0], f[1], f[2], M.origin, f[7] if f.size() > 7 else 0.0, f[6]])
		if not tally.has("prev_next"):
			tally.prev_next = {}
		tally.prev_next[key] = cur
		# where it is: up on something (its body well above the soil), on a slope or a wall, or on a floor
		var body_gap := _ground_dy(nest, M.origin, upw)
		var near_brood := false
		for b in brood:
			if (b[1] as Vector3).distance_squared_to(M.origin) < 9.0:
				near_brood = true
		if body_gap < -0.7:
			var why := "?"
			for mt in nv._mates + nv._dig_vis.values():
				if mt.has("xf") and (mt.xf as Transform3D).origin.distance_to(M.origin) < 0.01:
					var rear := _ground_dy(nest, M * Vector3(-1.0, 0, 0), upw)
					why = ("climbing over an ant" if mt.has("over_on") and float(mt.get("over", 0.0)) > 0.3 else
						("on the brood" if float(mt.get("over", 0.0)) > 0.3 else
						("lifted clear of the soil" if float(mt.get("clr", 0.0)) > 0.2 else
						("front over a drop" if rear > -0.4 else
						("digger" if not mt.has("role") else "in the open: %s rest %d settle %d script %s" % [mt.get("role"), int(mt.get("rest", 0)),
							(mt.get("settle", []) as Array).size(), mt.has("script")])))))
			tally["why:" + why] = int(tally.get("why:" + why, 0)) + 1
			tally._why_now = why.split(":")[0]
			if tally.has("debug") and why.begins_with("in the open") and int(tally.get("dbg_open", 0)) < 8:
				tally.dbg_open = int(tally.get("dbg_open", 0)) + 1
				for mt in nv._mates:
					if mt.has("xf") and (mt.xf as Transform3D).origin.distance_to(M.origin) < 0.01:
						print("  OPEN at %s up %s cell %s walkable %s goal %s path %d over %.2f clr %.2f floor_gap %.2f narrow %s lag %.2f" % [M.origin, upw, mt.cell, nv._walkable(mt.cell),
							mt.get("goal"), (mt.get("path", []) as Array).size(), float(mt.get("over", 0.0)), float(mt.get("clr", 0.0)), float(mt.get("floor_gap", -1.0)),
							mt.get("narrow", false), (Vector3(mt.cell) - M.origin).length()])
		var where := "over the brood" if near_brood and body_gap < -0.7 else ("up on something" if body_gap < -0.7 else (
			"by the brood" if near_brood else ("floor" if upw.y > 0.9 else ("slope" if upw.y > 0.3 else "wall/ceiling"))))
		for f in fs:
			if not f[1]:
				continue
			var tip: Vector3 = f[0]
			tally.feet = int(tally.get("feet", 0)) + 1
			var in_brood := false
			for b in brood:
				if (b[1] as Vector3).distance_squared_to(tip) > 9.0:
					continue
				for s in b[0]:
					if (s[0] as Vector3).distance_to(tip) < float(s[1]) - SUNK:
						in_brood = true
			tally["n:" + where] = int(tally.get("n:" + where, 0)) + 1
			if in_brood:
				tally.foot_brood = int(tally.get("foot_brood", 0)) + 1
				tally["brood:" + where] = int(tally.get("brood:" + where, 0)) + 1
				_note(tally, "brood", tip)
				continue
			var gd := _ground_dy(nest, tip, upw)
			# (through the soil's surface for real: in the soil itself - not the feet's map, which adds the brood and the
			# nestmates climbed on - by more than SUNK whichever way the surface is; along the ant's up alone, a foot set on
			# the wall beside it or on the ceiling curving over it counted as deep in. The keeper's target, 2026-10-24: <= 1%)
			var rho_map: PackedByteArray = rho
			rho = nest.rho
			if _vol(nest, tip) >= 0.5 and not _open_within(nest, tip, SUNK):
				tally.foot_pen = int(tally.get("foot_pen", 0)) + 1
				var why := "the leg could not reach its foothold" if float(f[3]) > 0.1 else (
					"its foothold in the soil" if _vol(nest, f[4]) >= 0.55 else "its foothold on the surface")
				why += ", the leg's root in the soil too" if _vol(nest, f[5]) >= 0.5 else ""
				tally["pw:" + why] = int(tally.get("pw:" + why, 0)) + 1
				if why.begins_with("its foothold in the soil"):
					# (how it got there: where the search found it, how far it was raised or lowered, and the soil from
					# the foothold along its up now)
					var inf: Dictionary = f[6]
					var fk := "found %s, raised %.1f, soil above it %.1f, body up %.1f" % ["under it" if int(inf.br) == 0 else ("nearer the body" if int(inf.br) < 10 else "brood search"),
						snappedf(float(inf.hy), 0.2), snappedf(_ground_dy(nest, f[4], upw), 0.2), snappedf(upw.y, 0.5)]
					tally["un:" + fk] = int(tally.get("un:" + fk, 0)) + 1
					if tally.has("debug") and int(tally.get("dbg_fis", 0)) < 12:
						tally.dbg_fis = int(tally.get("dbg_fis", 0)) + 1
						var fw: Vector3 = f[4]
						var soil_v := _vol(nest, fw)
						rho = rho_map
						print("  FIS at %s soil %.2f map %.2f  gd(map) along landing up %.2f now %.2f  up then %s now %s  tip %s" % [fw, soil_v, _vol(nest, fw),
							_ground_dy(nest, fw, inf.lu), _ground_dy(nest, fw, upw), inf.lu, upw, tip])
						if int(tally.dbg_fis) <= 3:
							_sd_dbg = true
							print("   body at %s" % M.origin)
							feet(nest, M, mm.get_instance_custom_data(i), _rec(nv, i), true)
							_sd_dbg = false
						rho = nest.rho
				if float(f[3]) > 0.1:
					# (where the foothold it could not reach lies from where the foot rests, in its own units / K)
					var Tl: Vector3 = M.affine_inverse() * (f[4] as Vector3)
					var li := float(f[2])
					var L := Vector3(0.85, 0.75, 1.8) if li < 0.5 else (Vector3(0.2, 0.1, -0.1) if li < 1.5 else Vector3(-0.4, -0.65, -2.2))
					var d := Tl / K - Vector3(L.x + L.z, 0.0, 3.15 * signf(Tl.z))
					var uk := "leg %d: ahead %.0f out %.0f up %.0f" % [li, d.x, d.z * signf(Tl.z), d.y]
					tally["un:" + uk] = int(tally.get("un:" + uk, 0)) + 1
			rho = rho_map
			if (gd > SUNK or gd < -AIR_GAP) and where == "floor" and tally.has("debug") and int(tally.get("dbg_floor", 0)) < 8:
				tally.dbg_floor = int(tally.get("dbg_floor", 0)) + 1
				print("  FLOOR foot gd %.2f leg %d  ant %s up %s body_gap %.2f custom %s" % [gd, f[2], M.origin, upw, body_gap, mm.get_instance_custom_data(i)])
				feet(nest, M, mm.get_instance_custom_data(i), _rec(nv, i), true)
			if gd > SUNK:
				tally.foot_soil = int(tally.get("foot_soil", 0)) + 1
				tally["soil:" + where] = int(tally.get("soil:" + where, 0)) + 1
				_note(tally, "soil", tip)
			elif gd < -AIR_GAP:
				var on := false
				for b in brood:
					if (b[1] as Vector3).distance_squared_to(tip) < 9.0:
						for s in b[0]:
							if (s[0] as Vector3).distance_to(tip) < float(s[1]) + AIR_GAP:
								on = true                   # (standing on the brood)
				for bd in bodies:
					if on or (bd[1] as Vector3).distance_squared_to(tip) > 9.0 or (bd[1] as Vector3) == M.origin:
						continue
					for q in bd[0]:
						if (q[0] as Vector3).distance_to(tip) < float(q[1]) + AIR_GAP:
							on = true                       # (on another ant's back)
				if not on and tally.has("debug") and where in ["over the brood", "up on something"] and int(tally.get("dbg_up", 0)) < 14:
					tally.dbg_up = int(tally.get("dbg_up", 0)) + 1
					var bd_min := INF
					for b in brood:
						for s2 in b[0]:
							bd_min = minf(bd_min, (s2[0] as Vector3).distance_to(tip) - float(s2[1]))
					var an_min := INF
					for bd in bodies:
						if (bd[1] as Vector3) == M.origin:
							continue
						for q in bd[0]:
							an_min = minf(an_min, (q[0] as Vector3).distance_to(tip) - float(q[1]))
					var who := "?"
					for mt in nv._mates + nv._dig_vis.values():
						if mt.has("xf") and (mt.xf as Transform3D).origin.distance_to(M.origin) < 0.01:
							who = "role %s over %.2f clr %.2f rest %d mv %.2f walkable %s cell %s goal %s wander %s settle %d" % [mt.get("role", "dig"), float(mt.get("over", 0.0)), float(mt.get("clr", 0.0)),
								int(mt.get("rest", 0)), float(mt.get("mv", 0.0)), nv._walkable(mt.get("cell", Vector3i.ZERO)), mt.get("cell"),
								nv._rooms[int(mt.goal)].cell if int(mt.get("goal", -1)) >= 0 and int(mt.goal) < nv._rooms.size() else mt.get("goal", -1), mt.get("wander", 0), (mt.get("settle", []) as Array).size()]
					print("  WHO ", who)
					if gd <= -1.35 and where == "over the brood" and int(tally.get("dbg_l", 0)) < 2:
						tally.dbg_l = int(tally.get("dbg_l", 0)) + 1
						feet(nest, M, mm.get_instance_custom_data(i), _rec(nv, i), true)
					print("  UP %s leg %d fmode %d gd %.2f body_gap %.2f  nearest brood %.2f ant %.2f  tip-origin along up %.2f" % [where, f[2],
						int(floorf(mm.get_instance_custom_data(i).b / 16384.0)), gd, body_gap, bd_min, an_min, (tip - M.origin).dot(upw)])
				if not on and where == "over the brood":
					var hb := "gap %.1f" % snappedf(clampf(-body_gap, 0.0, 1.4), 0.2)
					tally["hb:" + hb] = int(tally.get("hb:" + hb, 0)) + 1
				if not on and where == "up on something":
					tally["upwhy:" + String(tally.get("_why_now", "?"))] = int(tally.get("upwhy:" + String(tally.get("_why_now", "?")), 0)) + 1
				if not on:
					tally.foot_air = int(tally.get("foot_air", 0)) + 1
					tally["air:" + where] = int(tally.get("air:" + where, 0)) + 1
					_note(tally, "air", tip)
					if gd <= -1.35:
						tally.foot_air_far = int(tally.get("foot_air_far", 0)) + 1      # (no soil within reach at all)


## Why a planted foot jumped from one frame to the next (a, b: feet()'s info for it then and now): first what changed
## at once (the body, the activity, a new step, the feet's mode, where the foothold search found ground), else the
## stage of the shader's foot that moved the most - the stride's foothold, the search, its height on the soil, the leg.
static func _jump_cause(a: Dictionary, b: Dictionary, body: float) -> String:
	if body > 0.25:
		return "the body moved far in one frame (%.1f-%.1f)" % [snappedf(body - 0.05, 0.1), snappedf(body - 0.05, 0.1) + 0.1]
	if a.act != b.act:
		return "its activity changed"
	if a.lo != b.lo:
		return "set down again (left behind: the body moved on without stepping)"
	if (float(a.mv) < 0.05) != (float(b.mv) < 0.05):
		return "it started or stopped walking (standing, every foot counts as planted)"
	if float(b.u) < float(a.u) - 0.02:
		return "a new step began with no swing between (the gait ran past the swing in a frame)"
	if a.fm != b.fm:
		if int(a.fm) > 1 and int(b.fm) > 1:
			return "how far down its lifted feet reach changed (a 0.1 step of freach)"
		return "its feet's mode changed (floor / on a back / lifted %d -> %d)" % [mini(int(a.fm), 2), mini(int(b.fm), 2)]
	if a.br != b.br:
		var kind := func(x: int) -> String: return "under it" if x == 0 else ("nearer the body" if x < 10 else "the brood search")
		return "the foothold search found ground elsewhere (%s -> %s)" % [kind.call(int(a.br)), kind.call(int(b.br))]
	var d_base := ((b.tb as Vector3) - (a.tb as Vector3)).length()
	var d_search := (((b.ts as Vector3) - (b.tb as Vector3)) - ((a.ts as Vector3) - (a.tb as Vector3))).length()
	var d_height := absf(float(b.hy) - float(a.hy))
	var d_leg := ((b.err as Vector3) - (a.err as Vector3)).length()
	var top := maxf(maxf(d_base, d_search), maxf(d_height, d_leg))
	if top == d_base:
		if absf(float(b.mv) - float(a.mv)) > 0.03:
			return "stride: its speed changed (mv %s)" % ("up" if float(b.mv) > float(a.mv) else "down")
		if a.ss != b.ss:
			return "stride: its step length changed"
		if a.tw != b.tw:
			return "stride: its share of turning changed"
		var Ma: Transform3D = a.M
		var Mb: Transform3D = b.M
		var tl: Vector3 = b.tl
		var rot := ((Mb.basis * tl) - (Ma.basis * tl)).length()      # (the body turning or tilting under the same foothold)
		if rot > 0.5 * d_base:
			return "stride: the body turned or tilted more than the feet step round"
		var mvd := Mb.origin - Ma.origin
		var fwd := Ma.basis.x.normalized()
		var slide := 2.0 * STRIDE_A * K * float(b.ss) * float(b.mv) / lerpf(0.55, 0.42, clampf((float(b.ss) - 1.0) / 0.5, 0.0, 1.0)) * (float(b.u) - float(a.u))
		var sc := Ma.basis.y.length()
		if absf(mvd.dot(Ma.basis.z.normalized())) > 0.5 * absf(mvd.dot(fwd)):
			return "stride: the body moved sideways (the feet slide only back)"
		if mvd.dot(fwd) < -0.02:
			return "stride: the body moved backwards"
		return "stride: the body moved %s than the feet slide back" % ("further" if mvd.dot(fwd) > slide * sc else "less")
	if top == d_search:
		return "the foothold search moved it (same kind)"
	if top == d_height:
		return "its height on the soil changed"
	return "the leg reaching it or not (IK)"


static func _rec(nv, i: int) -> PackedFloat32Array:
	var b: PackedFloat32Array = nv._feet_buf
	return b.slice(i * 32, i * 32 + 32) if b.size() >= i * 32 + 32 else PackedFloat32Array()


static func _note(tally: Dictionary, kind: String, at: Vector3) -> void:
	var w: Dictionary = tally.get("foot_at", {})
	if not w.has(kind):
		w[kind] = []
	if (w[kind] as Array).size() < 6:
		w[kind].append(at)
	tally.foot_at = w


## Whether there is open space within r of p (14 directions, at r/2 and r): the surface close by.
static func _open_within(nest, p: Vector3, r: float) -> bool:
	for d in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1),
			Vector3(1, 1, 1), Vector3(1, 1, -1), Vector3(1, -1, 1), Vector3(1, -1, -1), Vector3(-1, 1, 1), Vector3(-1, 1, -1),
			Vector3(-1, -1, 1), Vector3(-1, -1, -1)]:
		var u: Vector3 = (d as Vector3).normalized()
		if _vol(nest, p + u * r * 0.5) < 0.5 or _vol(nest, p + u * r) < 0.5:
			return true
	return false


static func report(tally: Dictionary) -> String:
	var n := maxf(1.0, float(tally.get("feet", 0)))
	var s := "planted feet %d: in the air %.2f%% (of them far from any soil %.2f%%), in the soil %.2f%%, in the brood %.2f%%" % [
		int(tally.get("feet", 0)), 100.0 * float(tally.get("foot_air", 0)) / n, 100.0 * float(tally.get("foot_air_far", 0)) / n,
		100.0 * float(tally.get("foot_soil", 0)) / n, 100.0 * float(tally.get("foot_brood", 0)) / n]
	s += "
    planted feet through the soil's surface (in by more than %.2f whichever way): %.2f%%" % [SUNK, 100.0 * float(tally.get("foot_pen", 0)) / n]
	for k in tally:
		if String(k).begins_with("pw:"):
			s += "
      through the surface: %5d  %s" % [tally[k], String(k).substr(3)]
	for bk in ["body still", "body bobbing", "body moving up/down"]:
		if tally.has("vn:" + bk):
			s += "
      planted feet moving up/down >0.03 while its %s: %.1f%% of %d" % [bk, 100.0 * float(tally.get("vb:" + bk, 0)) / float(tally["vn:" + bk]), int(tally["vn:" + bk])]
	for key in ["wall", "open"]:
		var nst := float(tally.get("st_n:" + key, 0))
		if nst > 0:
			s += "
    ants staying put for a second, %s: %d - heading swinging to and fro %.1f%%, head/gaster nodding %.1f%%, bending sideways to and fro %.1f%%" % [
				"beside a wall" if key == "wall" else "in the open", int(nst), 100.0 * float(tally.get("st_turn:" + key, 0)) / nst,
				100.0 * float(tally.get("st_bend:" + key, 0)) / nst, 100.0 * float(tally.get("st_lat:" + key, 0)) / nst]
	s += "
    ants standing (nearly) still swaying - turned one way then back the next frame: %.2f%% of %d" % [100.0 * float(tally.get("sway", 0)) / maxf(1.0, float(tally.get("sway_n", 0))), int(tally.get("sway_n", 0))]
	s += "
    ants standing still whose head or gaster moves (neck/waist bend changes) from frame to frame: %.2f%% of %d" % [100.0 * float(tally.get("wob", 0)) / maxf(1.0, float(tally.get("wob_n", 0))), int(tally.get("wob_n", 0))]
	s += "
    bodies bobbing (up then down, >0.01 each frame): %.2f%% of ant-frames" % [100.0 * float(tally.get("bob", 0)) / maxf(1.0, float(tally.get("bob_n", 0)))]
	if int(tally.get("g_n", 0)) > 0:
		s += "
    walking ants: %.1f steps a second per leg, %.1f body lengths a second" % [float(tally.g_sum) / float(tally.g_n), float(tally.v_sum) / float(tally.g_n)]
	s += "
    planted feet moving up or down more than 0.03 in a frame: %.2f%%, flickering (up then down) %.2f%%" % [100.0 * float(tally.get("vib", 0)) / maxf(1.0, float(tally.get("vib_n", 0))),
		100.0 * float(tally.get("flick", 0)) / maxf(1.0, float(tally.get("vib_n", 0)))]
	s += "
    planted feet jumping more than 0.12 between frames: %.2f%% of %d" % [100.0 * float(tally.get("jit", 0)) / maxf(1.0, float(tally.get("jit_n", 0))), int(tally.get("jit_n", 0))]
	s += "
      frames %d, %.1f ms a frame on average" % [int(tally.get("frames_f", 0)), 1000.0 * float(tally.get("dt_sum", 0.0)) / maxf(1.0, float(tally.get("frames_f", 0)))]
	var jc := []
	for k in tally:
		if String(k).begins_with("jc:"):
			jc.append([int(tally[k]), String(k).substr(3)])
	jc.sort_custom(func(x, y): return x[0] > y[0])
	for c in jc:
		s += "
      jumping: %5.1f%%  %s" % [100.0 * float(c[0]) / maxf(1.0, float(tally.get("jit", 0))), c[1]]
	var un := []
	for k in tally:
		if String(k).begins_with("un:"):
			un.append([int(tally[k]), String(k).substr(3)])
	un.sort_custom(func(x, y): return x[0] > y[0])
	for c in un.slice(0, 20):
		s += "
        out of reach: %5d  %s" % c
	for k in tally:
		if String(k).begins_with("side:"):
			s += "
        sideways/backwards: %5d  %s" % [tally[k], String(k).substr(5)]
	for k in tally:
		if String(k).begins_with("upwhy:"):
			s += "
      air feet up on something, %s: %d" % [String(k).substr(6), tally[k]]
	for k in tally:
		if String(k).begins_with("st_src:"):
			s += "
      heading swinging, %s: %d" % [String(k).substr(7), tally[k]]
	for k in tally:
		if String(k).begins_with("hb:"):
			s += "
      air feet over the brood, body %s above the floor: %d" % [String(k).substr(3), tally[k]]
	for k in tally:
		if String(k).begins_with("why:"):
			s += "
      high ant-frames: %5d  %s" % [tally[k], String(k).substr(4)]
	for fm in 6:
		if tally.has("jn:%d" % fm):
			s += "
      feet mode %d (0 floor, 1 on a back, 2-3 lifted): jumping %.2f%% of %d" % [fm, 100.0 * float(tally.get("j:%d" % fm, 0)) / float(tally["jn:%d" % fm]), int(tally["jn:%d" % fm])]
	for where in ["floor", "slope", "wall/ceiling", "by the brood", "over the brood", "up on something"]:
		var m := float(tally.get("n:" + where, 0))
		if m > 0:
			s += "\n    %-16s %6d feet: air %5.1f%%  soil %5.1f%%  brood %5.1f%%" % [where, int(m), 100.0 * float(tally.get("air:" + where, 0)) / m,
				100.0 * float(tally.get("soil:" + where, 0)) / m, 100.0 * float(tally.get("brood:" + where, 0)) / m]
	for k in tally.get("foot_at", {}):
		s += "\n    %s e.g. at %s" % [k, tally.foot_at[k].slice(0, 3)]
	return s
