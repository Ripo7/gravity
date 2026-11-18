extends TestCase
## The bench itself: a bare ground, one brute, no sun shadow, a round shadow
## that stays on the ground.

var main: Main


func test_the_bench_is_a_bare_ground_with_one_brute() -> void:
	await _load()
	var p := main.player
	check(p.is_on_floor(), "the brute stands on the ground")
	check_near(p.global_position.y, 0.0, 0.05, "which is at 0")
	# It is alone, and there is nothing to run into but the ground.
	var brutes := 0
	var bodies := 0
	var suns := 0
	for child in main.get_children():
		if child is CharacterBody3D:
			brutes += 1
		elif child is PhysicsBody3D:
			bodies += 1
		if child is DirectionalLight3D:
			suns += 1
			check(not (child as DirectionalLight3D).shadow_enabled, "the sun casts no shadow")
	check_eq(brutes, 1, "one brute")
	check_eq(bodies, 1, "one body besides it: the ground")
	check_eq(suns, 1, "one sun")
	# Far from the middle the ground is still there.
	p.global_position = Vector3(150, 0.05, -150)
	await frames(30)
	check(p.is_on_floor(), "the ground goes on far from the middle")
	await _unload()


func test_the_round_shadow_stays_on_the_ground() -> void:
	await _load()
	var p := main.player
	var blob: BlobShadow
	for child in main.get_children():
		if child is BlobShadow:
			blob = child
	check(blob != null, "the brute has a round shadow")
	if blob == null:
		await _unload()
		return
	await frames(3)
	var under := blob.global_position - p.global_position
	check(Vector2(under.x, under.z).length() < 0.05 and blob.visible, "at its feet")
	p.touch_move = Vector2(0, -1)
	await frames(30)
	p.touch_jump = true
	var top := 0.0
	var highest := 0.0
	for k in 50:
		await frames(1)
		top = maxf(top, p.global_position.y)
		highest = maxf(highest, blob.global_position.y)
	p.touch_move = Vector2.ZERO
	check(top > 1.2, "the brute jumps (%.1f m)" % top)
	check(highest < 0.1, "its shadow stays on the ground (%.2f m)" % highest)
	under = blob.global_position - p.global_position
	check(
		Vector2(under.x, under.z).length() < 0.2,
		"and follows it (%.2f m off)" % Vector2(under.x, under.z).length()
	)
	await _unload()


func _load() -> void:
	seed(5)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await frames(20)


func _unload() -> void:
	main.queue_free()
	await frames(2)
