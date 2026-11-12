extends TestCase
## The house in the real scene: it stands, it comes down the way one
## expects, and the shock wave does what it should.

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


func test_a_shock_wave_up_close_makes_a_hole_and_the_wall_shelters() -> void:
	await _load()
	# Three metres from the back wall (solid), a pillar right behind it.
	var from := main.house_at * Vector3(-2.5, 1.4, -6.6)
	var wave := main.cast_shockwave(from, main.house_at.basis * Vector3(0, 0, 1))
	await frames(30)
	check(wave.torn >= 6, "it tore shards out of the wall (%d)" % wave.torn)
	var hole := 0
	var pillar := Vector2i.ZERO
	var thrown_in := 0
	for i in s.count:
		var p := _local(i)
		if p.z < -3.1 and p.y < 3.0 and s.held[i] == 0:
			hole += 1
			var now := main.house_at.affine_inverse() * s.pieces.transform_of(s.piece_of[i]).origin
			if now.z > -3.0:
				thrown_in += 1
		if absf(p.x + 2.5) < 0.3 and absf(p.z) < 0.3 and p.y < 3.0:
			pillar += Vector2i(1, s.held[i])
	check(hole >= 6 and hole < 60, "a hole, not the whole wall (%d shards)" % hole)
	check(thrown_in >= hole / 2, "what it tore out was thrown inside (%d of %d)" % [thrown_in, hole])
	check_eq(pillar.y, pillar.x, "the pillar behind the wall was sheltered")
	check(s.held_count > s.count * 0.9, "the house stands (%d of %d)" % [s.held_count, s.count])
	await _unload()


func test_a_shock_wave_from_afar_or_aimed_away_breaks_nothing() -> void:
	await _load()
	main.cast_shockwave(main.house_at * Vector3(0, 1.4, 30), main.house_at.basis * Vector3(0, 0, -1))
	main.cast_shockwave(main.house_at * Vector3(0, 1.4, 8.5), main.house_at.basis * Vector3(0, 0, 1))
	await frames(60)
	check_eq(s.held_count, s.count, "nothing broke")
	check_eq(s.pieces.live, 0, "nothing came off")
	await _unload()


func test_what_breaks_stays_and_comes_to_rest() -> void:
	await _load()
	var shots: Array[Array] = [
		[Vector3(-2.5, 1.4, 7.5), Vector3(-2.5, 1.4, 3.3)],
		[Vector3(-1.5, 1.4, 10.5), Vector3(-1.5, 1.4, 6.6)],
		[Vector3(1.5, 1.4, 10.5), Vector3(1.5, 1.4, 6.6)],
		[Vector3(-8.0, 1.4, 0.0), Vector3(-4.3, 1.4, 0.0)],
		[Vector3(8.0, 1.4, 1.0), Vector3(4.3, 1.4, 1.0)],
		[Vector3(0, 1.4, -7.5), Vector3(0, 1.4, -3.3)],
	]
	var most := 0
	for shot in shots:
		var from := main.house_at * (shot[0] as Vector3)
		main.cast_shockwave(from, (main.house_at * (shot[1] as Vector3) - from).normalized())
		for k in 6:
			await frames(10)
			most = maxi(most, s.pieces.awake)
	check(s.pieces.live > 100, "a lot came off (%d pieces)" % s.pieces.live)
	check(most > 30, "and moved (%d at once)" % most)
	await frames(600)
	_check_nothing_vanished()
	check(s.pieces.awake <= s.pieces.live / 20, "it all came to rest (%d still moving)" % s.pieces.awake)
	await _unload()


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
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await frames(2)
	s = main.structure
	main.player.input_enabled = false


func _unload() -> void:
	main.queue_free()
	await frames(2)
