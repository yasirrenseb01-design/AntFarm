extends SceneTree
## (dev) The dug nest of grown test colonies (user://growtest/<name>/, read only) drawn as a map: the open space
## seen from the front (x across, depth down) and from above (x across, z down), shaded by how deep or how far
## back it lies, chambers ringed. To compare how alike nests come out. One png per colony in shots/layout/.
##   godot --headless --path . --script res://tests/_layout_map.gd -- mine2 mine3 lay_new_12:2 ...

const SIM := "res://scripts/sim/simulation.gd"
const STORE := "res://scripts/game/save_store.gd"
const MIGRATIONS := "res://scripts/sim/save_migrations.gd"
const S := 6                    # pixels a voxel


func _init() -> void:
	var store = load(STORE)
	for arg in OS.get_cmdline_user_args():
		# <name> or <name>:<year> (the slot year_run.gd saved at the end of that year)
		var name := String(arg).get_slice(":", 0)
		var slot := int(String(arg).get_slice(":", 1)) if String(arg).contains(":") else 1
		store.base = "user://growtest/%s/" % name.validate_filename()
		var data: Dictionary = store.load_slot(slot)
		if data.is_empty():
			print("%s: no save" % name)
			continue
		var sim = load(SIM).new()
		sim.from_dict(load(MIGRATIONS).migrate(data.sim, sim.SAVE_VERSION))
		var nest = sim.nest
		var nx: int = nest.nx
		var ny: int = nest.ny
		var nz: int = nest.nz
		var img := Image.create((nx * 2 + 3) * S, maxi(ny, nz) * S, false, Image.FORMAT_RGB8)
		img.fill(Color(0.36, 0.25, 0.16))
		# front: x across, y down (top of the block at the top); the nearest open cell along z, darker further back
		for x in nx:
			for y in ny:
				var hit := -1
				for z in nz:
					if nest.is_open(Vector3i(x, y, z)):
						hit = z
						break
				if hit >= 0:
					var k := 1.0 - 0.6 * float(hit) / float(nz)
					img.fill_rect(Rect2i(x * S, (ny - 1 - y) * S, S, S), Color(0.98, 0.88, 0.66) * k)
		# above: x across, z down; the highest open cell along y, darker deeper
		var ox := (nx + 3) * S
		for x in nx:
			for z in nz:
				var hit := -1
				for y in range(ny - 1, -1, -1):
					if nest.is_open(Vector3i(x, y, z)):
						hit = y
						break
				if hit >= 0:
					var k := 0.35 + 0.65 * float(hit) / float(ny)
					img.fill_rect(Rect2i(ox + x * S, z * S, S, S), Color(0.98, 0.88, 0.66) * k)
		# open cells outside today's plan (no chamber, shaft or widened entrance shaft there - the founding cell and
		# the first narrow shaft count too): only counted
		var unplanned := 0
		for x in nx:
			for y in ny:
				for z in nz:
					var v := Vector3i(x, y, z)
					if nest.is_open(v) and y < ny - 1 and nest._plan_at(v) == 0:
						unplanned += 1
		print("%s: open cells outside the plan %d of %d" % [name, unplanned, nest.air])
		# chambers: their centres (queen's red, brood blue)
		for ch in nest.chambers:
			var c: Vector3 = ch.c
			var col := Color(0.9, 0.2, 0.2) if ch.get("kind", "") == "queen" else Color(0.2, 0.5, 1.0)
			img.fill_rect(Rect2i(int(c.x) * S - 3, (ny - 1 - int(c.y)) * S - 3, 7, 7), col)
			img.fill_rect(Rect2i(ox + int(c.x) * S - 3, int(c.z) * S - 3, 7, 7), col)
		var path := "res://shots/layout/%s_y%d.png" % [name, slot]
		img.save_png(path)
		print("%s: day %s workers %d chambers %d traits depth %s spread %s entrance %s -> %s" % [name, str(sim.summary().day), sim.workers.size(),
			nest.chambers.size(), str(nest.depth_k), str(nest.spread_k), nest.entrance, path])
	quit()
