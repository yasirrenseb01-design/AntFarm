extends "res://scripts/sim/parts/sim_enemies.gd"
## Simulation, layer 5 of 8: how warm each chamber is (by its depth), where the nurses keep the brood, and which
## chamber the queen stays in (v0.11.19, the keeper 2026-10-21: "the queen never moves; does the brood really move
## with the temperature?").
##   The soil's daily warmth fades with depth: its swing at depth z is exp(-z / D) of the swing at the surface,
##   D (the damping depth of the daily cycle) ~5-15 cm in soil [soil physics, e.g. Hillel 1998]; here D = 8 cm.
##   Outdoors the top chambers warm in the sun by day and cool below the deeper ones at night; indoors the room is
##   nearly even, and the heat mat (under the box) warms the bottom.
##   Nurses carry larvae and cocoons to the chamber where they grow fastest [other ants: Camponotus mus nurses carry
##   brood to ~31 C by day and ~27.5 C at night - Roces & Nunez 1995 (J Insect Physiol 41); Lasius: brood under sun-warmed stones by day,
##   deeper at night - field and keepers' observations], cocoons rather higher, where it is drier [keepers];
##   eggs stay by the queen; she moves to the warmest good chamber now and then, slowly [inference].
## The brood's development runs at its own chamber's temperature (sim_colony._brood).

const DAMP_CM := 8.0           # damping depth of the daily cycle in the soil
const REF_CM := 2.0            # the depth climate.nest stands for (the top chambers)

var brood_at := {"larvae": -1, "pupae": -1}    # the chamber (nest.chambers index) each kind of brood is kept in
var queen_at := -1                             # the chamber the queen stays in (her eggs lie by her)
var _queen_stay := 0.0                         # days since she last moved
var _brood_stay := {"larvae": 0.0, "pupae": 0.0}
var _ch_t := PackedFloat32Array()              # each chamber's temperature this colony tick (-1000: not dug yet)
var ch_mean := PackedFloat32Array()            # and over about the last day (the queen goes by this, not by the hour)
var surf_mean := -1000.0                       # the ground's daytime temperature over about the last ten days (°C)


func _dev_rate(t: float) -> float:
	if t < sp["dev_min_c"]:
		return 0.0
	if t < sp["dev_opt_c"]:
		return (t - sp["dev_min_c"]) / (sp["dev_opt_c"] - sp["dev_min_c"])
	if t <= sp["dev_hot_c"]:
		return 1.0
	return maxf(0.0, 1.0 - (t - sp["dev_hot_c"]) / (sp["dev_lethal_c"] - sp["dev_hot_c"]))


## The temperature at z cm below the surface, now.
func temp_at_cm(z: float) -> float:
	var top: float = climate.nest
	if climate.scenario == "wild":
		var deep: float = climate._soil(climate.doy) + 2.0 * climate._sun_k()
		return deep + (top - deep) * exp(-(maxf(z, 0.0) - REF_CM) / DAMP_CM)
	# indoors: the top exchanges with the room air; a heat mat under the box warms its bottom more than its top
	var zmax: float = nest.ny * nest.VOXEL_MM / 10.0
	var t := top + (climate.air - top) * 0.25 * exp(-maxf(z, 0.0) / 2.5)
	if heater:
		t += climate.HEATER_C * (clampf(z / zmax, 0.0, 1.0) - 0.4) * 1.2
	return t


func chamber_depth_cm(i: int) -> float:
	return (nest.ny - float(nest.chambers[i].c.y)) * nest.VOXEL_MM / 10.0


## The temperature in chamber i this colony tick (the nest's top temperature if it is not known).
func chamber_temp(i: int) -> float:
	return _ch_t[i] if i >= 0 and i < _ch_t.size() and _ch_t[i] > -999.0 else climate.nest


## How fast an egg, larva or cocoon in chamber c develops (0..1).
func dev_in(c: int) -> float:
	return _dev_rate(chamber_temp(c)) if c >= 0 else dev


## Once a colony tick: the chambers' temperatures, then the queen's and the brood's chambers, and the nurses carry
## a few of the brood that are not where they should be.
func _place_brood(dt: float) -> void:
	var tod := time_of_day()
	if tod > 0.33 and tod < 0.79:
		# (by day: the lamps-on means of the soil-column study - García Ibarra et al. 2024 - are what nest depth went by)
		var t: float = climate.surface()
		surf_mean = t if surf_mean < -999.0 else surf_mean + (t - surf_mean) * minf(1.0, dt / (10.0 * 0.46))
	var n: int = nest.chambers.size()
	_ch_t.resize(n)
	var had := ch_mean.size()
	ch_mean.resize(n)
	var open := []
	for i in n:
		if nest.chambers[i].get("open", true):
			_ch_t[i] = temp_at_cm(chamber_depth_cm(i))
			ch_mean[i] = _ch_t[i] if i >= had or ch_mean[i] < -999.0 else ch_mean[i] + (_ch_t[i] - ch_mean[i]) * minf(1.0, dt)
			open.append(i)
		else:
			_ch_t[i] = -1000.0
			ch_mean[i] = -1000.0
	if open.is_empty():
		return
	if queen_at < 0 or queen_at >= n or not nest.chambers[queen_at].get("open", true):
		queen_at = open[0]
		for i in open:
			if nest.chambers[i].get("kind", "") == "queen":
				queen_at = i
	# the queen: to the warmest good chamber, only now and then (she is heavy and slow; a young colony's one chamber)
	# - and in the winter rest to the deepest, the brood with her: the chambers' daily means differ by under a degree
	# (the soil's yearly warmth reaches far deeper than a nest), no chamber lets the brood grow, and she stayed in her
	# founding chamber at the top for four years (the keeper, 2026-10-24) [inference: ants overwinter deep in the nest,
	# below the frost - general; no measurement for L. niger queens found]
	_queen_stay += dt
	var winter := hibernating()
	var deepest: int = open[0]
	for i in open:
		if chamber_depth_cm(i) > chamber_depth_cm(deepest):
			deepest = i
	var q_best: int = open[0]
	for i in open:
		if _mean_score(i) > _mean_score(q_best):
			q_best = i
	var better := _mean_score(q_best) > _mean_score(queen_at) + 0.15
	if winter:
		q_best = deepest
		better = true
	elif queen_at == deepest:
		better = _mean_score(q_best) > _mean_score(queen_at)          # (out of her winter quarters as soon as it is warmer up)
	if q_best != queen_at and _queen_stay > 2.0 and better and queen.alive:
		queen_at = q_best
		_queen_stay = 0.0
	# larvae (by day and night) and cocoons (a little higher, drier)
	for kind in ["larvae", "pupae"]:
		var up := 0.0 if kind == "larvae" else 0.012
		_brood_stay[kind] += dt
		var cur: int = brood_at[kind]
		var best := deepest if winter else _best_chamber(open, up)
		if cur < 0 or cur >= n or not nest.chambers[cur].get("open", true):
			brood_at[kind] = best
		elif best != cur and _brood_stay[kind] > (0.08 if kind == "larvae" else 0.25) and (winter or _score(best, up) > _score(cur, up) + 0.08):
			brood_at[kind] = best
			_brood_stay[kind] = 0.0
	# the nurses carry a few at a time (eggs stay where she laid them: she lays new ones where she goes)
	var hands := maxi(1, int(nurses * 0.3))
	for pair in [[eggs, -1], [larvae, int(brood_at.larvae)], [pupae, int(brood_at.pupae)]]:
		var list: Array = pair[0]
		var to: int = pair[1]
		for item in list:
			var c := int(item.get("c", -1))
			if c < 0 or c >= n:
				item["c"] = to if to >= 0 else queen_at     # (brood from before v0.11.19: where it should be)
			elif to >= 0 and c != to and hands > 0:
				item["c"] = to
				hands -= 1


## The open chamber the brood grows fastest in (in the cold: the warmest), `up` favouring the higher ones.
func _best_chamber(open: Array, up: float) -> int:
	var best: int = open[0]
	for i in open:
		if _score(i, up) > _score(best, up):
			best = i
	return best


## The same over the last day: where it is warmest on the whole, not just this hour.
func _mean_score(i: int) -> float:
	if i < 0 or i >= ch_mean.size() or ch_mean[i] < -999.0:
		return -INF
	return _dev_rate(ch_mean[i]) + 0.001 * ch_mean[i]


func _score(i: int, up: float) -> float:
	if i < 0 or i >= _ch_t.size() or _ch_t[i] < -999.0:
		return -INF
	return _dev_rate(_ch_t[i]) + 0.001 * _ch_t[i] - up * chamber_depth_cm(i)
