extends "res://scripts/sim/parts/sim_base.gd"
## Simulation, layer 2 of 5: foragers in the outworld (trails, food, encounters, obstacles).


## Two foragers meeting head-on stop for a moment and drum each other with their antennae
## (how Lasius check nestmate scent and pass on news of food).
func _encounters() -> void:
	var grid := {}
	for a: Ant in outside:
		if a.busy > 0 or a.meet_cd > 0 or a.state == Ant.IN_NEST or a.state == Ant.DEFEND:
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


const ACT_SCAN := 15        # standing still, head and antennae sweeping (shaders/ants/ant.gdshader)


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
	# stop-and-go: a searching ant halts every few seconds to sweep its head and antennae, then walks
	# on; one walking home along a trail stops far less often
	if a.state == Ant.SEARCH or a.state == Ant.HOME:
		var stop_p := 0.004 if a.state == Ant.SEARCH else 0.0012
		if rng.randf() < stop_p * n:
			a.busy = rng.randi_range(10, 30)
			a.act = ACT_SCAN
			return
	var spd := _spd
	if a.carry >= Ant.PROTEIN:
		spd *= 0.7
	if a.hurt > 0.0:
		spd *= 1.0 - 0.35 * a.hurt
	a.phase += spd * 0.95
	var pos := a.pos
	var ci := int(pos.y * INV_CELL) * gw + int(pos.x * INV_CELL)
	# antennae sample the trail a few times per body length; deposits are pulsed every other tick
	# periods are in ticks of game time, so behaviour per distance walked is the same at any substep
	var sense_p := maxi(SENSE_EVERY, n)
	var drop_p := maxi(2, n)
	var sense_now := ((a.trip + a.id) % sense_p) < n
	var drop_now := ((a.trip + a.id) % drop_p) < n
	if sense_now and not creatures.is_empty():
		# an enemy close by: mark the spot with alarm pheromone; unladen ants join the fight
		for c in creatures:
			if pos.distance_squared_to(c.pos) < 900.0:
				alarm.deposit_i(ci, 3.0)
				if not c.get("alarmed", false):
					c.alarmed = true
					_log(T.alarm_raised, "bad")
				if a.carry == Ant.NONE and workers.size() >= 20:
					a.state = Ant.DEFEND
					a.foe = c.id
					return
				if a.state == Ant.SEARCH:
					a.state = Ant.HOME            # a young colony avoids the fight: back to the nest
		if a.carry == Ant.NONE and alarm.read_i(ci) > 0.6:
			if workers.size() >= 20:
				a.state = Ant.DEFEND
				a.foe = 0
				return
			if a.state == Ant.SEARCH:
				a.state = Ant.HOME
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


func _pick_up(a: Ant, f: Dictionary) -> void:
	# collecting a load takes a while: stroking aphids for honeydew, drinking until the crop is full,
	# or cutting a piece off a carcass with the mandibles
	var h: Array = FoodKinds.info(f.kind).get("handling", [30, 60, 2])
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
		var line: String = FoodKinds.info(f.kind).get("found", "")
		if line != "":
			_log(line, "ok")


func _arrive(a: Ant) -> void:
	var had: bool = a.carry != Ant.NONE
	if a.carry == Ant.SUGAR:
		sugar = minf(sugar_cap(), sugar + 1.0)
		sugar_income += 1.0
		if humidity < 0.8:
			humidity = minf(0.8, humidity + 0.004)  # honeydew is mostly water (the ants get rid of any excess)
		stats.sugar_in += 1
	elif a.carry == Ant.PROTEIN:
		protein = minf(protein_cap(), protein + 1.0)
		if humidity < 0.8:
			humidity = minf(0.8, humidity + 0.002)
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
