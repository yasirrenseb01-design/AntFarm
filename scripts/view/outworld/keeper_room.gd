extends RefCounted
## Round a keeper's foraging box (the keeper, 2026-10-27: "the background should be where it stands in the room"): the
## Home's room, drawn round it in the outworld view - the desk's top under it (the first small tank and the bigger
## one stand on the desk) or a shelf's board with the wall just behind (the tanks on shelves), the room's cream
## walls, its plank floor and its ceiling. Built in metres under one node scaled to the view's units (1 unit = 1.5 mm),
## so the Home's own wood and wall colours carry over (view/home/home_kit.gd). The walls and the ceiling are faces
## seen only from inside, so a camera turned round behind one still sees the box through it; they cast no shadow
## (the view's sun shines through the ceiling). Only the view: nothing here touches the simulation.

const Kit := preload("res://scripts/view/home/home_kit.gd")
const M := 1.0 / 0.0015                 # units per metre
const ROOM := 4.0                       # the Home's room (home_kit.W), metres
const ROOM_H := 2.6
const DESK_SIZE := Vector3(1.5, 0.04, 0.72)
const DESK_H := 0.75                    # the desk's top above the floor
const SHELF_H := 1.1


## parent: the outworld view; w, d: the box (units); base: the desk's or the shelf's top under it (units, y);
## stand: "desk" or "shelf".
static func build(parent: Node3D, w: float, d: float, base: float, stand: String) -> void:
	var root := Node3D.new()
	root.scale = Vector3.ONE * M
	root.position = Vector3(w * 0.5, base, d * 0.5)
	parent.add_child(root)
	var bd := d / M
	var bw := w / M
	var back: float                       # the wall behind (z, metres from the box's middle)
	var floor_y: float
	if stand == "shelf":
		# a board a little wider and deeper than the box, on two brackets, against the wall
		var sd := bd + 0.08
		back = -sd * 0.5 - 0.005
		floor_y = -SHELF_H
		var board := Kit.wood(Color(0.5, 0.36, 0.22), Color(0.66, 0.5, 0.33), 9.0, 9.0, 55.0)
		_box(root, Vector3(bw + 0.3, 0.025, sd), Vector3(0, -0.0125, 0), board)
		var steel := Kit.flat(Color(0.18, 0.17, 0.16), 0.5, 0.6)
		for sx in [-1, 1]:
			var x: float = sx * (bw * 0.5 + 0.05)
			_box(root, Vector3(0.02, 0.18, 0.006), Vector3(x, -0.115, back + 0.003), steel)
			_box(root, Vector3(0.02, 0.006, sd * 0.85), Vector3(x, -0.028, back + sd * 0.425), steel)
	else:
		# the desk: its top, the box nearer its front edge, four legs down to the floor
		var zc := bd * 0.5 + 0.12 - DESK_SIZE.z * 0.5
		back = zc - DESK_SIZE.z * 0.5 - 0.02
		floor_y = -DESK_H
		var top := Kit.wood(Color(0.4, 0.25, 0.13), Color(0.58, 0.4, 0.23), 9.0, 9.0, 45.0)
		_box(root, DESK_SIZE, Vector3(0, -DESK_SIZE.y * 0.5, zc), top)
		var leg := Kit.wood(Color(0.36, 0.22, 0.12), Color(0.5, 0.33, 0.19), 9.0, 9.0, 45.0)
		var lh := DESK_H - DESK_SIZE.y
		for sx in [-1, 1]:
			for sz in [-1, 1]:
				_box(root, Vector3(0.05, lh, 0.05), Vector3(sx * (DESK_SIZE.x * 0.5 - 0.05), floor_y + lh * 0.5,
					zc + sz * (DESK_SIZE.z * 0.5 - 0.05)), leg)
	# the room: the floor, the walls (the one behind just there), the ceiling
	var floor_m := Kit.wood(Color(0.36, 0.21, 0.11), Color(0.56, 0.35, 0.19), 0.14, 1.3, 70.0)
	var wall := Kit.flat(Color(0.66, 0.58, 0.47), 0.92)       # (the Home's cream, a shade darker under this view's sun)
	var ceil_m := Kit.flat(Color(0.7, 0.66, 0.6), 0.95)
	var zm := back + ROOM * 0.5
	var ym := floor_y + ROOM_H * 0.5
	_face(root, PlaneMesh.FACE_Y, false, Vector2(ROOM, ROOM), Vector3(0, floor_y, zm), floor_m)
	_face(root, PlaneMesh.FACE_Y, true, Vector2(ROOM, ROOM), Vector3(0, floor_y + ROOM_H, zm), ceil_m)
	_face(root, PlaneMesh.FACE_Z, false, Vector2(ROOM, ROOM_H), Vector3(0, ym, back), wall)
	_face(root, PlaneMesh.FACE_Z, true, Vector2(ROOM, ROOM_H), Vector3(0, ym, back + ROOM), wall)
	_face(root, PlaneMesh.FACE_X, false, Vector2(ROOM, ROOM), Vector3(-ROOM * 0.5, ym, zm), wall)     # (square: past the
	_face(root, PlaneMesh.FACE_X, true, Vector2(ROOM, ROOM), Vector3(ROOM * 0.5, ym, zm), wall)       # floor and ceiling)
	# a skirting board along the wall behind
	var skirt := Kit.flat(Color(0.95, 0.92, 0.85), 0.7)
	_box(root, Vector3(ROOM, 0.08, 0.015), Vector3(0, floor_y + 0.04, back + 0.0075), skirt).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _box(root: Node3D, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = at
	root.add_child(mi)
	return mi


## A face seen from one side only (flip: the other side).
static func _face(root: Node3D, axis: int, flip: bool, size: Vector2, at: Vector3, mat: Material) -> void:
	var pm := PlaneMesh.new()
	pm.orientation = axis
	pm.flip_faces = flip
	pm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = mat
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
