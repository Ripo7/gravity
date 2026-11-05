extends TestCase
## The city's life and colour: painted buildings, birds that take off.

var world: GameWorld


func _load_world() -> void:
	world = load("res://scenes/game.tscn").instantiate()
	add_child(world)
	world.player.input_enabled = false
	world.player.global_position = Vector3(-50, 0.1, 50)
	await frames(2)


func _unload() -> void:
	world.queue_free()
	await frames(2)


func test_paint_rides_in_the_seed() -> void:
	var s := Materials.paint_seed(3, 0.42)
	check_eq(Materials.paint_of(s), 3, "paint comes back out")
	check_near(fposmod(s, 1.0), 0.42, 0.001, "the random part is kept")
	var c := Materials.custom(Materials.Kind.WOOD, 0.5, s)
	check_eq(int(floor(c)), 3 * Materials.KIND_SLOTS + Materials.Kind.WOOD, "packed for the shader")
	check_near(fposmod(c, 1.0), 0.45, 0.001, "damage still in the fraction")


func test_buildings_are_painted_and_their_debris_too() -> void:
	await _load_world()
	var s := world.structures
	var paints := {}
	var painted := -1
	for i in s.segment_count():
		var p := Materials.paint_of(s.get("_seed")[i])
		paints[p] = true
		if p > 0 and painted < 0 and s.kind_of(i) == Materials.Kind.CONCRETE:
			painted = i
	check(paints.size() >= 5, "several colours across the district (%d)" % paints.size())
	var paint := Materials.paint_of(s.get("_seed")[painted])
	s.break_segment(painted)
	await frames(2)
	var same := 0
	for i in world.debris.capacity:
		if world.debris.is_active(i) and Materials.paint_of(world.debris.get("_seed")[i]) == paint:
			same += 1
	check(same >= 1, "the pieces keep the building's colour")
	await _unload()


func test_pigeons_take_off_when_something_breaks_nearby() -> void:
	await _load_world()
	var b := world.birds
	check(b.count >= 20, "there are birds (%d)" % b.count)
	var i := 0
	var at: Vector3 = b.get("_pos")[i]
	check_eq(b.get("_state")[i], BirdSystem.State.PERCHED, "perched at first")
	b.scare(at + Vector3(1, -2, 0), 10.0)
	check_eq(b.get("_state")[i], BirdSystem.State.FLEEING, "takes off")
	await get_tree().create_timer(1.0).timeout
	var now: Vector3 = b.get("_pos")[i]
	check(now.y > at.y + 1.0 and now.distance_to(at) > 4.0, "up and away (%.1f m)" % now.distance_to(at))
	await _unload()


func test_pigeons_leave_a_roof_that_falls() -> void:
	await _load_world()
	var b := world.birds
	var block: int = b.get("_perch_block")[0]
	world.structures.break_segment(block)
	await frames(3)
	check(b.get("_state")[0] != BirdSystem.State.PERCHED, "no perching on air")
	await _unload()
