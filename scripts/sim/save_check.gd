extends RefCounted
## Is a save safe to hand to Simulation.from_dict()? (PART EA-R R8: a save is a file on the keeper's disk, and anyone or
## anything can change it. A value of the wrong kind or an array of the wrong length would stop the loading half way
## with a script error, or leave the colony in pieces.) The save, once migrated, is compared with a colony the game
## sets up itself: every value it has must be there with the same kind of value, every list a list of the same kind of
## thing, and the sizes the loader trusts (the voxels of the nest, the pheromone grids, an ant's row) must add up.
## problem() is "" for a save that can be loaded, else what is wrong with it (for the log).

const Sim := preload("res://scripts/sim/simulation.gd")
const Ant := preload("res://scripts/sim/ant.gd")

const MAX_ITEMS := 200000          # longest list (ants, eggs, journal lines ...) a save may hold
const MAX_SIDE := 1024             # voxels along one side of the nest
const MAX_VOXELS := 8000000

## read with a default by the loader (saves older than these keys)
const OPTIONAL := ["sim.water", "sim.nest.entrance_r", "sim.nest.work_left", "sim.nest.work_at", "sim.nest.work_dist",
	"sim.nest.entrance_done", "sim.plot_seed", "sim.nest_pos", "sim.midden_pos", "sim.traits", "sim.nest.soil",
	"sim.brood_at", "sim.queen_at", "sim.queen_stay", "sim.ch_mean"]

static var _ref := {}              # a colony as the game sets one up, made once


static func problem(d) -> String:
	if not d is Dictionary:
		return "not a dictionary"
	if _ref.is_empty():
		var s = Sim.new()
		s.setup(1, 14, false, "keeper")
		_ref = s.to_dict()
	var why := _like(d, _ref, "sim", true)
	if why != "":
		return why
	return _sizes(d)


## v is the same kind of value as r (numbers count as one kind; a list is checked item by item against r's first item;
## strict: every key r has, v has).
static func _like(v, r, path: String, strict: bool) -> String:
	if r == null or (v == null and path == "sim.alarm") or path == "sim.workers":     # (alarm: none in old saves; the ants: _sizes())
		return ""
	if r is Dictionary:
		if not v is Dictionary:
			return "%s: not a dictionary" % path
		for k in r:
			if v.has(k):
				var why := _like(v[k], r[k], "%s.%s" % [path, k], strict)
				if why != "":
					return why
			elif strict and not "%s.%s" % [path, k] in OPTIONAL:
				return "%s.%s: missing" % [path, k]
		return ""
	if r is int or r is float:
		return "" if v is int or v is float else "%s: not a number" % path
	if r is String or r is StringName:
		return "" if v is String or v is StringName else "%s: not text" % path
	if r is Array:
		if not v is Array:
			return "%s: not a list" % path
		if v.size() > MAX_ITEMS:
			return "%s: %d items" % [path, v.size()]
		if r.is_empty():
			return ""
		for i in v.size():
			var why := _like(v[i], r[0], "%s[%d]" % [path, i], false)
			if why != "":
				return why
		return ""
	if typeof(v) != typeof(r):
		return "%s: %s, not %s" % [path, type_string(typeof(v)), type_string(typeof(r))]
	if v is PackedByteArray or v is PackedInt32Array or v is PackedInt64Array or v is PackedFloat32Array or v is PackedFloat64Array:
		if v.size() > MAX_VOXELS:
			return "%s: %d items" % [path, v.size()]
	return ""


## The sizes Simulation.from_dict() and the nest trust without looking.
static func _sizes(d: Dictionary) -> String:
	var n: Dictionary = d.nest
	for k in ["nx", "ny", "nz"]:
		if not n[k] is int or n[k] < 1 or n[k] > MAX_SIDE:
			return "nest.%s: %s" % [k, n[k]]
	var cells: int = n.nx * n.ny * n.nz
	if cells > MAX_VOXELS:
		return "nest: %d voxels" % cells
	for k in ["rho", "dug_at", "dist"]:
		if n[k].size() != cells:
			return "nest.%s: %d voxels, not %d" % [k, n[k].size(), cells]
	var wd = n.get("work_dist", PackedInt32Array())
	if not wd.is_empty() and wd.size() != cells:
		return "nest.work_dist: %d voxels, not %d" % [wd.size(), cells]
	var grid: int = _ref.home.val.size()
	for f in ["home", "food", "alarm"]:
		if f == "alarm" and d.alarm == null:
			continue
		for k in ["val", "stamp"]:
			if d[f][k].size() != grid:
				return "%s.%s: %d cells, not %d" % [f, k, d[f][k].size(), grid]
	# an ant is a row of Sim.ANT_FIELDS, each the kind of value an ant keeps there
	var ant := Ant.new()
	if not d.workers is Array or d.workers.size() > MAX_ITEMS:
		return "workers: not a list"
	for i in d.workers.size():
		var row = d.workers[i]
		if not row is Array or row.size() != Sim.ANT_FIELDS.size():
			return "workers[%d]: not a row of %d" % [i, Sim.ANT_FIELDS.size()]
		for j in row.size():
			var why := _like(row[j], ant.get(Sim.ANT_FIELDS[j]), "workers[%d].%s" % [i, Sim.ANT_FIELDS[j]], true)
			if why != "":
				return why
	for i in d.outside.size():
		if not d.outside[i] is int:
			return "outside[%d]: not an id" % i
	if d.duty_rng.is_empty() or d.duty_rng.size() > 2:
		return "duty_rng: %d numbers" % d.duty_rng.size()
	return ""
