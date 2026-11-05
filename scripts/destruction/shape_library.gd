class_name ShapeLibrary
extends RefCounted
## The palace's carved pieces, modelled in Blender by tools/make_sculptures.py
## (assets/shapes/shapes.json): column capitals and bases, cornice brackets,
## the bands of the dome, the bell. Each fits the unit cube, so a block with
## a "shape" is drawn as that piece stretched to the block (one MultiMesh
## per piece, same shader as every block) and still breaks like a block.

const PATH := "res://assets/shapes/shapes.json"
## Pieces turned round their axis: their patterns wrap round them.
const TURNED := ["capital", "base", "bell", "dome_0", "dome_1", "dome_2", "dome_3", "dome_4"]

static var names: Array[String] = []
static var meshes: Array[ArrayMesh] = []
static var _tried := false


## Loads the pieces once. False if the file is missing (blocks stay boxes).
static func ensure() -> bool:
	if _tried:
		return not names.is_empty()
	_tried = true
	var res: Variant = load(PATH) if ResourceLoader.exists(PATH) else null
	var data: Variant = (res as JSON).data if res is JSON else null
	if not data is Dictionary:
		push_warning("Shape library missing: %s" % PATH)
		return false
	var shapes: Dictionary = data["shapes"]
	for name: String in shapes:
		var s: Dictionary = shapes[name]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _vectors(s["vertices"])
		arrays[Mesh.ARRAY_NORMAL] = _vectors(s["normals"])
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(s["indices"])
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		names.append(name)
		meshes.append(mesh)
	return true


## 1 + the piece's index (0 = no such piece: the block stays as it was).
static func index(name: String) -> int:
	return names.find(name) + 1 if ensure() else 0


static func is_turned(k: int) -> bool:
	return k > 0 and names[k - 1] in TURNED


static func _vectors(flat: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for k in range(0, flat.size(), 3):
		out.append(Vector3(flat[k], flat[k + 1], flat[k + 2]))
	return out
