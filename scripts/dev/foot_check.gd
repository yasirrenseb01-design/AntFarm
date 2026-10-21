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
const K := 0.34              # model design units -> mesh units (the shader's K)
const STRIDE_A := 1.3
const AIR_GAP := 0.15        # world units (~0.2 mm)
const SUNK := 0.12


## The shader's leg_ik(): femur and tibia rotations for the knee-up solution reaching the ankle for TA.
static func _leg_ik(C: Vector3, N: Vector3, A: Vector3, TA: Vector3) -> Array:
	var d := TA - C
	var dir := (Vector3(d.x, 0.0, d.z) + Vector3(1e-4, 0.0, 0.0)).normalized()
	var axis := dir.cross(Vector3.UP).normalized()
	var u1 := Vector2((N - C).dot(dir), N.y - C.y)
	var r2 := Vector2((A - C).dot(dir), A.y - C.y)
	var c2 := Vector2((TA - C).dot(dir), TA.y - C.y)
	var l1 := u1.length()
	var l2 := (r2 - u1).length()
	var dr := r2.length()
	var dc := clampf(c2.length(), absf(l1 - l2) + 1e-4, l1 + l2 - 1e-4)
	var a0 := acos(clampf((l1 * l1 + dr * dr - l2 * l2) / (2.0 * l1 * dr), -1.0, 1.0))
	var a1 := acos(clampf((l1 * l1 + dc * dc - l2 * l2) / (2.0 * l1 * dc), -1.0, 1.0))
	var sgn := signf(r2.x * u1.y - r2.y * u1.x)
	var f := atan2(c2.y, c2.x) - atan2(r2.y, r2.x) + sgn * (a1 - a0)
	var n2 := Vector2(u1.x * cos(f) - u1.y * sin(f), u1.x * sin(f) + u1.y * cos(f))
	var cc := c2.normalized() * dc
	var tb0 := r2 - u1
	var tb1 := cc - n2
	var t := atan2(tb1.y, tb1.x) - atan2(tb0.y, tb0.x)
	return [f, t, axis]


static func _yaw(v: Vector3, a: float) -> Vector3:
	return Vector3(v.x * cos(a) - v.z * sin(a), v.y, v.x * sin(a) + v.z * cos(a))


static func _rot_axis(v: Vector3, k: Vector3, a: float) -> Vector3:
	return v * cos(a) + k.cross(v) * sin(a) + k * k.dot(v) * (1.0 - cos(a))


## The soil volume as the shader samples it (texture(vol): rho / 255, trilinear, voxel centres on the integers).
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
				var c := Vector3i(clampi(x0 + dx, 0, nest.nx - 1), clampi(y0 + dy, 0, nest.ny - 1), clampi(z0 + dz, 0, nest.nz - 1))
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


## The six feet of one drawn ant: [[world tip, planted?, leg index], ...] (empty when its legs are posed).
static func feet(nest, M: Transform3D, cus: Color, debug := false) -> Array:
	var y := cus.g
	var code := fmod(floorf(y + 0.0005), 128.0)
	var act := code - (100.0 if code >= 99.5 else 0.0)
	var bc := floorf(cus.r / 512.0)
	var gait := cus.r - bc * 512.0
	var cz := cus.b
	var fmode := floorf(cz / 16384.0)
	cz -= fmode * 16384.0
	var on_back := 1.0 if fmode == 1.0 else 0.0
	var reach := 0.88 if fmode == 3.0 else (0.75 if fmode == 2.0 else 0.5)
	var lc := floorf(cz / 600.0)
	var t := cz - lc * 600.0
	var cw := cus.a
	var tcode := floorf(cw / 1000.0)
	var tw := fmod(tcode, 9.0) / 8.0
	var tdir := -1.0 if tcode >= 9.0 else 1.0
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
		var dx := 0.0
		var up := 0.0
		var planted := u < duty or mv < 0.05
		if u < duty:
			dx = amp * (1.0 - 2.0 * u / duty)
		else:
			var w := (u - duty) / (1.0 - duty)
			dx = amp * (-1.0 + 2.0 * w * w * (3.0 - 2.0 * w))
			up = 0.42 * K * minf(sscale, 1.2) * mv * sin(PI * w)
		if mv < 0.05:
			dx += 0.03 * K * sin(t * 0.9 + li * 2.0 + side)
		var tg := Vector2(F.z, -F.x).normalized() * tdir
		var T := F + Vector3(dx * (1.0 - tw) + tg.x * dx * tw, 0.0, tg.y * dx * tw)
		if on_back > 0.5:
			T.z *= 0.42
			T.y -= 0.35 * K * clampf(absf(T.z) / (0.8 * K), 0.0, 1.0)
		var fw := M * T
		var gd := _ground_dy(nest, fw, upw) if on_back < 0.5 else 0.0
		if on_back < 0.5 and (gd < -reach * sc or gd > 0.6 * sc):
			for k in range(1, 4):              # (the shader: at an edge, set down nearer the body where it reaches)
				var Tk := T
				Tk.x = lerpf(T.x, H.x, 0.28 * k)
				Tk.z = lerpf(T.z, H.z, 0.28 * k)
				var gk := _ground_dy(nest, M * Tk, upw)
				if gk >= -reach * sc and gk <= 0.6 * sc:
					T = Tk
					gd = gk
					break
		if on_back < 0.5 and (gd > -1.35 or absf(M.basis.y.y) > 0.5 * sc):
			T.y += clampf(gd / sc, -reach, 0.6)
		T.y += up - hlift
		var v0 := Vector2((F - H).x, (F - H).z)
		var v1 := Vector2((T - H).x, (T - H).z)
		var th := atan2(v0.x * v1.y - v0.y * v1.x, v0.dot(v1))
		var Cy := H + _yaw(C - H, th)
		var Ny := H + _yaw(N - H, th)
		var Ay := H + _yaw(A - H, th)
		var Fy := H + _yaw(F - H, th)
		var TA := T + (Ay - Fy)
		var ik := _leg_ik(Cy, Ny, Ay, TA)
		var N2 := Cy + _rot_axis(Ny - Cy, ik[2], ik[0])
		var A2 := N2 + _rot_axis(Ay - Ny, ik[2], ik[1])
		var tip := A2 + (Fy - Ay)
		if debug:
			print("    leg %d%s planted %s gd0 %.2f  T %s  tipErr %.3f  gd_tip %.2f" % [li, "R" if side > 0 else "L", planted, gd,
				M * T, (A2 - TA).length(), _ground_dy(nest, M * tip, upw)])
		out.append([M * tip, planted, int(li)])
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
		var fs := feet(nest, M, mm.get_instance_custom_data(i), dbg)
		var upw := M.basis.y.normalized()
		# where it is: up on something (its body well above the soil), on a slope or a wall, or on a floor
		var body_gap := _ground_dy(nest, M.origin, upw)
		var near_brood := false
		for b in brood:
			if (b[1] as Vector3).distance_squared_to(M.origin) < 9.0:
				near_brood = true
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
			if (gd > SUNK or gd < -AIR_GAP) and where == "floor" and tally.has("debug") and int(tally.get("dbg_floor", 0)) < 8:
				tally.dbg_floor = int(tally.get("dbg_floor", 0)) + 1
				print("  FLOOR foot gd %.2f leg %d  ant %s up %s body_gap %.2f custom %s" % [gd, f[2], M.origin, upw, body_gap, mm.get_instance_custom_data(i)])
				feet(nest, M, mm.get_instance_custom_data(i), true)
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
							who = "role %s over %.2f clr %.2f rest %d mv %.2f walkable %s cell %s" % [mt.get("role", "dig"), float(mt.get("over", 0.0)), float(mt.get("clr", 0.0)),
								int(mt.get("rest", 0)), float(mt.get("mv", 0.0)), nv._walkable(mt.get("cell", Vector3i.ZERO)), mt.get("cell")]
					print("  WHO ", who)
					print("  UP %s leg %d fmode %d gd %.2f body_gap %.2f  nearest brood %.2f ant %.2f  tip-origin along up %.2f" % [where, f[2],
						int(floorf(mm.get_instance_custom_data(i).b / 16384.0)), gd, body_gap, bd_min, an_min, (tip - M.origin).dot(upw)])
				if not on:
					tally.foot_air = int(tally.get("foot_air", 0)) + 1
					tally["air:" + where] = int(tally.get("air:" + where, 0)) + 1
					_note(tally, "air", tip)
					if gd <= -1.35:
						tally.foot_air_far = int(tally.get("foot_air_far", 0)) + 1      # (no soil within reach at all)


static func _note(tally: Dictionary, kind: String, at: Vector3) -> void:
	var w: Dictionary = tally.get("foot_at", {})
	if not w.has(kind):
		w[kind] = []
	if (w[kind] as Array).size() < 6:
		w[kind].append(at)
	tally.foot_at = w


static func report(tally: Dictionary) -> String:
	var n := maxf(1.0, float(tally.get("feet", 0)))
	var s := "planted feet %d: in the air %.2f%% (of them far from any soil %.2f%%), in the soil %.2f%%, in the brood %.2f%%" % [
		int(tally.get("feet", 0)), 100.0 * float(tally.get("foot_air", 0)) / n, 100.0 * float(tally.get("foot_air_far", 0)) / n,
		100.0 * float(tally.get("foot_soil", 0)) / n, 100.0 * float(tally.get("foot_brood", 0)) / n]
	for where in ["floor", "slope", "wall/ceiling", "by the brood", "over the brood", "up on something"]:
		var m := float(tally.get("n:" + where, 0))
		if m > 0:
			s += "\n    %-16s %6d feet: air %5.1f%%  soil %5.1f%%  brood %5.1f%%" % [where, int(m), 100.0 * float(tally.get("air:" + where, 0)) / m,
				100.0 * float(tally.get("soil:" + where, 0)) / m, 100.0 * float(tally.get("brood:" + where, 0)) / m]
	for k in tally.get("foot_at", {}):
		s += "\n    %s e.g. at %s" % [k, tally.foot_at[k].slice(0, 3)]
	return s
