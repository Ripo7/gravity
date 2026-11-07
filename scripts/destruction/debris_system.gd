class_name DebrisSystem
extends Node3D
## Every loose piece in the world: fragments and dislodged blocks.
##
## Pieces are raw PhysicsServer3D bodies (no nodes) drawn by a single
## MultiMesh, so hundreds of pieces cost one draw call and no scene-tree
## overhead. Bodies are created once and pooled. Above a soft budget the
## pieces out of sight go first and the smallest looking ones shrink away
## over a second; when the pool runs dry anyway, the piece the player would
## miss least makes room. Nothing pops out of existence in front of them,
## and nothing that broke is lost: what leaves the pool, and what is too
## small to be a piece, ends up on the rubble heaps (RubbleField).

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
## The rubble heaps (RubbleField): pieces and the player stand on them, a
## falling piece of building ploughs into them.
const LAYER_RUBBLE := 16
const KILL_Y := -40.0
const FLOATS_PER_INSTANCE := 20  # 12 transform + 4 colour + 4 custom
const TINT_DECAY := 0.6  # violet glow fades per second
const FADE_TIME := 1.2  ## seconds a retired piece takes to shrink away
const RETIRE_PER_FRAME := 4
## A shard splitting along its own cracks pushes its pieces apart this fast.
const SPLIT_PUSH := 0.3
## Average volume (m^3) of a gravel chip or a grain: how many a small piece
## turns into.
const CHIP_VOLUME := 0.0013
## A piece with no sub-shards left and smaller than this (m^3) crumbles into
## gravel (grains in a black hole) when it breaks.
const CRUMBLE_VOLUME := 0.08
## When the pool is full and nothing in it is out of sight, fragments
## smaller than this (m^3) become gravel instead of pushing a piece the
## player can see out of it.
const FULL_POOL_GRAVEL := 0.15
## A break leaves no piece longer than this (m): long and big blocks first
## part into chunks, each of which breaks along a pattern.
const CHUNK_SIDE := 1.4
## Big pieces break on softer landings: the speed that breaks a piece of
## v m^3 is BREAK_SPEED * (BREAK_VOLUME / v)^(1/3), down to BREAK_SPEED_MIN.
const BREAK_VOLUME := 0.15
const BREAK_SPEED_MIN := 3.2
## A piece can leave the pool unnoticed when it is off screen or looks
## smaller than this (its radius over its distance: about 2 px on a phone).
const UNSEEN := 0.006
## Seconds between two rankings of the pieces to give up (see _rank_spare).
const RANK_EVERY := 0.1
## Above the soft budget, at most this many unseen pieces go per frame.
const DROP_PER_FRAME := 24
## A break leaves at least one body for a block this big (m^3), even when
## that means taking the least visible piece out of the pool.
const KEEP_ONE_VOLUME := 0.05
const _SLOT_BITS := 20
const _SEEN_SCALE := 100000.0

## Set before the scene loads to force a pool size (benchmarks).
static var capacity_override := 0

@export var capacity_desktop := 1500
@export var capacity_web := 900
@export var capacity_mobile := 500
## Pieces younger than this are never retired by the soft budget.
@export var retire_min_age := 6.0
## Shards at least this big (m^3) collide as their hull, smaller ones as a
## box of the same volume (hull contacts cost more in rubble piles).
## Negative: picked from the quality tier.
@export var hull_min_volume := -1.0
## Shards smaller than this (m^3) are not bodies at all: they become gravel.
@export var shard_min_volume := 0.012
## Seconds a piece may live; 0 keeps pieces until the budget recycles them.
@export var lifetime_desktop := 0.0
@export var lifetime_web := 240.0
@export var material: Material

var capacity := 0
## A shard landing hard splits into its sub-shards; on phones and in
## browsers only the biggest few stay bodies, the rest is gravel (0 = all).
var landing_keep := 0
## Biggest piece (m^3) a break aims for, and most bodies one break leaves
## (the smaller rest is gravel): phones keep fewer, bigger pieces.
var max_piece := 0.3
var max_bodies := 8
var lifetime := 0.0
## Pieces the player could see that the full pool had to take back: they
## crumble into gravel (nothing just vanishes).
var crumbled_in_view := 0
var active_count := 0
var frozen_count := 0
var chips: ChipSystem  ## where tiny shards go (set by the world)
var rubble: RubbleField  ## where what leaves the pool piles up (set by the world)
## Fraction of capacity kept before the oldest pieces start shrinking away;
## lowered by the adaptive quality when the frame rate drops.
var soft_budget := 0.8
var awake_count := 0
var recycled_total := 0
var fading_count := 0

var _bodies: Array[RID] = []
var _speed := PackedFloat32Array()  ## last frame's speed, for hard landings
var _last_vel := PackedVector3Array()  ## velocity one physics step ago
var _breaks_left := 0
var _shapes: Array[RID] = []
var _hulls: Array[RID] = []  ## convex hull shape per slot, made on first use
var _uses_hull := PackedByteArray()
var _render: Array[Basis] = []  ## unit mesh -> body space (scale, turn)
var _shard := PackedInt32Array()  ## shard shape drawn, -1 for a plain chunk
var _bsize := PackedVector3Array()  ## size of the block a shard's pattern spans
var _turn: Array[Basis] = []  ## how that pattern was turned (see ShardLibrary)
var _storm_since := PackedFloat32Array()  ## clock when the black hole caught it
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
var _quiet_speed := QUIET_SPEED
var _quiet_spin := QUIET_SPIN
## Pieces ranked least visible first: (young << 50 | look << 20 | slot).
var _spare := PackedInt64Array()
var _spare_next := 0
var _spare_clock := -INF
var _serial := PackedInt32Array()  ## bumped each time a slot gets a new piece
var _ranked := PackedInt32Array()  ## a slot's serial when it was ranked
var _eye := Vector3.ZERO
var _ahead := Vector3.FORWARD
var _cone := -2.0  ## cos of the view's half diagonal; < -1 with no camera


func _ready() -> void:
	var low := Quality.tier() == Quality.Tier.LOW
	if capacity_override > 0:
		capacity = capacity_override
	elif capacity <= 0:
		capacity = int(Quality.pick(capacity_mobile, capacity_web, capacity_desktop))
	# Fewer, chunkier fragments per break on phones so the budget lasts.
	Fracture.quality = 0.6 if low else 1.0
	# Phones call rubble still a little sooner.
	_quiet_speed = QUIET_SPEED * (1.7 if low else 1.0)
	_quiet_spin = QUIET_SPIN * (1.7 if low else 1.0)
	Fracture.max_pieces = int(Quality.pick(3, 4, 6))
	landing_keep = int(Quality.pick(2, 3, 0))
	max_piece = float(Quality.pick(0.45, 0.3, 0.2))
	max_bodies = int(Quality.pick(4, 7, 10))
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
	_serial.resize(capacity)
	_serial.fill(0)
	_ranked.resize(capacity)
	_ranked.fill(-1)
	_tint.resize(capacity)
	_storm.resize(capacity)
	_storm.fill(0)
	_quiet.resize(capacity)
	_quiet.fill(0)
	_speed.resize(capacity)
	_speed.fill(0.0)
	_last_vel.resize(capacity)
	_last_vel.fill(Vector3.ZERO)
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
	_bsize.resize(capacity)
	_turn.resize(capacity)
	_turn.fill(Basis.IDENTITY)
	_storm_since.resize(capacity)
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
			body, LAYER_WORLD | LAYER_STRUCTURES | LAYER_DEBRIS | LAYER_PLAYER | LAYER_RUBBLE
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
			(material as ShaderMaterial).set_shader_parameter("shard_centers", ShardLibrary.centers)
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
	_bsize[i] = block_size
	_turn[i] = turn
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
## at `push` m/s on top of `inherit`. At most `keep` (else max_bodies) of
## the biggest pieces stay bodies, the rest is gravel. Returns the new
## indices.
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
	keep := 0
) -> PackedInt32Array:
	var out := PackedInt32Array()
	var basis := xf.basis.orthonormalized()
	var block := Transform3D(basis, xf.origin)
	if ShardLibrary.has(kind):
		var look := [tint, shade, seed_value]
		return _shatter_chunks(block, size, kind, from, push, inherit, look, variant, keep)
	var count := Fracture.piece_count_for(size, Materials.prop(kind, "pieces"))
	var grain_axis := Fracture.grain_for(kind, size)
	for piece: AABB in Fracture.pattern(size, maxi(count, 1), variant % 4, grain_axis):
		var world := block * Transform3D(Basis(), piece.get_center())
		var away := (
			(world.origin - from).normalized() if world.origin.distance_to(from) > 0.01 else Vector3.UP
		)
		var spin := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 3.0
		var j := -1
		if piece.get_volume() >= FULL_POOL_GRAVEL or room(1) > 0:
			j = spawn(world, piece.size * 0.985, away * push + inherit, spin, tint, shade, kind, seed_value)
		if j >= 0:
			out.append(j)
		else:
			gravel(world.origin, piece.size, kind, piece.get_volume(), 2.0 + push, inherit, seed_value)
	return out


## Breaks a block along library patterns. A big or long block first parts
## into chunks (see _chunks), so no break leaves a slab or a beam whole;
## each chunk breaks along a pattern. The biggest pieces (at most `keep`, else
## max_bodies) become bodies; the rest of each chunk crumbles to gravel.
## `look` = [tint, shade, seed].
func _shatter_chunks(
	block: Transform3D,
	size: Vector3,
	kind: int,
	from: Vector3,
	push: float,
	inherit: Vector3,
	look: Array,
	variant: int,
	keep: int
) -> PackedInt32Array:
	var out := PackedInt32Array()
	var tint: float = look[0]
	var shade: float = look[1]
	var seed_value: float = look[2]
	var chunks := _chunks(size, variant)
	var vols := PackedFloat32Array()
	var where := PackedInt32Array()  # chunk of each piece
	var shards: Array[Dictionary] = []
	var turns: Array[Basis] = []
	for k in chunks.size():
		var cv := chunks[k].get_volume()
		# Wood and metal break along their grain (the chunk's longest axis).
		var v := variant + k
		var grain := chunks[k].size.max_axis_index() if kind != Materials.Kind.CONCRETE else v % 3
		var turn := ShardLibrary.axis_turn(grain, (v / 3) % 2 == 1)
		for shard: Dictionary in ShardLibrary.pattern(kind, clampi(roundi(cv / max_piece), 2, 4), v):
			vols.append(float(shard["volume"]) * cv)
			where.append(k)
			shards.append(shard)
			turns.append(turn)
	# The biggest pieces become bodies, never more than the pool can spare
	# unseen; a big block always leaves one (the least visible piece goes).
	var bodies := room(keep if keep > 0 else max_bodies)
	if bodies == 0 and size.x * size.y * size.z >= KEEP_ONE_VOLUME:
		bodies = 1
	var least := INF
	if bodies > 0:
		var sorted := vols.duplicate()
		sorted.sort()
		least = maxf(sorted[maxi(sorted.size() - bodies, 0)], shard_min_volume)
	# What does not become a body crumbles: one burst of gravel per third of
	# the block (along its length).
	var axis := size.max_axis_index()
	var leftover := PackedFloat32Array([0.0, 0.0, 0.0])
	var spots: Array[AABB] = [AABB(), AABB(), AABB()]
	for p in vols.size():
		var c := chunks[where[p]]
		if bodies > 0 and vols[p] >= least:
			var chunk := block * Transform3D(Basis(), c.get_center())
			var centre: Vector3 = (
				chunk * ((Basis.from_scale(c.size) * turns[p]) * (shards[p]["center"] as Vector3))
			)
			var away := (centre - from).normalized() if centre.distance_to(from) > 0.01 else Vector3.UP
			var spin := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 3.0
			var j := spawn_shard(
				chunk, c.size, turns[p], shards[p], away * push + inherit, spin, tint, shade, kind, seed_value
			)
			if j >= 0:
				out.append(j)
				bodies -= 1
				continue
		var third := clampi(int((c.get_center()[axis] / size[axis] + 0.5) * 3.0), 0, 2)
		spots[third] = c if leftover[third] == 0.0 else spots[third].merge(c)
		leftover[third] += vols[p]
	for t in 3:
		if leftover[t] > 0.0:
			var at := block * spots[t].get_center()
			gravel(at, spots[t].size, kind, leftover[t], 2.0 + push, inherit, seed_value)
	return out


## A block of `size` cut into boxes (centred on it) none longer than
## CHUNK_SIDE nor bigger than a few max_piece: each box is split across its
## longest side, a little off the middle, until it is small enough.
func _chunks(size: Vector3, variant: int) -> Array[AABB]:
	var rng := RandomNumberGenerator.new()
	rng.seed = variant * 7919 + 17
	var most := max_piece * 2.5
	var boxes: Array[AABB] = [AABB(-size * 0.5, size)]
	var k := 0
	while k < boxes.size() and boxes.size() < 40:
		var b := boxes[k]
		var axis := b.size.max_axis_index()
		if b.size[axis] <= CHUNK_SIDE and b.get_volume() <= most:
			k += 1
			continue
		var cut := b.size[axis] * rng.randf_range(0.35, 0.65)
		var rest := b
		b.size[axis] = cut
		rest.position[axis] += cut
		rest.size[axis] -= cut
		boxes[k] = b
		boxes.append(rest)
	return boxes


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
	_last_vel[i] = velocity
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
	_serial[i] += 1
	_tint[i] = tint
	_shade[i] = shade
	_kind[i] = kind
	_seed[i] = seed_value if seed_value >= 0.0 else randf()
	_fade[i] = 0.0
	active_count += 1
	_write_instance(i, clean)
	if i >= _multimesh.visible_instance_count:
		_multimesh.visible_instance_count = i + 1


## Takes piece `i` out of the pool; what rested on it is woken (unless
## `wake` is false: it was buried under the rubble heap, so was all round it).
func despawn(i: int, wake := true) -> void:
	if i < 0 or i >= capacity or not _active[i]:
		return
	PhysicsServer3D.body_set_space(_bodies[i], RID())
	_active[i] = 0
	active_count -= 1
	if _frozen[i]:
		_frozen[i] = 0
		frozen_count -= 1
		PhysicsServer3D.body_set_mode(_bodies[i], PhysicsServer3D.BODY_MODE_RIGID)
	# What rested on it must be free to fall now.
	if frozen_count > 0 and wake:
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
	# Kept highest first so pop_back() hands out the lowest free slot: live
	# pieces stay packed at the start and only they are drawn.
	_free.insert(_free.bsearch_custom(i, func(a: int, b: int) -> bool: return a > b), i)


func clear() -> void:
	for i in capacity:
		despawn(i)


## Starts shrinking piece `i` away; it is freed when the shrink ends.
func retire(i: int) -> void:
	if is_active(i) and _fade[i] <= 0.0:
		_fade[i] = FADE_TIME
		fading_count += 1


## True for a piece lying still (asleep, or frozen into the rubble).
func is_resting(i: int) -> bool:
	return _active[i] == 1 and (_frozen[i] == 1 or _sleeping[i] == 1)


func is_active(i: int) -> bool:
	return i >= 0 and i < capacity and _active[i] == 1


func rid_of(i: int) -> RID:
	return _bodies[i]


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
	if on:
		_storm_since[i] = _clock
	var mask := LAYER_WORLD | LAYER_STRUCTURES | LAYER_PLAYER | LAYER_RUBBLE
	if not on:
		mask |= LAYER_DEBRIS
	PhysicsServer3D.body_set_collision_mask(_bodies[i], mask)
	# Sweeping hundreds of fast orbiting pieces every step is the other big
	# cost; inside the storm a piece may as well cut through a thin panel.
	PhysicsServer3D.body_set_enable_continuous_collision_detection(_bodies[i], not on)


func in_storm(i: int) -> bool:
	return _storm[i] == 1


## Seconds piece `i` has been spinning in a black hole (0 if it is not).
func storm_age(i: int) -> float:
	return _clock - _storm_since[i] if _storm[i] == 1 else 0.0


## Finish and random seed a piece carries (the look of what it broke from).
func seed_of(i: int) -> float:
	return _seed[i]


func shade_of(i: int) -> float:
	return _shade[i]


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


## The faster of its velocity now and one physics step ago: a piece stopped
## dead by what it hit (the player, a shield) still counts at the speed it
## came in at.
func recent_velocity_of(i: int) -> Vector3:
	var now := velocity_of(i)
	return _last_vel[i] if _last_vel[i].length_squared() > now.length_squared() else now


## One past the highest slot in use (loops over live pieces stop here).
func slot_end() -> int:
	return _multimesh.visible_instance_count


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


func tint_of(i: int) -> float:
	return _tint[i]


func set_tint(i: int, t: float) -> void:
	_tint[i] = maxf(_tint[i], t)


## Breaks piece `i` into smaller pieces. Returns the new indices. A shard
## with sub-shards splits along the cracks already inside it; anything else
## is broken with a fresh pattern stretched to its bounds.
## With `keep` > 0 only that many of the biggest pieces stay bodies and the
## rest turns to gravel (or grains): grinding chips bits off a piece.
func fracture(i: int, extra_velocity := Vector3.ZERO, keep := 0) -> PackedInt32Array:
	var out := PackedInt32Array()
	if not is_active(i):
		return out
	if _shard[i] >= 0:
		var kids := ShardLibrary.children_of(_shard[i])
		if not kids.is_empty():
			return _split_shard(i, kids, extra_velocity, keep)
	var size := _size[i]
	var kind := _kind[i]
	var volume := volume_of(i)
	var xform := transform_of(i)
	var vel := velocity_of(i) + extra_velocity
	if volume < CRUMBLE_VOLUME:
		# Nothing left to split along: it crumbles.
		var seed_value := _seed[i]
		despawn(i)
		gravel(xform.origin, size, kind, volume, 2.0, vel, seed_value)
		return out
	if size[size.min_axis_index()] < Fracture.MIN_EDGE * 2.0:
		return out
	var tint := _tint[i]
	var shade := _shade[i]
	var piece_seed := _seed[i]
	despawn(i)
	# A fresh pattern spans a box of the piece's own volume (its bounds would
	# make more matter than there was).
	var fit := size * pow(clampf(volume / maxf(size.x * size.y * size.z, 1e-6), 0.05, 1.0), 1.0 / 3.0)
	return shatter_box(xform, fit, kind, xform.origin, 0.0, vel, tint, shade, piece_seed, i, keep)


## Splits shard `i` into its sub-shards, each exactly where it sat inside it,
## moving with it (spin included) and pushed a little apart.
func _split_shard(i: int, kids: Array, extra: Vector3, keep := 0) -> PackedInt32Array:
	var out := PackedInt32Array()
	var xf := transform_of(i)
	var basis := xf.basis.orthonormalized()
	var parent := ShardLibrary.shard(_shard[i])
	var bsize := _bsize[i]
	var turn := _turn[i]
	var to_block := Basis.from_scale(bsize) * turn
	# The block the pattern was cut from: shard centres are relative to it.
	var block := Transform3D(basis, xf.origin - basis * (to_block * (parent["center"] as Vector3)))
	var v := velocity_of(i) + extra
	var w: Vector3 = PhysicsServer3D.body_get_state(_bodies[i], PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
	var tint := _tint[i]
	var shade := _shade[i]
	var kind := _kind[i]
	var seed_value := _seed[i]
	var block_vol := bsize.x * bsize.y * bsize.z
	var min_body := shard_min_volume
	if keep > 0 and keep < kids.size():
		var vols: Array[float] = []
		for kid: Dictionary in kids:
			vols.append(kid["volume"] * block_vol)
		vols.sort()
		min_body = maxf(min_body, vols[vols.size() - keep])
	despawn(i)
	for kid: Dictionary in kids:
		var centre := block * (to_block * (kid["center"] as Vector3))
		var r := centre - xf.origin
		var away := r.normalized() if r.length() > 0.01 else Vector3.UP
		var kv := v + w.cross(r) + away * SPLIT_PUSH * randf_range(0.5, 1.2)
		var vol: float = kid["volume"] * block_vol
		var j := -1
		if vol >= min_body and (vol >= FULL_POOL_GRAVEL or room(1) > 0):
			var spin := w * 0.8 + Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5)
			j = spawn_shard(block, bsize, turn, kid, kv, spin, tint, shade, kind, seed_value)
		if j >= 0:
			out.append(j)
			continue
		var kid_size := (to_block * (kid["size"] as Vector3)).abs()
		gravel(centre, kid_size, kind, vol, SPLIT_PUSH * 2.0, kv, seed_value)
	return out


## A piece too small to be a body: grains of a black hole's cloud when one
## spins here, gravel chips otherwise (a few, bigger for a big lot), which
## take it all along and leave it on the rubble heap where they land.
func gravel(
	at: Vector3, size: Vector3, kind: int, volume: float, speed: float, kick: Vector3, seed_value: float
) -> void:
	var count := clampi(int(round(volume / CHIP_VOLUME)), 2, 14)
	var cloud := GrainCloud.find(get_tree(), at) if is_inside_tree() else null
	if cloud:
		cloud.add(at, size, kind, seed_value, count * 3, volume)
	elif chips:
		# The rubble of a big break: bigger stones, not just more gravel.
		# The chips take all of it to the heap (they only last a while).
		var scale := clampf(pow(volume / (count * CHIP_VOLUME), 1.0 / 3.0), 1.0, 2.0)
		chips.burst(at, size, kind, count, speed, kick, seed_value, scale, volume)
	elif rubble:
		rubble.deposit(at, volume, RubbleField.color_of(kind, seed_value))


## Piece `i` leaves the pool for the rubble heap under it: all of it, even
## when it has shrunk away (it went into the heap). `wake`: see despawn.
func bury(i: int, wake := true) -> void:
	if not is_active(i):
		return
	if rubble:
		rubble.deposit(_pos[i], volume_of(i), RubbleField.color_of(_kind[i], _seed[i]))
	despawn(i, wake)


## How many new pieces (up to `want`) the pool can take right now without
## anything vanishing in view: free slots, then pieces nobody can see.
func room(want: int) -> int:
	if _free.size() >= want:
		return want
	_rank_spare()
	var n := _free.size()
	for k in range(_spare_next, _spare.size()):
		if n >= want or not _unseen(_spare[k]):
			break  # ranked: everything after it can be seen
		if _still_ranked(_spare[k]):
			n += 1
	return n


## A free slot; when the pool is full, the piece the player would miss least
## leaves it: off screen (or not drawn yet) it just goes, else the smallest
## looking one crumbles into gravel.
func _take_slot() -> int:
	if not _free.is_empty():
		return _free.pop_back()
	_rank_spare()
	for _attempt in 2:
		while _spare_next < _spare.size():
			var key := _spare[_spare_next]
			_spare_next += 1
			if not _still_ranked(key):
				continue
			var i := int(key & ((1 << _SLOT_BITS) - 1))
			if _unseen(key) or _born[i] >= _clock:
				bury(i)  # nobody saw it (out of sight, or not drawn yet)
			else:
				_crumble(i)
			recycled_total += 1
			return _free.pop_back()
		_rank_spare(true)  # all used up within the frame: rank again
	return -1


## Piece `i`, which the player may see, leaves the pool by crumbling into
## gravel where it is (all of it: a piece shrinking away goes to the heap).
func _crumble(i: int) -> void:
	crumbled_in_view += 1
	var left := _fade[i] / FADE_TIME if _fade[i] > 0.0 else 1.0
	var at := transform_of(i).origin
	var kick := velocity_of(i)
	var vol := volume_of(i)
	var size := _size[i] * left
	var seed_value := _seed[i]
	var kind := _kind[i]
	despawn(i)
	gravel(at, size, kind, vol, 1.0, kick, seed_value)


## The ranked piece is still the one in its slot (not freed or replaced).
func _still_ranked(key: int) -> bool:
	var i := int(key & ((1 << _SLOT_BITS) - 1))
	return _active[i] == 1 and _serial[i] == _ranked[i]


## Ranks the live pieces from least to most visible: off screen first, then
## the smallest on screen (a shrinking one by what is left of it), pieces
## born in the last half second last. At most every RANK_EVERY seconds.
func _rank_spare(now := false) -> void:
	if not now and _clock - _spare_clock < RANK_EVERY:
		return
	_spare_clock = _clock
	_spare_next = 0
	_spare.clear()
	_look()
	for i in capacity:
		if not _active[i]:
			continue
		var look := _looks(i)
		if _fade[i] > 0.0:
			look *= _fade[i] / FADE_TIME
		var young := 1 if _clock - _born[i] < 0.5 else 0
		_spare.append((young << 50) | (mini(int(look * _SEEN_SCALE), (1 << 29) - 1) << _SLOT_BITS) | i)
		_ranked[i] = _serial[i]
	_spare.sort()


## Where the camera is and how wide it sees, for _looks.
func _look() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		_cone = -2.0
		return
	_eye = cam.global_position
	_ahead = -cam.global_basis.z
	var view := get_viewport().get_visible_rect().size
	var aspect := view.x / maxf(view.y, 1.0)
	var t := tan(deg_to_rad(cam.fov) * 0.5)
	var tall := t if cam.keep_aspect == Camera3D.KEEP_HEIGHT else t / aspect
	var wide := tall * aspect
	_cone = cos(atan(sqrt(tall * tall + wide * wide)) + 0.1)


## How big piece `i` looks: its radius over its distance, 0 off screen.
func _looks(i: int) -> float:
	var r := _size[i].length() * 0.5
	if _cone < -1.0:
		return r * 0.1  # no camera: by size alone
	var d := _pos[i] - _eye
	var dist := d.length()
	if dist <= r:
		return 10.0
	if d.dot(_ahead) < dist * _cone - r:
		return 0.0
	return r / dist


func _unseen(key: int) -> bool:
	return key >> 50 == 0 and (key >> _SLOT_BITS) & ((1 << 30) - 1) < int(UNSEEN * _SEEN_SCALE)


## Above the soft budget: pieces nobody can see go at once (a few dozen per
## frame), visible ones shrink away, the smallest looking first. Nothing
## younger than retire_min_age (a second if unseen) goes; INF turns the
## budget off (benchmarks).
func _enforce_budget() -> void:
	var excess := active_count - fading_count - int(capacity * soft_budget)
	if excess <= 0 or retire_min_age == INF:
		return
	_rank_spare()
	var dropped := 0
	var faded := 0
	var drop_age := minf(retire_min_age, 1.0)
	for k in range(_spare_next, _spare.size()):
		if dropped + faded >= excess or faded >= RETIRE_PER_FRAME:
			break
		var key := _spare[k]
		var i := int(key & ((1 << _SLOT_BITS) - 1))
		if not _still_ranked(key) or _fade[i] > 0.0 or _tint[i] > 0.0:
			continue
		var age := _clock - _born[i]
		if _unseen(key):
			if age >= drop_age:
				bury(i)
				dropped += 1
				if dropped >= DROP_PER_FRAME:
					break  # the rest next frame, before anything in view
		elif age >= retire_min_age:
			retire(i)
			faded += 1


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
				bury(i)
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
	_last_vel[i] = v
	if frozen_count > 0 and speed > THAW_AHEAD_SPEED and volume_of(i) >= PLOUGH_MIN_VOLUME:
		var r := _size[i][_size[i].max_axis_index()] * 0.6 + 0.2
		thaw_box(AABB(at + v * 0.1 - Vector3.ONE * r, Vector3.ONE * r * 2.0), 0.5)
	var volume := volume_of(i)
	var needed := maxf(BREAK_SPEED * pow(BREAK_VOLUME / maxf(volume, 1e-4), 1.0 / 3.0), BREAK_SPEED_MIN)
	if before < minf(needed, BREAK_SPEED) or speed > before * 0.45 or _clock - _born[i] < 0.15:
		return
	if _breaks_left <= 0 or volume < MIN_BREAK_VOLUME:
		return
	_breaks_left -= 1
	var size := _size[i]
	var kind := _kind[i]
	if not fracture(i, Vector3.ZERO, landing_keep).is_empty():
		piece_broke.emit(at, size, kind, before)


## Rubble piles form one big island that the engine only puts to sleep when
## every piece in it is still, so a single jittering piece keeps hundreds of
## resting ones awake and costing time (putting them to sleep does not
## help: awake neighbours wake them right back). Every sweep, the pieces
## that were still at this sweep and the previous one are frozen instead.
## A loose piece the rubble heap has grown over (all of it under the heap's
## surface) joins the heap.
func _settle_still_pieces() -> void:
	var still := PackedInt32Array()
	var heap := rubble != null and rubble.volume > 0.0
	for i in capacity:
		if not _active[i] or _frozen[i] or _storm[i] or _fade[i] > 0.0:
			_quiet[i] = 0
			continue
		if heap and _pos[i].y + _size[i].length() * 0.5 < rubble.height_at(_pos[i]):
			bury(i, false)
			continue
		var body := _bodies[i]
		var lin: Vector3 = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
		var ang: Vector3 = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
		var quiet := (
			lin.length_squared() < _quiet_speed * _quiet_speed
			and ang.length_squared() < _quiet_spin * _quiet_spin
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
	_buffer[o + 14] = fposmod(_seed[i], 1.0)
	_buffer[o + 15] = _tint[i]
	_buffer[o + 16] = Materials.custom(_kind[i], 0.0, _seed[i])
	_buffer[o + 17] = float(_shard[i] + 1)  # 0 = plain chunk
	_buffer_dirty = true
