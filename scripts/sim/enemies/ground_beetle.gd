extends RefCounted
## Ground beetle (Carabidae, e.g. Carabus): a big, fast night runner with crushing mandibles and a hard,
## shiny black-violet armour the ants' bites barely dent. When ants cling to it, it sprays a defensive
## secretion from glands at the tip of its abdomen (pygidial glands) and they drop off stunned. A colony
## seldom kills one; mostly it is harried until it leaves. Registered in parts/sim_enemies.gd ENEMY_KINDS.

const T := preload("res://scripts/sim/text_th.gd")
const L := preload("res://scripts/sim/lang.gd")
const IN_NEST := 0

const NAME := "enemy_ground_beetle"            # (keys of lang/strings.csv)
const LATIN := "Carabidae"
const ABOUT := "enemy_ground_beetle_about"      # (the HUD's enemy panel)
const CHASED := T.beetle_chased
const STATS := {
	"hp": 1.4,
	"armor": 0.7,       # thick, smooth cuticle: little purchase for mandibles or acid
	"r": 10.0,          # px: ants grab its legs and antennae round its body
	"hold": 7,          # ants holding on that bite and pin it in full; more get in each other's way (a quarter each)
	# where ants hold on (grip_spots.gd): its legs and antennae from the ground, up the sides of elytra and pronotum, on its
	# back (tools/blender/props/beetle.py: elytra 7 mm high, pronotum 6 mm), the head and the tip of the abdomen
	"spots": [[18.0, 13.0, 0.0, 0.5], [25.0, 15.0, 0.0, 0.3], [0.0, 17.0, 0.0, 0.5], [-6.0, 23.0, 0.0, 0.3],
		[-12.0, 15.0, 0.0, 0.5], [-22.0, 20.0, 0.0, 0.3], [40.0, 16.0, 0.5, 0.6],
		[-16.0, 10.5, 3.0, 0.9], [-6.0, 11.0, 3.2, 0.9], [4.0, 9.5, 3.0, 0.9], [12.0, 8.0, 3.5, 0.9],
		[-16.0, 4.0, 6.6, 0.0], [-6.0, 4.5, 7.0, 0.0], [4.0, 3.5, 6.6, 0.1], [12.0, 3.0, 5.9, 0.1],
		[21.0, 0.0, 5.0, 0.2], [-25.0, 0.0, 3.0, 0.6]],
	"pin": 16,          # strong: a full load of 7 ants only halves its pace (8: they held it, and killed 5 of 8, v0.11.1)
	"flee_at": 0.8,     # harried by a mob it soon gives up and leaves
	"speed": 1.0,       # px per tick: a fast runner
	"bite": 0.015,
	"lethal": 0.6,      # crushing mandibles
	"shake": 0.0012,
	"spray": 0.012,     # chance per tick, with ants on it, of a defensive spray that drops them all (v0.11.68: 0.005 - now that the ants really get on it, a big colony killed it 4 times in 8)
	"carcass": "ground_beetle_dead",
	"night": true,
	"rate": 0.05,       # chance per day of one turning up (counted over the night only; v0.11.2: was 0.18)
}


static func spawn(sim) -> Dictionary:
	var world: Vector2 = sim.WORLD
	var side: int = sim.rng.randi_range(0, 3)
	var t: float = sim.rng.randf()
	var starts := [Vector2(t * world.x, -25), Vector2(world.x + 25, t * world.y),
		Vector2(t * world.x, world.y + 25), Vector2(-25, t * world.y)]
	var start: Vector2 = starts[side]
	var c := {"pos": start, "ang": (world * 0.5 - start).angle(), "life": sim.TPD * 0.45, "kills": 0,
		"exit": start + (start - world * 0.5).normalized() * 70.0, "phase": 0.0}
	sim._log(T.beetle_arrives, "bad")
	return c


static func step(sim, c: Dictionary, clinging: Array) -> bool:
	c.life -= 1
	var held := clinging.size()
	var free := clampf(1.0 - float(c.get("load", held)) / STATS.pin, 0.0, 1.0)
	c.phase += 0.35 * maxf(free, 0.3)
	if c.hp < STATS.flee_at and not c.get("fleeing", false):
		c.fleeing = true
		sim._log(T.enemy_flees, "ok", [L.k(NAME)])
	var leaving: bool = c.life <= 0 or c.get("fleeing", false) or (sim.daylight() > 0.35 and not c.get("released", false))
	var best = null
	var bd := 140.0
	for a in sim.outside:
		if a.state != IN_NEST and not a.dead:
			var d: float = a.pos.distance_to(c.pos)
			if d < bd:
				bd = d
				best = a
	# runs in bursts, stopping now and then to search with its antennae
	var target_ang: float = c.ang + sim.rng.randf_range(-0.2, 0.2)
	if leaving:
		target_ang = (c.exit - c.pos).angle()
	elif best != null:
		target_ang = (best.pos - c.pos).angle()
	c.ang += wrapf(target_ang - c.ang, -PI, PI) * 0.1
	var burst := 1.0 if fmod(c.phase, 9.0) < 7.0 or leaving else 0.15
	var np: Vector2 = c.pos + Vector2.from_angle(c.ang) * STATS.speed * free * burst
	var world: Vector2 = sim.WORLD
	# walls and stones turn it once it is in (judged where it is, not where it steps: blocked() counts the 3 px band
	# along the edge as wall, and a slow enemy coming in turned back there - spiders and beetles never came in, v0.8.25-v0.11.1)
	var inside := Rect2(Vector2(3, 3), world - Vector2(6, 6)).has_point(c.pos)
	if not leaving and inside and sim.blocked(np):
		c.ang += 1.8
	else:
		c.pos = np
	if held >= 2 and sim.rng.randf() < STATS.spray:
		# defensive spray: every ant on it lets go, stunned and hurt
		c.strike = 20
		for a in clinging:
			sim._shake_off(a, c)
		if not c.get("sprayed", false):
			c.sprayed = true
			sim._log(T.beetle_sprays, "bad")
	else:
		var victim = null
		if held > 0:
			victim = clinging[sim.rng.randi() % held]
		elif best != null and bd < 8.0:
			victim = best
		if victim != null and sim.rng.randf() < STATS.bite * (0.4 + 0.6 * free):
			c.strike = 14
			sim._bite(victim, c)
			c.kills += 1 if victim.dead else 0
		elif held > 0 and sim.rng.randf() < STATS.shake * held:
			c.strike = 10
			sim._shake_off(clinging[sim.rng.randi() % held], c)
	c.strike = maxi(0, int(c.get("strike", 0)) - 1)
	if leaving and not Rect2(Vector2(-40, -40), world + Vector2(80, 80)).has_point(c.pos):
		sim._log(T.beetle_leaves, "", [c.kills])
		return false
	return true
