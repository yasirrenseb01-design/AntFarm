extends Node2D
## Game, layer 1 of 4: state, switching views, saving, and catching up on the time the game was
## closed. Layers: main_base <- main_camera <- dev/dev_tools <- main.
const Sim := preload("res://scripts/sim/simulation.gd")
const WorldView := preload("res://scripts/view/surface2d/world_view.gd")
const Hud := preload("res://scripts/view/ui/hud.gd")
const NestView := preload("res://scripts/view/nest/nest_view.gd")
const OutworldView := preload("res://scripts/view/outworld/outworld_view.gd")
const Store := preload("res://scripts/game/save_store.gd")
const Migrations := preload("res://scripts/sim/save_migrations.gd")

var sim
var world
var hud
var nest_view
var outworld
var mode := "surface"              # "outworld" (3D), "surface" (top-down 2D) or "nest" (3D underground)
static var next_nest := ""      # "<soil|glass>:<queen|young>:<wild|keeper>": start a fresh colony after the reload
static var next_slot := 0       # which save slot to open after the reload (0 = the last one played)
var slot := 1
var _persist := false
var _load_note := ""                # told to the keeper once the HUD is up (a save that could not be used)           # tests and screenshots never touch the player's saves
var _settings := {}
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
var camera: Camera2D
var speed := 1.0
var _acc := 0.0
var _panning := false
var _zoom_t := 1.0
var _pos_t := Vector2.ZERO
var _opts := {}


func _set_mode(m: String) -> void:
	mode = m
	var surface := m == "surface"
	world.visible = surface
	world.set_process_unhandled_input(surface)
	camera.enabled = surface
	outworld.set_active(m == "outworld")
	nest_view.set_active(m == "nest")


# ---------------------------------------------------------------- saving and time away

func _save_now() -> void:
	if _persist and sim != null:
		Store.save(slot, sim)
		_autosave_t = 0.0


## Switch to another slot, or start a fresh colony in one: save the current colony, then reload.
func _go_to(target_slot: int, kind: String) -> void:
	_save_now()
	if kind != "":
		Store.delete(target_slot)
	next_slot = target_slot
	next_nest = kind
	get_tree().reload_current_scene()


## Work out how much game time passed while the game was closed.
func _plan_catchup(meta: Dictionary) -> void:
	var rate := Store.away_rate(int(_settings.get("away", 3)))
	var real_s: float = maxf(0.0, Time.get_unix_time_from_system() - float(meta.get("saved_unix", 0.0)))
	real_s += float(_opts.get("pretend-away", "0")) * 3600.0
	var days := real_s / 3600.0 * rate
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
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(520, 0)
	box.position = get_viewport_rect().size * 0.5 - Vector2(260, 60)
	box.add_theme_constant_override("separation", 12)
	_overlay.add_child(box)
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
	var done := _catchup_total - _catchup_left
	_overlay_label.text = "ระหว่างที่คุณไม่อยู่ รังยังมีชีวิตต่อ…\nกำลังจำลอง %.1f จาก %.1f วันในเกม" % [
		float(done) / sim.TPD, float(_catchup_total) / sim.TPD]
	_overlay_bar.value = 100.0 * done / maxf(1.0, _catchup_total)
	if _catchup_left <= 0:
		sim.ant_substep = 1
		_overlay.queue_free()
		_save_now()
		_report_away()


func _report_away() -> void:
	var b: Dictionary = _away_before
	var a: Dictionary = sim.summary()
	var lines := PackedStringArray()
	lines.append("คุณไม่อยู่ %s → ในรังผ่านไป %.1f วัน (วันที่ %d → %d)%s" % [_hours_text(_away_hours),
		float(_catchup_total) / sim.TPD, b.day, a.day, "\n(จำลองให้สูงสุด %d วันในเกม)" % int(Store.MAX_AWAY_DAYS) if _away_capped else ""])
	lines.append("")
	lines.append("มดงาน  %d → %d   (เกิดใหม่ %d · ตาย %d · ลูกมดตาย %d)" % [b.workers, a.workers, a.born - b.born, a.dead - b.dead,
		int(a.get("brood_dead", 0)) - int(b.get("brood_dead", 0))])
	lines.append("ไข่ %d · ตัวอ่อน %d · ดักแด้ %d" % [a.eggs, a.larvae, a.pupae])
	lines.append("ห้องในรัง  %d → %d   · ปริมาตร %.1f ซม³" % [b.chambers, a.chambers, a.volume])
	lines.append("ความชื้นในรังตอนนี้ %d%%%s" % [int(a.humidity * 100), "  (ควรเติมน้ำ)" if a.humidity < 0.35 else ""])
	if not a.queen:
		lines.append("ราชินีตายระหว่างที่คุณไม่อยู่")
	if not _away_events.is_empty():
		lines.append("")
		lines.append("เรื่องที่เกิดขึ้น:")
		var shown := 0
		for e in _away_events:
			if shown >= 8:
				lines.append("…และอีก %d เรื่อง" % (_away_events.size() - shown))
				break
			lines.append("• %s  %s" % [e.stamp, e.text])
			shown += 1
	hud.show_report("ระหว่างที่คุณไม่อยู่", "\n".join(lines))


func _hours_text(h: float) -> String:
	if h < 1.0:
		return "%d นาที" % int(h * 60.0)
	if h < 48.0:
		return "%.1f ชั่วโมง" % h
	return "%.1f วัน" % (h / 24.0)
