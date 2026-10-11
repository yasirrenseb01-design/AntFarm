extends SceneTree
## Ants released around stone-walled honey: how many get to it, and how long it takes.

const Sim := preload("res://scripts/sim/simulation.gd")
const Ant := preload("res://scripts/sim/ant.gd")

func _init() -> void:
	var sim := Sim.new()
	sim.setup(7)
	var h := Vector2(700, 300)
	sim.place_food("honey", h)
	for p in [Vector2(680, 280), Vector2(700, 270), Vector2(722, 284), Vector2(675, 305)]:
		sim.add_rock(p, 10.0)
	sim._rebuild_food_grid()
	var reached := 0
	var ticks := []
	for k in 8:
		var a = sim.workers[k]
		var start := h + Vector2.from_angle(TAU * k / 8.0) * 70.0
		a.state = Ant.SEARCH
		a.pos = start
		a.ang = (h - start).angle()
		a.trip = 0
		a.patience = 100000
		a.carry = Ant.NONE
		var hit := -1
		for t in 1500:
			sim._step_ant(a)
			if a.carry != Ant.NONE:
				hit = t
				break
		if hit >= 0:
			reached += 1
			ticks.append(hit)
		print("from %3d°: %s" % [k * 45, ("reached in %d ticks" % hit) if hit >= 0 else "stuck at %s" % a.pos])
	print("reached ", reached, "/8")
	quit()
