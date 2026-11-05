class_name ShardLibrary
extends RefCounted
## How concrete, wood and metal break: patterns of shards cut in Blender by
## tools/make_shards.py (assets/shards/shards.json).
##
## Every shard of every pattern shares one vertex layout, so all of them are
## drawn with a single mesh: the shape of each shard lives in a texture row
## the block shader reads by vertex index. Each shard also carries its
## collision hull (a handful of points) and its volume.
##
## Patterns live in a unit cube. To break a block, a pattern is turned so
## its x axis follows the grain (wood, metal: the block's longest axis),
## then stretched to the block's size.

const PATH := "res://assets/shards/shards.json"
const KINDS := {
	Materials.Kind.CONCRETE: "concrete",
	Materials.Kind.WOOD: "wood",
	Materials.Kind.METAL: "metal",
}

static var mesh: ArrayMesh
static var shapes: ImageTexture
static var _patterns := {}  # kind -> Array[Array[Dictionary]]
static var _tried := false


## Loads the library once. False if it is missing (then blocks break into
## boxes, as before).
static func ensure() -> bool:
	if _tried:
		return mesh != null
	_tried = true
	var res: Variant = load(PATH) if ResourceLoader.exists(PATH) else null
	var data: Variant = (res as JSON).data if res is JSON else null
	if not data is Dictionary:
		push_warning("Shard library missing: %s" % PATH)
		return false
	_build(data)
	return true


static func has(kind: int) -> bool:
	return ensure() and _patterns.has(kind)


## A pattern for `kind` with about `count` pieces; `variant` picks among
## the patterns of that size.
static func pattern(kind: int, count: int, variant: int) -> Array:
	var list: Array = _patterns[kind]
	var best := 1 << 30
	var options: Array = []
	for p: Array in list:
		var d := absi(p.size() - count)
		if d < best:
			best = d
			options = [p]
		elif d == best:
			options.append(p)
	return options[variant % options.size()]


## Turns pattern space so its x axis lies along `axis` of the block (a
## rotation, never a mirror: mirrored shards would be drawn inside out).
static func axis_turn(axis: int, flip: bool) -> Basis:
	var cols := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	var b := Basis(cols[axis], cols[(axis + 1) % 3], cols[(axis + 2) % 3])
	if flip:
		b = b * Basis(Vector3.RIGHT, PI)
	return b


static func _build(d: Dictionary) -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var base: Array = d["base_vertices"]
	for k in range(0, base.size(), 3):
		var p := Vector3(base[k], base[k + 1], base[k + 2])
		verts.append(p)
		# Normal of the cube face the point is on (used when a piece is
		# drawn as a plain chunk, not a shard).
		var a := p.abs()
		var n := Vector3.ZERO
		var axis := a.max_axis_index()
		n[axis] = signf(p[axis])
		normals.append(n)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(d["indices"])
	mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var bytes := Marshalls.base64_to_raw(d["shapes_rgba16f_b64"])
	var img := Image.create_from_data(
		int(d["vertex_count"]), int(d["shard_count"]), false, Image.FORMAT_RGBAH, bytes
	)
	shapes = ImageTexture.create_from_image(img)
	for kind: int in KINDS:
		var list: Array = []
		for p: Dictionary in d["materials"].get(KINDS[kind], []):
			var shards: Array = []
			for s: Dictionary in p["shards"]:
				var hull := PackedVector3Array()
				var h: Array = s["hull"]
				for k in range(0, h.size(), 3):
					hull.append(Vector3(h[k], h[k + 1], h[k + 2]))
				(
					shards
					. append(
						{
							"id": int(s["id"]),
							"center": Vector3(s["center"][0], s["center"][1], s["center"][2]),
							"size": Vector3(s["size"][0], s["size"][1], s["size"][2]),
							"hull": hull,
							"volume": float(s["volume"]),
						}
					)
				)
			list.append(shards)
		if not list.is_empty():
			_patterns[kind] = list
