extends "res://scripts/sim/parts/sim_foragers.gd"
## Simulation, layer 3 of 5: natural enemies in the outworld and how Lasius niger fights them.
## Each enemy kind lives in its own file under scripts/sim/enemies/ and is registered here;
## sim.creatures holds the ones present (saved as is).
##
## The fight (docs/BIOLOGY.md): an ant that meets an enemy marks the spot with alarm pheromone;
## nestmates that smell it rush in (state DEFEND), seize legs and body with the mandibles and spray
## formic acid into the bite. Clinging ants slow the enemy until it is pinned; it bites back
## (killing or maiming) and shakes ants off; badly hurt it flees, and if it dies it becomes food.

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


## Now and then an enemy finds its way into the box (one at a time); night hunters only after dark.
func _maybe_spawn(dt: float) -> void:
	if not creatures.is_empty():
		return
	for kind in ENEMY_KINDS:
		var S: Dictionary = ENEMY_KINDS[kind].STATS
		if S.get("night", false) and daylight() > 0.15:
			continue
		if rng.randf() < S.rate * dt * season_life():
			_spawn_creature(kind)
			return


## The keeper lets an enemy into the box (HUD enemy panel): it comes in from an edge as a wild one does, by day
## or night, with natural enemies on or off. Returns its id, or 0 when RELEASE_MAX are in already.
## Called between steps like placing food, and drawing only on sim.rng, so a run stays reproducible.
func release_enemy(kind: String) -> int:
	if creatures.size() >= RELEASE_MAX or not ENEMY_KINDS.has(kind):
		return 0
	_spawn_creature(kind)
	creatures[-1]["released"] = true            # (a night hunter let in by day stays out till its time is up)
	log_entries[0].text = T.enemy_released % ENEMY_KINDS[kind].NAME     # (in place of its wild arrival line: "at night" may not be true)
	return creatures[-1].id


## Where on the enemy this ant holds on: round its body (spider) or along its sides (centipede).
func _grip(a: Ant, c: Dictionary, S: Dictionary) -> Vector2:
	if S.get("shape", "round") == "long":
		var along := float((a.id * 7) % 13) / 12.0 - 0.5
		var side := 1.0 if a.id % 2 == 0 else -1.0
		var fwd := Vector2.from_angle(c.ang)
		return c.pos + fwd * along * S.length * 0.9 + fwd.orthogonal() * side * S.width
	var grip := float(a.id % 16) / 16.0 * TAU
	return c.pos + Vector2.from_angle(c.ang + grip) * S.r


func _spawn_creature(kind: String) -> void:
	var c: Dictionary = ENEMY_KINDS[kind].spawn(self)
	c["kind"] = kind
	c["id"] = _next_cid
	_next_cid += 1
	c["hp"] = ENEMY_KINDS[kind].STATS.hp
	c["held"] = 0
	creatures.append(c)


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
		c.held = clinging.size()
		var K = ENEMY_KINDS[c.kind]
		if c.hp <= 0.0:
			_creature_dies(c, clinging)
			gone.append(c)
		elif not K.step(self, c, clinging):
			_release(c, clinging)
			gone.append(c)
	for c in gone:
		creatures.erase(c)


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
	_log(T.enemy_killed % K.NAME, "ok")


func _release(c: Dictionary, clinging: Array) -> void:
	for a in clinging:
		a.busy = 0
		a.act = 0
		a.pos = a.pos.clamp(Vector2(4, 4), WORLD - Vector2(4, 4))
	for a in outside:
		if a.foe == c.id:
			a.foe = 0


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
	if a.busy > 0:
		# clinging on: ride with the enemy at its grip point, biting and spraying formic acid
		a.pos = _grip(a, c, S)
		a.ang = (c.pos - a.pos).angle() if S.get("shape", "round") != "long" else (c.pos - a.pos).angle() + 0.6 * (1.0 if a.id % 2 == 0 else -1.0)
		a.act = ACT_ATTACK
		c.hp -= ACID * n * (1.0 - S.armor)
		if ((tick + a.id) % 6) < n:
			alarm.deposit(a.pos.x, a.pos.y, 1.5)
		return
	a.act = ACT_ALARM
	a.trip += n
	var spd := _spd * 1.3 * (1.0 - 0.35 * a.hurt)
	a.phase += spd * 0.95
	var to: Vector2 = _grip(a, c, S) - a.pos
	if to.length() < 3.0 + spd:
		if c.held < S.hold:
			c.held += 1
			a.busy = 1
			return
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
