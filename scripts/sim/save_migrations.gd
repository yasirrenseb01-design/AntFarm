extends RefCounted
## Brings a saved colony from an older version of the game up to the current format, one step at a
## time, so a keeper's colony survives every update. When the save format changes:
##   1. raise SAVE_VERSION in parts/sim_base.gd,
##   2. add a step `_vN_to_vN+1(d)` here and call it from migrate(),
##   3. extend tests/migration_test.gd.
## Each step only edits the plain dictionary that Simulation.to_dict() produced.


static func migrate(d: Dictionary, target: int) -> Dictionary:
	var v := int(d.get("version", 1))
	while v < target:
		match v:
			1:
				_v1_to_v2(d)
		v += 1
		d["version"] = v
	return d


## v0.5.8: every ant gets a caste (all were workers), and the single spider slot becomes the list
## of creatures in the outworld.
static func _v1_to_v2(d: Dictionary) -> void:
	for row in d.workers:
		row.append(0)
	var spider: Dictionary = d.get("spider", {})
	var creatures := []
	if not spider.is_empty():
		var c := spider.duplicate()
		c["kind"] = "wolf_spider"
		creatures.append(c)
	d["creatures"] = creatures
	d.erase("spider")
