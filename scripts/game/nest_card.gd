extends RefCounted
## The colony's nest as the Home's tank shows it through the glass (the keeper, 2026-10-27: a tank with a colony should
## show that colony's nest): the side view of the real excavated nest - open space projected through the depth of the
## block, on the soil's layers, as the side panel draws it (hud_panel._refresh_nest_image) - written beside the save
## each time it is saved (slotN_nest.png) and read by the Home. Only an image: nothing in it is run, and one far bigger
## than ours is not read.

const MAX_BYTES := 512 * 1024


static func path(dir: String, slot: int) -> String:
	return "%s/slot%d_nest.png" % [dir, slot]


static func image(nest) -> Image:
	var h: int = nest.hy()
	var img := Image.create(nest.nx, h, false, Image.FORMAT_RGB8)
	var loam := Color(0.3, 0.2, 0.12)
	var clay := Color(0.55, 0.34, 0.2)
	var sand := Color(0.72, 0.59, 0.4)
	var hole := Color(0.07, 0.045, 0.03)
	for yy in h:
		var y: int = nest.y_lo + yy
		var depth: int = nest.ny - 1 - y
		var soil := loam.lerp(clay, clampf((depth - 11) / 6.0, 0.0, 1.0)).lerp(sand, clampf((depth - 37) / 8.0, 0.0, 1.0))
		for x in nest.nx:
			var open: int = nest.proj[yy * nest.nx + x]
			var tone := soil * (0.9 + 0.2 * float((x * 131 + y * 7) % 17) / 17.0)
			img.set_pixel(x, h - 1 - yy, tone if open == 0 else hole.lerp(tone, 0.2 / open))
	return img


static func write(dir: String, slot: int, nest) -> void:
	image(nest).save_png(path(dir, slot))


## The image for that slot, or null (none yet: saved before v0.11.49, or not a PNG of a sensible size).
static func read(dir: String, slot: int) -> ImageTexture:
	var p := path(dir, slot)
	if not FileAccess.file_exists(p):
		return null
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null or f.get_length() > MAX_BYTES:
		return null
	var img := Image.new()
	if img.load_png_from_buffer(f.get_buffer(f.get_length())) != OK or img.get_width() > 512 or img.get_height() > 1024:
		return null
	return ImageTexture.create_from_image(img)
