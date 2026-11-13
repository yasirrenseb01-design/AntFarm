extends RefCounted
## Jointed legs for the creatures (v0.12.33, docs/roadmap/PLAN_CREATURES.md): the joints of a model's legs at rest come
## from the .json its Blender script writes beside the .antmesh (tools/blender/props/<kind>.py) and go to its shader
## (shaders/creatures/leg_ik.gdshaderinc) - written once, there. And the gait such a creature is drawn at: by the ground
## it really covers, one turn for each `stride`, so a foot set down stays where it is while the body goes over it.

const U := 1.0 / 3.0            # simulation px -> units (outworld_scene.U)
const LEGS_MAX := 8             # (leg_ik.gdshaderinc; a model with more legs says so in its shader: the centipede's 30)
const HELD_TURNS := 1.6         # held down by ants its legs work on the spot: turns of the gait a second


## The joints of assets/models/<name>.json given to the creature's material; cv["stride"] set (model units a turn of
## the gait). A model without one is left as it is (its shader moves the legs its own way).
static func setup(cv: Dictionary, name: String) -> void:
	var path := "res://assets/models/%s.json" % name
	if not FileAccess.file_exists(path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary or not d.get("hips") is Array:
		return
	var mat: ShaderMaterial = cv.mat
	for key in ["hips", "knees", "ankles"]:
		var pts := PackedVector3Array()
		var rows: Array = d.get(key, [])
		pts.resize(maxi(LEGS_MAX, rows.size()))
		for i in rows.size():
			pts[i] = Vector3(rows[i][0], rows[i][1], rows[i][2])
		mat.set_shader_parameter(key.trim_suffix("s"), pts)
	var bends := PackedVector2Array()
	var rows: Array = d.get("bends", [])
	bends.resize(maxi(LEGS_MAX, rows.size()))
	for i in rows.size():
		bends[i] = Vector2(rows[i][0], rows[i][1])
	mat.set_shader_parameter("bend", bends)
	cv["stride"] = float(d.get("stride", 3.0))
	mat.set_shader_parameter("stride", cv.stride)
	mat.set_shader_parameter("leg_lift", float(d.get("lift", 0.55)))
	mat.set_shader_parameter("knee_up", float(d.get("knee_up", 0.0)))      # (how the knee is bent: leg_ik.gdshaderinc)


## The gait phase a creature is drawn at this frame. v: its smoothing state (kept there as "gaitd"); s: the simulation's;
## moved_px: how far it was drawn on this frame.
static func gait(cv: Dictionary, v: Dictionary, s: Dictionary, moved_px: float, delta: float) -> float:
	if not cv.has("stride"):
		return fmod(float(s.phase) * float(cv.gait), TAU * 64.0)
	var turn := moved_px * U / (float(cv.scale) * float(cv.stride))
	if int(s.get("held", 0)) > 0:
		turn = maxf(turn, HELD_TURNS * delta)
	# (no more than max_hz steps a second: the centipede, the fastest, stepped 6.4 a second at 0.5x - its 30 legs moved
	# so far each frame they flickered, "like a low frame rate" (v0.13.11, the keeper); faster, its feet slip a little)
	turn = minf(turn, float(cv.get("max_hz", 99.0)) * delta)
	v["gaitd"] = fmod(float(v.get("gaitd", 0.0)) + turn * TAU, TAU * 64.0)
	return v.gaitd
