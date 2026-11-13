extends RefCounted
## Dev, each frame of --seq in the outworld: the camera on the enemy being watched (--watch-fight, or --enemy-spin),
## and with --enemy-spin=<radians a second> the staged enemy (--enemy=<kind>) made to turn round and round as it goes -
## the centipede's legs through a turn (v0.13.17, the keeper: "the front legs bend oddly as it turns"). Prints how far
## its body is bent round the turn (creature_pose.gd "bend", -1..1) every 10th frame. Run at --fixed-fps 60.


static func frame(dev) -> void:
	var sim = dev.sim
	var o = dev.outworld
	if dev._opts.has("enemy-spin") and dev._watch_creature == null and not sim.creatures.is_empty():
		dev._watch_creature = sim.creatures[-1]
	var c = dev._watch_creature
	if c == null or dev.mode != "outworld" or not sim.creatures.has(c):
		return
	if dev._opts.has("enemy-spin"):
		c.ang = float(c.ang) + float(dev._opts["enemy-spin"]) / 60.0
		var v: Dictionary = o._creature_vis.get(c.id, {})
		dev._spin_n = int(dev._spin_n) + 1
		if int(dev._spin_n) % 10 == 0:
			print("  spin frame %d: bend %.2f moving %.2f" % [dev._spin_n, float(v.get("bend", 0.0)), float(v.get("mv", 0.0))])
	var cp: Vector2 = c.pos
	o.target_t = Vector3(cp.x, 0, cp.y) * o.U
	o.target = o.target_t
