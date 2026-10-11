extends SceneTree
## Every older save format must load and play on exactly as the colony would have.
## For each past version: run a colony, write it out in that version's shape, migrate it back up,
## and check both copies stay identical for two more days.
##   godot --headless --path . --script res://tests/migration_test.gd

const SIM := "res://scripts/sim/simulation.gd"
const MIGRATIONS := "res://scripts/sim/save_migrations.gd"


## The current save written as the v1 format (before castes and the creature list).
func _as_v1(d: Dictionary) -> Dictionary:
	var o: Dictionary = d.duplicate(true)
	o["version"] = 1
	for row in o.workers:
		row.pop_back()
	var spiders: Array = o.creatures.filter(func(c): return c.kind == "wolf_spider")
	var sp: Dictionary = spiders[0].duplicate() if not spiders.is_empty() else {}
	sp.erase("kind")
	o["spider"] = sp
	o.erase("creatures")
	return o


func _print(sim) -> String:
	var pos := 0.0
	for w in sim.workers:
		pos += w.pos.x + w.pos.y * 0.5 + w.age + w.caste
	return "tick %d workers %d eggs %d sugar %.6f hum %.6f pos %.4f creatures %d rng %d" % [sim.tick, sim.workers.size(),
		sim.eggs.size(), sim.sugar, sim.humidity, pos, sim.creatures.size(), sim.rng.state]


func _init() -> void:
	var Sim = load(SIM)
	var M = load(MIGRATIONS)
	var ok := true
	for seed_value in [5, 11]:
		var a = Sim.new()
		a.setup(seed_value, 14, false)
		# run until a spider is in the box so the creature conversion is exercised too
		var guard := 0
		while a.creatures.is_empty() and guard < a.TPD * 20:
			a.step()
			guard += 1
		var v1 := _as_v1(a.to_dict())
		var had_spider: bool = not v1.spider.is_empty()
		var b = Sim.new()
		b.from_dict(M.migrate(v1, Sim.SAVE_VERSION))
		for i in a.TPD * 2:
			a.step()
			b.step()
		var pa := _print(a)
		var pb := _print(b)
		print("seed %d  spider present at save: %s" % [seed_value, had_spider])
		print("  original: ", pa)
		print("  migrated: ", pb)
		ok = ok and pa == pb
	print("MIGRATION TEST PASSED" if ok else "MIGRATION TEST FAILED")
	quit(0 if ok else 1)
