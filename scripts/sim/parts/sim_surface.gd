extends "res://scripts/sim/parts/sim_foragers.gd"
## Simulation, layer 4 of 10: the diggers' pellets carried out of the nest (_surface) and the id -> worker map.
## Split from sim_foragers.gd in v0.12.2 (it had grown past ~500 lines).


# id -> worker, made again only when the workers change (born: appended; died: a new array) - v0.12.2: _surface made
# it every nest step, ~0.5 ms a time in a colony of 1,000
var _map_of: Array = []
var _map_n := -1
var _map := {}


func _worker_map() -> Dictionary:
	if not (is_same(_map_of, workers) and _map_n == workers.size()):
		_map_of = workers
		_map_n = workers.size()
		_map = {}
		for w in workers:
			_map[w.id] = w
	return _map


## The diggers and their workers (the keeper, 2026-10-27: "the simulation as the one truth"): each digger in the
## tunnels (nest.diggers) is one worker digging (TASK_DIG), kept by id ("wid"); one at the entrance with its pellet
## sends its worker out with it (Ant.DUMP) to set it down on the crater's ring and come back in, and only then digs on.
## [Lasius niger workers carry excavated soil out and drop it round the entrance, building the crater: field and
## keepers' observations; the ring 4.5-10 mm out matches the crater drawn.]
func _surface() -> void:
	if nest.diggers.is_empty():
		return
	var by_id := _worker_map()
	var taken := {}
	for d in nest.diggers:
		var wid := int(d.get("wid", -1))
		var w = by_id.get(wid)
		var keep: bool = w != null and not w.dead and (w.task == Ant.TASK_DIG or w.state == Ant.DUMP)
		if keep:
			taken[wid] = true
		elif wid >= 0 and not d.get("surfacing", false):
			d.wid = -1                                 # its worker gone or taken off digging: another takes it on
	for d in nest.diggers:
		if int(d.get("wid", -1)) < 0:
			var best = null
			for w in workers:
				if w.task == Ant.TASK_DIG and w.state == Ant.IN_NEST and not w.dead and not taken.has(w.id) and (best == null or w.id < best.id):
					best = w
			if best != null:
				d.wid = best.id
				taken[best.id] = true
		if not d.get("surfacing", false):
			continue
		var wid := int(d.get("wid", -1))
		var w = by_id.get(wid)
		var job = _dumps.get(wid)
		if job != null:
			if job.get("dropped", false) and (w == null or w.dead or w.state == Ant.IN_NEST):
				_dumps.erase(wid)
				nest.finish_surface(d)
			continue
		if w == null or w.dead or w.state != Ant.IN_NEST:
			nest.excavated += 1                        # no worker to carry it: dropped at the entrance (as before v0.11.57)
			nest.finish_surface(d)
			continue
		_send_out(w, Ant.DUMP)
		w.carry = Ant.SOIL
		w.pos = nest_pos
		var a := rng.randf() * TAU
		_dumps[wid] = {"to": nest_pos + Vector2.from_angle(a) * (9.0 + absf(rng.randfn(0.0, 1.0)) * 7.0), "dig": int(d.id),
			"dropped": false}
		w.ang = a
