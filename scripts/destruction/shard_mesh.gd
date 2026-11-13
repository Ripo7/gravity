class_name ShardMesh
extends MeshInstance3D
## Draws every shard of a Structure in one draw call (see shards.gdshader).
## The mesh never changes: breaking only changes two small textures, which
## shard belongs to which rigid body, and where each body is. Crumbs, cut
## while the game runs, are a second, small mesh drawn the same way; it is
## made again whenever some are added, without those that are gone.

const SHADER := preload("res://shaders/shards.gdshader")
const TEXTURES := "res://addons/kenney_prototype_textures/"
## Texels per row of the two data textures.
const WIDTH := 256
## Floats per body: where rest-space points go (xyz), its size (1 unless it
## is dwindling into an orb) and a rotation.
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
var _crumbs: MeshInstance3D
var _crumbs_changed := false
var _bits := {}  # crumb id: its [corners, normals, colours, uvs, triangles]


## Adds shard `id`: its corners where it stands (`points`), its faces as
## cut by Fracture, and the box's rotation to turn the face normals with.
## `base` is the id of the first shard of its box (Fracture numbers the
## shards of a box from 0). For a crumb, `alone` is an id that is never
## drawn: its cut faces always show once it is out. After build(), what is
## added is a crumb: it goes to the crumbs' mesh, until forget().
func _init() -> void:
	_rng.seed = 20261112


func add_shard(
	id: int, base: int, points: PackedVector3Array, cut: Fracture.Shard, turn: Basis, tint: Color, alone := -1
) -> void:
	for f in cut.faces.size():
		var ring := cut.faces[f]
		var normal := turn * cut.normals[f]
		var from := _verts.size()
		var broken := cut.others[f] >= 0
		# Which shard, and for a face made by the cut, 1 + the shard on its
		# other side (0 for a face of the box).
		var uv := Vector2(id, 0)
		if broken:
			uv.y = (alone if alone >= 0 else base + cut.others[f]) + 1
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
	if _crumbs != null:
		_bits[id] = [_verts, _normals, _colors, _uvs, _indices]
		_clear()
		_crumbs_changed = true


## Crumb `id` is gone for good: it is left out the next time the crumbs'
## mesh is made (until then it is only not drawn, like any hidden shard).
func forget(id: int) -> void:
	_bits.erase(id)


## Builds the mesh once every shard is added. Body 0 is the world: shards
## that stand belong to it. Ids from `hidden_from` on start out not drawn.
func build(shards: int, bodies: int, hidden_from: int) -> void:
	mesh = _surface()
	# Shards move far from where the mesh has them: never cull it.
	custom_aabb = AABB(Vector3.ONE * -500.0, Vector3.ONE * 1000.0)
	vertex_count = _verts.size()
	var rows := maxi(ceili(float(shards) / WIDTH), 1)
	_slots.resize(WIDTH * rows)
	_slots.fill(0.0)
	for k in range(hidden_from, _slots.size()):
		_slots[k] = -1.0
	_slot_image = Image.create_from_data(WIDTH, rows, false, Image.FORMAT_RF, _slots.to_byte_array())
	_slot_texture = ImageTexture.create_from_image(_slot_image)
	var body_rows := maxi(ceili(bodies * 2.0 / WIDTH), 1)
	_bodies.resize(WIDTH * body_rows * 4)
	_bodies.fill(0.0)
	for b in _bodies.size() / BODY_FLOATS:
		_bodies[b * BODY_FLOATS + 3] = 1.0  # full size
		_bodies[b * BODY_FLOATS + 7] = 1.0  # no rotation
	_body_image = Image.create_from_data(WIDTH, body_rows, false, Image.FORMAT_RGBAF, _bodies.to_byte_array())
	_body_texture = ImageTexture.create_from_image(_body_image)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("slot_of", _slot_texture)
	mat.set_shader_parameter("bodies", _body_texture)
	mat.set_shader_parameter("grid", load(TEXTURES + "light/texture_07.png"))
	material_override = mat
	_clear()
	_crumbs = MeshInstance3D.new()
	_crumbs.material_override = mat
	_crumbs.custom_aabb = custom_aabb
	add_child(_crumbs)


## Shard `shard` now moves with body `slot` (0: the world, -1: hidden).
func set_slot(shard: int, slot: int) -> void:
	_slots[shard] = slot
	_slots_changed = true


## Body `slot` is at `xf`; `origin` is where its own origin was in the whole
## building (shards keep their place around it). `size`: drawn that much
## smaller around its origin.
func set_body(slot: int, xf: Transform3D, origin: Vector3, size := 1.0) -> void:
	var o := slot * BODY_FLOATS
	var at := xf.origin - xf.basis * origin * size
	var q := xf.basis.get_rotation_quaternion()
	_bodies[o] = at.x
	_bodies[o + 1] = at.y
	_bodies[o + 2] = at.z
	_bodies[o + 3] = size
	_bodies[o + 4] = q.x
	_bodies[o + 5] = q.y
	_bodies[o + 6] = q.z
	_bodies[o + 7] = q.w
	_bodies_changed = true


func _process(_delta: float) -> void:
	if _crumbs_changed:
		_crumbs_changed = false
		for bit: Array in _bits.values():
			var from := _verts.size()
			_verts.append_array(bit[0])
			_normals.append_array(bit[1])
			_colors.append_array(bit[2])
			_uvs.append_array(bit[3])
			for index: int in bit[4]:
				_indices.append(from + index)
		_crumbs.mesh = _surface() if not _verts.is_empty() else null
		_clear()
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


func _clear() -> void:
	_verts = PackedVector3Array()
	_normals = PackedVector3Array()
	_colors = PackedColorArray()
	_uvs = PackedVector2Array()
	_indices = PackedInt32Array()


## A mesh of what has been added so far.
func _surface() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_INDEX] = _indices
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m
