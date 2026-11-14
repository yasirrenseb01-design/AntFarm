extends SceneTree
## The album's plates are never lost and never told twice (v0.13.19, the keeper: "New in the album: Plate IIb" again, in
## the bigger tank after an update, though it was won long before):
##  1. settings saved from an older dict (plate a only) over a file that has a and b: the file keeps a and b
##  2. the HUD with an older dict (a only) in a colony past 200 workers: plate b taken in quietly from the file, not told
##   godot --headless --path . --script res://tests/album_test.gd     -> "ALBUM TEST PASSED"

const Store := preload("res://scripts/game/save_store.gd")
const Sim := preload("res://scripts/sim/simulation.gd")
const Hud := preload("res://scripts/view/ui/hud.gd")
const DIR := "user://albumtest/"

var ok := true


func _check(what: String, good: bool) -> void:
	print(("  ok    " if good else "  FAIL  ") + what)
	ok = ok and good


func _init() -> void:
	Store.base = DIR
	DirAccess.make_dir_recursive_absolute(DIR)
	DirAccess.remove_absolute(DIR + "settings.cfg")
	_check("union: %s" % Store.album_union("lasius_niger:a", "lasius_niger:a,b;other:x"),
		Store.album_union("lasius_niger:a", "lasius_niger:a,b;other:x") == "lasius_niger:a,b;other:x")
	Store.save_settings({"album": "lasius_niger:a,b", "music": 0.5})
	var old := {"album": "lasius_niger:a", "music": 0.3}
	Store.save_settings(old)
	_check("an older dict saved over a,b: file %s, the dict now %s" % [Store.album_on_disk(), old.album],
		Store.album_on_disk() == "lasius_niger:a,b" and old.album == "lasius_niger:a,b")
	# the HUD: not added to a tree (no UI built) - only its album check
	var s := Sim.new()
	s.setup(5, 210, false, "keeper")
	var h = Hud.new()
	h.sim = s
	h.settings = {"album": "lasius_niger:a"}
	var told := [0]
	h.settings_changed.connect(func(_st): told[0] += 1)
	h._album_seen = 1.0
	h._check_album(0.0)
	_check("HUD with an older dict, %d workers: album %s, told %d time(s)" % [s.workers.size(), h.settings.album, told[0]],
		h.settings.album == "lasius_niger:a,b" and told[0] == 0)
	h.free()
	DirAccess.remove_absolute(DIR + "settings.cfg")
	DirAccess.remove_absolute(DIR)
	print("ALBUM TEST PASSED" if ok else "ALBUM TEST FAILED")
	quit()
