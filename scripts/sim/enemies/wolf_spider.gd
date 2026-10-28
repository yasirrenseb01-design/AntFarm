extends RefCounted
## Wolf spider (Lycosidae): wanders into the outworld from an edge, hunts foragers, and fights back
## when the ants mob it — biting the ants that cling to it and shaking them off. Badly hurt it runs
## for the edge; if the ants pin and kill it, it becomes a carcass they eat.
## One enemy kind = one file like this, registered in parts/sim_enemies.gd ENEMY_KINDS.
## A creature is a plain Dictionary (saved as is): kind, id, pos, ang, hp, held, life, ...

const T := preload("res://scripts/sim/text_th.gd")
const L := preload("res://scripts/sim/lang.gd")
const IN_NEST := 0

const NAME := "enemy_wolf_spider"            # (keys of lang/strings.csv)
const LATIN := "Lycosidae"
const ABOUT := "enemy_wolf_spider_about"      # (the HUD's enemy panel)
const CHASED := T.spider_chased        # journal line when the keeper removes it
const STATS := {
	"hp": 1.0,          # health; formic acid and bites wear it down
	"armor": 0.15,      # share of the ants' damage its body shrugs off
	"r": 16.0,          # px from its centre where ants grab on (its legs)
	"hold": 8,          # ants holding on that bite and pin it in full; more get in each other's way (a quarter each)
	# where ants hold on (scripts/sim/enemies/grip_spots.gd): its legs (from the ground, rearing up), up its sides, on its
	# carapace and abdomen (the model, x0.85: carapace up to 4.6 mm high, abdomen 5.5 mm), the spinnerets
	"spots": [[12.4, 8.5, 0.0, 0.5], [4.7, 14.2, 0.0, 0.5], [-4.8, 14.2, 0.0, 0.5], [-12.4, 8.3, 0.0, 0.5],
		[18.2, 12.4, 0.0, 0.3], [6.9, 20.9, 0.0, 0.3], [-7.1, 20.8, 0.0, 0.3], [-18.2, 12.2, 0.0, 0.3],
		[4.0, 6.0, 1.8, 0.9], [-5.0, 7.0, 2.0, 0.9], [-12.0, 6.0, 2.0, 0.9],
		[5.0, 2.2, 4.4, 0.1], [-5.0, 2.8, 5.3, 0.0], [-12.0, 2.0, 4.8, -0.1], [-17.0, 0.0, 2.5, 0.7]],
	"pin": 5,           # this many ants stop it moving (spread-eagling)
	"flee_at": 0.45,    # below this health it runs for the edge
	# pace, px per tick (1 px = 0.5 mm, 60 ticks a second at 1x) at full warmth: wolf spiders sprint at 20-50 cm/s
	# (Pardosa valens, Brown & Formanowicz 2012) and hunt in short rushes. Slower here so the keeper can follow it:
	# (v0.11.68, the keeper: "far slower than a real one - faster, but not that fast"; it was 0.55, 1.7 cm/s, slower than
	# the ants answering the alarm at 2.7 cm/s)
	"speed": 1.0,       # prowling: 3 cm/s
	"dash": 2.6,        # a rush at an ant within dash_at: 7.8 cm/s for dash_ticks
	"dash_at": 30.0,    # px (15 mm)
	"dash_ticks": 24,   # 0.4 s
	"dash_rest": 90,    # ticks before it rushes again
	"flee": 2.0,        # running for the edge when badly hurt: 6 cm/s
	"bite": 0.02,       # chance per tick to bite an ant within reach (less while pinned)
	"shake": 0.0016,    # chance per tick, per clinging ant, to throw one off
	"carcass": "wolf_spider_dead",
	"night": false,     # hunts by day as well
	"rate": 0.07,       # chance per day of one wandering in (v0.11.2: 0.25 came every ~4 days once it could come in at all)
}


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


## One tick. Returns false once the spider has left the box. `clinging` = ants holding on to it.
static func step(sim, s: Dictionary, clinging: Array) -> bool:
	s.life -= 1
	var held := clinging.size()
	var free := clampf(1.0 - float(s.get("load", held)) / STATS.pin, 0.0, 1.0)      # pinned by the ants holding on
	if s.hp < STATS.flee_at and not s.get("fleeing", false):
		s.fleeing = true
		sim._log(T.enemy_flees, "ok", [L.k(NAME)])
	var leaving: bool = s.life <= 0 or s.get("fleeing", false)
	var best = null
	var bd := 150.0
	for a in sim.outside:
		if a.state != IN_NEST and not a.dead:
			var d: float = a.pos.distance_to(s.pos)
			if d < bd:
				bd = d
				best = a
	var target_ang: float = s.ang + sim.rng.randf_range(-0.12, 0.12)
	if leaving:
		target_ang = (s.exit - s.pos).angle()
	elif best != null:
		target_ang = (best.pos - s.pos).angle()
	# a rush at an ant close by (not while ants hold it, or on its way out)
	s.dash_cd = maxi(0, int(s.get("dash_cd", 0)) - 1)
	if not leaving and held == 0 and best != null and bd < STATS.dash_at and s.dash_cd == 0:
		s.dash = STATS.dash_ticks
		s.dash_cd = STATS.dash_rest
	var dashing: bool = int(s.get("dash", 0)) > 0
	s.dash = maxi(0, int(s.get("dash", 0)) - 1)
	s.ang += wrapf(target_ang - s.ang, -PI, PI) * (0.25 if dashing else 0.08)
	# a cold spider is slower, as the ants are (Pardosa ran 4x faster at 30 than at 7 °C: Villaseñor-Amador et al., Animal Behaviour 2023)
	var warm: float = 0.25 + 0.75 * sim.activity
	var pace: float = STATS.flee if s.get("fleeing", false) else (STATS.dash if dashing else STATS.speed)
	var np: Vector2 = s.pos + Vector2.from_angle(s.ang) * pace * warm * free
	s.phase += 0.55 * maxf(pace * warm * free, 0.14)                    # legs step with the ground covered; pinned, they thrash
	var world: Vector2 = sim.WORLD
	# walls and stones turn it once it is in (judged where it is, not where it steps: blocked() counts the 3 px band
	# along the edge as wall, and a slow enemy coming in turned back there - spiders and beetles never came in, v0.8.25-v0.11.1)
	var inside := Rect2(Vector2(3, 3), world - Vector2(6, 6)).has_point(s.pos)
	if not leaving and inside and sim.blocked(np):
		s.ang += 2.0
	else:
		s.pos = np
	# bite: an ant clinging to it first, otherwise the nearest one within reach
	var victim = null
	if held > 0:
		victim = clinging[sim.rng.randi() % held]
	elif best != null and bd < 7.0:
		victim = best
	if victim != null and sim.rng.randf() < STATS.bite * (0.4 + 0.6 * free):
		s.strike = 18
		sim._bite(victim, s)
		s.kills += 1 if victim.dead else 0
		if s.kills == 1 and victim.dead:
			sim._log(T.spider_first_kill, "bad")
	elif held > 0 and sim.rng.randf() < STATS.shake * held:
		s.strike = 12
		sim._shake_off(clinging[sim.rng.randi() % held], s)
	s.strike = maxi(0, int(s.get("strike", 0)) - 1)
	if leaving and not Rect2(Vector2(-30, -30), world + Vector2(60, 60)).has_point(s.pos):
		sim._log(T.spider_leaves, "", [s.kills])
		return false
	return true
