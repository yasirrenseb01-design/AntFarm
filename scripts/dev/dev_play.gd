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
	if active():
		m._opts.merge(opts, true)
		Store.base = BASE
		Harmony.base = BASE                  # (the HUD's enemy panel pays and saves the purse whatever main._persist says)
