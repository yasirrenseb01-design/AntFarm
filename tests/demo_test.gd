extends SceneTree
## The free demo (v0.13.18, scripts/game/demo.gd):
##  1. a colony stops at the demo's limit: workers + pupae + larvae + eggs never past it (a keeper colony of 50 kept fed
##     for 130 days); the queen lays again as ants die, and the journal says it once
##  2. the Home: one small tank as in the full game; the shop sells the bigger tank once, nothing else (v0.13.19)
##  3. the full game is not touched: a colony without the limit lays past it the same days (the 25-day baseline of
##     tools/check.ps1 is the full game's as before)
##   godot --headless --path . --script res://tests/demo_test.gd

const Sim := preload("res://scripts/sim/simulation.gd")
const Demo := preload("res://scripts/game/demo.gd")
const HomeStore := preload("res://scripts/game/home_store.gd")
const Store := preload("res://scripts/game/save_store.gd")
var ok := true


func _check(what: String, good: bool) -> void:
	print(("  ok    " if good else "  FAIL  ") + what)
	ok = ok and good


func _run(cap: int, days: int) -> Dictionary:
	var s := Sim.new()
	s.setup(7, 50, false, "keeper")
	s.demo_max = cap
	var told := [0]
	s.logged.connect(func(e): if e.key == "log_demo_limit": told[0] += 1)
	var most := 0
	var reached := -1
	var laid_after := 0
	var eggs_was := 0
	for d in days:
		for i in s.TPD:
			s.step()
			if i % 60 == 0:
				var whole: int = s.workers.size() + s.eggs.size() + s.larvae.size() + s.pupae.size()
				most = maxi(most, whole)
				if reached < 0 and cap > 0 and whole >= cap:
					reached = d
				if reached >= 0 and s.eggs.size() > eggs_was:
					laid_after += s.eggs.size() - eggs_was
				eggs_was = s.eggs.size()
		if d % 3 == 0:
			s.auto_care(d)
	return {"most": most, "reached": reached, "laid_after": laid_after, "told": told[0], "workers": s.workers.size()}


func _init() -> void:
	var r := _run(Demo.MAX_COLONY, 130)
	_check("demo, 50 kept 130 days: largest %d (<= %d + 1), reached on day %d, eggs laid after %d (> 0: laying again as ants die), told %d time(s), workers at the end %d" % [
		r.most, Demo.MAX_COLONY, r.reached, r.laid_after, r.told, r.workers],
		r.most <= Demo.MAX_COLONY + 1 and r.reached >= 0 and r.laid_after > 0 and r.told == 1)
	var f := _run(0, 150)
	_check("full game, the same colony: largest %d (past %d)" % [f.most, Demo.MAX_COLONY], f.most > Demo.MAX_COLONY + 5)
	# the Home in a sandbox: a first run, then opened again
	Store.base = "user://demo_test/"
	DirAccess.make_dir_recursive_absolute(Store.base)
	DirAccess.remove_absolute(Store.base + "home.json")
	Demo.forced = true
	var h := HomeStore.new()
	h.load_layout()
	_check("demo Home: tanks %s, shelves %s (one small tank, as the full game starts)" % [str(h.tanks), str(h.shelves)],
		h.tanks.size() == 1 and h.shelves.is_empty())
	var nots := []
	for it in ["small", "shelf2", "shelf4", "farm"]:
		if h.why_not(it, 1e9) == "shop_demo" and not h.buy(it):
			nots.append(it)
	_check("demo shop: not sold %s" % str(nots), nots.size() == 4 and h.tanks.size() == 1 and h.shelves.is_empty())
	_check("demo shop, the bigger tank: short of points '%s', with them '%s'" % [h.why_not("big", 10.0), h.why_not("big", 1e9)],
		h.why_not("big", 10.0) == "shop_short" and h.why_not("big", 1e9) == "")
	var got := h.buy("big")
	_check("demo bought the bigger tank: %s, tanks %s, big %d; again: '%s', buy %s" % [str(got), str(h.tanks), h.big, h.why_not("big", 1e9), str(h.buy("big"))],
		got and h.tanks.size() == 2 and h.big != 0 and h.why_not("big", 1e9) == "shop_owned" and not h.buy("big"))
	Demo.forced = false
	var full := HomeStore.new()
	full.load_layout()
	_check("the full game opens that home.json: tanks %s big %d, small tanks for sale '%s'" % [str(full.tanks), full.big, full.why_not("small", 1e9)],
		full.tanks == h.tanks and full.big == h.big and full.why_not("small", 1e9) == "shop_no_place")
	DirAccess.remove_absolute(Store.base + "home.json")
	DirAccess.remove_absolute(Store.base + "home.json.bak")
	print("DEMO TEST PASSED" if ok else "DEMO TEST FAILED")
	quit()
