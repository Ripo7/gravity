extends TestCase
## What falls does not stay a rigid lump of blocks: it is cut in ragged
## chunks and comes apart chunk by chunk into rubble, and a black hole drags
## it in. Test pieces are built in an empty corner of the square.

const GAME := preload("res://scenes/game.tscn")
const SPOT := Vector3(60, 0, 60)

var world: GameWorld


func _load() -> void:
	world = GAME.instantiate()
	world.level_path = GameState.SANDBOX
	add_child(world)
	await frames(3)
	world.player.input_enabled = false
	world.player.global_position = SPOT + Vector3(0, 0.05, 25)


func _unload() -> void:
	world.queue_free()
	await frames(2)


## A wall of `cols` x `rows` stones of 1 x 0.5 x 0.5 m at `at`, its bottom
## row lifted out so the rest falls as one piece. Returns its blocks.
func _drop_wall(at: Vector3, cols: int, rows: int) -> Vector2i:
	var s := world.structures
	var st := Structure.new()
	st.kind = Structure.Kind.WALL
	st.counts = Vector3i(cols, rows, 1)
	st.block = Vector3(1, 0.5, 0.5)
	var first := s.segment_count()
	s.add_structure(Transform3D(Basis(), at), st.build_segments())
	st.free()
	for i in range(first, s.segment_count()):
		if s.transform_of(i).origin.y < at.y + 0.3:
			s.remove_segment(i)
	s.settle()
	return Vector2i(first, s.segment_count())


func test_a_falling_piece_is_cut_in_ragged_chunks() -> void:
	await _load()
	var s := world.structures
	_drop_wall(SPOT, 12, 8)
	check_eq(s.cluster_count(), 1, "the wall falls as one piece")
	var c := s.falls.clusters[0]
	var cells := {}  # chunk -> {(column, row): true}
	for k in c.members.size():
		var p := s.transform_of(c.members[k]).origin - SPOT
		var spot := Vector2i(roundi(p.x * 2.0), roundi(p.y * 2.0))  # half-metre grid
		if not cells.has(c.chunk[k]):
			cells[c.chunk[k]] = {}
		cells[c.chunk[k]][spot] = true
	check(cells.size() >= 3, "in several chunks (%d)" % cells.size())
	# A chunk cut along straight lines fills its bounding rectangle.
	var ragged := 0
	for q: int in cells:
		var lo := Vector2i(1 << 20, 1 << 20)
		var hi := -lo
		for spot: Vector2i in cells[q]:
			lo = Vector2i(mini(lo.x, spot.x), mini(lo.y, spot.y))
			hi = Vector2i(maxi(hi.x, spot.x), maxi(hi.y, spot.y))
		var box := ((hi.x - lo.x) / 2 + 1) * (hi.y - lo.y + 1)
		if (cells[q] as Dictionary).size() < box:
			ragged += 1
	check(ragged >= 2, "along ragged lines (%d of %d chunks)" % [ragged, cells.size()])
	await _unload()


func test_a_falling_piece_comes_apart_bit_by_bit_into_rubble() -> void:
	await _load()
	var s := world.structures
	var d := world.debris
	# Lifted 6 m, it lands hard.
	_drop_wall(SPOT + Vector3(0, 6, 0), 12, 8)
	var landed := [-1]
	s.cluster_impact.connect(
		func(_at: Vector3, _m: float, _v: float, _n: int) -> void:
			if landed[0] < 0:
				landed[0] = Engine.get_physics_frames()
	)
	var falling := PackedInt32Array()  # blocks still in falling pieces, per step
	for k in 200:
		await get_tree().physics_frame
		var n := 0
		for c in s.falls.clusters:
			n += c.members.size()
		falling.append(n)
	check(landed[0] >= 0, "it landed")
	var start: int = falling.size() - (Engine.get_physics_frames() - int(landed[0]))
	var right_after := falling[clampi(start + 1, 0, falling.size() - 1)]
	check(right_after > 0, "it did not all come apart in the step it landed")
	check_eq(falling[falling.size() - 1], 0, "but it is all rubble now")
	var shards := 0
	for i in d.capacity:
		if d.is_active(i) and d.shard_of(i) >= 0:
			shards += 1
	check(
		shards * 10 >= d.active_count * 7, "rubble, not blocks (%d shards of %d)" % [shards, d.active_count]
	)
	await _unload()


func test_a_black_hole_drags_what_falls_near_it() -> void:
	await _load()
	var s := world.structures
	var hole := SPOT + Vector3(0, 4, 0)
	world.cast_vortex(hole)
	await get_tree().create_timer(PowerDefs.VORTEX_SPINUP + 0.1).timeout
	# A wall falling 7.5 m from the core: outside the radius, inside the reach.
	_drop_wall(SPOT + Vector3(0, 4, 7.5), 6, 6)
	check_eq(s.cluster_count(), 1, "it falls as one piece")
	var c := s.falls.clusters[0]
	var flat := func(p: Vector3) -> float: return Vector2(p.x - hole.x, p.z - hole.z).length()
	var before: float = flat.call(c.transform().origin)
	await get_tree().create_timer(0.5).timeout
	var after: float = flat.call(c.transform().origin) if s.falls.clusters.has(c) else 0.0
	check(after < before - 1.0, "it was dragged toward the hole (%.1f m -> %.1f m)" % [before, after])
	await _unload()
