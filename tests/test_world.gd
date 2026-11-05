extends TestCase
## Integration tests on the real arena scene, with physics running.

var world: GameWorld


func _load_world() -> void:
	world = load("res://scenes/game.tscn").instantiate()
	add_child(world)
	world.player.input_enabled = false
	await frames(2)


func _unload() -> void:
	world.queue_free()
	await frames(2)


func test_arena_builds_structures() -> void:
	await _load_world()
	check(
		world.structures.segment_count() > 500,
		"arena has many blocks (%d)" % world.structures.segment_count()
	)
	check_eq(world.structures.alive_count, world.structures.segment_count(), "all standing")
	check_eq(world.debris.active_count, 0, "no debris yet")
	await _unload()


func test_unsupported_blocks_fall() -> void:
	await _load_world()
	var s := world.structures
	# Knock out the ground floor of one building: the floors above have
	# nothing left to stand on.
	var at := Vector3(-29, 0, -31)
	var broke := 0
	for i in s.segment_count():
		var p := s.transform_of(i).origin
		if s.is_alive(i) and p.y < 2.9 and absf(p.x - at.x) < 6.5 and absf(p.z - at.z) < 6.5:
			s.break_segment(i)
			broke += 1
	var fell := s.settle()
	check(broke > 15, "broke the ground floor (%d)" % broke)
	check(fell > 60, "the storeys above lost support (%d fell)" % fell)
	await _unload()


func test_ramps_and_walkway_stand_and_lead_up() -> void:
	await _load_world()
	await frames(60)
	check_eq(world.structures.cluster_count(), 0, "nothing falls on its own")
	# The walkway over the avenue is walkable at the 2nd floor (6.4 m).
	var q := PhysicsRayQueryParameters3D.create(Vector3(0, 12, -14), Vector3(0, 0, -14))
	var hit := world.get_world_3d().direct_space_state.intersect_ray(q)
	check(not hit.is_empty(), "something under the walkway centre")
	if not hit.is_empty():
		check_near(hit["position"].y, 6.4, 0.05, "walkway deck at 6.4 m")
	# Walk the player up the south-east alley ramp's first flight (it climbs
	# toward +z to the first floor, 3.2 m).
	var p := world.player
	p.input_enabled = true
	p.global_position = Vector3(19.4, 0.1, 8.8)
	p.rotation.y = PI
	p.touch_move = Vector2(0, -1)
	var top := 0.0
	for k in 120:
		await get_tree().physics_frame
		top = maxf(top, p.global_position.y)
	p.touch_move = Vector2.ZERO
	check(top > 2.9, "climbed the ramp (reached y %.2f)" % top)
	await _unload()


func test_debris_budget_recycles_oldest() -> void:
	await _load_world()
	var d := world.debris
	var cap := d.capacity
	for i in cap + 25:
		d.spawn(Transform3D(Basis(), Vector3(i % 20, 5 + i / 20.0 * 0.6, 40)), Vector3.ONE * 0.3)
	check_eq(d.active_count, cap, "never exceeds capacity")
	check_eq(d.recycled_total, 25, "oldest recycled")
	await _unload()


func test_touch_controls_move_look_and_cast() -> void:
	await _load_world()
	var p := world.player
	p.input_enabled = true
	var tc := TouchControls.new()
	tc.player = p
	add_child(tc)
	tc.set_anchors_preset(Control.PRESET_TOP_LEFT)
	tc.size = Vector2(1600, 900)
	# Left thumb down, then drag up: walk forward.
	tc._on_touch(_touch(0, Vector2(300, 700), true))
	tc._on_drag(_drag(0, Vector2(300, 560), Vector2(0, -140)))
	check(p.touch_move.y < -0.9, "stick forward (%s)" % p.touch_move)
	var z := p.global_position.z
	await frames(30)
	check(p.global_position.z < z - 1.0, "player walked forward")
	# Right side drag turns the view.
	var yaw := p.rotation.y
	tc._on_touch(_touch(1, Vector2(1100, 400), true))
	tc._on_drag(_drag(1, Vector2(1000, 400), Vector2(-100, 0)))
	check(p.rotation.y > yaw, "drag left turns left")
	# The violet button opens a black hole; the shield slot raises the
	# shield at once.
	var casts: Array[int] = []
	p.power.cast.connect(func(pw: int) -> void: casts.append(pw))
	tc._on_touch(_touch(2, tc.charge_center(), true))
	await get_tree().process_frame
	await get_tree().process_frame
	tc._on_touch(_touch(2, tc.charge_center(), false))
	check_eq(casts, [PowerDefs.Power.VORTEX] as Array[int], "the violet button opens a black hole")
	var shield_slot := Hud.power_slot_rect(PowerDefs.Power.SHIELD, tc.size, true).get_center()
	tc._on_touch(_touch(3, shield_slot, true))
	tc._on_touch(_touch(3, shield_slot, false))
	check_eq(casts.size(), 2, "tapping the shield slot raises it")
	check_eq(casts[-1], PowerDefs.Power.SHIELD, "the shield")
	# The slots sit right next to the cast button.
	for k in 2:
		var d := Hud.power_slot_rect(k, tc.size, true).get_center().distance_to(tc.charge_center())
		check(d < tc.size.y * 0.25, "slot %d next to the cast button" % k)
	# Releasing the stick stops movement input.
	tc._on_touch(_touch(0, Vector2(300, 560), false))
	check_eq(p.touch_move, Vector2.ZERO, "stick released")
	tc.queue_free()
	await _unload()


func _touch(i: int, pos: Vector2, pressed: bool) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = i
	e.position = pos
	e.pressed = pressed
	return e


func _drag(i: int, pos: Vector2, rel: Vector2) -> InputEventScreenDrag:
	var e := InputEventScreenDrag.new()
	e.index = i
	e.position = pos
	e.relative = rel
	return e


func test_touch_look_ignores_bogus_relative() -> void:
	await _load_world()
	var p := world.player
	var tc := TouchControls.new()
	tc.player = p
	add_child(tc)
	tc.set_anchors_preset(Control.PRESET_TOP_LEFT)
	tc.size = Vector2(1600, 900)
	tc._on_touch(_touch(7, Vector2(300, 700), true))
	tc._on_touch(_touch(42, Vector2(1100, 400), true))
	var yaw := p.rotation.y
	# Web builds can report another finger's delta in `relative`.
	tc._on_drag(_drag(42, Vector2(1110, 400), Vector2(-800, 300)))
	check_near(p.rotation.y - yaw, -10.0 * tc.look_sensitivity / 900.0, 1e-4, "uses own 10 px delta")
	# A single teleporting jump is ignored.
	yaw = p.rotation.y
	tc._on_drag(_drag(42, Vector2(300, 100), Vector2.ZERO))
	check_near(p.rotation.y, yaw, 1e-5, "spike ignored")
	tc.queue_free()
	await _unload()


func test_soft_budget_shrinks_pieces_away_gradually() -> void:
	await _load_world()
	var d := world.debris
	d.retire_min_age = 0.0
	var n := int(d.capacity * 0.95)
	for i in n:
		d.spawn(
			Transform3D(Basis(), Vector3(i % 30, 0.5 + floorf(i / 900.0), 30 + floori(i / 30.0) % 30)),
			Vector3.ONE * 0.3
		)
	await frames(2)
	check(d.fading_count > 0, "retiring started")
	check_eq(d.active_count, n, "nothing vanished instantly")
	await frames(int(DebrisSystem.FADE_TIME * 60.0) + 90)
	var target := int(d.capacity * DebrisSystem.SOFT_BUDGET)
	check(d.active_count <= target + d.fading_count, "back under soft budget (%d)" % d.active_count)
	check(d.active_count >= target - DebrisSystem.RETIRE_PER_FRAME, "did not over-retire")
	await _unload()
