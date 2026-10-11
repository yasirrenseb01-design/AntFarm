extends RefCounted
## Procedural drawing of creatures and objects. All shapes are drawn facing +x in local units
## (1 unit = 1 px at scale 1 ≈ 0.5 mm), then placed with a transform.

const Ant := preload("res://scripts/sim/ant.gd")

const SUGAR_TINT := Color(0.86, 0.6, 0.2)
const PREY_TINT := Color(0.55, 0.36, 0.2)

static var _unit := PackedVector2Array()


static func _circle() -> PackedVector2Array:
	if _unit.is_empty():
		for i in 12:
			_unit.append(Vector2.from_angle(TAU * i / 12.0))
	return _unit


static func ellipse(ci: CanvasItem, c: Vector2, r: Vector2, col: Color, rot := 0.0) -> void:
	var u := _circle()
	var pts := PackedVector2Array()
	pts.resize(u.size())
	var cs := cos(rot)
	var sn := sin(rot)
	for i in u.size():
		var p := Vector2(u[i].x * r.x, u[i].y * r.y)
		pts[i] = c + Vector2(p.x * cs - p.y * sn, p.x * sn + p.y * cs)
	ci.draw_colored_polygon(pts, col)


static func leaf_shape(length: float, width: float, steps := 10) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps + 1:
		var t := float(i) / steps
		pts.append(Vector2((t - 0.5) * length, -sin(t * PI) * width * (1.0 - 0.25 * t)))
	for i in range(steps - 1, 0, -1):
		var t := float(i) / steps
		pts.append(Vector2((t - 0.5) * length, sin(t * PI) * width * (1.0 - 0.25 * t)))
	return pts


# ---------------------------------------------------------------- ant

static var _shapes := {}


## Ellipse outline built once and reused (shapes drawn every frame must not rebuild their points).
static func shape(key: String, c: Vector2, r: Vector2, n := 12) -> PackedVector2Array:
	var pts: PackedVector2Array = _shapes.get(key, PackedVector2Array())
	if pts.is_empty():
		for i in n:
			var a := TAU * i / n
			pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
		_shapes[key] = pts
	return pts


static func ant(ci: CanvasItem, pos: Vector2, ang: float, scale: float, phase: float, carry: int,
		body: Color, shadow := true) -> void:
	var xf := Transform2D(ang, Vector2(scale, scale), 0.0, pos)
	var replete := carry == Ant.SUGAR
	var gaster := shape("gaster_full", Vector2(-2.8, 0), Vector2(2.25, 1.75)) if replete 		else shape("gaster", Vector2(-2.5, 0), Vector2(1.9, 1.45))
	var petiole := shape("petiole", Vector2(-0.75, 0), Vector2(0.45, 0.4), 8)
	var meso := shape("meso", Vector2(0.25, 0), Vector2(1.2, 0.68))
	var head := shape("head", Vector2(2.05, 0), Vector2(1.05, 0.95))
	if shadow:
		ci.draw_set_transform_matrix(Transform2D(ang, Vector2(scale, scale), 0.0, pos + Vector2(1.0, 1.5) * scale))
		var sc := Color(0, 0, 0, 0.26)
		ci.draw_colored_polygon(gaster, sc)
		ci.draw_colored_polygon(meso, sc)
		ci.draw_colored_polygon(head, sc)
	ci.draw_set_transform_matrix(xf)

	# six legs (tripod gait) and two elbowed antennae in one batched call
	var s := sin(phase)
	var wig := sin(phase * 1.7) * 0.25
	var lines := PackedVector2Array()
	lines.resize(32)
	var j := 0
	for k in 3:
		var ax: float = [0.85, 0.25, -0.35][k]
		var kx: float = [0.7, 0.1, -0.6][k]
		var fx: float = [1.7, -0.1, -2.0][k]
		for side in [-1.0, 1.0]:
			var sw := s if ((k % 2 == 0) == (side < 0.0)) else -s
			var knee := Vector2(ax + kx + sw * 0.35, 2.0 * side)
			lines[j] = Vector2(ax, 0.45 * side)
			lines[j + 1] = knee
			lines[j + 2] = knee
			lines[j + 3] = Vector2(ax + fx + sw * 0.8, 3.1 * side)
			j += 4
	for side in [-1.0, 1.0]:
		var elbow := Vector2(3.3, 1.35 * side)
		lines[j] = Vector2(2.55, 0.45 * side)
		lines[j + 1] = elbow
		lines[j + 2] = elbow
		lines[j + 3] = Vector2(4.55, (1.0 + wig * side) * side)
		j += 4
	ci.draw_multiline(lines, body.lightened(0.1), 0.3)

	ci.draw_colored_polygon(gaster, body.lerp(SUGAR_TINT, 0.35) if replete else body)
	if replete:
		for x in [-1.7, -2.7, -3.7]:
			ci.draw_line(Vector2(x, -1.35), Vector2(x, 1.35), body, 0.4)
	ci.draw_colored_polygon(petiole, body)
	ci.draw_colored_polygon(meso, body)
	ci.draw_colored_polygon(head, body)
	ci.draw_colored_polygon(_mandibles(), body)
	ci.draw_colored_polygon(shape("sheen_g_full" if replete else "sheen_g", Vector2(-3.25 if replete else -2.95, -0.5),
		Vector2(0.8, 0.35), 8), Color(1, 1, 1, 0.14))
	ci.draw_colored_polygon(shape("sheen_h", Vector2(2.2, -0.42), Vector2(0.4, 0.2), 8), Color(1, 1, 1, 0.12))

	if carry == Ant.PROTEIN:
		ci.draw_colored_polygon(PackedVector2Array([Vector2(3.4, -0.9), Vector2(4.9, -0.6), Vector2(5.2, 0.7),
			Vector2(3.9, 1.0), Vector2(3.3, 0.2)]), PREY_TINT)
	elif carry == Ant.CORPSE:
		ci.draw_set_transform_matrix(xf * Transform2D(PI * 0.5, Vector2(0.8, 0.8), 0.0, Vector2(4.6, 0)))
		dead_ant_local(ci, Color(0.2, 0.16, 0.13))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


static var _mand := PackedVector2Array()


static func _mandibles() -> PackedVector2Array:
	# both mandibles as one closed outline in front of the head
	if _mand.is_empty():
		_mand = PackedVector2Array([Vector2(2.85, -0.62), Vector2(3.55, -0.05), Vector2(3.0, 0.0), Vector2(3.55, 0.05),
			Vector2(2.85, 0.62), Vector2(2.95, 0.0)])
	return _mand


static func dead_ant_local(ci: CanvasItem, col: Color) -> void:
	for x in [0.85, 0.25, -0.35]:
		for side in [-1.0, 1.0]:
			ci.draw_polyline(PackedVector2Array([Vector2(x, 0.4 * side), Vector2(x + 0.4, 1.3 * side),
				Vector2(x - 0.3, 0.9 * side)]), col, 0.3, true)
	ellipse(ci, Vector2(-2.4, 0), Vector2(1.8, 1.35), col)
	ellipse(ci, Vector2(0.25, 0), Vector2(1.15, 0.65), col)
	ellipse(ci, Vector2(2.0, 0), Vector2(1.0, 0.9), col)


static func dead_ant(ci: CanvasItem, pos: Vector2, ang: float, alpha: float) -> void:
	ci.draw_set_transform_matrix(Transform2D(ang, Vector2.ONE, 0.0, pos))
	dead_ant_local(ci, Color(0.16, 0.13, 0.11, alpha))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


# ---------------------------------------------------------------- prey and food

static func cricket(ci: CanvasItem, pos: Vector2, ang: float, left: float, rotten: bool) -> void:
	# left: fraction of the carcass still there (1 = whole)
	var body := Color(0.27, 0.17, 0.09)
	var dark := Color(0.15, 0.09, 0.05)
	if rotten:
		body = body.lerp(Color(0.38, 0.4, 0.3), 0.5)
		dark = dark.lerp(Color(0.25, 0.27, 0.2), 0.5)
	var a := 0.45 + 0.55 * left
	body.a = a
	dark.a = a
	ci.draw_set_transform_matrix(Transform2D(ang, Vector2.ONE, 0.0, pos + Vector2(2, 3)))
	ellipse(ci, Vector2(-3, 0), Vector2(14, 6), Color(0, 0, 0, 0.22 * a))
	ci.draw_set_transform_matrix(Transform2D(ang, Vector2.ONE, 0.0, pos))
	for side in [-1.0, 1.0]:
		# big jumping hind legs
		ci.draw_colored_polygon(PackedVector2Array([Vector2(1, 3 * side), Vector2(-4, 8.5 * side),
			Vector2(-12, 9.5 * side), Vector2(-10, 7 * side), Vector2(-2, 3.5 * side)]), dark)
		ci.draw_polyline(PackedVector2Array([Vector2(-11, 9 * side), Vector2(-19, 6 * side), Vector2(-21, 7 * side)]), dark, 0.9, true)
		ci.draw_polyline(PackedVector2Array([Vector2(3, 3.5 * side), Vector2(5, 7.5 * side), Vector2(2, 10 * side)]), dark, 0.8, true)
		ci.draw_polyline(PackedVector2Array([Vector2(7, 3.5 * side), Vector2(10, 7 * side), Vector2(9, 9.5 * side)]), dark, 0.8, true)
		ci.draw_polyline(PackedVector2Array([Vector2(12, 1.5 * side), Vector2(20, 5 * side), Vector2(30, 9 * side),
			Vector2(36, 10 * side)]), dark, 0.45, true)
		ci.draw_line(Vector2(-12, 1 * side), Vector2(-19, 3 * side), dark, 0.6, true)
	var abd := maxf(0.35, left)
	ellipse(ci, Vector2(-4, 0), Vector2(10 * abd, 4.6 * abd), body)
	for x in [-1.0, -4.0, -7.0, -10.0]:
		if x > -4.0 - 10.0 * abd:
			ci.draw_line(Vector2(x, -4.2 * abd), Vector2(x, 4.2 * abd), dark, 0.5, true)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(5, -3.6), Vector2(-9, -2.8), Vector2(-12, 0), Vector2(-9, 2.8),
		Vector2(5, 3.6)]), Color(0.42, 0.3, 0.17, 0.55 * a))
	ellipse(ci, Vector2(6, 0), Vector2(4.2, 4.6), body)
	ellipse(ci, Vector2(11, 0), Vector2(3.4, 3.9), dark)
	ellipse(ci, Vector2(12, -1.8), Vector2(0.8, 0.6), Color(0.05, 0.03, 0.02, a))
	ellipse(ci, Vector2(12, 1.8), Vector2(0.8, 0.6), Color(0.05, 0.03, 0.02, a))
	ellipse(ci, Vector2(4, -2), Vector2(2.4, 0.9), Color(1, 1, 1, 0.1 * a))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


static func fly(ci: CanvasItem, pos: Vector2, ang: float, left: float) -> void:
	var a := 0.4 + 0.6 * left
	ci.draw_set_transform_matrix(Transform2D(ang, Vector2.ONE, 0.0, pos))
	var body := Color(0.18, 0.18, 0.17, a)
	for side in [-1.0, 1.0]:
		ellipse(ci, Vector2(-2.5, 2.2 * side), Vector2(3.6, 1.6), Color(0.85, 0.9, 1.0, 0.32 * a), 0.45 * side)
		for x in [-0.5, 0.6, 1.6]:
			ci.draw_polyline(PackedVector2Array([Vector2(x, 0.6 * side), Vector2(x + 0.6, 1.8 * side),
				Vector2(x + 0.1, 2.4 * side)]), body, 0.3, true)
	ellipse(ci, Vector2(-1.6, 0), Vector2(2.6, 1.6), body)
	ellipse(ci, Vector2(1.0, 0), Vector2(1.5, 1.4), body)
	ellipse(ci, Vector2(2.7, 0), Vector2(1.0, 1.4), body)
	ellipse(ci, Vector2(2.9, -0.9), Vector2(0.6, 0.55), Color(0.55, 0.12, 0.08, a))
	ellipse(ci, Vector2(2.9, 0.9), Vector2(0.6, 0.55), Color(0.55, 0.12, 0.08, a))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


static func honey(ci: CanvasItem, pos: Vector2, left: float) -> void:
	var r := 3.0 + 7.0 * sqrt(clampf(left, 0.0, 1.0))
	ellipse(ci, pos + Vector2(1.0, 1.4), Vector2(r * 1.15, r), Color(0.12, 0.07, 0.03, 0.35))
	ellipse(ci, pos, Vector2(r * 1.12, r), Color(0.72, 0.42, 0.08, 0.7))
	ellipse(ci, pos + Vector2(-0.2, -0.2), Vector2(r * 0.85, r * 0.75), Color(0.92, 0.62, 0.18, 0.8))
	ellipse(ci, pos + Vector2(-r * 0.35, -r * 0.4), Vector2(r * 0.3, r * 0.18), Color(1, 0.97, 0.88, 0.7), -0.4)


static func aphid_plant(ci: CanvasItem, pos: Vector2, seed: int, left: float, t: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var n := 6
	for i in n:
		var a := TAU * i / n + rng.randf_range(-0.3, 0.3)
		var length := rng.randf_range(24, 34)
		var leaf := Color(0.29, 0.47, 0.18).lerp(Color(0.42, 0.58, 0.24), rng.randf())
		var sway := sin(t * 0.8 + i) * 0.03
		var xf := Transform2D(a + sway, Vector2.ONE, 0.0, pos + Vector2.from_angle(a) * length * 0.5)
		ci.draw_set_transform_matrix(Transform2D(a + sway, Vector2.ONE, 0.0, pos + Vector2(3, 4) + Vector2.from_angle(a) * length * 0.5))
		ci.draw_colored_polygon(leaf_shape(length, 7.5), Color(0, 0, 0, 0.2))
		ci.draw_set_transform_matrix(xf)
		ci.draw_colored_polygon(leaf_shape(length, 7.5), leaf)
		ci.draw_line(Vector2(-length * 0.5, 0), Vector2(length * 0.45, 0), leaf.darkened(0.25), 0.7, true)
		for v in 3:
			var vx := -length * 0.3 + v * length * 0.22
			ci.draw_line(Vector2(vx, 0), Vector2(vx + 4, -4), leaf.darkened(0.18), 0.4, true)
			ci.draw_line(Vector2(vx, 0), Vector2(vx + 4, 4), leaf.darkened(0.18), 0.4, true)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	ellipse(ci, pos, Vector2(4.2, 4.2), Color(0.33, 0.4, 0.17))
	ellipse(ci, pos + Vector2(-1, -1), Vector2(2.2, 2.2), Color(0.45, 0.55, 0.25))
	# aphids cluster along the stem and leaf bases
	var count := 22
	for i in count:
		var a := rng.randf() * TAU
		var d := rng.randf_range(4.0, 15.0)
		var p := pos + Vector2.from_angle(a) * d
		var sz := rng.randf_range(0.7, 1.3)
		ellipse(ci, p, Vector2(1.5, 1.0) * sz, Color(0.66, 0.8, 0.42), a)
		ellipse(ci, p + Vector2(-0.3, -0.3) * sz, Vector2(0.6, 0.35) * sz, Color(0.9, 0.98, 0.75, 0.6), a)
	var drops := int(round(left * 7.0))
	for i in drops:
		var p := pos + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(3.0, 12.0)
		ellipse(ci, p, Vector2(1.1, 1.1), Color(0.98, 0.8, 0.35, 0.85))


# ---------------------------------------------------------------- predator

static func wolf_spider(ci: CanvasItem, pos: Vector2, ang: float, phase: float) -> void:
	ci.draw_set_transform_matrix(Transform2D(ang, Vector2.ONE, 0.0, pos + Vector2(2.5, 3.5)))
	ellipse(ci, Vector2(-6, 0), Vector2(9, 7), Color(0, 0, 0, 0.25))
	ellipse(ci, Vector2(5, 0), Vector2(6.5, 5.5), Color(0, 0, 0, 0.25))
	ci.draw_set_transform_matrix(Transform2D(ang, Vector2.ONE, 0.0, pos))
	var leg := Color(0.22, 0.16, 0.11)
	var base_angles := [0.55, 1.15, 1.85, 2.45]
	for k in 4:
		for side in [-1.0, 1.0]:
			var sw := sin(phase + k * 1.6 + (0.0 if side > 0 else PI)) * 0.18
			var a: float = (base_angles[k] + sw) * side
			var hip := Vector2(5 - k * 1.6, 2.0 * side)
			var knee := hip + Vector2.from_angle(a) * 11.0 + Vector2(0, 3.0 * side)
			var foot := knee + Vector2.from_angle(a + 0.5 * side * (1.0 if k < 2 else -1.0)) * 10.0
			ci.draw_polyline(PackedVector2Array([hip, knee, foot]), leg, 1.3, true)
	var body := Color(0.33, 0.24, 0.16)
	ellipse(ci, Vector2(-7, 0), Vector2(8.5, 6.5), body)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(-1, -1.4), Vector2(-14, -1.0), Vector2(-14, 1.0), Vector2(-1, 1.4)]), body.darkened(0.45))
	for x in [-5.0, -8.5, -12.0]:
		ellipse(ci, Vector2(x, -3.2), Vector2(1.1, 0.8), Color(0.55, 0.45, 0.32))
		ellipse(ci, Vector2(x, 3.2), Vector2(1.1, 0.8), Color(0.55, 0.45, 0.32))
	ellipse(ci, Vector2(5, 0), Vector2(6.2, 5.2), body.darkened(0.1))
	ci.draw_line(Vector2(0, 0), Vector2(9, 0), Color(0.62, 0.52, 0.38), 1.6, true)
	for e in [Vector2(10, -1.6), Vector2(10, 1.6), Vector2(9, -3), Vector2(9, 3)]:
		ellipse(ci, e, Vector2(0.75, 0.75), Color(0.02, 0.02, 0.02))
	for side in [-1.0, 1.0]:
		ci.draw_polyline(PackedVector2Array([Vector2(10, 1.8 * side), Vector2(14, 3.2 * side), Vector2(15.5, 2.0 * side)]), leg, 1.4, true)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


## Giant centipede from above: red head, dark segments, a pair of orange legs on each, long last legs.
static func centipede(ci: CanvasItem, pos: Vector2, ang: float, phase: float, dead := false) -> void:
	var fwd := Vector2.from_angle(ang)
	var side := fwd.orthogonal()
	var n := 21
	for i in n:
		var t := float(i) / (n - 1)
		var along := (0.5 - t) * 100.0
		var sway := sin(t * 6.0 - phase) * 3.0 if not dead else (t - 0.5) * (t - 0.5) * 40.0
		var c := pos + fwd * along + side * sway
		for s in [-1.0, 1.0]:
			var step := sin(phase * 2.0 - i * 0.9 + (PI if s > 0.0 else 0.0)) * 2.0 if not dead else 0.0
			ci.draw_line(c, c + side * s * 9.0 + fwd * (step - 1.5), Color(0.85, 0.55, 0.15), 1.1, true)
		ellipse(ci, c, Vector2(3.0, 4.6), Color(0.55, 0.2, 0.07) if i == 0 else Color(0.14, 0.14, 0.11), ang)
	var head := pos + fwd * 53.0
	ellipse(ci, head, Vector2(4.0, 4.4), Color(0.55, 0.2, 0.07), ang)
	for s in [-1.0, 1.0]:
		ci.draw_polyline(PackedVector2Array([head + side * s * 1.5, head + fwd * 12.0 + side * s * 6.0,
			head + fwd * 22.0 + side * s * 12.0]), Color(0.75, 0.32, 0.1), 1.0, true)
		var tail := pos - fwd * 50.0
		ci.draw_line(tail, tail - fwd * 20.0 + side * s * 6.0, Color(0.7, 0.3, 0.09), 1.6, true)
