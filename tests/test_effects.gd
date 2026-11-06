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
	# Gravel stays as the rubble field's gravel; it fades when it gets old.
	await get_tree().create_timer(3.0).timeout
	check_eq(chips.active, 30, "it stays on the ground for a while")
	for i in chips.capacity:
		if chips._state[i] != 0:
			chips._life[i] = 0.5
	await get_tree().create_timer(1.5).timeout
	check_eq(chips.active, 0, "then fades away")
	await _unload()


func test_tall_building_creaks_then_pancakes() -> void:
	seed(4242)  # which crushed blocks shatter is random: same draw every run
	await _load_world()
	var st := Structure.new()
	st.kind = Structure.Kind.BUILDING
	st.counts = Vector3i(3, 7, 3)
	st.block = Vector3(3.5, 3.2, 0.45)
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
	await get_tree().create_timer(5.5).timeout
	# The lowest storey of the falling block is crushed where it lands (a
	# second storey goes too when it hits hard enough again).
	check(events["crush"] >= 1, "it lands crushing a storey (%d)" % events["crush"])
	await _unload()


## A structure standing on another (a water tower on a roof) is tied to the
## blocks it stands on: it falls when they go, even one at a time.
func test_a_structure_on_a_roof_falls_with_its_support() -> void:
	await _load_world()
	var s := world.structures
	var house := Structure.new()
	house.kind = Structure.Kind.BUILDING
	house.counts = Vector3i(1, 2, 1)
	house.block = Vector3(4.0, 3.0, 0.4)
	var base := SPOT + Vector3(-6, 0, -6)
	var first := s.segment_count()
	s.add_structure(Transform3D(Basis(), base), house.build_segments())
	house.free()
	var roof_top := 0.0
	for i in range(first, s.segment_count()):
		roof_top = maxf(roof_top, s.transform_of(i).origin.y + s.size_of(i).y * 0.5)
	var tank := Structure.new()
	tank.kind = Structure.Kind.WALL
	tank.counts = Vector3i(2, 3, 1)
	tank.block = Vector3(0.8, 0.5, 0.8)
	var top_first := s.segment_count()
	s.add_structure(Transform3D(Basis(), base + Vector3(0, roof_top, 0)), tank.build_segments())
	var top_last := s.segment_count()  # walls it hits may crack into new blocks after this
	tank.free()
	s.link_anchors()
	await frames(5)
	check_eq(s.cluster_count(), 0, "both stand")
	# Break the roof slab under it, one block at a time (no blast).
	for i in range(first, top_first):
		var p := s.transform_of(i).origin
		if s.is_alive(i) and p.y > roof_top - 0.5:
			s.break_segment(i)
	await get_tree().create_timer(2.0).timeout
	var left := 0
	for i in range(top_first, top_last):
		if s.is_alive(i):
			left += 1
	check_eq(left, 0, "it comes down with the roof")
	await _unload()


func test_a_resting_block_breaking_up_does_not_fling_pieces() -> void:
	await _load_world()
	var s := world.structures
	var d := world.debris
	var st := Structure.new()
	st.kind = Structure.Kind.BUILDING
	st.counts = Vector3i(2, 2, 1)
	st.block = Vector3(3.0, 2.6, 0.4)
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
		s.falls.dissolve(s.falls.clusters[s.falls.clusters.size() - 1], Vector3.ZERO, 0.0)
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
	# A ground-floor pier of the palace: its neighbours are stone too.
	var col := -1
	for i in s.segment_count():
		var p := s.transform_of(i).origin
		var sz := s._size[i]
		var concrete := s.kind_of(i) == Materials.Kind.CONCRETE
		if (
			s.is_alive(i)
			and concrete
			and p.y > 1.5
			and p.y < 4.0
			and sz.y > 2.0
			and minf(sz.x, sz.z) < 0.7
			and maxf(sz.x, sz.z) < 2.5
		):
			col = i
			break
	check(col >= 0, "found a ground-floor pier")
	var at := s.transform_of(col).origin + Vector3(0, 1.0, 0)
	s._damage(col, 0.1, at)
	check(s._hit[col] != Vector3.ZERO, "the hit point is kept for the cracks")
	check(s._hit[col].y > 1.2, "near the top, where it was hit")
	s.break_segment(col)
	await frames(2)
	var rebar := s.rebar
	check(rebar != null and rebar.count() > 0, "steel rods stick out where it broke")
	await _unload()


func test_a_big_piece_breaks_on_a_hard_landing() -> void:
	await _load_world()
	var d := world.debris
	var broke := [0]
	d.piece_broke.connect(func(_a: Vector3, _s: Vector3, _k: int, _v: float) -> void: broke[0] += 1)
	d.spawn(Transform3D(Basis(), SPOT + Vector3(0, 8, 0)), Vector3(1.2, 0.5, 0.6), Vector3(0, -6, 0))
	await get_tree().create_timer(1.2).timeout
	check(broke[0] >= 1, "it broke up instead of bouncing whole")
	check(d.active_count > 1, "into pieces (%d)" % d.active_count)
	await _unload()


func test_falling_pieces_push_frozen_rubble() -> void:
	await _load_world()
	var d := world.debris
	var pile: Array[int] = []
	for k in 6:
		pile.append(
			d.spawn(Transform3D(Basis(), SPOT + Vector3(k * 0.45 - 1.1, 0.2, 0)), Vector3(0.4, 0.4, 0.4))
		)
	await get_tree().create_timer(2.0).timeout
	var frozen := 0
	for i in pile:
		frozen += 1 if d.is_frozen(i) else 0
	check(frozen >= 5, "the pile froze (%d)" % frozen)
	# A slab slides in fast along the ground into the pile.
	d.spawn(Transform3D(Basis(), SPOT + Vector3(-5, 0.35, 0)), Vector3(1.0, 0.3, 0.6), Vector3(12, 0, 0))
	await get_tree().create_timer(0.6).timeout
	var moved := 0
	for i in pile:
		if not d.is_frozen(i):
			moved += 1
	check(moved >= 2, "it ploughs into the pile instead of stopping dead (%d freed)" % moved)
	await _unload()


func test_dust_settles_on_the_square() -> void:
	await _load_world()
	var dust := world.dust
	check(dust.floor_mat != null, "the dust knows the floor")
	var at := SPOT + Vector3(-40, 0, -40)  # inside the map, away from the palace
	dust.roll(at, 3.0, 1.0)
	check(dust.floor_mat.get_shader_parameter("ground_dust") is ImageTexture, "the floor reads a dust map")
	var size := DustSystem.GROUND_SIZE
	var texel := int((at.x + DustSystem.GROUND_HALF) / (DustSystem.GROUND_HALF * 2.0) * size)
	texel += int((at.z + DustSystem.GROUND_HALF) / (DustSystem.GROUND_HALF * 2.0) * size) * size
	check(
		dust._dusty[texel] > 50, "where the dust rolled out, the square turned pale (%d)" % dust._dusty[texel]
	)
	check(dust._dusty[2 * size + 2] == 0, "and nowhere else")
	await _unload()


func test_a_crushed_storey_blows_dust_out_sideways() -> void:
	await _load_world()
	var dust := world.dust
	var before := dust.active
	world.structures.floor_crushed.emit(SPOT + Vector3(0, 4, 0), 60, 9.0)
	check(dust.active >= before + 6, "jets of dust all round (%d new)" % (dust.active - before))
	await frames(10)
	# They fly out sideways, away from the storey.
	var out := 0
	for i in dust.capacity:
		if dust._life[i] > 0.0 and Vector2(dust._vel[i].x, dust._vel[i].z).length() > 2.0:
			out += 1
	check(out >= 4, "flying out (%d)" % out)
	await _unload()


func test_the_sky_has_its_clouds_and_time_never_slows() -> void:
	await _load_world()
	var env := (world.get_node("WorldEnvironment") as WorldEnvironment).environment
	var sky := env.sky.sky_material as ShaderMaterial
	check(sky != null and sky.get_shader_parameter("clouds") is Texture2D, "clouds baked in Blender")
	# A big piece of building landing: shake and dust, never slow motion.
	world.structures.cluster_impact.emit(SPOT, 50000.0, 14.0, 120)
	await frames(5)
	check_eq(Engine.time_scale, 1.0, "the game keeps its pace")
	await _unload()
