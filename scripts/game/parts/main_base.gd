extends Node2D
## Game, layer 1 of 4: state, switching views, saving, and catching up on the time the game was
## closed. Layers: main_base <- main_camera <- dev/dev_tools <- main.
const OutworldCard := preload("res://scripts/game/outworld_card.gd")
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
var _refill_ticks: Array = []    # ticks into the time away at which the keeper filled the water tank from the Home
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
## the command-line options the released game keeps (main._ready): the wallpaper restart's own; "sandbox": a save folder of
## its own (measuring the released build without the keeper's saves)
const RELEASE_OPTS := ["desktop", "win", "slot", "view", "gpu", "desk-driver", "windowed", "sandbox"]


func _set_mode(m: String) -> void:
	mode = m
	outworld.set_active(m == "outworld")
	nest_view.set_active(m == "nest")


# ---------------------------------------------------------------- saving and time away

var _closing := false           # (the window closing: saved once - main.gd _notification)
var _card_ms := -1000000         # (when the box from above was last drawn for the Home)


## card: the box from above drawn for the Home's tank too (not with the autosave: drawn with the whole scene, 0.1-0.25 s
## - the game stood still that long every minute, the keeper 2026-11-04 "it stutters"; the Home draws it as it opens:
## write_card).
func _save_now(card := true) -> void:
	if _persist and sim != null and not _demo and not _opts.has("testsave"):        # (a grown test colony stays as it was)
		var t0 := Time.get_ticks_msec()
		Store.save(slot, sim)
		var t1 := Time.get_ticks_msec()
		# (closing: not again if drawn in the last ten minutes - the Home drew it as it opened)
		if card and not (_closing and Time.get_ticks_msec() - _card_ms < 600000):
			write_card()
		harmony.save_purse()
		quitdbg("save %d ms, card+purse %d ms" % [t1 - t0, Time.get_ticks_msec() - t1])
		_autosave_t = 0.0


## The box from above for the Home's tank (outworld_card.gd), of the colony open now.
func write_card() -> void:
	if _persist and sim != null and not _demo and not _opts.has("testsave") and sim.scenario != "wild" and outworld != null:
		OutworldCard.write(Store.base + "saves", slot, outworld, nest_view)
		_card_ms = Time.get_ticks_msec()


## (dev: QUITDBG=1 - what quitting takes, step by step, in user://quitdbg.txt with the time: a released build's printing
## is not written out before it ends)
static func quitdbg(what: String) -> void:
	if not OS.has_environment("QUITDBG"):
		return
	var f := FileAccess.open("user://quitdbg.txt", FileAccess.READ_WRITE if FileAccess.file_exists("user://quitdbg.txt") else FileAccess.WRITE)
	if f != null:
		f.seek_end()
		f.store_line("%.3f %s" % [Time.get_unix_time_from_system(), what])
		f.close()


var _going := false             # (a colony being opened: a second click waits)
## Switch to another slot, or start a fresh colony in one: save the current colony, then reload.
func _go_to(target_slot: int, kind: String) -> void:
	if _going:
		return
	_going = true
	# (a page saying so on screen at once, then the work: the Home stood still ~2 s from the click until the time-away
	# page, the colony saved and the scene loaded behind it - the keeper, 2026-11-10, v0.12.30)
	_show_catchup_overlay()
	_overlay_label.text = tr("opening_tank")
	_overlay_bar.visible = false
	await get_tree().process_frame
	await get_tree().process_frame
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
	# the water tank filled from the Home meanwhile: at that moment of the time away (all at once if none is worked out)
	_refill_ticks = []
	var s0: float = float(saved) if saved is int or saved is float else 0.0
	for u in Store.refills(Store.meta(slot)):
		if u >= s0:
			_refill_ticks.append(int(minf(days, (u - s0) / 3600.0 * rate) * sim.TPD))
	if days < 0.02:
		if not _refill_ticks.is_empty():
			sim.add_water()
		_refill_ticks = []
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


var _cu_frames := 0
var _cu_start := 0
var _cu_sim := 0
## Simulate the time away in slices that fit in a frame, so the window stays responsive.
func _run_catchup() -> void:
	sim.ant_substep = 4      # fastest stride that stays unbiased against full-detail stepping (tested)
	hud.quiet = true
	var care: bool = _settings.get("care", true)
	var t0 := Time.get_ticks_msec()
	_cu_frames += 1
	if _cu_start == 0:
		_cu_start = t0
	while _catchup_left > 0 and Time.get_ticks_msec() - t0 < 40:
		sim.step()
		_catchup_left -= 1
		while not _refill_ticks.is_empty() and _catchup_total - _catchup_left >= int(_refill_ticks[0]):
			_refill_ticks.pop_front()
			sim.add_water()                  # (filled from the Home then)
		if care and sim.tick % sim.TPD == sim.TPD / 4:
			sim.auto_care(sim.day())
	_cu_sim += Time.get_ticks_msec() - t0
	_earn(_away_rate, false)
	var done := _catchup_total - _catchup_left
	_overlay_label.text = tr("away_running") % [
		float(done) / sim.TPD, float(_catchup_total) / sim.TPD]
	_overlay_bar.value = 100.0 * done / maxf(1.0, _catchup_total)
	if _catchup_left <= 0:
		if _opts.has("hitch-log"):
			# (dev: where the time away's minutes go)
			var total := Time.get_ticks_msec() - _cu_start
			print("catch-up: %d ticks (%.1f game days) in %.1f s, %d frames; simulating %.1f s (%.0f%%), %.3f ms a tick; the rest %.1f ms a frame" % [_catchup_total, float(_catchup_total) / sim.TPD, total / 1000.0, _cu_frames,
				_cu_sim / 1000.0, 100.0 * _cu_sim / maxf(total, 1.0), float(_cu_sim) / maxf(_catchup_total, 1.0), float(total - _cu_sim) / maxf(_cu_frames, 1.0)])
			print("  workers %d, sim.prof %s" % [sim.workers.size(), str(sim.prof)])
		sim.ant_substep = 1
		hud.quiet = false
		if not _refill_ticks.is_empty():
			sim.add_water()
			_refill_ticks = []
		_overlay.queue_free()
		_report_away()
		# the nest made ready (1-2.5 s in a colony of 800) once the summary is on screen, read meanwhile: before, the full
		# bar stood that long first (the keeper, 2026-11-10: "2-3 seconds"); then saved, the card drawn with the nest ready
		await get_tree().process_frame
		await get_tree().process_frame
		_warm_nest()
		_save_now()


## The nest made ready while the loading is still on screen, so its first opening does not stand still (nest_view.warm).
func _warm_nest() -> void:
	if _persist and not _opts.has("shot") and not _opts.has("no-warm"):        # (--no-warm: dev, measuring without it)
		var t0 := Time.get_ticks_msec()
		nest_view.warm()
		if _opts.has("hitch-log"):
			print("nest made ready in %d ms: slot %d day %d, %d workers, %d drawn in the nest" % [Time.get_ticks_msec() - t0, slot, sim.day(), sim.workers.size(), nest_view._mates.size()])


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
