extends RefCounted
## What one sees close by out of the Home's window (the keeper, 2026-10-27, with a photo: "only green grass close to
## the window - put a house there, a white fence and a few trees in the lawn"): a white picket fence along the edge of
## the garden, a neighbour's house beyond it - white clapboard, a grey gable roof, windows, a door with a porch, a
## chimney - two leafy trees and a few shrubs. The meadow, the forest's edge and the mountains stay painted behind them
## (shaders/home/window_view.gdshader). Built in code; metres; the window looks out along -x from x = -2
## (home_kit.W), the lawn at y = 0. home_room._window calls build().

const Kit := preload("res://scripts/view/home/home_kit.gd")
const FENCE_X := -8.0                 # the fence, along z
const FENCE_Z := Vector2(-13.0, 11.0)
const HOUSE := Vector3(-19.0, 0.0, -3.0)     # the neighbour's house: the middle of its foot
const HOUSE_SIZE := Vector3(6.5, 3.0, 9.0)   # depth (x), the walls' height, width (z)


static func build(room: Node3D) -> void:
	_fence(room)
	_house(room)
	_tree(room, Vector3(-11.5, 0, 4.5), 5.2, 1.0)
	_tree(room, Vector3(-14.5, 0, -9.0), 6.0, 1.3)
	for b in [[Vector3(-15.6, 0, 1.0), 0.8], [Vector3(-15.8, 0, -6.6), 0.9], [Vector3(-9.0, 0, -4.0), 0.6]]:
		_shrub(room, b[0], b[1])


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


## A one-storey house, white clapboard, its long side to the window.
static func _house(room: Node3D) -> void:
	var c := HOUSE
	var s := HOUSE_SIZE
	var board := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """shader_type spatial;
// clapboard: boards 16 cm high, each overlapping the one below - a shadow line under each, lighter toward its foot
varying vec3 wp;
void vertex() { wp = VERTEX; }      // (its own metres: the room is drawn scaled up round a box in the game)
void fragment() {
	float f = fract(wp.y / 0.16);
	vec3 c = vec3(0.93, 0.93, 0.9) * (0.86 + 0.14 * f);
	c *= 1.0 - 0.35 * (1.0 - smoothstep(0.0, 0.06, f));
	ALBEDO = c;
	ROUGHNESS = 0.7;
}"""
	board.shader = sh
	var trim := Kit.flat(Color(0.97, 0.97, 0.95), 0.5)
	var roof := Kit.flat(Color(0.32, 0.33, 0.35), 0.85)
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
	_box(room, Vector3(0.09, 2.0, 0.9), Vector3(fx + 0.05, 0.4 + 1.0, dz), Kit.flat(Color(0.2, 0.32, 0.3), 0.45))      # (a green door)
	for i in 3:                                                                          # the porch's steps
		_box(room, Vector3(0.9 - i * 0.3, 0.14, 1.6), Vector3(fx + 0.45 - i * 0.15, 0.07 + i * 0.14, dz), trim)
	_box(room, Vector3(1.3, 0.08, 1.9), Vector3(fx + 0.65, 2.75, dz), trim)                # the porch's little roof
	for sz in [-1, 1]:
		_box(room, Vector3(0.08, 2.3, 0.08), Vector3(fx + 1.2, 1.15, dz + sz * 0.85), trim)
	# a path to the porch
	_box(room, Vector3(FENCE_X - fx - 0.4, 0.02, 1.0), Vector3((fx + FENCE_X) * 0.5, 0.01, dz), Kit.flat(Color(0.6, 0.6, 0.58), 0.95))


## A leafy tree: a trunk forking into two, a crown of overlapping lumps, a little different in green.
static func _tree(room: Node3D, at: Vector3, tall: float, wide: float) -> void:
	var bark := Kit.flat(Color(0.3, 0.23, 0.17), 0.95)
	var trunk_h := tall * 0.45
	_cyl(room, 0.16 * wide, trunk_h, at + Vector3(0, trunk_h * 0.5, 0), bark, 0.11 * wide)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(at.x * 100.0 + at.z * 7.0)
	for k in [-1, 1]:
		var a := at + Vector3(0, trunk_h * 0.9, 0)
		var b := a + Vector3(k * 0.5 * wide, tall * 0.25, rng.randf_range(-0.3, 0.3))
		var piv := Node3D.new()
		room.add_child(piv)
		piv.look_at_from_position((a + b) * 0.5, b, Vector3.RIGHT)
		var br := _cyl(piv, 0.08 * wide, a.distance_to(b), Vector3.ZERO, bark, 0.05 * wide)
		br.rotation.x = PI * 0.5
	for i in 14:
		var leaf := Kit.flat(Color(0.2, 0.36, 0.13).lerp(Color(0.33, 0.48, 0.18), rng.randf()), 0.9)
		var r := rng.randf_range(0.7, 1.15) * wide
		var p := at + Vector3(rng.randfn(0.0, 0.8) * wide, tall * 0.68 + rng.randfn(0.0, 0.5), rng.randfn(0.0, 0.8) * wide)
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = r
		sm.height = r * 1.7
		sm.radial_segments = 14
		sm.rings = 8
		mi.mesh = sm
		mi.material_override = leaf
		mi.position = p
		room.add_child(mi)


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
