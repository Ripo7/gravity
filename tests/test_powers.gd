extends TestCase
## The three powers, health and damage.

const GAME := preload("res://scenes/game.tscn")
const FAR := Vector3(55, 0.05, 55)  # empty corner of the sandbox
const INSIDE := Vector3(42, 0.05, 42)  # empty, well inside the walls

var world: GameWorld


func _load() -> void:
	world = GAME.instantiate()
	world.level_path = GameState.SANDBOX
	add_child(world)
	await frames(3)
	world.player.input_enabled = false
	world.player.power.auto_input = true


func _unload() -> void:
	world.queue_free()
	await frames(2)


func test_press_casts_and_cooldown_blocks_recast() -> void:
	await _load()
	var c := world.player.power
	var casts := [0]
	var denied := [0]
	c.cast.connect(func(_p: int) -> void: casts[0] += 1)
	c.denied.connect(func(_p: int) -> void: denied[0] += 1)
	check(c.cast_now(PowerDefs.Power.VORTEX), "first cast")
	check(not c.is_ready(PowerDefs.Power.VORTEX), "on cooldown")
	check(not c.cast_selected(), "cannot recast while cooling down")
	check_eq(denied[0], 1, "denied feedback")
	check(c.is_ready(PowerDefs.Power.SHIELD), "the shield is unaffected")
	check_eq(casts[0], 1, "one cast")
	await _unload()


func test_vortex_spins_pieces_without_exploding() -> void:
	await _load()
	var at := INSIDE + Vector3(0, 3.5, 0)
	var ids: Array[int] = []
	for k in 30:
		var p := at + Vector3(randf_range(-2.5, 2.5), randf_range(-0.5, 0.5), randf_range(-2.5, 2.5))
		ids.append(world.debris.spawn(Transform3D(Basis(), p), Vector3.ONE * 0.4))
	var v := world.cast_vortex(at)
	await get_tree().create_timer(PowerDefs.VORTEX_SPINUP + 1.5).timeout
	check(v.caught > 18, "pieces caught in the radius (%d)" % v.caught)
	# Pieces move around the core, not away from it.
	var tangential := 0.0
	var radial := 0.0
	for i in ids:
		if not world.debris.is_active(i):
			continue
		var off := world.debris.position_of(i) - at
		var flat := Vector3(off.x, 0, off.z)
		if flat.length() < 0.5:
			continue
		var vel := world.debris.velocity_of(i)
		tangential += absf(vel.dot(Vector3.UP.cross(flat.normalized())))
		radial += absf(vel.dot(flat.normalized()))
	check(tangential > radial * 2.0, "orbiting (tangential %.0f vs radial %.0f)" % [tangential, radial])
	var mean_d := 0.0
	for i in ids:
		mean_d += world.debris.position_of(i).distance_to(at)
	mean_d /= ids.size()
	check(mean_d < PowerDefs.VORTEX_RADIUS, "kept inside the radius (%.1f m)" % mean_d)
	await _unload()


func test_vortex_ends_by_flinging_pieces_outward() -> void:
	await _load()
	var at := INSIDE + Vector3(0, 3.5, 0)
	var ids: Array[int] = []
	for k in 20:
		var p := at + Vector3(randf_range(-2.5, 2.5), randf_range(-0.5, 0.5), randf_range(-2.5, 2.5))
		ids.append(world.debris.spawn(Transform3D(Basis(), p), Vector3.ONE * 0.4))
	var v := world.cast_vortex(at)
	await get_tree().create_timer(PowerDefs.VORTEX_SPINUP + PowerDefs.VORTEX_DURATION - 0.3).timeout
	while v.caught > 0:  # until it bursts
		await get_tree().physics_frame
	await get_tree().physics_frame
	var outward := 0
	var moving := 0
	for i in ids:
		if not world.debris.is_active(i):
			continue
		var off := world.debris.position_of(i) - at
		var vel := world.debris.velocity_of(i)
		moving += 1
		if Vector3(vel.x, 0, vel.z).dot(Vector3(off.x, 0, off.z).normalized()) > 6.0:
			outward += 1
	check(moving > 10 and outward * 4 > moving * 3, "%d of %d fly outward" % [outward, moving])
	# Flung pieces never hurt the one who cast it.
	var flung: PackedInt32Array = v.get("_flung")
	check(not flung.is_empty(), "the burst flung pieces")
	var harmless := true
	for i in flung:
		harmless = harmless and Hazards.motion_of(world, world.debris.rid_of(i), null).is_empty()
	check(harmless, "harmless to you")
	await _unload()


func test_vortex_shreds_the_band_and_hurts() -> void:
	await _load()
	var p := world.player
	# Stand in the band: just outside the radius.
	var at := FAR + Vector3(0, 1.0, -(PowerDefs.VORTEX_RADIUS + 1.5))
	p.global_position = FAR
	await frames(3)
	world.cast_vortex(at)
	await get_tree().create_timer(PowerDefs.VORTEX_SPINUP + 1.0).timeout
	check(p.health < Player.MAX_HEALTH - 15.0, "the band hurts (%.0f)" % p.health)
	check(p.global_position.distance_to(FAR) < 1.0, "but does not pull")
	await _unload()


func test_vortex_breaks_blocks_inside() -> void:
	await _load()
	var standing := world.structures.alive_count
	world.cast_vortex(Vector3(6, 3, 14))  # a building corner on the avenue
	await get_tree().create_timer(PowerDefs.VORTEX_SPINUP + 2.0).timeout
	check(
		world.structures.alive_count < standing - 20,
		"blocks torn loose (%d)" % (standing - world.structures.alive_count)
	)
	await _unload()


func test_shield_button_raises_it_at_once() -> void:
	await _load()
	var c := world.player.power
	c.select(PowerDefs.Power.SHIELD)
	await frames(2)
	check_eq(get_tree().get_nodes_in_group("ice_shield").size(), 1, "shield up")
	check_eq(c.selected, PowerDefs.Power.VORTEX, "the cast button still opens black holes")
	check(c.is_ready(PowerDefs.Power.VORTEX), "and the black hole is not on cooldown")
	await _unload()


func test_shield_is_a_tall_curved_shell_that_blocks() -> void:
	await _load()
	var p := world.player
	p.global_position = FAR
	p.rotation.y = 0.0  # looking toward -z
	await frames(3)
	world.player.power.cast_now(PowerDefs.Power.SHIELD)
	await get_tree().create_timer(IceShield.RISE_TIME + 0.15).timeout
	var shields := get_tree().get_nodes_in_group("ice_shield")
	check_eq(shields.size(), 1, "one shield")
	var shield := shields[0] as IceShield
	check(shield.global_position.distance_to(p.global_position) < 0.5, "centred on the player")
	# Rays from the player hit ice ahead, to the sides and overhead-front,
	# but not behind: a curved shell, open at the back.
	var space := world.get_world_3d().direct_space_state
	var head := p.global_position + Vector3(0, 1.5, 0)
	var hits := {}
	for dir_name: String in ["ahead", "left", "right", "up_front", "behind"]:
		var d: Vector3 = {
			"ahead": Vector3(0, 0, -1),
			"left": Vector3(-1, 0, 0),
			"right": Vector3(1, 0, 0),
			"up_front": Vector3(0, 1.4, -1).normalized(),
			"behind": Vector3(0, 0, 1),
		}[dir_name]
		var q := PhysicsRayQueryParameters3D.create(head, head + d * 8.0, DebrisSystem.LAYER_STRUCTURES)
		q.exclude = [p.get_rid()]
		var hit := space.intersect_ray(q)
		hits[dir_name] = not hit.is_empty() and hit["collider"] == shield
	check(hits["ahead"] and hits["left"] and hits["right"], "wraps around the front (%s)" % hits)
	check(hits["up_front"], "curves up over the front")
	check(not hits["behind"], "open at the back")
	# Taller than you.
	var q := PhysicsRayQueryParameters3D.create(
		FAR + Vector3(0, 4.2, 0), FAR + Vector3(0, 4.2, -6.0), DebrisSystem.LAYER_STRUCTURES
	)
	check(not space.intersect_ray(q).is_empty(), "reaches over 4 m")
	var i := world.debris.spawn(
		Transform3D(Basis(), FAR + Vector3(0, 1.5, -8)), Vector3.ONE * 0.8, Vector3(0, 0, 20)
	)
	await get_tree().create_timer(0.6).timeout
	check(world.debris.position_of(i).z < FAR.z - 2.0, "debris did not pass through")
	check(shield.hp < shield.max_hp, "shield took the hit")
	check_eq(p.health, Player.MAX_HEALTH, "you are safe behind it")
	shield.hit(100000.0)
	await frames(2)
	check(not is_instance_valid(shield), "shattered")
	await get_tree().create_timer(1.5).timeout
	check_eq(p.health, Player.MAX_HEALTH, "its shards do not hurt you")
	await _unload()


func test_a_flying_brick_nearly_kills_you() -> void:
	await _load()
	var p := world.player
	p.global_position = FAR
	await frames(5)
	# A 0.25 m3 brick (~65 kg) at 9 m/s.
	world.debris.spawn(
		Transform3D(Basis(), FAR + Vector3(0, 1.1, 1.6)), Vector3(1.0, 0.5, 0.5), Vector3(0, 0, -9)
	)
	await get_tree().create_timer(0.5).timeout
	check(p.health < 50.0, "you are a chip (%.0f left)" % p.health)
	var low := p.health
	if not p.dead:
		await get_tree().create_timer(Player.REGEN_DELAY + 1.0).timeout
		check(p.health > low, "health comes back")
	await _unload()


func test_long_fall_hurts() -> void:
	await _load()
	var p := world.player
	p.global_position = FAR + Vector3(0, 22, 0)
	await get_tree().create_timer(2.0).timeout
	check(p.health < Player.MAX_HEALTH, "landing from 22 m hurts (%.0f)" % p.health)
	await _unload()


func test_running_over_rubble_never_hurts() -> void:
	await _load()
	var p := world.player
	# A carpet of loose bricks and slabs, settled on the ground.
	for x in 6:
		for z in 10:
			var at := FAR + Vector3(-2.5 + x, 0.3, -2.0 - z * 1.1)
			world.debris.spawn(Transform3D(Basis(), at), Vector3(0.9, 0.45, 0.5))
	await get_tree().create_timer(1.5).timeout
	p.global_position = FAR + Vector3(0, 0.1, 1.0)
	p.rotation.y = 0.0
	p.input_enabled = true
	p.walk_speed = p.sprint_speed  # sprinting into and over the pile
	p.touch_move = Vector2(0, -1)
	for k in 150:
		if k % 40 == 20:
			p.touch_jump = true
		await get_tree().physics_frame
		p.touch_jump = false
	p.touch_move = Vector2.ZERO
	check(p.global_position.z < FAR.z - 8.0, "crossed the rubble (z %.1f)" % p.global_position.z)
	check_eq(p.health, Player.MAX_HEALTH, "no damage from walking on debris")
	await _unload()
