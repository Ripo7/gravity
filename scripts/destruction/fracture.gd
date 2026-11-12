class_name Fracture
extends RefCounted
## Cuts a box into irregular convex shards: each shard is the part of the
## box nearer to its seed than to any other (a Voronoi diagram). Seeds sit on
## a jittered grid about `grain` metres apart, and here and there a grid cell
## holds a few seeds instead of one, so big shards and small ones are mixed.
## The same seed number always gives the same cut.

## Nearest seeds tried first; farther ones only if the shard reaches them.
const FIRST := 14
## Two corners closer than this are one corner (m).
const WELD := 2e-5
## A corner this close to a plane lies on it (m).
const ON_PLANE := 1e-4


## One convex shard, in the box's own space (origin at the box's centre).
class Shard:
	var points := PackedVector3Array()  ## its corners
	var centroid := Vector3.ZERO
	var volume := 0.0
	## Per face: its corners (indices into points, anticlockwise seen from
	## outside), outward normal, area, and what is on the other side: a
	## shard's index, or -1 - side for a face of the box (side 0..5 is
	## -x +x -y +y -z +z).
	var faces: Array[PackedInt32Array] = []
	var normals := PackedVector3Array()
	var areas := PackedFloat32Array()
	var others := PackedInt32Array()


## The shards of a box of `size`. `fine` is the share of grid cells that
## hold several small shards instead of one.
static func cut(size: Vector3, grain: float, rng_seed: int, fine := 0.25) -> Array[Shard]:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var n := Vector3i(
		maxi(1, roundi(size.x / grain)), maxi(1, roundi(size.y / grain)), maxi(1, roundi(size.z / grain))
	)
	var cell := size / Vector3(n)
	var half := size * 0.5
	var seeds := PackedVector3Array()
	var first := PackedInt32Array()  # first seed of each grid cell, then the total
	for z in n.z:
		for y in n.y:
			for x in n.x:
				first.append(seeds.size())
				var k := rng.randi_range(2, 4) if rng.randf() < fine else 1
				_scatter(seeds, k, Vector3(x, y, z) * cell - half, cell, n, rng)
	first.append(seeds.size())
	var box: Array[Plane] = [
		Plane(Vector3.LEFT, half.x),
		Plane(Vector3.RIGHT, half.x),
		Plane(Vector3.DOWN, half.y),
		Plane(Vector3.UP, half.y),
		Plane(Vector3.FORWARD, half.z),
		Plane(Vector3.BACK, half.z),
	]
	var out: Array[Shard] = []
	for z in n.z:
		for y in n.y:
			for x in n.x:
				var c := (z * n.y + y) * n.x + x
				for i in range(first[c], first[c + 1]):
					out.append(_shard(i, seeds, _around(i, Vector3i(x, y, z), n, first, seeds), box))
	return out


## `count` seeds in the grid cell at `base`, kept apart from each other.
static func _scatter(
	seeds: PackedVector3Array,
	count: int,
	base: Vector3,
	cell: Vector3,
	n: Vector3i,
	rng: RandomNumberGenerator
) -> void:
	var from := seeds.size()
	# Across a thin box (one cell thick) seeds stay near the middle, so the
	# cuts go through it nearly square.
	var lo := Vector3(0.3 if n.x == 1 else 0.06, 0.3 if n.y == 1 else 0.06, 0.3 if n.z == 1 else 0.06)
	for s in count:
		var best := Vector3.ZERO
		var best_gap := -1.0
		for attempt in 1 if s == 0 else 5:
			var f := Vector3(rng.randf(), rng.randf(), rng.randf())
			var p := base + (lo + f * (Vector3.ONE - lo * 2.0)) * cell
			var gap := INF
			for k in range(from, seeds.size()):
				gap = minf(gap, p.distance_squared_to(seeds[k]))
			if gap > best_gap:
				best_gap = gap
				best = p
		seeds.append(best)


## The other seeds near seed `i` (grid cell `at`), nearest first.
static func _around(
	i: int, at: Vector3i, n: Vector3i, first: PackedInt32Array, seeds: PackedVector3Array
) -> PackedInt32Array:
	var s := seeds[i]
	var near: Array[Vector2] = []  # (distance squared, seed)
	for z in range(maxi(at.z - 2, 0), mini(at.z + 3, n.z)):
		for y in range(maxi(at.y - 2, 0), mini(at.y + 3, n.y)):
			for x in range(maxi(at.x - 2, 0), mini(at.x + 3, n.x)):
				var c := (z * n.y + y) * n.x + x
				for j in range(first[c], first[c + 1]):
					if j != i:
						near.append(Vector2(seeds[j].distance_squared_to(s), j))
	near.sort()
	var out := PackedInt32Array()
	for v in near:
		out.append(int(v.y))
	return out


## The shard of seed `i`: the box cut by the planes halfway to the seeds
## `around` it (nearest first).
static func _shard(i: int, seeds: PackedVector3Array, around: PackedInt32Array, box: Array[Plane]) -> Shard:
	var s := seeds[i]
	# Worked out around the seed, where numbers are small and exact.
	var planes: Array[Plane] = []
	var gens := PackedInt32Array()  # what made each plane: a seed, or -1 - side
	for side in 6:
		planes.append(Plane(box[side].normal, box[side].d - box[side].normal.dot(s)))
		gens.append(-1 - side)
	var used := mini(FIRST, around.size())
	for k in used:
		_add_bisector(planes, gens, s, seeds, around[k])
	var pts := Geometry3D.compute_convex_mesh_points(planes)
	if used < around.size():
		var reach := 0.0
		for p in pts:
			reach = maxf(reach, p.length())
		# A seed farther than twice the shard's reach cannot cut it.
		var more := false
		for k in range(used, around.size()):
			if seeds[around[k]].distance_to(s) >= reach * 2.0:
				break
			_add_bisector(planes, gens, s, seeds, around[k])
			more = true
		if more:
			pts = Geometry3D.compute_convex_mesh_points(planes)
	return _build(i, seeds, pts, planes, gens, box)


static func _add_bisector(
	planes: Array[Plane], gens: PackedInt32Array, s: Vector3, seeds: PackedVector3Array, j: int
) -> void:
	var to := seeds[j] - s
	var length := to.length()
	planes.append(Plane(to / length, length * 0.5))
	gens.append(j)


## Corners, faces, volume and centroid from the raw corner cloud `raw`
## (around the seed) and the planes that bound it.
static func _build(
	i: int,
	seeds: PackedVector3Array,
	raw: PackedVector3Array,
	planes: Array[Plane],
	gens: PackedInt32Array,
	box: Array[Plane]
) -> Shard:
	var s := seeds[i]
	var local := PackedVector3Array()  # corners around the seed, welded
	for p in raw:
		var known := false
		for q in local:
			if p.distance_squared_to(q) < WELD * WELD:
				known = true
				break
		if not known:
			local.append(p)
	var on_plane: Array[PackedInt32Array] = []  # per plane: the corners on it
	on_plane.resize(planes.size())
	var shard := Shard.new()
	for c in local.size():
		var mine := PackedInt32Array()  # the planes through this corner
		for k in planes.size():
			if absf(planes[k].distance_to(local[c])) < ON_PLANE:
				mine.append(gens[k])
				on_plane[k].append(c)
		shard.points.append(_corner(i, mine, seeds, box, local[c] + s))
	var volume := 0.0
	var moment := Vector3.ZERO
	for k in planes.size():
		if on_plane[k].size() < 3:
			continue
		var ring := _ring(on_plane[k], local, planes[k].normal)
		var area := 0.0
		var a := local[ring[0]]
		for t in range(1, ring.size() - 1):
			var b := local[ring[t]]
			var c := local[ring[t + 1]]
			area += (b - a).cross(c - a).length() * 0.5
			var tet := a.dot(b.cross(c)) / 6.0
			volume += tet
			moment += (a + b + c) * (tet * 0.25)
		if area < 1e-7:
			continue
		shard.faces.append(ring)
		shard.normals.append(planes[k].normal)
		shard.areas.append(area)
		shard.others.append(gens[k])
	shard.volume = volume
	shard.centroid = s + (moment / volume if volume > 0.0 else Vector3.ZERO)
	return shard


## The exact place of a corner where the planes made by `gens` meet. Every
## shard that shares the corner works it out from the same three planes in
## the same order, so they all get the very same numbers: no hairline gaps
## between shards that are still together.
static func _corner(
	i: int, gens: PackedInt32Array, seeds: PackedVector3Array, box: Array[Plane], fallback: Vector3
) -> Vector3:
	var sides := PackedInt32Array()
	var meet := PackedInt32Array([i])
	for g in gens:
		if g < 0:
			sides.append(-1 - g)
		else:
			meet.append(g)
	sides.sort()
	meet.sort()
	var three: Array[Plane] = []
	for side in sides:
		three.append(box[side])
	var a := seeds[meet[0]]
	for k in range(1, meet.size()):
		var to := seeds[meet[k]] - a
		three.append(Plane(to.normalized(), to.normalized().dot((a + seeds[meet[k]]) * 0.5)))
	if three.size() < 3:
		return fallback
	var at: Variant = three[0].intersect_3(three[1], three[2])
	if at == null or (at as Vector3).distance_to(fallback) > ON_PLANE * 4.0:
		return fallback
	return at


## The corners `on` a face put in order round it, anticlockwise seen from
## outside (`normal` points out).
static func _ring(on: PackedInt32Array, pts: PackedVector3Array, normal: Vector3) -> PackedInt32Array:
	var mid := Vector3.ZERO
	for c in on:
		mid += pts[c]
	mid /= on.size()
	var u := normal.cross(Vector3.UP if absf(normal.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := normal.cross(u)
	var turn: Array[Vector2] = []  # (angle, corner)
	for c in on:
		var d := pts[c] - mid
		turn.append(Vector2(atan2(d.dot(v), d.dot(u)), c))
	turn.sort()
	var ring := PackedInt32Array()
	for t in turn:
		ring.append(int(t.y))
	return ring
