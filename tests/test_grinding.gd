extends TestCase
## The cascade: shards split again along their own cracks (sub-shards cut in
## Blender), loose blocks crack open, and the black hole grinds pieces into
## a cloud of grains.

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


func test_every_concrete_and_wood_shard_has_sub_shards_that_tile_it() -> void:
	ShardLibrary.ensure()
	for kind in [Materials.Kind.CONCRETE, Materials.Kind.WOOD]:
		for count in [2, 3, 4, 5]:
			for shard: Dictionary in ShardLibrary.pattern(kind, count, 0):
				var kids := ShardLibrary.children_of(shard["id"])
				check(kids.size() >= 3, "a shard cracks into several pieces (%d)" % kids.size())
				var total := 0.0
				var box := AABB(
					(shard["center"] as Vector3) - (shard["size"] as Vector3) * 0.5, shard["size"] as Vector3
				)
				for kid: Dictionary in kids:
					total += kid["volume"]
					check(box.grow(0.01).has_point(kid["center"]), "each piece lies inside its shard")
				check(absf(total - float(shard["volume"])) < 0.002, "and together they are the shard")


func test_a_shard_splits_along_its_own_cracks() -> void:
	await _load_world()
	var d := world.debris
	var size := Vector3(1.6, 1.2, 1.2)
	var xf := Transform3D(Basis(), SPOT + Vector3(0, 3, 0))
	var out := d.shatter_box(xf, size, Materials.Kind.CONCRETE, xf.origin, 0.0, Vector3.ZERO, 0, 1, 0.5, 0)
	var big := -1
	for i in out:
		if big < 0 or d.volume_of(i) > d.volume_of(big):
			big = i
	var bounds := AABB(d.position_of(big) - d.size_of(big) * 0.5, d.size_of(big)).grow(0.05)
	var vol := d.volume_of(big)
	var kids := ShardLibrary.children_of(d.shard_of(big))
	var pieces := d.fracture(big)
	check(not d.is_active(big) or pieces.has(big), "the shard is gone")
	check(
		pieces.size() >= 2 and pieces.size() <= kids.size(),
		"it split into its sub-shards (%d)" % pieces.size()
	)
	var total := 0.0
	for i in pieces:
		check(d.shard_of(i) >= 0, "each piece is a library shard")
		check(bounds.has_point(d.position_of(i)), "each piece where the shard was")
		total += d.volume_of(i)
	check(total <= vol * 1.01 and total > vol * 0.6, "the same matter (%.3f of %.3f)" % [total, vol])
	await _unload()


func test_a_big_block_coming_loose_cracks_open() -> void:
	await _load_world()
	var s := world.structures
	var big := -1
	for i in s.segment_count():
		var sz := s.size_of(i)
		if s.is_alive(i) and s.kind_of(i) == Materials.Kind.CONCRETE and sz.x * sz.y * sz.z > 1.0:
			big = i
			break
	check(big >= 0, "the palace has big blocks")
	var before := world.debris.active_count
	s._dislodge(big, Vector3(0, 0, 2))
	check(world.debris.active_count - before >= 2, "it came away in several pieces, not whole")
	await _unload()


func test_the_black_hole_grinds_pieces_into_a_cloud_of_grains() -> void:
	await _load_world()
	var d := world.debris
	var at := SPOT + Vector3(0, 3.5, 0)
	for k in 12:
		var p := at + Vector3(randf_range(-2.5, 2.5), randf_range(-0.5, 0.5), randf_range(-2.5, 2.5))
		var xf := Transform3D(Basis(), p)
		d.shatter_box(xf, Vector3(0.9, 0.7, 0.7), Materials.Kind.CONCRETE, p, 0.0, Vector3.ZERO, 0, 1, 1.3, k)
	var start := _matter_near(at)
	var v := world.cast_vortex(at)
	await get_tree().create_timer(PowerDefs.VORTEX_SPINUP + PowerDefs.VORTEX_DURATION - 0.3).timeout
	var cloud := v.cloud()
	check(cloud != null and cloud.used > 200, "a cloud of grains (%d)" % (cloud.used if cloud else 0))
	var left := _matter_near(at)
	check(left < start * 0.4, "most of it was ground down (%.2f of %.2f m3 left)" % [left, start])
	await get_tree().create_timer(0.3 + GrainCloud.FADE + 0.4).timeout
	check(not is_instance_valid(cloud), "the cloud burst and faded away")
	check(world.debris.chips.active > 20, "some of it landed as gravel")
	await _unload()


## Volume of the pieces (bodies) within the black hole's radius of `at`.
func _matter_near(at: Vector3) -> float:
	var d := world.debris
	var total := 0.0
	for i in d.slot_end():
		if d.is_active(i) and d.position_of(i).distance_to(at) < PowerDefs.VORTEX_RADIUS:
			total += d.volume_of(i)
	return total
