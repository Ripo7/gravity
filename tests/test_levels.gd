extends TestCase
## Level content and game flow.

const GAME := preload("res://scenes/game.tscn")


func test_every_level_loads_and_stands() -> void:
	for path in GameState.LEVELS + [GameState.SANDBOX]:
		var world: GameWorld = GAME.instantiate()
		world.level_path = path
		add_child(world)
		await frames(2)
		var lv := world.level
		check(lv != null, "%s loads" % path)
		if lv == null:
			world.queue_free()
			continue
		check(lv.get_node_or_null("PlayerStart") != null, "%s has a PlayerStart" % path)
		check(world.structures.segment_count() > 20, "%s has structures" % path)
		if not lv.is_sandbox():
			check(lv.star_times.x < lv.star_times.y, "%s star times ascend" % path)
			check(lv.target > 0.3 and lv.target <= 1.0, "%s target sensible" % path)
		# Intact level must not fall down on its own.
		await frames(60)
		check_eq(world.structures.alive_count, world.structures.segment_count(), "%s stands" % path)
		check_eq(world.structures.cluster_count(), 0, "%s nothing falling" % path)
		world.queue_free()
		await frames(2)


func test_stars_for_time() -> void:
	var lv := Level.new()
	lv.star_times = Vector2(30, 60)
	check_eq(lv.stars_for(20.0), 3, "fast = 3 stars")
	check_eq(lv.stars_for(30.0), 3, "exactly gold")
	check_eq(lv.stars_for(45.0), 2, "two stars")
	check_eq(lv.stars_for(200.0), 1, "slow but cleared = 1 star")
	lv.free()


func test_progress_unlocks_next_level() -> void:
	GameState.reset_progress()
	var first := GameState.LEVELS[0]
	var second := GameState.LEVELS[1]
	check(GameState.is_unlocked(first), "first level open")
	check(not GameState.is_unlocked(second), "second locked")
	check(GameState.record(first, 1, 80.0), "first clear is a record")
	check(GameState.is_unlocked(second), "a clear unlocks the next")
	check(GameState.record(first, 3, 25.0), "faster is a record")
	check(not GameState.record(first, 2, 40.0), "slower is not a record")
	check_eq(GameState.stars(first), 3, "keeps the best stars")
	check_near(GameState.best_time(first), 25.0, 0.001, "keeps the best time")
	check_eq(GameState.continue_level(), second, "continue goes to the next unfinished level")
	GameState.reset_progress()


func _start(path: String) -> GameWorld:
	var world: GameWorld = GAME.instantiate()
	world.level_path = path
	add_child(world)
	await frames(3)
	(world.get_node("Run") as LevelRun)._begin_play()
	return world


func test_reaching_the_target_clears_the_level() -> void:
	var world := await _start(GameState.LEVELS[0])
	var run := world.get_node("Run") as LevelRun
	await get_tree().create_timer(0.3).timeout
	# Knock down blocks until the goal is met.
	var s := world.structures
	for i in s.segment_count():
		if s.destruction() >= run.level.target:
			break
		s.remove_segment(i)
	await frames(2)
	check(run.cleared, "cleared at the target")
	check(run.elapsed > 0.2, "clock ran (%.2f s)" % run.elapsed)
	var done := [false]
	run.finished.connect(func(_c: bool, _s: int, _t: float) -> void: done[0] = true)
	await get_tree().create_timer(LevelRun.RESULT_DELAY + 0.5).timeout
	check(done[0], "results shown")
	check(GameState.stars(GameState.LEVELS[0]) >= 1, "clear saved")
	get_tree().paused = false
	world.queue_free()
	await frames(2)
	GameState.reset_progress()


func test_dying_fails_the_level() -> void:
	var world := await _start(GameState.LEVELS[0])
	var run := world.get_node("Run") as LevelRun
	world.player.hurt(500.0, world.player.global_position)
	check(world.player.dead, "player dead")
	check_eq(run.state, LevelRun.State.DEAD, "level failed")
	await get_tree().create_timer(LevelRun.RESULT_DELAY + 0.5).timeout
	check_eq(run.state, LevelRun.State.RESULT, "results shown")
	check(not run.cleared, "not cleared")
	check_eq(GameState.stars(GameState.LEVELS[0]), 0, "no stars saved")
	get_tree().paused = false
	world.queue_free()
	await frames(2)
	GameState.reset_progress()
