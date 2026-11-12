extends RefCounted
## Dev options for looking at a fight and the windows of v0.13.3 (kept out of dev_tools.gd, at its size limit):
##   --enemy-state=back|dying   the enemy staged with --enemy turned over now (held there) / in its death throes
##   --album                    the album open, as the queen's sketch opens it


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
	if o.has("album"):
		d.hud.open_album()
