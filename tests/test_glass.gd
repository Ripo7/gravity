extends TestCase
## Glass, on the bench: a pane stops the brute while it stands; it bursts
## whole at the first blow, wherever that lands, into glitter that are not
## bodies and are gone a moment later; the panes beside it take nothing.

var main: Main
var p: Player
var s: Structure


func test_walking_running_and_jumping_break_no_glass() -> void:
	await _load()
	_face(Main.GLASS_AT + Vector3(0, 0.05, -4), Main.GLASS_AT + Vector3.UP)
	p.touch_move = Vector2(0, -1)
	p.touch_sprint = true
	await frames(120)
	check(p.global_position.z < Main.GLASS_AT.z, "the pane stops the brute (z %.2f)" % p.global_position.z)
	check(p.global_position.z > Main.GLASS_AT.z - 1.0, "which ran right up to it")
	for k in 3:
		p.touch_jump = true
		await frames(50)
	p.touch_move = Vector2.ZERO
	p.touch_sprint = false
	for q in main.panes:
		check_eq(s.harm[q], 0.0, "pane %d took nothing" % q)
		check_eq(s.state[q], Structure.STANDS, "and stands")
	check_eq(s.glitter.bursts, 0, "no glitter")
	await _unload()


func test_a_pane_bursts_whole_at_the_first_blow_wherever_it_lands() -> void:
	await _load()
	var q := main.panes[1]
	# A light blow, low in a corner of the pane.
	var corner := Main.GLASS_AT + Vector3(Main.PANE.x * 0.4, 0.2, -Main.PANE.z * 0.5)
	check(s.strike(corner, Vector3.BACK, 2, s.body_of(q)), "a blow lands low in a corner of a pane")
	check_eq(s.state[q], Structure.BROKEN, "the pane is gone, all of it")
	check_eq(s.standing_count, s.pieces - 1, "one piece fewer stands")
	check_eq(s.rubble.live, 0, "in no loose body: glitter is not pieces")
	check_eq(s.glitter.bursts, 1, "its glitter falls")
	for other: int in [main.panes[0], main.panes[2]]:
		check_eq(s.harm[other], 0.0, "the pane beside it took nothing")
		check_eq(s.state[other], Structure.STANDS, "and stands")
	# Nothing is in the way where it stood.
	var ray := PhysicsRayQueryParameters3D.create(
		Main.GLASS_AT + Vector3(0, 1, -1), Main.GLASS_AT + Vector3(0, 1, 1), Layers.STRUCTURE | Layers.RUBBLE
	)
	await frames(2)
	check(
		p.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(),
		"nothing is in the way where it stood"
	)
	# The glitter lies a moment, then is gone.
	var fell := sqrt(2.0 * Main.PANE.y / Rubble.GRAVITY)
	await frames(roundi(fell * 60.0) + 30)
	check_eq(s.glitter.bursts, 1, "once it has all landed, the glitter lies there a moment")
	await frames(roundi((Glitter.LIES + Glitter.FADES) * 60.0) + 30)
	check_eq(s.glitter.bursts, 0, "then it is gone")
	check_eq(s.glitter.get_child_count(), 0, "and takes nothing any more")
	# A blow where the pane was lands on nothing.
	check(
		not s.strike(Main.GLASS_AT + Vector3(0, 1.2, 0), Vector3.BACK, 2),
		"a blow where it stood meets nothing"
	)
	check_eq(s.standing_count, s.pieces - 1, "and the panes beside still stand")
	await _unload()


func test_the_lightest_blow_bursts_a_pane_and_no_blow_does_not() -> void:
	await _load()
	var q := main.panes[0]
	s.hit(q, 0.0, Vector3.BACK, s.place[q].origin)
	check_eq(s.state[q], Structure.STANDS, "nothing: it stands")
	s.hit(q, 0.1, Vector3.ZERO, s.place[q].origin + Vector3.UP)
	check_eq(s.state[q], Structure.BROKEN, "the lightest blow, from above: it bursts")
	check_eq(s.rubble.live, 0, "in no loose body")
	await _unload()


func test_the_brute_bursts_a_pane_with_one_blow_and_walks_through() -> void:
	await _load()
	_face(Main.GLASS_AT + Vector3(0, 0.05, -1.0), Main.GLASS_AT + Vector3.UP)
	await frames(5)
	var thrown := [0]
	p.blow.connect(func(_at: Vector3, _way: Vector3, _power: int, _on: RID) -> void: thrown[0] += 1)
	p.punch()
	for k in 60:
		await frames(1)
		if thrown[0] >= 1:
			break
	check_eq(thrown[0], 1, "one blow")
	check_eq(s.state[main.panes[1]], Structure.BROKEN, "the pane in front of it is gone")
	check_eq(s.standing_count, s.pieces - 1, "and only that one")
	await frames(60)
	p.touch_move = Vector2(0, -1)
	await frames(90)
	p.touch_move = Vector2.ZERO
	check(
		p.global_position.z > Main.GLASS_AT.z + 1.0,
		"the brute walks through where it stood (z %.2f)" % p.global_position.z
	)
	await _unload()


## Puts the brute at `at`, facing `target`.
func _face(at: Vector3, target: Vector3) -> void:
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.facing = atan2(at.x - target.x, at.z - target.z)
	p.look(Vector2(angle_difference(p.yaw, p.facing), 0.0))


func _load() -> void:
	seed(5)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await frames(20)
	p = main.player
	s = main.structure


func _unload() -> void:
	main.queue_free()
	await frames(2)
