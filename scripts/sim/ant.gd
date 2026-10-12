extends RefCounted
## One ant (so far always a worker). Plain data; behaviour lives in simulation.gd.

const IN_NEST := 0
const SEARCH := 1
const RETURN := 2
const HOME := 3
const UNDERTAKER := 4
const DEFEND := 5          # answering the alarm: running at an enemy or clinging to it
const DRAG := 6            # holding a whole small prey with nestmates and hauling it home (foe = the food's seed)

# castes: workers now; winged gynes (new queens) and males come with the nuptial flight (PART 10)
const WORKER := 0
const GYNE := 1
const MALE := 2

# what a worker in the nest is doing (set each colony step; not saved — worked out again after loading)
const TASK_OUT := 0        # outside (foraging, defending, carrying out the dead, hauling)
const TASK_CALLOW := 1     # just eclosed, still pale
const TASK_NURSE := 2      # young: tends the brood and the queen
const TASK_RESERVE := 3    # older, resting inside: the pool the foragers, undertakers and defenders come from
const TASK_DIG := 4        # digging the nest
# individual thresholds (response-threshold model of division of labour, Bonabeau et al. 1996): each worker
# answers each kind of need at its own level, so some always go first and others hardly ever
const TH_AGE := 0          # how long it stays a nurse
const TH_FORAGE := 1
const TH_UNDERTAKE := 2
const TH_DEFEND := 3
const TH_DIG := 4
const TH_ATTEND := 5       # drawn to the queen (her retinue, in the nest view)

const NONE := 0
const SUGAR := 1
const PROTEIN := 2
const CORPSE := 3

var id := 0
var caste := WORKER
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
var task := TASK_OUT     # (see TASK_*)
var came_in := -1000000  # tick it last came back into the nest (the view walks it in from the entrance)
var turn_after := false  # turn round once the current task is done
var phase := 0.0        # gait phase for leg animation
var foe := 0            # id of the enemy it is fighting (sim.creatures), 0 = none
var hurt := 0.0          # 0..1 injuries from enemy bites (a lost leg or antenna); slows it for good
var dead := false

# view-only smoothing state (the simulation never reads these)
var vpos := Vector2(INF, INF)
var vang := 0.0
var anim := 0.0
var vmv := 0.0
var vgait := 0.0         # 3D: leg cycle phase, advanced by distance walked over the stride length
var vfeed := 0.0         # 3D outworld: how far the ant has moved onto the food it is handling
var vpose = null
var vflung := false     # set by the simulation when an enemy throws it off (the view plays the fall; never read by the sim)
var vright := 0.0       # 3D: seconds left of being thrown, landing on its back and righting itself
var vfly_from := Vector2.ZERO
var vact := Vector3(-1, 0, 0)   # 3D: easing from one activity's pose to the next (AntModel.act_step)


## This worker's threshold for a kind of need (TH_*), 0.6 (eager) .. 1.4 (reluctant): fixed for life,
## worked out from its id so nothing extra needs saving.
func threshold(kind: int) -> float:
	var h := sin(float(id) * 12.9898 + float(kind) * 78.233) * 43758.5453
	return 0.6 + 0.8 * (h - floorf(h))


func is_out() -> bool:
	return state != IN_NEST
