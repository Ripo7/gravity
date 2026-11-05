extends TestCase
## The Blender shard library (tools/make_shards.py) and how blocks use it.

const SPOT := Vector3(42, 0, 42)  # empty corner of the sandbox, inside the walls

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


func test_library_covers_concrete_wood_and_metal() -> void:
	check(ShardLibrary.ensure(), "the library loads")
	for kind: int in [Materials.Kind.CONCRETE, Materials.Kind.WOOD, Materials.Kind.METAL]:
		check(ShardLibrary.has(kind), "%s has patterns" % ShardLibrary.KINDS[kind])
		check_eq(ShardLibrary.pattern(kind, 2, 0).size(), 2, "a two-piece break exists")
	check(not ShardLibrary.has(Materials.Kind.GLASS), "glass bursts into chips instead")
	var verts := ShardLibrary.mesh.surface_get_array_len(0)
	check_eq(ShardLibrary.shapes.get_width(), verts, "one texel per mesh vertex")


func test_every_pattern_fills_its_block() -> void:
	ShardLibrary.ensure()
	var rows := ShardLibrary.shapes.get_height()
	for kind: int in ShardLibrary.KINDS:
		for count in range(2, 11):
			var total := 0.0
			for shard: Dictionary in ShardLibrary.pattern(kind, count, 0):
				total += shard["volume"]
				check(int(shard["id"]) < rows, "shard has a shape row")
				check((shard["hull"] as PackedVector3Array).size() >= 4, "and a hull")
				var c: Vector3 = shard["center"]
				check(absf(c.x) < 0.5 and absf(c.y) < 0.5 and absf(c.z) < 0.5, "inside the block")
			# Rough fracture faces only cut inward, so a little goes missing.
			check(total > 0.8 and total < 1.01, "pieces add up to the block (%.2f)" % total)


func test_wood_splinters_run_along_the_grain() -> void:
	ShardLibrary.ensure()
	var along := 0.0
	var across := 0.0
	for shard: Dictionary in ShardLibrary.pattern(Materials.Kind.WOOD, 6, 0):
		var size: Vector3 = shard["size"]
		along += size.x
		across += (size.y + size.z) * 0.5
	check(along > across * 1.5, "splinters are long along x (%.2f vs %.2f)" % [along, across])


func test_concrete_block_breaks_into_shards() -> void:
	await _load_world()
	var d := world.debris
	var size := Vector3(1.2, 0.9, 0.9)
	var xf := Transform3D(Basis(), SPOT + Vector3(0, 2, 0))
	var out := d.shatter_box(xf, size, Materials.Kind.CONCRETE, xf.origin, 0.0, Vector3.ZERO, 0, 1, 0.5, 0)
	check(out.size() >= 2, "several pieces (%d)" % out.size())
	var total := 0.0
	for i in out:
		check(d.shard_of(i) >= 0, "each one a library shard")
		total += d.volume_of(i)
	var block := size.x * size.y * size.z
	check(total > block * 0.7 and total <= block * 1.01, "same matter as the block (%.2f)" % total)
	await _unload()


func test_wood_beam_splits_along_its_length() -> void:
	await _load_world()
	var d := world.debris
	var xf := Transform3D(Basis(), SPOT + Vector3(0, 2, 0))
	var size := Vector3(0.35, 0.35, 2.4)
	var out := d.shatter_box(xf, size, Materials.Kind.WOOD, xf.origin, 0.0, Vector3.ZERO, 0, 1, 0.5, 1)
	var long := 0
	for i in out:
		long += 1 if d.size_of(i).max_axis_index() == Vector3.AXIS_Z else 0
	check(out.size() >= 2 and long * 2 > out.size(), "%d of %d run along the beam" % [long, out.size()])
	await _unload()


func test_hulls_for_big_shards_boxes_for_small() -> void:
	await _load_world()
	var d := world.debris
	var xf := Transform3D(Basis(), SPOT + Vector3(0, 2, 0))
	var size := Vector3(1.2, 0.9, 0.9)
	d.hull_min_volume = 0.0
	var hulls := d.shatter_box(xf, size, Materials.Kind.CONCRETE, xf.origin, 0, Vector3.ZERO, 0, 1, 0.5, 0)
	var all_hull := true
	for i in hulls:
		all_hull = all_hull and d.uses_hull(i)
	check(all_hull, "hulls when allowed")
	d.clear()
	d.hull_min_volume = INF
	var boxes := d.shatter_box(xf, size, Materials.Kind.CONCRETE, xf.origin, 0, Vector3.ZERO, 0, 1, 0.5, 0)
	var any_hull := false
	for i in boxes:
		any_hull = any_hull or d.uses_hull(i)
	check(not any_hull and not boxes.is_empty(), "boxes when the budget is tight")
	# Box stand-ins keep the shard's volume, so piles do not grow or shrink.
	var total := 0.0
	for i in boxes:
		var s := d.size_of(i)
		total += d.volume_of(i)
		check(s.x > 0.0 and s.y > 0.0 and s.z > 0.0, "a real box")
	check(total > 0.7 * size.x * size.y * size.z, "same matter")
	await _unload()
