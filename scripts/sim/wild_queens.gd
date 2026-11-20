extends RefCounted
## Newly mated queens on the wild plot after a flight (PART 0.14 step 4): the keeper can catch them into a founding
## tube (the Home's desk) and start a colony with one later. Static, given the simulation (sim.ground_queens, saved).
## They come from two places [keeper, 2026-11-18]:
##   - the area's flights: other colonies round the plot fly on warm, calm July-August afternoons, not all on the same
##     day [A5]; on such an afternoon a few of their queens come down on this plot [chosen: AREA_CHANCE, 1-3 queens],
##   - this colony's own gynes, once it makes them (sim/alates.gd): a few of those that flew come down on it again,
##     mated [chosen: OWN_BACK - most fly off far].
## A mated queen sheds her wings and starts her nest at once [A8]: she walks a while looking for a spot, then digs in
## and is gone (WALK_H, GONE_H [chosen]). Her weight, against the mean, is drawn as a founding queen's is (0.78-1.25,
## Fjerdingstad & Keller 2004 [A7]); an own gyne's from how well she was fattened (sim/alates.gd "w").
## Nothing here draws on sim.rng (each colony's chances stay as they were): a generator of its own per day, seeded from
## the colony's seed and the day.

const AREA_CHANCE := 0.18       # a flight afternoon (warm, dry, calm) in July-August: chance the area's colonies fly
                                # (~8 days a summer) [chosen]
const AREA_MOST := 3            # queens coming down on the plot that afternoon: 1 to this [chosen; a plot ~0.2 m2]
const OWN_BACK := 0.25          # of this colony's gynes that fly, the share coming down on its plot [chosen]
const WALK_H := 3.0             # hours she walks about before digging in (her own: 2-4) [chosen]
const GONE_H := 5.0             # hours after landing she is gone into the soil [chosen; A8: she founds at once]
const SPEED := 0.25             # px a tick walking (~0.4 of a worker's: a heavy queen, looking for a spot) [chosen]
const LAND_TOD := 0.75          # she comes down at ~18:00 [keepers: flights in the late afternoon to evening]
const MOST := 12                # on the plot at once at most


## Each colony tick (sim_colony._colony, wild only): the area's flight lands its queens this afternoon; those gone into
## the soil leave the list.
static func step(s) -> void:
	if s.scenario != "wild":
		return
	var t: int = s.tick
	for i in range(s.ground_queens.size() - 1, -1, -1):
		if t > int(s.ground_queens[i].t0) + int(GONE_H * s.TPD / 24.0):
			s.ground_queens.remove_at(i)
	var today: int = s.day()
	if int(s.stats.get("area_fly", 0)) == today or s.time_of_day() < LAND_TOD:
		return
	s.stats["area_fly"] = today
	var d: float = s.doy_f()
	if d < 182.0 or d > 243.0 or s.climate.raining():
		return
	if s.climate.air_at(0.67, false) <= 13.0 or s.wind(0.67) >= s.climate.WIND_MOST:
		return                          # (16:00 too cool or too windy: none flew round here today [A5])
	var g := _gen(s, today)
	if g.randf() >= AREA_CHANCE:
		return
	var n := 1 + g.randi_range(0, AREA_MOST - 1)
	for i in n:
		_land(s, g, clampf(g.randfn(1.0, 0.12), 0.78, 1.25), "area")
	s._log(s.T.queens_landed, "ok", [n])


## This colony's own flight (sim/alates.gd _fly): a few of its gynes come down on the plot, mated. `weights`: each
## gyne's fattening (her "w" / GYNE_COST).
static func own_flight(s, weights: Array) -> void:
	if s.scenario != "wild" or weights.is_empty():
		return
	var g := _gen(s, s.day() * 7 + 3)
	var n := 0
	for w in weights:
		if g.randf() < OWN_BACK:
			_land(s, g, clampf(float(w) * g.randfn(1.0, 0.05), 0.78, 1.25), "own")
			n += 1
	if n > 0:
		s._log(s.T.queens_landed_own, "ok", [n])


static func _gen(s, n: int) -> RandomNumberGenerator:
	var g := RandomNumberGenerator.new()
	g.seed = (int(s.rng.seed) ^ 0x3C6EF372 ^ (n * 0x9E3779B1)) & 0x7fffffff | 1
	return g


static func _land(s, g: RandomNumberGenerator, w: float, from: String) -> void:
	if s.ground_queens.size() >= MOST:
		return
	var at := Vector2.ZERO
	for tries in 12:                  # (not on a stone, not in the entrance)
		at = Vector2(g.randf_range(40.0, s.WORLD.x - 40.0), g.randf_range(40.0, s.WORLD.y - 40.0))
		var i: int = s.home.index(at.x, at.y)
		if i >= 0 and s.rock[i] == 0 and at.distance_to(s.nest_pos) > 40.0:
			break
	s.ground_queens.append({"id": _next_id(s), "x": at.x, "y": at.y, "a": g.randf() * TAU,
		"walk": g.randf_range(2.0, 4.0), "t0": int(s.tick), "w": snappedf(w, 0.001), "from": from})


## A queen's id: a counter of her own (sim.stats "gq_id", saved), not the creatures' (sim._next_cid) - until v0.14.2
## she took the next creature id, so every queen landing moved the ids of the enemies after her, and with them which
## way each turns at a wall (int(id) % 2): an unkept wild colony's run changed though nothing new drew on sim.rng.
## Above every queen on the plot, so a save from v0.14.2 (ids taken from the creatures' counter) never gets two alike.
static func _next_id(s) -> int:
	var id: int = int(s.stats.get("gq_id", 1))
	for q in s.ground_queens:
		id = maxi(id, int(q.id) + 1)
	s.stats["gq_id"] = id + 1
	return id


## Where a queen is now (px), and whether she is still walking: out from where she came down, wandering a little
## (worked out from the tick: nothing to save but where and when she landed).
static func pos_of(s, q: Dictionary) -> Vector2:
	var hours: float = float(int(s.tick) - int(q.t0)) / s.TPD * 24.0
	var walked := minf(hours, float(q.walk))
	var ticks: float = walked / 24.0 * s.TPD
	var dir := Vector2.from_angle(float(q.a) + 0.5 * sin(walked * 1.7))
	var p: Vector2 = Vector2(float(q.x), float(q.y)) + dir * SPEED * ticks * 0.35          # (she stops and turns: ~a third)
	return Vector2(clampf(p.x, 10.0, s.WORLD.x - 10.0), clampf(p.y, 10.0, s.WORLD.y - 10.0))


static func walking(s, q: Dictionary) -> bool:
	return float(int(s.tick) - int(q.t0)) / s.TPD * 24.0 < float(q.walk)


## The keeper caught her (outworld click): off the plot; what to keep of her ({} if she is not there).
static func catch(s, id: int) -> Dictionary:
	for i in s.ground_queens.size():
		if int(s.ground_queens[i].id) == id:
			var q: Dictionary = s.ground_queens[i]
			s.ground_queens.remove_at(i)
			s._log(s.T.queen_caught, "ok")
			return {"w": float(q.w), "from": String(q.from), "day": int(s.day())}
	return {}


## The queens of a save, each checked (sim/alates.gd from_save: user:// files are anyone's to edit).
static func from_save(s, d: Dictionary) -> void:
	s.ground_queens = []
	var v = d.get("ground_queens", [])
	if not v is Array:
		return
	for q in v:
		if not q is Dictionary or s.ground_queens.size() >= MOST:
			continue
		var ok := true
		for k in ["id", "x", "y", "a", "walk", "t0", "w"]:
			if not (q.get(k) is int or q.get(k) is float):
				ok = false
		if ok:
			s.ground_queens.append({"id": int(q.id), "x": clampf(float(q.x), 0.0, 4000.0), "y": clampf(float(q.y), 0.0, 4000.0),
				"a": float(q.a), "walk": clampf(float(q.walk), 0.0, 24.0), "t0": int(q.t0), "w": clampf(float(q.w), 0.78, 1.25),
				"from": "own" if String(q.get("from", "")) == "own" else "area"})


## A new colony started with a queen from a founding tube (main, the new-colony window): her weight is the colony's
## founding queen's (traits "queen": her eggs and her reserve [A7]) - the rest of its character as drawn.
static func found_with(s, w: float) -> void:
	s.traits["queen"] = clampf(w, 0.78, 1.25)
	s.queen.reserve = s.sp["queen_reserve"] * s.colony_trait("queen")
	s._log(s.T.founding_tube, "ok")
