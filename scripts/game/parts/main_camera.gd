extends "res://scripts/game/parts/main_base.gd"
## Game, layer 2 of 4: the HUD's camera buttons for both 3D views (the top-down 2D view and its camera: gone v0.11.5).


## Camera buttons on the HUD, shared by both views.
func _cam_action(a: String) -> void:
	if mode == "outworld":
		match a:
			"zoom_in": outworld.zoom_by(1.0 / 1.4)
			"zoom_out": outworld.zoom_by(1.4)
			"left": outworld.turn_by(0.5)
			"right": outworld.turn_by(-0.5)
			"reset": outworld.reset_view()
			"top": outworld.top_down()
			"nest": outworld.focus_nest()
	else:
		match a:
			"zoom_in": nest_view.zoom_by(1.0 / 1.4)
			"zoom_out": nest_view.zoom_by(1.4)
			"left": nest_view.turn_by(0.5)
			"right": nest_view.turn_by(-0.5)
			"reset": nest_view.reset_view()
			_: nest_view.focus(a)
