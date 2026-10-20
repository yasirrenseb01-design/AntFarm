extends PanelContainer
## Click an ant to select it: a white outline follows it (drawn by the view) and this box stays open with who it
## is - its job in the colony, what it is doing now, its age and size, injuries, and its leanings (the thresholds
## that decide which work it takes up first). Click empty ground or press Esc to let it go. The views find the
## ant under the mouse (pick_ant) and report the selected one as it is now (info_for).
## A worker can be given a name here (sim.name_ant; any number of them): the title tour follows named ants, and the
## HUD tells the keeper when one dies.

const Ant := preload("res://scripts/sim/ant.gd")
const Hud := preload("res://scripts/view/ui/parts/hud_base.gd")

var sim
var views: Array = []            # the 3D views (pick_ant, info_for, can_select, sel_kind / sel_id)
var sel := {}                    # {"kind": "worker"|"digger"|"queen", "id": worker id (a digger: its own id)}
var test_mouse := Vector2.INF    # dev (--hover): select the ant at this screen position
var _press := Vector2.INF
var _text: Label
var _t := 0.0
var _name_row: HBoxContainer
var _name_edit: LineEdit
var _name_for := -2              # the worker id the name box was filled for (-2: none yet)


func setup(s, view_list: Array, font: Font) -> void:
	sim = s
	views = view_list
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 50
	position = Vector2(18, 140)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	_text = Label.new()
	if font != null:
		_text.add_theme_font_override("font", font)
	_text.add_theme_font_size_override("font_size", 14)
	col.add_child(_text)
	# the name box (workers only): type, then Enter or the button; an empty name takes it away
	_name_row = HBoxContainer.new()
	_name_row.add_theme_constant_override("separation", 6)
	_name_row.visible = false
	col.add_child(_name_row)
	_name_edit = LineEdit.new()
	_name_edit.max_length = sim.NAME_MAX
	_name_edit.placeholder_text = tr("tip_name_ant")
	_name_edit.custom_minimum_size.x = 190
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.add_theme_color_override("font_color", Hud.INK)
	_name_edit.add_theme_color_override("font_placeholder_color", Hud.MUTED)
	_name_edit.add_theme_font_size_override("font_size", 14)
	_name_edit.text_submitted.connect(func(_t): _give_name())
	_name_row.add_child(_name_edit)
	var save := Button.new()
	save.text = tr("tip_name_set")
	save.focus_mode = Control.FOCUS_NONE
	save.pressed.connect(_give_name)
	_name_row.add_child(save)


## The name in the box goes to the selected worker (sim.name_ant: only words, nothing in the simulation changes).
func _give_name() -> void:
	if sel.get("kind", "") == "worker":
		sim.name_ant(int(sel.id), _name_edit.text)
		_name_edit.text = _find_worker(int(sel.id)).name if _find_worker(int(sel.id)) != null else ""
	elif sel.get("kind", "") == "queen" and sim.queen.alive:
		sim.name_queen(_name_edit.text)
		_name_edit.text = String(sim.queen.get("name", ""))
	_name_edit.release_focus()
	_t = 1.0                                 # (the words with the new name at once)


func _find_worker(id: int):
	for w in sim.workers:
		if w.id == id:
			return w
	return null


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_press = e.position
		elif _press != Vector2.INF and _press.distance_to(e.position) < 6.0:      # a click, not a drag
			_click(e.position)
			_press = Vector2.INF
	elif e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE and not sel.is_empty():
		_select({})


func _active_view():
	for v in views:
		if v != null and v.active:
			return v
	return null


func _click(at: Vector2) -> void:
	var v = _active_view()
	if v == null or not v.can_select():
		return
	_select(v.pick_ant(at))


func _select(info: Dictionary) -> void:
	if info.is_empty():
		sel = {}
	elif info.kind == "digger":
		sel = {"kind": "digger", "id": int(info.get("dig", -1))}
	elif info.kind == "queen":
		sel = {"kind": "queen", "id": -1}
	elif info.kind in ["eggs", "larvae", "pupae"]:
		sel = {"kind": info.kind, "id": int(info.get("id", -1))}
	else:
		sel = {"kind": "worker", "id": info.w.id if info.get("w") != null else -1}
	for v in views:
		if v != null:
			v.sel_kind = sel.get("kind", "")
			v.sel_id = int(sel.get("id", -1))
	visible = not sel.is_empty()
	_name_edit.release_focus()
	_t = 1.0                                 # (its words now, not in a quarter of a second)


func _process(delta: float) -> void:
	if test_mouse != Vector2.INF:
		_click(test_mouse)
		test_mouse = Vector2.INF
	if sel.is_empty():
		return
	_t += delta
	if _t < 0.25:
		return                                 # (the words are refreshed four times a second)
	_t = 0.0
	var v = _active_view()
	var info: Dictionary = v.info_for(sel.kind, sel.id) if v != null else {}
	if info.is_empty() and sel.kind == "worker":
		# not in this view (gone into the nest, or out): still say who it is and where
		for w in sim.workers:
			if w.id == sel.id:
				info = {"kind": "worker", "w": w, "act": w.act, "elsewhere": tr("tip_in_nest") if w.state == Ant.IN_NEST else tr("tip_outside")}
	if info.is_empty() and sel.kind in ["eggs", "larvae", "pupae"]:
		_text.text = {"eggs": tr("tip_egg_gone"), "larvae": tr("tip_larva_gone"),
			"pupae": tr("tip_pupa_gone")}[sel.kind] + tr("tip_click_another")
	elif info.is_empty():
		_text.text = tr("tip_gone")
	else:
		_text.text = describe(info) + (tr("tip_elsewhere") % info.elsewhere if info.has("elsewhere") else "")
	_update_name_box()
	reset_size()


## The name box shows for a worker still in the colony, filled with its name when it was chosen (not while typing).
func _update_name_box() -> void:
	var queen: bool = sel.get("kind", "") == "queen" and sim.queen.alive
	var w = _find_worker(int(sel.id)) if sel.get("kind", "") == "worker" else null
	_name_row.visible = w != null or queen
	if w == null and not queen:
		_name_for = -2
		_name_edit.release_focus()
		return
	var id: int = -1 if queen else w.id                 # (the queen: -1)
	var now: String = String(sim.queen.get("name", "")) if queen else w.name
	if _name_for != id and not _name_edit.has_focus():
		_name_for = id
		_name_edit.text = now
		_name_edit.placeholder_text = (tr("tip_name_queen") if queen else tr("tip_name_ant")) if now == "" else tr("tip_name_clear")


## The words for an ant found by a view: {"kind": "worker"|"queen"|"digger", "w": Ant or null, "role", "act"}.
func describe(info: Dictionary) -> String:
	if info.kind in ["eggs", "larvae", "pupae"]:
		return _brood_words(info.kind, info.item)
	if info.kind == "queen":
		var qn := String(sim.queen.get("name", ""))
		var lines := [tr("queen") if qn == "" else tr("tip_queen_named") % qn]
		if not sim.queen.alive:
			lines.append(tr("tip_dead"))
		elif sim.hibernating() or sim.climate.nest < 6.0:
			lines.append(tr("tip_hibernating"))
		elif sim.founding():
			lines.append(tr("tip_queen_founding") % int(sim.queen.reserve / float(sim.sp["queen_reserve"]) * 100.0))
		else:
			lines.append(tr("tip_laying") if not (sim.starving or sim.queen.starve > 0.5) else tr("tip_queen_not_laying"))
		lines.append(tr("tip_doing") + _act_name(int(info.get("act", 1))))
		return "\n".join(lines)
	var w = info.get("w")
	var lines := []
	lines.append((tr("tip_worker_named") % [w.name, w.id] if w.name != "" else tr("tip_worker_n") % w.id) if w != null else tr("worker"))
	lines.append(tr("tip_job") + _job(w, info))
	lines.append(tr("tip_doing") + _act_name(int(info.get("act", 0))))
	if w != null:
		lines.append(tr("tip_age_size") % [int(w.age), w.size * 4.2])
		if w.carry == Ant.SUGAR:
			lines.append(tr("tip_crop_full"))
		elif w.carry == Ant.PROTEIN:
			lines.append(tr("tip_carry_prey"))
		elif w.carry == Ant.CORPSE:
			lines.append(tr("tip_carry_corpse"))
		if w.hurt > 0.05:
			lines.append(tr("tip_hurt"))
		if w.energy < 0.6:
			lines.append(tr("tip_hungry"))
		var lean := _leanings(w)
		if lean != "":
			lines.append(tr("tip_leanings") + lean)
	return "\n".join(lines)


func _job(w, info: Dictionary) -> String:
	if info.kind == "digger":
		return tr("job_dig")
	if info.get("role", "") == "attend":
		return tr("job_attend")
	if w == null:
		return "-"
	match w.state:
		Ant.SEARCH:
			return tr("job_search")
		Ant.RETURN:
			return tr("job_return")
		Ant.HOME:
			return tr("job_home")
		Ant.UNDERTAKER:
			return tr("job_undertaker")
		Ant.DEFEND:
			return tr("job_defend")
		Ant.DRAG:
			return tr("job_drag")
	match w.task:
		Ant.TASK_CALLOW:
			return tr("job_callow")
		Ant.TASK_NURSE:
			return tr("job_nurse")
		Ant.TASK_DIG:
			return tr("job_dig")
		Ant.TASK_RESERVE:
			return tr("job_just_back") if info.get("role", "") == "traffic" else tr("job_reserve")
	return "-"


## Its standing leanings from the response thresholds (only the clear ones).
func _leanings(w) -> String:
	var out := []
	if w.threshold(Ant.TH_FORAGE) < 0.8:
		out.append(tr("lean_forage"))
	elif w.threshold(Ant.TH_FORAGE) > 1.25:
		out.append(tr("lean_stay"))
	if w.threshold(Ant.TH_DIG) < 0.75:
		out.append(tr("lean_dig"))
	if w.threshold(Ant.TH_DEFEND) < 0.75:
		out.append(tr("lean_fight"))
	if w.threshold(Ant.TH_ATTEND) < 0.75:
		out.append(tr("lean_queen"))
	if w.threshold(Ant.TH_AGE) > 1.25:
		out.append(tr("lean_nurse"))
	return ", ".join(out)


func _act_name(act: int) -> String:
	match act % 100:
		0: return tr("act_walk")
		1: return tr("act_rest")
		2: return tr("act_bite")
		3: return tr("act_antennate")
		4: return tr("act_groom")
		5: return tr("tip_laying")
		6: return tr("act_feed")
		21: return tr("act_fed")
		22: return tr("act_allogroom")
		23: return tr("act_groomed")
		7: return tr("act_tend")
		8: return tr("act_carry")
		9: return tr("act_milk")
		10: return tr("act_drink")
		13: return tr("act_attack")
		14: return tr("act_alarm")
		15: return tr("act_pause")
		16: return tr("act_trail")
		17: return tr("act_egg")
		18: return tr("act_flipped")
		19: return tr("act_drag")
		20: return tr("act_glass")
		22: return tr("act_beyond")
	return "-"


## The words for an egg, a larva or a cocoon: its stage, how far on it is, and when it moves on (at the nest's
## warmth now: cold slows it all, and a larva grows only as fast as it is fed). Lengths from the species' data.
func _brood_words(kind: String, it: Dictionary) -> String:
	var sp: Dictionary = sim.sp
	var p: float = it.get("p", 0.0)
	var lines := []
	var days_key: String = {"eggs": "egg_days", "larvae": "larva_days", "pupae": "pupa_days"}[kind]
	var rate: float = sim.dev * (sim.larva_fed if kind == "larvae" else 1.0)
	var left := tr("tip_brood_stopped") if rate < 0.02 else tr("tip_in_about") % _days(float(sp[days_key]) * (1.0 - p) / rate)
	match kind:
		"eggs":
			lines.append(tr("eggs"))
			lines.append(tr("tip_developed") % int(p * 100.0))
			lines.append(tr("tip_hatches") + left)
		"larvae":
			lines.append(tr("larvae"))
			lines.append(tr("tip_grown") % int(p * 100.0))
			if sim.winding_down() and p >= 0.94:
				lines.append(tr("tip_diapause"))
			else:
				lines.append(tr("tip_spins") + left)
			var h: float = it.get("h", 0.0)
			if h > 0.05:
				lines.append(tr("tip_larva_hungry") % [_days(h), int(sp["larva_starve_days"])])
			elif sim.larva_fed < 0.95:
				lines.append(tr("tip_larva_underfed") % int(sim.larva_fed * 100.0))
			else:
				lines.append(tr("tip_larva_fed"))
			lines.append(tr("tip_larva_size") % (sim._adult_size(float(it.get("q", 0.6))) * 4.2))
		"pupae":
			lines.append(tr("tip_pupa"))
			lines.append(tr("tip_developed") % int(p * 100.0))
			lines.append(tr("tip_ecloses") + left)
			lines.append(tr("tip_pupa_size") % (float(it.get("s", 1.0)) * 4.2))
	return "\n".join(lines)


func _days(d: float) -> String:
	if d < 1.0:
		return tr("hours_d") % maxi(1, int(d * 24.0))
	return tr("days_d") % int(round(d))
