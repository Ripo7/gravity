@tool
class_name Structure
extends Node3D
## A destructible structure placed in a scene. It only describes its blocks;
## StructureSet owns the physics bodies and rendering at runtime.
## Move, rotate and tweak these nodes in the editor to lay out an arena.

enum Kind { WALL, TOWER, STACK, PILLARS, BUILDING, RAMP, BRIDGE, APARTMENT, ARCADE, KEEP, DOME }
## Which past the printers copied: decides every block's finish.
enum Style { MODERN, ROMAN, MEDIEVAL, RENAISSANCE }

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
## ARCADE: (arches, storeys, -); block = (span, pier height, depth). Stacked
## loggias of round arches (voussoirs) on piers, a cornice on each storey.
## KEEP: (blocks per side, courses, -); block = (block length, course
## height, wall thickness). A medieval tower: slit windows, floors, a
## projecting parapet with merlons.
## DOME: (sides, drum courses, dome rings); block = (radius, course height,
## wall thickness). A round church: a windowed drum, a stepped tiled dome
## and a lantern on top.
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
@export var style := Style.MODERN:
	set(v):
		style = v
		_refresh_preview()
## Counts toward the level's destruction score.
@export var scored := true
## BRIDGE: how far the deck reaches past the end columns.
@export var end_overhang := 0.0:
	set(v):
		end_overhang = v
		_refresh_preview()
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
			if style == Style.MODERN:
				_build_apartment(out, rng)
			else:
				_build_masonry(out, rng)
		Kind.ARCADE:
			_build_arcade(out)
		Kind.KEEP:
			_build_keep(out)
		Kind.DOME:
			_build_dome(out)
	for seg in out:
		seg["strength"] = seg.get("strength", strength)
		seg["material"] = seg.get("material", material)
		# Old styles are built of masonry whatever the materials asked for;
		# only full-height panels stay timber (shutters) or copper.
		var role: String = seg.get("role", "")
		if style != Style.MODERN and role != "panel" and seg["material"] != Materials.Kind.GLASS:
			seg["material"] = Materials.Kind.CONCRETE
		seg["shade"] = rng.randf_range(0.93, 1.04)
		# Masonry spreads its load over few piers: give it more reserve so a
		# lost pier does not bring the whole building down at once.
		if kind == Kind.APARTMENT and style != Style.MODERN:
			seg["robust"] = 3.0
		var finish: int = seg.get("finish", _finish_for(seg))
		seg["seed"] = Materials.finish_seed(finish, rng.randf())
	return out


## The finish of a block from the building's style and the block's role
## ("column", "wall", "slab", "parapet", or none) and height: the lower
## storeys are the older stone, what the printers rebuilt above is smooth.
func _finish_for(seg: Dictionary) -> int:
	var kind_of_block: int = seg["material"]
	if kind_of_block != Materials.Kind.CONCRETE:
		return _accent_finish(kind_of_block)
	var role: String = seg.get("role", "")
	var y: float = (seg["local"] as Transform3D).origin.y
	var ground := y < (block.y if kind == Kind.APARTMENT else 3.0)
	match style:
		Style.ROMAN:
			return Materials.Finish.MARBLE if role in ["column", "parapet"] else Materials.Finish.TRAVERTINE
		Style.MEDIEVAL:
			return _medieval_finish(role, ground)
		Style.RENAISSANCE:
			return _renaissance_finish(role, ground)
	return Materials.Finish.RAW


func _accent_finish(kind_of_block: int) -> int:
	if style != Style.MODERN and kind_of_block == Materials.Kind.METAL:
		return Materials.Finish.VERDIGRIS
	if style == Style.RENAISSANCE and kind_of_block == Materials.Kind.WOOD:
		return Materials.Finish.SHUTTER
	return Materials.Finish.RAW


func _medieval_finish(role: String, ground: bool) -> int:
	if role == "slab":
		return Materials.Finish.COMPOSITE
	if ground or role in ["column", "parapet"] or seed_value % 2 == 1:
		return Materials.Finish.STONE
	return Materials.Finish.BRICK


func _renaissance_finish(role: String, ground: bool) -> int:
	if ground:
		return Materials.Finish.STONE
	if role in ["slab", "parapet"]:
		return Materials.Finish.MARBLE
	if role == "column":
		return Materials.Finish.TRAVERTINE
	var plasters: Array[int] = [
		Materials.Finish.PLASTER_OCHRE,
		Materials.Finish.PLASTER_ROSE,
		Materials.Finish.PLASTER_SIENNA,
		Materials.Finish.PLASTER_CREAM,
	]
	return plasters[seed_value % plasters.size()]


func _role(out: Array[Dictionary], role: String) -> void:
	out[-1]["role"] = role


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
					_role(out, "column")
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
					_role(out, "parapet")
					continue
				if roll > 0.8:
					c.y = base + col_h * 0.5
					_seg(out, c, size_of.call(col_h), 0.6, true)
					_role(out, "panel")
				else:
					c.y = base + sill * 0.5
					_seg(out, c, size_of.call(sill), 0.5, true)
					_role(out, "wall")
					# Most windows are glazed. The pane stops short of the slab
					# above so it never carries any load.
					if roll < 0.62:
						var pane_h := col_h - sill - 0.06
						var g := Vector3(c.x, base + sill + pane_h * 0.5, c.z)
						var pane := size_of.call(pane_h) as Vector3
						pane = Vector3(pane.x, pane.y, 0.03) if along_x else Vector3(0.03, pane.y, pane.z)
						(
							out
							. append(
								{
									"local": Transform3D(Basis(), g),
									"size": pane,
									"strength": strength * 0.3,
									"material": Materials.Kind.GLASS,
								}
							)
						)
		if roof:
			break
		for ix in nx:
			for iz in nz:
				var c := Vector3(x0 + (ix + 0.5) * bay, base + col_h + slab_t * 0.5, z0 + (iz + 0.5) * bay)
				_seg(out, c, Vector3(bay, slab_t, bay), 0.9)
				_role(out, "slab")


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
		# The ends reach past the last columns to just short of whatever
		# they lead to: overlapping a building would fling both apart the
		# moment either one falls.
		if j == 0:
			a -= end_overhang
		if j == spans - 1:
			b += end_overhang
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


## Old-style city building (APARTMENT with a style): thick walls with
## punched windows between piers, a string course at every floor, floors
## of printed composite inside, a cornice and a tiled roof.
func _build_masonry(out: Array[Dictionary], rng: RandomNumberGenerator) -> void:
	var bay := block.x
	var storey := block.y
	var wt := _wall_t()
	var nx := maxi(counts.x, 1)
	var nz := maxi(counts.z, 1)
	var w := nx * bay
	var d := nz * bay
	var slab_t := 0.25
	var wall_h := storey - slab_t
	var open := {}
	for o in doors:
		open[Vector3i(o)] = true
	for s in counts.y:
		var base := s * storey
		for side in 4:
			var along_x := side < 2
			var n := nx if along_x else nz
			var length := w if along_x else d - 2.0 * wt
			var b := length / n
			var pw := b * (0.32 if s > 0 else 0.28)
			# Piers stop at the window heads; a band over each bay rests on
			# the piers either side (lintels must sit on something).
			var top := wall_h * (0.86 if s == 0 else 0.8)
			for k in n + 1:
				var pier := pw if k > 0 and k < n else pw * 0.5
				var u := -length * 0.5 + k * b
				if k == 0:
					u += pier * 0.5
				elif k == n:
					u -= pier * 0.5
				_masonry_seg(out, side, u, base + top * 0.5, Vector3(pier, top, wt), w, d, "column", 2.0)
			for k in n:
				var u := -length * 0.5 + (k + 0.5) * b
				var ww := b - pw
				var door := (s == 0 and (k % 3 == 1 or rng.randf() < 0.15)) or open.has(Vector3i(side, k, s))
				# Medieval windows sit on a sill; the others are tall windows
				# down to the floor (fewer blocks, lighter on the phone).
				var sill := 0.95 if style == Style.MEDIEVAL and not door else 0.0
				if sill > 0.0:
					_masonry_seg(out, side, u, base + sill * 0.5, Vector3(ww, sill, wt), w, d, "wall", 0.6)
				_masonry_seg(
					out, side, u, base + (top + wall_h) * 0.5, Vector3(b, wall_h - top, wt), w, d, "wall", 0.9
				)
				if door:
					continue
				var roll := rng.randf()
				var pane_h := top - sill - 0.1
				if style == Style.RENAISSANCE and roll < 0.3:
					# Closed shutters.
					_masonry_seg(
						out,
						side,
						u,
						base + sill + pane_h * 0.5,
						Vector3(ww - 0.06, pane_h, 0.08),
						w,
						d,
						"panel",
						0.3
					)
					out[-1]["material"] = Materials.Kind.WOOD
				elif roll < 0.85:
					_masonry_seg(
						out,
						side,
						u,
						base + sill + pane_h * 0.5,
						Vector3(ww - 0.02, pane_h, 0.03),
						w,
						d,
						"",
						0.3
					)
					out[-1]["material"] = Materials.Kind.GLASS
			# A string course runs round the building at every floor.
			var course_len := w + 0.24 if along_x else d
			_masonry_seg(
				out,
				side,
				0.0,
				base + storey - slab_t * 0.5,
				Vector3(course_len, slab_t, wt + 0.24),
				w,
				d,
				"parapet",
				0.9
			)
		# One printed composite floor per storey, wall to wall (one block:
		# when it goes it breaks into a few big plates, not dozens).
		_seg(
			out, Vector3(0, base + storey - slab_t * 0.5, 0), Vector3(w - 2.0 * wt, slab_t, d - 2.0 * wt), 2.0
		)
		_role(out, "slab")
		out[-1]["finish"] = Materials.Finish.COMPOSITE
	_masonry_roof(out, w, d, counts.y * storey)


## Cornice all round, then a low tiled hip roof in steps (Roman: a flat
## roof behind a parapet).
func _masonry_roof(out: Array[Dictionary], w: float, d: float, top: float) -> void:
	for side in 4:
		var along_x := side < 2
		var length := w + 0.6 if along_x else d - 2.0 * _wall_t()
		_masonry_seg(out, side, 0.0, top + 0.2, Vector3(length, 0.4, _wall_t() + 0.6), w, d, "parapet", 0.8)
	if style == Style.ROMAN:
		for side in 4:
			var along_x := side < 2
			var length := w if along_x else d - 2.0 * _wall_t()
			_masonry_seg(
				out, side, 0.0, top + 0.75, Vector3(length, 0.7, _wall_t() * 0.6), w, d, "parapet", 0.5
			)
		return
	var steps := 4
	for k in steps:
		var inset := 0.2 + k * minf(w, d) * 0.11
		var size := Vector3(w + 0.4 - inset * 2.0, 0.42, d + 0.4 - inset * 2.0)
		if size.x < 0.8 or size.z < 0.8:
			break
		_seg(out, Vector3(0, top + 0.4 + 0.21 + k * 0.42, 0), size, 0.7)
		out[-1]["finish"] = Materials.Finish.TERRACOTTA


## A facade block on `side` (0 = -z, 1 = +z, 2 = -x, 3 = +x) at `u` along
## it, `y` up; `size` is (along, height, thickness).
func _masonry_seg(
	out: Array[Dictionary],
	side: int,
	u: float,
	y: float,
	size: Vector3,
	w: float,
	d: float,
	role: String,
	mult: float
) -> void:
	var t := size.z
	var c: Vector3
	var sz: Vector3
	if side < 2:
		var z := (d * 0.5 - _wall_t() * 0.5) * (-1.0 if side == 0 else 1.0)
		c = Vector3(u, y, z)
		sz = size
	else:
		var x := (w * 0.5 - _wall_t() * 0.5) * (-1.0 if side == 2 else 1.0)
		c = Vector3(x, y, u)
		sz = Vector3(t, size.y, size.x)
	_seg(out, c, sz, mult)
	if role != "":
		_role(out, role)


## Masonry walls: thick enough to read as stone, thin enough that a
## collapse does not bury the phone's physics in rubble.
func _wall_t() -> float:
	return minf(block.z, 0.32)


## Stacked loggias: piers, round arches of voussoirs, spandrels, a cornice
## per storey and a balustrade on top.
func _build_arcade(out: Array[Dictionary]) -> void:
	var n := maxi(counts.x, 1)
	var span := block.x
	var pier_h := block.y
	var depth := block.z
	var pw := span * 0.3
	var pitch := span + pw
	var total := n * pitch + pw
	var x0 := -total * 0.5
	var r := span * 0.5
	var t := span * 0.17
	var voussoirs := 9
	var base := 0.0
	for s in maxi(counts.y, 1):
		var crown := base + pier_h + r + t
		for i in n + 1:
			var px := x0 + pw * 0.5 + i * pitch
			for d in 2:
				_seg(
					out,
					Vector3(px, base + (d + 0.5) * pier_h * 0.5, 0),
					Vector3(pw, pier_h * 0.5, depth),
					1.3
				)
				_role(out, "column")
			# Spandrels: narrow just above the impost, wider up to the crown.
			var low_h := r * 0.55
			var low_w := pw + span * 0.06
			var high_w := pw + span * 0.42
			if i == 0 or i == n:
				low_w = pw
				high_w = pw + span * 0.21
			_seg(out, Vector3(px, base + pier_h + low_h * 0.5, 0), Vector3(low_w, low_h, depth), 1.0)
			_role(out, "wall")
			var hx := high_w
			var hc := px
			if i == 0:
				hc = px + (hx - pw) * 0.5
			elif i == n:
				hc = px - (hx - pw) * 0.5
			var hh := crown - (base + pier_h + low_h)
			_seg(out, Vector3(hc, base + pier_h + low_h + hh * 0.5, 0), Vector3(hx, hh, depth), 1.0)
			_role(out, "wall")
		for i in n:
			var c := Vector3(x0 + pw + span * 0.5 + i * pitch, base + pier_h, 0)
			var rm := r + t * 0.5
			for k in voussoirs:
				var a := PI * (k + 0.5) / voussoirs
				var len := PI * rm / voussoirs * 1.04
				var at := c + Vector3(cos(a) * rm, sin(a) * rm, 0)
				_seg(out, at, Vector3(t, len, depth * 1.04), 1.1, false, Basis(Vector3.BACK, a))
				_role(out, "parapet")
		# Cornice across the whole storey.
		_seg(out, Vector3(0, crown + 0.18, 0), Vector3(total + 0.3, 0.36, depth * 1.2), 1.2)
		_role(out, "slab")
		base = crown + 0.36
	# Balustrade: little posts and a rail.
	var posts := int(total / 0.7)
	for p in posts:
		var x := -total * 0.5 + (p + 0.5) * total / posts
		_seg(out, Vector3(x, base + 0.35, 0), Vector3(0.18, 0.7, 0.18), 0.4)
		_role(out, "column")
	_seg(out, Vector3(0, base + 0.78, 0), Vector3(total, 0.16, 0.3), 0.4)
	_role(out, "parapet")


## Medieval tower: courses of stone in a broken bond, slit windows, a floor
## every few courses, a projecting parapet with merlons.
func _build_keep(out: Array[Dictionary]) -> void:
	var n := maxi(counts.x, 3)
	var h := block.y
	var t := block.z
	var side := n * block.x
	var half := side * 0.5
	var y := 0.0
	for c in counts.y:
		var slit := c % 5 == 2 and c > 1
		var shift := block.x * 0.5 if c % 2 == 1 else 0.0
		for face in 4:
			# Front/back faces run full width; the sides fit between.
			var along_x := face < 2
			var length := side if along_x else side - 2.0 * t
			var start := -length * 0.5
			var pieces: Array[Vector2] = []  # (centre, length) along the face
			var a := start
			var first := shift if shift > 0.0 else block.x
			var w := first
			while a < start + length - 0.01:
				w = minf(w, start + length - a)
				pieces.append(Vector2(a + w * 0.5, w))
				a += w
				w = block.x
			for k in pieces.size():
				var p := pieces[k]
				if slit and k == pieces.size() / 2:
					continue
				var pos := (
					Vector3(p.x, y + h * 0.5, half - t * 0.5)
					if along_x
					else Vector3(half - t * 0.5, y + h * 0.5, p.x)
				)
				var size := Vector3(p.y, h, t) if along_x else Vector3(t, h, p.y)
				if face % 2 == 1:
					pos = Vector3(-pos.x, pos.y, -pos.z)
				_seg(out, pos, size, 1.2)
				_role(out, "wall")
		y += h
		if c % 6 == 5 and c < counts.y - 1:
			_seg(
				out, Vector3(0, y + 0.12, 0), Vector3(side - 2.0 * t + 0.02, 0.24, side - 2.0 * t + 0.02), 0.8
			)
			_role(out, "slab")
			y += 0.24
	# Corbelled parapet: a projecting ring, then merlons with gaps.
	var over := 0.35
	var ring := side + over * 2.0
	for face in 4:
		var along_x := face < 2
		var pos := (
			Vector3(0, y + 0.2, half + over - t * 0.5)
			if along_x
			else Vector3(half + over - t * 0.5, y + 0.2, 0)
		)
		var size := Vector3(ring, 0.4, t + 0.1) if along_x else Vector3(t + 0.1, 0.4, ring - 2.0 * (t + 0.1))
		if face % 2 == 1:
			pos = Vector3(-pos.x, pos.y, -pos.z)
		_seg(out, pos, size, 1.0)
		_role(out, "parapet")
	var merlons := maxi(int(ring / 0.9), 3)
	var mw := ring / (merlons * 2 - 1)
	for face in 4:
		for m in merlons:
			var u := -ring * 0.5 + (m * 2 + 0.5) * mw
			var along_x := face < 2
			if not along_x and absf(u) > ring * 0.5 - (t + 0.1):
				continue
			var pos := (
				Vector3(u, y + 0.4 + 0.45, half + over - t * 0.5)
				if along_x
				else Vector3(half + over - t * 0.5, y + 0.85, u)
			)
			var size := Vector3(mw, 0.9, t) if along_x else Vector3(t, 0.9, mw)
			if face % 2 == 1:
				pos = Vector3(-pos.x, pos.y, -pos.z)
			_seg(out, pos, size, 0.8)
			_role(out, "parapet")


## Round church: a drum of tangent wall blocks with windows and doors, a
## cornice, a stepped dome of tile rings and a lantern.
func _build_dome(out: Array[Dictionary]) -> void:
	var sides := maxi(counts.x, 6)
	var radius := block.x
	var h := block.y
	var t := block.z
	var chord := 2.0 * (radius - t * 0.5) * sin(PI / sides) * 1.03
	var y := 0.0
	for c in counts.y:
		for i in sides:
			var a := TAU * i / sides
			var door := c < 3 and i % (sides / 2) == 0
			var window := c % 4 == 2 and c > 3 and i % 2 == 1
			if door or window:
				continue
			var at := Vector3(cos(a), 0, sin(a)) * (radius - t * 0.5) + Vector3(0, y + h * 0.5, 0)
			_seg(out, at, Vector3(t, h, chord), 1.2, false, Basis(Vector3.UP, -a))
			_role(out, "wall")
		y += h
	# Cornice ring.
	for i in sides:
		var a := TAU * i / sides
		var at := Vector3(cos(a), 0, sin(a)) * (radius - t * 0.3) + Vector3(0, y + 0.15, 0)
		_seg(out, at, Vector3(t + 0.3, 0.3, chord * 1.08), 1.0, false, Basis(Vector3.UP, -a))
		_role(out, "parapet")
	y += 0.3
	# Dome: rings of tiles, each a little smaller and higher (a slightly
	# raised profile, like Florence).
	var rings := maxi(counts.z, 3)
	var rise := radius * 0.95
	for k in rings:
		var phi := (k + 0.5) / rings * PI * 0.5
		var rk := radius * cos(phi) - t * 0.2
		var ring_y := y + rise * sin(phi)
		var dh := rise / rings * 1.12
		if rk < 0.7:
			break
		var ck := 2.0 * rk * sin(PI / sides) * 1.06
		for i in sides:
			var a := TAU * (i + 0.5 * (k % 2)) / sides
			var at := Vector3(cos(a), 0, sin(a)) * rk + Vector3(0, ring_y, 0)
			var seg_t := minf(t * 1.1, rk * 0.5)
			_seg(out, at, Vector3(seg_t, dh, ck), 0.9, false, Basis(Vector3.UP, -a))
			out[-1]["finish"] = (
				Materials.Finish.TERRACOTTA if style != Style.ROMAN else Materials.Finish.MARBLE
			)
	# Lantern: a small drum and a cap.
	var top := y + rise
	_seg(out, Vector3(0, top + 0.5, 0), Vector3(1.0, 1.0, 1.0), 0.6)
	_role(out, "column")
	_seg(out, Vector3(0, top + 1.15, 0), Vector3(1.3, 0.3, 1.3), 0.6)
	_role(out, "parapet")


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
