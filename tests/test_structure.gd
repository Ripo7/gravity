extends TestCase
## What holds, what falls, what stays (small structures built by hand).

var root: Node3D
var s: Structure


func test_a_wall_on_the_ground_stands() -> void:
	await _begin()
	s.add_box(Transform3D(Basis(), Vector3(0, 1.5, 0)), Vector3(4, 3, 0.35))
	s.build()
	s.recheck()
	await frames(20)
	check_eq(s.held_count, s.count, "every shard stands")
	check_eq(s.pieces.live, 0, "nothing came off")
	check(s.support.worst < 0.5, "far from its limit (%.2f)" % s.support.worst)
	await _end()


func test_what_nothing_holds_falls_and_breaks_on_landing() -> void:
	await _begin()
	# A slab in the air, bonded to nothing.
	s.add_box(Transform3D(Basis(), Vector3(0, 5, 0)), Vector3(2.4, 0.3, 2.4))
	s.build()
	s.recheck()
	await frames(10)
	check_eq(s.held_count, 0, "none of it stands")
	check_eq(s.pieces.live, 1, "it comes off in one piece")
	await frames(150)
	check(s.pieces.live > 8, "it broke on landing (%d pieces)" % s.pieces.live)
	var top := 0.0
	for i in s.pieces.alive.size():
		if s.pieces.alive[i] == 1:
			top = maxf(top, s.pieces.transform_of(i).origin.y)
	check(top < 1.5, "all of it is down (highest at %.1f m)" % top)
	check_near(s.pieces.volume(), s.total_volume, 1e-3, "nothing vanished")
	await _end()


func test_a_slab_stays_on_two_walls_and_falls_without_them() -> void:
	await _begin()
	s.add_box(Transform3D(Basis(), Vector3(-1.5, 1, 0)), Vector3(0.35, 2, 3))
	s.add_box(Transform3D(Basis(), Vector3(1.5, 1, 0)), Vector3(0.35, 2, 3))
	var slab := s.add_box(Transform3D(Basis(), Vector3(0, 2.15, 0)), Vector3(3.35, 0.3, 3))
	s.build()
	s.recheck()
	await frames(20)
	check_eq(s.held_count, s.count, "walls and slab stand")
	# Knock both walls out from under it.
	for i in s.count:
		if s.element[i] != slab:
			s.blow(i, Vector3(signf(s.centroid[i].x) * 6.0, 1.0, 0.0))
	await frames(30)
	check_eq(s.held_count, 0, "the slab no longer stands")
	await frames(120)
	check_near(s.standing_volume() + s.pieces.volume(), s.total_volume, 1e-3, "nothing vanished")
	await _end()


func test_what_sticks_out_too_far_snaps_off() -> void:
	await _begin()
	# A wall, and a slab on top of it that sticks out a long way on one side.
	s.add_box(Transform3D(Basis(), Vector3(0, 1.5, 0)), Vector3(0.5, 3, 3))
	s.add_box(Transform3D(Basis(), Vector3(4.0, 3.15, 0)), Vector3(8.5, 0.3, 3))
	s.build()
	s.recheck()
	await frames(120)
	var far_out := 0
	var held_far_out := 0
	for i in s.count:
		if s.centroid[i].x > 3.0:
			far_out += 1
			held_far_out += s.held[i]
	check(far_out > 20, "the slab has an end far out (%d shards)" % far_out)
	check_eq(held_far_out, 0, "which came down")
	var wall := 0
	for i in s.count:
		if s.centroid[i].y < 3.0:
			wall += s.held[i]
	check(wall > 10, "the wall still stands (%d shards)" % wall)
	await _end()


func test_a_shard_hit_hard_breaks_into_crumbs() -> void:
	await _begin()
	s.add_box(Transform3D(Basis(), Vector3(0, 1.5, 0)), Vector3(4, 3, 0.35))
	s.build()
	check_eq(s.crumbs_out, 0, "no crumbs to begin with")
	var big := 0
	for i in s.count:
		big += int(s.can_crumble(i))
	check(big > s.count / 2, "most shards are big enough to crumble (%d of %d)" % [big, s.count])
	# A shard in the middle of the wall.
	var hit := -1
	for i in s.count:
		if s.centroid[i].distance_to(Vector3(0, 1.5, 0)) < 0.6 and s.can_crumble(i):
			hit = i
			break
	check(hit >= 0, "there is a shard in the middle")
	s.shatter(hit, Vector3(0, 0, -6))
	await frames(3)
	var crumbs: PackedInt32Array = s.crumbs_of.get(hit, PackedInt32Array())
	var bits := crumbs.size()
	check_eq(s.held[hit], 0, "it no longer stands")
	check(bits >= 2, "it is in several crumbs (%d)" % bits)
	check_eq(s.pieces.live, bits, "each of them a piece")
	check_eq(s.crumbs_out, bits, "and counted")
	var volume := 0.0
	for c in crumbs:
		check(c >= s.count, "numbered after the shards")
		volume += s.volume[c]
	check_near(volume, s.volume[hit], s.volume[hit] * 1e-3, "that add up to the shard")
	check_near(s.standing_volume() + s.pieces.volume(), s.total_volume, 1e-3, "nothing vanished")
	await frames(60)
	check(s.place_of(hit).z < -0.5, "they were thrown through (%.1f m)" % s.place_of(hit).z)
	check_eq(s.held_count, s.count - 1, "the rest of the wall stands")
	await _end()


func test_crumbs_stop_when_there_is_no_room_left() -> void:
	await _begin()
	s.most_crumbs = 14
	s.add_box(Transform3D(Basis(), Vector3(0, 1.5, 0)), Vector3(4, 3, 0.35))
	s.build()
	for i in s.count:
		s.shatter(i, Vector3(0, 0, -6))
		await frames(1)
	check(s.crumbs_out > 0, "some crumbs were made (%d)" % s.crumbs_out)
	check(s.crumbs_out <= 14, "never more than there is room for")
	check_eq(s.held_count, 0, "every shard left all the same")
	check_near(s.pieces.volume(), s.total_volume, 1e-3, "nothing vanished")
	await _end()


func test_crumbs_that_are_gone_leave_their_room_to_others() -> void:
	await _begin()
	s.most_crumbs = 14
	s.add_box(Transform3D(Basis(), Vector3(0, 1.5, 0)), Vector3(4, 3, 0.35))
	s.build()
	# Shards crumble until there is no room left.
	var next := 0
	while next < s.count and s.crumbs_out + Structure.MAX_CRUMBS <= 14:
		s.shatter(next, Vector3(0, 0, -6))
		next += 1
		await frames(1)
	var full := s.crumbs_out
	var numbers := s.total
	check(full > 0 and not s.pieces.can_crumble(next), "the room for crumbs is full (%d)" % full)
	# Every crumb is taken away, as an orb does.
	var p := s.pieces
	var gone := 0.0
	for i in p.top:
		if p.alive[i] == 1 and p.members[i][0] >= s.count:
			gone += s.volume[p.members[i][0]]
			p.take(i)
	check_eq(s.crumbs_out, 0, "no crumb is left")
	check_near(p.taken_volume, gone, 1e-4, "what was taken is counted")
	check_near(s.standing_volume() + p.volume(), s.total_volume, 1e-3, "so nothing is unaccounted for")
	await frames(2)
	# And shards can crumble again, into the numbers that came free.
	var before := p.live
	while next < s.count and not s.can_crumble(next):
		next += 1
	s.shatter(next, Vector3(0, 0, -6))
	await frames(3)
	check(s.crumbs_out >= 2, "another shard broke into crumbs (%d)" % s.crumbs_out)
	check_eq(p.live, before + s.crumbs_out, "each of them a piece")
	check_eq(s.total, numbers, "with the numbers of those that were gone")
	var volume := 0.0
	for c: int in s.crumbs_of[next]:
		volume += s.volume[c]
	check_near(volume, s.volume[next], s.volume[next] * 1e-3, "that add up to their shard")
	await _end()


func test_pieces_come_to_rest_and_wake_when_disturbed() -> void:
	await _begin()
	s.add_box(Transform3D(Basis(), Vector3(0, 2.5, 0)), Vector3(2, 0.3, 2))
	s.build()
	s.recheck()
	await frames(300)
	var p := s.pieces
	check(p.live > 3, "it broke up (%d pieces)" % p.live)
	check_eq(p.awake, 0, "every piece came to rest")
	check_eq(p.asleep, p.live, "and was frozen")
	# The piece on top of the heap: nothing lies on it.
	var first := -1
	for i in p.top:
		if p.alive[i] == 1 and (first < 0 or p.transform_of(i).origin.y > p.transform_of(first).origin.y):
			first = i
	var was := p.transform_of(first).origin.y
	p.push(first, Vector3(0, 6, 0))
	await frames(5)
	check(p.awake >= 1, "a push wakes it")
	var rose := p.transform_of(first).origin.y - was
	check(rose > 0.1, "and it moves (up %.2f m)" % rose)
	await frames(240)
	check_eq(p.awake, 0, "then rests again")
	await _end()


func _begin() -> void:
	seed(7)
	root = Node3D.new()
	get_tree().root.add_child.call_deferred(root)
	await get_tree().process_frame
	var ground := StaticBody3D.new()
	ground.collision_layer = Structure.LAYER_WORLD
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	ground.add_child(shape)
	root.add_child(ground)
	s = Structure.new()
	root.add_child(s)


func _end() -> void:
	root.queue_free()
	await frames(2)
