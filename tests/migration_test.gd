extends SceneTree
## Saves written by older versions of the game (tests/fixtures/save_vN.antfarm, made by that version's
## code) must still load after migration, keep their colony, and play on — and a migrated colony
## must save and reload exactly like a fresh one. Add a fixture for every new save format.
##   godot --headless --path . --script res://tests/migration_test.gd

const SIM := "res://scripts/sim/simulation.gd"
const MIGRATIONS := "res://scripts/sim/save_migrations.gd"
const FIXTURES := ["res://tests/fixtures/save_v1.antfarm", "res://tests/fixtures/save_v2.antfarm", "res://tests/fixtures/save_v3.antfarm",
	"res://tests/fixtures/save_v4.antfarm"]


func _read(path: String) -> Dictionary:
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {}
	var d = f.get_var()
	f.close()
	return d


func _print(sim) -> String:
	var pos := 0.0
	for w in sim.workers:
		pos += w.pos.x + w.pos.y * 0.5 + w.age + w.caste + w.hurt
	return "tick %d workers %d eggs %d sugar %.6f hum %.6f pos %.4f creatures %d rng %d" % [sim.tick, sim.workers.size(),
		sim.eggs.size(), sim.sugar, sim.humidity, pos, sim.creatures.size(), sim.rng.state]


func _init() -> void:
	var Sim = load(SIM)
	var M = load(MIGRATIONS)
	var ok := true
	for path in FIXTURES:
		var data := _read(path)
		if data.is_empty():
			print("missing fixture ", path)
			ok = false
			continue
		var d: Dictionary = data.sim
		var from_v := int(d.get("version", 1))
		var workers: int = d.workers.size()
		var had_spider: bool = not d.get("spider", {}).is_empty() or not d.get("creatures", []).is_empty()
		var sim = Sim.new()
		sim.from_dict(M.migrate(d, Sim.SAVE_VERSION))
		var kept: bool = sim.workers.size() == workers and (sim.creatures.size() > 0) == had_spider
		# play on for two days (the spider gets its fight), then a save/load round trip must match
		for i in sim.TPD * 2:
			sim.step()
		var copy = Sim.new()
		copy.from_dict(bytes_to_var(var_to_bytes(sim.to_dict())))     # as written to and read from a file
		for i in sim.TPD:
			sim.step()
			copy.step()
		var same: bool = _print(sim) == _print(copy)
		print("%s  v%d -> v%d  workers kept %s  spider kept %s  plays on + round trip identical %s" % [path.get_file(), from_v,
			Sim.SAVE_VERSION, kept, had_spider, same])
		print("   ", _print(sim))
		ok = ok and kept and same
	print("MIGRATION TEST PASSED" if ok else "MIGRATION TEST FAILED")
	quit(0 if ok else 1)
