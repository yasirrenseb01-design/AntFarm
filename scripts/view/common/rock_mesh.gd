extends RefCounted
## Stones the keeper lays (the stone tool): three kinds, one picked by where it lies (v0.13.15, the keeper: "two more
## kinds of stone, picked at random as I lay them"). 0 the rounded field stone (mesh_kit_base.gd rock), 1 a flat slate
## with cut edges, 2 an angular broken chunk of granite. Faceted: each face lit flat. The height each stands is its
## own, and the ants' height grid is stamped with it (outworld_props.gd _sync_rocks).

const Props := preload("res://scripts/view/common/mesh_kit.gd")


## Which kind a stone is: the one the keeper chose (v0.13.17: three stone tools), else by where it lies (laid before
## v0.13.17: any of three; the plot's own stones stay the rounded kind).
static func kind_for(rk: Dictionary, seed_value: int) -> int:
	var k := int(rk.get("kind", -1))
	return k if k >= 0 and k < 3 else kind_of(seed_value, bool(rk.get("placed", false)))


static func kind_of(seed_value: int, placed: bool) -> int:
	if not placed:
		return 0
	return posmod(seed_value * 7919 + 13, 3)


## How tall it stands (the same draw as its mesh).
static func height(r: float, seed_value: int, kind: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	match kind:
		1:
			return r * rng.randf_range(0.22, 0.32)
		2:
			return r * rng.randf_range(0.7, 0.95)
	return r * rng.randf_range(0.45, 0.7)


static func mesh(outline: PackedVector2Array, r: float, tone: float, seed_value: int, kind: int) -> ArrayMesh:
	if kind == 0:
		return Props.rock(outline, r, tone, seed_value)
	var h := height(r, seed_value, kind)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 101
	# the corners: fewer than the outline's points, so the edges run straight between them
	var corners := 7 if kind == 1 else 6
	var start := rng.randf() * TAU
	var base := []
	for k in corners:
		var a := start + TAU * (k + rng.randf_range(-0.25, 0.25)) / corners
		var rr := r * rng.randf_range(0.8, 1.0)
		base.append(Vector2.from_angle(a) * rr)
	var rows := []                     # each a ring of Vector3 from the floor up; the last a single top point
	if kind == 1:
		# slate: straight sides, a chamfer round its top, a flat top a little tilted
		var tilt := Vector2.from_angle(rng.randf() * TAU) * h * 0.12
		rows.append(_ring(base, 1.0, -0.4))
		rows.append(_ring(base, 0.98, h * 0.7))
		var top := []
		for p in _ring(base, 0.84, h):
			top.append(p + Vector3(0, tilt.dot(Vector2(p.x, p.z)) / r, 0))
		rows.append(top)
	else:
		# a broken chunk: wide at the foot, faces leaning in at odd angles, a ridge of a top
		rows.append(_ring(base, 1.0, -0.4))
		var mid := []
		for p in _ring(base, rng.randf_range(0.78, 0.9), h * 0.5):
			mid.append(p + Vector3(rng.randf_range(-0.12, 0.12) * r, rng.randf_range(-0.1, 0.15) * h, rng.randf_range(-0.12, 0.12) * r))
		rows.append(mid)
		var top := []
		for p in _ring(base, rng.randf_range(0.35, 0.5), h):
			top.append(p + Vector3(0, rng.randf_range(-0.22, 0.0) * h, 0))
		rows.append(top)
	var peak := Vector3(0, h * (1.0 if kind == 1 else 1.08), 0)
	if kind == 1:
		var c := Vector3.ZERO
		for p in rows[-1]:
			c += p
		peak = c / rows[-1].size()
	# colours: a blue-grey slate, or a speckled granite; each face its own shade
	var col := Color(0.29, 0.32, 0.37).lerp(Color(0.38, 0.4, 0.44), tone) if kind == 1 \
		else Color(0.5, 0.46, 0.41).lerp(Color(0.6, 0.55, 0.48), tone)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tri := func(a: Vector3, b: Vector3, c: Vector3, lift: float) -> void:
		var n := (c - a).cross(b - a).normalized()
		var shade := 0.82 + 0.25 * lift + rng.randf_range(-0.08, 0.08)
		if kind == 2 and rng.randf() < 0.3:
			shade *= rng.randf_range(0.7, 1.25)            # (the granite's dark and light grains, face by face)
		st.set_color(Color(col.r * shade, col.g * shade, col.b * shade))
		for p in [a, b, c]:
			st.set_normal(n)
			st.add_vertex(p)
	for ri in rows.size() - 1:
		var lo: Array = rows[ri]
		var hi: Array = rows[ri + 1]
		for k in corners:
			var k2 := (k + 1) % corners
			var lift := float(ri + 1) / rows.size()
			tri.call(lo[k], lo[k2], hi[k], lift)
			tri.call(lo[k2], hi[k2], hi[k], lift)
	var last: Array = rows[-1]
	for k in corners:
		tri.call(last[k], last[(k + 1) % corners], peak, 1.0)
	return st.commit()


static func _ring(base: Array, k: float, y: float) -> Array:
	var out := []
	for p in base:
		out.append(Vector3(p.x * k, y, p.y * k))
	return out
