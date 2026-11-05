extends SceneTree
## The faster daily count of the work left (v0.11.89) against the plain way it was worked out before: on nests grown a
## while, the same count, the same work face and the same steps from every voxel.
## Run: godot --headless --path . --script res://tests/work_left_test.gd

const Sim := preload("res://scripts/sim/simulation.gd")


func _plain_in_chamber(nest, ch: Dictionary) -> int:
	if not ch.get("open", true):
		return -1
	var n := 0
	var ax: Vector3 = nest.chamber_axes(ch)
	var m: float = maxf(ax.x, ax.z) * nest._lobe_max(ch) + 1.0
	var c: Vector3 = ch.c
	for y in range(maxi(nest.y_lo, floori(c.y - ax.y - 1.0)), mini(nest.ny, ceili(c.y + ax.y + 1.0) + 1)):
		for z in range(maxi(0, floori(c.z - m)), mini(nest.nz, ceili(c.z + m) + 1)):
			for x in range(maxi(0, floori(c.x - m)), mini(nest.nx, ceili(c.x + m) + 1)):
				var v := Vector3i(x, y, z)
				if nest.rho[nest.idx(v)] >= nest.AIR and not nest.is_hard(v) and (not nest.slab or z >= nest.nz - 3) and nest.chamber_q(Vector3(v), ch) <= 1.0:
					n += 1
	return n


func _plain_paths(nest) -> PackedInt32Array:
	var d := PackedInt32Array()
	d.resize(nest.nx * nest.hy() * nest.nz)
	d.fill(-1)
	if nest.work_at.x < 0 or not nest.inside(nest.work_at) or not nest.is_open(nest.work_at):
		return d
	d[nest.idx(nest.work_at)] = 0
	var q: Array[Vector3i] = [nest.work_at]
	var h := 0
	while h < q.size():
		var c: Vector3i = q[h]
		h += 1
		for dd in nest.DIRS:
			var n: Vector3i = c + dd
			if nest.inside(n) and nest.is_open(n) and d[nest.idx(n)] < 0:
				d[nest.idx(n)] = d[nest.idx(c)] + 1
				q.append(n)
	return d


func _check(what: String, nest) -> int:
	var bad := 0
	var chambers: Array = nest.chambers
	var counted := 0
	for ch in chambers:
		ch.erase("done")                # (looked at whatever it was found to be yesterday)
		var want := _plain_in_chamber(nest, ch)
		if want >= 0:
			var got: int = nest._work_in_chamber(ch, [1 << 30])
			counted += want
			if got != want:
				print("  FAIL %s: chamber at %s: %d voxels, plain way %d" % [what, ch.c, got, want])
				bad += 1
	nest.count_work_left()
	var plain := _plain_paths(nest)
	var reached := 0
	for i in plain.size():
		if plain[i] >= 0:
			reached += 1
	if plain != nest.work_dist:
		print("  FAIL %s: steps to the work face differ" % what)
		bad += 1
	print("  %s: %d chambers, %d planned voxels left, %d voxels reached from the face at %s" % [what, chambers.size(), counted, reached, nest.work_at])
	return bad


func _init() -> void:
	var bad := 0
	var looked := 0
	for case in [[1, false, "keeper"], [2, false, "keeper"], [3, false, "wild"], [4, true, "keeper"]]:
		var sim = Sim.new()
		sim.setup(case[0], 80, case[1], case[2])
		for t in 12 * sim.TPD:
			sim.step()
		bad += _check("%s seed %d%s" % [case[2], case[0], " glass" if case[1] else ""], sim.nest)
		# (and with every chamber planned bigger: plenty of soil left to find)
		for ch in sim.nest.chambers:
			ch.goal = float(ch.goal) + 2.5
		bad += _check("  planned bigger", sim.nest)
		looked += 1
	if bad == 0 and looked > 0:
		print("WORK LEFT PASSED")
	else:
		print("WORK LEFT FAILED")
	quit(1 if bad > 0 else 0)
