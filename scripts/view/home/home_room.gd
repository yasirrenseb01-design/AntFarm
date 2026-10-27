extends "res://scripts/view/home/home_kit.gd"
## The Home room, layer 2 of 2 (the keeper, 2026-10-26; in two layers from v0.11.49): a small room 4 x 4 m and 2.6 m high
## - a desk against the far wall with the tanks on it, a chair, a window on the left wall looking out on a meadow, a
## forest and mountains (painted in code: shaders/home/window_view.gdshader), a door on the right (not open yet), a rug,
## a ceiling lamp and a desk lamp, the shelves bought. The light follows the computer's clock (set_hour): the sun comes
## in through the window and its patch moves over the floor through the day, warm and low in the morning and evening;
## at night the lamps. game/home.gd owns it (camera, the hand, what a click does).

const View := preload("res://shaders/home/window_view.gdshader")
const SHELF_D := 0.3                         # a shelf's depth; each column 0.45 wide, two tiers
const SHELF_Y := [0.55, 1.08]                # the tops of its boards a tank stands on
# where the shelves go, in the order they are bought: the foot's centre against a wall, and its turn (front to the room)
const SHELF_AT := [[Vector3(1.45, 0, -1.85), 0.0], [Vector3(-1.0, 0, 1.85), PI], [Vector3(0.55, 0, 1.85), PI],
	[Vector3(-1.85, 0, 1.0), PI * 0.5]]
var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _lamp: OmniLight3D
var _spot: SpotLight3D
var _env: Environment
var _views: Array = []            # the window view's materials (far, near)
var _lawn: StandardMaterial3D


## places: home_store.places() (where each tank stands); shelves: how many tanks each shelf bought holds; hour: the
## clock's; env: the room's environment (its ambient light follows the hour).
func build(places: Array, shelves: Array, filled: Callable, hour: float, env: Environment) -> void:
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
	# on the desk: the small one in the middle, or left of the big one
	var has_big := places.any(func(p): return p.big)
	var top := DESK.y + DESK_SIZE.y * 0.5
	for p in places:
		var full: bool = filled.call(int(p.slot))
		var sz: Vector3 = BIG if p.big else (FARM if p.get("farm", false) else TANK)
		if p.shelf == -1:
			var x := 0.0 if not has_big else (0.3 if p.big else -0.25)
			_tank(self, Vector3(DESK.x + x, top, DESK.z + 0.05), sz, int(p.slot), int(p.number), full)
		elif p.shelf >= 0 and p.shelf < units.size():
			var cols := int(shelves[p.shelf]) / 2
			var col: int = int(p.spot) % cols
			var tier: int = int(p.spot) / cols
			_tank(units[p.shelf], Vector3((col - (cols - 1) * 0.5) * 0.45, SHELF_Y[tier], 0.0), sz, int(p.slot), int(p.number), full)
	set_hour(hour)


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


func _room() -> void:
	var floor_m := wood(Color(0.36, 0.21, 0.11), Color(0.56, 0.35, 0.19), 0.14, 1.3, 70.0)
	_box(Vector3(W, 0.05, W), Vector3(0, -0.025, 0), floor_m)
	var wall := flat(Color(0.9, 0.82, 0.69), 0.92)           # (a warm cream: the keeper, 2026-10-27 "cozy")
	var ceil_m := flat(Color(0.95, 0.91, 0.84), 0.95)
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
	_notebook(Vector3(DESK.x - 0.55, y, DESK.z + 0.12), 0.2)
	_pencil(Vector3(DESK.x - 0.42, y, DESK.z + 0.22), 0.5)


func _lights() -> void:
	# the ceiling lamp: a fabric shade, a warm bulb
	var shade := flat(Color(0.93, 0.86, 0.74), 0.85)
	shade.emission_enabled = true
	shade.emission = Color(1.0, 0.8, 0.55)
	shade.emission_energy_multiplier = 0.25
	_cyl(0.2, 0.14, Vector3(0, H - 0.26, 0), shade, self, 0.16, 32)
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
	_spot.position = Vector3(DESK.x - 0.5, DESK.y + 0.6, DESK.z + 0.1)
	_spot.look_at_from_position(_spot.position, Vector3(DESK.x, DESK.y, DESK.z), Vector3.UP)
	_spot.light_color = Color(1.0, 0.82, 0.58)
	_spot.spot_range = 1.7
	_spot.spot_angle = 42.0
	_spot.spot_angle_attenuation = 1.6
	_spot.shadow_enabled = true
	add_child(_spot)
	# the lamp itself
	var metal := flat(Color(0.15, 0.17, 0.16), 0.4, 0.6)
	var by := DESK.y + DESK_SIZE.y * 0.5
	_cyl(0.07, 0.015, Vector3(DESK.x - 0.58, by + 0.008, DESK.z - 0.15), metal)
	var foot := Vector3(DESK.x - 0.58, by + 0.01, DESK.z - 0.15)
	var head := Vector3(DESK.x - 0.5, by + 0.52, DESK.z - 0.02)
	_rod(foot, head, 0.008, metal)
	# the shade, a cone, its open end to the tanks
	var piv := _pivot(head, Vector3(DESK.x - 0.1, DESK.y, DESK.z + 0.05))
	var cone := _cyl(0.075, 0.12, Vector3(0, 0, -0.05), metal, piv, 0.025, 20)
	cone.rotation.x = PI * 0.5            # (its wide end, -y, along the pivot's -z: to the tanks)
	var bulb := flat(Color(1, 0.95, 0.85))
	bulb.emission_enabled = true
	bulb.emission = Color(1, 0.86, 0.62)
	bulb.emission_energy_multiplier = 3.0
	var b := _cyl(0.06, 0.004, Vector3(0, 0, -0.105), bulb, piv)
	b.rotation.x = PI * 0.5


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
	_lamp.light_energy = lerpf(1.9, 0.35, day)
	_spot.light_energy = lerpf(2.4, 1.2, day)
	if _env != null:
		_env.background_color = Color(0.015, 0.025, 0.07).lerp(Color(0.32, 0.55, 0.85), day).lerp(Color(0.6, 0.5, 0.62), dusk * 0.5)
		_env.ambient_light_color = Color(0.36, 0.33, 0.42).lerp(Color(0.86, 0.76, 0.62), day)
		_env.ambient_light_energy = lerpf(0.2, 0.42, day)
	for m in _views:
		m.set_shader_parameter("day", day)
		m.set_shader_parameter("dusk", dusk)
		m.set_shader_parameter("sun_dir", s)
	_lawn.albedo_color = Color(0.04, 0.06, 0.04).lerp(Color(0.42, 0.56, 0.27), day)
