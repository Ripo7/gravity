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
	check(d.position_of(top).y < y - 0.6, "what rested on it falls (%.2f -> %.2f)" % [y, d.position_of(top).y])
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
