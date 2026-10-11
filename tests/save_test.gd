extends SceneTree
## Save/load must be exact: a colony saved, written to bytes, loaded and stepped on has to stay
## identical to the original stepped on without stopping.

const Sim := preload("res://scripts/sim/simulation.gd")


func fingerprint(s) -> String:
	var px := 0.0
	var age := 0.0
	for a in s.workers:
		px += a.pos.x * 0.37 + a.pos.y
		age += a.age
	return "tick %d  workers %d  out %d  eggs %d larvae %d pupae %d  sugar %.4f protein %.4f  hum %.5f  air %d dug %d  pos %.3f age %.4f  log %d  rng %d" % [
		s.tick, s.workers.size(), s.outside.size(), s.eggs.size(), s.larvae.size(), s.pupae.size(), s.sugar,
		s.protein, s.humidity, s.nest.air, s.nest.excavated, px, age, s.log_entries.size(), s.rng.state]


func run(s, days: float) -> void:
	for i in int(days * s.TPD):
		s.step()


func _init() -> void:
	var ok := true
	for start in [14, 0]:
		var a := Sim.new()
		a.setup(11, start)
		run(a, 3.0)
		# round-trip through bytes exactly like the save file does
		var bytes := var_to_bytes(a.to_dict())
		var b := Sim.new()
		b.from_dict(bytes_to_var(bytes))
		var same_now := fingerprint(a) == fingerprint(b)
		run(a, 3.0)
		run(b, 3.0)
		var fa := fingerprint(a)
		var fb := fingerprint(b)
		print("start=%d  save size %.1f KB" % [start, bytes.size() / 1024.0])
		print("  original: ", fa)
		print("  loaded:   ", fb)
		print("  identical right after load: %s   identical 3 days later: %s" % [same_now, fa == fb])
		ok = ok and same_now and fa == fb
	print("SAVE TEST ", "PASSED" if ok else "FAILED")
	quit()
