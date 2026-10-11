extends RefCounted
## Air temperature with a daily cycle and day-to-day weather drift, plus a nest temperature that lags
## behind it (soil has thermal inertia).
##   "keeper": an indoor formicarium on a shelf — room temperature all year, an optional heat mat, and
##             the keeper's fridge for hibernation (fridge 0..1 ramps the box toward FRIDGE_C).
##   "wild":   a plot of ground in a temperate climate (where Lasius niger lives) — the year turns:
##             freezing winters, warm summers, the nest soil lagging weeks behind the air.

const SOIL_BASE_C := 24.0   # indoor formicarium on a shelf
const MEAN_C := 22.0
const HEATER_C := 4.5
const FRIDGE_C := 6.5       # the keeper's hibernation fridge

var rng: RandomNumberGenerator
var scenario := "keeper"
var doy := 200.0            # day of the year (set by the simulation every tick)
var fridge := 0.0           # keeper: 0 = on the shelf, 1 = fully cooled in the fridge
var day_mean := MEAN_C
var day_amp := 6.5
var air := 18.0
var nest := 21.0
var rain_ticks := 0
var sun := 0.0              # daylight 0..1 (set by the simulation), warms a wild nest


func _init(r: RandomNumberGenerator) -> void:
	rng = r


## Typical daily mean air temperature for this day of the year (temperate Europe: ~0 °C mid-January,
## ~19 °C mid-July) — or the room, indoors.
func season_mean(d: float = doy) -> float:
	if scenario == "wild":
		return 9.8 - 9.5 * cos(TAU * (d - 20.0) / 365.0)
	return MEAN_C


## Soil temperature a few centimetres down: damped and a few weeks behind the air
## (~3 °C in January, ~20 °C in July).
func _soil(d: float) -> float:
	return 11.5 - 8.5 * cos(TAU * (d - 40.0) / 365.0)


func new_day() -> void:
	if scenario == "wild":
		var m := season_mean()
		day_mean = clampf(day_mean + rng.randfn(0.0, 1.3) + (m - day_mean) * 0.25, m - 7.0, m + 7.0)
		day_amp = rng.randf_range(3.0, 5.0) + 3.0 * clampf((m - 2.0) / 16.0, 0.0, 1.0)
	else:
		day_mean = clampf(day_mean + rng.randfn(0.0, 1.2) + (MEAN_C - day_mean) * 0.2, 14.0, 29.0)
		day_amp = rng.randf_range(4.0, 8.0)


func raining() -> bool:
	return rain_ticks > 0


func _nest_target(heater: bool) -> float:
	if scenario == "wild":
		# Lasius niger nests where the sun reaches it (under a stone, in a sunny bank): the top
		# chambers warm well above the air through a summer day
		return air * 0.35 + _soil(doy) * 0.65 + sun * 9.0 * _sun_k()
	var room := air * 0.45 + SOIL_BASE_C * 0.55 + (HEATER_C if heater else 0.0)
	return lerpf(room, FRIDGE_C, fridge)


## How strongly the sun heats bare ground this time of year (weak in winter).
func _sun_k() -> float:
	return clampf((season_mean() - 4.0) / 12.0, 0.0, 1.0) if scenario == "wild" else 0.0


## Temperature on the ground where the ants walk: sunlit soil outdoors is well above the shade air,
## which is why ants are out on a sunny April day at 10 °C.
func surface() -> float:
	return air + sun * 8.0 * _sun_k()


func update(tod: float, heater: bool, ticks_per_day: int) -> void:
	# coolest around 03:00, warmest around 15:00
	air = day_mean + day_amp * sin(TAU * (tod - 0.375)) - (3.0 if raining() else 0.0)
	if fridge > 0.0:
		air = lerpf(air, FRIDGE_C, fridge)
	nest += (_nest_target(heater) - nest) / (ticks_per_day * 0.08)


func settle(tod: float, heater: bool) -> void:
	if scenario == "wild":
		day_mean = season_mean()
	air = day_mean + day_amp * sin(TAU * (tod - 0.375))
	nest = _nest_target(heater)


## Hours of daylight: from ~8 h at midwinter to ~16 h at midsummer outdoors; a room keeps a steady 12.
func day_hours() -> float:
	if scenario == "wild":
		return 12.0 - 4.0 * cos(TAU * (doy + 10.0) / 365.0)
	return 12.0


# ---------------------------------------------------------------- save / load

func to_dict() -> Dictionary:
	return {"day_mean": day_mean, "day_amp": day_amp, "air": air, "nest": nest, "rain_ticks": rain_ticks,
		"scenario": scenario, "fridge": fridge}


func from_dict(d: Dictionary) -> void:
	day_mean = d.day_mean
	day_amp = d.day_amp
	air = d.air
	nest = d.nest
	rain_ticks = d.rain_ticks
	scenario = d.scenario
	fridge = d.fridge
