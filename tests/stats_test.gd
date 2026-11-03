extends SceneTree
## The Statistics tab's saved sets (ui/stats_chart.gd, user://charts.json): saved and read back; from a file changed by
## hand only names and known keys are taken; and every key it plots is in a day of the colony's record.
##   godot --headless --path . --script res://tests/stats_test.gd     -> "STATS TEST PASSED"

const Chart := preload("res://scripts/view/ui/stats_chart.gd")
const Store := preload("res://scripts/game/save_store.gd")
const Sim := preload("res://scripts/sim/simulation.gd")
const DIR := "user://statstest/"

var ok := true


func _case(name: String, fine: bool, got = "") -> void:
	print("  %-56s %s %s" % [name, "ok" if fine else "FAILED", str(got)])
	ok = ok and fine


func _init() -> void:
	Store.base = DIR
	DirAccess.make_dir_recursive_absolute(DIR)
	var c := Chart.new()
	c.sets = [{"name": "warm", "x": "day", "ys": ["nest_t", "air"], "own": true}]
	c._write_sets()
	var c2 := Chart.new()
	c2._load_sets()
	_case("a set saved and read back", c2.sets.size() == 1 and c2.sets[0].ys == ["nest_t", "air"] and c2.sets[0].own == true, c2.sets)
	var f := FileAccess.open(Chart.path(), FileAccess.WRITE)
	f.store_string(JSON.stringify({"v": 1, "sets": [{"name": "x", "x": "nope", "ys": ["workers"]}, {"name": "", "x": "day", "ys": ["workers"]},
		{"name": "ok", "x": "workers", "ys": ["sugar", "bogus", "day", 5, "sugar"]}, "junk", {"name": 3}]}))
	f.close()
	c2._load_sets()
	_case("from a changed file: only the good set, known keys", c2.sets.size() == 1 and c2.sets[0].ys == ["sugar"], c2.sets)
	f = FileAccess.open(Chart.path(), FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	c2._load_sets()
	_case("not JSON: no sets, no error", c2.sets.is_empty())
	var s := Sim.new()
	s.setup(2, 14, false, "keeper")
	var snap: Dictionary = s._snapshot()
	var missing := []
	for k in Chart.KEYS:
		if not snap.has(k[0]):
			missing.append(k[0])
	_case("every key plotted is in a day's record", missing.is_empty(), missing)
	DirAccess.remove_absolute(Chart.path())
	c.free()
	c2.free()
	print("STATS TEST PASSED" if ok else "STATS TEST FAILED")
	quit()
