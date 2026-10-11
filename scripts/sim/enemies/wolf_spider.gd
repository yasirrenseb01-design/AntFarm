extends RefCounted
## Wolf spider (Lycosidae): wanders into the outworld from an edge, hunts the nearest forager, then
## leaves again. One enemy kind = one file like this, registered in parts/sim_enemies.gd ENEMY_KINDS.
## A creature is a plain Dictionary (saved as is) with at least "kind" and "pos".

const T := preload("res://scripts/sim/text_th.gd")
const IN_NEST := 0
const CHASED := T.spider_chased        # journal line when the keeper removes it


## A new spider entering from a random edge (sim.rng only, so runs stay reproducible).
static func spawn(sim) -> Dictionary:
	var world: Vector2 = sim.WORLD
	var side: int = sim.rng.randi_range(0, 3)
	var t: float = sim.rng.randf()
	var starts := [Vector2(t * world.x, -20), Vector2(world.x + 20, t * world.y),
		Vector2(t * world.x, world.y + 20), Vector2(-20, t * world.y)]
	var start: Vector2 = starts[side]
	var s := {"pos": start, "ang": (world * 0.5 - start).angle(), "life": sim.TPD * 0.45, "kills": 0,
		"exit": start + (start - world * 0.5).normalized() * 60.0, "phase": 0.0}
	sim._log(T.spider_arrives, "bad")
	return s


## One tick. Returns false once the spider has left the box.
static func step(sim, s: Dictionary) -> bool:
	s.life -= 1
	s.phase += 0.3
	var best = null
	var bd := 150.0
	for a in sim.outside:
		if a.state != IN_NEST and not a.dead:
			var d: float = a.pos.distance_to(s.pos)
			if d < bd:
				bd = d
				best = a
	var target_ang: float = s.ang + sim.rng.randf_range(-0.12, 0.12)
	if s.life <= 0:
		target_ang = (s.exit - s.pos).angle()
	elif best != null:
		target_ang = (best.pos - s.pos).angle()
	s.ang += wrapf(target_ang - s.ang, -PI, PI) * 0.08
	var np: Vector2 = s.pos + Vector2.from_angle(s.ang) * 0.55
	var world: Vector2 = sim.WORLD
	var inside := np.x > 0 and np.y > 0 and np.x < world.x and np.y < world.y
	if s.life > 0 and inside and sim.blocked(np):
		s.ang += 2.0
	else:
		s.pos = np
	if best != null and bd < 7.0 and sim.rng.randf() < 0.04:
		sim._kill(best)
		s.kills += 1
		if s.kills == 1:
			sim._log(T.spider_first_kill, "bad")
	if s.life <= 0 and not Rect2(Vector2(-30, -30), world + Vector2(60, 60)).has_point(s.pos):
		sim._log(T.spider_leaves % s.kills)
		return false
	return true
