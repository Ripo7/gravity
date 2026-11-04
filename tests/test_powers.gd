extends TestCase
## The three powers, health and damage.

const GAME := preload("res://scenes/game.tscn")

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


func test_hold_time_picks_the_size() -> void:
	check_eq(PowerDefs.tier_for(0.0), 0, "tap = small")
	check_eq(PowerDefs.tier_for(PowerDefs.TIER_TIMES.x + 0.01), 1, "medium")
	check_eq(PowerDefs.tier_for(PowerDefs.TIER_TIMES.y + 0.01), 2, "large")
	for p in 3:
		var cd: Array = PowerDefs.COOLDOWN[p]
		check(cd[0] < cd[1] and cd[1] < cd[2], "bigger costs a longer cooldown")


func test_cooldown_blocks_recast() -> void:
	await _load()
	var c := world.player.power
	var casts := [0]
	var denied := [0]
	c.cast.connect(func(_p: int, _t: int) -> void: casts[0] += 1)
	c.denied.connect(func(_p: int) -> void: denied[0] += 1)
	c.cast_now(PowerDefs.Power.GRAVITY, 0)
	check_eq(casts[0], 1, "first cast")
	check(not c.is_ready(PowerDefs.Power.GRAVITY), "on cooldown")
	c.begin()
	check(not c.holding, "cannot start while cooling down")
	check_eq(denied[0], 1, "denied feedback")
	check(c.is_ready(PowerDefs.Power.PORTAL), "other powers unaffected")
	await _unload()


func test_singularity_appears_where_aimed_then_goes_off() -> void:
	await _load()
	var at := Vector3(0, 2, 2.6)  # in front of the sandbox's front wall
	var orb := world.cast_gravity(at, 1)
	check(orb.global_position.distance_to(at) < 0.01, "orb sits at the target")
	var standing := world.structures.alive_count
	var went_off := [false]
	world.detonated.connect(func(_a: Vector3, _p: BlastParams) -> void: went_off[0] = true)
	await get_tree().create_timer(PowerDefs.GRAVITY_FUSE[1] * 0.5).timeout
	check(not went_off[0], "waits for its fuse")
	await get_tree().create_timer(PowerDefs.GRAVITY_FUSE[1] * 0.5 + 0.2).timeout
	check(went_off[0], "then explodes")
	await frames(30)
	check(world.structures.alive_count < standing, "and breaks blocks")
	await _unload()


func test_portal_drops_stones_that_smash_blocks() -> void:
	await _load()
	var standing := world.structures.alive_count
	world.cast_portal(Vector3(0, 0, 2), 1)
	await get_tree().create_timer(1.0).timeout
	check(get_tree().get_nodes_in_group("meteor_stone").size() > 0, "stones fell out")
	await get_tree().create_timer(3.0).timeout
	check(
		world.structures.alive_count < standing - 10,
		"stones broke blocks (%d)" % (standing - world.structures.alive_count)
	)
	await _unload()


func test_shield_rises_blocks_and_breaks() -> void:
	await _load()
	var base := Transform3D(Basis(), Vector3(40, 0, 40))
	var shield := world.cast_shield(base, 1)
	await get_tree().create_timer(IceShield.RISE_TIME + 0.1).timeout
	check(shield.global_position.y > 1.0, "rose out of the ground")
	# A heavy piece thrown at it is stopped.
	var i := world.debris.spawn(
		Transform3D(Basis(), Vector3(40, 1.5, 44)), Vector3.ONE * 0.8, Vector3(0, 0, -20)
	)
	await get_tree().create_timer(0.6).timeout
	check(world.debris.position_of(i).z > 40.2, "debris did not pass through")
	check(shield.hp < shield.max_hp, "shield took the hit")
	shield.hit(10000.0)
	await frames(2)
	check(not is_instance_valid(shield), "shattered")
	await _unload()


func test_heavy_debris_hurts_and_regenerates() -> void:
	await _load()
	var p := world.player
	p.global_position = Vector3(40, 0.05, 40)
	await frames(5)
	var hp := p.health
	world.debris.spawn(Transform3D(Basis(), Vector3(40, 1.0, 43)), Vector3.ONE * 0.9, Vector3(0, 0, -18))
	await get_tree().create_timer(0.5).timeout
	check(p.health < hp, "hit by a block (%.0f -> %.0f)" % [hp, p.health])
	var low := p.health
	await get_tree().create_timer(Player.REGEN_DELAY + 1.0).timeout
	check(p.health > low, "health comes back")
	await _unload()


func test_own_blast_hurts_up_close() -> void:
	await _load()
	var p := world.player
	p.global_position = Vector3(40, 0.05, 40)
	await frames(3)
	world.detonate(Vector3(40, 1.0, 41.5), PowerDefs.gravity_params(2))
	await get_tree().create_timer(1.3).timeout
	check(
		p.health < Player.MAX_HEALTH * 0.6 or p.dead, "standing on a big singularity hurts (%.0f)" % p.health
	)
	await _unload()


func test_long_fall_hurts() -> void:
	await _load()
	var p := world.player
	p.global_position = Vector3(40, 22, 40)
	await get_tree().create_timer(2.0).timeout
	check(p.health < Player.MAX_HEALTH, "landing from 22 m hurts (%.0f)" % p.health)
	await _unload()
