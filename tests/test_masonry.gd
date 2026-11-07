extends TestCase
## What falls comes apart as masonry, not as blocks of Lego: a big block that
## falls becomes the stones it is laid in (courses of staggered stones, rows
## of slabs), every stone touching its neighbours, all of the block's
## matter and no more.

const GAME := preload("res://scenes/game.tscn")


func _volume(boxes: Array[AABB]) -> float:
	var v := 0.0
	for b in boxes:
		v += b.get_volume()
	return v


## True when the stones tile the block: inside it, not overlapping.
func _tiles(boxes: Array[AABB], size: Vector3) -> bool:
	var block := AABB(-size * 0.5, size).grow(0.001)
	for a in boxes.size():
		if not block.encloses(boxes[a]):
			return false
		for b in range(a + 1, boxes.size()):
			if boxes[a].grow(-0.001).intersects(boxes[b].grow(-0.001)):
				return false
	return true


## Number of connected groups of stones linked by `pairs`.
func _groups(count: int, pairs: PackedInt32Array) -> int:
	var group := PackedInt32Array()
	group.resize(count)
	for k in count:
		group[k] = k
	var changed := true
	while changed:
		changed = false
		for k in range(0, pairs.size(), 2):
			var a := pairs[k]
			var b := pairs[k + 1]
			var g := mini(group[a], group[b])
			if group[a] != g or group[b] != g:
				group[a] = g
				group[b] = g
				changed = true
	var seen := {}
	for g in group:
		seen[g] = true
	return seen.size()


func test_a_wall_is_laid_in_staggered_courses() -> void:
	var m := Masonry.new(null)
	var size := Vector3(6.7, 1.6, 1.0)  # a course of the bell tower
	var stones := m.layout(size)
	check(stones.size() >= 6, "in stones (%d)" % stones.size())
	check_near(_volume(stones), size.x * size.y * size.z, 0.001, "all of the block's matter")
	check(_tiles(stones, size), "the stones tile the block")
	var longest := 0.0
	for b in stones:
		longest = maxf(longest, b.size.x)
		check_near(b.size.z, size.z, 0.001, "each stone goes through the wall")
	check(longest < 2.2, "no stone longer than a stone (%.2f m)" % longest)
	# Running bond: a joint in one course is not over a joint in the next.
	var joints := {}  # course -> joint positions along the wall
	for b in stones:
		var course := roundi(b.position.y * 100.0)
		if b.end.x < size.x * 0.5 - 0.01:
			if not joints.has(course):
				joints[course] = []
			joints[course].append(b.end.x)
	var lined := 0
	var keys := joints.keys()
	keys.sort()
	for k in range(1, keys.size()):
		for x: float in joints[keys[k]]:
			for y: float in joints[keys[k - 1]]:
				if absf(x - y) < 0.1:
					lined += 1
	check(keys.size() >= 2, "in courses (%d)" % keys.size())
	check_eq(lined, 0, "joints staggered from course to course")
	check_eq(_groups(stones.size(), m._pairs), 1, "every stone touches the next")


func test_a_floor_is_laid_in_rows_of_slabs() -> void:
	var m := Masonry.new(null)
	var size := Vector3(5.7, 0.4, 7.0)  # a piece of the palace's floor
	var slabs := m.layout(size)
	check(slabs.size() >= 9, "in slabs (%d)" % slabs.size())
	check_near(_volume(slabs), size.x * size.y * size.z, 0.001, "all of it")
	check(_tiles(slabs, size), "the slabs tile the floor")
	for b in slabs:
		check_near(b.size.y, size.y, 0.001, "each slab as thick as the floor")
	check_eq(_groups(slabs.size(), m._pairs), 1, "every slab touches the next")


func test_a_small_stone_stays_whole() -> void:
	var m := Masonry.new(null)
	check_eq(m.layout(Vector3(0.9, 0.4, 0.4)).size(), 1, "a window sill is one stone")


func test_what_falls_is_laid_in_stones() -> void:
	var world: GameWorld = GAME.instantiate()
	world.level_path = GameState.SANDBOX
	add_child(world)
	await frames(3)
	world.player.input_enabled = false
	world.player.global_position = Vector3(-6, 0.05, 34)
	var s := world.structures
	var tower := (world.level.get_node("Campanile") as Node3D).global_position
	var blocks := s.segment_count()
	var volume := 0.0
	for i in blocks:
		var p := s.transform_of(i).origin
		if absf(p.x - tower.x) < 4.5 and absf(p.z - tower.z) < 4.5:
			var z := s.size_of(i)
			volume += z.x * z.y * z.z
	for i in blocks:
		var p := s.transform_of(i).origin
		if (
			s.is_alive(i)
			and p.y < 4.5
			and p.x > tower.x - 1.2
			and absf(p.x - tower.x) < 4.5
			and absf(p.z - tower.z) < 4.5
		):
			s.break_segment(i)
	var stones := 0
	var members := 0
	var falling := 0.0
	for t in 40:
		await frames(3)
		if s.cluster_count() > 0:
			for c in s.falls.clusters:
				for i in c.members:
					members += 1
					stones += s._stone[i]
					var z := s.size_of(i)
					falling += z.x * z.y * z.z
			break
	check(members > 0, "the tower falls")
	check(stones > members * 0.6, "laid in stones (%d of %d pieces)" % [stones, members])
	check(stones > 300, "many of them (%d)" % stones)
	check(
		falling > volume * 0.6 and falling < volume * 1.01,
		"as much stone as stood: %.0f of %.0f m^3" % [falling, volume]
	)
	# Every stone of it touches another stone of it: it is masonry, not a
	# cloud of stones.
	var c := s.falls.clusters[0]
	var at := c.index()
	var alone := 0
	for i in c.members:
		var held := false
		for n in s._neighbors[i]:
			held = held or at.has(n)
		alone += 0 if held else 1
	check(alone <= c.members.size() / 50, "its stones hold together (%d alone)" % alone)
	world.queue_free()
	await frames(2)
