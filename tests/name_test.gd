extends SceneTree
## Ant names (PART EA3b): the keeper names workers (sim.name_ant); the names survive a save round trip, change
## nothing in the simulation (a named colony plays on exactly as the same colony unnamed) and a named ant's death
## is announced (a log line of kind "named", with the cause).
##   godot --headless --path . --script res://tests/name_test.gd     -> "NAME TEST PASSED"
func _init():
	var Sim = load("res://scripts/sim/simulation.gd")
	var ok := true
	var a = Sim.new()
	var b = Sim.new()
	a.setup(5, 30, false, "wild")
	b.setup(5, 30, false, "wild")
	for i in a.TPD:
		a.step()
		b.step()
	var ids := []
	for k in 12:
		ids.append(a.workers[k].id)
		ok = a.name_ant(a.workers[k].id, "  มดหมายเลข %d  " % k) and ok
	ok = ok and a.workers[0].name == "มดหมายเลข 0"                       # (trimmed)
	ok = ok and a.name_ant(a.workers[1].id, "x".repeat(60)) and a.workers[1].name.length() == a.NAME_MAX
	ok = ok and not a.name_ant(-5, "ใคร")
	# a save round trip keeps every name
	var c = Sim.new()
	c.from_dict(bytes_to_var(var_to_bytes(a.to_dict())))
	var kept := 0
	for w in c.workers:
		if w.name != "":
			kept += 1
	print("named 12, after a save round trip %d" % kept)
	ok = ok and kept == 12
	# names change nothing: the named colony and the unnamed one play on alike
	for i in a.TPD * 3:
		a.step()
		b.step()
	var same: bool = a.rng.state == b.rng.state and a.workers.size() == b.workers.size() and a.stats.dead == b.stats.dead
	print("named and unnamed colony alike after 3 more days: %s (workers %d / %d)" % [same, a.workers.size(), b.workers.size()])
	ok = ok and same
	# a named ant dies: announced with its cause
	var w = null
	for x in a.workers:
		if x.name != "":
			w = x
	var before: int = a.log_entries.size()
	a._kill(w, "enemy")
	var e: Dictionary = a.log_entries[0]
	a.L.use("en")
	var said: String = a.L.entry_text(e)
	print("death notice: [%s] %s" % [e.kind, said])
	ok = ok and e.kind == "named" and said.contains(w.name) and said.contains("predator") and e.key == a.T.named_died
	var u = null
	for x in a.workers:
		if x.name == "" and not x.dead:
			u = x
	var n_before: int = a.log_entries.size()
	a._kill(u, "old")
	ok = ok and (a.log_entries.size() == n_before or a.log_entries[0].kind != "named")      # (an unnamed one: no notice)
	print("NAME TEST PASSED" if ok else "NAME TEST FAILED")
	quit()
