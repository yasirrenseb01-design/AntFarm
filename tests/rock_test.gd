extends SceneTree
## Regression test: stones dropped on ants must not trap them, and food behind stones stays reachable.

const Sim := preload("res://scripts/sim/simulation.gd")

func _init() -> void:
	var sim := Sim.new()
	sim.setup(7)
	# honey half-walled by stones, like the player's screenshot
	var h := Vector2(700, 300)
	sim.place_food("honey", h)
	var walls := [] if OS.get_cmdline_user_args().has("--norocks") else [Vector2(680, 280), Vector2(700, 270), Vector2(722, 284), Vector2(675, 305)]
	for p in walls:
		sim.add_rock(p, 10.0)
	var start: float = sim.foods.filter(func(f): return f.kind == "honey")[0].amt
	var trapped_max := 0
	for t in sim.TPD * 2:
		sim.step()
		if t % 600 == 0 and not sim.outside.is_empty():
			# drop a stone right on top of a forager
			var a = sim.outside[0]
			sim.add_rock(a.pos + Vector2(2, 1), 10.0)
		var trapped := 0
		for a in sim.outside:
			if sim.blocked(a.pos):
				trapped += 1
		trapped_max = maxi(trapped_max, trapped)
	var honey = sim.foods.filter(func(f): return f.kind == "honey")
	var left: float = honey[0].amt if not honey.is_empty() else 0.0
	print("ants ever inside a stone: ", trapped_max)
	var evaporated := start - start * pow(0.78, 2.0)
	print("honey gone %.1f (evaporation alone ≈ %.1f) -> ants carried ≈ %.1f, found=%s" % [start - left, evaporated,
		start - left - evaporated, honey[0].found if not honey.is_empty() else "eaten"])
	quit()
