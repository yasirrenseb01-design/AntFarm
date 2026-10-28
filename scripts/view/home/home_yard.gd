extends RefCounted
## What one sees out of the Home's window: an American suburb (the keeper, 2026-10-27: "like a neighbourhood in
## America - open lawns, the street running on as far as one can see, no fence across it"). Our lawn down to a
## pavement and a street running across the view (left to right, to the edge of sight both ways); across it a row of
## one-storey clapboard houses facing us on open front lawns, each its own colours; beside the one in front of us a
## side street running away from the window, houses facing it on both sides; low-poly trees (Blender:
## tools/blender/build_tree.py) and shrubs on the lawns, street lamps. The forest's edge and the mountains stay painted
## far behind (shaders/home/window_view.gdshader, its near ring now 140 m off). Built in code; metres; the window looks
## out along -x from x = -2 (home_kit.W), the ground at y = 0. home_room._window calls build().

const Kit := preload("res://scripts/view/home/home_kit.gd")
const AntModel := preload("res://scripts/view/common/ant_model3d.gd")
const FAR := 130.0                           # how far the streets run (short of the painted forest)
const CROSS_X := Vector2(-13.0, -19.0)       # the street across the view: its two kerbs (x; our front lawn ~9 m)
const SIDE_Z := Vector2(3.6, 9.6)            # the side street running away from the window: its kerbs (z)
const ROW_X := -30.0                         # the houses across the street: the middle of their feet (x)
const HOUSE_SIZE := Vector3(6.5, 3.0, 9.0)   # depth (x), the walls' height, width (z)
const WALLS := [Color(0.93, 0.93, 0.9), Color(0.78, 0.84, 0.88), Color(0.93, 0.88, 0.72), Color(0.86, 0.8, 0.74),
	Color(0.74, 0.8, 0.72), Color(0.95, 0.95, 0.95), Color(0.84, 0.74, 0.66)]
const DOORS := [Color(0.2, 0.32, 0.3), Color(0.55, 0.16, 0.12), Color(0.16, 0.2, 0.35), Color(0.12, 0.12, 0.12),
	Color(0.45, 0.3, 0.16)]
const ROOFS := [Color(0.32, 0.33, 0.35), Color(0.24, 0.25, 0.28), Color(0.38, 0.3, 0.26), Color(0.3, 0.27, 0.25)]


static var _made: Node3D             # the yard built once (it is the same every time: rng seed 2026), copied after


## (The yard was built anew each time the room was - every time the Home opened and every colony opened: ~2 s, the
## keeper, 2026-10-28: "Esc back to the Home hangs". Built once now and copied: the copies share its meshes.)
static func build(parent: Node3D) -> void:
	if _made == null:
		_made = _make()
	parent.add_child(_made.duplicate())


static func _make() -> Node3D:
	var room := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	# the street across the view, and the side street off it beside the house in front
	# (a T-junction - the keeper, 2026-10-27: they did not join: the far kerb and pavement of the street across ran on
	# over the side street's mouth; now they stop at its corners, and the side street's start at the far kerb)
	var mouth := Vector2(SIDE_Z.x - 0.14, SIDE_Z.y + 0.14)
	_street(room, Vector3((CROSS_X.x + CROSS_X.y) * 0.5, 0, 0), absf(CROSS_X.y - CROSS_X.x), FAR * 2.0, true, mouth)
	var side_len := FAR + CROSS_X.y
	_street(room, Vector3(CROSS_X.y - side_len * 0.5, 0, (SIDE_Z.x + SIDE_Z.y) * 0.5), SIDE_Z.y - SIDE_Z.x, side_len, false,
		Vector2.ZERO, 1.64)
	# the row across the street, facing us (+x): a lot every 17 m, the side street's mouth left clear
	var k := 0
	var z := -3.0 - 17.0 * 4.0
	while z < 70.0:
		if absf(z - (SIDE_Z.x + SIDE_Z.y) * 0.5) > 9.0:
			_lot(room, Vector3(ROW_X, 0, z), 0.0, k, rng)
			k += 1
		z += 17.0
	# along the side street, facing it from both sides
	var x := ROW_X - 16.0
	while x > -100.0:
		_lot(room, Vector3(x, 0, SIDE_Z.y + 9.5), PI * 0.5, k, rng)          # (facing -z, the street)
		_lot(room, Vector3(x - 6.0, 0, SIDE_Z.x - 9.5), -PI * 0.5, k + 1, rng)
		k += 2
		x -= 17.0
	# our own lawn: a tree and a shrub by the pavement
	_tree(room, Vector3(-7.5, 0, -7.5), "tree_b", 1.0, 0.4)
	_tree(room, Vector3(-10.5, 0, 9.0), "tree_a", 0.9, 2.4)
	_shrub(room, Vector3(-4.4, 0, 6.5), 0.6)
	_shrub(room, Vector3(-4.6, 0, -4.0), 0.5)
	# street lamps along our kerb
	z = -60.0
	while z <= 60.0:
		_lamp(room, Vector3(CROSS_X.x - 0.6, 0, z), -1.0)
		z += 30.0
	_bake(room)
	return room


## All the plain-coloured pieces merged into one mesh, coloured by vertex (hundreds of boxes, a draw call each, slowed
## the Home: 35 fps on the Intel UHD) - the clapboard, the trees, the glowing lamps stay as they are.
static func _bake(root: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	var inv := root.global_transform.affine_inverse() if root.is_inside_tree() else Transform3D()
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m: Material = mi.material_override
		if not (m is StandardMaterial3D) or (m as StandardMaterial3D).emission_enabled or (m as StandardMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			continue
		if mi.mesh is ArrayMesh:
			continue                                  # (the trees: their own vertex colours and sway)
		var xf: Transform3D = _local(mi, root)
		var col: Color = (m as StandardMaterial3D).albedo_color
		var arr: Array = mi.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx = arr[Mesh.ARRAY_INDEX]
		var nb := xf.basis.inverse().transposed()
		var order: PackedInt32Array = idx if idx != null and (idx as PackedInt32Array).size() > 0 else PackedInt32Array(range(v.size()))
		for i in order:
			st.set_color(col)
			st.set_normal((nb * n[i]).normalized())
			st.add_vertex(xf * v[i])
		any = true
		mi.queue_free()
	if not any:
		return
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	var out := MeshInstance3D.new()
	out.mesh = st.commit()
	out.material_override = mat
	root.add_child(out)


## mi's transform relative to root (the yard is built before the room is in the tree).
static func _local(n: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D()
	var at: Node = n
	while at != null and at != root:
		xf = (at as Node3D).transform * xf
		at = at.get_parent()
	return xf


## A house on its lot, turned (0: facing +x, toward the window), with a tree and shrubs on its front lawn.
static func _lot(room: Node3D, at: Vector3, turn: float, k: int, rng: RandomNumberGenerator) -> void:
	var lot := Node3D.new()
	lot.position = at
	lot.rotation.y = turn
	room.add_child(lot)
	_house(lot, Vector3.ZERO, WALLS[k % WALLS.size()], DOORS[(k * 3 + 1) % DOORS.size()], ROOFS[(k * 2) % ROOFS.size()])
	var front := HOUSE_SIZE.x * 0.5
	for t in 2:
		_tree(lot, Vector3(front + rng.randf_range(4.0, 6.5), 0, rng.randf_range(3.5, 7.0) * (1.0 if (k + t) % 2 == 0 else -1.0)),
			"tree_a" if (k + t) % 3 != 1 else "tree_b", rng.randf_range(0.85, 1.2), rng.randf() * TAU)
	for i in 2:
		_shrub(lot, Vector3(front + 0.7, 0, (i * 2 - 1) * rng.randf_range(2.4, 3.6)), rng.randf_range(0.55, 0.8))


## A street (asphalt between kerbs, a dashed white line down its middle, a pavement each side), its middle at `c`,
## `w` across and `l` long, along z (along_z) or along x. gap: where (along it) its far side's kerb and pavement stop
## for a side street (zero: none); start_in: how far its kerbs and pavements start past its near end (where it meets a
## street across, under that one's pavement).
static func _street(room: Node3D, c: Vector3, w: float, l: float, along_z: bool, gap := Vector2.ZERO, start_in := 0.0) -> void:
	var asphalt := Kit.flat(Color(0.2, 0.2, 0.21), 0.95)
	var kerb := Kit.flat(Color(0.62, 0.62, 0.6), 0.9)
	var pave := Kit.flat(Color(0.6, 0.59, 0.56), 0.95)
	var paint := Kit.flat(Color(0.92, 0.92, 0.88), 0.7)
	_box(room, _dims(w, 0.04, l, along_z), c + Vector3(0, 0.02, 0), asphalt)
	var t := -l * 0.5 + 1.0
	while t < l * 0.5 - 2.5:
		_box(room, _dims(0.1, 0.01, 1.5, along_z), c + _dims(0.0, 0.045, t + 0.75, along_z), paint)
		t += 3.0
	for side in [-1, 1]:
		# the stretches it runs along: whole, or both sides of the gap (a gap on the far side, -1); its near end
		# (+l/2 for a street along x running off to -x) moved in by start_in
		var runs: Array = [Vector2(-l * 0.5, l * 0.5 - start_in)]
		if side == -1 and gap != Vector2.ZERO:
			var g0 := gap.x - c.z - 1.64
			var g1 := gap.y - c.z + 1.64
			runs = [Vector2(-l * 0.5, g0), Vector2(g1, l * 0.5)]
		for r in runs:
			var ln: float = r.y - r.x
			var mid: float = (r.x + r.y) * 0.5
			if ln <= 0.0:
				continue
			_box(room, _dims(0.14, 0.14, ln, along_z), c + _dims(side * (w * 0.5 + 0.07), 0.07, mid, along_z), kerb)
			_box(room, _dims(1.5, 0.12, ln, along_z), c + _dims(side * (w * 0.5 + 0.9), 0.06, mid, along_z), pave)


## (across, up, along) as x/y/z for a street along z, or along x.
static func _dims(across: float, up: float, along: float, along_z: bool) -> Vector3:
	return Vector3(across, up, along) if along_z else Vector3(along, up, across)


## A street lamp: a pole, its arm out over the street (toward `side` along x), its lamp glowing a little.
static func _lamp(room: Node3D, at: Vector3, side: float) -> void:
	var pole := Kit.flat(Color(0.18, 0.2, 0.2), 0.5, 0.5)
	_cyl(room, 0.07, 4.6, at + Vector3(0, 2.3, 0), pole, 0.05)
	_box(room, Vector3(1.0, 0.05, 0.05), at + Vector3(side * 0.5, 4.55, 0), pole)
	var head := Kit.flat(Color(0.95, 0.9, 0.75), 0.4)
	head.emission_enabled = true
	head.emission = Color(1.0, 0.85, 0.6)
	head.emission_energy_multiplier = 0.6
	_box(room, Vector3(0.4, 0.12, 0.22), at + Vector3(side * 1.0, 4.48, 0), head)


## A one-storey house in clapboard of that colour, its long side to the window, a door of that colour with a porch.
static func _house(room: Node3D, c: Vector3, wall: Color, door: Color, roof_c: Color) -> void:
	var s := HOUSE_SIZE
	var board := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """shader_type spatial;
// clapboard: boards 16 cm high, each overlapping the one below - a shadow line under each, lighter toward its foot
varying vec3 wp;
void vertex() { wp = VERTEX; }      // (its own metres: the room is drawn scaled up round a box in the game)
uniform vec3 tint : source_color = vec3(0.93, 0.93, 0.9);
void fragment() {
	float f = fract(wp.y / 0.16);
	vec3 c = tint * (0.86 + 0.14 * f);
	c *= 1.0 - 0.35 * (1.0 - smoothstep(0.0, 0.06, f));
	ALBEDO = c;
	ROUGHNESS = 0.7;
}"""
	board.shader = sh
	board.set_shader_parameter("tint", wall)
	var trim := Kit.flat(Color(0.97, 0.97, 0.95), 0.5)
	var roof := Kit.flat(roof_c, 0.85)
	var glass := Kit.flat(Color(0.16, 0.2, 0.26), 0.15, 0.3)
	var found := Kit.flat(Color(0.55, 0.53, 0.5), 0.95)
	_box(room, Vector3(s.x + 0.1, 0.4, s.z + 0.1), c + Vector3(0, 0.2, 0), found)          # the foundation
	_box(room, Vector3(s.x, s.y, s.z), c + Vector3(0, 0.4 + s.y * 0.5, 0), board)
	# the gable roof: two slopes meeting along z, overhanging; the gable ends in clapboard
	var rise := 1.9
	var top := 0.4 + s.y
	var half := s.x * 0.5 + 0.45
	var slope := sqrt(half * half + rise * rise)
	var ang := atan2(rise, half)
	for sx in [-1, 1]:
		var r := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(slope, 0.12, s.z + 0.7)
		r.mesh = bm
		r.material_override = roof
		r.position = c + Vector3(sx * half * 0.5, top + rise * 0.5 - 0.05, 0)
		r.rotation.z = -sx * ang
		room.add_child(r)
	for sz in [-1, 1]:
		var g := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(s.x, rise, 0.08)
		g.mesh = pm
		g.material_override = board
		g.position = c + Vector3(0, top + rise * 0.5, sz * (s.z * 0.5 - 0.04))
		room.add_child(g)
	# the chimney
	_box(room, Vector3(0.6, 1.8, 0.6), c + Vector3(-0.8, top + rise - 0.2, -s.z * 0.3), Kit.flat(Color(0.55, 0.3, 0.24), 0.9))
	# the side toward the window (+x): windows with frames and a white door with a porch
	var fx := c.x + s.x * 0.5
	for wz in [-3.2, -1.2, 2.6]:
		_box(room, Vector3(0.06, 1.25, 1.0), Vector3(fx + 0.03, 0.4 + 1.45, c.z + wz), trim)
		_box(room, Vector3(0.07, 1.1, 0.85), Vector3(fx + 0.04, 0.4 + 1.45, c.z + wz), glass)
		_box(room, Vector3(0.08, 0.05, 0.85), Vector3(fx + 0.06, 0.4 + 1.45, c.z + wz), trim)      # (the sash bar)
		for sz in [-1, 1]:
			_box(room, Vector3(0.05, 1.25, 0.32), Vector3(fx + 0.05, 0.4 + 1.45, c.z + wz + sz * 0.68), Kit.flat(Color(0.12, 0.16, 0.2), 0.6))   # shutters
	var dz := c.z + 0.7
	_box(room, Vector3(0.08, 2.2, 1.1), Vector3(fx + 0.04, 0.4 + 1.1, dz), trim)
	_box(room, Vector3(0.09, 2.0, 0.9), Vector3(fx + 0.05, 0.4 + 1.0, dz), Kit.flat(door, 0.45))
	for i in 3:                                                                          # the porch's steps
		_box(room, Vector3(0.9 - i * 0.3, 0.14, 1.6), Vector3(fx + 0.45 - i * 0.15, 0.07 + i * 0.14, dz), trim)
	_box(room, Vector3(1.3, 0.08, 1.9), Vector3(fx + 0.65, 2.75, dz), trim)                # the porch's little roof
	for sz in [-1, 1]:
		_box(room, Vector3(0.08, 2.3, 0.08), Vector3(fx + 1.2, 1.15, dz + sz * 0.85), trim)
	# a path from the porch down the lawn to the pavement
	var reach := 6.4
	_box(room, Vector3(reach, 0.02, 1.0), Vector3(fx + reach * 0.5, 0.01, dz), Kit.flat(Color(0.6, 0.6, 0.58), 0.95))


## A leafy tree modelled in Blender (tools/blender/build_tree.py -> assets/models/trees/: forking limbs, a spray of
## leaves at each twig; until v0.11.55 a trunk under a heap of green balls, the keeper: "it does not look real"),
## turned and scaled so that no two look alike; its leaves sway a little in the wind (the vertex colour's alpha).
static var _trees := {}              # which -> its mesh, read once

static func _tree(room: Node3D, at: Vector3, which: String, scale: float, turn: float) -> void:
	if not _trees.has(which):
		_trees[which] = AntModel.load_antmesh("res://assets/models/trees/%s.antmesh" % which)
	var m: Mesh = _trees[which]
	if m == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = _leaf_mat()
	mi.position = at
	mi.rotation.y = turn
	mi.scale = Vector3.ONE * scale
	room.add_child(mi)


static var _leaves: ShaderMaterial

static func _leaf_mat() -> ShaderMaterial:
	if _leaves == null:
		var sh := Shader.new()
		sh.code = """shader_type spatial;
render_mode cull_disabled;
// a garden tree's bark and leaves (vertex colour, sRGB; alpha: how far the wind moves that point)
varying float w;
void vertex() {
	w = COLOR.a;
	vec3 p = VERTEX;
	float t = TIME * 1.3 + NODE_POSITION_WORLD.x * 0.7;
	VERTEX += vec3(sin(t + p.y * 0.8), 0.0, cos(t * 0.8 + p.x)) * 0.035 * w * w;
	COLOR.rgb = pow(COLOR.rgb, vec3(2.2));
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.9;
	SPECULAR = 0.15;                             // (leaves a little waxy, not shining white)
	if (!FRONT_FACING) { NORMAL = -NORMAL; }
	BACKLIGHT = vec3(0.25, 0.35, 0.1) * w;      // (sun through the leaves)
}"""
		_leaves = ShaderMaterial.new()
		_leaves.shader = sh
	return _leaves


static func _shrub(room: Node3D, at: Vector3, r: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(at.z * 31.0)
	for i in 4:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		var rr := r * rng.randf_range(0.55, 0.8)
		sm.radius = rr
		sm.height = rr * 1.6
		mi.mesh = sm
		mi.material_override = Kit.flat(Color(0.18, 0.33, 0.12).lerp(Color(0.28, 0.42, 0.16), rng.randf()), 0.9)
		mi.position = at + Vector3(rng.randfn(0.0, r * 0.3), rr * 0.75, rng.randfn(0.0, r * 0.4))
		room.add_child(mi)


static func _box(room: Node3D, size: Vector3, centre: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = centre
	room.add_child(mi)
	return mi


static func _cyl(parent: Node3D, r: float, h: float, centre: Vector3, mat: Material, r_top := -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.bottom_radius = r
	cm.top_radius = r if r_top < 0.0 else r_top
	cm.height = h
	cm.radial_segments = 12
	mi.mesh = cm
	mi.material_override = mat
	mi.position = centre
	parent.add_child(mi)
	return mi
