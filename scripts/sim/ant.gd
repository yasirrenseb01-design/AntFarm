extends RefCounted
## One ant (so far always a worker). Plain data; behaviour lives in simulation.gd.

const IN_NEST := 0
const SEARCH := 1
const RETURN := 2
const HOME := 3
const UNDERTAKER := 4
const DEFEND := 5          # answering the alarm: running at an enemy or clinging to it
const DRAG := 6            # holding a whole small prey with nestmates and hauling it home (foe = the food's seed)
const DUMP := 7            # a digger out of the entrance with a pellet of soil, to the crater's ring and back (sim._dumps)

# castes: workers now; winged gynes (new queens) and males come with the nuptial flight (PART 10)
const WORKER := 0
const GYNE := 1
const MALE := 2

# what a worker in the nest is doing (set each colony step; saved since v0.11.8 for the duties)
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

# what a worker inside is doing this half hour (its duty, set by parts/sim_duties.gd from the colony's needs; saved)
const D_OUT := 0           # outside (foraging, defending, carrying out the dead, hauling)
const D_REST := 1          # standing still: the colony's reserve
const D_FEED_LARVAE := 2
const D_CARRY := 3         # carrying brood (an egg to the pile, a larva to spin, an empty cocoon away)
const D_FEED_MATE := 4     # giving honeydew mouth to mouth (partner: who gets it)
const D_FED := 5           # being given honeydew (partner: who gives it)
const D_QUEEN := 6         # attending the queen
const D_GROOM := 7         # cleaning itself or a nestmate
const D_DIG := 8
const D_IDLE := 9          # walking about the nest

const NONE := 0
const SUGAR := 1
const PROTEIN := 2
const CORPSE := 3
const SOIL := 4            # a pellet of excavated soil (Ant.DUMP)

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
var task := TASK_OUT     # (see TASK_*; saved since v0.11.8: the duties read it)
var came_in := -1000000  # tick it last came back into the nest (the view walks it in from the entrance)
var brought := 0         # (view only, not saved) what it last brought in: SUGAR shows as a swollen gaster inside
var turn_after := false  # turn round once the current task is done
var phase := 0.0        # gait phase for leg animation
var foe := 0            # id of the enemy it is fighting (sim.creatures), 0 = none
var hurt := 0.0          # 0..1 injuries from enemy bites (a lost leg or antenna); slows it for good
var dead := false
var name := ""            # what the keeper calls it ("" = no name; saved, never read by the simulation)
var duty := D_OUT        # what it does this half hour inside (D_*; parts/sim_duties.gd)
var partner := 0         # who it gives honeydew to / gets it from (worker id), 0 = nobody
var sweet := 0.0         # honeydew in its crop to pass on, 0..1 (fills when it brings sugar home or is given some)
# what it has done in its life (the star ants panel; never read by the simulation)
var n_larvae := 0        # times it fed a larva
var n_brood := 0         # eggs, larvae and cocoons carried
var n_mates := 0         # nestmates it fed mouth to mouth
var rest_h := 0.0        # hours standing still
var dig_h := 0.0         # hours digging
var n_sugar := 0         # loads of honeydew brought home
var n_prey := 0          # pieces of prey brought home
var n_corpses := 0       # dead nestmates carried out
var n_fights := 0        # fights with an enemy it came through alive

# view-only smoothing state (the simulation never reads these)
var vpos := Vector2(INF, INF)
var vang := 0.0
var anim := 0.0
var vmv := 0.0
var vgait := 0.0         # 3D: leg cycle phase, advanced by distance walked over the stride length
var vstem := Vector3.INF # 3D outworld: where it was drawn last frame going up or down a plant's stem (its legs step it)
var vdown := false       # 3D outworld: coming down the stem (head first), not going up
var vbusy0 := 0          # 3D outworld: how long the drinking it is busy with was at its start (its crop fills over it)
var vfeed := 0.0         # 3D outworld: how far the ant has moved onto the food it is handling
var vpose = null
var vflung := false     # set by the simulation when an enemy throws it off (the view plays the fall; never read by the sim)
var vright := 0.0       # 3D: seconds left of being thrown, landing on its back and righting itself
var vfly_from := Vector2.ZERO
var vbeyond := 0.0      # 3D: seconds since it walked off past the plot (outdoors), -1 = walking back in
var vact := Vector3(-1, 0, 0)   # 3D: easing from one activity's pose to the next (AntModel.act_step)
var vxf = null          # 3D outworld: where it was drawn last (for picking it with a click)
var voff := Vector2.ZERO  # 3D outworld: drawn this far from vpos, clear of its neighbours (view/outworld/parts/outworld_crowd.gd)
var vdoff := 0.0          # 3D outworld: how far voff moved this frame (the legs walk it)
var vdir := Vector2.ZERO  # 3D outworld: its way of travel, smoothed over ~1/4 s (the body faces it, not each step's wobble)
var vup := Vector3.ZERO   # 3D outworld: its body's up, easing onto the ground's tilt (ZERO: not yet drawn)
var vfood := Vector2(INF, INF)   # 3D outworld: the centre of the food it is drawn at (INF: none)
var vring := 0            # 3D outworld: which ring round the drop (0 at its edge, 1 behind those ...)
var vrim_goal := INF      # 3D outworld: the gap round the food it walks round the edge to
var vrim := INF           # 3D outworld: the angle round the food it stands at (INF: not at food)
var vaphid := -1          # 3D outworld: which of the plant's low aphids it climbs to


## This worker's threshold for a kind of need (TH_*), 0.6 (eager) .. 1.4 (reluctant): fixed for life,
## worked out from its id so nothing extra needs saving.
func threshold(kind: int) -> float:
	var h := sin(float(id) * 12.9898 + float(kind) * 78.233) * 43758.5453
	return 0.6 + 0.8 * (h - floorf(h))


func is_out() -> bool:
	return state != IN_NEST
