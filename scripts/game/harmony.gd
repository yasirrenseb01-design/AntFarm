extends RefCounted
## Colony Harmony: the points the keeper earns from what the colonies do, spent in the Home shop (the keeper,
## 2026-10-26). One purse for every colony, kept in user://harmony.json.
##   a worker born: BORN (twice that for a big one - the largest fifth of the species' worker sizes, BIG_SIZE), a worker
##   back alive from a fight with an enemy: SURVIVED, a nestmate fed mouth to mouth: FED, a block of soil dug out: DUG.
## Counted by real time, not by the game's: points per event x the real hours one game day takes now, so fast-forward
## earns nothing more and a slower pace nothing less. x1.5 while the game runs (in its window or as the wallpaper),
## x1 for the time away worked out on return, and x0.3 in the wild mode (the garden) either way.

# (a tenth of the first values, v0.11.39 - the keeper, 2026-10-27: smaller numbers, not inflated; the prices too)
const BORN := 1.0
const SURVIVED := 0.6
const FED := 0.05
const DUG := 0.025
const LIVE := 1.5
const AWAY := 1.0
const WILD := 0.3
const GAME_DAYS_PER_HOUR_1X := 60.0     # (1 game day a minute at 1x)
const MAX_POINTS := 1.0e12
# the keeper filling a tank's water when it was under 30 % - more than 70 % in one go (the keeper, 2026-11-03): WATER, at
# most once a tank in WATER_WAIT real seconds (a tank lasts ~25 min at 1x and seconds at 100x: not a tap to farm)
const WATER := 30.0
const WATER_LOW := 0.3
const WATER_WAIT := 3600.0

static var base := "user://"            # (tests point this at a sandbox, as the save store)
var points := 0.0
var water_paid := {}                    # slot (as text) -> the unix time a filling was last paid for
var _last := {}                         # the colony's counts already paid for (sim.harmony_n and nest.dug)
var _sim_id := 0


## Pays for what the colony did since the last call. game_days_per_hour: how many game days pass per real hour now
## (live: speed x 60; time away: the away rate).
func collect(sim, game_days_per_hour: float, live: bool) -> void:
	var now := {"born": int(sim.harmony_n.born), "big": int(sim.harmony_n.big), "survived": int(sim.harmony_n.survived),
		"fed": int(sim.harmony_n.fed), "dug": int(sim.nest.dug)}
	if sim.get_instance_id() != _sim_id:
		_sim_id = sim.get_instance_id()           # (another colony loaded: its counts start from here)
		_last = now
		return
	if game_days_per_hour <= 0.0:
		_last = now
		return
	var raw := 0.0
	for k in now:
		var d: int = now[k] - int(_last.get(k, now[k]))
		if d < 0:
			continue
		raw += d * (BORN if k == "born" else (BORN if k == "big" else (SURVIVED if k == "survived" else (FED if k == "fed" else DUG))))
	_last = now
	var mult := WILD if sim.scenario == "wild" else (LIVE if live else AWAY)
	points = minf(MAX_POINTS, points + raw * mult * GAME_DAYS_PER_HOUR_1X / game_days_per_hour)


func load_purse() -> void:
	points = 0.0
	var path := base + "harmony.json"
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() > 4096:
		return
	var d = JSON.parse_string(f.get_as_text())          # (only a number is taken from it: nothing in the file is run)
	if d is Dictionary and (d.get("points") is float or d.get("points") is int):
		points = clampf(float(d.points), 0.0, MAX_POINTS)
		if not (d.get("v") is float or d.get("v") is int):
			points /= 10.0                              # (earned at v0.11.39's ten-times values)
		var wp = d.get("water_paid")
		water_paid = {}
		if wp is Dictionary:
			for k in wp:
				if k is String and k.is_valid_int() and (wp[k] is float or wp[k] is int) and water_paid.size() < 64:
					water_paid[k] = float(wp[k])


func save_purse() -> void:
	var f := FileAccess.open(base + "harmony.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"points": points, "v": 2, "water_paid": water_paid}))


## The keeper filled that tank's water, which held `before` (0..1): the points it earns (0 if none), added to the purse.
func pay_water(slot: int, before: float) -> float:
	var now := Time.get_unix_time_from_system()
	if before >= WATER_LOW or now - float(water_paid.get(str(slot), 0.0)) < WATER_WAIT:
		return 0.0
	water_paid[str(slot)] = now
	points = minf(MAX_POINTS, points + WATER)
	save_purse()
	return WATER
