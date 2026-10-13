extends "res://scripts/view/ui/parts/hud_controls.gd"
## HUD, layer 4 of 5: the side panel (colony readout, live nest cross-section, chart, journal).


func _build_panel(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -PANEL_W
	panel.offset_right = -12
	panel.offset_top = 12
	panel.offset_bottom = -12
	root.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)

	var st := _section(col, "สถานะรัง")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 3)
	st.add_child(grid)
	for key in ["queen", "workers", "out", "nurses", "callow", "eggs", "larvae", "pupae", "sugar", "fat", "protein",
			"nest_t", "dev", "dead", "brood_dead", "cycle", "vol", "depth", "size"]:
		var names := {"queen": "ราชินี", "workers": "มดงาน", "out": "นอกรัง", "nurses": "พี่เลี้ยง",
			"callow": "ตัวใหม่", "eggs": "ไข่", "larvae": "ตัวอ่อน", "pupae": "ดักแด้", "sugar": "น้ำตาล", "fat": "ไขมันสะสม",
			"protein": "โปรตีน", "nest_t": "ในรัง", "dev": "พัฒนาการ", "dead": "มดงานตาย", "brood_dead": "ลูกมดตาย", "cycle": "ไข่→มดงาน",
			"vol": "ปริมาตรรัง", "depth": "ลึก", "size": "ขนาดมดงาน"}
		var l := _label(names[key], 13, MUTED)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := _label("-", 13, INK, _mono)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.custom_minimum_size.x = 64
		v.mouse_filter = Control.MOUSE_FILTER_PASS      # tooltips (causes of death)
		grid.add_child(l)
		grid.add_child(v)
		_vals[key] = v
	var hum_row := HBoxContainer.new()
	hum_row.add_child(_label("ความชื้นในรัง", 13, MUTED))
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

	var ns := _section(col, "ภาพตัดขวางรัง")
	_nest = Control.new()
	_nest.custom_minimum_size = Vector2(0, 190)
	_nest.clip_contents = true
	_nest.draw.connect(_draw_nest)
	ns.add_child(_nest)

	var cs := _section(col, "ประชากรรายวัน")
	_chart = Control.new()
	_chart.custom_minimum_size = Vector2(0, 92)
	_chart.draw.connect(_draw_chart)
	cs.add_child(_chart)

	var ls := _section(col, "บันทึกผู้เลี้ยง")
	ls.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_active = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.add_theme_font_size_override("normal_font_size", 13)
	_log.add_theme_color_override("default_color", INK)
	ls.add_child(_log)


func _render_log() -> void:
	var lines := PackedStringArray()
	for e in sim.log_entries.slice(0, 40):
		var col := "#e8664f" if e.kind == "bad" else ("#9cc565" if e.kind == "ok" else "#f1e6d6")
		lines.append("[color=#8a7562]%s[/color]  [color=%s]%s[/color]" % [e.stamp, col, e.text])
	_log.text = "\n".join(lines)


## Side view of the real excavated nest: open space projected through the depth of the block,
## coloured with the same soil layers as the 3D view. Rebuilt only when the ants have dug.
func _refresh_nest_image() -> void:
	var nv = sim.nest
	if nv.air == _proj_air and _proj_tex != null:
		return
	_proj_air = nv.air
	var img := Image.create(nv.nx, nv.ny, false, Image.FORMAT_RGBA8)
	var loam := Color(0.3, 0.2, 0.12)
	var clay := Color(0.55, 0.34, 0.2)
	var sand := Color(0.72, 0.59, 0.4)
	var hole := Color(0.2, 0.14, 0.1)        # open space: dark enough to read, light enough to see ants in it
	for y in nv.ny:
		var depth: int = nv.ny - 1 - y
		var soil := loam.lerp(clay, clampf((depth - 11) / 6.0, 0.0, 1.0)).lerp(sand, clampf((depth - 37) / 8.0, 0.0, 1.0))
		for x in nv.nx:
			var open: int = nv.proj[y * nv.nx + x]
			var tone := soil * (0.9 + 0.2 * _seeded(x * 131 + y, 3))
			tone.a = 1.0
			img.set_pixel(x, depth, tone if open == 0 else hole.lerp(tone, 0.25 / open))
	if _proj_tex == null:
		_proj_tex = ImageTexture.create_from_image(img)
	else:
		_proj_tex.update(img)
	# frame the dug part of the block (plus the surface above it) so the nest fills the panel
	var lo := Vector2i(nv.nx, nv.ny)
	var hi := Vector2i(-1, -1)
	for y in nv.ny:
		for x in nv.nx:
			if nv.proj[y * nv.nx + x] > 0:
				lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
				hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
	if hi.x < 0:
		_crop = Rect2i(0, 0, nv.nx, nv.ny)
		return
	var cx: int = (lo.x + hi.x) / 2
	var half_w: int = maxi(16, (hi.x - lo.x) / 2 + 7)
	var top: int = nv.ny - 1                                   # always show up to the surface
	var bottom: int = maxi(0, lo.y - 7)
	var height: int = maxi(top - bottom + 1, 24)
	# keep roughly the panel's aspect (about 1.5 wide : 1 tall)
	half_w = maxi(half_w, int(height * 0.75))
	var x0: int = clampi(cx - half_w, 0, maxi(0, nv.nx - 2 * half_w))
	_crop = Rect2i(x0, nv.ny - 1 - top, mini(2 * half_w, nv.nx), mini(height, nv.ny))


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
	var res := Rect2(6, 22, 26, h - 30)
	c.draw_rect(res, Color(0.12, 0.1, 0.09))
	var lvl: float = (sim.humidity if sim.scenario == "wild" else sim.water) * (res.size.y - 6)
	c.draw_rect(Rect2(res.position.x + 3, res.end.y - 3 - lvl, res.size.x - 6, lvl), Color(0.3, 0.55, 0.8, 0.75))
	c.draw_rect(res, Color(0.55, 0.5, 0.45, 0.6), false, 1.0)
	_nest_label(c, "น้ำ", Vector2(8, 16))

	# the nest itself, fitted to the remaining space
	var area := Rect2(40, 12, w - 46, h - 16)
	var cr := _crop
	var s: float = minf(area.size.x / cr.size.x, area.size.y / cr.size.y)
	var size := Vector2(cr.size) * s
	var org := area.position + (area.size - size) * Vector2(0.5, 0.0)
	c.draw_rect(Rect2(org.x, org.y - 4, size.x, 4), Color("587a33"))          # turf on top
	c.draw_texture_rect_region(_proj_tex, Rect2(org, size), Rect2(cr))
	var to_screen := func(p: Vector3) -> Vector2:
		return org + Vector2(p.x + 0.5 - cr.position.x, nv.ny - 0.5 - p.y - cr.position.y) * s

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
			_nest_label(c, "ราชินี", qs + Vector2(-14, -2.4 * s))
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
	_nest_label(c, "ลึก %.1f ซม · %d ห้อง" % [nv.depth_cm(), nv.chambers.size()], Vector2(org.x + 4, org.y + 12))


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

func _draw_chart() -> void:
	var c := _chart
	var w := c.size.x
	var h := c.size.y
	var pts: Array = sim.history.duplicate()
	pts.append({"workers": sim.workers.size(), "brood": sim.eggs.size() + sim.larvae.size() + sim.pupae.size()})
	var top := 10
	for p in pts:
		top = maxi(top, maxi(p.workers, p.brood))
	top = int(ceil(top / 10.0)) * 10
	var left := 30.0
	var font := c.get_theme_default_font()
	for v in [0, top / 2, top]:
		var y := h - 12 - float(v) / top * (h - 20)
		c.draw_line(Vector2(left, y), Vector2(w, y), LINE, 1.0)
		c.draw_string(font, Vector2(0, y + 4), str(v), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, MUTED)
	var n := pts.size()
	for series in [["brood", INK], ["workers", AMBER]]:
		var line := PackedVector2Array()
		for i in n:
			var x := left + (0.0 if n < 2 else float(i) / (n - 1)) * (w - left - 4)
			line.append(Vector2(x, h - 12 - float(pts[i][series[0]]) / top * (h - 20)))
		if line.size() >= 2:
			c.draw_polyline(line, series[1], 2.0, true)
		c.draw_circle(line[line.size() - 1], 3.0, series[1])
	c.draw_string(font, Vector2(left, h), "วันที่ %d" % maxi(1, sim.day() - n + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, MUTED)
	c.draw_string(font, Vector2(w - 60, h), "วันนี้", HORIZONTAL_ALIGNMENT_RIGHT, 60, 10, MUTED)
