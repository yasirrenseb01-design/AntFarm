extends RefCounted
## The developer's playground (PART 0.14 step 8, the keeper 2026-11-21): a fresh colony to call things up in - the
## enemies now (ui/dev_panel.gd), the ants' doings and the scenes next (steps 9-10) - never saved. Only on the
## developer's machine (game/dev_machine.gd), started from the title page's "Developer".
##   - the colony open when it starts is saved first (main._go_to), then the game reloads into the playground: a young
##     colony of the chosen size in a keeper's tank or on the wild plot, the options merged into main._opts
##     (main_base._new_sim) as if typed after "--" - main._persist is off ("dev-play"), so nothing loads or saves
##   - every file the game might write meanwhile goes to BASE, not the keeper's own (Store.base): a setting changed,
##     the Home, the purse - LESSONS 54
##   - leaving: the game reloads into the keeper's last colony, as at a start
##   - or (step 11, the keeper 2026-11-21: "take one of my big colonies as the playground's start") a copy of one of the
##     keeper's own colonies: its save copied to user://growtest/devplay/ and opened as the year_run colonies are
##     (main "testsave": read only, no time away, never saved) - a grown nest of many chambers, not 2,000 workers
##     crammed into a 3-month nest's two (its nest view froze ~66 s: nest_scene LAYOUT_US)

const DevMachine := preload("res://scripts/game/dev_machine.gd")
const Store := preload("res://scripts/game/save_store.gd")
const Harmony := preload("res://scripts/game/harmony.gd")
const BASE := "user://devplay/"
const SIZES := [14, 200, 1000, 2000]

static var auto_done := false     # (dev: --dev-play-go pressed once only, not again after leaving)
static var opts := {}            # the playground's options while in it (kept over the reload: a static), {} when not


static func active() -> bool:
	return not opts.is_empty()


## Into the playground: `scenario` "keeper" or "wild", `workers` to start with.
static func start(m, scenario: String, workers: int) -> void:
	if not DevMachine.is_dev():
		return
	opts = {"dev-play": "1", "scenario": "wild" if scenario == "wild" else "keeper", "workers": str(clampi(workers, 1, 2000)),
		"nest": "soil", "seed": "7", "lang": TranslationServer.get_locale().left(2)}
	m._go_to(0, "")


## Into the playground with a copy of the keeper's colony in `slot` (the files copied; the keeper's not touched).
static func start_copy(m, slot: int) -> void:
	if not DevMachine.is_dev() or not Store.exists(slot):
		return
	opts = {"dev-play": "1", "copy-slot": str(slot), "lang": TranslationServer.get_locale().left(2)}
	m._go_to(0, "")


## The keeper's colonies to start from, the biggest first: [slot, its summary].
static func colonies() -> Array:
	var out := []
	for s in range(1, 33):
		if Store.exists(s):
			var meta: Dictionary = Store.meta(s)
			if not meta.is_empty():
				out.append([s, meta])
	out.sort_custom(func(a, b): return int(a[1].get("workers", 0)) > int(b[1].get("workers", 0)))
	return out


## Colonies grown by tests/year_run.gd (user://growtest/<name>/, save-name) of at least `most` workers, the biggest
## first: [name, slot, summary] - a grown wild colony for the alates and the flight (the keeper's own may all be tanks).
static func grown_tests(most := 500) -> Array:
	var out := []
	var root := "user://growtest/"
	for d in DirAccess.get_directories_at(root):
		if d == "devplay":
			continue
		for f in DirAccess.get_files_at(root + d + "/saves"):
			if f.begins_with("slot") and f.ends_with(".json") and f.trim_prefix("slot").trim_suffix(".json").is_valid_int():
				var meta = JSON.parse_string(FileAccess.get_file_as_string(root + d + "/saves/" + f))
				if meta is Dictionary and int(meta.get("workers", 0)) >= most:
					out.append([d, int(f.trim_prefix("slot").trim_suffix(".json")), meta])
	out.sort_custom(func(a, b): return int(a[2].get("workers", 0)) > int(b[2].get("workers", 0)))
	return out


## Into the playground with a colony grown by year_run, opened where it is (read only: main "testsave").
static func start_test(m, name: String, slot: int) -> void:
	if not DevMachine.is_dev():
		return
	opts = {"dev-play": "1", "test-save": name, "test-slot": str(slot), "lang": TranslationServer.get_locale().left(2)}
	m._go_to(0, "")


## Out of it: back to the keeper's own colonies (the playground left as it is - nothing of it is kept).
static func leave(m) -> void:
	opts = {}
	Store.base = "user://"
	Harmony.base = "user://"
	m.next_slot = 0
	m.next_nest = ""
	m.skip_title = false
	m.get_tree().reload_current_scene()


## main_base._new_sim: in the playground, its options and its own folder.
static func apply(m) -> void:
	if not active() and m._opts.has("dev-play") and DevMachine.is_dev():
		opts = {"dev-play": "1"}             # (--dev-play [--scenario= --workers=]: the same from the command line - shots, tests)
		if m._opts.has("dev-copy"):
			opts["copy-slot"] = String(m._opts["dev-copy"])     # (--dev-copy=<slot>: a copy of that colony of the keeper's)
		if m._opts.has("dev-test"):
			var dt: PackedStringArray = String(m._opts["dev-test"]).split(",")     # (--dev-test=<save-name>,<slot>: year_run's)
			opts["test-save"] = dt[0]
			opts["test-slot"] = dt[1] if dt.size() > 1 else "1"
	if active():
		if opts.has("copy-slot") and not m._opts.has("testsave"):
			_copy(int(opts["copy-slot"]))
			m._opts["testsave"] = "devplay"      # (then main opens it from user://growtest/devplay/, read only)
			m._opts["slot"] = String(opts["copy-slot"])
		elif opts.has("test-save") and not m._opts.has("testsave"):
			m._opts["testsave"] = String(opts["test-save"])
			m._opts["slot"] = String(opts["test-slot"])
		m._opts.merge(opts, true)
		Store.base = BASE
		Harmony.base = BASE                  # (the HUD's enemy panel pays and saves the purse whatever main._persist says)


## The keeper's save in `slot` (and its summary) copied to user://growtest/devplay/saves/ - read from, never written to.
static func _copy(slot: int) -> void:
	var dst := "user://growtest/devplay/saves/"
	DirAccess.make_dir_recursive_absolute(dst)
	for f in DirAccess.get_files_at(dst):
		DirAccess.remove_absolute(dst + f)       # (the copy before: only one at a time)
	for ext in [".antfarm", ".json"]:
		var src := "user://saves/slot%d%s" % [slot, ext]
		if FileAccess.file_exists(src):
			DirAccess.copy_absolute(src, dst + "slot%d%s" % [slot, ext])
