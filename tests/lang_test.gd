extends SceneTree
## The words of the game (PART EA-R R1, lang/strings.csv): every key the code asks for has words in both languages,
## the %-placeholders of each key are the same in Thai and English (else a line fails to show, or shows the wrong
## number), and no Thai is left in the scripts outside comments (it would never be translated).
##   godot --headless --path . --script res://tests/lang_test.gd     -> "LANG TEST PASSED"
const L := preload("res://scripts/sim/lang.gd")
const PH := "%[-+ 0#]*[0-9]*(?:\\.[0-9]+)?[sdfxXc%]"


func _init():
	var ok := true
	var rows := _csv()
	print("lang/strings.csv: %d keys" % rows.size())
	# both languages there, the same placeholders
	var ph := RegEx.create_from_string(PH)
	for key in rows:
		var th: String = rows[key][0]
		var en: String = rows[key][1]
		if th == "" or en == "":
			print("  empty: ", key)
			ok = false
		var a := ph.search_all(th).map(func(m): return m.get_string())
		var b := ph.search_all(en).map(func(m): return m.get_string())
		if a != b:
			print("  placeholders differ: %s  th %s  en %s" % [key, a, b])
			ok = false
	# every key the code asks for: tr("..."), L.t/L.f("..."), and the lists of keys kept in constants
	var used := {}
	var call := RegEx.create_from_string("(?<![\\w.])(?:tr|L\\.t|L\\.f|sim\\.L\\.t|sim\\.L\\.f)\\(\"([^\"]+)\"")
	var thai := RegEx.create_from_string("[\\x{0e00}-\\x{0e7f}]")
	for path in _scripts("res://scripts"):
		var src := FileAccess.get_file_as_string(path)
		for m in call.search_all(src):
			used[m.get_string(1)] = path
		var ln := 0
		for line in src.split("\n"):
			ln += 1
			var code := _code_part(line)
			if thai.search(code) != null and not path.ends_with("lang.gd"):
				print("  Thai in code: %s:%d" % [path, ln])
				ok = false
	for k in _listed_keys():
		used[k] = "(a list of keys)"
	var missing := 0
	for k in used:
		if not rows.has(k):
			print("  missing in lang/strings.csv: %s  (%s)" % [k, used[k]])
			missing += 1
	ok = ok and missing == 0
	print("keys asked for by the code: %d, missing %d" % [used.size(), missing])
	# the helper reads them, and a journal line comes out in either language
	L.use("en")
	var en_line := L.entry_text({"key": "log_young_colony", "args": [14]})
	L.use("th")
	var th_line := L.entry_text({"key": "log_young_colony", "args": [14]})
	var old_line := L.entry_text({"stamp": "ว.4 06:57", "text": "x", "kind": ""})
	print("journal: en \"%s\" | th \"%s\" | saved before v0.11.12: \"%s\"" % [en_line, th_line, old_line])
	ok = ok and en_line.contains("14") and th_line.contains("14") and en_line != th_line and old_line == "x"
	print("LANG TEST PASSED" if ok else "LANG TEST FAILED")
	quit()


## key -> [th, en] from the CSV (comment rows "# ..." left out).
func _csv() -> Dictionary:
	var out := {}
	var f := FileAccess.open(L.CSV, FileAccess.READ)
	var head := f.get_csv_line()
	assert(head[1] == "th" and head[2] == "en")
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < 3 or row[0] == "" or row[0].begins_with("#"):
			continue
		if out.has(row[0]):
			print("  key twice: ", row[0])
		out[row[0]] = [row[1], row[2]]
	return out


func _scripts(dir: String) -> Array:
	var out := []
	for d in DirAccess.get_directories_at(dir):
		out += _scripts(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	return out


## A line of GDScript without its comment (a "#" outside a string).
func _code_part(line: String) -> String:
	var q := ""
	var i := 0
	while i < line.length():
		var c := line[i]
		if q != "":
			if c == "\\":
				i += 1
			elif c == q:
				q = ""
		elif c == "\"" or c == "'":
			q = c
		elif c == "#":
			return line.substr(0, i)
		i += 1
	return line


## Keys the code keeps in constants and puts in words where it shows them.
func _listed_keys() -> Array:
	var out := []
	var T = load("res://scripts/sim/text_th.gd")
	for k in T.get_script_constant_map():
		var v = T.get_script_constant_map()[k]
		if v is String:
			out.append(v)
		elif v is Dictionary:
			out += v.values()
	var base = load("res://scripts/sim/parts/sim_base.gd")
	out += base.MONTHS
	var Store = load("res://scripts/game/save_store.gd")
	for r in Store.AWAY_RATES:
		out.append(r[0])
	var cols = load("res://scripts/view/ui/parts/hud_colonies.gd")
	for list in [cols.NEW_SCENARIOS, cols.NEW_NESTS, cols.NEW_STARTS]:
		for r in list:
			out += [r[1], r[2]]
	var stars = load("res://scripts/view/ui/parts/hud_stars.gd")
	for r in stars.STAR_COMING:
		out.append(r[1])
	var sp = load("res://scripts/view/ui/species_window.gd")
	for r in sp.SHOWN:
		out += [r[0], r[1]]
	for S in sp.SPECIES:
		out.append(S.DATA.name_th)
		out += [S.CARD.blurb, S.CARD.difficulty]
		for t in S.CARD.traits + S.CARD.care:
			out += t
	var foods = load("res://scripts/sim/food_kinds.gd")
	for t in foods.tools():
		out.append(t[0])
	var sim = load("res://scripts/sim/parts/sim_enemies.gd")
	for kind in sim.ENEMY_KINDS:
		out += [sim.ENEMY_KINDS[kind].NAME, sim.ENEMY_KINDS[kind].ABOUT]
	return out
