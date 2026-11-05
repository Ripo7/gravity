extends TestCase


func test_pieces_tile_the_block() -> void:
	var size := Vector3(1.0, 0.8, 0.4)
	var pieces := Fracture.pattern(size, 8, 0)
	check_eq(pieces.size(), 8, "piece count")
	var volume := 0.0
	var bounds := AABB(-size * 0.5, size).grow(0.0001)
	for p in pieces:
		volume += p.get_volume()
		check(bounds.encloses(p), "piece inside block")
	check_near(volume, size.x * size.y * size.z, 0.0001, "volume preserved")


func test_pieces_do_not_overlap() -> void:
	var pieces := Fracture.pattern(Vector3(2, 1, 1), 10, 3)
	for a in pieces.size():
		for b in range(a + 1, pieces.size()):
			var inter := pieces[a].intersection(pieces[b])
			check(inter.get_volume() < 1e-6, "pieces %d and %d overlap" % [a, b])


func test_pattern_is_cached_and_deterministic() -> void:
	var a := Fracture.pattern(Vector3(1, 1, 1), 6, 1)
	var b := Fracture.pattern(Vector3(1, 1, 1), 6, 1)
	check(is_same(a, b), "same array returned from cache")
	Fracture.clear_cache()
	var c := Fracture.pattern(Vector3(1, 1, 1), 6, 1)
	check_eq(c, a, "same layout after cache clear")


func test_tiny_blocks_stop_splitting() -> void:
	var pieces := Fracture.pattern(Vector3(0.2, 0.2, 0.2), 10, 0)
	for p in pieces:
		check(p.size[p.size.min_axis_index()] >= Fracture.MIN_EDGE * 0.5, "no slivers")


func test_piece_count_grows_with_volume() -> void:
	check(
		Fracture.piece_count_for(Vector3.ONE) > Fracture.piece_count_for(Vector3.ONE * 0.5),
		"bigger breaks more"
	)
	check(Fracture.piece_count_for(Vector3.ONE * 0.1) >= 2, "minimum pieces")


func test_wood_splits_along_the_grain() -> void:
	var size := Vector3(2.0, 0.3, 0.25)
	var grain := Fracture.grain_for(Materials.Kind.WOOD, size)
	check_eq(grain, 0, "grain follows the long edge")
	for p in Fracture.pattern(size, 6, 0, grain):
		check_near(p.size.x, 2.0, 1e-5, "every splinter runs the full length")


func test_metal_breaks_into_fewer_pieces() -> void:
	var size := Vector3(1, 1, 1)
	var metal := Fracture.piece_count_for(size, Materials.prop(Materials.Kind.METAL, "pieces"))
	var concrete := Fracture.piece_count_for(size, Materials.prop(Materials.Kind.CONCRETE, "pieces"))
	check(metal < concrete / 2, "metal %d vs concrete %d" % [metal, concrete])
	check(
		Materials.prop(Materials.Kind.METAL, "strength") > Materials.prop(Materials.Kind.WOOD, "strength"),
		"metal is stronger than wood"
	)
