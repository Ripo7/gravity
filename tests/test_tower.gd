extends TestCase
## The tower on the bench: four times as high as the brute, of metal and
## glass, stepped. Four storeys, each four posts at its corners, a deck on
## them and a pane in each side; the upper two narrower, in the middle of
## the deck under them.
##
## Metal stays in one: two pieces of metal, one of which rests on the
## other, stay fixed where they met when they come down. When a post at
## its foot gives, the glass over it bursts and the frame goes over and
## lies down in one, hanging from the posts that still stand.
##
## It stands askew on the bench (Main.TOWER_TURN): everything here is told
## as the tower is laid out, straight, and taken to the bench by `tower`.

var main: Main
var p: Player
var s: Structure
## From the tower as it is laid out (the middle of its floor at zero) to
## where it stands on the bench.
var tower: Transform3D


func test_the_tower_is_four_storeys_of_posts_decks_and_glass_the_upper_two_narrower() -> void:
	await _load()
	check_eq(main.tower_posts.size(), 4 * Main.TOWER_STOREYS, "four posts to a storey")
	check_eq(main.tower_decks.size(), Main.TOWER_STOREYS, "a deck to a storey")
	check_eq(main.tower_panes.size(), 4 * Main.TOWER_STOREYS, "four panes to a storey")
	check_eq(_tower().size(), 36, "thirty-six pieces")
	var top := 0.0
	for q in _tower():
		top = maxf(top, s._bounds(q).end.y)
		check_eq(
			s.matter[q], Matter.GLASS if q in main.tower_panes else Matter.METAL, "piece %d: its matter" % q
		)
	check_near(top, 7.2, 0.01, "it is four times as high as the brute")
	check(
		Main.TOWER_STOREY - Main.TOWER_DECK > 1.4 + 0.1, "a straight, 1.4 m up, lands on a post of its foot"
	)
	for k in Main.TOWER_STOREYS:
		var posts := main.tower_posts.slice(4 * k, 4 * k + 4)
		var deck := main.tower_decks[k]
		var across := Main.TOWER if k < Main.TOWER_STEP else Main.TOWER_TOP
		check_near(s.size[deck].x, across, 0.001, "storey %d is %.1f m across" % [k, across])
		check_eq(s.bend[deck].kind, Bend.PLATE, "its deck is a plate")
		check_eq(_sorted(s.rests_on[deck]), _sorted(posts), "which rests on its four posts")
		for q in posts:
			check_eq(s.bend[q].kind, Bend.POST, "post %d is a post" % q)
			check_eq(Array(s.carries[q]), [deck], "it carries the deck")
			if k == 0:
				check(s.rests_on[q].is_empty() and s._bounds(q).position.y < 0.03, "it stands on the ground")
			else:
				check_eq(Array(s.rests_on[q]), [main.tower_decks[k - 1]], "it stands on the deck under it")
				var off := _laid(s.place[q].origin)
				check(maxf(absf(off.x), absf(off.z)) < across * 0.5, "within its storey")
		for q in main.tower_panes.slice(4 * k, 4 * k + 4):
			check(s.carries[q].is_empty(), "pane %d carries nothing" % q)
			check(s._bounds(q).end.y < s._bounds(deck).position.y - 0.03, "it stops short of the deck")
			if k == 0:
				check(s.rests_on[q].is_empty(), "it stands on the ground")
			else:
				check_eq(Array(s.rests_on[q]), [main.tower_decks[k - 1]], "it stands on the deck under it")
	check(Main.TOWER_TOP < Main.TOWER and Main.TOWER_STEP > 0, "it is stepped: narrower at the top")
	# Behind the brute, beyond the glass; where it cannot lie down on the
	# house or on the office building, nor on the panes.
	check(Main.TOWER_AT.z > Main.GLASS_AT.z + top + 1.0, "it is behind the brute, beyond the panes of glass")
	for other: Vector3 in [Main.HOUSE_AT, Main.OFFICE_AT]:
		check(Main.TOWER_AT.distance_to(other) > top + 4.0, "and out of reach of the other buildings")
	var turned := tower.basis * Vector3.RIGHT
	check(absf(turned.x) < 0.99 and absf(turned.z) < 0.99, "askew")
	await frames(60)
	check_eq(s.standing_count, s.pieces, "nothing comes down on its own")
	check_eq(s.rubble.live, 0, "nothing comes off")
	await _unload()


func test_walking_running_and_jumping_break_nothing_of_the_tower() -> void:
	await _load()
	_face(_bench(Vector3(0.4, 0.05, 6)), _bench(Vector3(0.4, 1, 0)))
	p.touch_move = Vector2(0, -1)
	p.touch_sprint = true
	var inside := 0
	for k in 140:
		await frames(1)
		inside += 1 if _in_it(p.global_position) else 0
	var short := _laid(p.global_position).z - Main.TOWER * 0.5
	check(short > 0.0 and short < 1.0, "the glass stops the brute, which ran right up to it (%.2f m)" % short)
	for k in 3:
		p.touch_jump = true
		await frames(50)
	p.touch_sprint = false
	p.touch_move = Vector2(1, -0.4)
	for k in 110:
		await frames(1)
		inside += 1 if _in_it(p.global_position) else 0
	p.touch_move = Vector2.ZERO
	check_eq(inside, 0, "it never went in")
	for q in s.pieces:
		check_eq(s.harm[q], 0.0, "piece %d took nothing" % q)
	check_eq(s.standing_count, s.pieces, "everything stands")
	check_eq(s.rubble.live, 0, "nothing came off")
	await _unload()


func test_a_pane_bursts_at_a_blow_and_a_post_of_its_foot_bows_before_it_gives() -> void:
	await _load()
	var pane := main.tower_panes[0]
	check(
		s.strike(s.place[pane].origin, _turned(Vector3.FORWARD), 2, s.body_of(pane)), "a blow lands on a pane"
	)
	check_eq(s.state[pane], Structure.BROKEN, "it bursts")
	check_eq(s.standing_count, s.pieces - 1, "nothing else goes")
	check_eq(s.rubble.live, 0, "into glitter: no loose body")
	# A post of its foot, struck where a straight lands: it bows, its head
	# where it was, as long as it holds.
	var post := main.tower_posts[1]
	var blows := 0
	while s.harm[post] + 2.0 < s.strength[post]:
		s.hit(post, 2.0, _turned(Vector3.FORWARD), _at_fist(post))
		blows += 1
	check_eq(blows, 5, "five straights")
	check_eq(s.state[post], Structure.STANDS, "it still stands")
	check(s.bend[post].bows, "bowed (it carries a deck)")
	var rings := s.bend[post].ring_poses()
	var head := rings[rings.size() - 1].origin
	check(
		head.distance_to(s.place[post].origin + Vector3.UP * s.size[post].y * 0.5) < 0.01,
		"its head where it was"
	)
	var aside := 0.0
	for ring in rings:
		var off := ring.origin - s.place[post].origin
		aside = maxf(aside, Vector2(off.x, off.z).length())
	check(aside > 0.15, "and bowed %.2f m aside" % aside)
	check_eq(s.standing_count, s.pieces - 1, "everything else stands")
	await _unload()


func test_when_a_post_of_its_foot_gives_the_glass_bursts_and_the_frame_lies_down_in_one() -> void:
	await _load()
	var post := main.tower_posts[1]
	var blows := 0
	while s.state[post] == Structure.STANDS and blows < 20:
		s.hit(post, 2.0, _turned(Vector3.FORWARD), _at_fist(post))
		blows += 1
	check_eq(blows, 6, "it gives at the sixth straight")
	# At once: every deck sags or comes down, every post over the ground
	# has lost its footing, every pane over the ground has burst.
	for deck in main.tower_decks:
		check_eq(s.state[deck], Structure.FALLS, "deck %d has come loose" % deck)
	for k in main.tower_posts.size():
		var q := main.tower_posts[k]
		var stands := k < 4 and q != post
		check_eq(s.state[q], Structure.STANDS if stands else Structure.FALLS, "post %d: as it should be" % q)
	for k in main.tower_panes.size():
		var q := main.tower_panes[k]
		check(k < 4 or s.state[q] == Structure.BROKEN, "pane %d, over the ground, has burst" % q)
	# In one: the first deck hangs from the three posts that stand, and
	# every body of the frame rests and moves with all the others.
	var hangs := 0
	for k in 4:
		hangs += s._ties[main.tower_posts[k]].size()
	check_eq(hangs, 3, "the first deck hangs from the three posts that stand")
	var groups := {}
	var bodies := 0
	for q in _metal():
		for i in s._loose[q]:
			groups[s.rubble.joined[i]] = true
			bodies += 1
	check(bodies >= 4 * 2 + 13, "the frame is %d loose bodies" % bodies)
	check(groups.size() == 1 and not groups.has(-1), "all of them in one")
	check(await _rest(1500), "everything comes to rest")
	# It lies low, by where it stood, and still in one: each post over the
	# ground is by the deck it stood on and by the one it carried, where
	# they met.
	var lies := _lies()
	check(lies.x < 2.6, "nothing is left higher than its first storey was (%.2f m at the highest)" % lies.x)
	check(lies.y < 8.5, "it lies within its own height of where it stood (%.1f m)" % lies.y)
	var widest := 0.0
	for k in range(4, main.tower_posts.size()):
		var q := main.tower_posts[k]
		var under := main.tower_decks[k / 4 - 1]
		var over := main.tower_decks[k / 4]
		widest = maxf(widest, _apart(q, under))
		widest = maxf(widest, _apart(over, q))
	widest = maxf(widest, _apart(main.tower_decks[0], post))
	check(widest < 0.4, "no post has come away from a deck it was fixed to (%.2f m at the most)" % widest)
	for k in 4:
		var q := main.tower_posts[k]
		check(q == post or s.state[q] == Structure.STANDS, "post %d of its foot still stands" % q)
	for q in s.pieces:
		check(q in _tower() or s.harm[q] == 0.0, "piece %d, not of the tower, took nothing" % q)
	await _unload()


func test_whichever_post_of_its_foot_gives_it_lies_down_and_comes_to_rest() -> void:
	for k in 4:
		await _load()
		var post := main.tower_posts[k]
		var at := _laid(s.place[post].origin)
		# (Struck towards the middle of the tower, or along its front.)
		var way := Vector3(-signf(at.x), 0, -signf(at.z)).normalized()
		if k % 2 == 1:
			way = Vector3(0, 0, -signf(at.z))
		var blows := 0
		while s.state[post] == Structure.STANDS and blows < 20:
			s.hit(post, 2.0, _turned(way), _bench(Vector3(at.x, 1.4, at.z)))
			blows += 1
		check_eq(blows, 6, "post %d gives at the sixth straight" % k)
		var low := -1
		var rested := -1
		for step in 900:
			await frames(1)
			if low < 0 and step % 10 == 0 and _lies().x < 2.6:
				low = step
			if s.rubble.awake == 0:
				rested = step
				break
		check(low >= 0 and low <= 360, "it is down within six seconds (%d steps)" % low)
		check(rested >= 0, "and at rest within fifteen")
		check(_lies().y < 8.5, "within its own height of where it stood (%.1f m)" % _lies().y)
		var widest := _apart(main.tower_decks[0], post)
		for j in range(4, main.tower_posts.size()):
			widest = maxf(widest, _apart(main.tower_posts[j], main.tower_decks[j / 4 - 1]))
			widest = maxf(widest, _apart(main.tower_decks[j / 4], main.tower_posts[j]))
		check(widest < 0.4, "still in one (%.2f m at the most between a post and its deck)" % widest)
		for j in 4:
			check(j == k or s.state[main.tower_posts[j]] == Structure.STANDS, "post %d still stands" % j)
		await _unload()


func test_the_brute_brings_the_tower_down_at_one_post() -> void:
	await _load()
	var thrown := [0]
	p.blow.connect(func(_at: Vector3, _way: Vector3, _power: int, _on: RID) -> void: thrown[0] += 1)
	var post := main.tower_posts[1]
	var foot := _laid(s.place[post].origin)
	_face(_bench(Vector3(foot.x, 0.05, foot.z + 0.7)), _bench(Vector3(foot.x, 1.0, foot.z)))
	await frames(5)
	for step in 2400:
		var down := s.state[post] != Structure.STANDS
		if (down or thrown[0] >= 14) and not p.character.striking():
			break
		if step % 6 == 0 and not down and thrown[0] < 14:
			p.punch()
		await frames(1)
	# (Six straights on it. The leap that ends a combination lands over the
	# post, and bowed, the post is no longer where some of the others land.)
	check(s.state[post] != Structure.STANDS, "the post gives (%d blows)" % thrown[0])
	check(thrown[0] <= 12, "within four combinations")
	for deck in main.tower_decks:
		check(s.state[deck] != Structure.STANDS, "deck %d has come loose" % deck)
	await frames(240)
	check(
		p.global_position.is_finite() and p.global_position.y > -0.1 and p.global_position.y < 2.5,
		"the brute is on the ground or on what came down (%.2f m up)" % p.global_position.y
	)
	# (What lies against the brute is not left to rest: it is taken away.)
	p.set_down(_bench(Vector3(0, 0.05, 12)))
	check(await _rest(2400), "everything comes to rest")
	var lies := _lies()
	check(lies.x < 3.6, "nothing is left as high as its second storey was (%.2f m at the highest)" % lies.x)
	check(lies.y < 8.5, "it lies within its own height of where it stood (%.1f m)" % lies.y)
	for q in s.pieces:
		check(q in _tower() or s.harm[q] == 0.0, "piece %d, not of the tower, took nothing" % q)
	await _unload()


func test_on_the_bench_too_a_post_that_gives_stays_fixed_to_the_deck_it_carried() -> void:
	await _load()
	var gone := main.piers[0]
	s.hit(gone, s.strength[gone], Vector3.LEFT, s.place[gone].origin)
	check(s.state[gone] != Structure.STANDS, "a post under the deck gives")
	check(s.state[main.deck] != Structure.STANDS, "the deck sags")
	var group := s.rubble.joined[s._loose[gone][0]]
	check(group >= 0 and group == s.rubble.joined[s._loose[main.deck][0]], "they rest and move as one")
	check(await _rest(1800), "everything comes to rest")
	var apart := _apart(main.deck, gone)
	check(apart < 0.4, "the head of the post is still by the corner of the deck (%.2f m)" % apart)
	await _unload()


## How far apart the pieces `top` and `under`, which are metal and have
## come down, now are where the first stood on the second (m): how far
## the point they were fixed at has gone with the one, from where it has
## gone with the other.
func _apart(top: int, under: int) -> float:
	var touch := s._face(top, -1.0).intersection(s._face(under, 1.0)).get_center()
	var at := s._seat(top, under, touch)
	var mine := s._loose[top][s._part(top, touch, true)]
	var other := s._loose[under][s._part(under, touch, false)]
	return _gone_with(mine, at).distance_to(_gone_with(other, at))


## Where the point `at`, as the bench was laid, has gone with the loose
## body `i`.
func _gone_with(i: int, at: Vector3) -> Vector3:
	return s.rubble.transform_of(i) * (at - s.rubble.origin[i])


## How high what lies loose lies at the highest, and how far from the
## middle of the tower at the farthest (m, seen from above).
func _lies() -> Vector2:
	var high := 0.0
	var far := 0.0
	for i in s.rubble.body.size():
		if s.rubble.alive[i] == 1:
			var at := _laid(s.rubble.transform_of(i).origin)
			high = maxf(high, at.y)
			far = maxf(far, Vector2(at.x, at.z).length())
	return Vector2(high, far)


## Every piece of the tower.
func _tower() -> Array[int]:
	var all: Array[int] = []
	all.assign(main.tower_pieces())
	return all


## Its posts and its decks.
func _metal() -> Array[int]:
	var all: Array[int] = []
	all.assign(main.tower_posts)
	for deck in main.tower_decks:
		all.append(deck)
	return all


## The numbers `of`, in order.
func _sorted(of: PackedInt32Array) -> Array:
	var all := Array(of)
	all.sort()
	return all


## Where a straight of the brute lands on post `q` of the foot of the
## tower: 1.4 m up, on the face of it that looks out of the front.
func _at_fist(q: int) -> Vector3:
	return tower * (s._within[q].origin + Vector3(0, 1.4 - s.size[q].y * 0.5, Main.TOWER_POST * 0.5))


## Is the point `at` of the bench inside the foot of the tower, seen from
## above?
func _in_it(at: Vector3) -> bool:
	var off := _laid(at)
	return maxf(absf(off.x), absf(off.z)) < Main.TOWER * 0.5


## Where the point `of` the tower as it is laid out is on the bench.
func _bench(of: Vector3) -> Vector3:
	return tower * of


## Where the point `at` of the bench is in the tower as it is laid out.
func _laid(at: Vector3) -> Vector3:
	return tower.affine_inverse() * at


## The way `of` the tower as it is laid out, on the bench.
func _turned(of: Vector3) -> Vector3:
	return tower.basis * of


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
	tower = main.tower_frame()


func _unload() -> void:
	main.queue_free()
	await frames(2)
