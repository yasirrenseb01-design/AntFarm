extends RefCounted
## How high the litter lying on the outworld floor stands (pebbles, moss, twigs, fallen leaves): a grid of
## heights above the ground, so the ants walk up over them (body raised and tilted, feet set on the surface)
## instead of through them. Built once from the scenery layout; also handed to the ant shader as a texture.
## The simulation does not know about litter (it neither blocks nor slows the foragers); small single stones are
## climbed (sim rock cells = 2, slower) and stamped here too (outworld_props _sync_rocks).

const CELL := 0.5                 # grid spacing, outworld units
var w := 0
var h := 0
var size := Vector2.ZERO          # extent in outworld units
var top := PackedFloat32Array()   # height above the ground per cell
var _litter := PackedFloat32Array()   # the scenery alone (stones come and go: stamped again over it)


func setup(extent: Vector2) -> void:
	size = extent
	w = int(ceil(extent.x / CELL)) + 1
	h = int(ceil(extent.y / CELL)) + 1
	top.resize(w * h)
	top.fill(0.0)


## Raise the cells inside a shape to at least `height_at(local)` (local = offset from `centre` turned into the
## shape's own frame by `ang`); `reach` bounds the shape.
func stamp(centre: Vector2, ang: float, reach: float, height_at: Callable) -> void:
	var x0 := maxi(0, int((centre.x - reach) / CELL))
	var x1 := mini(w - 1, int((centre.x + reach) / CELL) + 1)
	var z0 := maxi(0, int((centre.y - reach) / CELL))
	var z1 := mini(h - 1, int((centre.y + reach) / CELL) + 1)
	var c := cos(ang)
	var s := sin(ang)
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var d := Vector2(x * CELL, z * CELL) - centre
			var local := Vector2(d.x * c + d.y * s, -d.x * s + d.y * c)
			var v: float = height_at.call(local)
			if v > 0.0:
				var i := z * w + x
				top[i] = maxf(top[i], v)


## A pebble or a moss cushion: an ellipsoid cap with half-axes r (in its frame) and this height.
func stamp_cap(centre: Vector2, ang: float, r: Vector2, height: float) -> void:
	stamp(centre, ang, maxf(r.x, r.y), func(p: Vector2) -> float:
		var q := 1.0 - (p.x / r.x) * (p.x / r.x) - (p.y / r.y) * (p.y / r.y)
		return height * sqrt(q) if q > 0.0 else 0.0)


## A twig: a round stick along its frame's x, `length` long, of this radius, its axis this high.
func stamp_twig(centre: Vector2, ang: float, length: float, radius: float, axis_y: float) -> void:
	stamp(centre, ang, length * 0.5 + radius, func(p: Vector2) -> float:
		if absf(p.x) > length * 0.5:
			return 0.0
		var q := radius * radius - p.y * p.y
		return axis_y + sqrt(q) if q > 0.0 else 0.0)


## A fallen leaf (mesh_kit leaf(): curled edges, the tip lifted).
func stamp_leaf(centre: Vector2, ang: float, length: float, width: float, curl: float, lift: float) -> void:
	stamp(centre, ang, length * 0.5 + width, func(p: Vector2) -> float:
		var t := p.x / length + 0.5
		if t < 0.0 or t > 1.0:
			return 0.0
		var half := sin(t * PI) * width * (1.0 - 0.25 * t)
		if absf(p.y) > half:
			return 0.0
		return lift + 0.18 + p.y * p.y / maxf(0.1, width) * (0.35 + curl) + maxf(0.0, p.x / length) * 0.6)


## The scenery is all stamped: keep it, so stones can be stamped again over it when they change.
func keep_litter() -> void:
	_litter = top.duplicate()


## Back to the scenery alone (before the climbable stones are stamped again).
func reset_to_litter() -> void:
	if not _litter.is_empty():
		top = _litter.duplicate()


## A small stone the ants climb over (mesh_kit_base rock(): a dome of this height, base radius r, set 0.6 into the
## ground; its bumps are left out).
func stamp_rock(centre: Vector2, r: float, height: float) -> void:
	stamp(centre, 0.0, r, func(p: Vector2) -> float:
		var d := p.length() / r
		if d >= 1.0:
			return 0.0
		var phi := acos(pow(d, 1.0 / 0.65))
		return maxf(0.0, sin(phi) * height - 0.6))


## Height above the ground at (x, z), outworld units (bilinear between cells).
func at(x: float, z: float) -> float:
	var fx := clampf(x / CELL, 0.0, w - 1.001)
	var fz := clampf(z / CELL, 0.0, h - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * w + ix
	return lerpf(lerpf(top[i], top[i + 1], tx), lerpf(top[i + w], top[i + w + 1], tx), tz)


## The grid as a texture for the ant shader (ground_mode 2: feet set down on the litter too).
func texture() -> ImageTexture:
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RF, top.to_byte_array())
	return ImageTexture.create_from_image(img)
