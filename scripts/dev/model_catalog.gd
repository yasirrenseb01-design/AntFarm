extends RefCounted
## What the developer's 3D model room shows (ui/model_room.gd; PART 0.14 step 10, gone over again in step 11 with the
## keeper, 2026-11-21: "near and far in one card, chosen inside; the eggs; the brood's stages and how one turns into the
## next; each enemy's poses; the cricket's states; the fly's wings; the wild plot's other plants; the stones' kinds and
## the soil's grains - look for what else is missing"). Made with the game's own code and materials where it has them,
## so a card looks as the thing does in the game (bar what moves it there).
## An item: {key (its word), src (its file or maker), mm (a unit in life), vars [[word, maker -> Node3D]],
##   poses (an enemy's: drawn by its own shader, ui/model_room.gd _pose), cycle (the brood's stages one after another)}

const AntModel := preload("res://scripts/view/common/ant_model3d.gd")
const MeshKit := preload("res://scripts/view/common/mesh_kit.gd")
const RockMesh := preload("res://scripts/view/common/rock_mesh.gd")
const Lumps := preload("res://scripts/view/common/lumps.gd")
const WeedMesh := preload("res://scripts/view/common/weed_mesh.gd")
const CreatureRig := preload("res://scripts/view/outworld/creature_rig.gd")
const HomeTools := preload("res://scripts/view/home/home_tools.gd")
const HomeFridge := preload("res://scripts/view/home/home_fridge.gd")
const GAME_MM := 1.5             # mm a game unit (the ants, the enemies, the prey, the plants, the ground)
const M_MM := 1000.0             # the Home's things: metres
const ANT_TINT := Color(0.16, 0.13, 0.11)
const MOSS := Color(0.3, 0.43, 0.13)            # (scenery_draw: 0.2,0.33,0.1 .. 0.4,0.53,0.17)
const SOIL := Color(0.42, 0.33, 0.24)           # (the crater's grains: the ground's colour, darkened)
## the enemies as the outworld draws them (outworld_view.gd): shader, scale, how many legs' joints
const FOES := {"wolf_spider": ["res://shaders/creatures/spider.gdshader", 0.85], "centipede": ["res://shaders/creatures/centipede.gdshader", 1.0],
	"ground_beetle": ["res://shaders/creatures/beetle.gdshader", 1.0]}
const POSES := ["mdl_pose_walk", "mdl_pose_stand", "mdl_pose_strike", "mdl_pose_held", "mdl_pose_back", "mdl_pose_dead"]
const SPIDER_POSES := ["mdl_pose_feed", "mdl_pose_shake"]


static func cats(holder: Node) -> Array:
	return [["mdl_tab_ants", _ants()], ["mdl_tab_enemies", _foes()], ["mdl_tab_prey", _prey()], ["mdl_tab_plants", _plants()],
		["mdl_tab_ground", _ground(holder)], ["mdl_tab_home", _home(holder)]]


static func _ants() -> Array:
	var out := []
	for n in ["worker", "queen", "gyne", "male"]:
		var vars := []
		for d in [["mdl_near", "hi"], ["mdl_far", "lo"]]:
			var path := "res://assets/models/ants/%s_%s.antmesh" % [n, d[1]]
			vars.append([d[0], func(): return ant(AntModel.load_antmesh(path))])
		out.append({"key": "mdl_" + n, "src": "ants/%s_{hi,lo}.antmesh" % n, "mm": GAME_MM, "vars": vars})
	# the brood: each stage, and played one after another (the cycle)
	var stages := [["mdl_egg", func(): return egg()], ["mdl_larva_s", func(): return larva(0.0)], ["mdl_larva_m", func(): return larva(0.5)],
		["mdl_larva_l", func(): return larva(1.0)], ["mdl_cocoon", func(): return cocoon(0.0)], ["mdl_cocoon_late", func(): return cocoon(1.0)],
		["mdl_larva_g", func(): return larva(1.0, 2.0)], ["mdl_larva_m_x", func(): return larva(1.0, 1.35)]]
	out.append({"key": "mdl_brood", "src": "nest_scene._ellipsoid / mesh_kit.larva() / cocoon()", "mm": GAME_MM, "vars": stages, "cycle": true})
	return out


static func _foes() -> Array:
	var out := []
	for k in FOES:
		var kind: String = k
		out.append({"key": "mdl_" + kind, "src": "creatures/%s.antmesh + %s" % [kind, String(FOES[kind][0]).get_file()],
			"mm": GAME_MM * float(FOES[kind][1]), "vars": [["mdl_shader", func(): return creature(kind)]],
			"poses": POSES + (SPIDER_POSES if kind == "wolf_spider" else [])})
	return out


static func _prey() -> Array:
	var aphids := []
	for i in 3:
		var k: int = i
		aphids.append([["mdl_aphid_adult", "mdl_aphid_nymph", "mdl_aphid_winged"][k], func():
			var n := prop(MeshKit.aphid(k))
			if k == 2:
				var w := MeshInstance3D.new()
				w.mesh = MeshKit.aphid_wings()
				w.material_override = glass(Color(0.85, 0.9, 1.0, 0.3))
				n.add_child(w)
			return n])
	var crickets := [["mdl_whole", func(): return cricket(1.0, false, 2)], ["mdl_half_eaten", func(): return cricket(0.55, false, 2)],
		["mdl_leg_off", func(): return cricket(0.3, false, 2)], ["mdl_leg_off_other", func(): return cricket(0.3, false, 3)],
		["mdl_rotten", func(): return cricket(1.0, true, 2)], ["mdl_rotten_eaten", func(): return cricket(0.3, true, 3)]]
	var flies := [["mdl_whole", func(): return fly(1.0)], ["mdl_half_eaten", func(): return fly(0.4)]]
	return [{"key": "mdl_aphid", "src": "prey/aphid_*.antmesh", "mm": GAME_MM, "vars": aphids},
		{"key": "mdl_cricket", "src": "prey/cricket_*.antmesh + outworld_props._food_cricket", "mm": GAME_MM, "vars": crickets},
		{"key": "mdl_fly", "src": "prey/fly.antmesh + fly_wings.antmesh", "mm": GAME_MM, "vars": flies},
		{"key": "mdl_honey", "src": "outworld_props._food_honey", "mm": GAME_MM, "vars": [["mdl_honey_drop", func(): return blob(Vector3(5.5, 2.1, 5.0), honey())],
			["mdl_honeydew", func(): return blob(Vector3(0.15, 0.14, 0.15), honey())]]}]


static func _plants() -> Array:
	var out := []
	for p in 3:
		var vars := []
		for st in 4:
			var path := "res://assets/models/plants/plant%d_%d.antmesh" % [p, st]
			vars.append(["mdl_stage_%d" % st, func(): return sway(AntModel.load_antmesh(path), Color(0.05, 0.07, 0.02), 0.7)])
		out.append({"key": "mdl_bean_%d" % p, "src": "plants/plant%d_{0..3}.antmesh" % p, "mm": GAME_MM, "vars": vars})
	var weeds := []
	for k in [["mdl_plantain", WeedMesh.PLANTAIN], ["mdl_dandelion", WeedMesh.DANDELION], ["mdl_clover", WeedMesh.CLOVER]]:
		var kind: int = k[1]
		weeds.append([k[0], func(): return weed(kind)])
	out.append({"key": "mdl_weeds", "src": "weed_mesh.gd + weed_leaf.gdshader", "mm": GAME_MM, "vars": weeds})
	out.append({"key": "mdl_grass", "src": "mesh_kit.blade() + sway.gdshader", "mm": GAME_MM, "vars": [["mdl_grass_green", func(): return grass(false)],
		["mdl_grass_dry", func(): return grass(true)]]})
	out.append({"key": "mdl_moss", "src": "lumps.moss()", "mm": GAME_MM, "vars": [["mdl_moss_0", func(): return vc(Lumps.moss(0), 1.0, Vector3.ONE * 3.0, false, MOSS)],
		["mdl_moss_1", func(): return vc(Lumps.moss(1), 1.0, Vector3.ONE * 3.0, false, MOSS)]]})
	return out


static func _ground(holder: Node) -> Array:
	var rocks := []
	for k in [["mdl_rock_round", 0], ["mdl_rock_slate", 1], ["mdl_rock_granite", 2]]:
		var kind: int = k[1]
		rocks.append([k[0], func(): return vc(RockMesh.mesh(round_outline(14.0, 11 + kind), 14.0, 0.5, 11 + kind, kind), 0.9)])
	var grains := []
	for i in Lumps.PELLETS:
		var k: int = i
		grains.append(["mdl_grain_%d" % k, func(): return vc(Lumps.pellet(k), 0.95, Vector3.ONE * 0.4, false, SOIL)])
	grains.append(["mdl_grain_carried", func(): return vc(Lumps.carried(), 0.95, Vector3.ONE, false, SOIL)])
	return [{"key": "mdl_rocks", "src": "rock_mesh.mesh(kind 0-2)", "mm": GAME_MM, "vars": rocks},
		{"key": "mdl_grains", "src": "lumps.pellet(0-4), carried()", "mm": GAME_MM, "vars": grains},
		{"key": "mdl_pebble", "src": "outworld_scene._blob_mesh", "mm": GAME_MM, "vars": [["mdl_pebble", func(): return blob(Vector3(1.2, 0.7, 1.0), flat(Color(0.5, 0.46, 0.4)))]]},
		{"key": "mdl_litter", "src": "mesh_kit.leaf() / twig()", "mm": GAME_MM, "vars": [["mdl_leaf", func(): return sway(MeshKit.leaf(9.0, 4.0, Color(0.55, 0.38, 0.16), 0.4), Color(0.08, 0.05, 0.02), 0.8, true, true)],
			["mdl_twig", func(): return prop(MeshKit.twig(16.0, 5))]]},
		{"key": "mdl_tanks", "src": "home_kit._tank()", "mm": M_MM, "vars": [["mdl_tank_small", func(): return kit(holder, "_tank", [false])],
			["mdl_tank_big", func(): return kit(holder, "_tank", [true])]]}]


static func _home(holder: Node) -> Array:
	var out := []
	for it in [["mdl_tubes", "_tubes", [Vector3.ZERO, 0.0]], ["mdl_aspirator", "_aspirator", [Vector3.ZERO, true]],
			["mdl_forceps", "_forceps", [Vector3.ZERO, 0.0]], ["mdl_brush", "_brush", [Vector3.ZERO, 0.0]],
			["mdl_syringe", "_syringe", [Vector3.ZERO, 0.0]], ["mdl_petri", "_petri", [Vector3.ZERO, true]],
			["mdl_lens", "_lens", [Vector3.ZERO, 0.0]], ["mdl_fluon", "_fluon", [Vector3.ZERO]], ["mdl_tray", "_tray", [Vector3.ZERO]],
			["mdl_notebook", "_notebook", [Vector3.ZERO, 0.0]], ["mdl_pencil", "_pencil", [Vector3.ZERO, 0.0]], ["mdl_chair", "_chair", []]]:
		var meth: String = it[1]
		var args: Array = it[2]
		out.append({"key": it[0], "src": "home_tools.%s()" % meth, "mm": M_MM, "vars": [["mdl_one", func(): return kit(holder, meth, args)]]})
	out.append({"key": "mdl_fridge", "src": "home_fridge.build()", "mm": M_MM, "vars": [["mdl_one", func():
		var n := Node3D.new()
		HomeFridge.build(n, Vector3.ZERO, 0.0)
		return n]]})
	var hands := []
	for n in [["mdl_hand_open", "hand_open"], ["mdl_hand_point", "hand_point"], ["mdl_sleeve", "sleeve"]]:
		var path := "res://assets/models/hand/%s.antmesh" % n[1]
		hands.append([n[0], func(): return prop(AntModel.load_antmesh(path))])
	out.append({"key": "mdl_hand", "src": "hand/*.antmesh", "mm": M_MM, "vars": hands})
	var trees := []
	for n in ["tree_a", "tree_b"]:
		var path := "res://assets/models/trees/%s.antmesh" % n
		trees.append(["mdl_" + n, func(): return prop(AntModel.load_antmesh(path))])
	out.append({"key": "mdl_tree", "src": "trees/tree_{a,b}.antmesh", "mm": 0.0, "vars": trees})
	return out


# ---------------------------------------------------------------- makers

## The ants: vertex colours times a tint as the game's shader takes them; the wings (part 12) pale and clear.
const ANT_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 tint = vec3(0.16, 0.13, 0.11);
uniform float fade = 1.0;
void fragment() {
	float part = floor(COLOR.a * 16.0 + 0.5);
	bool wing = part > 11.5 && part < 12.5;
	ALBEDO = wing ? mix(COLOR.rgb, vec3(0.86, 0.84, 0.8), 0.6) : COLOR.rgb * tint;
	ROUGHNESS = wing ? 0.3 : 0.7;
	ALPHA = (wing ? 0.55 : 1.0) * fade;
}
"""
static var _ant_shader: Shader = null


static func ant(m: Mesh) -> MeshInstance3D:
	if _ant_shader == null:
		_ant_shader = Shader.new()
		_ant_shader.code = ANT_SHADER
	var mi := MeshInstance3D.new()
	mi.mesh = m
	var sm := ShaderMaterial.new()
	sm.shader = _ant_shader
	sm.set_shader_parameter("tint", Vector3(ANT_TINT.r, ANT_TINT.g, ANT_TINT.b))
	mi.material_override = sm
	return mi


## An egg as the nest draws it (nest_scene._ellipsoid(0.32, 0.2), nest_view's egg material).
static func egg() -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = 0.2
	s.height = 0.4
	var mi := MeshInstance3D.new()
	mi.mesh = s
	mi.scale = Vector3(0.32 / 0.2, 1, 1)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.95, 0.96, 0.95, 0.88)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.12
	m.rim_enabled = true
	m.rim = 0.5
	mi.material_override = m
	return mi


## A larva at growth p (0..1), as the nest scales it (nest_piles: 0.28 + 0.8 p; a gyne's x2.0, a male's x1.35).
static func larva(p: float, k := 1.0) -> MeshInstance3D:
	var mi := vc(MeshKit.larva(), 0.3, Vector3.ONE * (0.28 + 0.8 * p) * k, true)
	return mi


## A cocoon, whitish when spun, greyer as the adult inside darkens (nest_piles: from p 0.75).
static func cocoon(late: float) -> MeshInstance3D:
	var mi := vc(MeshKit.cocoon(), 0.85, Vector3.ONE, true)
	(mi.material_override as StandardMaterial3D).albedo_color = Color.WHITE.lerp(Color(0.72, 0.72, 0.72), late)
	return mi


## An enemy drawn by its own shader (outworld_view.gd): one instance; its pose set each frame by ui/model_room.gd.
static func creature(kind: String) -> Node3D:
	var mat := ShaderMaterial.new()
	mat.shader = load(FOES[kind][0])
	mat.set_shader_parameter("nest_xz", Vector2(-10000, -10000))     # (no nest mound under it: flat ground)
	mat.set_shader_parameter("mound_h", 0.0)
	var cv := {"mat": mat}
	CreatureRig.setup(cv, "creatures/" + kind)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = MeshKit.spider() if kind == "wolf_spider" else MeshKit.asset("creatures/" + kind)
	mm.instance_count = 1
	var sc: float = FOES[kind][1]
	mm.set_instance_transform(0, Transform3D(Basis.from_scale(Vector3.ONE * sc), Vector3.ZERO))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.set_meta("creature", {"kind": kind, "scale": sc, "stride": float(cv.get("stride", 3.0))})
	return mmi


## The cricket carcass as the outworld lays it out (outworld_props._food_cricket): `left` of it uneaten - the abdomen
## sags, wounds open, and under 0.35 one hind leg comes off (which one: the seed's).
static func cricket(left: float, rotten: bool, seed_value: int) -> Node3D:
	var body := Node3D.new()
	body.rotation.x = 0.12
	var mat := prop_mat()
	if rotten:
		mat = mat.duplicate()
		mat.albedo_color = Color(0.72, 0.78, 0.66)
	var gone := 1.0 - left
	var lost := ("cricket_hindleg_l" if seed_value % 2 == 0 else "cricket_hindleg_r") if left < 0.35 else ""
	for pc in ["cricket_head", "cricket_abdomen", "cricket_hindleg_l", "cricket_hindleg_r", "cricket_legs"]:
		var mi := MeshInstance3D.new()
		mi.mesh = MeshKit.asset("prey/" + pc)
		mi.material_override = mat
		body.add_child(mi)
		if pc == lost:
			var sd := -1.0 if pc.ends_with("_l") else 1.0
			var piv := Vector3(-7.3, 0.0, 2.8 * sd)
			var tip := Transform3D(Basis.IDENTITY, piv) * Transform3D(Basis(Vector3.BACK, -0.22), Vector3.ZERO) * Transform3D(Basis.IDENTITY, -piv)
			mi.transform = Transform3D(Basis(Vector3.UP, -0.3 * sd), Vector3(1.2, 0.15, 2.0 * sd)) * tip
			var socket := blob(Vector3(0.45, 0.3, 0.4), flat(Color(0.78, 0.62, 0.46)))
			socket.position = Vector3(0.5, 1.75, 1.45 * sd)
			body.add_child(socket)
		if pc == "cricket_abdomen":
			var sc := Vector3(1.0 - 0.06 * gone, 1.0 - 0.5 * gone, 1.0 - 0.15 * gone)
			var pivot := Vector3(-1.6, 0.25, 0)
			mi.scale = sc
			mi.position = pivot - pivot * sc
			var wa := MeshKit.cricket_wounds(left, seed_value, true)
			if wa != null:
				var w := MeshInstance3D.new()
				w.mesh = wa
				w.material_override = prop_mat()
				mi.add_child(w)
	var wf := MeshKit.cricket_wounds(left, seed_value, false)
	if wf != null:
		var w2 := MeshInstance3D.new()
		w2.mesh = wf
		w2.material_override = prop_mat()
		body.add_child(w2)
	return body


## A dead house fly on its back with its wings (outworld_props._food_fly): smaller as it is eaten.
static func fly(left: float) -> Node3D:
	var n := Node3D.new()
	var b := prop(MeshKit.asset("prey/fly"))
	n.add_child(b)
	var w := MeshInstance3D.new()
	w.mesh = MeshKit.asset("prey/fly_wings")
	var wm := glass(Color(0.78, 0.8, 0.85, 0.35))
	wm.rim_enabled = true
	w.material_override = wm
	n.add_child(w)
	n.scale = Vector3.ONE * (0.6 + 0.4 * left)
	return n


## A tuft of blades as the outworld grows them (scenery_draw.gd): one multimesh, each blade its own green (or straw).
static func grass(dry: bool) -> Node3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = MeshKit.blade()
	mm.instance_count = 9
	var g := RandomNumberGenerator.new()
	g.seed = 5
	for i in 9:
		var hgt := g.randf_range(6.0, 17.0) * 1.4
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, g.randf() * TAU).scaled(Vector3(hgt * 0.6, hgt, hgt * 0.6)),
			Vector3(cos(i * 2.4), 0, sin(i * 2.4)) * g.randf_range(0.3, 1.6)))
		var col := Color(0.56, 0.5, 0.32).lerp(Color(0.68, 0.6, 0.4), g.randf()) if dry else Color(0.24, 0.42, 0.13).lerp(Color(0.5, 0.64, 0.26), g.randf())
		mm.set_instance_color(i, col.srgb_to_linear())
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = sway_mat(Color(0.05, 0.07, 0.02), 0.65, false)
	return mmi


static func weed(kind: int) -> Node3D:
	var wm := WeedMesh.new()
	var r := RandomNumberGenerator.new()
	r.seed = 7 + kind
	wm.plant(kind, Vector3.ZERO, 1.0, r, func(p: Vector2): return Vector3(p.x, 0.0, p.y))
	var mi := MeshInstance3D.new()
	mi.mesh = wm.commit()
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/plants/weed_leaf.gdshader")
	mi.material_override = m
	return mi


## The Home's things, made by the room's own code (view/home/home_tools.gd, home_kit.gd) on a builder of its own.
static func kit(holder: Node, meth: String, args: Array) -> Node3D:
	var k = HomeTools.new()
	if meth == "_tank":
		if holder != null and holder.is_inside_tree():
			holder.add_child(k)                 # (_tank reads its global place for the Home's hand: in the tree while made)
		k._tank(k, Vector3.ZERO, args[0], false, 0, 1, true, 0.0)      # (slot 0: no save of the keeper's read - plain soil)
		if k.get_parent() != null:
			k.get_parent().remove_child(k)
	else:
		k.callv(meth, args)
	return k


# ---------------------------------------------------------------- materials (as the outworld's: outworld_view.gd)

static func prop_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.8
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func prop(m: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = prop_mat()
	return mi


## tint: what the outworld gives each one as its instance colour (scenery_draw.gd: moss, the crater's grains)
static func vc(m: Mesh, rough: float, s := Vector3.ONE, srgb := false, tint := Color.WHITE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = srgb
	mat.roughness = rough
	mat.albedo_color = tint
	mi.material_override = mat
	mi.scale = s
	return mi


static func sway(m: Mesh, back: Color, rough: float, srgb := true, veins := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = sway_mat(back, rough, srgb, veins)
	return mi


## The plants' and the litter's swaying material (outworld_scene._sway_mat).
static func sway_mat(back: Color, rough: float, srgb := true, veins := false) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/plants/sway.gdshader")
	mat.set_shader_parameter("srgb_colors", srgb)
	mat.set_shader_parameter("backlight", Vector3(back.r, back.g, back.b))
	mat.set_shader_parameter("roughness_v", rough)
	if veins:
		mat.set_shader_parameter("leaf_veins", true)
	return mat


static func flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	return m


static func glass(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	m.roughness = 0.1
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func honey() -> StandardMaterial3D:
	var m := glass(Color(0.85, 0.5, 0.1, 0.82))
	m.metallic_specular = 0.9
	m.rim_enabled = true
	return m


static func blob(r: Vector3, mat: Material) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	var mi := MeshInstance3D.new()
	mi.mesh = s
	mi.scale = r
	mi.material_override = mat
	return mi


static func round_outline(r: float, sd: int) -> PackedVector2Array:
	var g := RandomNumberGenerator.new()
	g.seed = sd
	var o := PackedVector2Array()
	for i in 14:
		o.append(Vector2.from_angle(TAU * i / 14.0) * r * g.randf_range(0.75, 1.1))
	return o
