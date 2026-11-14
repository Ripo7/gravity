extends TestCase
## The character seen from behind: the camera, where it turns, what its legs
## and its arm show.

var main: Main
var p: Player


func test_the_camera_sits_behind_the_left_shoulder_and_comes_in_at_walls() -> void:
	await _load()
	# In the open, looking at the house.
	var eye := p.camera.global_position - p.global_position
	check(absf(eye.z - Player.BACK * cos(p.pitch)) < 0.3, "behind (%.1f m)" % eye.z)
	check(absf(eye.x + Player.SHOULDER) < 0.05, "to the left (%.2f m)" % -eye.x)
	check(eye.y > 1.5 and eye.y < 2.6, "above the shoulders (%.1f m)" % eye.y)
	# The view goes where it is told, although the camera is off to the
	# side: here, on a pillar of the porch.
	var target := main.house_at * Vector3(1.5, 1.4, 6.9)
	p.look_at_point(target)
	var along := -p.camera.global_basis.z
	var miss := (target - p.camera.global_position).cross(along).length()
	check(miss < 0.02, "look_at_point puts the middle of the view on its target (%.3f m off)" % miss)
	# Back to the front wall of the house (where it is solid), 0.9 m from it,
	# looking away: the camera must stay on this side of the wall.
	_stand(main.house_at * Vector3(-2.5, 0.05, 4.4), main.house_at * Vector3(-2.5, 1.5, 20))
	await frames(2)
	var room := (main.house_at.affine_inverse() * p.camera.global_position).z - House.Z1
	check(room > Player.ROOM * 0.9, "it stays in front of the wall behind you (%.2f m from it)" % room)
	check(
		p.camera.global_position.distance_to(p.global_position + Vector3.UP * Player.HEAD) < 1.2,
		"close to you"
	)
	check(p.character.visible, "the character is still drawn")
	# Right up against the wall, the camera has no room: it would only see
	# the character's back, which is not drawn then.
	_stand(main.house_at * Vector3(-2.5, 0.05, 4.0), main.house_at * Vector3(-2.5, 1.5, 20))
	await frames(2)
	check(not p.character.visible, "against the wall, the character is not drawn")
	# Away from the wall again, it eases back out.
	_stand(main.house_at * Vector3(2.5, 0.05, 12), main.house_at * Vector3(2.5, 1.5, 20))
	await frames(60)
	eye = p.camera.global_position - p.global_position
	check(Vector2(eye.x, eye.z).length() > Player.BACK * 0.9, "and comes back out in the open")
	check(p.character.visible, "where the character is drawn again")
	await _unload()


func test_the_character_turns_to_where_it_goes_not_the_camera() -> void:
	await _load()
	var yaw := p.yaw
	p.touch_move = Vector2(1, 0)  # to the right of the view
	await frames(40)
	check(
		absf(angle_difference(p.facing, yaw - PI * 0.5)) < 0.1,
		"it faces right (%.0f deg)" % rad_to_deg(p.facing)
	)
	check_eq(p.yaw, yaw, "the camera has not turned")
	check(p.global_position.x > 2.0, "and it went that way (%.1f m)" % p.global_position.x)
	# Its front is where it goes: the chest is ahead of the hips.
	var sk := p.character.skeleton
	var chest := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("DEF-spine.003")).origin
	var toe := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("DEF-toe.L")).origin
	var heel := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("DEF-foot.L")).origin
	check((toe - heel).x > 0.0 and chest.x > p.global_position.x - 0.2, "toes pointing where it runs")
	p.touch_move = Vector2(0, 1)  # towards the camera
	await frames(40)
	check(absf(angle_difference(p.facing, yaw + PI)) < 0.1, "then it faces the camera")
	p.touch_move = Vector2.ZERO
	await _unload()


func test_the_legs_keep_pace_with_the_ground() -> void:
	await _load()
	# From a slow walk to a sprint: the foot that is on the ground must stay
	# where it is, or nearly (it slides less than a sixth of the pace).
	for trial: Array in [[0.1, false], [0.2, false], [0.5, false], [1.0, false], [1.0, true]]:
		_stand(Vector3(-30, 0.05, 30), Vector3(0, 1.5, 30))
		p.touch_move = Vector2(0, -trial[0])
		p.touch_sprint = trial[1]
		await frames(90)
		var pace := Vector2(p.velocity.x, p.velocity.z).length()
		var slide := await _slide(120)
		check(slide < maxf(pace / 6.0, 0.15), "at %.1f m/s the planted foot slides %.2f m/s" % [pace, slide])
	p.touch_move = Vector2.ZERO
	p.touch_sprint = false
	await frames(40)
	check(Vector2(p.velocity.x, p.velocity.z).length() < 0.05, "it stops")
	check((await _slide(30)) < 0.02, "and stands still")
	await _unload()


func test_jumping_falling_and_landing_show() -> void:
	await _load()
	var c := p.character
	check_eq(c.state, "ground", "on the ground to begin with")
	p.touch_jump = true
	await frames(3)
	check_eq(c.state, "jump", "a jump leaves at once")
	var top := 0.0
	for k in 80:
		await frames(1)
		top = maxf(top, p.global_position.y)
		if p.is_on_floor():
			break
	check(top > 1.5 and top < 2.2, "it jumps %.1f m high" % top)
	await frames(2)
	check_eq(c.state, "land", "landing on the spot shows")
	await frames(60)
	check_eq(c.state, "ground", "then it stands again")
	# Running, a jump does not end in a crouch.
	p.touch_move = Vector2(0, -1)
	await frames(40)
	p.touch_jump = true
	await frames(10)
	check(not p.is_on_floor() and c.state == "jump", "a running jump")
	for k in 100:
		await frames(1)
		if p.is_on_floor():
			break
	await frames(2)
	check_eq(c.state, "ground", "runs on when it lands")
	p.touch_move = Vector2.ZERO
	await _unload()


## The speed (m/s) at which a foot moves over the ground while it is planted,
## over `steps` steps: the worse of the two feet.
func _slide(steps: int) -> float:
	var sk := p.character.skeleton
	var worst := 0.0
	var rows := {"L": [], "R": []}
	for k in steps:
		await frames(1)
		for side: String in rows:
			var foot := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("DEF-foot." + side)).origin
			var toe := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("DEF-toe." + side)).origin
			rows[side].append([foot, toe])
	for side: String in rows:
		var seen: Array = rows[side]
		var low := Vector2(INF, INF)
		for r: Array in seen:
			low = Vector2(minf(low.x, r[0].y), minf(low.y, r[1].y))
		var slid := 0.0
		var planted := 0
		for k in seen.size() - 1:
			if (
				seen[k][0].y < low.x + 0.03
				and seen[k][1].y < low.y + 0.025
				and seen[k + 1][0].y < low.x + 0.03
			):
				var d: Vector3 = seen[k + 1][0] - seen[k][0]
				slid += Vector2(d.x, d.z).length() * 60.0
				planted += 1
		worst = maxf(worst, slid / maxi(planted, 1))
	return worst


func _stand(at: Vector3, target: Vector3) -> void:
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.look_at_point(target)
	p.facing = p.yaw


func _load() -> void:
	seed(5)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
	main.fight = false  # the other brute only stands there
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await frames(20)
	p = main.player
	p.input_enabled = true


func _unload() -> void:
	main.queue_free()
	await frames(2)
