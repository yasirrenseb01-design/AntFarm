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
	# the C++ part (bin/ant_native.*.dll, v0.12.6) is built with godot-cpp (MIT) and the llvm-mingw toolchain's runtime
	# (LLVM's libc++: Apache 2.0 with the LLVM exception - no notice needed for compiled code; mingw-w64's runtime: permissive)
	var gc := FileAccess.get_file_as_string("res://native/GODOT_CPP_LICENSE.md")
	if gc != "":
		lines += ["---- godot-cpp (in ant_native.windows.template_release.x86_64.dll) ----", gc, ""]
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	print("written ", out)
	quit()
