class_name Masonry
extends RefCounted
## What the big blocks are made of: the stones they are laid in. Standing,
## a wall panel, a pier or a floor is one block for the statics (cheap to
## check, and its texture draws the courses); the moment it falls it
## becomes those stones, so what falls comes apart as masonry and not as
## blocks of Lego: a wall in courses of staggered stones through its whole
## thickness, a floor or a roof in rows of slabs. Each stone falls with its
## piece of building (see Falls) and cracks into shards and gravel when it
## comes away from it.
##
## Round pieces (columns), carved ones, the cells of a cracked wall, wood,
## metal and glass stay whole: they are pieces already.

## Stone sizes, metres: course height, stone length, side of a floor's
## slabs. The same on every tier: smaller stones on desktop made a toppling
## tower too soft to crush the palace (it wore away against it instead).
const COURSE := 1.0
const LENGTH := 1.9
const SLAB := 2.0
## A wall thicker than this is laid in more than one leaf (m).
const LEAF := 1.3
## Joints wander by this share of a stone's length (no two courses alike).
const JITTER := 0.14
## No piece shorter than this share of a stone's length.
const SHORTEST := 0.35

## Stones made so far (tests, stats).
var stones_made := 0
var _set: StructureSet
var _rng := RandomNumberGenerator.new()
## Pairs of stones (positions in the last layout) that touch.
var _pairs := PackedInt32Array()


func _init(structures: StructureSet) -> void:
	_set = structures
	_rng.seed = 9173


## The blocks of `comp` (about to fall together), each big one replaced by
## its stones: linked to each other where they touch, and to the blocks of
## `comp` they touch. The blocks they replace are gone. Blocks reaching
## into `whole` (world space; someone stands there) stay whole.
func loosen(comp: PackedInt32Array, whole := AABB()) -> PackedInt32Array:
	var s := _set
	var out := PackedInt32Array()
	var stones_of := {}  # block -> its stones
	for i in comp:
		var under := (
			whole.has_volume() and whole.intersects(s._xform[i] * AABB(-s._size[i] * 0.5, s._size[i]))
		)
		if under or not _splits(i):
			out.append(i)
			continue
		var boxes := layout(s._size[i])
		if boxes.size() < 2:
			out.append(i)
			continue
		var ids := s.add_stones(i, boxes)
		for k in range(0, _pairs.size(), 2):
			s.link_blocks(ids[_pairs[k]], ids[_pairs[k + 1]])
		stones_of[i] = ids
		out.append_array(ids)
		stones_made += ids.size()
	if stones_of.is_empty():
		return out
	var inside := {}
	for i in comp:
		inside[i] = true
	var eps := StructureSet.CONTACT_EPS
	for i in comp:
		var mine: PackedInt32Array = stones_of.get(i, PackedInt32Array([i]))
		for n in s._neighbors[i]:
			if n < i and inside.has(n) and (stones_of.has(i) or stones_of.has(n)):
				var theirs: PackedInt32Array = stones_of.get(n, PackedInt32Array([n]))
				var touch := s._local[i].grow(eps).intersection(s._local[n].grow(eps))
				_link(mine, theirs, touch)
	for i: int in stones_of:
		s.replace_by_stones(i)
	return out


## Stones of a block of `size` (in its own space, centred on it): a slab
## (thinnest upright) in rows of slabs across its longer side; anything
## else in courses of stones along its longer side, through its thickness
## (in leaves when it is thicker than LEAF). Every other row or course is
## shifted by half a stone, and the joints wander a little. Also lists the
## stones that touch (see _pairs).
func layout(size: Vector3) -> Array[AABB]:
	var out: Array[AABB] = []
	_pairs.clear()
	var lo := -size * 0.5
	var a := 0 if size.x >= size.z else 2  # along it
	var rows: Array[PackedFloat32Array] = []  # cuts along it, per row
	var starts := PackedInt32Array()  # first stone of each row
	if size.min_axis_index() == 1:
		var b := 2 - a  # across it
		var across := _cuts(size[b], SLAB, false)
		for r in across.size() - 1:
			var along := _cuts(size[a], SLAB, r % 2 == 1)
			rows.append(along)
			starts.append(out.size())
			for k in along.size() - 1:
				var p := lo
				var z := Vector3(0.0, size.y, 0.0)
				p[a] += along[k]
				z[a] = along[k + 1] - along[k]
				p[b] += across[r]
				z[b] = across[r + 1] - across[r]
				out.append(AABB(p, z))
			if r > 0:
				_touching(rows[r - 1], starts[r - 1], along, starts[r])
		_in_rows(rows, starts)
		return out
	var through := 2 - a  # the wall's thickness
	var leaves := PackedFloat32Array([0.0, size[through]])
	if size[through] > LEAF:
		leaves = _cuts(size[through], LEAF, false)
	var courses := _cuts(size.y, COURSE, false)
	var per := leaves.size() - 1
	for c in courses.size() - 1:
		for l in per:
			var along := _cuts(size[a], LENGTH, (c + l) % 2 == 1)
			rows.append(along)
			starts.append(out.size())
			for k in along.size() - 1:
				var p := lo
				var z := Vector3.ZERO
				p[a] += along[k]
				z[a] = along[k + 1] - along[k]
				p.y += courses[c]
				z.y = courses[c + 1] - courses[c]
				p[through] += leaves[l]
				z[through] = leaves[l + 1] - leaves[l]
				out.append(AABB(p, z))
			var row := rows.size() - 1
			if l > 0:  # the leaf beside it
				_touching(rows[row - 1], starts[row - 1], along, starts[row])
			if c > 0:  # the course under it
				_touching(rows[row - per], starts[row - per], along, starts[row])
	_in_rows(rows, starts)
	return out


## True when block `i` is laid in stones (a plain box of stone, brick,
## plaster or concrete standing upright).
func _splits(i: int) -> bool:
	var s := _set
	if s._kind[i] != Materials.Kind.CONCRETE or s._round[i] >= 0 or s._piece[i] > 0:
		return false
	if s.walls and s.walls.is_cell(i):
		return false
	return absf(s._xform[i].basis.orthonormalized().y.y) > 0.99


## Where the joints fall along `span` metres for pieces of about `piece`
## (from 0 to span, both ends included): equal pieces, joints wandering a
## little; `odd` shifts them by half a piece (half pieces at the ends). A
## span shorter than a piece stays whole, or is split in two on odd rows.
func _cuts(span: float, piece: float, odd: bool) -> PackedFloat32Array:
	var n := roundi(span / piece)
	var out := PackedFloat32Array([0.0])
	if n <= 1:
		if odd and span > piece * 0.9:
			out.append(span * _rng.randf_range(0.4, 0.6))
		out.append(span)
		return out
	var step := span / n
	var shortest := step * SHORTEST
	for k in n + 1:
		var at := (k + (0.5 if odd else 0.0)) * step
		if at <= 0.0 or at >= span:
			continue
		at += _rng.randf_range(-JITTER, JITTER) * step
		if at - out[out.size() - 1] >= shortest and span - at >= shortest:
			out.append(at)
	out.append(span)
	return out


## Stones next to each other in the same row touch.
func _in_rows(rows: Array[PackedFloat32Array], starts: PackedInt32Array) -> void:
	for r in rows.size():
		for k in rows[r].size() - 2:
			_pairs.append_array(PackedInt32Array([starts[r] + k, starts[r] + k + 1]))


## The stones of two rows side by side (cuts `a` from stone `sa` on, `b`
## from `sb` on) that overlap along them touch.
func _touching(a: PackedFloat32Array, sa: int, b: PackedFloat32Array, sb: int) -> void:
	var i := 0
	var j := 0
	while i < a.size() - 1 and j < b.size() - 1:
		if minf(a[i + 1], b[j + 1]) - maxf(a[i], b[j]) > 0.01:
			_pairs.append_array(PackedInt32Array([sa + i, sb + j]))
		if a[i + 1] < b[j + 1]:
			i += 1
		else:
			j += 1


## Links every stone of `a` to every stone of `b` it touches, of those
## reaching into `region` (structure space; all of them if it is empty).
func _link(a: PackedInt32Array, b: PackedInt32Array, region: AABB) -> void:
	var s := _set
	var eps := StructureSet.CONTACT_EPS
	var near_b := _within(b, region)
	for p in _within(a, region):
		var grown := s._local[p].grow(eps)
		for q in near_b:
			if grown.intersects(s._local[q]):
				s.link_blocks(p, q)


func _within(ids: PackedInt32Array, region: AABB) -> PackedInt32Array:
	if not region.has_volume():
		return ids
	var out := PackedInt32Array()
	for i in ids:
		if _set._local[i].intersects(region):
			out.append(i)
	return out
