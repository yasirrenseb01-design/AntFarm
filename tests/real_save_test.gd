extends SceneTree
## Loads the keeper's real colony from a copy in user://sandbox/ (never the real save), runs it on
## for a day and prints a fingerprint. Run before and after a refactor: the output must not change.
##   godot --headless --path . --script res://tests/real_save_test.gd

const SIM := "res://scripts/sim/simulation.gd"
const STORE := "res://scripts/game/save_store.gd"
const MIGRATIONS := "res://scripts/sim/save_migrations.gd"


func _init() -> void:
	var store = load(STORE)
	store.base = "user://sandbox/"
	var data: Dictionary = store.load_slot(1)
	if data.is_empty():
		print("REAL SAVE TEST: no save in user://sandbox/saves/slot1.antfarm")
		quit(1)
		return
	var sim = load(SIM).new()
	print("save format v%d -> v%d" % [int(data.sim.get("version", 1)), sim.SAVE_VERSION])
	sim.from_dict(load(MIGRATIONS).migrate(data.sim, sim.SAVE_VERSION))
	var a: Dictionary = sim.summary()
	for i in sim.TPD:
		sim.step()
	var b: Dictionary = sim.summary()
	var pos := 0.0
	for w in sim.workers:
		pos += w.pos.x + w.pos.y * 0.5 + w.age
	print("loaded: day %d workers %d eggs %d larvae %d pupae %d" % [a.day, a.workers, a.eggs, a.larvae, a.pupae])
	print("after 1 day: %s" % JSON.stringify(b))
	print("fingerprint: tick %d air %d sugar %.6f protein %.6f hum %.6f pos %.4f rng %d" % [sim.tick, sim.nest.air,
		sim.sugar, sim.protein, sim.humidity, pos, sim.rng.state])
	quit()
