extends "res://scripts/sim/parts/sim_foragers.gd"
## Simulation, layer 3 of 5: natural enemies in the outworld. Each kind lives in its own file under
## scripts/sim/enemies/ and is registered here; sim.creatures holds the ones present (saved as is).

const ENEMY_KINDS := {
	"wolf_spider": preload("res://scripts/sim/enemies/wolf_spider.gd"),
}


func _spawn_creature(kind: String) -> void:
	var c: Dictionary = ENEMY_KINDS[kind].spawn(self)
	c["kind"] = kind
	creatures.append(c)


func _step_creatures() -> void:
	var gone := []
	for c in creatures:
		if not ENEMY_KINDS[c.kind].step(self, c):
			gone.append(c)
	for c in gone:
		creatures.erase(c)


## The keeper takes every enemy out of the box.
func remove_enemies() -> void:
	if creatures.is_empty():
		return
	var kind: String = creatures[0].kind
	creatures.clear()
	_log(ENEMY_KINDS[kind].CHASED)
