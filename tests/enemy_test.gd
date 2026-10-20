extends SceneTree
## Each enemy kind let in by the keeper (sim.release_enemy, the HUD's enemy panel) comes in from the edge and is
## fought by the ants of a 60-worker colony, at four times of day. (From v0.8.25 to v0.11.0 wolf spiders and
## ground beetles turned back at the edge and never came in, wild or released, and nothing noticed.)
##   godot --headless --path . --script res://tests/enemy_test.gd     -> "ENEMY TEST PASSED"
func _init():
	var Sim = load("res://scripts/sim/simulation.gd")
	var ok := true
	for kind in ["wolf_spider", "centipede", "ground_beetle"]:
		var fights := 0
		for trial in 4:
			var s = Sim.new()
			s.setup(5 + trial, 60, false, "keeper")
			for i in s.TPD * 2 + trial * s.TPD / 4:
				s.step()
			if s.release_enemy(kind) == 0:
				print("%s: could not be released" % kind)
				ok = false
				break
			var held := 0
			for t in s.TPD:
				s.step()
				for c in s.creatures:
					held = maxi(held, int(c.get("held", 0)))
				if s.creatures.is_empty():
					break
			fights += 1 if held > 0 else 0
		print("%s: fought in %d of 4 releases" % [kind, fights])
		ok = ok and fights >= 3
	# no more than RELEASE_MAX at once
	var s2 = Sim.new()
	s2.setup(5, 60, false, "keeper")
	var ids := []
	for i in 5:
		ids.append(s2.release_enemy("wolf_spider"))
	print("released ids %s (at most %d)" % [str(ids), s2.RELEASE_MAX])
	ok = ok and s2.creatures.size() == s2.RELEASE_MAX and ids.count(0) == 5 - s2.RELEASE_MAX
	print("ENEMY TEST PASSED" if ok else "ENEMY TEST FAILED")
	quit()
