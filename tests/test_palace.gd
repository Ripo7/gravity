extends TestCase
## The palace and its bell tower: they stand, no block starts inside
## another, they stay within the block budget, and the tower comes down when
## its foot is cut.

const GAME := preload("res://scenes/game.tscn")
const BUDGET := 2000

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


func test_palace_and_tower_stand_when_rechecked() -> void:
	await _load()
	var s := world.structures
	var before := s.alive_count
	check(before > 0 and before < BUDGET, "%d blocks, budget %d" % [before, BUDGET])
	# Any damage re-checks a whole structure: intact, nothing may give way.
	check_eq(s.recheck_all(), 0, "nothing gives way on a re-check")
	await get_tree().create_timer(2.0).timeout
	check_eq(s.alive_count, before, "still standing after 2 s")
	check_eq(s.cluster_count(), 0, "nothing falling")
	await _unload()


func test_no_block_starts_inside_another() -> void:
	var level := (load(GameState.SANDBOX) as PackedScene).instantiate() as Level
	add_child(level)
	var boxes: Array[AABB] = []
	for st in level.structures():
		for seg in st.build_segments():
			var xf: Transform3D = st.transform * (seg["local"] as Transform3D)
			if not xf.basis.is_equal_approx(Basis()):
				continue  # tilted pieces (arch stones, pediments) are skipped
			var size: Vector3 = seg["size"]
			boxes.append(AABB(xf.origin - size * 0.5, size).grow(-0.02))
	level.queue_free()
	var grid := {}
	var seen := {}
	var bad := 0
	for i in boxes.size():
		var b := boxes[i]
		for x in range(floori(b.position.x / 4.0), floori(b.end.x / 4.0) + 1):
			for y in range(floori(b.position.y / 4.0), floori(b.end.y / 4.0) + 1):
				for z in range(floori(b.position.z / 4.0), floori(b.end.z / 4.0) + 1):
					var key := Vector3i(x, y, z)
					var cell: Array = grid.get(key, [])
					for j: int in cell:
						if seen.has(Vector2i(j, i)) or not boxes[j].intersects(b):
							continue
						seen[Vector2i(j, i)] = true
						if bad < 5:
							bad += 1
							failures.append(
								"%s: blocks %d and %d overlap at %s" % [current, j, i, b.get_center()]
							)
					cell.append(i)
					grid[key] = cell
	check(boxes.size() > 500, "found the blocks (%d)" % boxes.size())


func test_cutting_the_tower_foot_brings_it_down() -> void:
	await _load()
	var s := world.structures
	var tower := (world.level.get_node("Campanile") as Node3D).global_position
	# Knock out most of the first courses, from the palace side.
	for i in s.segment_count():
		var p := s.transform_of(i).origin
		if (
			s.is_alive(i)
			and p.y < 4.5
			and p.x > tower.x - 1.2
			and absf(p.z - tower.z) < 4.5
			and absf(p.x - tower.x) < 4.5
		):
			s.break_segment(i)
	var top_before := tower.y + 40.0
	await get_tree().create_timer(5.0).timeout
	var highest := 0.0
	for i in s.segment_count():
		if s.is_alive(i) and absf(s.transform_of(i).origin.x - tower.x) < 4.5:
			highest = maxf(highest, s.transform_of(i).origin.y)
	check(highest < top_before - 10.0, "the tower top came down (highest standing %.1f m)" % highest)
	await _unload()
