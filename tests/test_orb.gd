extends TestCase
## Tidying up: held, the orb gathers loose debris into one ball; let go, the
## ball is put down and stays; looked at and held again, it is taken back.

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


func test_let_go_the_ball_is_put_down_and_stays() -> void:
	await _load()
	await _bring_the_balcony_down()
	_stand(Vector3(0, 0.05, 13), Vector3(0, 1.0, 8))
	var orb := main.start_orb()
	await frames(300)
	var held := orb.volume
	var standing := s.held_count
	var was := orb.centre
	check(held > 1.0, "it holds something (%.2f m3)" % held)
	main.drop_orb()
	check_eq(orb.state, Orb.State.DOWN, "let go, it is put down")
	check(main.orb == null, "and no longer in hand")
	await frames(300)
	check(is_instance_valid(orb), "the ball is still there")
	check_near(orb.volume, held, 1e-4, "with all it swallowed")
	var up := orb.centre.y - orb.radius()
	check(up > -0.05 and up < 0.8, "resting on the ground or the rubble (%.2f m above it)" % up)
	var rolled := Vector2(orb.centre.x - was.x, orb.centre.z - was.z).length()
	check(rolled < 2.5, "near where you put it (%.1f m away)" % rolled)
	check_eq(s.held_count, standing, "it broke nothing")
	check_near(s.pieces.taken_volume, held, 1e-3, "and gave nothing back: what it holds is still counted")
	_check_nothing_vanished()
	# You cannot walk through it.
	var p := main.player
	p.global_position = orb.centre + Vector3(0, 0, orb.radius() + 1.2)
	p.global_position.y = 0.05
	p.input_enabled = true
	p.touch_move = Vector2(0, -1)
	p.rotation.y = 0.0
	await frames(120)
	p.touch_move = Vector2.ZERO
	var gap := Vector2(p.global_position.x - orb.centre.x, p.global_position.z - orb.centre.z).length()
	check(gap > orb.radius() * 0.8, "it is solid: you stop against it (%.2f m from its middle)" % gap)
	await _unload()


func test_looked_at_and_held_again_the_ball_is_taken_back() -> void:
	await _load()
	await _bring_the_balcony_down()
	_stand(Vector3(0, 0.05, 13), Vector3(0, 1.0, 8))
	var orb := main.start_orb()
	await frames(90)
	main.drop_orb()
	await frames(180)
	var held := orb.volume
	check(held > 0.2 and held < Orb.MOST, "a ball lies there, not full (%.2f m3)" % held)
	# Looking elsewhere: a new one.
	_stand(Vector3(0, 0.05, 13), Vector3(6, 3.0, 20))
	await frames(5)
	var other := main.start_orb()
	check(other != orb, "looking away, you start a new ball")
	main.drop_orb()
	await frames(5)
	check(not is_instance_valid(other), "which goes out, having swallowed nothing")
	# Looking at it: the same one, in hand again, and it goes on growing.
	_look_at_point(orb.centre)
	await frames(5)
	var again := main.start_orb()
	check(again == orb, "looking at it, you take the same ball back")
	check_eq(orb.state, Orb.State.HELD, "in hand")
	_stand(Vector3(0, 0.05, 13), Vector3(0, 1.0, 8))
	await frames(240)
	check(orb.volume > held + 0.3, "it goes on growing (%.2f to %.2f m3)" % [held, orb.volume])
	var eye := main.player.camera
	var ahead := (orb.centre - eye.global_position).dot(-eye.global_basis.z)
	check(ahead > 1.5, "held in front of you again (%.1f m)" % ahead)
	_check_nothing_vanished()
	main.drop_orb()
	await _unload()


func test_standing_on_a_piece_you_are_not_carried_off_with_it() -> void:
	await _load()
	await _bring_the_balcony_down()
	# A loose piece lying on the ground, away from the heap, to stand on.
	var p := s.pieces
	var under := -1
	for i in p.top:
		if p.alive[i] == 0 or p.frozen[i] == 0:
			continue
		var at := main.house_at.affine_inverse() * p.transform_of(i).origin
		if at.z > 9.0 and at.y < 0.4 and p.mass[i] > 60.0 and (under < 0 or p.mass[i] > p.mass[under]):
			under = i
	check(under >= 0, "there is a piece to stand on")
	if under >= 0:
		var top := main.house_at.affine_inverse() * p.transform_of(under).origin
		_stand(Vector3(top.x, top.y + 0.35, top.z), Vector3(0, 1.2, 3.4))
		await frames(20)
		var here := main.player.global_position
		var orb := main.start_orb()
		var moved := 0.0
		for k in 30:
			await frames(10)
			var off := main.player.global_position - here
			moved = maxf(moved, Vector2(off.x, off.z).length())
		check(orb.volume > 0.3, "the orb drew pieces in (%.2f m3)" % orb.volume)
		check(moved < 0.4, "you stayed where you were (moved %.2f m)" % moved)
		main.drop_orb()
	await _unload()


func test_what_comes_in_from_behind_does_not_push_you() -> void:
	await _load()
	# Loose shards on the ground behind where you stand, the orb in front.
	var behind := 0
	for i in s.count:
		var p := _local(i)
		if p.z > 6.3 and p.y < 3.0 and absf(p.x) < 2.0:
			s.blow(i, Vector3(0, 2, 12))
			behind += 1
	await frames(240)
	_stand(Vector3(0, 0.05, 11), Vector3(0, 1.2, 3.4))
	await frames(10)
	var here := main.player.global_position
	var back := 0
	for i in s.pieces.top:
		if s.pieces.alive[i] == 1 and s.pieces.transform_of(i).origin.z > here.z + 0.5:
			back += 1
	check(back >= 5, "there are loose pieces behind you (%d)" % back)
	var orb := main.start_orb()
	var moved := 0.0
	for k in 30:
		await frames(10)
		moved = maxf(moved, main.player.global_position.distance_to(here))
	check(orb.volume > 0.3, "it drew them in (%.2f m3)" % orb.volume)
	check(moved < 0.25, "and you stayed where you were (moved %.2f m)" % moved)
	main.drop_orb()
	await _unload()


func test_with_nothing_to_gather_nothing_happens() -> void:
	await _load()
	_stand(Vector3(0, 0.05, 13), Vector3(0, 1.4, 3.4))
	var orb := main.start_orb()
	await frames(60)
	check_eq(orb.volume, 0.0, "nothing to swallow")
	main.drop_orb()
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
	main.drop_orb()
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
	_look_at_point(main.house_at * target)


## Turns the player to look at `point` (in the world).
func _look_at_point(point: Vector3) -> void:
	var p := main.player
	var d := point - (p.global_position + Vector3(0, Player.EYES, 0))
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
