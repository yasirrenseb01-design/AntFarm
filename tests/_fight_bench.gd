extends SceneTree
## Dev: how fights go, over several seeds - an enemy put down beside the nest of a colony, run until it is gone
## (or one game day). Per fight: who won, how long, ants killed; the enemy's pace while free; and how many of the ants
## fighting it actually hold on to it (the keeper, 2026-10-28: "most just circle round, a few hold its legs").
##   godot --headless --path . --script res://tests/_fight_bench.gd -- <kind> <workers> [seeds, e.g. 1-8] [warm days] [edge]
## "on it" = ants clinging (busy > 0) / ants answering the alarm (DEFEND) for that enemy; "at it" = the same among
## those within 12 mm of it (the ones the keeper sees round it), counted every tick while 3 or more are there.
func _init():
	var Sim = load("res://scripts/sim/simulation.gd")
	var args := OS.get_cmdline_user_args()
	var kind: String = args[0] if args.size() > 0 else "wolf_spider"
	var workers := int(args[1]) if args.size() > 1 else 60
	var sr: PackedStringArray = (args[2] if args.size() > 2 else "1-8").split("-")
	var warm := float(args[3]) if args.size() > 3 else 2.0
	var tot := {"fights": 0, "killed": 0, "fled": 0, "ticks": 0, "dead": 0, "on": 0.0, "def": 0.0, "on_at": 0.0, "at": 0.0,
		"layer2": 0.0, "free_d": 0.0, "free_t": 0, "peak": 0}
	for seed in range(int(sr[0]), int(sr[-1]) + 1):
		var s = Sim.new()
		s.setup(seed, workers, false, "keeper")
		s.enemies = false
		for i in int(warm * s.TPD):
			s.step()
		if args.size() > 4 and args[4] == "edge":
			s.release_enemy(kind)                       # (in from an edge, as the keeper's enemy panel lets one in)
		else:
			s._spawn_creature(kind)
			s.creatures[-1].pos = s.nest_pos + Vector2(120, 40)
			s.creatures[-1].ang = 3.1
		var c: Dictionary = s.creatures[-1]
		var lost0 := _dead(s)
		var killed0 := int(s.stats.get("enemies_killed", 0))
		var t := 0
		var on := 0.0
		var dfd := 0.0
		var on_at := 0.0
		var at := 0.0
		var l2 := 0.0
		var peak := 0
		var last: Vector2 = c.pos
		while t < s.TPD and not s.creatures.is_empty():
			s.step()
			t += 1
			if s.creatures.is_empty():
				break
			c = s.creatures[-1]
			var held := int(c.get("held", 0))
			peak = maxi(peak, held)
			if held == 0 and not c.get("fleeing", false):
				tot.free_d += c.pos.distance_to(last)
				tot.free_t += 1
			last = c.pos
			var nd := 0
			var nc := 0
			var nat := 0
			var ncat := 0
			for a in s.outside:
				if a.dead or a.state != a.DEFEND or (a.foe != c.id and a.foe != 0):
					continue
				nd += 1
				var cl: bool = a.busy > 0 and a.foe == c.id
				nc += 1 if cl else 0
				if a.pos.distance_to(c.pos) < 24.0 + float(s.ENEMY_KINDS[kind].STATS.get("r", 10.0)):
					nat += 1
					ncat += 1 if cl else 0
			if nat >= 3:
				on_at += ncat
				at += nat
			on += nc
			dfd += nd
			l2 += maxf(0.0, held - float(s.ENEMY_KINDS[kind].STATS.hold))
		var won: bool = int(s.stats.get("enemies_killed", 0)) > killed0
		var lost := _dead(s) - lost0
		print("seed %d: %s after %d ticks (%.0f s), ants killed %d, most on it %d, on it %.0f%%, at it %.0f%% on it" % [seed,
			"killed" if won else ("gone" if s.creatures.is_empty() else "still there"), t, t / 60.0, lost, peak,
			100.0 * on / maxf(1.0, dfd), 100.0 * on_at / maxf(1.0, at)])
		tot.fights += 1
		tot.killed += 1 if won else 0
		tot.ticks += t
		tot.dead += lost
		tot.on += on
		tot.def += dfd
		tot.on_at += on_at
		tot.at += at
		tot.layer2 += l2
		tot.peak += peak
	print("== %s, %d workers, %d fights: killed %d, mean %.0f s, ants killed %.1f per fight, most on it %.1f, fighting ants on it %.1f%%, near it on it %.1f%%, free pace %.2f px/tick (%.1f cm/s)" % [kind, workers,
		tot.fights, tot.killed, tot.ticks / 60.0 / tot.fights, float(tot.dead) / tot.fights, float(tot.peak) / tot.fights,
		100.0 * tot.on / maxf(1.0, tot.def), 100.0 * tot.on_at / maxf(1.0, tot.at),
		tot.free_d / maxf(1.0, tot.free_t), tot.free_d / maxf(1.0, tot.free_t) * 60.0 * 0.05])
	quit()


func _dead(s) -> int:
	return int(s.stats.dead_by.get("enemy", 0))
