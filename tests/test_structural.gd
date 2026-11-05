extends TestCase
## Structural physics: standing, toppling, crushing, falling, impacts.
## Uses the sandbox arena and builds test structures in an empty corner.

const SPOT := Vector3(60, 0, 60)

var world: GameWorld


func _load_world() -> void:
	world = load("res://scenes/game.tscn").instantiate()
	add_child(world)
	world.player.input_enabled = false
	await frames(2)


func _unload() -> void:
	world.queue_free()
	await frames(2)


func _add(kind: Structure.Kind, counts: Vector3i, block: Vector3, mat := Materials.Kind.CONCRETE) -> Vector2i:
	var st := Structure.new()
	st.kind = kind
	st.counts = counts
	st.block = block
	st.material = mat
	st.accent_material = mat
	var first := world.structures.segment_count()
	world.structures.add_structure(Transform3D(Basis(), SPOT), st.build_segments())
	st.free()
	return Vector2i(first, world.structures.segment_count())


func _standing(r: Vector2i) -> int:
	var n := 0
	for i in range(r.x, r.y):
		if world.structures.is_alive(i):
			n += 1
	return n


func test_intact_arena_stays_up() -> void:
	await _load_world()
	var s := world.structures
	await frames(90)
	check_eq(s.alive_count, s.segment_count(), "nothing collapses on its own")
	check_eq(s.cluster_count(), 0, "no falling pieces")
	await _unload()


func test_cutting_one_side_topples_a_tower() -> void:
	await _load_world()
	var r := _add(Structure.Kind.TOWER, Vector3i(3, 14, 1), Vector3(1, 0.8, 0.4))
	var s := world.structures
	var toppled := [false]
	s.cluster_released.connect(func(_at: Vector3, _n: int, t: bool) -> void: toppled[0] = toppled[0] or t)
	# Remove the bottom two layers on the +x half of the footprint.
	for i in range(r.x, r.y):
		var p := s.transform_of(i).origin - SPOT
		if p.y < 1.6 and p.x > -0.1:
			s.break_segment(i)
	s.settle()
	check(toppled[0], "tower tipped over its remaining edge")
	check(_standing(r) < 30, "most of the tower left its base (%d standing)" % _standing(r))
	await _unload()


func test_floating_piece_falls_as_one_and_breaks_on_impact() -> void:
	await _load_world()
	var r := _add(Structure.Kind.WALL, Vector3i(6, 8, 1), Vector3(1, 0.5, 0.5))
	var s := world.structures
	var impacts := [0]
	s.cluster_impact.connect(func(_a: Vector3, _m: float, _v: float, _n: int) -> void: impacts[0] += 1)
	# Lift the wall's base out cleanly so it drops a full row height.
	for i in range(r.x, r.y):
		if s.transform_of(i).origin.y < 1.3:
			s.remove_segment(i)
	s.settle()
	check_eq(s.cluster_count(), 1, "wall above the cut falls as one piece")
	check_eq(_standing(r), 0, "nothing left standing")
	var debris_before := world.debris.active_count
	for k in 120:
		await get_tree().physics_frame
		if s.cluster_count() == 0:
			break
	check_eq(s.cluster_count(), 0, "piece broke up")
	check(impacts[0] >= 1, "impact reported")
	check(world.debris.active_count > debris_before + 30, "blocks became debris")
	await _unload()


func test_removing_columns_crushes_the_rest() -> void:
	await _load_world()
	var r := _add(Structure.Kind.BUILDING, Vector3i(3, 5, 2), Vector3(2.2, 2.4, 0.4))
	var s := world.structures
	var total := r.y - r.x
	await frames(30)
	check_eq(_standing(r), total, "building stands intact")
	# Take out every ground column except two at the -x end.
	var kept := 0
	for i in range(r.x, r.y):
		var p := s.transform_of(i).origin - SPOT
		var is_ground_column := p.y < 1.2 and s.transform_of(i).basis.get_scale().y >= 0.0
		if is_ground_column and absf(world.structures.transform_of(i).origin.y - SPOT.y - 1.075) < 0.05:
			if p.x < -3.0 and kept < 2:
				kept += 1
				continue
			s.break_segment(i)
	await frames(120)
	check(
		_standing(r) < total * 0.5, "overloaded floors collapsed (%d / %d standing)" % [_standing(r), total]
	)
	await _unload()


func test_damage_accumulates_and_weakens() -> void:
	await _load_world()
	var r := _add(Structure.Kind.WALL, Vector3i(2, 1, 1), Vector3(1, 0.5, 0.5))
	var s := world.structures
	var i := r.x
	var hp := s.health_of(i)
	s.apply_impact(s.transform_of(i).origin + Vector3(0, 0, 0.6), 1.0, hp * 0.2)
	check(s.health_of(i) < hp, "health dropped")
	check(s.is_alive(i), "still standing after a light hit")
	await _unload()


func test_destruction_fraction_tracks_score_volume() -> void:
	await _load_world()
	var s := world.structures
	check_near(s.destruction(), 0.0, 1e-6, "starts at zero")
	var broke := 0
	for i in s.segment_count():
		if broke < 40 and s.transform_of(i).origin.y > 2.0:
			s.break_segment(i)
			broke += 1
	check(s.destruction() > 0.0 and s.destruction() < 1.0, "partial (%.3f)" % s.destruction())
	await _unload()
