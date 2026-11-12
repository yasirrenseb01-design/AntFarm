extends Window
## The keeper's album of ant plates (the keeper, 2026-11-12: "a collector's book of drawings - a colony of this species
## that reaches its count gets the plate"): for each species, plates won by having that many workers at once in any of
## the keeper's colonies - Lasius niger: plate IIa (the queen and the brood) at 50 workers, IIb (the workers) at 200.
## Won for good (kept in the settings, "album": {species id: [plate ids]}); one not yet won shows faint, with what wins it.
## The plates are the keeper's own pictures (reference/album/, cut by tools/ui/make_album.py). Opened from the queen's
## sketch at the top of the colony bar.

const Paper := preload("res://scripts/view/ui/paper.gd")

## species id -> its plates: [id, picture, caption key, workers that win it]
const PLATES := {
	"lasius_niger": [
		["a", "res://assets/ui/album/lasius_niger_a.webp", "album_plate_a", 50],
		["b", "res://assets/ui/album/lasius_niger_b.webp", "album_plate_b", 200],
	],
}


## The plates of a species won with `workers` at once that `have` (the ids already won) lacks.
static func newly_won(species: String, workers: int, have: Array) -> Array:
	var out := []
	for p in PLATES.get(species, []):
		if workers >= int(p[3]) and not have.has(p[0]):
			out.append(p[0])
	return out


static func caption_of(species: String, id: String) -> String:
	for p in PLATES.get(species, []):
		if p[0] == id:
			return p[2]
	return ""


func setup(h, species: String, won: Array) -> void:
	title = tr("album_title") % tr(h.sim.sp["name_th"])
	theme = h._colonies.theme
	transient = true
	exclusive = true
	unresizable = true
	wrap_controls = true
	close_requested.connect(queue_free)
	var body := PanelContainer.new()
	body.add_theme_stylebox_override("panel", Paper.page(22, 18))
	body.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(body)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	body.add_child(col)
	var plates: Array = PLATES.get(species, [])
	var count := 0
	for p in plates:
		count += 1 if won.has(p[0]) else 0
	col.add_child(h._label(tr("album_count") % [count, plates.size()], 14, Paper.PENCIL))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	col.add_child(row)
	for p in plates:
		var have: bool = won.has(p[0])
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 6)
		row.add_child(cell)
		var frame := Control.new()
		frame.custom_minimum_size = Vector2(444, 304)
		cell.add_child(frame)
		var pic := TextureRect.new()
		pic.texture = load(p[1])
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.set_anchors_preset(Control.PRESET_FULL_RECT)
		# not won: a faint ghost of it on the page, the count that wins it over it
		pic.modulate = Color.WHITE if have else Color(0.55, 0.5, 0.42, 0.22)
		frame.add_child(pic)
		if not have:
			var mid := CenterContainer.new()
			mid.set_anchors_preset(Control.PRESET_FULL_RECT)
			frame.add_child(mid)
			var lock: Label = h._label(tr("album_locked") % int(p[3]), 16, Paper.INK)
			lock.add_theme_stylebox_override("normal", Paper.page(16, 8))       # (a slip of paper over the ghost)
			mid.add_child(lock)
		var cap: Label = h._label(tr(p[2]), 13, Paper.INK if have else Paper.PENCIL)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cap.custom_minimum_size.x = 444
		cell.add_child(cap)
	var note: Label = h._label(tr("album_note"), 12, Paper.PENCIL)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 904
	col.add_child(note)
