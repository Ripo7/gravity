extends TestCase
## The physics test asked for: the bell tower, cut at its foot on the palace
## side, falls onto the palace. It must tip that way, snap as it goes over
## (masonry does not bend), come down on the palace's west wing and crush
## it, and leave its rubble there. And what falls is never made to vanish:
## a black hole eats a falling piece bit by bit, a full debris pool takes
## back what is out of sight first and makes what the player can see
## crumble rather than disappear.

const GAME := preload("res://scenes/game.tscn")
const SPOT := Vector3(60, 0, 60)

var world: GameWorld


func _load() -> void:
	world = GAME.instantiate()
	world.level_path = GameState.SANDBOX
	add_child(world)
	await frames(3)
	world.player.input_enabled = false


func _unload() -> void:
	world.queue_free()
	await frames(2)


## Puts the player at `at` looking at `target`.
func _look(at: Vector3, target: Vector3) -> void:
	var p := world.player
	p.global_position = at
	p.velocity = Vector3.ZERO
	var d := target - (at + Vector3(0, 1.6, 0))
	p.rotation.y = atan2(-d.x, -d.z)
	p.head.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())


func _tower() -> Vector3:
	return (world.level.get_node("Campanile") as Node3D).global_position


## The first courses of the tower on the palace side, as a notch is cut to
## fell a tree.
func _cut_the_foot() -> void:
	var s := world.structures
	var tower := _tower()
	for i in s.segment_count():
		var p := s.transform_of(i).origin
		if (
			s.is_alive(i)
			and p.y < 4.5
			and p.x > tower.x - 1.2
			and absf(p.x - tower.x) < 4.5
			and absf(p.z - tower.z) < 4.5
		):
			s.break_segment(i)


func test_cut_on_the_palace_side_the_tower_falls_onto_the_palace() -> void:
	seed(7)
	await _load()
	var s := world.structures
	var d := world.debris
	_look(Vector3(-6, 0.05, 34), Vector3(-14, 12, -3))
	var palace := PackedInt32Array()  # its blocks as built (cracking adds cells)
	var tower := _tower()
	var built := Vector2.ZERO  # the tower's blocks as built: volume, count
	for i in s.segment_count():
		var p := s.transform_of(i).origin
		if p.x > -17.2:
			palace.append(i)
		elif absf(p.x - tower.x) < 4.5 and absf(p.z - tower.z) < 4.5:
			var z := s.size_of(i)
			built += Vector2(z.x * z.y * z.z, 1)
	# A big piece: a hundred of its blocks as built (it falls laid in stones).
	var big := 100.0 * built.x / built.y
	_cut_the_foot()
	var pieces := 0
	# Counted in physics steps: a slow machine must not see less of the fall.
	for t in 48:
		await frames(10)
		pieces = maxi(pieces, s.cluster_count())
	check(pieces >= 3, "it snapped into sections as it went over (%d pieces at once)" % pieces)
	# Blocks gone up the palace (its upper storeys and roof): the tower came
	# down on it, not beside it. How many depends on where the sections
	# land: on the wing's roof, or on into the open courtyard.
	var lost := 0
	for i in palace:
		if not s.is_alive(i) and s.transform_of(i).origin.y > 8.0:
			lost += 1
	check(lost >= 10, "it came down on the palace's west wing (%d blocks gone up there)" % lost)
	# What is left of it standing on its foot or leaning on the palace
	# crumbles within a couple of seconds more.
	var whole := INF
	for t in 5:
		whole = 0.0
		for c in s.falls.clusters:
			var v := 0.0
			for i in c.members:
				var z := s.size_of(i)
				v += z.x * z.y * z.z
			whole = maxf(whole, v)
		if whole < big:
			break
		await frames(30)
	check(whole < big, "no big piece of it was left leaning on the palace (%.0f m^3)" % whole)
	var rubble := 0
	var ruin := AABB(Vector3(-32, -1, -16), Vector3(32, 30, 28))
	for i in d.capacity:
		if d.is_active(i) and ruin.has_point(d.position_of(i)):
			rubble += 1
	check(rubble >= 100, "its rubble is there (%d pieces)" % rubble)
	await _unload()


func test_a_black_hole_eats_a_falling_piece_bit_by_bit() -> void:
	await _load()
	var s := world.structures
	var st := Structure.new()
	st.kind = Structure.Kind.WALL
	st.counts = Vector3i(10, 6, 1)
	st.block = Vector3(1, 0.5, 0.5)
	var first := s.segment_count()
	s.add_structure(Transform3D(Basis(), SPOT), st.build_segments())
	st.free()
	# Lift its base out: the wall above falls as one piece.
	for i in range(first, s.segment_count()):
		if s.transform_of(i).origin.y < 0.3:
			s.remove_segment(i)
	s.settle()
	check_eq(s.cluster_count(), 1, "the wall falls as one piece")
	var blocks := s.falls.clusters[0].members.size()
	# A hole reaching its left end only.
	s.tear_clusters(SPOT + Vector3(-5.5, 1.5, 0), 1.2)
	check_eq(s.cluster_count(), 1, "the rest still falls as one piece")
	var left := s.falls.clusters[0].members.size()
	check(
		left < blocks and left > blocks / 2,
		"only the blocks it reached were torn (%d of %d)" % [left, blocks]
	)
	# Through its middle: what is on either side falls on apart.
	s.tear_clusters(SPOT + Vector3(0.5, 1.5, 0), 1.2)
	check_eq(s.cluster_count(), 2, "cut in two, it falls as two pieces")
	await _unload()


func test_a_full_pool_takes_back_what_is_out_of_sight_first() -> void:
	await _load()
	var d := world.debris
	_look(SPOT + Vector3(0, 0, 20), SPOT + Vector3(0, 1, 0))
	await frames(2)
	# Half the pool in front of the player, half behind.
	var ahead := PackedInt32Array()
	for k in d.capacity:
		var behind := k % 2 == 1
		var at := SPOT + Vector3(k % 20 - 10.0, 0.3 + floori(k / 40.0) * 0.6, 45.0 if behind else 0.0)
		var i := d.spawn(Transform3D(Basis(), at), Vector3.ONE * 0.3)
		if not behind:
			ahead.append(i)
	await frames(40)
	for k in 40:
		d.spawn(Transform3D(Basis(), SPOT + Vector3(k % 10 - 5.0, 6, 2)), Vector3.ONE * 0.3)
	var kept := 0
	for i in ahead:
		if d.is_active(i):
			kept += 1
	check_eq(kept, ahead.size(), "everything in view is still there")
	check_eq(d.crumbled_in_view, 0, "nothing in view had to crumble")
	await _unload()


func test_a_piece_in_view_crumbles_rather_than_vanishes() -> void:
	await _load()
	var d := world.debris
	var chips := world.dust.chip_system
	_look(SPOT + Vector3(0, 0, 20), SPOT + Vector3(0, 1, 0))
	await frames(2)
	for k in d.capacity:
		var at := SPOT + Vector3(k % 20 - 10.0, 0.3 + floori(k / 20.0) % 6 * 0.6, -floori(k / 120.0) * 1.0)
		d.spawn(Transform3D(Basis(), at), Vector3.ONE * 0.3)
	await frames(40)
	var before := chips.active
	for k in 10:
		d.spawn(Transform3D(Basis(), SPOT + Vector3(k - 5.0, 6, 2)), Vector3.ONE * 0.5)
	check_eq(d.crumbled_in_view, 10, "each piece the pool took back crumbled")
	check(chips.active > before, "into gravel where it lay")
	await _unload()
