class_name Hud
extends Control
## What is drawn over the game: a dot to aim with, a line of numbers (frames
## per second, pieces moving and at rest), the button that starts the level
## again and the one that goes to the other level. In the course: the clock
## and the shock waves used, then the result once you are there.

signal rebuild_pressed
signal switch_pressed

var world: Main

var _stats: Label
var _hint: Label
var _clock: Label
var _result: Label
var _shade: ColorRect  # behind the result: you read it standing in the light
var _since := 0.0


## Where the button that starts again sits on a screen of `view` size.
static func rebuild_rect(view: Vector2) -> Rect2:
	return Rect2(view.x - 196.0, 16.0, 180.0, 56.0)


## Where the button that goes to the other level sits.
static func switch_rect(view: Vector2) -> Rect2:
	return Rect2(view.x - 196.0, 80.0, 180.0, 48.0)


## A time as minutes, seconds and tenths.
static func clock_text(seconds: float) -> String:
	var tenths := int(seconds * 10.0)
	return "%d:%02d.%d" % [tenths / 600, (tenths / 10) % 60, tenths % 10]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var in_course := world != null and world.course != null
	_stats = _label(18)
	_stats.position = Vector2(20, 14)
	_hint = _label(22)
	_hint.position = Vector2(20, 44)
	_hint.text = "Clic ou F : onde de choc  ·  Clic droit ou E, maintenu : aspirer  ·  R : recommencer"
	if TouchControls.should_show():
		_hint.text = "Bleu : onde de choc  ·  Violet, maintenu : aspirer les débris"
	if in_course:
		_hint.text = "Atteins la lumière au bout du couloir\n" + _hint.text
	_clock = _label(30)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock.visible = in_course
	_shade = ColorRect.new()
	_shade.color = Color(0.04, 0.04, 0.06, 0.6)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.visible = false
	add_child(_shade)
	_result = _label(54)
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_result.visible = false
	var again := _button("Recommencer" if in_course else "Reconstruire", 22)
	again.pressed.connect(func() -> void: rebuild_pressed.emit())
	var other := _button("Bac à sable" if in_course else "Parcours", 19)
	other.pressed.connect(func() -> void: switch_pressed.emit())
	var place := func() -> void:
		again.position = rebuild_rect(size).position
		again.size = rebuild_rect(size).size
		other.position = switch_rect(size).position
		other.size = switch_rect(size).size
		_clock.position = Vector2(0, 12)
		_clock.size = Vector2(size.x, 40)
		_result.position = Vector2.ZERO
		_result.size = size
		_shade.position = Vector2(0, size.y * 0.5 - 95)
		_shade.size = Vector2(size.x, 190)
	resized.connect(place)
	place.call()
	if in_course:
		world.course.finished.connect(_on_finished)


func _label(font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color(0.95, 0.95, 0.97))
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.1, 0.12))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _button(text: String, font_size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	add_child(b)
	return b


func _run_text(seconds: float, waves: int) -> String:
	return "%s  ·  %d onde%s" % [clock_text(seconds), waves, "" if waves == 1 else "s"]


func _on_finished(seconds: float, waves: int) -> void:
	_result.text = "Arrivé !\n" + _run_text(seconds, waves)
	_result.visible = true
	_shade.visible = true
	_clock.visible = false


func _process(delta: float) -> void:
	if world == null:
		return
	if _clock.visible:
		_clock.text = _run_text(world.course.seconds, world.course.waves)
	_since += delta
	if _since < 0.25:
		return
	_since = 0.0
	var p := world.structure.pieces
	_stats.text = (
		"%d i/s   physique %.1f ms   %d morceaux (%d actifs)"
		% [Engine.get_frames_per_second(), world.clock.avg_ms, p.live, p.awake]
	)
	var started := world.course.running if world.course != null else p.live > 0
	_hint.modulate.a = move_toward(_hint.modulate.a, 0.0 if started else 1.0, 0.25)


func _draw() -> void:
	var c := size * 0.5
	draw_circle(c, 4.0, Color(0, 0, 0, 0.5))
	draw_circle(c, 2.5, Color(1, 1, 1, 0.9))
