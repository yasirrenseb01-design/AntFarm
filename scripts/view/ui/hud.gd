extends "res://scripts/view/ui/parts/hud_panel.gd"
## Keeper's instrument panel: clock and speed on top, tools at the bottom, colony readout, nest
## cross-section, population chart and journal on the right. This file is the top of the chain.
## Layers: parts/hud_base <- hud_colonies <- hud_controls <- hud_panel <- hud.


func setup(s, w) -> void:
	sim = s
	world = w
	sim.logged.connect(func(_e): _log_dirty = true)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)
	_build_top(root)
	_build_tools(root)
	_build_panel(root)
	_build_camera_pad(root)
	_build_colonies(root)
	_apply_mode("surface")
	refresh(1.0)


# ---------------------------------------------------------------- refresh

func refresh(delta: float) -> void:
	_t += delta
	_clock.text = "วันที่ %d  %s" % [sim.day(), sim.clock_text()]
	var m := int(sim.time_of_day() * 1440)
	var sky := "ฝนตก" if sim.climate.raining() else ("กลางคืน" if m < 360 or m > 1110 else "แจ่มใส")
	_weather.text = "อากาศ %.1f°C · %s · มดออกหากิน %d%%" % [sim.climate.air, sky, int(sim.activity * 100)]
	_frame += 1
	if _frame % 4 == 0 and _nest.is_visible_in_tree():
		_nest.queue_redraw()
	if _log_dirty:
		_log_dirty = false
		_render_log()
	if fmod(_t, 0.2) > delta:
		return
	var q: Label = _vals["queen"]
	if not sim.queen.alive:
		_show(q, "ตายแล้ว", DANGER)
	elif sim.founding():
		_show(q, "ไขมัน %d%%" % int(sim.queen.reserve / float(sim.sp["queen_reserve"]) * 100.0), LEAF)   # sealed in, living on her reserves
	elif sim.starving or sim.queen.starve > 0.5:
		_show(q, "หยุดวางไข่", DANGER)
	else:
		_show(q, "วางไข่", LEAF)
	_show(_vals["workers"], str(sim.workers.size()))
	_show(_vals["out"], str(sim.out_count))
	_show(_vals["nurses"], str(sim.nurses))
	_show(_vals["callow"], str(sim.callow))
	_show(_vals["eggs"], str(sim.eggs.size()))
	_show(_vals["larvae"], str(sim.larvae.size()), DANGER if sim.protein < 0.5 and sim.larvae.size() > 0 else INK)
	_show(_vals["pupae"], str(sim.pupae.size()))
	var fnd: bool = sim.founding()      # a founding queen lives on her reserves: empty stores are normal
	_show(_vals["sugar"], "%.1f" % sim.sugar, DANGER if sim.sugar < 2.0 and not fnd else INK)
	_show(_vals["protein"], "%.1f" % sim.protein, DANGER if sim.protein < 1.0 and not fnd else INK)
	_show(_vals["nest_t"], "%.1f°C" % sim.climate.nest, DANGER if sim.climate.nest > 34.0 else INK)
	_show(_vals["dev"], "%d%%" % int(sim.dev * 100))
	_show(_vals["dead"], str(sim.stats.dead + sim.stats.cannibalized))
	var cyc: float = sim.cycle_days()
	_show(_vals["cycle"], "หยุด" if cyc == INF else "%d วัน" % int(cyc))
	_show(_vals["vol"], "%.1f ซม³" % sim.nest.volume_cm3(), DANGER if sim.nest.air < sim.target_air() * 0.7 and not fnd else INK)
	_show(_vals["depth"], "%.1f ซม · %d ห้อง" % [sim.nest.depth_cm(), sim.nest.chambers.size()])
	_show(_vals["size"], "%.1f มม." % sim.mean_worker_mm() if not sim.workers.is_empty() else "ยังไม่มี")
	var hum: float = sim.humidity
	_hum_bar.value = hum * 100.0
	var ok: bool = hum >= sim.sp["humidity_ok_min"] and hum <= sim.sp["humidity_ok_max"]
	_show(_vals["hum"], "%d%%" % int(hum * 100), INK if ok else DANGER)
	_chart.queue_redraw()
