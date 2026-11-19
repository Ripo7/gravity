class_name Structure
extends Node3D
## What stands and can be broken. It is made of pieces (a column, a slab, a
## panel of a wall): each one an upright box of one matter, which alone says
## how the piece answers a blow (Matter, docs/CONCEPT.md).
##
## A blow harms the place it lands on, not the whole piece. A piece has a
## strength of its own (Matter.strength), however it is cut or drawn: that
## is what one place of it takes before it gives.
##
## What breaks (concrete) was cut into a few blocks when it was made
## (Fracture). The blocks round the place that is struck show cracks, for
## all to see; when the place has taken what the piece can take they are
## knocked out, away from the blow: loose bodies (Rubble), and a hole.
## The rest stands as long as it holds together with something that
## stands. What is cut off from below, or no longer in balance, comes
## down in one and breaks into its blocks when it lands.
##
## What bends (metal) never breaks. A blow leaves its mark where it lands,
## away from the blow, and the piece keeps it: a post kinks at that height,
## a sheet takes a dent under the fist (Bend). Marked as deep as it goes in
## one place, it lies down: a sheet as one loose body, a post as its limbs,
## which fold at its kinks under what bears on them, so that a post never
## stays up under what it carried.
##
## What is no longer carried comes down: a piece rests on the pieces right
## under it, and when what is left of them no longer holds it up it falls,
## in one piece; what breaks, breaks when it lands. A metal plate does not
## wait for that: as soon as one of the pieces under it goes, it sags
## there, and folds as it comes down. Only a blow breaks or bends: from the
## brute (`strike`), or from something heavy landing on a piece (Rubble).

## What a piece is doing: some of it stands; none of it does, and some of
## it lies in one (all of it, if it is metal); it is all in blocks.
enum { STANDS, FALLS, BROKEN }

## Two pieces closer than this (m) touch; a piece this close to the ground
## stands on it.
const TOUCH := 0.03
## The collision shape of a block is a little smaller than the block:
## blocks that were one piece a moment ago do not start out pressed
## against each other.
const SHRINK := 0.96
## A piece that breaks shows cracks once it has taken a blow; from SPLIT of
## its strength on, wide ones. Each block is then drawn that much smaller
## (CRACKS, by how cracked: 0 not, 1, 2) and turned by up to TILT rad, so
## that the cuts between the blocks show.
const SPLIT := 0.5
const CRACKS: Array[float] = [1.0, 0.975, 0.94]
const TILT: Array[float] = [0.0, 0.012, 0.035]
## A fist is this wide (m): a blow that meets nothing on its way still
## lands on what stands within that of where it ends, and sends off what
## lies loose within REACH.
const FIST := 0.3
const REACH := 0.7
## How far across a place of concrete is (m, see Matter.PLACE).
const HOLE := 0.45
## Blocks of a wall with nothing under them hold, side by side, between
## two that sit, if those are no farther apart than LINTEL m: over the
## hole one blow makes, not over two side by side.
const LINTEL := 1.25
## What a blow cuts off from below goes over: it starts off turning about
## its foot at TOPPLE rad/s, away from the blow. (Left to drop straight,
## it lands on what it stood on and stays there, a cut column still
## standing.) So does metal that lies down, and a piece that is broken
## all at once. Each block that comes off also gets up to SCATTER m/s of
## its own. Both as at real gravity.
const TOPPLE := 2.5
const SCATTER := 0.4
## The triangles of a plate are this much smaller than drawn, as bodies:
## two that only meet at a corner do not start out pressed together.
const TILE := 0.97

## How many pieces there are, and per piece: what it is made of, its size,
## where its middle is, what one place of it takes, what it has taken
## where it has taken the most, what it is doing, how cracked it shows
## where it shows it the most (0 to 2), its parts in the mesh (the first,
## and how many: blocks if it breaks, rings or nodes if it bends).
var pieces := 0
var matter := PackedInt32Array()
var size := PackedVector3Array()
var place: Array[Transform3D] = []
var strength := PackedFloat32Array()
var harm := PackedFloat32Array()
var state := PackedByteArray()
var cracks := PackedByteArray()
var first := PackedInt32Array()
var blocks := PackedInt32Array()
## The pieces each piece rests on, and those that rest on it.
var rests_on: Array[PackedInt32Array] = []
var carries: Array[PackedInt32Array] = []
## Per piece that bends: how it is bent (null for a piece that breaks).
## Its harm is what it has taken where it has taken the most.
var bend: Array[Bend] = []
## How many parts there are in the mesh, and per part: where it stood (its
## centre of mass, or the middle of a ring, or a node), its volume, its
## piece, and whether it still stands in it (a block).
var count := 0
var centroid := PackedVector3Array()
var volume := PackedFloat32Array()
var piece_of := PackedInt32Array()
var stands := PackedByteArray()
var mesh: ShardMesh
var rubble: Rubble
## What glass turns into when it bursts.
var glitter: Glitter
## The cut depends on it: another number, other blocks.
var cut_seed := 1
## How many pieces still stand.
var standing_count := 0

var _shows := PackedByteArray()  # per block: how cracked it shows (0 to 2)
var _bonds: Array[PackedInt32Array] = []  # per block: the blocks of its piece it was cut from
var _foot: Array[Rect2] = []  # per block: where it is at the underside of its piece (x and z), if it is
var _head: Array[Rect2] = []  # per block: the same at the top of its piece
var _sits_on: Array[PackedInt32Array] = []  # per block of an upright piece: the blocks right under it
var _beside: Array[PackedInt32Array] = []  # per block of an upright piece: those right beside it, one way
var _other_side: Array[PackedInt32Array] = []  # and the other way
var _reach: Array[Vector2] = []  # per block of an upright piece: from where to where it goes along it
var _wound_at: Array[PackedVector3Array] = []  # per piece: the places it has been struck at
var _wound_harm: Array[PackedFloat32Array] = []  # per piece: what each of them has taken
var _whole := PackedFloat32Array()  # per piece: what it has taken nowhere in particular
var _clumps := {}  # loose body -> the blocks it is made of, lying in one
var _clump_harm := {}  # loose body -> the blows it has taken since
var _corners: Array[PackedVector3Array] = []  # per block: its collision corners, around its centre
var _radius := PackedFloat32Array()  # per block: how far its corners are from its centre
var _hull: Array[RID] = []  # per block: its collision shape, once it is needed
var _box: Array[RID] = []  # per piece: its collision shape as it was built
var _limbs: Array[Array] = []  # per post that has been kinked: the shapes of its limbs
var _made: Array[RID] = []  # the shapes of metal that has lain down: sheets, the triangles of plates
var _body: Array[RID] = []  # per piece: its static body while it stands
var _in_body: Array[PackedInt32Array] = []  # per piece: the blocks its body is made of, once not its box
var _loose: Array[PackedInt32Array] = []  # per piece: its bodies in the rubble once it has come down
var _ties: Array[Array] = []  # per piece that stands: what ties to it a plate that has come loose
var _by_body := {}  # RID -> piece that stands
var _built := false


func _init() -> void:
	mesh = ShardMesh.new()
	add_child(mesh)
	glitter = Glitter.new()
	add_child(glitter)
	rubble = Rubble.new()
	rubble.structure = self
	add_child(rubble)


func _exit_tree() -> void:
	# (The rubble has freed its bodies: children leave first.)
	for rid in _body:
		if rid.is_valid():
			PhysicsServer3D.free_rid(rid)
	for rid in _box:
		PhysicsServer3D.free_rid(rid)
	for limbs in _limbs:
		for rid: RID in limbs:
			PhysicsServer3D.free_rid(rid)
	for rid in _made:
		PhysicsServer3D.free_rid(rid)
	for rid in _hull:
		if rid.is_valid():
			PhysicsServer3D.free_rid(rid)


## Adds a piece made `of` a matter: an upright box of `box` size, its
## middle at `xf`. Call build() once every piece is in. Returns its number.
func add_piece(of: int, xf: Transform3D, box: Vector3) -> int:
	var p := pieces
	pieces += 1
	matter.append(of)
	size.append(box)
	place.append(xf)
	strength.append(Matter.strength(of, box))
	harm.append(0.0)
	state.append(STANDS)
	cracks.append(0)
	first.append(count)
	rests_on.append(PackedInt32Array())
	carries.append(PackedInt32Array())
	bend.append(null)
	_wound_at.append(PackedVector3Array())
	_wound_harm.append(PackedFloat32Array())
	_whole.append(0.0)
	_loose.append(PackedInt32Array())
	_limbs.append([])
	_ties.append([])
	_in_body.append(PackedInt32Array())
	if Matter.BENDS[of]:
		blocks.append(_add_skin(p))
	else:
		blocks.append(_add_blocks(p))
	return p


## Puts up what was added: nothing can be added after this.
func build() -> void:
	mesh.build(count)
	var space := get_world_3d().space
	for p in pieces:
		var shape := PhysicsServer3D.box_shape_create()
		PhysicsServer3D.shape_set_data(shape, size[p] * 0.5)
		_box.append(shape)
		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_add_shape(body, shape)
		PhysicsServer3D.body_set_collision_layer(body, Layers.STRUCTURE)
		PhysicsServer3D.body_set_collision_mask(body, 0)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, place[p])
		PhysicsServer3D.body_set_space(body, space)
		_body.append(body)
		_by_body[body] = p
	# Who rests on whom: a piece whose foot is on the head of another.
	for a in pieces:
		var low := _bounds(a)
		for b in pieces:
			if a == b:
				continue
			var under := _bounds(b)
			if absf(low.position.y - under.end.y) < TOUCH and _contact(low, under).has_area():
				rests_on[a].append(b)
				carries[b].append(a)
	standing_count = pieces
	_built = true


## The piece that stands whose body `rid` is, or -1.
func standing(rid: RID) -> int:
	return _by_body.get(rid, -1)


## A blow of the brute lands at `at`: its fist or foot touched the body
## `on` there, thrown along `way`, `power` hard. That takes it. If it
## touched nothing (`on` empty: `at` is where it ended), what a fist, as
## wide as it is, touches there does. What lies loose near there is sent
## off. Returns true if it met something.
func strike(at: Vector3, way: Vector3, power: int, on := RID()) -> bool:
	var found: Array[RID] = []
	if on.is_valid():
		found.append(on)
	else:
		var ball := SphereShape3D.new()
		ball.radius = FIST
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = ball
		query.transform = Transform3D(Basis(), at)
		query.collision_mask = Layers.STRUCTURE | Layers.RUBBLE
		for touched in get_world_3d().direct_space_state.intersect_shape(query, 8):
			found.append(touched["rid"])
	# One thing takes the blow: a piece that stands, rather than what lies.
	var taker := -1
	var lies := -1
	for rid in found:
		taker = standing(rid)
		if taker >= 0:
			break
		if lies < 0:
			lies = rubble.index_of(rid)
	rubble.shove(at, REACH, way, power)
	if taker >= 0:
		hit(taker, power, way, at)
	elif _clumps.has(lies):
		# Blocks that lie there in one: they come apart once they have
		# taken what their piece can.
		_clump_harm[lies] = _clump_harm.get(lies, 0.0) + power
		if _clump_harm[lies] >= strength[piece_of[_clumps[lies][0]]]:
			break_up(lies)
	return not found.is_empty()


## Piece `p` takes `points` of blows, from something going along `way`, at
## `at` (nowhere in particular, if that is not told: the whole piece takes
## it). What breaks cracks round there, and the blocks round there are
## knocked out when the place has taken all it can; what bends is marked
## that much deeper there, and lies down when it is marked as deep as it
## goes.
func hit(p: int, points: float, way := Vector3.ZERO, at := Vector3.INF) -> void:
	if state[p] == BROKEN:
		return
	if Matter.BURSTS[matter[p]]:
		if points > 0.0:
			_burst(p)
		return
	if bend[p] != null:
		# (Once it lies there, it has its shape for good.)
		if state[p] == STANDS:
			_bend(p, points, way, at)
		return
	if state[p] != STANDS or not at.is_finite():
		_whole[p] += points
		harm[p] = maxf(harm[p], _whole[p])
		if _whole[p] >= strength[p]:
			shatter(p, way)
		else:
			for i in range(first[p], first[p] + blocks[p]):
				if stands[i] == 1:
					_crack(i, 2 if _whole[p] >= strength[p] * SPLIT else 1)
		return
	# That place takes it, on top of what it has taken already.
	var w := _wound(p, at)
	_wound_harm[p][w] += points
	var taken := _wound_harm[p][w] + _whole[p]
	harm[p] = maxf(harm[p], taken)
	var there := _wound_at[p][w]
	var near := _around(p, there)
	if taken < strength[p]:
		for i in near:
			_crack(i, 2 if taken >= strength[p] * SPLIT else 1)
		return
	# It gives: the blocks round it are knocked out, and what they held
	# up comes down.
	_wound_at[p].remove_at(w)
	_wound_harm[p].remove_at(w)
	for i in near:
		_expel(i, way)
	_refresh(p)
	rubble.thaw_in(AABB(there, Vector3.ZERO).grow(HOLE + 0.6))
	_settle(p, way)


## Piece `p` breaks into its blocks all at once, where it is: what stands
## of it goes over along `way` and comes apart, what lies in one comes
## apart. What it carried comes down if nothing else holds it. (Not what
## bends: it never breaks.)
func shatter(p: int, way := Vector3.ZERO) -> void:
	if state[p] == BROKEN or bend[p] != null:
		return
	if Matter.BURSTS[matter[p]]:
		_burst(p)
		return
	for lying in _loose[p].duplicate():
		break_up(lying)
	if state[p] != STANDS:
		return
	var slow := sqrt(rubble.fall)
	var over := _over(way) * slow
	var foot := place[p].origin - Vector3.UP * size[p].y * 0.5
	var under := _carries(p)
	for i in range(first[p], first[p] + blocks[p]):
		if stands[i] == 0:
			continue
		stands[i] = 0
		var own := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 2.0 * SCATTER * slow
		var block := _free(
			i, Transform3D(Basis(), centroid[i]), over.cross(centroid[i] - foot) + own, over + own
		)
		if under:
			rubble.slip(block)
	_refresh(p)
	_let_go(p)


## Piece `p`, of a matter that bursts (glass), is gone all at once: what
## it was made of is no longer drawn nor in anything's way, and its bits
## fall as glitter, which are not bodies.
func _burst(p: int) -> void:
	harm[p] = strength[p]
	for i in range(first[p], first[p] + blocks[p]):
		if stands[i] == 1:
			stands[i] = 0
			mesh.set_slot(i, 1 + i)
			mesh.set_body(1 + i, Transform3D(Basis(), centroid[i]), centroid[i], 0.0)
	glitter.burst(place[p], size[p], Matter.TINT[matter[p]], rubble.fall)
	_refresh(p)
	_let_go(p)


## Loose body `lying` of the rubble, blocks that came down in one, has
## landed hard: it breaks into them, if it is of a matter that does.
func lands(lying: int) -> void:
	if _clumps.has(lying) and Matter.SHATTERS[matter[piece_of[_clumps[lying][0]]]]:
		break_up(lying)


## Loose body `lying` of the rubble, blocks that came down in one, breaks
## into them where it is (it has landed hard, or been struck enough).
func break_up(lying: int) -> void:
	if not _clumps.has(lying):
		return
	var chunk: PackedInt32Array = _clumps[lying]
	var p := piece_of[chunk[0]]
	_clumps.erase(lying)
	_clump_harm.erase(lying)
	_loose[p].remove_at(_loose[p].find(lying))
	if chunk.size() == 1:
		# (One block: the body it has will do.)
		rubble.piece[lying] = -1
	else:
		var xf := rubble.transform_of(lying)
		var now := xf * Transform3D(Basis(), -rubble.origin[lying])
		var lin := rubble.velocity_of(lying)
		var ang := rubble.spin_of(lying)
		rubble.remove(lying)
		var slow := sqrt(rubble.fall)
		for i in chunk:
			var at := now * centroid[i]
			var own := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 2.0 * SCATTER * slow
			_free(i, Transform3D(now.basis, at), lin + ang.cross(at - xf.origin) + own, ang + own)
	if state[p] == FALLS and _loose[p].is_empty():
		state[p] = BROKEN


## Cuts piece `p`, which breaks, into its blocks. Returns how many.
func _add_blocks(p: int) -> int:
	var xf := place[p]
	var cut := Fracture.cut(size[p], Matter.grain(matter[p], size[p]), cut_seed * 7919 + p * 104729, 0.0)
	var base := count
	var tint := Matter.TINT[matter[p]]
	if matter[p] == Matter.WOOD:
		# (Planks side by side are told apart: each its own shade.)
		tint = tint.darkened(0.14 * float(p % 3) / 2.0)
	for sh in cut:
		var c := xf * sh.centroid
		var world := PackedVector3Array()
		var around := PackedVector3Array()
		var far := 0.0
		for point in sh.points:
			var w := xf * point
			world.append(w)
			around.append((w - c) * SHRINK)
			far = maxf(far, w.distance_to(c))
		mesh.add_shard(count, base, world, sh, xf.basis, tint)
		var i := count
		_add_part(p, c, sh.volume, around, far)
		for f in sh.faces.size():
			var other := sh.others[f]
			if other >= 0:
				_bonds[i].append(base + other)
			elif other == -3 or other == -4:
				# A face of the underside of the piece (-3), or of its top.
				var corner := world[sh.faces[f][0]]
				var over := Rect2(corner.x, corner.z, 0, 0)
				for c2 in sh.faces[f]:
					over = over.expand(Vector2(world[c2].x, world[c2].z))
				if other == -3:
					_foot[i] = over
				else:
					_head[i] = over
	if Matter.upright(size[p]):
		_lay_courses(p, base, cut)
	return cut.size()


## Works out, for each block of upright piece `p` (its blocks numbered
## from `base`, as `cut`), which block is right under it and which are
## right beside it, on each side. Under: of the blocks cut from it that
## are lower, the one that is under the most of it, along the piece.
## Beside: cut from it, and level with at least half of it (of the lower
## of the two).
func _lay_courses(p: int, base: int, cut: Array[Fracture.Shard]) -> void:
	var along := 0 if size[p].x >= size[p].z else 2
	var reach: Array[Vector2] = []  # per block: from where to where it goes along the piece
	var rise: Array[Vector2] = []  # and from how high to how high
	for sh in cut:
		var wide := Vector2(INF, -INF)
		var high := Vector2(INF, -INF)
		for point in sh.points:
			wide = Vector2(minf(wide.x, point[along]), maxf(wide.y, point[along]))
			high = Vector2(minf(high.x, point.y), maxf(high.y, point.y))
		reach.append(wide)
		rise.append(high)
		_reach[base + reach.size() - 1] = wide
	for k in cut.size():
		var i := base + k
		var best := -1
		var best_over := 0.0
		for other in _bonds[i]:
			var o := other - base
			var over := minf(reach[k].y, reach[o].y) - maxf(reach[k].x, reach[o].x)
			var level := minf(rise[k].y, rise[o].y) - maxf(rise[k].x, rise[o].x)
			var lower := minf(rise[k].y - rise[k].x, rise[o].y - rise[o].x)
			if cut[o].centroid.y < cut[k].centroid.y and over > best_over:
				best = other
				best_over = over
			if level >= lower * 0.5:
				if cut[o].centroid[along] < cut[k].centroid[along]:
					_beside[i].append(other)
				else:
					_other_side[i].append(other)
		if best >= 0 and not _foot[i].has_area():
			_sits_on[i].append(best)


## Draws piece `p`, which bends: the parts its skin is stretched between
## (Bend). Returns how many.
func _add_skin(p: int) -> int:
	var b := Bend.new(size[p], place[p], strength[p])
	bend[p] = b
	b.draw(mesh, count, Matter.TINT[matter[p]])
	for k in b.parts:
		_add_part(p, b.rest(k), 0.0, PackedVector3Array(), 0.0)
	return b.parts


## One more part of the mesh, of piece `p`.
func _add_part(p: int, at: Vector3, of_volume: float, around: PackedVector3Array, far: float) -> void:
	centroid.append(at)
	volume.append(of_volume)
	piece_of.append(p)
	stands.append(1)
	_shows.append(0)
	_bonds.append(PackedInt32Array())
	_foot.append(Rect2())
	_head.append(Rect2())
	_sits_on.append(PackedInt32Array())
	_beside.append(PackedInt32Array())
	_other_side.append(PackedInt32Array())
	_reach.append(Vector2.ZERO)
	_corners.append(around)
	_radius.append(far)
	_hull.append(RID())
	count += 1


## How a piece that stood goes over when it gives to something going along
## `way` (any way, if that is not told): the turn it starts off with, about
## its foot, as at real gravity.
func _over(way: Vector3) -> Vector3:
	var flat := Vector3(way.x, 0.0, way.z)
	if flat.length() < 0.1:
		flat = Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	return Vector3.UP.cross(flat.normalized()) * TOPPLE


## Is something still on piece `p` (standing, or on its way down)?
func _carries(p: int) -> bool:
	for q in carries[p]:
		if state[q] != BROKEN:
			return true
	return false


## Piece `p`, which stood, is on its own from now on.
func _leave(p: int) -> void:
	for tie: RID in _ties[p]:
		rubble.release(tie)
	_ties[p].clear()
	_by_body.erase(_body[p])
	PhysicsServer3D.free_rid(_body[p])
	_body[p] = RID()
	standing_count -= 1
	# What rested against it or on it, frozen, moves again.
	rubble.thaw_in(_bounds(p).grow(0.4))


## Does something bear on piece `p`: stand on it, or, come loose, still lie
## on its head?
func _loaded(p: int) -> bool:
	if carries[p].is_empty():
		return false
	if not _ties[p].is_empty():
		return true
	for q in carries[p]:
		if state[q] == STANDS:
			return true
	var box := BoxShape3D.new()
	box.size = Vector3(size[p].x, 0.1, size[p].z)
	var probe := PhysicsShapeQueryParameters3D.new()
	probe.shape = box
	probe.transform = Transform3D(place[p].basis, place[p].origin + Vector3.UP * (size[p].y * 0.5 + 0.06))
	probe.collision_mask = Layers.RUBBLE
	return not get_world_3d().direct_space_state.intersect_shape(probe, 1).is_empty()


## Block `i` is a loose body from now on, at `xf`, going at `lin` and
## turning at `ang`. Returns its number in the rubble.
func _free(i: int, xf: Transform3D, lin: Vector3, ang: Vector3) -> int:
	mesh.set_slot(i, 1 + i)
	return rubble.add(
		[[_shape_of(i), Transform3D.IDENTITY]],
		xf,
		centroid[i],
		volume[i] * Matter.DENSITY[matter[piece_of[i]]],
		_radius[i],
		lin,
		ang,
		[[1 + i, Transform3D(Basis(), centroid[i]), centroid[i]]]
	)


## Block `i`, which stood, is knocked out of its piece by something going
## along `way` (out from the middle of the piece, if that is not told:
## something came down on it).
func _expel(i: int, way: Vector3) -> void:
	var p := piece_of[i]
	var flat := Vector3(way.x, 0.0, way.z)
	if flat.length() < 0.1:
		flat = Vector3(centroid[i].x - place[p].origin.x, 0.0, centroid[i].z - place[p].origin.z)
		if flat.length() < 0.05:
			flat = Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
		if not Matter.upright(size[p]):
			# (Out of a slab, from above: it drops.)
			flat = Vector3.ZERO
	var slow := sqrt(rubble.fall)
	var own := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 2.0 * SCATTER * slow
	stands[i] = 0
	var out := flat.normalized() * Matter.KNOCK[matter[p]] * slow + own
	var block := _free(i, Transform3D(Basis(), centroid[i]), out, own)
	# (Whatever its shape, it gets clear of what is left of its piece; and
	# from under what the piece carried, it slides out.)
	rubble.let_through(block, p, Rubble.THROUGH)
	if _carries(p):
		rubble.slip(block)


## The body piece `p` stands with, if it still does.
func body_of(p: int) -> RID:
	return _body[p]


## The place of piece `p` that a blow at `at` lands on: one it has been
## struck at within what a place of its matter is across (Matter.PLACE)
## of there, or a new one. Returns its number.
func _wound(p: int, at: Vector3) -> int:
	var best := -1
	for w in _wound_at[p].size():
		var off := _wound_at[p][w].distance_to(at)
		if off <= Matter.PLACE[matter[p]] and (best < 0 or off < _wound_at[p][best].distance_to(at)):
			best = w
	if best < 0:
		best = _wound_at[p].size()
		_wound_at[p].append(at)
		_wound_harm[p].append(0.0)
	return best


## The blocks of piece `p` that stand round `at`: the nearest, and those
## whose middle is within what a place of its matter is across of it.
func _around(p: int, at: Vector3) -> PackedInt32Array:
	var near := PackedInt32Array()
	var nearest := -1
	for i in range(first[p], first[p] + blocks[p]):
		if stands[i] == 0:
			continue
		var off := centroid[i].distance_to(at)
		if nearest < 0 or off < centroid[nearest].distance_to(at):
			nearest = i
		if off <= Matter.PLACE[matter[p]]:
			near.append(i)
	if nearest >= 0 and not near.has(nearest):
		near.append(nearest)
	return near


## The blocks `among` (of one piece, which breaks) as the lumps they are
## in: blocks that hold together through the cuts between them.
func _lumps(among: PackedInt32Array) -> Array[PackedInt32Array]:
	var lumps: Array[PackedInt32Array] = []
	var left := {}
	for i in among:
		left[i] = true
	for from in among:
		if not left.has(from):
			continue
		var lump := PackedInt32Array([from])
		left.erase(from)
		var next := 0
		while next < lump.size():
			for other in _bonds[lump[next]]:
				if left.has(other):
					left.erase(other)
					lump.append(other)
			next += 1
		lumps.append(lump)
	return lumps


## The blocks of piece `p`, which breaks, that still stand.
func _standing_of(p: int) -> PackedInt32Array:
	var up := PackedInt32Array()
	for i in range(first[p], first[p] + blocks[p]):
		if stands[i] == 1:
			up.append(i)
	return up


## The blocks of piece `p`, an upright piece that breaks (a wall, a
## column), that nothing holds any more. A block holds if it sits on
## something: the ground or what stands under the piece, or a block right
## under it that sits. Or if it is in a row of blocks, side by side,
## between two that sit no more than LINTEL apart: the lintel over the
## hole of one blow. Over a wider hole, what is left comes down.
func _unheld(p: int) -> PackedInt32Array:
	var up: Array = Array(_standing_of(p))
	up.sort_custom(func(a: int, b: int) -> bool: return centroid[a].y < centroid[b].y)
	var on_ground := _bounds(p).position.y < TOUCH
	var heads: Array[Rect2] = []
	for q in rests_on[p]:
		heads.append_array(_heads(q))
	var sits := {}
	for i: int in up:
		if _foot[i].has_area() and (on_ground or not _meeting([_foot[i]], heads).is_empty()):
			sits[i] = true
		elif _any(_sits_on[i], sits):
			sits[i] = true
	var loose := PackedInt32Array()
	for i: int in up:
		if sits.has(i):
			continue
		# How far apart the nearest that sit are, on each side of it, along
		# the blocks level with it that stand.
		var from := _nearest_seat(i, _beside, sits)
		var to := _nearest_seat(i, _other_side, sits)
		if from < 0 or to < 0 or _reach[to].x - _reach[from].y > LINTEL:
			loose.append(i)
	return loose


## The block that sits (is in `sits`) nearest block `i` on one side, going
## from block to block level with it (`side`: `_beside` or `_other_side`)
## through those that stand; -1 if there is none.
func _nearest_seat(i: int, side: Array[PackedInt32Array], sits: Dictionary) -> int:
	var seen := {i: true}
	var row := PackedInt32Array([i])
	var next := 0
	while next < row.size():
		for other in side[row[next]]:
			if seen.has(other) or stands[other] == 0:
				continue
			if sits.has(other):
				return other
			seen[other] = true
			row.append(other)
		next += 1
	return -1


## Is one of `these` in `among`?
func _any(these: PackedInt32Array, among: Dictionary) -> bool:
	for i in these:
		if among.has(i):
			return true
	return false


## The blocks `chunk` of piece `p`, which stood, come down in one: a loose
## body from now on, that breaks into them when it lands (`break_up`).
## Cut off by a blow going along `way`, it starts off going over that way.
func _fall(p: int, chunk: PackedInt32Array, way: Vector3) -> void:
	var middle := Vector3.ZERO
	var total := 0.0
	var low := INF
	for i in chunk:
		middle += centroid[i] * volume[i]
		total += volume[i]
		low = minf(low, centroid[i].y - _radius[i])
	middle /= total
	var shapes: Array = []
	var far := 0.0
	var around := AABB(middle, Vector3.ZERO)
	for i in chunk:
		stands[i] = 0
		_shows[i] = 0
		# All of them move with the body of the first, as one.
		mesh.set_slot(i, 1 + chunk[0])
		shapes.append([_shape_of(i), Transform3D(Basis(), centroid[i] - middle)])
		far = maxf(far, centroid[i].distance_to(middle) + _radius[i])
		around = around.expand(centroid[i])
	if chunk.size() == blocks[p]:
		# (The whole piece: its box will do.)
		shapes = [[_box[p], Transform3D(place[p].basis, place[p].origin - middle)]]
	var turn := Vector3.ZERO
	var thrown := Vector3.ZERO
	if way != Vector3.ZERO:
		turn = _over(way) * sqrt(rubble.fall)
		# (What is light is thrown as well, a little up.)
		var flat := Vector3(way.x, 0.0, way.z).normalized()
		thrown = (flat + Vector3.UP * 0.25) * Matter.THROWN[matter[p]] * sqrt(rubble.fall)
	var lying := rubble.add(
		shapes,
		Transform3D(Basis(), middle),
		middle,
		total * Matter.DENSITY[matter[p]],
		far,
		turn.cross(middle - Vector3(middle.x, low, middle.z)) + thrown,
		turn,
		[[1 + chunk[0], Transform3D(Basis(), middle), middle]],
		p
	)
	_clumps[lying] = chunk
	_loose[p].append(lying)
	if _carries(p):
		rubble.slip(lying)
	_refresh(p)
	if _body[p].is_valid():
		# (Cut every which way, it would stay caught between what is left
		# of its piece: that does not stop it.)
		rubble.let_through(lying, p, INF)
	rubble.thaw_in(around.grow(far + 0.4))


## Piece `p`, which breaks, has lost blocks: what is left of it is what is
## in the way from now on. Nothing left, and it no longer stands.
func _refresh(p: int) -> void:
	var left := 0
	for i in range(first[p], first[p] + blocks[p]):
		left += stands[i]
	if left == 0:
		if state[p] == STANDS:
			_leave(p)
		state[p] = BROKEN if _loose[p].is_empty() else FALLS
		return
	if _in_body[p].is_empty():
		# Until now it was its box: from now on, the blocks that are left.
		PhysicsServer3D.body_clear_shapes(_body[p])
		var here := place[p].affine_inverse()
		for i in range(first[p], first[p] + blocks[p]):
			if stands[i] == 1:
				PhysicsServer3D.body_add_shape(
					_body[p], _shape_of(i), here * Transform3D(Basis(), centroid[i])
				)
				_in_body[p].append(i)
		return
	for k in range(_in_body[p].size() - 1, -1, -1):
		if stands[_in_body[p][k]] == 0:
			PhysicsServer3D.body_remove_shape(_body[p], k)
			_in_body[p].remove_at(k)


## Piece `p` has lost something, or something under it has: what of it is
## no longer held comes down, and so on up through what rests on it.
## `way`: where the blow that did it was going, if one did.
func _settle(p: int, way: Vector3) -> void:
	if state[p] == STANDS:
		if bend[p] != null:
			if not _held(p, PackedInt32Array()) or _sags(p):
				_drop(p, Vector3.ZERO)
		elif Matter.upright(size[p]):
			for lump in _lumps(_unheld(p)):
				_fall(p, lump, way)
		else:
			# What lies flat (a slab) holds in one, as long as its middle
			# is over what is left under it.
			for lump in _lumps(_standing_of(p)):
				if not _held(p, lump):
					_fall(p, lump, way)
	_let_go(p)


## What rests on piece `p` is looked at again: it comes down unless what
## is left under it still holds it.
func _let_go(p: int) -> void:
	for q in carries[p]:
		if state[q] == STANDS:
			_settle(q, Vector3.ZERO)


## Is piece `p` a metal plate with nothing left under it of one of the
## pieces it rested on? It does not balance on the others: it sags there.
func _sags(p: int) -> bool:
	if bend[p].kind != Bend.PLATE:
		return false
	var feet := _feet(p, PackedInt32Array())
	for q in rests_on[p]:
		if _meeting(feet, _heads(q)).is_empty():
			return true
	return false


## Piece `p`, which is metal and stood, comes down, in the shape it has:
## loose from now on, as many bodies as it can fold into. It starts off
## turning at `turn` about its foot.
func _drop(p: int, turn: Vector3) -> void:
	_leave(p)
	state[p] = FALLS
	var middle := place[p].origin
	var foot := middle - Vector3.UP * size[p].y * 0.5
	if bend[p].kind == Bend.POST:
		_drop_post(p, turn, foot)
	elif bend[p].kind == Bend.SHEET:
		# One body, as dented as it is: what holds its corners and its dents.
		var b := bend[p]
		var thick := b.normal * minf(size[p].x, size[p].z) * 0.5
		var around := PackedVector3Array()
		for k in b.parts:
			var corner := (k % b.across) % (b.across - 1) == 0 and (k / b.across) % (b.rows - 1) == 0
			if corner or absf(b.dent[k]) > 0.01:
				around.append(b.node(k) - middle + thick)
				around.append(b.node(k) - middle - thick)
			mesh.set_slot(first[p] + k, 1 + first[p])
		var sheet := rubble.add(
			[[_shape(around), Transform3D.IDENTITY]],
			Transform3D(Basis(), middle),
			middle,
			size[p].x * size[p].y * size[p].z * Matter.DENSITY[matter[p]],
			size[p].length() * 0.75,
			turn.cross(middle - foot),
			turn,
			[[1 + first[p], Transform3D(Basis(), middle), middle]],
			p
		)
		_loose[p] = PackedInt32Array([sheet])
	else:
		_drop_plate(p)


## A post lies down: each of its limbs a body, the rings of the limb with
## it. They fold at the joints between them.
func _drop_post(p: int, turn: Vector3, foot: Vector3) -> void:
	var b := bend[p]
	var poses := b.ring_poses()
	var limbs := _limbs_of(p, poses)
	var across := size[p].x * size[p].z
	var made := PackedInt32Array()
	for limb in limbs:
		var xf: Transform3D = limb[1]
		var long: float = limb[4]
		var rig: Array = []
		# (The ring at a joint goes with the limb under it.)
		var low: int = limb[2]
		for k in range(low + (1 if low > 0 else 0), limb[3] + 1):
			var i := first[p] + k
			mesh.set_slot(i, 1 + i)
			rig.append([1 + i, poses[k], centroid[i]])
		made.append(
			rubble.add(
				[[limb[0], Transform3D(xf.basis, Vector3.ZERO)]],
				Transform3D(Basis(), xf.origin),
				xf.origin,
				across * long * Matter.DENSITY[matter[p]],
				long * 0.5 + maxf(size[p].x, size[p].z),
				turn.cross(xf.origin - foot),
				turn,
				rig,
				p
			)
		)
	var holds := Matter.FOLD * maxf(size[p].x, size[p].z) * pow(minf(size[p].x, size[p].z), 2.0)
	for k in made.size() - 1:
		var at := poses[limbs[k][3]].origin
		var axis := (at - poses[limbs[k][2]].origin).cross(poses[limbs[k + 1][3]].origin - at)
		if axis.length() < 0.0001:
			axis = place[p].basis.x
		rubble.join(made[k], made[k + 1], at, axis, holds)
	_loose[p] = made


## A plate comes loose: each of its triangles a body, joined to the next
## along the line between them, where the plate folds.
func _drop_plate(p: int) -> void:
	var b := bend[p]
	var up := place[p].basis.y.normalized() * size[p].y * 0.5
	var taken := {}  # node -> a triangle moves it already
	var made := PackedInt32Array()
	for tile in b.tiles:
		var middle := (b.rest(tile[0]) + b.rest(tile[1]) + b.rest(tile[2])) / 3.0
		var around := PackedVector3Array()
		var far := 0.0
		var rig: Array = []
		for n in tile:
			var from := (b.rest(n) - middle) * TILE
			around.append(from + up)
			around.append(from - up)
			far = maxf(far, from.length())
			if not taken.has(n):
				taken[n] = true
				var i := first[p] + n
				mesh.set_slot(i, 1 + i)
				rig.append([1 + i, Transform3D(Basis(), centroid[i]), centroid[i]])
		var area := (
			(b.rest(tile[1]) - b.rest(tile[0])).cross(b.rest(tile[2]) - b.rest(tile[0])).length() * 0.5
		)
		made.append(
			rubble.add(
				[[_shape(around), Transform3D.IDENTITY]],
				Transform3D(Basis(), middle),
				middle,
				area * size[p].y * Matter.DENSITY[matter[p]],
				far,
				Vector3.ZERO,
				Vector3.ZERO,
				rig,
				p
			)
		)
	for fold in b.folds:
		var from := b.rest(fold[2])
		var to := b.rest(fold[3])
		var holds := Matter.FOLD * from.distance_to(to) * size[p].y * size[p].y
		rubble.join(made[fold[0]], made[fold[1]], (from + to) * 0.5, to - from, holds)
	_loose[p] = made
	# It stays tied to the pieces under it that still stand: it hangs
	# from them, and sags where there is none. (Tied at the height of its
	# folds: it can fold along a line that goes through there.)
	var feet := _feet(p, PackedInt32Array())
	for q in rests_on[p]:
		var meet := _meeting(feet, _heads(q))
		if meet.is_empty():
			continue
		var touch := meet[0].get_center()
		for t in b.tiles.size():
			var corners := PackedVector2Array()
			for n in b.tiles[t]:
				corners.append(Vector2(b.rest(n).x, b.rest(n).z))
			if Geometry2D.point_is_inside_triangle(touch, corners[0], corners[1], corners[2]):
				var at := Vector3(touch.x, place[p].origin.y, touch.y)
				_ties[q].append(rubble.tie(made[t], _body[q], at))
				break


## A collision shape that holds the points `around`, kept to be freed.
func _shape(around: PackedVector3Array) -> RID:
	var hull := PhysicsServer3D.convex_polygon_shape_create()
	PhysicsServer3D.shape_set_data(hull, around)
	_made.append(hull)
	return hull


## Does what is under the blocks `chunk` of piece `p` (all of `p`, if it
## is metal) hold them up? Their middle has to be over where they stand:
## on the ground, or on what stands at the top of the pieces `p` rests on.
func _held(p: int, chunk: PackedInt32Array) -> bool:
	var feet := _feet(p, chunk)
	var under: Array[Rect2] = []
	if _bounds(p).position.y < TOUCH:
		under = feet
	for q in rests_on[p]:
		under.append_array(_meeting(feet, _heads(q)))
	if under.is_empty():
		return false
	var corners := PackedVector2Array()
	for touch in under:
		corners.append(touch.position)
		corners.append(touch.end)
		corners.append(Vector2(touch.position.x, touch.end.y))
		corners.append(Vector2(touch.end.x, touch.position.y))
	var middle := Vector2(place[p].origin.x, place[p].origin.z)
	if not chunk.is_empty():
		var weighed := Vector3.ZERO
		var total := 0.0
		for i in chunk:
			weighed += centroid[i] * volume[i]
			total += volume[i]
		middle = Vector2(weighed.x, weighed.z) / total
	return Geometry2D.is_point_in_polygon(middle, Geometry2D.convex_hull(corners))


## Where the blocks `chunk` of piece `p` are at its underside, seen from
## above (all of its underside, if `p` is metal).
func _feet(p: int, chunk: PackedInt32Array) -> Array[Rect2]:
	var feet: Array[Rect2] = []
	if bend[p] != null:
		var box := _bounds(p)
		feet.append(Rect2(box.position.x, box.position.z, box.size.x, box.size.z))
	for i in chunk:
		if _foot[i].has_area():
			feet.append(_foot[i])
	return feet


## Where something still stands at the top of piece `q`, seen from above.
func _heads(q: int) -> Array[Rect2]:
	var heads: Array[Rect2] = []
	if state[q] != STANDS:
		return heads
	if bend[q] != null:
		var box := _bounds(q)
		heads.append(Rect2(box.position.x, box.position.z, box.size.x, box.size.z))
		return heads
	for i in range(first[q], first[q] + blocks[q]):
		if stands[i] == 1 and _head[i].has_area():
			heads.append(_head[i])
	return heads


## Where `feet` are over `heads`.
func _meeting(feet: Array[Rect2], heads: Array[Rect2]) -> Array[Rect2]:
	var meet: Array[Rect2] = []
	for foot in feet:
		for head in heads:
			var over := foot.intersection(head)
			if over.size.x > TOUCH and over.size.y > TOUCH:
				meet.append(over)
	return meet


## Block `i`, which stands, shows cracks: `level` 1, or 2 for wide ones.
## It is drawn on its own, a little smaller and askew. (Cracks do not
## close.)
func _crack(i: int, level: int) -> void:
	if _shows[i] >= level:
		return
	_shows[i] = level
	cracks[piece_of[i]] = maxi(cracks[piece_of[i]], level)
	# (Always the same way for the same block: wider cracks open the ones
	# that were there.)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(i * 7919 + cut_seed)
	var axis := Vector3(rng.randf() - 0.5, rng.randf() - 0.5, rng.randf() - 0.5).normalized()
	var askew := Basis(axis, TILT[level] * rng.randf_range(0.4, 1.0))
	mesh.set_slot(i, 1 + i)
	mesh.set_body(1 + i, Transform3D(askew, centroid[i]), centroid[i], CRACKS[level])


## Piece `p`, which stands and bends, takes `points` of blows from
## something going along `way`, at `at` if that is known: it is marked
## that much deeper there (Bend). A blow from the other side takes as much
## back. Marked as deep as it goes, it lies down.
func _bend(p: int, points: float, way: Vector3, at: Vector3) -> void:
	var b := bend[p]
	if b.kind == Bend.PLATE:
		# (It takes nothing from a blow: it sags when what holds it goes.)
		return
	b.strike(points, way, at, b.kind == Bend.POST and b.kink_at.is_empty() and _loaded(p))
	harm[p] = b.harm()
	var poses: Array[Transform3D] = []
	var down := false
	if b.kind == Bend.POST:
		poses = b.ring_poses()
		down = not b.bows and b.touches_ground(poses)
	if harm[p] >= strength[p] or down:
		_drop(p, _over(b.leans()) * sqrt(rubble.fall))
		_let_go(p)
		return
	# It stands, in its new shape: to the eye, and to what runs into it.
	if b.kind == Bend.SHEET:
		for k in blocks[p]:
			mesh.set_offset(first[p] + k, b.normal * b.dent[k])
		return
	for k in blocks[p]:
		var i := first[p] + k
		mesh.set_slot(i, 1 + i)
		mesh.set_body(1 + i, poses[k], centroid[i])
	PhysicsServer3D.body_clear_shapes(_body[p])
	var here := place[p].affine_inverse()
	for limb in _limbs_of(p, poses):
		PhysicsServer3D.body_add_shape(_body[p], limb[0], here * (limb[1] as Transform3D))


## The limbs of post `p` as its rings are in `poses`, between its foot,
## its kinks and its head: for each, its shape, where it is, its first
## ring and its last, how long it is. (One, as it was built, if it was
## never kinked.)
func _limbs_of(p: int, poses: Array[Transform3D]) -> Array[Array]:
	var joints := bend[p].joints()
	if bend[p].kink_at.is_empty():
		return [[_box[p], place[p], 0, joints[1], size[p].y]]
	var limbs: Array[Array] = []
	for k in joints.size() - 1:
		if _limbs[p].size() <= k:
			_limbs[p].append(PhysicsServer3D.box_shape_create())
		var from := poses[joints[k]].origin
		var along := poses[joints[k + 1]].origin - from
		var long := along.length()
		PhysicsServer3D.shape_set_data(_limbs[p][k], Vector3(size[p].x, long, size[p].z) * 0.5)
		var tilt := Vector3.UP.cross(along)
		var turned := place[p].basis
		if tilt.length() > 0.0001:
			turned = Basis(tilt.normalized(), Vector3.UP.angle_to(along)) * turned
		limbs.append([_limbs[p][k], Transform3D(turned, from + along * 0.5), joints[k], joints[k + 1], long])
	return limbs


## The collision shape of block `i`.
func _shape_of(i: int) -> RID:
	if not _hull[i].is_valid():
		_hull[i] = PhysicsServer3D.convex_polygon_shape_create()
		PhysicsServer3D.shape_set_data(_hull[i], _corners[i])
	return _hull[i]


## The box that holds piece `p` where it stood (pieces stand upright).
func _bounds(p: int) -> AABB:
	var half := size[p] * 0.5
	var box := AABB(place[p].origin, Vector3.ZERO)
	for x: float in [-half.x, half.x]:
		for z: float in [-half.z, half.z]:
			box = box.expand(place[p] * Vector3(x, -half.y, z))
			box = box.expand(place[p] * Vector3(x, half.y, z))
	return box


## Where two boxes are over one another, seen from above (x and z); nothing
## if they are not.
func _contact(a: AABB, b: AABB) -> Rect2:
	var over := Rect2(a.position.x, a.position.z, a.size.x, a.size.z).intersection(
		Rect2(b.position.x, b.position.z, b.size.x, b.size.z)
	)
	return over if over.size.x > TOUCH and over.size.y > TOUCH else Rect2()
