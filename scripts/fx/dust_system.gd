class_name DustSystem
extends Node3D
## Dust and smoke: big soft clouds drawn as camera-facing puffs in one draw
## call, simulated here (a few dozen to a couple hundred puffs, cheap).
## - puff: a burst where a block breaks
## - roll: a wall of dust rolling out along the ground after a collapse
## - haze: a low veil that lingers over fresh rubble
## - trails behind pieces of building that are falling
## Owns the chip system too (gravel and splinters without physics).

const FLOATS := 20  # transform 12, colour 4, custom 4
const FLIPBOOK := "res://assets/textures/dust_flipbook.png"
const DUST_COLORS := {
	Materials.Kind.CONCRETE: Color(0.78, 0.75, 0.7, 0.75),
	Materials.Kind.WOOD: Color(0.74, 0.64, 0.5, 0.6),
	Materials.Kind.METAL: Color(0.7, 0.71, 0.74, 0.5),
	Materials.Kind.ICE: Color(0.22, 0.18, 0.3, 0.45),
}

var chip_system: ChipSystem
var structures: StructureSet
var capacity := 0
var active := 0
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _size := PackedFloat32Array()
var _grow := PackedFloat32Array()  # metres per second
var _life := PackedFloat32Array()
var _max_life := PackedFloat32Array()
var _ground := PackedFloat32Array()  # hugs the ground at this height, or -INF
var _drag := PackedFloat32Array()
var _next := 0
var _buffer := PackedFloat32Array()
var _multimesh: MultiMesh
var _budget := 40.0  # puffs that can still go out right now
var _trail_tick := 0.0


func _ready() -> void:
	capacity = Quality.pick(70, 140, 220)
	_pos.resize(capacity)
	_vel.resize(capacity)
	_size.resize(capacity)
	_grow.resize(capacity)
	_life.resize(capacity)
	_life.fill(0.0)
	_max_life.resize(capacity)
	_ground.resize(capacity)
	_drag.resize(capacity)
	_buffer.resize(capacity * FLOATS)
	_buffer.fill(0.0)
	var quad := QuadMesh.new()
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_colors = true
	_multimesh.use_custom_data = true
	_multimesh.mesh = quad
	_multimesh.instance_count = capacity
	_multimesh.buffer = _buffer
	_multimesh.custom_aabb = AABB(Vector3(-200, -50, -200), Vector3(400, 250, 400))
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/dust.gdshader")
	mat.set_shader_parameter("noise_tex", _noise_texture())
	# The billowing puff built and rendered in Blender (tools/make_smoke.py).
	if ResourceLoader.exists(FLIPBOOK):
		mat.set_shader_parameter("flipbook", load(FLIPBOOK))
		mat.set_shader_parameter("use_flipbook", true)
	mat.render_priority = 1
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _multimesh
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	chip_system = ChipSystem.new()
	add_child(chip_system)


static func _noise_texture() -> ImageTexture:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.035
	n.fractal_octaves = 3
	var img := n.get_seamless_image(128, 128)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _spawn(
	at: Vector3, vel: Vector3, size: float, grow: float, life: float, col: Color, ground := -INF, drag := 1.5
) -> void:
	if _budget <= 0.0:
		return
	_budget -= 1.0
	var i := _next
	_next = (_next + 1) % capacity
	if _life[i] <= 0.0:
		active += 1
	_pos[i] = at
	_vel[i] = vel
	_size[i] = size
	_grow[i] = grow
	_life[i] = life
	_max_life[i] = life
	_ground[i] = ground
	_drag[i] = drag
	var o := i * FLOATS
	var shade := randf_range(0.92, 1.04)
	_buffer[o + 12] = col.r * shade
	_buffer[o + 13] = col.g * shade
	_buffer[o + 14] = col.b * shade
	_buffer[o + 15] = col.a
	_buffer[o + 17] = randf()
	_buffer[o + 18] = randf() * TAU


func _process(delta: float) -> void:
	_budget = minf(_budget + delta * float(Quality.pick(40, 80, 120)), float(Quality.pick(20, 40, 60)))
	_trail_tick += delta
	if _trail_tick > 0.12 and structures:
		_trail_tick = 0.0
		for p in structures.falling_cluster_positions(5.0):
			_spawn(
				p,
				Vector3(0, 0.4, 0),
				1.6,
				1.8,
				2.2,
				DUST_COLORS[Materials.Kind.CONCRETE] * Color(1, 1, 1, 0.55)
			)
	if active == 0:
		return
	for i in capacity:
		if _life[i] <= 0.0:
			continue
		_life[i] -= delta
		var o := i * FLOATS
		if _life[i] <= 0.0:
			active -= 1
			_buffer[o + 0] = 0.0
			_buffer[o + 5] = 0.0
			_buffer[o + 10] = 0.0
			continue
		var v := _vel[i] * exp(-_drag[i] * delta)
		v.y += 0.15 * delta  # warm dust drifts up a little
		_vel[i] = v
		var p := _pos[i] + v * delta
		_size[i] += _grow[i] * delta
		var s := _size[i]
		if _ground[i] > -INF:
			p.y = maxf(p.y, _ground[i] + s * 0.32)
		_pos[i] = p
		var age := 1.0 - _life[i] / _max_life[i]
		_buffer[o + 0] = s
		_buffer[o + 1] = 0.0
		_buffer[o + 2] = 0.0
		_buffer[o + 3] = p.x
		_buffer[o + 4] = 0.0
		_buffer[o + 5] = s
		_buffer[o + 6] = 0.0
		_buffer[o + 7] = p.y
		_buffer[o + 8] = 0.0
		_buffer[o + 9] = 0.0
		_buffer[o + 10] = s
		_buffer[o + 11] = p.z
		_buffer[o + 16] = age  # the shader erodes it as it ages
	_multimesh.buffer = _buffer


## A dust cloud of roughly `radius` metres where something broke.
func puff(at: Vector3, radius: float, kind: int, amount := 10) -> void:
	var col: Color = DUST_COLORS.get(kind, DUST_COLORS[Materials.Kind.CONCRETE])
	var n := clampi(int(amount / 5.0), 1, 4)
	for k in n:
		var dir := Vector3(randf_range(-1, 1), randf_range(0.0, 0.8), randf_range(-1, 1))
		var size := maxf(radius, 0.5) * randf_range(1.6, 2.6)
		_spawn(
			at + dir * radius * 0.4, dir * (0.6 + radius * 0.6), size, size * 0.5, randf_range(1.8, 3.0), col
		)


## A wall of dust rolling out along the ground from a collapse at `at`.
## `radius` sets how big; `strength` (0..1) how thick.
func roll(at: Vector3, radius: float, strength := 1.0) -> void:
	var col: Color = DUST_COLORS[Materials.Kind.CONCRETE]
	col.a *= clampf(0.55 + strength * 0.45, 0.3, 1.0)
	var ground := _ground_below(at)
	var n := int(Quality.pick(6, 10, 14) * clampf(strength, 0.4, 1.0))
	for k in n:
		var a := TAU * (k + randf() * 0.6) / n
		var out := Vector3(cos(a), 0, sin(a))
		var size := radius * randf_range(0.7, 1.1)
		var speed := randf_range(4.0, 8.0) * (0.6 + strength * 0.4)
		_spawn(
			at + out * radius * 0.3,
			out * speed + Vector3.UP * 0.6,
			size,
			size * 0.35,
			randf_range(5.0, 7.5),
			col,
			ground,
			0.9
		)
	# A taller column at the centre.
	for k in 2:
		var size := radius * 1.3
		_spawn(
			at + Vector3.UP * size * 0.4,
			Vector3(0, randf_range(1.0, 2.0), 0),
			size,
			size * 0.25,
			6.0,
			col,
			ground,
			0.6
		)


## A thin veil that lingers low over fresh rubble.
func haze(at: Vector3, radius: float) -> void:
	var col: Color = DUST_COLORS[Materials.Kind.CONCRETE] * Color(1, 1, 1, 0.45)
	var ground := _ground_below(at)
	for k in 3:
		var off := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * radius
		_spawn(
			at + off,
			off.normalized() * 0.4,
			radius * 1.4,
			radius * 0.08,
			randf_range(8.0, 11.0),
			col,
			ground,
			0.4
		)


## Small flying fragments that are not simulated as bodies.
func chips(at: Vector3, radius: float, kind: int, speed := 5.0, amount := 12) -> void:
	chip_system.burst(at, Vector3.ONE * radius, kind, amount, speed)


## Gravel and splinters spraying out of a broken block of `size`.
func chips_box(
	at: Vector3, size: Vector3, kind: int, amount: int, speed := 4.0, kick := Vector3.ZERO
) -> void:
	chip_system.burst(at, size, kind, amount, speed, kick)


func _ground_below(at: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.5, at + Vector3.DOWN * 60.0)
	q.collision_mask = DebrisSystem.LAYER_WORLD | DebrisSystem.LAYER_STRUCTURES
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return (hit["position"] as Vector3).y if not hit.is_empty() else 0.0
