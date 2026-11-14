extends RefCounted
## The free demo (v0.13.18, the keeper 2026-11-14), beside the paid game: the same code, the demo exported with the
## feature tag "demo" (export_presets.cfg "Windows Demo" -> build/demo/AntFarm-demo.exe), or --demo in the editor.
## What the demo holds back (nothing of it is written to a save, so the full game opens the same colonies and they grow on):
##   - each colony at most MAX_COLONY (workers + pupae + larvae + eggs): the queen stops laying there, and lays again as
##     ants die (sim.demo_max; the keeper's journal says so once)
##   - the Home: one small tank, as in the full game; the shop sells only the bigger tank (SOLD, once, at its price in
##     Colony Harmony points) - anything else says the demo cannot, with a button to the full game's page (v0.13.19, the
##     keeper: "not fair on those who bought the game and save up for shelves and tanks" - v0.13.18 gave a second small
##     tank and a shelf)
##   - the wild mode: one plot
##   - the album's plates past MAX_COLONY: "in the full game"
## Everything else is as in the full game (releasing enemies for Colony Harmony points, the wallpaper, time away, the fridge).

const MAX_COLONY := 150
const SOLD := ["big"]           # what the demo's shop sells (home_store.gd why_not / buy): the bigger tank, once
const WILD_SLOTS := 1
const STORE_URL := "https://khwanjai.itch.io/antfarm-legion-of-the-unseen"

static var forced := false       # --demo (main.gd): the editor runs as the demo


static func on() -> bool:
	return forced or OS.has_feature("demo")
