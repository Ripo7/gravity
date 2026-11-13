class_name Pieces
extends Node
## The rigid pieces that have come off a Structure: a single shard, a crumb
## of one, or several shards still bonded together that move as one. A piece
## that lands hard is crushed where it hits (the shards there break into
## crumbs or come loose one by one), may split along the bonds that broke,
## and knocks out what it hits if that is still standing. A lone shard that
## hits hard enough breaks into crumbs. Pieces that have come to rest are
## frozen: they cost nothing and a pile stays put, until something disturbs
## them. Nothing is removed, except what an orb swallows (take), which is
## still counted; a piece an orb cannot get to itself comes apart (break_up).

## A piece slower than this (m/s, rad/s) for QUIET_TIME seconds is frozen.
const QUIET_SPEED := 0.25
const QUIET_SPIN := 0.7
const QUIET_TIME := 0.5
## With more than BUSY pieces moving, the rules above are HURRY times less
## strict: a heap settles sooner, when nobody can tell.
const BUSY := 180
const HURRY := 1.6
## A piece of several shards is damaged once it has lost, in hits, the
## energy of a stop from this speed (m/s): all at once in a hard landing, or
## bit by bit if it comes down gently (a slab does not survive either).
const BREAK_SPEED := 2.0
## A loss smaller than this in a step (J/kg) is not a hit.
const SCRAPE := 0.05
## Energy (J) it takes to crush 1 m3 into loose shards.
const TOUGHNESS := 7.0e4
## Around where a piece is crushed, its bonds crack up to this far (m) per
## cube root of the volume crushed: a slab that lands hard breaks in a few.
const CRACK_REACH := 2.2
## Of what is crushed where a piece hits, this share (the nearest) breaks
## into crumbs; the rest comes loose as whole shards.
const POWDER := 0.5
## A lone shard that loses the energy of a stop from this speed (m/s) in
## one step breaks into its crumbs.
const CRUMBLE_SPEED := 6.0
## ... one time in two at most (see crumble_chance): some shards stay whole
## among the crumbs.
const CRUMBLE_CHANCE := 0.5
## Crumbs are the finest and the dearest thing here: a few shards at most
## break into them per step, and none while more than CALM pieces are
## moving (when half the house is coming down, nobody looks at crumbs).
const CRUMBLES_PER_STEP := 3
const CALM := 260
## A shard torn out by a blast goes through what still stands for this many
## steps: the cuts lean, so it would often be wedged in its own hole.
const CLEAR_STEPS := 5
## Contacts looked at per piece of several shards.
const CONTACTS := 12
const GRID := 2.0  ## m, the grid frozen pieces are found by
const NOT_OURS := -1000000
const MASK_CLEARING := Structure.LAYER_WORLD | Structure.LAYER_DEBRIS
const MASK := MASK_CLEARING | Structure.LAYER_STRUCTURE
## A piece an orb is drawing in goes through other loose pieces (it would
## jam in a heap) and through you: see Structure.LAYER_GRIPPED.
const MASK_GRIPPED := Structure.LAYER_WORLD | Structure.LAYER_STRUCTURE

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
## No piece has a number of `top` or more yet (numbers are given lowest
## first): loops over the pieces stop there.
var top := 0
var gripped := PackedByteArray()  ## 1 while an orb is drawing the piece in
## Pieces born in an orb's grip (parts of one that broke on its way in) and
## that it has not taken charge of yet: it empties this list.
var adrift := PackedInt32Array()
var taken_volume := 0.0  ## m3 that orbs made disappear

var _xf: Array[Transform3D] = []
var _lin := PackedVector3Array()
var _ang := PackedVector3Array()
var _quiet := PackedFloat32Array()
var _size := PackedFloat32Array()  # 1, or less while it dwindles into an orb
var _bruise := PackedFloat32Array()  # energy lost in hits since it last broke (J/kg)
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
var _crumbles_left := CRUMBLES_PER_STEP
var _clearing: Array[Vector3i] = []  # (piece, serial, steps left) going through what stands
var _born_gripped := false  # while the parts of a gripped piece are being spawned


## Room for `count` pieces (as many as there are shards and crumbs).
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
	_size.resize(count)
	gripped.resize(count)
	_bruise.resize(count)
	_serial.resize(count)
	_cell.resize(count)
	_mark.resize(count)
	for i in range(count - 1, -1, -1):
		_free.append(i)


func free_bodies() -> void:
	for i in top:
		if alive[i] == 1:
			PhysicsServer3D.free_rid(body[i])
			alive[i] = 0


## Shards `group` become one rigid piece. `from_rest` takes a point of the
## whole building to where it is now (identity for what just came off a
## standing wall). `reuse`: a body that already has the single shard's shape.
## `torn`: thrown out of a standing wall (see CLEAR_STEPS).
func spawn(
	group: PackedInt32Array,
	from_rest: Transform3D,
	velocity: Vector3,
	spin: Vector3,
	reuse := RID(),
	torn := false
) -> int:
	var s := structure
	var i := _free[-1]
	_free.remove_at(_free.size() - 1)
	top = maxi(top, i + 1)
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
	PhysicsServer3D.body_set_collision_mask(b, MASK_CLEARING if torn else MASK)
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
	if torn:
		_clearing.append(Vector3i(i, _serial[i], CLEAR_STEPS))
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
	_bruise[i] = 0.0
	_size[i] = 1.0
	gripped[i] = 0
	live += 1
	awake += 1
	s.mesh.set_body(i + 1, xf, centre)
	if _born_gripped:
		grip(i)
		adrift.append(i)
	return i


## True if shard `m` may break into crumbs right now.
func can_crumble(m: int) -> bool:
	return _crumbles_left > 0 and awake < CALM and structure.can_crumble(m)


## The chance that a shard which could crumble does: 1 while there are no
## crumbs yet, less and less as the room for them fills up.
func crumble_chance() -> float:
	var s := structure
	return 1.0 - float(s.crumbs_out) / maxf(s.most_crumbs, 1.0)


## Shard `m` breaks into crumbs, each a piece of its own, flung apart (or
## leaves whole if it cannot be cut). `from_rest`, `velocity`, `spin` and
## `torn` as in spawn(), for the shard as a whole.
func crumble(m: int, from_rest: Transform3D, velocity: Vector3, spin: Vector3, torn := false) -> void:
	var s := structure
	var bits := s.make_crumbs(m)
	if bits.is_empty():
		spawn(PackedInt32Array([m]), from_rest, velocity, spin, RID(), torn)
		return
	_crumbles_left -= 1
	s.piece_of[m] = -1
	s.mesh.set_slot(m, -1)
	var fling := clampf(velocity.length() * 0.25, 1.0, 4.0)
	for c in bits:
		var out := from_rest.basis * (s.centroid[c] - s.centroid[m])
		var v := velocity + spin.cross(out) + out.normalized() * fling * randf_range(0.2, 1.0)
		var turn := spin + Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * fling * 2.0
		spawn(PackedInt32Array([c]), from_rest, v, turn, RID(), torn)


func _physics_process(_delta: float) -> void:
	_crumbles_left = CRUMBLES_PER_STEP
	for k in range(_clearing.size() - 1, -1, -1):
		var c := _clearing[k]
		if c.z > 1:
			_clearing[k] = Vector3i(c.x, c.y, c.z - 1)
			continue
		if alive[c.x] == 1 and _serial[c.x] == c.y and gripped[c.x] == 0:
			PhysicsServer3D.body_set_collision_mask(body[c.x], MASK)
		_clearing.remove_at(k)
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


## An orb takes hold of piece `i` (see MASK_GRIPPED); drag() then moves it.
func grip(i: int) -> void:
	if frozen[i] == 1:
		thaw(i)
	gripped[i] = 1
	PhysicsServer3D.body_set_collision_layer(body[i], Structure.LAYER_GRIPPED)
	PhysicsServer3D.body_set_collision_mask(body[i], MASK_GRIPPED)


## Gripped piece `i` moves at `velocity`, drawn at `size` (1: full size).
func drag(i: int, velocity: Vector3, size: float) -> void:
	_size[i] = size
	_quiet[i] = 0.0
	PhysicsServer3D.body_set_state(body[i], PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, velocity)


## The orb lets piece `i` go: it is a loose piece like any other again.
func let_go(i: int) -> void:
	gripped[i] = 0
	_size[i] = 1.0
	PhysicsServer3D.body_set_collision_layer(body[i], Structure.LAYER_DEBRIS)
	PhysicsServer3D.body_set_collision_mask(body[i], MASK)
	structure.mesh.set_body(i + 1, _xf[i], origin[i])


## Piece `i` leaves the world for good (an orb swallows it): no body, not
## drawn, its volume counted in taken_volume, its crumbs' room given back.
func take(i: int) -> void:
	var s := structure
	var group := members[i]
	for m in group:
		s.piece_of[m] = -1
		s.mesh.set_slot(m, -1)
		taken_volume += s.volume[m]
		for e in range(s.adj_first[m], s.adj_first[m + 1]):
			s.bond_health[s.adj_bond[e]] = 0.0
	_remove(i)
	for m in group:
		if m >= s.count:
			s.crumb_gone(m)


## Piece `i` of several shards comes apart (an orb pulls on it and it is
## stuck): each of its shards is a piece of its own, where it is (and in the
## orb's grip if the whole was: see adrift).
func break_up(i: int) -> void:
	var group := members[i]
	if group.size() < 2:
		return
	var s := structure
	var xf := _xf[i]
	var from_rest := xf * Transform3D(Basis(), -origin[i])
	var amount := mass[i] / Structure.DENSITY
	for m in group:
		for e in range(s.adj_first[m], s.adj_first[m + 1]):
			s.bond_health[s.adj_bond[e]] = 0.0
	_born_gripped = gripped[i] == 1
	_remove(i)
	for m in group:
		spawn(PackedInt32Array([m]), from_rest, Vector3.ZERO, Vector3.ZERO)
	_born_gripped = false
	s.released.emit(xf.origin, amount, Vector3.ZERO)


func serial_of(i: int) -> int:
	return _serial[i]


## Volume (m3) of everything that has come off, in pieces or in orbs.
func volume() -> float:
	var v := taken_volume
	for i in top:
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
	structure.mesh.set_body(i + 1, xf, origin[i], _size[i])
	var slack := HURRY if awake > BUSY else 1.0
	if (
		lin.length_squared() < QUIET_SPEED * QUIET_SPEED * slack * slack
		and ang.length_squared() < QUIET_SPIN * QUIET_SPIN * slack * slack
	):
		_quiet[i] += state.step * slack
		if _quiet[i] >= QUIET_TIME:
			_freeze.append(i)
	else:
		_quiet[i] = 0.0
	# Energy it lost in this step, per kg (it gains some while it falls).
	var lost := 0.5 * (was.length_squared() - lin.length_squared())
	if members[i].size() < 2:
		if lost >= 0.5 * CRUMBLE_SPEED * CRUMBLE_SPEED and can_crumble(members[i][0]):
			if randf() < CRUMBLE_CHANCE * crumble_chance():
				_hits.append([i, serial])
		return
	if lost < SCRAPE:
		return
	var n := state.get_contact_count()
	if n == 0:
		return
	_bruise[i] += lost
	if _bruise[i] < 0.5 * BREAK_SPEED * BREAK_SPEED:
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
	_hits.append([i, serial, points, impulses, owners, was, _bruise[i] * mass[i]])
	_bruise[i] = 0.0


## A piece of several shards hit something hard. The energy it lost crushes
## that much of it, starting where it hit, and as much of the building if
## that is what it hit. What is left splits along the bonds that broke.
func _shatter(hit: Array) -> void:
	var i: int = hit[0]
	if alive[i] == 0 or _serial[i] != hit[1]:
		return
	var s := structure
	if hit.size() == 2:
		# A lone shard that hit hard: it breaks into its crumbs.
		var whole := members[i][0]
		if not can_crumble(whole):
			return
		var at := _xf[i]
		var v := _lin[i]
		var w := _ang[i]
		_remove(i)
		crumble(whole, at * Transform3D(Basis(), -origin[i]), v, w)
		s.released.emit(at.origin, s.volume[whole], v)
		return
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
	var crushed := PackedInt32Array()  # shards that come loose whole
	var powder := PackedInt32Array()  # shards that break into crumbs
	var cracked := false
	for k in points.size():
		var share := amount * impulses[k] / total
		var fine := share * (1.0 - POWDER)
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
				if (
					share > fine
					and powder.size() < _crumbles_left
					and can_crumble(m)
					and randf() < crumble_chance()
				):
					powder.append(m)
				else:
					crushed.append(m)
				share -= s.volume[m]
				_mark[m] = gone
			elif entry.x < reach:
				# Too little left to free this one: its bonds crack.
				cracked = _crack(m, 1.0 - entry.x / reach) or cracked
			else:
				break
	var loose := crushed.size() + powder.size()
	if loose == 0 and not cracked:
		return
	var parts := _parts(i, gone)
	if loose == 0 and parts.size() == 1:
		return
	var lin := _lin[i]
	var ang := _ang[i]
	# What an orb was drawing in stays in its grip, in parts.
	_born_gripped = gripped[i] == 1
	for m in crushed + powder:
		for e in range(s.adj_first[m], s.adj_first[m + 1]):
			s.bond_health[s.adj_bond[e]] = 0.0
	_remove(i)
	for m in crushed:
		var arm := from_rest * s.centroid[m] - xf.origin
		var scatter := Vector3(randf() - 0.5, randf() * 0.6, randf() - 0.5) * 3.0
		spawn(PackedInt32Array([m]), from_rest, lin + ang.cross(arm) + scatter, ang)
	for m in powder:
		var arm := from_rest * s.centroid[m] - xf.origin
		crumble(m, from_rest, lin + ang.cross(arm), ang)
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
	_born_gripped = false
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
