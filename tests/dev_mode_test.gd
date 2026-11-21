extends SceneTree
## The developer's machine and a player's (PART 0.14 steps 7-8): on a player's the title has no "Developer" page and the
## playground cannot be opened, from the menu or the command line; on the developer's both can. game/dev_machine.gd,
## dev/dev_play.gd, ui/dev_panel.gd (the purse's cap: tests/water_test.gd).
##   godot --headless --path . --script res://tests/dev_mode_test.gd     -> "DEV MODE TEST PASSED"
var ok := true


func _case(what: String, cond: bool) -> void:
	print("  %-60s %s" % [what, "ok" if cond else "FAILED"])
	ok = ok and cond


class FakeMain:
	var _opts := {"dev-play": "1"}
	var went := false
	func _go_to(_s: int, _k: String) -> void:
		went = true


func _init() -> void:
	var D = load("res://scripts/game/dev_machine.gd")
	var Play = load("res://scripts/dev/dev_play.gd")
	var Panel = load("res://scripts/view/ui/dev_panel.gd")
	var Store = load("res://scripts/game/save_store.gd")
	_case("the salted hash: 64 hex, not the id", D.hash_of("x").length() == 64 and not D.hash_of("abc").contains("abc"))
	D.forced = 0
	_case("a player's: no Developer page on the title", Panel.title_page(null, null) == null)
	var m := FakeMain.new()
	Play.start(m, "wild", 200)
	_case("a player's: the playground does not open from the menu", not m.went and not Play.active())
	Play.apply(m)
	_case("a player's: nor from the command line (--dev-play)", not Play.active() and Store.base == "user://")
	D.forced = 1
	Play.start(m, "wild", 200)
	_case("the developer's: it opens (the colony open now saved first)", m.went and Play.active() and Play.opts.scenario == "wild")
	var m2 := FakeMain.new()
	m2._opts = {}
	Play.apply(m2)
	_case("in it: its options, its own folder for every file", m2._opts.get("dev-play") == "1" and m2._opts.get("workers") == "200"
		and Store.base == Play.BASE and load("res://scripts/game/harmony.gd").base == Play.BASE)
	Play.opts = {}
	Store.base = "user://"
	load("res://scripts/game/harmony.gd").base = "user://"
	D.forced = -1
	print("DEV MODE TEST PASSED" if ok else "DEV MODE TEST FAILED")
	quit()
