class_name UiTheme
extends RefCounted
## The game's one UI theme, built in code so it is reviewable: Space Grotesk,
## white panels, dark ink, violet for focus and the power.

const INK := Color(0.12, 0.11, 0.18)
const INK_SOFT := Color(0.12, 0.11, 0.18, 0.55)
const PAPER := Color(0.985, 0.985, 0.99, 0.94)
const VIOLET := Color(0.55, 0.24, 1.0)

static var _theme: Theme
static var _bold: FontFile


static func bold() -> Font:
	if _bold == null:
		_bold = load("res://fonts/SpaceGrotesk-Bold.woff")
	return _bold


static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = load("res://fonts/SpaceGrotesk-Medium.woff")
	t.default_font_size = 20
	t.set_color("font_color", "Label", INK)
	# Buttons: white pills, violet when focused or pressed (pad-friendly).
	t.set_stylebox("normal", "Button", _box(PAPER, Color(INK, 0.12), 2))
	t.set_stylebox("hover", "Button", _box(Color(0.95, 0.93, 1.0), Color(VIOLET, 0.6), 2))
	t.set_stylebox("pressed", "Button", _box(VIOLET, VIOLET, 2))
	t.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), VIOLET, 3))
	t.set_stylebox("disabled", "Button", _box(Color(PAPER, 0.5), Color(INK, 0.06), 2))
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", INK)
	t.set_color("font_focus_color", "Button", INK)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(INK, 0.3))
	t.set_font_size("font_size", "Button", 22)
	t.set_stylebox("panel", "PanelContainer", _box(PAPER, Color(INK, 0.08), 1, 18, 28))
	# Label variations.
	t.add_type("TitleLabel")
	t.set_type_variation("TitleLabel", "Label")
	t.set_font("font", "TitleLabel", bold())
	t.set_font_size("font_size", "TitleLabel", 44)
	t.add_type("HeadLabel")
	t.set_type_variation("HeadLabel", "Label")
	t.set_font("font", "HeadLabel", bold())
	t.set_font_size("font_size", "HeadLabel", 28)
	t.add_type("SmallLabel")
	t.set_type_variation("SmallLabel", "Label")
	t.set_font_size("font_size", "SmallLabel", 16)
	t.set_color("font_color", "SmallLabel", INK_SOFT)
	_theme = t
	return t


static func _box(bg: Color, border: Color, width: int, radius := 12, pad := 16) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.set_border_width_all(width)
	b.set_corner_radius_all(radius)
	b.content_margin_left = pad
	b.content_margin_right = pad
	b.content_margin_top = pad * 0.6
	b.content_margin_bottom = pad * 0.6
	b.anti_aliasing = true
	return b


static func button(text: String, on_press: Callable, min_width := 240.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 52)
	b.pressed.connect(on_press)
	b.pressed.connect(func() -> void: Sfx.ui("click"))
	return b


static func label(text: String, variation := "") -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l
