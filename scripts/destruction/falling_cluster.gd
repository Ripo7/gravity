class_name FallingCluster
extends RefCounted
## A falling piece of a structure: one rigid body with a box per block.
## StructureSet owns the blocks; this is their shared body while they fall.

var body: RID
var members := PackedInt32Array()
var offsets: Array[Transform3D] = []  # block transform in body space
var masses := PackedFloat32Array()  # of each member
var mass := 0.0
var age := 0.0
var prev_velocity := Vector3.ZERO
var prev_spin := Vector3.ZERO
var recent := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])  # last speeds
var toppled := false  # pivoting over its base: falls toward the cut side
var lean_time := 0.0  # seconds resting against a standing structure
var leaned := false
var crush_tick := 0.0
var press_tick := 0.0
var slow_time := 0.0  # seconds it has crept along (see StructureSet.SETTLE_TIME)
var whole := true  # false once it broke across its height (see sections)


## One rigid body for `blocks`, each where `xforms` says (world), of mass
## `block_masses` and shape `shapes` (boxes), in `space`. The body's origin
## is their centre of mass; `gravity_scale` < 1 makes it fall slower.
static func build(
	blocks: PackedInt32Array,
	xforms: Array[Transform3D],
	block_masses: PackedFloat32Array,
	shapes: Array[RID],
	space: RID,
	gravity_scale := 1.0
) -> FallingCluster:
	var c := FallingCluster.new()
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
	if gravity_scale != 1.0:
		PhysicsServer3D.body_set_param(c.body, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, gravity_scale)
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
	for k in order:
		out.append(members[k])
		where.append(xf * offsets[k])
		PhysicsServer3D.body_remove_shape(body, k)
		members.remove_at(k)
		offsets.remove_at(k)
		mass -= masses[k]
		masses.remove_at(k)
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_MASS, maxf(mass, 1.0))
	return out


## Which connected piece each member belongs to, members being linked by
## `neighbors` (block -> blocks it touches): 0 is the biggest piece.
func parts(neighbors: Array[PackedInt32Array]) -> PackedInt32Array:
	var n := members.size()
	var at := {}
	for k in n:
		at[members[k]] = k
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


## How a tall piece (a tower) breaks across its height once it has tipped
## more than `tilt` (radians): a section number per member, 0 being its
## foot, each section about `ratio` times as long as the piece is wide.
## Empty when it is not at least `tall` times as long as it is wide, or not
## tipped that far yet. Masonry does not bend: it snaps.
func sections(xf: Transform3D, tilt: float, tall: float, ratio: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	if not whole or xf.basis.y.angle_to(Vector3.UP) < tilt:
		return out
	var box := AABB(offsets[0].origin, Vector3.ZERO)
	for off in offsets:
		box = box.expand(off.origin)
	var width := maxf(box.size.x, box.size.z) + 1.0
	if box.size.y + 1.0 < width * tall:
		whole = false  # never will
		return out
	whole = false
	var count := clampi(roundi((box.size.y + 1.0) / (width * ratio)), 2, 4)
	var shift := randf_range(-0.2, 0.2)
	out.resize(offsets.size())
	for k in offsets.size():
		var along := (offsets[k].origin.y - box.position.y) / maxf(box.size.y, 0.01)
		out[k] = clampi(int(along * count + shift), 0, count - 1)
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
