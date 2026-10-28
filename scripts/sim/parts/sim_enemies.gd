extends "res://scripts/sim/parts/sim_foragers.gd"
## Simulation, layer 4 of 7: natural enemies in the outworld and how Lasius niger fights them.
## Each enemy kind lives in its own file under scripts/sim/enemies/ and is registered here;
## sim.creatures holds the ones present (saved as is).
##
## The fight (docs/BIOLOGY.md): an ant that meets an enemy marks the spot with alarm pheromone;
## nestmates that smell it rush in (state DEFEND), seize legs and body with the mandibles and spray
## formic acid into the bite. Clinging ants slow the enemy until it is pinned; it bites back
## (killing or maiming) and shakes ants off; badly hurt it flees, and if it dies it becomes food.

const Grip := preload("res://scripts/sim/enemies/grip_spots.gd")
const ENEMY_KINDS := {
	"wolf_spider": preload("res://scripts/sim/enemies/wolf_spider.gd"),
	"centipede": preload("res://scripts/sim/enemies/centipede.gd"),
	"ground_beetle": preload("res://scripts/sim/enemies/ground_beetle.gd"),
}
const ACID := 0.0004        # health an ant's bite + formic acid takes off per tick
const ACT_ATTACK := 13      # view: biting and spraying (gaster curled forward)
const ACT_ALARM := 14       # view: running in alarmed, mandibles open
const FIGHT_FROM := 20      # a colony smaller than this hides from big enemies instead of mobbing them
const RELEASE_MAX := 3      # enemies in the box at once when the keeper lets them in (the HUD's enemy panel)
const CROWD_SHARE := 0.0   # what an ant beyond an enemy's "hold" adds to biting and pinning it (in each other's way)

var _taken := {}            # creature id -> {spot index: ant id}: c.spots turned round (not saved: made again from it)


const NIGHT_SHARE := 0.33   # of a summer day dark enough for the night hunters (enemy_days: an estimate for the keeper)


## Now and then an enemy finds its way into the box (one at a time); night hunters only after dark.
func _maybe_spawn(dt: float) -> void:
	if not creatures.is_empty():
		return
	for kind in ENEMY_KINDS:
		var S: Dictionary = ENEMY_KINDS[kind].STATS
		if S.get("night", false) and daylight() > 0.15:
			continue
		if rng.randf() < S.rate * enemy_rate * dt * season_life():
			_spawn_creature(kind)
			return


## How often natural enemies come (x each kind's rate; 0 = none): the keeper's choice when the colony starts, and
## in the enemy panel. Enemies already in the box stay.
func set_enemy_rate(v: float) -> void:
	enemy_rate = maxf(0.0, v)
	enemies = enemy_rate > 0.0


## About how many days apart natural enemies come in high summer at this rate (INF: never) - for the keeper.
static func enemy_days(rate: float) -> float:
	var per_day := 0.0
	for kind in ENEMY_KINDS:
		var S: Dictionary = ENEMY_KINDS[kind].STATS
		per_day += S.rate * rate * (NIGHT_SHARE if S.get("night", false) else 1.0)
	return INF if per_day <= 0.0 else 1.0 / per_day


## The keeper lets an enemy into the box (HUD enemy panel): it comes in from an edge as a wild one does, by day
## or night, with natural enemies on or off. Returns its id, or 0 when RELEASE_MAX are in already.
## Called between steps like placing food, and drawing only on sim.rng, so a run stays reproducible.
func release_enemy(kind: String) -> int:
	if creatures.size() >= RELEASE_MAX or not ENEMY_KINDS.has(kind):
		return 0
	_spawn_creature(kind)
	creatures[-1]["released"] = true            # (a night hunter let in by day stays out till its time is up)
	log_entries[0].key = T.enemy_released     # (in place of its wild arrival line: "at night" may not be true)
	log_entries[0].args = [L.k(ENEMY_KINDS[kind].NAME)]
	return creatures[-1].id


## Where on the enemy this ant holds on: its spot (c.spots, see enemies/grip_spots.gd) - a leg, a side, its back.
func _grip(a: Ant, c: Dictionary) -> Vector2:
	var i := int(c.spots.get(a.id, -1))
	return Grip.at(c, ENEMY_KINDS[c.kind], i) if i >= 0 else c.pos


## The spots held on this enemy (spot index -> ant id), made again from c.spots after a load.
func _taken_on(c: Dictionary) -> Dictionary:
	if not c.get("spots") is Dictionary:
		c["spots"] = {}                      # (an enemy from before v0.11.68, or a save changed by hand)
	if not _taken.has(c.id):
		var t := {}
		for id in c.spots.keys():
			var i = c.spots[id]
			if (id is int) and (i is int) and i >= 0 and not t.has(i):
				t[i] = id
			else:
				c.spots.erase(id)
		_taken[c.id] = t
	return _taken[c.id]


## Keep the spots of the ants still holding on (thrown off, bitten, dead: theirs are free again); one holding on without
## a spot (an older save) gets the nearest free one, or lets go.
func _hold_spots(c: Dictionary, clinging: Array) -> void:
	var old: Dictionary = c.spots if c.get("spots") is Dictionary else {}
	var kept := {}
	var taken := {}
	for a in clinging:
		var v = old.get(a.id, -1)
		var i: int = v if v is int else -1
		if i >= 0 and not taken.has(i):
			kept[a.id] = i
			taken[i] = a.id
	for a in clinging:
		if not kept.has(a.id):
			var i := Grip.free_spot(c, ENEMY_KINDS[c.kind], taken, a.pos, Grip.layers(workers.size()))
			if i >= 0:
				kept[a.id] = i
				taken[i] = a.id
			else:
				a.busy = 0
	c.spots = kept
	_taken[c.id] = taken


func _spawn_creature(kind: String) -> void:
	var c: Dictionary = ENEMY_KINDS[kind].spawn(self)
	c["kind"] = kind
	c["id"] = _next_cid
	_next_cid += 1
	c["hp"] = ENEMY_KINDS[kind].STATS.hp
	c["held"] = 0
	c["spots"] = {}                          # ant id -> spot it holds (enemies/grip_spots.gd)
	creatures.append(c)
	stats["enemies_came"] = int(stats.get("enemies_came", 0)) + 1


func _creature(id: int):
	for c in creatures:
		if c.id == id:
			return c
	return null


func _nearest_creature(p: Vector2, within: float):
	var best = null
	var bd := within * within
	for c in creatures:
		var d: float = p.distance_squared_to(c.pos)
		if d < bd:
			bd = d
			best = c
	return best


func _clinging(c: Dictionary) -> Array:
	var out := []
	for a in outside:
		if a.foe == c.id and a.busy > 0 and not a.dead:
			out.append(a)
	return out


func _step_creatures() -> void:
	var gone := []
	for c in creatures:
		var clinging := _clinging(c)
		_hold_spots(c, clinging)
		clinging = clinging.filter(func(a): return a.busy > 0)
		c.held = clinging.size()
		var K = ENEMY_KINDS[c.kind]
		# biting and pinning: the first "hold" ants in full, the rest a little each (they hold on to it and to each other)
		var hold: float = K.STATS.hold
		c["load"] = minf(c.held, hold) + CROWD_SHARE * maxf(0.0, c.held - hold)
		if c.hp <= 0.0:
			_creature_dies(c, clinging)
			gone.append(c)
		elif not K.step(self, c, clinging):
			_release(c, clinging)
			gone.append(c)
	for c in gone:
		creatures.erase(c)
		_taken.erase(c.id)


## The ants have killed it: the body stays where it fell as food for the colony.
func _creature_dies(c: Dictionary, clinging: Array) -> void:
	var K = ENEMY_KINDS[c.kind]
	_release(c, clinging)
	var f := {"kind": K.STATS.carcass, "pos": c.pos, "found": true, "age": 0.0, "seed": rng.randi(), "rotten": false,
		"ang": c.ang}
	var k := FoodKinds.info(K.STATS.carcass)
	f.merge({"type": k.type, "amt": k.amt, "cap": k.cap, "regen": k.regen, "r": k.r})
	foods.append(f)
	_food_dirty = true
	stats["enemies_killed"] = int(stats.get("enemies_killed", 0)) + 1
	_log(T.enemy_killed, "ok", [L.k(K.NAME)])


func _release(c: Dictionary, clinging: Array) -> void:
	for a in clinging:
		a.busy = 0
		a.act = 0
		a.pos = a.pos.clamp(Vector2(4, 4), WORLD - Vector2(4, 4))
	for a in outside:
		if a.foe == c.id:
			a.foe = 0
			if not a.dead:
				a.n_fights += 1          # came through a fight with it alive
				harmony_n.survived += 1


## The enemy bites an ant: often fatal, otherwise it limps on maimed (a leg or antenna lost).
func _bite(a: Ant, c: Dictionary) -> void:
	if rng.randf() < ENEMY_KINDS[c.kind].STATS.get("lethal", 0.45) or a.hurt >= 0.5:
		_kill(a, "enemy")
	else:
		a.hurt = minf(0.9, a.hurt + 0.5)
		if a.busy > 0:
			a.busy = 0                     # let go
			a.pos += (a.pos - c.pos).normalized() * 5.0


func _shake_off(a: Ant, c: Dictionary) -> void:
	a.vflung = true                 # (for the view: thrown clear, it lands on its back and rights itself)
	a.busy = 0
	a.hurt = minf(0.9, a.hurt + 0.15)
	a.pos = (a.pos + (a.pos - c.pos).normalized() * 7.0).clamp(Vector2(4, 4), WORLD - Vector2(4, 4))


## A worker answering the alarm: run to the nearest enemy, seize it, bite and spray.
func _step_defender(a: Ant) -> void:
	var n := ant_substep
	var c = _creature(a.foe) if a.foe != 0 else null
	if c == null:
		c = _nearest_creature(a.pos, 220.0)
		if c == null:
			_calm(a)
			return
		a.foe = c.id
	var S: Dictionary = ENEMY_KINDS[c.kind].STATS
	var taken := _taken_on(c)
	if a.busy > 0:
		# clinging on: ride with the enemy at its spot, biting and spraying formic acid
		a.pos = _grip(a, c)
		var i := int(c.spots.get(a.id, -1))
		a.ang = Grip.pose(c, ENEMY_KINDS[c.kind], i)[2] if i >= 0 else (c.pos - a.pos).angle()
		a.act = ACT_ATTACK
		c.hp -= ACID * n * (1.0 - S.armor) * float(c.get("load", 1.0)) / maxf(1.0, float(c.held))
		if ((tick + a.id) % 6) < n:
			alarm.deposit(a.pos.x, a.pos.y, 1.5)
		return
	a.act = ACT_ALARM
	a.trip += n
	var spd := _spd * 1.3 * (1.0 - 0.35 * a.hurt)
	a.phase += spd * 0.95
	# close by: make for the nearest free spot on it (its legs, its sides, its back; on a nestmate holding one when the
	# colony is big enough to pile up - enemies/grip_spots.gd)
	var spot := -1
	if a.pos.distance_squared_to(c.pos) < pow(S.r + Grip.SEEK_PX, 2):
		spot = Grip.free_spot(c, ENEMY_KINDS[c.kind], taken, a.pos, Grip.layers(workers.size()))
	var to: Vector2 = (Grip.at(c, ENEMY_KINDS[c.kind], spot) if spot >= 0 else c.pos) - a.pos
	if spot >= 0 and to.length() < 3.0 + spd:
		c.spots[a.id] = spot
		taken[spot] = a.id
		c.held += 1
		a.busy = 1
		a.pos += to
		return
	if spot < 0 and to.length() < S.r + 8.0:
		a.ang = to.angle() + PI * 0.5 * a.slide       # no room on it: circle round, snapping
	else:
		a.ang = to.angle() + rng.randf_range(-0.25, 0.25) * _noise_k
	if ((a.trip + a.id) % 4) < n:
		alarm.deposit(a.pos.x, a.pos.y, 0.8)
	var np := a.pos + Vector2.from_angle(a.ang) * spd
	if blocked(np):
		a.ang += 1.2 * a.slide
		np = a.pos + Vector2.from_angle(a.ang) * spd
		if blocked(np):
			return
	a.pos = np


## Back to foraging once there is nothing left to fight.
func _calm(a: Ant) -> void:
	a.state = Ant.SEARCH if a.carry == Ant.NONE else Ant.RETURN
	a.busy = 0
	a.act = 0
	a.foe = 0
	a.trip = 0


## The keeper takes every enemy out of the box.
func remove_enemies() -> void:
	if creatures.is_empty():
		return
	var kinds := {}
	for c in creatures:
		_release(c, _clinging(c))
		kinds[c.kind] = true
	creatures.clear()
	for kind in kinds:
		_log(ENEMY_KINDS[kind].CHASED)
