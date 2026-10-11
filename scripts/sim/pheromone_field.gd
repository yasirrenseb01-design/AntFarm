extends RefCounted
## Pheromone grid with lazy evaporation.
## Instead of multiplying every cell each tick, a global log-decay clock advances and each
## cell's value is scaled by exp(clock - stamp) when read. Rain just advances the clock faster.

const MAX := 6.0

var w := 0
var h := 0
var cs := 5.0
var val := PackedFloat32Array()
var stamp := PackedFloat64Array()
var clock := 0.0


func _init(width: int, height: int, cell: float) -> void:
	w = width
	h = height
	cs = cell
	val.resize(w * h)
	val.fill(0.0)
	stamp.resize(w * h)
	stamp.fill(0.0)


func decay(log_factor: float) -> void:
	clock += log_factor


func index(x: float, y: float) -> int:
	if x < 0.0 or y < 0.0:
		return -1
	var cx := int(x / cs)
	var cy := int(y / cs)
	if cx >= w or cy >= h:
		return -1
	return cy * w + cx


func read_i(i: int) -> float:
	var v := val[i]
	if v <= 0.0:
		return 0.0
	return v * exp(clock - stamp[i])


func deposit(x: float, y: float, amount: float) -> void:
	var i := index(x, y)
	if i < 0:
		return
	val[i] = minf(MAX, read_i(i) + amount)
	stamp[i] = clock


func deposit_i(i: int, amount: float) -> void:
	var v := val[i]
	if v > 0.0:
		v *= exp(clock - stamp[i])
	val[i] = minf(MAX, v + amount)
	stamp[i] = clock


func clear_i(i: int) -> void:
	val[i] = 0.0


func clear_circle(center: Vector2, r: float) -> void:
	var x0 := maxi(0, int((center.x - r) / cs))
	var x1 := mini(w - 1, int((center.x + r) / cs))
	var y0 := maxi(0, int((center.y - r) / cs))
	var y1 := mini(h - 1, int((center.y + r) / cs))
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			if Vector2(cx * cs + cs * 0.5, cy * cs + cs * 0.5).distance_to(center) <= r:
				val[cy * w + cx] = 0.0


# ---------------------------------------------------------------- save / load

func to_dict() -> Dictionary:
	return {"val": val, "stamp": stamp, "clock": clock}


func from_dict(d: Dictionary) -> void:
	val = d.val
	stamp = d.stamp
	clock = d.clock
