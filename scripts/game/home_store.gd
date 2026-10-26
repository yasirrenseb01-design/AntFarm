extends RefCounted
## The Home's layout (the keeper, 2026-10-26): which save slots are the tanks on the desk and which are the wild mode's,
## kept in user://home.json {"v": 1, "tanks": [slot, ...], "wild": [slot, ...]}. Each tank is one colony (a formicarium,
## scenario "keeper"); the wild mode (the garden plot, scenario "wild") has as many colonies as there are tanks, saved
## apart. Slots in neither list are hidden, never deleted: the next tank bought takes one back (a formicarium for the
## tank, a garden for the wild mode) before a new number is used.
## The first time (no home.json): one tank, a new slot of its own; the wild mode's colony the lowest garden slot there
## is (the keeper's slot 1 - their slots 2 and 3 hidden until there are more tanks, as they agreed).

const Store := preload("res://scripts/game/save_store.gd")
const MAX_TEXT := 4096

var tanks: Array = []          # slot numbers, in the order the tanks were had
var wild: Array = []


static func _path() -> String:
	return Store.base + "home.json"


func load_layout() -> void:
	tanks = []
	wild = []
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
		f.store_string(JSON.stringify({"v": 1, "tanks": tanks, "wild": wild}))


## Another tank (the shop): one more colony on the desk and one more in the wild mode.
func add_tank() -> void:
	if tanks.size() >= Store.SLOTS / 2:
		return
	tanks.append(_take(["keeper"]))
	wild.append(_take(["wild"]))
	save_layout()


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
