extends SceneTree
## Dev (v0.12.10): where the diggers set their pellets down against the crater the views draw (Mound.size), how long a
## trip out takes, and how fast the colony digs - before/after a change to where they drop it.
##   godot --headless --path . --script res://tests/_dump_ring.gd -- <growtest name|new> <slot|workers> <days> [seed]
## "new": a new colony of <workers> (setup, keeper, seed); else a grown one, read only, from user://growtest/<name>/.

const Ant := preload("res://scripts/sim/ant.gd")


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var Mound = load("res://scripts/sim/mound.gd") if ResourceLoader.exists("res://scripts/sim/mound.gd") \
			else load("res://scripts/view/common/mound.gd")
	var Sim = load("res://scripts/sim/simulation.gd")
	var s = Sim.new()
	if a[0] == "new":
		s.setup(int(a[3]) if a.size() > 3 else 3, int(a[1]), false, "keeper")
	else:
		var Store = load("res://scripts/game/save_store.gd")
		Store.base = "user://growtest/%s/" % a[0]
		var d: Dictionary = Store.load_slot(int(a[1]))
		s.from_dict(d.sim)
	var days := float(a[2])
	var n := int(days * s.TPD)
	var ex0: int = s.nest.excavated
	var air0 := "%d / %d" % [s.nest.air, s.target_air()]
	var r0: float = Mound.size(ex0).y * 3.0
	var drops: Array = []                 # distance from the entrance / the ring's radius then
	var seen := {}
	var out_at := {}
	var trips: Array = []
	var stuck := 0
	for i in n:
		s.step()
		var by_id: Dictionary = s._worker_map()
		for wid in s._dumps:
			var job: Dictionary = s._dumps[wid]
			var key := "%d:%d" % [wid, int(job.dig)]
			var w = by_id.get(wid)
			if w == null:
				continue
			if not out_at.has(key):
				out_at[key] = i
			if job.dropped and not seen.has(key):
				seen[key] = true
				var r: float = Mound.size(s.nest.excavated).y * 3.0
				drops.append(Vector2(w.pos.distance_to(s.nest_pos), r))
			if not job.dropped and i - int(out_at[key]) == 3000:
				stuck += 1
		for key in out_at.keys():
			var wid := int(key.split(":")[0])
			if not s._dumps.has(wid) or "%d:%d" % [wid, int(s._dumps[wid].dig)] != key:
				trips.append(i - int(out_at[key]))
				out_at.erase(key)
	var ds: Array = drops.map(func(v): return v.x)
	ds.sort()
	var rel: Array = drops.map(func(v): return v.x / v.y)
	rel.sort()
	trips.sort()
	var q := func(arr: Array, f: float) -> float: return 0.0 if arr.is_empty() else float(arr[int(f * (arr.size() - 1))])
	var r1: float = Mound.size(s.nest.excavated).y * 3.0
	print("workers %d  pellets dumped %d in %.1f days (%.1f a day)  ring radius %.1f -> %.1f px (%.1f -> %.1f mm)" % [
		s.workers.size(), s.nest.excavated - ex0, days, (s.nest.excavated - ex0) / days, r0, r1, r0 * 0.5, r1 * 0.5])
	print("nest air / target  %s -> %d / %d" % [air0, s.nest.air, s.target_air()])
	print("drop distance px  p10 %.1f  median %.1f  p90 %.1f  max %.1f   (n %d)" % [q.call(ds, 0.1), q.call(ds, 0.5),
		q.call(ds, 0.9), q.call(ds, 1.0), ds.size()])
	print("drop / ring radius  p10 %.2f  median %.2f  p90 %.2f   inside 0.5 r: %.0f%%" % [q.call(rel, 0.1), q.call(rel, 0.5),
		q.call(rel, 0.9), 100.0 * rel.filter(func(x): return x < 0.5).size() / maxf(1.0, rel.size())])
	print("trip out and back (ticks)  median %.0f  p90 %.0f  max %.0f   (n %d)  out over 3000 ticks: %d" % [
		q.call(trips, 0.5), q.call(trips, 0.9), q.call(trips, 1.0), trips.size(), stuck])
	quit()
