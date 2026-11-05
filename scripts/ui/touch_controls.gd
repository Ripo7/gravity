class_name TouchControls
extends Control
## On-screen controls for phones and tablets.
##   Left half: a floating stick (appears where the thumb lands) to move.
##   Right half: drag to look.
##   Bottom-right: hold the violet button to grow the power, release to cast.
##   Left of it: tap a power slot to pick the power. Above it: jump.
## Multi-touch is tracked per finger so you can move, look and charge at once.

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
var _charge_finger := -1
var _jump_finger := -1
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


func charge_center() -> Vector2:
	return charge_center_for(size)


static func charge_center_for(view: Vector2) -> Vector2:
	return Vector2(view.x - view.y * 0.2, view.y * 0.76)


func charge_radius() -> float:
	return size.y * 0.11


func jump_center() -> Vector2:
	return Vector2(size.x - size.y * 0.2, size.y * 0.5)


func jump_radius() -> float:
	return size.y * 0.075


func _input(event: InputEvent) -> void:
	# Only steer the player during play: menus, cards and pause screens get
	# the taps (as emulated mouse clicks) instead.
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
	if _stick_finger < 0 and _look_finger < 0 and _charge_finger < 0 and _jump_finger < 0:
		return
	_stick_finger = -1
	_look_finger = -1
	_charge_finger = -1
	_jump_finger = -1
	_last.clear()
	if player:
		player.touch_move = Vector2.ZERO
		player.power.touch_held = false
	queue_redraw()


func _on_touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		_last[e.index] = e.position
		for k in 2:
			if Hud.power_slot_rect(k, size, true).grow(6).has_point(e.position):
				player.power.select(k)
				queue_redraw()
				return
		if e.position.distance_to(charge_center()) < charge_radius() * 1.3 and _charge_finger < 0:
			_charge_finger = e.index
			player.power.touch_held = true
			player.power.touch_tapped = true
		elif e.position.distance_to(jump_center()) < jump_radius() * 1.4 and _jump_finger < 0:
			_jump_finger = e.index
			player.touch_jump = true
		elif e.position.x < size.x * 0.5 and _stick_finger < 0:
			_stick_finger = e.index
			_stick_origin = e.position
			_stick_pos = e.position
		elif _look_finger < 0 and not (e.position.x > size.x - 100 and e.position.y < 90):
			_look_finger = e.index
	else:
		_last.erase(e.index)
		if e.index == _charge_finger:
			_charge_finger = -1
			player.power.touch_held = false
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
	elif e.index == _look_finger or e.index == _charge_finger:
		# Dragging the charge button also aims, like a real thumb would.
		var k := look_sensitivity / maxf(size.y, 1.0)
		player.look(Vector2(-step.x, -step.y) * k)


func _draw() -> void:
	var ink := Color(0.2, 0.2, 0.28, 0.22)
	var ink_strong := Color(0.2, 0.2, 0.28, 0.45)
	if _stick_finger >= 0:
		draw_circle(_stick_origin, stick_radius(), ink)
		draw_circle(_stick_pos, stick_radius() * 0.42, ink_strong)
	else:
		var hint := Vector2(size.y * 0.24, size.y * 0.76)
		draw_arc(hint, stick_radius(), 0, TAU, 48, ink, 3.0, true)
	var charging := _charge_finger >= 0
	var violet := Palette.VIOLET
	violet.a = 0.85 if charging else 0.5
	draw_circle(charge_center(), charge_radius() * (1.1 if charging else 1.0), violet)
	draw_arc(charge_center(), charge_radius() * 1.12, 0, TAU, 48, Color(1, 1, 1, 0.6), 3.0, true)
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
	if _charge_finger >= 0:
		queue_redraw()
