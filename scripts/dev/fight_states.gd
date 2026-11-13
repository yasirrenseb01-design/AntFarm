extends RefCounted
## Dev options for looking at a fight and the windows of v0.13.3 (kept out of dev_tools.gd, at its size limit):
##   --enemy-state=back|dying|carcass|eat|shake   the enemy staged with --enemy turned over now (held there) / in its death throes /
##                              (a spider) with the nearest ant in its fangs, to feed on (held a long while) or to shake
##   --carcass=<kind>           a carcass (food kind centipede_dead...) laid at --enemy-at
##   --home-click=<kind>        (with --home) that item of the Home's room clicked after a second
##   --place-rocks=<n>          n stones laid by the keeper at --enemy-at
##   --album                    the album open, as the queen's sketch opens it
##   --click-sketch             a real mouse click on the queen's sketch after a second; prints whether the album opened


static func apply(d) -> void:
	var o: Dictionary = d._opts
	var st := String(o.get("enemy-state", ""))
	if st != "" and not d.sim.creatures.is_empty():
		var c: Dictionary = d.sim.creatures[-1]
		if st == "dying":
			c.hp = 0.0
		elif st == "carcass":
			c.hp = 0.0
			c["dying"] = 2                      # (dead in a moment: its carcass, torn - v0.13.11)
		elif st == "back":
			d.sim.flip_over(c)
			c.flip = 100000
		elif st == "eat" or st == "shake":
			var SpiderPrey = load("res://scripts/sim/enemies/spider_prey.gd")
			var near = null
			for a in d.sim.outside:
				if not a.dead and a.state != 0 and (near == null or a.pos.distance_to(c.pos) < near.pos.distance_to(c.pos)):
					near = a
			if near != null:
				near.busy = 0
				SpiderPrey.catch_ant(d.sim, c, near)
				c.prey.mode = st
				c.prey.end = 100000 if st == "eat" else 100000
	if o.has("carcass"):
		# --carcass=<food kind> (centipede_dead...): laid at the enemy's spot (--enemy-at), as the ants find it
		var at: PackedStringArray = String(o.get("enemy-at", "200,125")).split(",")
		var cp := Vector2(float(at[0]), float(at[1]))
		print("carcass placed: ", d.sim.place_food(String(o["carcass"]), cp))
		d.outworld.follow_cid = 0
		d.outworld.target_t = d.outworld._on_ground(cp)
	if o.has("home-click"):
		# --home-click=<kind> (with --home): that item of the Home's room clicked after a second (notebook, lamp...)
		d.get_tree().create_timer(1.0).timeout.connect(func():
			for it in d.home_room._room.items:
				if it.kind == String(o["home-click"]):
					d.home_room._click(it)
					print("home-click: ", it.kind)
					return)
	if o.has("place-rocks"):
		# --place-rocks=<n>: n stones laid by the keeper in a row at --enemy-at (their three kinds: rock_mesh.gd)
		var at: PackedStringArray = String(o.get("enemy-at", "120,90")).split(",")
		var p0 := Vector2(float(at[0]), float(at[1]))
		for i in int(o["place-rocks"]):
			d.sim.add_rock(p0 + Vector2((i % 4) * 26.0, (i / 4) * 26.0), 9.0 + (i % 3) * 2.0, true)
		d.outworld.follow_cid = 0
		d.outworld.target_t = d.outworld._on_ground(p0 + Vector2(39, 13))
	if o.has("look-nest"):
		d.outworld.focus_nest()                 # --look-nest: the camera on the nest's crater (at --dist)
		d.outworld.dist_t = float(o.get("dist", 60.0))
	if o.has("album"):
		d.hud.open_album()
	if o.has("select-queen"):
		d.hud.ant_tip._select({"kind": "queen"})    # (the queen's card open, as clicked - her character on it: v0.13.9)
	if o.has("click-sketch"):
		d.get_tree().create_timer(1.0).timeout.connect(func(): _click_sketch(d))


static func _click_sketch(d) -> void:
	var b: Control = null
	for n in d.hud.find_children("*", "TextureButton", true, false):
		if (n as Control).tooltip_text == d.tr("album_tip"):
			b = n
	if b == null:
		print("click-sketch: no sketch button")
		return
	var at: Vector2 = b.get_global_rect().get_center()
	print("click-sketch: button at ", b.get_global_rect(), " visible ", b.is_visible_in_tree())
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = at
		e.global_position = at
		d.get_viewport().push_input(e)
	d.get_tree().create_timer(0.5).timeout.connect(func():
		var open := false
		for w in d.get_tree().root.find_children("*", "Window", true, false):
			if w.get_script() != null and String(w.get_script().resource_path).ends_with("album.gd"):
				open = true
		print("click-sketch: album open ", open, " hovered ", d.get_viewport().gui_get_hovered_control()))
