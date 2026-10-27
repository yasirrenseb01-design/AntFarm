extends RefCounted
## The outworld's scenery as meshes, from ground_data's layout: litter (each leaf and twig merged into one mesh per
## material), the big garden stones, pebbles, moss, grass, broad-leaved weeds and the crater/midden grains; and the
## litter heights the ants walk up over (prop_heights.gd).
## Split from outworld_scene.gd (_build_scenery) in v0.11.37.
const Props := preload("res://scripts/view/common/mesh_kit.gd")
const WeedMesh := preload("res://scripts/view/common/weed_mesh.gd")
const U := 1.0 / 3.0


static func build(v) -> void:
	var ground = v.ground
	var ph = v._props_h
	ph.setup(Vector2(v.sim.WORLD) * U)
	for l in ground.litter:
		if l.twig:
			ph.stamp_twig(l.p * U, l.a, l.l * 2.0 * U, 0.85, 0.5 + 0.05)
		else:
			ph.stamp_leaf(l.p * U, l.a, l.l * U, l.w * U, l.curl, 0.05)
	for p in ground.pebbles:
		var pr: Vector2 = p.r * U
		ph.stamp_cap(p.p * U, p.a, pr, minf(pr.x, pr.y) * 0.65)
	for m in ground.moss:
		for b in m:
			ph.stamp_cap(b[0] * U, 0.0, Vector2.ONE * b[1] * U, b[1] * U * 0.42)        # (as drawn below)
	# (the big stones lie outside the plot; a small one against them may reach in, and is climbed like sim stones)
	for b in ground.boulders:
		ph.stamp_rock(b.p * U, b.r * U, b.r * U * _rock_height(b.seed))
	ph.keep_litter()
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var twigs := SurfaceTool.new()
	twigs.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n_leaves := 0
	var n_twigs := 0
	for l in ground.litter:
		var xf := Transform3D(Basis(Vector3.UP, -l.a), v._on_ground(l.p, 0.05))
		if l.twig:
			twigs.append_from(Props.twig(l.l * 2.0 * U, int(l.p.x * 7 + l.p.y)), 0, xf)
			n_twigs += 1
		else:
			leaves.append_from(Props.leaf(l.l * U, l.w * U, l.c, l.curl), 0, xf)
			n_leaves += 1
	if n_leaves > 0:
		_add_mesh(v, leaves.commit(), v._litter_mat)
	if n_twigs > 0:
		_add_mesh(v, twigs.commit(), v._prop_mat)
	# weeds: plantain, dandelion and clover (weed_mesh.gd), green (they wither with the grass in winter); which kind and
	# how each leaf stands are drawn from where the weed grows, so the garden's layout draws are left as they were
	if not ground.rosettes.is_empty():
		var weeds := WeedMesh.new()
		var on_ground := func(q: Vector2) -> Vector3: return v._on_ground(q / U, -0.05)
		for w in ground.rosettes:
			var r := RandomNumberGenerator.new()
			r.seed = (int(w.p.x * 131.0) * 7919 + int(w.p.y * 17.0) ^ int(v.sim.plot_seed)) & 0x7fffffff | 1
			var pick := r.randf()
			var kind := WeedMesh.PLANTAIN if pick < 0.45 else (WeedMesh.DANDELION if pick < 0.75 else WeedMesh.CLOVER)
			weeds.plant(kind, v._on_ground(w.p, -0.05), float(w.l) / 22.0, r, on_ground)
		_add_mesh(v, weeds.commit(), v._weed_mat)
	for b in ground.boulders:
		var outline := PackedVector2Array()
		for p in b.poly:
			outline.append(p * U)
		var mi := MeshInstance3D.new()
		mi.mesh = Props.rock(outline, b.r * U, b.tone, b.seed)
		mi.material_override = v._vc_mat(0.85)
		mi.position = v._on_ground(b.p, 0.0)
		v.add_child(mi)
	var stone: MultiMesh = v._multimesh(v._blob_mesh(Vector3.ONE), v._vc_mat(0.9, false, false), true)
	stone.instance_count = ground.pebbles.size()
	for i in ground.pebbles.size():
		var p: Dictionary = ground.pebbles[i]
		var r: Vector2 = p.r * U
		var b := Basis(Vector3.UP, -p.a).scaled(Vector3(r.x, minf(r.x, r.y) * 0.65, r.y))
		stone.set_instance_transform(i, Transform3D(b, v._on_ground(p.p, 0.0)))
		stone.set_instance_color(i, (p.c as Color).darkened(0.3).srgb_to_linear())
	var moss: MultiMesh = v._multimesh(v._blob_mesh(Vector3.ONE), v._vc_mat(1.0, false, false), true)
	var blobs := []
	for m in ground.moss:
		blobs.append_array(m)
	moss.instance_count = blobs.size()
	for i in blobs.size():
		var b: Array = blobs[i]
		var r: float = b[1] * U
		moss.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(r, r * 0.42, r)), v._on_ground(b[0], 0.0)))
		moss.set_instance_color(i, Color(0.2, 0.33, 0.1).lerp(Color(0.4, 0.53, 0.17), b[2]).srgb_to_linear())
	var grass: MultiMesh = v._multimesh(Props.blade(), v._grass_mat, true)
	var bl := []
	var gr := RandomNumberGenerator.new()
	gr.seed = 777 + v.sim.plot_seed
	var box: bool = v.sim.scenario != "wild"
	var lim: Vector2 = v.sim.WORLD - Vector2(2, 2)
	for t in ground.tufts:
		var n := gr.randi_range(9, 16)
		if t.has("n"):
			n = int(t.n)
		var tall: float = t.get("h", 1.0)
		var spread: float = t.get("s", 2.2)
		for k in n:
			var yaw := gr.randf() * TAU
			var h := gr.randf_range(6.0, 17.0) * (1.25 if k < 3 else 1.0) * tall
			var lean := gr.randf_range(0.05, 0.5)
			var at: Vector2 = t.p + Vector2(gr.randfn(0.0, spread), gr.randfn(0.0, spread))
			var dry := gr.randf() < 0.14
			var col := Color(0.24, 0.42, 0.13).lerp(Color(0.5, 0.64, 0.26), gr.randf())
			if dry:
				col = Color(0.56, 0.5, 0.32).lerp(Color(0.68, 0.6, 0.4), gr.randf())
			if box:
				# in a keeper's box no blade through the glass (the keeper, 2026-10-27): its foot inside, and one that would
				# lean out leans back in (its top 1/U px a unit away, along (cos yaw, -sin yaw))
				at = at.clamp(Vector2(2, 2), lim)
				for tries in 3:
					var tip: Vector2 = at + Vector2(cos(yaw), -sin(yaw)) * h * sin(lean) / v.U
					if tip.x < 2.0 or tip.x > lim.x:
						yaw = PI - yaw
					elif tip.y < 2.0 or tip.y > lim.y:
						yaw = -yaw
					else:
						break
					if tries == 2:
						lean *= 0.3
			bl.append([at, yaw, h, lean, col])
	grass.instance_count = bl.size()
	for i in bl.size():
		var b: Array = bl[i]
		var basis := (Basis(Vector3.UP, b[1]) * Basis(Vector3.BACK, -b[3])).scaled(Vector3(b[2] * 0.8, b[2], 3.2))
		grass.set_instance_transform(i, Transform3D(basis, v._on_ground(b[0], -0.15)))
		grass.set_instance_color(i, (b[4] as Color).srgb_to_linear())
	var grains: MultiMesh = v._multimesh(v._blob_mesh(Vector3.ONE), v._vc_mat(0.95, false, false), true)
	var bits := []
	bits.append_array(ground.crater)
	bits.append_array(ground.midden_bits)
	grains.instance_count = bits.size()
	for i in bits.size():
		var g: Dictionary = bits[i]
		var r: float = g.r * U
		grains.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(r, r * 0.7, r)), v._on_ground(g.p, 0.0)))
		grains.set_instance_color(i, (g.c as Color).darkened(0.2).srgb_to_linear())


## A stone's height as a share of its radius: the same draw as mesh_kit_base rock() makes from its seed.
static func _rock_height(seed_value: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng.randf_range(0.45, 0.7)


static func _add_mesh(v, mesh: Mesh, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	v.add_child(mi)
