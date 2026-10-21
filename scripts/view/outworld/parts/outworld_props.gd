extends "res://scripts/view/outworld/parts/outworld_scene.gd"
## Outworld view, layer 2 of 5: stones and food in the box (aphid plants, honey, prey carcasses,
## their husks and the soil the ants pile on them).


func _sync_rocks() -> void:
	if sim.rocks.size() == _rocks_n:
		return
	_rocks_n = sim.rocks.size()
	for c in _rock_root.get_children():
		c.queue_free()
	# the small stones the ants climb over go into the height grid (body and feet ride over them)
	_props_h.reset_to_litter()
	for rk in sim.rocks:
		if rk.get("climb", false):
			var rng := RandomNumberGenerator.new()
			rng.seed = int(rk.pos.x * 13 + rk.pos.y)          # the same draw as the mesh's height below
			_props_h.stamp_rock(rk.pos * U, rk.r * U, rk.r * U * rng.randf_range(0.45, 0.7))
	if _ant_shader_mat != null and _props_h.w > 0:
		var tex := _props_h.texture()
		_ant_shader_mat.set_shader_parameter("prop_tex", tex)
		if _sel_shader_mat != null:
			_sel_shader_mat.set_shader_parameter("prop_tex", tex)
	for rk in sim.rocks:
		var outline := PackedVector2Array()
		for p in rk.poly:
			outline.append((p - rk.pos) * U)
		var mi := MeshInstance3D.new()
		mi.mesh = Props.rock(outline, rk.r * U, rk.tone, int(rk.pos.x * 13 + rk.pos.y))
		mi.material_override = _vc_mat(0.85)
		mi.position = _on_ground(rk.pos, 0.0)
		_rock_root.add_child(mi)


var _drinking := {}                    # food position -> ants still drinking there (filled by outworld_crowd each frame)


## How much of a food is left as it looks: the simulation takes each ant's share as it starts, the drop shrinks as
## they drink it.
func _left(f: Dictionary) -> float:
	return clampf((f.amt + float(_drinking.get(f.pos, 0))) / f.cap, 0.0, 1.0)


func _sync_foods() -> void:
	var seen := {}
	for f in sim.foods:
		var key: int = f.seed
		seen[key] = true
		var left: float = _left(f)
		var sig := "%s:%d:%s:%d" % [f.kind, int(left * 10.0), f.rotten, int(_cover(f) * 20.0)]
		var e: Dictionary = _foods.get(key, {})
		if not e.is_empty() and e.sig == sig:
			continue
		if not e.is_empty():
			e.node.queue_free()
		var node := _make_food(f, left)
		_food_root.add_child(node)
		var low := []
		if FoodKinds.info(f.kind).get("feed_pose", "") == "climb":
			for s in Props.aphid_spots(f.seed):
				if s[1] != 2 and (s[0] as Transform3D).origin.y < 10.0:
					low.append(s[0])
		_foods[key] = {"node": node, "sig": sig, "low": low, "at": f.pos}
	for key in _foods.keys():
		if not seen.has(key):
			var node: Node3D = _foods[key].node
			if node.has_meta("husk"):
				_make_husk(node)
				_husks.append({"node": node, "until": sim.tick + sim.TPD * 3})
			else:
				node.queue_free()
			_foods.erase(key)
	for h in _husks:
		if sim.tick > int(h.until) or sim.tick < int(h.until) - sim.TPD * 4:
			h.node.queue_free()
	_husks = _husks.filter(func(h): return sim.tick <= int(h.until) and sim.tick >= int(h.until) - sim.TPD * 4)


## Prey being hauled home moves every tick in the simulation: its model follows smoothly (the food models
## are only rebuilt now and then).
func _ease_foods(delta: float) -> void:
	var k := 1.0 - exp(-8.0 * delta)
	for f in sim.foods:
		var e: Dictionary = _foods.get(f.seed, {})
		if e.is_empty() or (f.pos as Vector2).distance_squared_to(e.get("at", f.pos)) < 0.01:
			continue
		var node: Node3D = e.node
		node.position = node.position.lerp(_on_ground(f.pos, 0.0), k)


## What is left of a carcass: the dry, hollow exoskeleton, faded and flattened.
func _make_husk(node: Node3D) -> void:
	if _husk_mat == null:
		_husk_mat = _prop_mat.duplicate()
		_husk_mat.albedo_color = Color(0.78, 0.74, 0.66)
		_husk_mat.roughness = 0.95
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = _husk_mat


func _make_food(f: Dictionary, left: float) -> Node3D:
	var root := Node3D.new()
	root.position = _on_ground(f.pos, 0.0)
	root.rotation.y = -f.ang
	var builder := "_food_" + String(f.kind)
	if has_method(builder):
		call(builder, root, f, left)
	else:
		# a kind without its own model yet: a plain lump
		var lump := MeshInstance3D.new()
		lump.mesh = _blob_mesh(Vector3(f.r, f.r * 0.5, f.r) * U * 0.6)
		lump.material_override = _mat(Color(0.6, 0.45, 0.3), 0.8)
		root.add_child(lump)
	if FoodKinds.info(f.kind).get("buried", false):
		_add_soil_cover(root, f, left)
	return root


## One builder per food kind (named _food_<kind>), called by _make_food().
func _food_aphids(root: Node3D, f: Dictionary, left: float) -> void:
	var plant := MeshInstance3D.new()
	plant.mesh = Props.aphid_plant(f.seed)
	plant.material_override = _plant_mat
	root.add_child(plant)
	var spots: Array = Props.aphid_spots(f.seed)
	for kind in 3:
		var xs := []
		for s in spots:
			if s[1] == kind:
				xs.append(s[0])
		if xs.is_empty():
			continue
		for layer in ([_aphid_meshes[kind], _aphid_wings] if kind == 2 else [_aphid_meshes[kind]]):
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = layer
			mm.instance_count = xs.size()
			for i in xs.size():
				mm.set_instance_transform(i, xs[i])
			var mi := MultiMeshInstance3D.new()
			mi.multimesh = mm
			mi.material_override = _prop_mat if layer != _aphid_wings else _wing_mat()
			root.add_child(mi)
	# honeydew waiting on the aphids: as many drops as the colony has to give right now
	var rng := RandomNumberGenerator.new()
	rng.seed = f.seed
	for i in int(round(left * 8.0)):
		var s: Array = spots[rng.randi() % spots.size()]
		var drop := MeshInstance3D.new()
		drop.mesh = _blob_mesh(Vector3(0.24, 0.22, 0.24))
		drop.material_override = _honey_mat()
		drop.position = (s[0] as Transform3D) * Vector3(-0.95, 0.4, 0)
		root.add_child(drop)


func _food_honey(root: Node3D, f: Dictionary, left: float) -> void:
	var r := (3.0 + 7.0 * sqrt(left)) * U
	var drop := MeshInstance3D.new()
	drop.mesh = _blob_mesh(Vector3(r * 1.1, r * 0.42, r))
	drop.material_override = _honey_mat()
	root.add_child(drop)


func _food_cricket(root: Node3D, f: Dictionary, left: float) -> void:
	var body := Node3D.new()
	body.rotation.x = 0.12        # lying a little on one side
	root.add_child(body)
	if Props.asset("prey/cricket_head") != null:
		# the Blender carcass comes in pieces: the abdomen shrinks and legs go as the ants cut it up
		var mat: StandardMaterial3D = _prop_mat
		if f.rotten:
			mat = _prop_mat.duplicate()
			mat.albedo_color = Color(0.72, 0.78, 0.66)
		# Lasius eat a big carcass where it lies: they bite in at the soft joints and drink or cut out
		# the insides, so the hard shell keeps its shape while the abdomen sags and wrinkles flat
		var gone := 1.0 - left
		# once the muscle inside the hip is eaten away, one hind leg comes off and lies beside it
		var lost := ("cricket_hindleg_l" if f.seed % 2 == 0 else "cricket_hindleg_r") if left < 0.35 else ""
		for pc in ["cricket_head", "cricket_abdomen", "cricket_hindleg_l", "cricket_hindleg_r", "cricket_legs"]:
			var mi := MeshInstance3D.new()
			mi.mesh = Props.asset("prey/" + pc)
			mi.material_override = mat
			body.add_child(mi)
			if pc == lost:
				var sd := -1.0 if pc.ends_with("_l") else 1.0
				# fallen flat on the ground, pulled a little way out from the body
				# tip it over its foot until the hip end rests on the ground, then shift it clear of the body
				var piv := Vector3(-7.3, 0.0, 2.8 * sd)
				var tip := Transform3D(Basis.IDENTITY, piv) * Transform3D(Basis(Vector3.BACK, -0.22), Vector3.ZERO) * Transform3D(Basis.IDENTITY, -piv)
				mi.transform = Transform3D(Basis(Vector3.UP, -0.3 * sd), Vector3(1.2, 0.15, 2.0 * sd)) * tip
				var socket := MeshInstance3D.new()
				socket.mesh = _blob_mesh(Vector3(0.45, 0.3, 0.4))
				socket.material_override = _flesh_mat()
				socket.position = Vector3(0.5, 1.75, 1.45 * sd)
				body.add_child(socket)
			if pc == "cricket_abdomen":
				# deflate about the belly, which stays on the ground
				var sc := Vector3(1.0 - 0.06 * gone, 1.0 - 0.5 * gone, 1.0 - 0.15 * gone)
				var pivot := Vector3(-1.6, 0.25, 0)
				mi.scale = sc
				mi.position = pivot - pivot * sc
				var wa := Props.cricket_wounds(left, f.seed, true)
				if wa != null:
					var w := MeshInstance3D.new()
					w.mesh = wa
					w.material_override = _prop_mat
					mi.add_child(w)
		var wf := Props.cricket_wounds(left, f.seed, false)
		if wf != null:
			var w2 := MeshInstance3D.new()
			w2.mesh = wf
			w2.material_override = _prop_mat
			body.add_child(w2)
		root.set_meta("husk", true)
	else:
		var c := MeshInstance3D.new()
		c.mesh = Props.cricket(left, f.rotten, f.seed)
		c.material_override = _prop_mat
		body.add_child(c)


## A dead house fly on its back (Blender model, tools/blender/build_props.py fly()); it shrinks as it is eaten.
func _food_fly(root: Node3D, f: Dictionary, left: float) -> void:
	var s := Vector3.ONE * (0.6 + 0.4 * left)
	var model := Props.asset("prey/fly")
	var b := MeshInstance3D.new()
	b.mesh = model if model != null else Props.fly(left)
	b.material_override = _prop_mat
	if model != null:
		b.scale = s
	root.add_child(b)
	var wings := MeshInstance3D.new()
	var wm := Props.asset("prey/fly_wings")
	wings.mesh = wm if wm != null else Props.fly_wings()
	wings.material_override = _fly_wing_mat()
	wings.scale = s
	root.add_child(wings)

func _add_soil_cover(root: Node3D, f: Dictionary, left: float) -> void:
	var cover := _cover(f) if sim.sp.get("buries_prey", false) else 0.0
	if cover <= 0.0:
		return
	if _grain_mesh == null:
		_grain_mesh = _blob_mesh(Vector3(1.0, 0.75, 1.0))
		_grain_mat = _vc_mat(0.95, false, false)
	var big: bool = FoodKinds.info(f.kind).get("big", false)
	var n_all := 220 if big else 60
	var rng := RandomNumberGenerator.new()
	rng.seed = f.seed + 51
	var grains := []
	for i in n_all:
		var thr := pow(rng.randf(), 0.8)                  # low thresholds sit on the ground, high ones up on the body
		var x := rng.randf_range(-7.0, 5.5) if big else rng.randf_range(-2.4, 2.4)
		var sd := 1.0 if rng.randf() < 0.5 else -1.0
		var span := 6.6 if big else 2.6
		var prof := sqrt(maxf(0.0, 1.0 - pow((x + (1.0 if big else 0.0)) / span, 2.0)))
		var height := (2.8 if big else 1.4) * prof
		if big and x < 0.5:
			height *= 1.0 - 0.45 * (1.0 - left)           # the abdomen has sagged
		var y := 0.15 + thr * height
		var half := (1.75 if big else 1.0) * prof + 0.35
		var z := sd * (half * sqrt(maxf(0.0, 1.0 - pow(thr, 2.0) * 0.85)) + (1.0 - thr) * rng.randf_range(0.1, 1.2))
		var r := rng.randf_range(0.22, 0.48)
		grains.append([thr, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * r), Vector3(x, y, z)),
			Color(0.34, 0.25, 0.16).lerp(Color(0.5, 0.38, 0.25), rng.randf())])
	grains.sort_custom(func(a, b): return a[0] < b[0])
	var n := int(cover * n_all)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _grain_mesh
	mm.instance_count = n
	for i in n:
		mm.set_instance_transform(i, grains[i][1])
		mm.set_instance_color(i, (grains[i][2] as Color).srgb_to_linear())
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = _grain_mat
	root.add_child(mi)


func _dead_creature(root: Node3D, kind: String, left: float, lift: float, on_back := false) -> void:
	var cv: Dictionary = _creature_views[kind]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = (cv.mm as MultiMesh).mesh
	mm.instance_count = 1
	var sag := 0.75 + 0.25 * left            # the body empties as the ants eat it
	var sc: float = cv.scale
	var b := Basis.from_scale(Vector3(sc, sc * sag, sc))
	if on_back:
		b = Basis(Vector3.RIGHT, PI) * b          # dead beetles end up on their backs, legs in the air
	mm.set_instance_transform(0, Transform3D(b, Vector3(0, lift, 0)))
	mm.set_instance_custom_data(0, Color(0.0, 2.0, 0.0, 0.0))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = cv.mat
	root.add_child(mi)
	root.set_meta("husk", true)


func _food_wolf_spider_dead(root: Node3D, f: Dictionary, left: float) -> void:
	_dead_creature(root, "wolf_spider", left, -0.3)


func _food_centipede_dead(root: Node3D, f: Dictionary, left: float) -> void:
	_dead_creature(root, "centipede", left, -0.2)


func _food_ground_beetle_dead(root: Node3D, f: Dictionary, left: float) -> void:
	_dead_creature(root, "ground_beetle", left, 3.6, true)
