extends SceneTree
## Every save in the keeper's own slots (user://saves/, read only - nothing is written) still passes the loading
## checks after migration: what main.gd would do on opening it. A save the game would give up on as unreadable is
## a colony lost (v0.11.28: both the year-35 colony and the newest one would have been, by two checks too strict).
##   godot --headless --path . --script res://tests/real_saves_check.gd

const STORE := "res://scripts/game/save_store.gd"
const SIM := "res://scripts/sim/simulation.gd"
const MIGRATIONS := "res://scripts/sim/save_migrations.gd"
const CHECK := "res://scripts/sim/save_check.gd"


func _init() -> void:
	var store = load(STORE)
	store.base = "user://"
	var ok := true
	var n := 0
	for slot in range(1, store.SLOTS + 1):
		if not store.exists(slot):
			continue
		var data: Dictionary = store.load_slot(slot)
		if data.is_empty() or not data.get("sim") is Dictionary:
			print("  slot %d: cannot be read" % slot)
			ok = false
			continue
		var sim_d: Dictionary = data.sim
		var v := int(sim_d.get("version", 0))
		if v > load(SIM).SAVE_VERSION:
			print("  slot %d: from a newer game (v%d) - left alone" % [slot, v])
			continue
		if v < load(SIM).SAVE_VERSION:
			sim_d = load(MIGRATIONS).migrate(sim_d, load(SIM).SAVE_VERSION)
		var why: String = load(CHECK).problem(sim_d)
		print("  slot %d (save v%d): %s" % [slot, v, "loads" if why == "" else "WOULD BE GIVEN UP ON: " + why])
		ok = ok and why == ""
		n += 1
	print("REAL SAVES CHECK %s (%d slots)" % ["PASSED" if ok else "FAILED", n])
	quit(0 if ok else 1)
