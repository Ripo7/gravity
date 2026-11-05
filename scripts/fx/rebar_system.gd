class_name RebarSystem
extends Node3D
## Reinforcing bars: when a concrete block breaks away, bent steel rods are
## left sticking out of the blocks it was joined to. Visual only (no
## physics), one draw call; the rods go when the block holding them goes.

var capacity := 0
var _next := 0
var _owner := PackedInt32Array()  # block holding each rod (-1 free)
var _by_owner := {}  # block -> PackedInt32Array of rods (may be stale)
var _buffer := PackedFloat32Array()
var _dirty := false
var _multimesh: MultiMesh


func _ready() -> void:
	capacity = Quality.pick(240, 600, 1000)
	_owner.resize(capacity)
	_owner.fill(-1)
	_buffer.resize(capacity * 12)
	_buffer.fill(0.0)
	var box := BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.21, 0.15)
	mat.roughness = 0.55
	mat.metallic = 0.6
	box.material = mat
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.mesh = box
	_multimesh.instance_count = capacity
	_multimesh.buffer = _buffer
	_multimesh.custom_aabb = AABB(Vector3(-200, -50, -200), Vector3(400, 250, 400))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _multimesh
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## Bent rods growing out of a face of block `owner`: centred on `face`
## (world space), spread over `span` (two in-plane axes, half extents), and
## pointing along `out` (toward where the broken block was).
func sprout(owner: int, face: Vector3, axis_a: Vector3, axis_b: Vector3, out: Vector3, count: int) -> void:
	for k in count:
		var start := face + axis_a * randf_range(-0.8, 0.8) + axis_b * randf_range(-0.8, 0.8)
		var len1 := randf_range(0.15, 0.45)
		var dir := (
			(out + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.12).normalized()
		)
		_rod(owner, start, dir, len1)
		# Bent: the free end sags and twists a little.
		var down := (
			dir
			+ Vector3.DOWN * randf_range(0.4, 1.2)
			+ Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5))
		)
		_rod(owner, start + dir * len1, down.normalized(), randf_range(0.1, 0.35))


func _rod(owner: int, from: Vector3, dir: Vector3, length: float) -> void:
	var i := _next
	_next = (_next + 1) % capacity
	_owner[i] = owner
	if not _by_owner.has(owner):
		_by_owner[owner] = PackedInt32Array()
	_by_owner[owner].append(i)
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	var x := up.cross(dir).normalized()
	var y := dir.cross(x).normalized()
	var t := 0.026
	var b := Basis(x * t, y * t, dir * length)
	var c := from + dir * length * 0.5
	var o := i * 12
	_buffer[o + 0] = b.x.x
	_buffer[o + 1] = b.y.x
	_buffer[o + 2] = b.z.x
	_buffer[o + 3] = c.x
	_buffer[o + 4] = b.x.y
	_buffer[o + 5] = b.y.y
	_buffer[o + 6] = b.z.y
	_buffer[o + 7] = c.y
	_buffer[o + 8] = b.x.z
	_buffer[o + 9] = b.y.z
	_buffer[o + 10] = b.z.z
	_buffer[o + 11] = c.z
	_dirty = true


## The block holding these rods is gone: so are they.
func drop_owner(owner: int) -> void:
	var rods: Variant = _by_owner.get(owner)
	if rods == null:
		return
	_by_owner.erase(owner)
	for i: int in rods:
		if _owner[i] != owner:
			continue  # recycled since
		_owner[i] = -1
		for k in 12:
			_buffer[i * 12 + k] = 0.0
		_dirty = true


func count() -> int:
	var n := 0
	for o in _owner:
		if o >= 0:
			n += 1
	return n


func _process(_delta: float) -> void:
	if _dirty:
		_multimesh.buffer = _buffer
		_dirty = false
