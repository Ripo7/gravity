class_name Footing
extends RefCounted
## Whether the standing blocks of a structure keep their footing (see
## StructureSet.settle):
##   - a piece whose centre of mass has left the area it stands on tips over;
##   - a block that rests on nothing hangs from its neighbours; one resting
##     on two supports with its centre between them bridges the gap; one
##     whose centre is off the edge of what it rests on would pivot off it
##     (a floor left on one wall) and can only hang from its neighbours.
##     Hanging and bridging only reach so far: a block held out farther from
##     what carries it down to the ground comes away, with all it carries.
##     So the roof over a big hole falls in instead of floating like a lid.
## The reach is walked from the ground up: a block sitting on one inherits
## its reach; a block hanging is held out as far (horizontally) as its centre
## is from the edge of the standing block the hold starts from, over how far
## its material reaches (a chain is as weak as its farthest link). A floor
## reaches far along its beams (from one wall to the other), little across.
## The walk is kept between checks: when blocks go, only what stood on them
## or hung from them is walked again.

## Metres a block can be held out sideways, by material.
const REACH := {
	Materials.Kind.CONCRETE: 1.5,
	Materials.Kind.WOOD: 4.0,
	Materials.Kind.METAL: 7.0,
	Materials.Kind.ICE: 2.0,
	Materials.Kind.GLASS: 1.0,
}
## Floors and roofs (flat slabs): metres they reach along their beams, and
## across them.
const SLAB_REACH := Vector2(4.0, 1.5)
## A slab whose centre is off the edge of the wall it rests on overhangs it
## (its beams are set into the wall), but only this share of its reach.
const SLAB_OVERHANG := 0.65
const SLAB_THICKNESS := 0.65  ## m: flatter level blocks (sides >= 1 m) are slabs
## A block sits on what it rests on when its centre is over a contact, or
## this close to one (m).
const SEAT_TOLERANCE := 0.35
## A block only hangs from one at least this share of its mass (a moulding
## does not hold up the wall it decorates).
const HOLD_SHARE := 0.25
## Long thin blocks (a moulding, a beam: over SLENDER.x m and SLENDER.y
## times their width) reach this share of their material's reach: a
## moulding whose wall has gone breaks off instead of sticking out.
const SLENDER := Vector2(1.0, 3.0)
const SLENDER_REACH := 0.4
const STEPS_PER_REACH := 16  ## distance resolution of the walk
const MAX_REACH := 3.0  ## reaches; farther counts as not held at all
## The intact structure sets each block's allowance (what stands at first
## always stands): this much over its own reach, at least 1.
const MARGIN := 1.15

var _set: StructureSet
var _reach := PackedFloat32Array()  ## metres, per block
var _slack := PackedFloat32Array()  ## reaches allowed, per block (>= 1)
var _beam := PackedByteArray()  ## slabs: 1 = beams along x, 2 = along z; 0 = not a slab
var _dist := PackedFloat32Array()  ## reaches held out (INF: nothing holds it)
var _from := PackedInt32Array()  ## the block it sits on or hangs from, -1 if none
var _root := PackedInt32Array()  ## the standing block its hold starts from
var _center := PackedVector3Array()  ## structure space, as built
var _foot := PackedVector4Array()  ## (min x, min z, max x, max z)
var _bottom := PackedFloat32Array()
var _far := PackedByteArray()  ## 1 while held out beyond its allowance
var _far_list := PackedInt32Array()  ## blocks flagged far (may hold stale ones)
var _dirty := PackedInt32Array()  ## blocks whose walk must be redone
var _seats := PackedByteArray()  ## during a walk: 0 not known yet, else see _seat


func _init(structures: StructureSet) -> void:
	_set = structures


## Registers block `i` (just added to the set). Indices skipped since the
## last one are stones of falling masonry (see StructureSet.add_stones): the
## footing never looks at them, they only keep their place.
func add(i: int) -> void:
	if _reach.size() < i:
		for arr: Variant in [_reach, _slack, _beam, _dist, _from, _root, _center, _foot, _bottom, _far]:
			arr.resize(i)
	var s := _set
	var size := s._size[i]
	var a := s._local[i]
	var upright := absf(s._xform[i].basis.orthonormalized().y.y) > 0.99
	var slab := upright and size.y < SLAB_THICKNESS and size.x >= 1.0 and size.z >= 1.0
	var long := size[size.max_axis_index()]
	var width := size.x + size.y + size.z - long - size[size.min_axis_index()]
	var slender := long > SLENDER.x and long > width * SLENDER.y
	_reach.append(REACH.get(s._kind[i], 2.5) * (SLENDER_REACH if slender else 1.0))
	_slack.append(1.0)
	# Until its supports say otherwise, a slab's beams cross its short side.
	_beam.append(0 if not slab else (1 if size.x <= size.z else 2))
	_dist.append(INF)
	_from.append(-1)
	_root.append(i)
	_center.append(a.get_center())
	_foot.append(Vector4(a.position.x, a.position.z, a.end.x, a.end.z))
	_bottom.append(a.position.y)
	_far.append(0)
	_dirty.append(i)


## Cell `c` of cracked block `parent` reaches like it.
func inherit(c: int, parent: int) -> void:
	_reach[c] = _reach[parent]
	_slack[c] = _slack[parent]
	_beam[c] = _beam[parent]


## Sets the allowances on a freshly built structure (all its blocks stand).
func calibrate(members: PackedInt32Array) -> void:
	for i in members:
		if _beam[i] > 0:
			_beam[i] = _beam_axis(i)
	_walk(members)
	for i in members:
		_slack[i] = maxf(1.0, _dist[i] * MARGIN) if _dist[i] < INF else INF
		_far[i] = 0
	_dirty.clear()


## Block `i` stopped standing (crushed, knocked out or falling): what sat on
## it or hung from it is walked again.
func removed(i: int) -> void:
	var s := _set
	for m in s._neighbors[i]:
		if _from[m] == i or s._supporters[m].has(i):
			_dirty.append(m)


## Block `i` stands on something else now (it lost its anchor).
func touched(i: int) -> void:
	_dirty.append(i)


## The standing blocks of structure `g` held out farther than they reach,
## in connected parts (each falls as a piece of its own).
func hanging(g: int) -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	if not _dirty.is_empty():
		_rewalk()
	if _far_list.is_empty():
		return out
	var s := _set
	var still := PackedInt32Array()
	for i in _far_list:
		if _far[i] == 1 and s._state[i] == StructureSet.State.STATIC:
			still.append(i)
		else:
			_far[i] = 0
	_far_list = still
	var seen := PackedByteArray()
	seen.resize(s._xform.size())
	for start in still:
		if seen[start] or s._group[start] != g:
			continue
		var part := PackedInt32Array()
		var stack := PackedInt32Array([start])
		seen[start] = 1
		while not stack.is_empty():
			var i := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			part.append(i)
			for n in s._neighbors[i]:
				if not seen[n] and _far[n] == 1 and s._state[n] == StructureSet.State.STATIC:
					seen[n] = 1
					stack.append(n)
		out.append(part)
	return out


## True when the piece's centre of mass is outside the area it stands on.
func tipping(comp: PackedInt32Array) -> bool:
	var s := _set
	var com := Vector2.ZERO
	var mass := 0.0
	var pts := PackedVector2Array()
	for i in comp:
		var c := s._local[i].get_center()
		com += Vector2(c.x, c.z) * s._mass[i]
		mass += s._mass[i]
		if s._grounded[i]:
			pts.append_array(_corners(s._local[i]))
	if mass <= 0.0 or pts.size() < 3:
		return false
	com /= mass
	# It falls away from what still holds it: from the footprint toward the
	# centre of mass.
	return not _inside_section(com, pts)


## The blocks above one of `levels` whose centre of mass has left the
## section of what still crosses that level, or an empty array.
func tipping_above(comp: PackedInt32Array, levels: PackedFloat32Array) -> PackedInt32Array:
	var s := _set
	for h in levels:
		var pts := PackedVector2Array()
		var upper := PackedInt32Array()
		var com := Vector2.ZERO
		var mass := 0.0
		for i in comp:
			var a := s._local[i]
			if a.position.y < h - 0.01 and a.end.y > h + 0.01:
				pts.append_array(_corners(a))
			elif a.position.y >= h - 0.01:
				var c := a.get_center()
				com += Vector2(c.x, c.z) * s._mass[i]
				mass += s._mass[i]
				upper.append(i)
		if upper.size() < 3 or mass <= 0.0 or pts.size() < 3:
			continue
		com /= mass
		if not _inside_section(com, pts):
			return upper
	return PackedInt32Array()


## Walks again what the blocks gone since the last check held up: those
## blocks, and all that sat on them or hung from them in turn.
func _rewalk() -> void:
	var s := _set
	var mark := PackedByteArray()
	mark.resize(s._xform.size())
	var area := PackedInt32Array()
	for i in _dirty:
		if not mark[i] and s._state[i] == StructureSet.State.STATIC:
			mark[i] = 1
			area.append(i)
	_dirty.clear()
	var k := 0
	while k < area.size():
		var x := area[k]
		k += 1
		for m in s._neighbors[x]:
			if not mark[m] and _from[m] == x and s._state[m] == StructureSet.State.STATIC:
				mark[m] = 1
				area.append(m)
	_walk(area, mark)


## How far (in reaches) each block of `area` is held out from what carries
## it down to the ground (blocks outside it keep theirs). `mark` flags the
## blocks of `area` (all of them when empty).
## First, bottom up, what stands straight on the ground (a block's supports
## are always lower); then a Dijkstra with a bucket queue for the rest.
func _walk(area: PackedInt32Array, mark := PackedByteArray()) -> void:
	var s := _set
	var n := s._xform.size()
	if mark.is_empty():
		mark.resize(n)
		for i in area:
			mark[i] = 1
	_seats.resize(n)
	_seats.fill(0)
	var buckets: Array[PackedInt32Array] = []
	for b in int(MAX_REACH * STEPS_PER_REACH) + 1:
		buckets.append(PackedInt32Array())
	var standing := StructureSet.State.STATIC
	var order := PackedInt64Array()
	order.resize(area.size())
	for k in area.size():
		var a := area[k]
		_dist[a] = INF
		_from[a] = -1
		_root[a] = a
		order[k] = (int(roundf(_bottom[a] * 100.0) + 100000) << 20) | a
	order.sort()
	for key in order:
		var a := key & 0xFFFFF
		var on := -1 if s._grounded[a] else _stands_on(a)
		if s._grounded[a] or on >= 0:
			_dist[a] = 0.0
			_from[a] = on
			buckets[0].append(a)
	for a in area:
		if _dist[a] == 0.0:
			continue
		# Held from outside the area: what still stands there keeps its walk.
		for u in s._neighbors[a]:
			if not mark[u] and s._state[u] == standing and _dist[u] < INF:
				var r := u if _dist[u] == 0.0 else _root[u]
				var h := _hold(u, a, r)
				var d := _reached(_dist[u], h)
				if d < _dist[a] and d < MAX_REACH:
					_dist[a] = d
					_from[a] = u
					_root[a] = a if h < 0.0 else r
		if _dist[a] < INF:
			buckets[int(_dist[a] * STEPS_PER_REACH)].append(a)
	for b in buckets.size():
		var k := 0
		while k < buckets[b].size():
			var i := buckets[b][k]
			k += 1
			var di := _dist[i]
			if int(di * STEPS_PER_REACH) != b:
				continue  # reached again closer since
			var r := i if di == 0.0 else _root[i]
			for m in s._neighbors[i]:
				if not mark[m] or s._state[m] != standing or _dist[m] <= di:
					continue
				var h := _hold(i, m, r)
				var d := _reached(di, h)
				if d < _dist[m] and d < MAX_REACH:
					_dist[m] = d
					_from[m] = i
					# What sits on a block is carried by it: what hangs from it
					# is held out from its edge, not from further down.
					_root[m] = m if h < 0.0 else r
					buckets[int(d * STEPS_PER_REACH)].append(m)
	for a in area:
		var far := 1 if _dist[a] > _slack[a] else 0
		if far and not _far[a]:
			_far_list.append(a)
		_far[a] = far


## The reach of a block held by one at `d` with `_hold` giving `h`.
static func _reached(d: float, h: float) -> float:
	return d if h < 0.0 else maxf(d, h)


## How block `m` is held by block `i`: -1 when it sits on it (centred over
## it); INF when `i` cannot hold it (above it, under it off-centre, or far
## lighter: a slab may overhang it a little); else
## how far it is held out (in reaches): from where it rests on `i` when it
## bridges a gap, else from the edge of block `root`, the standing block its
## hold starts from.
func _hold(i: int, m: int, root: int) -> float:
	var s := _set
	var c := _center[m]
	var f := _foot[root]
	if s._supporters[m].has(i):
		var a := _foot[m]
		var b := _foot[i]
		if _over(c, a, b):
			return -1.0
		# Centred over another support (it is held through that one), or
		# off the edge of them all: a block would pivot off (no hold from
		# `i`), a slab overhangs a little.
		if _seats[m] == 0:
			_seats[m] = _seat(m)
		if _seats[m] == 1 or (_seats[m] == 3 and _beam[m] == 0):
			return INF
		f = Vector4(maxf(a.x, b.x), maxf(a.y, b.y), minf(a.z, b.z), minf(a.w, b.w))
		if _seats[m] == 3:
			return _lever(m, c, f) / SLAB_OVERHANG
	elif _bottom[i] > _bottom[m] + StructureSet.CONTACT_EPS or s._mass[i] < s._mass[m] * HOLD_SHARE:
		return INF
	else:
		# A block resting on something under its centre goes where that
		# goes: it does not hang from its neighbours instead.
		if _seats[m] == 0:
			_seats[m] = _seat(m)
		if _seats[m] == 1:
			return INF
	return _lever(m, c, f)


## How far (in reaches) block `m`, centred at `c`, is held out from the
## footprint `f`: a slab reaches far along its beams, little across them.
func _lever(m: int, c: Vector3, f: Vector4) -> float:
	var d := Vector2(c.x - clampf(c.x, f.x, f.z), c.z - clampf(c.z, f.y, f.w))
	var length := d.length()
	if length < 0.01:
		return 0.0
	if _beam[m] == 0:
		return length / _reach[m]
	var along := absf(d.x if _beam[m] == 1 else d.y) / length
	return length / lerpf(SLAB_REACH.y, SLAB_REACH.x, along * along)


## The block that block `m` stands straight on the ground through (or -1):
## one it rests on, that does, with its centre over it; or one it rests on
## (a floor) right where that rests on one that does: the floor just
## passes the weight down.
func _stands_on(m: int) -> int:
	var s := _set
	var c := _center[m]
	for i in s._supporters[m]:
		if s._state[i] != StructureSet.State.STATIC:
			continue
		if _dist[i] == 0.0 and _over(c, _foot[m], _foot[i]):
			return i
		for j in s._supporters[i]:
			if _dist[j] == 0.0 and s._state[j] == StructureSet.State.STATIC and _over(c, _foot[i], _foot[j]):
				return i
	return -1


## True when point `c` is over the overlap of footprints `f` and `g` (or
## within SEAT_TOLERANCE of it).
static func _over(c: Vector3, f: Vector4, g: Vector4) -> bool:
	var t := SEAT_TOLERANCE
	return (
		c.x >= maxf(f.x, g.x) - t
		and c.x <= minf(f.z, g.z) + t
		and c.z >= maxf(f.y, g.y) - t
		and c.z <= minf(f.w, g.w) + t
	)


## How block `m` rests on the standing blocks under it: 1 its centre is over
## (or near) one of them; 2 between them (it bridges the gap); 3 off the edge
## of them all (or on nothing).
func _seat(m: int) -> int:
	var s := _set
	var f := _foot[m]
	var c := _center[m]
	var t := SEAT_TOLERANCE
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for j in s._supporters[m]:
		if s._state[j] != StructureSet.State.STATIC:
			continue
		var g := _foot[j]
		var x0 := maxf(f.x, g.x)
		var z0 := maxf(f.y, g.y)
		var x1 := minf(f.z, g.z)
		var z1 := minf(f.w, g.w)
		if c.x >= x0 - t and c.x <= x1 + t and c.z >= z0 - t and c.z <= z1 + t:
			return 1
		lo = Vector2(minf(lo.x, x0), minf(lo.y, z0))
		hi = Vector2(maxf(hi.x, x1), maxf(hi.y, z1))
	if c.x >= lo.x - t and c.x <= hi.x + t and c.z >= lo.y - t and c.z <= hi.y + t:
		return 2
	return 3


## Slab `i`'s beams run across the strips it rests on (walls): along x when
## those are long in z, along z when they are long in x. A slab lying flat
## on another (roof courses on a floor) runs like it.
func _beam_axis(i: int) -> int:
	var s := _set
	var f := _foot[i]
	var wx := 0.0
	var wz := 0.0
	var flat := 0.0
	var under := -1
	for j in s._supporters[i]:
		var g := _foot[j]
		var ox := maxf(minf(f.z, g.z) - maxf(f.x, g.x), 0.0)
		var oz := maxf(minf(f.w, g.w) - maxf(f.y, g.y), 0.0)
		wx += ox
		wz += oz
		if ox * oz > flat:
			flat = ox * oz
			under = j
	if under >= 0 and _beam[under] > 0 and flat > 0.6 * (f.z - f.x) * (f.w - f.y):
		return _beam[under]
	if wx == 0.0 and wz == 0.0:
		return _beam[i]
	return 2 if wx > wz else 1


## True when `com` is inside the convex section of `pts`, shrunk a little
## so knife-edge balance still tips; sets the set's tipping direction.
func _inside_section(com: Vector2, pts: PackedVector2Array) -> bool:
	var hull := Geometry2D.convex_hull(pts)
	if hull.size() < 3:
		return false
	var centroid := Vector2.ZERO
	for p in hull:
		centroid += p
	centroid /= hull.size()
	var inset := PackedVector2Array()
	for p in hull:
		inset.append(p + (centroid - p).limit_length(0.06))
	_set._tip = com - centroid
	return Geometry2D.is_point_in_polygon(com, inset)


static func _corners(a: AABB) -> PackedVector2Array:
	return PackedVector2Array(
		[
			Vector2(a.position.x, a.position.z),
			Vector2(a.end.x, a.position.z),
			Vector2(a.end.x, a.end.z),
			Vector2(a.position.x, a.end.z),
		]
	)
