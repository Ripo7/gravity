extends TestCase
## The palace's colours: every block carries its finish, and so do its pieces.

var world: GameWorld


func _load_world(level := "") -> void:
	world = load("res://scenes/game.tscn").instantiate()
	if level != "":
		world.level_path = level
	add_child(world)
	world.player.input_enabled = false
	world.player.global_position = Vector3(-50, 0.1, 50)
	await frames(2)


func _unload() -> void:
	world.queue_free()
	await frames(2)


func test_finish_rides_in_the_seed() -> void:
	var s := Materials.finish_seed(Materials.Finish.TRAVERTINE, 0.42)
	check_eq(Materials.finish_of(s), Materials.Finish.TRAVERTINE, "finish comes back out")
	check_near(fposmod(s, 1.0), 0.42, 0.001, "the random part is kept")
	var c := Materials.custom(Materials.Kind.WOOD, 0.5, s)
	check_eq(
		int(floor(c)), Materials.Finish.TRAVERTINE * Materials.KIND_SLOTS + Materials.Kind.WOOD, "packed"
	)
	check_near(fposmod(c, 1.0), 0.45, 0.001, "damage still in the fraction")


func test_the_palace_keeps_its_finishes_when_broken() -> void:
	await _load_world()
	var s := world.structures
	var finishes := {}
	var stone := -1
	for i in s.segment_count():
		var f := Materials.finish_of(s.get("_seed")[i])
		finishes[f] = true
		if f == Materials.Finish.TRAVERTINE and stone < 0 and s.kind_of(i) == Materials.Kind.CONCRETE:
			if s.size_of(i).x * s.size_of(i).y * s.size_of(i).z > 0.5:
				stone = i
	check(
		finishes.size() >= 8, "stone, plaster, travertine, marble, tiles... (%d finishes)" % finishes.size()
	)
	s.break_segment(stone)
	await frames(2)
	var same := 0
	for i in world.debris.capacity:
		var f := Materials.finish_of(world.debris.get("_seed")[i])
		if world.debris.is_active(i) and f == Materials.Finish.TRAVERTINE:
			same += 1
	check(same >= 1, "the pieces keep their finish")
	await _unload()


func test_the_finishes_baked_in_blender_are_loaded() -> void:
	for path in ["res://materials/block.tres", "res://materials/debris.tres"]:
		var m := load(path) as ShaderMaterial
		check(m.get_shader_parameter("use_textures"), "%s uses the baked finishes" % path)
		for name in ["finish_albedo", "finish_detail"]:
			# (Headless runs have no texture data: check the resource itself.)
			var t: Variant = m.get_shader_parameter(name)
			check(t is CompressedTexture2DArray, "%s: %s is the baked texture array" % [path, name])
