extends "res://scripts/sim/parts/sim_foragers.gd"
## Simulation, layer 5 of 11: the diggers' pellets carried out of the nest (_surface), the id -> worker map, foragers
## meeting head-on (_encounters) and whose turn it is to walk at a substep (_turn_of).
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
## keepers' observations; where on the ring: sim/mound.gd drop_distance, the crater the views draw - v0.12.10.]
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
			var gone: bool = w == null or w.dead
			if not job.get("dropped", false) and (gone or w.state != Ant.DUMP):
				# v0.12.31: its worker died outside (or was taken off the job) before setting the pellet down: the
				# job never came to "dropped" and the digger waited for ever, still counted as one of the diggers
				# (the keeper's colony of 812: 5 of its 6). The pellet falls by the way out it came up instead.
				_drop_at_hole(job)
				if not gone and w.carry == Ant.SOIL:
					w.carry = Ant.NONE
				job.dropped = true
				job.lost = true                        # (the digger does not wait for this worker to come back in)
			if job.get("dropped", false) and (gone or w.state == Ant.IN_NEST or job.get("lost", false)):
				_dumps.erase(wid)
				nest.finish_surface(d)
				if gone:
					d.wid = -1                         # another digging worker takes it on
			continue
		if w == null or w.dead or w.state != Ant.IN_NEST:
			nest.excavated += 1                        # no worker to carry it: dropped at the entrance (as before v0.11.57)
			nest.finish_surface(d)
			continue
		_send_out(w, Ant.DUMP)
		w.carry = Ant.SOIL
		var hi: int = nest.hole_index(d.cell)            # (out of the way out it came up, onto its own heap: nest_exits)
		var hole := nest_pos + nest.hole_off(hi) * (2.0 * nest.VOXEL_MM)
		w.pos = hole
		var a := rng.randf() * TAU
		var far := Mound.drop_distance(nest.hole_soil(hi), rng.randfn(0.0, 1.0))      # (on the crater's rim: sim/mound.gd)
		_dumps[wid] = {"to": hole + Vector2.from_angle(a) * far, "dig": int(d.id),
			"dropped": false, "hole": hi}
		w.ang = a
	if not _dumps.is_empty():
		_drop_orphans()


## A pellet set down by the way out it came up (sim_foragers._step_ant does the same at its spot on the ring).
func _drop_at_hole(job: Dictionary) -> void:
	var hv = job.get("hole", -1)
	var hi := int(hv) if hv is int or hv is float else -1
	if hi >= 0 and hi < nest.exits.size():
		nest.exits[hi].soil = int(nest.exits[hi].get("soil", 0)) + 1
	else:
		nest.excavated += 1


## Jobs no surfacing digger waits on any more (not made now; kept from a save of before v0.12.31 in case): a pellet
## still carried by a worker that is gone falls by its hole, and the job goes.
func _drop_orphans() -> void:
	var waited := {}
	for d in nest.diggers:
		if d.get("surfacing", false):
			waited[int(d.get("wid", -1))] = true
	var by_id := _worker_map()
	for wid in _dumps.keys():
		if waited.has(int(wid)):
			continue
		var w = by_id.get(int(wid))
		if w == null or w.dead or w.state != Ant.DUMP:
			var job: Dictionary = _dumps[wid]
			if not job.get("dropped", false):
				_drop_at_hole(job)
			_dumps.erase(wid)


# who stands in each 6 px square this round (_encounters): a square holds an ant while _meet_at[it] is this round's
# number (v0.12.3: a dictionary keyed by the square before - the same pairs, and one still for an ant off the box)
var _meet_at := PackedInt32Array()
var _meet_who: Array = []
var _meet_round := 0
var _meet_w := 0


## Two foragers meeting head-on stop for a moment and drum each other with their antennae
## (how Lasius check nestmate scent and pass on news of food).
func _encounters() -> void:
	var mw := int(WORLD.x / 6.0) + 2
	var mh := int(WORLD.y / 6.0) + 2
	if _meet_w != mw or _meet_at.size() != mw * mh:
		_meet_w = mw
		_meet_at.resize(mw * mh)
		_meet_at.fill(-1)
		_meet_who.resize(mw * mh)
		_meet_round = 0
	_meet_round += 1
	var rd := _meet_round
	var far := {}
	for a: Ant in outside:
		if a.busy > 0 or a.meet_cd > 0 or a.state == Ant.IN_NEST or a.state == Ant.DEFEND or a.state == Ant.DRAG:
			continue
		var kx := int(a.pos.x / 6.0)
		var ky := int(a.pos.y / 6.0)
		var o = null
		var k := ky * mw + kx
		var on := kx >= 0 and ky >= 0 and kx < mw and ky < mh
		if on:
			if _meet_at[k] == rd:
				o = _meet_who[k]
		else:
			o = far.get(Vector2i(kx, ky))
		if o == null:
			if on:
				_meet_at[k] = rd
				_meet_who[k] = a
			else:
				far[Vector2i(kx, ky)] = a
			continue
		if o.busy > 0 or a.pos.distance_squared_to(o.pos) > 16.0:
			continue
		if absf(wrapf(a.ang - o.ang, -PI, PI)) < 2.0:
			continue                      # walking the same way: no greeting
		var secs := rng.randi_range(12, 30)
		for p in [[a, o], [o, a]]:
			p[0].busy = secs
			p[0].act = 3
			p[0].ang = (p[1].pos - p[0].pos).angle()
			p[0].meet_cd = rng.randi_range(240, 600)
		if on:
			_meet_at[k] = -1
		else:
			far.erase(Vector2i(kx, ky))


# `outside` split by whose turn it is to walk at a substep (id % n), each in the order of `outside`; made again when
# `outside` changes (_out_ver: the colony tick builds it again, _send_out adds to it, the dead are taken out)
var _turns: Array = []
var _turns_key := []


func _turn_of(n: int, phase: int) -> Array:
	if _turns_key.size() != 3 or _turns_key[0] != _out_ver or _turns_key[1] != n or not is_same(_turns_key[2], outside):
		_turns_key = [_out_ver, n, outside]
		_turns = []
		for i in n:
			_turns.append([])
		for a: Ant in outside:
			_turns[a.id % n].append(a)
	return _turns[phase]
