extends RefCounted
## Giant centipede (Scolopendra): a fast night hunter. It slips into the outworld after dark, runs down
## foragers and seizes them with its venom claws (forcipules) — a bite is nearly always fatal. Its long
## segmented body gives the ants many legs to grab, so a big colony can pin it; it thrashes and throws
## them off, and leaves before dawn if it can. Registered in parts/sim_enemies.gd ENEMY_KINDS.

const T := preload("res://scripts/sim/text_th.gd")
const IN_NEST := 0

const NAME := "ตะขาบ"
const CHASED := T.centipede_chased
const STATS := {
	"hp": 1.6,          # bigger and tougher than a wolf spider
	"armor": 0.3,       # overlapping segment plates
	"shape": "long",    # the ants grip along its body, not round a centre
	"length": 110.0,    # px (about 55 mm)
	"width": 7.0,       # px from the midline to where its legs are seized
	"r": 12.0,          # px: ants within this of their grip point latch on
	"hold": 14,         # many legs to grab
	"pin": 9,
	"flee_at": 0.4,
	"speed": 0.95,      # px per tick: fast
	"bite": 0.03,
	"lethal": 0.85,     # venom: a bite kills far more often than it maims
	"shake": 0.0025,    # writhes hard
	"carcass": "centipede_dead",
	"night": true,      # only comes out in the dark, leaves at dawn
	"rate": 0.2,        # chance per day of one turning up (about once a week; counted over the night only)
}


static func spawn(sim) -> Dictionary:
	var world: Vector2 = sim.WORLD
	var side: int = sim.rng.randi_range(0, 3)
	var t: float = sim.rng.randf()
	var starts := [Vector2(t * world.x, -40), Vector2(world.x + 40, t * world.y),
		Vector2(t * world.x, world.y + 40), Vector2(-40, t * world.y)]
	var start: Vector2 = starts[side]
	var c := {"pos": start, "ang": (world * 0.5 - start).angle(), "life": sim.TPD * 0.5, "kills": 0,
		"exit": start + (start - world * 0.5).normalized() * 120.0, "phase": 0.0}
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
