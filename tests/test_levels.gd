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
		var t := lv.star_thresholds
		check(t.x < t.y and t.y < t.z and t.z <= 1.0, "%s thresholds ascend" % path)
		# Intact level must not fall down on its own.
		await frames(60)
		check_eq(world.structures.alive_count, world.structures.segment_count(), "%s stands" % path)
		check_eq(world.structures.cluster_count(), 0, "%s nothing falling" % path)
		world.queue_free()
		await frames(2)


func test_stars_for_destruction() -> void:
	var lv := Level.new()
	lv.star_thresholds = Vector3(0.4, 0.65, 0.85)
	check_eq(lv.stars_for(0.2), 0, "below one star")
	check_eq(lv.stars_for(0.4), 1, "exactly one star")
	check_eq(lv.stars_for(0.7), 2, "two stars")
	check_eq(lv.stars_for(1.0), 3, "three stars")
	lv.free()


func test_progress_unlocks_next_level() -> void:
	GameState.reset_progress()
	var first := GameState.LEVELS[0]
	var second := GameState.LEVELS[1]
	check(GameState.is_unlocked(first), "first level open")
	check(not GameState.is_unlocked(second), "second locked")
	check(GameState.record(first, 0, 200, 0.2), "first record is a best")
	check(not GameState.is_unlocked(second), "no star, still locked")
	GameState.record(first, 2, 700, 0.7)
	check(GameState.is_unlocked(second), "a star unlocks the next")
	check(not GameState.record(first, 1, 500, 0.5), "worse score is not a best")
	check_eq(GameState.stars(first), 2, "keeps the best stars")
	check_eq(GameState.continue_level(), second, "continue goes to the next unfinished level")
	GameState.reset_progress()


func test_running_out_of_charges_ends_the_level() -> void:
	var world: GameWorld = GAME.instantiate()
	world.level_path = GameState.LEVELS[0]
	add_child(world)
	await frames(3)
	var run := world.get_node("Run") as LevelRun
	run._begin_play()
	var charges := run.charges_left
	check(charges > 0, "level has charges")
	for k in charges:
		world.player.power.thrown.emit(BlastParams.from_charge(0.5))
	check_eq(run.charges_left, 0, "all charges used")
	check(not world.player.power.enabled, "power disabled")
	var done := [false]
	run.finished.connect(func(_s: int, _sc: int) -> void: done[0] = true)
	for k in 60:
		await get_tree().create_timer(0.25).timeout
		if done[0]:
			break
	check(done[0], "results shown once things settle")
	check_eq(run.state, LevelRun.State.RESULT, "in result state")
	get_tree().paused = false
	world.queue_free()
	await frames(2)
	GameState.reset_progress()
