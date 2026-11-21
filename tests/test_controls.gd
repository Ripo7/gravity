extends TestCase
## Walking around and striking, with keys or with thumbs.

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
	# The buttons do not sit on each other, nor on what the HUD has for
	# thumbs (the rebuild button, the slider).
	var buttons := {
		"punch": [tc.punch_center(), tc.punch_radius() * 1.3],
		"jump": [tc.jump_center(), tc.jump_radius() * 1.4],
	}
	for a: String in buttons:
		var top: Vector2 = (buttons[a][0] as Vector2) - Vector2(0, buttons[a][1])
		check(not Hud.takes(top, tc.size), "%s is clear of the HUD" % a)
		for b: String in buttons:
			var apart: float = (
				(buttons[a][0] as Vector2).distance_to(buttons[b][0]) - buttons[a][1] - buttons[b][1]
			)
			check(a >= b or apart > 0.0, "%s and %s are apart (%.0f px)" % [a, b, apart])
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
	tc._on_touch(_touch(3, tc.jump_center(), false))
	await frames(90)
	# There is one button to strike with: where a second one was, left of
	# it, a thumb looks around.
	var beside := Vector2(tc.size.x - tc.size.y * 0.47, tc.size.y * 0.82)
	tc._on_touch(_touch(4, beside, true))
	await frames(2)
	check(not p.character.striking(), "a thumb beside the punch button strikes nothing")
	tc._on_touch(_touch(4, beside, false))
	# A thumb on the slider of the HUD is the slider's: the camera stays.
	var on_slider := Hud.fall_rect(tc.size).get_center()
	yaw = p.yaw
	tc._on_touch(_touch(5, on_slider, true))
	tc._on_drag(_drag(5, on_slider - Vector2(60, 0)))
	check_eq(p.yaw, yaw, "a thumb on the slider does not turn the camera")
	tc._on_touch(_touch(5, on_slider - Vector2(60, 0), false))
	await _unload()


func test_set_down_elsewhere_the_brute_throws_nothing_of_what_lay_against_it() -> void:
	await _load()
	var p := main.player
	var thrown := PackedFloat32Array()
	for set_down: bool in [false, true]:
		var at := Vector3(-30, 0.05, 40.0 if set_down else 30.0)
		p.set_down(at)
		await frames(5)
		# A block against it, on the side it leaves by.
		var block := RigidBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3.ONE * 0.5
		shape.shape = box
		block.add_child(shape)
		block.mass = 55.0
		block.can_sleep = false
		block.collision_layer = Layers.RUBBLE
		block.collision_mask = Layers.WORLD | Layers.PLAYER
		block.position = at + Vector3(Player.RADIUS + 0.23, 0.2, 0)
		main.add_child(block)
		await frames(20)
		var to := at + Vector3(8, 0, 0)
		if set_down:
			p.set_down(to)
		else:
			p.global_position = to
		var fastest := 0.0
		for k in 4:
			await frames(1)
			fastest = maxf(fastest, block.linear_velocity.length())
		thrown.append(fastest)
		await frames(15)
		check(p.global_position.distance_to(to) < 0.2, "it is there (%s)" % p.global_position)
		check(p.is_on_floor(), "on the ground")
		check_eq(p.collision_layer, Layers.PLAYER, "and in the way again")
		block.free()
	# (Moved from one step to the next, it is taken to have gone there in
	# that step: this is what `set_down` is for.)
	check(thrown[0] > 20.0, "(moved in one step, it throws the block: %.0f m/s)" % thrown[0])
	check(thrown[1] < 1.0, "set down, it does not (%.2f m/s)" % thrown[1])
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
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await frames(20)
	# In the open, away from what stands on the bench.
	main.player.global_position = Vector3(-30, 0.05, 30)
	await frames(5)


func _unload() -> void:
	main.queue_free()
	await frames(2)
