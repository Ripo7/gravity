extends TestCase
## A building is laid out straight and may stand turned, any way about the
## vertical (Structure.frame). Turned, it holds, breaks and falls as it
## does straight.

var main: Main


func test_however_it_is_turned_a_house_rests_on_the_same_things_and_stands() -> void:
	await _load()
	var rests: Array[Array] = []
	var carried: Array[Array] = []
	var cut: Array[int] = []
	for turn: float in [0.0, 37.0, 90.0, 211.5, Main.HOUSE_TURN]:
		main.house_turn = turn
		main.rebuild()
		await frames(3)
		var s := main.structure
		var house := main.house_frame()
		var k := 0
		for q in main.house_pieces():
			# Where it is told to be, and as it is laid out but for the turn.
			var up := s.place[q].basis.y
			check(
				(house.basis.inverse() * up).is_equal_approx(s._within[q].basis.y),
				"turned %.1f, piece %d is tilted as it is laid out" % [turn, q]
			)
			check(
				s.place[q].origin.is_equal_approx(house * s._within[q].origin),
				"turned %.1f, piece %d is where the house puts it" % [turn, q]
			)
			if rests.size() <= k:
				rests.append(Array(s.rests_on[q]))
				carried.append(Array(s.carries[q]))
				cut.append(s.blocks[q])
			check_eq(Array(s.rests_on[q]), rests[k], "turned %.1f, piece %d rests on the same" % [turn, q])
			check_eq(Array(s.carries[q]), carried[k], "turned %.1f, piece %d carries the same" % [turn, q])
			check_eq(s.blocks[q], cut[k], "turned %.1f, piece %d is cut the same" % [turn, q])
			k += 1
		# What is in the way is where it is drawn: over the middle of a slope
		# of the roof, straight down, the first thing is a board of the roof.
		for side: float in [-1.0, 1.0]:
			var over := house * Vector3(side * 0.7, 6.0, 0.2)
			var down := PhysicsRayQueryParameters3D.create(over, over + Vector3.DOWN * 6.0, Layers.STRUCTURE)
			var met := main.get_world_3d().direct_space_state.intersect_ray(down)
			check(
				not met.is_empty() and s.standing(met["rid"]) in main.house_roof,
				"turned %.1f, the roof is in the way where it is drawn" % turn
			)
		await frames(60)
		check_eq(s.standing_count, s.pieces, "turned %.1f, nothing comes down on its own" % turn)
		check_eq(s.rubble.live, 0, "turned %.1f, nothing comes off" % turn)
	await _unload()


func test_turned_what_stands_breaks_bends_and_comes_down_as_it_does_straight() -> void:
	await _load()
	# The same yard twice, far from the bench: straight, as everything was
	# until now, and turned. The same blows on both, told as the yard is
	# laid out.
	var straight := Transform3D.IDENTITY
	var turned := Transform3D(Basis(Vector3.UP, deg_to_rad(137.0)), Vector3(40, 0, -40))
	var a := _yard(straight, Vector3(40, 0, 40))
	var b := _yard(turned, Vector3.ZERO)
	var yards: Array = [[a, straight], [b, turned]]
	await frames(3)
	check_eq(a.pieces, b.pieces, "the same pieces")
	check_eq(a.count, b.count, "cut into the same parts")
	for q in a.pieces:
		check_eq(Array(b.rests_on[q]), Array(a.rests_on[q]), "piece %d rests on the same, turned" % q)
	# The triangle of the deck that is over each pier (what it will hang
	# by): the same one, and it is over that pier.
	for q: int in [6, 7, 8, 9]:
		var over: Array[int] = []
		for yard: Array in yards:
			var s: Structure = yard[0]
			var head := s._within[q].origin
			var tile := s._tile_over(10, Vector2(head.x, head.z))
			over.append(tile)
			var corners := PackedVector2Array()
			for n in s.bend[10].tiles[tile]:
				corners.append(Vector2(s.bend[10].rest(n).x, s.bend[10].rest(n).z))
			var foot := Vector2(s.place[q].origin.x, s.place[q].origin.z)
			var off := INF
			for k in 3:
				var on_edge := Geometry2D.get_closest_point_to_segment(foot, corners[k], corners[(k + 1) % 3])
				off = minf(off, foot.distance_to(on_edge))
			check(
				Geometry2D.point_is_inside_triangle(foot, corners[0], corners[1], corners[2]) or off < 0.002,
				"the triangle of the deck over pier %d is over it (%.3f m off)" % [q, off]
			)
		check_eq(over[1], over[0], "the same triangle of the deck is over pier %d, turned" % q)
	# [what is said of it, piece, points, which way, where from its middle
	# (nowhere in particular, if not finite), how many times]
	var blows: Array[Array] = [
		["a blow on the wall", 0, 1.0, Vector3.FORWARD, Vector3(-0.5, 0.2, 0), 3],
		["the wall gives there", 0, 1.0, Vector3.FORWARD, Vector3(-0.5, 0.2, 0), 9],
		["a hole beside the first", 0, 1.0, Vector3.FORWARD, Vector3(0.3, 0.2, 0), 12],
		["and low under them", 0, 1.0, Vector3.FORWARD, Vector3(-0.1, -0.7, 0), 12],
		["a hole in the slab, away from the post on it", 5, 1.0, Vector3.DOWN, Vector3(-1.0, 0, 0.4), 14],
		["a column under the slab goes", 1, 40.0, Vector3.RIGHT, Vector3.INF, 1],
		["and the next one", 2, 40.0, Vector3.RIGHT, Vector3.INF, 1],
		["a dent in the sheet", 11, 2.0, Vector3.FORWARD, Vector3(0.2, 0.3, 0), 2],
		["and from the other side", 11, 1.0, Vector3.BACK, Vector3(-0.3, -0.2, 0), 1],
		["a kink in the post", 12, 2.0, Vector3(1, 0, 1).normalized(), Vector3(0, 0.4, 0), 2],
		["a pier under the deck is kinked", 6, 2.0, Vector3.LEFT, Vector3(0, 0.1, 0), 1],
		["until it lies down", 6, 2.0, Vector3.LEFT, Vector3(0, 0.1, 0), 12],
		["a stilt under the floor is cut", 13, 2.0, Vector3.RIGHT, Vector3(0, 0.6, 0), 1],
		["a board of the floor is struck", 20, 2.0, Vector3.DOWN, Vector3(0.9, 0, 0), 1],
		["the plank under the pane is cut", 23, 2.0, Vector3.BACK, Vector3(0, 0.1, 0), 1]
	]
	var then := {}  # what is said of a blow -> what every piece of the straight yard was doing after it
	var out := {}  # and how many of its blocks were out
	for blow in blows:
		var q: int = blow[1]
		for yard: Array in yards:
			var s: Structure = yard[0]
			var frame: Transform3D = yard[1]
			var from_middle: Vector3 = blow[4]
			var at := Vector3.INF
			if from_middle.is_finite():
				at = frame * (s._within[q].origin + from_middle)
			for k: int in blow[5]:
				s.hit(q, blow[2], frame.basis * (blow[3] as Vector3), at)
		var said: String = blow[0]
		then[said] = a.state.duplicate()
		out[said] = a.stands.count(0)
		check_eq(Array(b.state), Array(a.state), "%s: turned, every piece is doing the same" % said)
		check_eq(Array(b.stands), Array(a.stands), "%s: turned, the same blocks stand" % said)
		check_eq(b.standing_count, a.standing_count, "%s: as many pieces stand" % said)
		check_eq(b.rubble.live, a.rubble.live, "%s: as many loose bodies" % said)
		check_eq(b.glitter.bursts, a.glitter.bursts, "%s: as much glass has burst" % said)
		for p in a.pieces:
			check_near(b.harm[p], a.harm[p], 0.001, "%s: piece %d has taken as much" % [said, p])
			check_eq(b._ties[p].size(), a._ties[p].size(), "%s: as much hangs from piece %d" % [said, p])
			if a.bend[p] == null:
				continue
			var bent_a := a.bend[p]
			var bent_b := b.bend[p]
			check_eq(
				bent_b.kink_at.size(), bent_a.kink_at.size(), "%s: piece %d has as many kinks" % [said, p]
			)
			for j in mini(bent_a.kink_at.size(), bent_b.kink_at.size()):
				check_near(bent_b.kink_at[j], bent_a.kink_at[j], 0.001, "%s: at the same height" % said)
				var lean := turned.basis.inverse() * bent_b.kink_lean[j]
				check(
					lean.distance_to(bent_a.kink_lean[j]) < 0.001,
					"%s: the same way, as it is laid out" % said
				)
			for n in bent_a.dent.size():
				check_near(
					bent_b.dent[n], bent_a.dent[n], 0.0005, "%s: node %d is dented as deep" % [said, n]
				)
	# And what it does, turned or not, is what it did on the bench.
	check_eq(a.state[0], Structure.STANDS, "the wall still stands, holed")
	check(a.stands.count(0) > 20, "blocks are out of it")
	var holed: String = "a hole in the slab, away from the post on it"
	check(out[holed] > out["and low under them"], "blocks are out of the slab")
	check_eq(then[holed][5], Structure.STANDS, "which holds")
	check_eq(then[holed][25], Structure.STANDS, "and the metal post on it stays up")
	check_eq(then["a column under the slab goes"][5], Structure.STANDS, "on three columns the slab holds")
	check(then["and the next one"][5] != Structure.STANDS, "on two, side by side, it comes down")
	check(then["and the next one"][25] != Structure.STANDS, "and the post on it with it")
	check(a.harm[11] > 0.0 and a.harm[12] > 0.0, "the sheet and the post are marked")
	check_eq(a.state[11], Structure.STANDS, "and stand")
	check_eq(
		then["a pier under the deck is kinked"][10], Structure.STANDS, "on a kinked pier the deck stays up"
	)
	check(then["until it lies down"][10] != Structure.STANDS, "it sags when the pier lies down")
	var hangs := 0
	for q: int in [7, 8, 9]:
		check_eq(a.state[q], Structure.STANDS, "pier %d stands" % q)
		hangs += b._ties[q].size()
	check(hangs >= 2, "and hangs from the piers that still stand (%d ties, turned)" % hangs)
	check(
		then["a stilt under the floor is cut"][17] != Structure.STANDS, "a stilt is cut: its beam comes down"
	)
	for q: int in [19, 20, 21, 22]:
		check(then["a stilt under the floor is cut"][q] != Structure.STANDS, "and board %d with it" % q)
	check_eq(a.state[18], Structure.STANDS, "the other beam stays up")
	check_eq(a.state[24], Structure.BROKEN, "the plank under the pane is cut: it bursts")
	# Left to itself, the deck hangs from the piers that stand, turned or
	# not: its corners over them are where they were, the one over the pier
	# that gave has come down.
	for k in 1800:
		await frames(1)
		if a.rubble.awake == 0 and b.rubble.awake == 0:
			break
	check(a.rubble.awake == 0 and b.rubble.awake == 0, "everything comes to rest")
	for yard: Array in yards:
		var s: Structure = yard[0]
		var frame: Transform3D = yard[1]
		var which := "turned" if s == b else "straight"
		var nodes := _parts(s, 10)
		var up := s.place[10].origin.y
		var low := 0
		for k in nodes.size():
			var corner := s.bend[10].rest(k)
			for q: int in [6, 7, 8, 9]:
				var foot := s.place[q].origin
				if Vector2(corner.x - foot.x, corner.z - foot.z).length() > 0.5:
					continue
				var off := frame.basis.inverse() * (nodes[k] - corner)
				if q == 6:
					low += 1
					check(nodes[k].y < up - 0.5, "%s, its corner over the pier that gave has sagged" % which)
				else:
					check(
						nodes[k].y > up - 0.25 and Vector2(off.x, off.z).length() < 0.5,
						(
							"%s, over pier %d it is where it was (%.2f, %.2f, %.2f off)"
							% [which, q, off.x, off.y, off.z]
						)
					)
		check_eq(low, 1, "%s, one corner was over that pier" % which)
	a.free()
	b.free()
	await _unload()


func test_what_is_laid_out_over_a_piece_of_another_building_does_not_rest_on_it() -> void:
	await _load()
	var s := Structure.new()
	main.add_child(s)
	# A column with a slab on it; and, in a frame that stands elsewhere,
	# turned, a slab laid out right where that one is in its own.
	s.frame = Transform3D(Basis(), Vector3(60, 0, 0))
	var column := _stand(s, Matter.CONCRETE, Main.POST, Vector3.ZERO)
	var on_it := _stand(s, Matter.CONCRETE, Vector3(1, 0.3, 1), Vector3.UP * Main.POST.y)
	s.frame = Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), Vector3(90, 0, 0))
	var elsewhere := _stand(s, Matter.CONCRETE, Vector3(1, 0.3, 1), Vector3.UP * Main.POST.y)
	s.frame = Transform3D(Basis(), Vector3(60, 0, 0))
	var beside := _stand(s, Matter.CONCRETE, Vector3(0.2, 0.3, 0.2), Vector3(0, Main.POST.y + 0.3, 0))
	s.build()
	check_eq(Array(s.rests_on[on_it]), [column], "a slab rests on the column under it")
	check_eq(Array(s.rests_on[beside]), [on_it], "what is added in that frame later rests on what is in it")
	check(s.rests_on[elsewhere].is_empty(), "a slab of another building, elsewhere, does not")
	check_eq(Array(s.carries[column]), [on_it], "the column carries its own slab only")
	check(s.place[elsewhere].origin.distance_to(s.place[on_it].origin) > 25.0, "(they are far apart)")
	s.free()
	await _unload()


## A yard in `frame`, its middle at `at` there: a concrete wall (piece 0),
## a slab (5) on four columns (1 to 4), a metal deck (10) on four piers (6
## to 9), a sheet (11), a metal post (12), a floor of four boards (19 to
## 22) on two beams (17, 18) on four stilts (13 to 16), a pane (24) on a
## plank (23), a metal post on the slab (25).
func _yard(frame: Transform3D, at: Vector3) -> Structure:
	var s := Structure.new()
	main.add_child(s)
	s.frame = frame
	var corners: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	_stand(s, Matter.CONCRETE, Main.WALL, at + Vector3(0, 0, 8))
	for corner in corners:
		_stand(s, Matter.CONCRETE, Main.POST, at + Vector3(corner.x, 0, corner.y) * Main.SPAN * 0.5)
	_stand(s, Matter.CONCRETE, Main.SLAB, at + Vector3.UP * Main.POST.y)
	for corner in corners:
		var out := Vector3(corner.x, 0, corner.y) * Main.SPAN * 0.5
		_stand(s, Matter.METAL, Main.PIER, at + Vector3(8, 0, 0) + out)
	_stand(s, Matter.METAL, Main.DECK, at + Vector3(8, Main.PIER.y, 0))
	_stand(s, Matter.METAL, Main.SHEET, at + Vector3(8, 0, 8))
	_stand(s, Matter.METAL, Main.METAL_POST, at + Vector3(11, 0, 8))
	for corner in corners:
		var out := Vector3(corner.x, 0, corner.y) * Main.FLOOR_SPAN * 0.5
		_stand(s, Matter.WOOD, Main.STILT, at + Vector3(-8, 0, 0) + out)
	for side: float in [-1.0, 1.0]:
		var out := Vector3(side * Main.FLOOR_SPAN * 0.5, Main.STILT.y, 0)
		_stand(s, Matter.WOOD, Main.BEAM, at + Vector3(-8, 0, 0) + out)
	for k in 4:
		var along := Vector3(0, Main.STILT.y + Main.BEAM.y, (k - 1.5) * Main.BOARD.z)
		_stand(s, Matter.WOOD, Main.BOARD, at + Vector3(-8, 0, 0) + along)
	_stand(s, Matter.WOOD, Vector3(0.4, 0.5, 0.06), at + Vector3(-8, 0, 8))
	_stand(s, Matter.GLASS, Vector3(0.4, 1.0, 0.04), at + Vector3(-8, 0.5, 8))
	_stand(s, Matter.METAL, Vector3(0.2, 1.0, 0.2), at + Vector3(1.2, Main.POST.y + Main.SLAB.y, 1.2))
	s.build()
	return s


## A piece of `s` made `of` a matter, `size` across, its foot at `foot` in
## the frame of `s`. Returns its number.
func _stand(s: Structure, of: int, size: Vector3, foot: Vector3) -> int:
	return s.add_piece(of, Transform3D(Basis(), foot + Vector3.UP * size.y * 0.5), size)


## Where the nodes of plate `q` of `built`, which has come loose, are now.
func _parts(built: Structure, q: int) -> PackedVector3Array:
	var at := PackedVector3Array()
	at.resize(built.blocks[q])
	var loose := built.rubble
	for i in built._loose[q]:
		var now := loose.transform_of(i) * Transform3D(Basis(), -loose.origin[i])
		for part: Array in loose._rig[i]:
			var slot: int = part[0]
			at[slot - 1 - built.first[q]] = (now * (part[1] as Transform3D)).origin
	return at


func _load() -> void:
	seed(5)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await frames(20)


func _unload() -> void:
	main.queue_free()
	await frames(2)
