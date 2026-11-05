class_name StructureSet
extends Node3D
## Every building block ("segment") of every structure, and how they hold up.
##
## Segments start STATIC: immovable PhysicsServer3D bodies drawn by one
## MultiMesh. Each has health (damage shows as cracks) and a load capacity.
## After anything changes, a structure is re-checked (`settle`):
##   - Blocks are grouped into connected pieces. A piece with no contact to
##     the ground falls as one rigid body (a FALLING cluster).
##   - A grounded piece whose centre of mass leaves its footprint topples:
##     it also becomes a cluster and tips over.
##   - Loads flow top-down from each block to the blocks it rests on. A
##     block carrying more than its capacity is crushed, which moves its load
##     onto its neighbours, so collapses spread floor by floor.
## A falling cluster breaks apart on impact: blocks near the hit shatter,
## the rest tumble as loose debris, and whatever it hits takes damage.

signal segment_broken(index: int)
signal shattered(at: Vector3, size: Vector3, kind: int)
signal cluster_released(at: Vector3, count: int, toppled: bool)
signal cluster_impact(at: Vector3, mass: float, speed: float, count: int)
## A big piece of building is about to give way (it creaks first).
signal about_to_fail(at: Vector3, count: int)
## A falling floor crushed the one below it and keeps going.
signal floor_crushed(at: Vector3, count: int, speed: float)
signal destruction_changed(fraction: float)

enum State { GONE, STATIC, FALLING }

const FLOATS_PER_INSTANCE := 20  # 12 transform + 4 colour + 4 custom
const CONTACT_EPS := 0.03
const GROUND_EPS := 0.03
const GRID_CELL := 2.0
## Intact structures carry at most 1/SAFETY of each block's capacity.
const SAFETY := {
	Materials.Kind.CONCRETE: 2.4,
	Materials.Kind.WOOD: 2.0,
	Materials.Kind.METAL: 3.0,
	Materials.Kind.ICE: 2.0,
	Materials.Kind.GLASS: 2.0,
}
## A block held only from the side carries at most this many times its weight.
const SHEAR_WEIGHTS := {
	Materials.Kind.CONCRETE: 5.0,
	Materials.Kind.WOOD: 7.0,
	Materials.Kind.METAL: 14.0,
	Materials.Kind.ICE: 5.0,
	Materials.Kind.GLASS: 2.0,
}
const MAX_CRUSH_PER_FRAME := 8
const MAX_CLUSTERS := 12
const IMPACT_DV := 3.5  ## m/s change in one step that counts as a hit
const IMPACT_MIN_SPEED := 4.5  ## m/s; slower contacts are just settling
const CLUSTER_MAX_AGE := 9.0
## Big falling pieces of building feel heavier: they fall a bit slower.
const CLUSTER_GRAVITY := 0.72
## Components this big creak and hesitate before they give way.
const HESITATE_MIN := 24
const HESITATE_TIME := Vector2(0.35, 0.7)  ## seconds, small -> big
## A falling block of at least this many pieces crushes its lowest storey on
## each hard landing and keeps falling, instead of bursting all at once.
const PANCAKE_MIN := 30
const PANCAKE_LAYER := 1.6  ## metres crushed per landing
const PANCAKE_KEEP := 0.3  ## share of speed kept after crushing a layer
## A falling piece knocks a standing one over when its momentum exceeds the
## standing piece's mass times this (m/s).
const KNOCK_SPEED := 0.9
const LEAN_TIME := 0.2  ## seconds of leaning before the weight tells
const LEAN_SPEED := 2.0  ## leaning counts like an impact at this speed

@export var debris: DebrisSystem
@export var material: Material

var dust: DustSystem  ## optional: gravel and dust when rubble is crushed
var rebar: RebarSystem  ## optional: steel rods left in broken concrete
var alive_count := 0
var scored_total := 0.0
var scored_destroyed := 0.0

var _state := PackedByteArray()
var _xform: Array[Transform3D] = []  # global rest transform
var _local: Array[AABB] = []  # in the structure's own space
var _size := PackedVector3Array()
var _kind := PackedByteArray()
var _seed := PackedFloat32Array()
var _shade := PackedFloat32Array()
var _health := PackedFloat32Array()
var _max_health := PackedFloat32Array()
var _mass := PackedFloat32Array()
var _capacity := PackedFloat32Array()
var _load := PackedFloat32Array()
var _score := PackedFloat32Array()  # volume counted toward the level score
var _group := PackedInt32Array()
var _grounded := PackedByteArray()
var _neighbors: Array[PackedInt32Array] = []
var _supporters: Array[PackedInt32Array] = []  # blocks directly below
var _support_area: Array[PackedFloat32Array] = []
var _groups: Array[PackedInt32Array] = []
var _group_origin: Array[Transform3D] = []
var _bodies: Array[RID] = []
var _shape_cache := {}
var _rid_to_seg := {}
var _grid := {}
var _dirty_groups := {}
var _tip := Vector2.ZERO  # last tipping direction (structure space)
var _clusters: Array[Cluster] = []
var _pending: Array[Dictionary] = []  # {comp, toppled, time, group}
## Structures standing on other structures (a water tower on a roof):
## block -> blocks of other structures it rests on, and the reverse.
var _anchors := {}
var _power_tint := 0.0  ## violet glow for pieces broken right now
var _hit := PackedVector3Array()  ## where each block was hit (unit space + 1)
var _anchored_by := {}
var _multimesh: MultiMesh
var _buffer := PackedFloat32Array()
var _buffer_dirty := false
var _score_dirty := false


## A falling piece of a structure: one rigid body with a box per block.
class Cluster:
	extends RefCounted
	var body: RID
	var members := PackedInt32Array()
	var offsets: Array[Transform3D] = []  # block transform in body space
	var mass := 0.0
	var age := 0.0
	var prev_velocity := Vector3.ZERO
	var recent := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])  # last speeds
	var toppled := false  # pivoting over its base: falls toward the cut side
	var lean_time := 0.0  # seconds resting against a standing structure
	var leaned := false
	var crush_tick := 0.0


func _exit_tree() -> void:
	for c in _clusters:
		PhysicsServer3D.free_rid(c.body)
	_clusters.clear()
	for rid in _bodies:
		PhysicsServer3D.free_rid(rid)
	for rid: RID in _shape_cache.values():
		PhysicsServer3D.free_rid(rid)
	_bodies.clear()
	_shape_cache.clear()


# --- Building ----------------------------------------------------------------


## `segments`: Array of {"local": Transform3D, "size": Vector3, "strength",
## "material", "shade", "seed"}; `origin` is the structure's transform.
## `scored`: whether these blocks count toward the level's destruction score.
func add_structure(origin: Transform3D, segments: Array[Dictionary], scored := true) -> int:
	var group_id := _groups.size()
	var members := PackedInt32Array()
	var space := get_world_3d().space
	for seg in segments:
		var i := _xform.size()
		var local: Transform3D = seg["local"]
		var size: Vector3 = seg["size"]
		var global := origin * local
		var kind: int = seg.get("material", Materials.Kind.CONCRETE)
		var volume := size.x * size.y * size.z
		_state.append(State.STATIC)
		_xform.append(global)
		# Bounds in structure space (segments may be tilted, e.g. ramps).
		_local.append(local * AABB(-size * 0.5, size))
		_size.append(size)
		_kind.append(kind)
		_seed.append(seg.get("seed", randf()))
		_shade.append(seg.get("shade", 1.0))
		_hit.append(Vector3.ZERO)
		var hp: float = seg.get("strength", 3.0) * Materials.prop(kind, "strength")
		_health.append(hp)
		_max_health.append(hp)
		_mass.append(volume * Materials.prop(kind, "density"))
		_capacity.append(0.0)
		_load.append(0.0)
		_score.append(volume if scored else 0.0)
		_group.append(group_id)
		_grounded.append(1 if _local[i].position.y <= GROUND_EPS else 0)
		_neighbors.append(PackedInt32Array())
		_supporters.append(PackedInt32Array())
		_support_area.append(PackedFloat32Array())
		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_add_shape(body, _box_shape(size))
		PhysicsServer3D.body_set_collision_layer(body, DebrisSystem.LAYER_STRUCTURES)
		PhysicsServer3D.body_set_collision_mask(body, 0)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, global)
		PhysicsServer3D.body_set_space(body, space)
		_bodies.append(body)
		_rid_to_seg[body] = i
		_grid_insert(i)
		members.append(i)
		alive_count += 1
		if scored:
			scored_total += volume
	_groups.append(members)
	_group_origin.append(origin)
	_link(members)
	# Calibrate capacities on the intact structure so it always stands.
	_compute_loads(members)
	for k in members.size():
		var i := members[k]
		var floor_cap := _mass[i] * 3.0
		var robust: float = segments[k].get("robust", 1.0)
		_capacity[i] = maxf(_load[i] * SAFETY[_kind[i]] * robust, floor_cap)
	_rebuild_multimesh()
	return group_id


## Call once every structure is in: a structure whose base is not on the
## ground (a water tower on a roof) is tied to the blocks it stands on, so
## it falls when they go.
func link_anchors() -> void:
	for i in _xform.size():
		if not _grounded[i] or _state[i] != State.STATIC:
			continue
		var bottom := _world_bottom(i)
		if bottom <= GROUND_EPS:
			continue
		var under := PackedInt32Array()
		var probe := Vector3(_xform[i].origin.x, bottom, _xform[i].origin.z)
		for j in _query(probe, _size[i].length() * 0.5 + 0.5):
			if _group[j] == _group[i]:
				continue
			var top := _xform[j].origin.y + (_world_bottom(j) - _xform[j].origin.y) * -1.0
			if absf(top - bottom) < 0.08:
				under.append(j)
				if not _anchored_by.has(j):
					_anchored_by[j] = PackedInt32Array()
				_anchored_by[j].append(i)
		if not under.is_empty():
			_anchors[i] = under


## Block `i` broke away: the concrete blocks it was joined to keep bent
## steel rods sticking out where it was.
func _leave_rebar(i: int) -> void:
	if rebar == null:
		return
	var origin := _group_origin[_group[i]]
	var mine := _local[i].grow(CONTACT_EPS)
	for n in _neighbors[i]:
		if _state[n] != State.STATIC or _kind[n] != Materials.Kind.CONCRETE:
			continue
		var touch := mine.intersection(_local[n].grow(CONTACT_EPS))
		if not touch.has_volume():
			continue
		var thin := touch.size.min_axis_index()
		var normal := Vector3.ZERO
		normal[thin] = signf(_local[i].get_center()[thin] - _local[n].get_center()[thin])
		var a := Vector3.ZERO
		var b := Vector3.ZERO
		a[(thin + 1) % 3] = touch.size[(thin + 1) % 3] * 0.45
		b[(thin + 2) % 3] = touch.size[(thin + 2) % 3] * 0.45
		var area := touch.size[(thin + 1) % 3] * touch.size[(thin + 2) % 3]
		if area < 0.05:
			continue
		var count := clampi(int(area * 2.5), 1, 4)
		rebar.sprout(
			n,
			origin * touch.get_center(),
			origin.basis * a,
			origin.basis * b,
			(origin.basis * normal).normalized(),
			count
		)


## Block `i` no longer stands: whatever stood on it from another structure
## loses its footing if nothing else holds it.
func _unanchor(i: int) -> void:
	if rebar:
		rebar.drop_owner(i)
	for b: int in _anchored_by.get(i, []):
		if not _grounded[b]:
			continue
		var still := false
		for a: int in _anchors[b]:
			if _state[a] == State.STATIC:
				still = true
				break
		if not still:
			_grounded[b] = 0
			_dirty_groups[_group[b]] = true


func _world_bottom(i: int) -> float:
	var b := _xform[i].basis
	var h := _size[i] * 0.5
	var extent := absf(b.x.y) * h.x + absf(b.y.y) * h.y + absf(b.z.y) * h.z
	return _xform[i].origin.y - extent


## Contact graph and "rests on" links inside one structure.
func _link(members: PackedInt32Array) -> void:
	for a in members:
		var grown := _local[a].grow(CONTACT_EPS)
		for b in members:
			if a >= b or not grown.intersects(_local[b]):
				continue
			_neighbors[a].append(b)
			_neighbors[b].append(a)
			var la := _local[a]
			var lb := _local[b]
			var ox := minf(la.end.x, lb.end.x) - maxf(la.position.x, lb.position.x)
			var oz := minf(la.end.z, lb.end.z) - maxf(la.position.z, lb.position.z)
			if ox <= 0.01 or oz <= 0.01:
				continue
			var area := ox * oz
			if absf(la.end.y - lb.position.y) < CONTACT_EPS:
				_supporters[b].append(a)
				_support_area[b].append(area)
			elif absf(lb.end.y - la.position.y) < CONTACT_EPS:
				_supporters[a].append(b)
				_support_area[a].append(area)


# --- Queries -------------------------------------------------------------------


func segment_count() -> int:
	return _xform.size()


func is_alive(i: int) -> bool:
	return _state[i] == State.STATIC


func is_falling(i: int) -> bool:
	return _state[i] == State.FALLING


func transform_of(i: int) -> Transform3D:
	return _xform[i]


func kind_of(i: int) -> int:
	return _kind[i]


func size_of(i: int) -> Vector3:
	return _size[i]


func health_of(i: int) -> float:
	return _health[i]


func load_of(i: int) -> float:
	return _load[i]


func capacity_of(i: int) -> float:
	return _capacity[i]


func cluster_count() -> int:
	return _clusters.size()


## {mass, velocity} of the falling piece whose body is `rid`, or empty.
func cluster_motion(rid: RID) -> Dictionary:
	for c in _clusters:
		if c.body == rid:
			var v: Vector3 = PhysicsServer3D.body_get_state(
				c.body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY
			)
			return {"mass": c.mass, "velocity": v}
	return {}


## Share of scored volume that is no longer standing (0..1).
func destruction() -> float:
	return scored_destroyed / scored_total if scored_total > 0.0 else 0.0


# --- Damage --------------------------------------------------------------------


## Damages every block within the blast. Returns how many broke or came loose.
## Damage over `dt` seconds from a field: `dps_inside` within `inner` of
## `center`, `dps_band` from there out to `outer`. Returns blocks broken.
func apply_field(
	center: Vector3, inner: float, outer: float, dps_inside: float, dps_band: float, dt: float
) -> int:
	var hits := 0
	_power_tint = 1.0  # what the black hole breaks glows violet
	for i in _query(center, outer):
		var d := _surface_distance(i, center)
		var dps := dps_inside if d < inner else (dps_band if d < outer else 0.0)
		if dps <= 0.0:
			continue
		var before := _state[i]
		_damage(i, dps * dt, center)
		if _state[i] != before:
			hits += 1
	_power_tint = 0.0
	return hits


## Tears falling pieces within `radius` apart so their blocks can be caught.
func tear_clusters(center: Vector3, radius: float) -> void:
	for c: Cluster in _clusters.duplicate():
		if _cluster_distance(c, center) < radius:
			_dissolve(c, center, 0.0)


func _cluster_distance(c: Cluster, p: Vector3) -> float:
	var xf: Transform3D = PhysicsServer3D.body_get_state(c.body, PhysicsServer3D.BODY_STATE_TRANSFORM)
	var best := INF
	for off in c.offsets:
		best = minf(best, (xf * off.origin).distance_to(p))
	return best


## Damage at a point, e.g. from a heavy impact.
func apply_impact(center: Vector3, radius: float, damage: float) -> void:
	for i in _query(center, radius):
		var f := 1.0 - clampf(_surface_distance(i, center) / radius, 0.0, 1.0)
		if f > 0.0:
			_damage(i, damage * f, center)


## Deletes a block without leaving debris (editor tools and tests).
func remove_segment(i: int) -> void:
	if _state[i] == State.STATIC:
		_remove(i)


func break_segment(i: int) -> void:
	if _state[i] == State.STATIC:
		_shatter(i, _xform[i].origin + Vector3.UP, 0.0)


func _damage(i: int, dmg: float, from: Vector3) -> void:
	if _state[i] != State.STATIC:
		return
	if _hit[i] == Vector3.ZERO:
		# Cracks will spread from where it was first hit.
		var local := _xform[i].affine_inverse() * from
		var unit := (local / _size[i]).clamp(-Vector3.ONE * 0.5, Vector3.ONE * 0.5)
		_hit[i] = unit + Vector3.ONE
	_health[i] -= dmg
	if _health[i] <= 0.0:
		_shatter(i, from, dmg)
		return
	# A strong hit on a lightly loaded block knocks it loose whole.
	var light := _load[i] < _mass[i] * 3.0
	if light and dmg >= _max_health[i] * Materials.prop(_kind[i], "dislodge"):
		var away := (_xform[i].origin - from).normalized()
		_dislodge(i, away * minf(dmg, 8.0) * 0.8 * Materials.prop(_kind[i], "blast_response"))
		return
	_write_instance(i, _xform[i])
	_dirty_groups[_group[i]] = true  # weaker block: loads may now exceed it


func _surface_distance(i: int, p: Vector3) -> float:
	var local := _xform[i].affine_inverse() * p
	var half := _size[i] * 0.5
	return local.clamp(-half, half).distance_to(local)


func _shatter(i: int, from: Vector3, dmg: float, inherit := Vector3.ZERO) -> void:
	var xf := _current_transform(i)
	var size := _size[i]
	var kind := _kind[i]
	_remove(i)
	shattered.emit(xf.origin, size, kind)
	if kind == Materials.Kind.CONCRETE:
		_leave_rebar(i)
	# Glass bursts into shards (chips, see the shattered signal): no bodies.
	if debris == null or kind == Materials.Kind.GLASS:
		return
	debris.shatter_box(
		xf, size, kind, from, minf(dmg, 6.0) * 0.4, inherit, _power_tint, _shade[i], _seed[i], i
	)


func _dislodge(i: int, velocity: Vector3, spin := Vector3.ZERO, tint := 0.5) -> void:
	if _kind[i] == Materials.Kind.GLASS:
		_shatter(i, _xform[i].origin + velocity, 0.0)
		return
	var xf := _current_transform(i)
	_remove(i)
	if debris:
		debris.spawn(xf, _size[i] * 0.995, velocity, spin, tint, _shade[i], _kind[i], _seed[i])


## Takes a block out of the structure (it became debris).
func _remove(i: int) -> void:
	if _state[i] == State.GONE:
		return
	if _state[i] == State.STATIC:
		alive_count -= 1
		scored_destroyed += _score[i]
		_score_dirty = true
		PhysicsServer3D.body_set_space(_bodies[i], RID())
		_dirty_groups[_group[i]] = true
		# Rubble frozen on or against it must be free to fall.
		if debris:
			var r := _size[i] * 0.5 + Vector3.ONE * 0.2
			debris.thaw_box(AABB(_xform[i].origin - r, r * 2.0), 0.3)
		_unanchor(i)
	_state[i] = State.GONE
	var o := i * FLOATS_PER_INSTANCE
	for k in FLOATS_PER_INSTANCE:
		_buffer[o + k] = 0.0
	_buffer_dirty = true
	segment_broken.emit(i)


# --- Stability -----------------------------------------------------------------


## Re-checks every changed structure. Returns how many blocks started
## falling or were crushed.
func settle() -> int:
	var changed := 0
	var guard := 0
	while not _dirty_groups.is_empty() and guard < 8:
		guard += 1
		var groups := _dirty_groups.keys()
		_dirty_groups.clear()
		for g: int in groups:
			changed += _settle_group(g)
	return changed


func _settle_group(g: int, hesitate := false) -> int:
	var changed := 0
	for comp in _components(_groups[g]):
		if hesitate and _is_pending(comp[0]):
			continue
		var grounded := false
		for i in comp:
			if _grounded[i]:
				grounded = true
				break
		if not grounded:
			changed += _release_or_wait(comp, false, g, hesitate)
			continue
		if comp.size() > 2 and _is_tipping(comp):
			changed += _release_or_wait(comp, true, g, hesitate)
			continue
		changed += _crush_overloaded(comp)
	return changed


func _components(members: PackedInt32Array) -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	var seen := {}
	for start in members:
		if _state[start] != State.STATIC or seen.has(start):
			continue
		var comp := PackedInt32Array()
		var stack: Array[int] = [start]
		seen[start] = true
		while not stack.is_empty():
			var i: int = stack.pop_back()
			comp.append(i)
			for n in _neighbors[i]:
				if _state[n] == State.STATIC and not seen.has(n):
					seen[n] = true
					stack.append(n)
		out.append(comp)
	return out


## Top-down load flow: each block passes its weight plus everything it holds
## to the blocks it rests on, in proportion to the contact area.
func _compute_loads(comp: PackedInt32Array) -> Dictionary:
	var supported := {}
	for i in comp:
		for s in _supporters[i]:
			if _state[s] == State.STATIC:
				supported[i] = true
				break
	var order: Array = Array(comp)
	# Highest first; at equal height, side-held blocks first so the load they
	# hand sideways is counted by their neighbours.
	order.sort_custom(
		func(a: int, b: int) -> bool:
			var ya := _local[a].position.y
			var yb := _local[b].position.y
			if absf(ya - yb) > 0.01:
				return ya > yb
			return not supported.has(a) and supported.has(b)
	)
	var incoming := {}
	var shear := {}
	for i: int in order:
		var total: float = _mass[i] + incoming.get(i, 0.0)
		_load[i] = total
		if _grounded[i]:
			continue
		var area := 0.0
		var sup: Array[int] = []
		var areas: Array[float] = []
		for k in _supporters[i].size():
			var s := _supporters[i][k]
			if _state[s] == State.STATIC:
				sup.append(s)
				areas.append(_support_area[i][k])
				area += _support_area[i][k]
		if area > 0.0:
			for k in sup.size():
				incoming[sup[k]] = incoming.get(sup[k], 0.0) + total * areas[k] / area
			continue
		# Held only from the side (lintel ends, overhangs): shear.
		shear[i] = total
		var side: Array[int] = []
		for n in _neighbors[i]:
			if _state[n] == State.STATIC and _local[n].position.y <= _local[i].position.y + CONTACT_EPS:
				side.append(n)
		for n in side:
			incoming[n] = incoming.get(n, 0.0) + total / side.size()
	return shear


func _crush_overloaded(comp: PackedInt32Array) -> int:
	var shear := _compute_loads(comp)
	var victims: Array[Vector2] = []  # (overload ratio, index)
	for i in comp:
		var cap := _capacity[i] * clampf(_health[i] / _max_health[i], 0.15, 1.0)
		if _load[i] > cap:
			victims.append(Vector2(_load[i] / cap, i))
		elif shear.has(i) and shear[i] > _mass[i] * SHEAR_WEIGHTS[_kind[i]]:
			victims.append(Vector2(-1.0, i))
	if victims.is_empty():
		return 0
	victims.sort()
	victims.reverse()
	var n := 0
	for v in victims:
		if n >= MAX_CRUSH_PER_FRAME:
			_dirty_groups[_group[int(v.y)]] = true  # continue next frame
			break
		var i := int(v.y)
		if v.x < 0.0:
			_dislodge(i, Vector3.ZERO)  # sheared off: drops whole
		else:
			_shatter(i, _xform[i].origin + Vector3.UP * _size[i].y, 2.0)
		n += 1
	return n


## True when the piece's centre of mass is outside the area it stands on.
func _is_tipping(comp: PackedInt32Array) -> bool:
	var com := Vector2.ZERO
	var mass := 0.0
	var pts := PackedVector2Array()
	for i in comp:
		var c := _local[i].get_center()
		com += Vector2(c.x, c.z) * _mass[i]
		mass += _mass[i]
		if _grounded[i]:
			var a := _local[i]
			pts.append(Vector2(a.position.x, a.position.z))
			pts.append(Vector2(a.end.x, a.position.z))
			pts.append(Vector2(a.end.x, a.end.z))
			pts.append(Vector2(a.position.x, a.end.z))
	if mass <= 0.0 or pts.size() < 3:
		return false
	com /= mass
	var hull := Geometry2D.convex_hull(pts)
	if hull.size() < 3:
		return true
	# Shrink the footprint a little so knife-edge balance still tips.
	var centroid := Vector2.ZERO
	for p in hull:
		centroid += p
	centroid /= hull.size()
	var inset := PackedVector2Array()
	for p in hull:
		inset.append(p + (centroid - p).limit_length(0.06))
	# It falls away from what still holds it: from the footprint toward the
	# centre of mass.
	_tip = com - centroid
	return not Geometry2D.is_point_in_polygon(com, inset)


# --- Falling clusters -----------------------------------------------------------


## Big pieces of building creak and hold for a moment before they go,
## which reads as weight; small ones go at once.
func _release_or_wait(comp: PackedInt32Array, toppled: bool, g: int, hesitate: bool) -> int:
	if not hesitate or comp.size() < HESITATE_MIN:
		return _release(comp, toppled)
	var k := clampf(comp.size() / 200.0, 0.0, 1.0)
	var at := Vector3.ZERO
	for i in comp:
		at += _xform[i].origin
	at /= comp.size()
	_pending.append(
		{"comp": comp, "toppled": toppled, "time": lerpf(HESITATE_TIME.x, HESITATE_TIME.y, k), "group": g}
	)
	about_to_fail.emit(at, comp.size())
	return 0


func _is_pending(i: int) -> bool:
	for p in _pending:
		if (p["comp"] as PackedInt32Array).has(i):
			return true
	return false


func _update_pending(delta: float) -> void:
	if _pending.is_empty():
		return
	for p in _pending.duplicate():
		p["time"] -= delta
		if p["time"] > 0.0:
			continue
		_pending.erase(p)
		# Whatever changed meanwhile, decide again with what still stands,
		# and this time without waiting.
		_settle_group(p["group"], false)


## Turns a set of blocks into one falling rigid body.
func _release(comp: PackedInt32Array, toppled: bool) -> int:
	if comp.size() < 3 or debris == null:
		for i in comp:
			_dislodge(i, Vector3.ZERO)
		return comp.size()
	if _clusters.size() >= MAX_CLUSTERS:
		_dissolve(_clusters[0], Vector3.ZERO, 0.0)
	var c := Cluster.new()
	var com := Vector3.ZERO
	var bounds := AABB(_xform[comp[0]].origin, Vector3.ZERO)
	for i in comp:
		com += _xform[i].origin * _mass[i]
		c.mass += _mass[i]
		bounds = bounds.expand(_xform[i].origin)
	# Rubble resting on what now falls must fall with it.
	debris.thaw_box(bounds.grow(1.0))
	com /= c.mass
	var body_xf := Transform3D(Basis(), com)
	var inv := body_xf.affine_inverse()
	c.body = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(c.body, PhysicsServer3D.BODY_MODE_RIGID)
	for i in comp:
		var off := inv * _xform[i]
		PhysicsServer3D.body_add_shape(c.body, _box_shape(_size[i] * 0.995), off)
		c.members.append(i)
		c.offsets.append(off)
		_state[i] = State.FALLING
		_unanchor(i)
		alive_count -= 1
		scored_destroyed += _score[i]
		PhysicsServer3D.body_set_space(_bodies[i], RID())
	_score_dirty = true
	PhysicsServer3D.body_set_param(c.body, PhysicsServer3D.BODY_PARAM_MASS, c.mass)
	if comp.size() >= PANCAKE_MIN:
		PhysicsServer3D.body_set_param(c.body, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, CLUSTER_GRAVITY)
	PhysicsServer3D.body_set_max_contacts_reported(c.body, 24)
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
	PhysicsServer3D.body_set_space(c.body, get_world_3d().space)
	PhysicsServer3D.body_set_state(c.body, PhysicsServer3D.BODY_STATE_TRANSFORM, body_xf)
	c.toppled = toppled
	if toppled:
		# Nudge it over its weakest edge so it visibly leans before it goes.
		var g := _group[comp[0]]
		var lean := _group_origin[g].basis * Vector3(_tip.x, 0, _tip.y)
		lean.y = 0.0
		var axis := Vector3.UP.cross(lean.normalized()).normalized()
		PhysicsServer3D.body_set_state(c.body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, axis * 0.6)
	_clusters.append(c)
	_dirty_groups[_group[comp[0]]] = true
	cluster_released.emit(com, comp.size(), toppled)
	return comp.size()


## Breaks a cluster into loose debris. `severity` (impact speed) decides how
## much of it shatters around `hit`.
func _dissolve(c: Cluster, hit: Vector3, severity: float) -> void:
	_clusters.erase(c)
	var xf: Transform3D = PhysicsServer3D.body_get_state(c.body, PhysicsServer3D.BODY_STATE_TRANSFORM)
	var v: Vector3 = PhysicsServer3D.body_get_state(c.body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	var w: Vector3 = PhysicsServer3D.body_get_state(c.body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
	PhysicsServer3D.free_rid(c.body)
	var shatter_chance := clampf((severity - 4.0) / 12.0, 0.0, 0.55)
	var near := clampf(severity * 0.18, 0.8, 2.5)
	for k in c.members.size():
		var i := c.members[k]
		if _state[i] != State.FALLING:
			continue
		var world := xf * c.offsets[k]
		_xform[i] = world
		var r := world.origin - xf.origin
		var vel := v + w.cross(r)
		var close := hit != Vector3.ZERO and world.origin.distance_to(hit) < near
		if severity > 4.0 and (close or randf() < shatter_chance):
			_shatter(i, hit, severity * 0.3, vel * 0.6)
		else:
			var spin := w
			if severity <= 0.0:
				# Came to rest without a real hit (leaning on rubble): loosen
				# the blocks so the pile slumps instead of standing in mid-air.
				# (Per piece: adding to `w` itself made it grow with every
				# block and flung big pieces across the city.)
				vel += Vector3(randf_range(-1, 1), randf_range(0, 0.5), randf_range(-1, 1)) * 0.8
				spin += Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 2.0
			_dislodge(i, vel, spin, 0.0)


## Centres of the falling pieces of building moving faster than `speed`
## (for dust trails).
func falling_cluster_positions(speed: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for c in _clusters:
		if c.prev_velocity.length_squared() > speed * speed:
			var xf: Transform3D = PhysicsServer3D.body_get_state(c.body, PhysicsServer3D.BODY_STATE_TRANSFORM)
			out.append(xf.origin)
	return out


func _update_clusters(delta: float) -> void:
	for c: Cluster in _clusters.duplicate():
		c.age += delta
		var xf: Transform3D = PhysicsServer3D.body_get_state(c.body, PhysicsServer3D.BODY_STATE_TRANSFORM)
		var v: Vector3 = PhysicsServer3D.body_get_state(c.body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
		var asleep: bool = PhysicsServer3D.body_get_state(c.body, PhysicsServer3D.BODY_STATE_SLEEPING)
		var dv := (c.prev_velocity - v).length()
		c.prev_velocity = v
		# Contacts can spread a landing over a few steps: compare with the
		# fastest recent speed too.
		var peak := 0.0
		for sp in c.recent:
			peak = maxf(peak, sp)
		c.recent.remove_at(0)
		c.recent.append(v.length())
		var drop := maxf(dv, peak - v.length())
		# Slow bumps (settling onto rubble) do not count; real hits do.
		# A big falling block landing on rubble crushes a storey too.
		var heavy := c.members.size() >= PANCAKE_MIN
		if c.age > 0.1 and drop > IMPACT_DV and peak > IMPACT_MIN_SPEED and (heavy or _touches_solid(c)):
			_impact(c, xf, peak)
			continue
		_check_lean(c, xf, delta)
		# Push through rubble rather than stopping dead on frozen pieces.
		if debris and debris.frozen_count > 0 and v.length() > 1.0:
			c.crush_tick -= delta
			if c.crush_tick <= -0.05:
				c.crush_tick = 0.0
				debris.thaw_box(
					_cluster_bounds(c, xf).grow(0.4).merge(_cluster_bounds(c, xf.translated(v * 0.15))), 0.4
				)
		# A heavy block resting on loose rubble grinds it down and sinks.
		if c.members.size() >= PANCAKE_MIN and v.length() < 1.0 and c.age > 0.3:
			c.crush_tick -= delta
			if c.crush_tick <= 0.0:
				c.crush_tick = 0.1
				if _crush_rubble_under(c, xf):
					continue
		if c.age > CLUSTER_MAX_AGE or (asleep and c.age > 0.5) or xf.origin.y < DebrisSystem.KILL_Y:
			_dissolve(c, Vector3.ZERO, 0.0)
			continue
		for k in c.members.size():
			_write_instance(c.members[k], xf * c.offsets[k])


## A big falling block landed: its lowest storey is crushed into rubble and
## the rest keeps falling, slowed down, onto it: floors pile up one after
## the other instead of the whole thing bursting at once. Returns false
## when there is nothing left to crush (then it breaks up as usual).
func _pancake(c: Cluster, xf: Transform3D, speed: float) -> bool:
	var low := INF
	for off in c.offsets:
		low = minf(low, (xf * off.origin).y)
	var crush: Array[int] = []  # positions in c.members
	var hit := Vector3.ZERO
	for k in c.members.size():
		var p := (xf * c.offsets[k]).origin
		if p.y < low + PANCAKE_LAYER:
			crush.append(k)
			hit += p
	if crush.is_empty() or c.members.size() - crush.size() < PANCAKE_MIN / 2:
		return false
	hit /= crush.size()
	var v: Vector3 = PhysicsServer3D.body_get_state(c.body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	floor_crushed.emit(hit, crush.size(), speed)
	cluster_impact.emit(hit, c.mass * crush.size() / c.members.size(), speed, crush.size())
	if debris:
		debris.thaw_near(hit, 3.0)
	apply_impact(hit, 1.5, speed * 0.3)
	# Shapes go from the end so the remaining indices stay valid.
	crush.reverse()
	for k in crush:
		var i := c.members[k]
		var world := xf * c.offsets[k]
		_xform[i] = world
		PhysicsServer3D.body_remove_shape(c.body, k)
		c.members.remove_at(k)
		c.offsets.remove_at(k)
		c.mass -= _mass[i]
		if randf() < 0.65:
			_shatter(i, hit, speed * 0.25, v * 0.2)
		else:
			_dislodge(i, v * 0.25 + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)), Vector3.ZERO, 0.0)
	PhysicsServer3D.body_set_param(c.body, PhysicsServer3D.BODY_PARAM_MASS, maxf(c.mass, 1.0))
	PhysicsServer3D.body_set_state(c.body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, v * PANCAKE_KEEP)
	PhysicsServer3D.body_set_state(c.body, PhysicsServer3D.BODY_STATE_SLEEPING, false)
	c.recent = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	c.prev_velocity = v * PANCAKE_KEEP
	c.age = 0.05
	return true


func _cluster_bounds(c: Cluster, xf: Transform3D) -> AABB:
	var box := AABB((xf * c.offsets[0]).origin, Vector3.ZERO)
	for off in c.offsets:
		box = box.expand((xf * off).origin)
	return box.grow(1.0)


## Loose pieces under a heavy resting block are ground into gravel so it
## keeps settling instead of standing on a few broken stubs. Returns true
## if anything was crushed.
func _crush_rubble_under(c: Cluster, xf: Transform3D) -> bool:
	if debris == null:
		return false
	var low := INF
	for off in c.offsets:
		low = minf(low, (xf * off.origin).y)
	var foot := AABB()
	var first := true
	for off in c.offsets:
		var p := xf * off.origin
		if p.y < low + 1.0:
			if first:
				foot = AABB(p, Vector3.ZERO)
				first = false
			else:
				foot = foot.expand(p)
	foot.position.y = low - 2.0
	foot.size.y = 2.2
	foot = foot.grow(0.4)
	var crushed := 0
	for i in debris.pieces_in(foot):
		if debris.mass_of(i) > c.mass * 0.25:
			continue
		var at := debris.position_of(i)
		if dust:
			dust.chips_box(at, debris.size_of(i), debris.kind_of(i), 6, 2.0)
		debris.despawn(i)
		crushed += 1
		if crushed >= 25:
			break
	if crushed == 0:
		return false
	if dust and randf() < 0.5:
		dust.puff(Vector3(foot.get_center().x, low, foot.get_center().z), 1.5, Materials.Kind.CONCRETE, 10)
	PhysicsServer3D.body_set_state(c.body, PhysicsServer3D.BODY_STATE_SLEEPING, false)
	# It drops into the space it just cleared.
	PhysicsServer3D.body_set_state(c.body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.DOWN * 2.5)
	c.age = maxf(c.age - 0.2, 0.35)  # keep it alive while it settles
	return true


## A heavy piece leaning on a standing one pushes it over (tower into tower).
func _check_lean(c: Cluster, xf: Transform3D, delta: float) -> void:
	if c.leaned or c.age < 0.2:
		return
	var state := PhysicsServer3D.body_get_direct_state(c.body)
	if state == null:
		return
	for k in state.get_contact_count():
		var seg: int = _rid_to_seg.get(state.get_contact_collider(k), -1)
		if seg < 0 or _state[seg] != State.STATIC:
			continue
		c.lean_time += delta
		if c.lean_time < LEAN_TIME:
			return
		c.leaned = true
		var at := state.get_contact_collider_position(k)
		var push := at - xf.origin
		push.y = 0.0
		_knock(seg, push.normalized() * 2.0, c.mass * LEAN_SPEED, at)
		return
	c.lean_time = maxf(c.lean_time - delta, 0.0)


## A falling piece hit something: damage what it struck, then break it up.
func _impact(c: Cluster, xf: Transform3D, speed: float) -> void:
	if c.members.size() >= PANCAKE_MIN and _pancake(c, xf, speed):
		return
	var hit := _lowest_point(c, xf)
	var struck := -1
	var state := PhysicsServer3D.body_get_direct_state(c.body)
	if state:
		for k in state.get_contact_count():
			hit = state.get_contact_collider_position(k)
			var seg: int = _rid_to_seg.get(state.get_contact_collider(k), -1)
			if seg >= 0 and _state[seg] == State.STATIC:
				struck = seg  # hitting a standing structure matters most
				break
	cluster_impact.emit(hit, c.mass, speed, c.members.size())
	if debris:
		debris.thaw_near(hit, 3.0)
	# Heavy pieces hit harder: chain reactions and dominoes.
	var heft := clampf(c.mass / 800.0, 1.0, 3.0)
	var reach := clampf(0.8 + c.members.size() * 0.02, 1.0, 2.5)
	apply_impact(hit, reach, speed * 0.35 * heft)
	var push := c.prev_velocity
	_dissolve(c, hit, speed)
	if struck >= 0 and _state[struck] == State.STATIC:
		_knock(struck, push, c.mass * speed, hit)


## A heavy hit can push a whole standing piece over (dominoes, towers).
func _knock(seg: int, velocity: Vector3, momentum: float, at: Vector3) -> void:
	var comp := _component_of(seg)
	var mass := 0.0
	var top := -INF
	var bottom := INF
	for i in comp:
		mass += _mass[i]
		top = maxf(top, _xform[i].origin.y)
		bottom = minf(bottom, _xform[i].origin.y)
	# Hits low on a piece barely tip it; hits near the top tip it easily.
	var lever := clampf((at.y - bottom) / maxf(top - bottom, 0.5), 0.2, 1.0)
	if momentum * lever < mass * KNOCK_SPEED:
		return
	var flat := Vector3(velocity.x, 0, velocity.z)
	if flat.length() < 0.1:
		return
	var n := _release(comp, false)
	if n == 0 or _clusters.is_empty():
		return
	var c := _clusters[_clusters.size() - 1]
	var dir := flat.normalized()
	var share := clampf(momentum / (mass + 1.0) * 0.4, 0.5, 4.0)
	PhysicsServer3D.body_set_state(c.body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, dir * share)
	PhysicsServer3D.body_set_state(
		c.body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.UP.cross(dir) * share * 0.35
	)
	cluster_released.emit(at, comp.size(), true)


func _component_of(seg: int) -> PackedInt32Array:
	var comp := PackedInt32Array()
	var seen := {seg: true}
	var stack: Array[int] = [seg]
	while not stack.is_empty():
		var i: int = stack.pop_back()
		comp.append(i)
		for n in _neighbors[i]:
			if _state[n] == State.STATIC and not seen.has(n):
				seen[n] = true
				stack.append(n)
	return comp


## True when the piece touches the ground, a structure or another falling
## piece; flying debris bumping into it does not count as a landing.
func _touches_solid(c: Cluster) -> bool:
	var state := PhysicsServer3D.body_get_direct_state(c.body)
	if state == null:
		return true
	for k in state.get_contact_count():
		if debris == null or debris.index_of(state.get_contact_collider(k)) < 0:
			return true
	return false


func _lowest_point(c: Cluster, xf: Transform3D) -> Vector3:
	var best := Vector3(0, INF, 0)
	for off in c.offsets:
		var p := xf * off.origin
		if p.y < best.y:
			best = p
	return best


func _current_transform(i: int) -> Transform3D:
	return _xform[i]


# --- Frame ---------------------------------------------------------------------


func _physics_process(delta: float) -> void:
	_update_clusters(delta)
	_update_pending(delta)
	if not _dirty_groups.is_empty():
		# One pass per frame so collapses visibly progress floor by floor.
		var groups := _dirty_groups.keys()
		_dirty_groups.clear()
		for g: int in groups:
			_settle_group(g, true)
	if _buffer_dirty:
		_multimesh.buffer = _buffer
		_buffer_dirty = false
	if _score_dirty:
		_score_dirty = false
		destruction_changed.emit(destruction())


# --- Spatial grid ----------------------------------------------------------------


func _grid_insert(i: int) -> void:
	var r := _size[i].length() * 0.5
	var p := _xform[i].origin
	var lo := Vector3i(((p - Vector3.ONE * r) / GRID_CELL).floor())
	var hi := Vector3i(((p + Vector3.ONE * r) / GRID_CELL).floor())
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for z in range(lo.z, hi.z + 1):
				var key := Vector3i(x, y, z)
				if not _grid.has(key):
					_grid[key] = PackedInt32Array()
				_grid[key].append(i)


## Static blocks whose bounds may reach within `radius` of `p`.
func _query(p: Vector3, radius: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var seen := {}
	var lo := Vector3i(((p - Vector3.ONE * radius) / GRID_CELL).floor())
	var hi := Vector3i(((p + Vector3.ONE * radius) / GRID_CELL).floor())
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for z in range(lo.z, hi.z + 1):
				var cell: Variant = _grid.get(Vector3i(x, y, z))
				if cell == null:
					continue
				for i: int in cell:
					if _state[i] == State.STATIC and not seen.has(i):
						seen[i] = true
						if _xform[i].origin.distance_to(p) <= radius + _size[i].length() * 0.5:
							out.append(i)
	return out


# --- Rendering -------------------------------------------------------------------


func _box_shape(size: Vector3) -> RID:
	var key := size.snappedf(0.001)
	if not _shape_cache.has(key):
		var shape := PhysicsServer3D.box_shape_create()
		PhysicsServer3D.shape_set_data(shape, size * 0.5)
		_shape_cache[key] = shape
	return _shape_cache[key]


func _write_instance(i: int, xf: Transform3D) -> void:
	var o := i * FLOATS_PER_INSTANCE
	var b := xf.basis
	var s := _size[i]
	_buffer[o + 0] = b.x.x * s.x
	_buffer[o + 1] = b.y.x * s.y
	_buffer[o + 2] = b.z.x * s.z
	_buffer[o + 3] = xf.origin.x
	_buffer[o + 4] = b.x.y * s.x
	_buffer[o + 5] = b.y.y * s.y
	_buffer[o + 6] = b.z.y * s.z
	_buffer[o + 7] = xf.origin.y
	_buffer[o + 8] = b.x.z * s.x
	_buffer[o + 9] = b.y.z * s.y
	_buffer[o + 10] = b.z.z * s.z
	_buffer[o + 11] = xf.origin.z
	_buffer[o + 12] = _shade[i]
	_buffer[o + 13] = Materials.encode(_kind[i])
	_buffer[o + 14] = fposmod(_seed[i], 1.0)
	_buffer[o + 15] = 0.0
	_buffer[o + 16] = Materials.custom(
		_kind[i], 1.0 - clampf(_health[i] / _max_health[i], 0.0, 1.0), _seed[i]
	)
	_buffer[o + 17] = _hit[i].x
	_buffer[o + 18] = _hit[i].y
	_buffer[o + 19] = _hit[i].z
	_buffer_dirty = true


func _rebuild_multimesh() -> void:
	if _multimesh == null:
		var box := BoxMesh.new()
		box.size = Vector3.ONE
		_multimesh = MultiMesh.new()
		_multimesh.transform_format = MultiMesh.TRANSFORM_3D
		_multimesh.use_colors = true
		_multimesh.use_custom_data = true
		_multimesh.mesh = box
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "StructureMesh"
		mmi.multimesh = _multimesh
		mmi.material_override = material
		add_child(mmi)
	var n := _xform.size()
	_buffer.resize(n * FLOATS_PER_INSTANCE)
	for i in n:
		if _state[i] == State.GONE:
			for k in FLOATS_PER_INSTANCE:
				_buffer[i * FLOATS_PER_INSTANCE + k] = 0.0
		else:
			_write_instance(i, _xform[i])
	_multimesh.instance_count = n
	_multimesh.buffer = _buffer
	_buffer_dirty = false
