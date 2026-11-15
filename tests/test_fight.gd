extends TestCase
## The fight: the blows, the kick and the guard, what they do to the other
## brute and to the house, the other brute hitting back, and locking on.

var main: Main
var p: Player
var d: Brute


func test_four_blows_in_a_row_then_it_stands_again() -> void:
	await _load()
	# In the open, no one near.
	_stand(Vector3(-30, 0.05, 30), Vector3(-30, 1.5, 0))
	await frames(10)
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
			low = minf(low, _bone(c, "hips").y - p.global_position.y)
		elif c.state == "slam":
			overhead = maxf(overhead, _bone(c, "hand.R").y - p.global_position.y)
			ground = minf(ground, _bone(c, "hand.R").y - p.global_position.y)
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
	check(moved > 1.5 and moved < 5.0, "the body followed the steps of the blows (%.2f m)" % moved)
	# Nothing of the kind in the air.
	p.touch_jump = true
	await frames(6)
	check(not p.punch() and not p.kick(), "no blow or kick in the air")
	p.touch_guard = true
	await frames(3)
	check(c.state != "guard", "nor the guard")
	p.touch_guard = false
	await _unload()


func test_a_blow_steps_in_and_the_other_takes_it() -> void:
	await _load()
	var at := d.global_position
	# A little too far for the arm.
	_stand(at + Vector3(0, 0, 1.7), at + Vector3.UP * 1.3)
	await frames(10)
	check(absf(angle_difference(d.facing, PI)) < 0.1, "the other brute faces who comes near")
	p.punch()
	var waited := 0
	while d.character.state == "ground" and waited < 60:
		await frames(1)
		waited += 1
	check_eq(d.character.state, "hit_chest", "its head goes back")
	check(waited > 12, "the blow takes its time: it is heavy (%.2f s)" % (waited / 60.0))
	var gap := p.global_position.distance_to(d.global_position)
	check(gap > 1.4 and gap < 1.7, "the character stepped in to the reach of its lunge (%.2f m)" % gap)
	# The fist is where the blow is: on the other.
	var fist := _bone(p.character, "hand.R") - d.global_position
	check(
		Vector2(fist.x, fist.z).length() < 0.4 and fist.y > 0.5 and fist.y < 1.0,
		"the fist is on it when it counts (%s from its feet)" % fist.snappedf(0.01)
	)
	await frames(20)
	check(d.global_position.z < at.z - 0.05, "which is pushed back (%.2f m)" % (at.z - d.global_position.z))
	check(d.fighter.up(), "and still on its feet")
	await frames(60)
	check_eq(p.character.state, "ground", "one press, one blow, and it stands again")
	await _unload()


func test_a_blow_at_nothing_hits_nothing() -> void:
	await _load()
	var at := d.global_position
	# Too far to go for it, and not locked on.
	_stand(at + Vector3(0, 0, Player.SEEK + 0.6), at + Vector3.UP * 1.3)
	await frames(10)
	var from := p.global_position
	p.punch()
	await frames(60)
	check_eq(d.character.state, "ground", "out of reach")
	check(p.global_position.distance_to(from) < 0.6, "and it did not go for it")
	await frames(30)  # the blow runs its course
	# Close, but its back to it.
	_stand(at + Vector3(0, 0, 1.0), at + Vector3(0, 1.3, 20))
	await frames(60)
	p.punch()
	await frames(60)
	check_eq(d.character.state, "ground", "a blow thrown the other way")
	check(absf(angle_difference(p.facing, PI)) < 0.3, "the character did not turn round for it")
	await _unload()


func test_the_blow_from_overhead_throws_the_other_through_the_house() -> void:
	await _load()
	# In front of the front wall, where it is solid: the other brute has its
	# back to it.
	var house := main.house_at
	d.global_position = house * Vector3(-2.9, 0.05, 5.0)
	_stand(house * Vector3(-2.9, 0.05, 6.2), house * Vector3(-2.9, 1.3, 5.0))
	await frames(10)
	var standing := main.structure.held_count
	var waited := 0
	while d.fighter.up() and waited < 300:
		if waited % 6 == 0:
			p.punch()
		await frames(1)
		waited += 1
	check_eq(d.fighter.state, "flying", "the fourth blow takes it off its feet")
	check_eq(p.character.state, "slam", "the one from overhead")
	check(waited < 180, "two seconds or so after the first (%.1f s)" % (waited / 60.0))
	check_eq(d.collision_layer, 0, "nothing to walk into while it is off its feet")
	await frames(150)
	var landed := house.affine_inverse() * d.global_position
	check(landed.z < House.Z1 - 1.0, "it went through the front wall (it is at z %.1f)" % landed.z)
	var gone := standing - main.structure.held_count
	check(gone > 15, "and took a good part of it along (%d shards)" % gone)
	check(d.global_position.distance_to(p.global_position) > 5.0, "thrown a long way")
	check(_bone(d.character, "hips").y - d.global_position.y < 0.4, "it lies where it landed")
	await frames(int((Fighter.LIES + 2.5) * 60.0))
	check(d.fighter.up(), "then it gets back up")
	check(_bone(d.character, "hips").y - d.global_position.y > 0.7, "on its feet")
	check_eq(d.collision_layer, Structure.LAYER_ACTOR, "and in the way again")
	await _unload()


func test_fists_break_what_stands() -> void:
	await _load()
	var house := main.house_at
	# Facing the front wall, where it is solid, at arm's length.
	_stand(house * Vector3(-2.5, 0.05, House.Z1 + 0.9), house * Vector3(-2.5, 1.3, 0.0))
	await frames(10)
	var standing := main.structure.held_count
	p.punch()
	await frames(50)
	var fist := standing - main.structure.held_count
	check(fist >= 3, "a blow knocks a hole in the wall (%d shards)" % fist)
	await frames(90)
	standing = main.structure.held_count
	p.kick()
	await frames(80)
	var kick := standing - main.structure.held_count
	check(kick >= 3, "a kick another (%d shards)" % kick)
	await _unload()


func test_the_other_brute_comes_through_the_house_to_hit_back() -> void:
	await _load()
	# The player in front of the house, the other brute behind it: the whole
	# house is between them.
	var house := main.house_at
	_stand(house * Vector3(-2.5, 0.05, 8.0), house * Vector3(-2.5, 1.5, 0))
	d.global_position = house * Vector3(-2.5, 0.05, -6.0)
	d.ai = true
	var standing := main.structure.held_count
	# Left alone, it comes straight through and strikes: sooner or later the
	# player is thrown.
	var took := false
	var thrown := false
	for k in 2400:
		await frames(1)
		took = took or p.character.state.begins_with("hit_") or not p.fighter.up()
		if not p.fighter.up():
			thrown = true
			break
	check(took, "it came and landed a blow")
	check(thrown, "and ended up throwing the player")
	var gone := standing - main.structure.held_count
	check(gone > 10, "having come through the walls that were in its way (%d shards)" % gone)
	check(not p.punch() and not p.kick(), "who can do nothing while off its feet")
	d.ai = false
	await frames(int((Fighter.LIES + 4.0) * 60.0))
	check(p.fighter.up(), "the player gets back up")
	await _unload()


func test_a_kick_reaches_farther_and_throws_the_other() -> void:
	await _load()
	var at := d.global_position
	_stand(at + Vector3(0, 0, 2.0), at + Vector3.UP * 1.3)
	await frames(10)
	check(p.kick(), "it kicks")
	check_eq(p.character.state, "kick", "a kick")
	var waited := 0
	while d.fighter.up() and waited < 90:
		await frames(1)
		waited += 1
	check_eq(d.fighter.state, "flying", "a kick takes the other off its feet")
	var foot := _bone(p.character, "foot.R") - at
	check(
		Vector2(foot.x, foot.z).length() < 0.5 and foot.y > 0.8,
		"the foot is on it when it counts (%s from its feet)" % foot.snappedf(0.01)
	)
	var gap := p.global_position.distance_to(at)
	check(gap > 1.0, "from a step away (%.2f m)" % gap)
	await frames(60)
	check_eq(p.character.state, "ground", "then it stands again")
	check(_bone(p.character, "foot.R").y < 0.25, "both feet on the ground")
	await frames(90)
	var went := at.z - d.global_position.z
	check(went > 6.0 and went < 20.0, "the other goes a long way in the open (%.1f m)" % went)
	await _unload()


func test_the_guard_is_held_and_stops_what_comes_from_in_front() -> void:
	await _load()
	var at := d.global_position
	_stand(at + Vector3(0, 0, 2.0), at + Vector3.UP * 1.3)
	await frames(10)
	var c := p.character
	var from := p.global_position
	# Held: both fists up in front of the face, and nothing else.
	p.touch_guard = true
	await frames(20)
	check_eq(c.state, "guard", "held, the guard is up")
	var head := _bone(c, "head").y
	for hand: String in ["hand.L", "hand.R"]:
		var up := _bone(c, hand).y
		check(
			up > head - 0.25 and _ahead(hand) > 0.0,
			(
				"%s up in front of the face (%.2f m up, the head at %.2f; %.2f ahead)"
				% [hand, up, head, _ahead(hand)]
			)
		)
	var pose := _bone(c, "hand.L")
	p.touch_move = Vector2(0, -1)
	await frames(60)
	p.touch_move = Vector2.ZERO
	check(_bone(c, "hand.L").distance_to(pose) < 0.001, "a second later nothing has moved")
	check(p.global_position.distance_to(from) < 0.01, "and the stick does not walk it away")
	# What comes from in front meets it: no flinch, and no throw either.
	check(p.fighter.take_hit(Vector3.BACK, 2, false), "a blow reaches it")
	check(c.state == "guard" and p.fighter.held(), "and meets the guard")
	await frames(12)
	check(p.fighter.take_hit(Vector3.BACK, 3, true), "so does one that throws")
	check(c.state == "guard" and p.fighter.up(), "which does not throw it")
	await frames(40)
	var back := p.global_position.z - from.z
	check(back > 0.03 and back < 1.0, "it only gives a little ground (%.2f m)" % back)
	# From behind, it is no use.
	check(p.fighter.take_hit(Vector3.FORWARD, 2, false), "a blow in the back")
	check_eq(c.state, "hit_chest", "is taken")
	await frames(50)
	check_eq(c.state, "guard", "still held, the guard comes back up after it")
	# A blow can be thrown from it, and it comes back after the blow.
	check(p.punch() and c.striking(), "a blow is thrown from the guard")
	await frames(100)
	check_eq(c.state, "guard", "and the guard is back, still held")
	# Let go: the fists come down at once.
	p.touch_guard = false
	await frames(2)
	check_eq(c.state, "ground", "let go, it stands as before")
	await _unload()


func test_the_other_brute_cannot_get_through_the_guard() -> void:
	await _load()
	var at := d.global_position
	_stand(at + Vector3(0, 0, 3.0), at + Vector3.UP * 1.3)
	p.lock()
	p.touch_guard = true
	d.ai = true
	var met := 0
	var held := false
	var only := true
	for k in 600:
		await frames(1)
		only = only and (p.character.state == "guard" or k < 12)
		if p.fighter.held() and not held:
			met += 1
		held = p.fighter.held()
	check(met >= 3, "ten seconds of its blows met the guard (%d of them)" % met)
	check(only and p.fighter.up(), "which held: not a flinch, not a throw")
	# Without it, the same blows land.
	p.touch_guard = false
	var hurt := false
	for k in 600:
		await frames(1)
		hurt = hurt or p.character.state.begins_with("hit_") or not p.fighter.up()
		if hurt:
			break
	check(hurt, "let go, the next blow lands")
	await _unload()


func test_a_blow_that_lands_holds_both_for_an_instant_and_shakes_the_camera() -> void:
	await _load()
	var at := d.global_position
	# Too far, and not locked on: a blow at nothing.
	_stand(at + Vector3(0, 0, 6.0), at + Vector3.UP * 1.3)
	await frames(10)
	p.punch()
	var shook := 0.0
	var held := false
	for k in 70:
		await frames(1)
		shook = maxf(shook, p.camera.rotation.length())
		held = held or p.fighter.held()
	check(not held and shook == 0.0, "a blow at nothing holds nothing and shakes nothing")
	# At arm's length.
	await frames(100)
	_stand(at + Vector3(0, 0, 1.8), at + Vector3.UP * 1.3)
	await frames(10)
	p.punch()
	var waited := 0
	while not d.fighter.held() and waited < 60:
		await frames(1)
		waited += 1
	check(d.fighter.held() and p.fighter.held(), "the instant a blow lands, both are held")
	var fist := _bone(p.character, "hand.R")
	var stood := d.global_position
	var short := Vector2(fist.x - stood.x, fist.z - stood.z).length()
	check(
		short > 0.12 and short < 0.32, "the fist where it landed: on the other (%.2f m from its axis)" % short
	)
	await frames(2)
	check(_bone(p.character, "hand.R").distance_to(fist) < 0.002, "the arm does not move meanwhile")
	check(d.global_position.distance_to(stood) < 0.002, "nor does the other")
	check(p.camera.rotation.length() > 0.0005, "and the camera shakes")
	await frames(int(Fighter.STOP[2] * 60.0) + 3)
	check(not p.fighter.held() and not d.fighter.held(), "then both are let go")
	await frames(12)
	var went := stood.z - d.global_position.z
	check(went > 0.3, "and the other goes back (%.2f m)" % went)
	await frames(int(Player.SHAKE_FOR * 60.0) + 5)
	check(p.camera.rotation.length() < 0.0001, "the shake has died out")
	await _unload()


func test_who_takes_a_blow_goes_the_way_the_blow_goes() -> void:
	await _load()
	var at := d.global_position
	_stand(at + Vector3(0, 0, 1.8), at + Vector3.UP * 1.3)
	await frames(10)
	# The hook goes ahead more than across: the other goes back, its head
	# first.
	p.punch()
	var waited := 0
	while not d.fighter.held() and waited < 60:
		await frames(1)
		waited += 1
	p.punch()  # the swing up is asked for: it follows
	var line := _flat(d.global_position - p.global_position)
	var head := 0.0
	for k in 26:
		await frames(1)
		head = maxf(head, (_bone(d.character, "head") - d.global_position).dot(line))
	check(head > 0.3, "its head goes back first (%.2f m behind its feet)" % head)
	var first := d.global_position - at
	var aside := (first - line * first.dot(line)).length()
	check(
		first.dot(line) > 0.3 and aside < first.dot(line) * 0.6,
		"it goes back (%.2f m, %.2f aside)" % [first.dot(line), aside]
	)
	# The swing up comes from the right: it goes to the left.
	waited = 0
	while not d.fighter.held() and waited < 90:
		await frames(1)
		waited += 1
	check_eq(p.character.state, "upswing", "the swing up lands in its turn")
	var from := d.global_position
	line = _flat(from - p.global_position)
	var left := line.cross(Vector3.UP) * -1.0
	await frames(30)
	var second := d.global_position - from
	check(
		second.dot(left) > 0.25, "it goes to the side the fist goes (%.2f m to the left)" % second.dot(left)
	)
	await _unload()


func test_locking_on_turns_the_camera_to_the_other() -> void:
	await _load()
	var at := d.global_position
	# The other brute behind and to the side: out of view.
	_stand(at + Vector3(4, 0, -5), at + Vector3(4, 1.3, -30))
	await frames(5)
	check(p.locked == null, "not locked on to start with (the fight is off)")
	p.lock()
	check(p.locked == d, "locking picks the other brute")
	await frames(60)
	var seen := _seen(at + Vector3.UP)
	check(seen < -0.05 and seen > -0.7, "a second later it is in view, left of the middle (%.2f rad)" % seen)
	var apart := _seen(p.global_position + Vector3.UP) - seen
	check(apart > 0.15, "and the character to its right, not in front of it (%.2f rad apart)" % apart)
	var yaw := p.yaw
	p.look(Vector2(0.6, 0.0))
	check_eq(p.yaw, yaw, "and stays on it: dragging does not turn it")
	p.lock()
	check(p.locked == null, "locking again lets go")
	p.look(Vector2(0.6, 0.0))
	check(p.yaw != yaw, "and the camera is free again")
	await _unload()


func test_locked_on_a_blow_from_afar_runs_at_the_other_and_lands() -> void:
	await _load()
	var at := d.global_position
	# Seven metres away: far beyond a blow. Not locked: it is thrown in the air.
	_stand(at + Vector3(0, 0, 7.0), at + Vector3.UP * 1.3)
	await frames(10)
	var from := p.global_position
	check(p.punch(), "a blow, not locked on")
	check(p.character.striking(), "is thrown where the character stands")
	await frames(120)
	check_eq(d.character.state, "ground", "and hits nothing")
	check(p.global_position.distance_to(from) < 0.5, "seven metres short")
	# Locked on: the character runs at the other first, and the blow lands.
	await frames(60)
	p.lock()
	check(p.punch(), "the same blow, locked on")
	check(not p.character.striking(), "is not thrown yet")
	var waited := 0
	while d.character.state == "ground" and waited < 240:
		await frames(1)
		waited += 1
	check_eq(d.character.state, "hit_chest", "the character ran at the other and hit it")
	check(waited < 180, "within a couple of seconds (%.1f s)" % (waited / 60.0))
	check(p.global_position.distance_to(from) > 4.5, "having run most of the way")
	# The other off its feet: nothing to run at, the blow is thrown on the spot.
	d.fighter.launch(Vector3(0, 4, -10))
	await frames(60)
	from = p.global_position
	check(p.kick(), "a kick while the other is down")
	check_eq(p.character.state, "kick", "is thrown on the spot")
	await _unload()


func test_locked_on_the_character_goes_through_a_wall_to_land_its_blow() -> void:
	await _load()
	var house := main.house_at
	# The other brute inside the house, behind the front wall where it is
	# solid; the player outside.
	d.global_position = house * Vector3(-2.9, 0.05, 1.2)
	_stand(house * Vector3(-2.9, 0.05, 9.0), house * Vector3(-2.9, 1.3, 1.2))
	await frames(10)
	var standing := main.structure.held_count
	p.lock()
	check(p.punch(), "a blow asked for with a wall in between")
	var waited := 0
	while d.character.state == "ground" and waited < 300:
		await frames(1)
		waited += 1
	check_eq(d.character.state, "hit_chest", "the character went through the wall and hit it")
	var gone := standing - main.structure.held_count
	check(gone >= 3, "leaving a hole (%d shards)" % gone)
	var inside := house.affine_inverse() * p.global_position
	check(inside.z < House.Z1 + 0.2, "it is in the house now (z %.1f)" % inside.z)
	await _unload()


func test_the_touch_buttons_strike_kick_guard_and_lock() -> void:
	await _load()
	var tc := TouchControls.new()
	tc.player = p
	main.add_child(tc)
	await frames(3)
	# No two buttons under the same thumb.
	var buttons := {
		"punch": [tc.punch_center(), tc.punch_radius()],
		"jump": [tc.jump_center(), tc.jump_radius()],
		"kick": [tc.kick_center(), tc.small_radius()],
		"guard": [tc.guard_center(), tc.small_radius()],
		"lock": [tc.lock_center(), tc.small_radius()],
	}
	var rebuild := Hud.rebuild_rect(tc.size).grow(10)
	for a: String in buttons:
		check(not rebuild.has_point(buttons[a][0]), "%s is clear of the rebuild button" % a)
		for b: String in buttons:
			var apart: float = (
				(buttons[a][0] as Vector2).distance_to(buttons[b][0]) - (buttons[a][1] + buttons[b][1]) * 1.3
			)
			check(a >= b or apart > 0.0, "%s and %s are apart (%.0f px)" % [a, b, apart])
	tc._on_touch(_touch(0, tc.punch_center(), true))
	await frames(2)
	check_eq(p.character.state, "hook", "the big button throws a blow")
	tc._on_touch(_touch(0, tc.punch_center(), false))
	await frames(100)
	tc._on_touch(_touch(1, tc.kick_center(), true))
	await frames(2)
	check_eq(p.character.state, "kick", "the orange button kicks")
	tc._on_touch(_touch(1, tc.kick_center(), false))
	await frames(100)
	tc._on_touch(_touch(2, tc.guard_center(), true))
	await frames(3)
	check_eq(p.character.state, "guard", "the white button, held, is the guard")
	await frames(60)
	check_eq(p.character.state, "guard", "for as long as it is held")
	tc._on_touch(_touch(2, tc.guard_center(), false))
	await frames(3)
	check_eq(p.character.state, "ground", "and no longer")
	tc._on_touch(_touch(3, tc.lock_center(), true))
	check(p.locked == d, "the sight locks on the other brute")
	tc._on_touch(_touch(3, tc.lock_center(), false))
	tc._on_touch(_touch(3, tc.lock_center(), true))
	check(p.locked == null, "and lets go of it")
	await _unload()


func _touch(index: int, at: Vector2, pressed: bool) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = at
	e.pressed = pressed
	return e


## Where bone `named` of `c` is, in the world.
func _bone(c: Character, named: String) -> Vector3:
	var sk := c.skeleton
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone("DEF-" + named)).origin


## Where `point` is seen by the camera: rad to the right of the middle.
func _seen(point: Vector3) -> float:
	var local := p.camera.global_transform.affine_inverse() * point
	return atan2(local.x, -local.z)


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z).normalized()


## How far ahead of the player (m, the way it faces) its bone `named` is.
func _ahead(named: String) -> float:
	var out := _bone(p.character, named) - p.global_position
	return out.dot(Basis(Vector3.UP, p.facing) * Vector3.FORWARD)


func _stand(at: Vector3, target: Vector3) -> void:
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.look_at_point(target)
	p.facing = p.yaw


func _load() -> void:
	seed(5)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
	main.level = "house"
	main.fight = false  # the other brute only stands there
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await frames(20)
	p = main.player
	d = main.brute
	p.input_enabled = true


func _unload() -> void:
	main.queue_free()
	await frames(2)
