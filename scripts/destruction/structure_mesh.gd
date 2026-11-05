class_name StructureMesh
extends RefCounted
## How StructureSet draws its blocks: one MultiMesh of boxes and one of
## cylinders (columns), both with the block shader, one row of floats per
## block (layout: shaders/block.gdshader). Wall cells are drawn by WallCells.

const FLOATS := 20  # 12 transform + 4 colour + 4 custom

var boxes: MultiMesh
var columns: MultiMesh
var _buffer := PackedFloat32Array()
var _rbuffer := PackedFloat32Array()
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


## Room for `box_count` blocks, `round_count` of them columns; all empty.
func resize(box_count: int, round_count: int) -> void:
	_buffer.resize(box_count * FLOATS)
	_buffer.fill(0.0)
	_rbuffer.resize(maxi(round_count, 1) * FLOATS)
	_rbuffer.fill(0.0)
	boxes.instance_count = box_count
	columns.instance_count = maxi(round_count, 1)
	_dirty = true


## Draws block `i` (in the column mesh at `round_slot` if that is >= 0; its
## box slot then stays empty). `custom` is Materials.custom; `hit` where it
## was first hit (unit space + 1, zero if never).
func write(
	i: int,
	round_slot: int,
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
	_row[13] = 1.0 if round_slot >= 0 else 0.0
	_row[14] = fposmod(seed_value, 1.0)
	_row[15] = 0.0
	_row[16] = custom
	_row[17] = hit.x
	_row[18] = hit.y
	_row[19] = hit.z
	var dst := _rbuffer if round_slot >= 0 else _buffer
	var o := (round_slot if round_slot >= 0 else i) * FLOATS
	for k in FLOATS:
		dst[o + k] = _row[k]
	_dirty = true


func clear(i: int, round_slot: int) -> void:
	var dst := _rbuffer if round_slot >= 0 else _buffer
	var o := (round_slot if round_slot >= 0 else i) * FLOATS
	for k in FLOATS:
		dst[o + k] = 0.0
	_dirty = true


## Sends what changed to the GPU (once a frame).
func flush() -> void:
	if _dirty:
		boxes.buffer = _buffer
		columns.buffer = _rbuffer
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
