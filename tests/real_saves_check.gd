extends SceneTree
## Every save in the keeper's own slots (user://saves/, read only - nothing is written) still passes the loading
## checks after migration: what main.gd would do on opening it. A save the game would give up on as unreadable is
## a colony lost (v0.11.28: both the year-35 colony and the newest one would have been, by two checks too strict).
## v0.12.31: each is also loaded into a simulation (in memory) and sim._surface run once: no digger is left waiting
## out at the entrance on a worker that is gone (they had been, for ever: 5 of 6 in the colony of 812).
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
		if why == "":
			var stuck := _stuck_after_surface(sim_d)
			print("  slot %d: diggers waiting on a gone worker %d -> %d after one _surface" % [slot, stuck[0], stuck[1]])
			ok = ok and stuck[1] == 0
		n += 1
	print("REAL SAVES CHECK %s (%d slots)" % ["PASSED" if ok else "FAILED", n])
	quit(0 if ok else 1)


## [before, after] one sim._surface: diggers out at the entrance whose worker is gone or no longer carrying, and jobs
## for a worker that is gone.
func _stuck_after_surface(sim_d: Dictionary) -> Array:
	var sim = load(SIM).new()
	sim.from_dict(sim_d.duplicate(true))
	var before := _stuck(sim)
	sim._surface()
	return [before, _stuck(sim)]


static func _stuck(sim) -> int:
	var live := {}
	for w in sim.workers:
		if not w.dead:
			live[w.id] = w
	var n := 0
	for d in sim.nest.diggers:
		if not d.get("surfacing", false):
			continue
		var wid := int(d.get("wid", -1))
		var job = sim._dumps.get(wid)
		var w = live.get(wid)
		if w == null or (job != null and not job.get("dropped", false) and w.state != 7):     # (7: Ant.DUMP)
			n += 1
	for wid in sim._dumps:
		if not live.has(int(wid)):
			n += 1
	return n
