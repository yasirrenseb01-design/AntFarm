extends "res://scripts/view/home/home_kit.gd"
## The Home room, layer 2 of 2 (the keeper, 2026-10-26; in two layers from v0.11.49): a small room 4 x 4 m and 2.6 m high
## - a desk against the far wall with the tanks on it, a chair, a window on the left wall looking out on a meadow, a
## forest and mountains (painted in code: shaders/home/window_view.gdshader), a door on the right (not open yet), a rug,
## a ceiling lamp and a desk lamp, the shelves bought. The light follows the computer's clock (set_hour): the sun comes
## in through the window and its patch moves over the floor through the day, warm and low in the morning and evening;
## at night the lamps. game/home.gd owns it (camera, the hand, what a click does).

const View := preload("res://shaders/home/window_view.gdshader")
const Yard := preload("res://scripts/view/home/home_yard.gd")
const Fridge := preload("res://scripts/view/home/home_fridge.gd")
const Zodiac := preload("res://scripts/view/home/zodiac_stars.gd")
const FRIDGE_AT := Vector3(-1.58, 0.0, -1.66)    # the wintering fridge: the corner left of the desk, its door to the room
const SHELF_D := 0.42                        # a shelf's depth; a column for a small tank (tank_spec), two tiers
const SHELF_COL := 0.69
const SHELF_Y := [0.55, 1.08]                # the tops of its boards a tank stands on
# where the shelves go, in the order they are bought: the foot's centre against a wall, and its turn (front to the room)
# (v0.11.53, the tanks as big as the game's: two along the wall behind the keeper, one on the left by the window, one on
# the right between the desk and the door)
const SHELF_AT := [[Vector3(-1.0, 0, 1.79), PI], [Vector3(0.55, 0, 1.79), PI], [Vector3(-1.79, 0, 0.7), PI * 0.5],
	[Vector3(1.79, 0, -0.8), -PI * 0.5]]
const DESK_SMALL_X := -0.313                 # the small tank on the desk, left of the middle; the bigger one right of it
const DESK_BIG_X := 0.463
var lamp_gain := 1.0                         # the lamps' light falls off as distance to the power of their
var spot_gain := 1.0                         # attenuation: the room drawn scaled up (keeper_room.gd) makes up for it
var doy := -1.0                              # the day of the year for the stars (-1: the computer's date; the game's in a colony)
var fridge_light: OmniLight3D                # (keeper_room.gd: lights do not scale)
var lamp_on := true                          # the desk lamp switched on (its switch: a click on it - game/home.gd)
var _bulb: StandardMaterial3D
var tank_nodes := {}                         # slot -> its tank's node (keeper_room.gd puts the game's box there)
var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _lamp: OmniLight3D
var _spot: SpotLight3D
var _env: Environment
var _views: Array = []            # the window view's materials (far, near)
var _lawn: StandardMaterial3D


## places: home_store.places() (where each tank stands); shelves: how many tanks each shelf bought holds; hour: the
## clock's; env: the room's environment (its ambient light follows the hour); hide: a slot whose tank is not drawn (the
## colony open in the game, its box drawn there by the foraging view instead).
func build(places: Array, shelves: Array, filled: Callable, hour: float, env: Environment, hide := 0) -> void:
	_env = env
	_room()
	_window()
	_desk()
	_chair()
	_door()
	_lights()
	_rug(Vector3(0.1, 0, 0.25), Vector2(1.6, 1.1))
	blocks.append(Rect2(DESK.x - DESK_SIZE.x * 0.5, DESK.z - DESK_SIZE.z * 0.5, DESK_SIZE.x, DESK_SIZE.z))
	var units: Array = []
	for i in mini(shelves.size(), SHELF_AT.size()):
		units.append(_shelf(i, int(shelves[i])))
	# the wintering fridge; a small tank whose colony is resting in it stands on one of its shelves (home_fridge.gd)
	var fr: Dictionary = Fridge.build(self, FRIDGE_AT, 0.0)
	fridge_light = fr.light
	var fs: Vector3 = Fridge.SIZE
	blocks.append(Rect2(FRIDGE_AT.x - fs.x * 0.5, FRIDGE_AT.z - fs.z * 0.5, fs.x, fs.z + 0.05))
	var resting := []
	var free_spots: Array = fr.spots.duplicate()
	# on the desk, against the wall: the small one left of the middle, the bigger one right of it
	var top := DESK.y + DESK_SIZE.y * 0.5
	for p in places:
		var s := int(p.slot)
		var full: bool = filled.call(s)
		if full and bool(Store.meta(s).get("fridge", false)):
			resting.append(int(p.number))
			if not p.big and not p.get("farm", false) and not free_spots.is_empty():
				var t2: Node3D = _tank(fr.node, free_spots.pop_front(), false, false, s, int(p.number), true,
					float(Store.meta(s).get("nest_x0", (Spec.SMALL.x - Spec.NEST.x) * 0.5)))
				tank_nodes[s] = t2
				if s == hide:
					t2.visible = false
					items.pop_back()
				continue
		var big: bool = p.big
		var farm: bool = p.get("farm", false)
		var f := Spec.floor_of(big)
		var x0 := float(Store.meta(s).get("nest_x0", (f.x - Spec.NEST.x) * 0.5)) if full else 0.0
		var t: Node3D = null
		if p.shelf == -1:
			var d := Spec.outside(big).z
			t = _tank(self, Vector3(DESK_BIG_X if big else DESK_SMALL_X, top, DESK.z - DESK_SIZE.z * 0.5 + 0.03 + d * 0.5),
				big, farm, s, int(p.number), full, x0)
		elif p.shelf >= 0 and p.shelf < units.size():
			var cols := int(shelves[p.shelf]) / 2
			var col: int = int(p.spot) % cols
			var tier: int = int(p.spot) / cols
			t = _tank(units[p.shelf], Vector3((col - (cols - 1) * 0.5) * SHELF_COL, SHELF_Y[tier], 0.0), big, farm, s, int(p.number), full, x0)
		if t != null:
			tank_nodes[s] = t
			if s == hide:
				t.visible = false
				items.pop_back()
	items.append({"kind": "fridge", "mats": [], "resting": resting,
		"box": AABB(FRIDGE_AT - Vector3(fs.x * 0.5, 0, fs.z * 0.5), fs + Vector3(0, 0, 0.06))})
	set_hour(hour)


## A shelf against a wall: two tiers of boards, one column for each two tanks it holds.
func _shelf(i: int, holds: int) -> Node3D:
	var u := Node3D.new()
	u.position = SHELF_AT[i][0]
	u.rotation.y = SHELF_AT[i][1]
	add_child(u)
	var w := SHELF_COL * (holds / 2)
	var m := wood(Color(0.5, 0.36, 0.22), Color(0.66, 0.5, 0.33), 9.0, 9.0, 55.0)
	for y in [0.06] + SHELF_Y:
		_box(Vector3(w, 0.025, SHELF_D), Vector3(0, y - 0.0125, 0), m, u)
	for sx in [-1, 1]:
		_box(Vector3(0.025, SHELF_Y[1], SHELF_D), Vector3(sx * (w * 0.5 + 0.0125), SHELF_Y[1] * 0.5, 0), m, u)
	_box(Vector3(w, SHELF_Y[1], 0.01), Vector3(0, SHELF_Y[1] * 0.5, -SHELF_D * 0.5 + 0.005), m, u)      # the back
	var r := (u.transform * AABB(Vector3(-w * 0.5 - 0.03, 0, -SHELF_D * 0.5), Vector3(w + 0.06, 1, SHELF_D)))
	blocks.append(Rect2(r.position.x, r.position.z, r.size.x, r.size.z))
	return u


func _room() -> void:
	var floor_m := wood(Color(0.36, 0.21, 0.11), Color(0.56, 0.35, 0.19), 0.14, 1.3, 70.0)
	_box(Vector3(W, 0.05, W), Vector3(0, -0.025, 0), floor_m)
	var wall := flat(Color(0.9, 0.82, 0.69), 0.92)           # (a warm cream: the keeper, 2026-10-27 "cozy")
	var ceil_m := flat(Color(0.95, 0.91, 0.84), 0.95)
	# (over the walls' tops: a ceiling only as wide as the room let the sun in along its edges - a bright line on top of
	# every wall, the keeper, 2026-10-27)
	_box(Vector3(W + 0.4, 0.1, W + 0.4), Vector3(0, H + 0.05, 0), ceil_m)
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
	var skirt := flat(Color(0.95, 0.92, 0.86), 0.6)
	_box(Vector3(W, 0.08, 0.015), Vector3(0, 0.04, -W * 0.5 + 0.008), skirt)
	_box(Vector3(W, 0.08, 0.015), Vector3(0, 0.04, W * 0.5 - 0.008), skirt)
	_box(Vector3(0.015, 0.08, W), Vector3(-W * 0.5 + 0.008, 0.04, 0), skirt)
	_box(Vector3(0.015, 0.08, W), Vector3(W * 0.5 - 0.008, 0.04, 0), skirt)


func _window() -> void:
	var x := -W * 0.5
	var frame := flat(Color(0.95, 0.93, 0.88), 0.45)
	_box(Vector3(0.12, 0.05, 1.3), Vector3(x, 0.875, WIN_Z), frame)        # sill
	_box(Vector3(0.1, 0.05, 1.3), Vector3(x - 0.02, 2.125, WIN_Z), frame)
	_box(Vector3(0.1, 1.3, 0.05), Vector3(x - 0.02, 1.5, WIN_Z - 0.625), frame)
	_box(Vector3(0.1, 1.3, 0.05), Vector3(x - 0.02, 1.5, WIN_Z + 0.625), frame)
	_box(Vector3(0.06, 1.2, 0.04), Vector3(x - 0.04, 1.5, WIN_Z), frame)     # the middle bar
	# outside: far - the sky and the mountains; near - the forest's edge; nearest - the meadow. Painted on two cylinders
	# round the house, so that close to the window, looking along it, one never sees past their edge (the keeper,
	# 2026-10-27, saw the black beyond the flat planes of v0.11.49)
	for near in [false, true]:
		var m := ShaderMaterial.new()
		m.shader = View
		m.set_shader_parameter("near", near)
		m.set_shader_parameter("wrap", 6.0 if near else 3.0)
		m.set_shader_parameter("y0", (3.5 if near else 40.0) - (5.0 if near else 85.0))
		m.set_shader_parameter("height", 10.0 if near else 170.0)
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 26.0 if near else 150.0
		cm.bottom_radius = cm.top_radius
		cm.height = 10.0 if near else 170.0
		cm.cap_top = not near                     # (the sky's top: no background showing through, looking up)
		cm.cap_bottom = false
		cm.radial_segments = 96
		cm.rings = 1
		mi.mesh = cm
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(0, 3.5 if near else 40.0, 0)
		add_child(mi)
		_views.append(m)
	_lawn = StandardMaterial3D.new()
	_lawn.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# (mown grass: lighter and darker patches, not one flat green)
	var nt := NoiseTexture2D.new()
	var nz := FastNoiseLite.new()
	nz.frequency = 0.02
	nt.noise = nz
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.55, 0.62, 0.45))
	ramp.set_color(1, Color(0.85, 0.92, 0.72))
	nt.color_ramp = ramp
	_lawn.albedo_texture = nt
	_lawn.uv1_scale = Vector3(60, 60, 60)
	_cyl(160.0, 0.02, Vector3(0, -0.03, 0), _lawn, self, -1.0, 64).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_plant(Vector3(x + 0.05, 0.9, WIN_Z + 0.42))
	Yard.build(self)                         # (close by: a fence, a neighbour's house, trees: home_yard.gd)


func _desk() -> void:
	var top := wood(Color(0.4, 0.25, 0.13), Color(0.58, 0.4, 0.23), 9.0, 9.0, 45.0)
	_box(DESK_SIZE, DESK, top)
	var leg := wood(Color(0.36, 0.22, 0.12), Color(0.5, 0.33, 0.19), 9.0, 9.0, 45.0)
	var lh := DESK.y - DESK_SIZE.y * 0.5
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_box(Vector3(0.05, lh, 0.05), Vector3(DESK.x + sx * (DESK_SIZE.x * 0.5 - 0.05), lh * 0.5, DESK.z + sz * (DESK_SIZE.z * 0.5 - 0.05)), leg)
	_box(Vector3(DESK_SIZE.x - 0.1, 0.1, 0.02), Vector3(DESK.x, lh - 0.05, DESK.z - DESK_SIZE.z * 0.5 + 0.05), leg)    # the back rail
	_drawer(Vector3(DESK.x + 0.45, lh - 0.07, DESK.z + DESK_SIZE.z * 0.5 - 0.03), 0.45, 0.12)
	var y := DESK.y + DESK_SIZE.y * 0.5
	_notebook(Vector3(DESK.x - 0.72, y, DESK.z + 0.22), 0.2)
	_pencil(Vector3(DESK.x - 0.52, y, DESK.z + 0.3), 0.5)


func _lights() -> void:
	# the ceiling lamp: a fabric shade, a warm bulb
	var shade := flat(Color(0.93, 0.86, 0.74), 0.85)
	shade.emission_enabled = true
	shade.emission = Color(1.0, 0.8, 0.55)
	shade.emission_energy_multiplier = 0.25
	# (a fabric shade lets the light through: no shadow of it on the ceiling - it drew a dark disc there)
	_cyl(0.2, 0.14, Vector3(0, H - 0.26, 0), shade, self, 0.16, 32).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cyl(0.005, 0.18, Vector3(0, H - 0.1, 0), flat(Color(0.1, 0.1, 0.1)))
	_lamp = OmniLight3D.new()
	_lamp.position = Vector3(0, H - 0.42, 0)
	_lamp.light_color = Color(1.0, 0.78, 0.52)
	_lamp.omni_range = 6.5
	_lamp.omni_attenuation = 1.3
	_lamp.shadow_enabled = true
	add_child(_lamp)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.shadow_blur = 1.5
	add_child(_sun)
	_moon = DirectionalLight3D.new()
	_moon.light_color = Color(0.55, 0.65, 0.95)
	_moon.light_energy = 0.0
	_moon.shadow_enabled = true
	_moon.rotation = Vector3(-0.7, -PI * 0.5 + 0.3, 0)
	add_child(_moon)
	# the desk lamp's light on the tanks
	_spot = SpotLight3D.new()
	_spot.position = Vector3(DESK.x - 0.7, DESK.y + 0.6, DESK.z)
	_spot.look_at_from_position(_spot.position, Vector3(DESK.x, DESK.y, DESK.z - 0.15), Vector3.UP)
	_spot.light_color = Color(1.0, 0.82, 0.58)
	_spot.spot_range = 1.7
	_spot.spot_angle = 58.0                 # (a soft-edged pool: 42 at 1.6 drew a hard circle on the wall)
	_spot.spot_angle_attenuation = 0.7
	_spot.shadow_enabled = true
	add_child(_spot)
	# the lamp itself: a weighted round base with a rocker switch, a hinge at its foot, the arm, a hinge under the shade
	# (the keeper, 2026-10-27: more like a real one - with its cord and a plug in a socket)
	var metal := flat(Color(0.15, 0.17, 0.16), 0.4, 0.6)
	var steel := flat(Color(0.62, 0.62, 0.6), 0.3, 0.9)
	var by := DESK.y + DESK_SIZE.y * 0.5
	var bc := Vector3(DESK.x - 0.84, by, DESK.z - 0.28)
	_cyl(0.075, 0.012, bc + Vector3(0, 0.006, 0), metal, self, 0.072, 32)
	_cyl(0.068, 0.006, bc + Vector3(0, 0.015, 0), metal, self, 0.06, 32)              # (its bevelled top)
	_cyl(0.074, 0.002, bc + Vector3(0, 0.001, 0), flat(Color(0.08, 0.08, 0.08), 0.95))   # (a felt pad under it)
	var sw := _box(Vector3(0.018, 0.006, 0.012), bc + Vector3(0.03, 0.019, 0.03), flat(Color(0.05, 0.05, 0.05), 0.4))
	sw.rotation.x = 0.18                                                              # (the switch, rocked)
	var foot := bc + Vector3(0, 0.03, 0)
	var head := Vector3(DESK.x - 0.76, by + 0.52, DESK.z - 0.12)
	_cyl(0.012, 0.022, bc + Vector3(0, 0.026, 0), steel, self, 0.009, 16)            # (the hinge's post)
	_rod(foot, head, 0.008, metal)
	for at in [foot, head]:
		var k := _cyl(0.011, 0.02, at, steel)                                        # (the hinges' knobs)
		k.rotation.z = PI * 0.5
	_cord(bc + Vector3(-0.06, 0.004, -0.02))
	items.append({"kind": "lamp", "mats": [], "box": AABB(bc + Vector3(-0.09, 0.0, -0.09), Vector3(0.26, 0.6, 0.3))})
	# the shade, a cone, its open end to the tanks
	var piv := _pivot(head, Vector3(DESK.x + DESK_SMALL_X, DESK.y, DESK.z - 0.15))
	var cone := _cyl(0.075, 0.12, Vector3(0, 0, -0.05), metal, piv, 0.025, 20)
	cone.rotation.x = PI * 0.5            # (its wide end, -y, along the pivot's -z: to the tanks)
	var bulb := flat(Color(1, 0.95, 0.85))
	_bulb = bulb
	bulb.emission_enabled = true
	bulb.emission = Color(1, 0.86, 0.62)
	bulb.emission_energy_multiplier = 3.0
	var b := _cyl(0.06, 0.004, Vector3(0, 0, -0.105), bulb, piv)
	b.rotation.x = PI * 0.5


## The lamp's cord: out of the back of its base, along the desk to its back edge, down behind it, along the floor by
## the wall to a socket on the skirting, its plug in it.
func _cord(from: Vector3) -> void:
	var black := flat(Color(0.04, 0.04, 0.04), 0.55)
	var by := DESK.y + DESK_SIZE.y * 0.5
	var back := DESK.z - DESK_SIZE.z * 0.5
	var sock := Vector3(DESK.x - 0.6, 0.25, -W * 0.5 + 0.006)                # the socket on the wall behind the desk
	# (down the 2 cm between the desk and the wall - v0.11.54 ran it through the wall: the keeper, 2026-10-27)
	var gap := (back + (-W * 0.5)) * 0.5
	var pts := [from, Vector3(from.x - 0.03, by + 0.003, back + 0.06), Vector3(from.x - 0.05, by + 0.003, back + 0.004),
		Vector3(from.x - 0.05, by - 0.03, gap), Vector3(from.x - 0.07, 0.45, gap),
		Vector3(sock.x - 0.02, 0.3, gap), Vector3(sock.x, sock.y + 0.045, sock.z + 0.03)]
	# a smooth curve through them (Catmull-Rom), drawn as short rods
	var curve := []
	for i in pts.size() - 1:
		var p0: Vector3 = pts[maxi(i - 1, 0)]
		var p1: Vector3 = pts[i]
		var p2: Vector3 = pts[i + 1]
		var p3: Vector3 = pts[mini(i + 2, pts.size() - 1)]
		for k in 6:
			var t := k / 6.0
			curve.append(0.5 * ((2.0 * p1) + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
				+ (3.0 * p1 - p0 - 3.0 * p2 + p3) * t * t * t))
	curve.append(pts[-1])
	for i in curve.size():
		var c: Vector3 = curve[i]
		c.z = maxf(c.z, -W * 0.5 + 0.004)                  # (the curve's swing never into the wall)
		curve[i] = c
	for i in curve.size() - 1:
		_rod(curve[i], curve[i + 1], 0.0025, black)
	# the socket: a white plate with two round holes' worth of plug in it
	var white := flat(Color(0.93, 0.92, 0.88), 0.35)
	_box(Vector3(0.08, 0.08, 0.008), sock + Vector3(0, 0, 0.004), white)
	_box(Vector3(0.066, 0.066, 0.004), sock + Vector3(0, 0, 0.009), flat(Color(0.97, 0.96, 0.93), 0.3))
	var plug := _cyl(0.017, 0.022, sock + Vector3(0, 0, 0.022), black, self, 0.015, 20)
	plug.rotation.x = PI * 0.5
	# (the cord out of the top of the plug, bending down: the plug's cable sleeve)
	_rod(sock + Vector3(0, 0.012, 0.024), sock + Vector3(0, 0.045, 0.03), 0.004, black)


## The light at that hour (0..24, the computer's clock): the sun's height and bearing through the day - it comes in at
## the window and its patch of light moves over the floor and the desk; orange when low; the sky, the hills and the
## meadow outside lit to match; at night only the lamps (and a little moonlight). [The sun's path is simplified: up at
## 6:15, highest (~52 degrees) at half past twelve, down at 19:15, across the window from left to right.]
func set_hour(h: float) -> void:
	var t := (h - 6.25) / 13.0                          # 0 sunrise .. 1 sunset
	var elev := sin(PI * t) * 0.9 if t > -0.05 and t < 1.05 else -0.3
	var az := lerpf(-1.05, 1.05, clampf(t, 0.0, 1.0))
	var day := smoothstep(-0.08, 0.18, elev)
	var dusk := (1.0 - smoothstep(0.08, 0.4, elev)) * smoothstep(-0.1, 0.02, elev)
	# toward the sun from the room (the window looks out along -x)
	var s := Vector3(-cos(elev) * cos(az), sin(elev), cos(elev) * sin(az)).normalized()
	if s.y > 0.02:
		_sun.basis = Basis.looking_at(-s, Vector3.UP)
	_sun.light_energy = 2.2 * smoothstep(0.0, 0.12, elev)
	_sun.light_color = Color(1.0, 0.96, 0.86).lerp(Color(1.0, 0.62, 0.34), dusk)
	_sun.visible = elev > 0.0
	_moon.light_energy = 0.18 * (1.0 - day)
	_moon.visible = day < 0.6
	_lamp.light_energy = lerpf(1.9, 0.35, day) * lamp_gain
	_spot.light_energy = lerpf(2.4, 1.2, day) * spot_gain
	_spot.visible = lamp_on
	if _bulb != null:
		_bulb.emission_energy_multiplier = 3.0 if lamp_on else 0.0
		_bulb.albedo_color = Color(1, 0.95, 0.85) if lamp_on else Color(0.75, 0.73, 0.7)
	if _env != null:
		_env.background_color = Color(0.015, 0.025, 0.07).lerp(Color(0.32, 0.55, 0.85), day).lerp(Color(0.6, 0.5, 0.62), dusk * 0.5)
		_env.ambient_light_color = Color(0.36, 0.33, 0.42).lerp(Color(0.86, 0.76, 0.62), day)
		_env.ambient_light_energy = lerpf(0.2, 0.42, day)
	# the night sky turning: the time of year by the computer's date (the Home), or the game's (keeper_room.gd: doy)
	var sid := Zodiac.lst(h, doy if doy >= 0.0 else Zodiac.today())
	var zd := Zodiac.dirs(sid)
	for m in _views:
		m.set_shader_parameter("sky_from_room", Zodiac.to_room(sid).transposed())
		m.set_shader_parameter("zodiac", zd)
		m.set_shader_parameter("day", day)
		m.set_shader_parameter("dusk", dusk)
		m.set_shader_parameter("sun_dir", s)
	_lawn.albedo_color = Color(0.04, 0.06, 0.04).lerp(Color(0.42, 0.56, 0.27), day)
