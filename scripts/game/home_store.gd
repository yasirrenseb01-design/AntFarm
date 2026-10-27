extends RefCounted
## The Home's layout (the keeper, 2026-10-26): which save slots are the tanks on the desk and which are the wild mode's,
## kept in user://home.json {"v": 1, "tanks": [slot, ...], "wild": [slot, ...]}. Each tank is one colony (a formicarium,
## scenario "keeper"); the wild mode (the garden plot, scenario "wild") has as many colonies as there are tanks, saved
## apart. Slots in neither list are hidden, never deleted: the next tank bought takes one back (a formicarium for the
## tank, a garden for the wild mode) before a new number is used.
## The first time (no home.json): one tank, a new slot of its own; the wild mode's colony the lowest garden slot there
## is (the keeper's slot 1 - their slots 2 and 3 hidden until there are more tanks, as they agreed).
## The shop (the keeper, 2026-10-27; prices in Colony Harmony points): a second, bigger tank (on the desk, once), a small
## tank (one more colony: it needs a free place on a shelf - the desk holds only the first), a shelf for 2 or for 4
## (only somewhere to put tanks; up to MAX_SHELVES against the walls). Kept with the rest: {"big": slot, "shelves": [2, 4]}.

const Store := preload("res://scripts/game/save_store.gd")
const MAX_TEXT := 4096
const PRICES := {"small": 100.0, "farm": 80.0, "big": 1500.0, "shelf2": 3500.0, "shelf4": 18000.0}
const MAX_SHELVES := 4

var tanks: Array = []          # slot numbers, in the order the tanks were had
var wild: Array = []
var big := 0                   # the bigger tank's slot (0: not bought)
var shelves: Array = []        # each shelf bought: how many tanks it holds (2 or 4)
var farms: Array = []          # the slots of the ant farms bought (a flat glass frame: its colony nests in the glass slab,
                               # sim nest.slab; the keeper, 2026-10-27: sold in the shop, a little cheaper than a small tank)


static func _path() -> String:
	return Store.base + "home.json"


func load_layout() -> void:
	tanks = []
	wild = []
	big = 0
	shelves = []
	farms = []
	var path := _path()
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null and f.get_length() <= MAX_TEXT:
			var d = JSON.parse_string(f.get_as_text())      # (only numbers are taken from it: nothing in the file is run)
			if d is Dictionary:
				tanks = _slots(d.get("tanks"))
				wild = _slots(d.get("wild"))
				for s in tanks:
					wild.erase(s)
				var b = d.get("big")
				if (b is float or b is int) and tanks.has(int(b)):
					big = int(b)
				var sh = d.get("shelves")
				if sh is Array:
					for c in sh:
						if (c is float or c is int) and (int(c) == 2 or int(c) == 4) and shelves.size() < MAX_SHELVES:
							shelves.append(int(c))
				for s in _slots(d.get("farms")):
					if tanks.has(s) and s != big:
						farms.append(s)
	if tanks.is_empty():
		_first_time()
	while wild.size() < tanks.size():
		var w := _take(["wild"])
		if w == 0:
			break
		wild.append(w)
	save_layout()


## Slot numbers from the file: whole numbers in range, each once, no more than there can be.
static func _slots(v) -> Array:
	var out: Array = []
	if v is Array:
		for x in v:
			if (x is float or x is int) and float(x) == floorf(float(x)):
				var s := int(x)
				if s >= 1 and s <= Store.SLOTS and not out.has(s) and out.size() < Store.SLOTS / 2:
					out.append(s)
	return out


func _first_time() -> void:
	var garden := 0
	for s in range(1, Store.SLOTS + 1):
		if garden == 0 and Store.exists(s) and String(Store.meta(s).get("scenario", "keeper")) == "wild":
			garden = s
	if garden != 0 and not wild.has(garden):
		wild.append(garden)
	tanks.append(_free())


func save_layout() -> void:
	DirAccess.make_dir_recursive_absolute(Store.base)
	var f := FileAccess.open(_path(), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"v": 1, "tanks": tanks, "wild": wild, "big": big, "shelves": shelves, "farms": farms}))


## Another tank: one more colony at home and one more in the wild mode; its slot (0 if there can be no more).
func add_tank() -> int:
	if tanks.size() >= Store.SLOTS / 2:
		return 0
	var t := _take(["keeper"])
	if t == 0:
		return 0
	tanks.append(t)                     # (before the wild mode's is picked: else both took the same free number)
	var w := _take(["wild"])
	if w == 0:
		tanks.pop_back()
		return 0
	wild.append(w)
	save_layout()
	return t


## How many small tanks there are (an ant farm takes a small tank's place), and how many there is room for (the desk's
## one and the shelves').
func smalls() -> int:
	return tanks.size() - (1 if big != 0 else 0)


func small_room() -> int:
	var n := 1
	for c in shelves:
		n += int(c)
	return n


## The nest a colony started in that tank has: "glass" in an ant farm, else "soil".
func nest_of(slot: int) -> String:
	return "glass" if farms.has(slot) else "soil"


## Why that cannot be bought now (a key of lang/strings.csv), "" if it can.
func why_not(item: String, points: float) -> String:
	if item == "big" and big != 0:
		return "shop_owned"
	if item.begins_with("shelf") and shelves.size() >= MAX_SHELVES:
		return "shop_no_wall"
	if (item == "small" or item == "farm") and smalls() >= small_room():
		return "shop_no_place"
	if (item == "small" or item == "farm" or item == "big") and tanks.size() >= Store.SLOTS / 2:
		return "shop_full"
	if points < float(PRICES[item]):
		return "shop_short"
	return ""


## Buys it (the points are the caller's to take): true if it was.
func buy(item: String) -> bool:
	match item:
		"big", "farm":
			# (a new slot, never a hidden one: the bigger box, or the glass slab, is set when a colony starts - an old one
			# would keep its own)
			var t := 0
			if tanks.size() < Store.SLOTS / 2:
				t = _free()
				if t != 0:
					tanks.append(t)
					var w := _take(["wild"])
					if w == 0:
						tanks.pop_back()
						t = 0
					else:
						wild.append(w)
			if t == 0:
				return false
			if item == "big":
				big = t
			else:
				farms.append(t)
		"small":
			if add_tank() == 0:
				return false
		"shelf2", "shelf4":
			shelves.append(2 if item == "shelf2" else 4)
		_:
			return false
	save_layout()
	return true


## Where each tank stands: [{"slot", "number", "big", "farm", "shelf" (-1: the desk), "spot"}]. The first small tank and the
## big one on the desk, the other small ones on the shelves in the order they were bought.
func places() -> Array:
	var out: Array = []
	var shelf := 0
	var spot := 0
	var desk_small := false
	for i in tanks.size():
		var s: int = tanks[i]
		var p := {"slot": s, "number": i + 1, "big": s == big, "farm": farms.has(s), "shelf": -1, "spot": 0}
		if s != big:
			if not desk_small:
				desk_small = true
			else:
				while shelf < shelves.size() and spot >= int(shelves[shelf]):
					shelf += 1
					spot = 0
				p.shelf = shelf if shelf < shelves.size() else -2      # (-2: nowhere - a home.json changed by hand)
				p.spot = spot
				spot += 1
		out.append(p)
	return out


## A hidden slot holding a colony of that scenario, else the lowest number with nothing in it.
func _take(scenarios: Array) -> int:
	for s in hidden():
		if scenarios.has(String(Store.meta(s).get("scenario", "keeper"))):
			return s
	return _free()


func _free() -> int:
	for s in range(1, Store.SLOTS + 1):
		if not Store.exists(s) and not tanks.has(s) and not wild.has(s):
			return s
	return 0


## Saved colonies in neither list.
func hidden() -> Array:
	var out: Array = []
	for s in range(1, Store.SLOTS + 1):
		if Store.exists(s) and not tanks.has(s) and not wild.has(s):
			out.append(s)
	return out


func shown(slot: int) -> bool:
	return tanks.has(slot) or wild.has(slot)


## The colony to open behind the title: the last one played if it is still shown, else the first shown that has one;
## 0 if none has (a first run: the demo garden).
func pick(last: int) -> int:
	if shown(last) and Store.exists(last):
		return last
	for s in tanks + wild:
		if Store.exists(s):
			return s
	return 0
