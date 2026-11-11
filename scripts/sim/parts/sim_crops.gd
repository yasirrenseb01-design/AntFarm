extends "res://scripts/sim/parts/sim_state.gd"
## Simulation, layer 2 of 11: each worker's own share of the colony's sugar and fat (PART 0.13, step 1).
## Layers: sim_state <- sim_crops <- sim_base <- sim_foragers <- sim_surface <- sim_enemies <- sim_warmth <- sim_brood <- sim_colony <- sim_duties <- simulation.
##
## So far only a LEDGER: sim.sugar and sim.fat stay the real stores every formula reads, and Ant.crop / Ant.body_fat /
## queen.crop are a split of them kept equal to the sums (sum of crop + queen.crop = sugar, sum of body_fat = fat).
## Nothing reads the split and nothing here draws from the random generator, so the colony plays out exactly as before
## (tests/crop_ledger_test.gd). Every place that writes sugar or fat goes through here or calls ledger_sync() after.


var _led_c := 0.0       # what the shares of sugar (the queen's included) add up to as the ledger last left them
var _led_f := 0.0       # the same for fat (so a colony step does not add them up again: one pass over the ants, not two)


## A forager's load goes into its own crop: the colony's sugar is set to `v` and the difference is the forager's.
func ledger_arrive(a: Ant, v: float) -> void:
	a.crop += v - sugar
	sugar = v
	_led_c = v


## The colony's sugar set to `v` by something that is nobody's doing (the dev tools): spread over the whole colony.
func ledger_set_sugar(v: float) -> void:
	sugar = v
	ledger_sync(true)


## A colony that has just been set up: the sugar and fat spread evenly, and the queen fed as much as she eats.
func ledger_start() -> void:
	queen["fed"] = sp["sugar_queen"]
	ledger_sync(true)


## Brings the split back in line with sugar and fat after they were changed as a whole (eaten, burnt, stored, the dead
## taken out): every share scaled by the same factor, or spread evenly where there was nothing to scale; whatever the
## rounding leaves goes to the queen's crop (sugar) or the last worker (fat), so the sums stay within ~1e-12.
## full: add the shares up first (after the ants changed: a load, the dead taken out); otherwise the sums as left are used.
func ledger_sync(full := false) -> void:
	if full:
		_led_c = queen.crop
		_led_f = 0.0
		for a: Ant in workers:
			_led_c += a.crop
			_led_f += a.body_fat
	var fix_c := absf(_led_c - sugar) > 1e-12
	var fix_f := absf(_led_f - fat) > 1e-12
	if fix_c and fix_f and _led_c > 1e-9 and _led_f > 1e-9 and not workers.is_empty():
		var kc := sugar / _led_c
		var kf := fat / _led_f
		queen.crop *= kc
		var got_c: float = queen.crop
		var got_f := 0.0
		for a: Ant in workers:
			a.crop *= kc
			a.body_fat *= kf
			got_c += a.crop
			got_f += a.body_fat
		_close_crops(got_c)
		_close_fat(got_f)
		return
	if fix_c:
		_fit_crops()
	if fix_f:
		_fit_fat()


func _fit_crops() -> void:
	var got := 0.0
	if _led_c > 1e-9:
		var k := sugar / _led_c
		queen.crop *= k
		got = queen.crop
		for a: Ant in workers:
			a.crop *= k
			got += a.crop
	elif not workers.is_empty():
		var each := sugar / workers.size()
		for a: Ant in workers:
			a.crop = each
			got += each
		queen.crop = 0.0
	else:
		queen.crop = 0.0
	_close_crops(got)


func _fit_fat() -> void:
	var n := workers.size()
	if n == 0:
		return
	var got := 0.0
	if _led_f > 1e-9:
		var k := fat / _led_f
		for a: Ant in workers:
			a.body_fat *= k
			got += a.body_fat
	else:
		var each := fat / n
		for a: Ant in workers:
			a.body_fat = each
			got += each
	_close_fat(got)


func _close_crops(got: float) -> void:
	queen.crop = maxf(0.0, queen.crop + sugar - got)
	_led_c = sugar


func _close_fat(got: float) -> void:
	var last: Ant = workers[workers.size() - 1]
	last.body_fat = maxf(0.0, last.body_fat + fat - got)
	_led_f = fat
