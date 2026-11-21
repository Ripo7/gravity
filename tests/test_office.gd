extends TestCase
## The office building on the bench: twice as high as the brute. A ground
## floor of glass between six concrete columns, taller than a storey so
## that the brute's straights reach it; three slabs; and on each of the
## two lower ones a storey of concrete: a low wall all round, piers on it
## that carry the slab over them, a pane in each window between the piers.
## What is no longer carried comes down: all of it above the ground floor
## once the three columns of a long side are cut.
##
## It stands askew on the bench (Main.OFFICE_TURN): everything here is told
## as the building is laid out, straight, and taken to the bench by
## `office`.

## How many piers, low walls and panes a storey has.
const PIERS := 14
const LOW_WALLS := 4
const PANES := 10

var main: Main
var p: Player
var s: Structure
## From the building as it is laid out (the middle of its floor at zero,
## its front towards +z) to where it stands on the bench.
var office: Transform3D


func test_the_office_building_is_glass_between_columns_under_two_concrete_storeys() -> void:
	await _load()
	check_eq(main.office_columns.size(), 6, "six columns")
	check_eq(main.office_shop.size(), 6, "six panes round the ground floor")
	check_eq(main.office_slabs.size(), Main.STOREYS + 1, "a slab under each storey, and the roof")
	check_eq(main.office_low_walls.size(), Main.STOREYS * LOW_WALLS, "four low walls to a storey")
	check_eq(main.office_piers.size(), Main.STOREYS * PIERS, "fourteen piers to a storey")
	check_eq(main.office_panes.size(), Main.STOREYS * PANES, "ten windows to a storey")
	check_eq(_office().size(), 71, "seventy-one pieces")
	var top := 0.0
	for q in _office():
		top = maxf(top, s._bounds(q).end.y)
		var glass := q in main.office_shop or q in main.office_panes
		check_eq(s.matter[q], Matter.GLASS if glass else Matter.CONCRETE, "piece %d: glass or concrete" % q)
	check_near(top, 3.6, 0.01, "it is twice as high as the brute")
	check(Main.GROUND_FLOOR > Main.STOREY + 0.5, "its ground floor is taller than a storey")
	check(Main.GROUND_FLOOR > 1.4 + 0.1, "tall enough for a straight, 1.4 m up, to land under its slab")
	# What carries what: the columns the first slab; on each slab the low
	# walls of a storey, on those its piers and its panes; the piers the
	# slab over them. No pane carries anything.
	var slabs := main.office_slabs
	check_eq(
		_sorted(s.rests_on[slabs[0]]), _sorted(main.office_columns), "the first slab rests on the six columns"
	)
	for q in main.office_columns:
		check(
			s.rests_on[q].is_empty() and s._bounds(q).position.y < 0.03, "column %d stands on the ground" % q
		)
	for q in main.office_shop:
		check(s.rests_on[q].is_empty() and s._bounds(q).position.y < 0.03, "pane %d stands on the ground" % q)
		check(s.carries[q].is_empty(), "and carries nothing")
		check(s._bounds(q).end.y < Main.GROUND_FLOOR - 0.03, "it stops short of the slab")
	for k in Main.STOREYS:
		var low_walls := main.office_low_walls.slice(k * LOW_WALLS, (k + 1) * LOW_WALLS)
		var piers := main.office_piers.slice(k * PIERS, (k + 1) * PIERS)
		check_eq(
			_sorted(s.rests_on[slabs[k + 1]]),
			_sorted(piers),
			"the slab over storey %d rests on its piers" % k
		)
		for q in low_walls:
			check_eq(Array(s.rests_on[q]), [slabs[k]], "low wall %d rests on the slab under it" % q)
			check(Matter.upright(s.size[q]), "it stands (it takes blows as a wall does)")
		for q in piers:
			check(
				s.rests_on[q].size() == 1 and s.rests_on[q][0] in low_walls, "pier %d rests on a low wall" % q
			)
			check_eq(Array(s.carries[q]), [slabs[k + 1]], "and carries the slab")
		for q in main.office_panes.slice(k * PANES, (k + 1) * PANES):
			check(
				s.rests_on[q].size() == 1 and s.rests_on[q][0] in low_walls,
				"window %d rests on a low wall" % q
			)
			check(s.carries[q].is_empty(), "and carries nothing")
	# Its front faces the start, askew.
	var to_start := (Main.START - Main.OFFICE_AT).normalized()
	check(_turned(Vector3.BACK).dot(to_start) > 0.8, "its front faces the start")
	check(absf(_turned(Vector3.BACK).x) < 0.99 and absf(_turned(Vector3.BACK).z) < 0.99, "askew")
	check(Main.OFFICE_AT.x < -3.0 and Main.HOUSE_AT.x > 3.0, "on the brute's left, the house on its right")
	await frames(60)
	check_eq(s.standing_count, s.pieces, "nothing comes down on its own")
	check_eq(s.rubble.live, 0, "nothing comes off")
	await _unload()


func test_walking_running_and_jumping_break_nothing_of_the_office_building() -> void:
	await _load()
	# At its front, then along it; then at a side.
	_face(_bench(Vector3(0.5, 0.05, 6)), _bench(Vector3(0.5, 1, 0)))
	p.touch_move = Vector2(0, -1)
	p.touch_sprint = true
	var inside := 0
	for k in 140:
		await frames(1)
		inside += 1 if _in_it(p.global_position) else 0
	var short := _laid(p.global_position).z - Main.OFFICE.y * 0.5
	check(short > 0.0 and short < 1.0, "the glass stops the brute, which ran right up to it (%.2f m)" % short)
	for k in 3:
		p.touch_jump = true
		await frames(50)
	p.touch_sprint = false
	p.touch_move = Vector2(1, -0.4)
	for k in 110:
		await frames(1)
		inside += 1 if _in_it(p.global_position) else 0
	_face(_bench(Vector3(-6, 0.05, 0.3)), _bench(Vector3(0, 1, 0.3)))
	p.touch_move = Vector2(0, -1)
	p.touch_sprint = true
	for k in 140:
		await frames(1)
		inside += 1 if _in_it(p.global_position) else 0
	p.touch_move = Vector2.ZERO
	p.touch_sprint = false
	short = -Main.OFFICE.x * 0.5 - _laid(p.global_position).x
	check(short > 0.0 and short < 1.0, "a side stops it too (%.2f m)" % short)
	check_eq(inside, 0, "it never went in")
	for q in s.pieces:
		check_eq(s.harm[q], 0.0, "piece %d took nothing" % q)
	check_eq(s.standing_count, s.pieces, "everything stands")
	check_eq(s.rubble.live, 0, "nothing came off")
	await _unload()


func test_a_pane_bursts_at_a_blow_and_a_window_when_the_low_wall_under_it_goes() -> void:
	await _load()
	var shop := main.office_shop[0]
	check(
		s.strike(s.place[shop].origin, _turned(Vector3.FORWARD), 2, s.body_of(shop)),
		"a blow lands on a pane of the ground floor"
	)
	check_eq(s.state[shop], Structure.BROKEN, "it bursts")
	for q in main.office_shop:
		check(q == shop or s.state[q] == Structure.STANDS, "pane %d, which was not struck, stands" % q)
	check_eq(s.rubble.live, 0, "into glitter: no loose body")
	# The low wall of the front of the first storey, struck under a window.
	var window := main.office_panes[0]
	var low := main.office_low_walls[0]
	check(low in s.rests_on[window], "(that window is on that wall)")
	var under := s.place[window].origin - Vector3.UP * (s.size[window].y + Main.LOW_WALL) * 0.5
	s.hit(low, 2.0, _turned(Vector3.FORWARD), under)
	s.hit(low, 2.0, _turned(Vector3.FORWARD), under)
	check_eq(s.state[window], Structure.STANDS, "two blows on the wall under it: the window stands")
	check(s.cracks[low] > 0, "the wall is cracked")
	s.hit(low, 3.0, _turned(Vector3.FORWARD), under)
	check(s.rubble.live > 0, "at the third, blocks are out of the wall")
	check_eq(s.state[low], Structure.STANDS, "the rest of it stands")
	check_eq(s.state[window], Structure.BROKEN, "the window over the hole has burst")
	for slab in main.office_slabs:
		check_eq(s.state[slab], Structure.STANDS, "slab %d stays up" % slab)
	check(await _rest(900), "everything comes to rest")
	for slab in main.office_slabs:
		check_eq(s.state[slab], Structure.STANDS, "slab %d is still up" % slab)
	await _unload()


func test_a_column_gives_at_the_third_straight_and_the_slab_holds_on_those_that_are_left() -> void:
	await _load()
	var column := main.office_columns[0]
	var at := _at_fist(column)
	s.hit(column, 2.0, _turned(Vector3.FORWARD), at)
	s.hit(column, 2.0, _turned(Vector3.FORWARD), at)
	check_eq(s._standing_of(column).size(), s.blocks[column], "two blows: the column is whole")
	check(s.cracks[column] > 0, "and cracked")
	s.hit(column, 2.0, _turned(Vector3.FORWARD), at)
	var left := s._standing_of(column).size()
	check(
		left > 0 and left < s.blocks[column], "the third: its top is out, a stump stands (%d blocks)" % left
	)
	check(s._heads(column).is_empty(), "nothing of it is under the slab any more")
	for q in _office():
		check_eq(s.state[q], Structure.STANDS, "piece %d stands: the slab holds on five columns" % q)
	check(await _rest(900), "everything comes to rest")
	check_eq(s.standing_count, s.pieces, "and nothing has come down since")
	# A pier of the first storey knocked out: the slab over it holds on the
	# others.
	var pier := main.office_piers[1]
	for points: float in [2.0, 2.0, 3.0]:
		s.hit(pier, points, _turned(Vector3.FORWARD), s.place[pier].origin)
	check(s.state[pier] != Structure.STANDS, "a combination on a pier: it is out")
	for slab in main.office_slabs:
		check_eq(s.state[slab], Structure.STANDS, "slab %d stays up" % slab)
	await _unload()


func test_with_the_three_columns_of_its_front_cut_all_of_it_comes_down_and_breaks() -> void:
	await _load()
	for k in 3:
		check_eq(
			s.state[main.office_slabs[0]], Structure.STANDS, "(the slab is up before column %d goes)" % k
		)
		for blow in 3:
			s.hit(main.office_columns[k], 2.0, _turned(Vector3.FORWARD), _at_fist(main.office_columns[k]))
	# All of it but the ground floor is on its way down, at once.
	for group: PackedInt32Array in [main.office_slabs, main.office_low_walls, main.office_piers]:
		for q in group:
			check(s.state[q] != Structure.STANDS, "piece %d no longer stands" % q)
	for q in main.office_panes:
		check_eq(s.state[q], Structure.BROKEN, "window %d has burst" % q)
	for k: int in [3, 4, 5]:
		var back := main.office_columns[k]
		check_eq(s._standing_of(back).size(), s.blocks[back], "column %d of the back is whole" % back)
	for q in main.office_shop:
		check_eq(s.state[q], Structure.STANDS, "(pane %d of the ground floor stands: nothing struck it)" % q)
	check(await _rest(1800), "everything comes to rest")
	# It broke as it landed, and lies low.
	for slab in main.office_slabs:
		check_eq(s.state[slab], Structure.BROKEN, "slab %d is in blocks" % slab)
	var lies := _lies()
	check(lies.x < 3.0, "nothing is left as high as the top storey was (%.2f m at the highest)" % lies.x)
	check(lies.y < 9.0, "nothing went far (%.1f m from its middle)" % lies.y)
	# Glass carries nothing: the panes of the front, which nothing struck,
	# gave under what came to rest on them.
	for k: int in [0, 1]:
		check_eq(s.state[main.office_shop[k]], Structure.BROKEN, "pane %d of the front has burst" % k)
	for q in s.pieces:
		check(q in _office() or s.harm[q] == 0.0, "piece %d, not of the building, took nothing" % q)
	await _unload()


func test_the_brute_cuts_the_columns_of_the_front_and_brings_the_building_down() -> void:
	await _load()
	var thrown := [0]
	p.blow.connect(func(_at: Vector3, _way: Vector3, _power: int, _on: RID) -> void: thrown[0] += 1)
	var half := Main.OFFICE * 0.5
	var most := 0
	for k in 3:
		var column := main.office_columns[k]
		var x := (k - 1) * (half.x - Main.OFFICE_COLUMN * 0.5)
		check_eq(
			s.state[main.office_slabs[0]], Structure.STANDS, "(the slab is up as it comes to column %d)" % k
		)
		_face(_bench(Vector3(x, 0.05, half.y + 0.6)), _bench(Vector3(x, 1.0, half.y)))
		await frames(5)
		var before: int = thrown[0]
		for step in 1500:
			var cut := s._heads(column).is_empty()
			if (cut or thrown[0] - before >= 9) and not p.character.striking():
				break
			if step % 6 == 0 and not cut and thrown[0] - before < 9:
				p.punch()
			await frames(1)
		check(s._heads(column).is_empty(), "column %d is cut (%d blows)" % [k, thrown[0] - before])
		most = maxi(most, thrown[0] - before)
	# (Three straights cut it: the leap that ends a combination lands over
	# it, on the low wall of the first storey.)
	check(most <= 6, "each within two combinations (%d blows at most)" % most)
	for group: PackedInt32Array in [main.office_slabs, main.office_low_walls, main.office_piers]:
		for q in group:
			check(s.state[q] != Structure.STANDS, "piece %d no longer stands" % q)
	await frames(240)
	check(
		p.global_position.is_finite() and p.global_position.y > -0.1 and p.global_position.y < 2.5,
		"the brute is on the ground or on what came down (%.2f m up)" % p.global_position.y
	)
	# (What lies against the brute is not left to rest: it is taken away.)
	p.set_down(_bench(Vector3(0, 0.05, 10)))
	check(await _rest(2400), "everything comes to rest")
	var lies := _lies()
	check(lies.x < 3.0, "nothing is left as high as the top storey was (%.2f m at the highest)" % lies.x)
	check(lies.y < 9.0, "nothing went far (%.1f m from its middle)" % lies.y)
	for q in s.pieces:
		check(q in _office() or s.harm[q] == 0.0, "piece %d, not of the building, took nothing" % q)
	await _unload()


## How high what lies loose lies at the highest, and how far from the
## middle of the building at the farthest (m, seen from above).
func _lies() -> Vector2:
	var high := 0.0
	var far := 0.0
	for i in s.rubble.body.size():
		if s.rubble.alive[i] == 1:
			var at := _laid(s.rubble.transform_of(i).origin)
			high = maxf(high, at.y)
			far = maxf(far, Vector2(at.x, at.z).length())
	return Vector2(high, far)


## Every piece of the office building.
func _office() -> Array[int]:
	var all: Array[int] = []
	all.assign(main.office_pieces())
	return all


## The numbers `of`, in order.
func _sorted(of: PackedInt32Array) -> Array:
	var all := Array(of)
	all.sort()
	return all


## Where a straight of the brute lands on column `q`: 1.4 m up, on the face
## of it that looks out of the front.
func _at_fist(q: int) -> Vector3:
	return (
		office * (s._within[q].origin + Vector3(0, 1.4 - Main.GROUND_FLOOR * 0.5, Main.OFFICE_COLUMN * 0.5))
	)


## Is the point `at` of the bench inside the building, seen from above?
func _in_it(at: Vector3) -> bool:
	var off := _laid(at)
	return absf(off.x) < Main.OFFICE.x * 0.5 and absf(off.z) < Main.OFFICE.y * 0.5


## Where the point `of` the building as it is laid out is on the bench.
func _bench(of: Vector3) -> Vector3:
	return office * of


## Where the point `at` of the bench is in the building as it is laid out.
func _laid(at: Vector3) -> Vector3:
	return office.affine_inverse() * at


## The way `of` the building as it is laid out, on the bench.
func _turned(of: Vector3) -> Vector3:
	return office.basis * of


## Puts the brute at `at`, turned (and looking) towards `target`.
func _face(at: Vector3, target: Vector3) -> void:
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.facing = atan2(at.x - target.x, at.z - target.z)
	p.look(Vector2(angle_difference(p.yaw, p.facing), 0.0))


## Waits for everything loose to come to rest, `most` steps at most.
## Returns whether it did.
func _rest(most: int) -> bool:
	for k in most:
		await frames(1)
		if s.rubble.awake == 0:
			return true
	return false


func _load() -> void:
	seed(5)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await frames(20)
	p = main.player
	s = main.structure
	office = main.office_frame()


func _unload() -> void:
	main.queue_free()
	await frames(2)
