class_name Falls
extends RefCounted
## The falling pieces of building, one rigid body each (FallingCluster), and
## what becomes of them (StructureSet decides what stands and what falls):
##   - a tall piece toppling over snaps across its height, each section
##     flying on as it was moving (masonry does not bend);
##   - resting or leaning, a piece bears down on what it touches: standing
##     blocks give way when that is more than they can carry, rubble is
##     ground to gravel;
##   - a hard landing crushes the part that struck (floors pile up storey by
##     storey) and damages what it hit; a smaller piece breaks up;
##   - a black hole tears the blocks it reaches out of a piece as it sinks in.

const MAX_CLUSTERS := 12
const IMPACT_DV := 3.5  ## m/s change in one step that counts as a hit
const IMPACT_MIN_SPEED := 4.5  ## m/s; slower contacts are just settling
const CLUSTER_MAX_AGE := 9.0
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
## breaks across its height into sections about SECTION times as long as it
## is wide once it has tipped BREAK_TILT (radians) over: masonry snaps.
const TALL := 2.5
const SECTION := 1.3
const BREAK_TILT := 0.2
## A piece that has crept slower than SETTLE_SPEED (m/s) for SETTLE_TIME
## seconds has come to rest (lying across rubble or a ruin): it comes apart.
const SETTLE_SPEED := 0.5
const SETTLE_TIME := 0.6

var clusters: Array[FallingCluster] = []

var _set: StructureSet


func _init(structures: StructureSet) -> void:
	_set = structures


## Frees every falling body (the world is going away).
func clear() -> void:
	for c in clusters:
		PhysicsServer3D.free_rid(c.body)
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
## already MAX_CLUSTERS: the smallest one comes apart into loose blocks (the
## least visible change). False if the new one is the smallest itself.
func make_room(count: int) -> bool:
	if clusters.size() < MAX_CLUSTERS:
		return true
	var least := clusters[0]
	for c in clusters:
		if c.members.size() < least.members.size():
			least = c
	if least.members.size() >= count:
		return false
	dissolve(least, Vector3.ZERO, 0.0)
	return true


## One rigid body for `blocks` (already FALLING) where they are now, with a
## box per block.
func add(blocks: PackedInt32Array) -> FallingCluster:
	var xforms: Array[Transform3D] = []
	var masses := PackedFloat32Array()
	var shapes: Array[RID] = []
	for i in blocks:
		xforms.append(_set._xform[i])
		masses.append(_set._mass[i])
		shapes.append(_set._box_shape(_set._size[i] * 0.995))
	var heavy := CLUSTER_GRAVITY if blocks.size() >= PANCAKE_MIN else 1.0
	var c := FallingCluster.build(blocks, xforms, masses, shapes, _set.get_world_3d().space, heavy)
	clusters.append(c)
	return c


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
	var away := PackedInt32Array()
	for k in part.size():
		if part[k] == 0:
			continue
		if part[k] >= pieces.size():
			pieces.resize(part[k] + 1)
		pieces[part[k]].append(c.members[k])
		away.append(k)
	if away.is_empty():
		return
	var xf := c.transform()
	var v: Vector3 = PhysicsServer3D.body_get_state(c.body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	var w: Vector3 = PhysicsServer3D.body_get_state(c.body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
	_take_out(c, away, xf)
	for blocks in pieces:
		if blocks.is_empty():
			continue
		if blocks.size() < 3 or not make_room(blocks.size()):
			for i in blocks:
				_set._dislodge(i, v + w.cross(_set._xform[i].origin - xf.origin), w, 0.0)
			continue
		var piece := add(blocks)
		var pv := v + w.cross(piece.transform().origin - xf.origin)
		PhysicsServer3D.body_set_state(piece.body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, pv)
		PhysicsServer3D.body_set_state(piece.body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, w)
		piece.age = c.age
		piece.toppled = c.toppled
		piece.prev_velocity = pv
		piece.recent.fill(pv.length())


## Breaks a cluster into loose debris. `severity` (impact speed) decides how
## much of it shatters around `hit`.
func dissolve(c: FallingCluster, hit: Vector3, severity: float) -> void:
	clusters.erase(c)
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
			_set._dislodge(i, vel, spin, 0.0, keep)


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
		if not clusters.has(c):
			continue
		var cut := c.sections(xf, BREAK_TILT, TALL, SECTION)
		if not cut.is_empty():
			_split(c, cut)
		# Push through rubble rather than stopping dead on frozen pieces.
		if _set.debris and _set.debris.frozen_count > 0 and v.length() > 1.0:
			c.crush_tick -= delta
			if c.crush_tick <= -0.05:
				c.crush_tick = 0.0
				_set.debris.thaw_box(c.bounds(xf).grow(0.4).merge(c.bounds(xf.translated(v * 0.15))), 0.4)
		c.slow_time = c.slow_time + delta if v.length() < SETTLE_SPEED else 0.0
		var settled := c.slow_time > SETTLE_TIME or (asleep and c.age > 0.5)
		if c.age > CLUSTER_MAX_AGE or settled or xf.origin.y < DebrisSystem.KILL_Y:
			dissolve(c, Vector3.ZERO, 0.0)
			continue
		for k in c.members.size():
			_set._write_instance(c.members[k], xf * c.offsets[k])


## A big falling block landed: the storey that struck (around `struck`,
## else its lowest) is crushed into rubble and the rest keeps going, slowed
## down: floors pile up one after the other, a toppling tower breaks up
## from its top as it comes down onto the palace, instead of the whole
## thing bursting at once. Returns false when there is nothing left to
## crush (then it breaks up as usual).
func _pancake(c: FallingCluster, xf: Transform3D, speed: float, struck: PackedVector3Array) -> bool:
	var crush := c.near(xf, struck, PANCAKE_LAYER) if not struck.is_empty() else PackedInt32Array()
	if crush.is_empty():
		crush = c.bottom(xf, PANCAKE_LAYER)  # positions in c.members
	if crush.is_empty() or c.members.size() - crush.size() < PANCAKE_MIN / 2:
		return false
	var hit := Vector3.ZERO
	for k in crush:
		hit += xf * c.offsets[k].origin
	hit /= crush.size()
	var v: Vector3 = PhysicsServer3D.body_get_state(c.body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	_set.floor_crushed.emit(hit, crush.size(), speed)
	_set.cluster_impact.emit(hit, c.mass * crush.size() / c.members.size(), speed, crush.size())
	if _set.debris:
		_set.debris.thaw_near(hit, 3.0)
	_strike(struck if not struck.is_empty() else PackedVector3Array([hit]), 1.5, speed * 0.3 * _heft(c))
	var keep := _fair_share(crush.size())
	for i in _take_out(c, crush, xf):
		if randf() < 0.65:
			_set._shatter(i, hit, speed * 0.25, v * 0.2, false, keep)
		else:
			var kick := v * 0.25 + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
			_set._dislodge(i, kick, Vector3.ZERO, 0.0, keep)
	_regroup(c)
	PhysicsServer3D.body_set_state(c.body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, v * PANCAKE_KEEP)
	PhysicsServer3D.body_set_state(c.body, PhysicsServer3D.BODY_STATE_SLEEPING, false)
	c.recent = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	c.prev_velocity = v * PANCAKE_KEEP
	c.age = 0.05
	return true


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
				_set.debris.despawn(piece)
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
		elif over > 1.0:
			_set._shatter(key, where[key], 2.0)  # a little: it cracks open there
			gave += 1
	if gave > 0:
		# It sinks into the room it just made: keep it awake and falling.
		PhysicsServer3D.body_set_state(c.body, PhysicsServer3D.BODY_STATE_SLEEPING, false)
		c.age = maxf(c.age - PRESS_TICK, 0.35)


## A falling piece hit something: damage what it struck, then break it up.
## `push` is the velocity it had just before the hit (the direction it was
## going: after the hit it may be stopped or bouncing back).
func _impact(c: FallingCluster, xf: Transform3D, speed: float, push: Vector3, spin: Vector3) -> void:
	var spots := c.struck_points(xf, push, spin)
	if c.members.size() >= PANCAKE_MIN and _pancake(c, xf, speed, spots):
		return
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
	_set.cluster_impact.emit(hit, c.mass, speed, c.members.size())
	if _set.debris:
		_set.debris.thaw_near(hit, 3.0)
	# Heavy pieces hit harder: chain reactions and dominoes.
	var reach := clampf(0.8 + c.members.size() * 0.02, 1.0, 2.5)
	spots.append(hit)
	_strike(spots, reach, speed * 0.35 * _heft(c))
	dissolve(c, hit, speed)
	if struck >= 0 and _set._state[struck] == StructureSet.State.STATIC:
		_knock(struck, push, c.mass * speed, hit)


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
