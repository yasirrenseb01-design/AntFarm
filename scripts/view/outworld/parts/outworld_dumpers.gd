extends "res://scripts/view/outworld/parts/outworld_creatures.gd"
## Outworld view, after the foragers (new in v0.11.45): the diggers bringing the soil out. The simulation's diggers
## carry each pellet up the tunnels and drop it at the entrance (nest_volume: excavated += 1) without ever being outside,
## so out here no ant was ever seen with soil while the crater round the entrance grew by itself. Now each pellet brought
## up is carried out by an ant drawn here: out of the entrance to the crater's ring, set down, and back in. Only drawn -
## the simulation is not changed (in the nest view the digger turns back at the entrance as before).
## [Lasius niger workers carry excavated soil out and drop it round the entrance, building the crater: field and keepers'
## observations; how far out (here 4.5-10 mm, the crater's ring) is chosen to match the crater drawn.]

const DUMP_MAX := 8               # drawn at once (more pellets than that a moment - fast-forward - go uncarried)
const DUMP_DROP := 0.6            # seconds (at 1x) setting the pellet down
var _dumpers: Array = []          # {"pos", "to", "phase" (0 out, 1 setting down, 2 back in), "t", "ang", "anim", "gait", "size", "vact", "mv"}
var _dug_seen := -1


func _update_ants(delta: float) -> void:
	super(delta)
	_update_dumpers(delta)


func _update_dumpers(delta: float) -> void:
	var ex: int = sim.nest.excavated
	var fresh := ex - _dug_seen if _dug_seen >= 0 else 0
	_dug_seen = ex
	if fresh > 3 * DUMP_MAX:
		fresh = 0                     # (the outworld was not being drawn: those were carried out unseen)
	for i in mini(fresh, DUMP_MAX - _dumpers.size()):
		var a := randf() * TAU
		var r := 9.0 + absf(randfn(0.0, 1.0)) * 7.0          # px: where the crater's pellets lie (ground_data)
		_dumpers.append({"pos": sim.nest_pos, "to": sim.nest_pos + Vector2.from_angle(a) * r, "phase": 0, "t": 0.0,
			"ang": a, "anim": randf() * 50.0, "gait": randf() * TAU, "size": randf_range(0.85, 1.05), "vact": Vector3(-1, 0, 0), "mv": 0.0})
	var adt := delta * minf(speed, 1.0) if speed > 0 else 0.0
	var pace := (0.35 + 0.65 * float(sim.activity))
	var px_s: float = float(sim.sp["walk_speed"]) * pace * 60.0 * speed     # px a second
	var body: Color = AntModel.body_linear(sim.sp["body_color"])
	var xs := []
	var cus := []
	var pellets := []
	var done := []
	for d in _dumpers:
		var goal: Vector2 = d.to if d.phase == 0 else sim.nest_pos
		var step := Vector2.ZERO
		if d.phase == 1:
			d.t += delta * speed
			if d.t >= DUMP_DROP:
				d.phase = 2
		else:
			var left: Vector2 = goal - d.pos
			var go := minf(left.length(), px_s * delta)
			if left.length() > 0.01:
				step = left.normalized() * go
				d.ang = lerp_angle(d.ang, left.angle(), 1.0 - exp(-10.0 * delta))
			d.pos += step
			if left.length() <= 0.5:
				if d.phase == 0:
					d.phase = 1
					d.t = 0.0
				else:
					done.append(d)
					continue
		d.anim += adt
		d.mv = lerpf(d.mv, 1.0 if step.length_squared() > 0.0 else 0.0, minf(1.0, 10.0 * delta))
		var p: Vector2 = d.pos * U
		var up := ground_top_n(p.x, p.y)
		var f := Vector3(cos(d.ang), 0, sin(d.ang))
		f = (f - up * f.dot(up)).normalized()
		var s: float = ANT_SCALE * float(d.size)
		var stride := AntModel.stride_scale(pace, d.phase == 0)
		d.gait = fmod(d.gait + step.length() * U / (AntModel.stride_len(stride) * s) * TAU, TAU * 64.0)
		var tr := Transform3D(Basis(f, up, f.cross(up)).scaled(Vector3.ONE * s), Vector3(p.x, ground_top(p.x, p.y), p.y))
		var act := 8 if d.phase == 0 else (2 if d.phase == 1 else 0)     # carrying, head down setting it down, walking back
		d.vact = AntModel.act_step(d.vact, act, d.anim)
		xs.append(tr)
		cus.append(Color(d.gait, AntModel.act_y(d.vact, d.anim), fmod(d.anim, 600.0), AntModel.gait_w(d.mv, stride)))
		if d.phase == 0:
			pellets.append(tr * Transform3D(Basis.from_scale(Vector3.ONE * 0.45), CARRY_OFFSET.origin))
		elif d.phase == 1:
			pellets.append(tr * Transform3D(Basis.from_scale(Vector3.ONE * 0.45), Vector3(1.5, 0.2, 0.0)))     # on the ground at its head
	for d in done:
		_dumpers.erase(d)
	if xs.is_empty():
		return
	var n := _ant_mm.instance_count
	_ant_mm.instance_count = n + xs.size()
	for i in xs.size():
		_ant_mm.set_instance_transform(n + i, xs[i])
		_ant_mm.set_instance_color(n + i, body)
		_ant_mm.set_instance_custom_data(n + i, cus[i])
	var k := _soil_mm.instance_count
	_soil_mm.instance_count = k + pellets.size()
	for i in pellets.size():
		_soil_mm.set_instance_transform(k + i, pellets[i])
