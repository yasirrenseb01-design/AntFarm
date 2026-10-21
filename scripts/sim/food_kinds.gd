extends RefCounted
## Every kind of food the outworld can hold, in one table. The simulation and all the views read it,
## so a new food is: one entry here + (optionally) a 3D builder in view/outworld/parts/outworld_props.gd
## (it falls back to something plain without one).
##   type       what a forager carries home (Ant.SUGAR / Ant.PROTEIN)
##   amt, cap   loads available now / at most;  regen  loads per day it renews (aphids)
##   r          radius in px within which foragers handle it
##   handling   [min ticks, max ticks, activity] spent collecting one load (activity ids: docs/ARCHITECTURE.md)
##   found      journal line the first time the colony finds it
##   dries      fraction left after a day (honey crystallising);  rots_after  days until a carcass rots
##   tool       label of the keeper's tool that places it (only placeable kinds have one)
##   feed_pose  how the 3D view stands an ant on it: "climb" (stem), "rim" (drop), "carcass" (body outline)
##   carcass    [half length, half width] of the body outline in units, for "carcass"
##   buried     ants pile soil on it;  big  a large carcass (more soil, deflates as it is eaten)
##   drag       n: nestmates haul it home whole once n hold it (sim_foragers _step_drags) - unused for L. niger

const Ant := preload("res://scripts/sim/ant.gd")
const T := preload("res://scripts/sim/text_th.gd")

const KINDS := {
	"aphids": {"type": Ant.SUGAR, "amt": 10.0, "cap": 16.0, "regen": 9.0, "r": 16.0, "handling": [60, 140, 9],
		"found": T.found_aphids, "feed_pose": "climb"},
	# (drinking: 23-51 s at a drop - L. niger at 0.6 M sucrose, 51 +- 12 s at the first source, 23 +- 11 s at a second one
	# on the way home: Mailleux et al. 2009, C R Biol 332; until v0.11.18 it was 40-80 ticks, about a second)
	"honey": {"type": Ant.SUGAR, "amt": 25.0, "cap": 25.0, "regen": 0.0, "r": 8.0, "handling": [1380, 3060, 10],
		"found": T.found_honey, "dries": 0.78, "tool": "tool_honey", "feed_pose": "rim"},
	"cricket": {"type": Ant.PROTEIN, "amt": 30.0, "cap": 30.0, "regen": 0.0, "r": 12.0, "handling": [90, 200, 2],
		"found": T.found_cricket, "rots_after": 6.0, "tool": "tool_cricket", "feed_pose": "carcass",
		"carcass": [6.4, 2.4], "buried": true, "big": true},
	"fly": {"type": Ant.PROTEIN, "amt": 6.0, "cap": 6.0, "regen": 0.0, "r": 5.0, "handling": [50, 110, 2],
		"found": T.found_fly, "rots_after": 6.0, "feed_pose": "carcass", "carcass": [2.2, 1.3], "buried": true},
	# ("drag": n would have n workers haul it home whole - not used for L. niger: group prey retrieval is only
	# documented in its relative L. neoniger, so the ants cut prey up where it lies; see docs/BIOLOGY.md)
	# enemies the ants killed (never placed by the keeper)
	"wolf_spider_dead": {"type": Ant.PROTEIN, "amt": 18.0, "cap": 18.0, "regen": 0.0, "r": 10.0, "handling": [90, 200, 2],
		"found": T.found_spider_dead, "rots_after": 6.0, "feed_pose": "carcass", "carcass": [4.6, 2.2], "buried": true},
	"ground_beetle_dead": {"type": Ant.PROTEIN, "amt": 22.0, "cap": 22.0, "regen": 0.0, "r": 12.0, "handling": [90, 200, 2],
		"found": T.found_beetle_dead, "rots_after": 6.0, "feed_pose": "carcass", "carcass": [7.0, 3.0], "buried": true, "big": true},
	"centipede_dead": {"type": Ant.PROTEIN, "amt": 16.0, "cap": 16.0, "regen": 0.0, "r": 12.0, "handling": [90, 200, 2],
		"found": T.found_centipede_dead, "rots_after": 6.0, "feed_pose": "carcass", "carcass": [8.5, 1.1]},     # curled up dead: the straight soil cover would not fit
}


static func info(kind: String) -> Dictionary:
	return KINDS.get(kind, {})


## [[label, kind], ...] for the keeper's tool bar, in table order.
static func tools() -> Array:
	var out := []
	for k in KINDS:
		if KINDS[k].has("tool"):
			out.append([KINDS[k].tool, k])
	return out
