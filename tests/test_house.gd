extends TestCase
## The house in the real scene: it stands, it comes down the way one
## expects, and a shot does what it should.

var main: Main
var s: Structure


func test_the_house_stands_as_built() -> void:
	await _load()
	check(s.count > 900 and s.count < 2000, "about 1400 shards (%d)" % s.count)
	s.recheck()
	await frames(30)
	check_eq(s.held_count, s.count, "every shard stands")
	check(s.support.worst > 0.2 and s.support.worst < 0.8, "loaded, with a margin (%.2f)" % s.support.worst)
	check(main.build_ms < 3000.0, "built quickly (%.0f ms)" % main.build_ms)
	await _unload()


func test_without_its_pillars_the_balcony_comes_down() -> void:
	await _load()
	# The four pillars of the porch, thrown clear.
	for i in s.count:
		var p := _local(i)
		if p.z > 6.3 and p.y < 3.0:
			s.blow(i, Vector3(0, 1, 7))
	await frames(240)
	var balcony := Vector2i.ZERO  # (shards, of which still standing)
	var house := Vector2i.ZERO
	for i in s.count:
		var p := _local(i)
		if p.z > 4.2 and p.y > 3.0:
			balcony += Vector2i(1, s.held[i])
		elif p.z < 3.5:
			house += Vector2i(1, s.held[i])
	check(balcony.x > 80, "the balcony is a good part of the house (%d shards)" % balcony.x)
	check(balcony.y < balcony.x * 0.2, "most of it came down (%d of %d still up)" % [balcony.y, balcony.x])
	check(house.y > house.x * 0.9, "the house itself still stands (%d of %d)" % [house.y, house.x])
	_check_nothing_vanished()
	await _unload()


func test_a_blow_makes_a_hole_where_it_lands_and_the_next_goes_through() -> void:
	await _load()
	# At the back wall (solid), a pillar three metres behind it.
	var from := main.house_at * Vector3(-2.5, 1.4, -8.5)
	var target := Vector3(-2.5, 1.4, -3.5)
	var torn := await _shoot(from, main.house_at.basis * Vector3(0, 0, 1))
	check(torn >= 3 and torn < 15, "it knocked a few shards out of the wall (%d)" % torn)
	var hole := 0
	var far := 0.0
	var thrown_in := 0
	for i in s.count:
		if s.held[i] == 0:
			hole += 1
			far = maxf(far, _local(i).distance_to(target))
			if (main.house_at.affine_inverse() * s.place_of(i)).z > -3.3:
				thrown_in += 1
	check_eq(hole, torn, "nothing else came off")
	check(far < 1.3, "all of it around where it landed (the farthest %.2f m)" % far)
	check(thrown_in >= hole / 2, "what it knocked out went inside (%d of %d)" % [thrown_in, hole])
	check(s.pieces.live >= hole, "and is still there, in pieces (%d)" % s.pieces.live)
	check_eq(_pillar().y, _pillar().x, "the pillar behind the wall is untouched")
	# The same blow again goes through the hole, to the pillar.
	await frames(60)
	torn = await _shoot(from, main.house_at.basis * Vector3(0, 0, 1))
	check(torn >= 1, "the next one reaches the pillar (%d shards)" % torn)
	check(_pillar().y < _pillar().x, "which is broken")
	check(s.held_count > s.count * 0.9, "the house stands (%d of %d)" % [s.held_count, s.count])
	_check_nothing_vanished()
	await _unload()


func test_what_breaks_stays_and_comes_to_rest() -> void:
	await _load()
	var stops: Array[Array] = [
		[Vector3(-2.5, 1.4, 7.5), Vector3(-2.5, 1.4, 3.3)],
		[Vector3(-1.5, 1.4, 10.5), Vector3(-1.5, 1.4, 6.6)],
		[Vector3(1.5, 1.4, 10.5), Vector3(1.5, 1.4, 6.6)],
		[Vector3(-8.0, 1.4, 0.0), Vector3(-4.3, 1.4, 0.0)],
		[Vector3(8.0, 1.4, 1.0), Vector3(4.3, 1.4, 1.0)],
		[Vector3(0, 1.4, -7.5), Vector3(0, 1.4, -3.3)],
	]
	var most := 0
	for stop in stops:
		# Six blows at each, one after the other, in two rows of three.
		var from := main.house_at * (stop[0] as Vector3)
		var target := main.house_at * (stop[1] as Vector3)
		var across := (target - from).cross(Vector3.UP).normalized()
		for k in 6:
			var to := target + across * (k % 3 - 1) * 0.8 + Vector3.UP * (k / 3 - 0.5) * 0.9
			main.blow(from, to - from)
			await frames(12)
			most = maxi(most, s.pieces.awake)
	check(s.pieces.live > 100, "a lot came off (%d pieces)" % s.pieces.live)
	check(most > 30, "and moved (%d at once)" % most)
	await frames(600)
	_check_nothing_vanished()
	check(s.pieces.awake <= s.pieces.live / 20, "it all came to rest (%d still moving)" % s.pieces.awake)
	await _unload()


## A brute's blow where the line from `from` along `direction` meets the
## house. Returns how many standing shards it knocked out.
func _shoot(from: Vector3, direction: Vector3) -> int:
	var torn := main.blow(from, direction)
	await frames(3)
	return torn


## The pillar behind the back wall on the left: (its shards, of which stand).
func _pillar() -> Vector2i:
	var pillar := Vector2i.ZERO
	for i in s.count:
		var p := _local(i)
		if absf(p.x + 2.5) < 0.3 and absf(p.z) < 0.3 and p.y < 3.0:
			pillar += Vector2i(1, s.held[i])
	return pillar


func _check_nothing_vanished() -> void:
	check_near(s.standing_volume() + s.pieces.volume(), s.total_volume, 1e-2, "nothing vanished")
	var lost := 0
	var p := s.pieces
	for i in p.alive.size():
		if p.alive[i] == 1:
			var at := p.transform_of(i).origin
			if at.y < -0.3 or at.length() > 80.0:
				lost += 1
	check_eq(lost, 0, "no piece fell through the ground or flew off")


## Where shard `i` stands, in the house's own space.
func _local(i: int) -> Vector3:
	return main.house_at.affine_inverse() * s.centroid[i]


func _load() -> void:
	seed(5)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
	main.fight = false  # the other brute only stands there
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await frames(2)
	s = main.structure
	main.player.input_enabled = false


func _unload() -> void:
	main.queue_free()
	await frames(2)
