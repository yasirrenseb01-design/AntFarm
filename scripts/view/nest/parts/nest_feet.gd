extends "res://scripts/view/nest/parts/nest_lifecycle.gd"
## Nest view, layer 6 of 14 (split from parts/nest_bodies.gd in v0.11.33): the legs - the gait stepped as far as the
## drawn body really goes, the feet's reach, and where each tripod was set down (remembered: sent to the shader as feet_tex).


## Its legs step as far as the body it is drawn with has really gone this frame (call with the finished transform): the
## pushes and lifts after _smooth (kept apart, out of the walls, held behind another) move it off its point on the path,
## and stepping by the path its planted feet slid - walking on the spot against a nestmate, they jumped from frame to
## frame (feet_bench, 2026-10-24). Forward only: a body pushed sideways or back does not step its feet straight back.
## And the share of its stepping that is turning (the shader's gait_w turn, as the queen's): its planted feet sweep
## round the body as it turns - they slid straight back while the body turned over them.
func _step_gait(v: Dictionary, tr: Transform3D, delta: float, scale: float) -> void:
	var o: Vector3 = v.get("g_at", tr.origin)
	var d := tr.origin - o
	v.g_at = tr.origin
	var walked := 0.0
	if v.get("walks", false) and d.length() < 0.6:
		walked = maxf(0.0, d.dot(tr.basis.x.normalized()))
	var sweep := float(v.get("sweep", 0.0))
	v.gait = fmod(float(v.get("gait", 0.0)) + (walked + absf(sweep)) / (AntModel.stride_len(v.get("stride", 1.0)) * scale) * TAU, TAU * 64.0)
	var tshare := sweep / maxf(absf(sweep) + walked, 0.0001) if float(v.get("mv", 0.0)) > 0.05 else 0.0
	v.tshare = lerpf(float(v.get("tshare", 0.0)), tshare, minf(1.0, 6.0 * delta))
	# stopping, it finishes the step it is in: the tripod in the air sets its feet down (its feet are remembered where
	# they land - see _feet_rec - and one stopped mid-swing hung between two footholds)
	if walked + absf(sweep) < 0.0005:
		if float(v.get("g_left", -1.0)) < 0.0:
			var u := fposmod(float(v.gait) / TAU, 1.0)
			var duty := AntModel.duty(float(v.get("stride", 1.0)))
			v.g_left = (1.0 - u if u >= duty else (0.5 - u if u >= duty - 0.5 and u < 0.5 else 0.0)) * TAU + 0.02
		var st := minf(float(v.g_left), 3.0 * TAU * delta)
		v.gait = fmod(float(v.gait) + st, TAU * 64.0)
		v.g_left = float(v.g_left) - st
	else:
		v.g_left = -1.0


## Where each tripod's feet stand (the shader's feet_tex row, 8 texels: see ant_core.gdshaderinc): the body as it was
## when they were set down and the stride then, worked out again from what the shader gets (cu: its INSTANCE_CUSTOM) so
## the two agree on when a foot lands. A planted foot stays where it was set down in the world while the body walks,
## turns or is pushed over it; one left far behind (the body moved on without stepping) is set down again.
func _feet_rec(v: Dictionary, tr: Transform3D, cu: Color) -> PackedFloat32Array:
	var gait := cu.r - floorf(cu.r / 512.0) * 512.0
	var cw := cu.a
	var tcode := floorf(cw / 1000.0)
	var tws := fmod(tcode, 17.0) / 16.0 * (-1.0 if tcode >= 17.0 else 1.0)
	cw -= tcode * 1000.0
	var ss := floorf(cw) / 100.0
	var mv := cw - floorf(cw)
	if ss < 0.01:
		ss = 1.0
		mv = cw
	var fmode := floorf(cu.b / 16384.0)
	var duty := AntModel.duty(ss)
	var amp := AntModel.STRIDE_A * AntModel.K * ss * mv
	var fresh := int(v.get("f_frame", -9)) != _mate_frame - 1
	v.f_frame = _mate_frame
	if fresh or not v.has("f_at"):
		v.f_at = [tr, tr]
		v.f_p = [Vector3.ZERO, Vector3.ZERO]
		v.f_u = [-1.0, -1.0]
	var sc := tr.basis.x.length()
	var far := AntModel.stride_len(ss) * sc + 0.3
	var out := PackedFloat32Array()
	out.resize(32)
	for g in 2:
		var u := fposmod((gait + g * PI) / TAU, 1.0)
		var pu: float = v.f_u[g]
		var stance := u < duty
		var at: Transform3D = v.f_at[g]
		if pu < 0.0:
			# (just come on screen: its feet where they would be now)
			v.f_at[g] = tr
			v.f_p[g] = Vector3(amp * (1.0 - 2.0 * u / duty) if stance else -amp, tws, fmode)
		elif stance and (pu >= duty or u < pu - 0.0001 or at.origin.distance_to(tr.origin) > far):
			v.f_at[g] = tr                                   # (set down: from a swing, or again, left behind)
			v.f_p[g] = Vector3(amp * (1.0 - 2.0 * u / duty), tws, fmode)
		v.f_u[g] = u
		var x: Transform3D = v.f_at[g]
		var p: Vector3 = v.f_p[g]
		var k := g * 16
		out[k] = x.basis.x.x; out[k + 1] = x.basis.y.x; out[k + 2] = x.basis.z.x; out[k + 3] = x.origin.x
		out[k + 4] = x.basis.x.y; out[k + 5] = x.basis.y.y; out[k + 6] = x.basis.z.y; out[k + 7] = x.origin.y
		out[k + 8] = x.basis.x.z; out[k + 9] = x.basis.y.z; out[k + 10] = x.basis.z.z; out[k + 11] = x.origin.z
		out[k + 12] = p.x; out[k + 13] = p.y; out[k + 14] = p.z
		out[k + 15] = 0.0 if stance else 1.0 + (u - duty) / (1.0 - duty)
	return out


## The feet records of this frame's drawn ants (_feet_rec, in instance order; those with none: -1) up to the shader.
func _upload_feet(fts: PackedFloat32Array, n: int) -> void:
	var h := maxi(64, nearest_po2(maxi(n, 1)))
	var have := fts.size()
	fts.resize(h * 32)
	for i in range(have / 32, n):
		fts[i * 32 + 15] = -1.0
		fts[i * 32 + 31] = -1.0
	_feet_buf = fts
	var img := Image.create_from_data(8, h, false, Image.FORMAT_RGBAF, fts.to_byte_array())
	if _feet_tex == null or _feet_tex.get_height() != h:
		_feet_tex = ImageTexture.create_from_image(img)
		for m in [_ant_shader_mat, _sel_mat]:
			m.set_shader_parameter("feet_tex", _feet_tex)
			m.set_shader_parameter("feet_on", true)
	else:
		_feet_tex.update(img)


func _custom(v: Dictionary, act: int) -> Color:
	var clock: float = v.get("anim", 0.0)
	v.vact = AntModel.act_step(v.get("vact", Vector3(-1, 0, 0)), act, clock)    # poses ease into one another
	var gx := AntModel.gait_x(v.get("gait", 0.0), v.get("bend", Vector2.ZERO))       # (and the waist and neck bent to the ground)
	var cz := AntModel.clock_z(clock, v.get("lat", 0.0))                              # (and bent sideways round a turn)
	cz += 16384.0 * float(_feet_mode(v))
	if v.get("fed", false):
		return Color(gx, AntModel.act_y(v.vact, clock) + 100.0, cz, AntModel.gait_w(v.get("mv", 0.0), v.get("stride", 1.0), v.get("tshare", 0.0)))   # crop full of honeydew
	return Color(gx, AntModel.act_y(v.vact, clock), cz, AntModel.gait_w(v.get("mv", 0.0), v.get("stride", 1.0), v.get("tshare", 0.0)))


## Where its feet stand (the shader's z / 16384): 0 on the floor, 1 on a nestmate's back (not reaching for the soil),
## 2-5 its body lifted off the floor - on the brood, pushed clear of the soil, at a shaft's lip - its feet reaching
## 0.6-0.9 down (0.5 on the floor). With some hold-off and eased, so the reach never flips from frame to frame (the
## feet jumped: the keeper saw them shake, 2026-10-22).
func _feet_mode(v: Dictionary) -> int:
	var on_back: bool = v.get("fback", false)
	var ov := float(v.get("over", 0.0))
	if v.has("over_on") and ov > 0.35:
		on_back = true
	elif not v.has("over_on") or ov < 0.2:
		on_back = false
	v.fback = on_back
	var lifted := float(v.get("clr", 0.0)) if on_back else maxf(ov, float(v.get("clr", 0.0)))    # (the back under it is in the foot map)
	if v.has("xf"):
		# (and by what is really under it - every fourth frame, kept between)
		if (_mate_frame + int(v.get("wid", v.get("id", 0)))) % 4 == 0 or not v.has("floor_gap"):
			v.floor_gap = _gap_under(v.xf)
		lifted = maxf(lifted, float(v.floor_gap))
	var want := clampf(0.5 + lifted, 0.5, 1.1)
	v.freach = move_toward(float(v.get("freach", 0.5)), want, 1.2 * get_process_delta_time())
	return 1 + roundi((float(v.freach) - 0.5) / 0.1) if float(v.freach) > 0.55 else 0


## How far below the body the floor is (along its up, up to 1.5): where the feet's own map of the floor (the soil and the
## brood on it, nest_scene._foot_rho, read as the shader reads it) turns solid.
func _gap_under(xf: Transform3D) -> float:
	# (as the shader's ground_dy: from just above the feet down to the first solid, or up out of it)
	var up := xf.basis.y.normalized()
	var fw := xf.origin
	var prev := 0.5
	var dprev := _foot_at(fw + up * prev)
	if dprev >= 0.5:
		return 0.0                             # (the floor rises here: not lifted)
	for i in range(1, 9):
		var s := 0.5 - 0.25 * i
		var d := _foot_at(fw + up * s)
		if d >= 0.5:
			return maxf(0.0, -lerpf(prev, s, clampf((0.5 - dprev) / maxf(d - dprev, 0.001), 0.0, 1.0)))
		prev = s
		dprev = d
	return 1.5


## The feet's floor map at p, as the shader samples it (trilinear over the voxels; 0 open, 1 solid).
func _foot_at(p: Vector3) -> float:
	# (the feet's map, unless the soil was just taken in deeper and it is not laid out again yet)
	var rho: PackedByteArray = _foot_rho if _foot_rho.size() == nest.rho.size() else nest.rho
	var nx: int = nest.nx
	var ny: int = nest.ny
	var nz: int = nest.nz
	var y_lo: int = nest.y_lo
	var x0 := floori(p.x)
	var y0 := floori(p.y)
	var z0 := floori(p.z)
	var fx := p.x - x0
	var fy := p.y - y0
	var fz := p.z - z0
	var v := 0.0
	for dz in 2:
		var z := clampi(z0 + dz, 0, nz - 1)
		var wz := fz if dz == 1 else 1.0 - fz
		for dy in 2:
			var y := clampi(y0 + dy, y_lo, ny - 1)
			var wy := (fy if dy == 1 else 1.0 - fy) * wz
			var row := (z * (ny - y_lo) + y - y_lo) * nx
			v += wy * ((1.0 - fx) * rho[row + clampi(x0, 0, nx - 1)] + fx * rho[row + clampi(x0 + 1, 0, nx - 1)])
	return v / 255.0


const _NEAR := [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
	Vector3i(1, 0, 1), Vector3i(1, 0, -1), Vector3i(-1, 0, 1), Vector3i(-1, 0, -1), Vector3i(0, 1, 0), Vector3i(0, -1, 0)]


## How many body parts of nestmates still stand on eggs, larvae or cocoons: dev check (--trace).
var _overlap_who := []
