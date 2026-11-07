# What the AntFarm game actually simulates: husbandry and biology audit of Lasius niger

Audit of code at git `76fa065` (v0.11.93, the in-store build is v0.11.88), 2026-11-06. The game was not run, so nothing here is a fresh measurement. Population figures are copied from the project's own records. Paths are relative to `E:/AntFarm`.

Shorthand for files:
- `LN` = `scripts/sim/species/lasius_niger.gd`
- `COL` = `scripts/sim/parts/sim_colony.gd`
- `BASE` = `scripts/sim/parts/sim_base.gd`
- `WARM` = `scripts/sim/parts/sim_warmth.gd`
- `DUTY` = `scripts/sim/parts/sim_duties.gd`
- `FOR` = `scripts/sim/parts/sim_foragers.gd`
- `ENEMY` = `scripts/sim/parts/sim_enemies.gd`
- `STATE` = `scripts/sim/parts/sim_state.gd`
- `CLIM` = `scripts/sim/climate.gd`
- `FOOD` = `scripts/sim/food_kinds.gd`
- `SIM` = `scripts/sim/simulation.gd`
- `BIO` = `docs/BIOLOGY.md`
- `BL` = `docs/roadmap/BACKLOG.md`
- `CL` = `CHANGELOG.md`
- `STR` = `lang/strings.csv`

Evidence tags are the project's own, from `BIO:234-235`:
- [Ln] = study of L. niger
- [relative] = other ants
- [keeper] = keepers or forums
- [inference] = the developer's assumption

"Arithmetic" under Inferences means I worked it out from code constants and did not observe it in a run.

Time scale: 3600 ticks = 1 game day = 60 s at 1× (`STATE:17`). Default speed is 0.5×, and the HUD offers 0.2-5× (`scripts/game/parts/main_base.gd:49`). Options while the game is closed are off, 1/24, 1/6, 1 or 4 game days per real hour (`scripts/game/save_store.gd:11-17`), capped at 120 game days per absence (`save_store.gd:18`).

## Life cycle

### Takeaway
Three brood stages run on a piecewise-linear temperature curve with no brood deaths from cold. Adults and brood can die of starvation, dryness, mould, heat, old age (workers only) and foraging or enemy losses. The queen does not age: she dies only of starvation or thirst. After her death there is no replacement and no worker-laid eggs, so the colony dwindles.

### Cited Findings
- Egg 10 d, larva 13 d, pupa 11 d at optimum (34 d total): `LN:32-34`. BIO: keeper plus Wikipedia ranges of 9-16, 9-14 and 9-12 d at ~25 C, tagged [keeper + Wikipedia]; BIO itself calls the game "in range but rather fast" (`BIO:238-239`).
- Development rate: 0 below 13 C, linear to 1.0 at 28 C, 1.0 up to 33 C, linear to 0 at 38 C: `LN:35-38`, `WARM:29-36`. The 13 C stop is stated in `BIO:13`. Temperature affecting L. niger brood time is tagged [Ln] (`BIO:105`), but I found no cited source for the exact curve.
- Each egg, larva and pupa develops at its own chamber's temperature: `COL:375,408,434`, `WARM:63-64`.
- Larval growth also needs feeding. A larva grows only in half-hours it was fed (`COL:407-408`, `DUTY:88-129`). Each feeding round, one nurse feeds 6 larvae, tagged "no figure for L. niger" (`DUTY:14`, `LN:52`).
- Diapause cap: larval progress stops at 0.95 late in the year or in the fridge (`COL:402,409-410`).
- Callow: 3 d, as a task state only (`LN:49`, `COL:100-102`). Pale colour is a view value (`LN:87`). Callows count toward larval care (`COL:116`, `DUTY:95`).
- Worker lifespan: uniform 300-700 d × colony trait 0.82-1.2 (`LN:47-48`, `BASE:132,259`). Tagged [inference] for between-colony variation (`STATE:135`, `BIO:227-228`).
- `BIO:266` records [Ln] first-brood workers at about 430 d expected and 1,129 d maximum, and says the game's maximum is too low. Raising it is queued (`BL:223`).
- Ageing slows in the cold: age rate 0.35-1.0, full at 24 C nest temperature (`COL:83,94`). No source is cited in code for this.
- Queen lifespan: absent. `queen` holds alive, starve, reserve, name, plus rested and dry (`STATE:58`, `BASE:34`, `COL:329`). The only assignment of `queen.alive = false` is `COL:331`, reached on starvation or thirst.
- Search method for the above: grep for `queen.alive`, `queen_died`, and reads of all of `COL` and `BASE`.
- A player colony was recorded at game year 35 with 114 workers (`CL:1377`), consistent with no queen ageing. The species page still quotes "almost 29 years" (`STR:135`, `LN:15`). `BIO:265` tags this [Ln, single record].
- Queen death thresholds: unfed for more than 12 d (`LN:67`, `COL:330`, the counter scaled by cold factor at `COL:328`), or nest humidity below 0.1 for more than 18 d (12 × 1.5, `COL:329-330`).
- After queen death: `_queen` returns early (`COL:326-327`), so no eggs are laid. The journal says "With no new eggs the colony will slowly dwindle away" (`STR:18`). The HUD shows dead status (`scripts/view/ui/hud.gd:175`).
- Worker reproduction after queenlessness, adoption and replacement queens: absent. I grepped `scripts/` for gyne, nuptial, supersed and similar terms, and read `_queen` and `_brood`.
- Worker death causes in the code: starve, thirst, old, out (lost foraging), enemy (`STATE:77`, `COL:255-259`).

### Inferences
- Arithmetic: at the default room, nest mean is 0.45×22 + 0.55×24 = 23.1 C (`CLIM:63`), so development rate is 0.67 and egg-to-worker takes about 50 d. With the heat mat, 27.6 C gives rate 0.97 and about 35 d. These do not include food limits or chamber offsets.
- Nothing in the model separates queen fertility decline from age. The `rested` factor is the only long-term laying modifier.

### Gaps
- No code path or doc gives a source for the 28, 33 and 38 C values specifically. `LN:31` only states them.

## Founding

### Takeaway
Founding is modelled as a reserve budget of 90 units × queen trait. The queen spends it on herself and on larvae above a floor of 20. "Sealed" is narrative: the geometry has an open shaft and no seal state. The player cannot help or harm founding except through water, heat and fridge. First workers appear in about 7 weeks.

### Cited Findings
- Start: lone queen on day-of-year 205 (late July), 3 eggs, reserve 90 × trait 0.78-1.25 (`BASE:31,75-77,258`, `LN:79-81`). Heavier queens raising more brood is tagged [Ln] Fjerdingstad & Keller 2004 (`BIO:221-223`, `STATE:132`). The 90 itself is uncited.
- Alternative start: "A 3-month-old colony" with a queen, 14 workers, and 9 eggs, 7 larvae, 4 pupae, in mid-April (day 105) (`BASE:31,60-66`, `STR:340-341`, `main.gd:144`).
- Queen reserve spending:
  - Own need 0.5 food units/day × cold factor, taken from the reserve without limit (`LN:62`, `COL:206,212-214`)
  - Larvae from the reserve only above `QUEEN_KEEP` 20 and while workers < 5 (`COL:5,390-395`)
  - Eggs are free of the reserve while it is above 20: `yolk` is forced to 3.0 (`COL:345`)
  - Workers are fed from her reserve while under 5 workers (`COL:224-228`)
  - A queen feeds up to 15 larvae per round, falling to 0 at 15 workers (`DUTY:15,106-111`)
- Founding laying rate: base 3 eggs/day × development × brood-room factor, where room = 1 − brood/(12 + 2.5·workers) (`LN:57`, `COL:339-346`). So eggs plus larvae saturate at 12 with no workers.
- Docs tag wing-muscle and fat use, and trophic eggs or saliva, as [Ln] Janet 1907 (`BIO:249`). Code comments call the reserve transfer "trophic eggs, saliva" (`COL:391`), but no trophic-egg object exists.
- `founding()` is true when the queen is alive, workers < 3 and reserve > 0 (`BASE:114-115`). Its effects: water loss × 0.3 (`COL:271-272,284-285`) and HUD text.
- Journal: "The first worker takes about 6-8 weeks" (`STR:4`). Species page: 6-10 weeks, [keeper + Wikipedia] (`STR:143`).
- Recorded simulation: 2 seeds started 25 July had 2-5 workers by mid-September, and laying resumed in May (`BL:24`, wild, alone).
- Nanitics: yes, by formula, not by a founding flag. Adult size = (0.76 + 0.16·fed + 0.1·min(workers/150, 1)) × trait + noise, clamped to 0.7-1.15 of 4.2 mm (`BASE:108-110`). Larvae start at fed quality 0.6 (`COL:379`).
- `nanitic_size` (mean 0.8, range 0.72-0.9) is read only for workers of the 14-worker start (`LN:82`, `BASE:57-58`). `BIO:268` tags small first workers [Ln].
- Early foraging: with under 8 workers, foragers start at callow age, 3 d (`COL:80-81`).
- Player during founding: `place_food` has no founding check (`BASE:301-312`), but no ant can collect the food until workers exist. The queen never forages (`COL:325-370` has no such path), and `sugar` starts at 0 (`BASE:67`). So water, heat mat and fridge are the only actions that reach her.
- The doc tags "claustral queens fed regularly raise more pupae and workers" as [Ln], flagged uncertain (`BIO:325,374`). Nothing in the code implements queen feeding.
- Geometry disagreement: the journal says "sealed herself in" (`STR:3`), but `scripts/sim/parts/nest_voxels.gd:101-106` carves an open shaft from the entrance to a chamber ~1.8 cm across.
- Pleometrosis: absent in code. `BIO:271` records it as [Ln].

### Inferences
- Arithmetic: a larva costs 13 × 0.25 = 3.25 protein units at full feeding, because cost and growth both scale with development. About 50 d of queen upkeep at 22-23 C costs ~25 units. So about 45 of the 70 spendable units remain, enough for about 14 larvae with an average queen.
- Founding queen death from reserves looks unlikely. `COL:212-214` keeps her "fed" until the reserve hits zero, and her winter burn is low.

### Gaps
- I found no recorded first-brood worker count at the moment of first emergence, only the 2-5 figure above.

## Colony growth

### Takeaway
Laying has a nominal maximum of 30 eggs/day (× queen trait) but is multiplied down by temperature, brood space, nest volume, food stock and sugar income. There is no population cap in the simulation. Recorded colonies reach about 200-390 in a tended tank by the end of year 2 and about 40-130 outdoors. The 1,000 cap is only planned.

### Cited Findings
- Base rate: min(30, 3 + 0.4·workers) × queen trait (`LN:56-58`, `COL:339`). The nominal maximum is reached at about 68 workers.
- Multipliers (`COL:342-362`):
  - Development at the queen's chamber
  - Protein: yolk/3, clamped 0-1
  - Room: brood factor above × nest air/target, clamped 0.3-1
  - Winter rest: 0.35 + 0.65·rested
  - × 0.3 if humidity < 0.35
  - 0 when winding down outdoors with at least 5 workers
  - Stock: (sugar + fat)/(half of caps), clamped 0.1-1
  - Income: (sugar_income/weekly upkeep − 1)/0.5, clamped 0.05-1
- All laying stops if `starving` (`COL:337-338`). × 0.9 if the queen is unattended, stated as "the keeper's choice: no evidence either way" (`STATE:140`, `COL:363-364`, `BIO:353-354`).
- An egg costs 0.05 protein (`LN:65`, `COL:369`).
- The food-regulated growth rule is the doc's explanation for hundreds rather than thousands (`BIO:144-145`). Whether that matches real colonies is not sourced; it is a modelling decision (`CL:2086`).
- Population records (latest `year_run` balance table I found is v0.11.20):

| Source | Setup | Result |
|---|---|---|
| `docs/roadmap/DONE.md:8` | tended 1 year, early version | 14 → 78-298 |
| `CL:2087` (v0.7.1) | tank, fed, year 1 | ~250 |
| `CL:2112` (v0.7.0) | wild lone queen, year 3 | ~130 |
| `CL:1865` (v0.8.19) | wild alone, 4 seeds | end Y2 40-85, Y3 ~100 |
| `CL:1834` (v0.8.22) | 3 years, 2 seeds | keeper Y3 ~240-360, wild ~100-140 |
| `CL:1276` (v0.11.2) | wild 14 workers alone, 1 year, 4 seeds | no enemies 58-68, 100% 46-80, 300% 19-58 |
| `BL:410-412` | keeper seed 5, 2 years | enemies 100%: ~66-79, none: ~100-119 |
| `CL:1198-1200` (v0.11.8) | keeper tended day 420, seeds 1-5 | 259/159/159/218/203 |
| `CL:1200` (v0.11.8) | wild alone, no enemies, day 300 | 60/74/98 |
| `CL:1057` (v0.11.18) | 2 years, 4 seeds | keeper 207-431 (mean 279), wild 52-144 (99) |
| `CL:1037-1038` (v0.11.19) | 2 years, 4 seeds | keeper 192-528 (314), wild 34-107 (76) |
| `CL:1020-1021` (v0.11.20) | 2 years, 4 seeds | keeper 200-389 (270), wild 42-128 (101) |
| `CL:859` (v0.11.31) | wild, forced start at 400, 1 year | 480-620 |

- Player colonies are smaller than tests in some records: year 11 with 88 workers (`CL:1402`), year 35 with 114 (`CL:1377`), year 4 ~148 (`BL:161`), and a 368-worker colony (`docs/roadmap/PLAN_0.12.md:41`).
- Current cap: absent in the simulation. Grep for `MAX_WORKERS|MAX_ANTS|max_workers` in `scripts/sim`, `scripts/game` found nothing. The view draws at most 250 workers in the nest (`scripts/view/nest/parts/nest_bind.gd:34`, `BL:147`).
- The planned cap of 1,000 total is decided but not started (`docs/roadmap/PLAN_0.12.md:3,11`). A taper near the cap is proposed and is a game-design choice (`PLAN_0.12.md:16`).
- Real size figures in docs: 4,000-7,000, up to ~40,000 [Wikipedia] (`BIO:267`); up to ~10,000, in good cases ~70,000 (`BIO:66`).

### Inferences
- Free food sets the keeper plateau (see Food). Arithmetic: two aphid plants produce about 12 sugar loads a day, which at 0.08 per worker supports about 150 workers at room temperature, before honey.
- Year-by-year growth past year 3 is not recorded by tests, and the player colonies suggest long-term plateau or decline. I did not establish why.

### Gaps
- No recorded long `year_run` (more than 3 years) in the docs I searched. The CHANGELOG search was regex-based, so a table written in other wording could have been missed.

## Temperature and humidity

### Takeaway
The player cannot set a temperature or humidity. Controls are a heat-mat on/off, a fridge on/off, and an "Add water" button. Too dry kills brood and eventually adults. Too wet only triggers mould on brood and stored protein. Heat kills brood in code, but the branch looks unreachable with the default climate. Nothing dies directly of cold.

### Cited Findings
- Player controls, keeper mode only: water, heat mat, fridge (`scripts/view/ui/parts/hud_controls.gd:325-356`). Water can also be filled from the Home water panel (`scripts/game/home_water.gd:137`). Wild mode hides all three.
- Room: daily mean drifts within 14-29 C around 22 (`CLIM:10,50`), with daily amplitude 4-8 C (`CLIM:51`).
- Nest target = 0.45·air + 0.55·24 (+4.5 with mat), blended toward 6.5 by fridge (`CLIM:9-12,63-64`).
- Nest lag time constant is 0.08 day (`CLIM:83`).
- Heat mat also warms lower chambers relative to upper ones, spread ±(z/zmax − 0.4)×4.5×1.2 (`WARM:48-49`).
- Heat mat water effect: k + 0.06 (`COL:270`). There is no thermostat or overheat setting.
- Wild climate: air 0-19 C seasonal (`CLIM:32-35`), soil 3-20 C (`CLIM:40-42`), and nest = 0.35·air + 0.65·soil + sun × 9 × seasonal factor (`CLIM:62`). `BIO:130-131`. Chamber depth damping D = 8 cm, tagged soil physics, Hillel 1998 (`WARM:15`, `BIO:100-101`).
- Moisture, keeper mode (one nest-wide value 0-1, no per-chamber humidity; a per-point model is a backlog idea, `BL:426`):
  - While the tank has water, humidity relaxes to 0.72 at rate 0.6/day (`COL:286-288`)
  - Tank empties in 25 d at the base rate, "chosen with the user" (`COL:265,282,269-273`)
  - Use rises with heat mat and workers (+0.0002 per worker) and × 0.3 while founding (`COL:270-272`)
  - Empty tank: humidity × exp(−k·dt), k = 0.09 baseline (`COL:290`)
  - Each fill sets water to 1.0 and adds 0.2 humidity (`BASE:315-317`)
- Water use has no temperature term, so the tank drains at the same rate in the fridge (`COL:269-273`).
- Moisture, wild: ground target 0.5-0.75, drying, rain soak, and drainage above 0.8 (`COL:313-322`). Rain 14% of days, 0.15-0.4 day long, outdoors only (`COL:44-48`).
- Food adds humidity up to 0.8: +0.004 per sugar load, +0.002 per prey (`FOR:429-430,437-438`).
- Too dry:
  - Below 0.35: daily egg loss (0.35 − h)×2, larvae half of that, pupae none (`LN:71`, `COL:293-296`), and laying × 0.3 (`COL:347-348`)
  - Below 0.1: workers lose 1/6 energy per day ÷ hardiness 0.5-1.6, then die of thirst (`COL:246,250-255`, `BASE:133`); the queen dies after 18 d (`COL:329-330`)
- The 0.35, 0.9 and 0.1 thresholds and the loss rates have no cited source. `LN:70` only describes the range, and `BIO:285` says only that the species prefers moist but not wet soil [Ln ecology + keeper].
- Too wet: above 0.9, mould counter +1/day (decays 0.5/day below 0.9). Above 2: larvae −15%/d, pupae −10%/d, stored protein × 0.85/d (`LN:72`, `COL:298-306`). Adults, eggs and the queen are unaffected. Flooding or drowning is absent.
- Too hot: if nest temperature is above 36 C (lethal − 2), brood in chambers over 36 C die at 40%/day (`COL:452-460`). Adults have no heat death.
- Too cold: no death. Food burn falls by Q10 2.5, with a further torpor reduction below 8 C (`BASE:215-219`, `BIO:132`, general knowledge). Foraging stops below 8 C (`LN:41`, `COL:53-55`). Grep for `freez|frost` in `scripts/sim` found only a climate comment. Frost exists only as a ground shader (`outworld_scene.gd:461-470`).
- Foraging curve: 8 / 22 / 32 / 40 C (`LN:41-44`). `BIO:133` gives ~8 C, untagged.
- Mould has no visual. Grep of `scripts/view` and `scripts/game` for `.mold` found nothing, so the player learns about it only from the journal warning (`STR:17`).
- Warning text mismatches: the heat warning says larvae (`STR:22`) but code kills eggs, larvae and pupae (`COL:455`). The low-humidity warning says eggs (`STR:14`) but code also kills larvae (`COL:296`).

### Inferences
- Arithmetic: tank plus drying means about 25 d until empty, about 8 d more to reach 0.35, and about 22 d after empty to reach 0.1 (at k = 0.09).
- Consistent with this, `DONE.md:8` reports unattended early colonies collapsing in ~75 days, with drying as the cause (an early version, so the timing may have changed).
- Arithmetic: mould appears reachable indoors only by repeatedly clicking "Add water". One click from 0.72 stays above 0.9 for about 0.18 d; from 1.0 about 0.74 d. So staying wet long enough takes about 3 or more fills within 2 days. Outdoors, soak and drainage balance near 0.875 in rain, below the 0.9 threshold.
- Arithmetic: maximum indoor nest is about 34 C (air 37, mat on). Maximum wild is about 34 C. Both are under the 36 C gate at `COL:453`, so heat death looks unreachable without a code or climate change. Development will slow above 33 C.

### Gaps
- Not established by a run. Rare weather stacking or the `temp_at_cm` chamber offset cannot pass the gate because the gate reads `climate.nest`, but I did not test it.

## Hibernation

### Takeaway
Indoors, hibernation is an optional fridge button that ramps to 6.5 C over a week. Six weeks below 10 C resets a queen "rested" value. Skipping it causes no deaths, only laying decline to 35% over 300 days. Outdoors it happens automatically with the climate. Diapause larvae exist as a progress cap.

### Cited Findings
- Fridge: target 6.5 C (`CLIM:12`), ramp 1/7 per day in and out (`COL:10`). The Home fridge holds two tanks (`hud_controls.gd:349-353`). Docs cite 5-8 C keeper practice (`BIO:140`), and the Home fridge cites forum threads (`scripts/view/home/home_fridge.gd:2-5`).
- Rest rule: nest < 10 C adds 1 to `cold_days`, and at exactly 42 days `rested` = 1.0 (`COL:14-20`). Above 14 C the counter resets (`COL:22-23`). `BIO:139` says "game uses" 6 weeks, phrased as a game choice. Partial cold gives no partial benefit.
- Skipped: `rested` falls by 1/300 per non-cold day (`COL:24-25`), warning below 0.5 (`COL:26-27`, `STR:49`), floor effect laying × 0.35 (`COL:346`). No effect on workers, lifespan or brood survival.
- Hint: on 1 November in keeper mode, if not in the fridge (`COL:11-12`, `STR:48`). The season dates differ between texts: Nov-Feb (`STR:48`), late Oct-early Mar (`STR:142`, `BIO:286` [keeper]).
- Keeper mode has no photoperiod (12 h constant, `CLIM:97`) and no automatic slowdown outside the fridge.
- Outdoors, automatic: laying stops once days are under 13.5 h after day 172, about late August (`BASE:435-437`, `COL:349-350`, `BIO:134`). `hibernating()` is seasonal mean < 9 C and nest < 12 C (`BASE:206-209`). Queen and brood move to the deepest chamber in winter, tagged [inference] (`WARM:95-99,111-113,127`, `BL:163-165`).
- Fat: up to 2.2 units per worker, "a winter's worth" (`BASE:441-442`). Stored from surplus (`COL:240-245`). `BIO:134-135`.
- Diapause larvae: progress cap 0.95 when `winding_down()` or `fridge_on` (`COL:402,409-410`); hunger suspended by cold (`COL:403,411`). `BIO:136` states this, while `BIO:287` says overwintering as larvae is unconfirmed and comes from keepers.
- Larvae in a mat-warmed box, outside the fridge, have no diapause (`COL:402`).
- Outdoors with low activity is reported as an open player complaint, with a founding queen's nest near-idle to April-May, unconfirmed as a bug (`BL:24`, `PLAN_0.12.md:8`).

### Inferences
- Arithmetic: about 6 days of ramp to reach 10 C, so 42 cold days takes about 48 days after pressing the button.
- Arithmetic: food burn at 6.5 C is about 0.19 of room rate (`BASE:215-219`). At that temperature the outworld is inactive (surface below 8 C, `COL:53-55,77`), so stores must carry the colony.
- Water still drains in the fridge, so a keeper must refill about every 25 days during a 6-week rest. Whether this is intended is not stated.

### Gaps
- No doc source gives the 6 weeks or the 300-day decay as L. niger measurements. `BIO:139` gives no citation.

## Food

### Takeaway
Only two foods are placeable: a honey drop and a dead cricket. Every keeper tank also gets two free self-renewing aphid plants and free dead flies, so ants can live without being fed. Food is colony-wide pools (sugar, protein, fat), not per-ant. Overfeeding has no penalty, rot only hides food from foragers, and old food disappears by itself.

### Cited Findings
- Placeable tools: honey and cricket only (`FOOD:48-54`, tool entries at `FOOD:26,28`).
- Other kinds: aphids, fly, and enemy carcasses (`FOOD:21-22,30-40`). Sugar water, fruit, seeds and other insect feeders: absent from the `KINDS` table.
- Loads and decay (`FOOD:21-40`, `COL:468-483`):

| Food | Type | Loads | Renewal or decay |
|---|---|---|---|
| Aphids | sugar | 10, cap 16 | +9/day × (0.4 + 0.6·light) × season |
| Honey | sugar | 25 | × 0.78/day; removed at 9 d |
| Cricket | protein | 30 | rotten after 6 d; removed at 9 d |
| Fly | protein | 6 | rotten after 6 d; removed at 9 d |
| Dead spider / beetle / centipede | protein | 18 / 22 / 16 | rotten after 6 d; removed at 9 d |

- Free food indoors:
  - 2 aphid plants at setup in every scenario (`BASE:80-84`)
  - An aphid plant nearby too, outdoors only (`BASE:88-93`)
  - One dead cricket at start (`BASE:85-87`)
  - Dead flies at 0.8/day indoors, 3/day outdoors (`COL:491-495`). `CL:2085` says about 4×.
- `season_life()` is 1.0 indoors all year because `season_mean` returns 22 (`BASE:200-201`, `CLIM:32-35`), so indoor aphids and flies also continue during the fridge rest.
- Consumption per day (`LN:61-65`), scaled by `cold_factor`: worker sugar 0.08, queen sugar 0.5, larva sugar 0.04 and protein 0.25 (× development clamped 0.1-1, per larva fed), protein 0.05 per egg. Pupae do not eat ([general knowledge], `BIO:246`). Adults need no protein. The numbers are not attributed to any study.
- Starvation: workers 7 d ÷ hardiness (`LN:66`, `COL:249`), queen 12 d, larva hunger over 3 d leads to cannibalism (`LN:68`, `COL:420-431`). Cannibalism: at most one larva per 0.15 d, yields 0.3 protein. Queen fed first (`COL:204-216`).
- Who eats what:
  - Liquid or solid distinction is not simulated
  - Docs tag adults swallowing only liquid as [relative] (`BIO:244`) and solid digestion by larvae as [relative] (`BIO:245`)
  - Larva eggs-as-food is [Ln] (`BIO:247`), absent in code
  - Foragers take only what is wanted, under 95% of cap (`SIM:37-38`, `FOR:132`)
  - Per-ant crops are absent, a known gap (`BL:407,457`). `sweet` is social-animation state with a small energy effect (`DUTY:18-19,172-219`)
- Stores: sugar cap 10 + 2.5/worker; protein cap 6 + 1.2/larva + 0.3/worker; both capped on delivery (`BASE:445-450`, `FOR:427,436`). Stored protein decays 8%/day (`COL:203`). No nest food-storage chambers, per `BIO:25`.
- Overfeeding: no penalty. `place_food` has no count limit or cost (`BASE:301-312`). Excess goes to fat or is left alone.
- Rot: only a flag. Foragers ignore rotten items (`FOR:35,133`). It causes no health effect, no mould, no smell, no pests. Removal is automatic at 9 d, unless ants are still at it (`COL:483`). `outworld_props.gd:50` shows its look follows the rotten flag. Burying prey is visual only (`BL:427,462`).
- Water for ants: no drinking source object. "Thirst" is purely nest humidity under 0.1 (`COL:246-255`). Sugar loads add humidity (`FOR:429-430`). The player's water is a tank abstraction wicking into soil (`COL:279-282`).
- Rates: drinking at honey lasts 23-51 s (real time at 1×), from Mailleux et al. 2009, [Ln] (`FOOD:23-25`, `BIO:252-254`). Because 1× is 60 s per game day, that same drink is 9-20 game hours on the simulation clock. Honeydew handling is still 1-2.3 s (`BL:284`).
- Auto-care: when the game is closed (default on, `main_base.gd:194`), every 3 days 1 + workers/40 crickets, plus honey when sugar is under 30% of cap, and water when empty or below 0.45 (`SIM:270-282`). In-game the keeper does this manually, and low-food warnings exist (`SIM:239`, `STR:473`).

### Inferences
- Arithmetic: 2 plants at average light produce about 12.6 sugar loads a day, feeding about 150 workers at 22 C. Flies supply about 4.8 protein loads a day, feeding about 19 larvae at optimum.
- So an untended keeper colony's main risk is water, not food (`DONE.md:8` supports drying as the failure path in early versions).
- The `CL:1058` note reports honey intake capped ~12 units/day for 100 workers after handling time was made realistic, and `BIO:254` says aphid handling was not updated.

### Gaps
- No source found in docs for overall sugar versus protein ratio: `BIO:250` states "no figures yet".

## Hygiene and disease

### Takeaway
Corpse carrying and a midden exist and mould exists as one global counter. Latrines, pathogens, mites, parasites and any health cost from dirt are absent. Corpses and rotten food have no consequence, and they clear by themselves. The player has no cleaning action.

### Cited Findings
- Exists:
  - Undertaking: while `corpses_inside > 0`, a 50% chance each colony tick (every 20 ticks) of sending an eager idle worker (`COL:118-123`, `FOR:168-177`)
  - Midden 110-140 px (5.5-7 cm) from the entrance (`BASE:241`)
  - Empty cocoons carried out as a view-only effect (`scripts/view/nest/parts/nest_lifecycle.gd:715-726`)
  - Grooming as a duty, count only with no health effect (`DUTY:45-46,63-64,70-80`, rates from Bueno et al. 2026 [relative], `BIO:330`). `BIO:346` says "count only".
- Mould: only `COL:298-308`, see above. Not linked to food, corpses, or any place.
- Corpses: `corpses_inside` appears only at `BASE:485`, `COL:119,123` and save code, so it has no effect on health. Outdoor corpses fade at 30 d and are capped at 250 (`COL:499-503`).
- Absent:
  - Latrine: `BIO:257-258` records the Czaczkes et al. 2015 [Ln] finding and marks the game "not yet ✗". Grep for toilet, latrine, ส้วม in `scripts/` found none.
  - Disease and fungus: `BIO:261-262` records Metarhizium [Ln], "game: no disease ✗". Grep for metarhizium, pathogen, disease in `scripts/` found none.
  - Parasites: `BIO:290-293` lists Pseudacteon, Microdon, Hybrizon, L. umbratus, L. mixtus, Plebejus argus; "no parasites/disease ✗". Grep for parasit found none.
  - Mites as pests: grep for `mite` in `scripts/` found none. `BL:460` mentions springtails and mites only as a soil-fauna and prey idea.
  - Cleaning: no tool for clearing corpses, midden or tank. The tools are honey, cricket, stone, take stone, wipe scent (`outworld_view.gd:249-259`, `STR:388-391`).
- Roadmap status: `BL:223` queues latrine, worker lifespan ~1,100 d, trophic eggs, foraging switch at ~75 workers and aphid predators, then a "disease/parasites" part. These lines sit under an older status heading (2026-10-16). The current plan table in `docs/ROADMAP.md:31-38` and `PLAN_0.12.md` lists no disease or parasite part.

### Inferences
- The midden is decorative for biology purposes. Nothing reads it apart from undertaker destination and view.

### Gaps
- None material.

## Enclosure

### Takeaway
Three settings exist: a soil-block tank, a thin glass ant farm, and an outdoor plot. The dug soil is one small central block. Ants cannot escape, so the Fluon band is visual, and moving a colony, connecting extensions and cleaning are absent.

### Cited Findings
- Tank foraging floors: small 60 × 37.5 cm, big 90 × 56 cm (`STATE:18-19`, `scripts/view/common/tank_spec.gd:14-15`). Glass height 20 and 27 cm (`tank_spec.gd:18-19`).
- Diggable nest:
  - Soil block 9.6 × 9.6 × 10.8 cm, 64 × 72 × 64 voxels at 1.5 mm (`tank_spec.gd:16`, `scripts/sim/parts/nest_voxels.gd:16,25-27`)
  - Ant farm 16.5 × 10.8 × 0.75 cm (`tank_spec.gd:22`, `nest_voxels.gd:67-70`)
  - Outdoor soil to 30 cm, loaded as dug (`nest_voxels.gd:33`, `BASE:48-51`)
  - Outdoors there is no ant-farm option (`hud_colonies.gd:383`)
- Roadmap says digging across the whole tank (7.2 and 16.2 million voxels) is PART 0.12, not done (`docs/ROADMAP.md:46-50`, `PLAN_0.12.md:13`).
- Soil depth is not decided (`ROADMAP:58`, `PLAN_0.12.md:18`), and the doc notes 14-19 cm for nests of ~100 workers [Ln] García Ibarra et al. 2024 (`BIO:82`, `BASE:48-49`).
- Depth target: 15 + 4·log10(workers/100) cm × traits (`scripts/sim/parts/nest_chambers.gd:288-292`), clamped to the block.
- Doc disagreement: `BIO:64-65` still says ~5 cm at 100 workers and 6.6 cm at 300, whereas code says ~15 and ~17 cm, tagged inference (`nest_chambers.gd:288`).
- Nest volume: 80 + 22 voxels per worker (+¼ per brood) (`BASE:428-430`). `BIO:57` says about 74 mm³ per adult, "an estimate, not measured."
- Materials: "soil" only. Plaster, Ytong, acrylic and test-tube setups are absent (grep for `plaster|ytong|acrylic|test.?tube`). The one plaster mention is a comment at `COL:279`. Test-tube founding is absent.
- Soil contents: stones, clay and sand layers; roots only outdoors since v0.11.85 (`BASE:52`, `SIM:124-128`, `BIO:229-230` [inference]).
- Outworld connection: fixed, entrance goes straight from nest top to floor (`tank_spec.gd:9-10`). No tubes, no separate modules. An ant-farm extension connected by tube is a post-EA idea (`BL:106-108`).
- Escape: absent as a mechanic. `blocked()` keeps ants in (`BASE:516-519`). Foragers at the glass climb with 12% probability, 240 ticks, then return (`FOR:317-319,202-208`). Fluon band is a 1.8 cm view band plus a Home prop (`outworld_scene.gd:28`, `outworld_creatures.gd:529-549`, `home_tools.gd:8,270-271`). Keepers' Fluon is tagged forum, not research (`BIO:125`). No keeper failure or lid mechanic.
- Moving a colony between enclosures: absent. Grep `relocat|move.*colony|ย้ายรัง` in `scripts/game`, `scripts/sim` found nothing. Colony migration or nest moves by the ants: absent. Only brood and queen move between chambers.
- Fridge moves a tank in the Home scene and does not change the colony's enclosure (`outworld_scene.gd:282`).
- Stones are placeable and removable; "wipe scent" erases trails in radius 24 px (`BASE:322-408`, `outworld_view.gd:252-259`).
- Limit: 6 tanks per species, another 6 for wild (`scripts/game/home_store.gd:21`, `ROADMAP:42`). Tanks are purchased with game points (`STR:203-225`).

### Inferences
- A keeper's cleaning, moving, housing upgrade and escape-control work has no in-game counterpart beyond buying another tank for a new colony.

### Gaps
- None material.

## Reproduction

### Takeaway
Absent. Constants for gynes and males exist, but no simulation code uses them. The planned PART is 0.13.

### Cited Findings
- `Ant.GYNE` and `Ant.MALE` constants with the comment "come with the nuptial flight (PART 10)" (`scripts/sim/ant.gd:13-16`). Grep for `GYNE|MALE|gyne|nuptial|alate` in `scripts/` matched only that comment block.
- All brood becomes workers (`COL:433-449`). Queen and male brood fates, sex determination and colony maturity age are absent.
- Roadmap: "Mature colony and mating flight, winged queens and males, flight days after warm wet rain, collecting a queen for a new colony" is PART 0.13 (`docs/ROADMAP.md:36`, renumbered from PART 10 at line 88).
- Models for males and winged queens do not exist (`BL:359`).
- Flight data recorded: July-August, warm humid days after rain, ~18-20 h [Ln/BWARS + keeper] (`BIO:272`).
- The opening text does treat the queen as just mated and dealated (`STR:3`, `BASE:30`). In-game capture of a new queen: absent.

### Inferences
- Since `L. niger` colonies of real alate-producing size are far above the observed in-game plateau (see Colony growth), reproduction will depend on PART 0.12 growth changes. The roadmap says this directly: "needs a big colony first" (`ROADMAP:36`).

### Gaps
- The docs give no alate-production colony size for L. niger.

## Behaviours modelled

### Takeaway
Age polyethism, response thresholds, half-hourly duties, trails and alarm, digging, aphid milking and predator mobbing all exist in the simulation. Several realistic-looking behaviours are abstract: trophallaxis moves no food, and brood sorting is by chamber. Rival colonies and enemies inside the nest are absent.

### Cited Findings
- Age polyethism: callow under 3 d, nurse under 20 d (9 d if hungry, 3 d under 8 workers), scaled 0.8-1.2 by individual threshold (`LN:49-51`, `COL:79-81,100-105`, `scripts/sim/ant.gd:125-137`). Thresholds are from Bonabeau et al. 1996 (`ant.gd:24`). Stated role over age is [Ln] (`BIO:332`), so the code differs on its emphasis.
- Task allocation: every 30 game minutes (`DUTY:12,24-67`). `BIO:338-357` gives each rate and its tag. Rest share 40% is [inference] from [relative] 25-50%. More rest when starved is [Ln] (`BIO:312,353`).
- Trophallaxis: `DUTY:172-219`. Pairs are real, energy +0.15, but "food itself stays the colony's" (`DUTY:10`, `BIO:355`). Frequency-over-size as [Ln] Buffin et al. 2011 (`BIO:313-315`).
- Recruitment trails:
  - `home` and `food` fields (`STATE:27-28`)
  - Laden foragers lay food trail (`FOR:180-181`)
  - Arrival with a load adds 2 recruits (`FOR:443-444`, `COL:155-160`)
  - Foragers limited to 20-32% of colony plus 3, max 60% (`COL:151`, `DONE.md:11`)
  - Tagged [Ln] for hindgut trail source (`BIO:275`) and individual thresholds (`BIO:277`)
  - Rain clears trails faster (`STATE:29`, `SIM:22-24`)
  - The change of foraging mode at ~75 workers is [Ln], absent in game (`BIO:268-269`)
- Day and night: foraging follows temperature only, and the doc calls real diurnality "not clear" (`BIO:281`).
- Losses: foragers die at 1.2%/day outside (`LN:53`, `COL:258-259`), with the comment naming birds and spiders. This is not gated by scenario, so it applies inside closed tanks too. `BIO:138` lists it under the wild heading.
- Brood placement: chamber-level. Larvae to the fastest-developing chamber, pupae slightly higher, eggs stay where laid, queen moves at most every 2 d (`WARM:100-144`). Tags: [relative] Camponotus mus, [keeper/field] Lasius, [inference] queen (`WARM:9-12`, `BIO:102-107`). Direct L. niger evidence "not found" (`BIO:105`).
- Sorting within piles: view only, separate piles, not concentric rings (`BIO:112-115`, `BL:449-450`). The keeper's stated rule is that brood moves only when carried (project auto-memory, not a code citation).
- Aphids: milking with a fixed-regen resource (`FOOD:21-22`, `FOR:285-305`). Aphids do not move, die or get eaten. Protecting them, eating low-yield aphids and predators are absent (`BIO:278-280`), yet the species page says ants chase ladybirds (`STR:129`). Doc tags [Ln]. Soil shelters are absent.
- Digging: `COL:169-193` (up to 20 diggers, chosen cap), soil carried out (`FOR:238-282`), chambers by plan (`COL:31-37`, `nest_chambers.gd`). Heat deepens nests (`COL:28-30`, García Ibarra et al. 2024 [Ln], `BIO:77-90`). Refilling upper chambers: absent (`BL:249,252`). Real stigmergy is replaced by a plan (`BL:434`).
- Prey: cut on site in pieces (`BIO:119-120`, user decision). Group drag exists in code but no food uses it (`FOOD:32-33`, comment at `FOR:307-311`).
- Combat:
  - Alarm field (`STATE:30`, `FOR:102-122`)
  - Defenders min(4 + 15% workers, 40) from colonies of 20 or more; under 20, they hide (`COL:133-144`, `ENEMY:20`)
  - Formic-acid damage 0.0004 per tick (`ENEMY:17`)
  - Mobbing layers tagged [inference] (`BIO:160-161`)
  - Spread-eagling tagged [relative] (`BIO:158-159`)
- Enemies, chance per day × `enemy_rate`:
  - Wolf spider 0.07 by day and night
  - Ground beetle 0.05 at night
  - Stone centipede 0.12 at night
  - Only outside; one wild enemy at a time (`scripts/sim/enemies/*.gd`, `ENEMY:31-40`)
  - Rate defaults to 1.0 outdoors, 0 indoors, player adjustable, can release up to 3 (`BASE:32-33`, `ENEMY:21,45-47,62-69`)
  - Dead enemies become food (`FOOD:34-40`)
- Absent: rival ant colonies, called the most important real enemy (`BIO:165`, `BL:429`); enemies entering the nest (`BL:413,430`); birds as actors; carrying wounded (`BL:430`).
- Colony individuality: queen, forage, life, size, depth, spread, wind, lean, bush traits (`BASE:255-265`). Tagged [Ln] queen, [relative] foraging, [inference] rest (`BIO:221-228`).
- Determinism note: duties use `duty_rng`, not `sim.rng` (`STATE:122-125`, `BL:384`). CLAUDE.md says "use `sim.rng`". This is a documented exception.

### Inferences
- Effects of per-worker duties on outcomes are limited to larval feeding, a small energy gain, and queen attendance (× 0.9). Most duties only drive the view and counters.

### Gaps
- `BIO:335-336` lists what has no evidence: resting share, feeding rate per hour, retinue size, digging share, retinue effect on laying.

## Known gaps already recorded, and doc-code disagreements

### Takeaway
The project already lists most biological gaps in `BIO` with ✗ marks and in `BL`. The main doc-code disagreements are the depth figures, "sealed" founding, species-page claims, and the roadmap's description of controls.

### Cited Findings
Gaps recorded by the project:
- Latrine, disease and parasites (`BIO:258,262,293`).
- Foraging mode switch at ~75 workers (`BIO:269`).
- Worker lifespan too short (`BIO:266`).
- Aphid predators, defence and eating aphids (`BIO:280`).
- Trophic-egg feeding as an item (`BL:223`, `BIO:247`).
- Concentric brood pile (`BIO:115`, `BL:449`).
- Per-point humidity (`BL:426`).
- Per-ant crops (`BL:407,457`).
- Rival colonies (`BL:429`).
- Nest top-heaviness, near-surface branching tunnels, multiple entrances (`BIO:96-97`).
- Filling upper chambers (`BL:249`).
- Prey burial having real effect (`BL:427,462`).
- Soil fauna, earthworms, springtails, mites (`BL:460`).
- Starvation winter collapse in wild untended colonies (`BL:439-441`).
- Decor before colony start, deferred (`BL:444`).
- Queen-feeding effect on founding: recorded as evidence only (`BIO:325`), no backlog item found.
- Urban scenario and nest-mound rain erosion, ideas (`BL:461,463-465`).

Doc versus code:
1. Depth: `BIO:64-65` (~5 and 6.6 cm) versus `nest_chambers.gd:288-292` (~15 and 17 cm, clamped in tanks to the 10.8 cm block).
2. Founding: "sealed" in `STR:3`, `STR:127`, `BASE:73`, versus open shaft `nest_voxels.gd:101-106`.
3. Controls: `docs/ROADMAP.md:10` says the player can "adjust temperature and humidity". Code gives only mat on/off, fridge on/off, water.
4. Species page `STR:129` says the ants chase ladybirds, but no such code exists (`BIO:280` admits this).
5. Species page `STR:135` quotes queen age ~29 years, with no queen ageing in code. This also means a queen can outlive any real record, as with the player's year-35 colony.
6. `nanitic_size` comment "first workers" (`LN:82`): used only for the prebuilt 14-worker start. Real first brood size comes from `_adult_size`.
7. `BIO:138` frames the 1.2% forager risk as predators and outdoors, but code applies it in closed tanks too (`COL:258`).
8. `FOR:307-311` describes small prey hauled whole; `FOOD:32-33` disables this for L. niger, and `BIO:119-120` explains the disabling.
9. `DUTY` table at `BIO:345` says attending the queen has no effect, and `BIO:353-354` plus `STATE:140` override it with × 0.9. BIO notes this itself.
10. Warnings: `STR:14,22` name fewer brood stages than code kills.
11. `BL:9-10` still lists a wall screen step, and older text uses old PART numbers; `BL:10` says to trust the new order.
12. `BIO:143` says outdoor hunting is greater, consistent with code at `COL:492`, so no disagreement there. `BIO:267` (~300 keeper plateau) broadly matches `CL:1020`.

### Inferences
- The largest husbandry mismatches for a line-by-line comparison:
  - Food appears free in closed tanks
  - Nest humidity is a single value, driven by a tank button
  - No hygiene or health loop
  - No queen ageing
  - No escape risk
  - Hibernation only affects laying
  - Heat and overwatering are nearly harmless in practice

### Gaps
- Items in this file marked "Arithmetic" were not confirmed by running the game, as instructed. Running `tests/year_run.gd` with short scenarios could confirm them.
- `CL` is 2,369 lines and was searched by regex, not read in full. Other year-run results may exist in unusual wording.
- `scripts/sim/nest_volume.gd`, most of `nest_voxels.gd` and `nest_chambers.gd`, the enemy behaviour bodies, and view code were read only where cited.
