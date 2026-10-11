extends RefCounted
## Stone centipede (Lithobius forficatus, since v0.8.6 — the centipede of temperate gardens; the giant
## Scolopendra is Mediterranean): 20–30 mm, chestnut, 15 pairs of legs, very fast. It hunts at night out of
## the litter and from under stones, seizing small insects (ants among them) with its venom claws. Small
## enough that a crowd of ants can grab its legs and pin it; it writhes free and runs. Registered in
## parts/sim_enemies.gd ENEMY_KINDS.

const T := preload("res://scripts/sim/text_th.gd")
const IN_NEST := 0

const NAME := "ตะขาบหิน"
const CHASED := T.centipede_chased
const STATS := {
	"hp": 0.9,          # a little tougher than a spider of its size
	"armor": 0.2,       # thin, flexible plates
	"shape": "long",    # the ants grip along its body, not round a centre
	"length": 50.0,     # px (about 25 mm)
	"width": 4.0,       # px from the midline to where its legs are seized
	"r": 8.0,           # px: ants within this of their grip point latch on
	"hold": 10,         # 15 pairs of legs to grab
	"pin": 6,
	"flee_at": 0.5,     # runs as soon as it is badly mobbed
	"speed": 1.15,      # px per tick: one of the fastest things in the leaf litter
	"bite": 0.025,
	"lethal": 0.55,     # its venom is weak, but an ant is small
	"shake": 0.002,     # writhes free
	"carcass": "centipede_dead",
	"night": true,      # only comes out in the dark, leaves at dawn
	"rate": 0.3,        # common in gardens (counted over the night only)
}


static func spawn(sim) -> Dictionary:
	var world: Vector2 = sim.WORLD
	var side: int = sim.rng.randi_range(0, 3)
	var t: float = sim.rng.randf()
	var starts := [Vector2(t * world.x, -30), Vector2(world.x + 30, t * world.y),
		Vector2(t * world.x, world.y + 30), Vector2(-30, t * world.y)]
	var start: Vector2 = starts[side]
	var c := {"pos": start, "ang": (world * 0.5 - start).angle(), "life": sim.TPD * 0.5, "kills": 0,
		"exit": start + (start - world * 0.5).normalized() * 70.0, "phase": 0.0}
	sim._log(T.centipede_arrives, "bad")
	return c


static func step(sim, c: Dictionary, clinging: Array) -> bool:
	c.life -= 1
	var held := clinging.size()
	var free := clampf(1.0 - float(held) / STATS.pin, 0.0, 1.0)
	c.phase += 0.45 * maxf(free, 0.3)
	if c.hp < STATS.flee_at and not c.get("fleeing", false):
		c.fleeing = true
		sim._log(T.enemy_flees % NAME, "ok")
	# daylight sends it back under cover
	var leaving: bool = c.life <= 0 or c.get("fleeing", false) or sim.daylight() > 0.35
	var head: Vector2 = c.pos + Vector2.from_angle(c.ang) * STATS.length * 0.5
	var best = null
	var bd := 180.0
	for a in sim.outside:
		if a.state != IN_NEST and not a.dead:
			var d: float = a.pos.distance_to(head)
			if d < bd:
				bd = d
				best = a
	# it hunts by touch, sweeping its head from side to side
	var target_ang: float = c.ang + sin(c.phase * 0.35) * 0.25 + sim.rng.randf_range(-0.1, 0.1)
	if leaving:
		target_ang = (c.exit - c.pos).angle()
	elif best != null and bd < 90.0:
		target_ang = (best.pos - c.pos).angle()
	c.ang += wrapf(target_ang - c.ang, -PI, PI) * 0.06
	var np: Vector2 = c.pos + Vector2.from_angle(c.ang) * STATS.speed * free * (1.3 if leaving else 1.0)
	var world: Vector2 = sim.WORLD
	var inside := np.x > 0 and np.y > 0 and np.x < world.x and np.y < world.y
	if not leaving and inside and sim.blocked(np + Vector2.from_angle(c.ang) * STATS.length * 0.5):
		c.ang += 1.6
	else:
		c.pos = np
	var victim = null
	if held > 0:
		victim = clinging[sim.rng.randi() % held]
	elif best != null and bd < 8.0:
		victim = best
	if victim != null and sim.rng.randf() < STATS.bite * (0.4 + 0.6 * free):
		c.strike = 16
		sim._bite(victim, c)
		c.kills += 1 if victim.dead else 0
	elif held > 0 and sim.rng.randf() < STATS.shake * held:
		c.strike = 10
		sim._shake_off(clinging[sim.rng.randi() % held], c)
	c.strike = maxi(0, int(c.get("strike", 0)) - 1)
	if leaving and not Rect2(Vector2(-90, -90), world + Vector2(180, 180)).has_point(c.pos):
		sim._log(T.centipede_leaves % c.kills)
		return false
	return true
