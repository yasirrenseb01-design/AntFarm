extends "res://scripts/view/ui/parts/hud_enemies.gd"
## HUD, layer 4 of 7: the star ants panel (PART EA3a) - the first in each line of work (biggest, smallest, oldest, the
## nurse who fed the larvae most, the forager who brought most honeydew home...) and every ant the keeper has named,
## the queen first. tr("go_see") switches to the view the ant is in, picks it (its outline and info box) and the camera rides
## along until the keeper moves it.
## The rankings come from sim.top_ants() (the simulation's duties, EA3a round 1 - Cloud): a list of
## {"key", "title", "id" (worker id), "text" (what it did, in words)}; until it is there, what the colony already knows
## (size, age, injuries) is ranked here and the rest of the lines say they are coming.

const STARS_W := 400.0
## lines of work the duties will count (shown waiting until sim.top_ants() gives them)
const STAR_COMING := [["feed_larvae", "top_feed_larvae"], ["carry_brood", "top_carry_brood"], ["feed_mates", "top_feed_mates"],
	["rest", "top_rest"], ["dig", "top_dig"], ["sugar_trips", "top_sugar_trips"], ["prey", "top_prey"],
	["corpses", "top_corpses"], ["fights", "top_fights"]]

var _stars_list: VBoxContainer
var _stars_scroll: ScrollContainer
var _named_list: VBoxContainer
var _stars_sig := ""                 # what the rows were built from (rebuilt only when it changes)
var _star_follow := -2               # the worker the camera was sent after (-1: the queen, -2: none)
var _star_out := false               # whether it was outside then (it goes through the entrance: the view follows it)


func _build_stars(root: Control) -> void:
	_stars = PanelContainer.new()
	_stars.position = Vector2(14, 140)
	_stars.visible = false
	root.add_child(_stars)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(STARS_W, 620)
	_stars.add_child(scroll)
	_stars_scroll = scroll
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.custom_minimum_size = Vector2(STARS_W - 16, 0)
	scroll.add_child(col)
	var head := HBoxContainer.new()
	var title := _label(tr("stars_title"), 17, INK, _display)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := _button("×", false)
	close.pressed.connect(func(): _stars.visible = false)
	head.add_child(close)
	col.add_child(head)
	col.add_child(_label(tr("stars_named"), 13, MUTED))
	_named_list = VBoxContainer.new()
	_named_list.add_theme_constant_override("separation", 4)
	col.add_child(_named_list)
	var how := _label(tr("stars_how"), 12, MUTED)
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	how.custom_minimum_size.x = STARS_W - 40
	col.add_child(how)
	col.add_child(HSeparator.new())
	col.add_child(_label(tr("stars_firsts"), 13, MUTED))
	_stars_list = VBoxContainer.new()
	_stars_list.add_theme_constant_override("separation", 4)
	col.add_child(_stars_list)


func toggle_stars() -> void:
	_stars.visible = not _stars.visible
	if _stars.visible:
		_enemies.visible = false             # (one panel on the left at a time)
		_stars_sig = ""
		_refresh_stars()
		fit_left_panel(_stars_scroll, STARS_W)


## What the colony knows of its workers now, ranked (until sim.top_ants() is there): size, age, injuries.
func _top_now() -> Array:
	if sim.has_method("top_ants"):
		return sim.top_ants()
	var out := []
	if sim.workers.is_empty():
		return out
	var by := func(f: Callable) -> Object:
		var best = sim.workers[0]
		for w in sim.workers:
			if f.call(w) > f.call(best):
				best = w
		return best
	var big = by.call(func(w): return w.size)
	var small = by.call(func(w): return -w.size)
	var old = by.call(func(w): return w.age)
	out.append({"key": "big", "title": tr("top_big"), "id": big.id, "text": tr("top_big_text") % (big.size * 4.2)})
	out.append({"key": "small", "title": tr("top_small"), "id": small.id, "text": tr("top_big_text") % (small.size * 4.2)})
	out.append({"key": "old", "title": tr("top_old"), "id": old.id, "text": tr("top_old_text") % int(old.age)})
	var hurt = by.call(func(w): return w.hurt)
	if hurt.hurt > 0.0:
		out.append({"key": "hurt", "title": tr("top_hurt"), "id": hurt.id, "text": tr("top_hurt_text") % roundi(hurt.hurt * 100.0)})
	return out


func _worker(id: int):
	for w in sim.workers:
		if w.id == id:
			return w
	return null


func _ant_label(w) -> String:
	return ("\"%s\" · #%d" % [w.name, w.id]) if String(w.get("name") if w.get("name") != null else "") != "" else tr("tip_worker_n") % w.id


## The panel as things are now (called every 0.2 s while it is open; the rows are built again only when they change).
func _refresh_stars() -> void:
	if _stars == null or not _stars.visible:
		return
	var tops := _top_now()
	var named: Array = sim.workers.filter(func(w): return String(w.get("name") if w.get("name") != null else "") != "")
	var qname := String(sim.queen.get("name", ""))
	var sig := str(tops) + "|" + str(named.map(func(w): return [w.id, w.name, w.task, sim.outside.has(w)])) + "|" + qname + str(sim.queen.alive)
	if sig == _stars_sig:
		return
	_stars_sig = sig
	for c in _stars_list.get_children():
		c.queue_free()
	for c in _named_list.get_children():
		c.queue_free()
	var have := {}
	for t in tops:
		var w = _worker(int(t.id))
		if w == null:
			continue
		have[t.key] = true
		_star_row(_stars_list, t.title, "%s · %s" % [_ant_label(w), t.text], int(t.id))
	for c in STAR_COMING:
		if not have.has(c[0]):
			_star_row(_stars_list, tr(c[1]), tr("stars_coming"), -2)
	if qname != "" and sim.queen.alive:
		_star_row(_named_list, tr("tip_queen_named") % qname, tr("stars_in_queen_room"), -1)
	for w in named:
		_star_row(_named_list, _ant_label(w), tr("stars_job_age") % [_job_word(w), int(w.age)], w.id)
	if named.is_empty() and qname == "":
		_named_list.add_child(_label(tr("not_yet"), 12, MUTED))


func _job_word(w) -> String:
	if sim.outside.has(w):
		return tr("tip_outside")
	match int(w.task):
		1: return tr("stars_callow")
		2: return tr("stars_nurse")
		3: return tr("stars_reserve")
		4: return tr("stars_digging")
	return tr("stars_in_nest")


## One line: what, who and how much, and tr("go_see") (`id`: a worker, -1 the queen, -2 nothing to see yet).
func _star_row(parent: Control, title: String, text: String, id: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 0)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(_label(title, 13, AMBER if id != -2 else MUTED))
	var t := _label(text, 12, INK if id != -2 else MUTED)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = STARS_W - 120
	info.add_child(t)
	row.add_child(info)
	if id != -2:
		var go := _button(tr("go_see"), false)
		go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		go.pressed.connect(func(): go_to_ant(id))
		row.add_child(go)
	parent.add_child(row)


## Shows this ant: the view it is in, picked (outline + info box), the camera riding along. -1: the queen.
func go_to_ant(id: int) -> void:
	var w = _worker(id) if id >= 0 else null
	if id >= 0 and w == null:
		return                                       # (died since the list was made)
	var outside: bool = w != null and sim.outside.has(w)
	var m := "outworld" if outside else "nest"
	call("_apply_mode", m)                      # (a layer above: hud_controls)
	view_changed.emit(m)
	if id == -1:
		nest_view.focus("queen")
		ant_tip._select({"kind": "queen"})
	elif outside:
		outworld.follow_ant(id)
		ant_tip._select({"kind": "worker", "w": w})
	else:
		nest_view.follow_ant(id)
		ant_tip._select({"kind": "worker", "w": w})
	_star_follow = id
	_star_out = outside


## The ant the camera was sent after goes in or out through the entrance: the other view takes it up. The keeper
## moved the camera (the view stopped following): that is the end of it.
func _tick_stars() -> void:
	# the ant's info box beside a panel open on the left (the enemy panel or this one), not over it
	var left: Control = _stars if _stars.visible else (_enemies if _enemies.visible else null)
	ant_tip.position.x = (left.position.x + left.size.x + 12.0) if left != null else 18.0
	if _star_follow < 0:
		return
	var w = _worker(_star_follow)
	if w == null:
		_star_follow = -2
		return
	if outworld.follow_wid == _star_follow or nest_view.follow_wid == _star_follow:
		return
	var out: bool = sim.outside.has(w)
	if out != _star_out:
		go_to_ant(_star_follow)
	else:
		_star_follow = -2
