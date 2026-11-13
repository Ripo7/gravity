class_name Structure
extends Node3D
## Everything that can break. A building is given as boxes (walls, slabs,
## pillars). Each box is cut into irregular shards (Fracture), and every
## shard is bonded to the shards it touches. Shards that keep a chain of
## bonds down to the ground stand; Support works that out, and breaks the
## bonds that carry too much. What no longer holds comes off as rigid pieces
## (Pieces), which break again where they land. A shard that is hit hard
## is cut once more, there and then, and leaves in crumbs. Nothing is ever
## deleted: a shard stands, is part of a piece, or is in crumbs.

## Something came off: where, how much (m3) and how fast.
signal released(at: Vector3, volume: float, velocity: Vector3)

const LAYER_WORLD := 1
const LAYER_STRUCTURE := 2
const LAYER_DEBRIS := 4
const LAYER_PLAYER := 8
## Loose pieces being drawn into an orb: nothing sees them (you would be
## carried off standing on one), they only stop at the ground and at what
## still stands.
const LAYER_GRIPPED := 16
## Shards are about this big (m).
const GRAIN := 0.6
const DENSITY := 2400.0  ## kg/m3
## Collision shapes are a little smaller than the shards: pieces that were
## one a moment ago do not start out pressed against each other.
const SHRINK := 0.96
## Shards of two boxes closer than this are bonded (m).
const TOUCH := 0.02
## A bond smaller than this (m2) is not worth keeping.
const MIN_BOND := 0.004
## What comes off in one go is cut in pieces of at most this many shards
## (or MAX_CHUNK_BUSY while a lot is already moving, see Pieces.BUSY).
const MAX_CHUNK := 32
const MAX_CHUNK_BUSY := 45
## A blast below this does nothing to a shard; at 1 it tears it out, and
## from about SHATTER on the shard leaves in crumbs.
const CRACK := 0.3
const SHATTER := 2.0
## A shard thrown out faster than this (m/s) clears what stands around it
## (Pieces.CLEAR_STEPS).
const TORN_SPEED := 5.0
## A shard that crumbles is cut into crumbs of about this volume (m3); a
## shard too small for two stays whole.
const CRUMB := 0.02
const MAX_CRUMBS := 6
const CELL := 1.0  ## m, the grid used to find shards near a point
const WARM_PER_STEP := 6
## While whole, a box collides as a few plain blocks of at most this size
## (m); the first shard to leave a block turns it into its shards.
const BLOCK := 2.5
## When a lot lets go at once it comes off over a few steps, about this many
## shards per step: making all the bodies in one step is a visible hitch.
const FALL_PER_STEP := 28

# The cuts already made, by size and seed: rebuilding does not cut again.
static var _cuts := {}

## Shards are numbered 0 .. count - 1. Crumbs get the numbers after them,
## up to total - 1, as they are made (a crumb that is gone leaves its number
## to the next one): no bonds, never standing. The first six arrays below
## cover both.
var count := 0
var total := 0
## No more crumbs than this at a time (set it before build()): each is one
## more body to move.
var most_crumbs := 400
var crumbs_out := 0  ## how many crumbs there are now
var crumbs_of := {}  ## shard: the crumbs it broke into that are still there
var crumbled_count := 0  ## how many shards have broken into crumbs
## Blocks of ground that does not break, other than the ground itself (a
## ledge, a platform): shards that touch one are held by it. Add them before
## build().
var footings: Array[AABB] = []
## Per shard: where it stands (its centre of mass), size, and its state.
var centroid := PackedVector3Array()
var volume := PackedFloat32Array()
var mass := PackedFloat32Array()
var radius := PackedFloat32Array()
var piece_of := PackedInt32Array()  ## its piece once it has come off, else -1
var corners: Array[PackedVector3Array] = []  ## its collision corners, around its centre
var element := PackedInt32Array()  ## the box it was cut from
var held := PackedByteArray()  ## 1 while it stands
var anchored := PackedByteArray()  ## 1 if it rests on the ground
## Bonds between two shards: 1 whole .. 0 broken.
var bond_a := PackedInt32Array()
var bond_b := PackedInt32Array()
var bond_area := PackedFloat32Array()
var bond_health := PackedFloat32Array()
var bond_mid := PackedVector3Array()
## Bonds of shard i: adj_bond/adj_other[adj_first[i] .. adj_first[i + 1]].
var adj_first := PackedInt32Array()
var adj_bond := PackedInt32Array()
var adj_other := PackedInt32Array()
var held_count := 0
var total_volume := 0.0
var mesh: ShardMesh
var pieces: Pieces
var support := Support.new()
var solve_usec := 0  ## the longest step of the last look at what holds
var cut_seed := 1

var _lo := PackedVector3Array()
var _hi := PackedVector3Array()
var _shape: Array[RID] = []
var _own: Array[RID] = []  # a standing shard's own static body, once its box is broken
var _kick := PackedVector3Array()  # push received while standing, used if it comes off
var _box_shards: Array[PackedInt32Array] = []
var _box_lo := PackedVector3Array()
var _box_hi := PackedVector3Array()
var _box_blocks: Array[PackedInt32Array] = []
# Per block of a box: its body while it is whole, its shape, shards, bounds.
var _solid: Array[RID] = []
var _block_shape: Array[RID] = []
var _block_shards: Array[PackedInt32Array] = []
var _block_lo := PackedVector3Array()
var _block_hi := PackedVector3Array()
var _rid_shard := {}
var _rid_block := {}
var _cells := {}  # Vector3i -> PackedInt32Array of shards standing there when built
var _mark := PackedInt32Array()
var _stamp := 0
var _dirty := false
var _warm := 0
var _kicked := PackedInt32Array()
var _falling: Array[PackedInt32Array] = []  # chunks nothing holds any more, the lowest last
var _falling_push := PackedVector3Array()
var _falling_low := PackedFloat32Array()
var _leaving := PackedByteArray()  # 1 for a shard in _falling
var _built := false
# Only while building: every shard's corners and faces in the world.
var _points: Array[PackedVector3Array] = []
var _planes: Array = []
var _spare := PackedInt32Array()  # the numbers of crumbs that are gone
var _crumb_shard := PackedInt32Array()  # per crumb (from `count` on): the shard it was cut from
# To cut a shard into crumbs later: how Fracture made it, and its box.
var _cut_of: Array[Fracture.Shard] = []
var _box_xf: Array[Transform3D] = []
var _box_tint := PackedColorArray()


func _init() -> void:
	mesh = ShardMesh.new()
	add_child(mesh)
	pieces = Pieces.new()
	pieces.structure = self
	add_child(pieces)


func _exit_tree() -> void:
	for rid in _own:
		if rid.is_valid():
			PhysicsServer3D.free_rid(rid)
	for rid in _solid:
		if rid.is_valid():
			PhysicsServer3D.free_rid(rid)
	pieces.free_bodies()
	for rid in _shape:
		if rid.is_valid():
			PhysicsServer3D.free_rid(rid)
	for rid in _block_shape:
		PhysicsServer3D.free_rid(rid)


## Adds a box of `size` at `xf` and cuts it into shards. Call build() once
## every box is in.
func add_box(xf: Transform3D, size: Vector3, tint := Color.WHITE, grain := GRAIN) -> int:
	var box := _box_shards.size()
	var cut_key := [size, grain, cut_seed * 7919 + box * 104729]
	if not _cuts.has(cut_key):
		_cuts[cut_key] = Fracture.cut(size, grain, cut_key[2])
	var cut: Array[Fracture.Shard] = _cuts[cut_key]
	_box_xf.append(xf)
	_box_tint.append(tint)
	var base := count
	var mine := PackedInt32Array()
	var box_lo := Vector3.INF
	var box_hi := -Vector3.INF
	for sh in cut:
		var i := count
		count += 1
		mine.append(i)
		_cut_of.append(sh)
		var c := xf * sh.centroid
		var world := PackedVector3Array()
		var around := PackedVector3Array()
		var lo := Vector3.INF
		var hi := -Vector3.INF
		var reach := 0.0
		for p in sh.points:
			var w := xf * p
			world.append(w)
			around.append((w - c) * SHRINK)
			lo = lo.min(w)
			hi = hi.max(w)
			reach = maxf(reach, w.distance_to(c))
		var faces: Array[Plane] = []
		for f in sh.faces.size():
			faces.append(Plane(xf.basis * sh.normals[f], world[sh.faces[f][0]]))
			var other := sh.others[f]
			if other > i - base:  # each pair once
				var mid := Vector3.ZERO
				for corner in sh.faces[f]:
					mid += world[corner]
				_add_bond(i, base + other, sh.areas[f], mid / sh.faces[f].size())
		centroid.append(c)
		volume.append(sh.volume)
		mass.append(sh.volume * DENSITY)
		radius.append(reach)
		element.append(box)
		held.append(1)
		anchored.append(0)
		piece_of.append(-1)
		corners.append(around)
		_lo.append(lo)
		_hi.append(hi)
		_shape.append(RID())
		_own.append(RID())
		_kick.append(Vector3.ZERO)
		_points.append(world)
		_planes.append(faces)
		box_lo = box_lo.min(lo)
		box_hi = box_hi.max(hi)
		total_volume += sh.volume
		mesh.add_shard(i, base, world, sh, xf.basis, tint)
	_box_shards.append(mine)
	_box_lo.append(box_lo)
	_box_hi.append(box_hi)
	_add_blocks(xf, size, cut, base)
	return box


## Bonds the boxes that touch, anchors what rests at `ground` height, and
## gets everything ready. Nothing can be added after this.
func build(ground := 0.0) -> void:
	_bond_boxes()
	for i in count:
		if _lo[i].y < ground + TOUCH:
			anchored[i] = 1
		else:
			var box := AABB(_lo[i], _hi[i] - _lo[i]).grow(TOUCH)
			for footing in footings:
				if footing.intersects(box):
					anchored[i] = 1
					break
		# (Put back after adding: a packed array taken out of a dictionary
		# is a copy.)
		var cell := Vector3i((centroid[i] / CELL).floor())
		var there: PackedInt32Array = _cells.get(cell, PackedInt32Array())
		there.append(i)
		_cells[cell] = there
	total = count
	_index_bonds()
	held_count = count
	_mark.resize(count)
	_leaving.resize(count)
	# Room for the crumbs to come, and one more id, never drawn: what a
	# crumb's cut faces look at.
	var room := count + most_crumbs
	mesh.build(room + 1, room + 1, count)
	pieces.setup(room)
	support.setup(self)
	_points.clear()
	_planes.clear()
	_built = true


func _physics_process(_delta: float) -> void:
	# Collision shapes are made a few per step from the start, so that the
	# first blast does not have to make a whole wall's worth at once.
	for n in WARM_PER_STEP:
		if _warm >= count:
			break
		shape_of(_warm)
		_warm += 1
	if not _falling.is_empty():
		# The look waits until all that it found unheld has come off.
		_drop_some()
		return
	if not support.busy:
		if not _dirty:
			return
		_dirty = false
		support.begin(self)
		solve_usec = 0
	var t := Time.get_ticks_usec()
	match support.advance(self):
		Support.REACHED:
			for group in support.unheld:
				_let_go(group)
			for i in _kicked:
				_kick[i] = Vector3.ZERO
			_kicked.clear()
			_drop_some()
		Support.WEIGHED:
			for b in support.overloaded:
				break_bond(b)
	solve_usec = maxi(solve_usec, Time.get_ticks_usec() - t)


## The shards that stood within `reach` of `at` when the building was whole
## (wherever they are now).
func shards_near(at: Vector3, reach: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var lo := Vector3i(((at - Vector3.ONE * reach) / CELL).floor())
	var hi := Vector3i(((at + Vector3.ONE * reach) / CELL).floor())
	for z in range(lo.z, hi.z + 1):
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var found: Variant = _cells.get(Vector3i(x, y, z))
				if found == null:
					continue
				for i: int in found:
					if centroid[i].distance_squared_to(at) < reach * reach:
						out.append(i)
	return out


## A blast reaches standing shard `i`. `force` 1 or more tears it out and
## throws it at `velocity`; less only cracks the bonds that hold it.
func strike(i: int, force: float, velocity: Vector3) -> void:
	if held[i] == 0 or force < CRACK:
		return
	if force >= SHATTER * randf_range(0.85, 1.35) and randf() < pieces.crumble_chance():
		shatter(i, velocity)
		return
	if force >= 1.0:
		blow(i, velocity)
		return
	if _kick[i] == Vector3.ZERO:
		_kicked.append(i)
	_kick[i] += velocity * force
	for k in range(adj_first[i], adj_first[i + 1]):
		var b := adj_bond[k]
		if bond_health[b] > 0.0:
			damage_bond(b, (force - CRACK) * randf_range(0.5, 1.5))


## Tears standing shard `i` out: it leaves on its own at `velocity`.
func blow(i: int, velocity: Vector3) -> void:
	if held[i] == 0:
		return
	var spin := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * minf(velocity.length(), 12.0)
	_release(PackedInt32Array([i]), velocity, spin, false, velocity.length() > TORN_SPEED)
	_dirty = true


## Standing shard `i` is hit hard enough to break up: it leaves in crumbs,
## thrown at about `velocity`. (Whole, if it cannot crumble or too much is
## going on, see Pieces.can_crumble.)
func shatter(i: int, velocity: Vector3) -> void:
	if held[i] == 0:
		return
	if not pieces.can_crumble(i):
		blow(i, velocity)
		return
	_release(PackedInt32Array([i]), velocity, Vector3.ZERO, true, velocity.length() > TORN_SPEED)
	_dirty = true


## Something heavy hit the standing building at `at`: about `amount` m3 of
## it is knocked out there, nearest first, and leaves at `velocity`. The
## nearest half of it leaves in crumbs.
func crush(at: Vector3, amount: float, velocity: Vector3) -> void:
	var near: Array[Vector2] = []  # (distance to its surface, shard)
	for i in shards_near(at, 1.6):
		if held[i] == 1:
			near.append(Vector2(maxf(centroid[i].distance_to(at) - radius[i], 0.0), i))
	near.sort()
	var left := amount
	for n in near:
		var i := int(n.y)
		if left < volume[i] * 0.5:
			strike(i, clampf(CRACK + left / volume[i], 0.0, 0.95), velocity)
			break
		left -= volume[i]
		if left > amount * 0.5:
			shatter(i, velocity * randf_range(0.3, 0.7))
		else:
			blow(i, velocity * randf_range(0.3, 0.7))


func damage_bond(b: int, amount: float) -> void:
	if bond_health[b] <= 0.0:
		return
	bond_health[b] -= amount
	if bond_health[b] <= 0.0:
		break_bond(b)


func break_bond(b: int) -> void:
	bond_health[b] = 0.0
	# Between two standing shards: what holds has to be looked at again.
	# (Inside a piece, Pieces sees to it.)
	if held[bond_a[b]] == 1 and held[bond_b[b]] == 1:
		_dirty = true


## What a physics body is: a standing shard (its index), a whole block of
## a box (-1 - block), or nothing of this structure (-1000000).
func owner_of(rid: RID) -> int:
	if _rid_shard.has(rid):
		return _rid_shard[rid]
	if _rid_block.has(rid):
		return -1 - int(_rid_block[rid])
	return -1000000


## The collision shape of shard `i` (made the first time it is needed).
func shape_of(i: int) -> RID:
	if not _shape[i].is_valid():
		var shape := PhysicsServer3D.convex_polygon_shape_create()
		PhysicsServer3D.shape_set_data(shape, corners[i])
		_shape[i] = shape
	return _shape[i]


## Where shard or crumb `i` is now (its centre of mass); for a shard that
## broke into crumbs, the middle of them.
func place_of(i: int) -> Vector3:
	if i < count and crumbs_of.has(i) and not (crumbs_of[i] as PackedInt32Array).is_empty():
		var sum := Vector3.ZERO
		for c: int in crumbs_of[i]:
			sum += place_of(c)
		return sum / (crumbs_of[i] as PackedInt32Array).size()
	var piece := piece_of[i]
	if piece < 0:
		return centroid[i]
	return pieces.transform_of(piece) * (centroid[i] - pieces.origin[piece])


## True if shard `i` is big enough to be cut into crumbs and there is room
## left for them.
func can_crumble(i: int) -> bool:
	return i < count and volume[i] >= CRUMB * 1.5 and crumbs_out + MAX_CRUMBS <= most_crumbs


## Cuts shard `i` into crumbs and gives them their numbers (what becomes of
## the shard and of them is the caller's business). Empty if it cannot be.
func make_crumbs(i: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if not can_crumble(i):
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = cut_seed * 31 + i * 7919
	var bits := Fracture.crumble(_cut_of[i], mini(roundi(volume[i] / CRUMB), MAX_CRUMBS), rng)
	if bits.is_empty():
		return out
	var xf := _box_xf[element[i]]
	crumbled_count += 1
	for bit in bits:
		var c := xf * bit.centroid
		var world := PackedVector3Array()
		var around := PackedVector3Array()
		var reach := 0.0
		for p in bit.points:
			var w := xf * p
			world.append(w)
			around.append((w - c) * SHRINK)
			reach = maxf(reach, w.distance_to(c))
		# The number of a crumb that is gone, or a new one.
		var id := total
		if _spare.is_empty():
			total += 1
			centroid.append(c)
			volume.append(0.0)
			mass.append(0.0)
			radius.append(0.0)
			piece_of.append(-1)
			corners.append(around)
			_shape.append(RID())
			_crumb_shard.append(i)
		else:
			id = _spare[_spare.size() - 1]
			_spare.remove_at(_spare.size() - 1)
		centroid[id] = c
		volume[id] = bit.volume
		mass[id] = bit.volume * DENSITY
		radius[id] = reach
		piece_of[id] = -1
		corners[id] = around
		_crumb_shard[id - count] = i
		mesh.add_shard(id, 0, world, bit, xf.basis, _box_tint[element[i]], count + most_crumbs)
		out.append(id)
	crumbs_out += out.size()
	crumbs_of[i] = out.duplicate()
	return out


## Crumb `id` is gone for good (an orb swallowed it): its number and its
## room are free for another.
func crumb_gone(id: int) -> void:
	crumbs_out -= 1
	_spare.append(id)
	mesh.forget(id)
	if _shape[id].is_valid():
		PhysicsServer3D.free_rid(_shape[id])
		_shape[id] = RID()
	var of: PackedInt32Array = crumbs_of[_crumb_shard[id - count]]
	of.remove_at(of.find(id))
	crumbs_of[_crumb_shard[id - count]] = of


## Volume (m3) still standing.
func standing_volume() -> float:
	var v := 0.0
	for i in count:
		if held[i] == 1:
			v += volume[i]
	return v


## Asks for a fresh look at what holds (after bonds were changed by hand).
func recheck() -> void:
	_dirty = true


func _add_bond(a: int, b: int, area: float, mid: Vector3) -> void:
	if area < MIN_BOND:
		return
	bond_a.append(a)
	bond_b.append(b)
	bond_area.append(area)
	bond_health.append(1.0)
	bond_mid.append(mid)


## Bonds between shards of different boxes that touch (a slab on its walls,
## two walls at a corner).
func _bond_boxes() -> void:
	var grow := Vector3.ONE * TOUCH
	for e in _box_shards.size():
		for f in range(e + 1, _box_shards.size()):
			var lo := _box_lo[e].max(_box_lo[f]) - grow
			var hi := _box_hi[e].min(_box_hi[f]) + grow
			if lo.x > hi.x or lo.y > hi.y or lo.z > hi.z:
				continue
			var mine := _within(_box_shards[e], lo, hi)
			var theirs := _within(_box_shards[f], lo, hi)
			for a in mine:
				for b in theirs:
					var from := _lo[a].max(_lo[b]) - grow
					var to := _hi[a].min(_hi[b]) + grow
					if from.x > to.x or from.y > to.y or from.z > to.z:
						continue
					if not (_apart(a, b) or _apart(b, a)):
						var d := to - from
						var thin := minf(d.x, minf(d.y, d.z))
						var area := d.x * d.y * d.z / maxf(thin, 1e-4)
						_add_bond(a, b, area, (from + to) * 0.5)


func _within(shards: PackedInt32Array, lo: Vector3, hi: Vector3) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in shards:
		if not (
			_lo[i].x > hi.x
			or _hi[i].x < lo.x
			or _lo[i].y > hi.y
			or _hi[i].y < lo.y
			or _lo[i].z > hi.z
			or _hi[i].z < lo.z
		):
			out.append(i)
	return out


## True when a face of shard `a` has all of shard `b` on its outer side.
func _apart(a: int, b: int) -> bool:
	for face: Plane in _planes[a]:
		var outside := true
		for p in _points[b]:
			if face.distance_to(p) < TOUCH:
				outside = false
				break
		if outside:
			return true
	return false


func _index_bonds() -> void:
	var degree := PackedInt32Array()
	degree.resize(count + 1)
	for b in bond_a.size():
		degree[bond_a[b] + 1] += 1
		degree[bond_b[b] + 1] += 1
	# (Crumbs to come have no bonds: their ranges are empty.)
	adj_first.resize(count + most_crumbs + 1)
	for i in count:
		adj_first[i + 1] = adj_first[i] + degree[i + 1]
	for i in range(count, count + most_crumbs):
		adj_first[i + 1] = adj_first[count]
	adj_bond.resize(bond_a.size() * 2)
	adj_other.resize(bond_a.size() * 2)
	var next := adj_first.duplicate()
	for b in bond_a.size():
		for side in 2:
			var i := bond_a[b] if side == 0 else bond_b[b]
			adj_bond[next[i]] = b
			adj_other[next[i]] = bond_b[b] if side == 0 else bond_a[b]
			next[i] += 1


## A set of shards that no longer holds is about to come off: in one piece
## if it is small, cut in chunks if it is big. It will leave with the push
## its shards got from the blast that freed it.
func _let_go(group: PackedInt32Array) -> void:
	for chunk in _chunks(group):
		var push := Vector3.ZERO
		var weight := 0.0
		var low := INF
		for i in chunk:
			push += _kick[i] * mass[i]
			weight += mass[i]
			low = minf(low, _lo[i].y)
			_leaving[i] = 1
		# Kept sorted, the lowest last: what is underneath goes first.
		var at := _falling.size()
		while at > 0 and _falling_low[at - 1] < low:
			at -= 1
		_falling.insert(at, chunk)
		_falling_low.insert(at, low)
		_falling_push.insert(at, push / weight * 0.5)


## Some of what waits in _falling comes off, the lowest first.
func _drop_some() -> void:
	var left := FALL_PER_STEP
	while left > 0 and not _falling.is_empty():
		var chunk: PackedInt32Array = _falling.pop_back()
		var push := _falling_push[_falling_push.size() - 1]
		_falling_push.remove_at(_falling_push.size() - 1)
		_falling_low.remove_at(_falling_low.size() - 1)
		# A blast may have torn some of it out while it waited.
		var still := PackedInt32Array()
		for i in chunk:
			_leaving[i] = 0
			if held[i] == 1:
				still.append(i)
		if still.is_empty():
			continue
		left -= still.size()
		if still.size() == chunk.size():
			_release(still, push)
		else:
			for part in _chunks(still, true):
				_release(part, push)


## `group` cut in connected chunks of MAX_CHUNK shards at most (see there). A small
## group is taken to be in one part unless `check`.
func _chunks(group: PackedInt32Array, check := false) -> Array[PackedInt32Array]:
	var most := MAX_CHUNK if pieces.awake <= Pieces.BUSY else MAX_CHUNK_BUSY
	if group.size() <= most and not check:
		return [group]
	_stamp += 2
	var todo := _stamp - 1
	for i in group:
		_mark[i] = todo
	var out: Array[PackedInt32Array] = []
	for start in group:
		if _mark[start] != todo:
			continue
		var chunk := PackedInt32Array([start])
		_mark[start] = _stamp
		var head := 0
		while head < chunk.size() and chunk.size() < most:
			var i := chunk[head]
			head += 1
			for k in range(adj_first[i], adj_first[i + 1]):
				var j := adj_other[k]
				if _mark[j] == todo and bond_health[adj_bond[k]] > 0.0 and chunk.size() < most:
					_mark[j] = _stamp
					chunk.append(j)
		out.append(chunk)
	return out


## Shards `group` stop standing and become one rigid piece; or, `in_crumbs`,
## the one shard of the group breaks into its crumbs. `torn`: thrown out by
## a blast.
func _release(
	group: PackedInt32Array, velocity: Vector3, spin := Vector3.ZERO, in_crumbs := false, torn := false
) -> void:
	_stamp += 1
	var lo := Vector3.INF
	var hi := -Vector3.INF
	var at := Vector3.ZERO
	var size := 0.0
	for i in group:
		held[i] = 0
		_mark[i] = _stamp
		lo = lo.min(_lo[i])
		hi = hi.max(_hi[i])
		at += centroid[i] * volume[i]
		size += volume[i]
	held_count -= group.size()
	var reuse := RID()
	for i in group:
		# The whole blocks it was part of (or reached into) become shards.
		for block in _box_blocks[element[i]]:
			if (
				_solid[block].is_valid()
				and _lo[i].x < _block_hi[block].x
				and _hi[i].x > _block_lo[block].x
				and _lo[i].y < _block_hi[block].y
				and _hi[i].y > _block_lo[block].y
				and _lo[i].z < _block_hi[block].z
				and _hi[i].z > _block_lo[block].z
			):
				_open(block)
		# Its bonds to what it leaves behind are gone.
		for k in range(adj_first[i], adj_first[i + 1]):
			if _mark[adj_other[k]] != _stamp:
				bond_health[adj_bond[k]] = 0.0
		if _own[i].is_valid():
			_rid_shard.erase(_own[i])
			if group.size() == 1 and not in_crumbs:
				reuse = _own[i]
			else:
				PhysicsServer3D.free_rid(_own[i])
			_own[i] = RID()
	# What was resting on it has to move again.
	pieces.thaw_box(lo - Vector3.ONE * 0.3, hi + Vector3(0.3, 0.6, 0.3))
	if in_crumbs:
		pieces.crumble(group[0], Transform3D.IDENTITY, velocity, spin, torn)
	else:
		pieces.spawn(group, Transform3D.IDENTITY, velocity, spin, reuse, torn)
	released.emit(at / size, size, velocity)


## A whole block takes its first damage: from now on each of its standing
## shards has its own body, so holes are real.
func _open(block: int) -> void:
	_rid_block.erase(_solid[block])
	PhysicsServer3D.free_rid(_solid[block])
	_solid[block] = RID()
	for i in _block_shards[block]:
		# (Not for a shard about to come off: it would be for a step or two.)
		if held[i] == 1 and _leaving[i] == 0:
			var body := _static_body(shape_of(i), Transform3D(Basis(), centroid[i]))
			_own[i] = body
			_rid_shard[body] = i


## The plain blocks a whole box collides as, and which shards are in each.
func _add_blocks(xf: Transform3D, size: Vector3, cut: Array[Fracture.Shard], base: int) -> void:
	var n := Vector3i((size / BLOCK).ceil()).maxi(1)
	var each := size / Vector3(n)
	var first := _solid.size()
	var blocks := PackedInt32Array()
	for z in n.z:
		for y in n.y:
			for x in n.x:
				var shape := PhysicsServer3D.box_shape_create()
				PhysicsServer3D.shape_set_data(shape, each * 0.5)
				var middle := (Vector3(x, y, z) + Vector3.ONE * 0.5) * each - size * 0.5
				var body := _static_body(shape, xf * Transform3D(Basis(), middle))
				var bounds := xf * AABB(middle - each * 0.5, each)
				_rid_block[body] = _solid.size()
				blocks.append(_solid.size())
				_solid.append(body)
				_block_shape.append(shape)
				_block_shards.append(PackedInt32Array())
				_block_lo.append(bounds.position)
				_block_hi.append(bounds.end)
	for k in cut.size():
		var at := Vector3i(((cut[k].centroid + size * 0.5) / each).floor()).clamp(
			Vector3i.ZERO, n - Vector3i.ONE
		)
		_block_shards[first + (at.z * n.y + at.y) * n.x + at.x].append(base + k)
	_box_blocks.append(blocks)


func _static_body(shape: RID, xf: Transform3D) -> RID:
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_add_shape(body, shape)
	PhysicsServer3D.body_set_collision_layer(body, LAYER_STRUCTURE)
	PhysicsServer3D.body_set_collision_mask(body, 0)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
	PhysicsServer3D.body_set_space(body, get_world_3d().space)
	return body
