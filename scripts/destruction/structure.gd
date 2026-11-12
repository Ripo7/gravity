class_name Structure
extends Node3D
## Everything that can break. A building is given as boxes (walls, slabs,
## pillars). Each box is cut into irregular shards (Fracture), and every
## shard is bonded to the shards it touches. Shards that keep a chain of
## bonds down to the ground stand; Support works that out, and breaks the
## bonds that carry too much. What no longer holds comes off as rigid pieces
## (Pieces), which break again where they land. Nothing is ever deleted: a
## shard either stands or is part of a piece.

## Something came off: where, how much (m3) and how fast.
signal released(at: Vector3, volume: float, velocity: Vector3)

const LAYER_WORLD := 1
const LAYER_STRUCTURE := 2
const LAYER_DEBRIS := 4
const LAYER_PLAYER := 8
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
## Physics steps between two looks at what still holds: a collapse spreads
## over a few frames instead of happening all at once.
const LOOK_EVERY := 2
## What comes off in one go is cut in pieces of at most this many shards.
const MAX_CHUNK := 45
## A blast below this does nothing to a shard; at 1 it tears it out.
const CRACK := 0.3
const CELL := 1.0  ## m, the grid used to find shards near a point

var count := 0
## Per shard: where it stands (its centre of mass), size, and its state.
var centroid := PackedVector3Array()
var volume := PackedFloat32Array()
var mass := PackedFloat32Array()
var radius := PackedFloat32Array()
var element := PackedInt32Array()  ## the box it was cut from
var held := PackedByteArray()  ## 1 while it stands
var anchored := PackedByteArray()  ## 1 if it rests on the ground
var piece_of := PackedInt32Array()  ## its piece once it has come off, else -1
var corners: Array[PackedVector3Array] = []  ## its collision corners, around its centre
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
var solve_usec := 0  ## time the last look at what holds took (the longer half)
var cut_seed := 1

var _lo := PackedVector3Array()
var _hi := PackedVector3Array()
var _shape: Array[RID] = []
var _own: Array[RID] = []  # a standing shard's own static body, once its box is broken
var _kick := PackedVector3Array()  # push received while standing, used if it comes off
var _solid: Array[RID] = []  # per box: one body while it is whole
var _box_shape: Array[RID] = []
var _box_shards: Array[PackedInt32Array] = []
var _box_lo := PackedVector3Array()
var _box_hi := PackedVector3Array()
var _rid_shard := {}
var _rid_box := {}
var _cells := {}  # Vector3i -> PackedInt32Array of shards standing there when built
var _mark := PackedInt32Array()
var _stamp := 0
var _dirty := false
var _weigh := false
var _tick := 0
var _next_look := 0
var _kicked := PackedInt32Array()
var _built := false
# Only while building: every shard's corners and faces in the world.
var _points: Array[PackedVector3Array] = []
var _planes: Array = []


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
	for rid in _box_shape:
		PhysicsServer3D.free_rid(rid)


## Adds a box of `size` at `xf` and cuts it into shards. Call build() once
## every box is in.
func add_box(xf: Transform3D, size: Vector3, tint := Color.WHITE, grain := GRAIN) -> int:
	var box := _box_shards.size()
	var cut := Fracture.cut(size, grain, cut_seed * 7919 + box * 104729)
	var base := count
	var mine := PackedInt32Array()
	var box_lo := Vector3.INF
	var box_hi := -Vector3.INF
	for sh in cut:
		var i := count
		count += 1
		mine.append(i)
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
		mesh.add_shard(i, world, sh, xf.basis, tint)
	_box_shards.append(mine)
	_box_lo.append(box_lo)
	_box_hi.append(box_hi)
	var shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(shape, size * 0.5)
	_box_shape.append(shape)
	var body := _static_body(shape, xf)
	_solid.append(body)
	_rid_box[body] = box
	return box


## Bonds the boxes that touch, anchors what rests at `ground` height, and
## gets everything ready. Nothing can be added after this.
func build(ground := 0.0) -> void:
	_bond_boxes()
	for i in count:
		if _lo[i].y < ground + TOUCH:
			anchored[i] = 1
		var cell := Vector3i((centroid[i] / CELL).floor())
		if not _cells.has(cell):
			_cells[cell] = PackedInt32Array()
		(_cells[cell] as PackedInt32Array).append(i)
	_index_bonds()
	held_count = count
	_mark.resize(count)
	mesh.build(count, count + 1)
	pieces.setup(count)
	support.setup(self)
	_points.clear()
	_planes.clear()
	_built = true


func _physics_process(_delta: float) -> void:
	_tick += 1
	if _tick < _next_look:
		return
	# Two halves on two different steps, so neither is long: first what is
	# still reached from the ground, then what is overloaded.
	var t := Time.get_ticks_usec()
	if _weigh:
		_weigh = false
		_next_look = _tick + LOOK_EVERY
		for b in support.overloaded(self):
			break_bond(b)
		solve_usec = maxi(solve_usec, Time.get_ticks_usec() - t)
	elif _dirty:
		_dirty = false
		_weigh = true
		_next_look = _tick + LOOK_EVERY
		for group in support.unheld(self):
			_let_go(group)
		for i in _kicked:
			_kick[i] = Vector3.ZERO
		_kicked.clear()
		solve_usec = Time.get_ticks_usec() - t


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
	_release(PackedInt32Array([i]), velocity, spin)
	_dirty = true


## Something heavy hit the standing building at `at`: about `amount` m3 of
## it is knocked out there, nearest first, and leaves at `velocity`.
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


## What a physics body is: a standing shard (its index), a whole box
## (-1 - box), or nothing of this structure (-1000000).
func owner_of(rid: RID) -> int:
	if _rid_shard.has(rid):
		return _rid_shard[rid]
	if _rid_box.has(rid):
		return -1 - int(_rid_box[rid])
	return -1000000


## The collision shape of shard `i` (made the first time it is needed).
func shape_of(i: int) -> RID:
	if not _shape[i].is_valid():
		var shape := PhysicsServer3D.convex_polygon_shape_create()
		PhysicsServer3D.shape_set_data(shape, corners[i])
		_shape[i] = shape
	return _shape[i]


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
	adj_first.resize(count + 1)
	for i in count:
		adj_first[i + 1] = adj_first[i] + degree[i + 1]
	adj_bond.resize(bond_a.size() * 2)
	adj_other.resize(bond_a.size() * 2)
	var next := adj_first.duplicate()
	for b in bond_a.size():
		for side in 2:
			var i := bond_a[b] if side == 0 else bond_b[b]
			adj_bond[next[i]] = b
			adj_other[next[i]] = bond_b[b] if side == 0 else bond_a[b]
			next[i] += 1


## A set of shards that no longer holds comes off: in one piece if it is
## small, cut in chunks if it is big. It leaves with the push its shards
## got from the blast that freed it.
func _let_go(group: PackedInt32Array) -> void:
	for chunk in _chunks(group):
		var push := Vector3.ZERO
		var weight := 0.0
		for i in chunk:
			push += _kick[i] * mass[i]
			weight += mass[i]
		_release(chunk, push / weight * 0.5)


func _chunks(group: PackedInt32Array) -> Array[PackedInt32Array]:
	if group.size() <= MAX_CHUNK:
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
		while head < chunk.size() and chunk.size() < MAX_CHUNK:
			var i := chunk[head]
			head += 1
			for k in range(adj_first[i], adj_first[i + 1]):
				var j := adj_other[k]
				if _mark[j] == todo and bond_health[adj_bond[k]] > 0.0 and chunk.size() < MAX_CHUNK:
					_mark[j] = _stamp
					chunk.append(j)
		out.append(chunk)
	return out


## Shards `group` stop standing and become one rigid piece.
func _release(group: PackedInt32Array, velocity: Vector3, spin := Vector3.ZERO) -> void:
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
		if _solid[element[i]].is_valid():
			_open(element[i])
		# Its bonds to what it leaves behind are gone.
		for k in range(adj_first[i], adj_first[i + 1]):
			if _mark[adj_other[k]] != _stamp:
				bond_health[adj_bond[k]] = 0.0
		if _own[i].is_valid():
			_rid_shard.erase(_own[i])
			if group.size() == 1:
				reuse = _own[i]
			else:
				PhysicsServer3D.free_rid(_own[i])
			_own[i] = RID()
	# What was resting on it has to move again.
	pieces.thaw_box(lo - Vector3.ONE * 0.3, hi + Vector3(0.3, 0.6, 0.3))
	pieces.spawn(group, Transform3D.IDENTITY, velocity, spin, reuse)
	released.emit(at / size, size, velocity)


## A whole box takes its first damage: from now on each of its standing
## shards has its own body, so holes are real.
func _open(box: int) -> void:
	_rid_box.erase(_solid[box])
	PhysicsServer3D.free_rid(_solid[box])
	_solid[box] = RID()
	for i in _box_shards[box]:
		if held[i] == 1:
			var body := _static_body(shape_of(i), Transform3D(Basis(), centroid[i]))
			_own[i] = body
			_rid_shard[body] = i


func _static_body(shape: RID, xf: Transform3D) -> RID:
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_add_shape(body, shape)
	PhysicsServer3D.body_set_collision_layer(body, LAYER_STRUCTURE)
	PhysicsServer3D.body_set_collision_mask(body, 0)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
	PhysicsServer3D.body_set_space(body, get_world_3d().space)
	return body
