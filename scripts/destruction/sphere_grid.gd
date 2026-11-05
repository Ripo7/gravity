class_name SphereGrid
extends RefCounted
## Uniform grid of bounding spheres: which items may reach within a radius
## of a point, without testing them all. Items are ids (ints) with a centre
## and a radius; nothing is ever removed (callers skip ids that are gone).

var cell := 2.0
var _cells := {}  ## Vector3i -> PackedInt32Array of ids
var _centre := PackedVector3Array()
var _radius := PackedFloat32Array()


func _init(cell_size := 2.0) -> void:
	cell = cell_size


func insert(id: int, centre: Vector3, radius: float) -> void:
	if id >= _centre.size():
		_centre.resize(id + 1)
		_radius.resize(id + 1)
	_centre[id] = centre
	_radius[id] = radius
	var lo := Vector3i(((centre - Vector3.ONE * radius) / cell).floor())
	var hi := Vector3i(((centre + Vector3.ONE * radius) / cell).floor())
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for z in range(lo.z, hi.z + 1):
				var key := Vector3i(x, y, z)
				if not _cells.has(key):
					_cells[key] = PackedInt32Array()
				_cells[key].append(id)


## Ids whose sphere reaches within `radius` of `p`, each once.
func query(p: Vector3, radius: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var seen := {}
	var lo := Vector3i(((p - Vector3.ONE * radius) / cell).floor())
	var hi := Vector3i(((p + Vector3.ONE * radius) / cell).floor())
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for z in range(lo.z, hi.z + 1):
				var ids: Variant = _cells.get(Vector3i(x, y, z))
				if ids == null:
					continue
				for i: int in ids:
					if not seen.has(i):
						seen[i] = true
						if _centre[i].distance_to(p) <= radius + _radius[i]:
							out.append(i)
	return out
