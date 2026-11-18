class_name Structure
extends Node3D
## What stands and can be broken. It is made of pieces (a column, a slab, a
## panel of a wall): each one an upright box of one matter, which alone says
## how the piece answers a blow (Matter, docs/CONCEPT.md).
##
## A piece takes blows as a whole: it has a strength of its own (Matter.
## strength) and lets go when it has taken that much, wherever it was hit and
## however it is cut. Until then it cracks, for all to see. When it lets go
## it breaks into the few blocks it was cut into when it was made (Fracture),
## which become loose bodies (Rubble).
##
## What is no longer carried comes down: a piece rests on the pieces right
## under it, and when those that are left no longer hold it up it falls, in
## one piece, and breaks when it lands. Only a blow breaks: from the brute
## (`strike`), or from something heavy landing on a piece (Rubble).

## What a piece is doing.
enum { STANDS, FALLS, BROKEN }

## Two pieces closer than this (m) touch; a piece this close to the ground
## stands on it.
const TOUCH := 0.03
## The collision shape of a block is a little smaller than the block:
## blocks that were one piece a moment ago do not start out pressed
## against each other.
const SHRINK := 0.96
## A piece that has taken a blow shows cracks; from SPLIT of its strength
## on, wide ones. Each block is then drawn that much smaller (CRACKS, by
## how cracked: 0 not, 1, 2) and turned by up to TILT rad, so that the cuts
## between the blocks show.
const SPLIT := 0.5
const CRACKS: Array[float] = [1.0, 0.975, 0.94]
const TILT: Array[float] = [0.0, 0.012, 0.035]
## A fist is this wide (m): a blow that meets nothing on its way still
## lands on what stands within that of where it ends, and sends off what
## lies loose within REACH.
const FIST := 0.3
const REACH := 0.7
## A piece that stood goes over as it lets go: its blocks start off as if
## the whole piece turned about its foot at TOPPLE rad/s, away from the
## blow, and come apart as they go down. (Left where they stood, blocks cut
## one on top of the other stay there, a broken column still standing.)
## Each block also gets up to SCATTER m/s of its own. Both as at real
## gravity.
const TOPPLE := 2.5
const SCATTER := 0.4

## How many pieces there are, and per piece: what it is made of, its size,
## where its middle is, what it takes and has taken, what it is doing, how
## cracked it shows (0 to 2), its blocks (the first, and how many).
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
## How many blocks there are, and per block: where it stood (its centre of
## mass), its volume, its piece.
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
var _box: Array[RID] = []  # per piece: its collision shape
var _body: Array[RID] = []  # per piece: its static body while it stands
var _loose := PackedInt32Array()  # per piece: its body in the rubble while it falls
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
	_loose.append(-1)
	var cut := Fracture.cut(box, Matter.grain(of, box), cut_seed * 7919 + p * 104729, 0.0)
	blocks.append(cut.size())
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
		mesh.add_shard(count, base, world, sh, xf.basis, Matter.TINT[of])
		centroid.append(c)
		volume.append(sh.volume)
		piece_of.append(p)
		_corners.append(around)
		_radius.append(far)
		_hull.append(RID())
		count += 1
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
		hit(taker, power, way)
	return not found.is_empty()


## Piece `p` takes `points` of blows, from something going along `way`: it
## cracks, and lets go when it has taken all it can.
func hit(p: int, points: float, way := Vector3.ZERO) -> void:
	if state[p] == BROKEN:
		return
	harm[p] += points
	if harm[p] >= strength[p]:
		shatter(p, way)
	elif state[p] == STANDS:
		_crack(p, 2 if harm[p] >= strength[p] * SPLIT else 1)


## Piece `p` breaks into its blocks, where it is, pushed along `way`. What
## it carried comes down if nothing else holds it.
func shatter(p: int, way := Vector3.ZERO) -> void:
	if state[p] == BROKEN:
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
	var over := Vector3.ZERO  # how it goes over: a turn about its foot
	var foot := middle - Vector3.UP * size[p].y * 0.5
	if stood:
		var flat := Vector3(way.x, 0.0, way.z)
		if flat.length() < 0.1:
			flat = Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
		over = Vector3.UP.cross(flat.normalized()) * TOPPLE * slow
	state[p] = BROKEN
	var density := Matter.DENSITY[matter[p]]
	for i in range(first[p], first[p] + blocks[p]):
		var at := now * centroid[i]
		var own := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 2.0 * SCATTER * slow
		mesh.set_slot(i, 1 + i)
		rubble.add(
			1 + i,
			_shape_of(i),
			Basis(),
			Transform3D(now.basis, at),
			centroid[i],
			volume[i] * density,
			_radius[i],
			lin + ang.cross(at - now * middle) + over.cross(centroid[i] - foot) + own,
			ang + over + own
		)
	_let_go(p)


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
			_leave(q)
			state[q] = FALLS
			# All its blocks move with the body of the first, as one.
			for i in range(first[q], first[q] + blocks[q]):
				mesh.set_slot(i, 1 + first[q])
			var weight := size[q].x * size[q].y * size[q].z * Matter.DENSITY[matter[q]]
			_loose[q] = rubble.add(
				1 + first[q],
				_box[q],
				place[q].basis,
				Transform3D(Basis(), place[q].origin),
				place[q].origin,
				weight,
				size[q].length() * 0.5,
				Vector3.ZERO,
				Vector3.ZERO,
				q
			)
			_let_go(q)


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
