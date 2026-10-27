extends "res://scripts/view/outworld/parts/outworld_creatures.gd"
## Outworld view, after the foragers. From v0.11.45 to v0.11.56 this drew soil carriers of its own - ants only drawn,
## with no ant in the simulation behind them: they laid no trail, met nobody, and the nest view's digger never came out
## (the keeper, 2026-10-27). Since v0.11.57 the diggers themselves walk out in the simulation (Ant.DUMP, sim._surface)
## and are drawn with every other ant outside, their pellet in their mandibles (outworld_creatures). Kept as a layer for
## what is drawn after the foragers.
