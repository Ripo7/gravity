class_name StructureSet
extends Node3D
## All intact building blocks ("segments") of every structure in the arena.
##
## Segments are static PhysicsServer3D bodies drawn by one MultiMesh. When a
## blast damages a segment it either shatters into pre-fractured pieces or is
## dislodged as a whole block; both become DebrisSystem pieces. Afterwards a
## support check runs per structure: any segment with no chain of contacts to
## the ground falls as a whole block, so towers and walls collapse.

signal segment_broken(index: int)

const FLOATS_PER_INSTANCE := 16
const CONTACT_EPS := 0.03
const GROUND_EPS := 0.03

@export var debris: DebrisSystem
@export var material: Material

var alive_count := 0

var _xform: Array[Transform3D] = []  # global
var _local: Array[AABB] = []  # in its structure's space, for contacts
var _size := PackedVector3Array()
var _strength := PackedFloat32Array()
var _shade := PackedFloat32Array()
var _kind := PackedByteArray()
var _seed := PackedFloat32Array()
var _alive := PackedByteArray()
var _group := PackedInt32Array()
var _grounded := PackedByteArray()
var _neighbors: Array[PackedInt32Array] = []
var _groups: Array[PackedInt32Array] = []
var _bodies: Array[RID] = []
var _shape_cache := {}
var _dirty_groups := {}
var _multimesh: MultiMesh
var _buffer := PackedFloat32Array()
var _buffer_dirty := false


func _exit_tree() -> void:
	for rid in _bodies:
		PhysicsServer3D.free_rid(rid)
	for rid: RID in _shape_cache.values():
		PhysicsServer3D.free_rid(rid)
	_bodies.clear()
	_shape_cache.clear()


## `segments`: Array of {"local": Transform3D, "size": Vector3,
## "strength": float, "shade": float}; `origin` is the structure's transform.
func add_structure(origin: Transform3D, segments: Array[Dictionary]) -> int:
	var group_id := _groups.size()
	var members := PackedInt32Array()
	var space := get_world_3d().space
	for seg in segments:
		var i := _xform.size()
		var local: Transform3D = seg["local"]
		var size: Vector3 = seg["size"]
		var global := origin * local
		_xform.append(global)
		_local.append(AABB(local.origin - size * 0.5, size))
		_size.append(size)
		var kind: int = seg.get("material", Materials.Kind.CONCRETE)
		_kind.append(kind)
		_seed.append(seg.get("seed", randf()))
		_strength.append(seg.get("strength", 3.0) * Materials.prop(kind, "strength"))
		_shade.append(seg.get("shade", 1.0))
		_alive.append(1)
		_group.append(group_id)
		_grounded.append(1 if local.origin.y - size.y * 0.5 <= GROUND_EPS else 0)
		_neighbors.append(PackedInt32Array())
		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_add_shape(body, _box_shape(size))
		PhysicsServer3D.body_set_collision_layer(body, DebrisSystem.LAYER_STRUCTURES)
		PhysicsServer3D.body_set_collision_mask(body, 0)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, global)
		PhysicsServer3D.body_set_space(body, space)
		_bodies.append(body)
		members.append(i)
		alive_count += 1
	# Contact graph inside this structure (n is small, n^2 is fine).
	for a in members:
		var grown := _local[a].grow(CONTACT_EPS)
		for b in members:
			if a < b and grown.intersects(_local[b]):
				_neighbors[a].append(b)
				_neighbors[b].append(a)
	_groups.append(members)
	_rebuild_multimesh()
	return group_id


func segment_count() -> int:
	return _xform.size()


func is_alive(i: int) -> bool:
	return _alive[i] == 1


func transform_of(i: int) -> Transform3D:
	return _xform[i]


func kind_of(i: int) -> int:
	return _kind[i]


## Damages every segment within the blast. Returns how many broke or fell.
func apply_blast(center: Vector3, params: BlastParams, scale := 1.0) -> int:
	var hits := 0
	var reach := params.radius + 1.5
	for i in _xform.size():
		if not _alive[i]:
			continue
		var xf := _xform[i]
		if xf.origin.distance_to(center) > reach:
			continue
		# Distance from the blast to the block's surface, not its centre.
		var local_center := xf.affine_inverse() * center
		var half := _size[i] * 0.5
		var nearest := local_center.clamp(-half, half)
		var dist := nearest.distance_to(local_center)
		var dmg := params.damage * params.falloff(dist) * scale
		if dmg <= 0.0:
			continue
		if dmg >= _strength[i]:
			_shatter(i, center, dmg)
			hits += 1
		elif dmg >= _strength[i] * Materials.prop(_kind[i], "dislodge"):
			var away := (xf.origin - center).normalized()
			_dislodge(i, away * dmg * 0.8)
			hits += 1
	return hits


func break_segment(i: int) -> void:
	_shatter(i, _xform[i].origin + Vector3.UP, 0.0)


func _shatter(i: int, center: Vector3, dmg: float) -> void:
	var xf := _xform[i]
	var size := _size[i]
	var kind := _kind[i]
	var count := Fracture.piece_count_for(size, Materials.prop(kind, "pieces"))
	_remove(i)
	if debris == null:
		return
	var grain := Fracture.grain_for(kind, size)
	for piece: AABB in Fracture.pattern(size, count, i % 4, grain):
		var local := Transform3D(Basis(), piece.get_center())
		var world := xf * local
		var away := (world.origin - center).normalized()
		var kick := away * minf(dmg, 6.0) * 0.4
		var spin := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 3.0
		debris.spawn(world, piece.size * 0.985, kick, spin, 1.0, _shade[i], kind, _seed[i])


func _dislodge(i: int, velocity: Vector3) -> void:
	var xf := _xform[i]
	_remove(i)
	if debris:
		debris.spawn(xf, _size[i] * 0.995, velocity, Vector3.ZERO, 0.5, _shade[i], _kind[i], _seed[i])


func _remove(i: int) -> void:
	if not _alive[i]:
		return
	_alive[i] = 0
	alive_count -= 1
	PhysicsServer3D.body_set_space(_bodies[i], RID())
	var o := i * FLOATS_PER_INSTANCE
	for k in FLOATS_PER_INSTANCE:
		_buffer[o + k] = 0.0
	_buffer_dirty = true
	_dirty_groups[_group[i]] = true
	segment_broken.emit(i)


## Runs the support check now (normally once per physics frame).
func settle() -> int:
	var fallen := 0
	while not _dirty_groups.is_empty():
		var groups := _dirty_groups.keys()
		_dirty_groups.clear()
		for g: int in groups:
			fallen += _drop_unsupported(g)
	return fallen


func _drop_unsupported(g: int) -> int:
	var members := _groups[g]
	var supported := {}
	var stack: Array[int] = []
	for i in members:
		if _alive[i] and _grounded[i]:
			supported[i] = true
			stack.append(i)
	while not stack.is_empty():
		var i: int = stack.pop_back()
		for n in _neighbors[i]:
			if _alive[n] and not supported.has(n):
				supported[n] = true
				stack.append(n)
	var fallen := 0
	for i in members:
		if _alive[i] and not supported.has(i):
			_dislodge(i, Vector3.ZERO)
			fallen += 1
	return fallen


func _physics_process(_delta: float) -> void:
	if not _dirty_groups.is_empty():
		settle()
	if _buffer_dirty:
		_multimesh.buffer = _buffer
		_buffer_dirty = false


func _box_shape(size: Vector3) -> RID:
	var key := size.snappedf(0.001)
	if not _shape_cache.has(key):
		var shape := PhysicsServer3D.box_shape_create()
		PhysicsServer3D.shape_set_data(shape, size * 0.5)
		_shape_cache[key] = shape
	return _shape_cache[key]


func _rebuild_multimesh() -> void:
	if _multimesh == null:
		var box := BoxMesh.new()
		box.size = Vector3.ONE
		_multimesh = MultiMesh.new()
		_multimesh.transform_format = MultiMesh.TRANSFORM_3D
		_multimesh.use_colors = true
		_multimesh.mesh = box
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "StructureMesh"
		mmi.multimesh = _multimesh
		mmi.material_override = material
		add_child(mmi)
	var n := _xform.size()
	_buffer.resize(n * FLOATS_PER_INSTANCE)
	for i in n:
		var o := i * FLOATS_PER_INSTANCE
		if not _alive[i]:
			for k in FLOATS_PER_INSTANCE:
				_buffer[o + k] = 0.0
			continue
		var xf := _xform[i]
		var b := xf.basis
		var s := _size[i]
		var vals := [
			b.x.x * s.x,
			b.y.x * s.y,
			b.z.x * s.z,
			xf.origin.x,
			b.x.y * s.x,
			b.y.y * s.y,
			b.z.y * s.z,
			xf.origin.y,
			b.x.z * s.x,
			b.y.z * s.y,
			b.z.z * s.z,
			xf.origin.z,
			_shade[i],
			Materials.encode(_kind[i]),
			_seed[i],
			0.0,
		]
		for k in FLOATS_PER_INSTANCE:
			_buffer[o + k] = vals[k]
	_multimesh.instance_count = n
	_multimesh.buffer = _buffer
