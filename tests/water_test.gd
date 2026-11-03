extends SceneTree
## The water tanks (the keeper, 2026-11-03): filled from the Home - the time kept in slotN.json and read back; a tank's
## level worked out from its meta, refilled by the helper when it runs dry; the helper in the simulation fills an empty
## tank; Colony Harmony for a filling under 30 %, once an hour a tank.
##   godot --headless --path . --script res://tests/water_test.gd     -> "WATER TEST PASSED"

const Sim := preload("res://scripts/sim/simulation.gd")
const Store := preload("res://scripts/game/save_store.gd")
const Harmony := preload("res://scripts/game/harmony.gd")
const DIR := "user://watertest/"

var ok := true


func _case(name: String, fine: bool, got = "") -> void:
	print("  %-58s %s %s" % [name, "ok" if fine else "FAILED", str(got)])
	ok = ok and fine


func _init() -> void:
	Store.base = DIR
	Harmony.base = DIR
	DirAccess.make_dir_recursive_absolute(DIR + "saves")
	var s := Sim.new()
	s.setup(7, 14, false, "keeper")
	s.water = 0.4
	Store.save(1, s)
	var m := Store.meta(1)
	_case("the meta has the water and its use a day", is_equal_approx(float(m.get("water", -1.0)), 0.4) and float(m.get("water_use", 0.0)) > 0.0, m.get("water_use"))
	var now := Time.get_unix_time_from_system()
	_case("its level now, just saved", absf(Store.water_now(m, 1.0, false) - 0.4) < 0.01, Store.water_now(m, 1.0, false))
	m["saved_unix"] = now - 3600.0 * 1000.0
	_case("long ago, no helper: empty", Store.water_now(m, 1.0, false) == 0.0)
	_case("long ago, the helper on: filled again", Store.water_now(m, 1.0, true) > 0.0)
	Store.add_refill(1, now - 10.0)
	Store.add_refill(1, now)
	var m2 := Store.meta(1)
	_case("two fillings kept in slot1.json", Store.refills(m2).size() == 2, m2.get("refills"))
	_case("filled from the Home: full", Store.water_now(m2, 1.0, false) > 0.99)
	Store.save(1, s)
	_case("the next save leaves them out", Store.refills(Store.meta(1)).is_empty())
	# the helper (time away): an empty tank is filled
	s.water = 0.0
	s.humidity = 0.7
	s.auto_care(1)
	_case("the helper fills an empty tank", s.water == 1.0)
	# Colony Harmony
	var h := Harmony.new()
	h.points = 0.0
	_case("filled at 50 %: nothing", h.pay_water(1, 0.5) == 0.0)
	_case("filled at 20 %: 30 points", h.pay_water(1, 0.2) == 30.0 and h.points == 30.0)
	_case("again within the hour: nothing", h.pay_water(1, 0.1) == 0.0)
	_case("another tank: 30 points", h.pay_water(2, 0.1) == 30.0)
	var h2 := Harmony.new()
	h2.load_purse()
	_case("the hour kept in harmony.json", h2.pay_water(1, 0.1) == 0.0 and h2.points == 60.0, h2.points)
	for f in DirAccess.get_files_at(DIR + "saves"):
		DirAccess.remove_absolute(DIR + "saves/" + f)
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + f)
	print("WATER TEST PASSED" if ok else "WATER TEST FAILED")
	quit()
