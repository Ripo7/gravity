extends TestCase
## The bench itself: a bare ground, one brute, what stands on it to be
## broken (concrete on one side, metal on the other, wood ahead, glass
## behind, a house on its right), no sun shadow, a round shadow that stays
## on the ground, and the button that puts it all back.

var main: Main


func test_the_bench_is_a_bare_ground_with_one_brute_and_things_to_break() -> void:
	await _load()
	var p := main.player
	var s := main.structure
	check(p.is_on_floor(), "the brute stands on the ground")
	check_near(p.global_position.y, 0.0, 0.05, "which is at 0")
	var brutes := 0
	var suns := 0
	for child in main.get_children():
		if child is CharacterBody3D:
			brutes += 1
		if child is DirectionalLight3D:
			suns += 1
			check(not (child as DirectionalLight3D).shadow_enabled, "the sun casts no shadow")
	check_eq(brutes, 1, "one brute")
	check_eq(suns, 1, "one sun")
	# What stands, in concrete and again in metal: a column, a wall (in
	# one piece in concrete, three sheets in metal), a slab on four
	# columns.
	# And in wood: a post, a palisade of ten planks, a floor of eight
	# boards on two beams on four posts.
	# And in glass: three panes.
	# And a house, in wood, of forty-seven pieces (see test_house.gd).
	var house: Array[int] = [main.house_ridge]
	for group: PackedInt32Array in [main.house_walls, main.house_gables, main.house_roof]:
		house.append_array(Array(group))
	check_eq(house.size(), 47, "forty-seven pieces to the house")
	check_eq(s.pieces, 44 + 47, "ninety-one pieces")
	check_eq(s.standing_count, s.pieces, "all standing")
	check_eq(main.panes.size(), 3, "three panes")
	check_eq(main.planks.size(), 10, "ten planks to the palisade")
	for beam in main.beams:
		check_eq(Array(s.rests_on[beam]).size(), 2, "beam %d rests on two posts" % beam)
	for board in main.boards:
		check_eq(Array(s.rests_on[board]), Array(main.beams), "board %d rests on the two beams" % board)
	check(main.wall >= 0, "a wall")
	check_eq(main.sheets.size(), 3, "three sheets to the fence")
	check_eq(Array(s.rests_on[main.slab]).size(), 4, "the slab rests on its four columns")
	check_eq(Array(s.rests_on[main.deck]).size(), 4, "the deck rests on its four posts")
	for post in main.posts:
		check(post in s.rests_on[main.slab], "column %d carries the slab" % post)
	for pier in main.piers:
		check(pier in s.rests_on[main.deck], "post %d carries the deck" % pier)
	var concrete: Array[int] = [main.column, main.slab, main.wall]
	concrete.append_array(Array(main.posts))
	var wood: Array[int] = [main.wood_post]
	for group: PackedInt32Array in [main.planks, main.stilts, main.beams, main.boards]:
		wood.append_array(Array(group))
	var carried: Array[int] = [main.slab, main.deck]
	carried.append_array(Array(main.beams))
	carried.append_array(Array(main.boards))
	for q in s.pieces:
		var made_of := Matter.CONCRETE if q in concrete else (Matter.WOOD if q in wood else Matter.METAL)
		if q in main.panes:
			made_of = Matter.GLASS
		if q in house:
			var from := s.place[q].origin - p.global_position
			check(
				from.x > 5.0 and from.x < 9.0 and absf(from.z) < 4.0, "piece %d is on the brute's right" % q
			)
			continue
		check_eq(s.matter[q], made_of, "piece %d is made of what it should be" % q)
		check(q in carried or s.rests_on[q].is_empty(), "piece %d stands on the ground" % q)
		# Concrete to the brute's right as it starts, metal to its left,
		# wood between them and farther off.
		var at := s.place[q].origin
		if made_of == Matter.GLASS:
			check(absf(at.x) < 2.0 and at.z > 3.0, "piece %d is behind the brute as it starts" % q)
			check_eq(s.blocks[q], 1, "piece %d is not cut: it bursts" % q)
		elif made_of == Matter.WOOD:
			check(absf(at.x) < 2.0 and at.z < -9.5, "piece %d is ahead, past the others" % q)
			check(
				s.blocks[q] >= 5 and s.blocks[q] <= 10,
				"piece %d is cut into a few lengths (%d)" % [q, s.blocks[q]]
			)
		else:
			check(
				at.x * (1.0 if made_of == Matter.CONCRETE else -1.0) > 0.5,
				"piece %d is on its matter's side" % q
			)
		if made_of == Matter.CONCRETE:
			check(
				s.blocks[q] >= 2 and s.blocks[q] <= Matter.MOST_BLOCKS,
				"piece %d is cut into a few blocks (%d)" % [q, s.blocks[q]]
			)
	check_eq(s.rubble.live, 0, "nothing lies loose")
	# All of it but the glass and the house in front of the brute as it
	# starts, a few steps away.
	for q in s.pieces:
		if q in main.panes or q in house:
			continue
		var to := s.place[q].origin - p.global_position
		check(to.z < -4.0 and to.z > -21.0 and absf(to.x) < 11.0, "piece %d is in front of the brute" % q)
	# Far from the middle the ground is still there.
	p.global_position = Vector3(150, 0.05, -150)
	await frames(30)
	check(p.is_on_floor(), "the ground goes on far from the middle")
	await _unload()


func test_the_round_shadow_stays_on_the_ground() -> void:
	await _load()
	var p := main.player
	var blob: BlobShadow
	for child in main.get_children():
		if child is BlobShadow:
			blob = child
	check(blob != null, "the brute has a round shadow")
	if blob == null:
		await _unload()
		return
	await frames(3)
	var under := blob.global_position - p.global_position
	check(Vector2(under.x, under.z).length() < 0.05 and blob.visible, "at its feet")
	p.touch_move = Vector2(0, 1)  # away from what stands on the bench
	await frames(30)
	p.touch_jump = true
	var top := 0.0
	var highest := 0.0
	for k in 50:
		await frames(1)
		top = maxf(top, p.global_position.y)
		highest = maxf(highest, blob.global_position.y)
	p.touch_move = Vector2.ZERO
	check(top > 1.2, "the brute jumps (%.1f m)" % top)
	check(highest < 0.1, "its shadow stays on the ground (%.2f m)" % highest)
	under = blob.global_position - p.global_position
	check(
		Vector2(under.x, under.z).length() < 0.2,
		"and follows it (%.2f m off)" % Vector2(under.x, under.z).length()
	)
	await _unload()


func test_rebuilding_puts_the_bench_back() -> void:
	await _load()
	var s := main.structure
	var s_pieces := s.pieces
	s.hit(main.column, s.strength[main.column], Vector3.FORWARD)
	s.hit(main.posts[0], s.strength[main.posts[0]], Vector3.FORWARD)
	s.hit(main.posts[1], s.strength[main.posts[1]], Vector3.FORWARD)
	await frames(30)
	s.hit(main.metal_post, s.strength[main.metal_post], Vector3.FORWARD)
	s.hit(main.planks[0], s.strength[main.planks[0]], Vector3.FORWARD)
	s.hit(main.panes[0], 1.0, Vector3.FORWARD)
	# (One end of the ridge of the house: its whole roof comes down.)
	for q in s.rests_on[main.house_ridge]:
		if s.place[q].origin.z > Main.HOUSE_AT.z:
			s.hit(q, 2.0, Vector3.FORWARD, s.place[q].origin + Vector3.UP * (s.size[q].y * 0.5 - 0.1))
	check(s.standing_count < s.pieces - 16 and s.rubble.live > 0, "things are down")
	main.fall = 0.6
	main.player.global_position = Vector3(3, 0.05, 3)
	main.rebuild()
	await frames(5)
	check(main.structure != s and not is_instance_valid(s), "what stood is gone")
	check_eq(main.structure.standing_count, main.structure.pieces, "and stands again")
	check_eq(main.structure.pieces, s_pieces, "all of it")
	for q in main.house_roof:
		check_eq(
			main.structure.state[q], Structure.STANDS, "board %d of the roof of the house is up again" % q
		)
	check_eq(main.structure.glitter.bursts, 0, "no glitter is left")
	check_eq(main.structure.harm[main.metal_post], 0.0, "what was bent is straight")
	check_eq(main.structure.rubble.live, 0, "nothing lies loose")
	check_near(main.structure.rubble.fall, 0.6, 0.001, "things still fall as fast as they were set to")
	check(main.player.global_position.distance_to(Main.START) < 0.3, "the brute is back where it starts")
	await _unload()


func _load() -> void:
	seed(5)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await frames(20)


func _unload() -> void:
	main.queue_free()
	await frames(2)
