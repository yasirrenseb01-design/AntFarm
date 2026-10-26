extends RefCounted
## Simulation, layer 1 of 7: all colony and outworld state - constants, variables, the save format (split from
## sim_base.gd in v0.11.8). Layers: sim_state <- sim_base <- sim_foragers <- sim_enemies <- sim_colony <- sim_duties
## <- simulation.

const Ant := preload("res://scripts/sim/ant.gd")
const Field := preload("res://scripts/sim/pheromone_field.gd")
const Climate := preload("res://scripts/sim/climate.gd")
const LasiusNiger := preload("res://scripts/sim/species/lasius_niger.gd")
const NestVolume := preload("res://scripts/sim/nest_volume.gd")
const T := preload("res://scripts/sim/text_th.gd")     # journal keys
const L := preload("res://scripts/sim/lang.gd")        # words in the language in use
const FoodKinds := preload("res://scripts/sim/food_kinds.gd")

signal logged(entry: Dictionary)

const TPD := 3600                    # ticks per game day (60 s at 1×)
const WORLD := Vector2(1200, 750)    # outworld in px, 1 px ≈ 0.5 mm → 60 × 37.5 cm box
const CELL := 5.0
const NEST_R := 9.0
const COLONY_EVERY := 20             # colony bookkeeping runs every N ticks
const SENSE_EVERY := 4               # ants re-read pheromone gradients every N ticks
const INV_CELL := 1.0 / CELL

const HOME_EVAP := 0.9995
const FOOD_EVAP := 0.9993
const RAIN_EVAP := 0.985
const ALARM_EVAP := 0.97             # alarm pheromone is volatile: gone within a minute or two

var sp: Dictionary = LasiusNiger.DATA
var rng := RandomNumberGenerator.new()
var tick := 0
var climate: Climate
var nest: NestVolume
var diggers_wanted := 0
var home: Field
var food: Field
var alarm: Field                     # alarm pheromone around a fight (formic acid, undecane)
var gw := 0
var gh := 0
var rock := PackedByteArray()
var rocks: Array = []
var nest_pos := Vector2(480, 400)
var midden_pos := Vector2(575, 480)
var plot_seed := 0                    # how this colony's plot is laid out (sim_base._lay_out_plot; 0: the one plot every
                                      # colony had before v0.11.18 - its stones, plants and looks never change)
var foods: Array = []
var corpses: Array = []
var workers: Array = []
var outside: Array = []               # workers currently in the outworld (rebuilt each colony tick)
var eggs: Array = []
var larvae: Array = []
var pupae: Array = []
var water := 1.0               # the nest's water tank (keeper's formicarium), 0..1: keeps the nest damp while it lasts
var queen := {"alive": true, "starve": 0.0, "reserve": 0.0, "name": ""}   # reserve: fat body + dissolved wing muscle; name: the keeper's
var sugar := 6.0
var sugar_income := 0.0             # sugar brought home, averaged over about a week (units per week)
var sugar_spend := 0.0              # sugar eaten by the colony, averaged the same way
var fat := 0.0                     # food stored in the workers' fat bodies (what carries a colony through winter)
var protein := 3.0
var humidity := 0.7
var mold := 0.0
var heater := false
var enemies := true
var enemy_rate := 1.0              # how often natural enemies come: x each kind's own rate (the keeper's choice, set_enemy_rate)
var _next_cid := 1                 # next creature id
var creatures: Array = []          # enemies in the outworld: {"kind", "pos", ...} (see parts/sim_enemies.gd)
var corpses_inside := 0
var scenario := "keeper"          # "keeper" (indoor formicarium) or "wild" (a plot of ground; seasons, enemies)
var start_doy := 205               # day of the year the colony started (a founding queen: late July)
var fridge_on := false             # keeper: the formicarium is in the fridge for its winter rest
var cold_days := 0                 # days this winter with the nest below 10 °C (the queen's winter rest)
var egg_acc := 0.0
## dead = workers (dead_by: starve, thirst, old, out = lost while foraging, enemy); brood_dead = eggs, larvae
## and pupae lost to drought, mould or heat (larvae eaten by hungry workers are counted in cannibalized)
var stats := {"dead": 0, "cannibalized": 0, "born": 0, "sugar_in": 0, "protein_in": 0, "brood_dead": 0, "dead_by": {}}
# what the colony has done since it was loaded, for the keeper's Colony Harmony points (game/harmony.gd; not saved,
# and nothing in the simulation reads it): workers born, of them big ones, back alive from a fight, nestmates fed
var harmony_n := {"born": 0, "big": 0, "survived": 0, "fed": 0}
const HARMONY_BIG := 1.06      # a big worker: the largest fifth of the sizes a worker comes out at (0.7 - 1.15, sim_base._adult_size)
var history: Array = []
var log_entries: Array = []

# Recent life-cycle moments for the views to animate ("egg" laid, larva "pupate"d, worker "eclose"d).
# Not part of the saved state and never read by the simulation itself.
var events: Array = []
var event_seq := 0

# derived each colony tick, read by the UI
var nurses := 0
var callow := 0
var out_count := 0
var dev := 0.5
var larva_fed := 1.0            # how much of what the larvae need they got in the last step, 0..1 (shown to the keeper; not saved)
var activity := 0.5
var starving := false
var queen_fed := true
var hungry := false

var _warned := {}
var _next_id := 1
var _any_dead := false
var _cannibal_cd := 0.0
var _spd := 0.5
var _want_sugar := true
var _want_protein := true
var food_cell := PackedInt32Array()     # per pheromone cell: index of a food within smelling range, or -1
var _food_dirty := true
var prof := {"colony": 0, "grid": 0, "ants": 0, "other": 0, "steps": 0, "grids": 0}
var _noise_k := 1.0
var _recruits := 0                       # nestmates excited by successful foragers, sent out next colony tick
var ant_substep := 1                     # >1 at high game speeds: each ant moves every N ticks with N× stride
var _log_home := log(HOME_EVAP)
var _log_food := log(FOOD_EVAP)
var _log_rain := log(RAIN_EVAP)
var _log_alarm := log(ALARM_EVAP)

# duties in the nest (parts/sim_duties.gd; saved)
## The duties draw on their own generator, seeded from the colony's (deterministic, saved): drawn from sim.rng, every
## later draw of the colony moved on and each colony grew as another one would - more or less at random (5 seeds: the
## same colony 137-219 workers at day 420 against 159-259 with v0.11.7; on its own generator seed 1 grew exactly as before)
var duty_rng := RandomNumberGenerator.new()
const DUTY_SEED := 0x2B992DDF                  # (mixed into the colony's seed for the duties' generator)
const PLOT_SEED := 0x51A7C0DE                  # (mixed into it for the plot's layout)
const TRAIT_SEED := 0x7EA51DE5                 # (and for the colony's character)
# What sets this colony apart from others of its kind, drawn once when it is founded (sim_base._draw_traits; {} in
# colonies from before v0.11.18: every one 1.0). Each a multiplier round 1:
#   queen   her weight at founding: how many eggs she can lay and her founding reserve [L. niger: heavier queens raise
#           more brood by the first workers and more by winter - Fjerdingstad & Keller 2004, Evolution 58:1056]
#   forage  how readily its workers go out [colonies of one species differ lastingly in how actively they forage -
#           "colony personality", other ants; e.g. Bengston & Jandt 2014, Front Ecol Evol 2:81 - not shown for L. niger]
#   life    how long its workers live [inference: worker lifespan varies, by colony as well is assumed]
#   size    its workers' size [inference: worker size differs among colonies with food and age (sim_base._adult_size)]
#   depth, spread   how deep it digs, and how much its new chambers go sideways rather than down [inference: nests of
#           one species differ in shape (Tschinkel 2004 for other ants); here a habit of the colony, not of the soil]
var traits := {}
const UNTENDED_LAYING := 0.9             # a queen nobody attended lays this much (the keeper's choice: no evidence either way)
var queen_tended := true                 # someone attended the queen this half hour (none: she lays UNTENDED_LAYING)
var _carry_due := 0                      # brood to carry since the last duty round (eggs laid, larvae pupating, workers out)
var _unloaded: Array = []                # foragers (ids) who brought honeydew home since the last duty round



# ---------------------------------------------------------------- save / load

const SAVE_VERSION := 11             # raise together with a step in save_migrations.gd
const ANT_FIELDS := ["id", "age", "life", "state", "pos", "ang", "carry", "trip", "since", "energy", "size",
	"hardiness", "patience", "follow", "slide", "busy", "act", "meet_cd", "turn_after", "phase", "caste", "foe", "hurt", "name",
	"duty", "partner", "sweet", "n_larvae", "n_brood", "n_mates", "rest_h", "dig_h", "n_sugar", "n_prey", "n_corpses", "n_fights", "task"]
