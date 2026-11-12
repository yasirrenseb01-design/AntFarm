extends RefCounted
## A wolf spider taking prey (v0.13.4, the keeper 2026-11-12: "it only walks round the ants and they die - let it do
## something: hold its food with its legs or palps and eat, like the photo"; the keeper chose: a worker or a dead fly
## lying in the box; once caught, by chance either fed on where it is - held up before the fangs - or bitten, shaken and
## dropped; the ants can save a nestmate if they pin the spider before it dies).
## Evidence and inference (docs/BIOLOGY.md "แมงมุมหมาป่าจับเหยื่อ"): wolf spiders run prey down and seize it with the
## front legs and chelicerae, without a web, and hold it to the fangs while they feed, chewing it with the chelicerae
## [Lycosidae]; they also take dead insects [Lycosidae scavenging]; that a bitten ant lives about 2.5 s, a meal lasts
## 10-20 s, half the catches are fed on there and then, and how many ants it takes to make it let go [inference: game
## pacing].
## The prey ant is held where the spider's mouth is (act ACT_PREY: it takes no steps of its own; not counted among the
## ants clinging to the spider); a fly is a food item moved there and eaten away.

const T := preload("res://scripts/sim/text_th.gd")
const L := preload("res://scripts/sim/lang.gd")
const ACT_PREY := 23            # (sim_enemies / the view: an ant in a spider's fangs)
const MOUTH_PX := 15.0          # px ahead of the spider's middle: its fangs (the model's x 5.5 x 0.85 x 3 px)
## the same for each kind (v0.13.5, the keeper: "the centipede and the beetle have no such move yet - make them the
## same"): the beetle's mandibles (x 9.3 units, 3 px a unit), the centipede's venom claws (x 10)
const MOUTH := {"wolf_spider": MOUTH_PX, "ground_beetle": 28.0, "centipede": 30.0}
const DIE_AT := 150             # ticks a bitten ant lives (2.5 s at 1x): till then the ants can still save it
const SHAKE_TICKS := 55         # bitten and shaken, then dropped
const MEAL := [600, 1200]       # ticks it feeds (10-20 s at 1x)
const RESCUE_LOAD := 0.8        # of the ants it takes to pin it ("pin"): that many make it let go of a live ant
const FLY_SEEK_PX := 110.0      # how far it goes for a dead fly when no ant is nearer


static func busy(s: Dictionary) -> bool:
	return s.has("prey")


## Where its fangs are.
static func mouth(s: Dictionary) -> Vector2:
	return s.pos + Vector2.from_angle(s.ang) * float(MOUTH.get(String(s.get("kind", "")), MOUTH_PX))


## It seizes ant a: to eat it there, or to bite, shake and drop it.
static func catch_ant(sim, s: Dictionary, a) -> void:
	var eat: bool = sim.rng.randf() < 0.5
	s["prey"] = {"kind": "ant", "id": a.id, "mode": "eat" if eat else "shake", "t": 0,
		"end": sim.rng.randi_range(MEAL[0], MEAL[1]) if eat else SHAKE_TICKS}
	a.busy = 1000000
	a.act = ACT_PREY
	a.foe = s.id
	a.pos = mouth(s)
	s.strike = 18
	if not s.get("caught_told", false):
		s["caught_told"] = true
		if s.get("kind", "") == "wolf_spider":
			sim._log(T.spider_caught, "bad")
		else:
			sim._log(T.enemy_caught, "bad", [L.k(sim.ENEMY_KINDS[s.kind].NAME)])


## A dead fly lying near, to go for when no ant is nearer (or null).
static func fly_near(sim, s: Dictionary):
	var best = null
	var bd := FLY_SEEK_PX * FLY_SEEK_PX
	for f in sim.foods:
		if f.kind == "fly" and f.amt >= 1.0 and int(f.get("held_until", 0)) <= sim.tick:
			var d: float = (f.pos as Vector2).distance_squared_to(s.pos)
			if d < bd:
				bd = d
				best = f
	return best


static func catch_fly(sim, s: Dictionary, f: Dictionary) -> void:
	var end: int = sim.rng.randi_range(MEAL[0], MEAL[1])
	s["prey"] = {"kind": "fly", "seed": f.seed, "mode": "eat", "t": 0, "end": end, "amt": float(f.amt)}
	f["held_until"] = sim.tick + end + 60
	s.strike = 18


static func _prey_ant(sim, id: int):
	for a in sim.outside:
		if a.id == id and not a.dead:
			return a
	return null


## The ant within reach of its fangs it would seize (out on its own, or one holding it when only a couple do), or null.
static func at_fangs(sim, s: Dictionary):
	var m := mouth(s)
	var best = null
	var bd := 8.0 * 8.0
	for a in sim.outside:
		if a.state != 0 and not a.dead and a.act != ACT_PREY:
			var d: float = a.pos.distance_squared_to(m)
			if d < bd:
				bd = d
				best = a
	return best


## One tick of it with prey in its fangs (it does not walk): true while it has prey. clinging: the ants on it.
static func step(sim, s: Dictionary, clinging: Array, K) -> bool:
	if not busy(s):
		return false
	var p: Dictionary = s.prey
	p.t = int(p.t) + 1
	s.phase = float(s.get("phase", 0.0)) + 0.2
	if p.kind == "fly":
		var f = null
		for g in sim.foods:
			if g.seed == p.seed:
				f = g
		if f == null:
			s.erase("prey")
			return false
		f.pos = mouth(s)
		f.amt = maxf(0.0, float(p.amt) * (1.0 - float(p.t) / float(p.end)))
		sim._food_dirty = true
		if int(p.t) >= int(p.end):
			f.amt = 0.0
			s.erase("prey")
		return true
	var a = _prey_ant(sim, int(p.get("id", -1)))
	if a == null:
		s.erase("prey")
		return false
	a.pos = mouth(s)
	a.ang = s.ang + PI * 0.5
	# the ants make it let go of a nestmate still alive if enough of them hold it down
	var load: float = float(s.get("load", clinging.size()))
	if int(p.t) < DIE_AT and load >= RESCUE_LOAD * float(K.STATS.pin):
		drop(sim, s, true)
		sim._log(T.ant_rescued, "ok")
		return false
	# it still throws off the ants on it now and then, less while it feeds
	if not clinging.is_empty() and sim.rng.randf() < K.STATS.shake * clinging.size() * 0.5:
		sim._shake_off(clinging[sim.rng.randi() % clinging.size()], s)
	if p.mode == "shake":
		s.strike = 2                  # (the view: the head shaken)
	if int(p.t) >= int(p.end):
		drop(sim, s, int(p.t) < DIE_AT)
	return true


## It lets go of its prey: an ant still alive (`alive`) gets away hurt; otherwise it is dead where it falls (a bitten
## and shaken one by the bite's usual odds).
static func drop(sim, s: Dictionary, alive: bool) -> void:
	if not busy(s):
		return
	var p: Dictionary = s.prey
	s.erase("prey")
	if p.kind != "ant":
		return
	var a = _prey_ant(sim, int(p.get("id", -1)))
	if a == null:
		return
	a.busy = 0
	a.act = 0
	a.foe = 0
	if p.mode == "shake":
		sim._bite(a, s)                   # (dies or limps off maimed, as a bite goes)
		if not a.dead:
			sim._shake_off(a, s)
	elif alive:
		a.hurt = minf(0.9, a.hurt + 0.5)
		sim._shake_off(a, s)
	else:
		sim._kill(a, "enemy")
	if a.dead:
		s.kills = int(s.get("kills", 0)) + 1


## Whatever it holds, let go (it is turned over, dies, leaves, or the keeper takes it out): a bitten ant still in
## time gets away.
static func let_go(sim, s: Dictionary) -> void:
	if busy(s):
		drop(sim, s, int(s.prey.get("t", 0)) < DIE_AT)
