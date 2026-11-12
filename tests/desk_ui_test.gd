extends SceneTree
## The desk look's widgets do what their buttons did (v0.13.2, the keeper's picture): a click on each speed's segment of
## the brass dial (ui/desk_dial.gd) and on its word picks that speed; a click off the dial picks nothing; a developer
## speed pegs it past 5×; a click on each half of the leather strap (ui/desk_controls.gd) picks that view, once.
##   godot --headless --path . --script res://tests/desk_ui_test.gd     -> "DESK UI TEST PASSED"
func _init():
	var Dial = load("res://scripts/view/ui/desk_dial.gd")
	var Ctl = load("res://scripts/view/ui/desk_controls.gd")
	var ok := true
	var d = Dial.new()
	d.size = Vector2(206, 108)
	var got := []
	d.picked.connect(func(v): got.append(v))
	var c: Vector2 = d._centre()
	var r: float = d._radius()
	for i in d.speeds.size():
		var a: float = d._angle_of(i)
		for rr in [r * 0.75, r + 14.0]:            # (on its segment, on its word)
			got.clear()
			_click(d, c + Vector2(cos(a), -sin(a)) * rr + Vector2(0, -1))
			if got != [d.speeds[i]]:
				print("dial: a click at stop %d (radius %.0f) gave %s" % [i, rr, str(got)])
				ok = false
	got.clear()
	_click(d, c + Vector2(0, 20))                  # under the dial
	_click(d, Vector2(2, 2))                       # its corner, far off
	if not got.is_empty():
		print("dial: clicks off it gave ", got)
		ok = false
	d.show_speed(50.0)
	ok = ok and d._index() == -1 and d._target() < 0.0
	var s = Ctl.ViewStrap.new()
	s.size = Vector2(206, 40)
	var views := []
	s.chosen.connect(func(m): views.append(m))
	_click(s, Vector2(160, 20))
	_click(s, Vector2(170, 20))                    # (the same half again: nothing)
	_click(s, Vector2(30, 20))
	if views != ["nest", "outworld"]:
		print("strap: ", views)
		ok = false
	var b = Ctl.SealButton.new("enemy", Color.RED)
	ok = ok and b.get_theme_stylebox("normal") != null
	# the album: plate a at 50 workers, b at 200, each once
	var Album = load("res://scripts/view/ui/album.gd")
	var steps := [Album.newly_won("lasius_niger", 49, []), Album.newly_won("lasius_niger", 50, []),
		Album.newly_won("lasius_niger", 250, ["a"]), Album.newly_won("lasius_niger", 250, ["a", "b"]), Album.newly_won("nobody", 999, [])]
	if steps != [[], ["a"], ["b"], [], []]:
		print("album: ", steps)
		ok = false
	print("dial and strap: %s" % ("as their buttons were" if ok else "WRONG"))
	print("DESK UI TEST PASSED" if ok else "DESK UI TEST FAILED")
	d.free()
	s.free()
	b.free()
	quit()


func _click(w: Control, at: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = at
	w._gui_input(e)
