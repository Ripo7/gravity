extends TestCase
## What is left after a collapse: nothing floats over a big hole, floors
## crack open in place, and what falls breaks into pieces, never whole
## slabs or beams.

const SPOT := Vector3(60, 0, 60)

var world: GameWorld


func _load_world() -> void:
	world = load("res://scenes/game.tscn").instantiate()
	world.level_path = GameState.SANDBOX
	add_child(world)
	world.player.input_enabled = false
	await frames(3)


func _unload() -> void:
	world.queue_free()
	await frames(2)


func _alive_in(box: AABB) -> int:
	var s := world.structures
	var n := 0
	for i in s.segment_count():
		if s.is_alive(i) and box.has_point(s.transform_of(i).origin):
			n += 1
	return n


func test_the_roof_over_a_big_hole_falls_in() -> void:
	await _load_world()
	var s := world.structures
	# The front facade (z = 3) is knocked out over two storeys, 13 m wide.
	for i in s.segment_count():
		var p := s.transform_of(i).origin
		if s.is_alive(i) and p.y < 10.9 and absf(p.x) < 6.5 and absf(p.z - 3.0) < 6.5:
			s.break_segment(i)
	var lid := AABB(Vector3(-2.5, 14.5, -4.0), Vector3(5.0, 4.0, 8.0))
	check(_alive_in(lid) > 0, "the roof was there")
	await get_tree().create_timer(3.0).timeout
	check_eq(_alive_in(lid), 0, "nothing of the roof is left floating over the hole")
	var beside := AABB(Vector3(-17.0, 14.5, -4.0), Vector3(6.0, 4.0, 8.0))
	check(_alive_in(beside) > 0, "the roof beside the hole still stands")
	await _unload()


func test_a_small_hole_leaves_the_wall_above_standing() -> void:
	await _load_world()
	var s := world.structures
	var panel := -1
	for i in s.segment_count():
		var p := s.transform_of(i).origin
		if s.is_alive(i) and p.y > 1.0 and p.y < 5.0 and absf(p.x - 8.0) < 2.0 and p.z > 2.2:
			if s.size_of(i).x > 1.0:
				panel = i
				break
	check(panel >= 0, "a ground floor wall panel")
	var above := AABB(Vector3(5.0, 5.8, 1.5), Vector3(6.0, 10.0, 2.0))
	var before := _alive_in(above)
	s.break_segment(panel)
	await get_tree().create_timer(2.0).timeout
	var after := _alive_in(above)
	check(after >= before * 0.9, "the wall above holds (%d of %d)" % [after, before])
	await _unload()


func test_a_floor_cracks_open_in_place() -> void:
	await _load_world()
	var s := world.structures
	var slab := -1
	for i in s.segment_count():
		var sz := s.size_of(i)
		if s.is_alive(i) and sz.y < 0.5 and sz.x > 3.0 and sz.z > 3.0 and s.walls.can_crack(i):
			if s.transform_of(i).origin.y > 5.0:
				slab = i
				break
	check(slab >= 0, "the palace has floors that can crack")
	var blocks := s.segment_count()
	var at := s.transform_of(slab).origin + Vector3.UP * 0.6
	s._damage(slab, s._max_health[slab] + 0.5, at)
	check(not s.is_alive(slab), "the slab itself is gone")
	var cells := PackedInt32Array()
	for i in range(blocks, s.segment_count()):
		if s.is_alive(i):
			cells.append(i)
	check(cells.size() >= 6, "it cracked into cells (%d)" % cells.size())
	await get_tree().create_timer(1.5).timeout
	var standing := 0
	for i in cells:
		standing += 1 if s.is_alive(i) else 0
	check(
		standing * 2 >= cells.size(),
		"most of the floor still spans its walls (%d of %d)" % [standing, cells.size()]
	)
	await _unload()


func test_a_big_break_leaves_no_slab_whole() -> void:
	await _load_world()
	var d := world.debris
	var xf := Transform3D(Basis(), SPOT + Vector3(0, 3, 0))
	var out := d.shatter_box(
		xf, Vector3(5, 0.4, 5), Materials.Kind.CONCRETE, xf.origin, 0.0, Vector3.ZERO, 0, 1, 0.5, 0
	)
	check(out.size() >= 2 and out.size() <= d.max_bodies, "a few bodies (%d)" % out.size())
	for i in out:
		var sz := d.size_of(i)
		check(d.volume_of(i) <= d.max_piece * 4.0, "no big piece (%.2f m3)" % d.volume_of(i))
		check(sz[sz.max_axis_index()] < 2.0, "no long piece (%.2f m)" % sz[sz.max_axis_index()])
	check(d.chips.active > 0, "the rest is rubble")
	await _unload()


func test_a_long_moulding_breaks_into_lengths() -> void:
	await _load_world()
	var s := world.structures
	var d := world.debris
	var long := -1
	for i in s.segment_count():
		var sz := s.size_of(i)
		var l := sz[sz.max_axis_index()]
		if s.is_alive(i) and l > 4.0 and sz.x * sz.y * sz.z < 0.4 and l > 8.0 * sz[sz.min_axis_index()]:
			long = i
			break
	check(long >= 0, "the palace has long mouldings")
	var before := d.active_count
	s._dislodge(long, Vector3(0, 0, 1))
	check(d.active_count - before >= 2, "it came away in pieces (%d)" % (d.active_count - before))
	for i in d.slot_end():
		if d.is_active(i):
			var sz := d.size_of(i)
			check(sz[sz.max_axis_index()] < 2.0, "none of them long (%.2f m)" % sz[sz.max_axis_index()])
	await _unload()


func test_a_big_piece_breaks_on_a_soft_landing() -> void:
	await _load_world()
	var d := world.debris
	var broke := [0]
	d.piece_broke.connect(
		func(_at: Vector3, _size: Vector3, _kind: int, _speed: float) -> void: broke[0] += 1
	)
	# A one cubic metre block hits the ground at about 6 m/s: too slow to
	# break a stone, fast enough to break a block that big.
	d.spawn(Transform3D(Basis(), SPOT + Vector3(0, 1.3, 0)), Vector3.ONE, Vector3(0, -3.5, 0))
	await get_tree().create_timer(0.8).timeout
	check(broke[0] >= 1, "it broke when it landed")
	await _unload()
