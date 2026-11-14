class_name TouchControls
extends Control
## On-screen controls for phones and tablets.
##   Left half: a floating stick (appears where the thumb lands) to move:
##   how far it is pushed sets the pace, from a walk to a run, and held at
##   full tilt it breaks into a sprint.
##   Right half: drag to look.
##   Bottom-right: the punch button. Above it: jump. Left of it: the kick,
##   with the duck above and the lock farther left.
## Multi-touch is tracked per finger so you can move, look and strike at once.

@export var player: Player
## Radians per pixel of drag, scaled by screen height so it feels the same
## on every phone.
@export var look_sensitivity := 2.2
## Drags longer than this fraction of screen height in one event are
## treated as glitches and ignored.
@export var max_step := 0.2
## The stick held at full tilt this long (s) breaks into a sprint.
@export var sprint_after := 0.8

var _stick_finger := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _look_finger := -1
var _jump_finger := -1
var _punch_finger := -1
var _kick_finger := -1
var _dodge_finger := -1
var _lock_finger := -1
## Last position per finger. Deltas are computed from these instead of the
## event's `relative`: on the web, Godot pairs multi-touch moves with the
## wrong previous finger, which made the camera jump and spin on iOS.
var _last := {}
var _tilted := 0.0  # s the stick has been at full tilt


static func should_show() -> bool:
	return DisplayServer.is_touchscreen_available() or Quality.is_handheld()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func stick_radius() -> float:
	return size.y * 0.13


func punch_center() -> Vector2:
	return Vector2(size.x - size.y * 0.2, size.y * 0.76)


func punch_radius() -> float:
	return size.y * 0.11


func kick_center() -> Vector2:
	return Vector2(size.x - size.y * 0.47, size.y * 0.82)


func dodge_center() -> Vector2:
	return Vector2(size.x - size.y * 0.44, size.y * 0.585)


func lock_center() -> Vector2:
	return Vector2(size.x - size.y * 0.7, size.y * 0.86)


## The radius of the kick, duck and lock buttons.
func small_radius() -> float:
	return size.y * 0.08


func jump_center() -> Vector2:
	return Vector2(size.x - size.y * 0.2, size.y * 0.5)


func jump_radius() -> float:
	return size.y * 0.075


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or player == null or get_tree().paused or not player.input_enabled:
		_release_all()
		return
	if event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		_on_drag(event as InputEventScreenDrag)
		get_viewport().set_input_as_handled()


func _release_all() -> void:
	var fingers: Array[int] = [
		_stick_finger, _look_finger, _jump_finger, _punch_finger, _kick_finger, _dodge_finger, _lock_finger
	]
	if fingers.max() < 0:
		return
	_punch_finger = -1
	_kick_finger = -1
	_dodge_finger = -1
	_stick_finger = -1
	_look_finger = -1
	_lock_finger = -1
	_jump_finger = -1
	_last.clear()
	if player:
		player.touch_move = Vector2.ZERO
	queue_redraw()


func _physics_process(delta: float) -> void:
	if player == null:
		return
	var full := _stick_finger >= 0 and player.touch_move.length() > 0.95
	if full:
		_tilted += delta
		if _tilted > sprint_after:
			player.touch_sprint = true
	elif _tilted > 0.0:
		_tilted = 0.0
		player.touch_sprint = false


func _on_touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		_last[e.index] = e.position
		if e.position.distance_to(lock_center()) < small_radius() * 1.3 and _lock_finger < 0:
			_lock_finger = e.index
			player.lock()
		elif e.position.distance_to(jump_center()) < jump_radius() * 1.4 and _jump_finger < 0:
			_jump_finger = e.index
			player.touch_jump = true
		elif e.position.distance_to(punch_center()) < punch_radius() * 1.3 and _punch_finger < 0:
			_punch_finger = e.index
			player.touch_punch = true
		elif e.position.distance_to(kick_center()) < small_radius() * 1.3 and _kick_finger < 0:
			_kick_finger = e.index
			player.touch_kick = true
		elif e.position.distance_to(dodge_center()) < small_radius() * 1.3 and _dodge_finger < 0:
			_dodge_finger = e.index
			player.touch_dodge = true
		elif e.position.x < size.x * 0.5 and _stick_finger < 0:
			_stick_finger = e.index
			_stick_origin = e.position
			_stick_pos = e.position
		elif _look_finger < 0 and not Hud.rebuild_rect(size).grow(10).has_point(e.position):
			_look_finger = e.index
	else:
		_last.erase(e.index)
		if e.index == _lock_finger:
			_lock_finger = -1
		elif e.index == _jump_finger:
			_jump_finger = -1
		elif e.index == _punch_finger:
			_punch_finger = -1
		elif e.index == _kick_finger:
			_kick_finger = -1
		elif e.index == _dodge_finger:
			_dodge_finger = -1
		elif e.index == _stick_finger:
			_stick_finger = -1
			player.touch_move = Vector2.ZERO
		elif e.index == _look_finger:
			_look_finger = -1
	queue_redraw()


func _on_drag(e: InputEventScreenDrag) -> void:
	var prev: Vector2 = _last.get(e.index, e.position)
	_last[e.index] = e.position
	var step := e.position - prev
	if step.length() > size.y * max_step:
		step = Vector2.ZERO
	if e.index == _stick_finger:
		_stick_pos = e.position
		var offset := (_stick_pos - _stick_origin) / stick_radius()
		player.touch_move = offset.limit_length(1.0)
		# Let the base follow a thumb that slides too far.
		var r := stick_radius()
		if _stick_pos.distance_to(_stick_origin) > r:
			_stick_origin = _stick_pos - (_stick_pos - _stick_origin).normalized() * r
		queue_redraw()
	elif e.index == _look_finger:
		var k := look_sensitivity / maxf(size.y, 1.0)
		player.look(Vector2(-step.x, -step.y) * k)


func _draw() -> void:
	var ink := Color(1, 1, 1, 0.22)
	var ink_strong := Color(1, 1, 1, 0.45)
	if _stick_finger >= 0:
		draw_circle(_stick_origin, stick_radius(), ink)
		draw_circle(_stick_pos, stick_radius() * 0.42, ink_strong)
	else:
		var hint := Vector2(size.y * 0.24, size.y * 0.76)
		draw_arc(hint, stick_radius(), 0, TAU, 48, ink, 3.0, true)
	# The punch button, the big one: a fist seen from the front (four
	# knuckles, a thumb).
	var c := punch_center()
	var r := punch_radius()
	draw_circle(c, r * (1.08 if _punch_finger >= 0 else 1.0), Color(0.95, 0.35, 0.25, 0.6))
	draw_arc(c, r * 1.12, 0, TAU, 48, Color(1, 1, 1, 0.6), 3.0, true)
	for k in 4:
		draw_circle(c + Vector2((k - 1.5) * r * 0.26, -r * 0.1), r * 0.14, Color(1, 1, 1, 0.9))
	draw_line(
		c + Vector2(-r * 0.45, r * 0.22), c + Vector2(r * 0.3, r * 0.22), Color(1, 1, 1, 0.9), r * 0.16, true
	)
	# The kick: a boot, in orange.
	c = kick_center()
	r = small_radius()
	draw_circle(c, r * (1.08 if _kick_finger >= 0 else 1.0), Color(1.0, 0.6, 0.15, 0.6))
	draw_arc(c, r * 1.12, 0, TAU, 48, Color(1, 1, 1, 0.6), 3.0, true)
	var boot := PackedVector2Array(
		[
			c + Vector2(-r * 0.3, -r * 0.5),
			c + Vector2(-r * 0.3, r * 0.3),
			c + Vector2(r * 0.5, r * 0.3),
		]
	)
	draw_polyline(boot, Color(1, 1, 1, 0.9), r * 0.2, true)
	# The duck: an arrow that dips, in white.
	c = dodge_center()
	draw_circle(c, r * (1.08 if _dodge_finger >= 0 else 1.0), Color(1, 1, 1, 0.35))
	draw_arc(c, r * 1.12, 0, TAU, 48, Color(1, 1, 1, 0.6), 3.0, true)
	draw_arc(
		c + Vector2(0, -r * 0.35), r * 0.55, 0.15 * PI, 0.85 * PI, 16, Color(1, 1, 1, 0.9), r * 0.16, true
	)
	# The lock: a sight, filled while the other brute is locked on.
	c = lock_center()
	var on := player != null and player.locked != null
	draw_circle(c, r, Color(1.0, 0.75, 0.2, 0.6) if on else Color(1, 1, 1, 0.2))
	draw_arc(c, r * 1.12, 0, TAU, 48, Color(1, 1, 1, 0.6), 3.0, true)
	draw_arc(c, r * 0.5, 0, TAU, 32, Color(1, 1, 1, 0.9), r * 0.12, true)
	for k in 4:
		var out := Vector2.RIGHT.rotated(k * PI * 0.5)
		draw_line(c + out * r * 0.35, c + out * r * 0.8, Color(1, 1, 1, 0.9), r * 0.12, true)
	draw_circle(jump_center(), jump_radius(), ink_strong if _jump_finger >= 0 else ink)
	var a := jump_center() + Vector2(0, -jump_radius() * 0.35)
	var w := jump_radius() * 0.4
	draw_polyline(
		PackedVector2Array([a + Vector2(-w, w * 0.8), a, a + Vector2(w, w * 0.8)]),
		Color(1, 1, 1, 0.8),
		4.0,
		true
	)


func _process(_delta: float) -> void:
	# A mouse in use (touchscreen laptops): the thumb controls step aside.
	visible = Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
	queue_redraw()
