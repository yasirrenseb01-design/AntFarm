extends SceneTree
## The tank's sizes (view/common/tank_spec.gd) against the simulation's own: the box's floor (sim_state), the nest's
## block and the ant farm's slab (nest_voxels, a fresh nest each way), and the soil as deep as the nest.
##   godot --headless --path . --script res://tests/tank_spec_test.gd     -> "TANK SPEC TEST PASSED"

const Spec := preload("res://scripts/view/common/tank_spec.gd")
const SimState := preload("res://scripts/sim/parts/sim_state.gd")
const NestVolume := preload("res://scripts/sim/nest_volume.gd")
var ok := true


func _init() -> void:
	_near("small box", SimState.SMALL_WORLD * Spec.PX, Spec.SMALL)
	_near("big box", SimState.BIG_WORLD * Spec.PX, Spec.BIG)
	var r := RandomNumberGenerator.new()
	r.seed = 1
	var n := NestVolume.new()
	n.setup(r)
	_near("nest block", Vector3(n.nx, n.ny, n.nz) * Spec.VOXEL, Spec.NEST)
	var f := NestVolume.new()
	f.setup(r, true)
	_near("ant farm", Vector3(f.nx, f.ny, f.nz) * Spec.VOXEL, Spec.FARM)
	_near("soil = nest depth", Spec.SOIL, Spec.NEST.y)
	print("TANK SPEC TEST PASSED" if ok else "TANK SPEC TEST FAILED")
	quit()


func _near(what: String, got, want) -> void:
	var good: bool = got.is_equal_approx(want) if not (got is float) else is_equal_approx(got, want)
	print("  %s %s: %s (spec %s)" % ["ok  " if good else "FAIL", what, got, want])
	ok = ok and good
