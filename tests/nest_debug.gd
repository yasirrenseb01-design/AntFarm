extends SceneTree
## Debug: watch a few diggers for a while and report what they do.

const NestVolume := preload("res://scripts/sim/nest_volume.gd")

func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var n := NestVolume.new()
	n.setup(rng)
	print("air ", n.air, " entrance dist ", n.dist[n.idx(n.entrance)], " chamber0 open ", n.is_open(Vector3i(n.chambers[0].c)), " dist ", n.dist[n.idx(Vector3i(n.chambers[0].c))])
	var bites := 0
	for t in 18000:
		var before := n.air
		n.step(t * 4, 8, 3000, 0.6)
		if t % 900 == 0:
			n.plan_chambers(60, 20 + t / 300)
		if t % 4500 == 0:
			var s := ""
			for d in n.diggers:
				s += "%s%s d=%d walk=%s | " % [d.cell, "C" if d.carry else "", n.dist[n.idx(d.cell)], n.walkable(d.cell)]
			print(t, " air ", n.air, " excavated ", n.excavated, "  ", s)
	# vertical slices at three depths into the block, and the open-space fraction per depth band
	for zz in [n.nz / 2 - 4, n.nz / 2, n.nz / 2 + 4]:
		print("--- slice z=", zz)
		for y in range(n.ny - 1, 20, -2):
			var row := ""
			for x in range(12, n.nx - 12):
				row += "." if n.rho[(zz * n.ny + y) * n.nx + x] < n.AIR else "#"
			print(row)
	quit()
