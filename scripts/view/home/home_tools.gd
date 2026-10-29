extends "res://scripts/view/home/home_kit.gd"
## The Home room, between its pieces (home_kit.gd) and the room (home_room.gd): an ant keeper's everyday kit laid out
## along the front of the desk (the keeper, 2026-10-29: "things for keeping and catching ants on the desk, in some
## detail"). What keepers use [keepers' practice - forums and care guides, not a study]: founding tubes (a glass test
## tube, water held behind a cotton plug, a second plug closing it; a queen inside one), an aspirator (a "pooter": a
## vial with a stopper, a short pipe to suck the ant in and a hose with a mouthpiece, gauze over its inner end), soft
## forceps, a fine paintbrush to move ants, a syringe for water, a petri dish as a feeding dish with a drop of honey on
## it, a hand lens, and a bottle of PTFE (Fluon) for the escape barrier. Metres; the strip in front of the tanks is
## free whichever tanks stand there (the big one reaches to 20 cm from the desk's front edge).

const GLASS_TINT := Color(0.85, 0.92, 0.95, 0.22)


func _glass_mat(a := 0.22) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(GLASS_TINT.r, GLASS_TINT.g, GLASS_TINT.b, a)
	m.roughness = 0.04
	m.metallic_specular = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## A capsule-ish ellipsoid (scaled sphere) - cotton, a drop, an ant's body.
func _blob(r: Vector3, centre: Vector3, mat: Material, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 14
	sm.rings = 8
	mi.mesh = sm
	mi.material_override = mat
	mi.position = centre
	mi.scale = r
	parent.add_child(mi)
	return mi


## A thin rod from a to b in the parent's own space (home_kit._rod aims by the world's: off inside a turned group).
func _stick(a: Vector3, b: Vector3, r: float, mat: Material, parent: Node3D) -> void:
	var d := b - a
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var c := _cyl(r, d.length(), (a + b) * 0.5, mat, parent, -1.0, 8)
	c.basis = Basis(x, y, x.cross(y))


## The kit put away in a wooden tray with three compartments, at the desk's front right (the keeper, 2026-10-29: "laid
## out loose it looks untidy - put them in a box"): the long tools side by side, the tubes in their cradle, the dish,
## the aspirator with its hose coiled and the bottle; y: the desk top.
const TRAY := Vector3(0.56, 0.035, 0.2)         # outside: long, the walls' height, deep

func _keeper_tools(y: float) -> void:
	var c := Vector3(DESK.x + 0.48, y, DESK.z + DESK_SIZE.z * 0.5 - 0.115)      # (its front 1.5 cm in from the desk's edge)
	_tray(c)
	var f := c.y + 0.006                                    # the tray's floor
	_brush(Vector3(c.x - 0.18, f, c.z - 0.07), 0.0)
	_forceps(Vector3(c.x - 0.185, f, c.z - 0.035), 0.0)
	_syringe(Vector3(c.x - 0.18, f, c.z + 0.0), 0.0)
	_lens(Vector3(c.x - 0.225, f, c.z + 0.055), 0.0)
	_tubes(Vector3(c.x + 0.0, f, c.z), PI * 0.5)
	_aspirator(Vector3(c.x + 0.13, f, c.z - 0.05), true)
	_petri(Vector3(c.x + 0.135, f, c.z + 0.048), true)
	_fluon(Vector3(c.x + 0.225, f, c.z - 0.055))


## The tray: a floor, four walls, two dividers; wood a little paler than the desk's.
func _tray(c: Vector3) -> void:
	var g := Node3D.new()
	g.position = c
	add_child(g)
	var m := wood(Color(0.66, 0.5, 0.32), Color(0.78, 0.62, 0.42), 9.0, 9.0, 60.0)
	var t := 0.01
	_box(Vector3(TRAY.x, 0.006, TRAY.z), Vector3(0, 0.003, 0), m, g)
	for sz in [-1.0, 1.0]:
		_box(Vector3(TRAY.x, TRAY.y, t), Vector3(0, TRAY.y * 0.5, sz * (TRAY.z - t) * 0.5), m, g)
	for sx in [-1.0, 1.0]:
		_box(Vector3(t, TRAY.y, TRAY.z - 2.0 * t), Vector3(sx * (TRAY.x - t) * 0.5, TRAY.y * 0.5, 0), m, g)
	for dx in [-0.09, 0.08]:
		_box(Vector3(0.006, TRAY.y * 0.8, TRAY.z - 2.0 * t), Vector3(dx, TRAY.y * 0.4, 0), m, g)


## Two founding tubes lying in a little wooden cradle: water at the closed end behind a cotton plug, a cotton plug
## closing the open end, a queen in the first one (8-9 mm, Lasius niger).
func _tubes(at: Vector3, turn := 0.08) -> void:
	var g := Node3D.new()
	g.position = at
	g.rotation.y = turn
	add_child(g)
	var wood_m := wood(Color(0.62, 0.45, 0.28), Color(0.74, 0.56, 0.36), 9.0, 9.0, 60.0)
	for sx in [-0.06, 0.06]:
		var cradle := _box(Vector3(0.012, 0.016, 0.07), Vector3(sx, 0.008, 0), wood_m, g)
		cradle.name = "cradle"
	var glass := _glass_mat(0.2)
	var water := StandardMaterial3D.new()
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.albedo_color = Color(0.55, 0.72, 0.85, 0.45)
	water.roughness = 0.05
	var cotton := flat(Color(0.96, 0.95, 0.92), 0.98)
	var cotton_damp := flat(Color(0.86, 0.87, 0.86), 0.9)
	for i in 2:
		var tz := (i - 0.5) * 0.024
		var ty := 0.016 + 0.008
		var tube := _cyl(0.008, 0.15, Vector3(0, ty, tz), glass, g, -1.0, 18)
		tube.rotation.z = PI * 0.5
		_blob(Vector3(0.008, 0.0078, 0.0078), Vector3(-0.075, ty, tz), glass, g)          # (its round closed end)
		var w := _cyl(0.0072, 0.04, Vector3(-0.056, ty - 0.0006, tz), water, g, -1.0, 14)    # the water
		w.rotation.z = PI * 0.5
		var plug := _cyl(0.0074, 0.016, Vector3(-0.028, ty, tz), cotton_damp, g, -1.0, 12)   # cotton holding it in
		plug.rotation.z = PI * 0.5
		var cap := _cyl(0.0075, 0.014, Vector3(0.07, ty, tz), cotton, g, -1.0, 12)           # cotton closing the mouth
		cap.rotation.z = PI * 0.5
		_blob(Vector3(0.006, 0.006, 0.0072), Vector3(0.077, ty, tz), cotton, g)              # (fluffed out)
		if i == 0:
			# the queen: head, thorax, a big gaster; legs suggested by a dark band under her
			var ant := flat(Color(0.07, 0.055, 0.047), 0.3)
			_blob(Vector3(0.0014, 0.0012, 0.0013), Vector3(0.012, ty - 0.0055, tz), ant, g)
			_blob(Vector3(0.0018, 0.0015, 0.0014), Vector3(0.0092, ty - 0.0053, tz), ant, g)
			_blob(Vector3(0.0032, 0.0022, 0.0024), Vector3(0.0045, ty - 0.005, tz), ant, g)
	# a label on the second tube: date and species in pencil
	_box(Vector3(0.03, 0.0004, 0.012), Vector3(0.0, 0.0322, 0.012), flat(Color(0.95, 0.93, 0.85), 0.9), g)


## An aspirator ("pooter"): a clear vial standing on its foot, a rubber stopper, a short glass pipe out of it to suck
## an ant in, and a hose from the stopper to a mouthpiece, lying in a loose curve on the desk.
func _aspirator(at: Vector3, coiled := false) -> void:
	var g := Node3D.new()
	g.position = at
	add_child(g)
	_cyl(0.013, 0.065, Vector3(0, 0.0325, 0), _glass_mat(0.24), g, -1.0, 20)
	_cyl(0.0128, 0.002, Vector3(0, 0.001, 0), _glass_mat(0.4), g, -1.0, 20)        # (its thicker foot)
	var rubber := flat(Color(0.2, 0.2, 0.22), 0.7)
	_cyl(0.012, 0.018, Vector3(0, 0.072, 0), rubber, g, 0.0135, 20)
	var pipe := _glass_mat(0.3)
	_stick(Vector3(0.004, 0.06, 0.0), Vector3(0.03, 0.098, 0.004), 0.0026, pipe, g)    # the intake, angled out
	_stick(Vector3(-0.004, 0.07, 0.0), Vector3(-0.006, 0.09, 0.0), 0.0026, pipe, g)
	_blob(Vector3(0.0028, 0.0006, 0.0028), Vector3(-0.004, 0.055, 0.0), flat(Color(0.9, 0.9, 0.9), 0.9), g)   # gauze
	var hose := flat(Color(0.85, 0.55, 0.3), 0.45)
	if coiled:
		# put away: the hose down from the stopper and coiled beside the vial, the mouthpiece in the coil
		_stick(Vector3(-0.006, 0.09, 0), Vector3(0.03, 0.06, 0.03), 0.0032, hose, g)
		_stick(Vector3(0.03, 0.06, 0.03), Vector3(0.06, 0.006, 0.07), 0.0032, hose, g)
		var coil := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.022
		tm.outer_radius = 0.0284
		tm.rings = 24
		tm.ring_segments = 8
		coil.mesh = tm
		coil.material_override = hose
		coil.position = Vector3(0.085, 0.0035, 0.095)
		g.add_child(coil)
		var coil2: MeshInstance3D = coil.duplicate()
		coil2.position.y += 0.0062
		coil2.scale = Vector3.ONE * 0.92
		g.add_child(coil2)
		_cyl(0.004, 0.025, Vector3(0.085, 0.006, 0.095), flat(Color(0.15, 0.15, 0.16), 0.5), g).rotation.z = PI * 0.5
		return
	# the hose: clear-ish orange tubing in a loose curve down to the desk and a mouthpiece
	var pts := [Vector3(-0.006, 0.09, 0), Vector3(-0.02, 0.1, 0.005), Vector3(-0.045, 0.07, 0.015), Vector3(-0.06, 0.02, 0.03),
		Vector3(-0.07, 0.004, 0.06), Vector3(-0.05, 0.004, 0.09), Vector3(-0.015, 0.004, 0.1)]
	for i in pts.size() - 1:
		_stick(pts[i], pts[i + 1], 0.0032, hose, g)
	_cyl(0.004, 0.025, Vector3(0.0, 0.004, 0.1), flat(Color(0.15, 0.15, 0.16), 0.5), g).rotation.z = PI * 0.5   # mouthpiece


## Soft forceps (featherweight): two thin blades of spring steel joined at the back, their tips a little apart.
func _forceps(at: Vector3, turn: float) -> void:
	var g := Node3D.new()
	g.position = at + Vector3(0, 0.0015, 0)
	g.rotation.y = turn
	add_child(g)
	var steel := flat(Color(0.7, 0.71, 0.72), 0.25, 0.9)
	for s in [-1.0, 1.0]:
		_stick(Vector3(-0.055, 0.003, 0.0), Vector3(0.0, 0.004, s * 0.0045), 0.0013, steel, g)
		_stick(Vector3(0.0, 0.004, s * 0.0045), Vector3(0.055, 0.0012, s * 0.0012), 0.0009, steel, g)
	_box(Vector3(0.006, 0.004, 0.004), Vector3(-0.056, 0.003, 0), steel, g)


## A fine paintbrush: a lacquered handle, a crimped ferrule, a small pointed tuft.
func _brush(at: Vector3, turn: float) -> void:
	var g := Node3D.new()
	g.position = at + Vector3(0, 0.0032, 0)
	g.rotation.y = turn
	add_child(g)
	var handle := _cyl(0.003, 0.13, Vector3(-0.02, 0, 0), flat(Color(0.12, 0.2, 0.35), 0.35), g, 0.0024, 10)
	handle.rotation.z = PI * 0.5
	var ferrule := _cyl(0.0024, 0.018, Vector3(0.054, 0, 0), flat(Color(0.75, 0.74, 0.7), 0.25, 0.9), g, 0.0018, 10)
	ferrule.rotation.z = -PI * 0.5
	var tuft := _cyl(0.0017, 0.012, Vector3(0.069, 0, 0), flat(Color(0.32, 0.22, 0.14), 0.9), g, 0.0002, 8)
	tuft.rotation.z = -PI * 0.5


## A 5 ml syringe for water: clear barrel with its finger flange, a white plunger, the luer tip.
func _syringe(at: Vector3, turn: float) -> void:
	var g := Node3D.new()
	g.position = at + Vector3(0, 0.0068, 0)
	g.rotation.y = turn
	add_child(g)
	var barrel := _cyl(0.0065, 0.07, Vector3.ZERO, _glass_mat(0.28), g, -1.0, 16)
	barrel.rotation.z = PI * 0.5
	var water := StandardMaterial3D.new()
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.albedo_color = Color(0.6, 0.75, 0.88, 0.4)
	var w := _cyl(0.006, 0.03, Vector3(0.018, 0, 0), water, g, -1.0, 14)
	w.rotation.z = PI * 0.5
	var white := flat(Color(0.95, 0.95, 0.94), 0.5)
	var plunger := _cyl(0.0058, 0.004, Vector3(0.002, 0, 0), flat(Color(0.15, 0.15, 0.15), 0.6), g, -1.0, 14)   # its rubber
	plunger.rotation.z = PI * 0.5
	var rod := _box(Vector3(0.06, 0.004, 0.004), Vector3(-0.028, 0, 0), white, g)
	rod.name = "rod"
	var thumb := _cyl(0.008, 0.002, Vector3(-0.058, 0, 0), white, g, -1.0, 16)
	thumb.rotation.z = PI * 0.5
	_box(Vector3(0.002, 0.004, 0.022), Vector3(-0.034, 0, 0), _glass_mat(0.35), g)          # the finger flange
	var tip := _cyl(0.002, 0.009, Vector3(0.0395, 0, 0), _glass_mat(0.35), g, 0.001, 10)
	tip.rotation.z = -PI * 0.5
	for i in 6:                                                                   # graduations
		_box(Vector3(0.0004, 0.0003, 0.004), Vector3(-0.02 + i * 0.01, 0.0064, 0), flat(Color(0.1, 0.1, 0.1), 0.8), g)


## A petri dish as the feeding dish, its lid leaning against it: a drop of honey and a dead cricket's leg in it.
func _petri(at: Vector3, lid_on := false) -> void:
	var g := Node3D.new()
	g.position = at
	add_child(g)
	var glass := _glass_mat(0.2)
	_cyl(0.045, 0.0015, Vector3(0, 0.00075, 0), glass, g, -1.0, 32)                      # its floor
	var wall := _cyl(0.045, 0.012, Vector3(0, 0.006, 0), glass, g, -1.0, 32)
	wall.name = "wall"
	var honey := StandardMaterial3D.new()
	honey.albedo_color = Color(0.85, 0.52, 0.12)
	honey.roughness = 0.08
	honey.metallic_specular = 0.9
	_blob(Vector3(0.007, 0.0018, 0.006), Vector3(-0.012, 0.0028, 0.008), honey, g)
	var leg := flat(Color(0.55, 0.38, 0.2), 0.6)
	_stick(Vector3(0.008, 0.0025, -0.01), Vector3(0.024, 0.0045, -0.016), 0.0012, leg, g)
	_stick(Vector3(0.024, 0.0045, -0.016), Vector3(0.033, 0.0022, -0.004), 0.0008, leg, g)
	if lid_on:
		_cyl(0.047, 0.01, Vector3(0, 0.0115, 0), glass, g, -1.0, 32)                 # (its lid on, put away)
	else:
		var lid := _cyl(0.047, 0.01, Vector3(0.06, 0.03, 0.0), glass, g, -1.0, 32)
		lid.rotation.z = 1.2                                                       # (stood on its edge, leaning)


## A hand lens: a glass disc in a black rim on a handle, lying flat.
func _lens(at: Vector3, turn := -0.5) -> void:
	var g := Node3D.new()
	g.position = at
	g.rotation.y = turn
	add_child(g)
	var black := flat(Color(0.06, 0.06, 0.07), 0.35)
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.032
	tm.outer_radius = 0.037
	tm.rings = 32
	tm.ring_segments = 8
	rim.mesh = tm
	rim.material_override = black
	rim.position = Vector3(0, 0.0028, 0)
	g.add_child(rim)
	_blob(Vector3(0.033, 0.0022, 0.033), Vector3(0, 0.0028, 0), _glass_mat(0.12), g)
	var handle := _cyl(0.0055, 0.09, Vector3(0.081, 0.0055, 0), black, g, 0.0065, 14)
	handle.rotation.z = PI * 0.5


## A small bottle of PTFE (Fluon) with a brush cap, a white label with a blue band.
func _fluon(at: Vector3) -> void:
	var g := Node3D.new()
	g.position = at
	add_child(g)
	_cyl(0.016, 0.05, Vector3(0, 0.025, 0), flat(Color(0.93, 0.93, 0.92), 0.35), g, -1.0, 20)
	_cyl(0.0162, 0.02, Vector3(0, 0.024, 0), flat(Color(0.97, 0.97, 0.96), 0.7), g, -1.0, 20)      # label
	_cyl(0.0163, 0.005, Vector3(0, 0.03, 0), flat(Color(0.12, 0.35, 0.7), 0.6), g, -1.0, 20)
	_cyl(0.008, 0.006, Vector3(0, 0.053, 0), flat(Color(0.93, 0.93, 0.92), 0.35), g, -1.0, 16)    # neck
	_cyl(0.0095, 0.022, Vector3(0, 0.067, 0), flat(Color(0.1, 0.1, 0.11), 0.5), g, 0.009, 16)      # the cap
