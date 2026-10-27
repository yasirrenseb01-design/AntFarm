extends Node2D
## Game, layer 1 of 4: state, switching views, saving, and catching up on the time the game was
## closed. Layers: main_base <- main_camera <- dev/dev_tools <- main.
const Sim := preload("res://scripts/sim/simulation.gd")
const Hud := preload("res://scripts/view/ui/hud.gd")
const NestView := preload("res://scripts/view/nest/nest_view.gd")
const OutworldView := preload("res://scripts/view/outworld/outworld_view.gd")
const L := preload("res://scripts/sim/lang.gd")
const Store := preload("res://scripts/game/save_store.gd")
const Harmony := preload("res://scripts/game/harmony.gd")
const HomeStore := preload("res://scripts/game/home_store.gd")
var home := HomeStore.new()       # which slots are the Home's tanks and which the wild mode's (home.json)
var harmony := Harmony.new()       # the keeper's Colony Harmony points (one purse for every colony)
var _away_rate := 0.0              # game days per real hour of the time away being worked out
const Title := preload("res://scripts/game/title.gd")
const HomeRoom := preload("res://scripts/game/home.gd")
var home_room                   # game/home.gd: the Home, the room with the tanks
const Graphics := preload("res://scripts/game/graphics.gd")
const SingleInstance := preload("res://scripts/game/single_instance.gd")
const Migrations := preload("res://scripts/sim/save_migrations.gd")

var sim
var hud
var nest_view
var outworld
var mode := "outworld"             # "outworld" (3D, above ground) or "nest" (3D underground)
static var next_nest := ""      # "<soil|glass>:<queen|young>:<wild|keeper>": start a fresh colony after the reload
static var next_slot := 0       # which save slot to open after the reload (0 = the last one played)
static var skip_title := false  # reloaded for another colony from the game: straight into it, not the title screen
var slot := 1
var _persist := false
var _load_note := ""                # told to the keeper once the HUD is up (a save that could not be used)           # tests and screenshots never touch the player's saves
var _settings := {}
var title                       # game/title.gd: the title screen
var one                         # game/single_instance.gd: one game at a time (null in tests)
var _demo := false              # no colony saved yet: the one behind the title screen is only to look at, never saved
var _autosave_t := 0.0
var _catchup_left := 0          # ticks still to simulate for the time the game was closed
var _catchup_total := 0
var _away_before := {}
var _away_events: Array = []
var _away_hours := 0.0
var _away_capped := false
var _overlay: CanvasLayer
var _overlay_label: Label
var _overlay_bar: ProgressBar
var speed := 0.5             # a calm pace to watch the ants by (the HUD offers 0.2× - 5×)
var _acc := 0.0
var _sim_us := 0                 # how long the last frame's simulation took (main.gd: the budget for fast-forward)
var fprof := {}              # dev (--perf): microseconds spent per part of the frame, summed


## Adds the time since t0 to fprof[key]; returns now (the start of the next part).
func _pt(key: String, t0: int) -> int:
	var now := Time.get_ticks_usec()
	fprof[key] = fprof.get(key, 0) + now - t0
	return now
var _opts := {}
## the command-line options the released game keeps (main._ready): the wallpaper restart's own
const RELEASE_OPTS := ["desktop", "win", "slot", "view", "gpu", "desk-driver", "windowed"]


func _set_mode(m: String) -> void:
	mode = m
	outworld.set_active(m == "outworld")
	nest_view.set_active(m == "nest")


# ---------------------------------------------------------------- saving and time away

func _save_now() -> void:
	if _persist and sim != null and not _demo and not _opts.has("testsave"):        # (a grown test colony stays as it was)
		Store.save(slot, sim)
		harmony.save_purse()
		_autosave_t = 0.0


## Switch to another slot, or start a fresh colony in one: save the current colony, then reload.
func _go_to(target_slot: int, kind: String) -> void:
	_save_now()
	if kind != "":
		Store.delete(target_slot)
	next_slot = target_slot
	next_nest = kind
	skip_title = true
	get_tree().reload_current_scene()


## Work out how much game time passed while the game was closed.
func _plan_catchup(meta: Dictionary) -> void:
	if _opts.has("testsave"):
		return
	var rate := Store.away_rate(int(_settings.get("away", 3)))
	var saved = meta.get("saved_unix", 0.0)
	var real_s: float = maxf(0.0, Time.get_unix_time_from_system() - (float(saved) if saved is int or saved is float else 0.0))
	real_s += float(_opts.get("pretend-away", "0")) * 3600.0
	var days := real_s / 3600.0 * rate
	_away_rate = rate
	_away_hours = real_s / 3600.0
	_away_capped = days > Store.MAX_AWAY_DAYS
	days = minf(days, Store.MAX_AWAY_DAYS)
	if days < 0.02:
		return
	_catchup_total = int(days * sim.TPD)
	_catchup_left = _catchup_total
	_away_before = sim.summary()
	sim.logged.connect(_collect_away_event)


func _collect_away_event(e: Dictionary) -> void:
	if _catchup_left > 0 and e.kind != "":
		_away_events.append(e)


func _show_catchup_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 20
	add_child(_overlay)
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.045, 0.035, 0.97)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(bg)
	# (in the middle of the window whatever size it is, now or after: it was placed once from the size at the start,
	# and off to the right in a 1366 x 768 window)
	var mid := CenterContainer.new()
	mid.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(mid)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(520, 0)
	box.add_theme_constant_override("separation", 12)
	mid.add_child(box)
	_overlay_label = Label.new()
	_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_label.add_theme_font_size_override("font_size", 18)
	_overlay_label.add_theme_color_override("font_color", Color("f1e6d6"))
	box.add_child(_overlay_label)
	_overlay_bar = ProgressBar.new()
	_overlay_bar.custom_minimum_size = Vector2(520, 14)
	_overlay_bar.show_percentage = false
	box.add_child(_overlay_bar)


## Simulate the time away in slices that fit in a frame, so the window stays responsive.
func _run_catchup() -> void:
	sim.ant_substep = 4      # fastest stride that stays unbiased against full-detail stepping (tested)
	var care: bool = _settings.get("care", true)
	var t0 := Time.get_ticks_msec()
	while _catchup_left > 0 and Time.get_ticks_msec() - t0 < 40:
		sim.step()
		_catchup_left -= 1
		if care and sim.tick % sim.TPD == sim.TPD / 4:
			sim.auto_care(sim.day())
	_earn(_away_rate, false)
	var done := _catchup_total - _catchup_left
	_overlay_label.text = tr("away_running") % [
		float(done) / sim.TPD, float(_catchup_total) / sim.TPD]
	_overlay_bar.value = 100.0 * done / maxf(1.0, _catchup_total)
	if _catchup_left <= 0:
		sim.ant_substep = 1
		_overlay.queue_free()
		_save_now()
		_report_away()


## Colony Harmony for what the colony did since the last call (not a test colony, nor the one behind the title).
func _earn(game_days_per_hour: float, live: bool) -> void:
	if _persist and not _demo and not _opts.has("testsave") and sim != null:
		harmony.collect(sim, game_days_per_hour, live)


func _report_away() -> void:
	var b: Dictionary = _away_before
	var a: Dictionary = sim.summary()
	var lines := PackedStringArray()
	lines.append(tr("away_summary") % [_hours_text(_away_hours),
		float(_catchup_total) / sim.TPD, b.day, a.day, tr("away_capped") % int(Store.MAX_AWAY_DAYS) if _away_capped else ""])
	lines.append("")
	lines.append(tr("away_workers") % [b.workers, a.workers, a.born - b.born, a.dead - b.dead,
		int(a.get("brood_dead", 0)) - int(b.get("brood_dead", 0))])
	lines.append(tr("away_brood") % [a.eggs, a.larvae, a.pupae])
	lines.append(tr("away_chambers") % [b.chambers, a.chambers, a.volume])
	lines.append(tr("away_humidity") % [int(a.humidity * 100), tr("away_add_water") if a.humidity < 0.35 else ""])
	if not a.queen:
		lines.append(tr("away_queen_died"))
	if not _away_events.is_empty():
		lines.append("")
		lines.append(tr("away_events"))
		var shown := 0
		for e in _away_events:
			if shown >= 8:
				lines.append(tr("away_more") % (_away_events.size() - shown))
				break
			lines.append("• %s  %s" % [sim.L.stamp(e), sim.L.entry_text(e)])
			shown += 1
	if title != null and title.is_open:
		title.pending_report = [tr("away_title"), "\n".join(lines)]     # (shown once the keeper goes on into the game)
	else:
		hud.show_report(tr("away_title"), "\n".join(lines))


func _hours_text(h: float) -> String:
	if h < 1.0:
		return tr("minutes_n") % int(h * 60.0)
	if h < 48.0:
		return tr("hours_n") % h
	return tr("days_n") % (h / 24.0)
