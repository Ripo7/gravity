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


func test_a_shot_makes_a_hole_where_it_lands_and_the_next_goes_through() -> void:
	await _load()
	# At the back wall (solid), a pillar three metres behind it.
	var from := main.house_at * Vector3(-2.5, 1.4, -8.5)
	var target := Vector3(-2.5, 1.4, -3.5)
	var torn := await _shoot(from, main.house_at.basis * Vector3(0, 0, 1))
	check(torn >= 3 and torn < 15, "it knocked a few shards out of the wall (%d)" % torn)
	check_eq(get_tree().get_nodes_in_group("projectile").size(), 0, "and is gone")
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
	# The same shot again goes through the hole, to the pillar.
	await frames(60)
	torn = await _shoot(from, main.house_at.basis * Vector3(0, 0, 1))
	check(torn >= 1, "the next one reaches the pillar (%d shards)" % torn)
	check(_pillar().y < _pillar().x, "which is broken")
	check(s.held_count > s.count * 0.9, "the house stands (%d of %d)" % [s.held_count, s.count])
	_check_nothing_vanished()
	await _unload()


func test_a_shot_that_misses_breaks_nothing() -> void:
	await _load()
	# Away from the house, into the ground in front of it, and over its roof.
	var from := main.house_at * Vector3(0, 1.6, 12)
	main.shoot(from, main.house_at.basis * Vector3(0, 0, 1))
	main.shoot(from, main.house_at.basis * Vector3(0, -0.5, -1))
	main.shoot(from, main.house_at.basis * Vector3(0, 1, -1))
	await frames(10)
	check_eq(get_tree().get_nodes_in_group("projectile").size(), 2, "the one into the ground has stopped")
	await frames(int(Projectile.RANGE / Projectile.SPEED * 60.0) + 5)
	check_eq(get_tree().get_nodes_in_group("projectile").size(), 0, "the others are gone, out of range")
	check_eq(s.held_count, s.count, "nothing broke")
	check_eq(s.pieces.live, 0, "nothing came off")
	await _unload()


func test_a_shot_shoves_a_loose_piece() -> void:
	await _load()
	# A shard knocked out of the back wall, left to rest on the ground.
	var hit := -1
	for i in s.count:
		var p := _local(i)
		if absf(p.x) < 0.5 and absf(p.y - 1.4) < 0.4 and p.z < -3.1:
			hit = i
			break
	s.blow(hit, main.house_at.basis * Vector3(0, 0, -4))
	await frames(180)
	var at := s.place_of(hit)
	var piece := s.piece_of[hit]
	check(piece >= 0 and s.pieces.frozen[piece] == 1, "a piece at rest behind the house")
	var from := at + main.house_at.basis * Vector3(4, 0.3, 0)
	var torn := await _shoot(from, at - from)
	check_eq(torn, 0, "the shot broke nothing standing")
	var moved := (s.place_of(hit) - at).dot((at - from).normalized())
	check(moved > 0.3, "the piece was shoved along (%.2f m)" % moved)
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
		# Six shots at each, one after the other, in two rows of three.
		var from := main.house_at * (stop[0] as Vector3)
		var target := main.house_at * (stop[1] as Vector3)
		var across := (target - from).cross(Vector3.UP).normalized()
		for k in 6:
			var to := target + across * (k % 3 - 1) * 0.8 + Vector3.UP * (k / 3 - 0.5) * 0.9
			main.shoot(from, to - from)
			await frames(12)
			most = maxi(most, s.pieces.awake)
	check(s.pieces.live > 100, "a lot came off (%d pieces)" % s.pieces.live)
	check(most > 30, "and moved (%d at once)" % most)
	await frames(600)
	_check_nothing_vanished()
	check(s.pieces.awake <= s.pieces.live / 20, "it all came to rest (%d still moving)" % s.pieces.awake)
	await _unload()


## Shoots from `from` along `direction` and waits for it to land (half a
## second at most). Returns how many standing shards it knocked out.
func _shoot(from: Vector3, direction: Vector3) -> int:
	var torn := [-1]
	main.shoot(from, direction).landed.connect(func(_at: Vector3, _n: Vector3, n: int) -> void: torn[0] = n)
	for k in 30:
		if torn[0] >= 0:
			break
		await frames(1)
	await frames(2)
	return torn[0]


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
