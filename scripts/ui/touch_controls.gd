class_name TouchControls
extends Control
## On-screen controls for phones and tablets.
##   Left half: a floating stick (appears where the thumb lands) to move.
##   Right half: drag to look.
##   Bottom-right: the shock wave button. Above it: jump. Beside it: the
##   orb button, to hold (debris gathers) and let go (the orb is thrown).
## Multi-touch is tracked per finger so you can move, look and fire at once.

@export var player: Player
## Radians per pixel of drag, scaled by screen height so it feels the same
## on every phone.
@export var look_sensitivity := 2.2
## Drags longer than this fraction of screen height in one event are
## treated as glitches and ignored.
@export var max_step := 0.2

var _stick_finger := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _look_finger := -1
var _fire_finger := -1
var _jump_finger := -1
var _gather_finger := -1
## Last position per finger. Deltas are computed from these instead of the
## event's `relative`: on the web, Godot pairs multi-touch moves with the
## wrong previous finger, which made the camera jump and spin on iOS.
var _last := {}


static func should_show() -> bool:
	return DisplayServer.is_touchscreen_available() or Quality.is_handheld()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func stick_radius() -> float:
	return size.y * 0.13


func fire_center() -> Vector2:
	return Vector2(size.x - size.y * 0.2, size.y * 0.76)


func fire_radius() -> float:
	return size.y * 0.11


func gather_center() -> Vector2:
	return Vector2(size.x - size.y * 0.47, size.y * 0.84)


func gather_radius() -> float:
	return size.y * 0.095


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
	var none := _stick_finger < 0 and _look_finger < 0 and _fire_finger < 0 and _jump_finger < 0
	if none and _gather_finger < 0:
		return
	_stick_finger = -1
	_look_finger = -1
	_fire_finger = -1
	_jump_finger = -1
	_gather_finger = -1
	_last.clear()
	if player:
		player.touch_move = Vector2.ZERO
		player.touch_gather = false
	queue_redraw()


func _on_touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		_last[e.index] = e.position
		if e.position.distance_to(fire_center()) < fire_radius() * 1.3 and _fire_finger < 0:
			_fire_finger = e.index
			player.touch_fire = true
		elif e.position.distance_to(gather_center()) < gather_radius() * 1.3 and _gather_finger < 0:
			_gather_finger = e.index
			player.touch_gather = true
		elif e.position.distance_to(jump_center()) < jump_radius() * 1.4 and _jump_finger < 0:
			_jump_finger = e.index
			player.touch_jump = true
		elif e.position.x < size.x * 0.5 and _stick_finger < 0:
			_stick_finger = e.index
			_stick_origin = e.position
			_stick_pos = e.position
		elif _look_finger < 0 and not Hud.rebuild_rect(size).grow(10).has_point(e.position):
			_look_finger = e.index
	else:
		_last.erase(e.index)
		if e.index == _fire_finger:
			_fire_finger = -1
		elif e.index == _gather_finger:
			_gather_finger = -1
			player.touch_gather = false
		elif e.index == _jump_finger:
			_jump_finger = -1
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
	elif e.index == _look_finger or e.index == _fire_finger or e.index == _gather_finger:
		# Dragging from the fire or the orb button also aims, like a real
		# thumb would: the orb is held, aimed, then let go.
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
	# The shock wave button: waves going out from a point. Dim while the
	# power comes back.
	var ready := player == null or player.cooldown_left <= 0.0
	var c := fire_center()
	var r := fire_radius()
	draw_circle(c, r * (1.08 if _fire_finger >= 0 else 1.0), Color(0.3, 0.55, 1.0, 0.6 if ready else 0.25))
	draw_arc(c, r * 1.12, 0, TAU, 48, Color(1, 1, 1, 0.6), 3.0, true)
	var mark := Color(1, 1, 1, 0.9 if ready else 0.4)
	draw_circle(c - Vector2(r * 0.45, 0), r * 0.1, mark)
	for j in 3:
		draw_arc(c - Vector2(r * 0.45, 0), r * (0.32 + 0.26 * j), -0.75, 0.75, 12, mark, 3.0, true)
	# The orb button: a ball, with a ring that fills as the orb grows.
	var held := _gather_finger >= 0
	var g := gather_center()
	var gr := gather_radius()
	draw_circle(g, gr * (1.08 if held else 1.0), Color(1.0, 0.62, 0.25, 0.75 if held else 0.55))
	draw_arc(g, gr * 1.12, 0, TAU, 48, Color(1, 1, 1, 0.6), 3.0, true)
	draw_circle(g, gr * 0.36, Color(1, 1, 1, 0.9))
	for j in 6:
		var way := Vector2.from_angle(TAU * j / 6.0 + 0.3)
		draw_circle(g + way * gr * 0.68, gr * 0.07, Color(1, 1, 1, 0.8))
	if player != null and player.orb_fill > 0.0:
		draw_arc(g, gr * 1.28, -PI / 2, -PI / 2 + TAU * player.orb_fill, 48, Color(1, 1, 1, 0.95), 5.0, true)
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
