extends SceneTree
## Dev: a wolf spider taking prey (enemies/spider_prey.gd), over several seeds: catches (fed on / bitten and shaken),
## ants saved by their nestmates, ants killed, dead flies taken, and how the fight ended.
##   godot --headless --path . --script res://tests/_prey_bench.gd -- [workers] [seeds, e.g. 1-6] [flies]
func _init():
	var Sim = load("res://scripts/sim/simulation.gd")
	var args := OS.get_cmdline_user_args()
	var workers := int(args[0]) if args.size() > 0 else 100
	var sr: PackedStringArray = (args[1] if args.size() > 1 else "1-6").split("-")
	var flies := int(args[2]) if args.size() > 2 else 0
	var tot := {"eat": 0, "shake": 0, "fly": 0, "saved": 0, "dead": 0, "s": 0.0, "won": 0}
	for seed in range(int(sr[0]), int(sr[-1]) + 1):
		var s = Sim.new()
		s.setup(seed, workers, false, "keeper")
		s.enemies = false
		for i in 2 * s.TPD:
			s.step()
		# (far from the nest, where lone foragers meet it before a mob does)
		var at: Vector2 = Vector2(s.WORLD.x - s.nest_pos.x, s.WORLD.y - s.nest_pos.y).clamp(Vector2(60, 60), s.WORLD - Vector2(60, 60))
		for k in flies:
			s.place_food("fly", at + Vector2(-60 + 40 * k, 50))
		s._spawn_creature("wolf_spider")
		var c: Dictionary = s.creatures[-1]
		c.pos = at
		c.ang = 3.1
		var dead0: int = int(s.stats.dead)
		var seen := {}
		var saved := 0
		var t := 0
		var logs0: int = s.log_entries.size()
		while t < s.TPD * 3 and not s.creatures.is_empty():
			s.step()
			t += 1
			if c.has("prey") and not seen.has(str(c.prey.get("id", c.prey.get("seed"))) + str(c.prey.get("kind"))):
				seen[str(c.prey.get("id", c.prey.get("seed"))) + str(c.prey.get("kind"))] = true
				var k: String = "fly" if c.prey.kind == "fly" else String(c.prey.mode)
				tot[k] += 1
		for e in s.log_entries:
			if String(e.key).contains("ant_rescued"):
				saved += 1
		var dead: int = int(s.stats.dead) - dead0
		tot.dead += dead
		tot.saved += saved
		tot.s += t / 60.0
		tot.won += 1 if int(s.stats.get("enemies_killed", 0)) > 0 else 0
		print("seed %d: %.0f s, ants killed %d, saved %d, catches %s" % [seed, t / 60.0, dead, saved, str(seen.keys())])
	print("== %d workers: catches eaten %d, bitten-shaken %d, flies %d; saved %d; ants killed %d; spider killed in %d; mean %.0f s" %
		[workers, tot.eat, tot.shake, tot.fly, tot.saved, tot.dead, tot.won, tot.s / maxf(1.0, int(sr[-1]) - int(sr[0]) + 1)])
	quit()
