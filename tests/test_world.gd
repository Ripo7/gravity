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
