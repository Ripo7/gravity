extends TestCase
## The brute's blows: the combination and the kick, what they show, where
## they take the body, and what each says when its fist or foot gets there.

var main: Main
var p: Player


func test_three_blows_in_a_row_then_it_stands_again() -> void:
	await _load()
	var c := p.character
	var from := p.global_position
	check(p.punch(), "it strikes")
	check_eq(c.state, "jab", "a straight left first")
	# Pressed again and again: the combination, in order.
	var seen: Array[String] = []
	var left := 0.0
	var right := 0.0
	var low := 9.0
	var overhead := 0.0
	var ground := 9.0
	for k in 360:
		if k % 6 == 0 and k < 100:
			p.punch()
		await frames(1)
		if seen.is_empty() or seen[-1] != c.state:
			seen.append(c.state)
		if seen.size() <= 2:
			left = maxf(left, _ahead("hand.L"))
			right = maxf(right, _ahead("hand.R"))
			low = minf(low, _bone("hips").y - p.global_position.y)
		elif c.state == "slam":
			overhead = maxf(overhead, _bone("hand.R").y - p.global_position.y)
			ground = minf(ground, _bone("hand.R").y - p.global_position.y)
		if c.state == "ground" and k > 100:
			break
	check_eq(
		seen,
		["jab", "cross", "slam", "jab", "ground"] as Array[String],
		"a straight left, a straight right, a leap and a slam, round again, then standing: nothing else"
	)
	check(
		left > 0.6 and right > 0.5,
		"the two straights go straight out (%.2f and %.2f m ahead)" % [left, right]
	)
	check(low > 0.7, "thrown standing (hips no lower than %.2f m)" % low)
	check(overhead > 1.7, "for the last the fist goes straight up (%.2f m)" % overhead)
	check(ground < 0.45, "and comes down to the ground (%.2f m)" % ground)
	# The straights stay where they are; the leap takes its own steps, and
	# the body has followed them.
	var moved := p.global_position.distance_to(from)
	check(moved > 0.7 and moved < 6.0, "the body followed the steps of the leap (%.2f m)" % moved)
	# Nothing of the kind in the air.
	p.touch_jump = true
	await frames(6)
	check(not p.punch() and not p.kick(), "no blow or kick in the air")
	await _unload()


func test_each_blow_says_when_it_lands_how_far_and_how_hard() -> void:
	await _load()
	var c := p.character
	# What the character says the moment each fist or foot gets there:
	# [move, s since the first press, reach, power, height], and then
	# where the limb that strikes is in the pose of that step (from the
	# body's feet): the pose is set after the character has spoken.
	var landed: Array[Array] = []
	var steps := [0]
	c.struck.connect(
		func(move: String) -> void: landed.append([move, steps[0] / 60.0, c.reach(), c.power(), c.height()])
	)
	p.punch()
	for k in 200:
		if k % 6 == 0 and k < 110:
			p.punch()
		await frames(1)
		steps[0] += 1
		if not landed.is_empty() and landed[-1].size() == 5:
			landed[-1].append(_bone("hand.L" if landed[-1][0] == "jab" else "hand.R") - p.global_position)
		if landed.size() == 3:
			break
	var named: Array[String] = []
	for blow in landed:
		named.append(blow[0])
	check_eq(named, Character.COMBO, "each blow of the combination lands, once and in order")
	if landed.size() == 3:
		for k in 3:
			var blow := landed[k]
			var limb: Vector3 = blow[5]
			var out := Vector2(limb.x, limb.z).length()
			check_eq(blow[3], 3 if k == 2 else 2, "%s: a blow is 2, the last one 3" % blow[0])
			check(blow[2] > 0.5 and blow[2] < 1.6, "%s reaches %.2f m" % [blow[0], blow[2]])
			check(
				absf(out - blow[2]) < 0.35,
				"%s: the fist is where the blow says (%.2f m out for %.2f)" % [blow[0], out, blow[2]]
			)
			check(
				absf(limb.y - blow[4]) < 0.35,
				"%s: and as high (%.2f m for %.2f)" % [blow[0], limb.y, blow[4]]
			)
			check(k == 0 or blow[1] > landed[k - 1][1] + 0.3, "%s lands after the one before" % blow[0])
		check(landed[0][1] < 0.3, "the first lands in a quarter of a second (%.2f s)" % landed[0][1])
		check(landed[2][1] < 2.0, "the last within two (%.2f s)" % landed[2][1])
	await frames(120)
	# The kick.
	landed.clear()
	steps[0] = 0
	check(p.kick(), "it kicks")
	check_eq(c.state, "kick", "a kick")
	for k in 90:
		await frames(1)
		steps[0] += 1
		if not landed.is_empty():
			landed[-1].append(_bone("foot.R") - p.global_position)
			break
	check_eq(landed.size(), 1, "the kick lands")
	if landed.size() == 1:
		var foot: Vector3 = landed[0][5]
		check_eq(landed[0][3], 3, "as hard as the last blow")
		check(foot.y < 0.4, "the foot is low when it counts (%.2f m up)" % foot.y)
		check(landed[0][2] > 0.5, "out in front of the brute (%.2f m)" % landed[0][2])
		check(landed[0][1] < 0.3, "within a third of a second (%.2f s)" % landed[0][1])
	await frames(70)
	check_eq(c.state, "ground", "then it stands again")
	check(_bone("foot.R").y < 0.25, "both feet on the ground")
	await _unload()


func test_a_blow_is_thrown_where_the_stick_pushes() -> void:
	await _load()
	var from := p.global_position
	p.touch_move = Vector2(1, 0)  # to the right of the view
	await frames(2)
	p.punch()
	p.touch_move = Vector2.ZERO
	var reached := 0.0
	for k in 40:
		await frames(1)
		reached = maxf(reached, _bone("hand.L").x - from.x)
	check(
		absf(angle_difference(p.facing, p.yaw - PI * 0.5)) < 0.2,
		"it turns to where the stick was pushed (%.0f deg)" % rad_to_deg(p.facing)
	)
	# (The straight left stays where it is; its fist goes that way.)
	check(reached > 0.5, "and strikes that way (its fist goes %.2f m)" % reached)
	await frames(90)
	# Without the stick: where it faces.
	var facing := p.facing
	p.punch()
	await frames(40)
	check(absf(angle_difference(p.facing, facing)) < 0.05, "or where it faces")
	await _unload()


func test_a_blow_lands_where_its_fist_first_touches() -> void:
	await _load()
	var c := p.character
	var s := main.structure
	# Right up against the wall, the arms go through it. Each blow lands
	# where its fist goes in, when it does: [move, where, on which piece,
	# steps since it was thrown, how far that is from where the fist and
	# the arm went in that step].
	_stand(Main.WALL_AT + Vector3(0, 0.05, 0.6), Main.WALL_AT + Vector3.UP)
	await frames(10)
	var landed: Array[Array] = []
	var step := [0]
	var began := [0]
	var fist_was := [Vector3.ZERO]
	c.swung.connect(func(_move: String) -> void: began[0] = step[0])
	p.blow.connect(
		func(at: Vector3, _way: Vector3, _power: int, on: RID) -> void:
			var limb := c.limb()
			var off := minf(
				_off(at, fist_was[0], limb[2]), minf(_off(at, limb[1], limb[2]), _off(at, limb[0], limb[1]))
			)
			landed.append([c.state, at, s.standing(on), step[0] - began[0], off])
	)
	for k in 400:
		if k % 6 == 0 and landed.size() < 3:
			p.punch()
		await frames(1)
		step[0] += 1
		fist_was[0] = c.limb()[2]
		if landed.size() == 3:
			break
	var named: Array[String] = []
	for blow in landed:
		named.append(blow[0])
	check_eq(named, Character.COMBO, "each blow of the combination lands, once and in order")
	if landed.size() == 3:
		var face := Main.WALL_AT.z + Main.WALL.z * 0.5
		for blow in landed:
			var at: Vector3 = blow[1]
			check_eq(blow[2], main.wall, "%s lands on the wall" % blow[0])
			check(absf(at.z - face) < 0.03, "%s: on its face (z %.2f for %.2f)" % [blow[0], at.z, face])
			check(
				blow[4] < Player.FIST + 0.03,
				"%s: where the fist went in that step (%.2f m off)" % [blow[0], blow[4]]
			)
			var hit: float = c._clips.get_animation("fight/" + blow[0]).get_meta("hit")
			check(
				blow[3] <= roundi(hit * 60.0) + 1,
				"%s: no later than its move has it land (step %d)" % [blow[0], blow[3]]
			)
		var left: Vector3 = landed[0][1] - p.global_position
		var right: Vector3 = landed[1][1] - p.global_position
		var slam: Vector3 = landed[2][1] - p.global_position
		for straight: Vector3 in [left, right]:
			check(
				straight.y > 1.25 and straight.y < 1.6,
				"a straight goes in at the height of the shoulder (%.2f m up)" % straight.y
			)
			check(absf(straight.x) < 0.3, "straight ahead (%.2f m aside)" % straight.x)
		check(slam.y > 1.7, "the fist from above goes in over the brute's head (%.2f m up)" % slam.y)
	await _unload()
	# A thin column, the brute a little to one side of it: the arms run
	# into it all the same.
	for side: float in [0.3, -0.3]:
		await _load()
		s = main.structure
		_stand(Main.COLUMN_AT + Vector3(side, 0.05, 1.0), Main.COLUMN_AT + Vector3(side, 1, 0))
		await frames(10)
		var on_it: Array[Vector3] = []
		var thrown := [0]
		p.blow.connect(
			func(at: Vector3, _way: Vector3, _power: int, on: RID) -> void:
				thrown[0] += 1
				if on.is_valid() and s.standing(on) == main.column:
					on_it.append(at)
		)
		for k in 400:
			if k % 6 == 0 and thrown[0] < 3:
				p.punch()
			await frames(1)
			if thrown[0] >= 3:
				break
		check(
			on_it.size() >= 2,
			"%.1f m to one side of a column, blows land on it (%d of 3)" % [side, on_it.size()]
		)
		for at in on_it:
			var off := Vector2(at.x - Main.COLUMN_AT.x, at.z - Main.COLUMN_AT.z)
			check(maxf(absf(off.x), absf(off.y)) < 0.23, "on the column itself (%s)" % at.snappedf(0.01))
		await _unload()


func test_a_blow_that_touches_nothing_says_where_its_fist_ended() -> void:
	await _load()
	var c := p.character
	var landed: Array[Array] = []
	var step := [0]
	var began := [0]
	c.swung.connect(func(_move: String) -> void: began[0] = step[0])
	p.blow.connect(
		func(at: Vector3, way: Vector3, power: int, on: RID) -> void:
			landed.append(
				[c.state, at.distance_to(c.limb()[2]), on.is_valid(), step[0] - began[0], way, power]
			)
	)
	for k in 400:
		if k % 6 == 0 and landed.size() < 3:
			p.punch()
		await frames(1)
		step[0] += 1
		if landed.size() == 3:
			break
	check_eq(landed.size(), 3, "each blow of the combination says so once")
	var ahead := Basis(Vector3.UP, p.facing) * Vector3.FORWARD
	for blow in landed:
		var hit: float = c._clips.get_animation("fight/" + blow[0]).get_meta("hit")
		check(not blow[2], "%s: on nothing" % blow[0])
		check(blow[1] < 0.01, "%s: where its fist is (%.2f m off)" % [blow[0], blow[1]])
		check(
			absi(blow[3] - roundi(hit * 60.0)) <= 1,
			"%s: when its move has it land (step %d)" % [blow[0], blow[3]]
		)
		check((blow[4] as Vector3).dot(ahead) > 0.9, "%s: thrown ahead" % blow[0])
		check_eq(blow[5], 3 if blow[0] == "slam" else 2, "%s: as hard as it is" % blow[0])
	check_eq(main.structure.standing_count, main.structure.pieces, "nothing on the bench took anything")
	await _unload()


func test_the_body_stays_out_of_what_stands_while_it_strikes() -> void:
	# Right up against the wall, the column and the thinner metal post: the
	# combination, then a kick. The moves lunge 0.9 m ahead of where the
	# brute stands in the leap.
	for target: Array in [
		["the wall", Main.WALL_AT, 0.6],
		["the column", Main.COLUMN_AT, 0.6],
		["the metal post", Main.METAL_POST_AT, 0.5]
	]:
		await _load()
		var c := p.character
		var s := main.structure
		var at: Vector3 = target[1]
		_stand(at + Vector3(0, 0.05, target[2]), at + Vector3.UP)
		await frames(10)
		var thrown := [0]
		var on_it := [0]
		p.blow.connect(
			func(_at: Vector3, _way: Vector3, _power: int, on: RID) -> void:
				thrown[0] += 1
				if on.is_valid() and s.standing(on) >= 0:
					on_it[0] += 1
		)
		var steps := 0
		var inside := 0
		var kicked := false
		var farthest := 0.0
		for k in 700:
			if k % 6 == 0 and thrown[0] < 3:
				p.punch()
			elif thrown[0] >= 3 and not c.striking() and not kicked:
				kicked = p.kick()
			await frames(1)
			if c.striking():
				steps += 1
				inside += _in_what_stands(c)
				farthest = maxf(farthest, p.global_position.z - at.z)
			elif kicked:
				break
		check(steps > 100 and kicked, "against %s: a combination and a kick (%d steps)" % [target[0], steps])
		check_eq(
			inside, 0, "against %s, nothing of the body but the limb that strikes goes into it" % target[0]
		)
		check(on_it[0] >= 3, "against %s, its blows land all the same (%d)" % [target[0], on_it[0]])
		check(
			farthest > target[2] + 0.2,
			"against %s, it is held back to lunge (%.2f m from it)" % [target[0], farthest]
		)
		check(farthest < 1.6, "no farther than its lunge is long")
		await _unload()
	# In the open nothing holds it back: it goes where its moves step.
	await _load()
	var from := p.global_position
	for k in 200:
		if k % 6 == 0 and k < 110:
			p.punch()
		await frames(1)
	check(p.global_position.distance_to(from) > 0.7, "in the open the body follows the steps of its blows")
	await _unload()


func test_the_two_straights_are_thrown_standing_at_the_height_of_the_shoulder() -> void:
	await _load()
	var c := p.character
	var s := main.structure
	# A step from the wall: a straight left, a straight right, then the
	# leap. [move, where from the brute, on which piece, how
	# far the body has gone, how far the fist that struck is from there]
	_stand(Main.WALL_AT + Vector3(0, 0.05, 0.9), Main.WALL_AT + Vector3.UP)
	await frames(10)
	var from := p.global_position
	var landed: Array[Array] = []
	var inside := 0
	p.blow.connect(
		func(at: Vector3, _way: Vector3, power: int, on: RID) -> void:
			var fist := _bone("f_middle.01.L" if c.state == "jab" else "f_middle.01.R")
			landed.append(
				[
					c.state,
					at - p.global_position,
					s.standing(on),
					p.global_position.distance_to(from),
					power,
					fist.distance_to(c.limb()[2])
				]
			)
	)
	for k in 400:
		if k % 6 == 0 and landed.size() < 3:
			p.punch()
		await frames(1)
		if c.striking():
			inside += _in_what_stands(c)
		if landed.size() == 3:
			break
	var named: Array[String] = []
	for blow in landed:
		named.append(blow[0])
	check_eq(named, Character.COMBO, "the three land, in order")
	for k in mini(landed.size(), 2):
		var blow := landed[k]
		var at: Vector3 = blow[1]
		check_eq(blow[2], main.wall, "%s lands on the wall" % blow[0])
		check(at.y > 1.25 and at.y < 1.6, "%s: at the height of the shoulder (%.2f m up)" % [blow[0], at.y])
		check(absf(at.x) < 0.3, "%s: straight ahead (%.2f m aside)" % [blow[0], at.x])
		check(blow[3] < 0.1, "%s: thrown standing (the body has gone %.2f m)" % [blow[0], blow[3]])
		check_eq(blow[4], 2, "%s: a blow of 2" % blow[0])
		check(blow[5] < 0.01, "%s: it is the fist of that hand that is followed" % blow[0])
	check_eq(inside, 0, "nothing of the body but the arm that strikes goes into the wall")
	await _unload()


## How many parts of the body of `c`, but for the limb that strikes, are in
## something that stands (a ball a little smaller than each).
func _in_what_stands(c: Character) -> int:
	var count := 0
	var ball := SphereShape3D.new()
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = ball
	query.collision_mask = Layers.STRUCTURE
	for part in c.bulk():
		ball.radius = part.w - 0.03
		query.transform = Transform3D(Basis(), Vector3(part.x, part.y, part.z))
		if not p.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			count += 1
	return count


## How far `at` is from the stretch between `from` and `to`.
func _off(at: Vector3, from: Vector3, to: Vector3) -> float:
	var along := to - from
	if along.length_squared() < 0.000001:
		return at.distance_to(from)
	return at.distance_to(from + along * clampf((at - from).dot(along) / along.length_squared(), 0.0, 1.0))


## Puts the brute at `at`, facing `target`.
func _stand(at: Vector3, target: Vector3) -> void:
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.facing = atan2(at.x - target.x, at.z - target.z)
	p.look(Vector2(angle_difference(p.yaw, p.facing), 0.0))


## Where bone `named` of the character is, in the world.
func _bone(named: String) -> Vector3:
	var sk := p.character.skeleton
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone("DEF-" + named)).origin


## How far ahead of the player (m, the way it faces) its bone `named` is.
func _ahead(named: String) -> float:
	var out := _bone(named) - p.global_position
	return out.dot(Basis(Vector3.UP, p.facing) * Vector3.FORWARD)


func _load() -> void:
	seed(5)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await frames(20)
	p = main.player
	# In the open, away from what stands on the bench.
	p.global_position = Vector3(-30, 0.05, 30)
	await frames(5)


func _unload() -> void:
	main.queue_free()
	await frames(2)
