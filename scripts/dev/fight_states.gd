extends RefCounted
## Dev options for looking at a fight and the windows of v0.13.3 (kept out of dev_tools.gd, at its size limit):
##   --enemy-state=back|dying|eat|shake   the enemy staged with --enemy turned over now (held there) / in its death throes /
##                              (a spider) with the nearest ant in its fangs, to feed on (held a long while) or to shake
##   --album                    the album open, as the queen's sketch opens it
##   --click-sketch             a real mouse click on the queen's sketch after a second; prints whether the album opened


static func apply(d) -> void:
	var o: Dictionary = d._opts
	var st := String(o.get("enemy-state", ""))
	if st != "" and not d.sim.creatures.is_empty():
		var c: Dictionary = d.sim.creatures[-1]
		if st == "dying":
			c.hp = 0.0
		elif st == "back":
			d.sim.flip_over(c)
			c.flip = 100000
		elif (st == "eat" or st == "shake") and c.kind == "wolf_spider":
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
	if o.has("album"):
		d.hud.open_album()
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
