@tool
class_name Structure
extends Node3D
## A destructible structure placed in a scene. It only describes its blocks;
## StructureSet owns the physics bodies and rendering at runtime.
## Move, rotate and tweak these nodes in the editor to lay out an arena.

enum Kind { WALL, TOWER, STACK, PILLARS }

@export var kind := Kind.WALL:
	set(v):
		kind = v
		_refresh_preview()
## WALL: (columns, rows, -). TOWER: (blocks per side, layers, -).
## STACK: (base x, -, base z). PILLARS: (pillars, drums per pillar, -).
@export var counts := Vector3i(8, 6, 1):
	set(v):
		counts = v
		_refresh_preview()
@export var block := Vector3(1.0, 0.5, 0.5):
	set(v):
		block = v
		_refresh_preview()
@export var strength := 3.0
@export var material := Materials.Kind.CONCRETE:
	set(v):
		material = v
		_refresh_preview()
## Used for tower floor slabs and colonnade lintels.
@export var accent_material := Materials.Kind.CONCRETE
@export var seed_value := 0

var _preview: MultiMeshInstance3D


func _ready() -> void:
	add_to_group("structures")
	_refresh_preview()


## Local-space block list consumed by StructureSet.add_structure.
func build_segments() -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + int(kind)
	var out: Array[Dictionary] = []
	match kind:
		Kind.WALL:
			_build_wall(out)
		Kind.TOWER:
			_build_tower(out)
		Kind.STACK:
			_build_stack(out)
		Kind.PILLARS:
			_build_pillars(out)
	for seg in out:
		seg["strength"] = seg.get("strength", strength)
		seg["material"] = seg.get("material", material)
		seg["shade"] = rng.randf_range(0.93, 1.04)
		seg["seed"] = rng.randf()
	return out


func _seg(out: Array[Dictionary], center: Vector3, size: Vector3, mult := 1.0, accent := false) -> void:
	var seg := {"local": Transform3D(Basis(), center), "size": size, "strength": strength * mult}
	if accent:
		seg["material"] = accent_material
	out.append(seg)


## Running-bond brick wall centred on x, standing on y=0.
func _build_wall(out: Array[Dictionary]) -> void:
	var cols := counts.x
	var w := cols * block.x
	for row in counts.y:
		var y := (row + 0.5) * block.y
		var x0 := -w * 0.5
		if row % 2 == 1:
			_seg(out, Vector3(x0 + block.x * 0.25, y, 0), Vector3(block.x * 0.5, block.y, block.z))
			x0 += block.x * 0.5
			for c in cols - 1:
				_seg(out, Vector3(x0 + (c + 0.5) * block.x, y, 0), block)
			_seg(out, Vector3(w * 0.5 - block.x * 0.25, y, 0), Vector3(block.x * 0.5, block.y, block.z))
		else:
			for c in cols:
				_seg(out, Vector3(x0 + (c + 0.5) * block.x, y, 0), block)


## Hollow square tower with window gaps and a floor slab every 4 layers.
func _build_tower(out: Array[Dictionary]) -> void:
	var n := maxi(counts.x, 2)
	var side := n * block.x
	var half := side * 0.5
	var t := block.z
	for layer in counts.y:
		var y := (layer + 0.5) * block.y
		var window_row := layer % 4 == 2 and layer < counts.y - 1
		for i in n:
			var along := -half + (i + 0.5) * block.x
			var is_window := window_row and i == int(n / 2.0)
			# Front/back run the full width, sides fit between them.
			if not is_window:
				_seg(out, Vector3(along, y, half - t * 0.5), Vector3(block.x, block.y, t))
				_seg(out, Vector3(-along, y, -half + t * 0.5), Vector3(block.x, block.y, t))
			var inner := side - 2.0 * t
			var piece := inner / n
			var z := -half + t + (i + 0.5) * piece
			if not is_window or layer % 8 == 6:
				_seg(out, Vector3(half - t * 0.5, y, z), Vector3(t, block.y, piece))
				_seg(out, Vector3(-half + t * 0.5, y, -z), Vector3(t, block.y, piece))
		if layer % 4 == 3:
			var slab_y := (layer + 1) * block.y + 0.1
			var inner_side := side - 2.0 * t
			var q := inner_side * 0.5
			for sx: float in [-0.5, 0.5]:
				for sz: float in [-0.5, 0.5]:
					_seg(out, Vector3(sx * q, slab_y - 0.1, sz * q), Vector3(q, 0.2, q), 0.8, true)


## Pyramid of crates.
func _build_stack(out: Array[Dictionary]) -> void:
	var layer := 0
	var nx := counts.x
	var nz := maxi(counts.z, 1)
	while nx > 0 and nz > 0:
		var y := (layer + 0.5) * block.y
		for ix in nx:
			for iz in nz:
				var x := (ix - (nx - 1) * 0.5) * block.x
				var z := (iz - (nz - 1) * 0.5) * block.z
				_seg(out, Vector3(x, y, z), block)
		nx -= 1
		nz -= 1
		layer += 1


## Colonnade: pillars of stacked drums with lintels across the tops.
func _build_pillars(out: Array[Dictionary]) -> void:
	var gap := block.x * 3.0
	var top := counts.y * block.y
	for p in counts.x:
		var x := (p - (counts.x - 1) * 0.5) * gap
		for d in counts.y:
			_seg(out, Vector3(x, (d + 0.5) * block.y, 0), Vector3(block.x, block.y, block.z))
	for p in counts.x - 1:
		var x := (p + 0.5 - (counts.x - 1) * 0.5) * gap
		_seg(out, Vector3(x, top + 0.25, 0), Vector3(gap + block.x, 0.5, block.z * 1.1), 1.5, true)


## Editor-only preview so the layout is visible while editing scenes.
func _refresh_preview() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _preview == null:
		_preview = MultiMeshInstance3D.new()
		add_child(_preview)
	var segs := build_segments()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	mm.mesh = box
	mm.instance_count = segs.size()
	for i in segs.size():
		var xf: Transform3D = segs[i]["local"]
		mm.set_instance_transform(i, xf.scaled_local(segs[i]["size"]))
	_preview.multimesh = mm
