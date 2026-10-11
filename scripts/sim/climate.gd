extends RefCounted
## Air temperature with a daily cycle and day-to-day weather drift, plus a nest temperature
## that lags behind it (soil has thermal inertia) and can be raised by a heat mat.

const SOIL_BASE_C := 24.0   # indoor formicarium on a shelf
const MEAN_C := 22.0
const HEATER_C := 4.5

var rng: RandomNumberGenerator
var day_mean := MEAN_C
var day_amp := 6.5
var air := 18.0
var nest := 21.0
var rain_ticks := 0


func _init(r: RandomNumberGenerator) -> void:
	rng = r


func new_day() -> void:
	day_mean = clampf(day_mean + rng.randfn(0.0, 1.2) + (MEAN_C - day_mean) * 0.2, 14.0, 29.0)
	day_amp = rng.randf_range(4.0, 8.0)


func raining() -> bool:
	return rain_ticks > 0


func _nest_target(heater: bool) -> float:
	return air * 0.45 + SOIL_BASE_C * 0.55 + (HEATER_C if heater else 0.0)


func update(tod: float, heater: bool, ticks_per_day: int) -> void:
	# coolest around 03:00, warmest around 15:00
	air = day_mean + day_amp * sin(TAU * (tod - 0.375)) - (3.0 if raining() else 0.0)
	nest += (_nest_target(heater) - nest) / (ticks_per_day * 0.08)


func settle(tod: float, heater: bool) -> void:
	air = day_mean + day_amp * sin(TAU * (tod - 0.375))
	nest = _nest_target(heater)


# ---------------------------------------------------------------- save / load

func to_dict() -> Dictionary:
	return {"day_mean": day_mean, "day_amp": day_amp, "air": air, "nest": nest, "rain_ticks": rain_ticks}


func from_dict(d: Dictionary) -> void:
	day_mean = d.day_mean
	day_amp = d.day_amp
	air = d.air
	nest = d.nest
	rain_ticks = d.rain_ticks
