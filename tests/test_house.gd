extends TestCase
## The house on the bench: wood, hollow, as tall as the brute. Walls of
## planks that stand, a roof of two slopes whose boards lean on the long
## walls and on the ridge beam. What is no longer carried comes down: the
## board over a wall that is cut, the whole roof when the ridge loses an
## end.

var main: Main
var p: Player
var s: Structure


func test_the_house_stands_as_tall_as_the_brute_under_a_roof_of_two_slopes() -> void:
	await _load()
	check_eq(main.house_walls.size(), 18, "eighteen planks to its long walls: ten a side, less a doorway")
	check_eq(main.house_gables.size(), 16, "eight to each gable")
	check_eq(main.house_roof.size(), 12, "six boards to each slope of its roof")
	var top := 0.0
	for q in _house():
		check_eq(s.matter[q], Matter.WOOD, "piece %d is wood" % q)
		top = maxf(top, s._bounds(q).end.y)
	var head := p.character.bulk()[0]
	var tall := head.y + head.w - p.global_position.y
	check(tall > 1.6 and tall < 2.0, "(the brute is %.2f m tall)" % tall)
	check(absf(top - tall) < 0.3, "its ridge is at the brute's head (%.2f m up)" % top)
	var door := 0
	for q in main.house_walls:
		var at := s.place[q].origin - Main.HOUSE_AT
		check(absf(absf(at.x) - 1.17) < 0.01, "plank %d is in one of the two long walls" % q)
		check(not s._tilted(q) and s.rests_on[q].is_empty(), "it stands on the ground")
		if at.x < 0.0 and absf(at.z) < 0.3:
			door += 1
	check_eq(door, 0, "a doorway in the middle of the wall that faces the start")
	check(Main.HOUSE_AT.x > 3.0, "(the start is on that side)")
	# The roof: boards tilted away from the ridge, each on the ridge and on
	# the wall under it.
	for q in main.house_roof:
		var up := s.place[q].basis.y
		var out := s.place[q].origin.x - Main.HOUSE_AT.x
		check(s._tilted(q) and up.y > 0.9, "board %d is tilted, a little" % q)
		check(up.x * out > 0.0, "away from the ridge")
		check(main.house_ridge in s.rests_on[q], "it rests on the ridge")
		check(not _under(q).is_empty(), "and on the wall under it (%d planks)" % _under(q).size())
		check(s.carries[q].is_empty(), "it carries nothing")
		check_eq(s.blocks[q], 3, "it is cut into three lengths")
	var ends := [0, 0]
	for q in s.rests_on[main.house_ridge]:
		check(q in main.house_gables, "the ridge rests on a plank of a gable")
		check(absf(s.place[q].origin.x - Main.HOUSE_AT.x) < 0.2, "one of the two in the middle")
		ends[0 if s.place[q].origin.z < Main.HOUSE_AT.z else 1] += 1
	check_eq(ends, [2, 2], "two at each end")
	check_eq(s.carries[main.house_ridge].size(), 12, "and carries the twelve boards")
	await frames(90)
	check_eq(s.standing_count, s.pieces, "nothing comes down on its own")
	check_eq(s.rubble.live, 0, "nothing comes off")
	await _unload()


func test_walking_running_and_jumping_break_nothing_of_the_house() -> void:
	await _load()
	_face(Main.HOUSE_AT + Vector3(-5, 0.05, 0.9), Main.HOUSE_AT + Vector3(0, 1, 0.9))
	p.touch_move = Vector2(0, -1)
	p.touch_sprint = true
	await frames(140)
	var short := Main.HOUSE_AT.x - Main.HOUSE.x * 0.5 - p.global_position.x
	check(short > 0.0 and short < 1.0, "the wall stops the brute, which ran right up to it (%.2f m)" % short)
	for k in 3:
		p.touch_jump = true
		await frames(50)
	# Along the wall, pressed against it, past the doorway: it is too
	# narrow to go in by.
	p.touch_sprint = false
	p.touch_move = Vector2(-1, -0.4)
	var inside := 0
	for k in 110:
		await frames(1)
		var off := p.global_position - Main.HOUSE_AT
		inside += 1 if absf(off.x) < Main.HOUSE.x * 0.5 and absf(off.z) < Main.HOUSE.y * 0.5 else 0
	p.touch_move = Vector2.ZERO
	var moved := p.global_position.z - Main.HOUSE_AT.z
	check(moved < -0.3, "it went along the wall, past the doorway (%.2f m from its middle)" % moved)
	check_eq(inside, 0, "and never into the house")
	for q in s.pieces:
		check_eq(s.harm[q], 0.0, "piece %d took nothing" % q)
	check_eq(s.standing_count, s.pieces, "everything stands")
	check_eq(s.rubble.live, 0, "nothing came off")
	await _unload()


func test_a_board_of_the_roof_comes_down_when_the_wall_under_it_is_cut() -> void:
	await _load()
	var board := main.house_roof[10]
	var under := _under(board)
	check(under.size() >= 2, "a board rests on a few planks (%d)" % under.size())
	for k in under.size() - 1:
		_cut(under[k])
	check_eq(s.state[board], Structure.STANDS, "one of them still under it: it holds")
	_cut(under[-1])
	check(s.state[board] != Structure.STANDS, "none: it comes down")
	var down := 0
	for i in s.rubble.body.size():
		if s.rubble.alive[i] == 1 and s._clumps.has(i) and s._clumps[i].size() == 3:
			down += 1
	check_eq(down, 1, "in one piece")
	check_eq(s.state[main.house_ridge], Structure.STANDS, "the ridge stays up")
	for q in main.house_roof:
		check(q == board or s.state[q] == Structure.STANDS, "board %d too" % q)
	for q in under:
		check_eq(s.state[q], Structure.STANDS, "the foot of plank %d stands" % q)
	check(await _rest(900), "everything comes to rest")
	await _unload()


func test_the_whole_roof_comes_down_when_the_ridge_loses_an_end() -> void:
	await _load()
	var end: Array[int] = []
	for q in s.rests_on[main.house_ridge]:
		if s.place[q].origin.z > Main.HOUSE_AT.z:
			end.append(q)
	_cut(end[0])
	check_eq(s.state[main.house_ridge], Structure.STANDS, "one plank still under that end: the ridge holds")
	check_eq(s.standing_count, s.pieces, "and all the rest")
	_cut(end[1])
	check(s.state[main.house_ridge] != Structure.STANDS, "none: the ridge comes down")
	for q in main.house_roof:
		check(s.state[q] != Structure.STANDS, "and board %d with it" % q)
	for q in main.house_walls:
		check_eq(s.state[q], Structure.STANDS, "wall plank %d stands" % q)
		check_eq(s.harm[q], 0.0, "untouched")
	for q in main.house_gables:
		check_eq(s.state[q], Structure.STANDS, "gable plank %d stands" % q)
	check(await _rest(1200), "everything comes to rest")
	# The roof is on the floor of the house, or against its walls: nothing
	# has been thrown about.
	for i in s.rubble.body.size():
		if s.rubble.alive[i] == 1:
			var off := s.rubble.transform_of(i).origin - Main.HOUSE_AT
			check(Vector2(off.x, off.z).length() < 3.5, "loose piece %d lies by the house" % i)
	for q in s.pieces:
		check(q in _house() or s.harm[q] == 0.0, "piece %d, not of the house, took nothing" % q)
	await _unload()


func test_a_blow_on_a_board_of_the_roof_snaps_it_and_none_of_it_stays_up() -> void:
	await _load()
	var board := main.house_roof[2]
	var at := s.place[board].origin
	check(s.strike(at, Vector3.RIGHT, 2, s.body_of(board)), "a blow lands on the middle of a board")
	check(s.state[board] != Structure.STANDS, "neither end holds alone: nothing of it is left up")
	check_eq(s.rubble.live, 3, "three loose pieces: the length struck, and what was on each side of it")
	check_eq(s.state[main.house_ridge], Structure.STANDS, "the ridge stays up")
	for q in main.house_roof:
		check(q == board or s.state[q] == Structure.STANDS, "board %d too" % q)
	check_eq(s.standing_count, s.pieces - 1, "and everything else")
	check(await _rest(900), "everything comes to rest")
	await _unload()


func test_the_brute_brings_the_roof_down_from_the_gable() -> void:
	await _load()
	_face(Main.HOUSE_AT + Vector3(0, 0.05, 2.5), Main.HOUSE_AT + Vector3.UP)
	await frames(5)
	var landed: Array[Vector3] = []
	var thrown := [0]
	p.blow.connect(
		func(at: Vector3, _way: Vector3, _power: int, on: RID) -> void:
			thrown[0] += 1
			if s.standing(on) in main.house_gables:
				landed.append(at)
	)
	for k in 1200:
		if thrown[0] >= 6 and not p.character.striking():
			break
		if k % 6 == 0 and thrown[0] < 6:
			p.punch()
		await frames(1)
	check(not landed.is_empty(), "its fists land on the gable")
	if not landed.is_empty():
		check(
			landed[0].y > 1.2 and landed[0].y < 1.6,
			"the first at the height of the shoulder (%.2f m up)" % landed[0].y
		)
	check(s.state[main.house_ridge] != Structure.STANDS, "within two combinations the ridge is down")
	var up := 0
	for q in main.house_roof:
		up += 1 if s.state[q] == Structure.STANDS else 0
	check_eq(up, 0, "and the whole roof with it")
	for q in main.house_walls:
		check_eq(s.state[q], Structure.STANDS, "long wall plank %d stands" % q)
	check(await _rest(1200), "everything comes to rest")
	for q in s.pieces:
		check(q in _house() or s.harm[q] == 0.0, "piece %d, not of the house, took nothing" % q)
	await _unload()


func test_the_brute_cuts_a_long_wall_down_and_the_roof_over_it_follows() -> void:
	await _load()
	_face(Main.HOUSE_AT + Vector3(2.2, 0.05, -0.6), Main.HOUSE_AT + Vector3(0, 1, -0.6))
	await frames(5)
	var thrown := [0]
	var on_roof := [0]
	p.blow.connect(
		func(_at: Vector3, _way: Vector3, _power: int, on: RID) -> void:
			thrown[0] += 1
			if s.standing(on) in main.house_roof:
				on_roof[0] += 1
	)
	for k in 1800:
		if thrown[0] >= 9 and not p.character.striking():
			break
		if k % 6 == 0 and thrown[0] < 9:
			p.punch()
		await frames(1)
	var cut := 0
	for q in main.house_walls:
		var out := s.place[q].origin.x - Main.HOUSE_AT.x
		var lost := false
		for i in range(s.first[q], s.first[q] + s.blocks[q]):
			lost = lost or s.stands[i] == 0
		check_eq(s.state[q], Structure.STANDS, "the foot of plank %d stands" % q)
		if lost:
			cut += 1
			check(out > 0.0, "plank %d, cut, is of the wall the brute strikes" % q)
	check(cut >= 2, "three combinations cut a few planks (%d)" % cut)
	var down := 0
	for q in main.house_roof:
		if s.state[q] != Structure.STANDS:
			down += 1
			check(s.place[q].origin.x > Main.HOUSE_AT.x, "board %d, down, is of the slope over that wall" % q)
	check(down >= 1, "and boards of the roof over them come down (%d)" % down)
	check_eq(s.state[main.house_ridge], Structure.STANDS, "the ridge stays up")
	check(await _rest(1200), "everything comes to rest")
	for q in s.pieces:
		check(q in _house() or s.harm[q] == 0.0, "piece %d, not of the house, took nothing" % q)
	await _unload()


## Every piece of the house.
func _house() -> Array[int]:
	var all: Array[int] = [main.house_ridge]
	for group: PackedInt32Array in [main.house_walls, main.house_gables, main.house_roof]:
		all.append_array(Array(group))
	return all


## The planks of the long walls that board `q` of the roof rests on.
func _under(q: int) -> Array[int]:
	var planks: Array[int] = []
	for r in s.rests_on[q]:
		if r in main.house_walls:
			planks.append(r)
	return planks


## The top of plank `q` is struck off: a blow at its head.
func _cut(q: int) -> void:
	s.hit(q, 2.0, Vector3.RIGHT, s.place[q].origin + Vector3.UP * (s.size[q].y * 0.5 - 0.1))


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
