class_name WallCells
extends RefCounted
## Walls that crack open in place. A wall panel (a big flat block) that
## breaks is replaced by the cells of a wall pattern cut in Blender (prisms
## through its thickness, tools/make_shards.py): the cells round the hit
## become debris, the others stay up as blocks of their own, linked to each
## other along the faces they share and to whatever the panel touched. So a
## hole has ragged edges that cross the stone joints, and the rest of the
## wall can go on falling a cell at a time.
##
## Cells are drawn with the debris mesh and material (one draw call for all
## of them), in their wall's own axes so the plaster or the stone courses
## run on across them exactly as on the panel.

const MIN_VOLUME := 1.2  ## m^3: smaller blocks just shatter
const MAX_THICKNESS := 1.3  ## m
const MIN_SIDE := 1.0  ## m: both sides of the face at least this
## m^2 of face per cell aimed for, by quality tier (fewer bodies on phones).
const CELL_AREA := Vector3(1.6, 1.1, 0.75)
const HOLE := 1.1  ## m beyond the nearest point of the wall that breaks out
const PUSH := 0.9  ## m/s the broken cells fly out at
const SUPPORT_SLOPE := 0.35  ## a shared face this far from upright carries weight
## A cell's share of the panel's capacity, at least / at most.
const SHARE := Vector2(0.2, 1.0)
const FLOATS := 20
## Walls cracked per physics step at most (each adds up to 28 bodies); past
## that a wall shatters the old way (a building coming down all at once).
const MAX_PER_STEP := 2
## Fewer free debris slots than this: broken-out cells crumble to gravel.
const FULL_POOL := 12
## Pattern turns: the patterns are cut with the thickness along z; a wall
## thin along x turns them a quarter round y (a rotation, never a mirror).
const TURNS: Array[Basis] = [Basis.IDENTITY, Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0))]

var capacity := 0
var cracked := 0  ## walls cracked so far
var cell_area := 0.75
var _left := MAX_PER_STEP
var _set: StructureSet
var _mm: MultiMesh
var _buffer := PackedFloat32Array()
var _dirty := false
var _free: Array[int] = []
var _used := 0
var _cells := {}  # block -> [slot, shard, panel size, turn index]
var _shapes := {}  # key -> convex hull shape RID


func _init(structures: StructureSet) -> void:
	_set = structures
	capacity = int(Quality.pick(1200, 2500, 4000))
	cell_area = float(Quality.pick(CELL_AREA.x, CELL_AREA.y, CELL_AREA.z))


func free_shapes() -> void:
	for rid: RID in _shapes.values():
		PhysicsServer3D.free_rid(rid)
	_shapes.clear()


func is_cell(i: int) -> bool:
	return _cells.has(i)


## True if block `i` is a wall panel that can crack open.
func can_crack(i: int) -> bool:
	if _cells.has(i) or _set._round[i] >= 0 or _set._kind[i] != Materials.Kind.CONCRETE:
		return false
	if _left <= 0 or not ShardLibrary.has_walls() or _set.debris == null or _used + 32 > capacity:
		return false
	var b := _set._xform[i].basis.orthonormalized()
	if absf(b.y.y) < 0.99:
		return false  # tilted (ramps, voussoirs)
	var size := _set._size[i]
	var thin := 0 if size.x < size.z else 2
	return (
		size[thin] <= MAX_THICKNESS
		and size.y >= MIN_SIDE
		and size[2 - thin] >= MIN_SIDE
		and size.x * size.y * size.z >= MIN_VOLUME
	)


## Cracks wall panel `i` open where `from` hit it with `dmg`.
func crack(i: int, from: Vector3, dmg: float, tint: float) -> void:
	var s := _set
	var size := s._size[i]
	var xf := s._xform[i]
	var basis := xf.basis.orthonormalized()
	var thin := 0 if size.x < size.z else 2
	var turn_index := 0 if thin == 2 else 1
	var width := size[2 - thin]
	var count := clampi(roundi(width * size.y / cell_area), 6, 28)
	var cells := ShardLibrary.wall_pattern(width / size.y, count)
	var to_block := Basis.from_scale(size) * TURNS[turn_index]
	var reach := s._surface_distance(i, from) + HOLE * clampf(0.75 + dmg * 0.05, 0.75, 1.6)
	var near := -1
	var near_d := INF
	for k in cells.size():
		var d := (xf * (to_block * (cells[k]["center"] as Vector3))).distance_to(from)
		if d < near_d:
			near_d = d
			near = k
	var group := s._group[i]
	var origin := s._group_origin[group]
	var local_xf := origin.affine_inverse() * Transform3D(basis, xf.origin)
	var outside := s._neighbors[i].duplicate()
	var hp := s._max_health[i]
	var mass_per_unit := s._mass[i]
	s._remove(i)
	cracked += 1
	_left -= 1
	var ids := PackedInt32Array()
	ids.resize(cells.size())
	var hole := AABB(from, Vector3.ZERO)
	for k in cells.size():
		var cell: Dictionary = cells[k]
		var rel := to_block * (cell["center"] as Vector3)
		var at := xf.origin + basis * rel
		if k == near or at.distance_to(from) <= reach:
			ids[k] = -1
			hole = hole.expand(at)
			var away := (at - from).normalized() * PUSH * randf_range(0.6, 1.3)
			if s.debris.free_slots() < FULL_POOL:
				# No room for more bodies: it crumbles (recycling pieces wakes
				# whole piles).
				var vol := mass_per_unit * float(cell["volume"]) / Materials.prop(s._kind[i], "density")
				var cell_size := (to_block * (cell["size"] as Vector3)).abs()
				s.debris.gravel(at, cell_size, s._kind[i], vol, 3.0, away, s._seed[i])
				continue
			var block := Transform3D(basis, xf.origin)
			var spin := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5)
			s.debris.spawn_shard(
				block, size, TURNS[turn_index], cell, away, spin, tint, s._shade[i], s._kind[i], s._seed[i]
			)
			continue
		var cell_size := (to_block * (cell["size"] as Vector3)).abs()
		var c := s.add_block(
			group,
			Transform3D(basis, at),
			local_xf * AABB(rel - cell_size * 0.5, cell_size),
			cell_size,
			s._kind[i],
			s._seed[i],
			s._shade[i],
			hp,
			mass_per_unit * float(cell["volume"]),
			_hull(cell, size, turn_index, to_block)
		)
		# Each cell carries its share of what the panel carried (the cells
		# of one column stand on each other, so shares overlap).
		var share := clampf(cell_size[2 - thin] / width * 1.5, SHARE.x, SHARE.y)
		s._capacity[c] = s._capacity[i] * share
		s._shear_cap[c] = s._shear_cap[i] * share
		_add(c, cell, size, turn_index)
		ids[k] = c
	_link_inside(cells, ids, size, turn_index)
	_link_outside(ids, outside)
	s.shattered.emit(hole.get_center(), hole.size + Vector3.ONE * 0.6, s._kind[i])
	s._dirty_groups[group] = true


## Sends cell `i` (no longer standing) to the debris as the shard it is.
func to_debris(i: int, xf: Transform3D, velocity: Vector3, spin: Vector3, tint: float) -> int:
	var info: Array = _cells[i]
	var cell: Dictionary = info[1]
	var size: Vector3 = info[2]
	var turn := TURNS[info[3]]
	var to_block := Basis.from_scale(size) * turn
	var basis := xf.basis.orthonormalized()
	# The panel the cell was cut from, wherever the cell is now.
	var block := Transform3D(basis, xf.origin - basis * (to_block * (cell["center"] as Vector3)))
	var s := _set
	return s.debris.spawn_shard(
		block, size, turn, cell, velocity, spin, tint, s._shade[i], s._kind[i], s._seed[i]
	)


func write(i: int, xf: Transform3D, damage: float) -> void:
	var info: Array = _cells[i]
	if info[0] < 0:
		return
	var o: int = info[0] * FLOATS
	var size: Vector3 = info[2]
	# The panel's axes and size: the shader turns and places the cell's shape.
	var b := xf.basis.orthonormalized() * Basis.from_scale(size)
	_buffer[o + 0] = b.x.x
	_buffer[o + 1] = b.y.x
	_buffer[o + 2] = b.z.x
	_buffer[o + 3] = xf.origin.x
	_buffer[o + 4] = b.x.y
	_buffer[o + 5] = b.y.y
	_buffer[o + 6] = b.z.y
	_buffer[o + 7] = xf.origin.y
	_buffer[o + 8] = b.x.z
	_buffer[o + 9] = b.y.z
	_buffer[o + 10] = b.z.z
	_buffer[o + 11] = xf.origin.z
	_buffer[o + 12] = _set._shade[i]
	_buffer[o + 13] = 0.0
	_buffer[o + 14] = fposmod(_set._seed[i], 1.0)
	_buffer[o + 15] = 0.0
	_buffer[o + 16] = Materials.custom(_set._kind[i], damage, _set._seed[i])
	_buffer[o + 17] = float((info[1] as Dictionary)["id"]) + 1.0
	_buffer[o + 18] = float(info[3]) + 1.0  # standing cell, and its turn
	_buffer[o + 19] = 0.0
	_dirty = true


## Stops drawing cell `i` (it stays known, to go to the debris as itself).
func clear(i: int) -> void:
	var info: Array = _cells[i]
	if info[0] < 0:
		return
	var o: int = info[0] * FLOATS
	for k in FLOATS:
		_buffer[o + k] = 0.0
	_dirty = true
	_free.append(info[0])
	info[0] = -1


## Once per physics step: uploads the cells and renews the crack budget.
func flush() -> void:
	_left = MAX_PER_STEP
	if _dirty:
		_mm.buffer = _buffer
		_mm.visible_instance_count = _used
		_dirty = false


func _add(c: int, cell: Dictionary, size: Vector3, turn_index: int) -> void:
	if _mm == null:
		_build_mesh()
	var slot := _used
	if not _free.is_empty():
		slot = _free.pop_back()
	else:
		_used += 1
	_cells[c] = [slot, cell, size, turn_index]
	write(c, _set._xform[c], 0.0)


func _build_mesh() -> void:
	_buffer.resize(capacity * FLOATS)
	_buffer.fill(0.0)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = ShardLibrary.mesh
	_mm.instance_count = capacity
	_mm.visible_instance_count = 0
	_mm.custom_aabb = AABB(Vector3(-90, -45, -90), Vector3(180, 140, 180))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "WallCells"
	mmi.multimesh = _mm
	mmi.material_override = _set.debris.material  # shards: same shader, same shapes
	_set.add_child(mmi)


## The cell's collision: its convex hull, in the panel's axes and size.
func _hull(cell: Dictionary, size: Vector3, turn_index: int, to_block: Basis) -> RID:
	var key := "%d/%s/%d" % [cell["id"], size.snappedf(0.01), turn_index]
	if not _shapes.has(key):
		var pts := PackedVector3Array()
		for p: Vector3 in cell["hull"]:
			pts.append(to_block * p * 0.995)
		var shape := PhysicsServer3D.convex_polygon_shape_create()
		PhysicsServer3D.shape_set_data(shape, pts)
		_shapes[key] = shape
	return _shapes[key]


## Cells touching along a shared face are neighbours; the lower one holds
## the upper one up when the face is far enough from upright.
func _link_inside(cells: Array, ids: PackedInt32Array, size: Vector3, turn_index: int) -> void:
	var thin := 2 if turn_index == 0 else 0
	var width := size[2 - thin]
	for k in cells.size():
		var a := ids[k]
		if a < 0:
			continue
		for link: Array in cells[k]["links"]:
			var b := ids[int(link[0])]
			if b < 0:
				continue
			# The face in metres: its edge across the face, times the thickness.
			var nx: float = link[2]
			var ny: float = link[3]
			var edge := Vector2(-ny * width, nx * size.y).length() * float(link[1])
			var normal := Vector2(nx / width, ny / size.y).normalized()
			var area := edge * size[thin]
			# Normal points from a to b: b is below a when it points down.
			var holds := area * -normal.y if normal.y < -SUPPORT_SLOPE else 0.0
			_set.link_blocks(a, b, holds)


## Cells touching what the panel touched take over its links (and what
## rested on the panel now rests on the cells under it).
func _link_outside(ids: PackedInt32Array, outside: PackedInt32Array) -> void:
	var s := _set
	var eps := StructureSet.CONTACT_EPS
	for c in ids:
		if c < 0:
			continue
		var mine := s._local[c].grow(eps)
		for n in outside:
			if s._state[n] == StructureSet.State.GONE or not mine.intersects(s._local[n]):
				continue
			var a := s._local[c]
			var b := s._local[n]
			var ox := minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x)
			var oz := minf(a.end.z, b.end.z) - maxf(a.position.z, b.position.z)
			var flat := ox * oz if ox > 0.01 and oz > 0.01 else 0.0
			if flat > 0.0 and absf(a.position.y - b.end.y) < eps:
				s.link_blocks(c, n, flat)
			elif flat > 0.0 and absf(b.position.y - a.end.y) < eps:
				s.link_blocks(n, c, flat)
			else:
				s.link_blocks(c, n)
