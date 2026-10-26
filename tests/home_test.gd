extends SceneTree
## The Home's layout (game/home_store.gd) in a folder of its own (user://hometest/, made and emptied here):
##   the keeper's case - slot 1 a garden, slot 2 a garden, slot 3 a formicarium: the wild mode gets slot 1, the first
##   tank a new slot (4), slots 2 and 3 hidden but kept; the colony opened is slot 1 even if slot 3 was played last;
##   another tank takes the hidden ones back (3 for the tank, 2 for the wild mode); it all comes back from home.json;
##   a first run: tank 1, wild 2; a home.json that is not ours: worked out again, nothing from it used.
##   godot --headless --path . --script res://tests/home_test.gd     -> "HOME TEST PASSED"

const Store := preload("res://scripts/game/save_store.gd")
const HomeStore := preload("res://scripts/game/home_store.gd")
const DIR := "user://hometest/"
var ok := true


func _init() -> void:
	Store.base = DIR
	_clear()
	_slot(1, "wild")
	_slot(2, "wild")
	_slot(3, "keeper")
	var h := HomeStore.new()
	h.load_layout()
	_is("keeper's saves: tanks", h.tanks, [4])
	_is("keeper's saves: wild", h.wild, [1])
	_is("hidden", h.hidden(), [2, 3])
	_is("opened (slot 3 played last)", h.pick(3), 1)
	# the bigger tank takes a new slot, never a hidden one (its bigger box is set when a colony starts in it)
	var bigs := HomeStore.new()
	bigs.load_layout()
	bigs.buy("big")
	_is("big tank: a new slot", [bigs.big, bigs.hidden().has(2) and bigs.hidden().has(3)], [5, false])
	bigs.tanks = [4]
	bigs.wild = [1]
	bigs.big = 0
	bigs.save_layout()
	h.add_tank()
	_is("another tank: tanks", h.tanks, [4, 3])
	_is("another tank: wild", h.wild, [1, 2])
	var again := HomeStore.new()
	again.load_layout()
	_is("from home.json: tanks", again.tanks, [4, 3])
	_is("from home.json: wild", again.wild, [1, 2])
	# the shop: the big tank once, small tanks only with room on a shelf, the purse checked
	_is("small, no shelf", again.why_not("small", 1.0e6), "shop_no_place")
	_is("big, too few points", again.why_not("big", 10.0), "shop_short")
	_is("buy big", again.buy("big"), true)
	_is("big again", again.why_not("big", 1.0e6), "shop_owned")
	_is("buy shelf2", again.buy("shelf2"), true)
	_is("buy small", again.buy("small"), true)
	_is("fourth small, shelf full", again.why_not("small", 1.0e6), "shop_no_place")
	_is("each a slot of its own", again.tanks.size() + again.wild.size(), (again.tanks + again.wild).reduce(func(a, x): return a if a.has(x) else a + [x], []).size())
	var shop := HomeStore.new()
	shop.load_layout()
	_is("after the shop: tanks", shop.tanks.size(), 4)
	_is("after the shop: big kept", shop.big, again.big)
	_is("after the shop: shelves", shop.shelves, [2])
	_is("places", shop.places().map(func(p): return [p.shelf, p.spot, p.big]), [[-1, 0, false], [0, 0, false], [-1, 0, true], [0, 1, false]])
	_clear()
	var fresh := HomeStore.new()
	fresh.load_layout()
	_is("first run: tanks", fresh.tanks, [1])
	_is("first run: wild", fresh.wild, [2])
	_is("first run: nothing to open", fresh.pick(1), 0)
	_clear()
	var f := FileAccess.open(DIR + "home.json", FileAccess.WRITE)
	f.store_string('{"tanks": [0, -3, 2.5, "Object(Node)", 99, [1]], "wild": "x"}')
	f.close()
	var odd := HomeStore.new()
	odd.load_layout()
	_is("not ours: tanks", odd.tanks, [1])
	_is("not ours: wild", odd.wild, [2])
	_clear()
	print("HOME TEST %s" % ("PASSED" if ok else "FAILED"))
	quit(0 if ok else 1)


func _is(what: String, got, want) -> void:
	var good: bool = str(got) == str(want)
	print("  %s: %s %s" % [what, str(got), "" if good else "(want %s)" % str(want)])
	ok = ok and good


func _slot(n: int, scenario: String) -> void:
	DirAccess.make_dir_recursive_absolute(DIR + "saves")
	var f := FileAccess.open("%ssaves/slot%d.antfarm" % [DIR, n], FileAccess.WRITE)
	f.store_string("x")
	f.close()
	f = FileAccess.open("%ssaves/slot%d.json" % [DIR, n], FileAccess.WRITE)
	f.store_string(JSON.stringify({"scenario": scenario, "day": 1}))
	f.close()


func _clear() -> void:
	for sub in ["saves/", ""]:
		var d := DirAccess.open(DIR + sub)
		if d == null:
			continue
		for fn in d.get_files():
			d.remove(fn)
