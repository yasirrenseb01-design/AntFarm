extends RefCounted
## Round a keeper's foraging box: the Home's own room (the keeper, 2026-10-27: "inside a colony, can I see the room as
## in the Home - the other tanks on the desk as they are there"), built by view/home/home_room.gd and set so that this
## colony's tank in it is where the game's box is - its desk or its shelf, the other tanks, the window, the lamps; the
## tank itself not drawn (the box is). The room is in metres under one node scaled to the view's units (1 unit =
## 1.5 mm, tank_spec.gd) and turned with its tank (a tank on a side wall's shelf: the room turns round the box). Its
## lights follow the game's hour, not the computer's clock (the keeper: the room as the ants live it); they are moved out
## from under the scaled node (lights do not scale), their reach multiplied. Only the view: nothing here touches the
## simulation.

const HomeRoom := preload("res://scripts/view/home/home_room.gd")
const Spec := preload("res://scripts/view/common/tank_spec.gd")
const Store := preload("res://scripts/game/save_store.gd")
const M := 1.0 / Spec.VOXEL             # units per metre


## view: the outworld view; info: {"places": home_store.places(), "shelves": [...], "slot": this colony's} - or {} for a
## colony with no Home (a test, the demo): it is put on the desk by itself; big: the bigger box; soil_bottom: the box's
## floor (units, y); env: the view's environment. Returns the room (the game's hour: room.set_hour).
static func build(view: Node3D, info: Dictionary, big: bool, soil_bottom: float, env: Environment):
	var slot := int(info.get("slot", 0))
	var places: Array = info.get("places", [])
	if not places.any(func(p): return int(p.slot) == slot):
		places = [{"slot": slot, "number": 1, "big": big, "farm": false, "shelf": -1, "spot": 0}]
	var room = HomeRoom.new()
	room.lamp_on = bool(info.get("lamp", true))
	view.add_child(room)
	# (this colony in the fridge or not as it is now: the keeper may have just put it in - v0.11.69)
	var cold := int(bool(info.fridge)) if info.has("fridge") else -1
	room.build(places, info.get("shelves", []), func(s): return Store.exists(s) or s == slot, 12.0, env, slot, cold)
	room.set_meta("fridge", info.get("fridge", null))
	var t: Node3D = room.tank_nodes.get(slot)
	var at := Transform3D()
	if t != null:
		# (an ant farm stands where a tank would; it has no box of its own: a small tank's)
		var f := Spec.floor_of(big)
		var inside: Vector3 = t.get_meta("inside", Vector3(-f.x * 0.5, Spec.GLASS, -f.y * 0.5))
		var g := t.global_transform
		at = Transform3D(g.basis.orthonormalized(), g * inside)
	room.transform = Transform3D(Basis.from_scale(Vector3.ONE * M), Vector3(0, soil_bottom, 0)) * at.affine_inverse()
	var to_room: Transform3D = room.transform.affine_inverse()
	for m in room._views + room._ao_mats:
		m.set_shader_parameter("to_room", Projection(to_room))
	# the lights out from under the scale
	room.fridge_light.omni_range *= M
	room.fridge_light.omni_attenuation = 0.0
	room.fridge_light.light_energy *= 0.4
	for l in [room._sun, room._moon, room._lamp, room._spot, room.fridge_light]:
		var gt: Transform3D = l.global_transform
		l.get_parent().remove_child(l)
		view.add_child(l)
		l.global_transform = Transform3D(gt.basis.orthonormalized(), gt.origin)
	room._lamp.omni_range *= M
	room._spot.spot_range *= M
	# (no fall-off with distance: at this scale distance^-attenuation runs out of precision and the light stopped dead in
	# a sharp circle on every wall - the keeper, 2026-10-27; the range's own soft edge does it, the energy set to what
	# the lamp gives at a usual distance in the Home)
	room.lamp_gain = pow(1.6, -room._lamp.omni_attenuation)
	room.spot_gain = pow(0.7, -room._spot.spot_attenuation)
	room._lamp.omni_attenuation = 0.0
	room._spot.spot_attenuation = 0.0
	room._lamp.omni_range = 4.2 * M
	# (their shadows, tuned in metres, streak at this scale: none - the sun's and the moon's stay)
	room._lamp.shadow_enabled = false
	room._spot.shadow_enabled = false
	room.set_meta("to_room", to_room)
	return room
