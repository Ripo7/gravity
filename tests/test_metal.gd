extends TestCase
## Metal, on the bench: a blow leaves its mark where it lands (a kink in
## a post, a dent in a sheet) and the piece keeps it; it never breaks;
## marked as deep as it goes it lies down, and what it carried sags and
## comes down folding.

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
	var head := _parts(s, q)[top]
	_face(Main.METAL_POST_AT + Vector3(0, 0.05, 1.0), Main.METAL_POST_AT + Vector3.UP)
	await frames(5)
	# What the post is after each blow that lands: [what it is doing, what
	# it has taken, how far its head has gone from where it was].
	var blows := [0]
	p.blow.connect(func(_at: Vector3, _way: Vector3, _power: int, _on: RID) -> void: blows[0] += 1)
	var seen: Array[Array] = []
	for k in 500:
		if k % 6 == 0:
			p.punch()
		await frames(1)
		if blows[0] > seen.size():
			var gone := 0.0
			if s.state[q] == Structure.STANDS:
				gone = _parts(s, q)[top].distance_to(head)
			seen.append([s.state[q], s.harm[q], gone])
		if s.state[q] != Structure.STANDS:
			break
	check(seen.size() >= 5 and seen.size() <= 12, "it takes two combinations or so (%d blows)" % seen.size())
	for k in seen.size() - 1:
		check_eq(seen[k][0], Structure.STANDS, "after blow %d it stands" % (k + 1))
		check(
			k == 0 or seen[k][1] >= seen[k - 1][1], "bent no less than at the blow before (%.1f)" % seen[k][1]
		)
		check(k == 0 or seen[k][2] > seen[k - 1][2] + 0.05, "its head farther off (%.2f m)" % seen[k][2])
	check(seen[0][2] > 0.1, "the first blow already shows (its head %.2f m off)" % seen[0][2])
	check_eq(s.state[q], Structure.FALLS, "in the end it lies down")
	var b := s.bend[q]
	check(b.leans().z < 0.0 and absf(b.leans().x) < absf(b.leans().z), "bent away from the brute")
	# The fists all land within half a metre of one another, up the post:
	# one kink.
	check_eq(b.kink_at.size(), 1, "one kink")
	check(b.kink_at[0] > 1.1 and b.kink_at[0] < 1.8, "where the fists landed (%.2f m up)" % b.kink_at[0])
	# In one piece: a limb either side of the kink, and nothing else.
	var loose := s.rubble
	check_eq(loose.live, 2, "two loose bodies")
	for i in loose.body.size():
		check_eq(loose.piece[i], q, "body %d is of the post" % i)
	# (The brute steps back: what it stands against does not come to rest.)
	p.touch_move = Vector2(0, 1)
	await frames(60)
	p.touch_move = Vector2.ZERO
	await frames(150)
	var rested := await _rest(900)
	check(rested, "it comes to rest")
	check_eq(loose.live, 2, "still two")
	check_eq(s.state[q], Structure.FALLS, "never in blocks")
	var rings := _parts(s, q)
	var highest := 0.0
	for k in rings.size():
		highest = maxf(highest, rings[k].y)
		if k > 0:
			var apart := rings[k].distance_to(rings[k - 1])
			check(apart < 2.6 / top + 0.1, "ring %d is still next to the one under it (%.2f m)" % [k, apart])
	check(highest < 0.9, "lying low (its highest ring %.2f m up)" % highest)
	check(rings[top].z < Main.METAL_POST_AT.z - 1.0, "its head away from the brute (z %.2f)" % rings[top].z)
	await _unload()


func test_it_keeps_the_shape_and_a_blow_from_the_other_side_straightens_it() -> void:
	await _load()
	var q := main.metal_post
	var top := s.blocks[q] - 1
	var head := _parts(s, q)[top]
	var at := Main.METAL_POST_AT + Vector3.UP * 0.9
	s.hit(q, 4.0, Vector3.FORWARD, at)
	var bent := _parts(s, q)[top]
	check(bent.z < head.z - 0.3, "four points bend it forward (its head %.2f m off)" % (head.z - bent.z))
	check(bent.y < head.y, "its head a little lower")
	check_eq(_parts(s, q)[0], s.centroid[s.first[q]], "its foot where it was")
	await frames(120)
	check_eq(_parts(s, q)[top], bent, "left alone, it keeps the shape")
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
	check(_parts(s, q)[top].distance_to(head) < 0.001, "its head where it was")
	check_eq(s.state[q], Structure.STANDS, "and it stands")
	await _unload()


func test_a_post_kinks_at_each_height_it_is_struck_at() -> void:
	await _load()
	var q := main.metal_post
	var b := s.bend[q]
	var foot := Main.METAL_POST_AT
	var top := s.blocks[q] - 1
	s.hit(q, 4.0, Vector3.FORWARD, foot + Vector3.UP * 0.7)
	s.hit(q, 4.0, Vector3.RIGHT, foot + Vector3.UP * 1.9)
	check_eq(b.kink_at.size(), 2, "struck low, then high: two kinks")
	check_near(b.kink_at[0], 0.7, 0.01, "one where the first blow landed")
	check_near(b.kink_at[1], 1.9, 0.01, "one where the second did")
	# Between the two it leans forward only; above the second, to the
	# right as well.
	var rings := _parts(s, q)
	var between := rings[roundi(1.3 / 2.6 * top)]
	check(between.z < foot.z - 0.05, "between them it leans forward (%.2f m)" % (foot.z - between.z))
	check(absf(between.x - foot.x) < 0.02, "and not to the side (%.2f m)" % (between.x - foot.x))
	check(rings[top].x > foot.x + 0.1, "its head is off to the right (%.2f m)" % (rings[top].x - foot.x))
	check_near(s.harm[q], 4.0, 0.001, "it has taken four where it has taken the most")
	# A blow near a kink deepens that one.
	s.hit(q, 2.0, Vector3.FORWARD, foot + Vector3.UP * 0.95)
	check_eq(b.kink_at.size(), 2, "a blow a little higher: still two kinks")
	check_near(b.kink_lean[0].length(), 6.0, 0.001, "the low one is deeper")
	check_near(b.kink_lean[1].length(), 4.0, 0.001, "the high one as it was")
	check_eq(s.state[q], Structure.STANDS, "ten points in all, and it stands: no place has had fourteen")
	# Kinked as far as it goes in one place, it lies down: a limb between
	# its foot, its kinks and its head.
	s.hit(q, 8.0, Vector3.FORWARD, foot + Vector3.UP * 0.7)
	check_eq(s.state[q], Structure.FALLS, "fourteen at the low kink: it lies down")
	check_eq(s.rubble.live, 3, "three limbs")
	await _unload()


func test_a_post_that_carries_bows_and_keeps_its_head_under_what_it_carries() -> void:
	await _load()
	var q := main.piers[2]
	var top := s.blocks[q] - 1
	var head := _parts(s, q)[top]
	s.hit(q, 9.0, Vector3.FORWARD, s.place[q].origin)
	check(s.bend[q].bows, "it bows")
	var rings := _parts(s, q)
	check(rings[top].distance_to(head) < 0.001, "its head stays where it was, under the deck")
	check(rings[0].distance_to(s.centroid[s.first[q]]) < 0.001, "its foot too")
	var most := 0.0
	for k in rings.size():
		most = maxf(most, s.centroid[s.first[q] + k].z - rings[k].z)
	check(most > 0.25 and most < 0.6, "its middle goes aside (%.2f m)" % most)
	check_eq(s.state[q], Structure.STANDS, "it stands")
	check_eq(s.state[main.deck], Structure.STANDS, "and the deck with it")
	await _unload()


func test_a_post_that_gives_under_a_deck_folds_and_the_deck_sags_there() -> void:
	await _load()
	var deck := main.deck
	var b := s.bend[deck]
	var up := s.place[deck].origin.y
	var gone := main.piers[2]
	s.hit(gone, s.strength[gone], Vector3.FORWARD, s.place[gone].origin)
	check_eq(s.state[gone], Structure.FALLS, "a post kinked as far as it goes gives")
	check_eq(s.state[deck], Structure.FALLS, "the deck comes loose at once")
	var loose := s.rubble
	check_eq(
		loose.live,
		2 + b.tiles.size(),
		"the two limbs of the post, the %d triangles of the deck" % b.tiles.size()
	)
	var rested := await _rest(1800)
	check(rested, "everything comes to rest")
	# Its corner over the post that gave has come down; over the three
	# others it is where it was.
	var nodes := _parts(s, deck)
	var low := 0
	for k in nodes.size():
		var corner := b.rest(k)
		var over := -1
		for pier in main.piers:
			var foot := s.place[pier].origin
			if Vector2(corner.x - foot.x, corner.z - foot.z).length() < 0.5:
				over = pier
		if over == gone:
			low += 1
			check(
				nodes[k].y < up - 0.5,
				"its corner there has sagged (%.2f m, it was at %.2f)" % [nodes[k].y, up]
			)
		elif over >= 0:
			check(nodes[k].y > up - 0.25, "over a post that stands it is still up (%.2f m)" % nodes[k].y)
	check_eq(low, 1, "one corner was over that post")
	_check_whole(s, deck)
	# The post did not stay up under it.
	var highest := 0.0
	for ring in _parts(s, gone):
		highest = maxf(highest, ring.y)
	check(highest < 1.2, "the post that gave lies low (its highest ring %.2f m up)" % highest)
	# A second one, on the same side: that side comes down.
	var next := main.piers[3]
	s.hit(next, s.strength[next], Vector3.FORWARD, s.place[next].origin)
	rested = await _rest(1800)
	check(rested, "everything comes to rest again")
	nodes = _parts(s, deck)
	var lowest := INF
	for at in nodes:
		lowest = minf(lowest, at.y)
	check(lowest < 0.45, "the deck touches the ground (its lowest corner %.2f m up)" % lowest)
	_check_whole(s, deck)
	for q in s.pieces:
		check(s.state[q] != Structure.BROKEN or s.matter[q] != Matter.METAL, "piece %d is not in blocks" % q)
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
	check_eq(built.state[1], Structure.FALLS, "the deck is not in blocks")
	check_eq(built.bend[1].tiles.size(), 2, "it is two triangles")
	check_eq(loose.live, built.blocks[0] + 2, "the column's blocks, and those two")
	_check_whole(built, 1)
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


func test_a_sheet_takes_a_dent_under_the_fist_and_the_rest_stays_flat() -> void:
	await _load()
	var q := main.sheets[1]
	var b := s.bend[q]
	check_eq(b.kind, Bend.SHEET, "a sheet of the fence is a sheet")
	var at := Main.FENCE_AT + Vector3(0.2, 1.4, 0.04)
	var under := _nearest(b, at)
	s.hit(q, 2.0, Vector3.FORWARD, at)
	var deep := b.rest(under).z - b.node(under).z
	check_near(deep, 2.0 * Matter.DENT, 0.02, "under the fist it is pushed in, away from the blow")
	var flat := 0
	for k in b.parts:
		var off := Vector2(b.rest(k).x - at.x, b.rest(k).y - at.y).length()
		if off > Matter.DENT_WIDE:
			flat += 1
			check_eq(b.dent[k], 0.0, "node %d, %.2f m from the blow, has not moved" % [k, off])
		if k < b.across:
			check_eq(b.dent[k], 0.0, "its foot stays where it is (node %d)" % k)
	check(flat > b.parts / 2, "most of the sheet is as flat as it was (%d nodes of %d)" % [flat, b.parts])
	check_near(s.harm[q], 2.0, 0.3, "it has taken two points there")
	check_eq(s.state[q], Structure.STANDS, "it stands")
	# A blow elsewhere is another dent: the first is as it was, and two
	# shallow dents are not one deep one.
	var first_dent := b.dent[under]
	var other := Main.FENCE_AT + Vector3(-0.4, 0.6, 0.04)
	s.hit(q, 2.0, Vector3.FORWARD, other)
	check_eq(b.dent[under], first_dent, "a blow elsewhere leaves the first dent as it was")
	check(absf(b.dent[_nearest(b, other)]) > Matter.DENT, "and makes another")
	check(s.harm[q] < 2.5, "two dents, each two points deep (%.1f)" % s.harm[q])
	# From the other side, as much is taken back.
	s.hit(q, 2.0, Vector3.BACK, at)
	check_near(b.dent[under], 0.0, 0.001, "a blow from the other side pushes it back")
	# Dented as deep as it goes in one place, it lies down, with its dents.
	for k in 3:
		check_eq(s.state[q], Structure.STANDS, "before blow %d there it stands" % (k + 1))
		s.hit(q, 2.0, Vector3.FORWARD, at)
	check_eq(s.state[q], Structure.FALLS, "three blows in the same place: it lies down")
	check_eq(s.rubble.live, 1, "one loose body")
	check_eq(s.rubble.piece[0], q, "which is the sheet")
	check_near(b.dent[under], -6.0 * Matter.DENT, 0.001, "dented as it was")
	check_eq(s.state[main.sheets[0]], Structure.STANDS, "the sheet on its left stands")
	check_eq(s.harm[main.sheets[0]], 0.0, "and took nothing")
	await _unload()


func test_the_brute_dents_a_sheet_until_it_lies_down_and_the_fence_is_open() -> void:
	await _load()
	var middle := main.sheets[1]
	_face(Main.FENCE_AT + Vector3(0, 0.05, 1.0), Main.FENCE_AT + Vector3.UP)
	await frames(5)
	var blows := [0]
	p.blow.connect(func(_at: Vector3, _way: Vector3, _power: int, _on: RID) -> void: blows[0] += 1)
	var first_blow := 0.0
	for k in 600:
		if k % 6 == 0:
			p.punch()
		await frames(1)
		if blows[0] == 1 and first_blow == 0.0:
			first_blow = s.harm[middle]
		if s.state[middle] != Structure.STANDS:
			break
	check(first_blow > 1.0, "the first blow dents it (%.1f points)" % first_blow)
	check_eq(s.state[middle], Structure.FALLS, "the middle sheet lies down")
	# (The blows of a combination land apart: only the dents that are close
	# to one another add up.)
	check(blows[0] >= 3 and blows[0] <= 16, "within four combinations (%d blows)" % blows[0])
	p.touch_move = Vector2(0, 1)
	await frames(60)
	p.touch_move = Vector2.ZERO
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


## Where each part of metal piece `q` of `built` is now: the rings of a
## post from its foot up, the nodes of a sheet that stands or of a plate.
func _parts(built: Structure, q: int) -> PackedVector3Array:
	var at := PackedVector3Array()
	at.resize(built.blocks[q])
	var b := built.bend[q]
	if built.state[q] == Structure.STANDS:
		var poses: Array[Transform3D] = []
		if b.kind == Bend.POST:
			poses = b.ring_poses()
		for k in at.size():
			at[k] = poses[k].origin if b.kind == Bend.POST else b.node(k)
		return at
	var loose := built.rubble
	for i in built._loose[q]:
		var now := loose.transform_of(i) * Transform3D(Basis(), -loose.origin[i])
		for part: Array in loose._rig[i]:
			var slot: int = part[0]
			at[slot - 1 - built.first[q]] = (now * (part[1] as Transform3D)).origin
	return at


## The node of sheet `b` nearest `at`.
func _nearest(b: Bend, at: Vector3) -> int:
	var best := 0
	for k in b.parts:
		if b.rest(k).distance_to(at) < b.rest(best).distance_to(at):
			best = k
	return best


## Checks that plate `q` of `built`, come loose, is still one piece: along
## every line it folds at, its two triangles are still together.
func _check_whole(built: Structure, q: int) -> void:
	var b := built.bend[q]
	var loose := built.rubble
	var most := 0.0
	for fold in b.folds:
		for n: int in [fold[2], fold[3]]:
			var seen := PackedVector3Array()
			for tile: int in [fold[0], fold[1]]:
				var i := built._loose[q][tile]
				seen.append(loose.transform_of(i) * Transform3D(Basis(), -loose.origin[i]) * b.rest(n))
			most = maxf(most, seen[0].distance_to(seen[1]))
	check(most < 0.1, "its triangles hold together along its folds (%.2f m apart at most)" % most)


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


func test_the_brute_does_not_hold_up_what_comes_down_on_it() -> void:
	await _load()
	# Under the corner of the deck, by the post it stands on.
	var gone := main.piers[2]
	var under := s.place[gone].origin + Vector3(-0.5, 0, -0.5)
	under.y = 0.05
	_face(under, under + Vector3.FORWARD)
	await frames(10)
	s.hit(gone, s.strength[gone], Vector3.FORWARD, s.place[gone].origin)
	var rested := await _rest(1800)
	check(rested, "everything comes to rest: nothing is left lying on the brute")
	var moved := Vector2(p.global_position.x - under.x, p.global_position.z - under.z).length()
	check(moved > 0.3, "the brute was pushed out from under it (%.2f m)" % moved)
	check(moved < 3.0, "not far")
	var lowest := INF
	for at in _parts(s, main.deck):
		lowest = minf(lowest, at.y)
	check(lowest < 1.0, "the deck's corner came down past its head (%.2f m up)" % lowest)
	check(p.global_position.y < 0.3, "and the brute is on the ground (%.2f m up)" % p.global_position.y)
	await _unload()


func test_the_brute_walking_into_a_sheet_that_falls_does_not_throw_it() -> void:
	# As on the phone: things falling at real gravity, the brute striking a
	# sheet and pushing on into it as it comes down. Propped against the
	# brute and pushed at its foot, the sheet left for the sky.
	for start: Vector3 in [Vector3(0, 0.05, 1.3), Vector3(0.2, 0.05, 1.5)]:
		await _load()
		main.fall = 1.0
		var q := main.sheets[1]
		_face(Main.FENCE_AT + start, Main.FENCE_AT + Vector3(start.x, 1, 0))
		await frames(5)
		var body := -1
		var highest := 0.0
		var fastest := 0.0
		for k in 420:
			if k % 6 == 0 and (body < 0 or k % 60 < 30):
				p.punch()
			if body < 0 and s.state[q] != Structure.STANDS:
				body = s._loose[q][0]
			if body >= 0:
				p.touch_move = Vector2(0, -1) if (k / 20) % 2 == 0 else Vector2.ZERO
				highest = maxf(highest, s.rubble.transform_of(body).origin.y)
				fastest = maxf(fastest, s.rubble.velocity_of(body).length())
			await frames(1)
		p.touch_move = Vector2.ZERO
		check(body >= 0, "the sheet lies down")
		check(highest < 1.5, "its middle never goes higher than it stood (%.2f m)" % highest)
		check(fastest < Rubble.PUSH + 1.5, "nor faster than the brute shoves (%.1f m/s)" % fastest)
		await _unload()
