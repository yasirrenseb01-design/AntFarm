extends RefCounted
## Save slots on disk (user://saves) and player settings (user://settings.cfg).
## Each slot has the full compressed colony state plus a small JSON summary for the menu, so the
## menu never has to load a whole colony just to show what is in a slot.

const NestCard := preload("res://scripts/game/nest_card.gd")
const SafeFile := preload("res://scripts/game/safe_file.gd")
const SaveLimits := preload("res://scripts/sim/save_limits.gd")
const SLOTS := 32                 # the highest slot number (home_store.gd says which are shown: the tanks and the wild mode's)
static var base := "user://"      # tests point this at a sandbox folder so they never touch real saves
static var _kept_off := {}        # slot -> true: unreadable and no copy of it could be made (backup): never written over

## Game days that pass per real hour while the game is closed (0 = time stops); the words are keys of lang/strings.csv.
const AWAY_RATES := [
	["away_stop", 0.0],
	["away_real", 1.0 / 24.0],
	["away_6h", 1.0 / 6.0],
	["away_1h", 1.0],
	["away_15m", 4.0],
]
const MAX_AWAY_DAYS := 120.0   # longest absence simulated on return
# (PART EA-R R8) anything bigger than a save can be is not one of ours, and is not read (a file can claim any length,
# and the reader would set that much memory aside first). How big: sim/save_limits.gd, the same numbers the loading
# checks use (v0.12.32: 32 / 64 MB before, while the checks took soil that saves to ~210 MB)
const MAX_FILE := SaveLimits.MAX_FILE
const MAX_RAW := SaveLimits.MAX_RAW
const MAX_TEXT := 1024 * 1024    # settings.cfg, slotN.json
# what each setting is, and the value it has when the file has none or something else there
const SETTINGS := {"slot": 1, "away": 3, "care": true, "lang": "", "view": "outworld", "desk_told": false, "show_fps": false,
	"side_open": true, "bar_open": true, "music": 0.6, "guide_done": false, "quality": "medium", "fps_cap": 1, "home_hand": true, "home_cross": true, "home_lamp": true,
	"look_speed": 1.0, "look_invert": false, "home_tips_done": false}
const META := {"day": 0, "workers": 0, "saved_unix": 0, "glass": false, "queen": true, "scenario": "keeper", "water": 1.0,
	"water_use": 0.0, "refills": "", "doy": 0.0}
const MAX_REFILLS := 20          # the water tank filled from the Home: the times kept for the colony's next opening


static func _dir() -> String:
	return base + "saves"


static func _settings_path() -> String:
	return base + "settings.cfg"


static func _path(slot: int) -> String:
	return "%s/slot%d.antfarm" % [_dir(), slot]


static func _meta_path(slot: int) -> String:
	return "%s/slot%d.json" % [_dir(), slot]


## A colony in the slot: its save, or what is left of one cut off mid-write (.tmp, .bak: game/safe_file.gd).
static func exists(slot: int) -> bool:
	return SafeFile.any(_path(slot))


## Write the colony. The data goes to a temporary file first, is read back and checked, and only then takes the old
## save's place - the old one kept as slotN.antfarm.bak (game/safe_file.gd) - so a crash, a power cut or a full disk
## mid-save never costs the previous save.
static func save(slot: int, sim, extra: Dictionary = {}) -> bool:
	if _kept_off.has(slot):
		return false
	var meta: Dictionary = sim.summary()
	meta.merge(extra, true)
	meta["saved_unix"] = Time.get_unix_time_from_system()
	meta["version"] = ProjectSettings.get_setting("application/config/version", "dev")
	# where the nest's block lies along the box, from its left inside (metres: the Home draws it there on the glass)
	meta["nest_x0"] = sim.nest_pos.x * 0.0005 - (sim.nest.entrance.x - sim.nest.x_lo) * 0.0015
	meta["nest_w"] = sim.nest.wx() * 0.0015         # (and how wide: the box held, grown sideways - PART 0.12)
	if not write_slot(slot, {"meta": meta, "sim": sim.to_dict()}):
		return false
	SafeFile.write_text(_meta_path(slot), JSON.stringify(meta))
	NestCard.write(_dir(), slot, sim.nest)              # (the nest, for the Home's tank glass)
	return true


## The save written (save() above): to .tmp, read back whole, then in the save's place. False if it could not be: the
## save there is left as it was.
static func write_slot(slot: int, data: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(_dir())
	var path := _path(slot)
	var tmp := path + ".tmp"
	var f := FileAccess.open_compressed(tmp, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return false
	f.store_var(data)
	f.close()
	# (read back: the length it says and that many bytes there - not decoded again, which would cost the save's time over)
	if _bytes(tmp).is_empty():
		DirAccess.remove_absolute(tmp)
		return false
	return SafeFile.replace(tmp, path)


## {"meta": {...}, "sim": {...}} or {} if the slot is empty or unreadable: the save, else what a save cut off mid-write
## left (its .tmp, then its .bak - game/safe_file.gd). Reads only.
static func load_slot(slot: int) -> Dictionary:
	var path := _path(slot)
	for p in SafeFile.candidates(path):
		var d := read_file(p)
		if not d.is_empty():
			if p != path:
				push_warning("slot %d: read from %s" % [slot, p.get_file()])
			return d
		if p == path:
			SafeFile.mark_bad(path)          # (the next save keeps it as .bad, not over the good .bak)
	return {}


## One save file read: {"meta", "sim"} or {}.
static func read_file(path: String) -> Dictionary:
	var bytes := _bytes(path)
	if bytes.is_empty():
		return {}
	var d = bytes_to_var(bytes)
	if not d is Dictionary or not d.get("sim") is Dictionary or not d.get("meta") is Dictionary:
		return {}
	return d


## The unpacked bytes of a save file, or none if it is not whole (or too big to be one of ours).
static func _bytes(path: String) -> PackedByteArray:
	if not FileAccess.file_exists(path) or _size(path) > MAX_FILE or not _whole(path):
		return PackedByteArray()
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return PackedByteArray()
	# (as get_var() reads it, with the length checked first; objects are never decoded - bytes_to_var, not _with_objects)
	var n := f.get_32()
	if n == 0 or n > MAX_RAW:
		return PackedByteArray()
	var bytes := f.get_buffer(n)
	f.close()
	return bytes if bytes.size() == n else PackedByteArray()


## The packed file is as long as its header says (Godot's FileAccessCompressed: "GCPF", mode, block size, length
## unpacked, then one packed size per block, the blocks and "GCPF" again). A file cut short is otherwise read on past its end as
## zeros, the length it claims "read" whole (v0.12.32, tests/save_files_test.gd).
static func _whole(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() < 16 or f.get_buffer(4).get_string_from_ascii() != "GCPF":
		return false
	f.get_32()                                   # (the packing)
	var block := f.get_32()
	var total := f.get_32()
	if block == 0:
		return false
	var blocks := total / block + 1
	if blocks * 4 > f.get_length() - 16:
		return false
	var want := 16 + blocks * 4
	for i in blocks:
		want += f.get_32()
	if f.get_length() != want + 4:
		return false
	f.seek(want)
	return f.get_buffer(4).get_string_from_ascii() == "GCPF"       # (and "GCPF" again at its very end)


static func _size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_length() if f != null else 0


static func meta(slot: int) -> Dictionary:
	var d = SafeFile.read_text(_meta_path(slot), MAX_TEXT, _json_dict)
	if d == null:
		return {}
	# the menu puts these in words with %d and %s: a value of the wrong kind is left out (JSON has no objects)
	var out := {}
	for k in d:
		var v = d[k]
		var want = META.get(k, v)
		if (v is float and (want is float or want is int)) or (v is String and want is String) or (v is bool and want is bool):
			out[k] = v
	return out


static func _json_dict(text: String) -> Variant:
	var d = JSON.parse_string(text)
	return d if d is Dictionary else null


## The keeper filled this colony's water tank from the Home (the keeper, 2026-11-03: "fill the tanks from the Home, many at
## once"): the time goes in its slotN.json, "refills" (unix seconds, comma-separated); the colony fills it at that moment
## of the time away worked out when it is opened next (main_base.gd), and the next save leaves it out again.
static func add_refill(slot: int, unix: float) -> void:
	var d = SafeFile.read_text(_meta_path(slot), MAX_TEXT, _json_dict)
	if d == null:
		return
	var times := refills(d)
	times.append(unix)
	d["refills"] = ",".join(times.slice(-MAX_REFILLS).map(func(t): return "%.0f" % t))
	SafeFile.write_text(_meta_path(slot), JSON.stringify(d))


## The refill times in a slot's meta, oldest first (only numbers are taken from it).
static func refills(m: Dictionary) -> Array:
	var out: Array = []
	var v = m.get("refills", "")
	if v is String:
		for part in v.split(",", false):
			if part.is_valid_float() and out.size() < MAX_REFILLS:
				out.append(float(part))
	out.sort()
	return out


## How full a colony's water tank is now that is not open (0..1), from its meta: what it held when saved or last
## filled from the Home, less what it used since at the away rate (game days per real hour); with the helper on
## (settings "care") an empty tank is filled again, as the time away will do.
static func water_now(m: Dictionary, days_per_hour: float, care: bool) -> float:
	var use := maxf(0.0, float(m.get("water_use", 0.0)))
	var level := clampf(float(m.get("water", 1.0)), 0.0, 1.0)
	var since := float(m.get("saved_unix", 0.0))
	var times := refills(m)
	if not times.is_empty():
		level = 1.0
		since = times.back()
	var days := minf(MAX_AWAY_DAYS, maxf(0.0, Time.get_unix_time_from_system() - since) / 3600.0 * days_per_hour)
	level -= days * use
	if level < 0.0 and care and use > 0.0:
		level = 1.0 - fmod(-level, 1.0)
	return clampf(level, 0.0, 1.0)


## Keep a copy of the slot as slotN.<tag>.antfarm (+ .json, and the .tmp/.bak a save cut off left) before it is
## migrated or given up on. An existing copy with the same tag is left alone, so the oldest one survives. False if a
## copy could not be made: save() then never writes over that slot in this run, until delete() (v0.12.32).
static func backup(slot: int, tag: String) -> bool:
	var ok := true
	for side in ["", ".tmp", ".bak"]:
		for pair in [[_path(slot), "%s/slot%d.%s.antfarm" % [_dir(), slot, tag]], [_meta_path(slot), "%s/slot%d.%s.json" % [_dir(), slot, tag]]]:
			var src: String = pair[0] + side
			var dst: String = pair[1] + side
			if FileAccess.file_exists(src) and not FileAccess.file_exists(dst):
				ok = DirAccess.copy_absolute(src, dst) == OK and ok
	if not ok:
		_kept_off[slot] = true
	return ok


## (a new colony started there by the keeper: Store writes there again)
static func delete(slot: int) -> void:
	_kept_off.erase(slot)
	SafeFile.remove(_path(slot))
	SafeFile.remove(_meta_path(slot))
	for p in [NestCard.path(_dir(), slot), "%s/slot%d_outworld.png" % [_dir(), slot]]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


# ---------------------------------------------------------------- settings

static func settings() -> Dictionary:
	var cf := _settings_file()
	var s := {"slot": 1, "away": 3, "care": true, "lang": ""}      # (lang "": the machine's)
	# everything saved comes back - music, the frame rate, the side panel, the view, the guide and wallpaper notes (only
	# these four did until v0.11.13: the rest were saved and forgotten at the next start)
	if cf.has_section("game"):
		for k in cf.get_section_keys("game"):
			var v = cf.get_value("game", k)
			if SETTINGS.has(k):
				var want = SETTINGS[k]
				if want is bool:
					s[k] = v if v is bool else want
				elif want is int:
					s[k] = int(v) if v is int or v is float else want
					if k == "slot":
						s[k] = clampi(s[k], 1, SLOTS)
					elif k == "away":
						s[k] = clampi(s[k], 0, AWAY_RATES.size() - 1)
				elif want is float:
					s[k] = clampf(float(v), 0.0, 1.0) if v is int or v is float else want      # (music: a volume)
				else:
					s[k] = String(v).left(64) if v is String else want
			elif v is bool or v is int or v is float or v is String:
				s[k] = v
	return s


## The settings file, read as text first: a ConfigFile turns Object(...) and Resource("...") into the real thing - a
## script named there would be loaded and could run (PART EA-R R8). The game only ever writes plain values, so a file
## with any of those is not read at all (the settings start over).
static func _settings_file() -> ConfigFile:
	var cf := ConfigFile.new()
	var path := _settings_path()
	if not FileAccess.file_exists(path) or _size(path) > MAX_TEXT:
		return cf
	var text := FileAccess.get_file_as_string(path)
	var objects := RegEx.create_from_string("(Object|Resource|ExtResource|SubResource|Callable|Signal|RID)\\s*\\(")
	# (and a value of lists in lists some thousand deep made the engine call itself until it ran out of stack and crashed:
	# the game writes no lists here, so a file with more than a few brackets of any kind - counted in text and notes too,
	# which cannot hide one - is not read either)
	var brackets := text.count("[") + text.count("{") + text.count("(")
	if objects.search(text) != null or brackets > 32:
		push_warning("settings.cfg holds more than plain values: not read")
		return cf
	if cf.parse(text) != OK:
		return ConfigFile.new()
	return cf


static func save_settings(s: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(base)
	var cf := _settings_file()
	# the album's plates: joined with those in the file, never written over - a plate won stays won whatever dict saves
	# last (v0.13.19, the keeper: "New in the album: Plate IIb" again after an update, though it was won long before)
	if s.has("album"):
		s["album"] = album_union(String(cf.get_value("game", "album", "")), String(s["album"]))
	for k in s:
		cf.set_value("game", k, s[k])
	cf.save(_settings_path())


## The album's plates won as written in the settings ("species:id,id;species:id"), of `a` and `b` together - each
## species once, `a`'s plates first.
static func album_union(a: String, b: String) -> String:
	var all := {}
	for raw in [a, b]:
		for part in String(raw).split(";", false):
			var kv := part.split(":", true, 1)
			if kv.size() != 2 or kv[0] == "":
				continue
			var ids: Array = all.get(kv[0], [])
			for id in kv[1].split(",", false):
				if not ids.has(id):
					ids.append(id)
			all[kv[0]] = ids
	var parts := PackedStringArray()
	for k in all:
		parts.append("%s:%s" % [k, ",".join(PackedStringArray(all[k]))])
	return ";".join(parts)


## The album's plates as the settings file has them now ("" if none): hud.gd looks here before telling of a new one.
static func album_on_disk() -> String:
	var v = _settings_file().get_value("game", "album", "")
	return v if v is String else ""


static func away_rate(index: int) -> float:
	return AWAY_RATES[clampi(index, 0, AWAY_RATES.size() - 1)][1]
