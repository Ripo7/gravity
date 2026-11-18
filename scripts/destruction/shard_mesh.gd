class_name ShardMesh
extends MeshInstance3D
## Draws every block of a Structure in one draw call (see shards.gdshader).
## The mesh never changes: breaking only changes two small textures, which
## block goes with which body, and where each body is.
##
## Body 0 is the world: a block that stands in a whole piece goes with it.
## Body 1 + i is block i's own: taken when it stands cracked (drawn a little
## smaller, see `set_body`) or lies loose. A piece that falls in one piece
## moves all its blocks with the body of the first.

const SHADER := preload("res://shaders/shards.gdshader")
## Texels per row of the two data textures.
const WIDTH := 256
## Floats per body: where rest-space points go (xyz), how much smaller it is
## drawn, and a rotation.
const BODY_FLOATS := 8
## A face made by a cut is not left flat: its middle is pushed in or out by
## up to this share of its size, so it catches the light like broken stone.
const ROUGH := 0.14

var vertex_count := 0

var _verts := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()
var _uvs := PackedVector2Array()
var _indices := PackedInt32Array()
var _slots := PackedFloat32Array()
var _slot_image: Image
var _slot_texture: ImageTexture
var _slots_changed := false
var _bodies := PackedFloat32Array()
var _body_image: Image
var _body_texture: ImageTexture
var _bodies_changed := false
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.seed = 20261118
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Adds block `id`: its corners where it stands (`points`), its faces as
## cut by Fracture, and its piece's rotation to turn the face normals with.
## `base` is the id of the first block of its piece (Fracture numbers the
## blocks of a piece from 0).
func add_shard(
	id: int, base: int, points: PackedVector3Array, cut: Fracture.Shard, turn: Basis, tint: Color
) -> void:
	for f in cut.faces.size():
		var ring := cut.faces[f]
		var normal := turn * cut.normals[f]
		var from := _verts.size()
		var broken := cut.others[f] >= 0
		# Which block, and for a face made by the cut, 1 + the block on its
		# other side (0 for a face of the piece).
		var uv := Vector2(id, base + cut.others[f] + 1 if broken else 0)
		var middle := Vector3.ZERO
		for c in ring:
			_verts.append(points[c])
			_normals.append(normal)
			_colors.append(tint)
			_uvs.append(uv)
			middle += points[c]
		# The ring runs anticlockwise seen from outside; triangles go clockwise.
		if not broken:
			for t in range(1, ring.size() - 1):
				_indices.append(from)
				_indices.append(from + t + 1)
				_indices.append(from + t)
			continue
		# A broken face: a fan round its middle, which is pushed in or out.
		var n := ring.size()
		middle = middle / n + normal * sqrt(cut.areas[f]) * ROUGH * _rng.randf_range(-1.0, 0.7)
		_verts.append(middle)
		_normals.append(normal)
		_colors.append(tint)
		_uvs.append(uv)
		for t in n:
			_indices.append(from + n)
			_indices.append(from + (t + 1) % n)
			_indices.append(from + t)


## Builds the mesh once every block is added: `shards` of them.
func build(shards: int) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_INDEX] = _indices
	var made := ArrayMesh.new()
	made.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = made
	# Blocks move far from where the mesh has them: never cull it.
	custom_aabb = AABB(Vector3.ONE * -500.0, Vector3.ONE * 1000.0)
	vertex_count = _verts.size()
	var rows := maxi(ceili(float(shards) / WIDTH), 1)
	_slots.resize(WIDTH * rows)
	_slots.fill(0.0)
	_slot_image = Image.create_from_data(WIDTH, rows, false, Image.FORMAT_RF, _slots.to_byte_array())
	_slot_texture = ImageTexture.create_from_image(_slot_image)
	var body_rows := maxi(ceili((shards + 1) * 2.0 / WIDTH), 1)
	_bodies.resize(WIDTH * body_rows * 4)
	_bodies.fill(0.0)
	for b in _bodies.size() / BODY_FLOATS:
		_bodies[b * BODY_FLOATS + 3] = 1.0  # drawn as big as it is
		_bodies[b * BODY_FLOATS + 7] = 1.0  # no rotation
	_body_image = Image.create_from_data(WIDTH, body_rows, false, Image.FORMAT_RGBAF, _bodies.to_byte_array())
	_body_texture = ImageTexture.create_from_image(_body_image)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("slot_of", _slot_texture)
	mat.set_shader_parameter("bodies", _body_texture)
	material_override = mat
	_verts = PackedVector3Array()
	_normals = PackedVector3Array()
	_colors = PackedColorArray()
	_uvs = PackedVector2Array()
	_indices = PackedInt32Array()


## Block `shard` now moves with body `slot` (0: the world).
func set_slot(shard: int, slot: int) -> void:
	_slots[shard] = slot
	_slots_changed = true


## Body `slot` is at `xf`; `origin` is where its own origin was when its
## piece was whole (blocks keep their place around it). `drawn`: how big it
## is drawn about that origin (1: as it is; less: a block that stands
## cracked, shrunk away from its neighbours).
func set_body(slot: int, xf: Transform3D, origin: Vector3, drawn := 1.0) -> void:
	var o := slot * BODY_FLOATS
	var at := xf.origin - xf.basis * origin * drawn
	var q := xf.basis.get_rotation_quaternion()
	_bodies[o] = at.x
	_bodies[o + 1] = at.y
	_bodies[o + 2] = at.z
	_bodies[o + 3] = drawn
	_bodies[o + 4] = q.x
	_bodies[o + 5] = q.y
	_bodies[o + 6] = q.z
	_bodies[o + 7] = q.w
	_bodies_changed = true


func _process(_delta: float) -> void:
	if _slots_changed:
		_slots_changed = false
		_slot_image.set_data(WIDTH, _slot_image.get_height(), false, Image.FORMAT_RF, _slots.to_byte_array())
		_slot_texture.update(_slot_image)
	if _bodies_changed:
		_bodies_changed = false
		_body_image.set_data(
			WIDTH, _body_image.get_height(), false, Image.FORMAT_RGBAF, _bodies.to_byte_array()
		)
		_body_texture.update(_body_image)
