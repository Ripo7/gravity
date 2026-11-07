class_name Falls
extends RefCounted
## The falling pieces of building, one rigid body each (FallingCluster), and
## how they come apart (StructureSet decides what stands and what falls).
## Nothing stays a rigid lump: a piece is cut in chunks along ragged lines
## the moment it falls, and crumbles chunk by chunk:
##   - a tall piece turning over (a toppling tower) cracks across, again and
##     again, along those lines (masonry does not bend);
##   - tumbling or falling fast, it sheds the stones sticking out of it;
##   - a hard landing crushes the part that struck and damages what it hit,
##     then the shock runs on through it and breaks chunks off one after
##     the other (a big piece keeps going, slowed: floors pile up);
##   - resting or leaning, it bears down on what it touches (standing blocks
##     give way, rubble is ground), and once at rest it falls apart from the
##     top into stones, shards and gravel;
##   - a black hole drags it in and tears out the blocks it reaches.

const IMPACT_DV := 3.5  ## m/s change in one step that counts as a hit
const IMPACT_MIN_SPEED := 4.5  ## m/s; slower contacts are just settling
const CLUSTER_MAX_AGE := 9.0
const CHUNK_VOLUME := 13.0
## Big falling pieces of building feel heavier: they fall a bit slower.
const CLUSTER_GRAVITY := 0.72
## A falling block of at least this many pieces crushes the storey that
## struck on each hard landing and keeps going, instead of bursting at once.
const PANCAKE_MIN := 30
const PANCAKE_LAYER := 1.6  ## metres crushed per landing
const PANCAKE_KEEP := 0.3  ## share of speed kept after crushing a layer
## A falling piece knocks a standing one over when its momentum exceeds the
## standing piece's mass times this (m/s).
const KNOCK_SPEED := 0.9
const LEAN_TIME := 0.2  ## seconds of leaning before the weight tells
const LEAN_SPEED := 2.0  ## leaning counts like an impact at this speed
## Seconds between two looks at what a falling piece rests or leans on.
const PRESS_TICK := 0.1
## A heavy piece grinds a piece of rubble it rests on to gravel when its
## weight on it is more than this many times the rubble's own.
const GRIND_LOAD := 40.0
## A standing block bearing this many times what it can take is crushed
## whole; less, it cracks open where it is pressed.
const CRUSH_WHOLE := 3.0
## A falling piece at least TALL times as long as it is wide (a tower)
## cracks across each time it has turned BREAK_TILT (radians) more.
const TALL := 2.5
const BREAK_TILT := 0.2
## The shock of a landing runs through a piece at WAVE_SPEED (m/s), as far
## as WAVE_REACH s times the speed it hit at (a third of that for a big
## piece), breaking off what it reaches with WAVE_KICK times that speed.
const WAVE_SPEED := 22.0
const WAVE_REACH := 0.5
const WAVE_KICK := 0.12
const WAVES_PER_FRAME := 3
## Along a crack, this share of the blocks crumbles instead of staying with
## the chunk that comes away (ragged edges, rubble).
const RIM_CRUMBLE := 0.6
## Blocks smaller than this (m^3) leave a piece as whole stones; bigger
## ones break into shards and gravel as they come away.
const STONE_VOLUME := 0.06
## Faster than this (m/s) or spinning faster than this (rad/s), a piece
## sheds up to PEEL_PER_TICK stones every PRESS_TICK.
const PEEL_SPEED := 5.0
const PEEL_SPIN := 0.8
const PEEL_PER_TICK := 2
## A piece at rest falls apart this many chunks a frame, from the top (see
## _crumble).
const CRUMBLE_CHUNKS := 2
const CRUMBLE_LOOK := 0.25
## A piece that has crept slower than SETTLE_SPEED (m/s) for SETTLE_TIME
## seconds has come to rest (lying across rubble or a ruin): it comes apart.
## So does a piece that has landed and only crawls on (slower than
## CRAWL_SPEED for CRAWL_TIME s), grinding through a roof.
const SETTLE_SPEED := 0.5
const SETTLE_TIME := 0.6
const CRAWL_SPEED := 2.0
const CRAWL_TIME := 0.8

var clusters: Array[FallingCluster] = []
## Most pieces falling at once (more break off: the smallest comes apart).
var max_clusters := int(Quality.pick(16, 22, 30))
## Blocks in a chunk at least (phones: fewer, bigger chunks), and up to
## three times that many small ones (stones), so that a chunk holds about
## CHUNK_VOLUME m^3 whatever the piece is laid in.
var chunk_blocks := int(Quality.pick(10, 8, 7))

var _set: StructureSet


func _init(structures: StructureSet) -> void:
	_set = structures


## Frees every falling body (the world is going away).
func clear() -> void:
	for c in clusters:
		PhysicsServer3D.free_rid(c.body)
		_set._mesh.free_body_mesh(c.mesh)
	clusters.clear()


## {mass, velocity} of the falling piece whose body is `rid`, or empty. The
## velocity is the faster of now and the last step (what it hit stopped it).
func motion(rid: RID) -> Dictionary:
	for c in clusters:
		if c.body == rid:
			return {"mass": c.mass, "velocity": c.hit_velocity()}
	return {}


## World position of the block of falling piece `rid` nearest to `p`, or
## Vector3.INF. Tells whether a falling floor comes at you or falls away.
func point(rid: RID, p: Vector3) -> Vector3:
	for c in clusters:
		if c.body == rid:
			return c.nearest_point(p)
	return Vector3.INF


## Tears the blocks of falling pieces that come within `radius` of `center`
## out of them, as they sink in (they are caught and spun): the rest keeps
## falling as it was, instead of the whole piece bursting at once.
func tear(center: Vector3, radius: float) -> void:
	for c: FallingCluster in clusters.duplicate():
		if not clusters.has(c):
			continue
		var xf := c.transform()
		var torn := PackedInt32Array()
		for k in c.members.size():
			var i := c.members[k]
			var half := _set._size[i] * 0.5
			var at := xf * c.offsets[k]
			if at.origin.distance_to(center) > radius + half.length():
				continue
			var local := at.affine_inverse() * center
			if local.clamp(-half, half).distance_to(local) < radius:
				torn.append(k)
		if torn.is_empty():
			continue
		if c.members.size() - torn.size() < 3:
			dissolve(c, center, 0.0)
			continue
		var v: Vector3 = PhysicsServer3D.body_get_state(c.body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
		var w: Vector3 = PhysicsServer3D.body_get_state(c.body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
		for i in _take_out(c, torn, xf):
			_set._dislodge(i, v + w.cross(_set._xform[i].origin - xf.origin), w, 0.0)
		_regroup(c)


## Makes room for a new falling body of `count` blocks when there are
## already max_clusters: the smallest one (never `spare`) comes apart into
## loose blocks, the least visible change. False if the new one would be
## the smallest itself.
func make_room(count: int, spare: FallingCluster = null) -> bool:
	if clusters.size() < max_clusters:
		return true
	var least: FallingCluster = null
	for c in clusters:
		if c != spare and (least == null or c.members.size() < least.members.size()):
			least = c
	if least == null or least.members.size() >= count:
		return false
	dissolve(least, Vector3.ZERO, 0.0)
	return true


## One rigid body for `blocks` (already FALLING) where they are now, with a
## box per block. `chunks` (one per block) keeps the cracks it had in a
## bigger piece; else it is cut in chunks afresh.
func add(blocks: PackedInt32Array, chunks := PackedInt32Array()) -> FallingCluster:
	var xforms: Array[Transform3D] = []
	var masses := PackedFloat32Array()
	var shapes: Array[RID] = []
	for i in blocks:
		xforms.append(_set._xform[i])
		masses.append(_set._mass[i])
		shapes.append(_set._box_shape(_set._size[i] * 0.995))
	var heavy := CLUSTER_GRAVITY if blocks.size() >= PANCAKE_MIN else 1.0
	var c := FallingCluster.build(blocks, xforms, masses, shapes, _set.get_world_3d().space, heavy)
	var kinds := {}
	for q in chunks:
		kinds[q] = true
	if chunks.size() == blocks.size() and kinds.size() > 1:
		c.chunk = chunks
	else:
		var volume := 0.0
		for i in blocks:
			var z := _set._size[i]
			volume += z.x * z.y * z.z
		var each := roundi(CHUNK_VOLUME * blocks.size() / maxf(volume, 0.01))
		each = clampi(each, chunk_blocks, chunk_blocks * 3)
		c.carve(_set._neighbors, mini(each, maxi(blocks.size() / 3, 2)))
	# Its boxes are drawn by a mesh of its own from now on (see draw).
	for i in blocks:
		if _set.is_box(i):
			_set._clear_instance(i)
	clusters.append(c)
	return c


## Moves each falling piece's mesh to where its body is now, and draws its
## other blocks there (once a rendered frame).
func draw() -> void:
	for c in clusters:
		var xf := c.transform()
		if not c.dressed:
			_dress(c)
		c.mesh.transform = xf
		for k in c.others:
			_set._write_instance(c.members[k], xf * c.offsets[k])


## Lays out the boxes of falling piece `c` in its mesh, in its body space.
func _dress(c: FallingCluster) -> void:
	var rows := PackedFloat32Array()
	rows.resize(c.members.size() * StructureMesh.FLOATS)
	var n := 0
	var bounds := AABB()
	c.others.clear()
	for k in c.members.size():
		var i := c.members[k]
		if not _set.is_box(i):
			c.others.append(k)
			continue
		_set.falling_row(rows, n * StructureMesh.FLOATS, i, c.offsets[k])
		var r := _set._size[i].length() * 0.5
		var box := AABB(c.offsets[k].origin - Vector3.ONE * r, Vector3.ONE * r * 2.0)
		bounds = box if n == 0 else bounds.merge(box)
		n += 1
	rows.resize(n * StructureMesh.FLOATS)
	if c.mesh == null:
		c.mesh = _set._mesh.body_mesh(rows, n, bounds)
	else:
		_set._mesh.refill(c.mesh, rows, n, bounds)
	c.dressed = true


## Takes the blocks at positions `ks` (in c.members) out of falling cluster
## `c`; their transform becomes where they are now (`xf`: the body's).
## Returns the blocks, still FALLING: the caller decides what they become.
func _take_out(c: FallingCluster, ks: PackedInt32Array, xf: Transform3D) -> PackedInt32Array:
	var where: Array[Transform3D] = []
	var out := c.take_out(ks, xf, where)
	for k in out.size():
		_set._xform[out[k]] = where[k]
	return out


## What is left of falling cluster `c` after blocks were taken out may be in
## several pieces (nothing holds them together any more): the biggest stays
## `c`, each other one falls on as a body of its own (loose blocks when
## small), moving as it was.
func _regroup(c: FallingCluster) -> void:
	_split(c, c.parts(_set._neighbors))


## Splits falling cluster `c` by `part` (a piece number per member): piece 0
## stays `c`, each other one falls on as a body of its own (loose blocks
## when small), moving as it was.
func _split(c: FallingCluster, part: PackedInt32Array) -> void:
	var pieces: Array[PackedInt32Array] = []
	var chunks: Array[PackedInt32Array] = []
	var away := PackedInt32Array()
	for k in part.size():
		if part[k] == 0:
			continue
		if part[k] >= pieces.size():
			pieces.resize(part[k] + 1)
			chunks.resize(part[k] + 1)
		pieces[part[k]].append(c.members[k])
		chunks[part[k]].append(c.chunk[k])
		away.append(k)
	if away.is_empty():
		return
	var xf := c.transform()
	var v: Vector3 = PhysicsServer3D.body_get_state(c.body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	var w: Vector3 = PhysicsServer3D.body_get_state(c.body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
	_take_out(c, away, xf)
	for p in pieces.size():
		var blocks := pieces[p]
		if blocks.is_empty():
			continue
		if blocks.size() < 3 or not make_room(blocks.size(), c):
			for i in blocks:
				_loosen(i, v + w.cross(_set._xform[i].origin - xf.origin), w)
			continue
		_fly_on(add(blocks, chunks[p]), c, xf, v, w, Vector3.ZERO)


## New piece `piece` (split off `from`, which was at `xf` moving at `v`,
## spinning at `w`) goes on as that part of it was moving, plus `kick`.
func _fly_on(
	piece: FallingCluster, from: FallingCluster, xf: Transform3D, v: Vector3, w: Vector3, kick: Vector3
) -> void:
	var pv := v + w.cross(piece.transform().origin - xf.origin) + kick
	PhysicsServer3D.body_set_state(piece.body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, pv)
	PhysicsServer3D.body_set_state(piece.body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, w)
	piece.age = from.age
	piece.toppled = from.toppled
	piece.prev_velocity = pv
	piece.recent.fill(pv.length())


## Breaks a cluster up at once into loose debris (the rest of what its
## chunks did not take). `severity` (impact speed) decides how much of it
## shatters around `hit`.
func dissolve(c: FallingCluster, hit: Vector3, severity: float) -> void:
	clusters.erase(c)
	_set._mesh.free_body_mesh(c.mesh)
	c.mesh = null
	var xf: Transform3D = PhysicsServer3D.body_get_state(c.body, PhysicsServer3D.BODY_STATE_TRANSFORM)
	var v: Vector3 = PhysicsServer3D.body_get_state(c.body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	var w: Vector3 = PhysicsServer3D.body_get_state(c.body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
	PhysicsServer3D.free_rid(c.body)
	# A real hit breaks what falls: all near the hit, every big block (a
	# floor never lands whole) and, the harder the hit, more of the rest.
	var shatter_chance := clampf((severity - 3.0) / 9.0, 0.0, 0.8)
	var near := clampf(severity * 0.18, 0.8, 2.5)
	var big := _set.debris.max_piece * 2.0 if _set.debris else INF
	var keep := _fair_share(c.members.size())
	for k in c.members.size():
		var i := c.members[k]
		if _set._state[i] != StructureSet.State.FALLING:
			continue
		var world := xf * c.offsets[k]
		_set._xform[i] = world
		var r := world.origin - xf.origin
		var vel := v + w.cross(r)
		var close := hit != Vector3.ZERO and world.origin.distance_to(hit) < near
		var bulk := _set._size[i].x * _set._size[i].y * _set._size[i].z > big
		if severity > 4.0 and (close or bulk or randf() < shatter_chance):
			_set._shatter(i, hit, severity * 0.3, vel * 0.6, true, keep)
		else:
			var spin := w
			if severity <= 0.0:
				# Came to rest without a real hit (leaning on rubble): loosen
				# the blocks so the pile slumps instead of standing in mid-air.
				# (Per piece: adding to `w` itself made it grow with every
				# block and flung big pieces across the city.)
				vel += Vector3(randf_range(-1, 1), randf_range(0, 0.5), randf_range(-1, 1)) * 0.8
				spin += Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 2.0
			_loosen(i, vel, spin, keep)


## Centres of the falling pieces of building moving faster than `speed`
## (for dust trails).
func positions(speed: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for c in clusters:
		if c.prev_velocity.length_squared() > speed * speed:
			var xf: Transform3D = PhysicsServer3D.body_get_state(c.body, PhysicsServer3D.BODY_STATE_TRANSFORM)
			out.append(xf.origin)
	return out


## Moves the falling pieces on by `delta` seconds (see the class notes).
func update(delta: float) -> void:
	for c: FallingCluster in clusters.duplicate():
		# An earlier one may have dissolved this one (knocked over, too many).
		if not clusters.has(c):
			continue
		c.age += delta
		var xf: Transform3D = PhysicsServer3D.body_get_state(c.body, PhysicsServer3D.BODY_STATE_TRANSFORM)
		if c.crumbling:
			_crumble(c, xf, delta)
			continue
		var v: Vector3 = PhysicsServer3D.body_get_state(c.body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
		var asleep: bool = PhysicsServer3D.body_get_state(c.body, PhysicsServer3D.BODY_STATE_SLEEPING)
		var w: Vector3 = PhysicsServer3D.body_get_state(c.body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
		var before := c.prev_velocity
		var spun := c.prev_spin
		var hit := c.track(v, w)  # (speed lost, fastest recent speed)
		# Slow bumps (settling onto rubble) do not count; real hits do.
		# A big falling block landing on rubble crushes a storey too.
		var heavy := c.members.size() >= PANCAKE_MIN
		if (
			c.age > 0.1
			and hit.x > IMPACT_DV
			and hit.y > IMPACT_MIN_SPEED
			and (heavy or c.touches_solid(_set.debris))
		):
			_impact(c, xf, hit.y, before, spun)
			continue
		_bear_down(c, xf, delta)
		if clusters.has(c):
			_run_waves(c, delta)
		if clusters.has(c):
			_crack(c, xf)
		if clusters.has(c):
			_peel(c, xf, v, w, delta)
		if not clusters.has(c):
			continue
		# Push through rubble rather than stopping dead on frozen pieces.
		if _set.debris and _set.debris.frozen_count > 0 and v.length() > 1.0:
			c.crush_tick -= delta
			if c.crush_tick <= -0.05:
				c.crush_tick = 0.0
				_set.debris.thaw_box(c.bounds(xf).grow(0.4).merge(c.bounds(xf.translated(v * 0.15))), 0.4)
		c.slow_time = c.slow_time + delta if v.length() < SETTLE_SPEED else 0.0
		c.crawl_time = c.crawl_time + delta if c.landed and v.length() < CRAWL_SPEED else 0.0
		if c.age > CLUSTER_MAX_AGE or xf.origin.y < DebrisSystem.KILL_Y:
			dissolve(c, Vector3.ZERO, 0.0)
			continue
		# At rest (lying across rubble or a ruin): it falls apart from now on.
		c.crumbling = (
			c.crumbling or c.slow_time > SETTLE_TIME or c.crawl_time > CRAWL_TIME or (asleep and c.age > 0.5)
		)


## A black hole at `center` drags the falling pieces within `reach` toward
## it (`strength` m/s^2 at `radius`, fading out at `reach`, twice that at
## the core) and round it (`swirl`), block by block, so a long piece swings in
## by its near end; inside the radius they weigh nothing. What gets inside
## is torn out of them (see tear).
func pull(center: Vector3, radius: float, reach: float, strength: float, swirl: float, dt: float) -> void:
	for c in clusters:
		var xf := c.transform()
		if xf.origin.distance_to(center) > reach + c.extent():
			continue
		var g := 9.8 * c.gravity_scale
		var force := Vector3.ZERO
		var torque := Vector3.ZERO
		for k in c.members.size():
			var p := xf * c.offsets[k].origin
			var to := center - p
			var d := to.length()
			if d > reach or d < 0.05:
				continue
			var near := (
				sqrt(clampf((reach - d) / (reach - radius), 0.0, 1.0)) if d > radius else 2.0 - d / radius
			)
			var around := Vector3.UP.cross(-to)
			around.y = 0.0
			var a := to / d * strength * near
			if around.length_squared() > 0.0025:
				a += around.normalized() * swirl * near
			if d < radius:
				a.y += g
			var f := a * c.masses[k]
			force += f
			torque += (p - xf.origin).cross(f)
		if force == Vector3.ZERO:
			continue
		PhysicsServer3D.body_apply_central_impulse(c.body, force * dt)
		PhysicsServer3D.body_apply_torque_impulse(c.body, torque * dt)
		PhysicsServer3D.body_set_state(c.body, PhysicsServer3D.BODY_STATE_SLEEPING, false)
		c.slow_time = 0.0


## A piece resting or leaning on things bears down on them with its weight,
## shared out as its contacts push (Jolt's impulses only give the shares):
##   - the first standing piece it leans on may be pushed over whole (a
##     tower into a tower);
##   - a standing block gives way when its share is more than it can carry
##     (down) or hold (sideways): a tower toppling onto the palace crushes
##     the wall it leans on and falls on into it, instead of resting there;
##   - loose rubble under a heavy piece is ground to gravel, so it settles
##     instead of standing on a few broken stubs.
func _bear_down(c: FallingCluster, xf: Transform3D, delta: float) -> void:
	c.press_tick -= delta
	if c.press_tick > 0.0 or c.age < 0.2:
		return
	c.press_tick = PRESS_TICK
	var state := PhysicsServer3D.body_get_direct_state(c.body)
	if state == null:
		return
	var pushes := {}  # standing block, or debris piece as -2 - index -> impulse
	var where := {}  # standing block -> a contact point on it
	var total := 0.0
	for k in state.get_contact_count():
		var j := state.get_contact_impulse(k)
		total += j.length()
		var rid := state.get_contact_collider(k)
		var seg: int = _set._rid_to_seg.get(rid, -1)
		var piece := _set.debris.index_of(rid) if _set.debris and seg < 0 else -1
		var key := (
			seg
			if seg >= 0 and _set._state[seg] == StructureSet.State.STATIC
			else (-2 - piece if piece >= 0 else -1)
		)
		if key != -1:
			pushes[key] = pushes.get(key, Vector3.ZERO) + j
			where[key] = state.get_contact_collider_position(k)
	c.lean_time = c.lean_time + PRESS_TICK if not pushes.is_empty() else 0.0

	if c.lean_time < LEAN_TIME or total <= 0.0:
		return
	# What its contacts carry of its weight now (kg): nothing in free fall,
	# all of it at rest (Jolt's impulses can add up to more: shares then).
	var carried := c.mass * minf(total / (c.mass * 9.8 * delta), 1.0)
	var gave := 0
	var worn := PackedVector3Array()  # where it crushed standing blocks
	for key: int in pushes:
		var j: Vector3 = pushes[key]
		var weight := carried * j.length() / total
		if key < 0:
			var piece := -2 - key
			if (
				c.members.size() >= PANCAKE_MIN
				and weight > _set.debris.mass_of(piece) * GRIND_LOAD
				and gave < 25
			):
				if _set.dust:
					_set.dust.chips_box(
						_set.debris.position_of(piece),
						_set.debris.size_of(piece),
						_set.debris.kind_of(piece),
						6,
						2.0
					)
				_set.debris.bury(piece)
				gave += 1
			continue
		if not c.leaned:
			c.leaned = true
			var push: Vector3 = where[key] - xf.origin
			push.y = 0.0
			_knock(key, push.normalized() * 2.0, c.mass * LEAN_SPEED, where[key])
		if _set._state[key] != StructureSet.State.STATIC:
			continue
		var down := weight * absf(j.normalized().y)
		var side := sqrt(maxf(weight * weight - down * down, 0.0))
		var health := clampf(_set._health[key] / _set._max_health[key], 0.15, 1.0)
		var over := maxf(
			down / maxf(_set._capacity[key] * health - _set._load[key], 1.0),
			side / maxf(_set._shear_cap[key] * health, 1.0)
		)
		if over > CRUSH_WHOLE:
			# Far too much: the block is crushed, and what is around it too.
			_set._shatter(key, where[key], 0.0)
			_set.apply_impact(where[key], clampf(over * 0.1, 0.8, 2.0), minf(over, 20.0))
			gave += 1
			worn.append(where[key])
		elif over > 1.0:
			_set._shatter(key, where[key], 2.0)  # a little: it cracks open there
			gave += 1
	if gave > 0:
		# It sinks into the room it just made: keep it awake and falling.
		PhysicsServer3D.body_set_state(c.body, PhysicsServer3D.BODY_STATE_SLEEPING, false)
		c.age = maxf(c.age - PRESS_TICK, 0.35)
	# Masonry crushing masonry gives way too, where it presses.
	var ground := c.near(xf, worn, 1.0)
	if not ground.is_empty() and ground.size() < c.members.size() - 3:
		var v: Vector3 = PhysicsServer3D.body_get_state(c.body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
		for i in _take_out(c, ground, xf):
			_loosen(i, v + Vector3(randf_range(-1, 1), 0.3, randf_range(-1, 1)), Vector3.ZERO)
		_regroup(c)


## A falling piece hit something: the part that struck is crushed into
## shards and gravel and what it hit takes the blow; then the shock runs on
## through it and breaks chunks off one after the other, the farther the
## harder it hit (see _shake). A big piece keeps going, slowed: floors pile
## up storey by storey, a toppling tower breaks up from its top as it comes
## down onto the palace. `push` and `spin`: how it moved just before.
func _impact(c: FallingCluster, xf: Transform3D, speed: float, push: Vector3, spin: Vector3) -> void:
	var spots := c.struck_points(xf, push, spin)
	var hit := c.lowest_point(xf)
	var struck := -1
	var state := PhysicsServer3D.body_get_direct_state(c.body)
	if state:
		for k in state.get_contact_count():
			hit = state.get_contact_collider_position(k)
			var seg: int = _set._rid_to_seg.get(state.get_contact_collider(k), -1)
			if seg >= 0 and _set._state[seg] == StructureSet.State.STATIC:
				struck = seg  # hitting a standing structure matters most
				break
	if spots.is_empty():
		spots.append(hit)
	var heavy := c.members.size() >= PANCAKE_MIN
	var crush := c.near(xf, spots, PANCAKE_LAYER)
	var mid := Vector3.ZERO
	for q in spots:
		mid += q
	mid /= spots.size()
	var v: Vector3 = PhysicsServer3D.body_get_state(c.body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	if heavy:
		_set.floor_crushed.emit(mid, crush.size(), speed)
		_set.cluster_impact.emit(mid, c.mass * crush.size() / c.members.size(), speed, crush.size())
	else:
		_set.cluster_impact.emit(mid, c.mass, speed, c.members.size())
	if _set.debris:
		_set.debris.thaw_near(mid, 3.0)
	var blow := spots.duplicate()
	blow.append(hit)
	if heavy:
		_strike(blow, 1.5, speed * 0.3 * _heft(c))
	else:
		_strike(blow, clampf(0.8 + c.members.size() * 0.02, 1.0, 2.5), speed * 0.35 * _heft(c))
	var keep := _fair_share(crush.size())
	for i in _take_out(c, crush, xf):
		if randf() < 0.65:
			_set._shatter(i, mid, speed * 0.25, v * 0.2, true, keep)
		else:
			_loosen(i, v * 0.25 + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)), Vector3.ZERO, keep)
	if c.members.size() < 3:
		dissolve(c, mid, speed)
	else:
		_shake(c, xf, spots, clampf(speed * WAVE_REACH * (0.35 if heavy else 1.0), 1.0, 12.0), speed)
		_regroup(c)
		# Keep going, slowed, onto what is below (and do not count this
		# landing again next step).
		var keep_v := v * (PANCAKE_KEEP if heavy else 1.0)
		PhysicsServer3D.body_set_state(c.body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, keep_v)
		PhysicsServer3D.body_set_state(c.body, PhysicsServer3D.BODY_STATE_SLEEPING, false)
		c.recent = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
		c.prev_velocity = keep_v
		c.age = 0.05
		c.landed = true
	if struck >= 0 and _set._state[struck] == StructureSet.State.STATIC:
		_knock(struck, push, c.mass * speed, hit)


## The shock of a landing runs through what is left of `c` from `spots`:
## each chunk within `reach` breaks off when it gets there (WAVE_SPEED),
## pushed off harder the nearer it is.
func _shake(
	c: FallingCluster, xf: Transform3D, spots: PackedVector3Array, reach: float, speed: float
) -> void:
	var near := {}  # chunk -> how far from the blow
	for k in c.members.size():
		var p := xf * c.offsets[k].origin
		var d := INF
		for q in spots:
			d = minf(d, p.distance_to(q))
		near[c.chunk[k]] = minf(near.get(c.chunk[k], INF), d)
	var from := spots[0]
	for q: int in near:
		var d: float = near[q]
		if d < reach:
			c.waves.append(
				{
					"time": d / WAVE_SPEED,
					"chunk": q,
					"from": from,
					"kick": speed * WAVE_KICK * (1.0 - d / reach)
				}
			)


## Breaks off the chunks the shock has reached by now (a few a frame).
func _run_waves(c: FallingCluster, delta: float) -> void:
	var done := 0
	for wave: Dictionary in c.waves.duplicate():
		wave["time"] -= delta
		if wave["time"] > 0.0 or done >= WAVES_PER_FRAME:
			continue
		c.waves.erase(wave)
		var ks := c.chunk_members(wave["chunk"])
		if ks.is_empty():
			continue
		if ks.size() > c.members.size() - 3:
			c.crumbling = true  # it is all that is left: it falls apart
			c.waves.clear()
			return
		_break_off(c, ks, wave["from"], wave["kick"])
		done += 1
		if not clusters.has(c):
			return


## The blocks at positions `ks` come away from falling piece `c`, pushed
## from `from` at `kick` m/s on top of how they moved: together as a piece
## of their own when they are enough, while about half of the rim along the
## crack crumbles into stones, shards and gravel.
func _break_off(c: FallingCluster, ks: PackedInt32Array, from: Vector3, kick: float) -> void:
	var xf := c.transform()
	var v: Vector3 = PhysicsServer3D.body_get_state(c.body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	var w: Vector3 = PhysicsServer3D.body_get_state(c.body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
	var rim := {}
	for k in c.rim(ks, _set._neighbors):
		rim[c.members[k]] = true
	var chunk_of := {}
	for k in ks:
		chunk_of[c.members[k]] = c.chunk[k]
	var blocks := _take_out(c, ks, xf)
	var centre := Vector3.ZERO
	for i in blocks:
		centre += _set._xform[i].origin
	centre /= blocks.size()
	var away := (centre - from).normalized() if centre.distance_to(from) > 0.05 else Vector3.UP
	var keep := _fair_share(blocks.size())
	var piece := PackedInt32Array()
	var chunks := PackedInt32Array()
	var crumbs := 0
	for i in blocks:
		if rim.has(i) and randf() < RIM_CRUMBLE:
			var r := _set._xform[i].origin - xf.origin
			_loosen(i, v + w.cross(r) + away * kick * randf_range(0.5, 1.2), w, keep)
			crumbs += 1
		else:
			piece.append(i)
			chunks.append(chunk_of[i])
	if piece.size() >= 3 and make_room(piece.size(), c):
		var spin := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * kick * 0.3
		var nc := add(piece, chunks)
		_fly_on(nc, c, xf, v, w + spin, away * kick)
	else:
		for i in piece:
			_loosen(i, v + w.cross(_set._xform[i].origin - xf.origin) + away * kick, w, keep)
	if crumbs > 0 and _set.dust:
		_set.dust.puff(centre, clampf(crumbs * 0.4, 0.8, 2.5), _set._kind[blocks[0]], mini(4 + crumbs, 10))
	if c.members.size() < 3:
		dissolve(c, from, 0.0)
	elif clusters.has(c):
		_regroup(c)


## A tall piece that has turned BREAK_TILT more since it last cracked (a
## toppling tower) cracks across along the ragged line of its chunks: what
## is beyond goes on alone. Masonry does not bend.
func _crack(c: FallingCluster, xf: Transform3D) -> void:
	if c.members.size() < 12:
		return
	var turned := xf.basis.get_rotation_quaternion().get_angle()
	if turned - c.turned_at < BREAK_TILT:
		return
	c.turned_at = turned
	var beyond := c.crack_line(xf, TALL)
	if not beyond.is_empty():
		_break_off(c, beyond, xf.origin, 0.0)


## Tumbling or falling fast, a piece sheds the stones sticking out of it.
func _peel(c: FallingCluster, xf: Transform3D, v: Vector3, w: Vector3, delta: float) -> void:
	c.peel_tick -= delta
	if c.peel_tick > 0.0 or c.members.size() < 6:
		return
	c.peel_tick = PRESS_TICK
	var rush := maxf(v.length() - PEEL_SPEED, 0.0) / 8.0 + maxf(w.length() - PEEL_SPIN, 0.0)
	if randf() >= rush:
		return
	var ks := c.loose(_set._neighbors, PEEL_PER_TICK)
	if ks.is_empty():
		return
	for i in _take_out(c, ks, xf):
		var r := _set._xform[i].origin - xf.origin
		var out := r.normalized() if r.length() > 0.1 else Vector3.UP
		_loosen(i, v + w.cross(r) + out * randf_range(0.5, 1.5), w)
	if c.members.size() < 3:
		dissolve(c, Vector3.ZERO, 0.0)
	else:
		_regroup(c)


## A piece at rest falls apart from the top, a few chunks a frame, into
## stones, shards and gravel: a heap, not blocks. Which chunks are on top,
## and whether what is left still holds together, is looked at again every
## CRUMBLE_LOOK seconds (a big piece is hundreds of stones).
func _crumble(c: FallingCluster, xf: Transform3D, delta: float) -> void:
	if c.members.size() < 3:
		dissolve(c, Vector3.ZERO, 0.0)
		return
	c.crumble_look -= delta
	if c.crumble_look <= 0.0 or c.crumble_order.is_empty():
		c.crumble_look = CRUMBLE_LOOK
		_regroup(c)
		if not clusters.has(c) or c.members.size() < 3:
			return
		var tops := {}  # chunk -> highest block centre
		for k in c.members.size():
			tops[c.chunk[k]] = maxf(tops.get(c.chunk[k], -INF), (xf * c.offsets[k].origin).y)
		var order := tops.keys()
		order.sort_custom(func(a: int, b: int) -> bool: return tops[a] < tops[b])
		c.crumble_order = PackedInt32Array(order)  # highest last
	var ks := PackedInt32Array()
	var taken := 0
	while taken < CRUMBLE_CHUNKS and not c.crumble_order.is_empty():
		var q := c.crumble_order[c.crumble_order.size() - 1]
		c.crumble_order.resize(c.crumble_order.size() - 1)
		var members := c.chunk_members(q)
		if not members.is_empty():
			ks.append_array(members)
			taken += 1
	if ks.size() > c.members.size() - 3:
		dissolve(c, Vector3.ZERO, 0.0)
		return
	var v: Vector3 = PhysicsServer3D.body_get_state(c.body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	var blocks := _take_out(c, ks, xf)
	var keep := _fair_share(blocks.size())
	var centre := Vector3.ZERO
	for i in blocks:
		var r := _set._xform[i].origin - xf.origin
		var slump := Vector3(r.x, 0, r.z).normalized() * randf_range(0.2, 0.8)
		_loosen(i, v + slump, Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5), keep)
		centre += _set._xform[i].origin
	if _set.dust and not blocks.is_empty():
		_set.dust.puff(centre / blocks.size(), 1.5, _set._kind[blocks[0]], 6)


## Block `i` leaves a falling piece as rubble, moving at `vel`: a small
## stone stays whole, a bigger block breaks into shards and gravel.
func _loosen(i: int, vel: Vector3, spin: Vector3, keep := 0) -> void:
	var size := _set._size[i]
	if size.x * size.y * size.z < STONE_VOLUME:
		_set._dislodge(i, vel, spin, 0.0, keep)
		return
	var behind := vel.normalized() * 0.5 if vel.length() > 0.1 else Vector3.DOWN * 0.5
	_set._shatter(i, _set._xform[i].origin - behind, 1.0, vel, true, keep)


## Heavy pieces hit harder (chain reactions, dominoes): 1 to 3.
func _heft(c: FallingCluster) -> float:
	return clampf(c.mass / 800.0, 1.0, 3.0)


## Damage around each of `points` (a piece lands on all it struck, not on
## one spot), skipping points within a metre of one already hit.
func _strike(points: PackedVector3Array, radius: float, damage: float) -> void:
	var done := PackedVector3Array()
	for p in points:
		var near := false
		for q in done:
			near = near or p.distance_squared_to(q) < 1.0
		if near:
			continue
		done.append(p)
		_set.apply_impact(p, radius, damage)
		if done.size() >= 8:
			return


## A heavy hit can push a whole standing piece over (dominoes, towers).
func _knock(seg: int, velocity: Vector3, momentum: float, at: Vector3) -> void:
	var comp := _component_of(seg)
	var mass := 0.0
	var top := -INF
	var bottom := INF
	for i in comp:
		mass += _set._mass[i]
		top = maxf(top, _set._xform[i].origin.y)
		bottom = minf(bottom, _set._xform[i].origin.y)
	# Hits low on a piece barely tip it; hits near the top tip it easily.
	var lever := clampf((at.y - bottom) / maxf(top - bottom, 0.5), 0.2, 1.0)
	if momentum * lever < mass * KNOCK_SPEED:
		return
	var flat := Vector3(velocity.x, 0, velocity.z)
	if flat.length() < 0.1:
		return
	var dir := flat.normalized()
	var share := clampf(momentum / (mass + 1.0) * 0.4, 0.5, 4.0)
	if comp.size() < 3 or _set.debris == null:
		# Too small for a falling body of its own: the pieces take the push.
		for i in comp:
			_set._dislodge(i, dir * share, Vector3.UP.cross(dir) * share * 0.35)
		return
	var before := clusters.size()
	_set._release(comp, false)
	if clusters.size() <= before:
		return
	var c := clusters[clusters.size() - 1]
	PhysicsServer3D.body_set_state(c.body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, dir * share)
	PhysicsServer3D.body_set_state(
		c.body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.UP.cross(dir) * share * 0.35
	)


func _component_of(seg: int) -> PackedInt32Array:
	var comp := PackedInt32Array()
	var seen := {seg: true}
	var stack: Array[int] = [seg]
	while not stack.is_empty():
		var i: int = stack.pop_back()
		comp.append(i)
		for n in _set._neighbors[i]:
			if _set._state[n] == StructureSet.State.STATIC and not seen.has(n):
				seen[n] = true
				stack.append(n)
	return comp


## Bodies each of `count` blocks breaking at once may leave, so the pool
## shares out what it can spare (0: as many as usual): a whole falling
## tower breaks into chunks, not into gravel once the pool is full.
func _fair_share(count: int) -> int:
	if _set.debris == null or count <= 0:
		return 0
	var want := count * _set.debris.max_bodies
	var room := _set.debris.room(want)
	if room >= want:
		return 0
	return clampi(room / count, 1, _set.debris.max_bodies)
