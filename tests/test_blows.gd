extends TestCase
## The brute's blows: the combination and the kick, what they show, where
## they take the body, and what each says when its fist or foot gets there.

var main: Main
var p: Player


func test_four_blows_in_a_row_then_it_stands_again() -> void:
	await _load()
	var c := p.character
	var from := p.global_position
	check(p.punch(), "it strikes")
	check_eq(c.state, "hook", "a hook first")
	# Pressed again and again: the combination, in order.
	var seen: Array[String] = []
	var right := 0.0
	var low := 9.0
	var overhead := 0.0
	var ground := 9.0
	for k in 360:
		if k % 6 == 0 and k < 150:
			p.punch()
		await frames(1)
		if seen.is_empty() or seen[-1] != c.state:
			seen.append(c.state)
		if c.state == "hook" and seen.size() == 1:
			right = maxf(right, _ahead("hand.R"))
			low = minf(low, _bone("hips").y - p.global_position.y)
		elif c.state == "slam":
			overhead = maxf(overhead, _bone("hand.R").y - p.global_position.y)
			ground = minf(ground, _bone("hand.R").y - p.global_position.y)
		if c.state == "ground" and k > 150:
			break
	check_eq(
		seen,
		["hook", "upswing", "backhand", "slam", "hook", "ground"] as Array[String],
		"a hook, a swing up, one back across, a leap and a slam, round again, then standing: nothing else"
	)
	check(right > 1.1, "the hook lunges: the fist goes far out (%.2f m ahead)" % right)
	check(low < 0.6, "the body dropping into it (hips %.2f m up)" % low)
	check(overhead > 1.7, "for the last the fist goes straight up (%.2f m)" % overhead)
	check(ground < 0.45, "and comes down to the ground (%.2f m)" % ground)
	# The moves take their own steps, and some dash a long way: the body has
	# followed them.
	var moved := p.global_position.distance_to(from)
	check(moved > 1.5 and moved < 6.0, "the body followed the steps of the blows (%.2f m)" % moved)
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
			landed[-1].append(_bone("hand.R") - p.global_position)
		if landed.size() == 4:
			break
	var named: Array[String] = []
	for blow in landed:
		named.append(blow[0])
	check_eq(named, Character.COMBO, "each blow of the combination lands, once and in order")
	if landed.size() == 4:
		for k in 4:
			var blow := landed[k]
			var limb: Vector3 = blow[5]
			var out := Vector2(limb.x, limb.z).length()
			check_eq(blow[3], 3 if k == 3 else 2, "%s: a blow is 2, the last one 3" % blow[0])
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
		check(landed[0][1] < 0.35, "the hook lands in a third of a second (%.2f s)" % landed[0][1])
		check(landed[3][1] < 2.4, "the last within two and a half (%.2f s)" % landed[3][1])
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
		check(foot.y > 0.8, "the foot is up when it counts (%.2f m)" % foot.y)
		check(landed[0][2] > 0.8, "and reaches farther than a fist (%.2f m)" % landed[0][2])
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
	await frames(40)
	check(
		absf(angle_difference(p.facing, p.yaw - PI * 0.5)) < 0.2,
		"it turns to where the stick was pushed (%.0f deg)" % rad_to_deg(p.facing)
	)
	check(p.global_position.x > from.x + 0.3, "and steps that way (%.2f m)" % (p.global_position.x - from.x))
	await frames(90)
	# Without the stick: where it faces.
	var facing := p.facing
	p.punch()
	await frames(40)
	check(absf(angle_difference(p.facing, facing)) < 0.05, "or where it faces")
	await _unload()


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
