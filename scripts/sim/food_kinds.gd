extends RefCounted
## Every kind of food the outworld can hold, in one table. The simulation and all the views read it,
## so a new food is: one entry here + (optionally) a 3D builder in view/outworld/parts/outworld_props.gd
## and a 2D drawing in view/surface2d/world_view.gd (both fall back to something plain).
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

const Ant := preload("res://scripts/sim/ant.gd")
const T := preload("res://scripts/sim/text_th.gd")

const KINDS := {
	"aphids": {"type": Ant.SUGAR, "amt": 10.0, "cap": 16.0, "regen": 9.0, "r": 16.0, "handling": [60, 140, 9],
		"found": T.found_aphids, "feed_pose": "climb"},
	"honey": {"type": Ant.SUGAR, "amt": 25.0, "cap": 25.0, "regen": 0.0, "r": 8.0, "handling": [40, 80, 10],
		"found": T.found_honey, "dries": 0.78, "tool": "หยดน้ำผึ้ง", "feed_pose": "rim"},
	"cricket": {"type": Ant.PROTEIN, "amt": 30.0, "cap": 30.0, "regen": 0.0, "r": 12.0, "handling": [90, 200, 2],
		"found": T.found_cricket, "rots_after": 6.0, "tool": "จิ้งหรีดตาย", "feed_pose": "carcass",
		"carcass": [6.4, 2.4], "buried": true, "big": true},
	"fly": {"type": Ant.PROTEIN, "amt": 6.0, "cap": 6.0, "regen": 0.0, "r": 5.0, "handling": [50, 110, 2],
		"found": T.found_fly, "rots_after": 6.0, "feed_pose": "carcass", "carcass": [2.2, 1.3], "buried": true},
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
