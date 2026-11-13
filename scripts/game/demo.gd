extends RefCounted
## The free demo (v0.13.18, the keeper 2026-11-14), beside the paid game: the same code, the demo exported with the
## feature tag "demo" (export_presets.cfg "Windows Demo" -> build/demo/AntFarm-demo.exe), or --demo in the editor.
## What the demo holds back (nothing of it is written to a save, so the full game opens the same colonies and they grow on):
##   - each colony at most MAX_COLONY (workers + pupae + larvae + eggs): the queen stops laying there, and lays again as
##     ants die (sim.demo_max; the keeper's journal says so once)
##   - the Home: two tanks from the first day (the second on a shelf for two, both kept by the full game), nothing sold
##     (the shop opens to look; buying says the demo cannot, with a button to the full game's page)
##   - the wild mode: one plot
##   - the album's plates past MAX_COLONY: "in the full game"
## Everything else is as in the full game (releasing enemies for Colony Harmony points, the wallpaper, time away, the fridge).

const MAX_COLONY := 150
const TANKS := 2
const WILD_SLOTS := 1
const STORE_URL := "https://khwanjai.itch.io/antfarm-legion-of-the-unseen"

static var forced := false       # --demo (main.gd): the editor runs as the demo


static func on() -> bool:
	return forced or OS.has_feature("demo")
