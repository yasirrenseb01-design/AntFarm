extends "res://scripts/view/ui/parts/hud_controls.gd"
## HUD, layer 6 of 7: the side panel (colony readout, live nest cross-section, journal; the Statistics tab).

const StatsChart := preload("res://scripts/view/ui/stats_chart.gd")

var _stats                      # ui/stats_chart.gd: the Statistics tab
var _side_tabs: Array = []      # its two tab buttons: the status, Statistics


## Shows the Statistics tab (dev: --stats-tab) or the status.
func show_side_tab(stats: bool) -> void:
	_side_tabs[1 if stats else 0].button_pressed = true
	_side_tabs[1 if stats else 0].pressed.emit()


func _build_panel(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -PANEL_W
	panel.offset_right = -12
	panel.offset_top = 22                          # (room above for the clip's ring)
	panel.offset_bottom = -12
	panel.add_theme_stylebox_override("panel", Desk.ClipboardBox.new(20, 38, 16))     # (a clipboard: the keeper, 2026-11-12)
	root.add_child(panel)
	_side = panel
	var whole := VBoxContainer.new()
	whole.add_theme_constant_override("separation", 10)
	panel.add_child(whole)
	# two tabs (the keeper, 2026-11-03): the colony's status - its readout, the nest's cross-section and the journal -
	# and Statistics, the day-by-day record plotted as the keeper sets it (ui/stats_chart.gd; the population chart was
	# in the status until v0.11.77)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	whole.add_child(tabs)
	var tg := ButtonGroup.new()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	whole.add_child(col)
	_stats = StatsChart.new()
	_stats.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stats.visible = false
	whole.add_child(_stats)
	_stats.setup(sim, self)
	for pair in [[tr("panel_status"), col], [tr("panel_stats"), _stats]]:
		var b := _button(pair[0], true, tg)
		b.button_pressed = pair[1] == col
		var show: Control = pair[1]
		b.pressed.connect(func():
			col.visible = show == col
			_stats.visible = show == _stats
			_stats.redraw())
		_leather_button(b)
		tabs.add_child(b)
		_side_tabs.append(b)
	guide_targets["stats"] = _side_tabs[1]
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(gap)
	# folded away, a tab is left at the right edge to bring it back (on a narrow window it covered the top bar's buttons)
	var fold := _button(tr("panel_fold"), false)
	fold.tooltip_text = tr("panel_fold_tip")
	fold.pressed.connect(func(): set_side_open(false))
	_side_tab = _button(tr("panel_open"), false)
	_side_tab.tooltip_text = tr("panel_open_tip")
	_side_tab.anchor_left = 1.0
	_side_tab.anchor_right = 1.0
	_side_tab.offset_right = -12
	_side_tab.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_side_tab.visible = false
	_style_postit(_side_tab)
	_side_tab.add_theme_font_size_override("font_size", 15)
	_side_tab.rotation = deg_to_rad(2.0)
	_side_tab.pressed.connect(func(): set_side_open(true))
	root.add_child(_side_tab)
	root.get_viewport().size_changed.connect(_layout_side)

	_leather_button(fold)
	tabs.add_child(fold)
	var st := VBoxContainer.new()
	st.add_theme_constant_override("separation", 6)
	col.add_child(st)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 3)
	st.add_child(grid)
	# (cut, the keeper: egg-to-worker v0.13.9; development and worker size v0.13.10 - on the Statistics tab still)
	for key in ["queen", "workers", "out", "nurses", "callow", "eggs", "larvae", "pupae", "sugar", "fat", "protein",
			"nest_t", "dead", "brood_dead", "depth", "vol"]:
		var names := {"queen": tr("queen"), "workers": tr("panel_workers"), "out": tr("panel_out"), "nurses": tr("panel_nurses"),
			"callow": tr("panel_callow"), "eggs": tr("eggs"), "larvae": tr("larvae"), "pupae": tr("pupae"), "sugar": tr("panel_sugar"), "fat": tr("panel_fat"),
			"protein": tr("panel_protein"), "nest_t": tr("panel_nest_temp"), "dev": tr("panel_dev"), "dead": tr("panel_dead"), "brood_dead": tr("panel_brood_dead"), "cycle": tr("panel_cycle"),
			"vol": tr("panel_volume"), "depth": tr("panel_depth"), "size": tr("panel_size")}
		var l := _label(names[key], 13, MUTED)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var lrow := HBoxContainer.new()           # (an inked sketch before the words: v0.13.7, the keeper's picture)
		lrow.add_theme_constant_override("separation", 3)
		lrow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lrow.add_child(DeskControls.StatIcon.new(key))
		lrow.add_child(l)
		var v := _label("-", 13, INK, _mono)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.custom_minimum_size.x = 64
		v.clip_text = true                         # (a longer value - another language - trimmed, not pushing the panel wider)
		v.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		v.mouse_filter = Control.MOUSE_FILTER_PASS      # tooltips (causes of death)
		grid.add_child(lrow)
		grid.add_child(v)
		_vals[key] = v
	var hum_row := HBoxContainer.new()
	hum_row.add_child(_label(tr("panel_humidity"), 13, MUTED))
	_hum_bar = ProgressBar.new()
	_hum_bar.min_value = 0
	_hum_bar.max_value = 100
	_hum_bar.show_percentage = false
	_hum_bar.custom_minimum_size = Vector2(0, 10)
	_hum_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hum_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hum_row.add_child(_hum_bar)
	var hv := _label("-", 13, INK, _mono)
	hv.custom_minimum_size.x = 44
	hv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_vals["hum"] = hv
	hum_row.add_child(hv)
	st.add_child(hum_row)
	# what sets this colony apart (sim.trait_words: its queen, how keen it forages, how it digs ...)
	var ch := _label("-", 12, MUTED)
	ch.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ch.mouse_filter = Control.MOUSE_FILTER_PASS
	ch.tooltip_text = tr("trait_tip")
	_vals["character"] = ch
	ch.visible = false                      # (shown on the queen's card instead: ant_tip.gd - v0.13.9)
	st.add_child(ch)

	var ns := _section(col, tr("panel_section"))
	_nest = Control.new()
	_nest.custom_minimum_size = Vector2(0, 190)
	_nest.clip_contents = true
	_nest.draw.connect(_draw_nest)
	ns.add_child(_nest)

	var ls := _section(col, tr("panel_journal"))
	var jt: Control = ls.get_child(0)
	jt.tooltip_text = tr("journal_colors")      # (what its colours mean)
	jt.mouse_filter = Control.MOUSE_FILTER_PASS
	ls.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_active = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.add_theme_font_size_override("normal_font_size", 13)
	_log.add_theme_color_override("default_color", INK)
	# the day stamp in bold: the font has no bold face of its own, so [b] fell back to the plain one (v0.13.10, the keeper:
	# "the Day still doesn't look bold") - the same font thickened
	var bold := FontVariation.new()
	bold.base_font = _log.get_theme_default_font()
	bold.variation_embolden = 0.9
	_log.add_theme_font_override("bold_font", bold)
	_log.add_theme_font_size_override("bold_font_size", 13)
	_log.add_theme_stylebox_override("normal", Desk.JournalBox.new())      # (a page with a stitched spine: v0.13.7)
	ls.add_child(_log)


## Journal lines that were good news (green) until v0.13.9 and are everyday now (the saves keep the old colour).
const EVERYDAY_INK := Color(0.33, 0.25, 0.18)     # the everyday words a softer ink than the bold day stamp (v0.13.10)
const EVERYDAY := ["log_new_worker", "log_chamber_planned", "log_chamber_opened", "log_beyond_food"]


func _render_log() -> void:
	var lines := PackedStringArray()
	for e in sim.log_entries.slice(0, 40):
		var kind: String = e.kind
		var key: String = e.get("key", "")
		if kind == "ok" and (key.begins_with("log_found_") or key in EVERYDAY):
			kind = ""                       # (written green before v0.13.9: everyday news, plain ink now)
		var col := "#" + (DANGER if kind == "bad" else (LEAF if kind == "ok" else (AMBER if kind == "named" else EVERYDAY_INK))).to_html(false)
		# (the day and time in bold dark ink; the words coloured by how much they matter - red danger, green good news,
		# amber a named ant, ink the everyday: v0.13.9)
		lines.append("[b][color=#%s]%s[/color][/b]  [color=%s]%s[/color]" % [INK.to_html(false), L.stamp(e), col, L.entry_text(e)])
	_log.text = "\n".join(lines)


## Side view of the real excavated nest: open space projected through the depth of the block,
## coloured with the same soil layers as the 3D view. Rebuilt only when the ants have dug.
func _refresh_nest_image() -> void:
	var nv = sim.nest
	if nv.air == _proj_air and nv.resized == _proj_resized and _proj_tex != null:
		return
	_proj_air = nv.air
	_proj_resized = nv.resized
	var h: int = nv.hy()                       # (the soil held: a deep garden nest's from y_lo, below 0)
	var img := Image.create(nv.wx(), h, false, Image.FORMAT_RGBA8)
	var loam := Color(0.3, 0.2, 0.12)
	var clay := Color(0.55, 0.34, 0.2)
	var sand := Color(0.72, 0.59, 0.4)
	var hole := Color(0.2, 0.14, 0.1)        # open space: dark enough to read, light enough to see ants in it
	for yy in h:
		var y: int = nv.y_lo + yy
		var depth: int = nv.ny - 1 - y
		var soil := loam.lerp(clay, clampf((depth - 11) / 6.0, 0.0, 1.0)).lerp(sand, clampf((depth - 37) / 8.0, 0.0, 1.0))
		for x in nv.wx():
			var open: int = nv.proj[yy * nv.wx() + x]
			var tone := soil * (0.9 + 0.2 * _seeded(x * 131 + y, 3))
			tone.a = 1.0
			img.set_pixel(x, depth, tone if open == 0 else hole.lerp(tone, 0.25 / open))
	if _proj_tex == null or _proj_tex.get_height() != h or _proj_tex.get_width() != nv.wx():
		_proj_tex = ImageTexture.create_from_image(img)
	else:
		_proj_tex.update(img)
	# frame the dug part of the block (plus the surface above it) so the nest fills the panel
	var lo := Vector2i(nv.wx(), nv.ny)
	var hi := Vector2i(-1, nv.y_lo - 1)
	for yy in h:
		var y: int = nv.y_lo + yy
		for x in nv.wx():
			if nv.proj[yy * nv.wx() + x] > 0:
				lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
				hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
	if hi.x < 0:
		_crop = Rect2i(0, 0, nv.wx(), h)
		return
	var cx: int = (lo.x + hi.x) / 2
	var half_w: int = maxi(16, (hi.x - lo.x) / 2 + 7)
	var top: int = nv.ny - 1                                   # always show up to the surface
	var bottom: int = maxi(nv.y_lo, lo.y - 7)
	var height: int = maxi(top - bottom + 1, 24)
	# keep roughly the panel's aspect (about 1.5 wide : 1 tall)
	half_w = maxi(half_w, int(height * 0.75))
	var x0: int = clampi(cx - half_w, 0, maxi(0, nv.wx() - 2 * half_w))
	_crop = Rect2i(x0, nv.ny - 1 - top, mini(2 * half_w, nv.wx()), mini(height, h))


func _draw_nest() -> void:
	var c := _nest
	var w := c.size.x
	var h := c.size.y
	var nv = sim.nest
	if nest_view and not nest_view.active and _t - _spots_t > 2.0:
		_spots_t = _t
		nest_view._refresh_spots()        # keep brood placement current while the 3D view is closed
	_refresh_nest_image()

	c.draw_rect(Rect2(0, 0, w, h), Color(0.08, 0.06, 0.05))
	# keeper's water tank on the left (outdoors: the soil's moisture, the nest humidity)
	var res := Rect2(8, 22, 22, h - 30)
	_water_tube(c, res, clampf(sim.humidity if sim.scenario == "wild" else sim.water, 0.0, 1.0))
	_nest_label(c, tr("panel_water"), Vector2(8, 16))

	# the nest itself, fitted to the remaining space
	var area := Rect2(40, 12, w - 46, h - 16)
	var cr := _crop
	var s: float = minf(area.size.x / cr.size.x, area.size.y / cr.size.y)
	var size := Vector2(cr.size) * s
	var org := area.position + (area.size - size) * Vector2(0.5, 0.0)
	c.draw_rect(Rect2(org.x, org.y - 4, size.x, 4), Color("587a33"))          # turf on top
	c.draw_texture_rect_region(_proj_tex, Rect2(org, size), Rect2(cr))
	var to_screen := func(p: Vector3) -> Vector2:
		return org + Vector2(p.x - nv.x_lo + 0.5 - cr.position.x, nv.ny - 0.5 - p.y - cr.position.y) * s      # (the image counts from the box's corner)

	# brood where the 3D view puts it
	if nest_view:
		var sp: Dictionary = nest_view._spots
		_brood_dots(c, to_screen, sp.get("eggs", []), sim.eggs.size(), 90, Color("f4efe2"), 0.45, s, 1)
		_brood_dots(c, to_screen, sp.get("larvae", []), sim.larvae.size(), 70, Color("efe3c4"), 0.75, s, 3)
		_brood_dots(c, to_screen, sp.get("pupae", []), sim.pupae.size(), 60, Color("c9a97a"), 0.9, s, 5)
		var qp: Vector3 = sp.get("queen", Vector3.ZERO)
		if sim.queen.alive and qp != Vector3.ZERO:
			var qs: Vector2 = to_screen.call(qp)
			Kit.ant(c, qs, sin(_t * 0.3) * 0.25, 0.75 * s, 0.0, Ant.NONE, Color("24170e"), false)
			_nest_label(c, tr("queen"), qs + Vector2(-14, -2.4 * s))
		# nestmates: the same ants that walk the 3D nest, or a few resting in the chambers
		var body: Color = sim.sp["body_color"]
		if not nest_view._mates.is_empty():
			if nest_view._mates.size() <= 40:
				for m in nest_view._mates:
					var p: Vector3 = m.get("vp", m.to)
					var f: Vector3 = m.get("vf", Vector3.RIGHT)
					Kit.ant(c, to_screen.call(p), atan2(-f.y, f.x if absf(f.x) > 0.01 else 0.01), 0.32 * s, m.get("gait", 0.0), Ant.NONE, body, false)
			else:
				# a big colony: each ant a short dash along its heading, all drawn in one go (a drawn ant each,
				# with legs, was thousands of draw calls a frame for the little cross-section)
				var segs := PackedVector2Array()
				for m in nest_view._mates:
					var p: Vector3 = m.get("vp", m.to)
					var f: Vector3 = m.get("vf", Vector3.RIGHT)
					var q: Vector2 = to_screen.call(p)
					var d := Vector2(f.x, -f.y).normalized() * 0.6 * s if absf(f.x) + absf(f.y) > 0.01 else Vector2(0.6 * s, 0)
					segs.append(q - d)
					segs.append(q + d)
				c.draw_multiline(segs, body.darkened(0.2), maxf(1.5, 0.45 * s))
		else:
			var all: Array = sp.get("all", [])
			var inside: int = mini(30, sim.workers.size() - sim.out_count)
			for i in (inside if not all.is_empty() else 0):
				var p: Vector3 = all[int(_seeded(i, 21) * all.size()) % all.size()]
				Kit.ant(c, to_screen.call(p), _seeded(i, 22) * TAU, 0.32 * s, _t * 3.0 + i, Ant.NONE, body, false)
	c.draw_set_transform_matrix(Transform2D.IDENTITY)
	_nest_label(c, tr("depth_chambers") % [nv.depth_cm(), nv.chambers.size()], Vector2(org.x + 4, org.y + 12))


## The water as a glass test tube (v0.13.9, the keeper: "like water in a tube"): a rounded glass, the water
## shaded deep to light with a curved meniscus that ripples a little, a few rising bubbles, scale ticks,
## and the glass's own shine over it all.
func _water_tube(c: Control, r: Rect2, frac: float) -> void:
	var rad: float = r.size.x * 0.5
	var glass := StyleBoxFlat.new()
	glass.bg_color = Color(0.16, 0.19, 0.2, 0.9)
	glass.set_corner_radius_all(int(rad))
	glass.corner_radius_top_left = 3
	glass.corner_radius_top_right = 3
	glass.anti_aliasing = true
	c.draw_style_box(glass, r)
	var inner := r.grow(-3.0)
	var top: float = inner.end.y - frac * inner.size.y
	if frac > 0.002:
		var water := StyleBoxFlat.new()
		water.set_corner_radius_all(int(rad - 3.0))
		water.corner_radius_top_left = 0
		water.corner_radius_top_right = 0
		water.anti_aliasing = true
		# deep at the bottom, lighter toward the top: drawn as bands
		var bands := 14
		for i in bands:
			var y0: float = lerpf(top, inner.end.y, float(i) / bands)
			var y1: float = lerpf(top, inner.end.y, float(i + 1) / bands)
			var col := Color(0.36, 0.66, 0.86, 0.85).lerp(Color(0.12, 0.33, 0.6, 0.92), float(i) / (bands - 1))
			if i == bands - 1:
				water.bg_color = col
				c.draw_style_box(water, Rect2(inner.position.x, y0, inner.size.x, inner.end.y - y0))
			else:
				c.draw_rect(Rect2(inner.position.x, y0, inner.size.x, y1 - y0 + 0.5), col)
		# the meniscus: the surface curves up at the glass, and ripples slowly
		var pts := PackedVector2Array()
		var n := 10
		for i in n + 1:
			var u: float = float(i) / n
			var x: float = inner.position.x + u * inner.size.x
			var cup: float = pow(absf(u - 0.5) * 2.0, 2.0) * 2.2
			pts.append(Vector2(x, top - cup + sin(_t * 1.6 + u * 5.0) * 0.5))
		c.draw_polyline(pts, Color(0.75, 0.9, 1.0, 0.85), 1.2, true)
		# rising bubbles
		for i in 3:
			var ph: float = fposmod(_t * (0.12 + 0.05 * i) + i * 0.37, 1.0)
			var by: float = lerpf(inner.end.y - 2.0, top + 3.0, ph)
			if by > top + 2.0:
				var bx: float = inner.position.x + inner.size.x * (0.3 + 0.4 * _seeded(i, 31)) + sin(_t * 2.0 + i) * 1.2
				c.draw_arc(Vector2(bx, by), 1.1 + 0.4 * i, 0, TAU, 10, Color(0.85, 0.95, 1.0, 0.5), 0.8, true)
	# scale ticks every quarter
	for q in range(1, 4):
		var ty: float = inner.end.y - inner.size.y * q / 4.0
		var tl: float = 6.0 if q == 2 else 4.0
		c.draw_line(Vector2(r.end.x - tl, ty), Vector2(r.end.x - 1.0, ty), Color(0.9, 0.88, 0.8, 0.45), 1.0)
	# the glass: rim, a long shine on the left and a short one on the right
	var rim := StyleBoxFlat.new()
	rim.draw_center = false
	rim.set_border_width_all(1)
	rim.border_color = Color(0.82, 0.86, 0.85, 0.55)
	rim.set_corner_radius_all(int(rad))
	rim.corner_radius_top_left = 3
	rim.corner_radius_top_right = 3
	rim.anti_aliasing = true
	c.draw_style_box(rim, r)
	c.draw_rect(Rect2(r.position.x - 1.0, r.position.y - 1.0, r.size.x + 2.0, 2.5), Color(0.82, 0.86, 0.85, 0.6))   # the lip
	c.draw_line(Vector2(r.position.x + 3.5, r.position.y + 6), Vector2(r.position.x + 3.5, r.end.y - rad - 2), Color(1, 1, 1, 0.28), 2.0)
	c.draw_line(Vector2(r.end.x - 4.0, r.position.y + 8), Vector2(r.end.x - 4.0, r.position.y + 8 + r.size.y * 0.18), Color(1, 1, 1, 0.16), 1.0)


func _brood_dots(c: Control, to_screen: Callable, spots: Array, count: int, cap: int, col: Color, r: float,
		s: float, seed: int) -> void:
	if spots.is_empty():
		return
	for i in mini(count, cap):
		var p: Vector3 = spots[i % spots.size()]
		var q: Vector2 = to_screen.call(p) + Vector2(_seeded(i, seed) - 0.5, -(i / spots.size()) * 0.5 - _seeded(i, seed + 1) * 0.4) * s
		Kit.ellipse(c, q, Vector2(r, r * 0.7) * s, col, _seeded(i, seed + 2) * 3.0)


func _nest_label(c: Control, text: String, p: Vector2) -> void:
	c.draw_string(c.get_theme_default_font(), p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, MUTED)


# ---------------------------------------------------------------- chart

## The side panel folded away or out (kept in the settings; the first time folded on a window too narrow for both it
## and the top bar). Folded, the outworld's camera centres on the whole window and the camera buttons move right.
## The tools at the bottom left, drawn smaller (down to 0.7) when they would run under the side panel - a narrow window
## with the panel open (1366 wide, the formicarium's nine tools went under it in English). The camera buttons go up
## over them where the two meet (_fit_bottom).
func _fit_tools() -> void:
	if _tools_bar == null or _side == null:
		return
	var vw: float = _side.get_viewport_rect().size.x
	var edge: float = (vw - PANEL_W - 14.0) if _side.visible else vw
	var need: float = _tools_bar.get_combined_minimum_size().x
	var f := clampf((edge - _tools_bar.offset_left - 12.0) / maxf(need, 1.0), 0.7, 1.0)
	if absf(f - _tools_bar.scale.x) > 0.005:
		_tools_bar.pivot_offset = Vector2(0.0, _tools_bar.size.y)
		_tools_bar.scale = Vector2(f, f)
		_fit_bottom()


func set_side_open(open: bool, keep := true) -> void:
	_side.visible = open
	_side_tab.visible = not open
	_cam_pad.offset_right = (-PANEL_W - 14.0) if open else -14.0
	if outworld:
		outworld.side_px = (PANEL_W + 12.0) if open else 0.0
	if keep:
		settings["side_open"] = open
		settings_changed.emit(settings)
	_layout_side()


## (the bar is on the left since v0.11.78: nothing of it runs in under the side panel any more)
func _crowded() -> bool:
	return false


func _layout_side() -> void:
	_side.offset_top = 22.0
	_side_tab.offset_top = _side.offset_top
	_fit_bottom()


## The camera buttons above the tool bar where the two would meet (a narrow window, longer English words).
func _fit_bottom() -> void:
	if _tools_bar == null:
		return
	_cam_pad.offset_bottom = -12.0
	var vp := _side.get_viewport_rect().size
	var pad_left: float = vp.x + _cam_pad.offset_right - _cam_pad.get_combined_minimum_size().x
	var k: float = _tools_bar.scale.x             # (drawn smaller in a narrow window: _fit_tools)
	if _tools_bar.position.x + _tools_bar.get_combined_minimum_size().x * k + 8.0 > pad_left:
		_cam_pad.offset_bottom = -12.0 - _tools_bar.get_combined_minimum_size().y * k - 34.0
