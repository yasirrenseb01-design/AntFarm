extends RefCounted
## Simulation, layer 1 of 5: all colony and outworld state, setup, time, the keeper's actions,
## shared helpers (log, warnings, deaths). Layers: sim_base <- sim_foragers <- sim_enemies <- sim_colony <- simulation.

const Ant := preload("res://scripts/sim/ant.gd")
const Field := preload("res://scripts/sim/pheromone_field.gd")
const Climate := preload("res://scripts/sim/climate.gd")
const LasiusNiger := preload("res://scripts/sim/species/lasius_niger.gd")
const NestVolume := preload("res://scripts/sim/nest_volume.gd")
const T := preload("res://scripts/sim/text_th.gd")     # journal texts
const FoodKinds := preload("res://scripts/sim/food_kinds.gd")

signal logged(entry: Dictionary)

const TPD := 3600                    # ticks per game day (60 s at 1×)
const WORLD := Vector2(1200, 750)    # outworld in px, 1 px ≈ 0.5 mm → 60 × 37.5 cm box
const CELL := 5.0
const NEST_R := 9.0
const COLONY_EVERY := 20             # colony bookkeeping runs every N ticks
const SENSE_EVERY := 4               # ants re-read pheromone gradients every N ticks
const INV_CELL := 1.0 / CELL

const HOME_EVAP := 0.9995
const FOOD_EVAP := 0.9993
const RAIN_EVAP := 0.985
const ALARM_EVAP := 0.97             # alarm pheromone is volatile: gone within a minute or two

var sp: Dictionary = LasiusNiger.DATA
var rng := RandomNumberGenerator.new()
var tick := 0
var climate: Climate
var nest: NestVolume
var diggers_wanted := 0
var home: Field
var food: Field
var alarm: Field                     # alarm pheromone around a fight (formic acid, undecane)
var gw := 0
var gh := 0
var rock := PackedByteArray()
var rocks: Array = []
var nest_pos := Vector2(480, 400)
var midden_pos := Vector2(575, 480)
var foods: Array = []
var corpses: Array = []
var workers: Array = []
var outside: Array = []               # workers currently in the outworld (rebuilt each colony tick)
var eggs: Array = []
var larvae: Array = []
var pupae: Array = []
var queen := {"alive": true, "starve": 0.0, "reserve": 0.0}   # reserve: fat body + dissolved wing muscle
var sugar := 6.0
var sugar_income := 0.0             # sugar brought home, averaged over about a week (units per week)
var sugar_spend := 0.0              # sugar eaten by the colony, averaged the same way
var fat := 0.0                     # food stored in the workers' fat bodies (what carries a colony through winter)
var protein := 3.0
var humidity := 0.7
var mold := 0.0
var heater := false
var enemies := true
var _next_cid := 1                 # next creature id
var creatures: Array = []          # enemies in the outworld: {"kind", "pos", ...} (see parts/sim_enemies.gd)
var corpses_inside := 0
var scenario := "keeper"          # "keeper" (indoor formicarium) or "wild" (a plot of ground; seasons, enemies)
var start_doy := 205               # day of the year the colony started (a founding queen: late July)
var fridge_on := false             # keeper: the formicarium is in the fridge for its winter rest
var cold_days := 0                 # days this winter with the nest below 10 °C (the queen's winter rest)
var egg_acc := 0.0
## dead = workers (dead_by: starve, thirst, old, out = lost while foraging, enemy); brood_dead = eggs, larvae
## and pupae lost to drought, mould or heat (larvae eaten by hungry workers are counted in cannibalized)
var stats := {"dead": 0, "cannibalized": 0, "born": 0, "sugar_in": 0, "protein_in": 0, "brood_dead": 0, "dead_by": {}}
var history: Array = []
var log_entries: Array = []

# Recent life-cycle moments for the views to animate ("egg" laid, larva "pupate"d, worker "eclose"d).
# Not part of the saved state and never read by the simulation itself.
var events: Array = []
var event_seq := 0

# derived each colony tick, read by the UI
var nurses := 0
var callow := 0
var out_count := 0
var dev := 0.5
var activity := 0.5
var starving := false
var queen_fed := true
var hungry := false

var _warned := {}
var _next_id := 1
var _any_dead := false
var _cannibal_cd := 0.0
var _spd := 0.5
var _want_sugar := true
var _want_protein := true
var food_cell := PackedInt32Array()     # per pheromone cell: index of a food within smelling range, or -1
var _food_dirty := true
var prof := {"colony": 0, "grid": 0, "ants": 0, "other": 0, "steps": 0, "grids": 0}
var _noise_k := 1.0
var _recruits := 0                       # nestmates excited by successful foragers, sent out next colony tick
var ant_substep := 1                     # >1 at high game speeds: each ant moves every N ticks with N× stride
var _log_home := log(HOME_EVAP)
var _log_food := log(FOOD_EVAP)
var _log_rain := log(RAIN_EVAP)
var _log_alarm := log(ALARM_EVAP)


# ---------------------------------------------------------------- setup

func setup(seed_value: int = 0, start_workers: int = 14, glass_nest := false, scen := "keeper") -> void:
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	gw = int(WORLD.x / CELL)
	gh = int(WORLD.y / CELL)
	home = Field.new(gw, gh, CELL)
	food = Field.new(gw, gh, CELL)
	alarm = Field.new(gw, gh, CELL)
	rock.resize(gw * gh)
	rock.fill(0)
	food_cell.resize(gw * gh)
	food_cell.fill(-1)
	climate = Climate.new(rng)
	scenario = scen
	climate.scenario = scen
	# a lone queen starts just after the summer mating flight; a young colony in spring
	start_doy = 205 if start_workers == 0 else 105
	enemies = scen == "wild"         # a keeper's formicarium has no wild predators
	queen["rested"] = 1.0
	nest = NestVolume.new()
	nest.setup(rng, glass_nest, start_workers == 0)
	tick = int(TPD * 0.29)
	climate.doy = doy_f()
	climate.settle(time_of_day(), heater)

	for r in [[160, 150, 34], [820, 330, 26], [858, 372, 18], [660, 650, 28], [300, 540, 15],
			[1070, 630, 42], [520, 170, 13], [1010, 110, 22], [90, 420, 20]]:
		add_rock(Vector2(r[0], r[1]), r[2])

	for i in start_workers:
		var w := _new_worker(rng.randf_range(5.0, 90.0))
		var ns: Array = sp["nanitic_size"]
		w.size = clampf(rng.randfn(ns[0], ns[1]), ns[2], ns[3])    # first-generation nanitics are small
		workers.append(w)
	var k := start_workers / 14.0
	for i in int(9 * k):
		eggs.append({"p": rng.randf()})
	for i in int(7 * k):
		larvae.append({"p": rng.randf(), "h": 0.0, "q": 0.6})
	for i in int(4 * k):
		pupae.append({"p": rng.randf(), "s": clampf(rng.randfn(0.84, 0.04), 0.75, 0.95)})
	sugar = sugar_cap() * 0.5 if start_workers > 0 else 0.0
	protein = 3.0 * k
	# a young colony starts out earning comfortably more than it eats (a week's worth of each)
	sugar_spend = 7.0 * (start_workers * sp["sugar_worker"] + sp["sugar_queen"])
	sugar_income = sugar_spend * 1.5
	if start_workers == 0:
		# Claustral founding: a newly mated queen seals herself in a small chamber and raises the first
		# workers alone, living on her fat body and the muscles of the wings she has shed.
		queen.reserve = sp["queen_reserve"]
		for i in int(sp["founding_eggs"]):
			eggs.append({"p": rng.randf() * 0.3})

	place_food("aphids", Vector2(985, 230))
	place_food("aphids", Vector2(210, 640))
	place_food("cricket", Vector2(760, 560))
	if scen == "wild":
		# a queen founds her nest near a plant with aphids on it: the colony's first sugar is close by
		for off in [Vector2(115, -55), Vector2(-110, -70), Vector2(100, 80), Vector2(-120, 60)]:
			if place_food("aphids", nest_pos + off):
				break

	history.append(_snapshot())
	if scen == "wild":
		_log(T.wild_start, "ok")
	if start_workers == 0:
		_log(T.founding_sealed)
		_log(T.founding_reserves, "ok")
	else:
		_log(T.young_colony % start_workers)
		_log(T.young_needs_protein, "ok")


## Adult size is fixed at pupation: well-fed larvae and nurses in a big colony make bigger workers.
## Lasius niger workers range ~3–5 mm; 1.0 = a typical 4.2 mm worker.
func _adult_size(fed: float) -> float:
	var colony := clampf(workers.size() / 150.0, 0.0, 1.0)
	return clampf(0.76 + 0.16 * fed + 0.1 * colony + rng.randfn(0.0, 0.035), 0.7, 1.15)


## True while a lone queen is still raising her first workers on her own reserves.
func founding() -> bool:
	return queen.alive and workers.size() < 3 and queen.reserve > 0.0


func mean_worker_mm() -> float:
	if workers.is_empty():
		return 0.0
	var s := 0.0
	for w in workers:
		s += w.size
	return s / workers.size() * 4.2


func _new_worker(age_days: float) -> Ant:
	var a := Ant.new()
	a.id = _next_id
	_next_id += 1
	a.age = age_days
	a.life = rng.randf_range(sp["worker_life_min"], sp["worker_life_max"])
	a.hardiness = clampf(rng.randfn(1.0, 0.25), 0.5, 1.6)
	a.slide = 1.0 if rng.randf() < 0.5 else -1.0
	return a


# ---------------------------------------------------------------- time

func day() -> int:
	return tick / TPD + 1


func time_of_day() -> float:
	return float(tick % TPD) / TPD


func clock_text() -> String:
	var m := int(time_of_day() * 1440.0)
	return "%02d:%02d" % [m / 60, m % 60]


## Height of the sun (-1..1 at noon); outdoors the days are longer in summer than in winter.
func sun_height() -> float:
	var c := sin(PI * (climate.day_hours() / 24.0 - 0.5))
	return sin(TAU * (time_of_day() - 0.25)) + c


func daylight() -> float:
	return clampf(sun_height() * 1.6 + 0.2, 0.0, 1.0)


# ---------------------------------------------------------------- calendar

const MONTHS := ["ม.ค.", "ก.พ.", "มี.ค.", "เม.ย.", "พ.ค.", "มิ.ย.", "ก.ค.", "ส.ค.", "ก.ย.", "ต.ค.", "พ.ย.", "ธ.ค."]
const MONTH_DAYS := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]


## Day of the year as a float (0 = 1 January), including the time of day.
func doy_f() -> float:
	return fmod(float(start_doy) + float(tick) / TPD - 0.29, 365.0)


func year() -> int:
	return int((float(start_doy) + float(tick) / TPD - 0.29) / 365.0) + 1


func date_text() -> String:
	var d := int(doy_f())
	var m := 0
	while m < 11 and d >= MONTH_DAYS[m]:
		d -= MONTH_DAYS[m]
		m += 1
	return "%d %s" % [d + 1, MONTHS[m]]


func season_name() -> String:
	var d := doy_f()
	if d < 59 or d >= 334:
		return "ฤดูหนาว"
	if d < 151:
		return "ใบไม้ผลิ"
	if d < 243:
		return "ฤดูร้อน"
	return "ใบไม้ร่วง"


## How much the outdoors is alive (aphids, flies, wandering predators): 0 in the cold, 1 when warm.
func season_life() -> float:
	return clampf((climate.season_mean() - 6.0) / 6.0, 0.0, 1.0)


## Whether the colony is in its winter rest: outdoors, the cold months with a cold nest; indoors,
## the formicarium cooled down in the fridge. (Not the hour's temperature, which crosses any line daily.)
func hibernating() -> bool:
	if scenario == "wild":
		return climate.season_mean() < 9.0 and climate.nest < 12.0
	return climate.fridge > 0.5


## Ants are cold-blooded: their metabolism changes ~2.5-fold per 10 °C (Q10), 1.0 at a room's 22 °C.
## Below ~8 °C Lasius niger falls into a chill torpor and barely burns anything, which is how a colony
## lives through four months of winter on what it stored in autumn.
func cold_factor(t: float) -> float:
	var q := pow(2.5, (t - 22.0) / 10.0)
	if t < 8.0:
		q *= lerpf(0.15, 1.0, clampf((t - 2.0) / 6.0, 0.0, 1.0))
	return clampf(q, 0.02, 1.3)


func cycle_days() -> float:
	if dev < 0.01:
		return INF
	return (sp["egg_days"] + sp["larva_days"] + sp["pupa_days"]) / dev


# ---------------------------------------------------------------- player actions

func can_place(p: Vector2) -> bool:
	var i: int = home.index(p.x, p.y)
	return i >= 0 and rock[i] == 0 and p.distance_to(nest_pos) > 22.0


func place_food(kind: String, p: Vector2) -> bool:
	if not can_place(p):
		return false
	var k := FoodKinds.info(kind)
	if k.is_empty():
		return false
	var f := {"kind": kind, "pos": p, "found": false, "age": 0.0, "seed": rng.randi(), "rotten": false,
		"ang": rng.randf() * TAU}
	f.merge({"type": k.type, "amt": k.amt, "cap": k.cap, "regen": k.regen, "r": k.r})
	foods.append(f)
	_food_dirty = true
	return true


func add_water() -> void:
	humidity = minf(1.0, humidity + 0.35)
	_log(T.water_added % int(humidity * 100))


func add_rock(p: Vector2, r: float) -> bool:
	if p.distance_to(nest_pos) < r + 24.0 or p.distance_to(midden_pos) < r + 10.0:
		return false
	for f in foods:
		if p.distance_to(f.pos) < r + f.r:
			return false                    # never bury food under a stone
	var x0 := maxi(0, int((p.x - r) / CELL))
	var x1 := mini(gw - 1, int((p.x + r) / CELL))
	var y0 := maxi(0, int((p.y - r) / CELL))
	var y1 := mini(gh - 1, int((p.y + r) / CELL))
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			if Vector2(cx * CELL + CELL * 0.5, cy * CELL + CELL * 0.5).distance_to(p) <= r:
				var i := cy * gw + cx
				rock[i] = 1
				home.clear_i(i)
				food.clear_i(i)
	var poly := PackedVector2Array()
	var s := rng.randf() * 100.0
	for k in 14:
		var a := TAU * k / 14.0
		var rr := r * (0.86 + 0.18 * sin(s + k * 1.9) + 0.08 * sin(s * 0.7 + k * 3.7))
		poly.append(p + Vector2.from_angle(a) * rr)
	rocks.append({"pos": p, "r": r, "poly": poly, "tone": rng.randf()})
	_restamp_rocks()
	# ants caught where the stone lands scramble out to its edge
	for a in outside:
		var d: Vector2 = a.pos - p
		if d.length() < r + 3.0:
			var dir := d.normalized() if d.length() > 0.01 else Vector2.from_angle(rng.randf() * TAU)
			# nearest free spot just outside the new stone (not inside a neighbouring one)
			for k in 16:
				var tryd := dir.rotated((k / 2) * 0.4 * (1 if k % 2 == 0 else -1))
				var q := p + tryd * (r + 4.0 + (k / 8) * 6.0)
				if not blocked(q):
					a.pos = q
					a.ang = tryd.angle()
					break
	for c in creatures:
		if c.pos.distance_to(p) < r + 6.0:
			c.pos = p + (c.pos - p).normalized() * (r + 8.0)
	# a small stone that now touches the new one has become part of a wall: ants on it step off
	for a in outside:
		if blocked(a.pos):
			for rk in rocks:
				var d: Vector2 = a.pos - rk.pos
				if d.length() < float(rk.r) + 1.0:
					a.pos = (rk.pos + (d.normalized() if d.length() > 0.01 else Vector2.RIGHT) * (float(rk.r) + 4.0)).clamp(Vector2(4, 4), WORLD - Vector2(4, 4))
					break
	return true


## Stones on the floor: a single stone up to CLIMB_R across is climbed over (rock cells = 2: walkable, slower);
## a larger stone, or stones touching others (a wall or heap the keeper laid), is walked round (cells = 1).
## Ants climb any small obstacle in nature; the size limit (and walls staying walls) is a choice for the
## keeper's sake (user, 2026-10-12), not a measured figure.
const CLIMB_R := 15.0          # px radius (~1.5 cm across)

func _restamp_rocks() -> void:
	for rk in rocks:
		var small: bool = float(rk.r) <= CLIMB_R
		if small:
			for o in rocks:
				if not is_same(o, rk) and (o.pos as Vector2).distance_to(rk.pos) < float(o.r) + float(rk.r):
					small = false
					break
		rk.climb = small
	rock.fill(0)
	for climbable in [true, false]:              # blocking stones are stamped over climbable ones
		for rk in rocks:
			if bool(rk.climb) != climbable:
				continue
			var p: Vector2 = rk.pos
			var r: float = rk.r
			for cy in range(maxi(0, int((p.y - r) / CELL)), mini(gh - 1, int((p.y + r) / CELL)) + 1):
				for cx in range(maxi(0, int((p.x - r) / CELL)), mini(gw - 1, int((p.x + r) / CELL)) + 1):
					if Vector2(cx * CELL + CELL * 0.5, cy * CELL + CELL * 0.5).distance_to(p) <= r:
						rock[cy * gw + cx] = 2 if climbable else 1


func erase_pheromones(p: Vector2, r: float) -> void:
	home.clear_circle(p, r)
	food.clear_circle(p, r)


func _snapshot() -> Dictionary:
	return {"day": day(), "workers": workers.size(), "brood": eggs.size() + larvae.size() + pupae.size(),
		"sugar": sugar, "protein": protein}


func target_air() -> int:
	# open volume a colony maintains grows in step with its population
	return int(80 + 22 * (workers.size() + (eggs.size() + larvae.size() + pupae.size()) * 0.25))


## Outdoors, once the days shorten below ~13½ hours (late August) the colony winds down for winter:
## the queen stops laying, the last brood is reared out and the workers fatten up.
func winding_down() -> bool:
	var d := doy_f()
	return scenario == "wild" and d > 172.0 and climate.day_hours() < 13.5


## How much the workers can lay down as body fat: roughly a winter's worth each.
func fat_cap() -> float:
	return workers.size() * 1.6


func sugar_cap() -> float:
	return 10.0 + workers.size() * 2.5


func protein_cap() -> float:
	return 6.0 + larvae.size() * 1.2 + workers.size() * 0.3


func satiated() -> bool:
	return sugar > sugar_cap() * 0.8 and protein > protein_cap() * 0.6


func _cull(list: Array, p: float) -> void:
	for i in range(list.size() - 1, -1, -1):
		if rng.randf() < p:
			list.remove_at(i)
			stats.brood_dead += 1


func _warn(key: String, on: bool, text: String) -> void:
	# announce when a problem starts; repeat at most every two days while it flickers on and off
	if on and not _warned.get(key, false):
		_warned[key] = true
		if tick - int(_warned.get(key + "_t", -TPD * 10)) > TPD * 2:
			_warned[key + "_t"] = tick
			_log(text, "bad")
	elif not on:
		_warned[key] = false


func _kill(a: Ant, cause := "other") -> void:
	if a.dead:
		return
	a.dead = true
	_any_dead = true
	stats.dead += 1
	stats.dead_by[cause] = int(stats.dead_by.get(cause, 0)) + 1
	if a.state == Ant.IN_NEST:
		corpses_inside += 1
	else:
		corpses.append({"pos": a.pos, "ang": a.ang, "age": 0.0})
		if a.carry == Ant.CORPSE:
			corpses.append({"pos": a.pos + Vector2(4, 2), "ang": a.ang + 1.0, "age": 0.0})


func blocked(p: Vector2) -> bool:
	if p.x < 3.0 or p.y < 3.0 or p.x > WORLD.x - 3.0 or p.y > WORLD.y - 3.0:
		return true
	return rock[home.index(p.x, p.y)] == 1           # (2: a small stone, climbed over)


# ---------------------------------------------------------------- log

func _event(kind: String, size := 1.0) -> void:
	event_seq += 1
	events.append({"n": event_seq, "k": kind, "s": size})
	if events.size() > 24:
		events.pop_front()


func _log(text: String, kind: String = "") -> void:
	var e := {"stamp": "ว.%d %s" % [day(), clock_text()], "text": text, "kind": kind}
	log_entries.push_front(e)
	if log_entries.size() > 80:
		log_entries.pop_back()
	logged.emit(e)


# ---------------------------------------------------------------- save / load

const SAVE_VERSION := 7              # raise together with a step in save_migrations.gd
const ANT_FIELDS := ["id", "age", "life", "state", "pos", "ang", "carry", "trip", "since", "energy", "size",
	"hardiness", "patience", "follow", "slide", "busy", "act", "meet_cd", "turn_after", "phase", "caste", "foe", "hurt"]
