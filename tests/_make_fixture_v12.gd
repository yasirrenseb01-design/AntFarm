extends SceneTree
## Dev (v0.13.30): writes tests/fixtures/save_v12.antfarm - run it in a checkout of v0.13.0 (cb40e25), the first code to
## write save format 12, where a worker's crop was only its share of the colony's sugar and could hold far over the cap
## (2.5): the loader of later versions moves the excess to the entrance (sim_crops.ledger_count). A wild colony with a
## creature out (the migration test checks it is kept), its sugar raised so the shares are over the cap.
##   godot --headless --path <v0.13.0 checkout> --script res://tests/_make_fixture_v12.gd -- <out path>

const Sim := preload("res://scripts/sim/simulation.gd")


func _init() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://save_v12.antfarm"
	var s := Sim.new()
	s.setup(23, 14, false, "wild")
	for i in int(2.0 * s.TPD):
		s.step()
	s.ledger_set_sugar(s.sugar + 120.0)
	for i in int(0.5 * s.TPD):
		s.step()
	var most := 0.0
	for a in s.workers:
		most = maxf(most, a.crop)
	var f := FileAccess.open_compressed(out, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	f.store_var({"meta": {"version": "0.13.0"}, "sim": s.to_dict()})
	f.close()
	print("fixture v%d: %d workers, creatures %d, sugar %.2f, biggest crop %.2f -> %s" % [int(s.to_dict().version), s.workers.size(),
		s.creatures.size(), s.sugar, most, out])
	quit()
