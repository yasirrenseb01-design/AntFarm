extends RefCounted
## (--feet, dev) legs under a body standing still, and legs stretched straight (the keeper, 2026-10-28: resting ants
## shake - some legs shift from spot to spot and back; and a leg seen stretched as if reaching its furthest).
## Staying put: the drawn body within 0.15 of where it was a second ago (its legs may step: what is measured), told
## apart by whether it is resting. Each still ant-frame with a foot moving more than SHIFT in the world is put down to why; and over a
## second (60 still frames) a foot going to and fro (two turns of direction or more, each SWING or more) is "shaking".
## Run with --fixed-fps 60 (a frame is a 60th of a second, as the keeper sees it).

const STILL_D := 0.01
const SHIFT := 0.03          # world units a frame (~2-3 pixels on screen zoomed in close)
const SWING := 0.04
const BODY_SWING := 0.02
const STRAIGHT := 0.97       # hip to ankle over the two segments' length: the leg straight (the IK's own limit)
const WIN := 60


static func track(i: int, M: Transform3D, fs: Array, tally: Dictionary) -> void:
	if fs.is_empty():
		return
	var info: Dictionary = fs[0][6]
	var walking := float(info.mv) >= 0.05
	var who := "resting" if int(info.act) == 1 else ("walking" if walking else "other still")
	var wst := "resting" if int(info.act) == 1 else "other"       # (staying put for a second: whatever its legs do)
	# legs stretched: planted feet whose leg is straight (or nearly) from the hip to the ankle
	for f in fs:
		if f[1]:
			tally["ex_n:" + who] = int(tally.get("ex_n:" + who, 0)) + 1
			var e := float(f[6].ext)
			if e >= STRAIGHT:
				tally["ex_s:" + who] = int(tally.get("ex_s:" + who, 0)) + 1
				var why := "feet mode %d" % mini(int(f[6].fm), 2)
				tally["exw:%s, %s" % [who, why]] = int(tally.get("exw:%s, %s" % [who, why], 0)) + 1
			elif e >= 0.93:
				tally["ex_a:" + who] = int(tally.get("ex_a:" + who, 0)) + 1
	# (the same ant last frame: the nearest drawn there - instances are not in the same order every frame)
	if int(tally.get("still_f", -1)) != int(tally.get("frames_f", 0)):
		tally.still_f = int(tally.get("frames_f", 0))
		tally.still_prev = tally.get("still_next", [])
		tally.still_next = []
	# (the same ant last frame: the one drawn within 0.15 of it, heading the same way. Two there - bodies drawn in one
	# another - and which was which is not known: left out, counted)
	var p: Array = []
	var n_near := 0
	for e in tally.still_prev:
		if (e[0] as Transform3D).origin.distance_to(M.origin) < 0.15 and (e[0] as Transform3D).basis.x.normalized().dot(M.basis.x.normalized()) > 0.9:
			n_near += 1
			p = e
	tally.dup_n = int(tally.get("dup_n", 0)) + 1
	if n_near > 1:
		tally.dup = int(tally.get("dup", 0)) + 1
		p = []
	var tips := []
	for f in fs:
		tips.append(f[0])
	var hd := M.basis.x.normalized()
	var still := false
	# (a window: the frames since it began staying put, and what to count for them - counted only once it has stayed a
	# whole second: an ant walking through counted its first frames of every window as standing)
	var win := {"pts": [], "inc": []}
	if p.size() == 4 and (p[2] as Array).size() == fs.size():
		var pm: Transform3D = p[0]
		var w0: Dictionary = p[3]
		still = (w0.pts as Array).is_empty() or ((w0.pts[0][0]) as Vector3).distance_to(M.origin) < 0.15
		if still:
			win = w0
			var inc: Array = win.inc
			if pm.origin.distance_to(M.origin) > STILL_D * M.basis.y.length() or pm.basis.x.normalized().dot(hd) < 0.9999:
				inc.append("sf_bm:" + wst)                   # (its body moved or turned this frame)
			inc.append("sf_n:" + wst)
			var why := ""
			for k in fs.size():
				var d := (fs[k][0] as Vector3).distance_to(p[2][k])
				if d > SHIFT:
					var a: Dictionary = p[1][k]
					var b: Dictionary = fs[k][6]
					why = _why(a, b, bool(fs[k][1]) and bool(a.get("pl", true)))
					break
			if why != "":
				inc.append("sf_s:" + wst)
				inc.append("sfw:%s, %s" % [wst, why])
			# (stepping in place: a planted foot lifted while the body stays)
			for k in fs.size():
				if bool(p[1][k].get("pl", true)) and not bool(fs[k][1]):
					inc.append("sf_lift:" + wst)
			if OS.has_environment("STILLDBG") and wst == "resting":
				var mvd := []
				for k in fs.size():
					mvd.append("%s%.2f" % ["P" if fs[k][1] else "s", (fs[k][0] as Vector3).distance_to(p[2][k])])
				inc.append("dbg:SD i %d at %s body %.3f mv %.2f u %.2f fm %d act %d  %s" % [i, M.origin.snapped(Vector3.ONE * 0.1), pm.origin.distance_to(M.origin),
					float(info.mv), float(info.u), int(info.fm), int(info.act), " ".join(mvd)])
	if still:
		(win.pts as Array).append([M.origin] + tips)
		if (win.pts as Array).size() >= WIN:
			for key in win.inc:
				if String(key).begins_with("dbg:"):
					print(String(key).substr(4))
				else:
					tally[key] = int(tally.get(key, 0)) + 1
			tally["sw_n:" + wst] = int(tally.get("sw_n:" + wst, 0)) + 1
			if _shakes(win.pts, 1, SWING):
				tally["sw_s:" + wst] = int(tally.get("sw_s:" + wst, 0)) + 1
			if _shakes(win.pts, 0, BODY_SWING, 1):
				tally["sw_b:" + wst] = int(tally.get("sw_b:" + wst, 0)) + 1
			win = {"pts": [], "inc": []}
	else:
		win = {"pts": [], "inc": []}
	var infos := []
	for f in fs:
		var d: Dictionary = (f[6] as Dictionary).duplicate()
		d.pl = f[1]
		infos.append(d)
	tally.still_next.append([M, infos, tips, win])


static func _why(a: Dictionary, b: Dictionary, planted: bool) -> String:
	if not planted:
		return "stepping in place (a tripod lifted: turned or pushed off its feet)"
	if a.act != b.act:
		return "its activity changed"
	if a.lo != b.lo:
		return "set down again (its tripod's record moved)"
	if a.fm != b.fm:
		return "how far its feet reach changed (feet mode %d -> %d)" % [int(a.fm), int(b.fm)]
	if a.br != b.br:
		return "the foothold search found ground elsewhere"
	if (((b.ts as Vector3) - (a.ts as Vector3)).length()) > 0.02:
		return "the foothold search moved it (same kind)"
	if absf(float(b.hy) - float(a.hy)) > 0.02:
		return "its height on the soil changed"
	return "the leg reaching it or not (IK)"


## Any foot (or the body: from = 0, n = 1) going to and fro over the window: along the way it moved most, two turns of
## direction or more of `step`.
static func _shakes(win: Array, from: int, step: float, n_of := -1) -> bool:
	for k in range(from, (win[0] as Array).size() if n_of < 0 else from + n_of):
		# (along the floor only: a foot lifted and set down again - one step - went up and back down, and counted)
		var o: Vector3 = win[0][k] * Vector3(1, 0, 1)
		var far := Vector3.ZERO
		for t in win:
			if ((t[k] as Vector3) * Vector3(1, 0, 1) - o).length() > far.length():
				far = (t[k] as Vector3) * Vector3(1, 0, 1) - o
		if far.length() < step:
			continue
		var ax := far.normalized()
		var v := []
		for t in win:
			v.append(((t[k] as Vector3) * Vector3(1, 0, 1) - o).dot(ax))
		var n := 0
		var ext: float = v[0]
		var dir := 0
		for x in v:
			if dir >= 0 and float(x) > ext:
				ext = x
				dir = 1
			elif dir <= 0 and float(x) < ext:
				ext = x
				dir = -1
			elif dir == 1 and ext - float(x) >= step:
				n += 1
				dir = -1
				ext = x
			elif dir == -1 and float(x) - ext >= step:
				n += 1
				dir = 1
				ext = x
		if n >= 2:
			if OS.has_environment("SHAKEDBG") and from == 1:
				print("SHAKE foot %d: %s" % [k - 1, " ".join(v.map(func(x): return "%.2f" % x))])
			return true
	return false


static func report(tally: Dictionary) -> String:
	var s := "
    DUP: ant-frames with another drawn within 0.15 of it, heading the same way (left out) %.3f%% of %d" % [100.0 * float(tally.get("dup", 0)) / maxf(1.0, float(tally.get("dup_n", 0))), int(tally.get("dup_n", 0))]
	for who in ["resting", "other", "other still", "walking"]:
		var n := float(tally.get("sf_n:" + who, 0))
		if n > 0:
			s += "\n    STILL %s: ant-frames with a leg shifting > %.2f %.2f%% of %d, feet lifted %.2f a second per ant, shaking (a foot to and fro within a second) %.2f%% of %d ant-seconds" % [
				who, SHIFT, 100.0 * float(tally.get("sf_s:" + who, 0)) / n, int(n), 60.0 * float(tally.get("sf_lift:" + who, 0)) / n,
				100.0 * float(tally.get("sw_s:" + who, 0)) / maxf(1.0, float(tally.get("sw_n:" + who, 0))), int(tally.get("sw_n:" + who, 0))]
			s += "
      its body moved or turned in a frame %.2f%%, the body to and fro within a second (>= %.2f) %.2f%%" % [
				100.0 * float(tally.get("sf_bm:" + who, 0)) / n, BODY_SWING, 100.0 * float(tally.get("sw_b:" + who, 0)) / maxf(1.0, float(tally.get("sw_n:" + who, 0)))]
			var ws := []
			for k in tally:
				if String(k).begins_with("sfw:" + who + ", "):
					ws.append([int(tally[k]), String(k).substr(6 + who.length())])
			ws.sort_custom(func(x, y): return x[0] > y[0])
			for w in ws:
				s += "\n      shifting: %5.1f%%  %s" % [100.0 * float(w[0]) / maxf(1.0, float(tally.get("sf_s:" + who, 0))), w[1]]
		var en := float(tally.get("ex_n:" + who, 0))
		if en > 0:
			s += "\n    STRETCH %s: planted legs straight (>= %.2f) %.2f%%, nearly (0.93-%.2f) %.2f%% of %d" % [who, STRAIGHT,
				100.0 * float(tally.get("ex_s:" + who, 0)) / en, STRAIGHT, 100.0 * float(tally.get("ex_a:" + who, 0)) / en, int(en)]
			for k in tally:
				if String(k).begins_with("exw:" + who + ", "):
					s += "\n      straight: %6d  %s" % [tally[k], String(k).substr(6 + who.length())]
	return s
