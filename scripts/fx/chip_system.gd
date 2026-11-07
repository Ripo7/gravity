class_name ChipSystem
extends Node3D
## Gravel and splinters: hundreds of tiny irregular chips per collapse with
## no physics bodies at all. Each chip flies on a simple arc, bounces once
## on the surface below the break, then lies there for a long while (the
## gravel on the rubble). When the pool fills up, the oldest resting chips
## shrink away; a chip in flight is never taken back (a burst that finds no
## room is just smaller). A burst can carry more broken material than its
## chips show: each chip takes its share along and leaves it on the rubble
## heap where it lands (see RubbleField). Only flying chips cost anything
## per frame; one draw call for all of them.

const GRAVITY := 18.0
const FADE := 0.8
## Seconds between lifetime checks (resting chips only change then).
const LIFE_TICK := 0.25
const FLOATS := 20  # same instance layout as the debris (block shader)
## Above this share of the pool in use, the oldest resting chips fade out.
const SOFT_BUDGET := 0.75

var capacity := 0
var active := 0
var rubble: RubbleField  ## where carried material is left (set by the world)
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _size := PackedVector3Array()
var _axis := PackedVector3Array()
var _angle := PackedFloat32Array()
var _spin := PackedFloat32Array()
var _floor := PackedFloat32Array()
var _life := PackedFloat32Array()
var _origin := PackedVector3Array()  # where the burst came from
var _carry := PackedFloat32Array()  ## m^3 of rubble a chip leaves where it lands
var _carry_color := PackedColorArray()
var _state := PackedByteArray()  # 0 free, 1 flying, 2 bounced, 3 resting
var _flying := PackedInt32Array()
var _free := PackedInt32Array()
var _rested := PackedInt32Array()  ## resting chips, oldest first (some stale)
var _rested_head := 0
var _life_tick := 0.0
var _buffer := PackedFloat32Array()
var _dirty := false
var _multimesh: MultiMesh


func _ready() -> void:
	capacity = Quality.pick(500, 1400, 2600)
	_pos.resize(capacity)
	_vel.resize(capacity)
	_size.resize(capacity)
	_axis.resize(capacity)
	_angle.resize(capacity)
	_spin.resize(capacity)
	_floor.resize(capacity)
	_life.resize(capacity)
	_origin.resize(capacity)
	_carry.resize(capacity)
	_carry.fill(0.0)
	_carry_color.resize(capacity)
	_state.resize(capacity)
	_state.fill(0)
	_free.resize(capacity)
	for k in capacity:
		_free[k] = capacity - 1 - k
	_buffer.resize(capacity * FLOATS)
	_buffer.fill(0.0)
	var box := BoxMesh.new()
	box.subdivide_width = 1
	box.subdivide_height = 1
	box.subdivide_depth = 1
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_colors = true
	_multimesh.use_custom_data = true
	_multimesh.mesh = box
	_multimesh.instance_count = capacity
	_multimesh.buffer = _buffer
	_multimesh.custom_aabb = AABB(Vector3(-200, -50, -200), Vector3(400, 250, 400))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _multimesh
	mmi.material_override = load("res://materials/debris.tres")
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## Throws `count` chips out of a box of `size` centred on `at`. `kick` is
## the velocity the pieces inherit, `speed` how hard chips spray out;
## `scale` makes them bigger (the rubble of a big break). `carry` m^3 of
## broken material go along, shared out between the chips, and pile up
## where they land.
func burst(
	at: Vector3,
	size: Vector3,
	kind: int,
	count: int,
	speed := 4.0,
	kick := Vector3.ZERO,
	seed_value := -1.0,
	scale := 1.0,
	carry := 0.0
) -> void:
	count = mini(count, capacity / 6)
	var thrown := PackedInt32Array()
	if count > 0:
		thrown = _throw(at, size, kind, count, speed, kick, seed_value, scale)
	if carry <= 0.0:
		return
	var tone := RubbleField.color_of(kind, maxf(seed_value, 0.0))
	if thrown.is_empty():
		# Nothing to carry it: it drops where it broke.
		if rubble:
			rubble.deposit(at, carry, tone)
		return
	for i in thrown:
		_carry[i] = carry / thrown.size()
		_carry_color[i] = tone


func _throw(
	at: Vector3,
	size: Vector3,
	kind: int,
	count: int,
	speed: float,
	kick: Vector3,
	seed_value: float,
	scale: float
) -> PackedInt32Array:
	var thrown := PackedInt32Array()
	var floor_y := _floor_below(at)
	var shade := randf_range(0.85, 1.05)
	for k in count:
		var i := _take()
		if i < 0:
			break  # every chip is in the air: this burst is smaller
		thrown.append(i)
		var p := (
			at
			+ Vector3(
				randf_range(-0.5, 0.5) * size.x,
				randf_range(-0.5, 0.5) * size.y,
				randf_range(-0.5, 0.5) * size.z
			)
		)
		var dir := Vector3(randf_range(-1, 1), randf_range(-0.2, 1.0), randf_range(-1, 1)).normalized()
		_pos[i] = p
		_origin[i] = at
		_vel[i] = kick + dir * speed * randf_range(0.3, 1.0)
		_size[i] = _chip_size(kind) * scale
		_axis[i] = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		_angle[i] = randf() * TAU
		_spin[i] = randf_range(-14.0, 14.0)
		_floor[i] = floor_y
		_life[i] = randf_range(40.0, 70.0) * float(Quality.pick(0.5, 0.8, 1.0))
		_state[i] = 1
		_flying.append(i)
		var o := i * FLOATS
		_buffer[o + 12] = shade * randf_range(0.9, 1.05)
		_buffer[o + 13] = Materials.encode(kind)
		# The finish (plaster, brick...) of what broke rides in the seed.
		var chip_seed := seed_value if seed_value >= 0.0 else randf()
		_buffer[o + 14] = fposmod(chip_seed + randf() * 0.5, 1.0)
		_buffer[o + 15] = 0.0
		_buffer[o + 16] = Materials.custom(kind, 0.0, chip_seed)
		_carry[i] = 0.0
		_write(i, 1.0)
	return thrown


## A free slot, else the chip that has been lying still the longest (it
## should have faded already, see SOFT_BUDGET), else -1.
func _take() -> int:
	if not _free.is_empty():
		var i := _free[_free.size() - 1]
		_free.remove_at(_free.size() - 1)
		active += 1
		return i
	while _rested_head < _rested.size():
		var i := _rested[_rested_head]
		_rested_head += 1
		if _state[i] == 3:
			return i
	return -1


func _chip_size(kind: int) -> Vector3:
	var e := randf_range(0.05, 0.17)
	match kind:
		Materials.Kind.WOOD:
			return Vector3(e * 0.5, e * 0.5, e * randf_range(2.5, 4.5))  # splinters
		Materials.Kind.METAL:
			return Vector3(e, e * 0.2, e * 1.3)  # bent plates
		Materials.Kind.ICE:
			return Vector3(e * 0.6, e * 1.4, e * 0.4)  # shards
		Materials.Kind.GLASS:
			return Vector3(e * 0.9, e * 1.3, 0.012)  # flat glass shards
	return Vector3(e, e * randf_range(0.5, 1.0), e * randf_range(0.7, 1.2))


func _floor_below(at: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(at, at + Vector3.DOWN * 60.0)
	q.collision_mask = DebrisSystem.LAYER_WORLD | DebrisSystem.LAYER_STRUCTURES | DebrisSystem.LAYER_RUBBLE
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return (hit["position"] as Vector3).y if not hit.is_empty() else 0.0


func _process(delta: float) -> void:
	if active == 0:
		return
	var still := PackedInt32Array()
	for i in _flying:
		if _state[i] == 0 or _state[i] == 3:
			continue
		var v := _vel[i]
		v.y -= GRAVITY * delta
		var p := _pos[i] + v * delta
		var rest := _floor[i] + _size[i].y * 0.35
		if p.y < rest:
			# Flew past the slab it came from: find what is below now.
			var flat := Vector2(p.x - _origin[i].x, p.z - _origin[i].z)
			if flat.length() > 1.5 and _state[i] == 1:
				_floor[i] = _floor_below(Vector3(p.x, _floor[i] + 0.2, p.z))
				rest = _floor[i] + _size[i].y * 0.35
			if p.y < rest:
				p.y = rest
				if _state[i] == 1 and v.y < -2.0:
					v = Vector3(v.x * 0.45, -v.y * 0.28, v.z * 0.45)
					_spin[i] *= 0.5
					_state[i] = 2
				else:
					v = Vector3.ZERO
					_state[i] = 3
					_rested.append(i)
					if _carry[i] > 0.0:
						if rubble:
							rubble.deposit(p, _carry[i], _carry_color[i])
						_carry[i] = 0.0
		_vel[i] = v
		_pos[i] = p
		_angle[i] += _spin[i] * delta
		_write(i, 1.0)
		if _state[i] != 3:
			still.append(i)
	_flying = still
	# Lifetime and the fade at the end, ten times a second (resting chips
	# only change here).
	_life_tick += delta
	if _life_tick >= LIFE_TICK:
		_trim()
		for i in capacity:
			if _state[i] == 0:
				continue
			_life[i] -= _life_tick
			if _life[i] <= 0.0:
				_state[i] = 0
				active -= 1
				_free.append(i)
				_write(i, 0.0)
			elif _life[i] < FADE:
				_write(i, _life[i] / FADE)
		_life_tick = 0.0
	if _dirty:
		_multimesh.buffer = _buffer
		_dirty = false


## Above the soft budget the oldest resting chips start their fade, so a
## new burst finds room without anything vanishing at once.
func _trim() -> void:
	# Chips gone (or flying again) since they came to rest leave the queue.
	while _rested_head < _rested.size() and _state[_rested[_rested_head]] != 3:
		_rested_head += 1
	var excess := active - int(capacity * SOFT_BUDGET)
	var k := _rested_head
	while excess > 0 and k < _rested.size():
		var i := _rested[k]
		k += 1
		if _state[i] != 3:
			continue
		_life[i] = minf(_life[i], FADE)  # the front ones may be fading already
		excess -= 1
	if _rested_head > 1024 and _rested_head * 2 > _rested.size():
		_rested = _rested.slice(_rested_head)
		_rested_head = 0


func _write(i: int, scale: float) -> void:
	var b := Basis(_axis[i], _angle[i])
	var s := _size[i] * scale
	var p := _pos[i]
	var o := i * FLOATS
	_buffer[o + 0] = b.x.x * s.x
	_buffer[o + 1] = b.y.x * s.y
	_buffer[o + 2] = b.z.x * s.z
	_buffer[o + 3] = p.x
	_buffer[o + 4] = b.x.y * s.x
	_buffer[o + 5] = b.y.y * s.y
	_buffer[o + 6] = b.z.y * s.z
	_buffer[o + 7] = p.y
	_buffer[o + 8] = b.x.z * s.x
	_buffer[o + 9] = b.y.z * s.y
	_buffer[o + 10] = b.z.z * s.z
	_buffer[o + 11] = p.z
	_dirty = true
