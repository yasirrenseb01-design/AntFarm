extends Node3D
## The Home room, layer 1 of 2 (split from home_room.gd in v0.11.49): its measures, materials, and the pieces in it made
## in some detail (the keeper, 2026-10-27: the door handle, the drawer, the pencil, the notebook, the plant on the sill,
## the rug; the door's panels set in, not standing out) - the chair one sits on, the tanks (a formicarium, the bigger
## one, a flat ant farm) with the colony's real nest seen through the glass. Metres; y up; the desk wall at -z.
## home_room.gd builds the room from them; game/home.gd owns it.

const Wood := preload("res://shaders/home/wood.gdshader")
const Rug := preload("res://shaders/home/rug.gdshader")
const NestCard := preload("res://scripts/game/nest_card.gd")
const Store := preload("res://scripts/game/save_store.gd")
const W := 4.0                    # the room, x and z
const H := 2.6
const DESK := Vector3(0.0, 0.75, -1.62)      # the desk top's centre (its top surface at y 0.75)
const DESK_SIZE := Vector3(1.5, 0.04, 0.72)
const TANK := Vector3(0.30, 0.20, 0.15)      # a small tank's glass
const BIG := Vector3(0.44, 0.27, 0.22)       # the bigger one's (the shop's second tank)
const FARM := Vector3(0.30, 0.22, 0.035)     # an ant farm: two panes close together, the soil between them
const DOOR := Vector3(1.98, 0.0, 0.85)       # the door's foot, on the right wall
const WIN_Z := -0.7                          # the window's centre along the left wall
const CHAIR := Vector3(0.1, 0.0, -0.87)      # the chair's foot, and its turn
const CHAIR_TURN := -0.25
var blocks: Array = []            # Rect2s on the floor (x, z) the keeper cannot walk into: the desk, the chair, the shelves
var items: Array = []             # what the hand can be on: {"kind": "tank"|"door"|"chair", "box": AABB, "mats": [...], ...}


# ---------------------------------------------------------------- materials and shapes

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


func _cyl(r: float, h: float, centre: Vector3, mat: Material, parent: Node3D = self, r_top := -1.0, sides := 16) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r if r_top < 0.0 else r_top
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = sides
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.position = centre
	parent.add_child(mi)
	return mi


## A node at `at` whose -z looks at `to` (its children laid along -z).
func _pivot(at: Vector3, to: Vector3, parent: Node3D = self) -> Node3D:
	var p := Node3D.new()
	parent.add_child(p)
	p.look_at_from_position(at, to, Vector3.UP if absf((to - at).normalized().y) < 0.99 else Vector3.RIGHT)
	return p


## A thin rod from a to b.
func _rod(a: Vector3, b: Vector3, r: float, mat: Material, parent: Node3D = self) -> void:
	var piv := _pivot((a + b) * 0.5, b, parent)
	var c := _cyl(r, a.distance_to(b), Vector3.ZERO, mat, piv)
	c.rotation.x = PI * 0.5


# ---------------------------------------------------------------- the door

## The door, its panels set into the frame of stiles and rails (not standing out), a lever handle on a rose and a
## keyhole below it.
func _door() -> void:
	var x := W * 0.5
	var casing := flat(Color(0.95, 0.93, 0.88), 0.45)
	_box(Vector3(0.03, 2.12, 0.07), Vector3(x - 0.015, 1.06, DOOR.z - 0.485), casing)
	_box(Vector3(0.03, 2.12, 0.07), Vector3(x - 0.015, 1.06, DOOR.z + 0.485), casing)
	_box(Vector3(0.03, 0.07, 1.04), Vector3(x - 0.015, 2.085, DOOR.z), casing)
	var leaf := wood(Color(0.4, 0.25, 0.14), Color(0.54, 0.36, 0.21), 9.0, 9.0, 40.0)
	var panel := wood(Color(0.36, 0.22, 0.12), Color(0.5, 0.33, 0.19), 9.0, 9.0, 40.0)
	var face := x - 0.035                        # the frame's face (the room side)
	# the panels' sheet, set back
	var d := _box(Vector3(0.025, 2.03, 0.86), Vector3(x - 0.008, 1.015, DOOR.z), panel)
	# stiles (up the sides) and rails (across), standing in front of it
	var t := 0.022
	for sz in [-1, 1]:
		_box(Vector3(t, 2.03, 0.12), Vector3(face + t * 0.5, 1.015, DOOR.z + sz * 0.38), leaf)
	_box(Vector3(t, 0.13, 0.64), Vector3(face + t * 0.5, 1.965, DOOR.z), leaf)          # top rail
	_box(Vector3(t, 0.16, 0.64), Vector3(face + t * 0.5, 1.02, DOOR.z), leaf)           # middle rail (the lock rail)
	_box(Vector3(t, 0.22, 0.64), Vector3(face + t * 0.5, 0.11, DOOR.z), leaf)           # bottom rail
	_box(Vector3(t, 1.81, 0.1), Vector3(face + t * 0.5, 1.02, DOOR.z), leaf)            # the middle stile
	# a small moulding round each panel's edge, in the corner between frame and panel
	var mould := wood(Color(0.32, 0.19, 0.1), Color(0.44, 0.28, 0.15), 9.0, 9.0, 40.0)
	for pz in [-0.185, 0.185]:
		for pr in [[0.22, 0.94], [1.1, 1.9]]:
			var y0: float = pr[0]
			var y1: float = pr[1]
			var zc: float = DOOR.z + pz
			var hw := 0.135
			for zz in [zc - hw, zc + hw]:
				_box(Vector3(0.012, y1 - y0, 0.012), Vector3(face + 0.006, (y0 + y1) * 0.5, zz), mould)
			for yy in [y0, y1]:
				_box(Vector3(0.012, 0.012, hw * 2.0), Vector3(face + 0.006, yy, zc), mould)
	# the lever handle: a round rose, a short neck, the lever turned toward the hinge side, a keyhole below
	var brass := flat(Color(0.86, 0.68, 0.36), 0.32, 0.45)
	var hz := DOOR.z - 0.36
	var rose := _cyl(0.028, 0.008, Vector3(face - 0.004, 1.02, hz), brass, self, 0.024, 24)
	rose.rotation.z = PI * 0.5
	var neck := _cyl(0.008, 0.045, Vector3(face - 0.03, 1.02, hz), brass)
	neck.rotation.z = PI * 0.5
	var lever := Node3D.new()
	lever.position = Vector3(face - 0.052, 1.02, hz)
	add_child(lever)
	var bar := CapsuleMesh.new()
	bar.radius = 0.0085
	bar.height = 0.12
	var bi := MeshInstance3D.new()
	bi.mesh = bar
	bi.material_override = brass
	bi.rotation.x = PI * 0.5
	bi.position = Vector3(0, 0, 0.055)                 # (toward the hinges, +z)
	lever.add_child(bi)
	var esc := _cyl(0.016, 0.006, Vector3(face - 0.003, 0.9, hz), brass, self, 0.014, 20)
	esc.rotation.z = PI * 0.5
	_box(Vector3(0.004, 0.016, 0.005), Vector3(face - 0.007, 0.898, hz), flat(Color(0.03, 0.025, 0.02), 0.9))
	items.append({"kind": "door", "box": AABB(Vector3(x - 0.1, 0.0, DOOR.z - 0.45), Vector3(0.12, 2.05, 0.9)), "mats": [], "node": d})


# ---------------------------------------------------------------- the desk and what is on it

## A drawer under the desk top: its front with a raised panel and bevelled edges, a brass bar pull on two posts.
func _drawer(at: Vector3, w: float, h: float) -> void:
	var front := wood(Color(0.38, 0.23, 0.12), Color(0.52, 0.34, 0.19), 9.0, 9.0, 45.0)
	var panel := wood(Color(0.42, 0.26, 0.14), Color(0.58, 0.39, 0.22), 9.0, 9.0, 45.0)
	_box(Vector3(w, h, 0.02), at, front)
	_box(Vector3(w - 0.05, h - 0.04, 0.008), at + Vector3(0, 0, 0.012), panel)
	# the gap round it (a dark line)
	var dark := flat(Color(0.08, 0.05, 0.03), 0.9)
	_box(Vector3(w + 0.006, 0.004, 0.018), at + Vector3(0, h * 0.5 + 0.002, -0.002), dark)
	_box(Vector3(w + 0.006, 0.004, 0.018), at + Vector3(0, -h * 0.5 - 0.002, -0.002), dark)
	var brass := flat(Color(0.86, 0.68, 0.36), 0.32, 0.45)
	for sx in [-1, 1]:
		var post := _cyl(0.005, 0.025, at + Vector3(sx * 0.045, 0, 0.026), brass)
		post.rotation.x = PI * 0.5
	var bar := _cyl(0.005, 0.11, at + Vector3(0, 0, 0.038), brass)
	bar.rotation.z = PI * 0.5


## A pencil lying on the desk: six-sided and yellow, sharpened to a graphite point at one end, a metal ferrule and a
## pink eraser at the other. at: its middle on the desk; turn: round y.
func _pencil(at: Vector3, turn: float) -> void:
	var p := Node3D.new()
	p.position = at + Vector3(0, 0.0042, 0)
	p.rotation.y = turn
	add_child(p)
	var body := _cyl(0.0042, 0.15, Vector3.ZERO, flat(Color(0.93, 0.72, 0.12), 0.45), p, -1.0, 6)
	body.rotation.z = PI * 0.5
	var tip := _cyl(0.0042, 0.018, Vector3(0.084, 0, 0), flat(Color(0.86, 0.7, 0.5), 0.8), p, 0.0012, 6)
	tip.rotation.z = -PI * 0.5
	var lead := _cyl(0.0012, 0.005, Vector3(0.0955, 0, 0), flat(Color(0.12, 0.12, 0.13), 0.4, 0.4), p, 0.0, 8)
	lead.rotation.z = -PI * 0.5
	var ferrule := _cyl(0.0045, 0.012, Vector3(-0.081, 0, 0), flat(Color(0.75, 0.75, 0.72), 0.25, 0.9), p)
	ferrule.rotation.z = PI * 0.5
	var eraser := _cyl(0.0042, 0.01, Vector3(-0.092, 0, 0), flat(Color(0.88, 0.5, 0.52), 0.9), p)
	eraser.rotation.z = PI * 0.5


## A notebook lying shut: a leather-brown cover a little bigger than the cream page block, a rounded spine, an elastic
## band across it and a ribbon marker out at the bottom.
func _notebook(at: Vector3, turn: float) -> void:
	var b := Node3D.new()
	b.position = at
	b.rotation.y = turn
	add_child(b)
	var cover := flat(Color(0.36, 0.22, 0.13), 0.7)
	var w := 0.15
	var l := 0.21
	_box(Vector3(w, 0.0025, l), Vector3(0, 0.00125, 0), cover, b)                  # back cover
	_box(Vector3(w, 0.0025, l), Vector3(0, 0.0135, 0), cover, b)                   # front cover
	var pages := flat(Color(0.93, 0.89, 0.78), 0.95)
	_box(Vector3(w - 0.008, 0.0095, l - 0.008), Vector3(0.002, 0.0072, 0), pages, b)
	var spine := _cyl(0.0074, l, Vector3(-w * 0.5, 0.0074, 0), cover, b)
	spine.rotation.x = PI * 0.5
	_box(Vector3(0.006, 0.0155, l + 0.001), Vector3(w * 0.5 - 0.02, 0.0075, 0), flat(Color(0.1, 0.07, 0.05), 0.6), b)      # the band
	_box(Vector3(0.005, 0.0008, 0.03), Vector3(0.02, 0.0004, l * 0.5 + 0.014), flat(Color(0.6, 0.15, 0.12), 0.7), b)      # the ribbon


# ---------------------------------------------------------------- the plant on the sill

static var _leaf_shader: Shader

## A snake plant (Sansevieria) in a terracotta pot: stiff upright sword leaves, dark green with paler cross bands and a
## yellow edge, curving a little outward and twisting.
func _plant(at: Vector3) -> void:
	var pot := flat(Color(0.66, 0.34, 0.2), 0.85)
	_cyl(0.058, 0.12, at + Vector3(0, 0.06, 0), pot, self, 0.072, 24)
	_cyl(0.078, 0.022, at + Vector3(0, 0.124, 0), pot, self, 0.078, 24)            # the rim
	_cyl(0.068, 0.006, at + Vector3(0, 0.127, 0), flat(Color(0.2, 0.13, 0.08), 1.0), self, 0.068, 24)     # the soil
	if _leaf_shader == null:
		_leaf_shader = Shader.new()
		_leaf_shader.code = """
shader_type spatial;
render_mode cull_disabled;
float h1(float n) { return fract(sin(n * 127.1) * 43758.5453); }
void fragment() {
	float v = UV.y;
	float bands = sin(v * 70.0 + sin(UV.x * 9.0) * 1.5) * 0.5 + 0.5;
	vec3 c = mix(vec3(0.08, 0.2, 0.08), vec3(0.22, 0.38, 0.18), bands * 0.6);
	float edge = smoothstep(0.38, 0.47, abs(UV.x - 0.5));
	c = mix(c, vec3(0.78, 0.72, 0.28), edge);
	ALBEDO = c;
	ROUGHNESS = 0.45;
	SPECULAR = 0.6;
	BACKLIGHT = vec3(0.12, 0.2, 0.05);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = _leaf_shader
	var r := RandomNumberGenerator.new()
	r.seed = 4
	for i in 9:
		var a := i * 2.39996 + r.randf() * 0.4
		var tall := r.randf_range(0.26, 0.42)
		var mi := MeshInstance3D.new()
		mi.mesh = _sword_leaf(tall, r.randf_range(0.055, 0.075), r.randf_range(0.12, 0.3), r.randf_range(-0.6, 0.6))
		mi.material_override = mat
		mi.position = at + Vector3(cos(a) * 0.02, 0.125, sin(a) * 0.02)
		mi.rotation.y = -a
		add_child(mi)


## One leaf: a strip up y, widest a third of the way up, to a point; bent outward (+x) by `bend`, twisted by `twist`.
func _sword_leaf(tall: float, wide: float, bend: float, twist: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 12
	var pts := []
	for k in n + 1:
		var t := float(k) / n
		var w := wide * 0.5 * pow(sin(PI * minf(1.0, t * 0.9 + 0.1)), 0.7) * (1.0 - t * 0.85)
		var c := Vector3(bend * t * t * tall, t * tall, 0.0)
		var side := Vector3(0, 0, 1).rotated(Vector3.UP, twist * t)
		pts.append([c - side * w, c + side * w, t])
	for k in n:
		var a0: Vector3 = pts[k][0]
		var a1: Vector3 = pts[k][1]
		var b0: Vector3 = pts[k + 1][0]
		var b1: Vector3 = pts[k + 1][1]
		var t0: float = pts[k][2]
		var t1: float = pts[k + 1][2]
		for v in [[a0, 0.0, t0], [b0, 0.0, t1], [a1, 1.0, t0], [a1, 1.0, t0], [b0, 0.0, t1], [b1, 1.0, t1]]:
			st.set_uv(Vector2(v[1], v[2]))
			st.add_vertex(v[0])
	st.generate_normals()
	return st.commit()


# ---------------------------------------------------------------- the rug

func _rug(at: Vector3, size: Vector2) -> void:
	var m := ShaderMaterial.new()
	m.shader = Rug
	m.set_shader_parameter("size", size)
	var top := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	top.mesh = pm
	top.material_override = m
	top.position = at + Vector3(0, 0.009, 0)
	add_child(top)
	_box(Vector3(size.x, 0.008, size.y), at + Vector3(0, 0.004, 0), flat(Color(0.3, 0.12, 0.08), 1.0))
	# a fringe on the two short ends
	var fringe := flat(Color(0.88, 0.8, 0.64), 1.0)
	for sx in [-1, 1]:
		for k in 34:
			var z := -size.y * 0.5 + (k + 0.5) * size.y / 34.0
			var f := _box(Vector3(0.045, 0.003, 0.006), at + Vector3(sx * (size.x * 0.5 + 0.022), 0.0025, z), fringe)
			f.rotation.y = (randf() - 0.5) * 0.25


# ---------------------------------------------------------------- the chair

## The chair at the desk: one sits on it (a click), and it is in the way when walking.
func _chair() -> void:
	var c := Node3D.new()
	c.position = CHAIR
	c.rotation.y = CHAIR_TURN
	add_child(c)
	var m := wood(Color(0.33, 0.2, 0.1), Color(0.48, 0.3, 0.16), 9.0, 9.0, 45.0)
	_box(Vector3(0.42, 0.035, 0.4), Vector3(0, 0.45, 0), m, c)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_box(Vector3(0.035, 0.45, 0.035), Vector3(sx * 0.18, 0.225, sz * 0.17), m, c)
		_box(Vector3(0.035, 0.45, 0.035), Vector3(sx * 0.18, 0.69, 0.17), m, c)
	_box(Vector3(0.4, 0.12, 0.02), Vector3(0, 0.84, 0.175), m, c)
	_box(Vector3(0.4, 0.05, 0.02), Vector3(0, 0.66, 0.175), m, c)
	var r := c.transform * AABB(Vector3(-0.22, 0, -0.21), Vector3(0.44, 0.92, 0.42))
	blocks.append(Rect2(r.position.x, r.position.z, r.size.x, r.size.z).grow(-0.1))
	# facing the desk: the way its seat looks (-z, turned)
	items.append({"kind": "chair", "box": r, "mats": [], "seat": c.transform * Vector3(0, 0.45, 0.02), "face": CHAIR_TURN})


# ---------------------------------------------------------------- the tanks

## One tank: a wooden base, glass, a wooden lid with a vent, and, when it has a colony, the soil behind the glass with
## that colony's nest in it (nest_card.gd, written with the save; until it is saved again, tunnels made up); a card
## with its number on the base. An ant farm: two panes close together on a wider stand, soil nearly to the top.
func _tank(parent: Node3D, at: Vector3, sz: Vector3, slot: int, number: int, has_colony: bool) -> void:
	var farm := sz.z < 0.06
	var t := Node3D.new()
	t.position = at
	parent.add_child(t)
	var base_m := wood(Color(0.32, 0.2, 0.1), Color(0.46, 0.29, 0.15), 9.0, 9.0, 50.0)
	var lid_m := base_m.duplicate()
	var base_d := 0.09 if farm else sz.z + 0.02
	_box(Vector3(sz.x + 0.02, 0.025, base_d), Vector3(0, 0.0125, 0), base_m, t)
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.85, 0.95, 0.95, 0.1)
	glass.roughness = 0.04
	glass.metallic_specular = 0.9
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var g := _box(sz, Vector3(0, 0.025 + sz.y * 0.5, 0), glass, t)
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_box(Vector3(sz.x + 0.012, 0.015, sz.z + 0.012), Vector3(0, 0.025 + sz.y + 0.0075, 0), lid_m, t)
	if farm:
		for sx in [-1, 1]:              # the frame's sides
			_box(Vector3(0.012, sz.y, sz.z + 0.012), Vector3(sx * (sz.x * 0.5 + 0.006), 0.025 + sz.y * 0.5, 0), lid_m, t)
	else:
		_box(Vector3(0.08, 0.004, 0.05), Vector3(0.07, 0.025 + sz.y + 0.016, 0), flat(Color(0.2, 0.2, 0.2), 0.6, 0.5), t)
	if has_colony:
		var soil := ShaderMaterial.new()
		soil.shader = _soil_shader()
		soil.set_shader_parameter("seed", float(slot) * 3.7)
		var tex := NestCard.read(Store.base + "saves", slot)
		var fill := 0.86 if farm else 0.72
		var ssz := Vector3(sz.x - 0.006, sz.y * fill, sz.z - 0.006)
		soil.set_shader_parameter("size", ssz)
		if tex != null:
			soil.set_shader_parameter("nest_tex", tex)
			soil.set_shader_parameter("has_tex", true)
		_box(ssz, Vector3(0, 0.025 + ssz.y * 0.5, 0), soil, t)
	# the card with its number
	var cz := base_d * 0.5 + 0.0105
	var card := Label3D.new()
	card.text = str(number)
	card.font_size = 48
	card.pixel_size = 0.0005
	card.modulate = Color(0.16, 0.11, 0.07)
	card.outline_size = 0
	card.position = Vector3(-sz.x * 0.5 + 0.03, 0.0125, cz)
	card.double_sided = false
	t.add_child(card)
	_box(Vector3(0.04, 0.02, 0.001), Vector3(-sz.x * 0.5 + 0.03, 0.0125, cz - 0.0003), flat(Color(0.9, 0.85, 0.72), 0.9), t)
	items.append({"kind": "tank", "slot": slot, "number": number, "mats": [base_m, lid_m],
		"box": t.global_transform * AABB(Vector3(-sz.x * 0.5 - 0.01, 0, -base_d * 0.5), Vector3(sz.x + 0.02, sz.y + 0.05, base_d))})


static var _soil: Shader

static func _soil_shader() -> Shader:
	if _soil == null:
		_soil = Shader.new()
		_soil.code = """
shader_type spatial;
// soil in a tank: the front and back show the colony's real nest (nest_tex: its side view, nest_card.gd), the rest is
// plain soil; without the image, tunnels made up from noise
uniform float seed = 0.0;
uniform vec3 size = vec3(0.3, 0.14, 0.14);
uniform sampler2D nest_tex : filter_linear;
uniform bool has_tex = false;
varying vec3 opos;
varying vec3 onrm;
float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y); }
void vertex() { opos = VERTEX; onrm = NORMAL; }
void fragment() {
	vec2 p = opos.xy * 40.0 + seed;
	float n = vn(p) * 0.5 + vn(p * 2.3) * 0.3 + vn(p * 7.0) * 0.2;
	vec3 c = mix(vec3(0.22, 0.14, 0.08), vec3(0.36, 0.25, 0.15), n);
	c *= 0.85 + 0.3 * h2(floor(opos.xy * 900.0));
	bool face = abs(onrm.z) > 0.5;
	if (face && has_tex) {
		vec2 uv = vec2(opos.x / size.x + 0.5, 0.5 - opos.y / size.y);
		if (onrm.z < 0.0) { uv.x = 1.0 - uv.x; }
		vec3 t = texture(nest_tex, uv).rgb;
		c = t * (0.9 + 0.2 * h2(floor(opos.xy * 700.0)));
	} else if (face) {
		float tt = abs(vn(opos.xy * 22.0 + seed * 1.3) - 0.5);
		float ch = vn(opos.xy * 9.0 + seed * 2.1);
		float tun = 1.0 - smoothstep(0.018, 0.03 + 0.05 * smoothstep(0.62, 0.8, ch), tt);
		tun *= smoothstep(size.y * 0.5 - 0.005, size.y * 0.5 - 0.025, opos.y);
		c = mix(c, vec3(0.06, 0.04, 0.025), tun);
	}
	ALBEDO = c;
	ROUGHNESS = 0.95;
}
"""
	return _soil


## The hand on an item (or none): its base glows a little.
func hover(item) -> void:
	for it in items:
		for m in it.mats:
			m.set_shader_parameter("hilite", 1.0 if is_same(it, item) else 0.0)
