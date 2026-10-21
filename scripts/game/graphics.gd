extends RefCounted
## Graphics quality (PART EA-R R7): low / medium / high and a frame-rate cap, chosen in the settings; the first time
## from the graphics card (an Intel integrated one: low; NVIDIA or AMD: high). main.gd applies it at the start and when
## the settings change; while the window is not in use the game draws less (main._notification / _process).
##   low     no shadows, no glow, the 3D drawn at 75% of the window (scaled up)
##   medium  shadows and glow, full size
##   high    as medium, 2x MSAA and finer shadows
## Desktop mode keeps its own frame rate (30) and puts this one back when it is done.

const LEVELS := ["low", "medium", "high"]
const FPS_CAPS := [30, 60, 0]           # (0: as fast as the screen shows them, vsync)
const FPS_IDLE := 30                    # the window not in use (another window in front)
const FPS_MINIMIZED := 5


## The level for this machine's graphics card, the first time the game starts.
static func auto_level() -> String:
	var who := (RenderingServer.get_video_adapter_vendor() + " " + RenderingServer.get_video_adapter_name()).to_lower()
	if who.contains("nvidia") or who.contains("geforce") or who.contains("radeon") or who.contains("amd"):
		return "high"
	if who.contains("intel"):
		return "low"
	return "medium"


## Applies a level and a frame-rate cap to the game's window and every 3D view under `root`.
static func apply(root: Node, level: String, fps_cap: int) -> void:
	var vp := root.get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = 0.75 if level == "low" else 1.0
	vp.msaa_3d = Viewport.MSAA_2X if level == "high" else Viewport.MSAA_DISABLED
	RenderingServer.directional_shadow_atlas_set_size(4096 if level == "high" else 2048, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
		RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM if level == "high" else RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	_walk(root, level)
	Engine.max_fps = fps_cap


static func _walk(n: Node, level: String) -> void:
	for c in n.get_children():
		if c is DirectionalLight3D:
			c.shadow_enabled = level != "low"
		elif c is Camera3D and c.environment != null:
			c.environment.glow_enabled = level != "low"
		elif c is SubViewport:
			continue                         # (the species page's turntable keeps its own look)
		_walk(c, level)
