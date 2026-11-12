extends SceneTree
## Each enemy kind let in by the keeper (sim.release_enemy, the HUD's enemy panel) comes in from the edge and is
## fought by the ants of a 60-worker colony (and never gets out of the keeper's box), at four times of day - in at least two of the four (a centipede let in by
## day meets few ants out on some days). (From v0.8.25 to v0.11.0 wolf spiders and
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
		ok = ok and fights >= 2              # (the bug it guards against: 0 of 4; how often depends on who is out then)
	# the keeper's box is shut (the keeper, 2026-11-12): one let in never gets out - hurt, it runs round the box - and
	# stays till the ants kill it; in the wild plot a hurt one still runs off over the edge
	for kind in ["wolf_spider", "centipede", "ground_beetle"]:
		var s = Sim.new()
		s.setup(7, 100, false, "keeper")
		for i in s.TPD * 2:
			s.step()
		s.release_enemy(kind)
		var out_px := 0.0
		var fled := false
		var t := 0
		var max_held := 0
		while t < s.TPD * 6 and not s.creatures.is_empty():
			s.step()
			t += 1
			if s.creatures.is_empty():
				break
			var c: Dictionary = s.creatures[0]
			max_held = maxi(max_held, int(c.get("held", 0)))
			fled = fled or bool(c.get("fleeing", false))
			if bool(c.get("was_in", false)):
				out_px = maxf(out_px, maxf(maxf(-c.pos.x, c.pos.x - s.WORLD.x), maxf(-c.pos.y, c.pos.y - s.WORLD.y)))
			elif Rect2(Vector2(3, 3), s.WORLD - Vector2(6, 6)).has_point(c.pos):
				c["was_in"] = true
		var killed := int(s.stats.get("enemies_killed", 0))
		print("keeper %s: %s after %.2f days (most ants holding %d, ran from them %s), farthest past the wall once in %.1f px"
			% [kind, "killed" if killed > 0 else ("still in the box" if not s.creatures.is_empty() else "GONE"),
			float(t) / s.TPD, max_held, str(fled), out_px])
		ok = ok and (killed > 0 or not s.creatures.is_empty()) and out_px <= 3.0
		var w = Sim.new()
		w.setup(7, 0, false, "wild")        # (no ants out to catch it on its way)
		w._spawn_creature(kind)
		var c2: Dictionary = w.creatures[0]
		c2.pos = Vector2(w.WORLD.x - w.nest_pos.x, w.WORLD.y - w.nest_pos.y).clamp(Vector2(40, 40), w.WORLD - Vector2(40, 40))   # (away from the nest)
		c2.hp = w.ENEMY_KINDS[kind].STATS.flee_at * 0.9
		c2.fleeing = true
		var left := false
		for i in w.TPD:
			w.step()
			if w.creatures.is_empty():
				left = int(w.stats.get("enemies_killed", 0)) == 0
				break
		print("wild %s, hurt: %s (killed %d, still in %d)" % [kind, "ran off over the edge" if left else "did not leave",
			int(w.stats.get("enemies_killed", 0)), w.creatures.size()])
		ok = ok and left
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
