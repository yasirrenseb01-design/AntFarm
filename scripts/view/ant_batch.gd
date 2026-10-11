extends Node2D
## Draws every forager in a few GPU batches (MultiMesh) instead of dozens of draw calls per ant.
## The body mesh is animated per ant by shaders/ant2d.gdshader (legs in tripod gait, antennae
## sweeping or drumming, head biting); loads (honeydew, prey, a dead nestmate) are overlays.

const Ant := preload("res://scripts/sim/ant.gd")
const Kit := preload("res://scripts/view/draw_kit.gd")

var _shadow: MultiMesh
var _body: MultiMesh
var _replete: MultiMesh
var _prey: MultiMesh
var _corpse: MultiMesh


func _ready() -> void:
	_shadow = _make(_shadow_mesh())
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/ant2d.gdshader")
	_body = _make(_body_mesh(), mat, true)
	_replete = _make(_replete_mesh())
	_prey = _make(_prey_mesh())
	_corpse = _make(_corpse_mesh())


func _make(mesh: ArrayMesh, mat: Material = null, custom := false) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.use_custom_data = custom
	mm.mesh = mesh
	mm.instance_count = 64
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance2D.new()
	mi.multimesh = mm
	if mat:
		mi.material = mat
	add_child(mi)
	return mm


# ---------------------------------------------------------------- mesh building

class Builder:
	var v := PackedVector2Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var i := PackedInt32Array()
	var part := 0.0         # body-part id stored in UV.x for the animation shader

	func poly(pts: PackedVector2Array, col: Color) -> void:
		var base := v.size()
		v.append_array(pts)
		for p in pts:
			c.append(col)
			uv.append(Vector2(part, 0.0))
		for k in Geometry2D.triangulate_polygon(pts):
			i.append(base + k)

	func seg(a: Vector2, b: Vector2, w: float, col: Color) -> void:
		var n := (b - a).orthogonal().normalized() * w * 0.5
		poly(PackedVector2Array([a - n, b - n, b + n, a + n]), col)

	func mesh() -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_INDEX] = i
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m


## Neutral pose; part ids: 0 trunk, 1 head, 2/3 antennae (left/right), 4-9 legs, 10 gaster.
func _body_mesh() -> ArrayMesh:
	var b := Builder.new()
	var limb := Color(1.25, 1.25, 1.25)       # a touch lighter than the body once tinted
	var ax := [0.85, 0.25, -0.35]
	var kx := [0.7, 0.1, -0.6]
	var fx := [1.7, -0.1, -2.0]
	for k in 3:
		for side in [-1.0, 1.0]:
			b.part = 4 + k * 2 + (0 if side < 0.0 else 1)
			var hip := Vector2(ax[k], 0.45 * side)
			var knee := Vector2(ax[k] + kx[k], 2.0 * side)
			var foot := Vector2(ax[k] + fx[k], 3.1 * side)
			b.seg(hip, knee, 0.34, limb)
			b.seg(knee, foot, 0.28, limb)
	for side in [-1.0, 1.0]:
		b.part = 2 if side < 0.0 else 3
		var elbow := Vector2(3.3, 1.35 * side)
		b.seg(Vector2(2.55, 0.45 * side), elbow, 0.26, limb)
		b.seg(elbow, Vector2(4.55, 1.0 * side), 0.22, limb)
	var w := Color.WHITE
	b.part = 10
	b.poly(Kit.shape("gaster", Vector2(-2.5, 0), Vector2(1.9, 1.45)), w)
	b.poly(Kit.shape("sheen_g", Vector2(-2.95, -0.5), Vector2(0.8, 0.35), 8), Color(2.2, 2.2, 2.2, 0.5))
	b.part = 0
	b.poly(Kit.shape("petiole", Vector2(-0.75, 0), Vector2(0.45, 0.4), 8), w)
	b.poly(Kit.shape("meso", Vector2(0.25, 0), Vector2(1.2, 0.68)), w)
	b.part = 1
	b.poly(Kit.shape("head", Vector2(2.05, 0), Vector2(1.05, 0.95)), w)
	b.poly(PackedVector2Array([Vector2(2.85, -0.62), Vector2(3.55, -0.05), Vector2(2.95, 0.0)]), w)
	b.poly(PackedVector2Array([Vector2(2.95, 0.0), Vector2(3.55, 0.05), Vector2(2.85, 0.62)]), w)
	b.poly(Kit.shape("sheen_h", Vector2(2.2, -0.42), Vector2(0.4, 0.2), 8), Color(2.2, 2.2, 2.2, 0.45))
	return b.mesh()


func _shadow_mesh() -> ArrayMesh:
	var b := Builder.new()
	var k := Color.WHITE
	b.poly(Kit.shape("gaster", Vector2(-2.5, 0), Vector2(1.9, 1.45)), k)
	b.poly(Kit.shape("meso", Vector2(0.25, 0), Vector2(1.2, 0.68)), k)
	b.poly(Kit.shape("head", Vector2(2.05, 0), Vector2(1.05, 0.95)), k)
	return b.mesh()


func _replete_mesh() -> ArrayMesh:
	# a crop full of honeydew stretches the gaster: the pale membranes show between dark plates
	var b := Builder.new()
	b.poly(Kit.shape("gaster_full", Vector2(-2.8, 0), Vector2(2.25, 1.75)), Color(0.36, 0.25, 0.11))
	for x in [-1.7, -2.7, -3.7]:
		b.seg(Vector2(x, -1.4), Vector2(x, 1.4), 0.4, Color(0.09, 0.065, 0.05))
	b.poly(Kit.shape("sheen_g_full", Vector2(-3.25, -0.5), Vector2(0.8, 0.35), 8), Color(1, 0.95, 0.85, 0.22))
	return b.mesh()


func _prey_mesh() -> ArrayMesh:
	var b := Builder.new()
	b.poly(PackedVector2Array([Vector2(3.4, -0.9), Vector2(4.9, -0.6), Vector2(5.2, 0.7), Vector2(3.9, 1.0),
		Vector2(3.3, 0.2)]), Kit.PREY_TINT)
	return b.mesh()


func _corpse_mesh() -> ArrayMesh:
	var b := Builder.new()
	var col := Color(0.2, 0.16, 0.13)
	var xf := Transform2D(PI * 0.5, Vector2(0.8, 0.8), 0.0, Vector2(4.6, 0))
	for part in [[Vector2(-2.4, 0), Vector2(1.8, 1.35)], [Vector2(0.25, 0), Vector2(1.15, 0.65)], [Vector2(2.0, 0), Vector2(1.0, 0.9)]]:
		var pts := PackedVector2Array()
		for i in 10:
			var a := TAU * i / 10.0
			pts.append(xf * (part[0] + Vector2(cos(a) * part[1].x, sin(a) * part[1].y)))
		b.poly(pts, col)
	return b.mesh()


# ---------------------------------------------------------------- per frame

func _push(mm: MultiMesh, n: int, xf: Transform2D, col: Color, custom := Color(0, 0, 0, 0)) -> int:
	if n >= mm.instance_count:
		var keep := mm.visible_instance_count
		mm.instance_count = mm.instance_count * 2
		mm.visible_instance_count = keep
	mm.set_instance_transform_2d(n, xf)
	mm.set_instance_color(n, col)
	if mm.use_custom_data:
		mm.set_instance_custom_data(n, custom)
	return n + 1


func update(ants: Array, body: Color, young: Color, scale: float, delta: float, running: bool) -> void:
	# the simulation jitters each ant's heading every tick (searching wiggle); the drawn body eases
	# toward where the ant is actually going so it turns smoothly instead of twitching
	var kp := 1.0 - exp(-20.0 * delta)
	var ka := 1.0 - exp(-10.0 * delta)
	var adt := delta if running else 0.0
	var nb := 0
	var ns := 0
	var nr := 0
	var np := 0
	var nc := 0
	var shadow_col := Color(0, 0, 0, 0.26)
	for a in ants:
		if a.state == Ant.IN_NEST:
			continue
		if a.vpos.x == INF or a.vpos.distance_squared_to(a.pos) > 400.0:
			a.vpos = a.pos
			a.vang = a.ang
			a.anim = randf() * 50.0
		var step: Vector2 = a.pos - a.vpos
		a.vpos += step * kp
		var moving := step.length_squared() > 0.01
		if moving:
			a.vang = lerp_angle(a.vang, step.angle(), ka)
		elif a.busy > 0:
			a.vang = lerp_angle(a.vang, a.ang, ka)     # face the food or the nestmate
		a.vmv = lerpf(a.vmv, 1.0 if moving else 0.0, minf(1.0, 10.0 * delta))
		a.anim += adt
		var s: float = scale * a.size
		var xf := Transform2D(a.vang, Vector2(s, s), 0.0, a.vpos)
		var col := body.lerp(young, clampf(1.0 - a.age / 6.0, 0.0, 1.0))
		ns = _push(_shadow, ns, Transform2D(a.vang, Vector2(s, s), 0.0, a.vpos + Vector2(1.0, 1.5) * s), shadow_col)
		nb = _push(_body, nb, xf, col, Color(fmod(a.phase, TAU * 64.0), a.act if a.busy > 0 else 0, fmod(a.anim, 600.0), a.vmv))
		if a.carry == Ant.SUGAR:
			nr = _push(_replete, nr, xf, Color.WHITE)
		elif a.carry == Ant.PROTEIN:
			np = _push(_prey, np, xf, Color.WHITE)
		elif a.carry == Ant.CORPSE:
			nc = _push(_corpse, nc, xf, Color.WHITE)
	_shadow.visible_instance_count = ns
	_body.visible_instance_count = nb
	_replete.visible_instance_count = nr
	_prey.visible_instance_count = np
	_corpse.visible_instance_count = nc
