class_name Hud
extends Control
## In-game HUD: crosshair + charge ring, destruction meter with star marks,
## remaining charges, level name, pop-up callouts, F3 stats, touch controls.

@export var world: GameWorld

var show_stats := false
var touch := false
## Fed by LevelRun.
var destruction := 0.0
var shown_destruction := 0.0
var thresholds := Vector3(0.4, 0.65, 0.85)
var charges_total := 0
var charges_left := 0
var meter_visible := true

var _charge := 0.0
var _stats: Label
var _title: Label
var _popups: Array[Label] = []
var _pause_button: Button
var _meter_pulse := 0.0


func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title = Label.new()
	_title.theme_type_variation = "SmallLabel"
	_title.position = Vector2(24, 18)
	add_child(_title)
	_stats = Label.new()
	_stats.theme_type_variation = "SmallLabel"
	_stats.position = Vector2(24, 48)
	_stats.visible = false
	add_child(_stats)
	touch = TouchControls.should_show() or OS.get_cmdline_user_args().has("--touch")
	if touch:
		var controls := TouchControls.new()
		controls.player = world.player if world else null
		add_child(controls)
	if world and world.player:
		world.player.power.charge_changed.connect(func(c: float) -> void: _charge = c)


func set_title(text: String) -> void:
	_title.text = text


## Adds the on-screen pause button (touch screens have no Esc key).
func add_pause_button(on_press: Callable) -> void:
	_pause_button = Button.new()
	_pause_button.text = "II"
	_pause_button.custom_minimum_size = Vector2(56, 56)
	_pause_button.focus_mode = Control.FOCUS_NONE
	_pause_button.pressed.connect(on_press)
	add_child(_pause_button)


## Big centred callout that floats up and fades ("COLLAPSE!", "+12%").
func popup(text: String, color := UiTheme.INK, font_size := 40, offset := Vector2.ZERO) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UiTheme.bold())
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.9))
	l.add_theme_constant_override("outline_size", 8)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	l.reset_size()
	var start := Vector2(size.x * 0.5 - l.size.x * 0.5, size.y * 0.3) + offset
	l.position = start + Vector2(0, 20)
	l.scale = Vector2.ONE * 0.6
	l.pivot_offset = l.size * 0.5
	var tw := l.create_tween().set_ignore_time_scale(true)
	tw.set_parallel()
	tw.tween_property(l, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position", start - Vector2(0, 40), 1.2).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.5).set_delay(0.8)
	tw.chain().tween_callback(l.queue_free)
	_popups.append(l)


func pulse_meter() -> void:
	_meter_pulse = 1.0


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("toggle_debug"):
		show_stats = not show_stats
	_stats.visible = show_stats
	if show_stats and world:
		_stats.text = stats_text(world)
	# Meter eases toward the real value so jumps read as growth.
	shown_destruction = move_toward(
		shown_destruction, destruction, maxf(0.4 * delta, absf(destruction - shown_destruction) * 6.0 * delta)
	)
	_meter_pulse = move_toward(_meter_pulse, 0.0, delta * 3.0)
	if _pause_button:
		_pause_button.position = Vector2(size.x - 80, 16)
	queue_redraw()


static func stats_text(w: GameWorld) -> String:
	return (
		(
			"%d fps  ·  physics %.1f ms\npieces %d / %d  (awake %d)\n"
			+ "blocks standing %d  ·  falling groups %d\ndraw calls %d"
		)
		% [
			Engine.get_frames_per_second(),
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			w.debris.active_count,
			w.debris.capacity,
			w.debris.awake_count,
			w.structures.alive_count,
			w.structures.cluster_count(),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		]
	)


func _draw() -> void:
	var c := size * 0.5
	var ink := Color(0.12, 0.11, 0.18, 0.75)
	# Crosshair: four short ticks and a dot.
	for d: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(c + d * 6.0, c + d * 11.0, ink, 2.0, true)
	draw_circle(c, 1.6, ink)
	if _charge > 0.0:
		var r := 18.0 + _charge * 10.0
		draw_arc(c, r, 0, TAU, 48, Color(UiTheme.VIOLET, 0.18), 3.0, true)
		draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * _charge, 48, UiTheme.VIOLET, 3.5, true)
	if meter_visible:
		_draw_meter()
	if charges_total > 0:
		_draw_charges()


func _draw_meter() -> void:
	var w := minf(size.x * 0.42, 520.0)
	var h := 12.0 + _meter_pulse * 4.0
	var top := 26.0
	var rect := Rect2(Vector2((size.x - w) * 0.5, top), Vector2(w, h))
	draw_rect(rect.grow(3), Color(1, 1, 1, 0.85))
	draw_rect(rect, Color(UiTheme.INK, 0.12))
	var fill := rect
	fill.size.x = w * clampf(shown_destruction, 0.0, 1.0)
	draw_rect(fill, UiTheme.VIOLET)
	var font := UiTheme.bold()
	for k in 3:
		var x := rect.position.x + w * thresholds[k]
		var reached := shown_destruction >= thresholds[k]
		draw_line(Vector2(x, top - 2), Vector2(x, top + h + 2), Color(UiTheme.INK, 0.5), 2.0)
		var star_c := Vector2(x, top + h + 16)
		for s in k + 1:
			var sx := star_c.x + (s - k * 0.5) * 13.0
			UiTheme.draw_star(
				self, Vector2(sx, star_c.y), 7.0, UiTheme.STAR_ON if reached else UiTheme.STAR_OFF
			)
	var pct := "%d%%" % int(round(shown_destruction * 100.0))
	draw_string(font, Vector2(rect.end.x + 14, top + h), pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UiTheme.INK)


func _draw_charges() -> void:
	var r := 11.0
	var gap := 30.0
	var right := size.x - (110.0 if _pause_button else 30.0)
	for k in charges_total:
		var p := Vector2(right - k * gap, 40)
		var full := k < charges_left
		if full:
			draw_circle(p, r + 3, Color(UiTheme.VIOLET, 0.25))
			draw_circle(p, r, UiTheme.VIOLET)
			draw_circle(p + Vector2(-3, -3), r * 0.35, Color(1, 1, 1, 0.7))
		else:
			draw_arc(p, r, 0, TAU, 32, Color(UiTheme.INK, 0.3), 2.0, true)
