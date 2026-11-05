extends TestCase
## Destruction effects and the optimisations behind them.

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


func test_resting_rubble_freezes_and_thaws() -> void:
	await _load_world()
	var d := world.debris
	var bottom := d.spawn(Transform3D(Basis(), SPOT + Vector3(0, 0.5, 0)), Vector3(1.2, 1.0, 1.2))
	var top := d.spawn(Transform3D(Basis(), SPOT + Vector3(0, 1.3, 0)), Vector3(0.6, 0.5, 0.6))
	await get_tree().create_timer(2.5).timeout
	check(d.is_frozen(bottom) and d.is_frozen(top), "a settled pile turns static")
	check_eq(d.awake_count, 0, "nothing left awake")
	var y := d.position_of(top).y
	d.despawn(bottom)
	await get_tree().create_timer(1.0).timeout
	check(
		d.position_of(top).y < y - 0.6, "what rested on it falls (%.2f -> %.2f)" % [y, d.position_of(top).y]
	)
	await _unload()


func test_powers_move_frozen_rubble() -> void:
	await _load_world()
	var d := world.debris
	var i := d.spawn(Transform3D(Basis(), SPOT + Vector3(0, 0.25, 0)), Vector3(0.5, 0.5, 0.5))
	await get_tree().create_timer(2.0).timeout
	check(d.is_frozen(i), "frozen")
	world.cast_vortex(SPOT + Vector3(1.5, 1.5, 0))
	await get_tree().create_timer(PowerDefs.VORTEX_SPINUP + 0.6).timeout
	check(not d.is_frozen(i), "the black hole thaws it")
	check(d.velocity_of(i).length() > 2.0, "and spins it")
	await _unload()


func test_breaks_spray_chips_that_land() -> void:
	await _load_world()
	var chips := world.dust.chip_system
	world.dust.chips_box(SPOT + Vector3(0, 3, 0), Vector3(1, 0.5, 0.5), Materials.Kind.CONCRETE, 30)
	check_eq(chips.active, 30, "chips sprayed")
	check_eq(world.debris.active_count, 0, "with no physics bodies")
	await get_tree().create_timer(2.0).timeout
	var low := 0
	for i in chips.capacity:
		if chips._state[i] == 3 and chips._pos[i].y < 0.2:
			low += 1
	check(low > 20, "most landed on the ground (%d)" % low)
	await get_tree().create_timer(7.5).timeout
	check_eq(chips.active, 0, "and faded away")
	await _unload()


func test_tall_building_creaks_then_pancakes_floor_by_floor() -> void:
	await _load_world()
	var st := Structure.new()
	st.kind = Structure.Kind.APARTMENT
	st.counts = Vector3i(2, 7, 2)
	st.block = Vector3(4.0, 3.2, 0.45)
	var s := world.structures
	var first := s.segment_count()
	s.add_structure(Transform3D(Basis(), SPOT + Vector3(0, 0, -12)), st.build_segments())
	st.free()
	var events := {"fail": 0, "crush": 0}
	s.about_to_fail.connect(func(_a: Vector3, _n: int) -> void: events["fail"] += 1)
	s.floor_crushed.connect(func(_a: Vector3, _n: int, _sp: float) -> void: events["crush"] += 1)
	await frames(5)
	# Blow out the two lowest storeys: the five above drop 6 m.
	for i in range(first, s.segment_count()):
		if s.is_alive(i) and s.transform_of(i).origin.y < 6.3:
			s.break_segment(i)
	world.debris.clear()
	await frames(3)
	check_eq(events["fail"], 1, "it creaks and holds a moment first")
	var standing := 0
	for i in range(first, s.segment_count()):
		if s.is_alive(i):
			standing += 1
	check(standing > 50, "still up during the creak (%d)" % standing)
	await get_tree().create_timer(4.0).timeout
	check(events["crush"] >= 2, "floors crush one after another (%d)" % events["crush"])
	await _unload()


func test_roof_water_tower_falls_with_its_building() -> void:
	await _load_world()
	var s := world.structures
	var roof := Vector3(12, 0, -14)  # building with a water tower on top
	var tower_before := 0
	for i in s.segment_count():
		var p := s.transform_of(i).origin
		if s.is_alive(i) and p.y > 19.0 and absf(p.x - roof.x) < 2.0 and absf(p.z - roof.z) < 2.0:
			tower_before += 1
	check(tower_before > 10, "water tower on the roof (%d)" % tower_before)
	for i in s.segment_count():
		var p := s.transform_of(i).origin
		if s.is_alive(i) and p.y < 6.3 and absf(p.x - roof.x) < 6.5 and absf(p.z - roof.z) < 6.5:
			s.break_segment(i)
	await get_tree().create_timer(3.0).timeout
	var left := 0
	for i in s.segment_count():
		var p := s.transform_of(i).origin
		if s.is_alive(i) and p.y > 19.0 and absf(p.x - roof.x) < 2.0 and absf(p.z - roof.z) < 2.0:
			left += 1
	check_eq(left, 0, "it comes down with the building")
	await _unload()


func test_a_resting_block_breaking_up_does_not_fling_pieces() -> void:
	await _load_world()
	var s := world.structures
	var d := world.debris
	var st := Structure.new()
	st.kind = Structure.Kind.BRIDGE
	st.counts = Vector3i(5, 8, 1)
	st.block = Vector3(2.9, 1.56, 2.6)
	var first := s.segment_count()
	s.add_structure(Transform3D(Basis(), SPOT + Vector3(-4, 0, -14)), st.build_segments())
	st.free()
	var comp := PackedInt32Array()
	for i in range(first, s.segment_count()):
		comp.append(i)
	s._release(comp, false)
	check_eq(s.cluster_count(), 1, "released as one block")
	await get_tree().create_timer(0.4).timeout
	if s.cluster_count() > 0:
		s._dissolve(s._clusters[s._clusters.size() - 1], Vector3.ZERO, 0.0)
	var vmax := 0.0
	for k in 10:
		await get_tree().physics_frame
		for i in d.capacity:
			if d.is_active(i):
				vmax = maxf(vmax, d.velocity_of(i).length())
	check(vmax < 10.0, "the pile slumps, nothing flies (max %.1f m/s)" % vmax)
	await _unload()


func test_glass_bursts_into_shards_without_bodies() -> void:
	await _load_world()
	var s := world.structures
	var pane := -1
	for i in s.segment_count():
		if s.is_alive(i) and s.kind_of(i) == Materials.Kind.GLASS:
			pane = i
			break
	check(pane >= 0, "the city has glazed windows")
	var bodies := world.debris.active_count
	var chips := world.dust.chip_system.active
	s.break_segment(pane)
	await frames(2)
	check(not s.is_alive(pane), "the pane broke")
	check_eq(world.debris.active_count, bodies, "no physics bodies for glass")
	check(world.dust.chip_system.active > chips + 8, "a spray of shards")
	await _unload()


func test_broken_concrete_leaves_rebar_and_cracks_start_at_the_hit() -> void:
	await _load_world()
	var s := world.structures
	# A ground column of a building: its neighbours are concrete slabs.
	var col := -1
	for i in s.segment_count():
		var p := s.transform_of(i).origin
		var sz := s._size[i]
		var concrete := s.kind_of(i) == Materials.Kind.CONCRETE
		if (
			s.is_alive(i)
			and concrete
			and absf(p.y - 4.675) < 0.05
			and absf(sz.y - 2.95) < 0.01
			and sz.x < 0.5
		):
			col = i
			break
	check(col >= 0, "found a first-floor column")
	var at := s.transform_of(col).origin + Vector3(0, 1.0, 0)
	s._damage(col, 0.1, at)
	check(s._hit[col] != Vector3.ZERO, "the hit point is kept for the cracks")
	check(s._hit[col].y > 1.2, "near the top, where it was hit")
	s.break_segment(col)
	await frames(2)
	var rebar := s.rebar
	check(rebar != null and rebar.count() > 0, "steel rods stick out where it broke")
	await _unload()
