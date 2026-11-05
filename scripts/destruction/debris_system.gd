class_name DebrisSystem
extends Node3D
## Every loose piece in the world: fragments and dislodged blocks.
##
## Pieces are raw PhysicsServer3D bodies (no nodes) drawn by a single
## MultiMesh, so hundreds of pieces cost one draw call and no scene-tree
## overhead. Bodies are created once and pooled. Above a soft budget the
## oldest settled pieces shrink away over a second, so the pool rarely runs
## dry and nothing pops out of existence in front of the player.

## A big piece broke up on a hard landing.
signal piece_broke(at: Vector3, size: Vector3, kind: int, speed: float)

## A piece slower than this (m/s, rad/s) at two sweeps in a row is frozen;
## see _settle_still_pieces.
const QUIET_SPEED := 0.35
const QUIET_SPIN := 0.7
const QUIET_SWEEP := 0.2  ## seconds between sweeps
const FREEZE_CELL := 2.0  ## metres, grid for finding frozen pieces
## A piece moving at least this fast that suddenly loses most of its speed
## (a hard landing) breaks up; at most this many per frame.
const BREAK_SPEED := 7.0
const MAX_BREAKS_PER_FRAME := 6
const SHARD_SPIN_DAMP := 1.6
## Pieces smaller than this (m^3) do not break any further.
const MIN_BREAK_VOLUME := 0.03
## Faster than this, frozen rubble just ahead of a piece of at least
## PLOUGH_MIN_VOLUME (m^3) is thawed; smaller pieces just bounce off it.
const THAW_AHEAD_SPEED := 2.0
const PLOUGH_MIN_VOLUME := 0.06
const LAYER_WORLD := 1
const LAYER_STRUCTURES := 2
const LAYER_DEBRIS := 4
const LAYER_PLAYER := 8
const KILL_Y := -40.0
const FLOATS_PER_INSTANCE := 20  # 12 transform + 4 colour + 4 custom
const TINT_DECAY := 0.6  # violet glow fades per second
const FADE_TIME := 1.2  ## seconds a retired piece takes to shrink away
const RETIRE_PER_FRAME := 4

## Set before the scene loads to force a pool size (benchmarks).
static var capacity_override := 0

@export var capacity_desktop := 1500
@export var capacity_web := 900
@export var capacity_mobile := 700
## Pieces younger than this are never retired by the soft budget.
@export var retire_min_age := 6.0
## Shards at least this big (m^3) collide as their hull, smaller ones as a
## box of the same volume (hull contacts cost more in rubble piles).
## Negative: picked from the quality tier.
@export var hull_min_volume := -1.0
## Shards smaller than this (m^3) are not bodies at all: they become gravel.
@export var shard_min_volume := 0.004
## Seconds a piece may live; 0 keeps pieces until the budget recycles them.
@export var lifetime_desktop := 0.0
@export var lifetime_web := 240.0
@export var material: Material

var capacity := 0
var lifetime := 0.0
var active_count := 0
var frozen_count := 0
var chips: ChipSystem  ## where tiny shards go (set by the world)
## Fraction of capacity kept before the oldest pieces start shrinking away;
## lowered by the adaptive quality when the frame rate drops.
var soft_budget := 0.8
var awake_count := 0
var recycled_total := 0
var fading_count := 0

var _bodies: Array[RID] = []
var _speed := PackedFloat32Array()  ## last frame's speed, for hard landings
var _breaks_left := 0
var _shapes: Array[RID] = []
var _hulls: Array[RID] = []  ## convex hull shape per slot, made on first use
var _uses_hull := PackedByteArray()
var _render: Array[Basis] = []  ## unit mesh -> body space (scale, turn)
var _shard := PackedInt32Array()  ## shard shape drawn, -1 for a plain chunk
var _rid_to_index := {}
var _active := PackedByteArray()
var _sleeping := PackedByteArray()
var _size := PackedVector3Array()
var _pos := PackedVector3Array()
var _mass := PackedFloat32Array()
var _born := PackedFloat64Array()
var _tint := PackedFloat32Array()
var _storm := PackedByteArray()  ## 1 while spun by a black hole
var _quiet := PackedByteArray()  ## 1 if a piece was still at the last sweep
var _sweep := 0.0
var _frozen := PackedByteArray()  ## 1 while a resting piece is a static body
var _frozen_grid := {}  ## Vector3i -> PackedInt32Array (may hold stale entries)
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
	var low := Quality.tier() == Quality.Tier.LOW
	if capacity_override > 0:
		capacity = capacity_override
	elif capacity <= 0:
		capacity = int(Quality.pick(capacity_mobile, capacity_web, capacity_desktop))
	# Fewer, chunkier fragments per break on phones so the budget lasts.
	Fracture.quality = 0.6 if low else 1.0
	lifetime = lifetime_desktop if Quality.tier() == Quality.Tier.HIGH else lifetime_web
	if hull_min_volume < 0.0:
		hull_min_volume = tier_hull_min_volume()
	_space = get_world_3d().space
	_build_pool()


## Hull threshold for the quality tier. Phones collide every shard as a box
## (it still looks like a shard, and hulls cost them 20-30% more physics
## time); desktop browsers give hulls to the big chunks where the shape
## shows, native desktop to nearly every shard.
static func tier_hull_min_volume() -> float:
	return float(Quality.pick(INF, 0.15, 0.02))


func _exit_tree() -> void:
	for rid in _bodies:
		PhysicsServer3D.free_rid(rid)
	for rid in _shapes:
		PhysicsServer3D.free_rid(rid)
	for rid in _hulls:
		if rid.is_valid():
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
	_storm.resize(capacity)
	_storm.fill(0)
	_quiet.resize(capacity)
	_quiet.fill(0)
	_speed.resize(capacity)
	_speed.fill(0.0)
	_frozen.resize(capacity)
	_frozen.fill(0)
	_shade.resize(capacity)
	_kind.resize(capacity)
	_seed.resize(capacity)
	_fade.resize(capacity)
	_fade.fill(0.0)
	_render.resize(capacity)
	_render.fill(Basis.IDENTITY)
	_shard.resize(capacity)
	_shard.fill(-1)
	_uses_hull.resize(capacity)
	_uses_hull.fill(0)
	_hulls.resize(capacity)
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
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_colors = true
	_multimesh.use_custom_data = true  # same shader as blocks (crack slot)
	# Shards and plain chunks share one mesh: a subdivided cube whose
	# vertices the shader moves to the shard's shape (or cuts into a chunk).
	if ShardLibrary.ensure():
		_multimesh.mesh = ShardLibrary.mesh
		if material is ShaderMaterial:
			(material as ShaderMaterial).set_shader_parameter("shard_shapes", ShardLibrary.shapes)
	else:
		var box := BoxMesh.new()
		box.subdivide_width = 1
		box.subdivide_height = 1
		box.subdivide_depth = 1
		_multimesh.mesh = box
	_multimesh.instance_count = capacity
	_multimesh.visible_instance_count = 0
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
	_use_box(i, size)
	PhysicsServer3D.body_set_param(_bodies[i], PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP, 0.6)
	_render[i] = Basis.from_scale(size)
	_shard[i] = -1
	var mass := maxf(size.x * size.y * size.z * Materials.prop(kind, "density"), 0.5)
	_place(i, xform, size, mass, velocity, spin, tint, shade, kind, seed_value)
	return i


## Spawns shard `shard` (from ShardLibrary) of a block of `block_size` at
## `block`, with the pattern turned by `turn`. Big shards collide as their
## convex hull, small ones as a box.
func spawn_shard(
	block: Transform3D,
	block_size: Vector3,
	turn: Basis,
	shard: Dictionary,
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
	# Unit pattern space -> block space: turn, then stretch to the block.
	var to_block := Basis.from_scale(block_size) * turn
	var centre: Vector3 = to_block * (shard["center"] as Vector3)
	var size: Vector3 = (to_block * (shard["size"] as Vector3)).abs()
	var volume: float = shard["volume"] * block_size.x * block_size.y * block_size.z
	if volume >= hull_min_volume:
		var pts := PackedVector3Array()
		for p: Vector3 in shard["hull"]:
			pts.append(to_block * p * 0.98)
		_use_hull(i, pts)
	else:
		# A box of the same volume: the shard's own bounds would overlap its
		# neighbours and shove them apart.
		var fill := pow(clampf(volume / maxf(size.x * size.y * size.z, 1e-6), 0.05, 1.0), 1.0 / 3.0)
		_use_box(i, size * fill * 0.98)
	_render[i] = to_block * 0.995
	_shard[i] = shard["id"]
	# Irregular shards rock for ages on their edges: damp the spin a bit
	# more so they settle (and freeze) like real rubble.
	PhysicsServer3D.body_set_param(_bodies[i], PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP, SHARD_SPIN_DAMP)
	var basis := block.basis.orthonormalized()
	var xf := Transform3D(basis, block.origin + basis * centre)
	var mass := maxf(volume * Materials.prop(kind, "density"), 0.5)
	_place(i, xf, size, mass, velocity, spin, tint, shade, kind, seed_value)
	return i


## Breaks a block of `size` at `xf` into pieces: shards from the library
## when it has this material, boxes otherwise. Pieces fly away from `from`
## at `push` m/s on top of `inherit`. Returns the new indices.
func shatter_box(
	xf: Transform3D,
	size: Vector3,
	kind: int,
	from: Vector3,
	push: float,
	inherit: Vector3,
	tint: float,
	shade: float,
	seed_value: float,
	variant: int,
	volume := -1.0
) -> PackedInt32Array:
	var out := PackedInt32Array()
	# Piece count from the real volume (a shard is smaller than its bounds).
	var count_size := size
	if volume > 0.0:
		count_size = Vector3.ONE * pow(volume, 1.0 / 3.0)
	var count := Fracture.piece_count_for(count_size, Materials.prop(kind, "pieces"))
	var basis := xf.basis.orthonormalized()
	var block := Transform3D(basis, xf.origin)
	if count >= 2 and ShardLibrary.has(kind):
		# Wood and metal break along their grain (the longest axis).
		var grain := size.max_axis_index() if kind != Materials.Kind.CONCRETE else variant % 3
		var turn := ShardLibrary.axis_turn(grain, (variant / 3) % 2 == 1)
		var vol := size.x * size.y * size.z
		# Real shards read as more pieces than boxes did: one fewer is plenty
		# (and keeps the physics budget where it was).
		for shard: Dictionary in ShardLibrary.pattern(kind, maxi(count - 1, 2), variant):
			var centre: Vector3 = block * ((Basis.from_scale(size) * turn) * (shard["center"] as Vector3))
			if shard["volume"] * vol < shard_min_volume and chips:
				# Too small to be worth a body: gravel.
				chips.burst(centre, (shard["size"] as Vector3) * size, kind, 3, 2.0 + push, inherit)
				continue
			var away := (centre - from).normalized() if centre.distance_to(from) > 0.01 else Vector3.UP
			var spin := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 3.0
			var j := spawn_shard(
				block, size, turn, shard, away * push + inherit, spin, tint, shade, kind, seed_value
			)
			if j >= 0:
				out.append(j)
		return out
	var grain_axis := Fracture.grain_for(kind, size)
	for piece: AABB in Fracture.pattern(size, maxi(count, 1), variant % 4, grain_axis):
		var world := block * Transform3D(Basis(), piece.get_center())
		var away := (
			(world.origin - from).normalized() if world.origin.distance_to(from) > 0.01 else Vector3.UP
		)
		var spin := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 3.0
		var j := spawn(world, piece.size * 0.985, away * push + inherit, spin, tint, shade, kind, seed_value)
		if j >= 0:
			out.append(j)
	return out


func _use_box(i: int, size: Vector3) -> void:
	PhysicsServer3D.shape_set_data(_shapes[i], size * 0.5)
	if _uses_hull[i]:
		_uses_hull[i] = 0
		PhysicsServer3D.body_set_shape(_bodies[i], 0, _shapes[i])


func _use_hull(i: int, points: PackedVector3Array) -> void:
	if not _hulls[i].is_valid():
		_hulls[i] = PhysicsServer3D.convex_polygon_shape_create()
	PhysicsServer3D.shape_set_data(_hulls[i], points)
	if not _uses_hull[i]:
		_uses_hull[i] = 1
		PhysicsServer3D.body_set_shape(_bodies[i], 0, _hulls[i])


func _place(
	i: int,
	xform: Transform3D,
	size: Vector3,
	mass: float,
	velocity: Vector3,
	spin: Vector3,
	tint: float,
	shade: float,
	kind: int,
	seed_value: float
) -> void:
	set_storm(i, false)
	var body := _bodies[i]
	if _frozen[i]:
		_frozen[i] = 0
		frozen_count -= 1
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
	_quiet[i] = 0
	_speed[i] = velocity.length()
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
	if i >= _multimesh.visible_instance_count:
		_multimesh.visible_instance_count = i + 1


func despawn(i: int) -> void:
	if i < 0 or i >= capacity or not _active[i]:
		return
	PhysicsServer3D.body_set_space(_bodies[i], RID())
	_active[i] = 0
	active_count -= 1
	# What rested on it must be free to fall now.
	if frozen_count > 0:
		var r := _size[i].length() * 0.5 + 0.2
		var p := _pos[i]
		thaw_box(AABB(p - Vector3(r, r * 0.5, r), Vector3(r * 2.0, r * 1.5 + 0.6, r * 2.0)), 0.4)
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


## Pieces spun by a black hole pass through each other (a dense storm of
## colliding pieces costs far too much); they still hit everything else.
func set_storm(i: int, on: bool) -> void:
	var v := 1 if on else 0
	if _storm[i] == v:
		return
	_storm[i] = v
	var mask := LAYER_WORLD | LAYER_STRUCTURES | LAYER_PLAYER
	if not on:
		mask |= LAYER_DEBRIS
	PhysicsServer3D.body_set_collision_mask(_bodies[i], mask)
	# Sweeping hundreds of fast orbiting pieces every step is the other big
	# cost; inside the storm a piece may as well cut through a thin panel.
	PhysicsServer3D.body_set_enable_continuous_collision_detection(_bodies[i], not on)


func in_storm(i: int) -> bool:
	return _storm[i] == 1


## Real volume of piece `i` (a shard fills only part of its bounds).
## Library shard drawn for piece `i`, -1 for a plain chunk.
func shard_of(i: int) -> int:
	return _shard[i]


## True if piece `i` collides as its convex hull (else as a box).
func uses_hull(i: int) -> bool:
	return _uses_hull[i] == 1


func volume_of(i: int) -> float:
	return _mass[i] / Materials.prop(_kind[i], "density")


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
	thaw(i)
	var body := _bodies[i]
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, v)
	if _sleeping[i]:
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_SLEEPING, false)
		_sleeping[i] = 0


func add_spin(i: int, w: Vector3) -> void:
	thaw(i)
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
	var volume := volume_of(i)
	if size[size.min_axis_index()] < Fracture.MIN_EDGE * 2.0 or volume < MIN_BREAK_VOLUME:
		return out
	var xform := transform_of(i)
	var vel := velocity_of(i) + extra_velocity
	var tint := _tint[i]
	var shade := _shade[i]
	var seed_value := _seed[i]
	despawn(i)
	return shatter_box(xform, size, kind, xform.origin, 0.0, vel, tint, shade, seed_value, i, volume)


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
	var excess := active_count - fading_count - int(capacity * soft_budget)
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
	var last := -1
	var tint_step := TINT_DECAY * delta
	for i in capacity:
		if not _active[i]:
			continue
		last = i
		var body := _bodies[i]
		var asleep: bool = (
			_frozen[i] == 1 or PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_SLEEPING)
		)
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
		if not asleep and _storm[i] == 0:
			_check_landing(i, xform.origin)
	awake_count = awake
	# Free slots are handed out lowest first, so pieces sit at the start of
	# the pool: only draw up to the last one (each shard is 152 vertices).
	if last + 1 < _multimesh.visible_instance_count:
		_multimesh.visible_instance_count = last + 1
	_breaks_left = MAX_BREAKS_PER_FRAME
	_sweep += delta
	if _sweep >= QUIET_SWEEP:
		_sweep = 0.0
		_settle_still_pieces()
	_enforce_budget()
	if _buffer_dirty:
		_multimesh.buffer = _buffer
		_buffer_dirty = false


## A big piece that slams into something breaks up instead of bouncing
## whole; anything moving fast frees the frozen rubble just ahead of it so
## it pushes the pile around instead of stopping dead on it.
func _check_landing(i: int, at: Vector3) -> void:
	var v := velocity_of(i)
	var speed := v.length()
	var before := _speed[i]
	_speed[i] = speed
	if frozen_count > 0 and speed > THAW_AHEAD_SPEED and volume_of(i) >= PLOUGH_MIN_VOLUME:
		var r := _size[i][_size[i].max_axis_index()] * 0.6 + 0.2
		thaw_box(AABB(at + v * 0.1 - Vector3.ONE * r, Vector3.ONE * r * 2.0), 0.5)
	if before < BREAK_SPEED or speed > before * 0.45 or _clock - _born[i] < 0.15:
		return
	if _breaks_left <= 0 or volume_of(i) < MIN_BREAK_VOLUME:
		return
	_breaks_left -= 1
	var size := _size[i]
	var kind := _kind[i]
	if not fracture(i).is_empty():
		piece_broke.emit(at, size, kind, before)


## Rubble piles form one big island that the engine only puts to sleep when
## every piece in it is still, so a single jittering piece keeps hundreds of
## resting ones awake and costing time (putting them to sleep does not
## help: awake neighbours wake them right back). Every sweep, the pieces
## that were still at this sweep and the previous one are frozen instead.
func _settle_still_pieces() -> void:
	var still := PackedInt32Array()
	for i in capacity:
		if not _active[i] or _frozen[i] or _storm[i] or _fade[i] > 0.0:
			_quiet[i] = 0
			continue
		var body := _bodies[i]
		var lin: Vector3 = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
		var ang: Vector3 = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
		var quiet := (
			lin.length_squared() < QUIET_SPEED * QUIET_SPEED
			and ang.length_squared() < QUIET_SPIN * QUIET_SPIN
		)
		if quiet and _quiet[i]:
			still.append(i)
		_quiet[i] = 1 if quiet else 0
	for i in still:
		_freeze(i)


## Resting piece `i` becomes a static body: it costs (almost) nothing and
## cannot be woken by a jittering neighbour. Anything that should move it
## (powers, the player, what it rests on breaking) thaws it first.
func _freeze(i: int) -> void:
	if _frozen[i]:
		return
	_frozen[i] = 1
	frozen_count += 1
	_sleeping[i] = 1
	_quiet[i] = 0
	PhysicsServer3D.body_set_mode(_bodies[i], PhysicsServer3D.BODY_MODE_STATIC)
	var key := Vector3i((_pos[i] / FREEZE_CELL).floor())
	if not _frozen_grid.has(key):
		_frozen_grid[key] = PackedInt32Array()
	_frozen_grid[key].append(i)


## Makes piece `i` a normal falling body again.
func thaw(i: int) -> void:
	if not _frozen[i]:
		return
	_frozen[i] = 0
	frozen_count -= 1
	var body := _bodies[i]
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_MASS, _mass[i])
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_SLEEPING, false)
	_sleeping[i] = 0


## Active pieces whose centre is inside `box`.
func pieces_in(box: AABB) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in capacity:
		if _active[i] and box.has_point(_pos[i]):
			out.append(i)
	return out


func is_frozen(i: int) -> bool:
	return _frozen[i] == 1


## Thaws every frozen piece within `radius` of `p`.
func thaw_near(p: Vector3, radius: float) -> void:
	thaw_box(AABB(p - Vector3.ONE * radius, Vector3.ONE * radius * 2.0))


## Thaws every frozen piece whose centre is inside `box` grown by `margin`
## (metres; pieces reach past their centre).
func thaw_box(box: AABB, margin := 1.0) -> void:
	if frozen_count == 0:
		return
	var grown := box.grow(margin)
	var lo := Vector3i((grown.position / FREEZE_CELL).floor())
	var hi := Vector3i((grown.end / FREEZE_CELL).floor())
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for z in range(lo.z, hi.z + 1):
				var key := Vector3i(x, y, z)
				var cell: Variant = _frozen_grid.get(key)
				if cell == null:
					continue
				var keep := PackedInt32Array()
				for i: int in cell:
					if not _active[i] or not _frozen[i]:
						continue  # stale entry
					if grown.has_point(_pos[i]):
						thaw(i)
					else:
						keep.append(i)
				if keep.is_empty():
					_frozen_grid.erase(key)
				else:
					_frozen_grid[key] = keep


func _write_instance(i: int, xform: Transform3D) -> void:
	var k := 1.0
	if _fade[i] > 0.0:
		var f := clampf(_fade[i] / FADE_TIME, 0.0, 1.0)
		k = f * f * (3.0 - 2.0 * f)
	# Unit mesh -> body (scale and pattern turn) -> world.
	var b := xform.basis * _render[i] * k
	var o := i * FLOATS_PER_INSTANCE
	_buffer[o + 0] = b.x.x
	_buffer[o + 1] = b.y.x
	_buffer[o + 2] = b.z.x
	_buffer[o + 3] = xform.origin.x
	_buffer[o + 4] = b.x.y
	_buffer[o + 5] = b.y.y
	_buffer[o + 6] = b.z.y
	_buffer[o + 7] = xform.origin.y
	_buffer[o + 8] = b.x.z
	_buffer[o + 9] = b.y.z
	_buffer[o + 10] = b.z.z
	_buffer[o + 11] = xform.origin.z
	_buffer[o + 12] = _shade[i]
	_buffer[o + 13] = Materials.encode(_kind[i])
	_buffer[o + 14] = _seed[i]
	_buffer[o + 15] = _tint[i]
	_buffer[o + 16] = Materials.custom(_kind[i], 0.0)
	_buffer[o + 17] = float(_shard[i] + 1)  # 0 = plain chunk
	_buffer_dirty = true
