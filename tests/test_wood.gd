extends TestCase
## Wood, on the bench: it snaps clean where it is struck, at the first
## blow; the length the blow lands on goes as small wood, what was above
## is cut off in one and thrown far; it stays in long pieces on the
## ground, and comes apart into small wood when it is struck again; what
## it carried comes down whole.

var main: Main
var p: Player
var s: Structure


func test_walking_running_and_jumping_break_no_wood() -> void:
	await _load()
	# (Beside the post that stands before it.)
	_face(Main.PALISADE_AT + Vector3(0.9, 0.05, 5), Main.PALISADE_AT + Vector3(0.9, 1, 0))
	p.touch_move = Vector2(0, -1)
	p.touch_sprint = true
	await frames(140)
	check(
		p.global_position.z > Main.PALISADE_AT.z,
		"the palisade stops the brute (z %.2f)" % p.global_position.z
	)
	check(p.global_position.z < Main.PALISADE_AT.z + 1.0, "which ran right up to it")
	for k in 3:
		p.touch_jump = true
		await frames(50)
	p.touch_move = Vector2(-1, -0.3)
	await frames(120)
	p.touch_move = Vector2.ZERO
	p.touch_sprint = false
	for q in s.pieces:
		check_eq(s.harm[q], 0.0, "piece %d took nothing" % q)
	check_eq(s.standing_count, s.pieces, "everything stands")
	check_eq(s.rubble.live, 0, "nothing came off")
	await _unload()


func test_a_plank_snaps_where_it_is_struck_at_the_first_blow() -> void:
	await _load()
	var q := main.planks[4]
	var all := s.blocks[q]
	var at := s.place[q].origin * Vector3(1, 0, 1) + Vector3(0, 0.9, Main.PLANK.z * 0.5)
	check(s.strike(at, Vector3.FORWARD, 2, s.body_of(q)), "a blow lands on a plank, 0.9 m up")
	# Its foot stands; the length the blow landed on is out, and what was
	# above is one loose piece.
	check_eq(s.state[q], Structure.STANDS, "what is left of it stands")
	var left := 0
	for i in range(s.first[q], s.first[q] + all):
		if s.stands[i] == 1:
			left += 1
			check(s.centroid[i].y < 0.9, "length %d still stands, below the blow" % i)
	check(left >= 1 and left <= 2, "its foot (%d lengths of %d)" % [left, all])
	var loose := s.rubble
	check_eq(loose.live, 2, "two loose bodies")
	var long := -1
	var small := -1
	for i in loose.body.size():
		if s._clumps.has(i):
			long = i
		else:
			small = i
	check(long >= 0 and small >= 0, "one long, in one, and one small")
	if long < 0 or small < 0:
		await _unload()
		return
	check(
		s._clumps[long].size() >= 3,
		"the long one is all that was above (%d lengths)" % s._clumps[long].size()
	)
	check(
		loose.mass[long] < 20.0 and loose.mass[small] < 6.0,
		"both light (%.1f and %.1f kg)" % [loose.mass[long], loose.mass[small]]
	)
	for other: int in [main.planks[3], main.planks[5]]:
		check_eq(s.harm[other], 0.0, "the plank beside it took nothing")
		check_eq(s.state[other], Structure.STANDS, "and stands")
	var rested := await _rest(900)
	check(rested, "they come to rest")
	check(s._clumps.has(long), "the long one is still in one: wood does not break when it lands")
	var far_long := Main.PALISADE_AT.z - loose.transform_of(long).origin.z
	var far_small := Main.PALISADE_AT.z - loose.transform_of(small).origin.z
	check(far_long > 2.5, "thrown far, away from the blow (%.1f m)" % far_long)
	check(far_small > 1.5, "the small one too (%.1f m)" % far_small)
	check(
		loose.transform_of(long).origin.y < 0.3,
		"it lies flat (%.2f m up)" % loose.transform_of(long).origin.y
	)
	# Struck again where it lies, it comes apart into small wood.
	var lengths: int = s._clumps[long].size()
	check(
		s.strike(loose.transform_of(long).origin + Vector3.UP * 0.05, Vector3.FORWARD, 2),
		"a blow lands on it"
	)
	check(not s._clumps.has(long), "it is no longer in one")
	check_eq(loose.live, 1 + lengths, "its %d lengths are loose, each by itself" % lengths)
	check_eq(s.state[q], Structure.STANDS, "the foot of the plank still stands")
	await _unload()


func test_a_wooden_post_is_cut_by_one_blow() -> void:
	await _load()
	var q := main.wood_post
	var all := s.blocks[q]
	var at := Main.WOOD_POST_AT + Vector3(0, 1.1, Main.WOOD_POST.z * 0.5)
	s.strike(at, Vector3.FORWARD, 2, s.body_of(q))
	var left := 0
	for i in range(s.first[q], s.first[q] + all):
		left += s.stands[i]
	check(left >= 1 and left < all - 1, "one blow cuts it: its foot stands (%d lengths of %d)" % [left, all])
	check_eq(s.state[q], Structure.STANDS, "what is left of it stands")
	check_eq(s.rubble.live, 2, "the length that was struck, and what was above in one")
	for other in s.pieces:
		check(other == q or s.harm[other] == 0.0, "piece %d took nothing" % other)
	await _unload()


func test_the_brute_snaps_the_planks_its_fists_land_on_and_walks_through() -> void:
	await _load()
	_face(Main.PALISADE_AT + Vector3(0, 0.05, 1.5), Main.PALISADE_AT + Vector3.UP)
	await frames(5)
	var thrown := [0]
	p.blow.connect(func(_at: Vector3, _way: Vector3, _power: int, _on: RID) -> void: thrown[0] += 1)
	var after_one := -1
	for k in 600:
		if k % 6 == 0:
			p.punch()
		await frames(1)
		if thrown[0] == 1 and after_one < 0:
			after_one = _snapped()
		if thrown[0] >= 8:
			break
	check_eq(after_one, 1, "its first blow snaps a plank: the one its fist lands on")
	var open := _snapped()
	check(open >= 4, "two combinations snap several: each blow its own (%d planks)" % open)
	for q in main.planks:
		check_eq(s.state[q], Structure.STANDS, "plank %d: its foot stands, or all of it" % q)
	await frames(120)
	# Through the gap, over the feet of the planks and the small wood.
	_face(Main.PALISADE_AT + Vector3(0, 0.05, 2.0), Main.PALISADE_AT + Vector3.UP)
	p.touch_move = Vector2(0, -1)
	var through := false
	for k in 5:
		await frames(60)
		if p.global_position.z < Main.PALISADE_AT.z - 1.5:
			through = true
			break
		for j in 3:
			p.punch()
			await frames(20)
	p.touch_move = Vector2.ZERO
	check(through, "the brute walks through (z %.2f)" % p.global_position.z)
	await _unload()


func test_small_wood_does_not_stop_the_brute() -> void:
	await _load()
	# Three planks, in lengths, lying in its way.
	for k in 3:
		s.hit(main.planks[6 + k], 2.0, Vector3.BACK)
	await _rest(900)
	check(s.rubble.live >= 15, "small wood lies before the palisade (%d lengths)" % s.rubble.live)
	var gap := (6 + 1 - (Main.PLANKS - 1) * 0.5) * Main.PLANK.x
	_face(Main.PALISADE_AT + Vector3(gap, 0.05, 6), Main.PALISADE_AT + Vector3(gap, 1, 0))
	p.touch_move = Vector2(0, -1)
	await frames(90)
	var before := p.global_position.z
	await frames(60)
	p.touch_move = Vector2.ZERO
	var pace := (before - p.global_position.z) / 1.0
	check(
		p.global_position.z < Main.PALISADE_AT.z - 0.5,
		"it goes through where the planks were (z %.2f)" % p.global_position.z
	)
	check(pace > Character.JOG_PACE * 0.6, "without being stopped (%.1f m/s)" % pace)
	await _unload()


func test_a_post_snapped_under_the_floor_brings_down_what_it_carried_whole() -> void:
	await _load()
	var q := main.stilts[0]
	var at := s.place[q].origin * Vector3(1, 0, 1) + Vector3(0, 0.9, Main.STILT.z * 0.5)
	s.strike(at, Vector3.FORWARD, 2, s.body_of(q))
	await frames(30)
	var rested := await _rest(1200)
	check(rested, "what comes down comes to rest")
	var beam := -1
	for b in main.beams:
		if q in s.rests_on[b]:
			beam = b
	check_eq(s.state[beam], Structure.FALLS, "the beam it carried is down")
	check_eq(s._loose[beam].size(), 1, "in one piece")
	for b in main.beams:
		check(b == beam or s.state[b] == Structure.STANDS, "the other beam stands")
	for other in main.stilts:
		check(other == q or s.harm[other] == 0.0, "the other posts took nothing")
	for board in main.boards:
		check_eq(s.state[board], Structure.FALLS, "board %d is down" % board)
		check_eq(s._loose[board].size(), 1, "whole")
	check_eq(s.rubble.live, 2 + 1 + main.boards.size(), "nothing else came off")
	await _unload()


## How many planks of the palisade have lost something.
func _snapped() -> int:
	var count := 0
	for q in main.planks:
		for i in range(s.first[q], s.first[q] + s.blocks[q]):
			if s.stands[i] == 0:
				count += 1
				break
	return count


## Puts the brute at `at`, facing `target`.
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
