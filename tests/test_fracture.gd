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
	check(Fracture.piece_count_for(Vector3.ONE * 0.1) >= 3, "minimum pieces")
