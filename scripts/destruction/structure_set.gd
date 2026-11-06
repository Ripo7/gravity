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

signal shattered(at: Vector3, size: Vector3, kind: int)
signal cluster_released(at: Vector3, count: int, toppled: bool)
signal cluster_impact(at: Vector3, mass: float, speed: float, count: int)
## A big piece of building is about to give way (it creaks first).
signal about_to_fail(at: Vector3, count: int)
## A falling floor crushed the one below it and keeps going.
signal floor_crushed(at: Vector3, count: int, speed: float)

enum State { GONE, STATIC, FALLING }

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
## Blocks bigger than this (m^3) crack into shards when they come loose: a
## wall panel never tumbles away whole (the Lego look). Smaller ones (a
## stone, a bracket, a column drum) may stay whole, unless they are long and
## thin (a cornice, a beam: they break into lengths). Phones let bigger
## blocks stay whole (fewer bodies).
const WHOLE_MAX_VOLUME := Vector3(0.6, 0.4, 0.4)
const SLENDER := Vector2(2.0, 3.0)  ## m long at least, and that many times its width
## Cracking open, the shards of a loosened block part this fast (m/s).
const LOOSE_CRACK_PUSH := 0.7
const LEAN_TIME := 0.2  ## seconds of leaning before the weight tells
const LEAN_SPEED := 2.0  ## leaning counts like an impact at this speed

@export var debris: DebrisSystem
@export var material: Material

var dust: DustSystem  ## optional: gravel and dust when rubble is crushed
var rebar: RebarSystem  ## optional: steel rods left in broken concrete
var alive_count := 0
var walls: WallCells  ## walls, floors and roofs that crack open in place
var footing: Footing  ## tipping, and how far blocks can hang from their neighbours

var _state := PackedByteArray()
var _xform: Array[Transform3D] = []  # global rest transform
var _local: Array[AABB] = []  # in the structure's own space
var _round := PackedInt32Array()  ## slot in the round (cylinder) MultiMesh, -1 = box
var _round_count := 0
var _piece := PackedInt32Array()  ## carved piece drawn (ShapeLibrary index), 0 = none
var _piece_counts := PackedInt32Array()
var _mesh: StructureMesh
var _size := PackedVector3Array()
var _kind := PackedByteArray()
var _seed := PackedFloat32Array()
var _shade := PackedFloat32Array()
var _health := PackedFloat32Array()
var _max_health := PackedFloat32Array()
var _mass := PackedFloat32Array()
var _capacity := PackedFloat32Array()
## Load a block held only from the side can carry, calibrated like _capacity.
var _shear_cap := PackedFloat32Array()
var _load := PackedFloat32Array()
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
var _grid := SphereGrid.new(GRID_CELL)
## One instance row, reused (no allocation per block per frame).
var _dirty_groups := {}
## group -> heights (structure space) where blocks went since its last check:
## where a tower may now pivot over what is left of a course.
var _cut_levels := {}
var _tip := Vector2.ZERO  # last tipping direction (structure space)
var _clusters: Array[FallingCluster] = []
var _pending: Array[Dictionary] = []  # {comp, toppled, time, group}
## Structures standing on other structures (a water tower on a roof):
## block -> blocks of other structures it rests on, and the reverse.
var _anchors := {}
var _power_tint := 0.0  ## violet glow for pieces broken right now
var _alive_mass := 0.0
var _built_mass := 0.0
var _whole_max := float(Quality.pick(WHOLE_MAX_VOLUME.x, WHOLE_MAX_VOLUME.y, WHOLE_MAX_VOLUME.z))
var _hit := PackedVector3Array()  ## where each block was hit (unit space + 1)
var _anchored_by := {}


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
	if walls:
		walls.free_shapes()


# --- Building ----------------------------------------------------------------


## `segments`: Array of {"local": Transform3D, "size": Vector3, "strength",
## "material", "shade", "seed"}; `origin` is the structure's transform.
func add_structure(origin: Transform3D, segments: Array[Dictionary]) -> int:
	var group_id := _groups.size()
	var members := PackedInt32Array()
	var before := _alive_mass
	if walls == null:
		walls = WallCells.new(self)
	if footing == null:
		footing = Footing.new(self)
	_groups.append(members)
	_group_origin.append(origin)
	for seg in segments:
		var local: Transform3D = seg["local"]
		var size: Vector3 = seg["size"]
		var kind: int = seg.get("material", Materials.Kind.CONCRETE)
		var hp: float = seg.get("strength", 3.0) * Materials.prop(kind, "strength")
		var i := add_block(
			group_id,
			origin * local,
			local * AABB(-size * 0.5, size),  # bounds in structure space (ramps tilt)
			size,
			kind,
			seg.get("seed", randf()),
			seg.get("shade", 1.0),
			hp,
			size.x * size.y * size.z * Materials.prop(kind, "density"),
			_box_shape(size)
		)
		var piece := ShapeLibrary.index(seg.get("shape", ""))
		if piece > 0:
			if _piece_counts.size() < piece:
				_piece_counts.resize(piece)
			_piece[i] = piece
			_round[i] = _piece_counts[piece - 1]
			_piece_counts[piece - 1] += 1
		elif seg.get("round", false):
			_round[i] = _round_count
			_round_count += 1
	members = _groups[group_id]
	_built_mass += _alive_mass - before
	_link(members)
	# Calibrate capacities on the intact structure so it always stands.
	# Blocks held from the side (lintels, arch stones) get the same reserve
	# over what they hold when intact, so every intact structure stands.
	var shear := _compute_loads(members)
	for k in members.size():
		var i := members[k]
		var floor_cap := _mass[i] * 3.0
		var robust: float = segments[k].get("robust", 1.0)
		_capacity[i] = maxf(_load[i] * SAFETY[_kind[i]] * robust, floor_cap)
		var held: float = shear.get(i, 0.0)
		_shear_cap[i] = maxf(held * SAFETY[_kind[i]] * robust, _mass[i] * SHEAR_WEIGHTS[_kind[i]])
	footing.calibrate(members)
	_rebuild_multimesh()
	return group_id


## Adds one static block to structure `group` (also used for the cells a
## wall cracks into, see WallCells). Returns its index.
func add_block(
	group: int,
	global: Transform3D,
	local: AABB,
	size: Vector3,
	kind: int,
	seed_value: float,
	shade: float,
	hp: float,
	mass: float,
	shape: RID
) -> int:
	var i := _xform.size()
	_state.append(State.STATIC)
	_xform.append(global)
	_local.append(local)
	_size.append(size)
	_kind.append(kind)
	_seed.append(seed_value)
	_round.append(-1)
	_piece.append(0)
	_shade.append(shade)
	_hit.append(Vector3.ZERO)
	_health.append(hp)
	_max_health.append(hp)
	_mass.append(mass)
	_capacity.append(0.0)
	_shear_cap.append(0.0)
	_load.append(0.0)
	_group.append(group)
	_grounded.append(1 if local.position.y <= GROUND_EPS else 0)
	_neighbors.append(PackedInt32Array())
	_supporters.append(PackedInt32Array())
	_support_area.append(PackedFloat32Array())
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_add_shape(body, shape)
	PhysicsServer3D.body_set_collision_layer(body, DebrisSystem.LAYER_STRUCTURES)
	PhysicsServer3D.body_set_collision_mask(body, 0)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, global)
	PhysicsServer3D.body_set_space(body, get_world_3d().space)
	_bodies.append(body)
	_rid_to_seg[body] = i
	_grid.insert(i, global.origin, size.length() * 0.5)
	_groups[group].append(i)
	alive_count += 1
	_alive_mass += mass
	footing.add(i)
	return i


## Links blocks `a` and `b` as touching; `area` > 0 if `b` holds `a` up.
func link_blocks(a: int, b: int, support_area := 0.0) -> void:
	if not _neighbors[a].has(b):
		_neighbors[a].append(b)
		_neighbors[b].append(a)
	if support_area > 0.0:
		_supporters[a].append(b)
		_support_area[a].append(support_area)


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
			footing.touched(b)
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


func transform_of(i: int) -> Transform3D:
	return _xform[i]


func kind_of(i: int) -> int:
	return _kind[i]


func size_of(i: int) -> Vector3:
	return _size[i]


func health_of(i: int) -> float:
	return _health[i]


func cluster_count() -> int:
	return _clusters.size()


## {mass, velocity} of the falling piece whose body is `rid`, or empty. The
## velocity is the faster of now and the last step (what it hit stopped it).
func cluster_motion(rid: RID) -> Dictionary:
	for c in _clusters:
		if c.body == rid:
			var v: Vector3 = PhysicsServer3D.body_get_state(
				c.body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY
			)
			if c.prev_velocity.length_squared() > v.length_squared():
				v = c.prev_velocity
			return {"mass": c.mass, "velocity": v}
	return {}


## World position of the block of falling piece `rid` nearest to `p`, or
## Vector3.INF. Tells whether a falling floor comes at you or falls away.
func cluster_point(rid: RID, p: Vector3) -> Vector3:
	for c in _clusters:
		if c.body == rid:
			return c.nearest_point(p)
	return Vector3.INF


## Share of all blocks still standing (1 = intact).
## Share of what was built that still stands (by mass: cracked walls add
## blocks, not matter).
func standing_fraction() -> float:
	return clampf(_alive_mass / maxf(_built_mass, 1e-6), 0.0, 1.0)


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
	for c: FallingCluster in _clusters.duplicate():
		if c.nearest_point(center).distance_to(center) < radius:
			_dissolve(c, center, 0.0)


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


## Breaks block `i`. A cell of a cracked wall comes away whole (it breaks
## when it lands) unless `crumble` (it already did: a falling piece's hit).
func _shatter(i: int, from: Vector3, dmg: float, inherit := Vector3.ZERO, crumble := false) -> void:
	# A wall hit for real cracks open in place (break_segment, dmg 0, takes
	# the whole block out: tools and tests).
	if walls and dmg > 0.0 and _state[i] == State.STATIC and walls.can_crack(i):
		walls.crack(i, from, dmg, _power_tint)
		return
	var xf := _current_transform(i)
	var size := _size[i]
	var kind := _kind[i]
	if walls and walls.is_cell(i):
		# A cell of a cracked wall is knocked out whole (it breaks on landing).
		var away := (xf.origin - from).normalized() * minf(dmg, 6.0) * 0.4
		_remove(i)
		shattered.emit(xf.origin, size, kind)
		var j := walls.to_debris(i, xf, away + inherit, Vector3.ZERO, _power_tint)
		if crumble and j >= 0:
			debris.fracture(j)
		return
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
	if debris == null:
		return
	if walls and walls.is_cell(i):
		walls.to_debris(i, xf, velocity, spin, tint)
		return
	var size := _size[i]
	var long := size[size.max_axis_index()]
	var width := size.x + size.y + size.z - long - size[size.min_axis_index()]
	var slender := long > SLENDER.x and long > width * SLENDER.y
	if (size.x * size.y * size.z > _whole_max or slender) and ShardLibrary.has(_kind[i]):
		debris.shatter_box(
			xf, size, _kind[i], xf.origin, LOOSE_CRACK_PUSH, velocity, tint, _shade[i], _seed[i], i
		)
		return
	debris.spawn(xf, size * 0.995, velocity, spin, tint, _shade[i], _kind[i], _seed[i])


## Takes a block out of the structure (it became debris).
func _remove(i: int) -> void:
	if _state[i] == State.GONE:
		return
	var was_standing := _state[i] == State.STATIC
	# Gone first: whatever stood on it must not count it as support.
	_state[i] = State.GONE
	if was_standing:
		alive_count -= 1
		_alive_mass -= _mass[i]
		PhysicsServer3D.body_set_space(_bodies[i], RID())
		_dirty_groups[_group[i]] = true
		_note_cut(i)
		footing.removed(i)
		# Rubble frozen on or against it must be free to fall (the box turns
		# with the block: ramps, rotated cornices).
		if debris:
			debris.thaw_box((_xform[i] * AABB(-_size[i] * 0.5, _size[i])).grow(0.2), 0.3)
		_unanchor(i)
	_clear_instance(i)


# --- Stability -----------------------------------------------------------------


## Marks every structure as changed and settles them at once. A sound,
## intact building returns 0 (tests and level authoring).
func recheck_all() -> int:
	for g in _groups.size():
		_dirty_groups[g] = true
	return settle()


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
	var levels: PackedFloat32Array = _cut_levels.get(g, PackedFloat32Array())
	var waiting := false
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
		if comp.size() > 2 and footing.tipping(comp):
			changed += _release_or_wait(comp, true, g, hesitate)
			continue
		# Standing on what is left of a cut course: the part above may pivot
		# over its edge (a tower cut at the foot on one side).
		var upper := footing.tipping_above(comp, levels)
		if upper.size() > 2:
			if hesitate and _is_pending(upper[0]):
				waiting = true
				continue
			var n := _release_or_wait(upper, true, g, hesitate)
			waiting = waiting or n == 0
			changed += n
			continue
		changed += _crush_overloaded(comp)
	# Hanging farther from what carries it than it can reach (the roof over
	# a big hole): it comes away, with all it carries.
	for part in footing.hanging(g):
		if hesitate and _is_pending(part[0]):
			waiting = true
			continue
		var n := _release_or_wait(part, false, g, hesitate)
		waiting = waiting or n == 0
		changed += n
	if not waiting:
		_cut_levels.erase(g)
	return changed


## Remembers where block `i` went (for Footing.tipping_above).
func _note_cut(i: int) -> void:
	var g := _group[i]
	var levels: PackedFloat32Array = _cut_levels.get(g, PackedFloat32Array())
	var h := _local[i].get_center().y
	for l in levels:
		if absf(l - h) < 0.3:
			return
	if levels.size() < 8:
		levels.append(h)
	_cut_levels[g] = levels


func _components(members: PackedInt32Array) -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	# Flags in a packed array: a Dictionary lookup per block per re-check
	# was most of the cost on a whole palace.
	var seen := PackedByteArray()
	seen.resize(_xform.size())
	for start in members:
		if _state[start] != State.STATIC or seen[start]:
			continue
		var comp := PackedInt32Array()
		var stack := PackedInt32Array([start])
		seen[start] = 1
		while not stack.is_empty():
			var i := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			comp.append(i)
			for n in _neighbors[i]:
				if not seen[n] and _state[n] == State.STATIC:
					seen[n] = 1
					stack.append(n)
		out.append(comp)
	return out


## Top-down load flow: each block passes its weight plus everything it holds
## to the blocks it rests on, in proportion to the contact area.
func _compute_loads(comp: PackedInt32Array) -> Dictionary:
	var supported := PackedByteArray()
	supported.resize(_xform.size())
	for i in comp:
		for s in _supporters[i]:
			if _state[s] == State.STATIC:
				supported[i] = 1
				break
	# Highest first; at equal height (to the cm), side-held blocks first so
	# the load they hand sideways is counted by their neighbours. Sorted as
	# packed integer keys: a GDScript comparator over a whole palace on
	# every re-check cost milliseconds.
	var order := PackedInt64Array()
	order.resize(comp.size())
	for k in comp.size():
		var i := comp[k]
		var y_cm := int(roundf(_local[i].position.y * 100.0))
		var rank := (100000 - y_cm) * 2 + supported[i]
		order[k] = (rank << 20) | i
	order.sort()
	var incoming := PackedFloat32Array()
	incoming.resize(_xform.size())
	var shear := {}
	for key in order:
		var i := key & 0xFFFFF
		var total: float = _mass[i] + incoming[i]
		_load[i] = total
		if _grounded[i]:
			continue
		var below := _supporters[i]
		var areas := _support_area[i]
		var area := 0.0
		for k in below.size():
			if _state[below[k]] == State.STATIC:
				area += areas[k]
		if area > 0.0:
			for k in below.size():
				if _state[below[k]] == State.STATIC:
					incoming[below[k]] += total * areas[k] / area
			continue
		# Held only from the side (lintel ends, overhangs): shear.
		shear[i] = total
		var side: Array[int] = []
		for n in _neighbors[i]:
			if _state[n] == State.STATIC and _local[n].position.y <= _local[i].position.y + CONTACT_EPS:
				side.append(n)
		for n in side:
			incoming[n] += total / side.size()
	return shear


func _crush_overloaded(comp: PackedInt32Array) -> int:
	var shear := _compute_loads(comp)
	var victims: Array[Vector2] = []  # (overload ratio, index)
	for i in comp:
		var cap := _capacity[i] * clampf(_health[i] / _max_health[i], 0.15, 1.0)
		if _load[i] > cap:
			victims.append(Vector2(_load[i] / cap, i))
		elif shear.has(i) and shear[i] > _shear_cap[i] * clampf(_health[i] / _max_health[i], 0.15, 1.0):
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
	var c := FallingCluster.new()
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
		footing.removed(i)
		_unanchor(i)
		alive_count -= 1
		_alive_mass -= _mass[i]
		PhysicsServer3D.body_set_space(_bodies[i], RID())
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
func _dissolve(c: FallingCluster, hit: Vector3, severity: float) -> void:
	_clusters.erase(c)
	var xf: Transform3D = PhysicsServer3D.body_get_state(c.body, PhysicsServer3D.BODY_STATE_TRANSFORM)
	var v: Vector3 = PhysicsServer3D.body_get_state(c.body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	var w: Vector3 = PhysicsServer3D.body_get_state(c.body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
	PhysicsServer3D.free_rid(c.body)
	# A real hit breaks what falls: all near the hit, every big block (a
	# floor never lands whole) and, the harder the hit, more of the rest.
	var shatter_chance := clampf((severity - 3.0) / 9.0, 0.0, 0.8)
	var near := clampf(severity * 0.18, 0.8, 2.5)
	var big := debris.max_piece * 2.0 if debris else INF
	for k in c.members.size():
		var i := c.members[k]
		if _state[i] != State.FALLING:
			continue
		var world := xf * c.offsets[k]
		_xform[i] = world
		var r := world.origin - xf.origin
		var vel := v + w.cross(r)
		var close := hit != Vector3.ZERO and world.origin.distance_to(hit) < near
		var bulk := _size[i].x * _size[i].y * _size[i].z > big
		if severity > 4.0 and (close or bulk or randf() < shatter_chance):
			_shatter(i, hit, severity * 0.3, vel * 0.6, true)
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
	for c: FallingCluster in _clusters.duplicate():
		# An earlier one may have dissolved this one (knocked over, too many).
		if not _clusters.has(c):
			continue
		c.age += delta
		var xf: Transform3D = PhysicsServer3D.body_get_state(c.body, PhysicsServer3D.BODY_STATE_TRANSFORM)
		var v: Vector3 = PhysicsServer3D.body_get_state(c.body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
		var asleep: bool = PhysicsServer3D.body_get_state(c.body, PhysicsServer3D.BODY_STATE_SLEEPING)
		var before := c.prev_velocity
		var dv := (before - v).length()
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
			_impact(c, xf, peak, before)
			continue
		_check_lean(c, xf, delta)
		if not _clusters.has(c):
			continue
		# Push through rubble rather than stopping dead on frozen pieces.
		if debris and debris.frozen_count > 0 and v.length() > 1.0:
			c.crush_tick -= delta
			if c.crush_tick <= -0.05:
				c.crush_tick = 0.0
				debris.thaw_box(c.bounds(xf).grow(0.4).merge(c.bounds(xf.translated(v * 0.15))), 0.4)
		# A heavy block resting on loose rubble grinds it down and sinks.
		if c.members.size() >= PANCAKE_MIN and v.length() < 1.0 and c.age > 0.3:
			c.crush_tick -= delta
			if c.crush_tick <= 0.0:
				c.crush_tick = 0.1
				if _crush_rubble_under(c, xf) or not _clusters.has(c):
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
func _pancake(c: FallingCluster, xf: Transform3D, speed: float) -> bool:
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


## Loose pieces under a heavy resting block are ground into gravel so it
## keeps settling instead of standing on a few broken stubs. Returns true
## if anything was crushed.
func _crush_rubble_under(c: FallingCluster, xf: Transform3D) -> bool:
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
func _check_lean(c: FallingCluster, xf: Transform3D, delta: float) -> void:
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
## `push` is the velocity it had just before the hit (the direction it was
## going: after the hit it may be stopped or bouncing back).
func _impact(c: FallingCluster, xf: Transform3D, speed: float, push: Vector3) -> void:
	if c.members.size() >= PANCAKE_MIN and _pancake(c, xf, speed):
		return
	var hit := c.lowest_point(xf)
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
	var dir := flat.normalized()
	var share := clampf(momentum / (mass + 1.0) * 0.4, 0.5, 4.0)
	if comp.size() < 3 or debris == null:
		# Too small for a falling body of its own: the pieces take the push.
		for i in comp:
			_dislodge(i, dir * share, Vector3.UP.cross(dir) * share * 0.35)
		return
	var before := _clusters.size()
	_release(comp, false)
	if _clusters.size() <= before:
		return
	var c := _clusters[_clusters.size() - 1]
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
		for n in _neighbors[i]:
			if _state[n] == State.STATIC and not seen.has(n):
				seen[n] = true
				stack.append(n)
	return comp


## True when the piece touches the ground, a structure, another falling
## piece or a pile of rubble; flying debris bumping into it does not count
## as a landing.
func _touches_solid(c: FallingCluster) -> bool:
	var state := PhysicsServer3D.body_get_direct_state(c.body)
	if state == null:
		return true
	for k in state.get_contact_count():
		var j := debris.index_of(state.get_contact_collider(k)) if debris else -1
		if j < 0 or debris.is_resting(j):
			return true
	return false


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
	_mesh.flush()
	if walls:
		walls.flush()


## Static blocks whose bounds may reach within `radius` of `p`.
func _query(p: Vector3, radius: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in _grid.query(p, radius):
		if _state[i] == State.STATIC:
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
	var damage := 1.0 - clampf(_health[i] / _max_health[i], 0.0, 1.0)
	if walls and walls.is_cell(i):
		walls.write(i, xf, damage)
		return
	var custom := Materials.custom(_kind[i], damage, _seed[i])
	_mesh.write(i, _round[i], _piece[i], xf, _size[i], _shade[i], _seed[i], custom, _hit[i])


func _clear_instance(i: int) -> void:
	if walls and walls.is_cell(i):
		walls.clear(i)
	else:
		_mesh.clear(i, _round[i], _piece[i])


func _rebuild_multimesh() -> void:
	if _mesh == null:
		_mesh = StructureMesh.new(self, material)
	var n := _xform.size()
	_mesh.resize(n, _round_count, _piece_counts)
	for i in n:
		if _state[i] == State.GONE:
			_clear_instance(i)
		else:
			_write_instance(i, _xform[i])
	_mesh.flush()
