class_name Pieces
extends Node
## The rigid pieces that have come off a Structure: a single shard, or
## several still bonded together that move as one. A piece that lands hard
## is crushed where it hits (those shards come loose one by one), may split
## along the bonds that broke, and knocks out what it hits if that is still
## standing. Pieces that have come to rest are frozen: they cost nothing and
## a pile stays put, until something disturbs them. Nothing is removed.

## A piece slower than this (m/s, rad/s) for QUIET_TIME seconds is frozen.
const QUIET_SPEED := 0.25
const QUIET_SPIN := 0.7
const QUIET_TIME := 0.5
## A piece that loses the energy of a stop from this speed (m/s) in one
## step is damaged.
const BREAK_SPEED := 2.0
## Energy (J) it takes to crush 1 m3 into loose shards.
const TOUGHNESS := 7.0e4
## Around where a piece is crushed, its bonds crack up to this far (m) per
## cube root of the volume crushed: a slab that lands hard breaks in a few.
const CRACK_REACH := 2.2
## Contacts looked at per piece of several shards.
const CONTACTS := 12
const GRID := 2.0  ## m, the grid frozen pieces are found by
const NOT_OURS := -1000000

var structure: Structure
## Per piece (a piece keeps its number until it breaks up).
var body: Array[RID] = []
var members: Array[PackedInt32Array] = []
var origin := PackedVector3Array()  ## where its body's origin was in the whole building
var mass := PackedFloat32Array()
var reach := PackedFloat32Array()
var alive := PackedByteArray()
var frozen := PackedByteArray()
## How many pieces there are, how many are moving, how many are frozen.
var live := 0
var awake := 0
var asleep := 0

var _xf: Array[Transform3D] = []
var _lin := PackedVector3Array()
var _ang := PackedVector3Array()
var _quiet := PackedFloat32Array()
var _serial := PackedInt32Array()
var _free := PackedInt32Array()
var _freeze := PackedInt32Array()
var _hits: Array[Array] = []
var _by_body := {}  # RID -> piece
var _cell: Array[Vector3i] = []  # where in the grid a frozen piece is filed
var _grid := {}  # Vector3i -> PackedInt32Array of frozen pieces
var _widest := 0.0  # the largest reach among frozen pieces
var _wake: Array[AABB] = []
var _mark := PackedInt32Array()
var _stamp := 0


## Room for `count` pieces (as many as there are shards).
func setup(count: int) -> void:
	body.resize(count)
	members.resize(count)
	origin.resize(count)
	mass.resize(count)
	reach.resize(count)
	alive.resize(count)
	frozen.resize(count)
	_xf.resize(count)
	_lin.resize(count)
	_ang.resize(count)
	_quiet.resize(count)
	_serial.resize(count)
	_cell.resize(count)
	_mark.resize(count)
	for i in range(count - 1, -1, -1):
		_free.append(i)


func free_bodies() -> void:
	for i in alive.size():
		if alive[i] == 1:
			PhysicsServer3D.free_rid(body[i])
			alive[i] = 0


## Shards `group` become one rigid piece. `from_rest` takes a point of the
## whole building to where it is now (identity for what just came off a
## standing wall). `reuse`: a body that already has the single shard's shape.
func spawn(
	group: PackedInt32Array, from_rest: Transform3D, velocity: Vector3, spin: Vector3, reuse := RID()
) -> int:
	var s := structure
	var i := _free[-1]
	_free.remove_at(_free.size() - 1)
	var weight := 0.0
	var centre := Vector3.ZERO
	for k in group:
		weight += s.mass[k]
		centre += s.centroid[k] * s.mass[k]
	centre /= weight
	var far := 0.0
	var b := reuse if reuse.is_valid() else PhysicsServer3D.body_create()
	for k in group:
		far = maxf(far, s.centroid[k].distance_to(centre) + s.radius[k])
		s.piece_of[k] = i
		s.mesh.set_slot(k, i + 1)
		if not reuse.is_valid():
			PhysicsServer3D.body_add_shape(b, s.shape_of(k), Transform3D(Basis(), s.centroid[k] - centre))
	var xf := Transform3D(from_rest.basis, from_rest * centre)
	PhysicsServer3D.body_set_mode(b, PhysicsServer3D.BODY_MODE_RIGID)
	PhysicsServer3D.body_set_param(b, PhysicsServer3D.BODY_PARAM_MASS, weight)
	PhysicsServer3D.body_set_param(b, PhysicsServer3D.BODY_PARAM_FRICTION, 0.8)
	PhysicsServer3D.body_set_param(b, PhysicsServer3D.BODY_PARAM_BOUNCE, 0.05)
	PhysicsServer3D.body_set_param(b, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP, 0.4)
	PhysicsServer3D.body_set_collision_layer(b, Structure.LAYER_DEBRIS)
	PhysicsServer3D.body_set_collision_mask(
		b, Structure.LAYER_WORLD | Structure.LAYER_STRUCTURE | Structure.LAYER_DEBRIS
	)
	PhysicsServer3D.body_set_state(b, PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
	PhysicsServer3D.body_set_state(b, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, velocity)
	PhysicsServer3D.body_set_state(b, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, spin)
	# Rest is decided here (frozen), not by the engine's own sleep.
	PhysicsServer3D.body_set_state(b, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
	if group.size() > 1:
		PhysicsServer3D.body_set_max_contacts_reported(b, CONTACTS)
	else:
		# A lone shard can be thrown fast enough to go through a thin wall.
		PhysicsServer3D.body_set_enable_continuous_collision_detection(b, velocity.length() > 12.0)
	if not reuse.is_valid():
		PhysicsServer3D.body_set_space(b, s.get_world_3d().space)
	_serial[i] += 1
	PhysicsServer3D.body_set_state_sync_callback(b, _moved.bind(i, _serial[i]))
	body[i] = b
	_by_body[b] = i
	members[i] = group
	origin[i] = centre
	mass[i] = weight
	reach[i] = far
	alive[i] = 1
	frozen[i] = 0
	_xf[i] = xf
	_lin[i] = velocity
	_ang[i] = spin
	_quiet[i] = 0.0
	live += 1
	awake += 1
	s.mesh.set_body(i + 1, xf, centre)
	return i


func _physics_process(_delta: float) -> void:
	for i in _freeze:
		if alive[i] == 1 and frozen[i] == 0 and _quiet[i] >= QUIET_TIME:
			_freeze_piece(i)
	_freeze.clear()
	if not _hits.is_empty():
		var hits := _hits
		_hits = []
		for hit in hits:
			_shatter(hit)
	for n in mini(_wake.size(), 6):
		var box: AABB = _wake.pop_back()
		_thaw_in(box.position, box.end, box.position.y + box.size.y * 0.3)


## The piece a physics body is, or -1.
func index_of(rid: RID) -> int:
	return _by_body.get(rid, -1)


## Where piece `i` is.
func transform_of(i: int) -> Transform3D:
	return _xf[i]


func velocity_of(i: int) -> Vector3:
	return _lin[i]


## Pushes piece `i`: its speed changes by `dv`. Wakes it if it was frozen.
func push(i: int, dv: Vector3, spin := Vector3.ZERO) -> void:
	if frozen[i] == 1:
		thaw(i)
	PhysicsServer3D.body_apply_central_impulse(body[i], dv * mass[i])
	if spin != Vector3.ZERO:
		var w: Vector3 = PhysicsServer3D.body_get_state(body[i], PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
		PhysicsServer3D.body_set_state(body[i], PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, w + spin)


## Frozen pieces touching the box from `lo` to `hi` move again.
func thaw_box(lo: Vector3, hi: Vector3) -> void:
	_thaw_in(lo, hi, -INF)


## Piece `i` moves again, and so will what rests on it.
func thaw(i: int) -> void:
	if frozen[i] == 0:
		return
	frozen[i] = 0
	asleep -= 1
	awake += 1
	_quiet[i] = 0.0
	var at := _xf[i].origin
	var list: PackedInt32Array = _grid[_cell[i]]
	list.remove_at(list.find(i))
	_grid[_cell[i]] = list
	PhysicsServer3D.body_set_mode(body[i], PhysicsServer3D.BODY_MODE_RIGID)
	PhysicsServer3D.body_set_state(body[i], PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
	var r := reach[i] + 0.15
	_wake.append(AABB(at - Vector3(r, 0.0, r), Vector3(r, r + 0.3, r) * 2.0))


## Volume (m3) of everything that has come off.
func volume() -> float:
	var v := 0.0
	for i in alive.size():
		if alive[i] == 1:
			for k in members[i]:
				v += structure.volume[k]
	return v


func _thaw_in(lo: Vector3, hi: Vector3, above: float) -> void:
	if asleep == 0:
		return
	var grow := Vector3.ONE * _widest
	var a := Vector3i(((lo - grow) / GRID).floor())
	var b := Vector3i(((hi + grow) / GRID).floor())
	var found := PackedInt32Array()
	for z in range(a.z, b.z + 1):
		for y in range(a.y, b.y + 1):
			for x in range(a.x, b.x + 1):
				var list: Variant = _grid.get(Vector3i(x, y, z))
				if list == null:
					continue
				for i: int in list:
					var at := _xf[i].origin
					if at.y < above:
						continue
					var near := at.clamp(lo, hi)
					if near.distance_squared_to(at) < reach[i] * reach[i]:
						found.append(i)
	for i in found:
		thaw(i)


func _freeze_piece(i: int) -> void:
	frozen[i] = 1
	asleep += 1
	awake -= 1
	_widest = maxf(_widest, reach[i])
	PhysicsServer3D.body_set_mode(body[i], PhysicsServer3D.BODY_MODE_STATIC)
	var cell := Vector3i((_xf[i].origin / GRID).floor())
	_cell[i] = cell
	var list: PackedInt32Array = _grid.get(cell, PackedInt32Array())
	list.append(i)
	_grid[cell] = list


func _remove(i: int) -> void:
	if frozen[i] == 1:
		thaw(i)
	_by_body.erase(body[i])
	PhysicsServer3D.free_rid(body[i])
	body[i] = RID()
	alive[i] = 0
	live -= 1
	awake -= 1
	_free.append(i)


## Called by the physics engine for every piece that moved in the last step.
func _moved(state: PhysicsDirectBodyState3D, i: int, serial: int) -> void:
	if alive[i] == 0 or _serial[i] != serial or frozen[i] == 1:
		return
	var xf := state.transform
	var lin := state.linear_velocity
	var ang := state.angular_velocity
	var was := _lin[i]
	_xf[i] = xf
	_lin[i] = lin
	_ang[i] = ang
	structure.mesh.set_body(i + 1, xf, origin[i])
	if lin.length_squared() < QUIET_SPEED * QUIET_SPEED and ang.length_squared() < QUIET_SPIN * QUIET_SPIN:
		_quiet[i] += state.step
		if _quiet[i] >= QUIET_TIME:
			_freeze.append(i)
	else:
		_quiet[i] = 0.0
	if members[i].size() < 2:
		return
	# Energy it lost in this step, per kg (it gains some while it falls).
	var lost := 0.5 * (was.length_squared() - lin.length_squared())
	if lost < 0.5 * BREAK_SPEED * BREAK_SPEED:
		return
	var n := state.get_contact_count()
	if n == 0:
		return
	var total := 0.0
	for k in n:
		total += state.get_contact_impulse(k).length()
	if total <= 0.0:
		return
	var points := PackedVector3Array()
	var impulses := PackedFloat32Array()
	var owners := PackedInt32Array()
	for k in n:
		var j := state.get_contact_impulse(k).length()
		if j > total * 0.05:
			points.append(state.get_contact_local_position(k))
			impulses.append(j)
			owners.append(structure.owner_of(state.get_contact_collider(k)))
	_hits.append([i, serial, points, impulses, owners, was, lost * mass[i]])


## A piece of several shards hit something hard. The energy it lost crushes
## that much of it, starting where it hit, and as much of the building if
## that is what it hit. What is left splits along the bonds that broke.
func _shatter(hit: Array) -> void:
	var i: int = hit[0]
	if alive[i] == 0 or _serial[i] != hit[1]:
		return
	var s := structure
	var points: PackedVector3Array = hit[2]
	var impulses: PackedFloat32Array = hit[3]
	var owners: PackedInt32Array = hit[4]
	var was: Vector3 = hit[5]
	var total := 0.0
	for j in impulses:
		total += j
	var amount: float = hit[6] / TOUGHNESS
	var xf := _xf[i]
	var from_rest := xf * Transform3D(Basis(), -origin[i])
	var to_rest := from_rest.affine_inverse()
	_stamp += 2
	var gone := _stamp - 1  # marks the shards crushed out of the piece
	var crushed := PackedInt32Array()
	var cracked := false
	for k in points.size():
		var share := amount * impulses[k] / total
		if owners[k] != NOT_OURS:
			s.crush(points[k], share * 0.5, was)
		var at := to_rest * points[k]
		var reach := CRACK_REACH * pow(share, 0.333)
		var near: Array[Vector2] = []  # (distance to its surface, shard)
		for m in members[i]:
			if _mark[m] != gone:
				near.append(Vector2(maxf(s.centroid[m].distance_to(at) - s.radius[m], 0.0), m))
		near.sort()
		for entry in near:
			var m := int(entry.y)
			if share >= s.volume[m] * 0.5:
				share -= s.volume[m]
				_mark[m] = gone
				crushed.append(m)
			elif entry.x < reach:
				# Too little left to free this one: its bonds crack.
				cracked = _crack(m, 1.0 - entry.x / reach) or cracked
			else:
				break
	if crushed.is_empty() and not cracked:
		return
	var parts := _parts(i, gone)
	if crushed.is_empty() and parts.size() == 1:
		return
	var lin := _lin[i]
	var ang := _ang[i]
	for m in crushed:
		for e in range(s.adj_first[m], s.adj_first[m + 1]):
			s.bond_health[s.adj_bond[e]] = 0.0
	_remove(i)
	for m in crushed:
		var arm := from_rest * s.centroid[m] - xf.origin
		var scatter := Vector3(randf() - 0.5, randf() * 0.6, randf() - 0.5) * 3.0
		spawn(PackedInt32Array([m]), from_rest, lin + ang.cross(arm) + scatter, ang)
	for part in parts:
		var centre := Vector3.ZERO
		var weight := 0.0
		for m in part:
			centre += s.centroid[m] * s.mass[m]
			weight += s.mass[m]
		var arm := from_rest * (centre / weight) - xf.origin
		# Bonds across two parts are broken for good.
		_stamp += 1
		for m in part:
			_mark[m] = _stamp
		for m in part:
			for e in range(s.adj_first[m], s.adj_first[m + 1]):
				if _mark[s.adj_other[e]] != _stamp:
					s.bond_health[s.adj_bond[e]] = 0.0
		spawn(part, from_rest, lin + ang.cross(arm), ang)
	s.released.emit(xf.origin, amount, lin)


## Weakens the bonds of shard `m` by up to `harm`. True if one broke.
func _crack(m: int, harm: float) -> bool:
	var s := structure
	var broke := false
	for e in range(s.adj_first[m], s.adj_first[m + 1]):
		var b := s.adj_bond[e]
		if s.bond_health[b] > 0.0:
			s.bond_health[b] = maxf(s.bond_health[b] - harm * randf_range(0.0, 1.6), 0.0)
			broke = broke or s.bond_health[b] <= 0.0
	return broke


## The members of piece `i` not marked `gone`, grouped by what is still
## bonded together.
func _parts(i: int, gone: int) -> Array[PackedInt32Array]:
	var s := structure
	var seen := gone + 1
	var out: Array[PackedInt32Array] = []
	for start in members[i]:
		if _mark[start] == gone or _mark[start] == seen:
			continue
		var part := PackedInt32Array([start])
		_mark[start] = seen
		var head := 0
		while head < part.size():
			var m := part[head]
			head += 1
			for e in range(s.adj_first[m], s.adj_first[m + 1]):
				var j := s.adj_other[e]
				if s.piece_of[j] != i or _mark[j] == gone or _mark[j] == seen:
					continue
				if s.bond_health[s.adj_bond[e]] > 0.0:
					_mark[j] = seen
					part.append(j)
		out.append(part)
	return out
