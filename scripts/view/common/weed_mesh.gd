extends RefCounted
## The garden's low weeds, built into one mesh: broad-leaved plantain (Plantago major), dandelion (Taraxacum) and
## white clover (Trifolium repens), the commonest small plants of trodden garden ground and lawns. Each leaf is a
## strip bent the way a real one stands (up from the centre, flattening out, the tip drooping, the sides cupped);
## shaders/plants/weed_leaf.gdshader cuts its outline and draws its veins (UV across/along the strip, UV2 its kind).
## New in v0.11.38 (the weeds of v0.11.37 were flat cut-outs with a stick for a midrib - the keeper, 2026-10-24).
## [shapes: general botany - plantain's ribbed egg-shaped blades on stalks in a rosette, the dandelion's toothed
## rosette, clover's three leaflets with a pale chevron on long stalks; that they grow here: inference]

const PLANTAIN := 0
const DANDELION := 1
const CLOVER := 2
const STALK := 3
const U := 1.0 / 3.0            # px -> units (1 unit = 1.5 mm)

var st := SurfaceTool.new()
var _count := 0


func _init() -> void:
	st.begin(Mesh.PRIMITIVE_TRIANGLES)


## A weed of `kind` growing at `base` (units, on the ground); `scale` its size, `r` its own draws.
func plant(kind: int, base: Vector3, scale: float, r: RandomNumberGenerator, ground_at: Callable) -> void:
	match kind:
		PLANTAIN:
			_rosette(base, r, PLANTAIN, r.randi_range(5, 9), Vector2(28.0, 58.0) * scale, Vector2(0.26, 0.34),
				Color(0.21, 0.35, 0.11).lerp(Color(0.31, 0.45, 0.15), r.randf()), Vector2(0.35, 1.0))
		DANDELION:
			_rosette(base, r, DANDELION, r.randi_range(7, 13), Vector2(32.0, 70.0) * scale, Vector2(0.17, 0.23),
				Color(0.27, 0.42, 0.14).lerp(Color(0.34, 0.48, 0.16), r.randf()), Vector2(0.12, 0.55))
		CLOVER:
			_clover(base, r, scale, ground_at)


func commit() -> ArrayMesh:
	st.generate_normals()
	return st.commit()


## Leaves from one point: the outer (older) ones lower and longer, the inner ones short and upright.
func _rosette(base: Vector3, r: RandomNumberGenerator, kind: int, n: int, length: Vector2, width: Vector2, col: Color,
		rise: Vector2) -> void:
	var a0 := r.randf() * TAU
	for k in n:
		var age := 1.0 - float(k) / n                       # 1 the outermost
		var yaw := a0 + k * 2.39996 + r.randfn(0.0, 0.15)   # (leaves come round the stem at the golden angle)
		var l := lerpf(length.x, length.y, r.randf()) * lerpf(0.6, 1.0, age) * U
		var up := lerpf(rise.y, rise.x, age) + r.randfn(0.0, 0.08)
		var c := col.darkened(0.12 * age).lerp(Color(0.42, 0.5, 0.2), r.randf() * 0.15)
		leaf(base + Vector3(0, 0.05, 0), yaw, l, l * lerpf(width.x, width.y, r.randf()), up, up + r.randf_range(0.15, 0.55),
			r.randf_range(0.12, 0.32), r.randf_range(-0.35, 0.35), kind, r.randf(), c, 0.1)


## A patch of clover: leaves of three on long stalks from a creeping stem.
func _clover(base: Vector3, r: RandomNumberGenerator, scale: float, ground_at: Callable) -> void:
	var col := Color(0.2, 0.37, 0.14).lerp(Color(0.28, 0.45, 0.17), r.randf())
	for i in r.randi_range(6, 13):
		var off := Vector2(r.randfn(0.0, 9.0), r.randfn(0.0, 9.0)) * scale * U
		var foot: Vector3 = ground_at.call(Vector2(base.x + off.x, base.z + off.y))
		var h := r.randf_range(10.0, 26.0) * scale * U
		var lean := Vector3(r.randfn(0.0, 0.25), 1.0, r.randfn(0.0, 0.25)).normalized()
		var top := foot + lean * h
		_stalk(foot, top, 0.12, col.darkened(0.15))
		var yaw := r.randf() * TAU
		var size := r.randf_range(9.0, 15.0) * scale * U
		var sd := r.randf()
		for k in 3:
			leaf(top, yaw + k * TAU / 3.0 + r.randfn(0.0, 0.12), size, size * 0.46, r.randf_range(0.0, 0.3), r.randf_range(-0.15, 0.2),
				0.2, 0.0, CLOVER, sd, col, 0.35, 6, 4)


## One leaf strip from `base`, heading `yaw` (as Basis(UP, -yaw): along +x turned), `length` long, `half_w` to each side:
## it leaves at `rise` radians above the ground and bends down to `rise - droop` at the tip, its sides cupped up by
## `cup` of its half width and turned `twist` along it. `flex`: how far the wind moves its tip.
func leaf(base: Vector3, yaw: float, length: float, half_w: float, rise: float, droop: float, cup: float, twist: float,
		kind: int, sd: float, col: Color, flex: float, rows := 10, cols := 6) -> void:
	var b := Basis(Vector3.UP, -yaw)
	var p := Vector2.ZERO
	var first := _count
	for i in rows + 1:
		var v := float(i) / rows
		var a := rise - droop * v * v
		if i > 0:
			var am := rise - droop * pow((i - 0.5) / rows, 2.0)
			p += Vector2(cos(am), sin(am)) * length / rows
		var nrm := Vector2(-sin(a), cos(a))
		for j in cols + 1:
			var u := -1.0 + 2.0 * j / cols
			var cross := Vector2(u * half_w, cup * half_w * u * u).rotated(twist * v)
			var local := Vector3(p.x + nrm.x * cross.y, p.y + nrm.y * cross.y, cross.x)
			st.set_color(Color(col.r, col.g, col.b, v * v * flex))
			st.set_uv(Vector2(u, v))
			st.set_uv2(Vector2(kind, sd))
			st.add_vertex(base + b * local)
			_count += 1
	for i in rows:
		for j in cols:
			var a := first + i * (cols + 1) + j
			var c := a + cols + 1
			st.add_index(a)
			st.add_index(c)
			st.add_index(a + 1)
			st.add_index(a + 1)
			st.add_index(c)
			st.add_index(c + 1)


## A thin three-sided stalk from a to b.
func _stalk(a: Vector3, b: Vector3, radius: float, col: Color) -> void:
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3.RIGHT if absf(axis.x) < 0.9 else Vector3.FORWARD).normalized()
	var first := _count
	for e in 2:
		var at := a if e == 0 else b
		for k in 3:
			var d := side.rotated(axis, TAU * k / 3.0) * radius
			st.set_color(Color(col.r, col.g, col.b, 0.3 * e))
			st.set_uv(Vector2(0, e))
			st.set_uv2(Vector2(STALK, 0))
			st.add_vertex(at + d)
			_count += 1
	for k in 3:
		var k2 := (k + 1) % 3
		for idx in [first + k, first + 3 + k, first + k2, first + k2, first + 3 + k, first + 3 + k2]:
			st.add_index(idx)
