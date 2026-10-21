extends RefCounted
## Two languages (PART EA-R R1, v0.11.12). Every word the game shows lives in res://lang/strings.csv - columns
## keys,th,en; a key is a short English name (tip_age_days), never the Thai itself - read once at start into the
## TranslationServer. Nodes use tr(key); everything else (the simulation, static functions, constants) L.t(key).
## The CSV is kept as it is (lang/strings.csv.import: "keep"), not turned into .translation files, so a corrected
## translation shows the next time the game starts. "\n" in a cell is a line break.
## The keeper's journal (sim.log_entries) keeps {key, args} and is put in words when shown (entry_text), so a
## colony's journal reads in whichever language the game is in; lines saved before v0.11.12 are Thai text and stay so.
## An argument that is itself words is {"t": key} (L.k(key)), translated when shown.

const CSV := "res://lang/strings.csv"
const LANGS := [["th", "\u0e44\u0e17\u0e22"], ["en", "English"]]     # (the settings window lists these, each in its own words: "Thai" in Thai)

static var _loaded := false
static var _ph: RegEx = null


## Reads the CSV into the TranslationServer (once).
static func load_all() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(CSV, FileAccess.READ)
	if f == null:
		push_error("lang: cannot read " + CSV)
		return
	var head := f.get_csv_line()
	var by_col := {}
	for i in range(1, head.size()):
		var t := Translation.new()
		t.locale = head[i].strip_edges()
		by_col[i] = t
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < head.size() or row[0].strip_edges() == "" or row[0].begins_with("#"):
			continue
		for i in by_col:
			if row[i] != "":
				by_col[i].add_message(row[0].strip_edges(), row[i].c_unescape())
	for i in by_col:
		TranslationServer.add_translation(by_col[i])


## The language a new player gets: Thai on a Thai machine, English everywhere else.
static func default_lang() -> String:
	return "th" if OS.get_locale_language() == "th" else "en"


## Shows the game in this language ("th" or "en").
static func use(lang: String) -> void:
	load_all()
	if not LANGS.any(func(l): return l[0] == lang):
		lang = default_lang()                # (settings.cfg or --lang= naming a language the game has no words for)
	TranslationServer.set_locale(lang)


static func current() -> String:
	return TranslationServer.get_locale().left(2)


## The words for a key in the language in use (the key itself if it has none).
static func t(key: String) -> String:
	load_all()
	return String(TranslationServer.translate(key))


## The words for a key, with its %-placeholders filled (args: a value, or an Array of them; {"t": key} = words).
static func f(key: String, args = []) -> String:
	var text := t(key)
	var a: Array = args if args is Array else [args]
	if a.is_empty():
		return text
	a = a.map(_word)
	return text % a if _fits(text, a) else text


## Whether the values fit the %-placeholders (a journal line comes from the save, which anything can change, and a
## line whose values do not fit would stop the game with a script error - PART EA-R R8).
static func _fits(text: String, a: Array) -> bool:
	if _ph == null:
		_ph = RegEx.create_from_string("%[-+ 0#]*[0-9]*(?:\\.[0-9]+)?([sdfoxXcv%])")
	var i := 0
	for m in _ph.search_all(text):
		var c := m.get_string(1)
		if c == "%":
			continue
		if i >= a.size():
			return false
		if c != "s" and c != "v" and not (a[i] is int or a[i] is float or (c == "c" and a[i] is String)):
			return false
		i += 1
	return i == a.size()


## An argument to be put in words when shown (a journal line kept as key + args).
static func k(key: String) -> Dictionary:
	return {"t": key}


static func _word(v):
	return t(String(v.t)) if v is Dictionary and v.has("t") else v


## One journal line in words: {key, args} (v0.11.12 on) or the Thai text it was saved with.
static func entry_text(e: Dictionary) -> String:
	if e.has("key"):
		return f(String(e.key), e.get("args", []))
	return String(e.get("text", ""))


## When a journal line was written ("Day 12 06:30").
static func stamp(e: Dictionary) -> String:
	if e.has("day"):
		return f("log_stamp", [e.day, String(e.get("clock", ""))])
	return String(e.get("stamp", ""))
