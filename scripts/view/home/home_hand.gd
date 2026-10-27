extends Node3D
## The keeper's right hand in the Home, in 3D (the keeper, 2026-10-27): in the lower right of the view, in a knit
## sleeve. A grown-up's hand modelled in Blender (tools/blender/build_hand.py -> assets/models/hand/: relaxed and open,
## and pointing - the same points in two poses, blended here as a blend shape); until v0.11.53 it was built here from
## capsules and looked a mannequin's (the keeper). Relaxed while the view's middle is on nothing; pointing with the first
## finger while it is on something that can be clicked; a short reach forward at a click; it sways a little with each
## step. A child of the camera (game/home.gd); metres; -z is where the fingers point, +y the back of the hand, the
## wrist at the origin.

const AntModel := preload("res://scripts/view/common/ant_model3d.gd")
const DIR := "res://assets/models/hand/"
const REST := Vector3(0.17, -0.1, -0.2)          # the wrist, from the eye
const TURN := Vector3(0.32, 0.45, -0.3)           # its turn: tilted up a little, toward the middle, rolled out

var _mesh: MeshInstance3D
var _point := 0.0                        # 0 open .. 1 pointing (eased)
var _want_point := false
var _poke := 1.0                         # a click's reach, 0..1 through it
var _walk_t := 0.0


func _ready() -> void:
	position = REST
	rotation = TURN
	var open := AntModel.load_antmesh(DIR + "hand_open.antmesh")
	var pointing := AntModel.load_antmesh(DIR + "hand_point.antmesh")
	var skin := StandardMaterial3D.new()
	skin.vertex_color_use_as_albedo = true
	skin.vertex_color_is_srgb = true
	skin.roughness = 0.6
	skin.rim_enabled = true
	skin.rim = 0.3
	skin.rim_tint = 0.6
	if open != null and pointing != null:
		var a: Array = open.surface_get_arrays(0)
		var b: Array = pointing.surface_get_arrays(0)
		var shape := []
		shape.resize(Mesh.ARRAY_MAX)
		shape[Mesh.ARRAY_VERTEX] = b[Mesh.ARRAY_VERTEX]
		shape[Mesh.ARRAY_NORMAL] = b[Mesh.ARRAY_NORMAL]
		var m := ArrayMesh.new()
		m.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
		m.add_blend_shape("point")
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a, [shape])
		_mesh = MeshInstance3D.new()
		_mesh.mesh = m
		_mesh.material_override = skin
		_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_mesh)
	var sleeve := AntModel.load_antmesh(DIR + "sleeve.antmesh")
	if sleeve != null:
		var knit := StandardMaterial3D.new()
		knit.vertex_color_use_as_albedo = true
		knit.vertex_color_is_srgb = true
		knit.roughness = 0.95
		var s := MeshInstance3D.new()
		s.mesh = sleeve
		s.material_override = knit
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(s)


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
	position = REST + Vector3(-reach * 0.35, reach * 0.2, -reach) + sway
	if _mesh != null:
		_mesh.set_blend_shape_value(0, smoothstep(0.0, 1.0, _point))
