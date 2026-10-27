extends RefCounted
## The bright stars of the twelve zodiac constellations for the Home's night sky (the keeper, 2026-10-27: "stars of the
## zodiac"): right ascension (hours), declination (degrees), visual magnitude - J2000 values rounded to a tenth of an
## hour or degree [from memory of the standard bright-star catalogues, rounded: close enough to make each pattern, not
## to navigate by]. The window's sky (shaders/home/window_view.gdshader) turns them with the hour and the time of year
## over a keeper at 52 degrees N (a Lasius niger garden: north-west Europe), and scatters faint random stars over the
## whole sky besides.

const LATITUDE := 52.0
const STARS := [
	# Aries
	[2.12, 23.5, 2.0], [1.91, 20.8, 2.6], [1.89, 19.3, 3.9], [2.83, 27.3, 3.6],
	# Taurus
	[4.60, 16.5, 0.9], [5.44, 28.6, 1.7], [3.79, 24.1, 2.9], [4.48, 19.2, 3.5], [5.63, 21.1, 3.0], [4.33, 15.6, 3.6],
	[4.38, 17.5, 3.8], [3.75, 24.4, 3.6], [3.82, 24.1, 3.7],
	# Gemini
	[7.76, 28.0, 1.1], [7.58, 31.9, 1.6], [6.63, 16.4, 1.9], [6.73, 25.1, 3.0], [6.38, 22.5, 2.9], [7.34, 22.0, 3.5],
	[6.25, 22.5, 3.3], [7.07, 20.6, 3.8], [6.75, 12.9, 3.4],
	# Cancer
	[8.28, 9.2, 3.5], [8.74, 18.2, 3.9], [8.97, 11.9, 4.3], [8.72, 21.5, 4.7],
	# Leo
	[10.14, 12.0, 1.4], [11.82, 14.6, 2.1], [10.33, 19.8, 2.0], [11.24, 20.5, 2.6], [11.24, 15.4, 3.3], [9.76, 23.8, 3.0],
	[10.28, 23.4, 3.4], [10.12, 16.8, 3.5], [9.88, 26.0, 3.9],
	# Virgo
	[13.42, -11.2, 1.0], [12.69, -1.4, 2.7], [13.04, 11.0, 2.8], [11.84, 1.8, 3.6], [12.93, 3.4, 3.4], [13.58, -0.6, 3.4],
	[14.27, -6.0, 4.1], [12.33, -0.7, 3.9],
	# Libra
	[15.28, -9.4, 2.6], [14.85, -16.0, 2.8], [15.07, -25.3, 3.3], [15.62, -28.1, 3.6], [15.59, -14.8, 3.9],
	# Scorpius
	[16.49, -26.4, 1.0], [17.56, -37.1, 1.6], [17.62, -43.0, 1.9], [16.01, -22.6, 2.3], [16.09, -19.8, 2.6],
	[15.98, -26.1, 2.9], [16.84, -34.3, 2.3], [17.51, -37.3, 2.7], [16.86, -38.0, 3.0], [17.71, -39.0, 2.4],
	[16.60, -28.2, 2.8], [16.35, -25.6, 2.9],
	# Sagittarius
	[18.40, -34.4, 1.8], [18.92, -26.3, 2.1], [19.04, -29.9, 2.6], [18.35, -29.8, 2.7], [18.47, -25.4, 2.8],
	[18.10, -30.4, 3.0], [18.76, -27.0, 3.2], [19.12, -27.7, 3.3], [19.16, -21.0, 2.9],
	# Capricornus
	[21.78, -16.1, 2.9], [20.35, -14.8, 3.1], [20.30, -12.5, 3.6], [21.67, -16.7, 3.7], [21.44, -22.4, 3.7],
	[20.86, -26.9, 4.1], [21.10, -17.2, 4.1],
	# Aquarius
	[21.53, -5.6, 2.9], [22.10, -0.3, 3.0], [22.91, -15.8, 3.3], [22.36, -1.4, 3.8], [22.88, -7.6, 3.7], [20.79, -9.5, 3.8],
	[22.48, 0.0, 3.6], [22.59, -0.1, 4.0],
	# Pisces
	[1.52, 15.3, 3.6], [23.29, 3.3, 3.7], [2.03, 2.8, 3.8], [23.99, 6.9, 4.0], [23.67, 5.6, 4.1], [23.47, 6.4, 4.3],
	[1.76, 9.2, 4.3], [1.19, 30.1, 4.5], [1.05, 7.9, 4.3],
]


## From the sky's own frame (x toward the March equinox, z toward the north pole) to the room's (y up; -x south through
## the window, -z east: home_room.set_hour's sun), at local sidereal time lst_h (hours).
static func to_room(lst_h: float) -> Basis:
	var th := lst_h / 24.0 * TAU
	var ph := deg_to_rad(LATITUDE)
	return Basis(Vector3(-sin(ph) * cos(th), cos(ph) * cos(th), sin(th)),
		Vector3(-sin(ph) * sin(th), cos(ph) * sin(th), -cos(th)), Vector3(cos(ph), sin(ph), 0.0))


## Local sidereal time (hours) at that clock hour on that day of the year [roughly: 0 h at noon on the March equinox,
## four minutes earlier each day; the longitude and the equation of time left out].
static func lst(hour: float, doy: float) -> float:
	return fposmod(hour - 12.0 + (doy - 80.0) / 365.25 * 24.0, 24.0)


## The day of the year by the computer's date.
static func today() -> float:
	var t := Time.get_datetime_dict_from_system()
	var start := Time.get_unix_time_from_datetime_dict({"year": t.year, "month": 1, "day": 1})
	return floorf((Time.get_unix_time_from_system() - start) / 86400.0) + 1.0


## The stars as directions in the room and brightness (x, y, z, b) at that time.
static func dirs(lst_h: float) -> PackedVector4Array:
	var m := to_room(lst_h)
	var out := PackedVector4Array()
	for s in STARS:
		var a: float = float(s[0]) / 24.0 * TAU
		var d := deg_to_rad(float(s[1]))
		var w := m * Vector3(cos(d) * cos(a), cos(d) * sin(a), sin(d))
		out.append(Vector4(w.x, w.y, w.z, clampf(pow(2.512, -(float(s[2]) - 1.0)), 0.08, 1.6)))
	return out
