class_name StructureMesh
extends RefCounted
## How StructureSet draws its blocks: one MultiMesh of boxes, one of
## cylinders (columns) and one per carved piece (ShapeLibrary), all with the
## block shader, one row of floats per block (layout: shaders/block.gdshader).
## A falling piece of building draws its boxes (stones, mostly) with a
## MultiMesh of its own, laid out in the piece's body space once and moved
## as one: a frame costs one transform per piece, not one per stone (see
## body_mesh). Wall cells are drawn by WallCells.

const FLOATS := 20  # 12 transform + 4 colour + 4 custom
## Finishes of wall panels: no chamfer.
const WALL_FINISHES := [
	Materials.Finish.STONE,
	Materials.Finish.BRICK,
	Materials.Finish.PLASTER_OCHRE,
	Materials.Finish.PLASTER_ROSE,
	Materials.Finish.PLASTER_SIENNA,
	Materials.Finish.PLASTER_CREAM,
]

var boxes: MultiMesh
var columns: MultiMesh
var pieces: Array[MultiMesh] = []  ## per ShapeLibrary piece (index - 1)
var _buffer := PackedFloat32Array()
var _rbuffer := PackedFloat32Array()
var _pbuffers: Array[PackedFloat32Array] = []
var _dirty := false
var _parent: Node3D
var _material: Material
var _spare: Array[MultiMeshInstance3D] = []  ## body meshes not in use


func _init(parent: Node3D, material: Material) -> void:
	_parent = parent
	_material = material
	boxes = _make(parent, material, bevelled_box(), "StructureMesh")
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
## space + 1, zero if never), or, `falling`, where it stood (its pattern
## stays as it was).
func write(
	i: int,
	round_slot: int,
	piece: int,
	xf: Transform3D,
	size: Vector3,
	shade: float,
	seed_value: float,
	custom: float,
	hit: Vector3,
	falling := false
) -> void:
	var dst := _target(round_slot, piece)
	var o := (round_slot if round_slot >= 0 else i) * FLOATS
	fill_row(dst, o, xf, size, shade, seed_value, custom, hit, falling)
	if round_slot >= 0:
		# Round: patterns wrap round it (1 = fluted shaft, 0.75 = turned piece).
		dst[o + 13] = 1.0 if piece == 0 else (0.75 if ShapeLibrary.is_turned(piece) else 0.0)
	_dirty = true


## Writes the row of a box at `xf` into `dst` at `o` (see write).
static func fill_row(
	dst: PackedFloat32Array,
	o: int,
	xf: Transform3D,
	size: Vector3,
	shade: float,
	seed_value: float,
	custom: float,
	hit: Vector3,
	falling: bool
) -> void:
	var b := xf.basis
	dst[o] = b.x.x * size.x
	dst[o + 1] = b.y.x * size.y
	dst[o + 2] = b.z.x * size.z
	dst[o + 3] = xf.origin.x
	dst[o + 4] = b.x.y * size.x
	dst[o + 5] = b.y.y * size.y
	dst[o + 6] = b.z.y * size.z
	dst[o + 7] = xf.origin.y
	dst[o + 8] = b.x.z * size.x
	dst[o + 9] = b.y.z * size.y
	dst[o + 10] = b.z.z * size.z
	dst[o + 11] = xf.origin.z
	dst[o + 12] = shade
	dst[o + 13] = 0.0
	dst[o + 14] = fposmod(seed_value, 1.0)
	# Chamfer (metres): trim and carved stone, not the wall panels (their
	# edges meet the next panel in one plane and would show as grooves).
	# Falling, every stone shows its edges; plus 0.5 tells the shader so.
	var fin := Materials.finish_of(seed_value)
	dst[o + 15] = 0.525 if falling else (0.0 if fin in WALL_FINISHES else 0.025)
	dst[o + 16] = custom
	dst[o + 17] = hit.x
	dst[o + 18] = hit.y
	dst[o + 19] = hit.z


func clear(i: int, round_slot: int, piece: int) -> void:
	var dst := _target(round_slot, piece)
	var o := (round_slot if round_slot >= 0 else i) * FLOATS
	for k in FLOATS:
		dst[o + k] = 0.0
	_dirty = true


## A MultiMesh of boxes for a falling piece, its rows `rows` (body space,
## `count` of them, within `bounds`): the caller moves the node with the
## body. Give it back with free_body_mesh.
func body_mesh(rows: PackedFloat32Array, count: int, bounds: AABB) -> MultiMeshInstance3D:
	var mmi: MultiMeshInstance3D = _spare.pop_back() if not _spare.is_empty() else null
	if mmi == null:
		mmi = MultiMeshInstance3D.new()
		mmi.name = "FallingPiece"
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = boxes.mesh
		mmi.multimesh = mm
		mmi.material_override = _material
		_parent.add_child(mmi)
	refill(mmi, rows, count, bounds)
	mmi.visible = true
	return mmi


## New rows for a falling piece's mesh (it lost some of its blocks).
func refill(mmi: MultiMeshInstance3D, rows: PackedFloat32Array, count: int, bounds: AABB) -> void:
	var mm := mmi.multimesh
	if mm.instance_count < count:
		mm.instance_count = maxi(count, mm.instance_count * 2)
	var full := rows
	if count < mm.instance_count:
		full = rows.duplicate()
		full.resize(mm.instance_count * FLOATS)
		for k in range(count * FLOATS, full.size()):
			full[k] = 0.0
	mm.buffer = full
	mm.visible_instance_count = count
	mm.custom_aabb = bounds


func free_body_mesh(mmi: MultiMeshInstance3D) -> void:
	if mmi == null:
		return
	mmi.visible = false
	mmi.multimesh.visible_instance_count = 0
	_spare.append(mmi)


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


## A unit box with chamfered edges: every face, the strip along every edge
## and a triangle at every corner. UV2.x flags (bits 1, 2, 4 = x, y, z) the
## axes on which the block shader pulls a vertex in by the chamfer, in
## metres whatever the block's size (shaders/block.gdshader, `bevel`).
static func bevelled_box() -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var flags := PackedVector2Array()
	var index := PackedInt32Array()
	var axes: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	# Corner of sign s, belonging to face k: pulled in on the other two axes.
	var corner := func(s: Vector3, k: int, n: Vector3) -> int:
		verts.append(s * 0.5)
		normals.append(n.normalized())
		flags.append(Vector2(float(7 & ~(1 << k)), 0.0))
		return verts.size() - 1
	var polygon := func(ids: Array, outward: Vector3) -> void:
		# Godot draws clockwise faces: the cross product points inward.
		for t in range(1, ids.size() - 1):
			var tri: Array = [ids[0], ids[t], ids[t + 1]]
			# Positions with a sample chamfer, to tell the winding apart.
			var pts: Array[Vector3] = []
			for v: int in tri:
				var f := int(flags[v].x)
				var m := Vector3(f & 1, (f >> 1) & 1, (f >> 2) & 1)
				pts.append(verts[v] - verts[v].sign() * m * 0.1)
			if (pts[1] - pts[0]).cross(pts[2] - pts[0]).dot(outward) > 0.0:
				tri = [tri[0], tri[2], tri[1]]
			index.append_array(PackedInt32Array(tri))
	for k in 3:
		for side: float in [-1.0, 1.0]:
			var n := axes[k] * side
			var a := axes[(k + 1) % 3]
			var b := axes[(k + 2) % 3]
			var ids: Array = []
			for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				ids.append(corner.call(n + a * c.x + b * c.y, k, n))
			polygon.call(ids, n)
	# Edge strips: edge along axis e, on the faces of axes a and b.
	for e in 3:
		var a := (e + 1) % 3
		var b := (e + 2) % 3
		for sa: float in [-1.0, 1.0]:
			for sb: float in [-1.0, 1.0]:
				var na := axes[a] * sa
				var nb := axes[b] * sb
				var ids: Array = []
				for k_end: Array in [[-1.0, a], [1.0, a], [1.0, b], [-1.0, b]]:
					var s := na + nb + axes[e] * float(k_end[0])
					ids.append(corner.call(s, int(k_end[1]), na + nb))
				polygon.call(ids, na + nb)
	# Corner triangles.
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var s := Vector3(sx, sy, sz)
				polygon.call([corner.call(s, 0, s), corner.call(s, 1, s), corner.call(s, 2, s)], s)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV2] = flags
	arrays[Mesh.ARRAY_INDEX] = index
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


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
