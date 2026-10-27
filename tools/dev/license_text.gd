extends SceneTree
## Writes the engine's licence and the third-party notices it carries (Godot is MIT: its notice goes with the game) to
## the file given, for the release zip (tools/package.ps1).
##   godot --headless --path . --script res://tools/dev/license_text.gd -- <out.txt>

func _init() -> void:
	var out := OS.get_cmdline_user_args()[0]
	var lines := ["AntFarm is made with the Godot Engine (https://godotengine.org).", "", Engine.get_license_text(), "",
		"Third-party components in the Godot Engine:", ""]
	for c in Engine.get_copyright_info():
		lines.append("- %s" % c.name)
		for p in c.parts:
			lines.append("    files: %s" % ", ".join(p.files))
			for cr in p.copyright:
				lines.append("    (c) %s" % cr)
			lines.append("    license: %s" % p.license)
	lines.append("")
	var lic := Engine.get_license_info()
	for k in lic:
		lines.append("---- %s ----" % k)
		lines.append(String(lic[k]))
		lines.append("")
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	print("written ", out)
	quit()
