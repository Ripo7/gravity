extends TestCase
## What breaks is never lost: what the debris pool and the gravel chips let
## go of piles up in rubble heaps, as much of it as broke, at the slope
## rubble stands at; pieces and the player stand on the heaps. Cut the
## tower's foot and nearly all of what came down is still there to see.

const GAME := preload("res://scenes/game.tscn")
const SPOT := Vector3(40, 0, 40)

var world: GameWorld


func _load() -> void:
	world = GAME.instantiate()
	world.level_path = GameState.SANDBOX
	add_child(world)
	await frames(3)
	world.player.input_enabled = false
	world.player.global_position = SPOT + Vector3(0, 0.05, 20)


func _unload() -> void:
	world.queue_free()
	await frames(2)


## Sum of the heap's heights over the grid, in m^3 (a point a square metre).
func _heap_volume(r: RubbleField) -> float:
	var total := 0.0
	for h in r._h:
		total += h * RubbleField.CELL * RubbleField.CELL
	return total


func test_a_heap_keeps_all_that_lands_on_it() -> void:
	await _load()
	var r := world.rubble
	var brick := RubbleField.color_of(
		Materials.Kind.CONCRETE, Materials.finish_seed(Materials.Finish.BRICK, 0.5)
	)
	for k in 60:
		r.deposit(SPOT + Vector3(randf_range(-0.5, 0.5), 3.0, randf_range(-0.5, 0.5)), 1.0, brick)
	for k in 240:
		r._flow(1000)
	check_near(r.volume, 60.0 * RubbleField.BULK, 0.01, "it counts all of it, loose")
	check_near(_heap_volume(r), r.volume, 0.05, "and all of it is on the ground")
	var top := r.height_at(SPOT)
	check(top > 2.0, "a real heap, not a film (%.2f m high)" % top)
	# No step steeper than the slope rubble stands at (with its spread).
	var steepest := 0.0
	var n := r._n
	for z in range(1, n - 1):
		for x in range(1, n - 1):
			var k := z * n + x
			steepest = maxf(steepest, r._h[k] - r._h[k + 1])
			steepest = maxf(steepest, r._h[k] - r._h[k + n])
	check(steepest < RubbleField.REPOSE * 1.25, "it slid down to a stable slope (%.2f m a metre)" % steepest)
	var o := (
		(
			roundi((SPOT.z + r._span()) / RubbleField.CELL) * n
			+ roundi((SPOT.x + r._span()) / RubbleField.CELL)
		)
		* 4
	)
	check(r._col[o] > r._col[o + 2] + 40, "it is the colour of what fell on it (brick)")
	await _unload()


func test_pieces_and_the_player_stand_on_a_heap() -> void:
	await _load()
	var r := world.rubble
	for k in 40:
		r.deposit(SPOT, 1.0, Color(0.6, 0.5, 0.4))
	for k in 240:
		r._flow(1000)
	await frames(150)  # the heap's collision follows
	var top := r.height_at(SPOT)
	var d := world.debris
	# Dropped gently (a hard landing would break it).
	var i := d.spawn(Transform3D(Basis(), SPOT + Vector3(0, top + 0.5, 0)), Vector3(0.4, 0.3, 0.4))
	world.player.global_position = SPOT + Vector3(1.0, top + 1.5, 0.5)
	await frames(120)
	var low := r.height_at(d.position_of(i))
	check(d.is_active(i), "the piece is still there")
	check(d.position_of(i).y > low - 0.3, "the piece rests on the heap, not under it")
	check(d.position_of(i).y > 1.0, "not on the paving under the heap")
	var feet := world.player.global_position
	check(feet.y > r.height_at(feet) - 0.4, "the player stands on it (%.2f m up)" % feet.y)
	await _unload()


func test_what_breaks_stays_on_the_ground() -> void:
	seed(3)
	await _load()
	var s := world.structures
	var d := world.debris
	var r := world.rubble
	var built := 0.0
	for i in s.segment_count():
		var z := s.size_of(i)
		built += z.x * z.y * z.z
	var tower := (world.level.get_node("Campanile") as Node3D).global_position
	world.player.global_position = Vector3(-6, 0.05, 34)
	for i in s.segment_count():
		var p := s.transform_of(i).origin
		if (
			s.is_alive(i)
			and p.y < 4.5
			and p.x > tower.x - 1.2
			and absf(p.x - tower.x) < 4.5
			and absf(p.z - tower.z) < 4.5
		):
			s.break_segment(i)
	await frames(600)  # 10 s of physics, however slow the machine
	var standing := 0.0
	var falling := 0.0
	for i in s.segment_count():
		var z := s.size_of(i)
		if s.is_alive(i):
			standing += z.x * z.y * z.z
	for c in s.falls.clusters:
		for i in c.members:
			var z := s.size_of(i)
			falling += z.x * z.y * z.z
	var pieces := 0.0
	for i in d.capacity:
		if d.is_active(i):
			pieces += d.volume_of(i)
	var gone := built - standing
	var seen := falling + pieces + r.volume / RubbleField.BULK
	check(gone > 500.0, "the tower came down (%.0f m^3)" % gone)
	check(seen > gone * 0.85, "what came down is still there: %.0f of %.0f m^3" % [seen, gone])
	check(r.volume / RubbleField.BULK > gone * 0.3, "much of it as heaps of rubble")
	await _unload()
