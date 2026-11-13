extends RefCounted
## Stone centipede (Lithobius forficatus, since v0.8.6 — the centipede of temperate gardens; the giant
## Scolopendra is Mediterranean): 20–30 mm, chestnut, 15 pairs of legs, very fast. It hunts at night out of
## the litter and from under stones, seizing small insects (ants among them) with its venom claws. Small
## enough that a crowd of ants can grab its legs and pin it; it writhes free and runs. Registered in
## parts/sim_enemies.gd ENEMY_KINDS.

const T := preload("res://scripts/sim/text_th.gd")
const L := preload("res://scripts/sim/lang.gd")
const Prey := preload("res://scripts/sim/enemies/spider_prey.gd")      # (taking prey, as the spider does: v0.13.5)
const IN_NEST := 0

const NAME := "enemy_centipede"            # (keys of lang/strings.csv)
const LATIN := "Lithobius forficatus"
const ABOUT := "enemy_centipede_about"      # (the HUD's enemy panel)
const CHASED := T.centipede_chased
const STATS := {
	"hp": 2.2,          # a little tougher than a spider of its size (0.9 until v0.13.3: "it dies too fast")
	"armor": 0.2,       # thin, flexible plates
	"length": 50.0,     # px (about 25 mm)
	"width": 4.0,       # px from the midline to where its legs are seized
	"r": 8.0,           # px: ants within this of their grip point latch on
	"hold": 10,         # 15 pairs of legs to grab; more ants get in each other's way (a quarter each)
	# where ants hold on (grip_spots.gd): its legs along both sides, on its flat back (1.1 mm high), the antennae, the
	# long last legs, its head (checked on the v0.12.35 model: `python tools/dev/grip_fit.py . centipede`)
	"spots": [[18.0, 8.0, 0.0, 0.3], [12.0, 8.0, 0.0, 0.3], [6.0, 8.0, 0.0, 0.3], [0.0, 8.0, 0.0, 0.3], [-6.0, 8.0, 0.0, 0.3],
		[-12.0, 8.0, 0.0, 0.3], [-18.0, 8.0, 0.0, 0.3], [15.0, 1.8, 1.2, 0.0], [5.0, 1.8, 1.2, 0.0], [-5.0, 1.8, 1.2, 0.0],
		[-15.0, 1.8, 1.2, 0.0], [36.2, 2.7, 0.0, 0.4], [-33.2, 7.0, 0.0, 0.3], [24.0, 0.0, 1.2, 0.0]],
	"pin": 6,
	"flee_at": 1.2,     # runs as soon as it is badly mobbed (56% of its health)
	"speed": 1.15,      # px per tick: one of the fastest things in the leaf litter
	"bite": 0.025,
	"lethal": 0.55,     # its venom is weak, but an ant is small
	"shake": 0.0036,    # writhes free (0.002 until v0.13.3)
	"carcass": "centipede_dead",
	"night": true,      # only comes out in the dark, leaves at dawn
	"rate": 0.12,       # common in gardens (counted over the night only; v0.11.2: was 0.3)
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
	if Prey.step(sim, c, clinging, sim.ENEMY_KINDS[c.kind]):
		return true                         # (prey in its jaws: it stands and feeds, or shakes it)
	var held := clinging.size()
	var free: float = sim.struggle_free(c, clampf(1.0 - float(c.get("load", held)) / STATS.pin, 0.0, 1.0))
	c.phase += 0.45 * maxf(free, 0.3)
	if c.hp < STATS.flee_at and not c.get("fleeing", false):
		c.fleeing = true
		sim._log(T.enemy_flees if sim.enemy_can_leave() else T.enemy_runs, "ok", [L.k(NAME)])
	# daylight sends it back under cover (not one the keeper let in: it hunts on till its time is up); the keeper's box is
	# shut: it stays in till the ants kill it or the keeper takes it out (sim_enemies.enemy_can_leave)
	var leaving: bool = sim.enemy_can_leave() and (c.life <= 0 or c.get("fleeing", false) or (sim.daylight() > 0.35 and not c.get("released", false)))
	var fleeing: bool = c.get("fleeing", false)
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
	elif (fleeing or sim.panicking(c)) and best != null and bd < 60.0:
		target_ang = (c.pos - best.pos).angle()          # shut in: away from the ants, round the box
	elif best != null and bd < 90.0:
		target_ang = (best.pos - c.pos).angle()
	sim.turn_toward(c, target_ang, 0.06, 0.03, free)
	# running off it is faster; shut in the keeper's box, the acid in it slows it the more hurt it is [inference] - it
	# outran the ants round the box for 6 days and more, v0.13.2 tests/enemy_test.gd
	var pace: float = 1.3 if leaving else (0.3 + 0.45 * clampf(c.hp / STATS.flee_at, 0.0, 1.0) if fleeing else 1.0)
	var np: Vector2 = c.pos + Vector2.from_angle(c.ang) * STATS.speed * free * pace
	var world: Vector2 = sim.WORLD
	# walls and stones turn it once it is in (judged where it is, not where it steps: blocked() counts the 3 px band
	# along the edge as wall, and a slow enemy coming in turned back there - spiders and beetles never came in, v0.8.25-v0.11.1)
	var inside := Rect2(Vector2(3, 3), world - Vector2(6, 6)).has_point(c.pos)
	if not leaving and inside and sim.creature_blocked(np + Vector2.from_angle(c.ang) * STATS.length * 0.5):
		c.ang += 0.06 * (1.0 if int(c.id) % 2 == 0 else -1.0)      # (1.6 rad in one tick until v0.13.7)
		if sim.panicking(c):
			sim.flip_over(c)             # (ran into the side of the box in its panic)
	else:
		c.pos = np
	# an ant at its jaws - out on its own, or one of the first to hold it - seized, to eat or to shake and drop
	var front = Prey.at_fangs(sim, c) if held <= 3 else null
	if front != null and sim.rng.randf() < STATS.bite * 3.0:
		if front.busy > 0:
			front.busy = 0
		Prey.catch_ant(sim, c, front)
		return true
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
		sim._log(T.centipede_leaves, "", [c.kills])
		return false
	return true
