extends RefCounted
## The Home's note of colonies to get ready for winter (moved out of home.gd, at its size limit: v0.13.13).

const Store := preload("res://scripts/game/save_store.gd")


## The tanks whose colony has come to its winter (November to February, when the colony's own journal says to put it in
## the fridge - sim_colony) and is not resting in the fridge (the keeper, 2026-11-03: "a note in the Home: which colony
## has come to winter"). The one open now from the simulation, the others from their last save's day of the year moved
## on by the time since, at the away rate.
static func lines(main) -> Array:
	var out := []
	var rate := Store.away_rate(int(main._settings.get("away", 3)))
	for p in main.home.places():
		var s: int = p.slot
		var doy := -1.0
		var cold := false
		var alive := true
		if s == main.slot and not main._demo and main.sim != null and main.sim.scenario == "keeper":
			doy = main.sim.doy_f()
			cold = main.sim.fridge_on
			alive = main.sim.queen.alive
		else:
			var m: Dictionary = Store.meta(s)
			if m.is_empty() or not m.has("doy") or String(m.get("scenario", "keeper")) != "keeper":
				continue
			var since := maxf(0.0, Time.get_unix_time_from_system() - float(m.get("saved_unix", 0.0))) / 3600.0 * rate
			doy = fmod(float(m.doy) + minf(since, Store.MAX_AWAY_DAYS), 365.0)
			cold = bool(m.get("fridge", false))
			alive = bool(m.get("queen", true))
		# (from 1 November, when the colony's journal says so, the wintering is to be got ready for; winter itself from
		# 1 December as the season shown in the colony - "winter has come" on 8 November, an autumn day there: the keeper,
		# 2026-11-06)
		if alive and not cold and (doy >= 334.0 or doy < 59.0):
			out.append(main.tr("home_winter") % p.number)
		elif alive and not cold and doy >= 305.0:
			out.append(main.tr("home_winter_near") % p.number)
	return out
