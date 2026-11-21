extends PanelContainer
## The developer's tab (PART 0.14 step 8, the keeper 2026-11-21: "call up the enemies' or the ants' movements in the
## game at once, without waiting for the moment or playing a save up to it"). Only on the developer's machine
## (game/dev_machine.gd); words lang/strings.csv dev_*.
##   - the title page's last word, "Developer": a page to start the playground (dev/dev_play.gd) - a keeper's tank or
##     the wild plot, how many workers; the colony open now is saved first, the playground never is
##   - in the playground: this panel (the menu button shows and hides it) - each enemy let in from an edge, as the
##     keeper's or a wild one comes, or straight by the nest; for each one in: the camera after it, turned on its back,
##     a panicked rush, made to flee, killed (each as the simulation does it itself: flip_over, panic, the hp under
##     flee_at, the hp 0); all of them out; out of the playground. The ants and the scenes: steps 9-10.

const DevPlay := preload("res://scripts/dev/dev_play.gd")
const DevMachine := preload("res://scripts/game/dev_machine.gd")
const Paper := preload("res://scripts/view/ui/paper.gd")
const W := 420.0
const NEAR := 70.0               # px from the nest's entrance an enemy let in "by the nest" comes down

var main
var h                            # the HUD: its widgets and colours
var _list: VBoxContainer
var _rows := {}                  # creature id -> its line
var _shown: Array = [-1]         # the ids the rows were made for
var _t := 0.0


## The title's "Developer" page: a window over the title page (null on a player's machine).
static func title_page(m, parent: Control) -> Control:
	if not DevMachine.is_dev():
		return null
	var h = m.hud
	var p := PanelContainer.new()
	p.theme = h._paper_theme
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 0.5
	p.anchor_bottom = 0.5
	p.offset_left = -W * 0.5
	p.offset_top = -190
	p.visible = false
	parent.add_child(p)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(W, 0)
	col.add_theme_constant_override("separation", 10)
	p.add_child(col)
	var head := HBoxContainer.new()
	var t: Label = h._label(m.tr("dev_title"), 18, Paper.ACCENT, h._display)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var x: Button = h._button("×", false)
	x.pressed.connect(func(): p.visible = false)
	head.add_child(x)
	col.add_child(head)
	col.add_child(h._wrapped(m.tr("dev_play_note"), 12, Paper.PENCIL))
	var pick := {"scen": "keeper", "n": 200}
	col.add_child(h._label(m.tr("dev_scene"), 13, Paper.PENCIL))
	var row := HBoxContainer.new()
	var g := ButtonGroup.new()
	for sc in [["keeper", "dev_scene_keeper"], ["wild", "dev_scene_wild"]]:
		var b: Button = h._button(m.tr(sc[1]), true, g)
		b.button_pressed = sc[0] == pick.scen
		var v: String = sc[0]
		b.pressed.connect(func(): pick.scen = v)
		row.add_child(b)
	col.add_child(row)
	col.add_child(h._label(m.tr("dev_workers"), 13, Paper.PENCIL))
	var row2 := HBoxContainer.new()
	var g2 := ButtonGroup.new()
	for n in DevPlay.SIZES:
		var b: Button = h._button(h._thousands(n), true, g2)
		b.button_pressed = n == pick.n
		var v: int = n
		b.pressed.connect(func(): pick.n = v)
		row2.add_child(b)
	col.add_child(row2)
	var go: Button = h._button(m.tr("dev_play_start"), false)
	go.pressed.connect(func(): DevPlay.start(m, pick.scen, pick.n))
	col.add_child(go)
	if m._opts.has("dev-play-go") and not DevPlay.auto_done:     # (dev: --dev-play-go - the button pressed after 3 s, once)
		DevPlay.auto_done = true
		m.get_tree().create_timer(3.0).timeout.connect(func(): go.pressed.emit())
	return p


## In the playground: built on the HUD (title.gd setup), shown at once.
func setup(m) -> void:
	main = m
	h = m.hud
	theme = h._paper_theme
	offset_left = 272                # (right of the colony's panel, clear of the middle: the camera puts an enemy followed there)
	offset_top = 118
	h.add_child(self)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(W, 0)
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	var head := HBoxContainer.new()
	var t: Label = h._label(tr("dev_play_title"), 16, Paper.ACCENT, h._display)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var hide_b: Button = h._button("×", false)
	hide_b.tooltip_text = tr("dev_hide_tip")
	hide_b.pressed.connect(func(): visible = false)
	head.add_child(hide_b)
	col.add_child(head)
	col.add_child(h._label(tr("dev_enemies"), 13, Paper.PENCIL))
	var sim = m.sim
	for kind in sim.ENEMY_KINDS:
		var r := HBoxContainer.new()
		var n: Label = h._label(h._cap(tr(sim.ENEMY_KINDS[kind].NAME)), 14, Paper.INK)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(n)
		var k: String = kind
		var edge: Button = h._button(tr("dev_from_edge"), false)
		edge.pressed.connect(func(): _let_in(k, false))
		r.add_child(edge)
		var near: Button = h._button(tr("dev_by_nest"), false)
		near.pressed.connect(func(): _let_in(k, true))
		r.add_child(near)
		col.add_child(r)
	col.add_child(HSeparator.new())
	col.add_child(h._label(tr("dev_in_now"), 13, Paper.PENCIL))
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	col.add_child(_list)
	var foot := HBoxContainer.new()
	var all_out: Button = h._button(tr("en_remove"), false)
	all_out.pressed.connect(func(): main.sim.remove_enemies())
	foot.add_child(all_out)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(gap)
	var out: Button = h._button(tr("dev_leave"), false)
	out.pressed.connect(func(): DevPlay.leave(main))
	foot.add_child(out)
	col.add_child(foot)
	# (dev, for shots: --dev-let-in=<kind>[,nest] after a second, then --dev-act=<follow|flip|panic|flee|kill> on it after 3 s)
	if m._opts.has("dev-leave-after"):          # (dev: --dev-leave-after=<s> - out of the playground then)
		get_tree().create_timer(float(m._opts["dev-leave-after"])).timeout.connect(func(): DevPlay.leave(main))
	if m._opts.has("dev-let-in"):
		get_tree().create_timer(1.0).timeout.connect(_dev_shot)


func _dev_shot() -> void:
	var li: PackedStringArray = String(main._opts["dev-let-in"]).split(",")
	_let_in(li[0], li.size() > 1)
	if main._opts.has("dev-act"):
		var id := int(main.sim.creatures[-1].id)
		get_tree().create_timer(3.0).timeout.connect(func(): _act(id, String(main._opts["dev-act"])))


## An enemy in now: from an edge (as one comes by itself), or put down by the nest's entrance heading for it.
func _let_in(kind: String, by_nest: bool) -> void:
	var sim = main.sim
	sim._spawn_creature(kind)
	var c: Dictionary = sim.creatures[-1]
	c["released"] = true                     # (a night hunter stays by day: it is here to be watched)
	if by_nest:
		var a: float = sim.rng.randf() * TAU      # (drawn on the colony's generator: a playground is never saved)
		c.pos = (sim.nest_pos + Vector2.from_angle(a) * NEAR).clamp(Vector2(40, 40), sim.WORLD - Vector2(40, 40))
		c.ang = (sim.nest_pos - c.pos).angle()
		c["in_box"] = true
		c["was_in"] = true
	main.hud.enemy_watch.emit(int(c.id))      # (the camera after it, in the outworld)


func _process(delta: float) -> void:
	if main == null or not visible:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.25
	var sim = main.sim
	var ids: Array = sim.creatures.map(func(c): return int(c.id))
	if ids != _shown:
		_shown = ids
		_rows.clear()
		for ch in _list.get_children():
			ch.queue_free()
		if ids.is_empty():
			_list.add_child(h._label(tr("dev_none"), 12, Paper.PENCIL))
		for c in sim.creatures:
			_list.add_child(_row(c))
	for c in sim.creatures:
		if _rows.has(int(c.id)):
			_rows[int(c.id)].text = _state(c)


func _row(c: Dictionary) -> Control:
	var id := int(c.id)
	var box := VBoxContainer.new()
	var l: Label = h._label(_state(c), 12, Paper.INK)
	_rows[id] = l
	box.add_child(l)
	var r := HBoxContainer.new()
	for act in [["dev_follow", "follow"], ["dev_flip", "flip"], ["dev_panic", "panic"], ["dev_flee", "flee"], ["dev_kill", "kill"]]:
		var b: Button = h._button(tr(act[0]), false)
		var what: String = act[1]
		b.pressed.connect(func(): _act(id, what))
		r.add_child(b)
	box.add_child(r)
	return box


## Done to one enemy, each as the simulation does it itself.
func _act(id: int, what: String) -> void:
	var sim = main.sim
	var c = sim._creature(id)
	if c == null:
		return
	var S: Dictionary = sim.ENEMY_KINDS[c.kind].STATS
	match what:
		"follow":
			main.hud.enemy_watch.emit(id)
		"flip":
			sim.flip_over(c)
		"panic":
			c["panic"] = sim.PANIC_TICKS
		"flee":
			c.hp = minf(float(c.hp), float(S.flee_at) * 0.9)
			c["fleeing"] = true
		"kill":
			c.hp = 0.0                       # (the next step: it rolls over and dies, as when the ants beat it)


func _state(c: Dictionary) -> String:
	var S: Dictionary = main.sim.ENEMY_KINDS[c.kind].STATS
	var st := tr("dev_st_dying") if c.has("dying") else (tr("dev_st_back") if main.sim.on_back(c) else (tr("dev_st_fleeing")
		if c.get("fleeing", false) else (tr("dev_st_panic") if main.sim.panicking(c) else tr("dev_st_hunting"))))
	return tr("dev_enemy_line") % [int(c.id), h._cap(tr(main.sim.ENEMY_KINDS[c.kind].NAME)), maxi(0, int(100.0 * float(c.hp) / float(S.hp))),
		int(c.held), st]
