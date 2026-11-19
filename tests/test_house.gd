extends TestCase
## The house on the bench. A frame of dark wood (corner posts, a plate
## along each long wall, a post under each end of the ridge beam, rafters)
## clad in planks that carry nothing, under a roof that overhangs: boards
## on the rafters. Windows of glass, a door, a porch. What is no longer
## carried comes down: a slope of the roof when its plate goes, the whole
## roof when the ridge loses a post.

var main: Main
var p: Player
var s: Structure


func test_the_house_is_a_frame_clad_in_planks_under_a_roof_that_overhangs() -> void:
	await _load()
	check_eq(main.house_posts.size(), 4, "four corner posts")
	check_eq(main.house_plates.size(), 2, "two plates")
	check_eq(main.house_ridge_posts.size(), 2, "two posts under the ridge")
	check_eq(main.house_rafters.size(), 8, "four rafters to each slope")
	check_eq(main.house_roof.size(), 8, "four boards to each slope")
	check_eq(main.house_walls.size(), 16, "sixteen planks to the long walls, those under the windows too")
	check_eq(main.house_gables.size(), 16, "eight to each gable")
	check_eq(main.house_panes.size(), 3, "three panes")
	check_eq(main.house_porch.size(), 9, "a porch of four posts, two beams, three boards")
	check_eq(_house().size(), 70, "seventy pieces")
	var half := Main.HOUSE * 0.5
	var top := 0.0
	var eaves := 9.0
	for q in _house():
		check_eq(
			s.matter[q],
			Matter.GLASS if q in main.house_panes else Matter.WOOD,
			"piece %d: wood, or glass" % q
		)
		top = maxf(top, s._bounds(q).end.y)
	for q in main.house_roof:
		eaves = minf(eaves, s._bounds(q).position.y)
	var head := p.character.bulk()[0]
	var tall := head.y + head.w - p.global_position.y
	check(tall > 1.6 and tall < 2.0, "(the brute is %.2f m tall)" % tall)
	check(eaves > 1.3 and eaves < tall, "its eaves are at the brute's shoulders (%.2f m up)" % eaves)
	check(top > tall + 0.3 and top < tall + 0.8, "its ridge over the brute's head (%.2f m up)" % top)
	# The frame carries the roof, and is drawn darker than what clads it.
	for k in 2:
		var plate := main.house_plates[k]
		var posts := [main.house_posts[2 * k], main.house_posts[2 * k + 1]]
		check_eq(Array(s.rests_on[plate]), posts, "plate %d rests on its two corner posts" % k)
		check_eq(s.carries[plate].size(), 4, "and carries four rafters")
	check_eq(
		Array(s.rests_on[main.house_ridge]), Array(main.house_ridge_posts), "the ridge rests on its two posts"
	)
	check_eq(s.carries[main.house_ridge].size(), 8, "and carries the eight rafters")
	for k in main.house_rafters.size():
		var q := main.house_rafters[k]
		var plate := main.house_plates[k / 4]
		check(s._tilted(q) and not Matter.upright(s.size[q]), "rafter %d leans" % k)
		check_eq(Array(s.rests_on[q]), [plate, main.house_ridge], "from its plate up to the ridge")
		check_eq(s.carries[q].size(), 4, "and carries the four boards of its slope")
		check(
			(
				s._bounds(q).end.x - Main.HOUSE_AT.x > half.x + 0.2
				or Main.HOUSE_AT.x - s._bounds(q).position.x > half.x + 0.2
			),
			"it goes past the wall"
		)
	for k in main.house_roof.size():
		var q := main.house_roof[k]
		var up := s.place[q].basis.y
		check(
			s._tilted(q) and up.x * (s.place[q].origin.x - Main.HOUSE_AT.x) > 0.0,
			"board %d leans away from the ridge" % k
		)
		check_eq(
			Array(s.rests_on[q]),
			Array(main.house_rafters.slice(4 * (k / 4), 4 * (k / 4) + 4)),
			"on the four rafters of its slope"
		)
		check(s.carries[q].is_empty(), "and carries nothing")
		check(s.size[q].z > Main.HOUSE.y + 0.3, "it goes past both gables")
	var frame: Array[int] = [main.house_ridge]
	for group: PackedInt32Array in [
		main.house_posts, main.house_plates, main.house_ridge_posts, main.house_rafters
	]:
		frame.append_array(Array(group))
	for q in frame:
		check(s._shade[q] > s._shade[main.house_roof[0]], "piece %d of the frame is darker than the roof" % q)
	check(s._shade[main.house_roof[0]] > 0.1, "which is darker than the walls")
	# What clads it carries nothing, but a pane on the two planks under it.
	var sills := 0
	for q in main.house_walls:
		check(s.rests_on[q].is_empty(), "plank %d stands on the ground" % q)
		check_eq(s._shade[q], 0.0, "in plain wood")
		if s.size[q].y < 1.0:
			sills += 1
			check_eq(s.carries[q].size(), 1, "plank %d, under a window, carries its pane" % q)
		else:
			check(s.carries[q].is_empty(), "plank %d carries nothing" % q)
	check_eq(sills, 6, "two planks under each window")
	for q in main.house_gables:
		check(s.rests_on[q].is_empty() and s.carries[q].is_empty(), "gable plank %d carries nothing" % q)
	for q in main.house_panes:
		check_eq(s.rests_on[q].size(), 2, "pane %d rests on two planks" % q)
		check_eq(s.blocks[q], 1, "and is not cut")
	# The door and its porch are on the side of the start.
	check(Main.HOUSE_AT.x > 3.0, "(the start is on the -x side)")
	check(
		s.place[main.house_door].origin.x < Main.HOUSE_AT.x - half.x + 0.1,
		"the door is in the wall that faces the start"
	)
	for q in main.house_porch:
		var at := s.place[q].origin
		check(at.x < Main.HOUSE_AT.x - half.x, "piece %d of the porch is in front of that wall" % q)
		check(absf(at.z - s.place[main.house_door].origin.z) < 0.8, "by the door")
		check(s._bounds(q).end.y < eaves + 0.1, "under the eaves")
	await frames(90)
	check_eq(s.standing_count, s.pieces, "nothing comes down on its own")
	check_eq(s.rubble.live, 0, "nothing comes off")
	await _unload()


func test_walking_running_and_jumping_break_nothing_of_the_house() -> void:
	await _load()
	# At the back wall, then along it; then at the porch.
	_face(Main.HOUSE_AT + Vector3(5, 0.05, 0.3), Main.HOUSE_AT + Vector3(0, 1, 0.3))
	p.touch_move = Vector2(0, -1)
	p.touch_sprint = true
	await frames(140)
	var short := p.global_position.x - Main.HOUSE_AT.x - Main.HOUSE.x * 0.5
	check(short > 0.0 and short < 1.0, "the house stops the brute, which ran right up to it (%.2f m)" % short)
	for k in 3:
		p.touch_jump = true
		await frames(50)
	p.touch_sprint = false
	p.touch_move = Vector2(1, -0.4)
	await frames(110)
	_face(Main.HOUSE_AT + Vector3(-5, 0.05, 0.45), Main.HOUSE_AT + Vector3(0, 1, 0.45))
	p.touch_move = Vector2(0, -1)
	p.touch_sprint = true
	var inside := 0
	for k in 160:
		await frames(1)
		var off := p.global_position - Main.HOUSE_AT
		inside += 1 if absf(off.x) < Main.HOUSE.x * 0.5 and absf(off.z) < Main.HOUSE.y * 0.5 else 0
	p.touch_move = Vector2.ZERO
	p.touch_sprint = false
	short = Main.HOUSE_AT.x - Main.HOUSE.x * 0.5 - p.global_position.x
	check(short > 0.3, "the porch stops it short of the door (%.2f m from the wall)" % short)
	check_eq(inside, 0, "it never went in")
	for q in s.pieces:
		check_eq(s.harm[q], 0.0, "piece %d took nothing" % q)
	check_eq(s.standing_count, s.pieces, "everything stands")
	check_eq(s.rubble.live, 0, "nothing came off")
	await _unload()


func test_a_blow_on_a_roof_board_knocks_a_hole_and_the_rest_stays_on_its_rafters() -> void:
	await _load()
	var board := main.house_roof[6]
	var all := s.blocks[board]
	# Between two rafters, half a metre from the middle of its length.
	var at := s.place[board].origin + Vector3(0, 0, 0.1)
	check(s.strike(at, Vector3.LEFT, 2, s.body_of(board)), "a blow lands on a board of the roof")
	check_eq(s.state[board], Structure.STANDS, "the board stays up")
	var left := 0
	for i in range(s.first[board], s.first[board] + all):
		left += s.stands[i]
	check(left >= all - 2 and left < all, "less the length the blow landed on (%d of %d)" % [left, all])
	check_eq(s.rubble.live, all - left, "which is loose")
	check_eq(s.standing_count, s.pieces, "and everything else")
	# A rafter that is cut does not let them down either: they lie on the
	# three others. What was above the cut comes down; a stub stays on the
	# plate, where it balances.
	var rafter := main.house_rafters[5]
	s.hit(rafter, 2.0, Vector3.LEFT, s.place[rafter].origin)
	var stub := 0
	for i in range(s.first[rafter], s.first[rafter] + s.blocks[rafter]):
		if s.stands[i] == 1:
			stub += 1
			check(
				absf(s.centroid[i].x - Main.HOUSE_AT.x) > Main.HOUSE.x * 0.5 - 0.5,
				"what is left of the rafter is over its plate"
			)
	check(
		stub < s.blocks[rafter] - 1,
		"a rafter that is cut loses what was above the cut (%d lengths left)" % stub
	)
	for q in main.house_roof:
		check_eq(s.state[q], Structure.STANDS, "board %d stays up" % q)
	check(await _rest(900), "everything comes to rest")
	await _unload()


func test_a_slope_of_the_roof_comes_down_when_its_plate_loses_a_post() -> void:
	await _load()
	_cut(main.house_posts[3])
	check(s.state[main.house_plates[1]] != Structure.STANDS, "a corner post is cut: its plate comes down")
	for k in 8:
		var down := k >= 4
		check_eq(
			s.state[main.house_rafters[k]] != Structure.STANDS, down, "rafter %d: down on that slope only" % k
		)
		check_eq(
			s.state[main.house_roof[k]] != Structure.STANDS, down, "board %d: down on that slope only" % k
		)
	check_eq(s.state[main.house_ridge], Structure.STANDS, "the ridge stays up")
	check_eq(s.state[main.house_plates[0]], Structure.STANDS, "and the other plate")
	for q in main.house_walls:
		check_eq(s.state[q], Structure.STANDS, "wall plank %d stands" % q)
		check_eq(s.harm[q], 0.0, "untouched")
	check(await _rest(1200), "everything comes to rest")
	for q in s.pieces:
		check(q in _house() or s.harm[q] == 0.0, "piece %d, not of the house, took nothing" % q)
	await _unload()


func test_the_whole_roof_comes_down_when_the_ridge_loses_a_post() -> void:
	await _load()
	_cut(main.house_ridge_posts[1])
	check(
		s.state[main.house_ridge] != Structure.STANDS, "a post under the ridge is cut: the ridge comes down"
	)
	for q in main.house_rafters:
		check(s.state[q] != Structure.STANDS, "and rafter %d with it" % q)
	for q in main.house_roof:
		check(s.state[q] != Structure.STANDS, "and board %d" % q)
	for q in main.house_plates:
		check_eq(s.state[q], Structure.STANDS, "plate %d stays up" % q)
	for q in main.house_posts:
		check_eq(s.state[q], Structure.STANDS, "corner post %d stands" % q)
	for group: PackedInt32Array in [main.house_walls, main.house_gables]:
		for q in group:
			check_eq(s.state[q], Structure.STANDS, "plank %d stands" % q)
	check(await _rest(1500), "everything comes to rest")
	# Nothing has been thrown about: the roof lies in the house and round it.
	for i in s.rubble.body.size():
		if s.rubble.alive[i] == 1:
			var off := s.rubble.transform_of(i).origin - Main.HOUSE_AT
			check(Vector2(off.x, off.z).length() < 4.5, "loose piece %d lies by the house" % i)
	for q in s.pieces:
		check(q in _house() or s.harm[q] == 0.0, "piece %d, not of the house, took nothing" % q)
	await _unload()


func test_a_pane_bursts_at_a_blow_and_when_nothing_holds_it() -> void:
	await _load()
	var pane := main.house_panes[0]
	var at := s.place[pane].origin
	check(s.strike(at, Vector3.RIGHT, 2, s.body_of(pane)), "a blow lands on a pane")
	check_eq(s.state[pane], Structure.BROKEN, "it is gone, all of it")
	check_eq(s.glitter.bursts, 1, "in glitter")
	check_eq(s.rubble.live, 0, "which is not loose pieces")
	check_eq(s.standing_count, s.pieces - 1, "everything else stands")
	# Another one: the two planks it stands on are cut.
	pane = main.house_panes[1]
	for q in s.rests_on[pane]:
		_cut(q)
	check_eq(s.state[pane], Structure.BROKEN, "the planks under a pane go: it bursts where it is")
	check_eq(s.glitter.bursts, 2, "in glitter too")
	check_eq(s.state[main.house_panes[2]], Structure.STANDS, "the third stands")
	await _unload()


func test_the_porch_comes_down_when_a_post_under_its_front_beam_goes() -> void:
	await _load()
	var porch := main.house_porch
	check_eq(Array(s.rests_on[porch[5]]), [porch[2], porch[3]], "the front beam rests on the two front posts")
	for k: int in [6, 7, 8]:
		check_eq(
			Array(s.rests_on[porch[k]]), [porch[4], porch[5]], "board %d leans from one beam to the other" % k
		)
	_cut(porch[2])
	check(s.state[porch[5]] != Structure.STANDS, "a front post is cut: the front beam comes down")
	for k: int in [6, 7, 8]:
		check(s.state[porch[k]] != Structure.STANDS, "and board %d" % k)
	check_eq(s.state[porch[4]], Structure.STANDS, "the beam at the wall stays up")
	for q in main.house_roof:
		check_eq(s.state[q], Structure.STANDS, "and the roof of the house (board %d)" % q)
	check(await _rest(900), "everything comes to rest")
	await _unload()


func test_the_brute_brings_the_whole_roof_down_from_the_middle_of_a_gable() -> void:
	await _load()
	_face(Main.HOUSE_AT + Vector3(0, 0.05, 2.7), Main.HOUSE_AT + Vector3.UP)
	await frames(5)
	var thrown := [0]
	p.blow.connect(func(_at: Vector3, _way: Vector3, _power: int, _on: RID) -> void: thrown[0] += 1)
	for k in 1200:
		if thrown[0] >= 6 and not p.character.striking():
			break
		if k % 6 == 0 and thrown[0] < 6:
			p.punch()
		await frames(1)
	check(s.state[main.house_ridge] != Structure.STANDS, "within two combinations the ridge is down")
	var up := 0
	for group: PackedInt32Array in [main.house_rafters, main.house_roof]:
		for q in group:
			up += 1 if s.state[q] == Structure.STANDS else 0
	check_eq(up, 0, "and the whole roof with it")
	for q in main.house_posts:
		check_eq(s.state[q], Structure.STANDS, "corner post %d stands" % q)
	for q in main.house_plates:
		check_eq(s.state[q], Structure.STANDS, "plate %d stays up" % q)
	check(await _rest(1500), "everything comes to rest")
	for q in s.pieces:
		check(q in _house() or s.harm[q] == 0.0, "piece %d, not of the house, took nothing" % q)
	await _unload()


func test_the_brute_at_a_long_wall_knocks_holes_then_brings_that_slope_down() -> void:
	await _load()
	_face(Main.HOUSE_AT + Vector3(2.45, 0.05, 0), Main.HOUSE_AT + Vector3.UP)
	await frames(5)
	var thrown := [0]
	var first_on := [-1]
	p.blow.connect(
		func(_at: Vector3, _way: Vector3, _power: int, on: RID) -> void:
			thrown[0] += 1
			if first_on[0] < 0 and s.standing(on) >= 0:
				first_on[0] = s.standing(on)
	)
	var holes_first := false
	for k in 2400:
		if thrown[0] >= 12 and not p.character.striking():
			break
		if k % 6 == 0 and thrown[0] < 12:
			p.punch()
		await frames(1)
		if s.rubble.live > 0 and s.standing_count == s.pieces:
			holes_first = true
	check(first_on[0] in _house(), "its first blow lands on the house")
	check(holes_first, "pieces come off before anything comes down whole")
	check(
		s.state[main.house_plates[1]] != Structure.STANDS,
		"within four combinations the plate of that wall is down"
	)
	for k in 8:
		var down := k >= 4
		check_eq(
			s.state[main.house_rafters[k]] != Structure.STANDS, down, "rafter %d: down on that slope only" % k
		)
		check_eq(
			s.state[main.house_roof[k]] != Structure.STANDS, down, "board %d: down on that slope only" % k
		)
	check_eq(s.state[main.house_ridge], Structure.STANDS, "the ridge stays up")
	for q in main.house_walls:
		check_eq(s.state[q], Structure.STANDS, "the foot of plank %d stands" % q)
	check(await _rest(1500), "everything comes to rest")
	for q in s.pieces:
		check(q in _house() or s.harm[q] == 0.0, "piece %d, not of the house, took nothing" % q)
	await _unload()


## Every piece of the house.
func _house() -> Array[int]:
	var all: Array[int] = []
	all.assign(main.house_pieces())
	return all


## Piece `q`, which stands upright, is struck near its top: cut there.
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
