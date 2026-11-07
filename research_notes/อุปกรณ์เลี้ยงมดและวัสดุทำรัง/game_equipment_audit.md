# What keeper equipment the AntFarm game has today, and where an equipment system would connect

Audit of code at git `76fa065` (v0.11.93), 2026-11-06. Nothing was run and no project file was edited, so no number here is a fresh measurement. Paths are relative to `E:/AntFarm`. This goes deeper on equipment than `research_notes/เลี้ยงมดดำสวนเทียบกับเกม AntFarm/game_model_audit.md` and does not repeat its biology.

Shorthand for files:
- `STORE` = `scripts/game/home_store.gd`
- `SHOP` = `scripts/game/home_shop.gd`
- `HARM` = `scripts/game/harmony.gd`
- `SPEC` = `scripts/view/common/tank_spec.gd`
- `BASE` = `scripts/sim/parts/sim_base.gd`
- `COL` = `scripts/sim/parts/sim_colony.gd`
- `WARM` = `scripts/sim/parts/sim_warmth.gd`
- `CLIM` = `scripts/sim/climate.gd`
- `VOX` = `scripts/sim/parts/nest_voxels.gd`
- `CHAM` = `scripts/sim/parts/nest_chambers.gd`
- `VOL` = `scripts/sim/nest_volume.gd`
- `SIM` = `scripts/sim/simulation.gd`
- `CHECK` = `scripts/sim/save_check.gd`
- `MIG` = `scripts/sim/save_migrations.gd`
- `SAVE` = `scripts/game/save_store.gd`
- `CTRL` = `scripts/view/ui/parts/hud_controls.gd`
- `TOOLS` = `scripts/view/home/home_tools.gd`
- `FRIDGE` = `scripts/view/home/home_fridge.gd`
- `KIT` = `scripts/view/home/home_kit.gd`
- `BL` = `docs/roadmap/BACKLOG.md`
- `PLAN` = `docs/roadmap/PLAN_0.12.md`
- `RM` = `docs/ROADMAP.md`
- `LES` = `docs/LESSONS.md`
- `CL` = `CHANGELOG.md`
- `STR` = `lang/strings.csv`

"Arithmetic" under Inferences means I worked it out from code constants or recorded figures. It was not observed in a run.

## What the player can own or place today

### Takeaway
Only tanks and shelves cost points, and they buy colony slots and places to stand tanks, not husbandry. The heat mat, fridge, water, food and stones are free and unlimited. What does change the simulation has almost no object in the world (heat mat and water tank have no model). What looks most like keeper kit (the desk tray) does nothing at all. There is no inventory, no per-tank fitting and no way to change equipment on a colony that already started.

### Cited Findings

| Item | Price (points) | Defined | What it changes in the simulation | Visual only? |
|---|---|---|---|---|
| First small tank | free | `STORE:88-95` | One keeper colony slot, one wild slot | No |
| Small tank | 600 | `STORE:15`, `SHOP:12` | Another colony slot. Needs a free shelf place (`STORE:152-153`) | No |
| Bigger tank (once) | 1,500 | `STORE:15,144-145,162-179` | Foraging floor 90 × 56 cm instead of 60 × 37.5 cm, with bigger pheromone grids (`BASE:12,18-22`, `SPEC:14-15`). Same nest block. Fixed when a colony starts (`scripts/game/main.gd:147,150`) | No |
| Ant farm | 80, **not on sale** | `STORE:15`; left out of `SHOP:12-13` and `scripts/game/shop_preview.gd:15-18` | Nest becomes a 110 × 72 × 5 voxel slab, digging limited to the last 3 layers (`VOX:35,67-70`, `VOL:21-22`). Already-bought farms remain (`STORE:63-65,137-139`, `SHOP:9-11`) | No |
| Shelf for 2 / for 4 | 3,500 / 18,000 | `STORE:15,185-186`; at most 4, placed at fixed wall spots (`scripts/view/home/home_room.gd:24-25`) | Nothing. Only raises `small_room()` (`STORE:130-134`) | Sim-free, gates purchases |
| Wall screen | removed | `STORE:16,57`; refund at `scripts/game/main.gd:103-107` | Gone; 4,000 points refunded (`CL:8`) | n/a |
| Heat mat | free toggle | `CTRL:338-343`, keeper only | Nest target +4.5 C (`CLIM:11,63`), bottom chambers warmer than top (`WARM:48-49`), water use up (`COL:270,283`). On/off only | **No 3D object.** Grep of Home, outworld and nest scene code found none |
| Fridge | free, one in the room | `CTRL:344-356`, `FRIDGE` | Ramps nest and air toward 6.5 C over a week (`COL:10`, `CLIM:12,64,81-82`). Caps larvae at diapause (`COL:402`). Lets the queen rest (`COL:14-20`). The limit of 2 tanks is checked only in the UI (`CTRL:223-230,347`), not in the simulation | Modelled, and the tank moves into it (`scripts/view/outworld/parts/outworld_scene.gd:275-291`) |
| Water tank | free | `CTRL:325-332`, `scripts/game/home_water.gd`, `BASE:315-318` | `sim.water` 0-1 drives humidity (see Moisture). Pays points when filled below 30% (`HARM:20-24,84-91`) | **No 3D object.** Only a bar (`scripts/view/ui/parts/hud_panel.gd:216-219`) |
| Closed-game helper | free setting, default on | `SAVE:25` ("care"), `SIM:270-282` | Fills water and feeds while the game is closed | Sim only |
| Honey, cricket | free, unlimited | `scripts/sim/food_kinds.gd:26,28,48-54`, `BASE:301-312` | Food items | No |
| Stone, take stone | free, unlimited | `scripts/view/outworld/outworld_view.gd:250-256`, `BASE:322-408` | Blocks or slows foragers (`BASE:378-393,516-519`) | No |
| Wipe scent | free | `scripts/view/outworld/outworld_view.gd:258-259`, `BASE:411-413` | Clears `home` and `food` fields in a radius | No |
| Let an enemy in | 50 × colonies with ants | `scripts/view/ui/parts/hud_enemies.gd:111-138` | Spawns a creature, at most `RELEASE_MAX` | No |
| Fluon band | comes with every tank, not buyable | `scripts/view/outworld/parts/outworld_scene.gd:28`, `scripts/sim/parts/sim_foragers.gd:315-319` | A searcher at the glass climbs with 12% chance for 240 ticks, then returns. The band has no sim state and cannot be missing | Climb is sim, band is drawn |
| Desk tray: brush, forceps, syringe, hand lens, 2 founding tubes (one with a queen), aspirator, petri dish, Fluon bottle | free, not interactive | `TOOLS:1-9,56-67`, `BL:80`, `CL:258,283-286` | Nothing | **Yes** |
| Room items: desk, chair, rug, potted plant, drawers, notebook, door, lamps | free, fixed | `scripts/view/home/home_room.gd:2-7`, `KIT:96-351` | Nothing | **Yes** (the door says "coming soon": `BL:140`) |
| Tank scenery: pebbles, litter, moss, tufts | not placeable | `scripts/view/outworld/ground_data.gd:2-4`, `scripts/view/outworld/prop_heights.gd:2-6` | "The simulation does not know about litter" (`prop_heights.gd:5`), though view ants climb it | **Yes** |
| 2 aphid plants, starting cricket, stones from the seed | not placeable | `BASE:80-87,243-250` | Real food and obstacles | No |

- Also view-only controls: scent overlay, cut plane, x-ray (`CTRL:305-313,333-337`).
- Instruments: thermometer and hygrometer are absent. Grep for `thermom|hygro` in `scripts/view/home`, `scripts/view/outworld` and nest scene code found none. The HUD simply shows the values (`scripts/view/ui/hud.gd:235-237`). The cooler has a printed label (`FRIDGE:18`).
- Inventory: absent. `grep -i inventory` in `scripts` and `tests` returned nothing. `BL:144` lists it as not done.
- Per-tank fittings or upgrades: absent. `STORE` holds only `tanks`, `wild`, `big`, `shelves`, `farms` (`STORE:24-30`), written as a fixed field list (`STORE:104`). Nothing stores which items belong to which colony, apart from the farm and big slot lists.

### Inferences
- The husbandry items a future equipment system would most naturally sell are the free ones (mat, water tank, fridge). Charging for them later changes the terms for existing players, and would need a grandfathering rule like the farm's (`SHOP:9-11`).
- The tray already shows gear the game lacks a mechanic for, including a tube with a queen. It can serve as the visual seed for the system, since the models exist.

### Gaps
- Disagreements between docs and code are listed under Prior notes.

## Nest and tank geometry: could plaster, acrylic or a test tube fit?

### Takeaway
A fixed-chamber nest fits the voxel data model, because `rho` stores only density and has no idea of material. What is tied to soil is the behaviour on top of it: digging, the chamber planner, the volume-driven dig demand, and every soil look. The ant farm slab shows a second geometry can exist with few branches. I estimate that a "no-dig" nest needs a small sim change plus a material-aware view, but it must wait for or align with the PART 0.12 storage rewrite.

### Cited Findings
Representation:
- Voxel 1.5 mm; `rho` 0-255 with open below 128 (`VOX:16-18,36`). Block 64 × 72 × 64, or slab 110 × 72 × 5, hardcoded in `setup` (`VOX:25-27,67-70`). Garden soil reaches 200 layers, loaded on demand (`VOX:28-34,430-462`, `BASE:50-51`).
- Per-voxel arrays: `rho`, `dug_at`, `dist`, `work_dist`, all saved (`VOX:501-504`), plus `hard` (not saved, rebuilt from `soil`: `VOX:42,219-243`).
- Chambers are dictionaries `{c, r, goal, kind, from, via, open, hd, yaw, round, lobe, done}` (`VOX:50`, `CHAM:439-442`). Their shape follows from `goal` (`CHAM:207-218`) and a wobble (`CHAM:228-235`). `kind` is "queen" or "brood" (`VOX:107,116,121`).
- Pre-made geometry already exists at setup: `carve_room`, `carve_line`, `carve_ellipsoid` then `_recount` and `_bfs` (`VOX:99-123,340-363`).
- `dist` is a flood from the single `entrance` (`VOX:52,468-483`), so any open shape with a route to the entrance is walkable by rule.
- Workers have no location in the nest in the simulation. `ANT_FIELDS` has `state` and outworld `pos`, no chamber or voxel (`scripts/sim/parts/sim_state.gd:151-153`, `scripts/sim/ant.gd:4`). Only diggers have cells (`VOL:129`), and brood and queen have chamber indices (`COL:368`, `WARM:18-19,138-143`). The view places the rest (`scripts/view/nest/parts/nest_brood.gd:2,213`, `docs/ARCHITECTURE.md:70`).

What is fixed to soil today:

| Coupling | Where |
|---|---|
| Dig chance: softness by clay and sand depth, humidity | `VOL:16-59` |
| `soil` dict of stones, roots, clay, sand; `from_dict` copies only those four keys, so **an extra key in `soil` is dropped on load** | `VOX:41,132-165,531-542` |
| `hard` can only mark stones and roots; there is no "all of it is hard" | `VOX:219-249` |
| Dig demand: if `air < target_air()`, at least 1 and up to 20 diggers | `COL:170-181`, `BASE:428-430` |
| Chamber goals grow and new chambers get planned whether or not digging is possible | `CHAM:298-363,373-443` |
| Depth target, heat deepening | `CHAM:290-292`, `COL:30` |
| Laying slowed by a cramped nest, factor 0.3-1 | `COL:343` |
| Points for digging | `HARM:14,37` |
| Soil look: layers, damp darkening, stones and roots | `shaders/terrain/soil.gdshader:8,78,92`, `shaders/terrain/xray.gdshader:10,39`, `scripts/view/nest/nest_view.gd:60-65,413-414` |
| Tank's outside view and Home card use loam, clay, sand colours | `shaders/common/tank_soil.gdshader:4,43-47`, `scripts/game/nest_card.gd:15-20` |
| Tank drawn as soil the whole floor, nest block a window on it | `SPEC:9-10,16-17`, `KIT:372-376,465-468`, `scripts/view/outworld/parts/outworld_scene.gd:323-331` |
| Mesher softens every voxel with its neighbours so "burrows come out rounded" | `VOX:305-312`, `scripts/view/nest/nest_mesher.gd:17-54` |

- The slab as precedent: 10 grep lines in 7 files mention `.slab`, such as `VOL:21-22`, `CHAM:209-210,230-231`, `scripts/view/nest/nest_view.gd:204-205`, `scripts/view/nest/parts/nest_scene.gd:310-329`. Its glass and wood case exists only in the view.
- Kind selection: `STORE:138-139` → `scripts/view/ui/parts/hud_colonies.gd:78,352,383,437` → positional string `"nest:start:scenario:rate:species"` → `scripts/game/main.gd:143-150` (`parts[0] == "glass"`) → `BASE:9` (`glass_nest: bool`).
- No plaster, Ytong, acrylic or test-tube nest type exists. Grep for `plaster|ytong|acrylic|test.?tube` in `scripts` found one comment, "wicks into the plaster/soil" (`COL:279`), and `TOOLS:4-5` for the prop.
- A nest-kind search of `scripts` also found only soil and glass (`scripts/view/ui/parts/hud_colonies.gd:352`).

### Inferences
Minimum sim changes for a no-dig nest (my estimate, not tried):
1. A `nest.kind`/material field, saved, defaulting to soil.
2. Skip digging when fixed: set `diggers_wanted = 0` at `COL:170` and return early from `plan_chambers`. Marking all voxels hard is not enough, since `air < target_air` still calls diggers who wander, and `goal` still grows.
3. Pre-made chambers appended with fixed `goal` and `done`. Non-elliptical rooms need care: `count_work_left` treats solid voxels inside the ellipse as work (`CHAM:96-115`), so the shape rule must match the carve, or digging must bypass it.
4. A geometry source for `setup`, replacing the hardcoded branch at `VOX:67-70`, with sizes added to `SPEC` (LESSONS 11e).
5. `scripts/game/main.gd:150` and the `setup` signature. About 20 test call sites pass `false` positionally (`tests/*.gd`), so add a parameter rather than change the bool.

Consequences that follow from the current formulas (arithmetic):
- `target_air` = 80 + 22 voxels per worker, 0.003375 cm³ per voxel. So 100 workers want ~7.7 cm³ and 1,000 want ~74.5 cm³.
- A fixed nest gives a soft limit only. Laying falls to × 0.3 at worst and never stops (`COL:343`), so an overfull fixed nest keeps growing while view crowding worsens (LES 3f, 8d).
- Test tube: the prop is 16 mm × 150 mm (`TOOLS:107`), i.e. about 10.7 × 100 voxels. That fits the grid, but `BL:436` already says the queen's legs are wider than small founding chambers.
- Sharp acrylic edges will come out rounded by the mesher at 1.5 mm. Plaster-like cavities suit this better than crisp acrylic.
- An acrylic or plaster flat nest is closest to the slab with digging off. A tube is closest to a very small block.

### Gaps
- Whether ant view systems (rest spots, floor fields, brood piles) behave on non-elliptical floors is not knowable from reading. They read the voxels (`scripts/view/nest/parts/nest_brood.gd:46,81,213`), but LES 8d and 11g say to test by running.

## Moisture and temperature model

### Takeaway
Humidity is one colony-wide number with about 20 readers, and the water tank is a timer that pulls it to a constant 0.72. Material moisture is cheap: replace constants with a per-material table. Per-chamber moisture is feasible with the `ch_mean` pattern, though it can only reach brood and queen, because workers have no chamber in the simulation. Temperature per chamber exists, but only as a function of depth.

### Cited Findings
Moisture paths:
- State: `humidity` 0.7 start (`scripts/sim/parts/sim_state.gd:64`), `water`, `mold`.
- Keeper update: with water, humidity relaxes to 0.72 at rate 0.6/day, and the tank drains by `water_use()` (`COL:286-288`). Without water, exponential drying with `k` (`COL:290`). `k` = 0.09 + 0.06 with mat + 0.0002 per worker, × 0.3 while founding, written twice (`COL:270-272,283-285`).
- Wild update is separate (`COL:313-322`).
- Inputs besides the tank: fill +0.2 (`BASE:315-318`), food deliveries up to 0.8 (`scripts/sim/parts/sim_foragers.gd:429-430,437-438`).
- Readers: brood loss below 0.35 (`COL:293-296`), mould above 0.9 (`COL:298-308`), worker and queen thirst below 0.1 (`COL:246,329`), laying (`COL:347`), dig keenness (`COL:178`), dig softness (`VOL:29`), auto care (`SIM:273`), HUD (`scripts/view/ui/hud.gd:235-237`), stats (`BASE:422`), away report (`scripts/game/parts/main_base.gd:257`), soil colour (`scripts/view/nest/nest_view.gd:413-414`), thresholds in species data (`scripts/sim/species/lasius_niger.gd:71-72`).
- Water outside the running sim: the Home works out each closed tank's level from meta (`SAVE:28-29,156-168`, `scripts/game/home_water.gd:58-62`), and queued fills replay on opening (`SAVE:124-134`, `scripts/game/parts/main_base.gd:140`).
- There is no drinking point, and water has no position. "Tank" has no location, volume or material.
- Per-point humidity is a backlog idea, with larvae following it: `BL:426`. Cocoons "a little higher, drier" is a depth proxy only (`WARM:122-124`, `scripts/view/nest/parts/nest_brood.gd:254`).

Temperature paths:
- Room: `CLIM:44-51,80`. Nest: one lagged value `climate.nest`, target = 0.45 air + 0.55 × 24 C + mat, blended to fridge (`CLIM:58-64,83`). Lag constant 0.08 day is the only thermal-mass number, and is the same for any material.
- Chamber: `temp_at_cm(depth)` (`WARM:40-50`), recalculated at colony ticks into `_ch_t`, with a one-day mean `ch_mean` that is saved (`WARM:75-87`, `SIM:92`). Indoors the mat adds a vertical gradient only. x and z play no part, though `ch.c` is available.
- `chamber_temp`/`dev_in` drive brood development and placement (`WARM:58-64,147-166`). Global `climate.nest` still drives winter counting (`COL:14,22`), ageing (`COL:83`), food burn (`COL:205,328`), `hibernating` (`BASE:208`), duties (`scripts/sim/parts/sim_duties.gd:51`), the heat-kill gate (`COL:453`).
- Mat setting: bool only (`scripts/sim/parts/sim_state.gd:66`), no thermostat or placement.
- Bug seen by reading: the mat button is never set from the save (`CTRL:338-341`, compare the fridge at `CTRL:345`). A colony saved with the mat on loads with `heater = true` (`SIM:199`) and an unpressed button. Grep for `heater` in UI code shows no other read. Not confirmed by running.

Pattern already in the code for per-chamber data:
- `ch_mean` is a `PackedFloat32Array` parallel to `chambers`, saved, listed `OPTIONAL` in `CHECK:20`, and size-limited on load (`SIM:149`).
- Chambers are capped at 44 (`CHAM:361`).
- A new key in a chamber dictionary passes `CHECK`, since list items are compared non-strictly (`CHECK:73-75`).

### Inferences
- Per-material, single-value: turn 0.72, 0.6, `TANK_DAYS` and `k` into properties of the nest material. Touches `COL:265-290` only, plus meta (`water_use` flows from `summary`, `SIM:264`). Lowest risk.
- Per-chamber: add `ch_wet`, keep `humidity` as a colony mean so readers stay valid. `_cull` takes a whole list (`BASE:457-461`), so brood loss would need filtering by `item.c`. Brood placement scoring (`WARM:163-166`) would add a wet term. Worker thirst must stay global or use a new rule, because workers have no chamber.
- Any new `rng` draw must only occur in the new mode or in its own generator, or the determinism baseline shifts (see Save).
- Material-specific temperature: the mat gradient and lag can be parameterised. Chamber position in x and z allows a side-mounted mat, a mechanic with no current basis in code.
- Evidence for these biology effects has to be sourced and tagged per the project rule (auto-memory `biology-claims-show-sources`). No value above has a material source in the code. `COL:282` calls the tank length a choice made with the user.

### Gaps
- Running time of a per-chamber update at 44 chambers was not measured. It is likely small, since it would run at colony ticks, not per voxel.

## Connections, escape, second nest, moving

### Takeaway
Tubes, a second nest, escape and moving a colony are all absent in code. The only existing plan is the ant farm add-on: an accepted design with no code behind it. "One nest, one outworld, one entrance" is an assumption throughout the simulation and views.

### Cited Findings
Absent, by search of `scripts` for `\btube\b|fluon|escape|relocat|second.?nest|lid\b` plus reading of `BASE`, `COL`, `CTRL`:
- Tube: only mesh helpers and the tray prop (`scripts/view/common/parts/mesh_kit_base.gd:60`, `TOOLS:107`), plus a note on future tubes (`SHOP:9-11`).
- Second nest in one colony: absent. One `nest` (`scripts/sim/parts/sim_state.gd` and `BASE:35`), one `nest_pos` (`scripts/sim/parts/sim_state.gd:46`), one `entrance` (`VOX:52`).
- Escape: absent. Ants cannot leave: `blocked()` stops at 3 px of the wall (`BASE:516-519`). Climbers return by timer (`scripts/sim/parts/sim_foragers.gd:315-319`). The fall from the band is a view effect (`scripts/view/outworld/parts/outworld_creatures.gd:529-549`, `CL:1802-1803`). There is no lid item; "lid" hits are the farm's view frame (`scripts/view/nest/parts/nest_scene.gd:329`) and petri dish (`TOOLS:242-245`).
- Fluon behaviour: fixed by constant. No bottle use, no wear. Evidence for Fluon is tagged forum, not research (`docs/BIOLOGY.md:125,399`, `CL:1809`).
- Colony moving: absent. Colony migration by ants: absent. Only brood and queen change chamber (`WARM:116-144`). A bought tank always takes a new slot, because a slot's box and nest "is set when a colony starts" (`STORE:163-164`, `CL:726`).

Rough size of the assumption (grep lines in `scripts`, comments included):

| Pattern | Lines | Files |
|---|---|---|
| `nest.` | 260 | 34 |
| `WORLD` | 64 | 22 |
| `nest_pos` | 36 | 12 |
| `.chambers` | 29 | 11 |
| `rho[` | 25 | 7 |
| `.entrance` | 17 | 11 |

Prior design:
- `BL:106-109` (player decision 2026-10-27): the ant farm returns post-EA as an add-on, 1 per tank, placed beside the tank and joined by a clear tube. Ants dig and live in it. "Two nest parts joined through a tube, ants walking through it; the nest view must show both."
- Removed from the shop in v0.11.54 (`CL:563`). Also promised publicly at `docs/release/STORE_PAGE.md:128,225`.
- Rival colonies were deferred because it needs "a whole second colony" in the sim (`BL:429-430`).

Home build mode, item 12:
- Decided by the user, community told 2026-11-05, not scheduled (`RM:40`, `BL:144`).
- Scope: place shelves, tanks, things on a grid plus Inventory.
- Today positions are not stored. Tanks are placed by order bought (`STORE:195-214`) and shelves by order at 4 fixed wall spots (`scripts/view/home/home_room.gd:24-25`). A grid or snap system: absent (grep of `home_room.gd`, `home.gd`).

### Inferences
- A cheap reading of the add-on: both parts live in one voxel grid, joined by a corridor of open cells, with a hard gap between. `_bfs` handles reachability automatically, and sim ants have no positions in the nest. The costs are in view, not sim: mesher, case, camera, walking fields. This is untested reasoning.
- Two separate grids would touch most of those 260 lines, so I would avoid that.
- Escape as a mechanic is new work in `blocked()`, with new ant states outside the box, and would interact with the "ants lost" count and offline catch-up.
- Moving a colony into new housing would need brood and worker transfer rules and chamber remapping. A simple abstraction is possible because workers have no nest position.

### Gaps
- Where the tube would attach in the outworld or the nest has not been designed anywhere I found.

## Shop and economy

### Takeaway
Earning is real-time, about 18 points an hour for a new colony and 125-160 for an established one, on figures measured at v0.11.39. Full housing costs at most ~10,900 points, after which the only sink is enemy release, so an equipment price list has room to add one. Those rates need remeasuring before setting prices.

### Cited Findings
Earning (`HARM:4-8,11-24`):

| Event | Points |
|---|---|
| Worker born | 1 (big worker 2) |
| Survived a fight | 0.6 |
| Fed nestmate | 0.05 |
| Dug block | 0.025 |
| Water fill under 30% | 30, once per tank per real hour |

- Multipliers: × 1.5 live, × 1 away, × 0.3 wild. Paid per event × 60 ÷ game days per real hour, so speed gives no gain (`HARM:35-53`). `_earn` at `scripts/game/parts/main_base.gd:241-243`.
- One purse, `harmony.json` (`HARM:2-3,77-80`), capped at 4 KB on read (`HARM:62`).
- Measured rates (`CL:771`, `BL:123-124`), pre-÷10 values divided by 10:

| Colony | Points per real hour while open |
|---|---|
| New, first 2 game months | ~18 |
| Year 1 average | ~78 |
| Year 2 | ~125 |
| Player's ~150 workers | ~159 |

- About 3/4 of a big colony's income is from feeding (`BL:124`). `STORE:18` says "the points come fast" (2026-11-06).

Prices (`STORE:15`, `scripts/view/ui/parts/hud_enemies.gd:114`):

| Item | Points | Hours at 18/h | at 78/h | at 125/h | at 159/h |
|---|---|---|---|---|---|
| Small tank | 600 | 33 | 7.7 | 4.8 | 3.8 |
| Bigger tank | 1,500 | 83 | 19 | 12 | 9.4 |
| Shelf 2 | 3,500 | 194 | 45 | 28 | 22 |
| Shelf 4 | 18,000 | 1,000 | 231 | 144 | 113 |
| Enemy release | 50 × colonies | 2.8 | 0.6 | 0.4 | 0.3 |

Hour columns are arithmetic. Enemy at one colony. Fridge, mat and water: free. Ant farm 80, unsold.

How a sale is built (what a new item must touch):
- `PRICES`, `why_not`, `buy` (`STORE:15,143-190`)
- `ITEMS` row and written-out string keys, which `lang_test` finds (`SHOP:8,12-13`)
- Thumbnail builder (`scripts/game/shop_preview.gd:15-18`)
- Name and note strings (`STR:203-225`)
- Field in `save_layout` (`STORE:104`)
- Validated field in `load_layout` (`STORE:49-65`)

Points are spent after `buy` succeeds (`SHOP:101-108`). All items are permanent, with no resale, except the refund precedent (`STORE:16,57`).

Limits: 6 tanks per species, wild 6 more (`STORE:21`); 3 per species when a second arrives (`BL:23`, `RM:42`, not coded).

### Inferences
- Arithmetic: cheapest full set of 6 tanks = big 1,500 + 4 small 2,400 + 2 shelf2 7,000 = **10,900 points** (first tank free; `small_room` needs 5). At 125-159/h that is roughly 3 days of an open game.
- Under the 6-tank limit, shelf4 is never required, and per place it costs 4,500 against shelf2's 1,750. It works as a points sink, which may not be intended. After the set is filled, enemy release is the only remaining spend.
- Water can match event income early on. At 0.5× default a tank falls below 30% in ~35 real minutes outside founding (arithmetic from `COL:270-273`), so the open colony can claim the hourly 30, more than the 18/h from events at the start.
- These rates predate later duty and growth changes, so a future list should use a fresh run of `--harmony --warm=N --autokeep` (`BL:123`).

### Gaps
- No recent earning measurement exists in the docs. Rates for a 1,000-worker colony are unknown, and PART 0.12 will raise income, since it scales with feeding events.
- Actual purse sizes of players are unknown.

## Save, migration and tests

### Takeaway
Saves are strict and already caught the project out twice, so each new key must be `OPTIONAL` or migrated, and each new nest kind needs its own fuzz case. Two stores matter: the per-colony slot file and the shared `home.json`, which drops unknown fields each time it loads.

### Cited Findings
Save rules:
- `SAVE_VERSION` 11 (`scripts/sim/parts/sim_state.gd:150`). Steps run in `MIG:10-36` after a backup (`scripts/game/main.gd:118-120`). A newer save is played as a scratch colony and not overwritten (`scripts/game/main.gd:113-116`).
- `CHECK` compares each save to one reference colony, made as `setup(1, 14, false, "keeper")` (`CHECK:35-37`). Any key the reference has but the save lacks fails unless `OPTIONAL` (`CHECK:18-21,59-60`). Failing saves are set aside as unreadable and the colony restarts (`scripts/game/main.gd:122-132`).
- `OPEN` dictionaries are type-checked only (`CHECK:26`). Size limits: `MAX_VOXELS` 8 million, `MAX_SIDE` 1024, `MAX_ITEMS` 200,000 (`CHECK:13-15`). `_sizes` trusts voxel arrays (`CHECK:87-106`) and recognises only two box sizes (`CHECK:109-113`), as does `SIM:109`.
- Slot meta: float, String or bool only; anything else is dropped on read (`SAVE:28-29,115-119`). Meta already carries `glass`, `water`, `nest_x0` (`SAVE:66`, `SIM:263-264`).
- `home.json`: max 4,096 bytes (`STORE:14,47`). Rewritten at the end of every load with the fixed field list, **so unknown fields vanish** (`STORE:73,104`). It is global, not per-colony.

Probable new fields (my proposal, none exist):

| Where | Field | Check needed |
|---|---|---|
| `sim.nest` | `kind` (material) | `OPTIONAL`, default "soil" |
| `sim.nest` | `tube`/linked-part data | `OPTIONAL` |
| `sim` | `ch_wet` | `OPTIONAL`, size limit as `SIM:149` |
| `sim` | `equip` dictionary (mat power, tank size) | `OPEN` + `OPTIONAL` |
| slot meta | `nest_kind` string | `META` entry |
| `home.json` | owned items, per-slot fittings, placements | load validation; the 4 KB limit may be tight with build mode |
| `SPEC` | every new size | `tests/tank_spec_test.gd` |

Adding keys in `soil` would need `VOX:534-542` extended. A version bump is only required when old data must be transformed.

Tests that would be affected:
- `tests/tank_spec_test.gd:13-23`: nest block, farm, soil equals nest depth.
- `tests/home_test.gd:44-70`: shop, `nest_of`, exact `places()` output.
- `tests/save_fuzz_test.gd:143-155,264`: nest kinds checked: small, big, garden, glass.
- `tests/save_test.gd:29`: never uses glass.
- `tests/migration_test.gd:48` with `tests/fixtures/save_v1..v10.antfarm`: no v11 fixture.
- `tests/work_left_test.gd:20,75-79`: knows about slab.
- `tests/water_test.gd`: meta water and pay rule.
- `tests/real_saves_check.gd`, `tests/real_save_test.gd`: player's real saves, read-only (`tools/check.ps1:81-85`).
- `tests/lang_test.gd`: shop keys.
- Determinism: `tests/baselines/selftest_w14_s5.txt` (`tools/check.ps1:90-102`). Past work keeps it by giving new draws their own generators (`BASE:236-239,256-257`, `VOX:84-85`) or making draws either way (`COL:42-44`). Baselines only on Windows (LES 11d).

### Inferences
- Default soil colonies must produce exactly the same run with equipment code present, or the baseline must be declared changed.
- Equipment owned at Home level and equipment affecting a colony need a clear rule. While a colony is closed, its catch-up runs only when opened, so anything Home-owned changing a closed colony must be queued, as refills are (`SAVE:124-134`).

### Gaps
- Uncompressed save size for a sparse nest depends on the 0.12 design, not decided (`PLAN:50`).

## Conflicts with PLAN_0.12, the 0.13 plan and LESSONS

### Takeaway
PART 0.12 rewrites the same storage and tank geometry that nest types depend on, so nest materials should be planned after it, or at least designed alongside. PART 0.13 needs a founding container and a move, which neither exists, and it pairs naturally with a test tube. Existing rules require a real sim effect for what is sold, and sizes in `SPEC`.

### Cited Findings
PART 0.12 (`PLAN`, `RM:46-58`):
- Not started (`PLAN:3`). Whole-tank soil at 400 × 250 × 72 and 600 × 375 × 72 voxels, sparse or chunked storage, new shader, routes across the tank (`PLAN:13,50`). Migration by `nest_x0` (`PLAN:51`). 1,000 cap with a proposed laying taper (`PLAN:11,16`). Soil depth undecided (`PLAN:18`, `RM:58`).
- Deep rework on its own branch (`PLAN:21-25`). CLAUDE.md says one PART at a time.

PART 0.13 (`RM:36`):
- Winged queens and collecting a queen for a new colony. Gyne and male constants only (`scripts/sim/ant.gd:13-16`).
- A colony starts only through `setup` with a slot, carved soil and a fixed date (`BASE:31`, `VOX:99-110`).
- Slot supply is limited (`STORE:21`), which a collected queen must fit into.
- PART 0.15 lowers it to 3 per species (`BL:23`).

Rules in force:
- `LES:205-206` 11i, `docs/SPECIES.md:32`: everything the player sees must exist in the sim; the view only draws it.
- `LES:195-199` 11e (tank_spec): all sizes in `SPEC`, tested. (The number 11e is used twice in `LES`: also `:221`.)
- `LES:257-262` 21 and `LES:305-309` 30: new keys `OPTIONAL`; a new colony kind means a new fuzz case.
- `LES:235-240` 15: new `user://` files only by safe readers.
- `LES:31-32` 3d, `LES:134-136` 4: compare before/after, tended and alone, several seeds, multi-year.
- `LES:36-39` 3f: test speed with colonies that grew for real.
- `LES:157-159` 8d: small chambers need checks with queen alone and large colony.
- `LES:217-219` 11f, `LES:213-215` 11g, `LES:333-336` 35: press every button; deep features need asking first (the wall screen was removed after being built).
- `docs/WORKFLOW.md`, LES 13: files ~500 lines; `BASE` 540, `VOX` 548, `COL` 506 are already over.

### Inferences
- **Storage conflict:** `rho[...]` is read directly in 25 lines across 7 files. Step 5 of `PLAN` will likely change this. Nest kinds built before it would be built twice.
- **Purpose conflict:** with soil across the whole tank, the add-on's space argument (`BL:106`) weakens. What remains for it is viewing and a second chamber. Worth revisiting with the user.
- **Identity conflict:** a tank "full of soil" and a plaster or acrylic nest are different enclosures. The foraging box's soil floor (`SPEC:9-10`) cannot be assumed once a nest is an object next to the box. The nest-to-floor link (`scripts/view/outworld/parts/outworld_scene.gd:323-331`, `SAVE:66`) would need redefining.
- **Cap interaction:** the 0.12 laying taper and a fixed nest's cramped factor (`COL:343`) would multiply unless designed together.
- **0.13 fit:** founding has no food needs (reserve model, game_model_audit "Founding"), so a tube matches well. It requires a no-outworld or closed mode, since `setup` always makes fields, plants and an open entrance (`BASE:20-22,80-87`), and `scenario` is branched on in 25 lines of `scripts/sim`. It then requires a move from tube to tank, currently absent.
- **11i applied:** the tray props, the queen in a tube and the scenery already sit outside the rule's spirit, tolerated as room dressing. Selling an item with no sim effect should be labelled decoration. Selling plaster or a thermometer needs a real effect (a thermometer could be a HUD gate, which today shows values for free).
- **Ordering, my view:** moisture per material and mat settings could come before 0.12 since they do not touch voxel storage. Nest kinds and tube come after 0.12. A test tube belongs with 0.13.

### Gaps
- There is no written plan for 0.13 beyond one roadmap line (`RM:36`), and `PLAN_0.13` does not exist (Glob of `docs/**/*.md`).

## Prior notes in the docs, and disagreements with code

### Takeaway
Equipment is mentioned only in scattered notes, and no doc plans an equipment system. Plaster appears only in passing, and test tubes only as a prop. Several notes disagree with the code, most importantly on what an ant farm colony gets for foraging.

### Cited Findings
Search: regex `ปูนปลาสเตอร์|ปูน|plaster|ytong|acrylic|อะคริลิก|test.?tube|หลอดทดลอง|หลอด|ท่อ|\btube\b|ของตกแต่ง|decor|อุปกรณ์|equipment|gear|thermometer|เทอร์โม|Fluon|ฟลูออน` over `docs/**`, `CHANGELOG.md`, `lang/strings.csv`, plus reads of `BL` lines 1-194 and 420-467. `BL` lines 195-419 and most of `CL` were seen only through search hits.

Notes found:
- Decoration shop post-EA: `BL:142` (bean plant, stones, dry leaves, twigs, mossy rocks, in keeper tanks only, before starting). `BL:444-445` (player 2026-10-24; reuse `garden_layout.gd`, `scenery_draw.gd`). Estimate 3-5 days: `BL:143`. Public: `docs/release/STORE_PAGE.md:129,226`.
- Ant farm add-on: `BL:106-109`, `SHOP:9-11`, `CL:563`, `docs/release/STORE_PAGE.md:128,225`.
- Tools on desk: `BL:78-80`, `CL:258-259,283-286`, tagged keepers' forums and guides, not study. Fridge design: `FRIDGE:2-5`.
- Stones in tanks affecting foragers: `BL:446`. Climbing litter: `BL:427`. Prey burial effect: `BL:427,462`.
- Per-point moisture: `BL:426`. Moist soil look: `BL:459`. Glass fog in the fridge: `BL:433`.
- Mixed scene: `BL:467`. Urban scene: `BL:463-465`.
- Plaster: only `COL:279`, and casts used by researchers (`docs/BIOLOGY.md:64,93`). Ytong and acrylic: absent from docs and code. Test tube or founding tube: `TOOLS:4-5,100-125`, `CL:284` (prop only).
- `docs/SPECIES.md` and `docs/ARCHITECTURE.md` have no equipment plan. ARCHITECTURE records farm and tank layout (`docs/ARCHITECTURE.md:122,127`). `docs/release/ROADMAP_PUBLIC.md` grep for ant farm, decoration, room, queen found nothing in the terms searched.

Disagreements:
1. **Ant farm foraging.** `SHOP:9` and `BL:106` say a farm has next to no foraging floor. In code a farm colony gets a full 60 × 37.5 cm box: `BASE:12` ignores `glass_nest`, `scripts/game/main.gd:147`, and `scripts/view/outworld/keeper_room.gd:35` ("it has no box of its own: a small tank's"). The Home draws a thin frame (`KIT:376`). So the sim and picture differ, a LES 11e/11i case.
2. **Small tank price.** `BL:125`, `CL:736,763` say 100. Code says 600 (`STORE:15`, changed at `CL:125`).
3. **Farm price note.** `STORE:30` "a little cheaper than a small tank", now 80 against 600.
4. **Price basis.** `BL:125-126` says times assume a new colony. The times given (~1,500 in half a day, 18,000 in 5 days) imply about 125-150 points/h, which is the year-2 rate, not a new colony's 18/h (arithmetic).
5. **Fridge temperature.** The door reads "8°C" (`FRIDGE:18`), the sim goes to 6.5 C (`CLIM:12`). The label is fixed text, not a live value.
6. **Room arranging.** `docs/release/STORE_PAGE.md:130` says "not decided yet"; `RM:40` and `BL:144` say decided 2026-11-05. The itch text may be out of date.
7. **Sealed cell.** `COL:281` calls a founding cell sealed, with an open shaft at `VOX:101-106` (already in the earlier audit). It matters for a tube design.
8. **Plaster comment.** `COL:279` mentions plaster though no plaster exists.
9. **Roadmap controls.** `RM:10` says the player can adjust temperature and humidity (already in the earlier audit). Mat, fridge and water only.
10. **Heat mat button** state after loading, under Moisture and temperature.

### Inferences
- Because STORE_PAGE already names the ant farm extension and decorations publicly, those two carry a community expectation, while plaster, acrylic and test tubes carry none yet.

### Gaps
- Not searched: `shots/`, `reports/`, `reference/`. Sibling research notes on husbandry exist in the earlier folder and were not used for claims here.
