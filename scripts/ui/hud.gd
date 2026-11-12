class_name Hud
extends Control
## What is drawn over the game: a dot to aim with, a line of numbers (frames
## per second, pieces moving and at rest) and the button that puts the
## building back up.

signal rebuild_pressed

var world: Main

var _stats: Label
var _hint: Label
var _since := 0.0


## Where the rebuild button sits on a screen of `view` size.
static func rebuild_rect(view: Vector2) -> Rect2:
	return Rect2(view.x - 196.0, 16.0, 180.0, 56.0)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats = _label(18)
	_stats.position = Vector2(20, 14)
	_hint = _label(22)
	_hint.position = Vector2(20, 44)
	_hint.text = "Clic ou F : onde de choc  ·  R : reconstruire"
	if TouchControls.should_show():
		_hint.text = "Bouton bleu : onde de choc"
	var button := Button.new()
	button.text = "Reconstruire"
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 22)
	add_child(button)
	button.pressed.connect(func() -> void: rebuild_pressed.emit())
	var place := func() -> void:
		var r := rebuild_rect(size)
		button.position = r.position
		button.size = r.size
	resized.connect(place)
	place.call()


func _label(font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color(0.95, 0.95, 0.97))
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.1, 0.12))
	l.add_theme_constant_override("outline_size", 5)
	add_child(l)
	return l


func _process(delta: float) -> void:
	_since += delta
	if _since < 0.25 or world == null:
		return
	_since = 0.0
	var p := world.structure.pieces
	_stats.text = (
		"%d i/s   physique %.1f ms   %d morceaux (%d en mouvement)"
		% [Engine.get_frames_per_second(), world.clock.avg_ms, p.live, p.awake]
	)
	_hint.modulate.a = move_toward(_hint.modulate.a, 0.0 if p.live > 0 else 1.0, 0.25)


func _draw() -> void:
	var c := size * 0.5
	draw_circle(c, 4.0, Color(0, 0, 0, 0.5))
	draw_circle(c, 2.5, Color(1, 1, 1, 0.9))
