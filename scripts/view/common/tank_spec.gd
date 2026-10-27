extends RefCounted
## The one set of sizes for a keeper's tank, used everywhere it is drawn (the keeper, 2026-10-27: "the box is tall but
## its soil is not - where would the nest be? make every size one value, everywhere"): the Home's room
## (view/home/home_kit.gd), the foraging box in the game (view/outworld/parts/outworld_scene.gd, keeper_room.gd) and the
## ant farm on its shelf. Metres. The numbers the simulation fixes are copied here, and tests/tank_spec_test.gd checks
## them against it (the box's floor from sim_state.SMALL_WORLD/BIG_WORLD at 0.5 mm a pixel, the nest's block from
## nest_voxels at 1.5 mm a voxel), so a change on either side shows.
##
## A tank: a glass box on the desk or a shelf, its soil as deep as the nest's block (the nest is dug in it, under the
## entrance), the foraging floor on top of the soil, glass up to the rim above it (a Fluon band under the rim).

const VOXEL := 0.0015                          # a nest voxel; one unit of the 3D views
const PX := 0.0005                             # a pixel of the simulation's foraging floor
const SMALL := Vector2(0.60, 0.375)            # the box's floor, inside the glass (sim_state.SMALL_WORLD)
const BIG := Vector2(0.90, 0.5625)             # the Home's bigger tank (sim_state.BIG_WORLD)
const NEST := Vector3(0.096, 0.108, 0.096)     # the nest's block of soil (nest_voxels 64 x 72 x 64)
const SOIL := 0.108                            # the soil in the box: the nest's depth
const TALL_SMALL := 0.20                       # glass, from the box's floor to the rim
const TALL_BIG := 0.27
const GLASS := 0.003                           # a pane's thickness
const RIM := 0.0018                            # the dark silicone rim along the top and bottom edges
const FARM := Vector3(0.165, 0.108, 0.0075)    # an ant farm's soil between its panes (nest_voxels slab 110 x 72 x 5)
const FARM_AIR := 0.02                         # glass above a farm's soil
const FARM_FRAME := 0.012                      # its wooden frame, round the sides and along the top
const ANT_SCALE := 1.0                         # the ants as big as they are (BIOLOGY.md); 1.1 until v0.11.53


## The floor of a box (metres): big or not.
static func floor_of(big: bool) -> Vector2:
	return BIG if big else SMALL


## The glass's height from the box's floor (metres).
static func tall(big: bool) -> float:
	return TALL_BIG if big else TALL_SMALL


## The whole tank outside (metres): its floor plus two panes, its height plus the bottom rim.
static func outside(big: bool) -> Vector3:
	var f := floor_of(big)
	return Vector3(f.x + GLASS * 2.0, tall(big) + GLASS, f.y + GLASS * 2.0)
