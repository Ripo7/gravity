class_name DustSystem
extends Node3D
## Dust and smoke: big soft clouds drawn as camera-facing puffs in one draw
## call, simulated here (a few dozen to a couple hundred puffs, cheap).
## - puff: a burst where a block breaks
## - roll: a wall of dust rolling out along the ground after a collapse
## - haze: a low veil that lingers over fresh rubble
## - jet: dust blasting out sideways where a storey is crushed
## And the dust that settles: the square round a collapse turns pale (a
## coarse map of how dusty the ground is, read by the floor shader).
## - trails behind pieces of building that are falling
## Owns the chip system too (gravel and splinters without physics).

const FLOATS := 20  # transform 12, colour 4, custom 4
const FLIPBOOK := "res://assets/textures/dust_flipbook.png"
## The ground's dust map: a texel every 2 m over the middle of the map.
const GROUND_SIZE := 64
const GROUND_HALF := 64.0
const GROUND_UPLOAD := 0.3  ## seconds between uploads of the map
const DUST_COLORS := {
	Materials.Kind.CONCRETE: Color(0.78, 0.75, 0.7, 0.75),
	Materials.Kind.WOOD: Color(0.74, 0.64, 0.5, 0.6),
	Materials.Kind.METAL: Color(0.7, 0.71, 0.74, 0.5),
	Materials.Kind.ICE: Color(0.22, 0.18, 0.3, 0.45),
}

var chip_system: ChipSystem
var structures: StructureSet
var floor_mat: ShaderMaterial  ## the floor's material (see use_floor)
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
var _dusty := PackedByteArray()  ## how dusty the ground is, 0..255, a byte a texel
var _ground_img: Image
var _ground_tex: ImageTexture
var _ground_dirty := false
var _ground_tick := 0.0


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


## Lights the dust with the scene's sun: its direction and colour (the
## sky's blue fills the other side).
func light_from(sun: DirectionalLight3D) -> void:
	var mat := _multimesh_material()
	if mat == null or sun == null:
		return
	mat.set_shader_parameter("sun_dir", sun.global_basis.z.normalized())
	mat.set_shader_parameter("sun_color", sun.light_color)


func _multimesh_material() -> ShaderMaterial:
	for child in get_children():
		if child is MultiMeshInstance3D and (child as MultiMeshInstance3D).multimesh == _multimesh:
			return (child as MultiMeshInstance3D).material_override as ShaderMaterial
	return null


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
	_ground_tick += delta
	if _ground_dirty and _ground_tick >= GROUND_UPLOAD:
		_ground_tick = 0.0
		_ground_dirty = false
		_ground_img.set_data(GROUND_SIZE, GROUND_SIZE, false, Image.FORMAT_R8, _dusty)
		_ground_tex.update(_ground_img)
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


## Settles dust on the floor drawn with `mat` from now on (a clean floor:
## a world loaded earlier may have left its dust on the shared material).
func use_floor(mat: ShaderMaterial) -> void:
	floor_mat = mat
	_ground_img = null
	_dusty.clear()
	if floor_mat:
		floor_mat.set_shader_parameter("ground_dust", null)


## Dust settling on the ground round `at`: up to `amount` (1 = fully
## covered) within `radius` metres, less towards the edge.
func settle(at: Vector3, radius: float, amount: float) -> void:
	if floor_mat == null:
		return
	if _ground_img == null:
		_dusty.resize(GROUND_SIZE * GROUND_SIZE)
		_dusty.fill(0)
		_ground_img = Image.create_from_data(GROUND_SIZE, GROUND_SIZE, false, Image.FORMAT_R8, _dusty)
		_ground_tex = ImageTexture.create_from_image(_ground_img)
		floor_mat.set_shader_parameter("ground_dust", _ground_tex)
		floor_mat.set_shader_parameter(
			"dust_rect", Vector4(-GROUND_HALF, -GROUND_HALF, GROUND_HALF * 2.0, GROUND_HALF * 2.0)
		)
	var scale := GROUND_SIZE / (GROUND_HALF * 2.0)
	var c := Vector2(at.x + GROUND_HALF, at.z + GROUND_HALF) * scale
	var r := maxf(radius * scale, 1.0)
	var add := amount * 255.0
	for y in range(maxi(int(c.y - r), 0), mini(int(c.y + r) + 1, GROUND_SIZE)):
		var row := y * GROUND_SIZE
		var dy := (y + 0.5 - c.y) / r
		for x in range(maxi(int(c.x - r), 0), mini(int(c.x + r) + 1, GROUND_SIZE)):
			var dx := (x + 0.5 - c.x) / r
			var f := 1.0 - sqrt(dx * dx + dy * dy)
			if f > 0.0:
				_dusty[row + x] = mini(_dusty[row + x] + int(add * f * f * (3.0 - 2.0 * f)), 255)
	_ground_dirty = true


## A dust cloud of roughly `radius` metres where something broke.
func puff(at: Vector3, radius: float, kind: int, amount := 10) -> void:
	var col: Color = DUST_COLORS.get(kind, DUST_COLORS[Materials.Kind.CONCRETE])
	if at.y < 6.0:
		settle(at, radius * 3.5, 0.08)
	var n := clampi(int(amount / 5.0), 1, 4)
	for k in n:
		var dir := Vector3(randf_range(-1, 1), randf_range(0.0, 0.8), randf_range(-1, 1))
		var size := maxf(radius, 0.5) * randf_range(1.6, 2.6)
		_spawn(
			at + dir * radius * 0.4, dir * (0.6 + radius * 0.6), size, size * 0.5, randf_range(1.8, 3.0), col
		)


## A gust out of `origin` in the cone round `dir` (cos of its half angle),
## from `near` to `far` metres out: the dust there is given `speed` m/s
## more away from `origin`, less the farther out (Shockwave.strength).
func blow(origin: Vector3, dir: Vector3, cos_half: float, near: float, far: float, speed: float) -> void:
	if active == 0:
		return
	for i in capacity:
		if _life[i] <= 0.0:
			continue
		var off := _pos[i] - origin
		var d := off.length()
		if d <= near or d > far or (d > 0.5 and off.dot(dir) < d * cos_half):
			continue
		_vel[i] += off / maxf(d, 0.01) * speed * maxf(Shockwave.strength(d), 0.15)


## A wall of dust rolling out along the ground from a collapse at `at`.
## `radius` sets how big; `strength` (0..1) how thick.
func roll(at: Vector3, radius: float, strength := 1.0) -> void:
	var col: Color = DUST_COLORS[Materials.Kind.CONCRETE]
	col.a *= clampf(0.55 + strength * 0.45, 0.3, 1.0)
	settle(at, radius * 3.0, 0.55 * strength)
	var ground_y := _ground_below(at)
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
			ground_y,
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
			ground_y,
			0.6
		)


## Dust blasting out sideways (a storey crushed flat pushes its air out
## through the windows): a few puffs shot along `dir`, quickly braked.
func jet(at: Vector3, dir: Vector3, radius: float, speed := 8.0) -> void:
	var col: Color = DUST_COLORS[Materials.Kind.CONCRETE]
	var out := Vector3(dir.x, 0.0, dir.z).normalized()
	for k in int(Quality.pick(2, 3, 4)):
		var v := out + Vector3(randf_range(-0.25, 0.25), randf_range(0.0, 0.35), randf_range(-0.25, 0.25))
		var size := radius * randf_range(0.8, 1.3)
		_spawn(
			at + out * radius * 0.5 * k,
			v.normalized() * speed * randf_range(0.7, 1.1),
			size,
			size * 0.9,
			randf_range(2.5, 3.8),
			col,
			-INF,
			2.4
		)


## A thin veil that lingers low over fresh rubble.
func haze(at: Vector3, radius: float) -> void:
	var col: Color = DUST_COLORS[Materials.Kind.CONCRETE] * Color(1, 1, 1, 0.45)
	var ground_y := _ground_below(at)
	settle(at, radius * 1.8, 0.2)
	for k in 3:
		var off := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * radius
		_spawn(
			at + off,
			off.normalized() * 0.4,
			radius * 1.4,
			radius * 0.08,
			randf_range(8.0, 11.0),
			col,
			ground_y,
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
	q.collision_mask = DebrisSystem.LAYER_WORLD | DebrisSystem.LAYER_STRUCTURES | DebrisSystem.LAYER_RUBBLE
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return (hit["position"] as Vector3).y if not hit.is_empty() else 0.0
