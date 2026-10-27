extends SceneTree
## Dev probe (not in check.ps1): how often what the nest view is given to draw does not add up - workers set to
## dig vs the simulation's diggers (matched by order in the view), workers inside over the 250 drawn, corpses kept
## inside. Runs a colony from user://growtest/<name>/saves/slot1 for some game days.
##   godot --headless --path . --script res://tests/_sync_probe.gd -- <name> <days>

const SIM := "res://scripts/sim/simulation.gd"
const STORE := "res://scripts/game/save_store.gd"
const MIGRATIONS := "res://scripts/sim/save_migrations.gd"
const Ant := preload("res://scripts/sim/ant.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var sim = load(SIM).new()
	if args[0].begins_with("new"):
		sim.setup(int(args[2]) if args.size() > 2 else 1, 14, false, "wild")      # ("new": a young garden colony, growing and digging)
	else:
		var store = load(STORE)
		store.base = "user://growtest/%s/" % args[0]
		var data: Dictionary = store.load_slot(1)
		sim.from_dict(load(MIGRATIONS).migrate(data.sim, sim.SAVE_VERSION))
	var days := float(args[1])
	var n := 0
	var c := {"dig_more_workers": 0, "dig_more_bodies": 0, "dig_task_outside": 0, "over_250": 0, "corpses_inside": 0}
	var worst := {"dig_gap": 0, "inside": 0, "corpses": 0}
	var id_shift := 0
	var last_pairs := {}
	var ids_was := {}
	var spawned := 0
	var task_to_dig := 0
	var task_was := {}
	for t in int(days * sim.TPD):
		sim.step()
		if t % 120 != 0:
			continue
		n += 1
		var dig_in := 0
		var dig_out := 0
		var inside := 0
		var dws := []
		for w in sim.workers:
			if w.state == Ant.IN_NEST:
				inside += 1
			if w.task == Ant.TASK_DIG:
				dws.append(w.id)
				if w.state == Ant.IN_NEST:
					dig_in += 1
				else:
					dig_out += 1
		var bodies: int = sim.nest.diggers.size()
		if dig_in > bodies:
			c.dig_more_workers += 1
		if bodies > dig_in:
			c.dig_more_bodies += 1
		if dig_out > 0:
			c.dig_task_outside += 1
		worst.dig_gap = maxi(worst.dig_gap, absi(dig_in - bodies))
		if inside - dig_in > 250:
			c.over_250 += 1
		worst.inside = maxi(worst.inside, inside)
		if sim.corpses_inside > 0:
			c.corpses_inside += 1
		worst.corpses = maxi(worst.corpses, int(sim.corpses_inside))
		# the view pairs digger bodies with dig workers by order of id: a body that changes worker
		dws.sort()
		var ds: Array = sim.nest.diggers.map(func(d): return d.id)
		ds.sort()
		var pairs := {}
		for i in mini(ds.size(), dws.size()):
			pairs[ds[i]] = dws[i]
		for b in pairs:
			if last_pairs.has(b) and last_pairs[b] != pairs[b]:
				id_shift += 1
		last_pairs = pairs
		for i in ds:
			if not ids_was.is_empty() and not ids_was.has(i):
				spawned += 1                 # a digger body that appears (at a chamber's middle: nest_volume._spawn_digger)
		ids_was.clear()
		for i in ds:
			ids_was[i] = true
		ids_was[-1] = true
		for w in sim.workers:
			if task_was.get(w.id, -1) != Ant.TASK_DIG and task_was.has(w.id) and w.task == Ant.TASK_DIG:
				task_to_dig += 1             # its nestmate body is dropped where it was
			task_was[w.id] = w.task
	print("samples %d (every 2 game minutes over %.1f days), workers %d" % [n, days, sim.workers.size()])
	for k in c:
		print("  %s: %d (%.1f%%)" % [k, c[k], 100.0 * c[k] / n])
	print("  worst: ", worst)
	print("  digger bodies that changed worker (by-order pairing): %d" % id_shift)
	print("  digger bodies appearing: %d, workers turned diggers: %d" % [spawned, task_to_dig])
	quit()
