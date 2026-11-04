extends TestCase
## The three powers, health and damage.

const GAME := preload("res://scenes/game.tscn")
const FAR := Vector3(55, 0.05, 55)  # empty corner of the sandbox

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
	check(c.cast_now(PowerDefs.Power.PORTAL), "first cast")
	check(not c.is_ready(PowerDefs.Power.PORTAL), "on cooldown")
	check(not c.cast_selected(), "cannot recast while cooling down")
	check_eq(denied[0], 1, "denied feedback")
	check(c.is_ready(PowerDefs.Power.VORTEX), "other powers unaffected")
	check_eq(casts[0], 1, "one cast")
	await _unload()


func test_vortex_spins_pieces_without_exploding() -> void:
	await _load()
	var at := FAR + Vector3(0, 3, -15)
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


func test_portal_drops_one_destructible_rock() -> void:
	await _load()
	var standing := world.structures.alive_count
	world.cast_portal(Vector3(12, 0, 14))  # a building on the avenue
	await get_tree().create_timer(1.0).timeout
	var stones := get_tree().get_nodes_in_group("meteor_stone")
	check_eq(stones.size(), 1, "one big rock")
	await get_tree().create_timer(3.0).timeout
	check(
		world.structures.alive_count < standing - 10,
		"it broke blocks (%d)" % (standing - world.structures.alive_count)
	)
	# It may already have burst on its hard landings; otherwise break it.
	var left := get_tree().get_nodes_in_group("meteor_stone")
	if not left.is_empty():
		var pieces := world.debris.active_count
		(left[0] as MeteorStone).damage(10000.0)
		await frames(3)
		check(world.debris.active_count > pieces, "into chunks")
	check_eq(get_tree().get_nodes_in_group("meteor_stone").size(), 0, "the rock breaks apart")
	await _unload()


func test_shield_slot_raises_it_without_selecting() -> void:
	await _load()
	var c := world.player.power
	c.select(PowerDefs.Power.PORTAL)
	c.select(PowerDefs.Power.SHIELD)
	await frames(2)
	check_eq(get_tree().get_nodes_in_group("ice_shield").size(), 1, "shield up")
	check_eq(c.selected, PowerDefs.Power.PORTAL, "portal still selected")
	await _unload()


func test_shield_rises_in_front_by_itself_and_blocks() -> void:
	await _load()
	var p := world.player
	p.global_position = FAR
	p.rotation.y = 0.0  # looking toward -z
	await frames(3)
	world.player.power.cast_now(PowerDefs.Power.SHIELD)
	await get_tree().create_timer(IceShield.RISE_TIME + 0.1).timeout
	var shields := get_tree().get_nodes_in_group("ice_shield")
	check_eq(shields.size(), 1, "one shield")
	var shield := shields[0] as IceShield
	var ahead := shield.global_position - p.global_position
	check(ahead.z < -2.0 and absf(ahead.x) < 0.5, "it stands in front of the player (%s)" % ahead)
	check(shield.global_position.y > 1.0, "rose out of the ground")
	var i := world.debris.spawn(
		Transform3D(Basis(), FAR + Vector3(0, 1.5, -8)), Vector3.ONE * 0.8, Vector3(0, 0, 20)
	)
	await get_tree().create_timer(0.6).timeout
	check(world.debris.position_of(i).z < shield.global_position.z, "debris did not pass through")
	check(shield.hp < shield.max_hp, "shield took the hit")
	shield.hit(100000.0)
	await frames(2)
	check(not is_instance_valid(shield), "shattered")
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
