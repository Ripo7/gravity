@tool
class_name Structure
extends Node3D
## A destructible structure placed in a scene. It only describes its blocks;
## StructureSet owns the physics bodies and rendering at runtime.
## Move, rotate and tweak these nodes in the editor to lay out an arena.

enum Kind { WALL, TOWER, STACK, PILLARS, BUILDING, RAMP, BRIDGE, APARTMENT }

const LANDING_DEPTH := 2.0
const SLAB := 0.3

@export var kind := Kind.WALL:
	set(v):
		kind = v
		_refresh_preview()
## WALL: (columns, rows, -). TOWER: (blocks per side, layers, -).
## STACK: (base x, -, base z). PILLARS: (pillars, drums per pillar, -).
## BUILDING: (bays along x, storeys, bays along z); block = (bay width,
## storey height, column width).
## RAMP: (-, flights, -); block = (lane width, rise per flight, run). A
## switchback ramp tower whose origin is its corner: lanes along +x, flights
## along +z, landings every `rise` metres (match a building's storeys).
## BRIDGE: (spans, column drums, -); block = (span length, drum height,
## deck width). A walkway along x on columns, deck top at drums * height + 0.3.
## APARTMENT: (bays along x, storeys, bays along z); block = (bay width,
## storey height, column width). A closed city building: ribbon windows
## above a sill band, some solid bays, open shop fronts on the ground floor,
## a floor slab per storey and a roof parapet. `doors` opens more bays.
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
## Counts toward the level's destruction score.
@export var scored := true
## APARTMENT: extra open bays, each (side, bay, storey); sides are
## 0 = -z, 1 = +z, 2 = -x, 3 = +x.
@export var doors := PackedVector3Array():
	set(v):
		doors = v
		_refresh_preview()

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
		Kind.BUILDING:
			_build_building(out)
		Kind.RAMP:
			_build_ramp(out)
		Kind.BRIDGE:
			_build_bridge(out)
		Kind.APARTMENT:
			_build_apartment(out, rng)
	for seg in out:
		seg["strength"] = seg.get("strength", strength)
		seg["material"] = seg.get("material", material)
		seg["shade"] = rng.randf_range(0.93, 1.04)
		seg["seed"] = rng.randf()
	return out


func _seg(
	out: Array[Dictionary],
	center: Vector3,
	size: Vector3,
	mult := 1.0,
	accent := false,
	basis := Basis(),
) -> void:
	var seg := {"local": Transform3D(basis, center), "size": size, "strength": strength * mult}
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


## Hollow square tower with window gaps. Every 4 layers a floor slab spans
## the whole tower and rests on the walls; the next layers stand on it.
func _build_tower(out: Array[Dictionary]) -> void:
	var n := maxi(counts.x, 2)
	var side := n * block.x
	var half := side * 0.5
	var t := block.z
	var slab_t := 0.2
	var base := 0.0
	for layer in counts.y:
		var y := base + 0.5 * block.y
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
		base += block.y
		if layer % 4 == 3 and layer < counts.y - 1:
			var q := side * 0.5
			for sx: float in [-0.5, 0.5]:
				for sz: float in [-0.5, 0.5]:
					_seg(out, Vector3(sx * q, base + slab_t * 0.5, sz * q), Vector3(q, slab_t, q), 0.8, true)
			base += slab_t


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


## Frame building: columns at every bay corner, a floor slab per bay on
## each storey, and some facade panels (accent material) between columns.
func _build_building(out: Array[Dictionary]) -> void:
	var bay := block.x
	var storey := block.y
	var cw := block.z
	var slab_t := 0.25
	var nx := maxi(counts.x, 1)
	var nz := maxi(counts.z, 1)
	var x0 := -nx * bay * 0.5
	var z0 := -nz * bay * 0.5
	var col_h := storey - slab_t
	for s in counts.y:
		var base := s * storey
		for ix in nx + 1:
			for iz in nz + 1:
				var c := Vector3(x0 + ix * bay, base + col_h * 0.5, z0 + iz * bay)
				_seg(out, c, Vector3(cw, col_h, cw), 1.2)
		# Facade panels on the long sides, every other bay, offset per storey.
		for ix in nx:
			if (ix + s) % 2 == 1:
				continue
			var px := x0 + (ix + 0.5) * bay
			var panel := Vector3(bay - cw, col_h, 0.12)
			_seg(out, Vector3(px, base + col_h * 0.5, z0), panel, 0.5, true)
			_seg(out, Vector3(px, base + col_h * 0.5, -z0), panel, 0.5, true)
		for ix in nx:
			for iz in nz:
				var c := Vector3(x0 + (ix + 0.5) * bay, base + col_h + slab_t * 0.5, z0 + (iz + 0.5) * bay)
				_seg(out, c, Vector3(bay, slab_t, bay), 0.9)


func _build_apartment(out: Array[Dictionary], rng: RandomNumberGenerator) -> void:
	var bay := block.x
	var storey := block.y
	var cw := block.z
	var slab_t := 0.25
	var wall_t := 0.22
	var sill := 1.05
	var nx := maxi(counts.x, 1)
	var nz := maxi(counts.z, 1)
	var x0 := -nx * bay * 0.5
	var z0 := -nz * bay * 0.5
	var col_h := storey - slab_t
	var open := {}
	for d in doors:
		open[Vector3i(d)] = true
	for s in counts.y + 1:
		var base := s * storey
		var roof := s == counts.y
		if not roof:
			for ix in nx + 1:
				for iz in nz + 1:
					var c := Vector3(x0 + ix * bay, base + col_h * 0.5, z0 + iz * bay)
					_seg(out, c, Vector3(cw, col_h, cw), 1.2)
		for side in 4:
			var along_x := side < 2
			var n := nx if along_x else nz
			for b in n:
				var t := (b + 0.5) * bay
				var c := Vector3(x0 + t, 0, z0 if side == 0 else -z0)
				if not along_x:
					c = Vector3(x0 if side == 2 else -x0, 0, z0 + t)
				var w := bay - cw
				var size_of := func(h: float) -> Vector3:
					return Vector3(w, h, wall_t) if along_x else Vector3(wall_t, h, w)
				var roll := rng.randf()
				if open.has(Vector3i(side, b, s)) or (s == 0 and roll < 0.45):
					continue
				if roof:
					c.y = base + 0.45
					_seg(out, c, size_of.call(0.9), 0.5, true)
					continue
				if roll > 0.8:
					c.y = base + col_h * 0.5
					_seg(out, c, size_of.call(col_h), 0.6, true)
				else:
					c.y = base + sill * 0.5
					_seg(out, c, size_of.call(sill), 0.5, true)
		if roof:
			break
		for ix in nx:
			for iz in nz:
				var c := Vector3(x0 + (ix + 0.5) * bay, base + col_h + slab_t * 0.5, z0 + (iz + 0.5) * bay)
				_seg(out, c, Vector3(bay, slab_t, bay), 0.9)


func _build_ramp(out: Array[Dictionary]) -> void:
	var w := block.x
	var rise := block.y
	var run := block.z
	var d := LANDING_DEPTH
	var a := atan2(rise, run)
	var length := sqrt(rise * rise + run * run)
	var flights := maxi(counts.y, 1)
	for k in flights:
		var lane := float(k % 2)
		var x := (lane + 0.5) * w
		var up_z := k % 2 == 0  # even flights climb toward +z
		var z0 := d if up_z else d + run
		var z1 := d + run if up_z else d
		var top_mid := Vector3(x, (k + 0.5) * rise, (z0 + z1) * 0.5)
		var basis := Basis(Vector3.RIGHT, -a if up_z else a)
		var center := top_mid - basis.y * SLAB * 0.5
		_seg(out, center, Vector3(w - 0.05, SLAB, length), 1.0, false, basis)
	for j in range(1, flights + 1):
		var at_far := j % 2 == 1
		var zc := d + run + d * 0.5 if at_far else d * 0.5
		var top := j * rise
		_seg(out, Vector3(w, top - SLAB * 0.5, zc), Vector3(w * 2.0, SLAB, d), 1.0, true)
		# Columns under the outer corners, standing on the landing two
		# levels down (or the ground).
		var base := maxf(top - 2.0 * rise, 0.0)
		var h := top - SLAB - base
		var zo := zc + (d * 0.5 - 0.25) * (1.0 if at_far else -1.0)
		for xo: float in [0.25, w * 2.0 - 0.25]:
			_seg(out, Vector3(xo, base + h * 0.5, zo), Vector3(0.5, h, 0.5), 1.4)


func _build_bridge(out: Array[Dictionary]) -> void:
	var spans := maxi(counts.x, 1)
	var span := block.x
	var drum := block.y
	var w := block.z
	var top := counts.y * drum
	var x0 := -spans * span * 0.5
	for j in spans + 1:
		var x := x0 + j * span
		for zs: float in [-1.0, 1.0]:
			for k in counts.y:
				_seg(out, Vector3(x, (k + 0.5) * drum, zs * (w * 0.5 - 0.35)), Vector3(0.7, drum, 0.7), 1.3)
	for j in spans:
		var a := x0 + j * span
		var b := a + span
		# The end pieces overhang a little to meet whatever they lead to.
		if j == 0:
			a -= 0.45
		if j == spans - 1:
			b += 0.45
		var piece_len := b - a
		var cx := (a + b) * 0.5
		_seg(out, Vector3(cx, top + SLAB * 0.5, 0), Vector3(piece_len, SLAB, w))
		for zs: float in [-1.0, 1.0]:
			_seg(
				out,
				Vector3(cx, top + SLAB + 0.25, zs * (w * 0.5 - 0.06)),
				Vector3(piece_len, 0.5, 0.12),
				0.6,
				true
			)


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
