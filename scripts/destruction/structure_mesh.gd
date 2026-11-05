class_name StructureMesh
extends RefCounted
## How StructureSet draws its blocks: one MultiMesh of boxes, one of
## cylinders (columns) and one per carved piece (ShapeLibrary), all with the
## block shader, one row of floats per block (layout: shaders/block.gdshader).
## Wall cells are drawn by WallCells.

const FLOATS := 20  # 12 transform + 4 colour + 4 custom

var boxes: MultiMesh
var columns: MultiMesh
var pieces: Array[MultiMesh] = []  ## per ShapeLibrary piece (index - 1)
var _buffer := PackedFloat32Array()
var _rbuffer := PackedFloat32Array()
var _pbuffers: Array[PackedFloat32Array] = []
var _row := PackedFloat32Array()
var _dirty := false


func _init(parent: Node3D, material: Material) -> void:
	_row.resize(FLOATS)
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	boxes = _make(parent, material, box, "StructureMesh")
	# Columns: a unit cylinder, enough sides to read round up close.
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.5
	cyl.height = 1.0
	cyl.radial_segments = int(Quality.pick(12, 16, 20))
	cyl.rings = 1
	columns = _make(parent, material, cyl, "ColumnMesh")
	if ShapeLibrary.ensure():
		for k in ShapeLibrary.meshes.size():
			pieces.append(_make(parent, material, ShapeLibrary.meshes[k], ShapeLibrary.names[k]))
			_pbuffers.append(PackedFloat32Array())


## Room for `box_count` blocks, `round_count` of them columns and
## `piece_counts[k]` of them carved piece k + 1; all empty.
func resize(box_count: int, round_count: int, piece_counts: PackedInt32Array) -> void:
	_buffer.resize(box_count * FLOATS)
	_buffer.fill(0.0)
	_rbuffer.resize(maxi(round_count, 1) * FLOATS)
	_rbuffer.fill(0.0)
	boxes.instance_count = box_count
	columns.instance_count = maxi(round_count, 1)
	for k in pieces.size():
		var n := maxi(piece_counts[k] if k < piece_counts.size() else 0, 1)
		_pbuffers[k].resize(n * FLOATS)
		_pbuffers[k].fill(0.0)
		pieces[k].instance_count = n
	_dirty = true


## Draws block `i` (at `round_slot` in the column mesh, or in carved piece
## `piece`'s if that is > 0, when the slot is >= 0; its box slot then stays
## empty). `custom` is Materials.custom; `hit` where it was first hit (unit
## space + 1, zero if never).
func write(
	i: int,
	round_slot: int,
	piece: int,
	xf: Transform3D,
	size: Vector3,
	shade: float,
	seed_value: float,
	custom: float,
	hit: Vector3
) -> void:
	var b := xf.basis
	_row[0] = b.x.x * size.x
	_row[1] = b.y.x * size.y
	_row[2] = b.z.x * size.z
	_row[3] = xf.origin.x
	_row[4] = b.x.y * size.x
	_row[5] = b.y.y * size.y
	_row[6] = b.z.y * size.z
	_row[7] = xf.origin.y
	_row[8] = b.x.z * size.x
	_row[9] = b.y.z * size.y
	_row[10] = b.z.z * size.z
	_row[11] = xf.origin.z
	_row[12] = shade
	# Round: patterns wrap round it (1 = fluted shaft, 0.75 = turned piece).
	_row[13] = 0.0
	if round_slot >= 0:
		_row[13] = 1.0 if piece == 0 else (0.75 if ShapeLibrary.is_turned(piece) else 0.0)
	_row[14] = fposmod(seed_value, 1.0)
	_row[15] = 0.0
	_row[16] = custom
	_row[17] = hit.x
	_row[18] = hit.y
	_row[19] = hit.z
	var dst := _target(round_slot, piece)
	var o := (round_slot if round_slot >= 0 else i) * FLOATS
	for k in FLOATS:
		dst[o + k] = _row[k]
	_dirty = true


func clear(i: int, round_slot: int, piece: int) -> void:
	var dst := _target(round_slot, piece)
	var o := (round_slot if round_slot >= 0 else i) * FLOATS
	for k in FLOATS:
		dst[o + k] = 0.0
	_dirty = true


func _target(round_slot: int, piece: int) -> PackedFloat32Array:
	if round_slot < 0:
		return _buffer
	return _rbuffer if piece == 0 else _pbuffers[piece - 1]


## Sends what changed to the GPU (once a frame).
func flush() -> void:
	if _dirty:
		boxes.buffer = _buffer
		columns.buffer = _rbuffer
		for k in pieces.size():
			pieces[k].buffer = _pbuffers[k]
		_dirty = false


static func _make(parent: Node3D, material: Material, mesh: Mesh, label: String) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	# Fixed bounds over the arena: setting the buffer then does not walk
	# every instance to find them (it is re-sent while pieces fall).
	mm.custom_aabb = AABB(Vector3(-90, -45, -90), Vector3(180, 140, 180))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = label
	mmi.multimesh = mm
	mmi.material_override = material
	parent.add_child(mmi)
	return mm
