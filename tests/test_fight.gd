extends TestCase
## Fighting: the punches, the kick and the duck, what they reach, and the
## dummy that takes them.

var main: Main
var p: Player
var d: Dummy


func test_four_punches_in_a_row_then_the_guard() -> void:
	await _load()
	# In the open, no one near.
	_stand(Vector3(-30, 0.05, 30), Vector3(-30, 1.5, 0))
	await frames(10)
	var c := p.character
	var from := p.global_position
	check(p.punch(), "it punches")
	check_eq(c.state, "jab", "a jab first")
	check(not p.fire(), "no shot in the middle of a punch")
	# Pressed again and again: the combination, in order.
	var seen: Array[String] = []
	var out := {"jab": 0.0, "cross": 0.0, "hook_l": 0.0, "hook_r": 0.0}
	for k in 150:
		if k % 6 == 0 and k < 60:
			p.punch()
		await frames(1)
		if seen.is_empty() or seen[-1] != c.state:
			seen.append(c.state)
		if out.has(c.state):
			var hand := "hand.L" if c.state in ["jab", "hook_l"] else "hand.R"
			out[c.state] = maxf(out[c.state], _ahead(hand))
		if c.state == "guard" and k > 60:
			break
	check_eq(
		seen.slice(0, 5),
		["jab", "cross", "hook_l", "hook_r", "jab"] as Array[String],
		"jab, cross, left and right to the body, and round again"
	)
	for move: String in out:
		check(out[move] > 0.5, "the fist of the %s goes out (%.2f m ahead)" % [move, out[move]])
	check_eq(c.state, "guard", "then the fists stay up")
	await frames(20)
	check(_bone(c, "hand.L").y > 1.05 and _bone(c, "hand.R").y > 1.05, "both of them")
	check(_bone(c, "head").y < 1.45, "in a crouch (head %.2f m up)" % _bone(c, "head").y)
	await frames(int((Character.GUARD_TIME + 0.6) * 60.0))
	check_eq(c.state, "ground", "for a while")
	check(_bone(c, "hand.L").y < 1.0, "then they come down (%.2f m up)" % _bone(c, "hand.L").y)
	# The moves take their own steps: the body has followed them, a little.
	var moved := p.global_position.distance_to(from)
	check(moved > 0.02 and moved < 0.6, "the body followed the steps of the punches (%.2f m)" % moved)
	# Walking away drops the guard at once.
	p.punch()
	await frames(40)
	check_eq(c.state, "guard", "fists up again after a jab")
	p.touch_move = Vector2(0, -1)
	await frames(3)
	check_eq(c.state, "ground", "walking away drops them")
	p.touch_move = Vector2.ZERO
	# Nothing of the kind in the air.
	p.touch_jump = true
	await frames(6)
	check(not p.punch() and not p.kick() and not p.dodge(), "no punch, kick or duck in the air")
	await _unload()


func test_a_punch_steps_in_and_the_dummy_takes_it() -> void:
	await _load()
	var at := d.global_position
	# A little too far for the arm.
	_stand(at + Vector3(0, 0, 1.6), at + Vector3.UP * 1.3)
	await frames(10)
	check(absf(angle_difference(d.facing, PI)) < 0.1, "the dummy faces who comes near")
	p.punch()
	var waited := 0
	while d.blows_left == Dummy.BLOWS and waited < 40:
		await frames(1)
		waited += 1
	check_eq(d.blows_left, Dummy.BLOWS - 1, "a jab counts for one")
	check_eq(d.character.state, "hit_head", "the dummy flinches")
	var gap := p.global_position.distance_to(d.global_position)
	check(gap > 0.8 and gap < 1.05, "it stepped in to arm's length (%.2f m)" % gap)
	# The fist is where the blow is: on the dummy, about its chest.
	var fist := _bone(p.character, "hand.L") - d.global_position
	check(
		Vector2(fist.x, fist.z).length() < 0.35 and fist.y > 1.1 and fist.y < 1.5,
		"the fist is on the dummy when it counts (%s from its feet)" % fist.snappedf(0.01)
	)
	await frames(20)
	check(d.global_position.z < at.z - 0.03, "which is pushed back (%.2f m)" % (at.z - d.global_position.z))
	# Pressed once, one punch. Pressed twice, the cross follows: two more.
	await frames(40)
	check_eq(p.character.state, "guard", "one press, one punch")
	check_eq(d.blows_left, Dummy.BLOWS - 1, "and one blow")
	p.punch()
	await frames(2)
	p.punch()
	await frames(60)
	check_eq(d.blows_left, Dummy.BLOWS - 4, "a jab and a cross: three more")
	await _unload()


func test_a_punch_at_nothing_hits_nothing() -> void:
	await _load()
	var at := d.global_position
	# Too far to go for it.
	_stand(at + Vector3(0, 0, Player.SEEK + 0.5), at + Vector3.UP * 1.3)
	await frames(10)
	var from := p.global_position
	p.punch()
	await frames(40)
	check_eq(d.blows_left, Dummy.BLOWS, "out of reach")
	check(p.global_position.distance_to(from) < 0.25, "and it did not go for it")
	# Close, but its back to it.
	_stand(at + Vector3(0, 0, 1.0), at + Vector3(0, 1.3, 20))
	await frames(40)
	p.punch()
	await frames(40)
	check_eq(d.blows_left, Dummy.BLOWS, "a punch thrown the other way")
	check(absf(angle_difference(p.facing, PI)) < 0.3, "the character did not turn round for it")
	await _unload()


func test_a_kick_reaches_farther_and_counts_for_three() -> void:
	await _load()
	var at := d.global_position
	_stand(at + Vector3(0, 0, 1.9), at + Vector3.UP * 1.3)
	await frames(10)
	check(p.kick(), "it kicks")
	check_eq(p.character.state, "kick", "a kick")
	var waited := 0
	while d.blows_left == Dummy.BLOWS and waited < 60:
		await frames(1)
		waited += 1
	check_eq(d.blows_left, Dummy.BLOWS - 3, "a kick counts for three")
	var foot := _bone(p.character, "foot.R") - d.global_position
	check(
		Vector2(foot.x, foot.z).length() < 0.5 and foot.y > 1.0,
		"the foot is on the dummy when it counts, high (%s from its feet)" % foot.snappedf(0.01)
	)
	var gap := p.global_position.distance_to(d.global_position)
	check(gap > 1.0, "from farther than a punch (%.2f m)" % gap)
	await frames(30)
	check(d.global_position.z < at.z - 0.2, "which sends it back (%.2f m)" % (at.z - d.global_position.z))
	await frames(40)
	check_eq(p.character.state, "guard", "then back to the guard")
	check(_bone(p.character, "foot.R").y < 0.25, "both feet on the ground")
	await _unload()


func test_ducking_brings_the_head_down() -> void:
	await _load()
	_stand(Vector3(-30, 0.05, 30), Vector3(-30, 1.5, 0))
	await frames(10)
	var c := p.character
	var standing := _bone(c, "head").y
	check(p.dodge(), "it ducks")
	check_eq(c.state, "duck", "a duck")
	check(not p.fire(), "no shot while ducking")
	var lowest := standing
	for k in 30:
		await frames(1)
		lowest = minf(lowest, _bone(c, "head").y)
	check(lowest < standing - 0.4, "the head goes down (%.2f m, from %.2f)" % [lowest, standing])
	await frames(20)
	check_eq(c.state, "guard", "and comes back up into the guard")
	# A punch asked for while ducking comes out of it.
	p.dodge()
	await frames(5)
	p.punch()
	await frames(40)
	check(c.state in Character.COMBO, "a punch out of the duck (%s)" % c.state)
	await _unload()


func test_the_dummy_goes_down_and_gets_back_up() -> void:
	await _load()
	var at := d.global_position
	_stand(at + Vector3(0, 0, 1.0), at + Vector3.UP * 1.3)
	await frames(10)
	var presses := 0
	var waited := 0
	while d.state == "up" and waited < 600:
		if waited % 12 == 0:
			p.punch()
			presses += 1
		await frames(1)
		waited += 1
	check_eq(d.state, "down", "enough blows and it goes down")
	check(waited < 150, "jab, cross, jab, cross: about a second and a half (%.1f s)" % (waited / 60.0))
	check_eq(d.collision_layer, 0, "nothing to walk into while it is down")
	await frames(int(Dummy.FALLS * 60.0))
	var hips := _bone(d.character, "hips")
	var head := _bone(d.character, "head") - d.global_position
	check(hips.y < 0.3, "flat on the ground (hips %.2f m up)" % hips.y)
	check(head.z < -0.8 and absf(head.x) < 0.4, "on its back, away from the blow (head at %s)" % head)
	var blows := d.blows_left
	p.punch()
	await frames(30)
	check_eq(d.blows_left, blows, "it takes no more while it is down")
	await frames(int((Dummy.LIES + 2.2) * 60.0))
	check_eq(d.state, "up", "then it gets back up")
	check_eq(d.blows_left, Dummy.BLOWS, "as good as new")
	check(_bone(d.character, "hips").y > 0.8, "on its feet")
	check_eq(d.collision_layer, Structure.LAYER_ACTOR, "and in the way again")
	await _unload()


func test_a_shot_hits_the_dummy() -> void:
	await _load()
	var at := d.global_position
	_stand(at + Vector3(0, 0, 5.0), at + Vector3.UP * 1.2)
	await frames(10)
	var standing := main.structure.held_count
	check(p.aim_point().distance_to(at + Vector3.UP * 1.2) < 0.4, "the crosshair is on it")
	check(p.fire(), "a shot")
	await frames(12)
	check_eq(d.blows_left, Dummy.BLOWS - 2, "counts for two")
	check_eq(d.character.state, "hit_chest", "and throws it back")
	check_eq(get_tree().get_nodes_in_group("projectile").size(), 0, "the ball stopped there")
	check_eq(main.structure.held_count, standing, "the house behind is untouched")
	# The player cannot walk through it.
	_stand(at + Vector3(0, 0, 2.0), at + Vector3.UP * 1.2)
	p.touch_move = Vector2(0, -1)
	var nearest := INF
	for k in 60:
		await frames(1)
		nearest = minf(nearest, p.global_position.distance_to(d.global_position))
	p.touch_move = Vector2.ZERO
	check(nearest > 0.65, "it is in the way of the player (%.2f m between them)" % nearest)
	await _unload()


func test_the_touch_buttons_punch_kick_and_duck() -> void:
	await _load()
	var tc := TouchControls.new()
	tc.player = p
	main.add_child(tc)
	await frames(3)
	# No two buttons under the same thumb.
	var buttons := {
		"fire": [tc.fire_center(), tc.fire_radius()],
		"jump": [tc.jump_center(), tc.jump_radius()],
		"punch": [tc.punch_center(), tc.punch_radius()],
		"kick": [tc.kick_center(), tc.small_radius()],
		"duck": [tc.dodge_center(), tc.small_radius()],
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
	check_eq(p.character.state, "jab", "the red button throws a jab")
	check_eq(get_tree().get_nodes_in_group("projectile").size(), 0, "and no shot")
	tc._on_touch(_touch(0, tc.punch_center(), false))
	await frames(int((Character.GUARD_TIME + 1.2) * 60.0))
	tc._on_touch(_touch(1, tc.kick_center(), true))
	await frames(2)
	check_eq(p.character.state, "kick", "the orange button kicks")
	tc._on_touch(_touch(1, tc.kick_center(), false))
	await frames(int((Character.GUARD_TIME + 1.5) * 60.0))
	tc._on_touch(_touch(2, tc.dodge_center(), true))
	await frames(2)
	check_eq(p.character.state, "duck", "the white button ducks")
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
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await frames(20)
	p = main.player
	d = main.dummy
	p.input_enabled = true


func _unload() -> void:
	main.queue_free()
	await frames(2)
