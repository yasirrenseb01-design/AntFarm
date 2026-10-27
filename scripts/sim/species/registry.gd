extends RefCounted
## Every species there is, by its id (the keeper, 2026-10-27: "make adding a new ant species easier"). A species is one
## file in this folder - its DATA (the biology the simulation reads, and how the views draw it: "look") and its CARD
## (what the species page says) - listed here once; nothing else names a species. The save keeps the id
## (simulation.to_dict "species"), so a colony loads as its own kind. To add one: copy lasius_niger.gd, change its
## numbers (with their sources, docs/BIOLOGY.md), its words in lang/strings.csv, its models
## (assets/models/ants/<look.models>/: tools/blender/build_ant.py), and add it below; tests/species_test.gd checks that
## every species has every key the first one has.

const LasiusNiger := preload("res://scripts/sim/species/lasius_niger.gd")
const ALL := [LasiusNiger]               # (the species page lists them in this order)
const DEFAULT := "lasius_niger"


## The species' script (DATA, CARD) for that id - the first one for an id not known (a save from a newer game).
static func of(id: String):
	for s in ALL:
		if s.DATA.id == id:
			return s
	return ALL[0]


static func data(id: String) -> Dictionary:
	return of(id).DATA
