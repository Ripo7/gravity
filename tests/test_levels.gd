extends TestCase
## The sandbox level and its flow.

const GAME := preload("res://scenes/game.tscn")


func _start() -> GameWorld:
	var world: GameWorld = GAME.instantiate()
	world.level_path = GameState.SANDBOX
	add_child(world)
	await frames(3)
	(world.get_node("Run") as LevelRun)._begin_play()
	return world


func test_sandbox_loads_and_stands() -> void:
	var world := await _start()
	check(world.level != null, "loads")
	check(world.level.get_node_or_null("PlayerStart") != null, "has a PlayerStart")
	check(world.structures.segment_count() > 1200, "rich (%d blocks)" % world.structures.segment_count())
	await frames(90)
	check_eq(world.structures.alive_count, world.structures.segment_count(), "nothing collapses on its own")
	check_eq(world.structures.cluster_count(), 0, "nothing falling")
	world.queue_free()
	await frames(2)


func test_crushed_player_comes_back() -> void:
	var world := await _start()
	var run := world.get_node("Run") as LevelRun
	var p := world.player
	p.global_position = Vector3(50, 0.05, 50)
	p.hurt(500.0, p.global_position)
	check(p.dead, "player down")
	check_eq(run.state, LevelRun.State.DOWN, "K.O.")
	check_eq(run.deaths, 1, "counted")
	await get_tree().create_timer(LevelRun.RESPAWN_DELAY + 0.3).timeout
	check(not p.dead and p.health == Player.MAX_HEALTH, "back on its feet")
	check(p.global_position.distance_to(world.level.player_start().origin) < 1.0, "at the start")
	check_eq(run.state, LevelRun.State.PLAY, "playing again")
	world.queue_free()
	await frames(2)
