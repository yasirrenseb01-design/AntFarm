extends RefCounted
## Save slots on disk (user://saves) and player settings (user://settings.cfg).
## Each slot has the full compressed colony state plus a small JSON summary for the menu, so the
## menu never has to load a whole colony just to show what is in a slot.

const NestCard := preload("res://scripts/game/nest_card.gd")
const SLOTS := 32                 # the highest slot number (home_store.gd says which are shown: the tanks and the wild mode's)
static var base := "user://"      # tests point this at a sandbox folder so they never touch real saves

## Game days that pass per real hour while the game is closed (0 = time stops); the words are keys of lang/strings.csv.
const AWAY_RATES := [
	["away_stop", 0.0],
	["away_real", 1.0 / 24.0],
	["away_6h", 1.0 / 6.0],
	["away_1h", 1.0],
	["away_15m", 4.0],
]
const MAX_AWAY_DAYS := 120.0   # longest absence simulated on return
# (PART EA-R R8) a save is ~0.1 MB on disk and ~5 MB unpacked: anything far bigger is not one of ours, and is not read
# (a file can claim any length, and the reader would set that much memory aside first)
const MAX_FILE := 32 * 1024 * 1024
const MAX_RAW := 64 * 1024 * 1024
const MAX_TEXT := 1024 * 1024    # settings.cfg, slotN.json
# what each setting is, and the value it has when the file has none or something else there
const SETTINGS := {"slot": 1, "away": 3, "care": true, "lang": "", "view": "outworld", "desk_told": false, "show_fps": false,
	"side_open": true, "music": 0.6, "guide_done": false, "quality": "medium", "fps_cap": 1, "home_hand": true, "home_cross": true, "home_lamp": true}
const META := {"day": 0, "workers": 0, "saved_unix": 0, "glass": false, "queen": true, "scenario": "keeper"}


static func _dir() -> String:
	return base + "saves"


static func _settings_path() -> String:
	return base + "settings.cfg"


static func _path(slot: int) -> String:
	return "%s/slot%d.antfarm" % [_dir(), slot]


static func _meta_path(slot: int) -> String:
	return "%s/slot%d.json" % [_dir(), slot]


static func exists(slot: int) -> bool:
	return FileAccess.file_exists(_path(slot))


## Write the colony. The data goes to a temporary file first and replaces the old save only once
## it is complete, so a crash or power cut mid-save never destroys the previous save.
static func save(slot: int, sim, extra: Dictionary = {}) -> bool:
	DirAccess.make_dir_recursive_absolute(_dir())
	var tmp := _path(slot) + ".tmp"
	var f := FileAccess.open_compressed(tmp, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return false
	var meta: Dictionary = sim.summary()
	meta.merge(extra, true)
	meta["saved_unix"] = Time.get_unix_time_from_system()
	meta["version"] = ProjectSettings.get_setting("application/config/version", "dev")
	# where the nest's block lies along the box, from its left inside (metres: the Home draws it there on the glass)
	meta["nest_x0"] = sim.nest_pos.x * 0.0005 - sim.nest.entrance.x * 0.0015
	f.store_var({"meta": meta, "sim": sim.to_dict()})
	f.close()
	if FileAccess.file_exists(_path(slot)):
		DirAccess.remove_absolute(_path(slot))
	if DirAccess.rename_absolute(tmp, _path(slot)) != OK:
		return false
	var m := FileAccess.open(_meta_path(slot), FileAccess.WRITE)
	if m:
		m.store_string(JSON.stringify(meta))
		m.close()
	NestCard.write(_dir(), slot, sim.nest)              # (the nest, for the Home's tank glass)
	return true


## {"meta": {...}, "sim": {...}} or {} if the slot is empty or unreadable.
static func load_slot(slot: int) -> Dictionary:
	if not exists(slot) or _size(_path(slot)) > MAX_FILE:
		return {}
	var f := FileAccess.open_compressed(_path(slot), FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {}
	# (as get_var() reads it, with the length checked first; objects are never decoded - bytes_to_var, not _with_objects)
	var n := f.get_32()
	if n == 0 or n > MAX_RAW:
		return {}
	var bytes := f.get_buffer(n)
	f.close()
	if bytes.size() != n:
		return {}
	var d = bytes_to_var(bytes)
	if not d is Dictionary or not d.get("sim") is Dictionary or not d.get("meta") is Dictionary:
		return {}
	return d


static func _size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_length() if f != null else 0


static func meta(slot: int) -> Dictionary:
	if not FileAccess.file_exists(_meta_path(slot)) or _size(_meta_path(slot)) > MAX_TEXT:
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(_meta_path(slot)))
	if not d is Dictionary:
		return {}
	# the menu puts these in words with %d and %s: a value of the wrong kind is left out (JSON has no objects)
	var out := {}
	for k in d:
		var v = d[k]
		var want = META.get(k, v)
		if (v is float and (want is float or want is int)) or (v is String and want is String) or (v is bool and want is bool):
			out[k] = v
	return out


## Keep a copy of the slot as slotN.<tag>.antfarm (+ .json) before it is migrated or given up on.
## An existing copy with the same tag is left alone, so the oldest one survives.
static func backup(slot: int, tag: String) -> void:
	var dst := "%s/slot%d.%s.antfarm" % [_dir(), slot, tag]
	if FileAccess.file_exists(_path(slot)) and not FileAccess.file_exists(dst):
		DirAccess.copy_absolute(_path(slot), dst)
		if FileAccess.file_exists(_meta_path(slot)):
			DirAccess.copy_absolute(_meta_path(slot), "%s/slot%d.%s.json" % [_dir(), slot, tag])


static func delete(slot: int) -> void:
	for p in [_path(slot), _meta_path(slot), NestCard.path(_dir(), slot), "%s/slot%d_outworld.png" % [_dir(), slot]]:
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
	for k in s:
		cf.set_value("game", k, s[k])
	cf.save(_settings_path())


static func away_rate(index: int) -> float:
	return AWAY_RATES[clampi(index, 0, AWAY_RATES.size() - 1)][1]
