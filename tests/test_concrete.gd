extends TestCase
## Concrete, on the bench: it cracks, then lets go in a few big blocks that
## come down slowly and lie low; it carries; only a blow breaks it.

var main: Main
var p: Player
var s: Structure


func test_walking_running_and_jumping_break_nothing() -> void:
	await _load()
	# Straight at the wall, at a sprint.
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


func test_a_column_cracks_blow_after_blow_then_lets_go_in_a_few_blocks() -> void:
	await _load()
	var q := main.column
	_face(Main.COLUMN_AT + Vector3(0, 0.05, 1.45), Main.COLUMN_AT + Vector3.UP)
	await frames(5)
	# What the column shows after each blow of the combination that lands.
	var blows := [0]
	p.blow.connect(func(_from: Vector3, _to: Vector3, _power: int) -> void: blows[0] += 1)
	var seen: Array[Array] = []
	for k in 200:
		if k % 6 == 0:
			p.punch()
		await frames(1)
		if blows[0] > seen.size():
			seen.append([s.state[q], s.cracks[q], s.harm[q]])
		if seen.size() == 4:
			break
	check_eq(seen.size(), 4, "four blows landed")
	if seen.size() == 4:
		check_eq(seen[0], [Structure.STANDS, 1, 2.0], "after the first it stands, cracked")
		check_eq(seen[1], [Structure.STANDS, 1, 4.0], "after the second too")
		check_eq(seen[2], [Structure.STANDS, 2, 6.0], "after the third the cracks are wide")
		check_eq(seen[3][0], Structure.BROKEN, "at the fourth, the heavy one, it lets go")
	check_eq(s.standing_count, s.pieces - 1, "it no longer stands")
	check_eq(s.rubble.live, s.blocks[q], "it is its few blocks now (%d)" % s.blocks[q])
	check(s.blocks[q] >= 3 and s.blocks[q] <= 5, "three to five of them")
	for other in s.pieces:
		check(other == q or s.harm[other] == 0.0, "piece %d took nothing" % other)
	# They come down, away from the brute, and lie low.
	var rested := await _rest(900)
	check(rested, "the blocks come to rest")
	var loose := s.rubble
	for i in loose.body.size():
		var at := loose.transform_of(i).origin
		check(at.y < 0.45, "block %d lies on the ground (its middle %.2f m up)" % [i, at.y])
		check(at.z < Main.COLUMN_AT.z + 0.4, "block %d went away from the brute (z %.2f)" % [i, at.z])
		check(at.distance_to(Main.COLUMN_AT) < 5.0, "block %d did not fly off (%s)" % [i, at.snappedf(0.1)])
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
	for k in 600:
		await frames(1)
		if built.state[0] == Structure.BROKEN:
			break
	check_eq(built.state[0], Structure.BROKEN, "the slab lands on the low column and breaks it")
	built.free()
	await _unload()


func test_things_fall_slowly_and_as_slowly_as_they_are_set_to() -> void:
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


func test_a_broken_panel_opens_the_wall_and_its_rubble_lies_low() -> void:
	await _load()
	var middle := main.panels[1]
	_face(Main.WALL_AT + Vector3(0, 0.05, 1.7), Main.WALL_AT + Vector3.UP)
	await frames(5)
	for k in 200:
		if k % 6 == 0:
			p.punch()
		await frames(1)
		if s.state[middle] == Structure.BROKEN:
			break
	check_eq(s.state[middle], Structure.BROKEN, "the middle panel lets go")
	await frames(150)  # the blow runs its course
	var rested := await _rest(900)
	check(rested, "its blocks come to rest")
	check_eq(s.state[main.panels[0]], Structure.STANDS, "the panel on its left stands")
	check_eq(s.state[main.panels[2]], Structure.STANDS, "the one on its right too")
	check_eq(
		s.harm[main.panels[0]] + s.harm[main.panels[2]], 0.0, "neither took anything from what fell past it"
	)
	var loose := s.rubble
	for i in loose.body.size():
		var at := loose.transform_of(i).origin
		check(at.y < 0.6, "block %d lies low (its middle %.2f m up)" % [i, at.y])
		check_eq(loose.frozen[i], 1, "block %d is at rest: frozen" % i)
	# The way is open: the brute goes through where the panel was, over
	# what lies there.
	_face(Main.WALL_AT + Vector3(0, 0.05, 2.0), Main.WALL_AT + Vector3.UP)
	p.touch_move = Vector2(0, -1)
	await frames(200)
	p.touch_move = Vector2.ZERO
	check(
		p.global_position.z < Main.WALL_AT.z - 1.5, "the brute walks through (z %.2f)" % p.global_position.z
	)
	check_eq(s.standing_count, s.pieces - 1, "breaking nothing on its way")
	await _unload()


func test_a_blow_sends_off_what_lies_loose() -> void:
	await _load()
	s.hit(main.column, s.strength[main.column], Vector3.FORWARD)
	var rested := await _rest(900)
	check(rested, "the column's blocks come to rest")
	var loose := s.rubble
	var at := loose.transform_of(0).origin
	check(
		s.strike(at + Vector3(0, 0.2, 1.0), at + Vector3(0, 0.2, 0.2), 3),
		"a blow at a block that lies there meets it"
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
