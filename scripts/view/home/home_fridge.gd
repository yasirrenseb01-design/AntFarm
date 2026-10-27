extends RefCounted
## The wintering fridge in the Home's corner (the keeper, 2026-10-27: "a fridge for hibernating the ants - look up what
## they look like, and make it like that"). [Keepers' own reports: a wine cooler or a beverage cooler with an adjustable
## thermostat, set ~4-12 °C, is what most use - a kitchen fridge runs too cold and its door is opened all day
## (formiculture.com forum threads on hibernation, 2014-2021); the colony's winter rest itself: docs/BIOLOGY.md.]
## So: an under-counter beverage cooler - a matt black cabinet, a glass door in a stainless frame with a long bar
## handle, a small blue digital thermostat on the door's top rail, wire shelves on runners inside, a cool white light
## strip under its top, a vent grille at its foot, levelling feet. Inside it, the tanks whose colony is wintering in it
## (the "Hibernate in fridge" tool in the colony; the save's meta "fridge"): one tank, small or the bigger one.
## Metres; its foot's middle at the origin, its front toward +z. home_room.gd places it; clicking it says who is in.

const Kit := preload("res://scripts/view/home/home_kit.gd")
const SIZE := Vector3(1.0, 0.86, 0.68)           # outside (a wide one: the bigger tank, 90.6 x 56.9 cm, fits - the keeper,
const INNER := Vector3(0.93, 0.7, 0.6)           # 2026-10-27: "the big tank too, but only one tank")
const SHELF_Y := [0.06]                          # its shelf's top inside, from the foot (one tank on it)
const TEMP := "8°C"


## parent: the room; returns {"node", "light", "spots": [where a tank stands, in the node's space]}.
static func build(parent: Node3D, at: Vector3, turn: float) -> Dictionary:
	var f := Node3D.new()
	f.position = at
	f.rotation.y = turn
	parent.add_child(f)
	var body := Kit.flat(Color(0.06, 0.06, 0.065), 0.55, 0.2)
	var inside := Kit.flat(Color(0.16, 0.17, 0.18), 0.6)
	var steel := Kit.flat(Color(0.72, 0.73, 0.74), 0.25, 0.9)
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.55, 0.62, 0.66, 0.16)          # (tinted, a little smoky: UV glass)
	glass.roughness = 0.05
	glass.metallic_specular = 1.0
	var s := SIZE
	var foot := 0.03
	var wall := (s.x - INNER.x) * 0.5
	# the cabinet: sides, top, bottom, back (black outside, grey inside)
	_box(f, Vector3(wall, s.y - foot, s.z), Vector3(-(s.x - wall) * 0.5, foot + (s.y - foot) * 0.5, 0), body)
	_box(f, Vector3(wall, s.y - foot, s.z), Vector3((s.x - wall) * 0.5, foot + (s.y - foot) * 0.5, 0), body)
	_box(f, Vector3(s.x, 0.05, s.z), Vector3(0, s.y - 0.025, 0), body)
	_box(f, Vector3(s.x, 0.11, s.z), Vector3(0, foot + 0.055, 0), body)                       # (the compressor's plinth)
	_box(f, Vector3(s.x, s.y - foot, 0.04), Vector3(0, foot + (s.y - foot) * 0.5, -s.z * 0.5 + 0.02), body)
	_box(f, Vector3(INNER.x, INNER.y, 0.004), Vector3(0, foot + 0.11 + INNER.y * 0.5, -s.z * 0.5 + 0.042), inside)
	_box(f, Vector3(INNER.x, 0.004, INNER.z), Vector3(0, foot + 0.112, -0.02), inside)
	# the vent grille at its foot: thin slats
	for i in 6:
		_box(f, Vector3(s.x - 0.08, 0.006, 0.006), Vector3(0, foot + 0.025 + i * 0.013, s.z * 0.5 + 0.003),
			Kit.flat(Color(0.02, 0.02, 0.02), 0.8))
	# levelling feet
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var c := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.018
			cm.bottom_radius = 0.022
			cm.height = foot
			c.mesh = cm
			c.material_override = Kit.flat(Color(0.1, 0.1, 0.1), 0.7)
			c.position = Vector3(sx * (s.x * 0.5 - 0.05), foot * 0.5, sz * (s.z * 0.5 - 0.05))
			f.add_child(c)
	# wire shelves on runners: a frame and close bars, chromed
	var wire := Kit.flat(Color(0.8, 0.8, 0.82), 0.3, 0.85)
	var spots := []
	for y in SHELF_Y:
		var yy: float = foot + 0.11 + y
		for sz in [-1, 1]:
			_box(f, Vector3(INNER.x, 0.006, 0.006), Vector3(0, yy, -0.02 + sz * INNER.z * 0.46), wire)
		var n := 22
		for i in n + 1:
			var x := -INNER.x * 0.48 + INNER.x * 0.96 * i / n
			_box(f, Vector3(0.004, 0.004, INNER.z * 0.92), Vector3(x, yy, -0.02), wire)
		for sx in [-1, 1]:
			_box(f, Vector3(0.008, 0.012, INNER.z), Vector3(sx * INNER.x * 0.5, yy - 0.008, -0.02), inside)   # (runners)
		spots.append(Vector3(0, yy + 0.004, -0.02))
	# the light strip under its top
	var led := Kit.flat(Color(0.9, 0.95, 1.0), 0.4)
	led.emission_enabled = true
	led.emission = Color(0.85, 0.92, 1.0)
	led.emission_energy_multiplier = 2.0
	_box(f, Vector3(INNER.x * 0.8, 0.008, 0.02), Vector3(0, s.y - 0.06, 0.12), led)
	var light := OmniLight3D.new()
	light.position = Vector3(0, s.y - 0.09, 0.05)
	light.light_color = Color(0.82, 0.9, 1.0)
	light.light_energy = 0.5
	light.omni_range = 0.9
	light.omni_attenuation = 1.2
	f.add_child(light)
	# the door: a stainless frame round the glass, a long bar handle on the right, the thermostat on its top rail
	var dz := s.z * 0.5 + 0.02
	var dh := s.y - foot - 0.11
	var dy := foot + 0.11 + dh * 0.5
	var rail := 0.045
	_box(f, Vector3(s.x, rail, 0.03), Vector3(0, dy + dh * 0.5 - rail * 0.5, dz), steel)
	_box(f, Vector3(s.x, 0.03, 0.03), Vector3(0, dy - dh * 0.5 + 0.015, dz), steel)
	for sx in [-1, 1]:
		_box(f, Vector3(0.03, dh, 0.03), Vector3(sx * (s.x * 0.5 - 0.015), dy, dz), steel)
	_box(f, Vector3(s.x - 0.06, dh - rail - 0.03, 0.01), Vector3(0, dy - rail * 0.5 + 0.015 - 0.0075, dz), glass).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var hx := s.x * 0.5 - 0.06
	_box(f, Vector3(0.018, dh * 0.7, 0.018), Vector3(hx, dy - 0.02, dz + 0.045), steel)
	for sy in [-1, 1]:
		_box(f, Vector3(0.014, 0.014, 0.035), Vector3(hx, dy - 0.02 + sy * dh * 0.33, dz + 0.025), steel)
	var panel := Kit.flat(Color(0.03, 0.03, 0.035), 0.3)
	_box(f, Vector3(0.12, 0.028, 0.004), Vector3(-0.18, dy + dh * 0.5 - rail * 0.5, dz + 0.016), panel)
	var lab := Label3D.new()
	lab.text = TEMP
	lab.font_size = 40
	lab.pixel_size = 0.0004
	lab.modulate = Color(0.35, 0.75, 1.0)
	lab.outline_size = 0
	lab.shaded = false
	lab.position = Vector3(-0.18, dy + dh * 0.5 - rail * 0.5, dz + 0.0185)
	f.add_child(lab)
	return {"node": f, "light": light, "spots": spots}


static func _box(p: Node3D, size: Vector3, centre: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = centre
	p.add_child(mi)
	return mi
