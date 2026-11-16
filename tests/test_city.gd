extends TestCase
## The city: a toy one, made up from a number, in which the two brutes are
## giants. What is low they walk through, a tower comes down when its foot
## goes, and a brute that is thrown goes through whatever is behind it.

var main: Main
var s: Structure
var p: Player
var d: Brute
var city: City
var _tops := {}


func test_a_number_makes_a_city_and_always_the_same_one() -> void:
	var one := City.new(7)
	var same := City.new(7)
	var other := City.new(8)
	check_eq(same.towers, one.towers, "the same number, the same towers")
	check_eq(same.houses, one.houses, "the same houses")
	check_eq(same.weight(), one.weight(), "the same city")
	check(other.towers != one.towers, "another number, another city")
	var sizes := {}
	var railways := 0
	for number in 40:
		var made := City.new(number)
		var what := "city %d" % number
		sizes[made.blocks.size()] = true
		railways += made.railway.size() / 2
		check(
			made.weight() <= City.MOST, "%s is not too much for a phone (%d shards)" % [what, made.weight()]
		)
		check(made.weight() > 600, "%s is a city (%d shards)" % [what, made.weight()])
		var count := made.towers.size()
		check(count >= City.TOWERS_LEAST and count <= City.TOWERS_MOST, "%s has %d towers" % [what, count])
		check(made.square.has_point(Vector2.ZERO), "%s has its square in the middle of the world" % what)
		check(minf(made.square.size.x, made.square.size.y) >= City.SQUARE_LEAST, "%s has room on it" % what)
		for start: Vector3 in [made.player_start, made.brute_start]:
			check(
				made.square.grow(-1.0).has_point(Vector2(start.x, start.z)),
				"%s: the brutes start on it" % what
			)
		# Blocks with a street between them, the square not on the edge.
		var edge := Rect2()
		for block in made.blocks:
			edge = block if edge.size == Vector2.ZERO else edge.merge(block)
			for against in made.blocks:
				var apart := not block.grow(City.AVENUE_LEAST * 0.5 - 0.01).intersects(against)
				check(block == against or apart, "%s: a street between two blocks" % what)
		check(edge.grow(-City.BLOCK_LEAST).encloses(made.square), "%s: the square is inside the city" % what)
		# What is built stands on a block, and not on the square.
		for built: Vector3 in made.towers + made.offices + made.houses:
			var on := made.block_at(built)
			check(on >= 0 and made.kinds[on] != City.SQUARE, "%s: built on a block" % what)
		for car in made.cars:
			check(made.block_at(car) < 0, "%s: cars in the street" % what)
	check(sizes.size() >= 3, "cities of several sizes (%s blocks)" % [sizes.keys()])
	check(railways > 10 and railways < 40, "with a railway or without (%d of 40 have one)" % railways)


func test_cities_stand_as_built_around_a_square() -> void:
	for number: int in [1, 2, 4]:
		await _load(number)
		var what := "city %d" % number
		check(s.count > 700 and s.count < 2300, "%s: what a phone can carry (%d shards)" % [what, s.count])
		s.recheck()
		await frames(60)
		check_eq(s.held_count, s.count, "%s: all of it stands" % what)
		check_eq(s.pieces.live, 0, "%s: nothing came off" % what)
		# The two brutes on the square, with room to fight.
		check_eq(
			s.shards_near(Vector3(0, 0.5, 0), 3.2).size(), 0, "%s: nothing in the middle of the square" % what
		)
		check(
			p.global_position.length() < 4.0 and d.global_position.length() < 4.0,
			"%s: the brutes are there" % what
		)
		check(p.is_on_floor() and d.is_on_floor(), "%s: on their feet" % what)
		# Towers three times as high as they are.
		for tower in city.towers:
			var top := 0.0
			for i in s.shards_near(tower + Vector3.UP * 4.0, 2.5):
				top = maxf(top, s.top(i))
			check(top > 4.3, "%s: a tower at %s (%.1f m high)" % [what, tower, top])
		# Houses, cars and trees are no higher than what a brute walks through.
		var low := 0
		for i in s.count:
			if _high(i) < Fighter.WADE:
				low += 1
		check(low > 250, "%s: a lot is lower than its waist (%d shards)" % [what, low])
		await _unload()


func test_a_brute_has_to_run_to_go_through_houses() -> void:
	await _load(1)
	# A line right across a block, with houses on it and nothing tall.
	var from := Vector3.INF
	var to := Vector3.INF
	for k in city.blocks.size():
		var block := city.blocks[k]
		for axis in 2:
			var at := block.position[1 - axis] + 1.0
			while at < block.end[1 - axis] - 1.0 and from == Vector3.INF:
				var a := _on_ground(axis, block.end[axis] + 1.0, at)
				var b := _on_ground(axis, block.position[axis] - 1.5, at)
				var met := 0
				for house in city.houses:
					var off := house - a
					if absf(off[2 - 2 * axis]) < 0.4 and block.has_point(Vector2(house.x, house.z)):
						met += 1
				if city.kinds[k] != City.SQUARE and met >= 2 and not _blocked(a, b, 0.7, Fighter.WADE):
					from = a
					to = b
				at += 0.4
	check(from != Vector3.INF, "a row of houses to go through")
	var far := from.distance_to(to)
	var along := (to - from).normalized()
	# At a jog, the first house is a wall.
	_stand(from + Vector3.UP * 0.05, to + Vector3.UP)
	await frames(10)
	var standing := s.held_count
	p.touch_move = Vector2(0, -1)
	await frames(int((far / Character.JOG_PACE + 0.8) * 60.0))
	p.touch_move = Vector2.ZERO
	var went := (p.global_position - from).dot(along)
	check(went < far - 2.0, "jogging, a house stops it (%.1f m of %.1f)" % [went, far])
	check(standing - s.held_count < 6, "and stands (%d shards went)" % (standing - s.held_count))
	# At a run it goes through, and each house slows it.
	_stand(from + Vector3.UP * 0.05, to + Vector3.UP)
	await frames(10)
	standing = s.held_count
	var highest := 0.0
	var took := 0
	p.touch_move = Vector2(0, -1)
	p.touch_sprint = true
	while (p.global_position - from).dot(along) < far - 1.0 and took < 600:
		await frames(1)
		took += 1
		highest = maxf(highest, p.global_position.y)
	p.touch_move = Vector2.ZERO
	p.touch_sprint = false
	check(took < 600, "running, it goes right through the block (%.1f s)" % (took / 60.0))
	check(highest < 0.7, "through the houses, not over them (feet at %.2f m at most)" % highest)
	var gone := standing - s.held_count
	check(gone > 8, "knocking down what was in its way (%d shards)" % gone)
	var open_ground := (far - 1.0) / Character.SPRINT_PACE
	check(
		took / 60.0 > open_ground * 1.2,
		"which slows it (%.1f s, %.1f in the open)" % [took / 60.0, open_ground]
	)
	await _unload()


func test_a_car_walked_into_is_kicked_away() -> void:
	await _load(1)
	# A car with a clear run up to it and beyond.
	var was := Vector3.INF
	var way := Vector3.ZERO
	for car in city.cars:
		for out: Vector3 in [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT]:
			if was == Vector3.INF and not _blocked(car - out * 2.5, car + out * 6.0, 0.6, 0.35):
				was = car
				way = out
	check(was != Vector3.INF, "a car in the open")
	var car_shard := s.shards_near(was + Vector3.UP * 0.06, 0.2)
	check(car_shard.size() > 0, "it stands there")
	_stand(was - way * 2.0 + Vector3.UP * 0.05, was + way * 10.0 + Vector3.UP)
	await frames(10)
	p.touch_move = Vector2(0, -1)
	var highest := 0.0
	for k in 60:
		await frames(1)
		highest = maxf(highest, p.global_position.y)
	p.touch_move = Vector2.ZERO
	await frames(60)
	check_eq(s.held[car_shard[0]], 0, "it does not stand there any more")
	var sent := (s.place_of(car_shard[0]) - was).dot(way)
	check(sent > 1.5, "it was sent off ahead (%.1f m)" % sent)
	check(highest < 0.2, "and the brute did not step onto it (feet at %.2f m at most)" % highest)
	check((p.global_position - was).dot(way) > 1.0, "it went on its way")
	await _unload()


func test_a_brute_that_comes_down_on_a_house_flattens_it() -> void:
	await _load(1)
	var at := city.houses[0]
	var house := s.shards_near(at + Vector3.UP * 0.3, 0.5)
	check(house.size() > 0, "a house")
	_stand(Vector3(at.x, 2.0, at.z), Vector3(at.x, 1.0, at.z - 10.0))
	await frames(90)
	var standing := 0
	for i in house:
		standing += s.held[i]
	check_eq(standing, 0, "it gave way under it")
	check(
		p.global_position.y < 0.5,
		"the brute is down among what is left (feet at %.2f m)" % p.global_position.y
	)
	await _unload()


func test_a_tower_comes_down_when_its_foot_is_knocked_out() -> void:
	# A tower that can be got at from one side, with room to fall on the
	# other (in the first city that has one); and an office that can be got
	# at, for what does not happen to it.
	var tower := Vector3.INF
	var out := Vector3.ZERO
	for number in range(1, 9):
		await _load(number)
		for candidate in city.towers:
			for way: Vector3 in [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT]:
				var open := not _blocked(candidate - way * 3.8, candidate - way * 1.5, 1.0, 0.4)
				var room := not _blocked(candidate + way * 2.2, candidate + way * 6.0, 0.8, Fighter.WADE)
				if tower == Vector3.INF and open and room:
					tower = candidate
					out = way
		if tower != Vector3.INF:
			break
		await _unload()
	check(tower != Vector3.INF, "a tower in the open, with room to fall behind it")
	var office := Vector3.INF
	var office_out := Vector3.ZERO
	var biggest := 0
	for candidate in city.offices:
		var size := s.shards_near(candidate + Vector3.UP * 1.3, 1.9).size()
		for way: Vector3 in [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT]:
			if size > biggest and not _blocked(candidate - way * 3.8, candidate - way * 2.1, 1.0, 0.4):
				office = candidate
				office_out = way
				biggest = size
	check(office != Vector3.INF, "and an office in the open")
	var up_there := s.shards_near(tower + Vector3.UP * 3.9, 1.2)
	check(up_there.size() > 6, "the tower stands, as built")
	var floors := s.shards_near(office + Vector3.UP * 1.3, 1.6)
	var roof := 0
	for i in floors:
		if s.centroid[i].y > 1.2:
			roof += 1
	# The same six blows at the foot of each, from the open side.
	for target: Array in [[tower, out], [office, office_out]]:
		var foot: Vector3 = target[0]
		var way: Vector3 = target[1]
		var from := foot - way * 3.2 + Vector3.UP * 1.6
		var across := way.cross(Vector3.UP)
		for k in 6:
			var to := foot + across * (k % 3 - 1) * 0.8 + Vector3.UP * (0.5 + (k / 3) * 1.0)
			main.blow(from, to - from)
			await frames(18)
	await frames(240)
	var standing := 0
	var fell := Vector3.ZERO
	for i in up_there:
		standing += s.held[i]
		fell += s.place_of(i) - tower
	fell /= up_there.size()
	check_eq(standing, 0, "nothing of the tower stands up there any more")
	check(fell.y < 1.6, "it is down (%.1f m up)" % fell.y)
	check(fell.dot(out) > 2.0, "fallen over, away from the blows (%.1f m)" % fell.dot(out))
	var left := 0
	for i in floors:
		if s.centroid[i].y > 1.2:
			left += s.held[i]
	check(left < floors.size(), "the office has a hole in it")
	check(left > roof / 3, "and its top is still up there (%d shards of %d)" % [left, roof])
	await _unload()


func test_a_brute_thrown_at_the_city_goes_through_it() -> void:
	await _load(1)
	# The other brute with its back to the office nearest the square.
	var office := city.offices[0]
	for candidate in city.offices:
		if candidate.length() < office.length():
			office = candidate
	var way := office.normalized()
	d.global_position = office - way * 3.6 + Vector3.UP * 0.05
	_stand(office - way * 4.8 + Vector3.UP * 0.05, office + Vector3.UP * 1.3)
	await frames(10)
	var standing := s.held_count
	var was := d.global_position
	var waited := 0
	while d.fighter.up() and waited < 300:
		if waited % 6 == 0:
			p.punch()
		await frames(1)
		waited += 1
	check_eq(d.fighter.state, "flying", "the blow from overhead takes it off its feet")
	await frames(240)
	var gone := standing - s.held_count
	var flew := (d.global_position - was).dot(way)
	check(flew > 4.0, "it went into the city (%.1f m)" % flew)
	check(gone > 8, "and took what was in its way along (%d shards)" % gone)
	await frames(int((Fighter.LIES + 2.5) * 60.0))
	check(d.fighter.up(), "then it gets back up")
	await _unload()


func test_the_other_brute_comes_through_the_city_to_hit_back() -> void:
	await _load(1)
	# The player on the square, the other brute behind a block of houses.
	var behind := Vector3.INF
	for k in city.blocks.size():
		var block := city.blocks[k]
		var middle := Vector3(block.get_center().x, 0, block.get_center().y)
		if city.kinds[k] == City.HOUSES and (behind == Vector3.INF or middle.length() < behind.length()):
			behind = middle + middle.normalized() * (block.size.length() * 0.5 + 1.0)
	check(behind != Vector3.INF, "a block of houses")
	_stand(Vector3(0, 0.05, 0), behind + Vector3.UP)
	d.global_position = behind + Vector3.UP * 0.05
	d.ai = true
	await frames(5)
	var standing := s.held_count
	var took := false
	var waited := 0
	while not took and waited < 1800:
		await frames(1)
		waited += 1
		took = p.character.state.begins_with("hit_") or not p.fighter.up()
	check(took, "it came and landed a blow")
	check(waited < 1200, "without going round (%.1f s for %.0f m)" % [waited / 60.0, behind.length()])
	var gone := standing - s.held_count
	check(gone > 6, "through what was in its way (%d shards)" % gone)
	d.ai = false
	await _unload()


## How high the thing that shard `i` is part of stands (m): the top of its
## box.
func _high(i: int) -> float:
	if _tops.is_empty():
		for k in s.count:
			_tops[s.element[k]] = maxf(_tops.get(s.element[k], 0.0), s.top(k))
	return _tops[s.element[i]]


## Does something at least `high` m tall stand within `half` m of the way
## from `a` to `b`?
func _blocked(a: Vector3, b: Vector3, half: float, high: float) -> bool:
	var along := Vector3(b.x - a.x, 0, b.z - a.z)
	var far := along.length()
	along /= far
	for i in s.count:
		if s.held[i] == 0 or _high(i) < high:
			continue
		var off := s.centroid[i] - a
		var at := off.dot(along)
		if at > 0.0 and at < far and absf(off.cross(along).y) < half + 0.4:
			return true
	return false


## The place on the ground `at` m along `axis` (0: x, 1: z) and `across` m
## along the other.
func _on_ground(axis: int, at: float, across: float) -> Vector3:
	return Vector3(at, 0, across) if axis == 0 else Vector3(across, 0, at)


func _stand(at: Vector3, target: Vector3) -> void:
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.look_at_point(target)
	p.facing = p.yaw


func _load(number: int) -> void:
	seed(5)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
	main.city_number = number
	main.fight = false  # the other brute only stands there
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await frames(20)
	s = main.structure
	p = main.player
	d = main.brute
	city = main.city
	p.input_enabled = true


func _unload() -> void:
	main.queue_free()
	_tops.clear()
	await frames(2)
