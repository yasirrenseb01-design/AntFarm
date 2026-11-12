extends "res://scripts/sim/parts/sim_state.gd"
## Simulation, layer 2 of 11: each worker's own crop of honeydew and its own body fat (PART 0.13).
## Layers: sim_state <- sim_crops <- sim_base <- sim_foragers <- sim_surface <- sim_enemies <- sim_warmth <- sim_brood <- sim_colony <- sim_duties <- simulation.
##
## Since step 2 (v0.13.1) Ant.crop and Ant.body_fat are the food itself: a worker eats from its own crop, then burns its
## own fat (sim_colony._metabolism), honeydew passes from crop to crop (sim_duties._share_honeydew) and a forager home
## with a load regurgitates it at the entrance (_pending_in), handed out at the next duty round. sim.sugar and sim.fat
## are the sums, kept up as the ants change (sugar = the workers' crops + queen.crop + _pending_in, fat = their body fat),
## so everything that reads them (the HUD, the charts, food_days, laying, hungry, _want_sugar) reads them as before.
## Draws nothing from the random generators. Sources and the values chosen: docs/biology/crop_and_hunger.md.

const KEEP_OWN := 0.3        # a forager home with a load keeps for itself up to this share of a full crop (chosen)
const SHARE_ROOM := 0.6      # a drop fills at most this share of the taker's room: not full at once (chosen; plan R3)
const SHARE_GAP := 0.5       # a drop is at most half the difference between the giver's crop and the taker's (chosen)
const MIN_DROP := 0.1        # units: smaller drops are not passed on (~1 day of a worker's eating; chosen: as many
                             # feedings shown and counted (Colony Harmony) as through v0.13.0 - 0.02 gave 5x)
const FAT_ASK := 0.1         # units: a worker with less than this in crop and fat together is fed from a nestmate's fat
const FAT_DROP := 0.25       # units given from fat at a time (~3 days of a worker's eating; chosen)
const FAT_SPARE := 0.5       # units of fat a giver keeps for itself (~6 days; chosen)
const STARVING_SHARE := 0.5  # the colony is "starving" (warning, more resting, no laying) with more of its workers
                             # than this out of crop and fat (chosen: through PART 0.12 it starved as a whole)

var _pending_in := 0.0       # honeydew regurgitated at the entrance, handed out at the next duty round (saved)
var _in_c := 0.0             # the crops and fat of the workers inside, counted by sim_colony._colony each tick
var _in_f := 0.0
var food_in := 0.0           # sugar brought home, and given by a founding queen to her workers (not saved: the tests)
var food_eaten := 0.0        # sugar and fat eaten by the queen, the larvae and the workers (the same)


## How much honeydew a worker's crop holds (species "crop_cap", in food units).
func crop_cap() -> float:
	return sp["crop_cap"]


## A forager's load comes home: the colony's sugar becomes `v`. The forager keeps enough to top its own crop up to
## KEEP_OWN of full (it drinks at the aphids too, and may go straight out again); the rest waits at the entrance.
func ledger_arrive(a: Ant, v: float) -> void:
	var load := maxf(0.0, v - sugar)
	var own := clampf(crop_cap() * KEEP_OWN - a.crop, 0.0, load)
	a.crop += own
	_pending_in += load - own
	sugar += load
	food_in += load


## The colony's sugar set to `v` as a whole (setup, the dev tools): spread evenly over the workers' crops, at most a
## full crop each; what does not fit goes to the queen's crop.
func ledger_set_sugar(v: float) -> void:
	_pending_in = 0.0
	var n := workers.size()
	var each := minf(v / n, crop_cap()) if n > 0 else 0.0
	for a: Ant in workers:
		a.crop = each
	queen.crop = maxf(0.0, v - each * n)
	ledger_count()


## A colony that has just been set up: its sugar and fat spread evenly, and the queen fed as much as she eats.
func ledger_start() -> void:
	queen["fed"] = sp["sugar_queen"]
	var n := workers.size()
	for a: Ant in workers:
		a.body_fat = fat / n
	ledger_set_sugar(sugar)


## sugar and fat added up again from the ants (a colony loaded). A crop over the cap - saved by v0.13.0, where the
## shares were only a ledger - gives the excess to the entrance, handed out at the next round. (Ant.sweet, the
## honeydew to pass on until v0.13.0, is no longer used: kept in the save, always 0.)
func ledger_count() -> void:
	var cap := crop_cap()
	var c: float = queen.crop
	var f := 0.0
	for a: Ant in workers:
		a.sweet = 0.0
		if a.crop > cap:
			_pending_in += a.crop - cap
			a.crop = cap
		c += a.crop
		f += a.body_fat
	sugar = c + _pending_in
	fat = f


## Workers that died this step (still in `workers`, marked dead): their crops go to the entrance, handed out at the next
## round, and their body fat is shared among the living - both stay the colony's, as the colony's stores did through
## PART 0.12 (chosen for step 2, to change one thing at a time: really a forager lost outside takes its food with it).
func ledger_dead() -> void:
	var lost_fat := 0.0
	var alive := 0
	for a: Ant in workers:
		if a.dead:
			_pending_in += a.crop
			lost_fat += a.body_fat
			a.crop = 0.0
			a.body_fat = 0.0
		else:
			alive += 1
	if alive == 0:
		fat = 0.0
		return
	if lost_fat > 0.0:
		var each := lost_fat / alive
		for a: Ant in workers:
			if not a.dead:
				a.body_fat += each


## Takes `want` units for the queen and the larvae: first from the honeydew at the entrance, then from the crops of the
## workers inside, then from their fat, each in proportion to what it holds (in_c, in_f: the sums inside). Returns
## [share of each crop taken, share of each body fat taken, what could not be found]; _pending_in is taken from here, the rest by the caller
## in its pass over the workers (sim_colony._metabolism: one pass, not two). Counts what is eaten (food_eaten).
func _nest_gives(want: float, in_c: float, in_f: float) -> Array:
	var p := minf(_pending_in, want)
	_pending_in -= p
	var left := maxf(0.0, want - p)
	var kc := minf(1.0, left / in_c) if in_c > 0.0 else 0.0
	left = maxf(0.0, left - in_c * kc)
	var kf := minf(1.0, left / in_f) if in_f > 0.0 and left > 0.0 else 0.0
	left = maxf(0.0, left - in_f * kf)
	food_eaten += want - left
	return [kc, kf, left]                # (not a Vector2: its floats are 32-bit)
