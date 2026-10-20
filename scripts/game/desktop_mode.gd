extends Node
## Desktop mode (PART 11): the nest as the desktop wallpaper, behind the icons. The game's window is put into the
## shell's wallpaper layer by a small Win32 helper (tools/desktop/antdesk.cs -> AntDesk.exe next to the game), the
## HUD is hidden, the frame rate is held at 30, and while a maximized or full-screen app covers the desktop nothing is
## drawn (the colony lives on). An ant icon in the system tray switches back to the game (a click) or quits (its menu);
## back in the game the window is as the keeper had it before the wallpaper button (`--win`, passed on by main.gd when
## the game starts itself again with Direct3D 12), framed and closable.
## main.gd owns it: enter() / leave(), `hidden` (skip the views' work), close() (quit, out of the wallpaper first).
##
## The helper is always run in a thread, never on the main thread: changing the game's window from another process
## sends messages to the thread that owns the window, and that thread waiting for the helper to finish was a deadlock
## (the game froze as it became the wallpaper).

signal failed(message: String)       # it could not become the wallpaper: why (main.gd tells the keeper)

const FPS := 30                      # frames a second as the wallpaper (a calm scene; the game window runs at the screen's rate)
const COVER_CHECK := 2.0             # seconds between looks at whether an app covers the desktop

var on := false                      # the window is the wallpaper
var hidden := false                  # ... and an app covers it: nothing to draw
var check_cover := true              # (dev --no-cover-check: draw even under a full-screen app)
var main: Node                       # (main.gd: hud, the views)
var _tray: StatusIndicator
var _menu: PopupMenu
var _saved := {}                     # the game window as it was, to put back
var _hwnd := 0
var _cover_t := 0.0
var _job: Thread                     # the helper running (one at a time)
var _job_kind := ""                  # "attach", "detach", "quit" (detach, then quit) or "covered"
var _job_out := []                   # [exit code, output] once done (set by the thread)
var _job_mutex := Mutex.new()
var _started_win_used := false       # (--win: the game window from before the restart, used the first time only)


func setup(m: Node) -> void:
	main = m
	_tray = StatusIndicator.new()
	_tray.icon = _ant_icon()
	_tray.tooltip = tr("tray_tooltip")
	_tray.visible = false
	_tray.pressed.connect(func(button: int, _at: Vector2i):
		if button == MOUSE_BUTTON_LEFT:
			leave())                             # (a click on the ant: back to the game; the right button opens the menu)
	_menu = PopupMenu.new()
	_menu.add_item(tr("tray_back"), 0)
	_menu.add_item(tr("tray_quit"), 1)
	_menu.id_pressed.connect(_on_menu)
	add_child(_menu)
	add_child(_tray)
	_tray.menu = _tray.get_path_to(_menu)


## The helper next to the game (exported) or in the project's build folder (running from the editor).
func _helper() -> String:
	for dir in [OS.get_executable_path().get_base_dir(), ProjectSettings.globalize_path("res://build")]:
		var p: String = dir.path_join("AntDesk.exe")
		if FileAccess.file_exists(p):
			return p
	return ""


## Whether desktop mode can be used here (Windows, the helper found).
func available() -> bool:
	return OS.get_name() == "Windows" and _helper() != ""


## Becomes the wallpaper (the helper attaches the window; `failed` if it cannot).
func enter() -> void:
	if on or _job != null:
		return
	if not available():
		failed.emit(tr("desk_no_helper") if OS.get_name() == "Windows" else tr("desk_windows_only"))
		return
	_saved = {"mode": DisplayServer.window_get_mode(), "pos": DisplayServer.window_get_position(),
		"size": DisplayServer.window_get_size(), "borderless": DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS),
		"fps": Engine.max_fps}
	var was: PackedStringArray = String(main._opts.get("win", "")).split(",")
	if was.size() == 5 and not _started_win_used:
		# started again for the wallpaper: the window to go back to is the one the keeper had in the game before
		_started_win_used = true
		_saved.pos = Vector2i(int(was[0]), int(was[1]))
		_saved.size = Vector2i(maxi(640, int(was[2])), maxi(400, int(was[3])))
		_saved.mode = int(was[4])
		_saved.borderless = false
	var screen := DisplayServer.get_primary_screen()
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_position(DisplayServer.screen_get_position(screen))
	DisplayServer.window_set_size(DisplayServer.screen_get_size(screen))
	_hwnd = DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE)
	main.hud.visible = false
	_run("attach", ["attach", str(_hwnd)])


## Back to the game window.
func leave() -> void:
	if not on:
		return
	_wait_job()
	_run("detach", ["detach", str(_hwnd)])


## The game is closing: out of the wallpaper layer first (else its last frame stays on the desktop until the
## wallpaper is next repainted), then quit. Returns true if it will quit by itself once that is done.
func close() -> bool:
	if not on:
		return false
	_wait_job()
	_run("quit", ["detach", str(_hwnd)])
	return true


func _on_menu(id: int) -> void:
	match id:
		0:
			leave()
		1:
			main._save_now()
			if not close():
				get_tree().quit()


func _run(kind: String, args: Array) -> void:
	_job_kind = kind
	_job_out = []
	_job = Thread.new()
	_job.start(_exec.bind(_helper(), args))


func _exec(helper: String, args: Array) -> void:
	var out := []
	var code := OS.execute(helper, args, out, true)
	_job_mutex.lock()
	_job_out = [code, "".join(out).strip_edges()]
	_job_mutex.unlock()


## Waits for the helper job running now (only a quick "covered" look can be running when this is called).
func _wait_job() -> void:
	if _job != null:
		_job.wait_to_finish()
		_job = null
		_job_kind = ""


func _process(delta: float) -> void:
	if _job != null:
		_job_mutex.lock()
		var res := _job_out
		_job_mutex.unlock()
		if not res.is_empty():
			_job.wait_to_finish()
			_job = null
			var kind := _job_kind
			_job_kind = ""
			_done(kind, int(res[0]), String(res[1]))
	if not on:
		return
	# whether an app covers the desktop (the helper looks; it takes a few tens of milliseconds)
	_cover_t += delta
	if _cover_t >= COVER_CHECK and _job == null and check_cover:
		_cover_t = 0.0
		_run("covered", ["covered"])


func _done(kind: String, code: int, out: String) -> void:
	match kind:
		"attach":
			_log("window %d attach -> %d %s; window size %s, viewport %s, driver %s" % [_hwnd, code, out, DisplayServer.window_get_size(),
				get_viewport().get_visible_rect().size, RenderingServer.get_current_rendering_driver_name()])
			if code != 0:
				_restore_window()
				main.hud.visible = true
				failed.emit(tr("desk_failed") % out)
				return
			on = true
			hidden = false
			Engine.max_fps = FPS
			get_tree().auto_accept_quit = false        # (closing: out of the wallpaper first - close())
			_tray.visible = true
			_cover_t = 0.0
		"detach":
			on = false
			get_tree().auto_accept_quit = true
			_set_hidden(false)
			_restore_window()
			main.hud.visible = true
			_tray.visible = false
			DisplayServer.window_move_to_foreground()
			_log("window %d detach -> %d %s; back to mode %d at %s size %s (wanted %s)" % [_hwnd, code, out,
				DisplayServer.window_get_mode(), DisplayServer.window_get_position(), DisplayServer.window_get_size(), _saved])
		"quit":
			on = false
			get_tree().quit()
		"covered":
			if on:
				_set_hidden(out == "1")


## What desktop mode did (printed, and kept in user://desktop_mode.log: started again with D3D12, the game has no
## console to print to).
func _log(line: String) -> void:
	print("desktop mode: " + line)
	var f := FileAccess.open("user://desktop_mode.log", FileAccess.READ_WRITE if FileAccess.file_exists("user://desktop_mode.log") else FileAccess.WRITE)
	if f != null:
		f.seek_end()
		f.store_line("%s %s" % [Time.get_datetime_string_from_system(), line])


func _restore_window() -> void:
	if _saved.is_empty():
		return
	Engine.max_fps = int(_saved.fps)
	# the frame back first: set the flag both ways so the engine works the window's style out again (the helper changed
	# it behind the engine's back, which still thought it borderless: no title bar, v0.11.0). Only then windowed and the
	# old size: a borderless window over the whole screen the engine takes for full screen (mode 4), and while it is
	# borderless it stays so and ignores a new size (came back framed but maximized - tested on Windows, v0.11.4)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, bool(_saved.borderless))
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(_saved.size)
	DisplayServer.window_set_position(_saved.pos)
	if int(_saved.mode) != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(int(_saved.mode))


## Covered by an app: nothing is drawn and the views' work is skipped (the simulation goes on), at a few frames a
## second; back to 30 when the desktop shows again.
func _set_hidden(h: bool) -> void:
	if h == hidden:
		return
	hidden = h
	_log("covered by an app: not drawing" if h else "desktop showing again: drawing")
	RenderingServer.render_loop_enabled = not h
	Engine.max_fps = 10 if h else FPS


func _exit_tree() -> void:
	if _job != null:
		_job.wait_to_finish()
		_job = null


## A small dark ant on a light disc for the tray (no image file needed).
static func _ant_icon() -> ImageTexture:
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var body := Color(0.16, 0.1, 0.06)
	var bg := Color(0.95, 0.78, 0.45)
	var parts := [[Vector2(16, 16), 15.0, bg], [Vector2(10, 16), 5.5, body], [Vector2(16.5, 16), 3.2, body], [Vector2(22, 16), 3.6, body]]
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5)
			for part in parts:
				var c: Vector2 = part[0]
				var d := (p - c) / Vector2(1.0, 0.8 if part[2] == body else 1.0)
				if d.length() <= float(part[1]):
					img.set_pixel(x, y, part[2])
			# legs: three thin lines each side of the thorax
			for k in 3:
				var lx := 13.5 + k * 3.0
				if absf(p.x - (lx + (absf(p.y - 16.0) - 3.0) * 0.4 * (k - 1))) < 0.6 and absf(p.y - 16.0) > 2.5 and absf(p.y - 16.0) < 8.0:
					img.set_pixel(x, y, body)
	return ImageTexture.create_from_image(img)
