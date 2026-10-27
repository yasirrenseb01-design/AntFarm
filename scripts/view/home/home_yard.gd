extends RefCounted
## What one sees close by out of the Home's window (the keeper, 2026-10-27, with a photo: "only green grass close to
## the window - put a house there, a white fence and a few trees in the lawn"): a white picket fence along the edge of
## the garden, a neighbour's house beyond it - white clapboard, a grey gable roof, windows, a door with a porch, a
## chimney - two leafy trees and a few shrubs. The meadow, the forest's edge and the mountains stay painted behind them
## (shaders/home/window_view.gdshader). Built in code; metres; the window looks out along -x from x = -2
## (home_kit.W), the lawn at y = 0. home_room._window calls build().

const Kit := preload("res://scripts/view/home/home_kit.gd")
const AntModel := preload("res://scripts/view/common/ant_model3d.gd")
const ROAD_Z := Vector2(3.6, 9.6)            # the street beside the neighbour's house, running away from the window
const ROAD_X := Vector2(-8.6, -25.5)         # (to the forest's painted edge, 26 m off)
const FENCE_X := -8.0                 # the fence, along z
const FENCE_Z := Vector2(-13.0, 11.0)
const HOUSE := Vector3(-19.0, 0.0, -3.0)     # the neighbour's house: the middle of its foot
const HOUSE_SIZE := Vector3(6.5, 3.0, 9.0)   # depth (x), the walls' height, width (z)


static func build(room: Node3D) -> void:
	_fence(room)
	# the neighbour's house, a street beside it (the keeper, 2026-10-27), a house across the street on the left and
	# another on the right of the first
	_house(room, HOUSE, Color(0.93, 0.93, 0.9), Color(0.2, 0.32, 0.3), Color(0.32, 0.33, 0.35))
	_house(room, Vector3(-19.5, 0.0, 15.2), Color(0.78, 0.84, 0.88), Color(0.55, 0.16, 0.12), Color(0.24, 0.25, 0.28))
	_house(room, Vector3(-18.5, 0.0, -15.0), Color(0.93, 0.88, 0.72), Color(0.16, 0.2, 0.35), Color(0.38, 0.3, 0.26))
	_road(room)
	_tree(room, Vector3(-11.2, 0, 1.4), "tree_a", 0.95, 0.3)
	_tree(room, Vector3(-14.0, 0, -9.3), "tree_b", 1.1, 2.1)
	_tree(room, Vector3(-13.0, 0, 12.4), "tree_b", 0.85, 4.0)
	_tree(room, Vector3(-24.0, 0, -6.5), "tree_a", 1.2, 1.2)
	for b in [[Vector3(-15.6, 0, 1.0), 0.8], [Vector3(-15.8, 0, -6.6), 0.9], [Vector3(-9.0, 0, -4.0), 0.6],
			[Vector3(-14.8, 0, 11.5), 0.7], [Vector3(-14.5, 0, -12.2), 0.75]]:
		_shrub(room, b[0], b[1])


## The street: asphalt between kerbs, a dashed white line down its middle, a pavement each side, a street lamp.
static func _road(room: Node3D) -> void:
	var asphalt := Kit.flat(Color(0.2, 0.2, 0.21), 0.95)
	var kerb := Kit.flat(Color(0.62, 0.62, 0.6), 0.9)
	var pave := Kit.flat(Color(0.55, 0.54, 0.52), 0.95)
	var paint := Kit.flat(Color(0.92, 0.92, 0.88), 0.7)
	var lx := absf(ROAD_X.y - ROAD_X.x)
	var cx := (ROAD_X.x + ROAD_X.y) * 0.5
	var cz := (ROAD_Z.x + ROAD_Z.y) * 0.5
	var wz := ROAD_Z.y - ROAD_Z.x
	_box(room, Vector3(lx, 0.04, wz), Vector3(cx, 0.02, cz), asphalt)
	var x := ROAD_X.x - 0.5
	while x > ROAD_X.y + 1.5:
		_box(room, Vector3(1.5, 0.01, 0.1), Vector3(x - 0.75, 0.045, cz), paint)
		x -= 3.0
	for side in [-1, 1]:
		var ez: float = cz + side * (wz * 0.5 + 0.07)
		_box(room, Vector3(lx, 0.14, 0.14), Vector3(cx, 0.07, ez), kerb)
		_box(room, Vector3(lx, 0.12, 1.4), Vector3(cx, 0.06, ez + side * 0.77), pave)
	# the street lamp, on the pavement by the fence
	var pole := Kit.flat(Color(0.18, 0.2, 0.2), 0.5, 0.5)
	var lamp_at := Vector3(-9.6, 0, ROAD_Z.x - 0.75)
	_cyl(room, 0.07, 4.6, lamp_at + Vector3(0, 2.3, 0), pole, 0.05)
	_box(room, Vector3(0.05, 0.05, 1.0), lamp_at + Vector3(0, 4.55, 0.5), pole)
	var head := Kit.flat(Color(0.95, 0.9, 0.75), 0.4)
	head.emission_enabled = true
	head.emission = Color(1.0, 0.85, 0.6)
	head.emission_energy_multiplier = 0.6
	_box(room, Vector3(0.22, 0.12, 0.4), lamp_at + Vector3(0, 4.48, 1.0), head)


## Pickets with pointed tops between square posts with caps, on two rails (seen from the house's side: the rails on
## the far face).
static func _fence(room: Node3D) -> void:
	var white := Kit.flat(Color(0.95, 0.95, 0.93), 0.55)
	var picket := BoxMesh.new()
	picket.size = Vector3(0.022, 1.0, 0.08)
	var tip := CylinderMesh.new()                   # (a four-sided point: a pyramid)
	tip.top_radius = 0.0
	tip.bottom_radius = 0.057
	tip.height = 0.08
	tip.radial_segments = 4
	tip.rings = 1
	var n := int((FENCE_Z.y - FENCE_Z.x) / 0.15)
	for part in [[picket, 0.5, 0.0], [tip, 1.04, PI * 0.25]]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = part[0]
		mm.instance_count = n
		for i in n:
			var z: float = FENCE_Z.x + i * 0.15
			var b := Basis(Vector3.UP, float(part[2]))
			if part[0] == tip:
				b = b.scaled(Vector3(0.28, 1.0, 1.0))
			mm.set_instance_transform(i, Transform3D(b, Vector3(FENCE_X, float(part[1]), z)))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = white
		room.add_child(mi)
	for y in [0.25, 0.8]:
		_box(room, Vector3(0.03, 0.08, FENCE_Z.y - FENCE_Z.x), Vector3(FENCE_X - 0.026, y, (FENCE_Z.x + FENCE_Z.y) * 0.5), white)
	var z := FENCE_Z.x
	while z <= FENCE_Z.y + 0.01:
		_box(room, Vector3(0.11, 1.25, 0.11), Vector3(FENCE_X - 0.03, 0.625, z), white)
		_box(room, Vector3(0.15, 0.04, 0.15), Vector3(FENCE_X - 0.03, 1.27, z), white)
		var cap := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.1
		cm.height = 0.07
		cm.radial_segments = 4
		cm.rings = 1
		cap.mesh = cm
		cap.material_override = white
		cap.position = Vector3(FENCE_X - 0.03, 1.325, z)
		cap.rotation.y = PI * 0.25
		room.add_child(cap)
		z += 2.4


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
	# a path to the porch (the first house: toward the fence; the others: their own yard)
	var reach := minf(FENCE_X - fx - 0.4, 3.0)
	_box(room, Vector3(reach, 0.02, 1.0), Vector3(fx + reach * 0.5, 0.01, dz), Kit.flat(Color(0.6, 0.6, 0.58), 0.95))


## A leafy tree modelled in Blender (tools/blender/build_tree.py -> assets/models/trees/: forking limbs, a spray of
## leaves at each twig; until v0.11.55 a trunk under a heap of green balls, the keeper: "it does not look real"),
## turned and scaled so that no two look alike; its leaves sway a little in the wind (the vertex colour's alpha).
static func _tree(room: Node3D, at: Vector3, which: String, scale: float, turn: float) -> void:
	var m := AntModel.load_antmesh("res://assets/models/trees/%s.antmesh" % which)
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
