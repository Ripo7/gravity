class_name Bend
extends RefCounted
## How one piece of metal is bent. Metal never breaks: a blow leaves its
## mark where it lands, and the piece keeps it (docs/CONCEPT.md). What the
## mark is depends on the shape of the piece.
##
## A post (upright, no wider than a fist's dent) kinks at the height it is
## struck at: from there up it leans away from the blow, or, if it carries
## something, its head stays where it is and it bows. Another height,
## another kink.
##
## A sheet (upright, wide) takes a dent under the fist: the rest of it
## stays flat. Dents add up.
##
## A plate (lying flat) takes nothing from a blow. It sags where nothing
## holds it any more: it is made of triangles that fold along the lines
## between them (see Structure and Rubble.join).
##
## This is the shape only: what it is drawn with (rings for a post, nodes
## for a sheet or a plate, the skin stretched between them) and where a
## blow puts them. The Structure makes bodies of it.

enum { POST, SHEET, PLATE }

var kind := POST
var size: Vector3
var place: Transform3D
## What it takes in one place before it lies down, in points of blows.
var strength := 1.0
## How many parts of the mesh it is drawn with: the rings of a post, from
## its foot to its head; the nodes of a sheet or a plate, row by row.
var parts := 0
## A post: the heights (m above its foot) it is kinked at, from the lowest
## up, and for each which way and how much (the blows it took there, each
## as long as its points); whether it bows (it carried something at the
## first blow).
var kink_at := PackedFloat32Array()
var kink_lean := PackedVector3Array()
var bows := false
## A sheet: how far in each node has been pushed (m, along `normal`).
var dent := PackedFloat32Array()
var normal := Vector3.ZERO
## A sheet or a plate: how many nodes in a row, and how many rows.
var across := 0
var rows := 0
## A plate: its triangles (three nodes each), and the lines it folds
## along, each [triangle, triangle, node, node].
var tiles: Array[PackedInt32Array] = []
var folds: Array[PackedInt32Array] = []

var _wide := 0  # a sheet: the axis it is wide along (0: x, 2: z)


func _init(of_size: Vector3, at: Transform3D, takes: float) -> void:
	size = of_size
	place = at
	strength = takes
	if not Matter.upright(size):
		kind = PLATE
		_lay_plate()
	elif maxf(size.x, size.z) > Matter.SLENDER:
		kind = SHEET
		_wide = 0 if size.x >= size.z else 2
		normal = place.basis[2 - _wide].normalized()
		across = maxi(2, ceili(size[_wide] / Matter.NODE - 0.001) + 1)
		rows = maxi(2, ceili(size.y / Matter.NODE - 0.001) + 1)
		parts = across * rows
		dent.resize(parts)
	else:
		parts = maxi(2, ceili(size.y / Matter.RING) + 1)


## Where part `k` is in the piece as it was built.
func rest(k: int) -> Vector3:
	var half := size * 0.5
	var at := Vector3.ZERO
	if kind == POST:
		at.y = lerpf(-half.y, half.y, float(k) / (parts - 1))
	elif kind == SHEET:
		at[_wide] = lerpf(-half[_wide], half[_wide], float(k % across) / (across - 1))
		at.y = lerpf(-half.y, half.y, float(k / across) / (rows - 1))
	else:
		at.x = lerpf(-half.x, half.x, float(k % across) / (across - 1))
		at.z = lerpf(-half.z, half.z, float(k / across) / (rows - 1))
	return place * at


## Adds its skin to `mesh`, its parts numbered from `first`.
func draw(mesh: ShardMesh, first: int, tint: Color) -> void:
	if kind == POST:
		var half := size * 0.5
		var rings: Array[PackedVector3Array] = []
		for k in parts:
			var y := lerpf(-half.y, half.y, float(k) / (parts - 1))
			var ring := PackedVector3Array()
			for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				ring.append(place * Vector3(corner.x * half.x, y, corner.y * half.z))
			rings.append(ring)
		mesh.add_skin(first, rings, tint)
		return
	# A sheet or a plate: two faces, half its thickness either side of its
	# nodes, and a rim round them.
	var out := normal if kind == SHEET else place.basis.y.normalized()
	var thick := out * (size[2 - _wide] if kind == SHEET else size.y) * 0.5
	var middle := place.origin
	var cells: Array[PackedInt32Array] = tiles
	if kind == SHEET:
		cells = []
		for r in rows - 1:
			for c in across - 1:
				var n := r * across + c
				cells.append(PackedInt32Array([n, n + 1, n + across + 1, n + across]))
	var met := {}  # edge -> how many cells have it
	for cell in cells:
		_face(mesh, first, cell, thick, out, tint)
		_face(mesh, first, cell, -thick, -out, tint)
		for k in cell.size():
			var edge := _edge(cell[k], cell[(k + 1) % cell.size()])
			met[edge] = met.get(edge, 0) + 1
	for edge: Vector2i in met:
		if met[edge] > 1:
			continue
		var a := rest(edge.x)
		var b := rest(edge.y)
		var away := (a + b) * 0.5 - middle
		var corners := PackedVector3Array([a + thick, b + thick, b - thick, a - thick])
		var of := PackedInt32Array([first + edge.x, first + edge.y, first + edge.y, first + edge.x])
		_add(mesh, of, corners, away, tint)


## It takes `points` of blows from something going along `way`, at `at`
## (its middle, if that is not known). `carrying`: something stands on it.
func strike(points: float, way: Vector3, at: Vector3, carrying: bool) -> void:
	if not at.is_finite():
		at = place.origin
	if kind == POST:
		_kink(points, way, at, carrying)
	elif kind == SHEET:
		_dent(points, way, at)


## How much it has taken where it has taken the most, in points of blows.
func harm() -> float:
	var most := 0.0
	if kind == POST:
		for lean in kink_lean:
			most = maxf(most, lean.length())
	elif kind == SHEET:
		for deep in dent:
			most = maxf(most, absf(deep) / Matter.DENT)
	return most


## The way it goes over when it lies down: the way it was bent.
func leans() -> Vector3:
	var way := Vector3.ZERO
	if kind == POST:
		for lean in kink_lean:
			way += lean
	elif kind == SHEET:
		var deepest := 0.0
		for deep in dent:
			if absf(deep) > absf(deepest):
				deepest = deep
		way = normal * deepest
	return way


## A post: where its kinks have put each of its rings, from its foot to
## its head: how the ring has turned since it was built, and where its
## middle is. A post that stands free leans from each kink up; one that
## bows keeps its head where it was, and goes aside at each kink.
func ring_poses() -> Array[Transform3D]:
	var poses: Array[Transform3D] = []
	var high := size.y
	var foot := place.origin - Vector3.UP * high * 0.5
	if bows:
		# A bump at each kink: nothing at the foot and at the head.
		var middles := PackedVector3Array()
		for k in parts:
			var y := high * k / (parts - 1)
			var aside := Vector3.ZERO
			for j in kink_at.size():
				var bend := kink_at[j]
				var from_end := y / bend if y <= bend else (high - y) / (high - bend)
				aside += kink_lean[j] / strength * Matter.BOW_MOST * smoothstep(0.0, 1.0, from_end)
			middles.append(foot + Vector3.UP * y + aside)
		for k in parts:
			var along := middles[mini(k + 1, parts - 1)] - middles[maxi(k - 1, 0)]
			var turned := Basis()
			var tilt := Vector3.UP.cross(along)
			if k > 0 and k < parts - 1 and tilt.length() > 0.0001:
				turned = Basis(tilt.normalized(), Vector3.UP.angle_to(along))
			poses.append(Transform3D(turned, middles[k]))
		return poses
	# Each kink turns what is above it, over KINK m of the post; the rings
	# follow the curve that makes.
	var at := foot
	var below := 0.0
	for k in parts:
		var y := high * k / (parts - 1)
		at += _turn(0.5 * (y + below)) * Vector3.UP * (y - below)
		poses.append(Transform3D(_turn(y), at))
		below = y
	return poses


## A post: the rings it is jointed at (the one nearest each kink), from the
## lowest up, between its first ring and its last.
func joints() -> PackedInt32Array:
	var at := PackedInt32Array([0])
	for bend in kink_at:
		var ring := clampi(roundi(bend / size.y * (parts - 1)), 1, parts - 2)
		if ring > at[at.size() - 1]:
			at.append(ring)
	at.append(parts - 1)
	return at


## A post: has a kink brought it down to the ground (`poses`: its rings)?
func touches_ground(poses: Array[Transform3D]) -> bool:
	var floor_at := place.origin.y - size.y * 0.5 + maxf(size.x, size.z)
	for k in range(2, parts):
		if poses[k].origin.y < floor_at:
			return true
	return false


## A sheet or a plate: where node `k` is now in the piece as it was built
## (a dent pushes it in).
func node(k: int) -> Vector3:
	return rest(k) + (normal * dent[k] if kind == SHEET else Vector3.ZERO)


## A blow at `at`, `high` m up a post: it kinks there, or deepens the kink
## it has near there.
func _kink(points: float, way: Vector3, at: Vector3, carrying: bool) -> void:
	var flat := Vector3(way.x, 0.0, way.z)
	if flat.length() < 0.1:
		# Something came down on it: it gives the way it leans already, or
		# any way.
		flat = leans()
		if flat.length() < 0.01:
			flat = Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	var high := size.y
	var least := high * 0.2
	var struck := clampf(at.y - (place.origin.y - high * 0.5), least, high - least)
	if kink_at.is_empty():
		bows = carrying
	var which := -1
	for j in kink_at.size():
		var apart := absf(kink_at[j] - struck)
		if which < 0 or apart < absf(kink_at[which] - struck):
			which = j
	if which < 0 or (absf(kink_at[which] - struck) > Matter.KINK_APART and kink_at.size() < Matter.KINKS):
		# A new one, kept in order of height.
		which = 0
		while which < kink_at.size() and kink_at[which] < struck:
			which += 1
		kink_at.insert(which, struck)
		kink_lean.insert(which, Vector3.ZERO)
	kink_lean[which] += flat.normalized() * points


## A blow at `at` on a sheet: the nodes near it are pushed in, the nearer
## the deeper. Its foot stays where it is.
func _dent(points: float, way: Vector3, at: Vector3) -> void:
	var side := 1.0 if way.dot(normal) >= 0.0 else -1.0
	var struck := place.affine_inverse() * at
	var half := size * 0.5
	for k in parts:
		var c := lerpf(-half[_wide], half[_wide], float(k % across) / (across - 1))
		var r := lerpf(-half.y, half.y, float(k / across) / (rows - 1))
		var off := Vector2(c - struck[_wide], r - struck.y).length()
		var held := clampf((r + half.y) / (2.0 * Matter.NODE), 0.0, 1.0)
		dent[k] += side * points * Matter.DENT * (1.0 - smoothstep(0.0, Matter.DENT_WIDE, off)) * held


## How the kinks of a post that stands free have turned it, `y` m up.
func _turn(y: float) -> Basis:
	var turned := Basis()
	for j in kink_at.size():
		var lean := kink_lean[j]
		if lean.length() < 0.001:
			continue
		var most := Matter.BEND_MOST * minf(lean.length() / strength, 1.0)
		var from := kink_at[j] - Matter.KINK * 0.5
		# (Turning about it takes what points up towards the lean.)
		var axis := Vector3.UP.cross(lean.normalized())
		turned = turned * Basis(axis, most * smoothstep(from, from + Matter.KINK, y))
	return turned


## A plate: its nodes, a square about CELL m across between four of them,
## each square two triangles. The squares are cut one way and the other in
## turn, so that the plate can fold along its diagonals too.
func _lay_plate() -> void:
	var wide := maxi(1, roundi(size.x / Matter.CELL))
	var deep := maxi(1, roundi(size.z / Matter.CELL))
	across = wide + 1
	rows = deep + 1
	parts = across * rows
	var met := {}  # edge -> the triangle that has it
	for j in deep:
		for i in wide:
			var a := j * across + i
			var b := a + 1
			var c := a + across + 1
			var d := a + across
			var cut: Array[PackedInt32Array] = [PackedInt32Array([a, b, c]), PackedInt32Array([a, c, d])]
			if (i + j) % 2 == 1:
				cut = [PackedInt32Array([a, b, d]), PackedInt32Array([b, c, d])]
			for tile in cut:
				var t := tiles.size()
				tiles.append(tile)
				for k in 3:
					var edge := _edge(tile[k], tile[(k + 1) % 3])
					if met.has(edge):
						folds.append(PackedInt32Array([met[edge], t, edge.x, edge.y]))
					else:
						met[edge] = t


func _edge(a: int, b: int) -> Vector2i:
	return Vector2i(mini(a, b), maxi(a, b))


## One face of a sheet or a plate: the nodes `cell`, each `thick` from
## where it is, seen from `out`.
func _face(
	mesh: ShardMesh, first: int, cell: PackedInt32Array, thick: Vector3, out: Vector3, tint: Color
) -> void:
	var of := PackedInt32Array()
	var corners := PackedVector3Array()
	for n in cell:
		of.append(first + n)
		corners.append(rest(n) + thick)
	_add(mesh, of, corners, out, tint)


## Adds a face to `mesh`, its corners put in the order that shows it from
## `out`.
func _add(
	mesh: ShardMesh, of: PackedInt32Array, corners: PackedVector3Array, out: Vector3, tint: Color
) -> void:
	if (corners[1] - corners[0]).cross(corners[2] - corners[0]).dot(out) < 0.0:
		of.reverse()
		corners.reverse()
	mesh.add_face(of, corners, tint)
