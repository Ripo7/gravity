class_name FallingCluster
extends RefCounted
## A falling piece of a structure: one rigid body with a box per block.
## StructureSet owns the blocks; this is their shared body while they fall.
## Its blocks are grouped in chunks along ragged lines (see carve): where it
## will crack, chunk by chunk, as it falls and lands (see Falls).

var body: RID
var members := PackedInt32Array()
var offsets: Array[Transform3D] = []  # block transform in body space
var masses := PackedFloat32Array()  # of each member
var chunk := PackedInt32Array()  # chunk of each member (see carve)
var mass := 0.0
var gravity_scale := 1.0
var age := 0.0
var prev_velocity := Vector3.ZERO
var prev_spin := Vector3.ZERO
var recent := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])  # last speeds
var toppled := false  # pivoting over its base: falls toward the cut side
var lean_time := 0.0  # seconds resting against a standing structure
var leaned := false
var crush_tick := 0.0
var press_tick := 0.0
var slow_time := 0.0  # seconds it has crept along (see Falls.SETTLE_TIME)
var crawl_time := 0.0  # seconds it has crawled since it landed (Falls.CRAWL_TIME)
var landed := false  # it hit something hard already
var turned_at := 0.0  # how far it had turned when it last cracked across (rad)
var peel_tick := 0.0
var crumbling := false  # come to rest: it falls apart chunk by chunk
var crumble_order := PackedInt32Array()  # its chunks, the highest last
var crumble_look := 0.0  # seconds until it looks again at what is on top
## Chunks the shock of a landing will break off: {"time", "chunk", "from", "kick"}.
var waves: Array[Dictionary] = []
## Its boxes, drawn in its body space (see Falls.draw), and the positions
## (in members) of its other blocks, drawn one by one; laid out again
## whenever it loses blocks.
var mesh: MultiMeshInstance3D
var others := PackedInt32Array()
var dressed := false

var _index := {}  # block -> position in members
var _index_ok := false
var _extent := -1.0


## One rigid body for `blocks`, each where `xforms` says (world), of mass
## `block_masses` and shape `shapes` (boxes), in `space`. The body's origin
## is their centre of mass; `gravity_scale` < 1 makes it fall slower.
static func build(
	blocks: PackedInt32Array,
	xforms: Array[Transform3D],
	block_masses: PackedFloat32Array,
	shapes: Array[RID],
	space: RID,
	gravity := 1.0
) -> FallingCluster:
	var c := FallingCluster.new()
	c.gravity_scale = gravity
	var com := Vector3.ZERO
	for k in blocks.size():
		com += xforms[k].origin * block_masses[k]
		c.mass += block_masses[k]
	com /= c.mass
	var body_xf := Transform3D(Basis(), com)
	var inv := body_xf.affine_inverse()
	c.body = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(c.body, PhysicsServer3D.BODY_MODE_RIGID)
	for k in blocks.size():
		var off := inv * xforms[k]
		PhysicsServer3D.body_add_shape(c.body, shapes[k], off)
		c.members.append(blocks[k])
		c.offsets.append(off)
		c.masses.append(block_masses[k])
	PhysicsServer3D.body_set_param(c.body, PhysicsServer3D.BODY_PARAM_MASS, c.mass)
	if gravity != 1.0:
		PhysicsServer3D.body_set_param(c.body, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, gravity)
	# A big piece touches a lot at once (its foot in rubble, its side on a
	# wall): it needs to hear about all of it to bear down where it leans.
	PhysicsServer3D.body_set_max_contacts_reported(c.body, 24 if blocks.size() < 30 else 96)
	PhysicsServer3D.body_set_param(c.body, PhysicsServer3D.BODY_PARAM_FRICTION, 0.8)
	PhysicsServer3D.body_set_collision_layer(c.body, DebrisSystem.LAYER_DEBRIS)
	PhysicsServer3D.body_set_collision_mask(
		c.body,
		(
			DebrisSystem.LAYER_WORLD
			| DebrisSystem.LAYER_STRUCTURES
			| DebrisSystem.LAYER_DEBRIS
			| DebrisSystem.LAYER_PLAYER
		)
	)
	PhysicsServer3D.body_set_space(c.body, space)
	PhysicsServer3D.body_set_state(c.body, PhysicsServer3D.BODY_STATE_TRANSFORM, body_xf)
	return c


func transform() -> Transform3D:
	return PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM)


## Takes the members at positions `ks` out of the body. Returns those
## blocks and appends to `where` where each one is now (body at `xf`).
func take_out(ks: PackedInt32Array, xf: Transform3D, where: Array[Transform3D]) -> PackedInt32Array:
	var out := PackedInt32Array()
	var order := ks.duplicate()
	order.sort()
	order.reverse()  # from the end, so the remaining shape indices stay valid
	# Out of the space while it changes: in it, Jolt rebuilds the whole
	# shape after every single removal (a tower losing half its stones).
	var space := PhysicsServer3D.body_get_space(body)
	if order.size() > 2:
		PhysicsServer3D.body_set_space(body, RID())
	for k in order:
		out.append(members[k])
		where.append(xf * offsets[k])
		PhysicsServer3D.body_remove_shape(body, k)
		members.remove_at(k)
		offsets.remove_at(k)
		mass -= masses[k]
		masses.remove_at(k)
		if k < chunk.size():
			chunk.remove_at(k)
	if order.size() > 2:
		PhysicsServer3D.body_set_space(body, space)
	_index_ok = false
	_extent = -1.0
	dressed = false
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_MASS, maxf(mass, 1.0))
	return out


## Block -> its position in members.
func index() -> Dictionary:
	if not _index_ok:
		_index.clear()
		for k in members.size():
			_index[members[k]] = k
		_index_ok = true
	return _index


## How far its farthest block centre is from the body's origin (m).
func extent() -> float:
	if _extent < 0.0:
		_extent = 0.0
		for off in offsets:
			_extent = maxf(_extent, off.origin.length())
	return _extent


## Cuts it into chunks of about `per_chunk` blocks along ragged lines: seeds
## spread over it (one in each cell of a grid laid at random over it, sized
## so there are about as many cells with blocks as chunks wanted), then a
## random flood through the blocks from all of them at once (a Voronoi of
## its blocks with torn edges). At least two chunks from 6 blocks on.
## Linked by `neighbors` (block -> blocks it touches).
func carve(neighbors: Array[PackedInt32Array], per_chunk: int) -> void:
	var n := members.size()
	chunk.resize(n)
	var count := roundi(float(n) / maxf(per_chunk, 1))
	count = mini(maxi(count, 2 if n >= 6 else 1), n)
	if count <= 1:
		chunk.fill(0)
		return
	chunk.fill(-1)
	var seeds := _spread(count)
	var at := index()
	var frontier := PackedInt32Array()
	for q in seeds.size():
		chunk[seeds[q]] = q
		frontier.append(seeds[q])
	while not frontier.is_empty():
		var f := randi() % frontier.size()
		var k := frontier[f]
		frontier[f] = frontier[frontier.size() - 1]
		frontier.remove_at(frontier.size() - 1)
		for nb in neighbors[members[k]]:
			var kn: int = at.get(nb, -1)
			if kn >= 0 and chunk[kn] < 0:
				chunk[kn] = chunk[k]
				frontier.append(kn)
	var next := seeds.size()
	for k in n:
		if chunk[k] < 0:  # cut off from the seeds: a chunk of its own
			chunk[k] = next
			next += 1


## About `count` members spread over it: a random one in each cell of a grid
## with a random offset, the cell grown or shrunk until about `count` cells
## hold blocks.
func _spread(count: int) -> PackedInt32Array:
	var n := members.size()
	var box := AABB(offsets[0].origin, Vector3.ZERO)
	for off in offsets:
		box = box.expand(off.origin)
	var cell := maxf(box.size[box.size.max_axis_index()] / pow(count, 1.0 / 3.0), 0.3)
	var shift := Vector3(randf(), randf(), randf())
	var picks := {}
	for _attempt in 6:
		picks.clear()
		for k in n:
			var key := Vector3i(((offsets[k].origin - box.position) / cell + shift).floor())
			# Reservoir pick: each block of the cell is as likely to seed it.
			var seen: Vector2i = picks.get(key, Vector2i(-1, 0))
			seen.y += 1
			if randi() % seen.y == 0:
				seen.x = k
			picks[key] = seen
		if picks.size() > count * 1.4:
			cell *= 1.25
		elif picks.size() < count * 0.7 and cell > 0.3:
			cell /= 1.25
		else:
			break
	var out := PackedInt32Array()
	for v: Vector2i in picks.values():
		out.append(v.x)
	return out


## Positions (in members) of the blocks of chunk `q`.
func chunk_members(q: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for k in chunk.size():
		if chunk[k] == q:
			out.append(k)
	return out


## Its chunks, each once.
func chunk_ids() -> PackedInt32Array:
	var seen := {}
	for q in chunk:
		seen[q] = true
	return PackedInt32Array(seen.keys())


## Of the positions `ks`, those of blocks touching a block of the piece that
## is not in `ks`: the rim along which they come away.
func rim(ks: PackedInt32Array, neighbors: Array[PackedInt32Array]) -> PackedInt32Array:
	var inside := {}
	for k in ks:
		inside[k] = true
	var at := index()
	var out := PackedInt32Array()
	for k in ks:
		for nb in neighbors[members[k]]:
			var kn: int = at.get(nb, -1)
			if kn >= 0 and not inside.has(kn):
				out.append(k)
				break
	return out


## Up to `count` blocks sticking out of it (touching at most two of its
## other blocks), picked at random: the stones that come off as it tumbles.
func loose(neighbors: Array[PackedInt32Array], count: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var at := index()
	var n := members.size()
	for _attempt in count * 4:
		if out.size() >= count:
			break
		var k := randi() % n
		if out.has(k):
			continue
		var held := 0
		for nb in neighbors[members[k]]:
			if at.has(nb):
				held += 1
		if held <= 2:
			out.append(k)
	return out


## Where a tall piece cracks across once it turns: the blocks of the chunks
## beyond a ragged line a third to half way along it from its lower end
## (bending is worst near the foot). Empty unless it is at least `tall`
## times as long as it is wide. At `xf`.
func crack_line(xf: Transform3D, tall: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var box := AABB(offsets[0].origin, Vector3.ZERO)
	for off in offsets:
		box = box.expand(off.origin)
	var axis := box.size.max_axis_index()
	var length := box.size[axis] + 1.0
	var width := 1.0
	for a in 3:
		if a != axis:
			width = maxf(width, box.size[a] + 1.0)
	if length < width * tall:
		return out
	var dir := Vector3.ZERO
	dir[axis] = 1.0
	# Its lower end, in the world, is the foot.
	var up := (xf.basis * dir).y >= 0.0
	var foot := box.position[axis] if up else box.end[axis]
	var cut := box.size[axis] * randf_range(0.3, 0.55)
	var sums := {}
	var counts := {}
	for k in offsets.size():
		var along := absf(offsets[k].origin[axis] - foot)
		sums[chunk[k]] = sums.get(chunk[k], 0.0) + along
		counts[chunk[k]] = counts.get(chunk[k], 0) + 1
	for k in offsets.size():
		if sums[chunk[k]] / counts[chunk[k]] > cut:
			out.append(k)
	if out.size() < 3 or out.size() > offsets.size() - 3:
		out.clear()
	return out


## Which connected piece each member belongs to, members being linked by
## `neighbors` (block -> blocks it touches): 0 is the biggest piece.
func parts(neighbors: Array[PackedInt32Array]) -> PackedInt32Array:
	var n := members.size()
	var at := index()
	var part := PackedInt32Array()
	part.resize(n)
	part.fill(-1)
	var sizes := PackedInt32Array()
	for first in n:
		if part[first] >= 0:
			continue
		var p := sizes.size()
		sizes.append(0)
		part[first] = p
		var stack := PackedInt32Array([first])
		while not stack.is_empty():
			var k := stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			sizes[p] += 1
			for nb in neighbors[members[k]]:
				var kn: int = at.get(nb, -1)
				if kn >= 0 and part[kn] < 0:
					part[kn] = p
					stack.append(kn)
	var biggest := 0
	for p in sizes.size():
		if sizes[p] > sizes[biggest]:
			biggest = p
	if biggest != 0:
		for k in n:
			part[k] = 0 if part[k] == biggest else (biggest if part[k] == 0 else part[k])
	return part


## Records this step's velocity `v` and spin `w`. Returns the speed just
## lost (x) and the fastest recent speed (y): contacts can spread a landing
## over a few steps.
func track(v: Vector3, w: Vector3) -> Vector2:
	var dv := (prev_velocity - v).length()
	prev_velocity = v
	prev_spin = w
	var peak := 0.0
	for sp in recent:
		peak = maxf(peak, sp)
	recent.remove_at(0)
	recent.append(v.length())
	return Vector2(maxf(dv, peak - v.length()), peak)


## Positions (in members) of the blocks whose centre is less than `depth`
## above the lowest one, the piece being at `xf`.
func bottom(xf: Transform3D, depth: float) -> PackedInt32Array:
	var low := lowest_point(xf).y
	var out := PackedInt32Array()
	for k in offsets.size():
		if (xf * offsets[k].origin).y < low + depth:
			out.append(k)
	return out


## Positions (in members) of the blocks whose centre is within `reach` of
## one of `points`, the piece being at `xf`.
func near(xf: Transform3D, points: PackedVector3Array, reach: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	for k in offsets.size():
		var p := xf * offsets[k].origin
		for q in points:
			if p.distance_squared_to(q) < reach * reach:
				out.append(k)
				break
	return out


## Where it struck: the contact points (world) that were coming at what they
## touch fastest, moving at `v` and spinning at `w` just before (a toppling
## tower hits with its top, not with the foot it pivots on).
func struck_points(xf: Transform3D, v: Vector3, w: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	var state := PhysicsServer3D.body_get_direct_state(body)
	if state == null:
		return out
	var speeds := PackedFloat32Array()
	var fastest := 0.0
	for k in state.get_contact_count():
		var p := state.get_contact_local_position(k)
		speeds.append((v + w.cross(p - xf.origin)).length())
		fastest = maxf(fastest, speeds[k])
	for k in speeds.size():
		if speeds[k] >= fastest * 0.5:
			out.append(state.get_contact_local_position(k))
	return out


## The faster of its velocity now and a step ago (what it hit stopped it).
func hit_velocity() -> Vector3:
	var v: Vector3 = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	return prev_velocity if prev_velocity.length_squared() > v.length_squared() else v


## True when the piece touches the ground, a structure, another falling
## piece or a pile of rubble; flying debris bumping into it does not count
## as a landing.
func touches_solid(debris: DebrisSystem) -> bool:
	var state := PhysicsServer3D.body_get_direct_state(body)
	if state == null:
		return true
	for k in state.get_contact_count():
		var j := debris.index_of(state.get_contact_collider(k)) if debris else -1
		if j < 0 or debris.is_resting(j):
			return true
	return false


## Bounds of the block centres at `xf`, grown by 1 m.
func bounds(xf: Transform3D) -> AABB:
	var box := AABB((xf * offsets[0]).origin, Vector3.ZERO)
	for off in offsets:
		box = box.expand((xf * off).origin)
	return box.grow(1.0)


func lowest_point(xf: Transform3D) -> Vector3:
	var best := Vector3(0, INF, 0)
	for off in offsets:
		var p := xf * off.origin
		if p.y < best.y:
			best = p
	return best


## World position of the block centre nearest to `p`.
func nearest_point(p: Vector3) -> Vector3:
	var xf := transform()
	var best := Vector3.INF
	var best_d := INF
	for off in offsets:
		var q := xf * off.origin
		var d := q.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = q
	return best
