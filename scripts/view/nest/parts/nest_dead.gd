extends "res://scripts/view/nest/parts/nest_rest.gd"
## Nest view, layer 9 of 15 (split from parts/nest_bind.gd in v0.11.46): the dead in the nest - lying there until an
## undertaker carries one out, a body the living keep clear of - and the prey carried down to the larvae; the extra
## distance fields (the dig face, a body to fetch) and the --io counts the binding layer above keeps.

var io := {}                     # dev (--io): ants in and out of the nest as the nest view drew them, counted
var _xfields := {}                # more distance fields: -2 the dig face (nest_bind), _corpse_key(id) a body to fetch


func _field_of(key: int) -> Dictionary:
	return _fields.get(key, _xfields.get(key, {}))


# ---------------------------------------------------------------- the dead in the nest (v0.11.45)

## A nestmate that dies in the nest lies there on its back, legs curled, until an undertaker carries it out (the
## simulation counts it, corpses_inside, and sends one out with it - before, the body just vanished and the undertaker
## left empty-handed while outside it came out carrying one). Bodies no one comes for go after CORPSE_KEEP s.
const CORPSE_KEEP := 120.0
const CORPSE_CARRY := Transform3D(Basis(Vector3(0.9, 0, 0), Vector3(0, -0.9, 0), Vector3(0, 0, -0.9)), Vector3(2.3, 0.95, 0))      # (turned over, 0.9 big: as in the outworld)
var _corpses := []                # {"id", "xf", "cell", "t", "taken"}
var _corpse_n := 0
var _undertaker := {}             # worker id -> the body it goes for
var _corpse_mm: MultiMesh


func _corpse_key(id: int) -> int:
	return -10 - id


func _lay_corpse(m: Dictionary) -> void:
	if m.has("xf"):
		_corpses_add(m.xf)


func _corpses_add(xf: Transform3D) -> void:
	# on its back: turned over along its length, resting on its upper side
	var tr := Transform3D(xf.basis * Basis(Vector3.RIGHT, PI), xf.origin + xf.basis.y * 0.5)
	_corpse_n += 1
	_corpses.append({"id": _corpse_n, "xf": tr, "cell": Vector3i(xf.origin.round()), "t": _t, "taken": false})
	io.corpse_laid = int(io.get("corpse_laid", 0)) + 1


func _corpses_by_id(id: int) -> Dictionary:
	for c in _corpses:
		if c.id == id:
			return c
	return {}


## The nearest body no undertaker has come for yet, to a body at m (-1: none).
func _free_corpse(m: Dictionary) -> int:
	var best := -1
	var bd := INF
	for c in _corpses:
		if not c.taken:
			var d := Vector3(c.cell).distance_to(m.to)
			if d < bd:
				bd = d
				best = c.id
	return best


func _corpse_field(id: int) -> Dictionary:
	var key := _corpse_key(id)
	if not _xfields.has(key):
		var c := _corpses_by_id(id)
		var at: Vector3i = c.cell
		for k in 4:
			if _walkable(at):
				break
			at.y -= 1
		_xfields[key] = _field_from(at)
	return _xfields[key]


## An undertaker that has reached the body picks it up and goes on out with it.
func _pick_corpse(m: Dictionary) -> void:
	var id: int = m.fetch
	m.erase("fetch")
	_xfields.erase(_corpse_key(id))
	_corpses = _corpses.filter(func(c): return c.id != id)
	m.carry = true
	m.item = "corpse"
	m.goal = -1
	io.corpse_taken = int(io.get("corpse_taken", 0)) + 1


## The bodies lying in the nest and those being carried out (carried: the carriers' transforms), drawn with the ant
## model in its dead pose.
func _draw_corpses(carried: Array) -> void:
	for c in _corpses:
		if not c.taken and _t - float(c.t) > CORPSE_KEEP:
			io.corpse_expired = int(io.get("corpse_expired", 0)) + 1
	_corpses = _corpses.filter(func(c): return c.taken or _t - float(c.t) <= CORPSE_KEEP)
	if _corpses.is_empty() and carried.is_empty() and _corpse_mm == null:
		return
	if _corpse_mm == null:
		var mat: ShaderMaterial = _ant_shader_mat.duplicate()
		mat.set_shader_parameter("feet_on", false)
		_corpse_mm = _multimesh(_ant_meshes.lo, mat, true)
		_corpse_mm.use_custom_data = true
	var xs := []
	for c in _corpses:
		if _shown(c.xf):
			xs.append(c.xf)
	for tr in carried:
		xs.append(tr * CORPSE_CARRY)
	if not carried.is_empty():
		io.corpse_carried_frames = int(io.get("corpse_carried_frames", 0)) + 1
	_corpse_mm.instance_count = xs.size()
	var dead: Color = AntModel.body_linear(sim.sp["body_color"]).lerp(Color(0.05, 0.035, 0.025), 0.4)     # (a little duller than the living)
	for i in xs.size():
		_corpse_mm.set_instance_transform(i, xs[i])
		_corpse_mm.set_instance_color(i, dead)
		_corpse_mm.set_instance_custom_data(i, Color(0, 11, 0, 0))


## The bodies lying in the nest, as the nestmates' keeping apart sees bodies (xf, size and the head-thorax and gaster
## discs, d0 and d1): the living walk round them or over them, never through.
func _corpse_bodies() -> Array:
	var out := []
	for c in _corpses:
		if not c.has("body"):
			var x: Transform3D = c.xf
			var f: Vector3 = x.basis.x.normalized() * 0.7
			c.body = {"xf": x, "size": 1.0, "d0": x.origin + f, "d1": x.origin - f * 1.2, "corpse": true, "rest": 1, "role": "corpse", "act": 0}
		out.append(c.body)
	return out


var _prey_mm: MultiMesh

## The prey carried down to the larvae (carriers' transforms), a piece of the brown of the outworld's.
func _draw_prey(loads: Array) -> void:
	if _prey_mm == null:
		if loads.is_empty():
			return
		_prey_mm = _multimesh(_ellipsoid(0.75, 0.55), _mat_simple(Color(0.5, 0.33, 0.18), 0.7), false)
	_fill(_prey_mm, loads.map(func(tr): return tr * CARRY_OFFSET))
