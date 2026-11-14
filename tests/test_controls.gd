extends TestCase
## Walking around and firing, with keys or with thumbs.

var main: Main


func test_the_player_stands_and_runs() -> void:
	await _load()
	var p := main.player
	await frames(30)
	check(p.is_on_floor() and absf(p.global_position.y) < 0.1, "stands on the ground")
	var z := p.global_position.z
	p.touch_move = Vector2(0, -1)  # the stick pushed forward
	await frames(60)
	p.touch_move = Vector2.ZERO
	check(p.global_position.z < z - 4.0, "runs forward (%.1f m)" % (z - p.global_position.z))
	await _unload()


func test_touch_controls_move_look_and_strike() -> void:
	await _load()
	var p := main.player
	var tc := TouchControls.new()
	tc.player = p
	main.add_child(tc)
	await frames(3)
	# The buttons do not sit on each other, nor on the rebuild button.
	var gap := (
		tc.punch_center().distance_to(tc.jump_center()) - tc.punch_radius() * 1.3 - tc.jump_radius() * 1.4
	)
	check(gap > 0.0, "punch and jump are apart")
	var rebuild := Hud.rebuild_rect(tc.size).grow(10)
	check(
		not rebuild.has_point(tc.jump_center() - Vector2(0, tc.jump_radius() * 1.4)), "jump clear of rebuild"
	)
	# Left thumb: the stick.
	var left := Vector2(tc.size.x * 0.18, tc.size.y * 0.75)
	tc._on_touch(_touch(0, left, true))
	tc._on_drag(_drag(0, left - Vector2(0, tc.stick_radius())))
	check(p.touch_move.y < -0.5, "stick forward")
	# Right thumb: look.
	var yaw := p.yaw
	var right := Vector2(tc.size.x * 0.7, tc.size.y * 0.3)
	tc._on_touch(_touch(1, right, true))
	tc._on_drag(_drag(1, right - Vector2(40, 0)))
	check(p.yaw > yaw, "dragging left turns the camera left")
	tc._on_touch(_touch(1, right - Vector2(40, 0), false))
	# A third finger on the big button.
	tc._on_touch(_touch(2, tc.punch_center(), true))
	await frames(2)
	check(p.character.striking(), "the big button strikes")
	tc._on_touch(_touch(2, tc.punch_center(), false))
	await frames(90)  # the blow runs its course: no jump in the middle of it
	tc._on_touch(_touch(0, left - Vector2(0, tc.stick_radius()), false))
	check_eq(p.touch_move, Vector2.ZERO, "lifting the thumb stops")
	tc._on_touch(_touch(3, tc.jump_center(), true))
	await frames(3)
	check(p.velocity.y > 1.0 or not p.is_on_floor(), "the arrow jumps")
	await _unload()


func _touch(index: int, at: Vector2, pressed: bool) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = at
	e.pressed = pressed
	return e


func _drag(index: int, at: Vector2) -> InputEventScreenDrag:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = at
	return e


func _load() -> void:
	seed(5)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
	main.fight = false  # the other brute only stands there
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await frames(20)


func _unload() -> void:
	main.queue_free()
	await frames(2)
