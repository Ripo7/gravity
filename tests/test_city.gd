extends TestCase
## The city: a toy one, in which the two brutes are giants. What is low
## they walk through, a tower comes down when its foot goes, and a brute
## that is thrown goes through whatever is behind it.

var main: Main
var s: Structure
var p: Player
var d: Brute
var _tops := {}


func test_the_city_stands_as_built_around_a_square() -> void:
	await _load()
	check(s.count > 1200 and s.count < 2200, "a city the phone can carry (%d shards)" % s.count)
	s.recheck()
	await frames(60)
	check_eq(s.held_count, s.count, "all of it stands")
	check_eq(s.pieces.live, 0, "nothing came off")
	# The two brutes on the square, with room to fight.
	check_eq(s.shards_near(Vector3(0, 0.5, 0), 3.5).size(), 0, "nothing stands in the middle of the square")
	check(p.global_position.length() < 4.0 and d.global_position.length() < 4.0, "the brutes start there")
	check(p.is_on_floor() and d.is_on_floor(), "on their feet")
	# A tower on each side of it, three times as high as they are.
	for out: Vector3 in [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT]:
		var top := 0.0
		for i in s.shards_near(out * City.PITCH + Vector3.UP * 4.0, 2.5):
			top = maxf(top, s.top(i))
		check(top > 4.3, "a tower towards %s (%.1f m high)" % [out, top])
	# Houses, cars and trees are no higher than what a brute walks through:
	# most of what stands.
	var low := 0
	for i in s.count:
		if _high(i) < Fighter.WADE:
			low += 1
	check(low > 500, "and a lot that is lower than its waist (%d shards)" % low)
	await _unload()


func test_a_brute_walks_through_the_houses() -> void:
	await _load()
	# Across a block of houses at a corner of the city, along a row that has
	# no office in it.
	var block := Vector3(-City.PITCH, 0, City.PITCH)
	var row := INF
	for lot: int in [-1, 0, 1]:
		var z := block.z + lot * City.LOT
		var tall := false
		for i in s.count:
			if (
				s.top(i) > Fighter.WADE
				and absf(s.centroid[i].z - z) < 1.6
				and absf(s.centroid[i].x - block.x) < 5.0
			):
				tall = true
		if not tall and row == INF:
			row = z
	check(row != INF, "a row of houses to go through")
	var from := Vector3(block.x + City.BLOCK * 0.5 + 1.0, 0.05, row)
	_stand(from, Vector3(block.x - 20.0, 1.0, row))
	await frames(10)
	var standing := s.held_count
	var highest := 0.0
	p.touch_move = Vector2(0, -1)
	for k in 240:
		await frames(1)
		highest = maxf(highest, p.global_position.y)
	p.touch_move = Vector2.ZERO
	var went := from.x - p.global_position.x
	check(went > City.BLOCK, "it went right through the block (%.1f m in 4 s)" % went)
	var off := absf(p.global_position.z - row)
	check(off < 2.5, "more or less straight on (%.1f m off its line)" % off)
	check(highest < 0.7, "through the houses, not over them (feet at %.2f m at most)" % highest)
	var gone := standing - s.held_count
	check(gone > 12, "knocking down what was in its way (%d shards)" % gone)
	await _unload()


func test_a_car_walked_into_is_kicked_away() -> void:
	await _load()
	# A car on the avenue to the east of the square.
	var car := -1
	for i in s.count:
		var at := s.centroid[i]
		if s.top(i) < 0.15 and absf(at.x - City.PITCH * 0.5) < City.KERB + 0.1 and absf(at.z) < 4.0:
			car = i
			break
	check(car >= 0, "a car there")
	var was := s.centroid[car]
	_stand(was + Vector3(0, 0.05, 2.0), was + Vector3(0, 1.0, -10.0))
	await frames(10)
	p.touch_move = Vector2(0, -1)
	var highest := 0.0
	for k in 60:
		await frames(1)
		highest = maxf(highest, p.global_position.y)
	p.touch_move = Vector2.ZERO
	await frames(60)
	check_eq(s.held[car], 0, "it does not stand there any more")
	var now := s.place_of(car)
	check(was.z - now.z > 1.5, "it was sent off ahead (%.1f m)" % (was.z - now.z))
	check(highest < 0.2, "and the brute did not step onto it (feet at %.2f m at most)" % highest)
	check(p.global_position.z < was.z - 1.0, "it went on its way")
	await _unload()


func test_a_brute_that_comes_down_on_a_house_flattens_it() -> void:
	await _load()
	# A house: a low box big enough to stand on.
	var house := -1
	for i in s.count:
		if _high(i) > 0.55 and _high(i) < 0.9 and s.volume[i] > 0.1:
			house = i
			break
	check(house >= 0, "a house")
	var at := s.centroid[house]
	_stand(Vector3(at.x, 2.0, at.z), Vector3(at.x, 1.0, at.z - 10.0))
	await frames(90)
	check_eq(s.held[house], 0, "it gave way under it")
	check(
		p.global_position.y < 0.5,
		"the brute is down among what is left (feet at %.2f m)" % p.global_position.y
	)
	await _unload()


func test_a_tower_comes_down_when_its_foot_is_knocked_out() -> void:
	await _load()
	# A tower with only houses behind it, seen from the square: room to fall.
	var out := Vector3.ZERO
	for way: Vector3 in [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT]:
		var behind := way * (City.PITCH + City.LOT)
		var clear := true
		for i in s.count:
			var off := s.centroid[i] - behind
			if _high(i) > Fighter.WADE and absf(off.x) < City.LOT * 0.5 and absf(off.z) < City.LOT * 0.5:
				clear = false
		if clear and out == Vector3.ZERO:
			out = way
	check(out != Vector3.ZERO, "a tower with room to fall behind it")
	var tower := out * City.PITCH
	var up_there := s.shards_near(tower + Vector3.UP * 4.0, 1.2)
	check(up_there.size() > 6, "it stands, as built")
	# An office too, for what does not happen to it: something tall that is
	# not near a tower.
	var office := -1
	for i in s.count:
		var from_tower := Vector2(absf(s.centroid[i].x), absf(s.centroid[i].z)).distance_to(
			Vector2(0, City.PITCH)
		)
		var from_other := Vector2(absf(s.centroid[i].x), absf(s.centroid[i].z)).distance_to(
			Vector2(City.PITCH, 0)
		)
		if s.top(i) > 1.45 and s.volume[i] > 0.2 and minf(from_tower, from_other) > 2.5:
			office = i
			break
	check(office >= 0, "and an office")
	var floors := 0
	for i in s.count:
		if s.element[i] == s.element[office] and s.centroid[i].y > 1.3:
			floors += 1
	# The same six blows at the foot of each, from the side of the square.
	for target: Vector3 in [tower, Vector3(s.centroid[office].x, 0, s.centroid[office].z)]:
		var from := target - out * 3.2 + Vector3.UP * 1.6
		var across := out.cross(Vector3.UP)
		for k in 6:
			var to := target + across * (k % 3 - 1) * 0.8 + Vector3.UP * (0.5 + (k / 3) * 1.0)
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
	for i in s.count:
		if s.element[i] == s.element[office] and s.centroid[i].y > 1.3:
			left += s.held[i]
	check(left < floors, "the office has a hole in it")
	check(left > floors / 3, "and its top is still up there (%d shards of %d)" % [left, floors])
	await _unload()


func test_a_brute_thrown_at_the_city_goes_through_it() -> void:
	await _load()
	# On the north side of the square, the other brute with its back to the
	# railway and to the tower behind it.
	d.global_position = Vector3(0, 0.05, -3.6)
	_stand(Vector3(0, 0.05, -2.4), Vector3(0, 1.3, -10.0))
	await frames(10)
	var standing := s.held_count
	var waited := 0
	while d.fighter.up() and waited < 300:
		if waited % 6 == 0:
			p.punch()
		await frames(1)
		waited += 1
	check_eq(d.fighter.state, "flying", "the blow from overhead takes it off its feet")
	await frames(240)
	var gone := standing - s.held_count
	check(
		d.global_position.z < -City.PITCH * 0.5 - 1.0,
		"it went through the railway (it is at z %.1f)" % d.global_position.z
	)
	check(gone > 8, "and took what was in its way along (%d shards)" % gone)
	await frames(int((Fighter.LIES + 2.5) * 60.0))
	check(d.fighter.up(), "then it gets back up")
	await _unload()


func test_the_other_brute_comes_through_the_houses_to_hit_back() -> void:
	await _load()
	# The player on the square, the other brute at the far corner of a block
	# of houses: the block is between them.
	_stand(Vector3(-2.0, 0.05, 2.0), Vector3(-20.0, 1.3, 20.0))
	d.global_position = Vector3(-City.PITCH - 3.0, 0.05, City.PITCH + 3.0)
	d.ai = true
	await frames(5)
	var standing := s.held_count
	var took := false
	var waited := 0
	while not took and waited < 1500:
		await frames(1)
		waited += 1
		took = p.character.state.begins_with("hit_") or not p.fighter.up()
	check(took, "it came and landed a blow")
	check(waited < 900, "without going round (%.1f s for %.0f m)" % [waited / 60.0, 23.0])
	var gone := standing - s.held_count
	check(gone > 10, "through what was in its way (%d shards)" % gone)
	d.ai = false
	await _unload()


## How high the thing that shard `i` is part of stands (m): the top of its
## box.
func _high(i: int) -> float:
	if _tops.is_empty():
		for k in s.count:
			_tops[s.element[k]] = maxf(_tops.get(s.element[k], 0.0), s.top(k))
	return _tops[s.element[i]]


func _stand(at: Vector3, target: Vector3) -> void:
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.look_at_point(target)
	p.facing = p.yaw


func _load() -> void:
	seed(5)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
	main.fight = false  # the other brute only stands there
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await frames(20)
	s = main.structure
	p = main.player
	d = main.brute
	p.input_enabled = true


func _unload() -> void:
	main.queue_free()
	_tops.clear()
	await frames(2)
