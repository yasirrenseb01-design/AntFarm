extends SceneTree
## Writes the pencil sounds (view/ui/paper.gd) to user://pencil_<n>.wav to listen to.
##   godot --headless --path . --script res://tests/pencil_dump.gd
func _init():
	var Paper = load("res://scripts/view/ui/paper.gd")
	for k in 3:
		var s: AudioStreamWAV = Paper._scribble(101 + k)
		s.save_to_wav("user://pencil_%d.wav" % k)
		print("pencil %d: %.2f s" % [k, s.data.size() / 2.0 / s.mix_rate])
	quit()
