extends TestCase
## Integration tests on the real arena scene, with physics running.

var world: GameWorld


func _load_world() -> void:
	world = load("res://scenes/main.tscn").instantiate()
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
	# Break every grounded block of the first structure (the front wall).
	var broke := 0
	for i in s.segment_count():
		var y := s.transform_of(i).origin.y
		if s.is_alive(i) and y < 0.3 and absf(s.transform_of(i).origin.z - 2.0) < 0.1:
			s.break_segment(i)
			broke += 1
	var fell := s.settle()
	check(broke > 5, "broke the wall's base row")
	check(fell > 50, "rest of the wall lost support (%d fell)" % fell)
	await _unload()


func test_blast_breaks_pulls_and_throws() -> void:
	await _load_world()
	var target := Vector3(0, 1.5, 2.6)  # just in front of the front wall
	var params := BlastParams.from_charge(1.0)
	var standing := world.structures.alive_count
	var blast := world.detonate(target, params)
	await frames(1)
	check(world.structures.alive_count < standing - 20, "blocks broke")
	check(world.debris.active_count > 50, "debris spawned (%d)" % world.debris.active_count)
	# Mid-pull: pieces should be closer to the core than where they started.
	var before := _mean_distance(target)
	await frames(int(params.pull_time * 60.0 * 0.8))
	var during := _mean_distance(target)
	check(during < before, "pull draws pieces in (%.2f -> %.2f)" % [before, during])
	await blast.burst
	await frames(20)
	var after := _mean_distance(target)
	check(after > during + 1.0, "burst throws pieces out (%.2f -> %.2f)" % [during, after])
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


func _mean_distance(c: Vector3) -> float:
	var d := world.debris
	var total := 0.0
	var n := 0
	for i in d.capacity:
		if d.is_active(i):
			total += d.position_of(i).distance_to(c)
			n += 1
	return total / maxf(n, 1)


func test_touch_controls_move_look_and_charge() -> void:
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
	# Hold the charge button, release to throw.
	var thrown := [false]
	p.power.thrown.connect(func(_params: BlastParams) -> void: thrown[0] = true)
	tc._on_touch(_touch(2, tc.charge_center(), true))
	await get_tree().create_timer(0.5).timeout
	check(p.power.charging and p.power.charge > 0.1, "charging while held")
	tc._on_touch(_touch(2, tc.charge_center(), false))
	await get_tree().process_frame
	await get_tree().process_frame
	check(thrown[0], "released ball")
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
