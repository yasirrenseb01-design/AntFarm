extends RefCounted
## Save slots on disk (user://saves) and player settings (user://settings.cfg).
## Each slot has the full compressed colony state plus a small JSON summary for the menu, so the
## menu never has to load a whole colony just to show what is in a slot.

const SLOTS := 3
static var base := "user://"      # tests point this at a sandbox folder so they never touch real saves

## Game days that pass per real hour while the game is closed (0 = time stops).
const AWAY_RATES := [
	["หยุดเวลาตอนปิดเกม", 0.0],
	["1 วันในเกม = 24 ชม. จริง (เวลาจริง)", 1.0 / 24.0],
	["1 วันในเกม = 6 ชม. จริง", 1.0 / 6.0],
	["1 วันในเกม = 1 ชม. จริง", 1.0],
	["1 วันในเกม = 15 นาทีจริง", 4.0],
]
const MAX_AWAY_DAYS := 120.0   # longest absence simulated on return


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
	return true


## {"meta": {...}, "sim": {...}} or {} if the slot is empty or unreadable.
static func load_slot(slot: int) -> Dictionary:
	if not exists(slot):
		return {}
	var f := FileAccess.open_compressed(_path(slot), FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {}
	var d = f.get_var()
	f.close()
	return d if d is Dictionary else {}


static func meta(slot: int) -> Dictionary:
	if not FileAccess.file_exists(_meta_path(slot)):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(_meta_path(slot)))
	return d if d is Dictionary else {}


## Keep a copy of the slot as slotN.<tag>.antfarm (+ .json) before it is migrated or given up on.
## An existing copy with the same tag is left alone, so the oldest one survives.
static func backup(slot: int, tag: String) -> void:
	var dst := "%s/slot%d.%s.antfarm" % [_dir(), slot, tag]
	if FileAccess.file_exists(_path(slot)) and not FileAccess.file_exists(dst):
		DirAccess.copy_absolute(_path(slot), dst)
		if FileAccess.file_exists(_meta_path(slot)):
			DirAccess.copy_absolute(_meta_path(slot), "%s/slot%d.%s.json" % [_dir(), slot, tag])


static func delete(slot: int) -> void:
	for p in [_path(slot), _meta_path(slot)]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


# ---------------------------------------------------------------- settings

static func settings() -> Dictionary:
	var cf := ConfigFile.new()
	cf.load(_settings_path())
	return {"slot": cf.get_value("game", "slot", 1), "away": cf.get_value("game", "away", 3),
		"care": cf.get_value("game", "care", true)}


static func save_settings(s: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(base)
	var cf := ConfigFile.new()
	cf.load(_settings_path())
	for k in s:
		cf.set_value("game", k, s[k])
	cf.save(_settings_path())


static func away_rate(index: int) -> float:
	return AWAY_RATES[clampi(index, 0, AWAY_RATES.size() - 1)][1]
