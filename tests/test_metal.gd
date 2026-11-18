extends TestCase
## Metal, on the bench: it bends blow after blow and keeps the shape, never
## breaks, and bent as far as it goes lies down in one piece with what it
## carried.

var main: Main
var p: Player
var s: Structure


func test_walking_running_and_jumping_bend_nothing() -> void:
	await _load()
	_face(Main.FENCE_AT + Vector3(0, 0.05, 6), Main.FENCE_AT + Vector3.UP)
	p.touch_move = Vector2(0, -1)
	p.touch_sprint = true
	await frames(150)
	check(p.global_position.z > Main.FENCE_AT.z, "the fence stops the brute (z %.2f)" % p.global_position.z)
	check(p.global_position.z < Main.FENCE_AT.z + 1.0, "which ran right up to it")
	for k in 3:
		p.touch_jump = true
		await frames(50)
	p.touch_move = Vector2(1, -0.3)
	await frames(150)
	p.touch_move = Vector2.ZERO
	p.touch_sprint = false
	for q in s.pieces:
		check_eq(s.harm[q], 0.0, "piece %d took nothing" % q)
	check_eq(s.standing_count, s.pieces, "everything stands")
	check_eq(s.rubble.live, 0, "nothing came off")
	await _unload()


func test_a_post_bends_blow_after_blow_keeps_the_shape_and_never_breaks() -> void:
	await _load()
	var q := main.metal_post
	var top := s.blocks[q] - 1
	var head := s._bent(q)[top].origin
	_face(Main.METAL_POST_AT + Vector3(0, 0.05, 1.45), Main.METAL_POST_AT + Vector3.UP)
	await frames(5)
	# What the post is after each blow that lands: [what it is doing, what
	# it has taken, how far its head has gone from where it was].
	var blows := [0]
	p.blow.connect(func(_from: Vector3, _to: Vector3, _power: int) -> void: blows[0] += 1)
	var seen: Array[Array] = []
	for k in 500:
		if k % 6 == 0:
			p.punch()
		await frames(1)
		if blows[0] > seen.size():
			var gone := 0.0
			if s.state[q] == Structure.STANDS:
				gone = s._bent(q)[top].origin.distance_to(head)
			seen.append([s.state[q], s.harm[q], gone])
		if s.state[q] != Structure.STANDS:
			break
	check_eq(seen.size(), 7, "it takes a combination and a half: seven blows")
	for k in mini(seen.size(), 6):
		check_eq(seen[k][0], Structure.STANDS, "after blow %d it stands" % (k + 1))
		check(k == 0 or seen[k][1] > seen[k - 1][1], "bent more than at the blow before (%.1f)" % seen[k][1])
		check(k == 0 or seen[k][2] > seen[k - 1][2] + 0.05, "its head farther off (%.2f m)" % seen[k][2])
	check(seen[0][2] > 0.1, "the first blow already shows (its head %.2f m off)" % seen[0][2])
	check_eq(s.state[q], Structure.FALLS, "at the seventh it lies down")
	check(s.lean[q].z < 0.0 and absf(s.lean[q].x) < absf(s.lean[q].z), "bent away from the brute")
	check(s.knee[q] > 0.5 and s.knee[q] < 1.3, "where the fists landed (%.2f m up)" % s.knee[q])
	# In one piece: one loose body, which is the post.
	var loose := s.rubble
	check_eq(loose.live, 1, "one loose body")
	check_eq(loose.piece[0], q, "which is the post")
	await frames(150)
	var rested := await _rest(900)
	check(rested, "it comes to rest")
	check_eq(loose.live, 1, "still one")
	check_eq(s.state[q], Structure.FALLS, "never in blocks")
	# Where the bend has put each of its rings, and where the post is now.
	var now := loose.transform_of(0) * Transform3D(Basis(), -loose.origin[0])
	var highest := 0.0
	for pose in s._bent(q):
		highest = maxf(highest, (now * pose).origin.y)
	check(highest < 0.9, "lying low (its highest ring %.2f m up)" % highest)
	var head_now := (now * s._bent(q)[top]).origin
	check(head_now.z < Main.METAL_POST_AT.z - 1.0, "its head away from the brute (z %.2f)" % head_now.z)
	await _unload()


func test_it_keeps_the_shape_and_a_blow_from_the_other_side_straightens_it() -> void:
	await _load()
	var q := main.metal_post
	var top := s.blocks[q] - 1
	var head := s._bent(q)[top].origin
	var at := Main.METAL_POST_AT + Vector3.UP * 0.9
	s.hit(q, 4.0, Vector3.FORWARD, at)
	var bent := s._bent(q)[top].origin
	check(bent.z < head.z - 0.3, "four points bend it forward (its head %.2f m off)" % (head.z - bent.z))
	check(bent.y < head.y, "its head a little lower")
	check_eq(s._bent(q)[0].origin, s.centroid[s.first[q]], "its foot where it was")
	await frames(120)
	check_eq(s._bent(q)[top].origin, bent, "left alone, it keeps the shape")
	# What runs into it now meets it where it is: nothing where its head
	# was, something where its head is.
	var space := main.get_world_3d().direct_space_state
	var across := Vector3(1, 0, 0)
	var was := PhysicsRayQueryParameters3D.create(
		head - across - Vector3.UP * 0.2, head + across - Vector3.UP * 0.2
	)
	was.collision_mask = Layers.STRUCTURE
	check(space.intersect_ray(was).is_empty(), "nothing is left where its head was")
	var now := PhysicsRayQueryParameters3D.create(
		bent - across - Vector3.UP * 0.2, bent + across - Vector3.UP * 0.2
	)
	now.collision_mask = Layers.STRUCTURE
	check(not space.intersect_ray(now).is_empty(), "it is in the way where its head is")
	# From the other side.
	s.hit(q, 2.0, Vector3.BACK, at)
	check_near(s.harm[q], 2.0, 0.001, "two points back: half the bend is gone")
	s.hit(q, 2.0, Vector3.BACK, at)
	check_near(s.harm[q], 0.0, 0.001, "two more: it is straight")
	check(s._bent(q)[top].origin.distance_to(head) < 0.001, "its head where it was")
	check_eq(s.state[q], Structure.STANDS, "and it stands")
	await _unload()


func test_a_post_that_carries_bows_and_keeps_its_head_under_what_it_carries() -> void:
	await _load()
	var q := main.piers[2]
	var top := s.blocks[q] - 1
	var head := s._bent(q)[top].origin
	s.hit(q, 9.0, Vector3.FORWARD, s.place[q].origin)
	check_eq(s.bows[q], 1, "it bows")
	var poses := s._bent(q)
	check(poses[top].origin.distance_to(head) < 0.001, "its head stays where it was, under the deck")
	check(poses[0].origin.distance_to(s.centroid[s.first[q]]) < 0.001, "its foot too")
	var most := 0.0
	for k in poses.size():
		most = maxf(most, s.centroid[s.first[q] + k].z - poses[k].origin.z)
	check(most > 0.25 and most < 0.6, "its middle goes aside (%.2f m)" % most)
	check_eq(s.state[q], Structure.STANDS, "it stands")
	check_eq(s.state[main.deck], Structure.STANDS, "and the deck with it")
	await _unload()


func test_bent_as_far_as_it_goes_it_lies_down_with_what_it_carried() -> void:
	await _load()
	var up := s.place[main.deck].origin.y
	s.hit(main.piers[2], s.strength[main.piers[2]], Vector3.FORWARD)
	check_eq(s.state[main.piers[2]], Structure.FALLS, "a post bent as far as it goes lies down")
	await frames(60)
	check_eq(s.state[main.deck], Structure.STANDS, "on three posts the deck holds")
	s.hit(main.piers[3], s.strength[main.piers[3]], Vector3.FORWARD)
	check_eq(s.state[main.deck], Structure.FALLS, "with two gone on one side it comes down")
	var loose := s.rubble
	check_eq(loose.live, 3, "three loose bodies: two posts and the deck")
	var rested := await _rest(1500)
	check(rested, "everything comes to rest")
	# Metal lands in one piece: every loose body is a whole piece still. (A
	# post left standing may have lain down too, under the deck.)
	var down := 0
	for q in s.pieces:
		check(s.state[q] != Structure.BROKEN, "piece %d is not in blocks" % q)
		if s.state[q] == Structure.FALLS:
			down += 1
	check_eq(loose.live, down, "as many loose bodies as pieces that came down (%d)" % down)
	var decks := 0
	var deck_now := 0.0
	for i in loose.body.size():
		check(loose.piece[i] >= 0, "loose body %d is a whole piece" % i)
		if loose.piece[i] == main.deck:
			decks += 1
			deck_now = loose.transform_of(i).origin.y
	check_eq(decks, 1, "one of them is the deck")
	check(deck_now < up - 0.3, "the deck is no longer up there (%.2f m, it was at %.2f)" % [deck_now, up])
	await _unload()


func test_metal_that_comes_down_from_high_lands_whole() -> void:
	await _load()
	# A deck on one tall concrete column: the column gone, it falls 6 m.
	var built := _alone(
		[
			[Matter.CONCRETE, Vector3(0.4, 6.0, 0.4), Vector3(60, 0, 0)],
			[Matter.METAL, Vector3(2.0, 0.12, 2.0), Vector3(60, 6.0, 0)],
		]
	)
	built.hit(0, built.strength[0], Vector3.FORWARD)
	check_eq(built.state[1], Structure.FALLS, "the deck comes down")
	var loose := built.rubble
	for k in 1500:
		await frames(1)
		if loose.awake == 0:
			break
	check_eq(loose.awake, 0, "everything comes to rest")
	check_eq(built.state[1], Structure.FALLS, "the deck is in one piece")
	check_eq(loose.live, built.blocks[0] + 1, "the column's blocks, and one deck")
	built.free()
	await _unload()


func test_what_lands_on_metal_bends_it() -> void:
	await _load()
	# A metal post, and over it a heavy concrete slab that rests on a tall
	# column to one side.
	var built := _alone(
		[
			[Matter.METAL, Vector3(0.2, 1.4, 0.2), Vector3(60, 0, 0)],
			[Matter.CONCRETE, Vector3(0.4, 3.0, 0.4), Vector3(61.2, 0, 0)],
			[Matter.CONCRETE, Vector3(3.0, 0.6, 2.0), Vector3(60, 3.0, 0)],
		]
	)
	built.hit(1, built.strength[1], Vector3.RIGHT)
	check_eq(built.state[2], Structure.FALLS, "the slab comes down")
	for k in 600:
		await frames(1)
		if built.harm[0] > 0.0:
			break
	check(built.harm[0] > 0.0, "it lands on the post and bends it (%.1f points)" % built.harm[0])
	check(built.state[0] != Structure.BROKEN, "which does not break")
	built.free()
	await _unload()


func test_a_sheet_folds_then_lies_down_and_the_fence_is_open() -> void:
	await _load()
	var middle := main.sheets[1]
	_face(Main.FENCE_AT + Vector3(0, 0.05, 1.5), Main.FENCE_AT + Vector3.UP)
	await frames(5)
	for k in 300:
		if k % 6 == 0:
			p.punch()
		await frames(1)
		if s.state[middle] != Structure.STANDS:
			break
	check_eq(s.state[middle], Structure.FALLS, "the middle sheet lies down")
	await frames(150)  # the blow runs its course
	var rested := await _rest(900)
	check(rested, "it comes to rest")
	check_eq(s.state[main.sheets[0]], Structure.STANDS, "the sheet on its left stands")
	check_eq(s.state[main.sheets[2]], Structure.STANDS, "the one on its right too")
	check_eq(s.rubble.live, 1, "one loose body: the sheet")
	# The way is open: the brute goes through where the sheet was, over it.
	_face(Main.FENCE_AT + Vector3(0, 0.05, 2.0), Main.FENCE_AT + Vector3.UP)
	p.touch_move = Vector2(0, -1)
	await frames(240)
	p.touch_move = Vector2.ZERO
	check(
		p.global_position.z < Main.FENCE_AT.z - 1.5, "the brute walks through (z %.2f)" % p.global_position.z
	)
	check_eq(s.standing_count, s.pieces - 1, "bending nothing on its way")
	await _unload()


## Puts the brute at `at`, its body turned to `target`, the camera behind.
func _face(at: Vector3, target: Vector3) -> void:
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.facing = atan2(at.x - target.x, at.z - target.z)
	p.look(Vector2(angle_difference(p.yaw, p.facing), 0.0))


## Waits for everything loose to come to rest, `most` steps at most.
## Returns whether it did.
func _rest(most: int) -> bool:
	for k in most:
		await frames(1)
		if s.rubble.awake == 0:
			return true
	return false


## A structure of its own, away from the bench: pieces, each [matter, size,
## where its foot is].
func _alone(pieces: Array) -> Structure:
	var built := Structure.new()
	main.add_child(built)
	for piece: Array in pieces:
		var size: Vector3 = piece[1]
		var foot: Vector3 = piece[2]
		built.add_piece(piece[0], Transform3D(Basis(), foot + Vector3.UP * size.y * 0.5), size)
	built.build()
	return built


func _load() -> void:
	seed(5)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await frames(20)
	p = main.player
	s = main.structure


func _unload() -> void:
	main.queue_free()
	await frames(2)
