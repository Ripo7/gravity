class_name Rubble
extends Node
## What has come off a Structure and lies or flies about: a block, a piece
## that comes down in one piece until it lands, or a piece of metal that
## has lain down. Each is a rigid body made straight on the physics server
## (no node), drawn by the Structure's mesh.
##
## A piece of metal can be several bodies joined along the lines it folds
## at (`join`): a fold holds until what bears on it is too much, then
## gives, slowly, and stays as it ends up. That is metal bending under a
## weight.
##
## They fall as fast as `fall` says: as things really do, to begin with
## (slower was tried, to make the brute a giant: see docs/CONCEPT.md). A
## body that has come to rest is frozen (static): it costs nothing, a heap stays
## put and the brute can stand on it, until something near it is broken or
## struck. Bodies joined to one another rest, and move again, together.

## Something loose, `weight` kg of it, has come down on the brute, its
## middle at `from`.
signal bears_down(from: Vector3, weight: float)

## The share of real gravity that pulls what has come off, to begin with,
## and what it may be set to.
const FALL := 1.0
const FALL_LEAST := 0.05
const FALL_MOST := 1.0
const GRAVITY := 9.8
## A body that touches something and is slower than this (m/s, rad/s) for
## QUIET_TIME s is frozen. (As at real gravity: speeds here go with the
## square root of `fall`, see `_slow`.)
const QUIET_SPEED := 0.3
const QUIET_SPIN := 0.8
const QUIET_TIME := 0.5
## Bodies joined to others have to be this much slower still: a fold that
## gives starts slowly.
const QUIET_JOINED := 0.12
## A fold goes this far (rad) from how it was made, either way.
const FOLD_MOST := 2.4
## Only a body that reaches within this (m) of the brute's middle is asked
## whether it touches it; it has come down on it if it touches it on a
## face that looks up by OVER at least.
const NEAR := 1.6
const OVER := 0.5
## The brute's body throws nothing: what it walks or lunges into is
## shoved along, not sent flying. Near it, no loose body goes sideways
## faster than PUSH m/s, up faster than LIFT, nor turns faster than SPIN
## rad/s. (A plate propped against it, pushed at its foot, left for the
## sky at 17 m/s.)
const PUSH := 6.5
const LIFT := 1.5
const SPIN := 5.0
## What is tied to a piece that stands can shift this far (m) from where
## it is tied, each way: enough to fold over the edge of what holds it.
const SLACK := 0.15
## A body stopped by less than this (m/s, as at real gravity) in a step has
## only scraped: nothing comes of it.
const SCRAPE := 0.8
## Blocks that come down in one break apart when something stops them
## once they have come down this far (m), or as hard as a drop from this
## high would.
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
## What weighs no more than LIGHT kg (a length of wood, a plank) is flung
## instead: FLUNG m/s at most.
const LIGHT := 40.0
const FLUNG := 6.0
## Contacts looked at per body.
const CONTACTS := 4
## How much a body rubs on what it touches; and how much one that is made
## to slip does, for SLIPS s (see `slip`).
const FRICTION := 0.8
const SLIPPERY := 0.08
const SLIPS := 0.45
## A block knocked out of a piece is not stopped by what is left of the
## piece for this long (s).
const THROUGH := 0.5

var structure: Structure
## The brute, if there is one: nothing comes to rest on it (it would be
## left in the air when the brute goes), and it is told what comes down on
## it (`bears_down`).
var brute: Node3D
## The share of real gravity that pulls what has come off (see FALL).
var fall := FALL:
	set = set_fall
## Per body.
var body: Array[RID] = []
var origin := PackedVector3Array()  ## where its own origin was when its piece stood
var mass := PackedFloat32Array()
var reach := PackedFloat32Array()  ## how far from its origin it goes (m)
var piece := PackedInt32Array()  ## the piece it is, coming down whole; -1 for a block
var alive := PackedByteArray()
var frozen := PackedByteArray()
var joined := PackedInt32Array()  ## the bodies it is joined with (a number in `_together`), or -1
## How many bodies there are, and how many are moving.
var live := 0
var awake := 0

var _xf: Array[Transform3D] = []
var _lin := PackedVector3Array()
var _ang := PackedVector3Array()
var _quiet := PackedFloat32Array()
var _from_high := PackedFloat32Array()  # per body: how high its middle was when it came loose
var _rig: Array[Array] = []  # per body: the bodies of the mesh it moves, each [slot, pose, origin]
var _by_body := {}  # RID -> body
var _slips: Array[Vector2] = []  # (body, s before it rubs as it should again)
var _through: Array[Vector3] = []  # (body, piece it goes through, s before it no longer does)
var _together: Array[PackedInt32Array] = []  # bodies joined to one another, directly or not
var _joints: Array[RID] = []
var _ties: Array[RID] = []  # what ties loose bodies to pieces that stand
var _holds := PackedFloat32Array()  # per joint: the turning force it holds (N.m, at real gravity)
var _brute_id := 0
var _brute_at := Vector3.ZERO
var _freeze := PackedInt32Array()
var _hits: Array[Array] = []  # [body, how hard it was stopped (m/s), who by, how much each]


func _exit_tree() -> void:
	for joint in _joints + _ties:
		PhysicsServer3D.free_rid(joint)
	_joints.clear()
	_ties.clear()
	for i in body.size():
		if alive[i] == 1:
			PhysicsServer3D.free_rid(body[i])
			alive[i] = 0


func set_fall(share: float) -> void:
	fall = clampf(share, FALL_LEAST, FALL_MOST)
	for i in body.size():
		if alive[i] == 1:
			PhysicsServer3D.body_set_param(body[i], PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, fall)
	# (What bears on a fold goes with the gravity: so does what it holds.)
	for k in _joints.size():
		PhysicsServer3D.hinge_joint_set_param(
			_joints[k], PhysicsServer3D.HINGE_JOINT_MOTOR_MAX_IMPULSE, _impulse(_holds[k])
		)


## A new loose body, at `xf`, going at `velocity` and turning at `spin`.
## `rest` is where its origin was when its piece stood: `xf` is where that
## point is now, and how the body has turned since. `shapes`: what it is
## made of, each [shape, where it is in the body]. `rig`: the bodies of the
## mesh it moves, each [slot, pose, origin], the pose being where that
## body of the mesh was when the piece stood (see ShardMesh.set_body).
## `whole`: the piece it is, if it is one coming down whole. Returns its
## number.
func add(
	shapes: Array,
	xf: Transform3D,
	rest: Vector3,
	weight: float,
	far: float,
	velocity: Vector3,
	spin: Vector3,
	rig: Array,
	whole := -1
) -> int:
	var i := body.size()
	var b := PhysicsServer3D.body_create()
	for shape: Array in shapes:
		PhysicsServer3D.body_add_shape(b, shape[0], shape[1])
	PhysicsServer3D.body_set_mode(b, PhysicsServer3D.BODY_MODE_RIGID)
	PhysicsServer3D.body_set_param(b, PhysicsServer3D.BODY_PARAM_MASS, weight)
	PhysicsServer3D.body_set_param(b, PhysicsServer3D.BODY_PARAM_FRICTION, FRICTION)
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
	origin.append(rest)
	mass.append(weight)
	reach.append(far)
	piece.append(whole)
	alive.append(1)
	frozen.append(0)
	joined.append(-1)
	_xf.append(xf)
	_lin.append(velocity)
	_ang.append(spin)
	_quiet.append(0.0)
	_from_high.append(xf.origin.y)
	_rig.append(rig)
	_by_body[b] = i
	live += 1
	awake += 1
	_draw(i)
	return i


## Bodies `a` and `b` are two parts of one piece of metal: they fold along
## the line through `at` that goes along `axis`. The fold holds `holds`
## N.m (as at real gravity); under more it gives, slowly, and stays where
## it ends up.
func join(a: int, b: int, at: Vector3, axis: Vector3, holds: float) -> void:
	# (A hinge turns about the z of its frame.)
	var z := axis.normalized()
	var x := z.cross(Vector3.UP)
	if x.length() < 0.01:
		x = z.cross(Vector3.RIGHT)
	x = x.normalized()
	var frame := Transform3D(Basis(x, z.cross(x), z), at)
	var joint := PhysicsServer3D.joint_create()
	PhysicsServer3D.joint_make_hinge(
		joint, body[a], _xf[a].affine_inverse() * frame, body[b], _xf[b].affine_inverse() * frame
	)
	PhysicsServer3D.joint_disable_collisions_between_bodies(joint, true)
	# (The two do not stop each other: the fold itself stops short of
	# laying one through the other.)
	PhysicsServer3D.hinge_joint_set_param(joint, PhysicsServer3D.HINGE_JOINT_LIMIT_LOWER, -FOLD_MOST)
	PhysicsServer3D.hinge_joint_set_param(joint, PhysicsServer3D.HINGE_JOINT_LIMIT_UPPER, FOLD_MOST)
	PhysicsServer3D.hinge_joint_set_flag(joint, PhysicsServer3D.HINGE_JOINT_FLAG_USE_LIMIT, true)
	# What holds it is a motor told to stay still, with only so much force.
	PhysicsServer3D.hinge_joint_set_param(joint, PhysicsServer3D.HINGE_JOINT_MOTOR_TARGET_VELOCITY, 0.0)
	PhysicsServer3D.hinge_joint_set_param(
		joint, PhysicsServer3D.HINGE_JOINT_MOTOR_MAX_IMPULSE, _impulse(holds)
	)
	PhysicsServer3D.hinge_joint_set_flag(joint, PhysicsServer3D.HINGE_JOINT_FLAG_ENABLE_MOTOR, true)
	_joints.append(joint)
	_holds.append(holds)
	# They rest and move again together, with all they are joined to.
	if joined[a] < 0 and joined[b] < 0:
		joined[a] = _together.size()
		joined[b] = joined[a]
		_together.append(PackedInt32Array([a, b]))
	elif joined[a] < 0 or joined[b] < 0:
		var alone := a if joined[a] < 0 else b
		var group := joined[b] if joined[a] < 0 else joined[a]
		joined[alone] = group
		_together[group].append(alone)
	elif joined[a] != joined[b]:
		var into := joined[a]
		var from := joined[b]
		for i in _together[from]:
			joined[i] = into
			_together[into].append(i)
		_together[from] = PackedInt32Array()


## Body `i` is tied at `at` to `anchor`, the body of a piece that stands
## (a deck to the post that still holds it): it can turn there as it
## likes and shift by SLACK m each way, no more. Returns the tie, to
## `release` when the piece goes.
func tie(i: int, anchor: RID, at: Vector3) -> RID:
	var there: Transform3D = PhysicsServer3D.body_get_state(anchor, PhysicsServer3D.BODY_STATE_TRANSFORM)
	var here := Transform3D(Basis(), at)
	var joint := PhysicsServer3D.joint_create()
	PhysicsServer3D.joint_make_generic_6dof(
		joint, body[i], _xf[i].affine_inverse() * here, anchor, there.affine_inverse() * here
	)
	for axis: int in [Vector3.AXIS_X, Vector3.AXIS_Y, Vector3.AXIS_Z]:
		PhysicsServer3D.generic_6dof_joint_set_param(
			joint, axis, PhysicsServer3D.G6DOF_JOINT_LINEAR_LOWER_LIMIT, -SLACK
		)
		PhysicsServer3D.generic_6dof_joint_set_param(
			joint, axis, PhysicsServer3D.G6DOF_JOINT_LINEAR_UPPER_LIMIT, SLACK
		)
		PhysicsServer3D.generic_6dof_joint_set_flag(
			joint, axis, PhysicsServer3D.G6DOF_JOINT_FLAG_ENABLE_LINEAR_LIMIT, true
		)
		PhysicsServer3D.generic_6dof_joint_set_flag(
			joint, axis, PhysicsServer3D.G6DOF_JOINT_FLAG_ENABLE_ANGULAR_LIMIT, false
		)
	_ties.append(joint)
	return joint


func release(tie_of: RID) -> void:
	_ties.erase(tie_of)
	PhysicsServer3D.free_rid(tie_of)


## Body `i` hardly rubs on anything for a moment. For what has just come
## off from under something: blocks cut one on top of the other slide out
## from under it then, instead of staying there as a broken column that
## still carries.
func slip(i: int) -> void:
	PhysicsServer3D.body_set_param(body[i], PhysicsServer3D.BODY_PARAM_FRICTION, SLIPPERY)
	_slips.append(Vector2(i, SLIPS))


## Body `i`, which has come off piece `p`, and what is left standing of
## `p` do not stop each other for `seconds`: whatever its shape, it gets
## clear of the hole it leaves.
func let_through(i: int, p: int, seconds: float) -> void:
	PhysicsServer3D.body_add_collision_exception(body[i], structure.body_of(p))
	if is_finite(seconds):
		_through.append(Vector3(i, p, seconds))


## Body `i` is no more (blocks that came down in one have broken up).
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
		var most := SHOVE_MOST if mass[i] > LIGHT else FLUNG
		var speed := minf(SHOVE * power / mass[i], most) * _slow()
		var push := (flat + Vector3.UP * 0.3) * speed * mass[i]
		PhysicsServer3D.body_apply_central_impulse(body[i], push)


## Frozen bodies that reach into `box` move again.
func thaw_in(box: AABB) -> void:
	for i in body.size():
		if alive[i] == 1 and frozen[i] == 1 and box.grow(reach[i]).has_point(_xf[i].origin):
			thaw(i)


## Body `i` moves again, if it was frozen, and those it is joined with.
func thaw(i: int) -> void:
	if alive[i] == 0:
		return
	var all := PackedInt32Array([i]) if joined[i] < 0 else _together[joined[i]]
	for k in all:
		_quiet[k] = 0.0
		if alive[k] == 0 or frozen[k] == 0:
			continue
		frozen[k] = 0
		awake += 1
		PhysicsServer3D.body_set_mode(body[k], PhysicsServer3D.BODY_MODE_RIGID)


func _physics_process(delta: float) -> void:
	_brute_id = brute.get_instance_id() if brute != null else 0
	if brute != null:
		_brute_at = brute.global_position + Vector3.UP
	for k in range(_slips.size() - 1, -1, -1):
		_slips[k].y -= delta
		if _slips[k].y <= 0.0:
			var i := int(_slips[k].x)
			if alive[i] == 1:
				PhysicsServer3D.body_set_param(body[i], PhysicsServer3D.BODY_PARAM_FRICTION, FRICTION)
			_slips.remove_at(k)
	for k in range(_through.size() - 1, -1, -1):
		_through[k].z -= delta
		if _through[k].z <= 0.0:
			var i := int(_through[k].x)
			var rest_of := structure.body_of(int(_through[k].y))
			if alive[i] == 1 and rest_of.is_valid():
				PhysicsServer3D.body_remove_collision_exception(body[i], rest_of)
			_through.remove_at(k)
	for i in _freeze:
		# (Bodies joined to one another: only once all of them are quiet.)
		var all := PackedInt32Array([i]) if joined[i] < 0 else _together[joined[i]]
		var rests := true
		for k in all:
			if alive[k] == 1 and frozen[k] == 0 and _quiet[k] < QUIET_TIME:
				rests = false
		if not rests:
			continue
		for k in all:
			if alive[k] == 1 and frozen[k] == 0:
				frozen[k] = 1
				awake -= 1
				_lin[k] = Vector3.ZERO
				_ang[k] = Vector3.ZERO
				PhysicsServer3D.body_set_mode(body[k], PhysicsServer3D.BODY_MODE_STATIC)
	_freeze.clear()
	if _hits.is_empty():
		return
	var hits := _hits
	_hits = []
	for hit in hits:
		_land(hit[0], hit[1], hit[2], hit[3], hit[4])


## Moves what body `i` moves of the mesh to where the body is.
func _draw(i: int) -> void:
	var now := _xf[i] * Transform3D(Basis(), -origin[i])
	for part: Array in _rig[i]:
		structure.mesh.set_body(part[0], now * (part[1] as Transform3D), part[2])


## Speeds go with the square root of the gravity that makes them: what is
## told as at real gravity is this much less here.
func _slow() -> float:
	return sqrt(fall)


## What a fold that holds `holds` N.m at real gravity is given to hold in
## a step, at the gravity there is here.
func _impulse(holds: float) -> float:
	return holds * fall / Engine.physics_ticks_per_second


## Called by the physics engine for every body that moved in the last step.
func _moved(state: PhysicsDirectBodyState3D, i: int) -> void:
	if alive[i] == 0 or frozen[i] == 1:
		return
	var lin := state.linear_velocity
	var ang := state.angular_velocity
	var was := _lin[i]
	_xf[i] = state.transform
	var near := _brute_id != 0 and _xf[i].origin.distance_to(_brute_at) < reach[i] + NEAR
	if near and (lin.y > LIFT or Vector2(lin.x, lin.z).length() > PUSH or ang.length() > SPIN):
		var along := Vector2(lin.x, lin.z).limit_length(PUSH)
		lin = Vector3(along.x, minf(lin.y, LIFT), along.y)
		ang = ang.limit_length(SPIN)
		state.linear_velocity = lin
		state.angular_velocity = ang
	_lin[i] = lin
	_ang[i] = ang
	_draw(i)
	var touching := state.get_contact_count()
	var slow := _slow()
	var on_brute := false
	if touching > 0 and near:
		for k in touching:
			if state.get_contact_collider_id(k) == _brute_id:
				on_brute = true
				if state.get_contact_local_normal(k).y >= OVER:
					bears_down.emit(_xf[i].origin, mass[i])
	# (What it is joined to holds it as well as what it touches.)
	var still := slow * (QUIET_JOINED if joined[i] >= 0 else 1.0)
	var held := (touching > 0 or joined[i] >= 0) and not on_brute
	if held and lin.length() < QUIET_SPEED * still and ang.length() < QUIET_SPIN * still:
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
	var where := PackedVector3Array()
	var total := 0.0
	for k in touching:
		var impulse := state.get_contact_impulse(k).length()
		total += impulse
		if state.get_contact_local_normal(k).y >= ON_TOP:
			by.append(state.get_contact_collider(k))
			share.append(impulse)
			where.append(state.get_contact_collider_position(k))
	if total <= 0.0:
		return
	for k in share.size():
		share[k] /= total
	# (What is joined to something is also stopped by that: only what the
	# bodies it came down on took from it counts.)
	var lost := total / mass[i] if joined[i] >= 0 else stopped
	_hits.append([i, lost, by, share, where])


## Body `i` was stopped by `stopped` m/s in a step; it came down on the
## bodies `by`, each for its `share` of the stop, at `where`: the pieces
## that stand among them take it as a blow, there, and a piece that was
## coming down whole breaks if it was stopped hard enough.
func _land(
	i: int, stopped: float, by: Array[RID], share: PackedFloat32Array, where: PackedVector3Array
) -> void:
	if alive[i] == 0:
		return
	var blow := mass[i] * stopped / (POINT * _slow())
	var taken := {}  # piece -> points
	var at := {}  # piece -> where
	for k in by.size():
		var stands := structure.standing(by[k])
		if stands >= 0:
			taken[stands] = taken.get(stands, 0.0) + blow * share[k]
			at[stands] = where[k]
	for stands: int in taken:
		if taken[stands] >= WEAK:
			structure.hit(stands, taken[stands], Vector3.ZERO, at[stands])
	if alive[i] == 0 or piece[i] < 0:
		return
	var down := _from_high[i] - _xf[i].origin.y
	if down >= BREAKS_FROM or stopped >= sqrt(2.0 * GRAVITY * fall * BREAKS_FROM):
		structure.lands(i)
