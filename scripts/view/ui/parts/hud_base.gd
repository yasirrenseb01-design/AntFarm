extends CanvasLayer
## Keeper's instrument panel: clock and speed on top, tools at the bottom, colony readout,
## nest cross-section, population chart and journal on the right.
## HUD, layer 1 of 7: state, colours, the theme and small widget helpers.
## Layers: hud_base <- hud_colonies <- hud_enemies <- hud_stars <- hud_controls <- hud_panel <- hud.
const Ant := preload("res://scripts/sim/ant.gd")
const Kit := preload("res://scripts/view/ui/draw_kit.gd")
const Store := preload("res://scripts/game/save_store.gd")
const SpeciesWindow := preload("res://scripts/view/ui/species_window.gd")
const Paper := preload("res://scripts/view/ui/paper.gd")
const FoodKinds := preload("res://scripts/sim/food_kinds.gd")
const T := preload("res://scripts/sim/text_th.gd")
const L := preload("res://scripts/sim/lang.gd")

signal speed_changed(speed: float)
signal view_changed(mode: String)
signal colony_new(slot: int, nest_kind: String)
signal colony_play(slot: int)
signal settings_changed(settings: Dictionary)
signal language_changed(lang: String)     # the keeper picked another language: main.gd saves and starts the scene again
signal save_requested
signal cam_action(action: String)
signal desktop_requested               # the keeper wants the nest as the desktop wallpaper (game/desktop_mode.gd)
signal menu_requested                  # back to the title screen (game/title.gd)
signal harmony_spent(points: float)     # Colony Harmony points paid for something (main.gd takes them from the purse)

var PANEL_W := 352.0             # the side panel (wider in English: its words are longer; hud.setup)
const INK := Color("f1e6d6")
const MUTED := Color("b09a83")
const AMBER := Color("e9a23b")
const LEAF := Color("9cc565")
const DANGER := Color("e8664f")
const BG := Color(0.1, 0.075, 0.055, 0.92)
const LINE := Color(0.3, 0.22, 0.16)

var sim
var ground                     # the outworld's ground_data.gd: the keeper's tool, trails shown or not
var _vals := {}
var _log: RichTextLabel
var _hum_bar: ProgressBar
var _nest: Control
var _chart: Control
var _clock: Label
var _weather: Label
var _mono: SystemFont
var _display: SystemFont
var _t := 0.0
var _frame := 0
var current_slot := 1
var settings := {}
var home                       # game/home_store.gd: which slots are the Home's tanks and which the wild mode's (main sets it)
var _colonies: Window
var _settings_win: Window
var _paper_theme: Theme         # the windows: the field notebook (ui/paper.gd)
var _colonies_body: PanelContainer
var _report: AcceptDialog
var _proj_tex: ImageTexture
var _proj_air := -1
var _spots_t := -10.0
var _crop := Rect2i(0, 0, 1, 1)
var nest_view
var outworld
var ant_tip                 # ui/ant_tip.gd
var _chime: AudioStreamPlayer
var _fps_label: Label
var _dev_speed_buttons: Array = []   # 20× 50× 100× (F10)
var real_speed := 0.0               # the speed the game is really running at (set by main)
var harmony := -1.0                 # the keeper's Colony Harmony points (set by main; below 0: not shown)
var _harmony_row: HBoxContainer
var _harmony_tab: PanelContainer      # the points, on a tab hung under the top bar (hud_controls._join_tab)
var _harmony_l: Label
var music                   # ui/music.gd (null in test runs)
var _outside_tools: Array = []
var _cut_row: HBoxContainer
var _xray_btn: Button
var _cut_slider: HSlider
var _cam_outside: Array = []
var _cam_nest: Array = []
var _hint: Label
var _log_dirty := true
var _view_btns := {}
var _cam_3d: Array = []          # rotate buttons: both 3D views
var _cam_out: Array = []
var _top: PanelContainer         # the top bar
var _top_row: HBoxContainer      # ... its row (tighter on a narrow window)
var guide_targets := {}          # what the first-colony guide points at (ui/guide.gd): name -> Control
var _tools_bar: PanelContainer   # the tool bar at the bottom
var _top_title: Control          # ... the species and the box, left out on a window too narrow for it all
var _side: PanelContainer        # the side panel (folds away: set_side_open)
var _side_tab: Button            # what is left of it folded: a tab to fold it out again
var _cam_pad: PanelContainer     # the camera buttons (move right while the side panel is folded)
var _stars: PanelContainer       # the star ants panel (hud_stars.gd; the enemy panel closes it: one on the left at a time)


# ---------------------------------------------------------------- theme

func _box(bg: Color, border: Color, radius: int, pad_h: int, pad_v: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	sb.content_margin_top = pad_v
	sb.content_margin_bottom = pad_v
	sb.anti_aliasing = true
	return sb


func _make_theme() -> Theme:
	var th := Theme.new()
	var body := SystemFont.new()
	body.font_names = PackedStringArray(["Leelawadee UI", "Segoe UI", "Tahoma"])
	_mono = SystemFont.new()
	_mono.font_names = PackedStringArray(["Cascadia Mono", "Consolas", "Leelawadee UI"])
	_display = SystemFont.new()
	_display.font_names = PackedStringArray(["Bahnschrift", "Leelawadee UI"])
	_display.font_weight = 600
	th.default_font = body
	th.default_font_size = 14
	th.set_stylebox("panel", "PanelContainer", _box(BG, LINE, 10, 14, 12))
	# dialogs (time-away report, confirmations) in the same dark keeper's-panel look
	for cls in ["AcceptDialog", "ConfirmationDialog", "PopupPanel"]:
		th.set_stylebox("panel", cls, _box(Color(0.1, 0.075, 0.055, 0.98), LINE, 10, 16, 14))
	th.set_stylebox("embedded_border", "Window", _box(Color(0.14, 0.1, 0.075), LINE, 10, 10, 32))
	th.set_color("title_color", "Window", INK)
	th.set_font("title_font", "Window", body)
	th.set_stylebox("normal", "OptionButton", _box(Color(0.17, 0.13, 0.1), LINE, 6, 10, 5))
	th.set_stylebox("normal", "MenuButton", _box(Color(0.17, 0.13, 0.1), LINE, 6, 10, 5))
	th.set_color("font_color", "MenuButton", INK)
	th.set_color("font_color", "CheckBox", INK)
	for st in ["normal", "pressed", "hover", "hover_pressed", "focus"]:
		th.set_stylebox(st, "CheckBox", StyleBoxEmpty.new())
	th.set_color("font_pressed_color", "CheckBox", INK)
	# (the engine's own boxes are dark grey: unticked, one could not be seen on these dark panels)
	th.set_icon("unchecked", "CheckBox", _check_icon(false))
	th.set_icon("checked", "CheckBox", _check_icon(true))
	th.set_color("font_hover_pressed_color", "CheckBox", INK)
	th.set_stylebox("normal", "Button", _box(Color(0.17, 0.13, 0.1), LINE, 6, 10, 5))
	th.set_stylebox("hover", "Button", _box(Color(0.22, 0.17, 0.12), MUTED, 6, 10, 5))
	th.set_stylebox("pressed", "Button", _box(AMBER, AMBER, 6, 10, 5))
	th.set_stylebox("hover_pressed", "Button", _box(AMBER.lightened(0.1), AMBER, 6, 10, 5))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", INK)
	th.set_color("font_hover_color", "Button", INK)
	th.set_color("font_pressed_color", "Button", Color("1d140b"))
	th.set_color("font_hover_pressed_color", "Button", Color("1d140b"))
	th.set_color("font_color", "Label", INK)
	th.set_stylebox("background", "ProgressBar", _box(Color(0.06, 0.045, 0.035), LINE, 4, 0, 0))
	th.set_stylebox("fill", "ProgressBar", _box(Color("5d9bd6"), Color("5d9bd6"), 4, 0, 0))
	th.set_constant("separation", "HBoxContainer", 8)
	th.set_constant("separation", "VBoxContainer", 8)
	return th


## A tick box for the theme: an outline (off) or an amber box with a tick (on).
static func _check_icon(on: bool) -> ImageTexture:
	var n := 18
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in n:
		for x in n:
			var edge := x <= 1 or y <= 1 or x >= n - 2 or y >= n - 2
			if on:
				img.set_pixel(x, y, AMBER)
			elif edge:
				img.set_pixel(x, y, MUTED)
	if on:
		# the tick: down from the left, then up to the right
		for t in 30:
			var u := t / 29.0
			var p := Vector2(4, 9).lerp(Vector2(7.5, 13), u * 2.0) if u < 0.5 else Vector2(7.5, 13).lerp(Vector2(14, 5), (u - 0.5) * 2.0)
			for dy in [-1, 0, 1]:
				for dx in [0, 1]:
					var q := Vector2i(int(p.x) + dx, int(p.y) + dy)
					if q.x >= 0 and q.y >= 0 and q.x < n and q.y < n:
						img.set_pixel(q.x, q.y, Color(0.12, 0.08, 0.05))
	return ImageTexture.create_from_image(img)


## (moved from hud.gd in v0.11.52: the panels below it use it too) 12345 -> "12,345"
static func _thousands(n: int) -> String:
	var t := str(absi(n))
	var out := ""
	while t.length() > 3:
		out = "," + t.substr(t.length() - 3) + out
		t = t.substr(0, t.length() - 3)
	return ("-" if n < 0 else "") + t + out


## The Colony Harmony points' icon (the keeper's drop of honey, 2026-10-27: assets/ui/harmony.png) at px high.
static func harmony_icon(px: float) -> TextureRect:
	var t := TextureRect.new()
	t.texture = load("res://assets/ui/harmony.png")
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(px, px)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


## Words with the points' icon before them.
static func with_harmony_icon(l: Label, px: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.add_child(harmony_icon(px))
	row.add_child(l)
	return row


func _label(text: String, size := 14, color := INK, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if font:
		l.add_theme_font_override("font", font)
	return l


func _button(text: String, toggle: bool, group: ButtonGroup = null) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.button_group = group
	b.focus_mode = Control.FOCUS_NONE
	return b


func _tz_offset() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60


func _section(parent: Control, title: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.add_child(_label(title.to_upper(), 12, MUTED, _display))
	parent.add_child(box)
	return box


func _show(l: Label, text: String, color := INK) -> void:
	l.text = text
	l.add_theme_color_override("font_color", color)


# ---------------------------------------------------------------- nest cross-section

func _seeded(i: int, s: int) -> float:
	var x := sin(i * 12.9898 + s * 78.233) * 43758.5453
	return x - floor(x)
