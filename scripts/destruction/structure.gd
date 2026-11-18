class_name Structure
extends Node3D
## What stands and can be broken. It is made of pieces (a column, a slab, a
## panel of a wall): each one an upright box of one matter, which alone says
## how the piece answers a blow (Matter, docs/CONCEPT.md).
##
## A piece takes blows as a whole: it has a strength of its own (Matter.
## strength) and gives when it has taken that much, however it is cut or
## drawn.
##
## What breaks (concrete) cracks until then, for all to see; when it lets
## go it breaks into the few blocks it was cut into when it was made
## (Fracture), which become loose bodies (Rubble).
##
## What bends (metal) never breaks. Each blow bends it a little more, away
## from the blow, where the first one landed; it keeps the shape. A piece
## that carries something keeps its head where it is and bows instead.
## Bent as far as it goes, it lies down: one loose body, in the shape it
## was bent to.
##
## What is no longer carried comes down: a piece rests on the pieces right
## under it, and when those that are left no longer hold it up it falls, in
## one piece; what breaks, breaks when it lands. Only a blow breaks or
## bends: from the brute (`strike`), or from something heavy landing on a
## piece (Rubble).

## What a piece is doing: it stands; it has come down in one piece (and
## lies there, if it is metal); it is in blocks.
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
## A piece that stood goes over as it lets go or lies down: it starts off
## turning about its foot at TOPPLE rad/s, away from the blow. What breaks
## comes apart as it goes down. (Left where they stood, blocks cut one on
## top of the other stay there, a broken column still standing.) Each
## block also gets up to SCATTER m/s of its own. Both as at real gravity.
const TOPPLE := 2.5
const SCATTER := 0.4
## The bend of a piece is not felt lower than this share of its height,
## nor higher than one less it.
const KNEE_LEAST := 0.2

## How many pieces there are, and per piece: what it is made of, its size,
## where its middle is, what it takes and has taken, what it is doing, how
## cracked it shows (0 to 2), its parts in the mesh (the first, and how
## many: blocks if it breaks, rings if it bends).
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
## Per piece that bends: which way and how much it has been bent (the
## blows it took, each as long as its points; their sum is its harm), how
## high above its foot the bend is (m; -1 until the first blow), and
## whether it bows (it carried something at that first blow).
var lean := PackedVector3Array()
var knee := PackedFloat32Array()
var bows := PackedByteArray()
## How many parts there are in the mesh, and per part: where it stood (its
## centre of mass, or the middle of a ring), its volume, its piece.
var count := 0
var centroid := PackedVector3Array()
var volume := PackedFloat32Array()
var piece_of := PackedInt32Array()
var mesh: ShardMesh
var rubble: Rubble
## The cut depends on it: another number, other blocks.
var cut_seed := 1
## How many pieces still stand.
var standing_count := 0

var _corners: Array[PackedVector3Array] = []  # per block: its collision corners, around its centre
var _radius := PackedFloat32Array()  # per block: how far its corners are from its centre
var _hull: Array[RID] = []  # per block: its collision shape, once it is needed
var _box: Array[RID] = []  # per piece: its collision shape as it was built
var _limbs: Array[Array] = []  # per piece that has been bent: the shapes of its two limbs
var _body: Array[RID] = []  # per piece: its static body while it stands
var _loose := PackedInt32Array()  # per piece: its body in the rubble once it has come down whole
var _by_body := {}  # RID -> piece that stands
var _built := false


func _init() -> void:
	mesh = ShardMesh.new()
	add_child(mesh)
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
	lean.append(Vector3.ZERO)
	knee.append(-1.0)
	bows.append(0)
	_loose.append(-1)
	_limbs.append([])
	if Matter.BENDS[of]:
		blocks.append(_add_rings(p))
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


## A blow of the brute: a fist or a foot goes from `from` to `to`, `power`
## hard. The first piece on its way takes it; what lies loose near where it
## ends is sent off. Returns true if it met something.
func strike(from: Vector3, to: Vector3, power: int) -> bool:
	var way := to - from
	var space := get_world_3d().direct_space_state
	var mask := Layers.STRUCTURE | Layers.RUBBLE
	var met := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, mask))
	var at := to
	var found: Array[RID] = []
	if met.is_empty():
		# Nothing right on its way: what the fist, as wide as it is, touches
		# where it ends.
		var ball := SphereShape3D.new()
		ball.radius = FIST
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = ball
		query.transform = Transform3D(Basis(), to)
		query.collision_mask = mask
		for touched in space.intersect_shape(query, 8):
			found.append(touched["rid"])
	else:
		at = met["position"]
		found.append(met["rid"])
	# One piece takes the blow: one that stands, rather than one that lies.
	var taker := -1
	for rid in found:
		var p := standing(rid)
		if p < 0:
			var lies := rubble.index_of(rid)
			p = rubble.piece[lies] if lies >= 0 else -1
			if p >= 0 and taker < 0:
				taker = p
		else:
			taker = p
			break
	rubble.shove(at, REACH, way, power)
	if taker >= 0:
		hit(taker, power, way, at)
	return not found.is_empty()


## Piece `p` takes `points` of blows, from something going along `way`, at
## `at` if that is known. What breaks cracks, and lets go when it has taken
## all it can; what bends is bent that much more, and lies down when it is
## bent as far as it goes.
func hit(p: int, points: float, way := Vector3.ZERO, at := Vector3.INF) -> void:
	if state[p] == BROKEN:
		return
	if Matter.BENDS[matter[p]]:
		# (Once it lies there, it has its shape for good. A plate has none
		# to take: it bends no way a blow could send it.)
		if state[p] == STANDS and Matter.upright(size[p]):
			_bend(p, points, way, at)
		return
	harm[p] += points
	if harm[p] >= strength[p]:
		shatter(p, way)
	elif state[p] == STANDS:
		_crack(p, 2 if harm[p] >= strength[p] * SPLIT else 1)


## Piece `p` breaks into its blocks, where it is, going over along `way` if
## it stood. What it carried comes down if nothing else holds it. (Not what
## bends: it never breaks.)
func shatter(p: int, way := Vector3.ZERO) -> void:
	if state[p] == BROKEN or Matter.BENDS[matter[p]]:
		return
	# Where a point of the piece as it stood is now, and how it moves.
	var now := Transform3D.IDENTITY
	var lin := Vector3.ZERO
	var ang := Vector3.ZERO
	var middle := place[p].origin
	var stood := state[p] == STANDS
	if stood:
		_leave(p)
	else:
		var whole := _loose[p]
		var xf := rubble.transform_of(whole)
		now = xf * Transform3D(Basis(), -middle)
		lin = rubble.velocity_of(whole)
		ang = rubble.spin_of(whole)
		rubble.remove(whole)
		_loose[p] = -1
	var slow := sqrt(rubble.fall)
	var over := _over(way) * slow if stood else Vector3.ZERO
	var foot := middle - Vector3.UP * size[p].y * 0.5
	state[p] = BROKEN
	var under := stood and _carries(p)
	var density := Matter.DENSITY[matter[p]]
	for i in range(first[p], first[p] + blocks[p]):
		var at := now * centroid[i]
		var own := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 2.0 * SCATTER * slow
		mesh.set_slot(i, 1 + i)
		var block := rubble.add(
			[[_shape_of(i), Transform3D.IDENTITY]],
			Transform3D(now.basis, at),
			centroid[i],
			volume[i] * density,
			_radius[i],
			lin + ang.cross(at - now * middle) + over.cross(centroid[i] - foot) + own,
			ang + over + own,
			[[1 + i, Transform3D(Basis(), centroid[i]), centroid[i]]]
		)
		if under:
			rubble.slip(block)
	_let_go(p)


## Cuts piece `p`, which breaks, into its blocks. Returns how many.
func _add_blocks(p: int) -> int:
	var xf := place[p]
	var cut := Fracture.cut(size[p], Matter.grain(size[p]), cut_seed * 7919 + p * 104729, 0.0)
	var base := count
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
		mesh.add_shard(count, base, world, sh, xf.basis, Matter.TINT[matter[p]])
		_add_part(p, c, sh.volume, around, far)
	return cut.size()


## Draws piece `p`, which bends, as rings across it, from its foot to its
## head. Returns how many.
func _add_rings(p: int) -> int:
	var xf := place[p]
	var half := size[p] * 0.5
	var rings: Array[PackedVector3Array] = []
	var many := Matter.rings(size[p])
	for k in many:
		var y := lerpf(-half.y, half.y, float(k) / (many - 1))
		var ring := PackedVector3Array()
		for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			ring.append(xf * Vector3(corner.x * half.x, y, corner.y * half.z))
		rings.append(ring)
	mesh.add_skin(count, rings, Matter.TINT[matter[p]])
	for k in many:
		var y := lerpf(-half.y, half.y, float(k) / (many - 1))
		_add_part(p, xf * Vector3(0, y, 0), 0.0, PackedVector3Array(), 0.0)
	return many


## One more part of the mesh, of piece `p`.
func _add_part(p: int, at: Vector3, of_volume: float, around: PackedVector3Array, far: float) -> void:
	centroid.append(at)
	volume.append(of_volume)
	piece_of.append(p)
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
	_by_body.erase(_body[p])
	PhysicsServer3D.free_rid(_body[p])
	_body[p] = RID()
	standing_count -= 1
	# What rested against it or on it, frozen, moves again.
	rubble.thaw_in(_bounds(p).grow(0.4))


## Piece `p` no longer holds anything up: what rested on it comes down, in
## one piece, unless what is left under it still holds it.
func _let_go(p: int) -> void:
	for q in carries[p]:
		if state[q] == STANDS and not _held(q):
			_drop(q, Vector3.ZERO)
			_let_go(q)


## Piece `p`, which stood, comes down in one piece, in the shape it has: a
## loose body from now on. It starts off turning at `turn` about its foot.
func _drop(p: int, turn: Vector3) -> void:
	_leave(p)
	state[p] = FALLS
	var middle := place[p].origin
	var shapes: Array = []
	var rig: Array = []
	if Matter.BENDS[matter[p]]:
		# Its limbs as they are bent, and each ring where the bend put it.
		var poses := _bent(p)
		for limb in _limbs_of(p, poses):
			shapes.append([limb[0], Transform3D(Basis(), -middle) * (limb[1] as Transform3D)])
		for k in blocks[p]:
			var i := first[p] + k
			mesh.set_slot(i, 1 + i)
			rig.append([1 + i, poses[k], centroid[i]])
	else:
		# All its blocks move with the body of the first, as one.
		shapes.append([_box[p], Transform3D(place[p].basis, Vector3.ZERO)])
		for i in range(first[p], first[p] + blocks[p]):
			mesh.set_slot(i, 1 + first[p])
		rig.append([1 + first[p], Transform3D(Basis(), middle), middle])
	var foot := middle - Vector3.UP * size[p].y * 0.5
	_loose[p] = rubble.add(
		shapes,
		Transform3D(Basis(), middle),
		middle,
		size[p].x * size[p].y * size[p].z * Matter.DENSITY[matter[p]],
		size[p].length() * 0.75,
		turn.cross(middle - foot),
		turn,
		rig,
		p
	)


## Does what is left under piece `p` hold it up? It stands on the ground,
## or its middle is over what it still rests on.
func _held(p: int) -> bool:
	var foot := _bounds(p)
	if foot.position.y < TOUCH:
		return true
	var under := PackedVector2Array()
	for q in rests_on[p]:
		if state[q] != STANDS:
			continue
		var touch := _contact(foot, _bounds(q))
		under.append(touch.position)
		under.append(touch.end)
		under.append(Vector2(touch.position.x, touch.end.y))
		under.append(Vector2(touch.end.x, touch.position.y))
	if under.is_empty():
		return false
	var middle := Vector2(place[p].origin.x, place[p].origin.z)
	return Geometry2D.is_point_in_polygon(middle, Geometry2D.convex_hull(under))


## Piece `p`, which stands, shows cracks: `level` 1, or 2 for wide ones.
## Each of its blocks is drawn on its own, a little smaller and askew.
func _crack(p: int, level: int) -> void:
	if cracks[p] == level:
		return
	cracks[p] = level
	for i in range(first[p], first[p] + blocks[p]):
		# (Always the same way for the same block: wider cracks open the
		# ones that were there.)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(i * 7919 + cut_seed)
		var axis := Vector3(rng.randf() - 0.5, rng.randf() - 0.5, rng.randf() - 0.5).normalized()
		var askew := Basis(axis, TILT[level] * rng.randf_range(0.4, 1.0))
		mesh.set_slot(i, 1 + i)
		mesh.set_body(1 + i, Transform3D(askew, centroid[i]), centroid[i], CRACKS[level])


## Piece `p`, which stands and bends, takes `points` of blows from
## something going along `way`, at `at` if that is known: it is bent that
## much more that way, where the first blow landed. A blow from the other
## side straightens it by as much. Bent as far as it goes, it lies down.
func _bend(p: int, points: float, way: Vector3, at: Vector3) -> void:
	var flat := Vector3(way.x, 0.0, way.z)
	if flat.length() < 0.1:
		# Something came down on it: it gives the way it leans already, or
		# any way.
		flat = lean[p] if lean[p].length() > 0.01 else Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	if knee[p] < 0.0:
		var high := size[p].y
		var foot := place[p].origin.y - high * 0.5
		var struck := at.y - foot if at.is_finite() else high * 0.5
		knee[p] = clampf(struck, high * KNEE_LEAST, high * (1.0 - KNEE_LEAST))
		bows[p] = 1 if _carries(p) else 0
	lean[p] += flat.normalized() * points
	harm[p] = lean[p].length()
	if harm[p] >= strength[p]:
		var under := _carries(p)
		_drop(p, _over(lean[p]) * sqrt(rubble.fall))
		if under:
			rubble.slip(_loose[p])
		_let_go(p)
		return
	# It stands, in its new shape: to the eye, and to what runs into it.
	var poses := _bent(p)
	for k in blocks[p]:
		var i := first[p] + k
		mesh.set_slot(i, 1 + i)
		mesh.set_body(1 + i, poses[k], centroid[i])
	PhysicsServer3D.body_clear_shapes(_body[p])
	var here := place[p].affine_inverse()
	for limb in _limbs_of(p, poses):
		PhysicsServer3D.body_add_shape(_body[p], limb[0], here * (limb[1] as Transform3D))


## Where the bend has put each ring of piece `p`, from its foot to its
## head: how the ring has turned since it was built, and where its middle
## is. A piece that stands free leans from the bend up; one that bows keeps
## its head where it was, and its middle goes aside.
func _bent(p: int) -> Array[Transform3D]:
	var poses: Array[Transform3D] = []
	var many := blocks[p]
	var high := size[p].y
	var foot := place[p].origin - Vector3.UP * high * 0.5
	var share := clampf(harm[p] / strength[p], 0.0, 1.0)
	var way := lean[p].normalized() if harm[p] > 0.0 else Vector3.FORWARD
	# (Turning about it takes what points up towards `way`.)
	var axis := Vector3.UP.cross(way)
	var bend := maxf(knee[p], 0.0)
	var at := foot
	var below := 0.0
	for k in many:
		var y := high * k / (many - 1)
		if bows[p] == 1:
			# A bump: nothing at the foot and at the head, the most at the bend.
			var from_end := y / bend if y <= bend else (high - y) / (high - bend)
			var run := bend if y <= bend else bend - high
			var aside := Matter.BOW_MOST * share
			var slope := aside * 6.0 * from_end * (1.0 - from_end) / run
			at = foot + Vector3.UP * y + way * aside * smoothstep(0.0, 1.0, from_end)
			poses.append(Transform3D(Basis(axis, atan(slope)), at))
		else:
			# The turn comes on over KINK m about the bend; the rings follow
			# the curve that makes.
			var most := Matter.BEND_MOST * share
			var from := bend - Matter.KINK * 0.5
			var half_way := most * smoothstep(from, from + Matter.KINK, (y + below) * 0.5)
			at += Basis(axis, half_way) * Vector3.UP * (y - below)
			poses.append(Transform3D(Basis(axis, most * smoothstep(from, from + Matter.KINK, y)), at))
			below = y
	return poses


## The two limbs of piece `p` as its rings are in `poses`, below and above
## its bend: for each, its shape and where it is. (One, as it was built, if
## it was never bent.)
func _limbs_of(p: int, poses: Array[Transform3D]) -> Array[Array]:
	if knee[p] < 0.0:
		return [[_box[p], place[p]]]
	if _limbs[p].is_empty():
		_limbs[p] = [PhysicsServer3D.box_shape_create(), PhysicsServer3D.box_shape_create()]
	# The ring nearest the bend parts the two.
	var many := blocks[p]
	var joint := clampi(roundi(knee[p] / size[p].y * (many - 1)), 1, many - 2)
	var ends: Array[Vector3] = [poses[0].origin, poses[joint].origin, poses[many - 1].origin]
	var limbs: Array[Array] = []
	for k in 2:
		var along := ends[k + 1] - ends[k]
		var long := along.length()
		PhysicsServer3D.shape_set_data(_limbs[p][k], Vector3(size[p].x, long, size[p].z) * 0.5)
		var tilt := Vector3.UP.cross(along)
		var turned := place[p].basis
		if tilt.length() > 0.0001:
			turned = Basis(tilt.normalized(), Vector3.UP.angle_to(along)) * turned
		limbs.append([_limbs[p][k], Transform3D(turned, (ends[k] + ends[k + 1]) * 0.5)])
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
