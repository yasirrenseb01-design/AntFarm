extends SceneTree
## Dev (v0.14.2): writes tests/fixtures/save_v12b.antfarm - run it in a checkout of v0.14.1 (1edfd09), the last code to
## write save format 12 (before the alates, PART 0.14 step 1): a wild colony 500 days old (it has wintered once - the
## loader of v13 works its winters out from its age: save_migrations._v12_to_v13), with a creature out.
##   godot --headless --path <v0.14.1 checkout> --script res://tests/_make_fixture_v12b.gd -- <out path>

const Sim := preload("res://scripts/sim/simulation.gd")


func _init() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://save_v12b.antfarm"
	var s := Sim.new()
	s.setup(29, 14, false, "wild")
	s.tick = 498 * s.TPD - 10          # (its calendar on: a colony 498 days old, in December of its 2nd year)
	for i in int(2.0 * s.TPD):
		s.step()
	var f := FileAccess.open_compressed(out, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	f.store_var({"meta": {"version": "0.14.1"}, "sim": s.to_dict()})
	f.close()
	print("fixture v%d: %d workers, day %d %s, creatures %d -> %s" % [int(s.to_dict().version), s.workers.size(), s.day(),
		s.date_text(), s.creatures.size(), out])
	quit()
