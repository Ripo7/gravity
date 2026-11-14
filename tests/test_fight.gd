extends TestCase
## Fighting: the punches, what they reach, and the dummy that takes them.

var main: Main
var p: Player
var d: Dummy


func test_a_jab_then_a_cross_then_the_guard() -> void:
	await _load()
	# In the open, no one near.
	_stand(Vector3(-30, 0.05, 30), Vector3(-30, 1.5, 0))
	await frames(10)
	var c := p.character
	var from := p.global_position
	check(p.punch(), "it punches")
	check_eq(c.state, "jab", "a jab first")
	var left := 0.0
	for k in 14:
		await frames(1)
		left = maxf(left, _ahead("hand.L"))
	check(left > 0.6, "the left fist goes out (%.2f m ahead)" % left)
	check(not p.fire(), "no shot in the middle of a punch")
	p.punch()  # asked for during the jab: the other hand follows
	var right := 0.0
	var seen := {}
	for k in 90:
		await frames(1)
		seen[c.state] = true
		if c.state == "cross":
			right = maxf(right, _ahead("hand.R"))
		elif c.state == "guard":
			break
	check(seen.has("cross") and right > 0.5, "then the right (%.2f m ahead)" % right)
	check_eq(c.state, "guard", "then the fists stay up")
	await frames(12)
	check(_bone(c, "hand.L").y > 1.25 and _bone(c, "hand.R").y > 1.2, "both of them")
	await frames(int((Character.GUARD_TIME + 0.6) * 60.0))
	check_eq(c.state, "ground", "for a while")
	check(_bone(c, "hand.L").y < 1.1, "then they come down (%.2f m up)" % _bone(c, "hand.L").y)
	check(p.global_position.distance_to(from) < 0.05, "it punched where it stood")
	# Walking away drops the guard at once.
	p.punch()
	await frames(50)
	check_eq(c.state, "guard", "fists up again after a jab")
	p.touch_move = Vector2(0, -1)
	await frames(3)
	check_eq(c.state, "ground", "walking away drops them")
	p.touch_move = Vector2.ZERO
	# No punch in the air.
	p.touch_jump = true
	await frames(6)
	check(not p.punch(), "no punch in the air")
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
	check(gap < Player.PUNCH_FROM + 0.1 and gap > 0.69, "it stepped in to arm's length (%.2f m)" % gap)
	# The fist is where the blow is: on the dummy, about its neck.
	var fist := _bone(p.character, "hand.L") - d.global_position
	check(
		Vector2(fist.x, fist.z).length() < 0.4 and fist.y > 1.2 and fist.y < 1.6,
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
	_stand(at + Vector3(0, 0, Player.PUNCH_SEEK + 0.5), at + Vector3.UP * 1.3)
	await frames(10)
	var from := p.global_position
	p.punch()
	await frames(40)
	check_eq(d.blows_left, Dummy.BLOWS, "out of reach")
	check(p.global_position.distance_to(from) < 0.05, "and it did not go for it")
	# Close, but its back to it.
	_stand(at + Vector3(0, 0, 1.0), at + Vector3(0, 1.3, 20))
	await frames(40)
	p.punch()
	await frames(40)
	check_eq(d.blows_left, Dummy.BLOWS, "a punch thrown the other way")
	check(absf(angle_difference(p.facing, PI)) < 0.3, "the character did not turn round for it")
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


func test_the_touch_button_punches() -> void:
	await _load()
	var tc := TouchControls.new()
	tc.player = p
	main.add_child(tc)
	await frames(3)
	var apart := (
		tc.punch_center().distance_to(tc.fire_center()) - tc.punch_radius() * 1.3 - tc.fire_radius() * 1.3
	)
	check(apart > 0.0, "punch and fire are apart (%.0f px)" % apart)
	var rebuild := Hud.rebuild_rect(tc.size).grow(10)
	check(not rebuild.has_point(tc.punch_center()), "and clear of the rebuild button")
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = tc.punch_center()
	e.pressed = true
	tc._on_touch(e)
	await frames(2)
	check_eq(p.character.state, "jab", "the red button throws a jab")
	check_eq(get_tree().get_nodes_in_group("projectile").size(), 0, "and no shot")
	await _unload()


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
