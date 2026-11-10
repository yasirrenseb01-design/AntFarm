extends RefCounted
## The nest's ways out on the outworld's ground (PART 0.12 step 5d, sim/parts/nest_exits.gd; new in v0.12.22): where
## each is (units = voxels across from the entrance under nest_xz) and its heap, as big as the soil carried out of it
## (Mound.size - the crater's shape). Two at most (the shader's holes_xz / holes_hr: shaders/terrain/ground_h.gdshaderinc).
const Mound := preload("res://scripts/sim/mound.gd")


## [where (Array[Vector2]), heaps (Array[Vector2] height, radius), holes_xz (Vector4), holes_hr (Vector4)].
static func lay_out(nest, nest_xz: Vector2) -> Array:
	var xz: Array[Vector2] = []
	var hr: Array[Vector2] = []
	var hv := Vector4(-1000, -1000, -1000, -1000)
	var hh := Vector4(0.25, 3.55, 0.25, 3.55)
	for ex in nest.exits:
		if ex.open and xz.size() < 2:
			var p := nest_xz + Vector2(ex.b.x - nest.entrance.x, ex.b.z - nest.entrance.z)
			var ehr := Mound.size(int(ex.get("soil", 0)))
			xz.append(p)
			hr.append(ehr)
			if xz.size() == 1:
				hv = Vector4(p.x, p.y, hv.z, hv.w)
				hh = Vector4(ehr.x, ehr.y, hh.z, hh.w)
			else:
				hv = Vector4(hv.x, hv.y, p.x, p.y)
				hh = Vector4(hh.x, hh.y, ehr.x, ehr.y)
	return [xz, hr, hv, hh]


## The soil heaped round the ways out (a change of it lays them out again).
static func soil(nest) -> int:
	var n := 0
	for ex in nest.exits:
		n += int(ex.get("soil", 0))
	return n
