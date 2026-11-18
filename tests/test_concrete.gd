extends TestCase
## Concrete, on the bench: it cracks where it is struck, then the blocks
## round the fist are knocked out and what they held up comes down and
## lies low; the rest stands; it carries; only a blow breaks it.

var main: Main
var p: Player
var s: Structure


func test_walking_running_and_jumping_break_nothing() -> void:
	await _load()
	# Straight at the wall, at a sprint.
	_face(Main.WALL_AT + Vector3(0, 0.05, 6), Main.WALL_AT + Vector3.UP)
	p.touch_move = Vector2(0, -1)
	p.touch_sprint = true
	await frames(150)
	check(p.global_position.z > Main.WALL_AT.z, "the wall stops the brute (z %.2f)" % p.global_position.z)
	check(p.global_position.z < Main.WALL_AT.z + 1.0, "which ran right up to it")
	# Jumping against it, then along it and into the column.
	for k in 3:
		p.touch_jump = true
		await frames(50)
	p.touch_move = Vector2(-1, -0.3)
	await frames(120)
	p.touch_move = Vector2.ZERO
	p.touch_sprint = false
	for q in s.pieces:
		check_eq(s.harm[q], 0.0, "piece %d took nothing" % q)
		check_eq(s.cracks[q], 0, "piece %d shows no crack" % q)
	check_eq(s.standing_count, s.pieces, "everything stands")
	check_eq(s.rubble.live, 0, "nothing came off")
	await _unload()


func test_a_column_cracks_where_the_fists_land_then_is_cut_there() -> void:
	await _load()
	var q := main.column
	var all := s.blocks[q]
	_face(Main.COLUMN_AT + Vector3(0, 0.05, 1.0), Main.COLUMN_AT + Vector3.UP)
	await frames(5)
	# Where each blow lands on the column; what it shows after the first,
	# and where it shows cracks once three have landed.
	var landed: Array[Vector3] = []
	p.blow.connect(
		func(at: Vector3, _way: Vector3, _power: int, on: RID) -> void:
			if s.standing(on) == q:
				landed.append(at)
	)
	var first: Array = []
	var cracked := 0
	var cracked_far := 0
	for k in 900:
		if k % 6 == 0:
			p.punch()
		await frames(1)
		if landed.size() == 1 and first.is_empty():
			first = [s.cracks[q], s.harm[q], _standing(s, q)]
		if landed.size() == 3 and cracked == 0:
			for i in range(s.first[q], s.first[q] + all):
				if s._shows[i] == 0:
					continue
				cracked += 1
				var off := 9.0
				for at in landed:
					off = minf(off, s.centroid[i].distance_to(at))
				if off > Structure.HOLE + 0.4:
					cracked_far += 1
		if _standing(s, q) < all:
			break
	check_eq(first, [1, 2.0, all], "after the first blow it stands, cracked")
	check(cracked > 0, "three blows on, blocks show cracks (%d)" % cracked)
	check_eq(cracked_far, 0, "all of them round where a fist landed")
	check(_standing(s, q) < all, "blocks are knocked out in the end")
	check(
		landed.size() >= 3 and landed.size() <= 8, "within two combinations (%d blows on it)" % landed.size()
	)
	for at in landed:
		var off := Vector2(at.x - Main.COLUMN_AT.x, at.z - Main.COLUMN_AT.z)
		check(
			maxf(absf(off.x), absf(off.y)) < 0.23,
			"a blow lands on the column itself (%s)" % at.snappedf(0.01)
		)
	check(all >= 5 and all <= 8, "the column is five to eight blocks (%d)" % all)
	for other in s.pieces:
		check(other == q or s.harm[other] == 0.0, "piece %d took nothing" % other)
	# It is cut where the fists landed: what was above comes down, away
	# from the brute, and lies low; what is left standing is below them.
	p.touch_move = Vector2(0, 1)
	await frames(40)
	p.touch_move = Vector2.ZERO
	await frames(150)  # the blows run their course
	var rested := await _rest(900)
	check(rested, "what came off comes to rest")
	var left := 0
	for i in range(s.first[q], s.first[q] + all):
		if s.stands[i] == 1:
			left += 1
			check(s.centroid[i].y < landed[0].y, "block %d still stands, below the fists" % i)
	check(left >= 1, "its foot stands (%d blocks)" % left)
	var loose := s.rubble
	check(loose.live >= 2, "what came off is at least two bodies (%d)" % loose.live)
	for i in loose.body.size():
		if loose.alive[i] == 0:
			continue
		var at := loose.transform_of(i).origin
		check(at.y < 0.8, "body %d lies low (its middle %.2f m up)" % [i, at.y])
		check(at.distance_to(Main.COLUMN_AT) < 8.0, "body %d did not fly off (%s)" % [i, at.snappedf(0.1)])
	await _unload()


func test_a_column_struck_half_way_up_is_cut_there() -> void:
	await _load()
	# A tall column, struck 2 m up with all a place can take.
	var built := _alone(1, [[Vector3(0.4, 3.9, 0.4), Vector3(60, 0, 0)]])
	var all := built.blocks[0]
	var at := Vector3(60, 2.0, 0.2)
	built.hit(0, 4.0, Vector3.FORWARD, at)
	check_eq(_standing(built, 0), all, "four points: every block stands")
	var cracked := 0
	for i in all:
		if built._shows[i] > 0:
			cracked += 1
			check(absf(built.centroid[i].y - 2.0) < 0.8, "block %d, cracked, is by the blow" % i)
	check(
		cracked >= 1 and cracked < all, "the blocks round the blow show cracks, not the others (%d)" % cracked
	)
	built.hit(0, 5.0, Vector3.FORWARD, at)
	check_eq(built.state[0], Structure.STANDS, "nine points there: the column still stands")
	var stump := 0
	for i in all:
		if built.stands[i] == 1:
			stump += 1
			check(built.centroid[i].y < 2.0, "block %d stands, below the blow" % i)
	check(stump >= 1, "its foot is left standing (%d blocks)" % stump)
	var loose := built.rubble
	var top := -1
	for i in loose.body.size():
		if loose.piece[i] == 0:
			top = i
	check(top >= 0, "what was above comes down in one")
	check(loose.live < all - stump, "fewer bodies than blocks came off (%d)" % loose.live)
	for k in 1500:
		await frames(1)
		if loose.awake == 0:
			break
	check_eq(loose.awake, 0, "everything comes to rest")
	check_eq(loose.live, all - stump, "it broke into its blocks when it landed")
	for i in loose.body.size():
		if loose.alive[i] == 1:
			var lies := loose.transform_of(i).origin
			check(lies.y < 0.9, "body %d lies low (%.2f m up)" % [i, lies.y])
	check_eq(built.state[0], Structure.STANDS, "and the foot of the column stands")
	built.free()
	await _unload()


func test_a_wall_struck_in_the_middle_keeps_a_hole() -> void:
	await _load()
	var built := _alone(1, [[Vector3(3.0, 2.4, 0.35), Vector3(60, 0, 0)]])
	var all := built.blocks[0]
	check(all >= 30, "a wall 3 m wide is cut into blocks a blow can knock out (%d)" % all)
	var middle := Vector3(60.4, 1.2, 0.18)
	built.hit(0, built.strength[0], Vector3.FORWARD, middle)
	check_eq(built.state[0], Structure.STANDS, "struck in the middle with all a place can take, it stands")
	var left := _standing(built, 0)
	check(
		left >= all - 6 and left < all, "the blocks round the blow are knocked out, no more (%d left)" % left
	)
	var loose := built.rubble
	check_eq(loose.live, all - left, "each a loose body")
	await frames(3)
	# A hole: nothing in the way through the middle, the wall still there
	# beside it.
	var space := main.get_world_3d().direct_space_state
	var through := PhysicsRayQueryParameters3D.create(middle + Vector3(0, 0, 1), middle - Vector3(0, 0, 1))
	through.collision_mask = Layers.STRUCTURE
	check(space.intersect_ray(through).is_empty(), "nothing is in the way through the hole")
	var beside := PhysicsRayQueryParameters3D.create(
		Vector3(61.2, 2.0, 1), Vector3(61.2, 2.0, -1), Layers.STRUCTURE
	)
	check(not space.intersect_ray(beside).is_empty(), "the wall is still there beside it")
	for k in 900:
		await frames(1)
		if loose.awake == 0:
			break
	check_eq(loose.awake, 0, "what was knocked out comes to rest")
	check_eq(_standing(built, 0), left, "nothing else came down: the rest holds together")
	for i in loose.body.size():
		var lies := loose.transform_of(i).origin
		check(lies.z < -0.3, "block %d went out the far side (z %.2f)" % [i, lies.z])
		check(lies.y < 0.6, "and lies low (%.2f m up)" % lies.y)
	built.free()
	await _unload()


func test_over_the_hole_of_one_blow_the_wall_holds_and_over_a_wider_one_it_comes_down() -> void:
	await _load()
	var built := _alone(1, [[Vector3(3.0, 2.4, 0.35), Vector3(60, 0, 0)]])
	var all := built.blocks[0]
	check_eq(built._unheld(0).size(), 0, "whole, every block of it holds")
	# A hole as one blow makes it: 0.9 m wide, from 0.4 to 1.2 m up.
	var narrow := _knock_out(built, Vector2(59.55, 0.4), Vector2(60.45, 1.2))
	check(narrow >= 2 and narrow <= 6, "a few blocks knocked out (%d)" % narrow)
	check_eq(_standing(built, 0), all - narrow, "nothing else comes down: what is over the hole holds")
	check_eq(built.rubble.live, narrow, "each block knocked out a loose body")
	# The same again beside it: a hole 1.8 m wide.
	var wide := _knock_out(built, Vector2(60.45, 0.4), Vector2(61.35, 1.2))
	check_eq(built.state[0], Structure.STANDS, "the wall stands on both sides")
	var left := _standing(built, 0)
	check(left < all - narrow - wide - 4, "what was over the two comes down (%d stand of %d)" % [left, all])
	var loose := built.rubble
	var in_one := 0
	for i in loose.body.size():
		if loose.alive[i] == 1 and loose.piece[i] == 0:
			in_one += 1
	check(in_one >= 1 and in_one <= 2, "in one, or two (%d)" % in_one)
	check_eq(loose.live, narrow + wide + in_one, "the blocks knocked out, and that")
	for k in 1500:
		await frames(1)
		if loose.awake == 0:
			break
	check_eq(loose.awake, 0, "everything comes to rest")
	check_eq(loose.live, all - left, "it broke into its blocks when it landed")
	check_eq(_standing(built, 0), left, "and nothing else came down")
	# The way is open to the top, over the foot of the wall.
	var space := main.get_world_3d().direct_space_state
	for high: float in [0.7, 1.4, 2.2]:
		var through := PhysicsRayQueryParameters3D.create(
			Vector3(60.45, high, 1), Vector3(60.45, high, -1), Layers.STRUCTURE
		)
		check(space.intersect_ray(through).is_empty(), "nothing in the way %.1f m up" % high)
	var sill := PhysicsRayQueryParameters3D.create(
		Vector3(60.45, 0.2, 1), Vector3(60.45, 0.2, -1), Layers.STRUCTURE
	)
	check(
		not space.intersect_ray(sill).is_empty(),
		"the foot of the wall is still there, low enough to step over"
	)
	built.free()
	await _unload()


func test_a_piece_takes_what_its_matter_and_size_say_however_it_is_cut() -> void:
	await _load()
	var size := Vector3(0.4, 2.6, 0.4)
	var broke_at: Array[int] = []
	var firsts: Array[Vector3] = []
	for cut: int in [1, 7, 23]:
		var built := _alone(cut, [[size, Vector3(60, 0, cut * 3.0)]])
		firsts.append(built.centroid[0])
		check_near(built.strength[0], 9.0, 0.001, "a column 0.4 m thick takes 9 points")
		var blows := 0
		while built.state[0] != Structure.BROKEN and blows < 20:
			built.hit(0, 2.0, Vector3.FORWARD)
			blows += 1
		broke_at.append(blows)
		built.free()
	check_eq(broke_at, [5, 5, 5] as Array[int], "cut three ways, it lets go at the same blow")
	check(
		firsts[0].y != firsts[1].y and firsts[1].y != firsts[2].y,
		"and the three were not cut the same (first blocks at %s)" % [firsts]
	)
	# The same for one place of it: struck there again and again.
	var gave_at: Array[int] = []
	for cut: int in [1, 7, 23]:
		var built := _alone(cut, [[size, Vector3(60, 0, cut * 3.0)]])
		var blows := 0
		while _standing(built, 0) == built.blocks[0] and blows < 20:
			built.hit(0, 2.0, Vector3.FORWARD, Vector3(60, 1.3, cut * 3.0 + 0.2))
			blows += 1
		gave_at.append(blows)
		built.free()
	check_eq(gave_at, [5, 5, 5] as Array[int], "cut three ways, a place of it gives at the same blow")
	# Twice as thick, twice as much; and the thinnest way counts.
	var thick := _alone(
		1, [[Vector3(0.8, 2.6, 0.8), Vector3(60, 0, 40)], [Vector3(3, 0.3, 3), Vector3(70, 0, 40)]]
	)
	check_near(thick.strength[0], 18.0, 0.001, "a column 0.8 m thick takes 18")
	check_near(thick.strength[1], 6.75, 0.001, "a slab 0.3 m thick takes 6.75")
	thick.free()
	await _unload()


func test_what_is_no_longer_carried_comes_down() -> void:
	await _load()
	var up := s.place[main.slab].origin.y
	s.hit(main.posts[0], s.strength[main.posts[0]], Vector3.FORWARD)
	await frames(60)
	check_eq(s.state[main.slab], Structure.STANDS, "on three columns the slab holds")
	check_eq(s.harm[main.slab], 0.0, "and took nothing")
	s.hit(main.posts[1], s.strength[main.posts[1]], Vector3.FORWARD)
	check_eq(s.state[main.slab], Structure.FALLS, "with two gone on one side it comes down, in one piece")
	check_eq(
		s.rubble.live,
		s.blocks[main.posts[0]] + s.blocks[main.posts[1]] + 1,
		"two columns in blocks, one slab"
	)
	var rested := await _rest(1500)
	check(rested, "everything comes to rest")
	# Wherever it ended, in one piece or in blocks, it is no longer up there.
	var loose := s.rubble
	var highest := 0.0
	for i in loose.body.size():
		if loose.alive[i] == 1:
			highest = maxf(highest, loose.transform_of(i).origin.y)
	check(
		highest < up - 0.5,
		"nothing is left up there (highest middle %.2f m, the slab was at %.2f)" % [highest, up]
	)
	check(s.state[main.posts[2]] != Structure.FALLS, "a column never falls whole: it stands or it is broken")
	await _unload()


func test_what_lands_on_a_piece_is_a_blow_to_it() -> void:
	await _load()
	# A low column, and over it a heavy slab that rests on a tall column to
	# one side.
	var built := _alone(
		1,
		[
			[Vector3(0.4, 1.0, 0.4), Vector3(60, 0, 0)],
			[Vector3(0.4, 3.0, 0.4), Vector3(61.2, 0, 0)],
			[Vector3(3.0, 0.6, 2.0), Vector3(60, 3.0, 0)],
		]
	)
	check_eq(Array(built.rests_on[2]), [1], "the slab rests on the tall column alone")
	built.hit(1, built.strength[1], Vector3.RIGHT)
	check_eq(built.state[2], Structure.FALLS, "which gone, it comes down")
	check_eq(built.harm[0], 0.0, "the low column has taken nothing yet")
	var whole := built.blocks[0]
	for k in 600:
		await frames(1)
		if _standing(built, 0) < whole:
			break
	check(built.harm[0] > 0.0, "the slab lands on the low column: a blow to it (%.1f points)" % built.harm[0])
	check(_standing(built, 0) < whole, "which knocks blocks out of it, where it landed")
	built.free()
	await _unload()


func test_things_fall_as_fast_as_they_are_set_to() -> void:
	await _load()
	check_near(s.rubble.fall, Rubble.FALL, 0.001, "to begin with, at %.2f of real gravity" % Rubble.FALL)
	# The same column let go of high in the air, twice: how long its blocks
	# take to come down 2 m.
	var took: Array[int] = []
	for share: float in [1.0, 0.25]:
		var built := _alone(3, [[Vector3(0.4, 2.0, 0.4), Vector3(60, 8, 0)]])
		built.rubble.fall = share
		seed(11)
		built.shatter(0, Vector3.FORWARD)
		var from := _height(built)
		var steps := 0
		while _height(built) > from - 2.0 and steps < 600:
			await frames(1)
			steps += 1
		took.append(steps)
		built.free()
	check(
		took[0] > 20 and took[0] < 60,
		"at real gravity, 2 m in about two thirds of a second (%d steps)" % took[0]
	)
	check_near(float(took[1]) / took[0], 2.0, 0.2, "at a quarter of it, twice as long (%d steps)" % took[1])
	# The slider of the HUD sets it, for what already lies about too.
	for child in main.hud.get_children():
		if child is HSlider:
			(child as HSlider).value = 0.6
	check_near(main.fall, 0.6, 0.001, "moving the slider sets it")
	check_near(s.rubble.fall, 0.6, 0.001, "and the setting reaches the rubble")
	main.fall = 0.5
	check_near(s.rubble.fall, 0.5, 0.001, "set from the code too")
	main.fall = 5.0
	check_near(s.rubble.fall, Rubble.FALL_MOST, 0.001, "never faster than real gravity")
	await _unload()


func test_the_brute_knocks_a_hole_in_the_wall_where_its_fists_land_then_kicks_a_way_through() -> void:
	await _load()
	var q := main.wall
	var all := s.blocks[q]
	_face(Main.WALL_AT + Vector3(0, 0.05, 1.0), Main.WALL_AT + Vector3.UP)
	await frames(5)
	var thrown := [0]
	var landed: Array[Vector3] = []
	p.blow.connect(
		func(at: Vector3, _way: Vector3, _power: int, on: RID) -> void:
			thrown[0] += 1
			if s.standing(on) == q:
				landed.append(at)
	)
	# The blows of a combination land apart: each place takes its own. The
	# first hole is where one of them has landed often enough.
	for k in 1200:
		if k % 6 == 0:
			p.punch()
		await frames(1)
		if _standing(s, q) < all:
			break
	var out := all - _standing(s, q)
	check(out > 0, "a hole is knocked in it")
	check(landed.size() <= 16, "within four combinations (%d blows on it)" % landed.size())
	check_eq(s.state[q], Structure.STANDS, "the wall stands round the hole")
	check(out >= 2 and out <= 8, "a few blocks knocked out, no more (%d of %d)" % [out, all])
	var face := Main.WALL_AT.z + Main.WALL.z * 0.5
	var high := 9.0
	for at in landed:
		check(absf(at.z - face) < 0.03, "a blow lands on the face of the wall (z %.2f)" % at.z)
		high = minf(high, at.y)
	check(high > 1.2, "all of them at the height of the shoulder or above (the lowest %.2f m up)" % high)
	for i in range(s.first[q], s.first[q] + all):
		if s.stands[i] == 1:
			continue
		var off := 9.0
		for at in landed:
			off = minf(off, Vector2(s.centroid[i].x - at.x, s.centroid[i].y - at.y).length())
		check(off < 0.6, "block %d, knocked out, was by a fist (%.2f m from it)" % [i, off])
	# The fists land high: what is below the shoulder is for the foot.
	# More blows, then kicks from a step back, and it walks through.
	for k in 1200:
		if k % 6 == 0:
			p.punch()
		await frames(1)
		if thrown[0] >= 12:
			break
	await frames(150)  # the blows run their course
	await _rest(1200)
	var low := all
	for i in range(s.first[q], s.first[q] + all):
		if s.stands[i] == 1 and absf(s.centroid[i].x - Main.WALL_AT.x) < 0.3:
			low = mini(low, int(s.centroid[i].y * 10.0))
	check(low < 5, "the fists have left the foot of the wall standing")
	var through := false
	var kicks := 0
	for attempt in 5:
		for aside: float in [0.0, -0.35, 0.35]:
			_face(Main.WALL_AT + Vector3(aside, 0.05, 1.1), Main.WALL_AT + Vector3(aside, 1, 0))
			await frames(5)
			p.kick()
			kicks += 1
			await frames(80)
		await _rest(600)
		_face(Main.WALL_AT + Vector3(0, 0.05, 2.0), Main.WALL_AT + Vector3.UP)
		p.touch_move = Vector2(0, -1)
		await frames(220)
		p.touch_move = Vector2.ZERO
		if p.global_position.z < Main.WALL_AT.z - 1.0:
			through = true
			break
	check(through, "the brute walks through (z %.2f)" % p.global_position.z)
	check(kicks <= 15, "after a few kicks (%d)" % kicks)
	check_eq(s.state[q], Structure.STANDS, "what is left of the wall stands")
	check(_standing(s, q) >= all / 4, "a good part of it (%d blocks of %d)" % [_standing(s, q), all])
	for other in s.pieces:
		check(other == q or s.harm[other] == 0.0, "piece %d took nothing" % other)
	await _unload()


func test_a_blow_sends_off_what_lies_loose() -> void:
	await _load()
	s.hit(main.column, s.strength[main.column], Vector3.FORWARD)
	var rested := await _rest(900)
	check(rested, "the column's blocks come to rest")
	var loose := s.rubble
	var at := loose.transform_of(0).origin
	check(
		s.strike(at + Vector3(0, 0.2, 0.2), Vector3.FORWARD, 3), "a blow at a block that lies there meets it"
	)
	await frames(20)
	check_eq(loose.frozen[0], 0, "the block moves again")
	check(loose.transform_of(0).origin.distance_to(at) > 0.05, "pushed along the blow")
	check(loose.transform_of(0).origin.distance_to(at) < 3.0, "not far: it is heavy")
	await _unload()


## Puts the brute at `at`, its body turned to `target`, the camera behind.
func _face(at: Vector3, target: Vector3) -> void:
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.facing = atan2(at.x - target.x, at.z - target.z)
	p.look(Vector2(angle_difference(p.yaw, p.facing), 0.0))


## Knocks out of piece 0 of `built` the blocks whose middle is between
## `from` and `to` (x, and how high), as a blow that had landed on them
## alone would. Returns how many.
func _knock_out(built: Structure, from: Vector2, to: Vector2) -> int:
	var out := 0
	for i in built.blocks[0]:
		var at := built.centroid[i]
		if built.stands[i] == 1 and at.x >= from.x and at.x <= to.x and at.y >= from.y and at.y <= to.y:
			built._expel(i, Vector3.FORWARD)
			out += 1
	built._refresh(0)
	built._settle(0, Vector3.FORWARD)
	return out


## How many blocks of piece `q` of `built` still stand.
func _standing(built: Structure, q: int) -> int:
	var left := 0
	for i in range(built.first[q], built.first[q] + built.blocks[q]):
		left += built.stands[i]
	return left


## Waits for everything loose to come to rest, `most` steps at most.
## Returns whether it did.
func _rest(most: int) -> bool:
	for k in most:
		await frames(1)
		if s.rubble.awake == 0:
			return true
	return false


## A structure of its own, away from the bench, cut with `cut`: concrete
## pieces, each [size, where its foot is].
func _alone(cut: int, pieces: Array) -> Structure:
	var built := Structure.new()
	built.cut_seed = cut
	main.add_child(built)
	for piece: Array in pieces:
		var size: Vector3 = piece[0]
		var foot: Vector3 = piece[1]
		built.add_piece(Matter.CONCRETE, Transform3D(Basis(), foot + Vector3.UP * size.y * 0.5), size)
	built.build()
	return built


## How high the middle of what lies loose in `built` is, on average.
func _height(built: Structure) -> float:
	var loose := built.rubble
	var sum := 0.0
	for i in loose.body.size():
		sum += loose.transform_of(i).origin.y
	return sum / maxi(loose.body.size(), 1)


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
