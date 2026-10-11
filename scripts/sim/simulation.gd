extends RefCounted
## Colony + outworld simulation. Pure data and no nodes, so it can run headless
## (self-tests now, offline catch-up later).

const Ant := preload("res://scripts/sim/ant.gd")
const Field := preload("res://scripts/sim/pheromone_field.gd")
const Climate := preload("res://scripts/sim/climate.gd")
const LasiusNiger := preload("res://scripts/sim/species/lasius_niger.gd")
const NestVolume := preload("res://scripts/sim/nest_volume.gd")

signal logged(entry: Dictionary)

const TPD := 3600                    # ticks per game day (60 s at 1×)
const WORLD := Vector2(1200, 750)    # outworld in px, 1 px ≈ 0.5 mm → 60 × 37.5 cm box
const CELL := 5.0
const NEST_R := 9.0
const QUEEN_RESERVE := 90.0          # body reserves of a newly mated queen, in food units
const COLONY_EVERY := 20             # colony bookkeeping runs every N ticks
const SENSE_EVERY := 4               # ants re-read pheromone gradients every N ticks
const INV_CELL := 1.0 / CELL

const HOME_EVAP := 0.9995
const FOOD_EVAP := 0.9993
const RAIN_EVAP := 0.985

var sp: Dictionary = LasiusNiger.DATA
var rng := RandomNumberGenerator.new()
var tick := 0
var climate: Climate
var nest: NestVolume
var diggers_wanted := 0
var home: Field
var food: Field
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
var protein := 3.0
var humidity := 0.7
var mold := 0.0
var heater := false
var enemies := true
var spider: Dictionary = {}
var corpses_inside := 0
var egg_acc := 0.0
var stats := {"dead": 0, "cannibalized": 0, "born": 0, "sugar_in": 0, "protein_in": 0}
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


# ---------------------------------------------------------------- setup

func setup(seed_value: int = 0, start_workers: int = 14, glass_nest := false) -> void:
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	gw = int(WORLD.x / CELL)
	gh = int(WORLD.y / CELL)
	home = Field.new(gw, gh, CELL)
	food = Field.new(gw, gh, CELL)
	rock.resize(gw * gh)
	rock.fill(0)
	food_cell.resize(gw * gh)
	food_cell.fill(-1)
	climate = Climate.new(rng)
	nest = NestVolume.new()
	nest.setup(rng, glass_nest, start_workers == 0)
	tick = int(TPD * 0.29)
	climate.settle(time_of_day(), heater)

	for r in [[160, 150, 34], [820, 330, 26], [858, 372, 18], [660, 650, 28], [300, 540, 15],
			[1070, 630, 42], [520, 170, 13], [1010, 110, 22], [90, 420, 20]]:
		add_rock(Vector2(r[0], r[1]), r[2])

	for i in start_workers:
		var w := _new_worker(rng.randf_range(5.0, 90.0))
		w.size = clampf(rng.randfn(0.8, 0.04), 0.72, 0.9)    # first-generation nanitics are small
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
	if start_workers == 0:
		# Claustral founding: a newly mated queen seals herself in a small chamber and raises the first
		# workers alone, living on her fat body and the muscles of the wings she has shed.
		queen.reserve = QUEEN_RESERVE
		for i in 3:
			eggs.append({"p": rng.randf() * 0.3})

	place_food("aphids", Vector2(985, 230))
	place_food("aphids", Vector2(210, 640))
	place_food("cricket", Vector2(760, 560))

	history.append(_snapshot())
	if start_workers == 0:
		_log("ราชินีที่เพิ่งผสมพันธุ์สลัดปีกทิ้ง ขุดห้องเล็กแล้วปิดตัวเองอยู่ในนั้น (ก่อตั้งรังแบบปิด)")
		_log("เธอจะเลี้ยงลูกรุ่นแรกด้วยไขมันสะสมในตัวโดยไม่ออกหาอาหาร มดงานตัวแรกใช้เวลาราว 6–8 สัปดาห์", "ok")
	else:
		_log("รังอายุราว 3 เดือน: ราชินี 1 ตัว มดงาน %d ตัว เริ่มบันทึกการสังเกต" % start_workers)
		_log("ตัวอ่อนต้องการโปรตีน มีจิ้งหรีดตายวางอยู่ทางขวาล่างของกล่อง", "ok")


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


func daylight() -> float:
	return clampf(sin(TAU * (time_of_day() - 0.25)) * 1.6 + 0.2, 0.0, 1.0)


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
	var f := {"kind": kind, "pos": p, "found": false, "age": 0.0, "seed": rng.randi(), "rotten": false,
		"ang": rng.randf() * TAU}
	match kind:
		"aphids":
			f.merge({"type": Ant.SUGAR, "amt": 10.0, "cap": 16.0, "regen": 9.0, "r": 16.0})
		"honey":
			f.merge({"type": Ant.SUGAR, "amt": 25.0, "cap": 25.0, "regen": 0.0, "r": 8.0})
		"cricket":
			f.merge({"type": Ant.PROTEIN, "amt": 30.0, "cap": 30.0, "regen": 0.0, "r": 12.0})
		"fly":
			f.merge({"type": Ant.PROTEIN, "amt": 6.0, "cap": 6.0, "regen": 0.0, "r": 5.0})
		_:
			return false
	foods.append(f)
	_food_dirty = true
	return true


func add_water() -> void:
	humidity = minf(1.0, humidity + 0.35)
	_log("เติมน้ำในแท็งก์น้ำของรัง ความชื้น %d%%" % int(humidity * 100))


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
	if not spider.is_empty() and spider.pos.distance_to(p) < r + 6.0:
		spider.pos = p + (spider.pos - p).normalized() * (r + 8.0)
	return true


func erase_pheromones(p: Vector2, r: float) -> void:
	home.clear_circle(p, r)
	food.clear_circle(p, r)


# ---------------------------------------------------------------- main step

func step() -> void:
	tick += 1
	if tick % TPD == 0:
		_new_day()
	climate.update(time_of_day(), heater, TPD)
	var raining: bool = climate.raining()
	if raining:
		climate.rain_ticks -= 1
		if climate.rain_ticks == 0:
			_log("ฝนหยุดแล้ว เส้นทางกลิ่นส่วนใหญ่ถูกชะล้างไป")
	home.decay(_log_rain if raining else _log_home)
	food.decay(_log_rain if raining else _log_food)
	var t0 := Time.get_ticks_usec()
	if tick % COLONY_EVERY == 0:
		_colony(float(COLONY_EVERY) / TPD)
	if tick % NestVolume.STEP_EVERY == 0:
		var tn := Time.get_ticks_usec()
		nest.step(tick, diggers_wanted, target_air(), humidity)
		prof.nest = prof.get("nest", 0) + Time.get_ticks_usec() - tn
	var t1 := Time.get_ticks_usec()
	_spd = sp["walk_speed"] * (0.35 + 0.65 * activity)
	_want_sugar = sugar < sugar_cap() * 0.95
	_want_protein = protein < protein_cap() * 0.95
	if _food_dirty:
		_rebuild_food_grid()
		prof.grids += 1
	var t2 := Time.get_ticks_usec()
	var n := maxi(1, ant_substep)
	var phase := tick % n
	_noise_k = sqrt(n)
	if n > 1:
		_spd *= n
	if tick % 4 == 0:
		_encounters()
	for a: Ant in outside:
		if a.state != Ant.IN_NEST and not a.dead and (n == 1 or a.id % n == phase):
			_step_ant(a)
			prof.steps += 1
	var t3 := Time.get_ticks_usec()
	if not spider.is_empty():
		_step_spider()
	if _any_dead:
		workers = workers.filter(func(w): return not w.dead)
		outside = outside.filter(func(w): return not w.dead)
		_any_dead = false
	var t4 := Time.get_ticks_usec()
	prof.colony += t1 - t0
	prof.grid += t2 - t1
	prof.ants += t3 - t2
	prof.other += t4 - t3


## Two foragers meeting head-on stop for a moment and drum each other with their antennae
## (how Lasius check nestmate scent and pass on news of food).
func _encounters() -> void:
	var grid := {}
	for a: Ant in outside:
		if a.busy > 0 or a.meet_cd > 0 or a.state == Ant.IN_NEST:
			continue
		var k := Vector2i(int(a.pos.x / 6.0), int(a.pos.y / 6.0))
		var o = grid.get(k)
		if o == null:
			grid[k] = a
			continue
		if o.busy > 0 or a.pos.distance_squared_to(o.pos) > 16.0:
			continue
		if absf(wrapf(a.ang - o.ang, -PI, PI)) < 2.0:
			continue                      # walking the same way: no greeting
		var secs := rng.randi_range(12, 30)
		for p in [[a, o], [o, a]]:
			p[0].busy = secs
			p[0].act = 3
			p[0].ang = (p[1].pos - p[0].pos).angle()
			p[0].meet_cd = rng.randi_range(240, 600)
		grid.erase(k)


func _rebuild_food_grid() -> void:
	_food_dirty = false
	food_cell.fill(-1)
	for fi in foods.size():
		var f: Dictionary = foods[fi]
		if f.amt < 1.0 or f.rotten:
			continue
		var p: Vector2 = f.pos
		var r: float = f.r + 40.0   # how far a forager can smell it
		for cy in range(maxi(0, int((p.y - r) / CELL)), mini(gh - 1, int((p.y + r) / CELL)) + 1):
			for cx in range(maxi(0, int((p.x - r) / CELL)), mini(gw - 1, int((p.x + r) / CELL)) + 1):
				if Vector2(cx * CELL + CELL * 0.5, cy * CELL + CELL * 0.5).distance_to(p) <= r:
					food_cell[cy * gw + cx] = fi


func _new_day() -> void:
	climate.new_day()
	match nest.plan_chambers(eggs.size() + larvae.size() + pupae.size(), workers.size()):
		"planned":
			_log("รังเริ่มแน่น มดเริ่มขุดปล่องลงไปทำห้องใหม่ (ห้องที่ %d)" % nest.chambers.size(), "ok")
		"opened":
			_log("มดขุดทะลุถึงห้องใหม่แล้ว กำลังขยายห้องให้กว้าง", "ok")
		"grown":
			_log("มดขยายห้องรังให้กว้างขึ้นเพราะตัวอ่อนเริ่มแน่น")
	history.append(_snapshot())
	if history.size() > 365:
		history.pop_front()
	if rng.randf() < 0.14:
		climate.rain_ticks = int(TPD * rng.randf_range(0.15, 0.4))
		_log("ฝนตก มดหลบเข้ารัง กลิ่นบนพื้นกำลังถูกชะล้าง")


func _snapshot() -> Dictionary:
	return {"day": day(), "workers": workers.size(), "brood": eggs.size() + larvae.size() + pupae.size(),
		"sugar": sugar, "protein": protein}


# ---------------------------------------------------------------- colony physiology

func _dev_rate(t: float) -> float:
	if t < sp["dev_min_c"]:
		return 0.0
	if t < sp["dev_opt_c"]:
		return (t - sp["dev_min_c"]) / (sp["dev_opt_c"] - sp["dev_min_c"])
	if t <= sp["dev_hot_c"]:
		return 1.0
	return maxf(0.0, 1.0 - (t - sp["dev_hot_c"]) / (sp["dev_lethal_c"] - sp["dev_hot_c"]))


func _activity(t: float) -> float:
	if t < sp["forage_min_c"]:
		return 0.0
	if t < sp["forage_opt_c"]:
		return (t - sp["forage_min_c"]) / (sp["forage_opt_c"] - sp["forage_min_c"])
	if t <= sp["forage_hot_c"]:
		return 1.0
	return maxf(0.0, 1.0 - (t - sp["forage_hot_c"]) / (sp["forage_max_c"] - sp["forage_hot_c"]))


func _colony(dt: float) -> void:
	dev = _dev_rate(climate.nest)
	activity = _activity(climate.air) * (0.1 if climate.raining() else 1.0)
	hungry = sugar < workers.size() * 0.4 + 2.0 or protein < larvae.size() * 0.5 + 1.0
	var forager_age: float = sp["nurse_until_hungry"] if hungry else sp["nurse_until_days"]
	if workers.size() < 8:
		forager_age = sp["callow_days"]     # the first nanitics start foraging within days of emerging

	nurses = 0
	callow = 0
	out_count = 0
	var idle: Array = []
	outside.clear()
	for a in workers:
		a.age += dt
		if a.state != Ant.IN_NEST:
			out_count += 1
			outside.append(a)
			continue
		if a.age < sp["callow_days"]:
			callow += 1
		elif a.age < forager_age:
			nurses += 1
		else:
			idle.append(a)
	# Older ants resting inside still help with brood care when nurses are short.
	var lpn: float = sp["larvae_per_nurse"]
	var nurse_cap: float = nurses * lpn + idle.size() * lpn * 0.8 + callow * 1.0
	if queen.alive and workers.size() < 15:
		# a founding queen licks and feeds her first larvae herself, handing over as workers appear
		nurse_cap += 15.0 * (1.0 - workers.size() / 15.0)
	var care_short: bool = larvae.size() > nurses * lpn + callow

	# Undertakers carry nestmates that died inside out to the refuse pile.
	if corpses_inside > 0 and not idle.is_empty() and rng.randf() < 0.5:
		var u = idle.pop_back()
		_send_out(u, Ant.UNDERTAKER)
		u.carry = Ant.CORPSE
		corpses_inside -= 1

	# Recruitment to forage depends on colony need: hungry → many, full stores → few.
	var need_k := 1.6 if hungry else (0.3 if satiated() else 0.7)
	if care_short:
		need_k *= 0.5
	# Only a minority of a colony forages at any moment.
	var max_out := ceili(minf(3.0 + workers.size() * (0.32 if hungry else 0.2), workers.size() * 0.6))
	var p_exit := 0.005 * (COLONY_EVERY / 10.0) * activity * need_k
	# A forager arriving with food stirs up nestmates, who leave along its fresh trail.
	while _recruits > 0 and not idle.is_empty() and out_count < max_out:
		_send_out(idle.pop_back(), Ant.SEARCH)
		out_count += 1
		_recruits -= 1
	_recruits = 0
	for a in idle:
		if out_count >= max_out:
			break
		if rng.randf() < p_exit:
			_send_out(a, Ant.SEARCH)
			out_count += 1

	# Excavation: idle workers dig until the nest volume fits the colony; damp soil after rain invites digging.
	if nest.air >= target_air():
		diggers_wanted = 0
	else:
		var keen := 1.4 if humidity > 0.6 else 1.0
		diggers_wanted = clampi(int((idle.size() * 0.35 + 1.0) * keen), 1, 40) if workers.size() - out_count > 0 else 0

	_metabolism(dt)
	_moisture(dt)
	_queen(dt)
	_brood(dt, nurse_cap)
	_outworld(dt)


func target_air() -> int:
	# open volume a colony maintains grows in step with its population
	return int(80 + 22 * (workers.size() + (eggs.size() + larvae.size() + pupae.size()) * 0.25))


func sugar_cap() -> float:
	return 10.0 + workers.size() * 2.5


func protein_cap() -> float:
	return 6.0 + larvae.size() * 1.2 + workers.size() * 0.3


func satiated() -> bool:
	return sugar > sugar_cap() * 0.8 and protein > protein_cap() * 0.6


func _metabolism(dt: float) -> void:
	protein *= pow(0.92, dt)  # stored prey dries out and spoils
	# Workers feed the queen first by trophallaxis, then share what is left among themselves.
	var q_need: float = sp["sugar_queen"] * dt if queen.alive else 0.0
	queen_fed = sugar >= q_need
	if not queen_fed and queen.reserve > 0.0:
		queen.reserve = maxf(0.0, queen.reserve - q_need)   # living off her own body
		queen_fed = true
	else:
		sugar = maxf(0.0, sugar - q_need)
	var need: float = (workers.size() * sp["sugar_worker"] + larvae.size() * sp["sugar_larva"]) * dt
	if sugar < need and queen.reserve > 0.0:
		# while her reserves last the queen regurgitates food to her first workers
		var give := minf(need - sugar, queen.reserve)
		queen.reserve -= give
		sugar += give
	var fed := 1.0 if need <= 0.0 else clampf(sugar / need, 0.0, 1.0)
	starving = fed < 0.999
	sugar = maxf(0.0, sugar - need)
	var dry := humidity < 0.1
	for a in workers:
		if starving:
			a.energy -= dt * (1.0 - fed) / sp["starve_days_worker"] / a.hardiness
		elif dry:
			a.energy -= dt / 6.0 / a.hardiness
		else:
			a.energy = minf(1.0, a.energy + dt)
		if a.energy <= 0.0 or a.age > a.life or (a.state != Ant.IN_NEST and rng.randf() < sp["forager_daily_risk"] * dt):
			_kill(a)
	_warn("starve", starving, "น้ำตาลในรังหมด มดงานเริ่มอดอาหาร")
	_warn("dry", dry, "รังแห้งมาก มดงานเริ่มขาดน้ำ ควรเติมน้ำ")


func _moisture(dt: float) -> void:
	# Evaporation is proportional to how wet the nest is, so a drying nest slows down
	# (a watered Ytong/plaster nest lasts 2–3 weeks; a heat mat dries it faster).
	var k := 0.09 + (0.06 if heater else 0.0) + workers.size() * 0.0002
	humidity = clampf(humidity * exp(-k * dt), 0.0, 1.0)
	if humidity < sp["humidity_ok_min"]:
		var p: float = (sp["humidity_ok_min"] - humidity) * 2.0 * dt
		_cull(eggs, p)
		_cull(larvae, p * 0.5)
	_warn("lowhum", humidity < sp["humidity_ok_min"], "ความชื้นในรังต่ำ ไข่เริ่มแห้งตาย")
	if humidity > sp["humidity_ok_max"]:
		mold += dt
	else:
		mold = maxf(0.0, mold - dt * 0.5)
	if mold > 2.0:
		_cull(larvae, 0.15 * dt)
		_cull(pupae, 0.1 * dt)
		protein *= pow(0.85, dt)
		_warn("mold", true, "ราขึ้นในรังเพราะชื้นเกินไป ตัวอ่อนและอาหารเริ่มเสีย")
	else:
		_warn("mold", false, "")


func _queen(dt: float) -> void:
	if not queen.alive:
		return
	queen.starve = (queen.starve + dt) if not queen_fed else maxf(0.0, queen.starve - dt)
	queen.dry = (queen.get("dry", 0.0) + dt) if humidity < 0.1 else maxf(0.0, queen.get("dry", 0.0) - dt)
	if queen.starve > sp["starve_days_queen"] or queen.dry > sp["starve_days_queen"] * 1.5:
		queen.alive = false
		var why := "ขาดอาหาร" if queen.starve > sp["starve_days_queen"] else "ขาดน้ำ"
		_log("ราชินีตายจาก%s รังจะค่อยๆ หมดไปเพราะไม่มีไข่ใหม่" % why, "bad")
		return
	if starving:
		return
	var cap: float = minf(sp["queen_eggs_max"], sp["queen_eggs_base"] + workers.size() * sp["queen_eggs_per_worker"])
	# Workers regulate brood: the queen is fed less when there is more brood than the colony can rear.
	var brood := eggs.size() + larvae.size()
	var room := clampf(1.0 - float(brood) / (12.0 + workers.size() * 2.5), 0.0, 1.0)
	room *= clampf(float(nest.air) / target_air(), 0.3, 1.0)   # a cramped nest holds back laying
	# a founding queen makes her first eggs from her own body reserves
	var yolk := maxf(protein, 3.0 if (queen.reserve > 8.0 and workers.size() < 5) else 0.0)
	var rate := cap * dev * clampf(yolk / 3.0, 0.0, 1.0) * room
	if humidity < sp["humidity_ok_min"]:
		rate *= 0.3
	egg_acc += rate * dt
	while egg_acc >= 1.0:
		egg_acc -= 1.0
		eggs.append({"p": 0.0})
		protein = maxf(0.0, protein - sp["protein_egg"])
		_event("egg")


func _brood(dt: float, nurse_cap: float) -> void:
	for i in range(eggs.size() - 1, -1, -1):
		eggs[i].p += dt / sp["egg_days"] * dev
		if eggs[i].p >= 1.0:
			eggs.remove_at(i)
			larvae.append({"p": 0.0, "h": 0.0, "q": 0.6})

	var n := larvae.size()
	if n > 0:
		var need: float = n * sp["protein_larva"] * dt
		if protein < need and queen.reserve > 0.0 and workers.size() < 5:
			# the founding queen feeds her larvae from her own reserves (trophic eggs, saliva)
			var give := minf(need - protein + 0.01, queen.reserve)
			queen.reserve -= give
			protein += give
		var r := minf(1.0, minf(nurse_cap / n, protein / need))
		protein = maxf(0.0, protein - need * r)
		var hungriest := -1
		var worst: float = sp["larva_starve_days"]
		for i in range(n - 1, -1, -1):
			var l = larvae[i]
			l.p += dt / sp["larva_days"] * dev * r
			l.h = maxf(0.0, l.h + dt * (1.0 - r) - dt * r * 0.5)
			l.q = lerpf(l.get("q", 0.6), r, minf(1.0, dt * 0.6))   # running average of how well it was fed
			if l.p >= 1.0:
				larvae.remove_at(i)
				pupae.append({"p": 0.0, "s": _adult_size(l.q)})
				_event("pupate", pupae[-1].s)
				if hungriest > i:
					hungriest -= 1
				continue
			if l.h > worst:
				worst = l.h
				hungriest = i
		_cannibal_cd = maxf(0.0, _cannibal_cd - dt)
		if hungriest >= 0 and _cannibal_cd <= 0.0:
			# Starving colonies recycle brood: workers eat the weakest larva, a few per day.
			_cannibal_cd = 0.15
			larvae.remove_at(hungriest)
			protein += 0.3
			stats.cannibalized += 1
			if stats.cannibalized == 1 or stats.cannibalized % 10 == 0:
				_log("ขาดโปรตีน มดงานกินตัวอ่อนที่อดอาหารไปแล้ว %d ตัว" % stats.cannibalized, "bad")

	for i in range(pupae.size() - 1, -1, -1):
		pupae[i].p += dt / sp["pupa_days"] * dev
		if pupae[i].p >= 1.0:
			var pupa: Dictionary = pupae[i]
			pupae.remove_at(i)
			if workers.is_empty():
				_log("มดงานตัวแรกออกจากรังไหมแล้ว! เป็นมดรุ่นแรกตัวเล็ก (nanitic) จะเปิดปากรังออกไปหาอาหาร", "ok")
			var nw := _new_worker(0.0)
			nw.size = pupa.get("s", 1.0)
			_event("eclose", nw.size)
			workers.append(nw)
			stats.born += 1
			if stats.born <= 3 or stats.born % 25 == 0:
				_log("มดงานตัวใหม่ออกจากรังไหม (รวม %d ตัว)" % stats.born, "ok")

	if climate.nest > sp["dev_lethal_c"] - 2.0:
		var p := 0.4 * dt
		_cull(eggs, p)
		_cull(larvae, p)
		_cull(pupae, p)
		_warn("heat", true, "ในรังร้อนเกินไป ตัวอ่อนเริ่มตาย")
	else:
		_warn("heat", false, "")


func _cull(list: Array, p: float) -> void:
	for i in range(list.size() - 1, -1, -1):
		if rng.randf() < p:
			list.remove_at(i)
			stats.dead += 1


func _outworld(dt: float) -> void:
	var light := daylight()
	for f in foods:
		f.age += dt
		if f.regen > 0.0:
			f.amt = minf(f.cap, f.amt + f.regen * dt * (0.4 + 0.6 * light))
		elif f.kind == "honey":
			f.amt *= pow(0.78, dt)  # the drop dries out and crystallises
		elif f.type == Ant.PROTEIN and f.age > 6.0 and not f.rotten:
			f.rotten = true
			_food_dirty = true
	var before := foods.size()
	foods = foods.filter(func(f): return f.regen > 0.0 or (f.amt >= 1.0 and f.age < 9.0))
	if foods.size() != before:
		_food_dirty = true

	if rng.randf() < 0.8 * dt:
		var p := Vector2(rng.randf_range(30, WORLD.x - 30), rng.randf_range(30, WORLD.y - 30))
		if place_food("fly", p) and not _warned.get("fly_hint", false):
			_warned["fly_hint"] = true
			_log("มีแมลงวันตายตกลงมาในกล่อง มดจะหาเจอเองถ้าออกสำรวจ")

	for c in corpses:
		c.age += dt
	corpses = corpses.filter(func(c): return c.age < 30.0)
	if corpses.size() > 250:
		corpses = corpses.slice(corpses.size() - 250)

	if enemies and spider.is_empty() and rng.randf() < 0.25 * dt:
		_spawn_spider()


func _warn(key: String, on: bool, text: String) -> void:
	# announce when a problem starts; repeat at most every two days while it flickers on and off
	if on and not _warned.get(key, false):
		_warned[key] = true
		if tick - int(_warned.get(key + "_t", -TPD * 10)) > TPD * 2:
			_warned[key + "_t"] = tick
			_log(text, "bad")
	elif not on:
		_warned[key] = false


func _kill(a: Ant) -> void:
	if a.dead:
		return
	a.dead = true
	_any_dead = true
	stats.dead += 1
	if a.state == Ant.IN_NEST:
		corpses_inside += 1
	else:
		corpses.append({"pos": a.pos, "ang": a.ang, "age": 0.0})
		if a.carry == Ant.CORPSE:
			corpses.append({"pos": a.pos + Vector2(4, 2), "ang": a.ang + 1.0, "age": 0.0})


func _send_out(a: Ant, state: int) -> void:
	if a.state == Ant.IN_NEST:
		outside.append(a)
	a.state = state
	a.pos = nest_pos + Vector2.from_angle(rng.randf() * TAU) * 3.0
	a.ang = rng.randf() * TAU
	a.trip = 0
	a.since = 0
	a.carry = Ant.NONE
	a.patience = rng.randi_range(700, 1600)


# ---------------------------------------------------------------- ant behaviour

func _step_ant(a: Ant) -> void:
	# Hot path: written flat (few calls, one cell lookup) because it runs for every forager every tick.
	var n := ant_substep
	if a.meet_cd > 0:
		a.meet_cd -= n
	if a.busy > 0:
		a.busy -= n
		if a.busy <= 0:
			a.act = 0
			if a.turn_after:
				a.turn_after = false
				a.ang += PI          # loaded up: turn round and head home
		return
	a.trip += n
	var spd := _spd
	if a.carry >= Ant.PROTEIN:
		spd *= 0.7
	a.phase += spd * 0.95
	var pos := a.pos
	var ci := int(pos.y * INV_CELL) * gw + int(pos.x * INV_CELL)
	# antennae sample the trail a few times per body length; deposits are pulsed every other tick
	# periods are in ticks of game time, so behaviour per distance walked is the same at any substep
	var sense_p := maxi(SENSE_EVERY, n)
	var drop_p := maxi(2, n)
	var sense_now := ((a.trip + a.id) % sense_p) < n
	var drop_now := ((a.trip + a.id) % drop_p) < n
	var st := a.state
	if st == Ant.SEARCH:
		if drop_now:
			home.deposit_i(ci, 0.5 * drop_p * maxf(0.05, 1.0 - a.trip / 4000.0))
		var fi := food_cell[ci]
		var near := false
		if fi >= 0:
			var f: Dictionary = foods[fi]
			# Foragers switch to what the colony lacks: a sugar-full colony ignores sugar, and so on.
			var wanted: bool = _want_sugar if f.type == Ant.SUGAR else _want_protein
			if wanted and f.amt >= 1.0 and not f.rotten:
				var fp: Vector2 = f.pos
				if pos.distance_squared_to(fp) < pow(f.r + 2.0 + spd, 2.0):
					_pick_up(a, f)
					return
				near = true
				_turn_toward(a, fp, 0.15)
		if not near and sense_now:
			_steer(a, food, sense_p)
		if a.trip > a.patience:
			a.state = Ant.HOME
	elif st == Ant.UNDERTAKER:
		var d2 := pos.distance_squared_to(midden_pos)
		_turn_toward(a, midden_pos, 0.1 if d2 > 1600.0 else 0.25)
		if d2 < 144.0:
			corpses.append({"pos": pos + Vector2(rng.randf_range(-6, 6), rng.randf_range(-6, 6)),
				"ang": rng.randf() * TAU, "age": 0.0})
			a.carry = Ant.NONE
			a.state = Ant.HOME
			a.since = 0
	else:
		a.since += n
		if drop_now and (a.carry == Ant.SUGAR or a.carry == Ant.PROTEIN):
			food.deposit_i(ci, 1.2 * drop_p * maxf(0.05, 1.0 - a.since / 3000.0))
		var d2 := pos.distance_squared_to(nest_pos)
		if d2 < NEST_R * NEST_R:
			_arrive(a)
			return
		if d2 < 6400.0:
			_turn_toward(a, nest_pos, 0.2)
		else:
			if sense_now:
				_steer(a, home, sense_p)
			_turn_toward(a, nest_pos, 0.03)  # path integration keeps them oriented
	a.ang += rng.randf_range(-0.16, 0.16) * _noise_k
	if a.follow > 0:
		a.follow -= ant_substep
	var np := pos + Vector2(cos(a.ang), sin(a.ang)) * spd
	if blocked(np):
		a.follow = 24
		# follow the edge of the obstacle: try headings swinging toward the ant's chosen side
		var found := false
		for turn in [0.5, 1.0, 1.6, 2.3]:
			for sgn in [a.slide, -a.slide]:
				var ang: float = a.ang + turn * sgn
				var q := pos + Vector2(cos(ang), sin(ang)) * spd
				if not blocked(q):
					a.ang = ang
					np = q
					found = true
					break
			if found:
				break
		if not found:
			a.ang += PI
			a.slide = -a.slide
			return
		if rng.randf() < 0.01:
			a.slide = -a.slide
	a.pos = np


const HANDLING := {"aphids": [60, 140, 9], "honey": [40, 80, 10], "cricket": [90, 200, 2], "fly": [50, 110, 2]}


func _pick_up(a: Ant, f: Dictionary) -> void:
	# collecting a load takes a while: stroking aphids for honeydew, drinking until the crop is full,
	# or cutting a piece off a carcass with the mandibles
	var h: Array = HANDLING.get(f.kind, [30, 60, 2])
	a.busy = rng.randi_range(h[0], h[1])
	a.act = h[2]
	a.ang = (f.pos - a.pos).angle()
	f.amt -= 1.0
	if f.amt < 1.0:
		_food_dirty = true
	a.carry = f.type
	a.state = Ant.RETURN
	a.since = 0
	a.turn_after = true
	if not f.found:
		f.found = true
		match f.kind:
			"aphids": _log("มดพบฝูงเพลี้ยอ่อน เริ่มรีดน้ำหวานและทิ้งกลิ่นนำทาง", "ok")
			"honey": _log("มดพบหยดน้ำผึ้ง กำลังชวนกันมาเก็บ", "ok")
			"cricket": _log("มดพบจิ้งหรีด กำลังตัดชิ้นส่วนกลับรัง", "ok")
			"fly": _log("มดพบแมลงวันตาย ได้โปรตีนเพิ่ม", "ok")


func _arrive(a: Ant) -> void:
	var had: bool = a.carry != Ant.NONE
	if a.carry == Ant.SUGAR:
		sugar = minf(sugar_cap(), sugar + 1.0)
		humidity = minf(1.0, humidity + 0.004)  # honeydew is mostly water
		stats.sugar_in += 1
	elif a.carry == Ant.PROTEIN:
		protein = minf(protein_cap(), protein + 1.0)
		humidity = minf(1.0, humidity + 0.002)
		stats.protein_in += 1
	a.carry = Ant.NONE
	if had and activity > 0.2:
		_recruits += 2
	if had and activity > 0.3 and rng.randf() < 0.75:
		a.state = Ant.SEARCH
		a.trip = 0
		a.ang += PI
		return
	a.state = Ant.IN_NEST
	a.trip = 0


func _sense(a: Ant, field: Field, off: float) -> float:
	var ang := a.ang + off
	var x := a.pos.x + cos(ang) * 10.0
	var y := a.pos.y + sin(ang) * 10.0
	if x < 0.0 or y < 0.0 or x >= WORLD.x or y >= WORLD.y:
		return -1.0
	var i := int(y * INV_CELL) * gw + int(x * INV_CELL)
	if rock[i] != 0:
		return -1.0
	return field.read_i(i)


func _steer(a: Ant, field: Field, period: int) -> void:
	if a.follow > 0:
		return
	var l := _sense(a, field, -0.55)
	var c := _sense(a, field, 0.0)
	var r := _sense(a, field, 0.55)
	if maxf(l, maxf(c, r)) < 0.03 or (c >= l and c >= r):
		return
	var turn := minf(1.0, 0.45 * period / SENSE_EVERY)
	a.ang += -turn if l > r else turn


func _turn_toward(a: Ant, target: Vector2, k: float) -> void:
	if a.follow > 0:
		# edging around an obstacle: only turn back toward the goal once the straight way is clear
		var probe := a.pos + (target - a.pos).normalized() * 6.0
		if blocked(probe) or blocked(a.pos.lerp(probe, 0.5)):
			return
		a.follow = 0
	# k is per tick; with substepping the same turn per distance needs a larger step
	var kk := 1.0 - pow(1.0 - k, ant_substep)
	a.ang += wrapf((target - a.pos).angle() - a.ang, -PI, PI) * kk


func blocked(p: Vector2) -> bool:
	if p.x < 3.0 or p.y < 3.0 or p.x > WORLD.x - 3.0 or p.y > WORLD.y - 3.0:
		return true
	return rock[home.index(p.x, p.y)] != 0


# ---------------------------------------------------------------- spider

func _spawn_spider() -> void:
	var side := rng.randi_range(0, 3)
	var t := rng.randf()
	var starts := [Vector2(t * WORLD.x, -20), Vector2(WORLD.x + 20, t * WORLD.y),
		Vector2(t * WORLD.x, WORLD.y + 20), Vector2(-20, t * WORLD.y)]
	var start: Vector2 = starts[side]
	spider = {"pos": start, "ang": (WORLD * 0.5 - start).angle(), "life": TPD * 0.45, "kills": 0,
		"exit": start + (start - WORLD * 0.5).normalized() * 60.0, "phase": 0.0}
	_log("แมงมุมหมาป่าเดินเข้ามาในพื้นที่หาอาหาร", "bad")


func _step_spider() -> void:
	var s := spider
	s.life -= 1
	s.phase += 0.3
	var best = null
	var bd := 150.0
	for a in outside:
		if a.state != Ant.IN_NEST and not a.dead:
			var d: float = a.pos.distance_to(s.pos)
			if d < bd:
				bd = d
				best = a
	var target_ang: float = s.ang + rng.randf_range(-0.12, 0.12)
	if s.life <= 0:
		target_ang = (s.exit - s.pos).angle()
	elif best != null:
		target_ang = (best.pos - s.pos).angle()
	s.ang += wrapf(target_ang - s.ang, -PI, PI) * 0.08
	var np: Vector2 = s.pos + Vector2.from_angle(s.ang) * 0.55
	var inside := np.x > 0 and np.y > 0 and np.x < WORLD.x and np.y < WORLD.y
	if s.life > 0 and inside and blocked(np):
		s.ang += 2.0
	else:
		s.pos = np
	if best != null and bd < 7.0 and rng.randf() < 0.04:
		_kill(best)
		s.kills += 1
		if s.kills == 1:
			_log("แมงมุมจับมดงานไป 1 ตัว", "bad")
	if s.life <= 0 and not Rect2(Vector2(-30, -30), WORLD + Vector2(60, 60)).has_point(s.pos):
		_log("แมงมุมออกไปแล้ว (จับมดได้ %d ตัว)" % s.kills)
		spider = {}


func remove_spider() -> void:
	if not spider.is_empty():
		spider = {}
		_log("ไล่แมงมุมออกจากกล่องแล้ว")


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

const SAVE_VERSION := 1
const ANT_FIELDS := ["id", "age", "life", "state", "pos", "ang", "carry", "trip", "since", "energy", "size",
	"hardiness", "patience", "follow", "slide", "busy", "act", "meet_cd", "turn_after", "phase"]


## The complete state of the colony and its box. Loading it with from_dict() and stepping on gives
## exactly the same future as never having stopped (the random generator's state is included).
func to_dict() -> Dictionary:
	var ants := []
	for a in workers:
		var row := []
		for f in ANT_FIELDS:
			row.append(a.get(f))
		ants.append(row)
	var out_ids := PackedInt32Array()
	for a in outside:
		out_ids.append(a.id)
	return {
		"version": SAVE_VERSION, "species": sp["id"], "rng_seed": rng.seed, "rng_state": rng.state, "tick": tick,
		"climate": climate.to_dict(), "nest": nest.to_dict(), "home": home.to_dict(), "food": food.to_dict(),
		"rock": rock, "rocks": rocks, "foods": foods, "corpses": corpses, "workers": ants, "outside": out_ids,
		"eggs": eggs, "larvae": larvae, "pupae": pupae, "queen": queen,
		"sugar": sugar, "protein": protein, "humidity": humidity, "mold": mold, "heater": heater, "enemies": enemies,
		"spider": spider, "corpses_inside": corpses_inside, "egg_acc": egg_acc, "stats": stats,
		"history": history, "log": log_entries, "warned": _warned, "next_id": _next_id,
		"cannibal_cd": _cannibal_cd, "recruits": _recruits,
		# values the colony tick derives but foragers read in between
		"derived": {"nurses": nurses, "callow": callow, "out_count": out_count, "dev": dev, "activity": activity,
			"starving": starving, "queen_fed": queen_fed, "hungry": hungry, "diggers_wanted": diggers_wanted},
	}


func from_dict(d: Dictionary) -> void:
	gw = int(WORLD.x / CELL)
	gh = int(WORLD.y / CELL)
	rng.seed = d.rng_seed
	rng.state = d.rng_state
	tick = d.tick
	climate = Climate.new(rng)
	climate.from_dict(d.climate)
	nest = NestVolume.new()
	nest.from_dict(rng, d.nest)
	home = Field.new(gw, gh, CELL)
	home.from_dict(d.home)
	food = Field.new(gw, gh, CELL)
	food.from_dict(d.food)
	rock = d.rock
	rocks = d.rocks
	foods = d.foods
	corpses = d.corpses
	workers = []
	var by_id := {}
	for row in d.workers:
		var a := Ant.new()
		for i in ANT_FIELDS.size():
			a.set(ANT_FIELDS[i], row[i])
		workers.append(a)
		by_id[a.id] = a
	outside = []
	for id in d.outside:
		if by_id.has(id):
			outside.append(by_id[id])
	eggs = d.eggs
	larvae = d.larvae
	pupae = d.pupae
	queen = d.queen
	sugar = d.sugar
	protein = d.protein
	humidity = d.humidity
	mold = d.mold
	heater = d.heater
	enemies = d.enemies
	spider = d.spider
	corpses_inside = d.corpses_inside
	egg_acc = d.egg_acc
	stats = d.stats
	history = d.history
	log_entries = d.log
	_warned = d.warned
	_next_id = d.next_id
	_cannibal_cd = d.cannibal_cd
	_recruits = d.recruits
	var dv: Dictionary = d.derived
	nurses = dv.nurses
	callow = dv.callow
	out_count = dv.out_count
	dev = dv.dev
	activity = dv.activity
	starving = dv.starving
	queen_fed = dv.queen_fed
	hungry = dv.hungry
	diggers_wanted = dv.diggers_wanted
	food_cell.resize(gw * gh)
	food_cell.fill(-1)
	_food_dirty = true


## A short summary for the save menu and the "while you were away" report.
func summary() -> Dictionary:
	return {"day": day(), "workers": workers.size(), "eggs": eggs.size(), "larvae": larvae.size(),
		"pupae": pupae.size(), "born": stats.born, "dead": stats.dead + stats.cannibalized,
		"chambers": nest.chambers.size(), "volume": nest.volume_cm3(), "humidity": humidity,
		"queen": queen.alive, "glass": nest.slab, "founding": founding()}


## The automatic keeper used by tests and, if the player allows it, while the game is closed:
## waters when the reservoir runs low and feeds in proportion to the colony.
func auto_care(day_index: int) -> void:
	if humidity < 0.45:
		add_water()
	if workers.is_empty():
		return
	if day_index % 3 == 0:
		for k in 1 + workers.size() / 40:
			place_food("cricket", Vector2(rng.randf_range(600, 1100), rng.randf_range(380, 700)))
	if sugar < sugar_cap() * 0.3:
		for k in 1 + workers.size() / 50:
			place_food("honey", Vector2(rng.randf_range(600, 1100), rng.randf_range(80, 300)))
