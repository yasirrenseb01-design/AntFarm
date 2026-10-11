extends RefCounted
## One worker ant. Plain data; behaviour lives in simulation.gd.

const IN_NEST := 0
const SEARCH := 1
const RETURN := 2
const HOME := 3
const UNDERTAKER := 4

const NONE := 0
const SUGAR := 1
const PROTEIN := 2
const CORPSE := 3

var id := 0
var age := 0.0          # days since eclosion
var life := 400.0       # days until death of old age
var state := IN_NEST
var pos := Vector2.ZERO
var ang := 0.0
var carry := NONE
var trip := 0           # ticks since leaving the nest or the last delivery
var since := 0          # ticks since picking up the current load
var energy := 1.0
var size := 1.0          # body size relative to a 4.2 mm worker, set at pupation
var hardiness := 1.0     # individual tolerance to starvation and drought
var patience := 2000
var follow := 0          # ticks left of edging along an obstacle before heading for the goal again
var slide := 1.0        # which way it turns to follow a wall (+1 left, -1 right)
var busy := 0           # ticks left standing still doing something (eating, milking aphids, meeting)
var act := 0            # what it is doing for the view: 0 walk, 2 bite/cut, 3 antennate, 9 milk aphids, 10 drink
var meet_cd := 0         # ticks before it will stop for another encounter
var turn_after := false  # turn round once the current task is done
var phase := 0.0        # gait phase for leg animation
var dead := false

# view-only smoothing state (the simulation never reads these)
var vpos := Vector2(INF, INF)
var vang := 0.0
var anim := 0.0
var vmv := 0.0
var vfeed := 0.0         # 3D outworld: how far the ant has moved onto the food it is handling
var vpose = null


func is_out() -> bool:
	return state != IN_NEST
