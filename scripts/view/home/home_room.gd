extends Node3D
## The Home room (the keeper, 2026-10-26), built in code: a small room 4 x 4 m and 2.6 m high, a desk against the far
## wall with the tanks on it (each a formicarium about 30 x 20 x 15 cm on a wooden base), a chair, a window on the
## left wall with the day (or night) outside, a door on the right (not open yet), a ceiling lamp. Metres; y up; the
## desk wall at -z. game/home.gd owns it (camera, pointer, what a click does).

const Wood := preload("res://shaders/home/wood.gdshader")
const W := 4.0                    # the room, x and z
const H := 2.6
const DESK := Vector3(0.0, 0.75, -1.62)      # the desk top's centre (its top surface at y 0.75)
const DESK_SIZE := Vector3(1.5, 0.04, 0.72)
const TANK := Vector3(0.30, 0.20, 0.15)      # a small tank's glass
const BIG := Vector3(0.44, 0.27, 0.22)       # the bigger one's (the shop's second tank)
const SHELF_D := 0.3                         # a shelf's depth; each column 0.45 wide, two tiers
const SHELF_Y := [0.55, 1.08]                # the tops of its boards a tank stands on
# where the shelves go, in the order they are bought: the foot's centre against a wall, and its turn (front to the room)
const SHELF_AT := [[Vector3(1.45, 0, -1.85), 0.0], [Vector3(-1.0, 0, 1.85), PI], [Vector3(0.55, 0, 1.85), PI],
	[Vector3(-1.85, 0, 1.0), PI * 0.5]]
const DOOR := Vector3(1.98, 0.0, 0.85)       # the door's foot, on the right wall
const WIN_Z := -0.7                          # the window's centre along the left wall
var blocks: Array = []            # Rect2s on the floor (x, z) the keeper cannot walk into: the desk and the shelves
var items: Array = []             # what the pointer can be on: {"kind": "tank"|"door", "box": AABB, "slot": n, "mats": [...]}
var _sun: DirectionalLight3D
var _lamp: OmniLight3D
var _sky: StandardMaterial3D


## places: home_store.places() (where each tank stands); shelves: how many tanks each shelf bought holds.
func build(places: Array, shelves: Array, filled: Callable, day: bool) -> void:
	_room()
	_window(day)
	_desk()
	_chair()
	_door()
	_lights(day)
	blocks.append(Rect2(DESK.x - DESK_SIZE.x * 0.5, DESK.z - DESK_SIZE.z * 0.5, DESK_SIZE.x, DESK_SIZE.z))
	var units: Array = []
	for i in mini(shelves.size(), SHELF_AT.size()):
		units.append(_shelf(i, int(shelves[i])))
	# on the desk: the small one in the middle, or left of the big one
	var has_big := places.any(func(p): return p.big)
	var top := DESK.y + DESK_SIZE.y * 0.5
	for p in places:
		var full: bool = filled.call(int(p.slot))
		if p.shelf == -1:
			var x := 0.0 if not has_big else (0.3 if p.big else -0.25)
			_tank(self, Vector3(DESK.x + x, top, DESK.z + 0.05), BIG if p.big else TANK, int(p.slot), int(p.number), full)
		elif p.shelf >= 0 and p.shelf < units.size():
			var cols := int(shelves[p.shelf]) / 2
			var col: int = int(p.spot) % cols
			var tier: int = int(p.spot) / cols
			_tank(units[p.shelf], Vector3((col - (cols - 1) * 0.5) * 0.45, SHELF_Y[tier], 0.0), TANK, int(p.slot), int(p.number), full)


## A shelf against a wall: two tiers of boards, one column for each two tanks it holds.
func _shelf(i: int, holds: int) -> Node3D:
	var u := Node3D.new()
	u.position = SHELF_AT[i][0]
	u.rotation.y = SHELF_AT[i][1]
	add_child(u)
	var w := 0.45 * (holds / 2)
	var m := wood(Color(0.5, 0.36, 0.22), Color(0.66, 0.5, 0.33), 9.0, 9.0, 55.0)
	for y in [0.06] + SHELF_Y:
		_box(Vector3(w, 0.025, SHELF_D), Vector3(0, y - 0.0125, 0), m, u)
	for sx in [-1, 1]:
		_box(Vector3(0.025, SHELF_Y[1], SHELF_D), Vector3(sx * (w * 0.5 + 0.0125), SHELF_Y[1] * 0.5, 0), m, u)
	_box(Vector3(w, SHELF_Y[1], 0.01), Vector3(0, SHELF_Y[1] * 0.5, -SHELF_D * 0.5 + 0.005), m, u)      # the back
	var r := (u.transform * AABB(Vector3(-w * 0.5 - 0.03, 0, -SHELF_D * 0.5), Vector3(w + 0.06, 1, SHELF_D)))
	blocks.append(Rect2(r.position.x, r.position.z, r.size.x, r.size.z))
	return u


# ---------------------------------------------------------------- materials and pieces

static func wood(a: Color, b: Color, plank_w := 9.0, plank_l := 9.0, grain := 60.0, along_z := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = Wood
	m.set_shader_parameter("tint_a", a)
	m.set_shader_parameter("tint_b", b)
	m.set_shader_parameter("plank_w", plank_w)
	m.set_shader_parameter("plank_l", plank_l)
	m.set_shader_parameter("grain", grain)
	m.set_shader_parameter("along_z", along_z)
	return m


static func flat(c: Color, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _box(size: Vector3, centre: Vector3, mat: Material, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = centre
	parent.add_child(mi)
	return mi


func _cyl(r: float, h: float, centre: Vector3, mat: Material, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 16
	mi.mesh = cm
	mi.material_override = mat
	mi.position = centre
	parent.add_child(mi)
	return mi


func _room() -> void:
	var floor_m := wood(Color(0.36, 0.22, 0.12), Color(0.55, 0.36, 0.2), 0.14, 1.3, 70.0)
	_box(Vector3(W, 0.05, W), Vector3(0, -0.025, 0), floor_m)
	var wall := flat(Color(0.86, 0.83, 0.76), 0.92)
	var ceil_m := flat(Color(0.93, 0.92, 0.89), 0.95)
	_box(Vector3(W, 0.05, W), Vector3(0, H + 0.025, 0), ceil_m)
	_box(Vector3(W, H, 0.1), Vector3(0, H * 0.5, -W * 0.5 - 0.05), wall)          # behind the desk
	_box(Vector3(W, H, 0.1), Vector3(0, H * 0.5, W * 0.5 + 0.05), wall)           # behind the keeper
	# the left wall, round the window (1.2 wide, 1.2 high, its sill at 0.9)
	var x := -W * 0.5 - 0.05
	var z0 := WIN_Z - 0.6
	var z1 := WIN_Z + 0.6
	_box(Vector3(0.1, H, z0 + W * 0.5), Vector3(x, H * 0.5, (-W * 0.5 + z0) * 0.5), wall)
	_box(Vector3(0.1, H, W * 0.5 - z1), Vector3(x, H * 0.5, (z1 + W * 0.5) * 0.5), wall)
	_box(Vector3(0.1, 0.9, 1.2), Vector3(x, 0.45, WIN_Z), wall)
	_box(Vector3(0.1, H - 2.1, 1.2), Vector3(x, (2.1 + H) * 0.5, WIN_Z), wall)
	# the right wall, round the door (0.9 wide, 2.05 high)
	x = W * 0.5 + 0.05
	z0 = DOOR.z - 0.45
	z1 = DOOR.z + 0.45
	_box(Vector3(0.1, H, z0 + W * 0.5), Vector3(x, H * 0.5, (-W * 0.5 + z0) * 0.5), wall)
	_box(Vector3(0.1, H, W * 0.5 - z1), Vector3(x, H * 0.5, (z1 + W * 0.5) * 0.5), wall)
	_box(Vector3(0.1, H - 2.05, 0.9), Vector3(x, (2.05 + H) * 0.5, DOOR.z), wall)
	# skirting boards
	var skirt := flat(Color(0.93, 0.92, 0.88), 0.6)
	_box(Vector3(W, 0.08, 0.015), Vector3(0, 0.04, -W * 0.5 + 0.008), skirt)
	_box(Vector3(W, 0.08, 0.015), Vector3(0, 0.04, W * 0.5 - 0.008), skirt)
	_box(Vector3(0.015, 0.08, W), Vector3(-W * 0.5 + 0.008, 0.04, 0), skirt)
	_box(Vector3(0.015, 0.08, W), Vector3(W * 0.5 - 0.008, 0.04, 0), skirt)
	# a rug in the middle
	var rug := flat(Color(0.45, 0.2, 0.14), 1.0)
	_box(Vector3(1.6, 0.008, 1.1), Vector3(0.1, 0.004, 0.2), rug)
	_box(Vector3(1.4, 0.009, 0.9), Vector3(0.1, 0.0045, 0.2), flat(Color(0.62, 0.48, 0.3), 1.0))
	_box(Vector3(1.2, 0.01, 0.7), Vector3(0.1, 0.005, 0.2), rug)


func _window(day: bool) -> void:
	var x := -W * 0.5
	var frame := flat(Color(0.95, 0.95, 0.93), 0.45)
	_box(Vector3(0.12, 0.05, 1.3), Vector3(x, 0.875, WIN_Z), frame)        # sill
	_box(Vector3(0.1, 0.05, 1.3), Vector3(x - 0.02, 2.125, WIN_Z), frame)
	_box(Vector3(0.1, 1.3, 0.05), Vector3(x - 0.02, 1.5, WIN_Z - 0.625), frame)
	_box(Vector3(0.1, 1.3, 0.05), Vector3(x - 0.02, 1.5, WIN_Z + 0.625), frame)
	_box(Vector3(0.06, 1.2, 0.04), Vector3(x - 0.04, 1.5, WIN_Z), frame)     # the middle bar
	# outside: the sky and a hedge, unlit (it is the light, not lit by it)
	_sky = StandardMaterial3D.new()
	_sky.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_sky.albedo_color = Color(0.68, 0.82, 0.95) if day else Color(0.04, 0.06, 0.12)
	# (wide enough to fill the window seen from anywhere in the room)
	_box(Vector3(0.02, 6.0, 9.0), Vector3(x - 2.5, 2.0, WIN_Z), _sky).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var hedge := StandardMaterial3D.new()
	hedge.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hedge.albedo_color = Color(0.25, 0.42, 0.2) if day else Color(0.02, 0.04, 0.03)
	_box(Vector3(0.3, 1.3, 9.0), Vector3(x - 2.2, 0.65, WIN_Z), hedge).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var lawn := StandardMaterial3D.new()
	lawn.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lawn.albedo_color = Color(0.36, 0.52, 0.26) if day else Color(0.03, 0.05, 0.03)
	_box(Vector3(2.2, 0.02, 9.0), Vector3(x - 1.1, 0.0, WIN_Z), lawn).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# a plant on the sill
	_cyl(0.07, 0.13, Vector3(x + 0.04, 0.965, WIN_Z + 0.4), flat(Color(0.62, 0.32, 0.2), 0.9))
	var leaf := flat(Color(0.18, 0.4, 0.16), 0.7)
	for i in 7:
		var a := i * 2.4
		var l := _box(Vector3(0.025, 0.16, 0.06), Vector3(x + 0.04 + cos(a) * 0.04, 1.1, WIN_Z + 0.4 + sin(a) * 0.04), leaf)
		l.rotation = Vector3(cos(a) * 0.5, a, sin(a) * 0.5)


func _desk() -> void:
	var top := wood(Color(0.4, 0.25, 0.13), Color(0.58, 0.4, 0.23), 9.0, 9.0, 45.0)
	_box(DESK_SIZE, DESK, top)
	var leg := wood(Color(0.36, 0.22, 0.12), Color(0.5, 0.33, 0.19), 9.0, 9.0, 45.0)
	var lh := DESK.y - DESK_SIZE.y * 0.5
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_box(Vector3(0.05, lh, 0.05), Vector3(DESK.x + sx * (DESK_SIZE.x * 0.5 - 0.05), lh * 0.5, DESK.z + sz * (DESK_SIZE.z * 0.5 - 0.05)), leg)
	_box(Vector3(DESK_SIZE.x - 0.1, 0.1, 0.02), Vector3(DESK.x, lh - 0.05, DESK.z - DESK_SIZE.z * 0.5 + 0.05), leg)    # the back rail
	# a drawer on the right, a notebook and a pencil on the left
	_box(Vector3(0.45, 0.12, 0.02), Vector3(DESK.x + 0.45, lh - 0.07, DESK.z + DESK_SIZE.z * 0.5 - 0.03), leg)
	_cyl(0.012, 0.03, Vector3(DESK.x + 0.45, lh - 0.07, DESK.z + DESK_SIZE.z * 0.5 - 0.005), flat(Color(0.7, 0.6, 0.35), 0.3, 0.8)).rotation.x = PI * 0.5
	var y := DESK.y + DESK_SIZE.y * 0.5
	var book := _box(Vector3(0.15, 0.012, 0.21), Vector3(DESK.x - 0.55, y + 0.006, DESK.z + 0.12), flat(Color(0.74, 0.6, 0.43), 0.9))
	book.rotation.y = 0.2
	var pencil := _cyl(0.004, 0.17, Vector3(DESK.x - 0.44, y + 0.004, DESK.z + 0.2), flat(Color(0.85, 0.65, 0.15), 0.5))
	pencil.rotation = Vector3(0, 0.5, PI * 0.5)


func _chair() -> void:
	var c := Node3D.new()
	c.position = Vector3(DESK.x + 0.1, 0, DESK.z + 0.75)
	c.rotation.y = -0.25
	add_child(c)
	var m := wood(Color(0.33, 0.2, 0.1), Color(0.48, 0.3, 0.16), 9.0, 9.0, 45.0)
	_box(Vector3(0.42, 0.035, 0.4), Vector3(0, 0.45, 0), m, c)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_box(Vector3(0.035, 0.45, 0.035), Vector3(sx * 0.18, 0.225, sz * 0.17), m, c)
		_box(Vector3(0.035, 0.45, 0.035), Vector3(sx * 0.18, 0.69, 0.17), m, c)
	_box(Vector3(0.4, 0.12, 0.02), Vector3(0, 0.84, 0.175), m, c)
	_box(Vector3(0.4, 0.05, 0.02), Vector3(0, 0.66, 0.175), m, c)


func _door() -> void:
	var x := W * 0.5
	var casing := flat(Color(0.95, 0.95, 0.93), 0.45)
	_box(Vector3(0.03, 2.12, 0.07), Vector3(x - 0.015, 1.06, DOOR.z - 0.485), casing)
	_box(Vector3(0.03, 2.12, 0.07), Vector3(x - 0.015, 1.06, DOOR.z + 0.485), casing)
	_box(Vector3(0.03, 0.07, 1.04), Vector3(x - 0.015, 2.085, DOOR.z), casing)
	var leaf := wood(Color(0.42, 0.27, 0.15), Color(0.56, 0.38, 0.22), 9.0, 9.0, 40.0)
	var d := _box(Vector3(0.04, 2.03, 0.88), Vector3(x + 0.0, 1.015, DOOR.z), leaf)
	# raised panels on the room side
	for py in [0.55, 1.45]:
		_box(Vector3(0.012, 0.7, 0.32), Vector3(x - 0.026, py, DOOR.z - 0.2), leaf)
		_box(Vector3(0.012, 0.7, 0.32), Vector3(x - 0.026, py, DOOR.z + 0.2), leaf)
	var brass := flat(Color(0.78, 0.62, 0.3), 0.3, 0.9)
	_box(Vector3(0.01, 0.16, 0.04), Vector3(x - 0.025, 1.0, DOOR.z - 0.36), brass)
	var knob := _cyl(0.012, 0.12, Vector3(x - 0.07, 1.04, DOOR.z - 0.36), brass)
	knob.rotation.z = PI * 0.5
	items.append({"kind": "door", "box": AABB(Vector3(x - 0.1, 0.0, DOOR.z - 0.45), Vector3(0.12, 2.05, 0.9)), "mats": [], "node": d})


func _lights(day: bool) -> void:
	# the ceiling lamp: a shade and a warm bulb
	_cyl(0.18, 0.12, Vector3(0, H - 0.25, 0), flat(Color(0.92, 0.88, 0.8), 0.8))
	_cyl(0.005, 0.2, Vector3(0, H - 0.1, 0), flat(Color(0.1, 0.1, 0.1)))
	_lamp = OmniLight3D.new()
	_lamp.position = Vector3(0, H - 0.4, 0)
	_lamp.light_color = Color(1.0, 0.82, 0.6)
	_lamp.light_energy = 0.7 if day else 1.6
	_lamp.omni_range = 6.0
	_lamp.shadow_enabled = true
	add_child(_lamp)
	if day:
		# the sun through the window, low over the hedge
		_sun = DirectionalLight3D.new()
		_sun.light_color = Color(1.0, 0.93, 0.8)
		_sun.light_energy = 1.6
		_sun.shadow_enabled = true
		_sun.rotation = Vector3(-0.55, -PI * 0.5 - 0.35, 0)
		add_child(_sun)
	# the desk lamp's light on the tanks
	var spot := SpotLight3D.new()
	spot.position = Vector3(DESK.x - 0.5, DESK.y + 0.6, DESK.z + 0.1)
	spot.look_at_from_position(spot.position, Vector3(DESK.x, DESK.y, DESK.z), Vector3.UP)
	spot.light_color = Color(1.0, 0.88, 0.7)
	spot.light_energy = 1.2 if day else 2.2
	spot.spot_range = 1.6
	spot.spot_angle = 40.0
	spot.shadow_enabled = true
	add_child(spot)
	# the lamp itself
	var metal := flat(Color(0.15, 0.17, 0.16), 0.4, 0.6)
	var by := DESK.y + DESK_SIZE.y * 0.5
	_cyl(0.07, 0.015, Vector3(DESK.x - 0.58, by + 0.008, DESK.z - 0.15), metal)
	var foot := Vector3(DESK.x - 0.58, by + 0.01, DESK.z - 0.15)
	var head := Vector3(DESK.x - 0.5, by + 0.52, DESK.z - 0.02)
	_rod(foot, head, 0.008, metal)
	# the shade, a cone, its open end to the tanks
	var piv := Node3D.new()
	add_child(piv)
	piv.look_at_from_position(head, Vector3(DESK.x - 0.1, DESK.y, DESK.z + 0.05), Vector3.UP)
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.025
	cm.bottom_radius = 0.075
	cm.height = 0.12
	cm.radial_segments = 20
	cone.mesh = cm
	cone.material_override = metal
	cone.rotation.x = PI * 0.5            # (its wide end, -y, along the pivot's -z: to the tanks)
	cone.position = Vector3(0, 0, -0.05)
	piv.add_child(cone)
	var bulb := flat(Color(1, 0.95, 0.85))
	bulb.emission_enabled = true
	bulb.emission = Color(1, 0.9, 0.7)
	bulb.emission_energy_multiplier = 3.0
	var b := _cyl(0.06, 0.004, Vector3(0, 0, -0.105), bulb, piv)
	b.rotation.x = PI * 0.5


## A thin rod from a to b.
func _rod(a: Vector3, b: Vector3, r: float, mat: Material) -> void:
	var piv := Node3D.new()
	add_child(piv)
	piv.look_at_from_position((a + b) * 0.5, b, Vector3.UP if absf((b - a).normalized().y) < 0.99 else Vector3.RIGHT)
	var c := _cyl(r, a.distance_to(b), Vector3.ZERO, mat, piv)
	c.rotation.x = PI * 0.5


## One tank: a wooden base, glass, a wooden lid with a vent, and, when it has a colony, soil with tunnels against the
## front glass; a card with its number on the base.
func _tank(parent: Node3D, at: Vector3, sz: Vector3, slot: int, number: int, has_colony: bool) -> void:
	var t := Node3D.new()
	t.position = at
	parent.add_child(t)
	var base_m := wood(Color(0.32, 0.2, 0.1), Color(0.46, 0.29, 0.15), 9.0, 9.0, 50.0)
	var lid_m := base_m.duplicate()
	_box(Vector3(sz.x + 0.02, 0.025, sz.z + 0.02), Vector3(0, 0.0125, 0), base_m, t)
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.85, 0.95, 0.95, 0.1)
	glass.roughness = 0.04
	glass.metallic_specular = 0.9
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var g := _box(sz, Vector3(0, 0.025 + sz.y * 0.5, 0), glass, t)
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_box(Vector3(sz.x + 0.012, 0.015, sz.z + 0.012), Vector3(0, 0.025 + sz.y + 0.0075, 0), lid_m, t)
	_box(Vector3(0.08, 0.004, 0.05), Vector3(0.07, 0.025 + sz.y + 0.016, 0), flat(Color(0.2, 0.2, 0.2), 0.6, 0.5), t)
	if has_colony:
		var soil := ShaderMaterial.new()
		soil.shader = _soil_shader()
		soil.set_shader_parameter("seed", float(slot) * 3.7)
		_box(Vector3(sz.x - 0.006, sz.y * 0.72, sz.z - 0.006), Vector3(0, 0.025 + sz.y * 0.36, 0), soil, t)
	# the card with its number
	var card := Label3D.new()
	card.text = str(number)
	card.font_size = 48
	card.pixel_size = 0.0005
	card.modulate = Color(0.16, 0.11, 0.07)
	card.outline_size = 0
	card.position = Vector3(-sz.x * 0.5 + 0.03, 0.0125, sz.z * 0.5 + 0.0105)
	card.double_sided = false
	t.add_child(card)
	_box(Vector3(0.04, 0.02, 0.001), Vector3(-sz.x * 0.5 + 0.03, 0.0125, sz.z * 0.5 + 0.0102), flat(Color(0.9, 0.85, 0.72), 0.9), t)
	items.append({"kind": "tank", "slot": slot, "number": number, "mats": [base_m, lid_m],
		"box": t.global_transform * AABB(Vector3(-sz.x * 0.5 - 0.01, 0, -sz.z * 0.5 - 0.01), Vector3(sz.x + 0.02, sz.y + 0.05, sz.z + 0.02))})


static var _soil: Shader

static func _soil_shader() -> Shader:
	if _soil == null:
		_soil = Shader.new()
		_soil.code = """
shader_type spatial;
// soil in a tank, with the colony's tunnels and chambers dark against the front glass
uniform float seed = 0.0;
varying vec3 opos;
float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y); }
void vertex() { opos = VERTEX; }
void fragment() {
	vec2 p = opos.xy * 40.0 + seed;
	float n = vn(p) * 0.5 + vn(p * 2.3) * 0.3 + vn(p * 7.0) * 0.2;
	vec3 c = mix(vec3(0.22, 0.14, 0.08), vec3(0.36, 0.25, 0.15), n);
	c *= 0.85 + 0.3 * h2(floor(opos.xy * 900.0));
	// tunnels: thin wandering lines, wider where they meet (chambers), only below the top
	float t = abs(vn(opos.xy * 22.0 + seed * 1.3) - 0.5);
	float ch = vn(opos.xy * 9.0 + seed * 2.1);
	float tun = 1.0 - smoothstep(0.018, 0.03 + 0.05 * smoothstep(0.62, 0.8, ch), t);
	tun *= smoothstep(0.065, 0.045, opos.y);
	c = mix(c, vec3(0.06, 0.04, 0.025), tun);
	ALBEDO = c;
	ROUGHNESS = 0.95;
}
"""
	return _soil


## The pointer on an item (or none): its base glows a little.
func hover(item) -> void:
	for it in items:
		for m in it.mats:
			m.set_shader_parameter("hilite", 1.0 if is_same(it, item) else 0.0)
