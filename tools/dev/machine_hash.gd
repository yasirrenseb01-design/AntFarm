extends SceneTree
## Prints this machine's hash for scripts/game/dev_machine.gd HASHES (the developer's machines: no points cap, the
## developer's tab). The id itself is not printed.
##   tools/dev/gd.sh --headless --path . --script res://tools/dev/machine_hash.gd
func _init() -> void:
	var D = load("res://scripts/game/dev_machine.gd")
	var id := OS.get_unique_id()
	print("this machine: %s" % (D.hash_of(id) if id != "" else "(no id)"))
	print("a developer's: %s" % D.is_dev())
	quit()
