class_name Hud
extends Control
## In-game HUD: destruction counter, health, the three power slots with
## cooldowns, damage flash, callouts, F3 stats and the touch controls.

## Touch: where each slot sits around the cast button (degrees, y down).
const SLOT_ANGLES := [168.0, 212.0]

@export var world: GameWorld

var show_stats := false
var touch := false
## Fed by LevelRun.
var destruction := 0.0
var shown_destruction := 0.0
var deaths := 0

var _stats: Label
var _title: Label
var _pause_button: Button
var _meter_pulse := 0.0
var _hurt_flash := 0.0
var _hurt_dir := 0.0
var _denied := [0.0, 0.0]
var _shown_health := 100.0
var _flash: ColorRect
var _last_hurt_sound := 0


func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash = ColorRect.new()
	_flash.color = Color(0.8, 0.05, 0.15, 0.0)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.material = _flash_material()
	add_child(_flash)
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
		world.player.power.denied.connect(func(p: int) -> void: _denied[p] = 1.0)


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


## Red flash toward the side the hit came from, plus a camera jolt.
func hurt(amount: float, from: Vector3) -> void:
	_hurt_flash = clampf(_hurt_flash + amount / 40.0, 0.25, 1.0)
	var cam := get_viewport().get_camera_3d()
	if cam:
		var local := cam.global_transform.affine_inverse() * from
		_hurt_dir = atan2(local.x, -local.z)
		if cam is CameraShake:
			(cam as CameraShake).add_trauma(clampf(amount / 60.0, 0.15, 0.8))
	# Damage over time arrives in small bites: one sound per bite burst.
	var now := Time.get_ticks_msec()
	if amount > 8.0 or now - _last_hurt_sound > 350:
		_last_hurt_sound = now
		Sfx.ui("hurt", -4.0 + minf(amount / 10.0, 6.0), randf_range(0.9, 1.1))


## Big centred callout that floats up and fades.
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


func pulse_meter() -> void:
	_meter_pulse = 1.0


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.001)
	if Input.is_action_just_pressed("toggle_debug"):
		show_stats = not show_stats
	_stats.visible = show_stats
	if show_stats and world:
		_stats.text = stats_text(world)
	var gap := absf(destruction - shown_destruction)
	shown_destruction = move_toward(shown_destruction, destruction, maxf(0.4 * real, gap * 6.0 * real))
	_meter_pulse = move_toward(_meter_pulse, 0.0, real * 3.0)
	_hurt_flash = move_toward(_hurt_flash, 0.0, real * 1.6)
	for k in 2:
		_denied[k] = move_toward(_denied[k], 0.0, real * 3.0)
	(_flash.material as ShaderMaterial).set_shader_parameter("amount", _hurt_flash)
	(_flash.material as ShaderMaterial).set_shader_parameter("dir", _hurt_dir)
	if world and world.player:
		_shown_health = move_toward(_shown_health, world.player.health, real * 120.0)
	if _pause_button:
		_pause_button.position = Vector2(size.x - 80, 16)
	queue_redraw()


static func stats_text(w: GameWorld) -> String:
	return (
		(
			"%d fps  ·  physique %.1f ms\nmorceaux %d / %d  (actifs %d)\n"
			+ "blocs debout %d  ·  pans en chute %d\nappels de rendu %d"
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
	_draw_crosshair()
	_draw_counter()
	if world and world.player:
		_draw_health()
		_draw_powers()


func _draw_crosshair() -> void:
	var c := size * 0.5
	var ink := Color(0.12, 0.11, 0.18, 0.75)
	for d: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(c + d * 6.0, c + d * 11.0, ink, 2.0, true)
	draw_circle(c, 1.6, ink)


## Top centre: how much of the place is down, and how often you died.
func _draw_counter() -> void:
	var font := UiTheme.bold()
	var txt := "%d%% détruit" % roundi(shown_destruction * 100.0)
	var fs := 30 + int(_meter_pulse * 8.0)
	var ts := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	_text(Vector2((size.x - ts.x) * 0.5, 46), txt, fs, UiTheme.INK)
	if deaths > 0:
		var d := "K.O. ×%d" % deaths
		var ds := font.get_string_size(d, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
		_text(Vector2((size.x - ds.x) * 0.5, 70), d, 16, Color(0.75, 0.1, 0.2))


func _draw_health() -> void:
	var p := world.player
	var w := 220.0
	var rect := Rect2(Vector2(28, size.y - 44), Vector2(w, 14))
	# White card behind label and bar: readable over anything.
	draw_rect(Rect2(rect.position - Vector2(12, 34), rect.size + Vector2(24, 46)), Color(1, 1, 1, 0.82))
	draw_rect(rect, Color(UiTheme.INK, 0.12))
	var k := clampf(_shown_health / Player.MAX_HEALTH, 0.0, 1.0)
	var low := k < 0.35
	var col := Color(0.85, 0.12, 0.22) if low else UiTheme.INK
	if low:
		col.a = 0.7 + 0.3 * sin(Time.get_ticks_msec() / 90.0)
	var fill := rect
	fill.size.x = w * k
	draw_rect(fill, col)
	var font := UiTheme.bold()
	draw_string(
		font,
		rect.position + Vector2(0, -10),
		"VIE %d" % ceili(p.health),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		16,
		UiTheme.INK
	)


func _draw_powers() -> void:
	var p := world.player.power
	var font := UiTheme.bold()
	for k in 2:
		var r := power_slot_rect(k, size, touch)
		var slot := r.size.x
		var shake := Vector2(sin(Time.get_ticks_msec() / 25.0) * 4.0 * _denied[k], 0)
		r.position += shake
		var ready := p.is_ready(k)
		draw_rect(r, Color(1, 1, 1, 0.9))
		draw_rect(r, UiTheme.VIOLET if ready else Color(UiTheme.INK, 0.15), false, 3.0 if ready else 1.5)
		_draw_icon(
			k, r.get_center(), slot * 0.3, UiTheme.VIOLET if k == PowerDefs.Power.VORTEX else UiTheme.INK
		)
		var left: float = p.cooldown_left[k]
		if left > 0.0:
			var frac := p.cooldown_fraction(k)
			var cover := Rect2(r.position + Vector2(0, slot * (1.0 - frac)), Vector2(slot, slot * frac))
			draw_rect(cover, Color(UiTheme.INK, 0.45))
			var s := "%d" % ceili(left)
			var ss := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 24)
			draw_string(
				font,
				r.get_center() + Vector2(-ss.x * 0.5, 9),
				s,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				24,
				Color.WHITE
			)
		if touch:
			continue
		# Name above, key below.
		var name: String = PowerDefs.NAMES[k]
		var ns := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
		_text(Vector2(r.get_center().x - ns.x * 0.5, r.position.y - 8.0), name, 16, UiTheme.INK)
		var key: String = PowerDefs.KEYS[k]
		var ks := font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
		draw_string(
			font,
			Vector2(r.get_center().x - ks.x * 0.5, r.end.y + 16.0),
			key,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			13,
			Color(UiTheme.INK, 0.6)
		)


## Screen rect of power slot `k`; on touch screens they are tap targets
## curved around the cast button, under the right thumb.
static func power_slot_rect(k: int, view: Vector2, is_touch: bool) -> Rect2:
	if is_touch:
		var slot := clampf(view.y * 0.1, 48.0, 84.0)
		var cast := TouchControls.charge_center_for(view)
		var angle := deg_to_rad(SLOT_ANGLES[k])
		var c := cast + Vector2(cos(angle), sin(angle)) * view.y * 0.215
		return Rect2(c - Vector2.ONE * slot * 0.5, Vector2(slot, slot))
	var size := 64.0
	var gap := 40.0
	var total := size * 2 + gap
	var x0 := (view.x - total) * 0.5
	return Rect2(Vector2(x0 + k * (size + gap), view.y - size - 34.0), Vector2(size, size))


## Text with a white outline so it reads on dark debris and black ice too.
func _text(pos: Vector2, text: String, font_size: int, color: Color) -> void:
	var font := UiTheme.bold()
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 6, Color(1, 1, 1, 0.9))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## Tiny vector icons so no texture assets are needed.
func _draw_icon(power: int, c: Vector2, r: float, col: Color) -> void:
	match power:
		PowerDefs.Power.VORTEX:
			draw_circle(c, r * 0.4, col)
			draw_arc(c, r, 0, TAU, 32, col, 2.5, true)
		PowerDefs.Power.SHIELD:
			# A curved dome of ice over a small figure.
			draw_arc(c + Vector2(0, r * 0.7), r * 1.1, PI * 1.05, PI * 1.95, 24, col, r * 0.3, true)
			draw_circle(c + Vector2(0, r * 0.25), r * 0.17, col)
			draw_line(c + Vector2(0, r * 0.4), c + Vector2(0, r * 0.75), col, 2.5)


static func _flash_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float amount = 0.0;
uniform float dir = 0.0;
void fragment() {
	vec2 uv = UV - 0.5;
	float edge = smoothstep(0.25, 0.75, length(uv * vec2(1.6, 1.0)));
	vec2 d = vec2(sin(dir), -cos(dir));
	float side = 0.6 + 0.4 * clamp(dot(normalize(uv + 0.0001), d), 0.0, 1.0);
	COLOR = vec4(0.75, 0.04, 0.12, edge * side * amount * 0.75);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	return m
