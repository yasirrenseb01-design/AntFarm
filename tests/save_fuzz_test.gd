extends SceneTree
## Files on the keeper's disk that anyone or any program can change must never run code, hang or stop the game with a
## script error (PART EA-R R8): broken and hand-changed saves, a settings.cfg naming a script, odd slotN.json menu notes,
## odd journal lines, and whatever another program sends to the one-game-at-a-time port. Every case must come out the
## way it says, with no script error on the way (counted by a Logger).
##   godot --headless --path . --script res://tests/save_fuzz_test.gd     -> "SAVE FUZZ TEST PASSED"

const Sim := preload("res://scripts/sim/simulation.gd")
const Store := preload("res://scripts/game/save_store.gd")
const Check := preload("res://scripts/sim/save_check.gd")
const M := preload("res://scripts/sim/save_migrations.gd")
const L := preload("res://scripts/sim/lang.gd")
const One := preload("res://scripts/game/single_instance.gd")
const DIR := "user://fuzz/"


class Errors extends Logger:
	var n := 0
	var last := ""

	func _log_error(function: String, _file: String, _line: int, _code: String, rationale: String, _notify: bool,
			type: int, _bt: Array[ScriptBacktrace]) -> void:
		if type == ERROR_TYPE_SCRIPT:
			n += 1
			last = "%s: %s" % [function, rationale]

	func _log_message(_message: String, _error: bool) -> void:
		pass


var errors := Errors.new()
var ok := true


func _init() -> void:
	OS.add_logger(errors)
	_clear(DIR)
	Store.base = DIR
	DirAccess.make_dir_recursive_absolute(DIR + "saves")
	_saves()
	_settings()
	_meta()
	_words()
	_port()
	_clear(DIR)
	print("script errors on the way: %d" % errors.n)
	ok = ok and errors.n == 0
	print("SAVE FUZZ TEST PASSED" if ok else "SAVE FUZZ TEST FAILED")
	quit()


## One case: what came out against what should, and no script error on the way.
func _case(name: String, got, want: Array) -> void:
	var before := errors.n
	var fine: bool = got in want and errors.n == before
	print("  %-46s %-11s %s" % [name, str(got), "ok" if fine else "FAILED (wanted %s) %s" % [want, errors.last]])
	ok = ok and fine


func _counted(name: String, f: Callable, want: Array) -> void:
	var before := errors.n
	var got = f.call()
	var fine: bool = got in want and errors.n == before
	print("  %-46s %-11s %s" % [name, str(got), "ok" if fine else "FAILED (wanted %s; %d script errors, last %s)" % [want,
		errors.n - before, errors.last]])
	ok = ok and fine


# ---------------------------------------------------------------- saves

## As main.gd loads a slot: "loaded" (and played on a little, its journal put in words), "newer" or "unreadable".
func _load() -> String:
	var data := Store.load_slot(1)
	if data.is_empty():
		return "unreadable"
	var ver = data.sim.get("version", -1)
	var v: int = int(ver) if ver is int or ver is float else -1
	if v > Sim.SAVE_VERSION:
		return "newer"
	if v < 1:
		return "unreadable"
	if v < Sim.SAVE_VERSION:
		data.sim = M.migrate(data.sim, Sim.SAVE_VERSION)
	if Check.problem(data.sim) != "":
		return "unreadable"
	var s := Sim.new()
	s.from_dict(data.sim)
	for i in 30:
		s.step()
	for e in s.log_entries:
		L.entry_text(e)
		L.stamp(e)
	return "loaded"


func _write_var(v) -> void:
	var f := FileAccess.open_compressed(Store._path(1), FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	f.store_var(v)
	f.close()


func _write_raw(bytes: PackedByteArray, compressed := true) -> void:
	var f := FileAccess.open_compressed(Store._path(1), FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD) if compressed \
		else FileAccess.open(Store._path(1), FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()


func _noise(n: int, seed_value: int) -> PackedByteArray:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var b := PackedByteArray()
	b.resize(n)
	for i in n:
		b[i] = r.randi() & 255
	return b


func _saves() -> void:
	print("saves:")
	var s := Sim.new()
	s.setup(3, 14, false, "keeper")
	for i in 300:
		s.step()
	var good := {"meta": s.summary(), "sim": s.to_dict()}
	_write_var(good)
	_counted("a good save", _load, ["loaded"])
	var bytes := var_to_bytes(good)
	# the file itself
	_write_raw(PackedByteArray(), false)
	_counted("an empty file", _load, ["unreadable"])
	_write_raw(_noise(5000, 1), false)
	_counted("random bytes", _load, ["unreadable"])
	_write_raw(_noise(5000, 2))
	_counted("random bytes, compressed", _load, ["unreadable"])
	for cut in [4, 1000, bytes.size() / 2, bytes.size() - 1]:
		var f := FileAccess.open_compressed(Store._path(1), FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
		f.store_32(bytes.size())
		f.store_buffer(bytes.slice(0, cut))
		f.close()
		_counted("cut short at %d of %d bytes" % [cut, bytes.size()], _load, ["unreadable"])
	var whole := FileAccess.get_file_as_bytes(Store._path(1))
	_write_raw(whole.slice(0, whole.size() / 2), false)
	_counted("compressed file cut in half", _load, ["unreadable"])
	var f := FileAccess.open_compressed(Store._path(1), FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	f.store_32(0xFFFFFFF0)
	f.store_buffer(_noise(64, 3))
	f.close()
	_counted("says it is 4 GB long", _load, ["unreadable"])
	var big := PackedByteArray()
	big.resize(Store.MAX_FILE + 1)
	_write_raw(big, false)
	_counted("a file bigger than any save", _load, ["unreadable"])
	# what is in it
	_write_var(42)
	_counted("a number, not a save", _load, ["unreadable"])
	_write_var(["meta", "sim"])
	_counted("a list, not a save", _load, ["unreadable"])
	_write_var({"meta": {}})
	_counted("no colony in it", _load, ["unreadable"])
	_write_var({"meta": [], "sim": good.sim})
	_counted("menu notes not a dictionary", _load, ["unreadable"])
	var with_object := var_to_bytes_with_objects({"meta": {}, "sim": {"version": Sim.SAVE_VERSION, "x": RefCounted.new()}})
	f = FileAccess.open_compressed(Store._path(1), FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	f.store_32(with_object.size())
	f.store_buffer(with_object)
	f.close()
	_counted("an object inside (never decoded)", _load, ["unreadable"])
	var deep := PackedByteArray()
	for i in 100000:
		deep.append_array(PackedByteArray([28, 0, 0, 0, 1, 0, 0, 0]))     # (a list in a list in a list ...)
	deep.append_array(PackedByteArray([0, 0, 0, 0]))
	_write_raw(_framed(deep))
	_counted("lists 100 000 deep", _load, ["unreadable"])
	_write_raw(_framed(PackedByteArray([28, 0, 0, 0, 255, 255, 255, 127])))
	_counted("a list that says it has 2 147 483 647 items", _load, ["unreadable"])
	# a save changed by hand: each value of the wrong kind, the sizes that do not add up
	var mutations := {
		"version as text": func(d): d.version = "eleven",
		"version as a list": func(d): d.version = [11],
		"version from the future": func(d): d.version = Sim.SAVE_VERSION + 1,
		"version 0": func(d): d.version = 0,
		"a value missing (sugar)": func(d): d.erase("sugar"),
		"a value missing (nest.rho)": func(d): d.nest.erase("rho"),
		"nest 5000 voxels wide": func(d): d.nest.nx = 5000,
		"nest of size 0": func(d): d.nest.ny = 0,
		"nest voxels cut short": func(d): d.nest.rho = d.nest.rho.slice(0, 10),
		"nest voxels the wrong kind": func(d): d.nest.dist = PackedFloat32Array(),
		"pheromone grid cut short": func(d): d.home.val = PackedFloat32Array([0.0]),
		"pheromone grid as text": func(d): d.food = "food",
		"an ant row cut short": func(d): d.workers[0] = d.workers[0].slice(0, 3),
		"an ant row too long": func(d): d.workers[0].append(1),
		"an ant's position as text": func(d): d.workers[0][Sim.ANT_FIELDS.find("pos")] = "here",
		"an ant as a number": func(d): d.workers[0] = 7,
		"ants as text": func(d): d.workers = "ants",
		"300 000 ants": func(d): d.workers = range(300000),
		"outside ids as text": func(d): d.outside = ["a"],
		"duty_rng empty": func(d): d.duty_rng = [],
		"climate as a number": func(d): d.climate = 1,
		"climate value the wrong kind": func(d): d.climate.air = "warm",
		"derived values missing": func(d): d.derived = {},
		"an egg as text": func(d): d.eggs = ["egg"],
		"the queen as a list": func(d): d.queen = [],
		"stats as a number": func(d): d.stats = 0,
		"journal as text": func(d): d.log = "log",
		"a journal line as a number": func(d): d.log.append(3),
	}
	for name in mutations:
		var d: Dictionary = good.sim.duplicate(true)
		mutations[name].call(d)
		_write_var({"meta": good.meta, "sim": d})
		var want := ["newer"] if name == "version from the future" else ["unreadable"]
		_counted(name, _load, want)
	# odd but well-formed: loads and plays on
	var odd := {
		"a journal line with too few values": func(d): d.log.append({"key": "log_young_colony", "args": [], "day": 1, "clock": "", "kind": ""}),
		"a journal line with text for a number": func(d): d.log.append({"key": "log_young_colony", "args": ["many"], "day": 1, "clock": "", "kind": ""}),
		"a journal line with a key there is no word for": func(d): d.log.append({"key": "no_such_key", "args": [1, 2], "day": 1, "clock": "", "kind": ""}),
		"sugar a huge number": func(d): d.sugar = 1e30,
		"a named ant with a very long name": func(d): d.workers[0][Sim.ANT_FIELDS.find("name")] = "x".repeat(100000),
	}
	for name in odd:
		var d: Dictionary = good.sim.duplicate(true)
		odd[name].call(d)
		_write_var({"meta": good.meta, "sim": d})
		_counted(name, _load, ["loaded"])
	# a good save is never taken for a broken one: colonies of every kind, fed, with stones, enemies let in, the fridge on
	var refused := []
	var states := 0
	for c in [[1, 0, false, "keeper"], [2, 14, true, "keeper"], [3, 14, false, "wild"], [4, 40, false, "keeper"]]:
		var g := Sim.new()
		g.setup(c[0], c[1], c[2], c[3])
		g.fridge_on = c[0] == 4
		for q in 24:
			if q % 3 == 0:
				g.add_water()
				for k in ["honey", "cricket", "sugar"]:
					g.place_food(k, Vector2(100 + q * 7, 120 + q * 3))
				g.add_rock(Vector2(200 + q, 300), 12.0)
			if q % 8 == 1:
				for e in ["wolf_spider", "centipede", "ground_beetle"]:
					g.release_enemy(e)
			for t in g.TPD / 4:
				g.step()
			var why: String = Check.problem(bytes_to_var(var_to_bytes(g.to_dict())))
			states += 1
			if why != "":
				refused.append("%s day %.2f: %s" % [c, q / 4.0, why])
	_case("%d states of 4 colonies over 6 days, none refused" % states, refused.size(), [0])
	if not refused.is_empty():
		print("    ", refused[0])
	# older saves still load
	for v in range(1, Sim.SAVE_VERSION):
		var p := "res://tests/fixtures/save_v%d.antfarm" % v
		if FileAccess.file_exists(p):
			DirAccess.copy_absolute(p, Store._path(1))
			_counted("save v%d (tests/fixtures)" % v, _load, ["loaded"])


## Bytes as store_var() frames them in a save (the length first).
func _framed(b: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(4)
	out.encode_u32(0, b.size())
	out.append_array(b)
	return out


# ---------------------------------------------------------------- settings.cfg

func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _settings() -> void:
	print("settings.cfg:")
	var cfg := DIR + "settings.cfg"
	var ran := DIR + "ran.txt"
	_write_text(DIR + "evil.gd", "extends RefCounted\nstatic func _static_init():\n\tFileAccess.open(\"%s\", FileAccess.WRITE).store_string(\"ran\")\n" % ran)
	for text in ["[game]\nslot=Resource(\"%sevil.gd\")\n" % DIR, "[game]\nx=Object(RefCounted,\"script\":Resource(\"%sevil.gd\"))\n" % DIR,
			"[game]\nx = Resource ( \"%sevil.gd\" )\n" % DIR]:
		_write_text(cfg, text)
		var s := Store.settings()
		Store.save_settings(s)
		_case("names a script: " + text.get_slice("\n", 1).left(30), "ran" if FileAccess.file_exists(ran) else "not run", ["not run"])
	_write_text(cfg, "[game]\nslot=\"two\"\naway=[1,2]\ncare=\"yes\"\nlang=5\nview=Vector2(1, 2)\nmusic=1e30\nshow_fps=3\nslot2=Color(1, 0, 0, 1)\n")
	var s := Store.settings()
	var kinds_ok: bool = s.has_all(["view", "music", "show_fps"]) and s.slot is int and s.away is int and s.care is bool and \
		s.lang is String and s.view is String and s.music is float and s.music <= 1.0 and s.show_fps is bool and not s.has("slot2")
	_case("values of the wrong kind", "plain" if kinds_ok else str(s), ["plain"])
	_write_text(cfg, "[game]\nslot=99\naway=-4\n")
	s = Store.settings()
	_case("slot and away out of range", "%d %d" % [s.slot, s.away], ["%d 0" % Store.SLOTS])
	_write_text(cfg, "[game]\nslot=Color(1,0\n")
	_counted("a value that does not parse", func(): return Store.settings().slot, [1])
	_write_text(cfg, _noise(3000, 4).get_string_from_ascii())
	_counted("random bytes", func(): return Store.settings().slot, [1])
	_write_text(cfg, "[game]\nslot=" + "[".repeat(100000) + "\n")
	_counted("a value 100 000 lists deep", func(): return Store.settings().slot, [1])
	var big := FileAccess.open(cfg, FileAccess.WRITE)
	big.store_buffer(_spaces(Store.MAX_TEXT + 1))
	big.close()
	_counted("a file bigger than any settings", func(): return Store.settings().slot, [1])
	L.use("zz")
	_case("a language the game has no words for", L.current(), [L.default_lang()])
	# (the reason for all this: read as it was, the file would have run the script)
	var cf := ConfigFile.new()
	cf.parse("[game]\nx=Resource(\"%sevil.gd\")\n" % DIR)
	_case("(read as before v0.11.15: the script ran)", "ran" if FileAccess.file_exists(ran) else "not run", ["ran"])
	DirAccess.remove_absolute(cfg)


func _spaces(n: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(n)
	b.fill(32)
	return b


# ---------------------------------------------------------------- slotN.json (the menu's notes)

func _meta() -> void:
	print("slotN.json:")
	var p := Store._meta_path(1)
	_write_text(p, "{\"day\": \"many\", \"workers\": [1], \"queen\": \"yes\", \"saved_unix\": {}, \"scenario\": 4, \"volume\": 2.5}")
	var m := Store.meta(1)
	_case("values of the wrong kind left out", ",".join(m.keys()), ["volume"])
	_write_text(p, "[".repeat(100000))
	_counted("100 000 lists deep", func(): return Store.meta(1).size(), [0])
	_write_text(p, "not json")
	_counted("not JSON", func(): return Store.meta(1).size(), [0])
	DirAccess.remove_absolute(p)


# ---------------------------------------------------------------- the words

func _words() -> void:
	print("words:")
	_counted("too few values", func(): return L.f("log_stamp", [3]) != "", [true])
	_counted("too many values", func(): return L.f("log_stamp", [3, "x", 4]) != "", [true])
	_counted("text for a number", func(): return L.f("log_stamp", ["x", "y"]) != "", [true])
	_counted("a key there are no words for, with values", func(): return L.f("no_such_key", [1]), ["no_such_key"])
	_counted("the right values", func(): return L.f("log_stamp", [3, "06:00"]).contains("3"), [true])


# ---------------------------------------------------------------- the one-game-at-a-time port

func _port() -> void:
	print("port 127.0.0.1:%d (as %d):" % [One.PORT + 5, One.PORT])
	var one = One.new()
	var woke := [0]
	one.wake.connect(func(): woke[0] += 1)
	one.listen(One.PORT + 5)
	var quiet := []
	for i in 20:                                  # connections that say nothing
		var c := StreamPeerTCP.new()
		c.connect_to_host("127.0.0.1", One.PORT + 5)
		quiet.append(c)
	var flood := StreamPeerTCP.new()              # a megabyte of rubbish
	flood.connect_to_host("127.0.0.1", One.PORT + 5)
	var t0 := Time.get_ticks_msec()
	var sent := false
	var slowest := 0
	while Time.get_ticks_msec() - t0 < One.PEER_TIMEOUT_MS + 800:
		flood.poll()
		for c in quiet:
			c.poll()
		if not sent and flood.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			flood.put_partial_data(_noise(1 << 20, 5))
			sent = true
		var f0 := Time.get_ticks_usec()
		one._process(0.016)
		slowest = maxi(slowest, Time.get_ticks_usec() - f0)
		OS.delay_msec(16)
	_case("20 silent + 1 MB of rubbish: dropped in time", "%d held" % one._peers.size(), ["0 held"])
	_case("... and no frame held up", "slow" if slowest > 50000 else "quick", ["quick"])
	_case("... and the game not woken by them", woke[0], [0])
	for i in 5:                                   # "show" five times in a row: comes forward once
		One.tell_running(One.PORT + 5)
		for k in 5:
			one._process(0.016)
			OS.delay_msec(10)
	_case("\"show\" 5 times in a row: woken once", woke[0], [1])
	one.stop()
	one.free()


func _clear(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for d in DirAccess.get_directories_at(dir):
		_clear(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
