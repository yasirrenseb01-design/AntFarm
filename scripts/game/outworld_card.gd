extends RefCounted
## The colony's foraging box as the Home's tank shows it from above (the keeper, 2026-10-27: "the tanks on the desk -
## can they show their outworld too, roughly, no ants walking"): a still picture of the real box seen straight down,
## its stones, litter, plants and the crater, taken by a camera of its own in the outworld view's world when the colony
## is saved and written beside the save (slotN_outworld.png), read by the Home (view/home/home_kit._tank) onto the top
## of the tank's soil. As it is lit at that moment (a colony saved at night shows a dark box), the ants there in it,
## still. Only an image: nothing in it is run, and one bigger than ours is not read.

const MAX_BYTES := 1024 * 1024
const W := 512


static func path(dir: String, slot: int) -> String:
	return "%s/slot%d_outworld.png" % [dir, slot]


## Its camera, set up once with the colony's view (a camera made just before the picture is taken is drawn from where
## it was made: its place reaches the renderer only at the end of the frame); outworld: view/outworld/outworld_view.gd.
static func prepare(outworld) -> void:
	var sim = outworld.sim
	var w: float = sim.WORLD.x * outworld.U
	var d: float = sim.WORLD.y * outworld.U
	var vp := SubViewport.new()
	vp.name = "OutworldCard"
	vp.size = Vector2i(W, int(W * d / w))
	vp.world_3d = outworld.get_viewport().world_3d
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.msaa_3d = Viewport.MSAA_2X
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = d                          # (the box's depth fills the picture's height)
	cam.near = 1.0
	cam.far = 400.0
	cam.position = Vector3(w * 0.5, float(outworld.wall_h) - 4.0, d * 0.5)
	cam.rotation = Vector3(-PI * 0.5, 0.0, 0.0)          # straight down, +x to the right, -z up the picture
	vp.add_child(cam)
	outworld.add_child(vp)
	cam.current = true


## Takes the picture there and then (a save just before the game quits or another colony loads is not lost) and writes
## it.
static func write(dir: String, slot: int, outworld) -> void:
	if outworld == null or not is_instance_valid(outworld) or not outworld.has_node("OutworldCard"):
		return
	if DisplayServer.get_name() == "headless":
		return                            # (no renderer: nothing to draw - tests, the self-test)
	var vp: SubViewport = outworld.get_node("OutworldCard")
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var gm: ShaderMaterial = outworld._ground_mat
	gm.set_shader_parameter("pher_on", 0.0)                      # (the scent trails left out)
	RenderingServer.force_draw(false)
	gm.set_shader_parameter("pher_on", 1.0 if outworld.ground.show_pheromones else 0.0)
	var img := vp.get_texture().get_image()
	if img != null and not img.is_empty():
		img.convert(Image.FORMAT_RGB8)
		img.save_png(path(dir, slot))


## The picture for that slot, or null (none yet, or not a PNG of a sensible size).
static func read(dir: String, slot: int) -> ImageTexture:
	var p := path(dir, slot)
	if not FileAccess.file_exists(p):
		return null
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null or f.get_length() > MAX_BYTES:
		return null
	var img := Image.new()
	if img.load_png_from_buffer(f.get_buffer(f.get_length())) != OK or img.get_width() > 1024 or img.get_height() > 1024:
		return null
	return ImageTexture.create_from_image(img)
