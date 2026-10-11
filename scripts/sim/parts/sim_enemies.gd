extends "res://scripts/sim/parts/sim_foragers.gd"
## Simulation, layer 3 of 5: natural enemies in the outworld (so far the wolf spider).


# ---------------------------------------------------------------- spider

func _spawn_spider() -> void:
	var side := rng.randi_range(0, 3)
	var t := rng.randf()
	var starts := [Vector2(t * WORLD.x, -20), Vector2(WORLD.x + 20, t * WORLD.y),
		Vector2(t * WORLD.x, WORLD.y + 20), Vector2(-20, t * WORLD.y)]
	var start: Vector2 = starts[side]
	spider = {"pos": start, "ang": (WORLD * 0.5 - start).angle(), "life": TPD * 0.45, "kills": 0,
		"exit": start + (start - WORLD * 0.5).normalized() * 60.0, "phase": 0.0}
	_log(T.spider_arrives, "bad")


func _step_spider() -> void:
	var s := spider
	s.life -= 1
	s.phase += 0.3
	var best = null
	var bd := 150.0
	for a in outside:
		if a.state != Ant.IN_NEST and not a.dead:
			var d: float = a.pos.distance_to(s.pos)
			if d < bd:
				bd = d
				best = a
	var target_ang: float = s.ang + rng.randf_range(-0.12, 0.12)
	if s.life <= 0:
		target_ang = (s.exit - s.pos).angle()
	elif best != null:
		target_ang = (best.pos - s.pos).angle()
	s.ang += wrapf(target_ang - s.ang, -PI, PI) * 0.08
	var np: Vector2 = s.pos + Vector2.from_angle(s.ang) * 0.55
	var inside := np.x > 0 and np.y > 0 and np.x < WORLD.x and np.y < WORLD.y
	if s.life > 0 and inside and blocked(np):
		s.ang += 2.0
	else:
		s.pos = np
	if best != null and bd < 7.0 and rng.randf() < 0.04:
		_kill(best)
		s.kills += 1
		if s.kills == 1:
			_log(T.spider_first_kill, "bad")
	if s.life <= 0 and not Rect2(Vector2(-30, -30), WORLD + Vector2(60, 60)).has_point(s.pos):
		_log(T.spider_leaves % s.kills)
		spider = {}


func remove_spider() -> void:
	if not spider.is_empty():
		spider = {}
		_log(T.spider_chased)
