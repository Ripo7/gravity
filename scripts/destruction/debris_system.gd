class_name DebrisSystem
extends Node3D
## Every loose piece in the world: fragments and dislodged blocks.
##
## Pieces are raw PhysicsServer3D bodies (no nodes) drawn by a single
## MultiMesh, so hundreds of pieces cost one draw call and no scene-tree
## overhead. Bodies are created once and pooled. Above a soft budget the
## oldest settled pieces shrink away over a second, so the pool rarely runs
## dry and nothing pops out of existence in front of the player.

const LAYER_WORLD := 1
const LAYER_STRUCTURES := 2
const LAYER_DEBRIS := 4
const LAYER_PLAYER := 8
const KILL_Y := -40.0
const FLOATS_PER_INSTANCE := 20  # 12 transform + 4 colour + 4 custom
const TINT_DECAY := 0.6  # violet glow fades per second
const SOFT_BUDGET := 0.8  ## fraction of capacity kept before retiring pieces
const FADE_TIME := 1.2  ## seconds a retired piece takes to shrink away
const RETIRE_PER_FRAME := 4

## Set before the scene loads to force a pool size (benchmarks).
static var capacity_override := 0

@export var capacity_desktop := 2000
@export var capacity_web := 900
@export var capacity_mobile := 700
## Pieces younger than this are never retired by the soft budget.
@export var retire_min_age := 6.0
## Seconds a piece may live; 0 keeps pieces until the budget recycles them.
@export var lifetime_desktop := 0.0
@export var lifetime_web := 240.0
@export var material: Material

var capacity := 0
var lifetime := 0.0
var active_count := 0
var awake_count := 0
var recycled_total := 0
var fading_count := 0

var _bodies: Array[RID] = []
var _shapes: Array[RID] = []
var _rid_to_index := {}
var _active := PackedByteArray()
var _sleeping := PackedByteArray()
var _size := PackedVector3Array()
var _pos := PackedVector3Array()
var _mass := PackedFloat32Array()
var _born := PackedFloat64Array()
var _tint := PackedFloat32Array()
var _shade := PackedFloat32Array()
var _kind := PackedByteArray()
var _seed := PackedFloat32Array()
var _fade := PackedFloat32Array()  # seconds left while shrinking away, 0 = not
var _free: Array[int] = []
var _buffer := PackedFloat32Array()
var _buffer_dirty := false
var _multimesh: MultiMesh
var _space: RID
var _clock := 0.0


func _ready() -> void:
	var web := OS.has_feature("web")
	if capacity_override > 0:
		capacity = capacity_override
	elif capacity <= 0:
		capacity = capacity_web if web else capacity_desktop
		if OS.has_feature("web_android") or OS.has_feature("web_ios") or OS.has_feature("mobile"):
			capacity = capacity_mobile
			# Fewer, chunkier fragments per break so the budget lasts longer.
			Fracture.quality = 0.6
	lifetime = lifetime_web if web else lifetime_desktop
	_space = get_world_3d().space
	_build_pool()


func _exit_tree() -> void:
	for rid in _bodies:
		PhysicsServer3D.free_rid(rid)
	for rid in _shapes:
		PhysicsServer3D.free_rid(rid)
	_bodies.clear()
	_shapes.clear()


func _build_pool() -> void:
	_active.resize(capacity)
	_sleeping.resize(capacity)
	_size.resize(capacity)
	_pos.resize(capacity)
	_mass.resize(capacity)
	_born.resize(capacity)
	_tint.resize(capacity)
	_shade.resize(capacity)
	_kind.resize(capacity)
	_seed.resize(capacity)
	_fade.resize(capacity)
	_fade.fill(0.0)
	_buffer.resize(capacity * FLOATS_PER_INSTANCE)
	_buffer.fill(0.0)
	for i in capacity:
		var shape := PhysicsServer3D.box_shape_create()
		PhysicsServer3D.shape_set_data(shape, Vector3.ONE * 0.5)
		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
		PhysicsServer3D.body_add_shape(body, shape)
		PhysicsServer3D.body_set_collision_layer(body, LAYER_DEBRIS)
		PhysicsServer3D.body_set_collision_mask(
			body, LAYER_WORLD | LAYER_STRUCTURES | LAYER_DEBRIS | LAYER_PLAYER
		)
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP, 0.05)
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP, 0.6)
		# Fast pieces must not tunnel through the floor or walls and vanish.
		# Jolt only sweeps bodies that move far in one step, so this is cheap.
		PhysicsServer3D.body_set_enable_continuous_collision_detection(body, true)
		_bodies.append(body)
		_shapes.append(shape)
		_rid_to_index[body] = i
		_free.append(capacity - 1 - i)  # pop() hands out low indices first
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_colors = true
	_multimesh.use_custom_data = true  # same shader as blocks (crack slot)
	_multimesh.mesh = box
	_multimesh.instance_count = capacity
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "DebrisMesh"
	mmi.multimesh = _multimesh
	mmi.material_override = material
	add_child(mmi)
	_multimesh.buffer = _buffer
	# Bounds never shrink below the arena; avoids per-frame AABB updates.
	_multimesh.custom_aabb = AABB(Vector3(-200, -50, -200), Vector3(400, 250, 400))


## Spawns a box piece. Returns its index, or -1 if nothing could be freed.
func spawn(
	xform: Transform3D,
	size: Vector3,
	velocity := Vector3.ZERO,
	spin := Vector3.ZERO,
	tint := 0.0,
	shade := 1.0,
	kind := Materials.Kind.CONCRETE,
	seed_value := -1.0
) -> int:
	var i := _take_slot()
	if i < 0:
		return -1
	var body := _bodies[i]
	PhysicsServer3D.shape_set_data(_shapes[i], size * 0.5)
	var mass := maxf(size.x * size.y * size.z * Materials.prop(kind, "density"), 0.5)
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_MASS, mass)
	PhysicsServer3D.body_set_param(
		body, PhysicsServer3D.BODY_PARAM_FRICTION, Materials.prop(kind, "friction")
	)
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_BOUNCE, Materials.prop(kind, "bounce"))
	PhysicsServer3D.body_set_space(body, _space)
	var clean := Transform3D(xform.basis.orthonormalized(), xform.origin)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, clean)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, velocity)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, spin)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_SLEEPING, false)
	_active[i] = 1
	_sleeping[i] = 0
	_size[i] = size
	_pos[i] = clean.origin
	_mass[i] = mass
	_born[i] = _clock
	_tint[i] = tint
	_shade[i] = shade
	_kind[i] = kind
	_seed[i] = seed_value if seed_value >= 0.0 else randf()
	_fade[i] = 0.0
	active_count += 1
	_write_instance(i, clean)
	return i


func despawn(i: int) -> void:
	if i < 0 or i >= capacity or not _active[i]:
		return
	PhysicsServer3D.body_set_space(_bodies[i], RID())
	_active[i] = 0
	active_count -= 1
	if _fade[i] > 0.0:
		fading_count -= 1
		_fade[i] = 0.0
	var o := i * FLOATS_PER_INSTANCE
	for k in FLOATS_PER_INSTANCE:
		_buffer[o + k] = 0.0
	_buffer_dirty = true
	_free.append(i)


func clear() -> void:
	for i in capacity:
		despawn(i)


## Starts shrinking piece `i` away; it is freed when the shrink ends.
func retire(i: int) -> void:
	if is_active(i) and _fade[i] <= 0.0:
		_fade[i] = FADE_TIME
		fading_count += 1


func is_fading(i: int) -> bool:
	return _fade[i] > 0.0


func is_active(i: int) -> bool:
	return i >= 0 and i < capacity and _active[i] == 1


func index_of(rid: RID) -> int:
	return _rid_to_index.get(rid, -1)


func position_of(i: int) -> Vector3:
	return _pos[i]


func size_of(i: int) -> Vector3:
	return _size[i]


func mass_of(i: int) -> float:
	return _mass[i]


func kind_of(i: int) -> int:
	return _kind[i]


## How strongly blasts move this piece (wood flies, metal resists).
func response_of(i: int) -> float:
	return Materials.prop(_kind[i], "blast_response")


func transform_of(i: int) -> Transform3D:
	return PhysicsServer3D.body_get_state(_bodies[i], PhysicsServer3D.BODY_STATE_TRANSFORM)


func velocity_of(i: int) -> Vector3:
	return PhysicsServer3D.body_get_state(_bodies[i], PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)


func set_velocity(i: int, v: Vector3) -> void:
	var body := _bodies[i]
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, v)
	if _sleeping[i]:
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_SLEEPING, false)
		_sleeping[i] = 0


func add_spin(i: int, w: Vector3) -> void:
	var body := _bodies[i]
	var cur: Vector3 = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, cur + w)


func apply_impulse(i: int, impulse: Vector3) -> void:
	set_velocity(i, velocity_of(i) + impulse / _mass[i])


func set_tint(i: int, t: float) -> void:
	_tint[i] = maxf(_tint[i], t)


## Breaks piece `i` into smaller pieces. Returns the new indices.
func fracture(i: int, extra_velocity := Vector3.ZERO) -> PackedInt32Array:
	var out := PackedInt32Array()
	if not is_active(i):
		return out
	var size := _size[i]
	var kind := _kind[i]
	var count := Fracture.piece_count_for(size, Materials.prop(kind, "pieces"))
	if size[size.min_axis_index()] < Fracture.MIN_EDGE * 2.0 or count < 2:
		return out
	var xform := transform_of(i)
	var vel := velocity_of(i) + extra_velocity
	var tint := _tint[i]
	var shade := _shade[i]
	var seed_value := _seed[i]
	despawn(i)
	var grain := Fracture.grain_for(kind, size)
	for piece: AABB in Fracture.pattern(size, count, i % 3, grain):
		var local := Transform3D(Basis(), piece.get_center())
		var j := spawn(xform * local, piece.size * 0.985, vel, Vector3.ZERO, tint, shade, kind, seed_value)
		if j >= 0:
			out.append(j)
	return out


func _take_slot() -> int:
	if not _free.is_empty():
		return _free.pop_back()
	# Pool empty: take the piece closest to finishing its shrink, else the
	# oldest sleeping piece, else the oldest piece.
	var victim := -1
	var best := INF
	for i in capacity:
		if not _active[i]:
			continue
		var score := _born[i]
		if _fade[i] > 0.0:
			score = -1e9 + _fade[i]
		elif _sleeping[i]:
			score -= 1e6
		if score < best:
			best = score
			victim = i
	if victim < 0:
		return -1
	despawn(victim)
	recycled_total += 1
	return _free.pop_back()


## Above the soft budget, retire a few of the oldest settled pieces per frame.
func _enforce_budget() -> void:
	var excess := active_count - fading_count - int(capacity * SOFT_BUDGET)
	if excess <= 0:
		return
	var candidates: Array[Vector2] = []  # (score, index)
	for i in capacity:
		if not _active[i] or _fade[i] > 0.0 or _tint[i] > 0.0:
			continue
		if _clock - _born[i] < retire_min_age:
			continue
		var score := _born[i] - (1e6 if _sleeping[i] else 0.0)
		candidates.append(Vector2(score, i))
	candidates.sort()
	for k in mini(mini(excess, RETIRE_PER_FRAME), candidates.size()):
		retire(int(candidates[k].y))


func _physics_process(delta: float) -> void:
	_clock += delta
	var awake := 0
	var tint_step := TINT_DECAY * delta
	for i in capacity:
		if not _active[i]:
			continue
		var body := _bodies[i]
		var asleep: bool = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_SLEEPING)
		_sleeping[i] = 1 if asleep else 0
		var tinted := _tint[i] > 0.0
		if tinted:
			_tint[i] = maxf(_tint[i] - tint_step, 0.0)
		var fading := _fade[i] > 0.0
		if fading:
			_fade[i] -= delta
			if _fade[i] <= 0.0:
				_fade[i] = 0.0001  # keep the counter consistent in despawn
				despawn(i)
				continue
		if asleep and not tinted and not fading:
			if lifetime > 0.0 and _clock - _born[i] > lifetime:
				retire(i)
			continue
		awake += 0 if asleep else 1
		var xform: Transform3D = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM)
		if xform.origin.y < KILL_Y:
			despawn(i)
			continue
		_pos[i] = xform.origin
		_write_instance(i, xform)
	awake_count = awake
	_enforce_budget()
	if _buffer_dirty:
		_multimesh.buffer = _buffer
		_buffer_dirty = false


func _write_instance(i: int, xform: Transform3D) -> void:
	var s := _size[i]
	if _fade[i] > 0.0:
		var k := clampf(_fade[i] / FADE_TIME, 0.0, 1.0)
		s *= k * k * (3.0 - 2.0 * k)
	var b := xform.basis
	var o := i * FLOATS_PER_INSTANCE
	_buffer[o + 0] = b.x.x * s.x
	_buffer[o + 1] = b.y.x * s.y
	_buffer[o + 2] = b.z.x * s.z
	_buffer[o + 3] = xform.origin.x
	_buffer[o + 4] = b.x.y * s.x
	_buffer[o + 5] = b.y.y * s.y
	_buffer[o + 6] = b.z.y * s.z
	_buffer[o + 7] = xform.origin.y
	_buffer[o + 8] = b.x.z * s.x
	_buffer[o + 9] = b.y.z * s.y
	_buffer[o + 10] = b.z.z * s.z
	_buffer[o + 11] = xform.origin.z
	_buffer[o + 12] = _shade[i]
	_buffer[o + 13] = Materials.encode(_kind[i])
	_buffer[o + 14] = _seed[i]
	_buffer[o + 15] = _tint[i]
	_buffer_dirty = true
