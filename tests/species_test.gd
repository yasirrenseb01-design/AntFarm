extends SceneTree
## Every species (scripts/sim/species/registry.gd) has every key the first one has, of the same kind, its look's too;
## ids are unique; an id not known gives the first species.
##   godot --headless --path . --script res://tests/species_test.gd     -> "SPECIES TEST PASSED"

const Species := preload("res://scripts/sim/species/registry.gd")
var ok := true


func _init() -> void:
	var first: Dictionary = Species.ALL[0].DATA
	var ids := {}
	for s in Species.ALL:
		var d: Dictionary = s.DATA
		_check(d.id + ": id unique", not ids.has(d.id))
		ids[d.id] = true
		for table in [[first, d, ""], [first.look, d.get("look", {}), "look."]]:
			for k in table[0]:
				var has: bool = table[1].has(k)
				_check("%s: %s%s" % [d.id, table[2], k], has and typeof(table[1][k]) == typeof(table[0][k]))
		_check(d.id + ": card", s.CARD.has("blurb") and s.CARD.has("traits"))
	_check("unknown id -> first", Species.data("no_such_ant").id == first.id)
	print("SPECIES TEST PASSED" if ok else "SPECIES TEST FAILED")
	quit()


func _check(what: String, good: bool) -> void:
	if not good:
		print("  FAIL ", what)
	ok = ok and good
