class_name Rubble
extends Node
## What has come off a Structure and lies or flies about: a block, or a
## piece that comes down in one piece until it lands. Each is a rigid body
## made straight on the physics server (no node), drawn by the Structure's
## mesh.
##
## They fall slowly (`fall`): that is what makes the brute a giant. A body
## that has come to rest is frozen (static): it costs nothing, a heap stays
## put and the brute can stand on it, until something near it is broken or
## struck.

## The share of real gravity that pulls what has come off, to begin with,
## and what it may be set to.
const FALL := 0.3
const FALL_LEAST := 0.05
const FALL_MOST := 1.0
const GRAVITY := 9.8
## A body that touches something and is slower than this (m/s, rad/s) for
## QUIET_TIME s is frozen. (As at real gravity: speeds here go with the
## square root of `fall`, see `_slow`.)
const QUIET_SPEED := 0.3
const QUIET_SPIN := 0.8
const QUIET_TIME := 0.5
## A body stopped by less than this (m/s, as at real gravity) in a step has
## only scraped: nothing comes of it.
const SCRAPE := 0.8
## A piece that comes down whole breaks when it is stopped as hard as by a
## drop from this high (m).
const BREAKS_FROM := 0.3
## What a body that lands on a standing piece does to it: a point of blows
## for each POINT kg.m/s it loses against it (as at real gravity); less
## than WEAK points is nothing. It has to land on it: come down on a face
## that looks up by ON_TOP at least (the y of its normal). What only
## brushes past a wall on its way down does nothing to it.
const POINT := 900.0
const WEAK := 0.5
const ON_TOP := 0.7
## A blow sends what lies loose near it off at SHOVE kg.m/s for each point
## of its power, SHOVE_MOST m/s at most (as at real gravity).
const SHOVE := 300.0
const SHOVE_MOST := 2.5
## Contacts looked at per body.
const CONTACTS := 4
## How much a body rubs on what it touches; and for its first FRESH s, when
## it has just come off: blocks cut one on top of the other slide apart
## then, instead of staying there as a broken column that still stands and
## still carries.
const FRICTION := 0.8
const FRESH_FRICTION := 0.08
const FRESH := 0.45

var structure: Structure
## The share of real gravity that pulls what has come off (see FALL).
var fall := FALL:
	set = set_fall
## Per body.
var body: Array[RID] = []
var slot := PackedInt32Array()  ## which body of the mesh it moves
var origin := PackedVector3Array()  ## where its own origin was when its piece was whole
var mass := PackedFloat32Array()
var reach := PackedFloat32Array()  ## how far from its origin it goes (m)
var piece := PackedInt32Array()  ## the piece it is, coming down whole; -1 for a block
var alive := PackedByteArray()
var frozen := PackedByteArray()
## How many bodies there are, and how many are moving.
var live := 0
var awake := 0

var _xf: Array[Transform3D] = []
var _lin := PackedVector3Array()
var _ang := PackedVector3Array()
var _quiet := PackedFloat32Array()
var _by_body := {}  # RID -> body
var _fresh: Array[Vector2] = []  # (body, s before it rubs as it should)
var _freeze := PackedInt32Array()
var _hits: Array[Array] = []  # [body, how hard it was stopped (m/s), who by, how much each]


func _exit_tree() -> void:
	for i in body.size():
		if alive[i] == 1:
			PhysicsServer3D.free_rid(body[i])
			alive[i] = 0


func set_fall(share: float) -> void:
	fall = clampf(share, FALL_LEAST, FALL_MOST)
	for i in body.size():
		if alive[i] == 1:
			PhysicsServer3D.body_set_param(body[i], PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, fall)


## A new loose body with `shape` (turned by `turned` in it), at `xf`, going
## at `velocity` and turning at `spin`. It moves body `mesh_slot` of the
## mesh, whose blocks stood around `rest`: `xf` is where that point is now,
## and how the body has turned since it stood. `whole`: the piece it is, if
## it is one coming down whole. Returns its number.
func add(
	mesh_slot: int,
	shape: RID,
	turned: Basis,
	xf: Transform3D,
	rest: Vector3,
	weight: float,
	far: float,
	velocity: Vector3,
	spin: Vector3,
	whole := -1
) -> int:
	var i := body.size()
	var b := PhysicsServer3D.body_create()
	PhysicsServer3D.body_add_shape(b, shape, Transform3D(turned, Vector3.ZERO))
	PhysicsServer3D.body_set_mode(b, PhysicsServer3D.BODY_MODE_RIGID)
	PhysicsServer3D.body_set_param(b, PhysicsServer3D.BODY_PARAM_MASS, weight)
	PhysicsServer3D.body_set_param(b, PhysicsServer3D.BODY_PARAM_FRICTION, FRESH_FRICTION)
	PhysicsServer3D.body_set_param(b, PhysicsServer3D.BODY_PARAM_BOUNCE, 0.05)
	PhysicsServer3D.body_set_param(b, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP, 0.4)
	PhysicsServer3D.body_set_param(b, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, fall)
	PhysicsServer3D.body_set_collision_layer(b, Layers.RUBBLE)
	PhysicsServer3D.body_set_collision_mask(
		b, Layers.WORLD | Layers.STRUCTURE | Layers.RUBBLE | Layers.PLAYER
	)
	PhysicsServer3D.body_set_state(b, PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
	PhysicsServer3D.body_set_state(b, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, velocity)
	PhysicsServer3D.body_set_state(b, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, spin)
	# Rest is decided here (frozen), not by the engine's own sleep.
	PhysicsServer3D.body_set_state(b, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
	PhysicsServer3D.body_set_max_contacts_reported(b, CONTACTS)
	PhysicsServer3D.body_set_space(b, structure.get_world_3d().space)
	PhysicsServer3D.body_set_state_sync_callback(b, _moved.bind(i))
	body.append(b)
	slot.append(mesh_slot)
	origin.append(rest)
	mass.append(weight)
	reach.append(far)
	piece.append(whole)
	alive.append(1)
	frozen.append(0)
	_xf.append(xf)
	_lin.append(velocity)
	_ang.append(spin)
	_quiet.append(0.0)
	_by_body[b] = i
	_fresh.append(Vector2(i, FRESH))
	live += 1
	awake += 1
	structure.mesh.set_body(mesh_slot, xf, rest)
	return i


## Body `i` is no more (a piece that came down whole has broken up).
func remove(i: int) -> void:
	if alive[i] == 0:
		return
	if frozen[i] == 0:
		awake -= 1
	_by_body.erase(body[i])
	PhysicsServer3D.free_rid(body[i])
	body[i] = RID()
	alive[i] = 0
	live -= 1


## The loose body a physics body is, or -1.
func index_of(rid: RID) -> int:
	return _by_body.get(rid, -1)


## Where body `i` is, how fast it goes and turns.
func transform_of(i: int) -> Transform3D:
	return _xf[i]


func velocity_of(i: int) -> Vector3:
	return _lin[i]


func spin_of(i: int) -> Vector3:
	return _ang[i]


## A blow of `power` lands at `at`, going along `way`: what lies loose
## within `radius` m of it is sent off, the lighter the faster.
func shove(at: Vector3, radius: float, way: Vector3, power: int) -> void:
	var flat := Vector3(way.x, 0.0, way.z).normalized()
	for i in body.size():
		if alive[i] == 0 or _xf[i].origin.distance_to(at) > radius + reach[i]:
			continue
		thaw(i)
		var speed := minf(SHOVE * power / mass[i], SHOVE_MOST) * _slow()
		var push := (flat + Vector3.UP * 0.3) * speed * mass[i]
		PhysicsServer3D.body_apply_central_impulse(body[i], push)


## Frozen bodies that reach into `box` move again.
func thaw_in(box: AABB) -> void:
	for i in body.size():
		if alive[i] == 1 and frozen[i] == 1 and box.grow(reach[i]).has_point(_xf[i].origin):
			thaw(i)


## Body `i` moves again, if it was frozen.
func thaw(i: int) -> void:
	if alive[i] == 0 or frozen[i] == 0:
		return
	frozen[i] = 0
	awake += 1
	_quiet[i] = 0.0
	PhysicsServer3D.body_set_mode(body[i], PhysicsServer3D.BODY_MODE_RIGID)


func _physics_process(delta: float) -> void:
	for k in range(_fresh.size() - 1, -1, -1):
		_fresh[k].y -= delta
		if _fresh[k].y <= 0.0:
			var i := int(_fresh[k].x)
			if alive[i] == 1:
				PhysicsServer3D.body_set_param(body[i], PhysicsServer3D.BODY_PARAM_FRICTION, FRICTION)
			_fresh.remove_at(k)
	for i in _freeze:
		if alive[i] == 1 and frozen[i] == 0 and _quiet[i] >= QUIET_TIME:
			frozen[i] = 1
			awake -= 1
			_lin[i] = Vector3.ZERO
			_ang[i] = Vector3.ZERO
			PhysicsServer3D.body_set_mode(body[i], PhysicsServer3D.BODY_MODE_STATIC)
	_freeze.clear()
	if _hits.is_empty():
		return
	var hits := _hits
	_hits = []
	for hit in hits:
		_land(hit[0], hit[1], hit[2], hit[3])


## Speeds go with the square root of the gravity that makes them: what is
## told as at real gravity is this much less here.
func _slow() -> float:
	return sqrt(fall)


## Called by the physics engine for every body that moved in the last step.
func _moved(state: PhysicsDirectBodyState3D, i: int) -> void:
	if alive[i] == 0 or frozen[i] == 1:
		return
	var lin := state.linear_velocity
	var ang := state.angular_velocity
	var was := _lin[i]
	_xf[i] = state.transform
	_lin[i] = lin
	_ang[i] = ang
	structure.mesh.set_body(slot[i], state.transform, origin[i])
	var touching := state.get_contact_count()
	var slow := _slow()
	if touching > 0 and lin.length() < QUIET_SPEED * slow and ang.length() < QUIET_SPIN * slow:
		_quiet[i] += state.step
		if _quiet[i] >= QUIET_TIME:
			_freeze.append(i)
	else:
		_quiet[i] = 0.0
	var stopped := (was - lin).length()
	if touching == 0 or stopped < SCRAPE * slow:
		return
	# What stopped it, and how much of the stop each one made.
	var by: Array[RID] = []
	var share := PackedFloat32Array()
	var total := 0.0
	for k in touching:
		var impulse := state.get_contact_impulse(k).length()
		total += impulse
		if state.get_contact_local_normal(k).y >= ON_TOP:
			by.append(state.get_contact_collider(k))
			share.append(impulse)
	if total <= 0.0:
		return
	for k in share.size():
		share[k] /= total
	_hits.append([i, stopped, by, share])


## Body `i` was stopped by `stopped` m/s in a step; it came down on the
## bodies `by`, each for its `share` of the stop: the pieces that stand
## among them take it as a blow, and a piece that was coming down whole
## breaks if it was stopped hard enough.
func _land(i: int, stopped: float, by: Array[RID], share: PackedFloat32Array) -> void:
	if alive[i] == 0:
		return
	var blow := mass[i] * stopped / (POINT * _slow())
	var taken := {}  # piece -> points
	for k in by.size():
		var stands := structure.standing(by[k])
		if stands >= 0:
			taken[stands] = taken.get(stands, 0.0) + blow * share[k]
	for stands: int in taken:
		if taken[stands] >= WEAK:
			structure.hit(stands, taken[stands])
	if alive[i] == 1 and piece[i] >= 0 and stopped >= sqrt(2.0 * GRAVITY * fall * BREAKS_FROM):
		structure.shatter(piece[i])
