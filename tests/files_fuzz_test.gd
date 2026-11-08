extends SceneTree
## The files beside the saves that came after the security review of v0.11.15 (docs/release/SECURITY_REVIEW.md), broken
## or changed by hand, in a folder of their own (user://filesfuzz/, made and emptied here) - none may give a script
## error, run anything, hang, or take a great deal of memory (v0.12.9):
##   harmony.json (the points purse), home.json (the Home's tanks and shelves), slotN_nest.png / slotN_outworld.png
##   (the tanks' pictures; one that says 16 000 x 16 000 pixels must be refused from its header, not decoded).
##   godot --headless --path . --script res://tests/files_fuzz_test.gd     -> "FILES FUZZ TEST PASSED"

const Store := preload("res://scripts/game/save_store.gd")
const Harmony := preload("res://scripts/game/harmony.gd")
const HomeStore := preload("res://scripts/game/home_store.gd")
const NestCard := preload("res://scripts/game/nest_card.gd")
const OutworldCard := preload("res://scripts/game/outworld_card.gd")
const PngCheck := preload("res://scripts/game/png_check.gd")
const DIR := "user://filesfuzz/"
var ok := true


func _init() -> void:
	Store.base = DIR
	Harmony.base = DIR
	_clear(DIR)
	DirAccess.make_dir_recursive_absolute(DIR)
	_harmony()
	_home()
	_cards()
	_clear(DIR)
	print("FILES FUZZ TEST PASSED" if ok else "FILES FUZZ TEST FAILED")
	quit(0 if ok else 1)


func _harmony() -> void:
	var cases := {
		"empty": "", "not JSON": "}{ not json", "a list": "[1, 2, 3]", "points as text": "{\"points\": \"lots\", \"v\": 2}",
		"points negative": "{\"points\": -5, \"v\": 2}", "points huge": "{\"points\": 1e300, \"v\": 2}",
		"an object": "{\"points\": Object(Node), \"v\": 2}", "deep": "[".repeat(100000),
		"water_paid wrong": "{\"points\": 3, \"v\": 2, \"water_paid\": {\"x\": \"y\", \"1\": [1], \"2\": 5}}",
		"too big": "{\"points\": 3, \"v\": 2, \"pad\": \"%s\"}" % "x".repeat(10000),
	}
	for name in cases:
		_write(DIR + "harmony.json", cases[name])
		var h := Harmony.new()
		h.load_purse()
		_check("harmony.json %s: points a sane number" % name, h.points >= 0.0 and h.points <= Harmony.MAX_POINTS)
		_check("harmony.json %s: water_paid only numbers" % name, h.water_paid.values().all(func(v): return v is float))


func _home() -> void:
	var cases := {
		"empty": "", "not JSON": "nope", "a number": "42", "deep": "{\"tanks\": %s}" % "[".repeat(100000),
		"wrong kinds": "{\"tanks\": \"1,2\", \"wild\": {\"a\": 1}, \"big\": \"yes\", \"shelves\": [9, \"x\", 2], \"farms\": 7}",
		"slots out of range": "{\"tanks\": [-1, 0, 99999999, 1e300], \"wild\": [2], \"shelves\": [2, 2, 2, 2, 2, 2, 2, 2, 2]}",
		"too big": "{\"tanks\": [1], \"pad\": \"%s\"}" % "x".repeat(10000),
	}
	for name in cases:
		_write(DIR + "home.json", cases[name])
		var h := HomeStore.new()
		h.load_layout()
		var slots: Array = h.tanks + h.wild + h.farms
		_check("home.json %s: some tank, slots sane" % name, not h.tanks.is_empty()
				and slots.all(func(s): return s is int and s >= 1 and s <= 999))
		_check("home.json %s: shelves sane" % name, h.shelves.size() <= HomeStore.MAX_SHELVES)
		DirAccess.remove_absolute(DIR + "home.json")


func _cards() -> void:
	var small := Image.create(8, 8, false, Image.FORMAT_RGB8)
	small.fill(Color(0.3, 0.2, 0.1))
	small.save_png(NestCard.path(DIR.trim_suffix("/"), 1))
	small.save_png(OutworldCard.path(DIR.trim_suffix("/"), 1))
	_check("a good nest picture is read", NestCard.read(DIR.trim_suffix("/"), 1) != null)
	_check("a good outworld picture is read", OutworldCard.read(DIR.trim_suffix("/"), 1) != null)
	# a real PNG's header with its size changed to 16 000 x 16 000: refused before anything is decoded
	var buf := small.save_png_to_buffer()
	var big := buf.duplicate()
	for i in [16, 20]:
		big[i] = 0
		big[i + 1] = 0
		big[i + 2] = 0x3E
		big[i + 3] = 0x80                       # (16 000, big-endian)
	_check("the header read: good", PngCheck.fits(buf, 512, 1024))
	_check("the header read: 16 000 x 16 000 refused", not PngCheck.fits(big, 1024, 1024))
	var cases := {"16 000 x 16 000": big, "empty": PackedByteArray(), "not a PNG": "hello".to_utf8_buffer(),
		"cut short": buf.slice(0, 30), "only the header": buf.slice(0, 24)}
	for name in cases:
		for card in [[NestCard, "nest"], [OutworldCard, "outworld"]]:
			var f := FileAccess.open(card[0].path(DIR.trim_suffix("/"), 2), FileAccess.WRITE)
			f.store_buffer(cases[name])
			f.close()
			_check("%s picture %s: not read" % [card[1], name], card[0].read(DIR.trim_suffix("/"), 2) == null)


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _check(what: String, good: bool) -> void:
	if not good:
		ok = false
		print("FAIL: ", what)


func _clear(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for d in DirAccess.get_directories_at(dir):
		_clear(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
