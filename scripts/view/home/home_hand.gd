extends Node3D
## The keeper's right hand in the Home, in 3D (the keeper, 2026-10-27): in the lower right of the view, a sleeve's cuff,
## the palm, four fingers of three joints and a thumb of two. Relaxed and a little open while the view's middle is on
## nothing; pointing with the first finger, the others curled in, while it is on something that can be clicked; a short
## reach forward at a click; it sways a little with each step. Built from capsules (no model file). A child of the
## camera (game/home.gd); metres; -z is where the fingers point, +y the back of the hand.

const SKIN := Color(0.93, 0.74, 0.6)
const CUFF := Color(0.9, 0.87, 0.78)
# per finger: [knuckle x, joint lengths, radius] - the first finger by the thumb (-x: a right hand, palm down)
const FINGERS := [[-0.029, [0.045, 0.027, 0.021], 0.0098], [-0.0095, [0.05, 0.03, 0.022], 0.0102],
	[0.0095, [0.047, 0.028, 0.021], 0.0097], [0.028, [0.037, 0.023, 0.018], 0.0086]]
const OPEN := [0.18, 0.22, 0.14]          # radians each joint bends (down, toward the palm)
const CURLED := [1.45, 1.55, 1.05]
const POINT_CURL := [0.06, 0.04, 0.03]
const THUMB_OPEN := [0.25, 0.15]
const THUMB_TUCK := [0.75, 0.6]
const REST := Vector3(0.165, -0.175, -0.33)     # where it is held, from the eye

var _joints: Array = []                  # per finger: the three joint pivots
var _thumb: Array = []
var _point := 0.0                        # 0 open .. 1 pointing (eased)
var _want_point := false
var _poke := 1.0                         # a click's reach, 0..1 through it
var _walk_t := 0.0


func _ready() -> void:
	position = REST
	rotation = Vector3(deg_to_rad(8.0), deg_to_rad(18.0), deg_to_rad(-12.0))
	var skin := StandardMaterial3D.new()
	skin.albedo_color = SKIN
	skin.roughness = 0.62
	skin.rim_enabled = true
	skin.rim = 0.25
	var cuff := StandardMaterial3D.new()
	cuff.albedo_color = CUFF
	cuff.roughness = 0.9
	# the palm: a flattened rounded block
	var palm := MeshInstance3D.new()
	var pm := SphereMesh.new()
	pm.radius = 0.5
	pm.height = 1.0
	palm.mesh = pm
	palm.scale = Vector3(0.088, 0.03, 0.095)
	palm.material_override = skin
	add_child(palm)
	# the wrist and forearm, going back out of view, and the cuff
	_capsule(self, 0.026, 0.22, Vector3(0.003, -0.004, 0.15), skin, Vector3(PI * 0.5, 0, 0))
	var c := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.037
	cm.bottom_radius = 0.039
	cm.height = 0.07
	c.mesh = cm
	c.material_override = cuff
	c.rotation.x = PI * 0.5
	c.position = Vector3(0.003, -0.004, 0.21)
	add_child(c)
	# the fingers: a pivot at each joint, the bone along -z from it
	for f in FINGERS:
		var lens: Array = f[1]
		var r: float = f[2]
		var at := Node3D.new()
		at.position = Vector3(float(f[0]), 0.002, -0.043)
		add_child(at)
		var chain := []
		var parent: Node3D = at
		for k in 3:
			var j := Node3D.new()
			parent.add_child(j)
			_capsule(j, r * (1.0 - k * 0.08), float(lens[k]), Vector3(0, 0, -float(lens[k]) * 0.5), skin, Vector3(PI * 0.5, 0, 0))
			chain.append(j)
			var next := Node3D.new()
			next.position = Vector3(0, 0, -float(lens[k]))
			j.add_child(next)
			parent = next
		_joints.append(chain)
	# the thumb, from the palm's inner side, turned out and forward
	var tb := Node3D.new()
	tb.position = Vector3(-0.04, -0.008, 0.012)
	tb.rotation = Vector3(0.0, deg_to_rad(38.0), deg_to_rad(-25.0))
	add_child(tb)
	var tp: Node3D = tb
	for k in 2:
		var j := Node3D.new()
		tp.add_child(j)
		var l := 0.038 if k == 0 else 0.03
		_capsule(j, 0.0115 - k * 0.001, l, Vector3(0, 0, -l * 0.5), skin, Vector3(PI * 0.5, 0, 0))
		_thumb.append(j)
		var nx := Node3D.new()
		nx.position = Vector3(0, 0, -l)
		j.add_child(nx)
		tp = nx
	_pose()


func _capsule(parent: Node3D, r: float, length: float, at: Vector3, mat: Material, rot: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = length + r * 2.0
	cm.radial_segments = 12
	cm.rings = 4
	mi.mesh = cm
	mi.material_override = mat
	mi.position = at
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## On something that can be clicked (true: pointing) or not.
func point(on: bool) -> void:
	_want_point = on


## A click: a short reach forward.
func poke() -> void:
	_poke = 0.0


## walking: whether the keeper is walking (the hand sways with the steps).
func tick(delta: float, walking: bool) -> void:
	_point = move_toward(_point, 1.0 if _want_point else 0.0, delta * 6.0)
	_poke = minf(1.0, _poke + delta / 0.28)
	if walking:
		_walk_t += delta
	var reach := sin(_poke * PI) * 0.06
	var sway := Vector3(sin(_walk_t * 7.0) * 0.006, absf(cos(_walk_t * 7.0)) * 0.007 if walking else 0.0, 0.0)
	position = REST + Vector3(-reach * 0.25, reach * 0.15, -reach) + sway
	_pose()


func _pose() -> void:
	for i in _joints.size():
		var chain: Array = _joints[i]
		var to: Array = POINT_CURL if i == 0 else CURLED
		for k in 3:
			(chain[k] as Node3D).rotation.x = -lerpf(float(OPEN[k]) + i * 0.04, float(to[k]), _point)
	for k in 2:
		(_thumb[k] as Node3D).rotation.x = -lerpf(float(THUMB_OPEN[k]), float(THUMB_TUCK[k]), _point)
