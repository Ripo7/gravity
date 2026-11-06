class_name GrainCloud
extends Node3D
## What a black hole grinds down: thousands of grains swirling round it in
## a disc, in a haze of their own dust. No physics and no script per grain:
## the shaders move every grain and every puff from the moment it was
## caught, so the cloud is two draw calls and a uniform update per frame.
## When the hole closes, the grains are flung out and fade into the dust,
## the dust billows out, and part of the grains lands as gravel.

const SHADER := preload("res://shaders/grain.gdshader")
const DUST_SHADER := preload("res://shaders/grain_dust.gdshader")
## One puff of dust for this many grains.
const GRAINS_PER_PUFF := 6
const FADE := 1.2  ## seconds the flung grains take to vanish
## Average volume of a grain (m^3): how many grains a piece is worth.
const GRAIN_VOLUME := 0.0004
## Crushed material, by finish (Materials.Finish): what the inside looks like.
const FINISH_COLORS := [
	Color(0.6, 0.58, 0.55),  # raw concrete
	Color(0.7, 0.64, 0.55),  # stone
	Color(0.62, 0.33, 0.24),  # brick
	Color(0.84, 0.78, 0.65),  # travertine
	Color(0.88, 0.87, 0.84),  # marble
	Color(0.72, 0.5, 0.33),  # ochre plaster over brick
	Color(0.74, 0.5, 0.44),  # rose plaster
	Color(0.62, 0.38, 0.26),  # sienna plaster
	Color(0.82, 0.74, 0.62),  # cream plaster
	Color(0.68, 0.36, 0.22),  # terracotta
	Color(0.3, 0.3, 0.32),  # composite
	Color(0.36, 0.4, 0.3),  # shutters
	Color(0.36, 0.56, 0.48),  # verdigris
	Color(0.6, 0.45, 0.25),  # bronze
	Color(0.2, 0.2, 0.22),  # black steel
]
const KIND_COLORS := {
	Materials.Kind.WOOD: Color(0.52, 0.38, 0.24),
	Materials.Kind.METAL: Color(0.45, 0.45, 0.47),
	Materials.Kind.ICE: Color(0.07, 0.07, 0.1),
	Materials.Kind.GLASS: Color(0.7, 0.78, 0.82),
}

var center := Vector3.ZERO
var capacity := 0
var used := 0  ## grain slots filled so far (the oldest are reused)
var accepting := false  ## true while the hole pulls
var _now := 0.0
var _released := -1.0
var _next := 0
var _mm: MultiMesh
var _mat: ShaderMaterial
var _buffer := PackedFloat32Array()
var _dust_mm: MultiMesh
var _dust_mat: ShaderMaterial
var _dust_buffer := PackedFloat32Array()
var _dust_capacity := 0
var _dust_next := 0
var _dust_used := 0
var _dirty := false
var _sources := {}  # finish key -> [kind, seed, grains]: what to drop as gravel


## The cloud of the black hole that `at` is inside, if one is grinding there.
static func find(tree: SceneTree, at: Vector3) -> GrainCloud:
	for n in tree.get_nodes_in_group("grain_cloud"):
		var c := n as GrainCloud
		if c.accepting and c.center.distance_to(at) <= PowerDefs.VORTEX_RADIUS + 0.5:
			return c
	return null


func setup(at: Vector3) -> void:
	center = at


func _ready() -> void:
	add_to_group("grain_cloud")
	capacity = int(Quality.pick(2000, 5000, 9000))
	_buffer.resize(capacity * 20)
	_buffer.fill(0.0)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = _rock()
	_mm.instance_count = capacity
	_mm.visible_instance_count = 0
	# Grains go wherever the shader sends them: bounds cover the flight.
	_mm.custom_aabb = AABB(center - Vector3(40, 20, 40), Vector3(80, 50, 80))
	_mat = _material(SHADER)
	_add_layer(_mm, _mat)
	_dust_capacity = int(Quality.pick(250, 600, 1000))
	_dust_buffer.resize(_dust_capacity * 20)
	_dust_buffer.fill(0.0)
	_dust_mm = MultiMesh.new()
	_dust_mm.transform_format = MultiMesh.TRANSFORM_3D
	_dust_mm.use_colors = true
	_dust_mm.use_custom_data = true
	_dust_mm.mesh = QuadMesh.new()
	_dust_mm.instance_count = _dust_capacity
	_dust_mm.visible_instance_count = 0
	_dust_mm.custom_aabb = _mm.custom_aabb
	_dust_mat = _material(DUST_SHADER)
	_add_layer(_dust_mm, _dust_mat)


func _material(shader: Shader) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("center", center)
	m.set_shader_parameter("radius", PowerDefs.VORTEX_RADIUS)
	m.set_shader_parameter("spin", PowerDefs.VORTEX_SPIN)
	m.set_shader_parameter("max_speed", PowerDefs.VORTEX_MAX_SPEED)
	m.set_shader_parameter("burst", PowerDefs.VORTEX_BURST_SPEED)
	m.set_shader_parameter("lift", PowerDefs.VORTEX_BURST_LIFT)
	m.set_shader_parameter("fade_time", FADE)
	m.set_shader_parameter("violet", Palette.VIOLET)
	return m


func _add_layer(mm: MultiMesh, m: ShaderMaterial) -> void:
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.top_level = true  # the shaders work in world space
	add_child(mmi)


## Turns debris piece `i` into grains (it leaves the physics for good).
func add_piece(debris: DebrisSystem, i: int) -> void:
	var n := clampi(int(debris.volume_of(i) / GRAIN_VOLUME), 8, 90)
	add(debris.position_of(i), debris.size_of(i), debris.kind_of(i), debris.seed_of(i), n)
	debris.despawn(i)


## Adds `n` grains of a piece of `size` at `at`.
func add(at: Vector3, size: Vector3, kind: int, seed_value: float, n: int) -> void:
	if capacity == 0:
		return
	var col := color_of(kind, seed_value)
	var key := Materials.finish_of(seed_value) * Materials.KIND_SLOTS + kind
	if _sources.has(key):
		_sources[key][2] += n
	else:
		_sources[key] = [kind, seed_value, n]
	var r := PowerDefs.VORTEX_RADIUS
	var spread := size * 0.5
	for k in n:
		var i := _next
		_next = (_next + 1) % capacity
		used = mini(used + 1, capacity)
		var p := at + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * spread
		# Mostly fine grains, now and then a bit of gravel.
		var s := randf_range(0.03, 0.08) if randf() < 0.85 else randf_range(0.09, 0.16)
		var lane := lerpf(PowerDefs.VORTEX_CORE * 1.3, r * 0.95, pow(randf(), 0.8))
		var layer := (randf() + randf() - 1.0) * 0.3
		var shade := randf_range(0.85, 1.1)
		var o := i * 20
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
		_buffer[o + 12] = col.r * shade
		_buffer[o + 13] = col.g * shade
		_buffer[o + 14] = col.b * shade
		_buffer[o + 15] = 1.0
		_buffer[o + 16] = _now
		_buffer[o + 17] = lane
		_buffer[o + 18] = layer
		_buffer[o + 19] = randf()
		if k % GRAINS_PER_PUFF == 0:
			_add_puff(p, col, lane, layer)
	_dirty = true


## A soft puff of the grains' dust (lighter than the grains), on the same orbit.
func _add_puff(p: Vector3, col: Color, lane: float, layer: float) -> void:
	var i := _dust_next
	_dust_next = (_dust_next + 1) % _dust_capacity
	_dust_used = mini(_dust_used + 1, _dust_capacity)
	var s := randf_range(0.35, 0.8)
	var dust := col.lerp(Color(0.82, 0.78, 0.72), 0.55)
	var o := i * 20
	_dust_buffer[o + 0] = s
	_dust_buffer[o + 3] = p.x
	_dust_buffer[o + 5] = s
	_dust_buffer[o + 7] = p.y
	_dust_buffer[o + 10] = s
	_dust_buffer[o + 11] = p.z
	_dust_buffer[o + 12] = dust.r
	_dust_buffer[o + 13] = dust.g
	_dust_buffer[o + 14] = dust.b
	_dust_buffer[o + 15] = 1.0
	_dust_buffer[o + 16] = _now
	_dust_buffer[o + 17] = lane
	_dust_buffer[o + 18] = layer * 1.4
	_dust_buffer[o + 19] = randf()


static func color_of(kind: int, seed_value: float) -> Color:
	if KIND_COLORS.has(kind):
		return KIND_COLORS[kind]
	return FINISH_COLORS[Materials.finish_of(seed_value)]


## The hole closed: grains fly out and fade into dust; some land as gravel.
func release(world: GameWorld) -> void:
	accepting = false
	_released = _now
	_mat.set_shader_parameter("released", _released)
	_dust_mat.set_shader_parameter("released", _released)
	if used == 0 or world == null:
		return
	var r := PowerDefs.VORTEX_RADIUS
	if world.dust:
		for k in 8:
			var a := TAU * k / 8.0 + randf() * 0.4
			var at := center + Vector3(cos(a), 0, sin(a)) * r * randf_range(0.5, 0.9)
			world.dust.puff(at, 1.6, Materials.Kind.CONCRETE, 6)
	var chips := world.debris.chips if world.debris else null
	if chips == null:
		return
	# About one chip of gravel for every six grains, with the right finishes.
	for key: int in _sources:
		var src: Array = _sources[key]
		var left := mini(int(src[2]) / 6, 160)
		while left > 0:
			var a := randf() * TAU
			var dir := Vector3(cos(a), 0, sin(a))
			var at := center + dir * randf_range(PowerDefs.VORTEX_CORE, r * 0.9)
			var n := mini(left, 6)
			var kick := dir * randf_range(4.0, 9.0) + Vector3.UP * 2.0
			chips.burst(at, Vector3.ONE * 0.6, int(src[0]), n, 2.5, kick, float(src[1]))
			left -= n


func _process(delta: float) -> void:
	_now += delta
	_mat.set_shader_parameter("now", _now)
	_dust_mat.set_shader_parameter("now", _now)
	if _dirty:
		_mm.buffer = _buffer
		_mm.visible_instance_count = used
		_dust_mm.buffer = _dust_buffer
		_dust_mm.visible_instance_count = _dust_used
		_dirty = false
	if _released >= 0.0 and _now - _released > FADE:
		queue_free()


## A small rock: an octahedron with jittered points, flat-shaded.
static func _rock() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var pts: Array[Vector3] = [
		Vector3(0.5, 0, 0),
		Vector3(-0.5, 0, 0),
		Vector3(0, 0.5, 0),
		Vector3(0, -0.5, 0),
		Vector3(0, 0, 0.5),
		Vector3(0, 0, -0.5)
	]
	for k in pts.size():
		pts[k] = pts[k] * rng.randf_range(0.7, 1.15) + Vector3(rng.randf(), rng.randf(), rng.randf()) * 0.08
	var faces := [[0, 2, 4], [4, 2, 1], [1, 2, 5], [5, 2, 0], [4, 3, 0], [1, 3, 4], [5, 3, 1], [0, 3, 5]]
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	for f: Array in faces:
		var a := pts[f[0]]
		var b := pts[f[1]]
		var c := pts[f[2]]
		# Godot's front faces wind clockwise seen from outside.
		var n := (c - a).cross(b - a).normalized()
		if n.dot(a + b + c) < 0.0:
			var t := b
			b = c
			c = t
			n = -n
		for p in [a, b, c]:
			verts.append(p)
			normals.append(n)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
