extends SceneTree
## How the keeper's files are written and read back when a write is cut off (v0.12.32, game/safe_file.gd), in a folder
## of its own (user://savefiles/, made and emptied here):
##   a save: only .tmp left (power cut between the two renames), only .bak left, the save cut short (its .bak read, and
##   kept at the next save: the cut one goes to .bad), a broken .tmp alone; a text write that cannot be put in place;
##   slotN.json, harmony.json, home.json the same way (home.json unreadable: its .bak used, not the tanks lost);
##   Store.backup of a slot that only has a .bak, one that fails (the slot then not saved over); Store.delete takes the
##   .bak/.tmp/.bad too;
##   with "big": a nest of the most soil a save may hold (SaveLimits.MAX_VOXELS) saved and read back (slow: tools/check.ps1
##   runs it outside -Quick).
##   godot --headless --path . --script res://tests/save_files_test.gd [-- big]     -> "SAVE FILES TEST PASSED"

const Store := preload("res://scripts/game/save_store.gd")
const SafeFile := preload("res://scripts/game/safe_file.gd")
const Harmony := preload("res://scripts/game/harmony.gd")
const HomeStore := preload("res://scripts/game/home_store.gd")
const Sim := preload("res://scripts/sim/simulation.gd")
const SaveCheck := preload("res://scripts/sim/save_check.gd")
const SaveLimits := preload("res://scripts/sim/save_limits.gd")
const DIR := "user://savefiles/"
var ok := true


func _init() -> void:
	Store.base = DIR
	Harmony.base = DIR
	_clear()
	var sim = Sim.new()
	sim.setup(3, 14, false, "keeper")
	for i in sim.TPD / 4:
		sim.step()
	_saves(sim)
	_texts()
	if OS.get_cmdline_user_args().has("big"):
		_big()
	_clear()
	print("SAVE FILES TEST PASSED" if ok else "SAVE FILES TEST FAILED")
	quit(0 if ok else 1)


func _saves(sim) -> void:
	var p := DIR + "saves/slot1.antfarm"
	_check("first save", Store.save(1, sim))
	var day1: int = sim.tick
	_check("first save: no .bak, no .tmp", not FileAccess.file_exists(p + ".bak") and not FileAccess.file_exists(p + ".tmp"))
	for i in 50:
		sim.step()
	_check("second save", Store.save(1, sim))
	_check("second save: the first kept as .bak", FileAccess.file_exists(p + ".bak"))
	_is("reads the newest", _tick(Store.load_slot(1)), sim.tick)
	# a power cut between the two renames: only .bak (the one before) and .tmp (the new one, written whole)
	DirAccess.rename_absolute(p, p + ".tmp")
	_check("only .tmp and .bak: the slot is not empty", Store.exists(1))
	_is("only .tmp and .bak: the .tmp read (the newer)", _tick(Store.load_slot(1)), sim.tick)
	DirAccess.remove_absolute(p + ".tmp")
	_check("only .bak: the slot is not empty", Store.exists(1))
	_is("only .bak: read", _tick(Store.load_slot(1)), day1)
	_check("only .bak: saves again", Store.save(1, sim))
	_is("only .bak: then the new one read", _tick(Store.load_slot(1)), sim.tick)
	# the save cut short (a full disk under the old way): the .bak read; the next save keeps that .bak and puts the
	# cut one aside as .bad
	var good_bak := _tick(_read_raw(p + ".bak"))
	_cut(p)
	_is("cut short: its .bak read", _tick(Store.load_slot(1)), good_bak)
	_check("cut short: saves again", Store.save(1, sim))
	_is("cut short: the good .bak kept", _tick(_read_raw(p + ".bak")), good_bak)
	_check("cut short: the cut one kept as .bad", FileAccess.file_exists(p + ".bad"))
	_is("cut short: then the new one read", _tick(Store.load_slot(1)), sim.tick)
	# a .tmp that is not whole and nothing else: unreadable, not read as a colony
	Store.delete(1)
	_check("deleted: .bak, .tmp, .bad gone too", not Store.exists(1) and not FileAccess.file_exists(p + ".bad"))
	var f := FileAccess.open(p + ".tmp", FileAccess.WRITE)
	f.store_string("not a save")
	f.close()
	_check("a broken .tmp only: nothing read", Store.load_slot(1).is_empty())
	Store.delete(1)
	# a backup of a slot that has only its .bak (main.gd: before a new colony is started over one it cannot read)
	Store.save(1, sim)
	Store.save(1, sim)
	DirAccess.remove_absolute(p)
	_check("backup of only a .bak: done", Store.backup(1, "unreadable-1"))
	_check("backup of only a .bak: its copy there", FileAccess.file_exists(DIR + "saves/slot1.unreadable-1.antfarm.bak"))
	# a copy that cannot be made (a folder in its way, as a full disk would): false, and the slot is not saved over
	DirAccess.make_dir_recursive_absolute(DIR + "saves/slot1.unreadable-2.antfarm.bak")
	_check("backup that fails: false", not Store.backup(1, "unreadable-2"))
	_check("backup that fails: not saved over", not Store.save(1, sim) and FileAccess.file_exists(p + ".bak") and not FileAccess.file_exists(p))
	DirAccess.remove_absolute(DIR + "saves/slot1.unreadable-2.antfarm.bak")
	Store.delete(1)
	_check("deleted (a new colony there): saved again", Store.save(1, sim))
	Store.delete(1)
	# the menu's line (slotN.json): cut short, its .bak read
	Store.save(2, sim)
	Store.save(2, sim)
	var mp := DIR + "saves/slot2.json"
	_cut(mp)
	_is("slotN.json cut short: its .bak read", int(Store.meta(2).get("workers", -1)), sim.workers.size())
	Store.delete(2)


func _texts() -> void:
	# harmony.json: points saved twice, the file then cut short - the points come from .bak, and are not written over it
	var h := Harmony.new()
	h.points = 12.0
	h.save_purse()
	h.points = 13.0
	h.save_purse()
	_cut(DIR + "harmony.json")
	var h2 := Harmony.new()
	h2.load_purse()
	_is("harmony.json cut short: the points from its .bak", h2.points, 12.0)
	h2.save_purse()
	_is("harmony.json cut short: the .bak kept", _json(DIR + "harmony.json.bak").get("points"), 12.0)
	# home.json: the tanks bought kept when the file is cut short
	var home := HomeStore.new()
	home.load_layout()
	home.add_tank()
	home.add_tank()
	var tanks: Array = home.tanks.duplicate()
	home.save_layout()
	_cut(DIR + "home.json")
	var again := HomeStore.new()
	again.load_layout()
	_is("home.json cut short: the tanks from its .bak", again.tanks, tanks)
	# a write that cannot be put in place leaves the file as it was
	_check("write_text: a folder in the way - false", not SafeFile.write_text(DIR + "nofile/", "x"))


## A nest of the most soil a save may hold, saved and read back whole (the save's two limits from one set of numbers).
func _big() -> void:
	var sim = Sim.new()
	sim.setup(3, 0, false, "keeper", true)
	var d: Dictionary = sim.to_dict()
	var n: Dictionary = d.nest
	var side := int(pow(SaveLimits.MAX_VOXELS, 1.0 / 3.0))
	n.nx = side
	n.ny = SaveLimits.MAX_VOXELS / (side * side)
	n.nz = side
	n.x_lo = 0
	n.z_lo = 0
	n.y_lo = 0
	n.y_floor = 0
	var cells: int = n.nx * n.ny * n.nz
	var r := RandomNumberGenerator.new()
	r.seed = 1
	var rho := PackedByteArray()
	rho.resize(cells)
	var ints := PackedInt32Array()
	ints.resize(cells)
	for i in range(0, cells, 7):           # (not all one value: else it packs to next to nothing)
		rho[i] = r.randi() & 255
		ints[i] = r.randi()
	n.rho = rho
	n.dug_at = ints
	n.dist = ints.duplicate()
	n.work_dist = ints.duplicate()
	_check("big nest: passes the loading checks", SaveCheck.problem(d) == "")
	var t0 := Time.get_ticks_msec()
	var wrote: bool = Store.write_slot(3, {"meta": {}, "sim": d})
	var t1 := Time.get_ticks_msec()
	var back := Store.load_slot(3)
	var t2 := Time.get_ticks_msec()
	var size := FileAccess.open(DIR + "saves/slot3.antfarm", FileAccess.READ).get_length() if wrote else 0
	print("  big nest %d voxels: written %s in %d ms (%.1f MB), read in %d ms" % [cells, wrote, t1 - t0, size / 1048576.0, t2 - t1])
	_check("big nest: written", wrote)
	_check("big nest: read back", not back.is_empty() and back.sim.nest.rho.size() == cells and back.sim.nest.work_dist.size() == cells)
	_check("big nest: what is read passes the loading checks", not back.is_empty() and SaveCheck.problem(back.sim) == "")
	Store.delete(3)


func _cut(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	var b := f.get_buffer(f.get_length())
	f.close()
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(b.slice(0, b.size() / 2))
	f.close()


func _read_raw(path: String) -> Dictionary:
	return Store.read_file(path)


static func _tick(d: Dictionary) -> int:
	return int(d.sim.tick) if d.get("sim") is Dictionary else -1


static func _json(path: String) -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


func _clear() -> void:
	for sub in ["saves/", ""]:
		var dir := DirAccess.open(DIR + sub)
		if dir != null:
			for fn in dir.get_files():
				dir.remove(fn)
	DirAccess.remove_absolute(DIR + "saves")


func _is(what: String, got, want) -> void:
	_check("%s (%s, want %s)" % [what, str(got), str(want)], got == want)


func _check(what: String, good: bool) -> void:
	if not good:
		print("  FAIL ", what)
		ok = false
