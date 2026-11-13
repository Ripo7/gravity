extends TestCase
## The course: it stands as built, each obstacle really is in the way, and
## there is a way to the light (blast the wall, have the orb swallow the
## plug, bring the tank down and climb its rubble, break into the hut).

var main: Main
var s: Structure
var course: Course
var p: Player


func test_as_built_only_the_plug_is_loose() -> void:
	await _load()
	await frames(120)
	var loose := s.pieces.volume()
	check(s.pieces.live >= 2, "the plug came loose in blocks (%d)" % s.pieces.live)
	check(loose > 8.0, "all of it (%.1f m3)" % loose)
	var heavy := 1e9
	var in_gate := true
	for i in s.pieces.top:
		if s.pieces.alive[i] == 1:
			heavy = minf(heavy, s.pieces.mass[i])
			var at := s.pieces.transform_of(i).origin
			in_gate = (
				in_gate
				and absf(at.x) < Course.GATE_HALF
				and at.z < Course.GATE_NEAR
				and at.z > Course.GATE_FAR
			)
	check(heavy > 1500.0, "each too heavy to shove (the lightest %.0f kg)" % heavy)
	check(in_gate, "and still in the gate")
	check_near(s.standing_volume() + loose, s.total_volume, 1e-2, "everything else stands")
	check_eq(s.pieces.awake, 0, "nothing is moving")
	s.support.look(s)
	check(s.support.worst < 0.9, "no bond near breaking (%.2f)" % s.support.worst)
	check(not course.running and not course.done, "the clock has not started")
	await _unload()


func test_each_obstacle_is_in_the_way() -> void:
	await _load()
	await frames(60)
	# The wall: walking and jumping at it gets you nowhere.
	_stand(Vector3(0, 0.05, 2), Vector3(0, 1.6, -30))
	await _walk(150, true)
	check(p.global_position.z > Course.WALL_Z, "the wall stops you (z %.1f)" % p.global_position.z)
	# The plugged gate.
	_stand(Vector3(0, 0.05, -8), Vector3(0, 1.6, -30))
	await _walk(150, true)
	check(p.global_position.z > Course.GATE_NEAR - 0.6, "the plug stops you (z %.1f)" % p.global_position.z)
	# A shock wave does not clear it.
	_stand(Vector3(0, 0.05, -8), Vector3(0, 1.2, -12))
	await _blast(Vector3(0, 1.2, -12))
	await _walk(150, true)
	check(
		p.global_position.z > Course.GATE_NEAR - 0.8,
		"nor does one shock wave clear it (z %.1f)" % p.global_position.z
	)
	# The ledge, on either side of the tank, and the rock of the bay.
	var top := 0.0
	for x: float in [-1.95, 1.95, -3.2, 3.2]:
		_stand(Vector3(x, 0.05, -17.5), Vector3(x, 1.6, -40))
		for k in 5:
			await _walk(40, true)
			top = maxf(top, p.global_position.y)
	check(top > 2.0 and top < Course.LEDGE_H, "the ledge is too high to jump onto (you reach %.2f m)" % top)
	check(not course.done, "and you are not there yet")
	await _unload()


func test_the_orb_clears_the_gate_from_wherever_you_hold_it() -> void:
	# Right against the plug, in front of it, from afar and off to the side:
	# blocks that jam in the gate come apart and go in shard by shard.
	for from: Vector3 in [Vector3(0, 0.05, -10.4), Vector3(0, 0.05, -6), Vector3(1.5, 0.05, -7)]:
		await _load()
		await frames(60)
		_stand(from, Vector3(0, 1.4, -12.5))
		var orb := main.start_orb()
		await frames(300)
		main.drop_orb()
		check(orb.swallowed > 10.0, "from %s the orb swallowed the plug (%.1f m3)" % [from, orb.swallowed])
		_stand(Vector3(0, 0.05, -9), Vector3(0, 1.6, -40))
		await _walk(150, true)
		check(
			p.global_position.z < Course.GATE_FAR - 0.5, "and the way is clear (z %.1f)" % p.global_position.z
		)
		await _unload()


func test_there_is_a_way_to_the_light() -> void:
	await _load()
	var result := []
	course.finished.connect(func(seconds: float, waves: int) -> void: result.append([seconds, waves]))
	await frames(60)
	# 1. Through the wall: one shock wave opens it, a second clears the foot
	# of the hole.
	await _walk(40)
	check(course.running, "the clock starts when you move")
	await _blast(Vector3(0, 1.2, Course.WALL_Z))
	await _blast(Vector3(0, 0.4, Course.WALL_Z))
	await _walk(240, true)
	check(p.global_position.z < Course.WALL_Z - 1.0, "through the wall (z %.1f)" % p.global_position.z)
	# 2. The orb swallows the plug.
	_stand(Vector3(0, p.global_position.y, -7.5), Vector3(0, 1.2, -12.5))
	var orb := main.start_orb()
	for k in 60:
		await frames(10)
		if s.pieces.live == 0:
			break
	main.drop_orb()
	check(orb.swallowed > 8.0, "the orb swallowed the plug (%.1f m3)" % orb.swallowed)
	_face(Vector3(0, 1.6, -40))
	await _walk(200, true)
	check(p.global_position.z < Course.GATE_FAR - 0.5, "through the gate (z %.1f)" % p.global_position.z)
	# 3. Two legs less and the tank comes down; you climb what is left of it.
	_stand(Vector3(0, 0.05, -16), Vector3(0, 1.0, -21))
	var loose := s.pieces.volume()
	var z := Course.LEDGE_Z + Course.TANK_GAP + Course.TANK_DEEP - Course.LEG * 0.5
	for x: float in [-1.0, 1.0]:
		await _blast(Vector3(x * (Course.TANK_HALF - Course.LEG * 0.5), 1.0, z))
	await frames(300)
	loose = s.pieces.volume() - loose
	check(loose > 15.0, "the tank came down (%.1f m3 of rubble)" % loose)
	var up := false
	for x: float in [0.0, -1.0, 1.0, -1.8, 1.8]:
		_stand(Vector3(x, 0.05, -17), Vector3(x, 1.6, -40))
		for k in 8:
			await _walk(40, true)
			up = p.global_position.y > Course.LEDGE_H - 0.05 and p.global_position.z < Course.LEDGE_Z - 0.3
			if up:
				break
		if up:
			break
	check(up, "up onto the ledge over the rubble (at %s)" % p.global_position.snappedf(0.1))
	# 4. Into the hut.
	if up:
		_stand(Vector3(0, Course.LEDGE_H + 0.05, -30), Vector3(0, Course.LEDGE_H + 1.2, -35))
		await _blast(Vector3(0, Course.LEDGE_H + 1.2, -35))
		_face(Vector3(0, Course.LEDGE_H + 1.6, -60))
		await _walk(240, true)
	check_eq(result.size(), 1, "you reach the light")
	if result.size() == 1:
		check(result[0][0] > 5.0, "the clock ran (%.1f s)" % result[0][0])
		check_eq(result[0][1], 5, "the shock waves were counted")
	check(course.done, "and the course is over")
	var clock := course.seconds
	await frames(30)
	check_eq(course.seconds, clock, "the clock has stopped")
	check_near(s.standing_volume() + s.pieces.volume(), s.total_volume, 1e-2, "nothing is unaccounted for")
	await _unload()


## Puts the player at `at`, looking at `target`.
func _stand(at: Vector3, target: Vector3) -> void:
	p.global_position = at
	p.velocity = Vector3.ZERO
	_face(target)


func _face(target: Vector3) -> void:
	var d := target - (p.global_position + Vector3(0, Player.EYES, 0))
	p.rotation.y = atan2(-d.x, -d.z)
	p.head.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())


## Walks forward for `steps` physics frames, jumping whenever on the ground
## if `jumping`.
func _walk(steps: int, jumping := false) -> void:
	for k in steps:
		p.touch_move = Vector2(0, -1)
		if jumping and p.is_on_floor():
			p.touch_jump = true
		await frames(1)
	p.touch_move = Vector2.ZERO


## A shock wave at `target`, then the time for the next one.
func _blast(target: Vector3) -> void:
	_face(target)
	p.touch_fire = true
	await frames(70)


func _load() -> void:
	seed(5)
	Main.next_level = "course"
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await frames(2)
	s = main.structure
	course = main.course
	p = main.player


func _unload() -> void:
	main.queue_free()
	Main.next_level = ""
	await frames(2)
