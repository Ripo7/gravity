extends TestCase
## Cutting a box into irregular shards.


func test_the_shards_fill_the_box_exactly() -> void:
	for size: Vector3 in [Vector3(6, 3, 0.35), Vector3(4, 0.3, 5), Vector3(0.5, 3, 0.5), Vector3(2, 2, 2)]:
		var shards := Fracture.cut(size, 0.6, 11)
		var volume := 0.0
		for sh in shards:
			volume += sh.volume
			check(sh.points.size() >= 4 and sh.faces.size() >= 4, "a shard is a solid")
			check(sh.volume > 0.0, "with some volume")
			var half := size * 0.5 + Vector3.ONE * 1e-3
			for p in sh.points:
				check(absf(p.x) <= half.x and absf(p.y) <= half.y and absf(p.z) <= half.z, "inside the box")
		check_near(volume, size.x * size.y * size.z, size.x * size.y * size.z * 1e-3, "volume of %s" % size)


func test_each_cut_is_shared_by_two_shards() -> void:
	var shards := Fracture.cut(Vector3(5, 3, 0.35), 0.6, 5)
	var cuts := 0
	for i in shards.size():
		var sh := shards[i]
		for f in sh.faces.size():
			var other := sh.others[f]
			if other < 0:
				continue
			cuts += 1
			var twin := shards[other].others.find(i)
			check(twin >= 0, "shard %d knows its neighbour %d" % [other, i])
			if twin >= 0:
				check_near(shards[other].areas[twin], sh.areas[f], 1e-3, "same face on both sides")
				check(shards[other].normals[twin].dot(sh.normals[f]) < -0.999, "facing each other")
	check(cuts > shards.size() * 3, "shards touch several others (%d cuts)" % cuts)


func test_shards_are_irregular_and_of_mixed_sizes() -> void:
	var shards := Fracture.cut(Vector3(8, 3, 0.35), 0.6, 3)
	check(shards.size() > 60 and shards.size() < 160, "about 4 shards per m2 (%d)" % shards.size())
	var small := INF
	var big := 0.0
	var corners := {}
	for sh in shards:
		small = minf(small, sh.volume)
		big = maxf(big, sh.volume)
		corners[sh.points.size()] = true
	check(big > small * 4.0, "big and small shards (%.3f to %.3f m3)" % [small, big])
	check(corners.size() >= 4, "of several shapes (corner counts %s)" % [corners.keys()])


func test_the_same_seed_gives_the_same_cut() -> void:
	var a := Fracture.cut(Vector3(3, 3, 0.35), 0.6, 42)
	var b := Fracture.cut(Vector3(3, 3, 0.35), 0.6, 42)
	var c := Fracture.cut(Vector3(3, 3, 0.35), 0.6, 43)
	check_eq(a.size(), b.size(), "same number of shards")
	var same := a.size() == b.size()
	for i in mini(a.size(), b.size()):
		same = same and a[i].points == b[i].points
	check(same, "same corners")
	check(c.size() != a.size() or c[0].points != a[0].points, "another seed, another cut")
