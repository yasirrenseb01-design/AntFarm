extends SceneTree
## The free demo (v0.13.18, scripts/game/demo.gd):
##  1. a colony stops at the demo's limit: workers + pupae + larvae + eggs never past it (a keeper colony of 50 kept fed
##     for 240 days); the queen lays again as ants die, and the journal says it once
##  2. the Home: two tanks from the first day (the second on a shelf for two), nothing sold
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


func _run(cap: int) -> Dictionary:
	var s := Sim.new()
	s.setup(7, 50, false, "keeper")
	s.demo_max = cap
	var told := [0]
	s.logged.connect(func(e): if e.key == "log_demo_limit": told[0] += 1)
	var most := 0
	var reached := -1
	var laid_after := 0
	var eggs_was := 0
	for d in 240:
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
	var r := _run(Demo.MAX_COLONY)
	_check("demo, 50 kept 240 days: largest %d (<= %d + 1), reached on day %d, eggs laid after %d (> 0: laying again as ants die), told %d time(s), workers at the end %d" % [
		r.most, Demo.MAX_COLONY, r.reached, r.laid_after, r.told, r.workers],
		r.most <= Demo.MAX_COLONY + 1 and r.reached >= 0 and r.laid_after > 0 and r.told == 1)
	var f := _run(0)
	_check("full game, the same colony: largest %d (past %d)" % [f.most, Demo.MAX_COLONY], f.most > Demo.MAX_COLONY + 5)
	# the Home in a sandbox: a first run, then opened again
	Store.base = "user://demo_test/"
	DirAccess.make_dir_recursive_absolute(Store.base)
	DirAccess.remove_absolute(Store.base + "home.json")
	Demo.forced = true
	var h := HomeStore.new()
	h.load_layout()
	var p: Array = h.places()
	_check("demo Home: tanks %s, shelves %s, the second on shelf %d" % [str(h.tanks), str(h.shelves), int(p[1].shelf) if p.size() > 1 else -9],
		h.tanks.size() == Demo.TANKS and h.shelves == [2] and p.size() == 2 and int(p[1].shelf) == 0)
	_check("demo shop: why_not %s, buy %s" % [h.why_not("small", 1e9), str(h.buy("small"))], h.why_not("small", 1e9) == "shop_demo" and not h.buy("small"))
	var again := HomeStore.new()
	again.load_layout()
	_check("opened again: tanks %s shelves %s (no more given)" % [str(again.tanks), str(again.shelves)], again.tanks == h.tanks and again.shelves == [2])
	Demo.forced = false
	var full := HomeStore.new()
	full.load_layout()
	_check("the full game opens that home.json: tanks %s, shop %s" % [str(full.tanks), full.why_not("small", 1e9)],
		full.tanks == h.tanks and full.why_not("small", 1e9) == "")
	DirAccess.remove_absolute(Store.base + "home.json")
	DirAccess.remove_absolute(Store.base + "home.json.bak")
	print("DEMO TEST PASSED" if ok else "DEMO TEST FAILED")
	quit()
