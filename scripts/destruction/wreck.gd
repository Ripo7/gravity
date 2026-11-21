class_name Wreck
extends RefCounted
## What a piece of metal comes down as: the loose bodies it folds into
## (Rubble). Metal never comes apart (docs/CONCEPT.md): a post lies down
## on its kinks, each limb between two of them a body, the limbs jointed
## where it is kinked; a sheet comes down in one, as dented as it is; a
## plate as its triangles, which fold along the lines between them.
##
## The Structure says when a piece comes down, and what it stays fixed
## to; this makes the bodies, in the shape the piece has (Bend).

## The triangles of a plate are this much smaller than drawn, as bodies:
## two that only meet at a corner do not start out pressed together.
const TILE := 0.97

var _of: Structure
var _limbs: Array[Array] = []  # per piece: the shapes of the limbs of a post that has been kinked
var _made: Array[RID] = []  # the shapes of what has lain down: sheets, the triangles of plates


func _init(of: Structure) -> void:
	_of = of


## One more piece was added to the structure.
func add_piece() -> void:
	_limbs.append([])


## Frees the shapes it made.
func free_shapes() -> void:
	for limbs in _limbs:
		for rid: RID in limbs:
			PhysicsServer3D.free_rid(rid)
	for rid in _made:
		PhysicsServer3D.free_rid(rid)
	_limbs.clear()
	_made.clear()


## Piece `p`, which is metal, comes down in the shape it has: as many
## bodies as it can fold into. It starts off turning at `turn` about its
## foot. `whole`: its shape as it was built. Returns its bodies: those of
## a post from its foot up, those of a plate triangle by triangle, as
## Bend has them.
func drop(p: int, turn: Vector3, whole: RID) -> PackedInt32Array:
	var b := _of.bend[p]
	if b.kind == Bend.POST:
		return _post(p, turn, whole)
	if b.kind == Bend.SHEET:
		return _sheet(p, turn)
	return _plate(p)


## The limbs of post `p` as its rings are in `poses`, between its foot,
## its kinks and its head: for each, its shape, where it is, its first
## ring and its last, how long it is. (One, `whole`, as it was built, if
## it was never kinked.)
func limbs_of(p: int, poses: Array[Transform3D], whole: RID) -> Array[Array]:
	var size := _of.size[p]
	var joints := _of.bend[p].joints()
	if _of.bend[p].kink_at.is_empty():
		return [[whole, _of.place[p], 0, joints[1], size.y]]
	var limbs: Array[Array] = []
	for k in joints.size() - 1:
		if _limbs[p].size() <= k:
			_limbs[p].append(PhysicsServer3D.box_shape_create())
		var from := poses[joints[k]].origin
		var along := poses[joints[k + 1]].origin - from
		var long := along.length()
		PhysicsServer3D.shape_set_data(_limbs[p][k], Vector3(size.x, long, size.z) * 0.5)
		var tilt := Vector3.UP.cross(along)
		var turned := _of.place[p].basis
		if tilt.length() > 0.0001:
			turned = Basis(tilt.normalized(), Vector3.UP.angle_to(along)) * turned
		limbs.append([_limbs[p][k], Transform3D(turned, from + along * 0.5), joints[k], joints[k + 1], long])
	return limbs


## A post lies down: each of its limbs a body, the rings of the limb with
## it. They fold at the joints between them.
func _post(p: int, turn: Vector3, whole: RID) -> PackedInt32Array:
	var size := _of.size[p]
	var first := _of.first[p]
	var foot := _of.place[p].origin - Vector3.UP * size.y * 0.5
	var poses := _of.bend[p].ring_poses()
	var limbs := limbs_of(p, poses, whole)
	var across := size.x * size.z
	var made := PackedInt32Array()
	for limb in limbs:
		var xf: Transform3D = limb[1]
		var long: float = limb[4]
		var rig: Array = []
		# (The ring at a joint goes with the limb under it.)
		var low: int = limb[2]
		for k in range(low + (1 if low > 0 else 0), limb[3] + 1):
			var i := first + k
			_of.mesh.set_slot(i, 1 + i)
			rig.append([1 + i, poses[k], _of.centroid[i]])
		made.append(
			_of.rubble.add(
				[[limb[0], Transform3D(xf.basis, Vector3.ZERO)]],
				Transform3D(Basis(), xf.origin),
				xf.origin,
				across * long * Matter.DENSITY[_of.matter[p]],
				long * 0.5 + maxf(size.x, size.z),
				turn.cross(xf.origin - foot),
				turn,
				rig,
				p
			)
		)
	var holds := Matter.FOLD * maxf(size.x, size.z) * pow(minf(size.x, size.z), 2.0)
	if _of.bend[p].bows and _of.harm[p] >= _of.strength[p]:
		holds *= Matter.BUCKLED
	for k in made.size() - 1:
		var at := poses[limbs[k][3]].origin
		var axis := (at - poses[limbs[k][2]].origin).cross(poses[limbs[k + 1][3]].origin - at)
		if axis.length() < 0.0001:
			axis = _of.place[p].basis.x
		_of.rubble.join(made[k], made[k + 1], at, axis, holds)
	return made


## A sheet lies down: one body, as dented as it is, which holds its
## corners and its dents.
func _sheet(p: int, turn: Vector3) -> PackedInt32Array:
	var b := _of.bend[p]
	var size := _of.size[p]
	var first := _of.first[p]
	var middle := _of.place[p].origin
	var foot := middle - Vector3.UP * size.y * 0.5
	var thick := b.normal * minf(size.x, size.z) * 0.5
	var around := PackedVector3Array()
	for k in b.parts:
		var corner := (k % b.across) % (b.across - 1) == 0 and (k / b.across) % (b.rows - 1) == 0
		if corner or absf(b.dent[k]) > 0.01:
			around.append(b.node(k) - middle + thick)
			around.append(b.node(k) - middle - thick)
		_of.mesh.set_slot(first + k, 1 + first)
	var sheet := _of.rubble.add(
		[[_shape(around), Transform3D.IDENTITY]],
		Transform3D(Basis(), middle),
		middle,
		size.x * size.y * size.z * Matter.DENSITY[_of.matter[p]],
		size.length() * 0.75,
		turn.cross(middle - foot),
		turn,
		[[1 + first, Transform3D(Basis(), middle), middle]],
		p
	)
	return PackedInt32Array([sheet])


## A plate comes loose: each of its triangles a body, joined to the next
## along the line between them, where the plate folds.
func _plate(p: int) -> PackedInt32Array:
	var b := _of.bend[p]
	var size := _of.size[p]
	var first := _of.first[p]
	var up := _of.place[p].basis.y.normalized() * size.y * 0.5
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
				var i := first + n
				_of.mesh.set_slot(i, 1 + i)
				rig.append([1 + i, Transform3D(Basis(), _of.centroid[i]), _of.centroid[i]])
		var area := (
			(b.rest(tile[1]) - b.rest(tile[0])).cross(b.rest(tile[2]) - b.rest(tile[0])).length() * 0.5
		)
		made.append(
			_of.rubble.add(
				[[_shape(around), Transform3D.IDENTITY]],
				Transform3D(Basis(), middle),
				middle,
				area * size.y * Matter.DENSITY[_of.matter[p]],
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
		var holds := Matter.FOLD * from.distance_to(to) * size.y * size.y
		_of.rubble.join(made[fold[0]], made[fold[1]], (from + to) * 0.5, to - from, holds)
	return made


## A collision shape that holds the points `around`, kept to be freed.
func _shape(around: PackedVector3Array) -> RID:
	var hull := PhysicsServer3D.convex_polygon_shape_create()
	PhysicsServer3D.shape_set_data(hull, around)
	_made.append(hull)
	return hull
