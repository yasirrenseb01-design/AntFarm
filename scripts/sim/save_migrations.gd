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
			2:
				_v2_to_v3(d)
			3:
				_v3_to_v4(d)
			4:
				_v4_to_v5(d)
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


## v0.6.0: ants remember the enemy they fight and their injuries; creatures get ids and health;
## the alarm pheromone field starts empty.
static func _v2_to_v3(d: Dictionary) -> void:
	for row in d.workers:
		row.append(0)
		row.append(0.0)
	var id := 1
	for c in d.creatures:
		c["id"] = id
		c["hp"] = 1.0
		c["held"] = 0
		id += 1
	d["next_cid"] = id
	d["alarm"] = null


## v0.7.0: scenarios and seasons. Colonies saved before then lived in an indoor formicarium, so they
## become "keeper" colonies (the room climate they always had); their queen counts as rested.
static func _v3_to_v4(d: Dictionary) -> void:
	d["scenario"] = "keeper"
	d["start_doy"] = 205
	d["cold_days"] = 0
	d["fridge_on"] = false
	d["fat"] = 0.0
	d.climate["scenario"] = "keeper"
	d.climate["fridge"] = 0.0
	d.queen["rested"] = 1.0


## v0.7.1: the colony keeps a running account of the sugar it brings in and eats (laying follows it).
## Start it as if income had just covered the colony's needs.
static func _v4_to_v5(d: Dictionary) -> void:
	d["sugar_spend"] = 7.0 * (d.workers.size() * 0.08 + 0.5)
	d["sugar_income"] = d.sugar_spend * 1.5
