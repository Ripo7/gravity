extends TestCase
## The orb: held, it gathers loose debris into one ball; thrown, it breaks
## what it hits and gives everything back.

var main: Main
var s: Structure


func test_held_it_swallows_loose_debris_and_grows() -> void:
	await _load()
	await _bring_the_balcony_down()
	var before := s.pieces.live
	_stand(Vector3(0, 0.05, 13), Vector3(0, 1.0, 8))
	var orb := main.start_orb()
	await frames(2)
	var small := orb.radius()
	await frames(300)
	check(orb.volume > 1.0, "it swallowed debris (%.2f m3)" % orb.volume)
	check(orb.volume <= Orb.MOST + 1e-3, "no more than it can hold")
	check(orb.radius() > small * 1.5, "and grew (%.2f m to %.2f m)" % [small, orb.radius()])
	var ball := 4.0 / 3.0 * PI * pow(orb.radius(), 3.0)
	check_near(ball, orb.volume, orb.volume * 0.01, "a ball of the volume it swallowed")
	check(s.pieces.live < before - 10, "what it swallowed is off the ground (%d pieces)" % s.pieces.live)
	check_near(s.pieces.taken_volume, orb.volume, 1e-3, "and counted")
	check_near(s.standing_volume() + s.pieces.volume(), s.total_volume, 1e-2, "nothing vanished")
	var eye := main.player.camera
	var ahead := (orb.centre - eye.global_position).dot(-eye.global_basis.z)
	check(ahead > 1.5 and ahead < Orb.HOLD + orb.radius() * 3.0, "held in front of you (%.1f m)" % ahead)
	check(orb.centre.y > orb.radius(), "above the ground")
	await _unload()


func test_thrown_it_breaks_what_it_hits_and_gives_everything_back() -> void:
	await _load()
	await _bring_the_balcony_down()
	_stand(Vector3(0, 0.05, 13), Vector3(0, 1.0, 8))
	var orb := main.start_orb()
	await frames(300)
	check(orb.volume > 1.0, "it holds something (%.2f m3)" % orb.volume)
	# The upper floor's front wall, near its left corner.
	var target := Vector3(-3.6, 4.2, 3.4)
	_stand(Vector3(0, 0.05, 13), target)
	await frames(20)
	var standing := s.held_count
	# What is in the middle of the view.
	var eye := main.player.camera
	var ray := PhysicsRayQueryParameters3D.create(
		eye.global_position,
		eye.global_position - eye.global_basis.z * 40.0,
		Structure.LAYER_WORLD | Structure.LAYER_STRUCTURE
	)
	var seen := main.get_world_3d().direct_space_state.intersect_ray(ray)
	check(not seen.is_empty(), "you are looking at the house")
	var size := orb.radius()
	var hits: Array[Vector3] = []
	orb.burst.connect(func(at: Vector3, _volume: float) -> void: hits.append(at))
	main.throw_orb()
	check_eq(orb.state, Orb.State.FLY, "let go, it flies")
	await frames(90)
	check_eq(hits.size(), 1, "it hit something")
	if hits.size() == 1 and not seen.is_empty():
		var off := hits[0].distance_to(seen["position"])
		check(off < size + 0.6, "what you were looking at (%.1f m off, ball of %.1f m)" % [off, size])
	check(s.held_count <= standing - 8, "it knocked a hole (%d shards)" % (standing - s.held_count))
	check(not is_instance_valid(orb), "the ball is gone")
	check_near(s.pieces.taken_volume, 0.0, 1e-3, "all it held is back")
	_check_nothing_vanished()
	await frames(600)
	_check_nothing_vanished()
	check(s.pieces.awake <= s.pieces.live / 20, "it all came to rest (%d still moving)" % s.pieces.awake)
	await _unload()


func test_with_nothing_to_gather_nothing_happens() -> void:
	await _load()
	_stand(Vector3(0, 0.05, 13), Vector3(0, 1.4, 3.4))
	var orb := main.start_orb()
	await frames(60)
	check_eq(orb.volume, 0.0, "nothing to swallow")
	main.throw_orb()
	await frames(30)
	check(not is_instance_valid(orb), "it goes out")
	check_eq(s.held_count, s.count, "nothing broke")
	check_eq(s.pieces.live, 0, "nothing came off")
	await _unload()


func test_what_is_behind_a_wall_stays_there() -> void:
	await _load()
	# Loose shards inside the house, the walls whole: torn from an inner pillar.
	var loose := 0
	for i in s.count:
		var p := _local(i)
		if absf(p.x) < 0.3 and absf(p.z) < 0.3 and p.y > 0.6 and p.y < 2.4:
			s.blow(i, Vector3(1, 1, 0))
			loose += 1
	await frames(120)
	check(loose >= 2 and s.pieces.live >= loose, "loose pieces inside (%d)" % s.pieces.live)
	# From behind the house, whose back wall has no opening.
	_stand(Vector3(0, 0.05, -9), Vector3(0, 1.0, -3.5))
	var orb := main.start_orb()
	await frames(180)
	check_eq(orb.volume, 0.0, "it cannot draw them through the wall")
	main.throw_orb()
	await _unload()


## The four pillars of the porch thrown clear: the balcony falls in front.
func _bring_the_balcony_down() -> void:
	for i in s.count:
		var p := _local(i)
		if p.z > 6.3 and p.y < 3.0:
			s.blow(i, Vector3(0, 1, 7))
	await frames(300)


## Puts the player at `at`, looking at `target` (both in the house's space).
func _stand(at: Vector3, target: Vector3) -> void:
	var p := main.player
	p.global_position = main.house_at * at
	p.velocity = Vector3.ZERO
	var d := main.house_at * target - (p.global_position + Vector3(0, Player.EYES, 0))
	p.rotation.y = atan2(-d.x, -d.z)
	p.head.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())


func _check_nothing_vanished() -> void:
	check_near(s.standing_volume() + s.pieces.volume(), s.total_volume, 1e-2, "nothing vanished")
	var lost := 0
	var p := s.pieces
	for i in p.top:
		if p.alive[i] == 1:
			var at := p.transform_of(i).origin
			if at.y < -0.3 or at.length() > 80.0:
				lost += 1
	check_eq(lost, 0, "no piece fell out of the world")


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
