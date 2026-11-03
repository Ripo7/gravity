class_name Hud
extends Control
## Crosshair with a violet charge ring, a start hint and an F3 stats panel.

@export var world: GameWorld

var show_stats := false
var touch := false
var _charge := 0.0
var _hint: Label
var _hint_time := 0.0
var _stats: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint = _make_label(24, HORIZONTAL_ALIGNMENT_CENTER)
	_hint.text = (
		"CLICK TO PLAY\nhold LMB / RT to charge  ·  release to throw\n"
		+ "WASD / stick move  ·  SPACE / A jump  ·  R reset  ·  F3 stats"
	)
	_stats = _make_label(16, HORIZONTAL_ALIGNMENT_LEFT)
	_stats.position = Vector2(16, 48)
	_stats.visible = false
	touch = TouchControls.should_show() or OS.get_cmdline_user_args().has("--touch")
	if touch:
		var controls := TouchControls.new()
		controls.player = world.player if world else null
		add_child(controls)
		_hint.text = (
			"left thumb: move  ·  drag right side: look\n"
			+ "hold the violet button to charge, release to throw"
		)
		_hint.add_theme_font_size_override("font_size", 20)
		var stats := Button.new()
		stats.text = "stats"
		stats.flat = true
		stats.position = Vector2(12, 12)
		stats.pressed.connect(func() -> void: show_stats = not show_stats)
		add_child(stats)
	if world and world.player:
		world.player.power.charge_changed.connect(func(c: float) -> void: _charge = c)


func _make_label(font_size: int, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color(0.25, 0.25, 0.3))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _process(delta: float) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	_hint.visible = not captured and Input.get_connected_joypads().is_empty()
	_hint.visible = _hint.visible and not Launch.options.has("mode")
	if touch:
		_hint_time += delta
		_hint.visible = _hint_time < 6.0
	if Input.is_action_just_pressed("toggle_debug"):
		show_stats = not show_stats
	_hint.position = Vector2((size.x - _hint.size.x) * 0.5, size.y * 0.66)
	_stats.visible = show_stats
	if show_stats and world:
		_stats.text = stats_text(world)
	queue_redraw()


static func stats_text(w: GameWorld) -> String:
	return (
		"%d fps  ·  physics %.1f ms\npieces %d / %d  (awake %d)\nblocks standing %d\ndraw calls %d"
		% [
			Engine.get_frames_per_second(),
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			w.debris.active_count,
			w.debris.capacity,
			w.debris.awake_count,
			w.structures.alive_count,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		]
	)


func _draw() -> void:
	var c := size * 0.5
	var ink := Color(0.15, 0.15, 0.2, 0.8)
	draw_circle(c, 2.5, ink)
	if _charge > 0.0:
		var r := 14.0 + _charge * 10.0
		draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * _charge, 48, Palette.VIOLET, 3.0, true)
