extends CanvasLayer
## Keeper's instrument panel: clock and speed on top, tools at the bottom, colony readout,
## nest cross-section, population chart and journal on the right.
## HUD, layer 1 of 5: state, colours, the theme and small widget helpers.
## Layers: hud_base <- hud_colonies <- hud_controls <- hud_panel <- hud.
const Ant := preload("res://scripts/sim/ant.gd")
const Kit := preload("res://scripts/view/surface2d/draw_kit.gd")
const Store := preload("res://scripts/game/save_store.gd")
const FoodKinds := preload("res://scripts/sim/food_kinds.gd")

signal speed_changed(speed: float)
signal view_changed(mode: String)
signal colony_new(slot: int, nest_kind: String)
signal colony_play(slot: int)
signal settings_changed(settings: Dictionary)
signal save_requested
signal cam_action(action: String)

const PANEL_W := 352.0
const INK := Color("f1e6d6")
const MUTED := Color("b09a83")
const AMBER := Color("e9a23b")
const LEAF := Color("9cc565")
const DANGER := Color("e8664f")
const BG := Color(0.1, 0.075, 0.055, 0.92)
const LINE := Color(0.3, 0.22, 0.16)

var sim
var world
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
var _colonies: Window
var _colonies_body: PanelContainer
var _confirm: ConfirmationDialog
var _report: AcceptDialog
var _pending := [1, "soil:queen"]
var _proj_tex: ImageTexture
var _proj_air := -1
var _spots_t := -10.0
var _crop := Rect2i(0, 0, 1, 1)
var nest_view
var _surface_tools: Array = []
var _cut_row: HBoxContainer
var _xray_btn: Button
var _cut_slider: HSlider
var _cam_surface: Array = []
var _cam_nest: Array = []
var _hint: Label
var _log_dirty := true
var _view_btns := {}
var _cam_3d: Array = []          # rotate buttons: both 3D views
var _cam_out: Array = []


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
