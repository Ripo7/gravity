class_name Palazzo
extends RefCounted
## The game's one building: a Renaissance palace round an arcaded courtyard,
## and its bell tower. The tower is a structure of its own, so it can be cut
## at the foot and topple onto the palace.
## Builders only list blocks (see Structure.build_segments); StructureSet owns
## the physics and the drawing. Metres; the palace origin is the middle of
## its footprint on the ground, its front facade faces +z. Blocks never
## overlap: a loose piece born inside another would be flung out of it.

const W := 34.0  ## palace width (x)
const D := 26.0  ## palace depth (z)
const WT := 0.6  ## outer wall thickness
## Courtyard arcade: column centres on a 21 x 12.6 m rectangle, 4.2 m apart.
const PITCH := 4.2
const AX := 10.5
const AZ := 6.3
const CT := 0.7  ## courtyard wall and arcade thickness
const SLAB := 0.4
## Storeys: base, wall top, window sill, window head, window width.
const STOREYS: Array[Vector4] = [
	Vector4(0.0, 5.6, 3.0, 4.6), Vector4(6.0, 10.6, 6.9, 9.8), Vector4(11.0, 14.8, 11.8, 13.8)
]
const WINDOW_W: Array[float] = [1.1, 1.5, 1.2]
const BAYS_FRONT := 9
const BAYS_SIDE := 7
const PORTAL_W := 3.0
const ROOF_STEP := 0.85
## Intact masonry carries at most 1/(SAFETY * ROBUST) of what breaks it.
const ROBUST := 2.5
## Bell tower: width, wall thickness, course height, courses in the shaft.
const TS := 7.0
const TT := 1.0
const COURSE := 1.6
const COURSES := 18

var out: Array[Dictionary] = []
var strength := 3.0
var _rng := RandomNumberGenerator.new()


static func palace(strength_value: float, seed_value := 0) -> Array[Dictionary]:
	var b := Palazzo.new()
	b.strength = strength_value
	b._rng.seed = 4111 + seed_value
	b._build_palace()
	return b.out


static func campanile(strength_value: float, seed_value := 0) -> Array[Dictionary]:
	var b := Palazzo.new()
	b.strength = strength_value
	b._rng.seed = 7151 + seed_value
	b._build_campanile()
	return b.out


# --- Blocks ---------------------------------------------------------------------


func _box(
	c: Vector3,
	size: Vector3,
	finish: int,
	mult := 1.0,
	kind := Materials.Kind.CONCRETE,
	basis := Basis(),
	is_round := false,
	shape := "",
) -> void:
	var seg := {
		"local": Transform3D(basis, c),
		"size": size,
		"strength": strength * mult,
		"material": kind,
		"finish": finish,
		"robust": ROBUST,
	}
	if is_round:
		seg["round"] = true
	if shape != "":
		seg["shape"] = shape  # a carved piece (ShapeLibrary) instead of a box
	out.append(seg)


## Box between two corners (x0..x1, y0..y1, z0..z1).
func _span(lo: Vector3, hi: Vector3, finish: int, mult := 1.0, kind := Materials.Kind.CONCRETE) -> void:
	_box((lo + hi) * 0.5, hi - lo, finish, mult, kind)


## A long box cut into pieces of at most `piece` metres along x or z (one
## giant block would break into giant plates).
func _cut(lo: Vector3, hi: Vector3, finish: int, mult: float, piece := 6.0) -> void:
	var size := hi - lo
	var axis := 0 if size.x >= size.z else 2
	var n := maxi(ceili(size[axis] / piece), 1)
	for k in n:
		var a := lo
		var b := hi
		a[axis] = lerpf(lo[axis], hi[axis], float(k) / n)
		b[axis] = lerpf(lo[axis], hi[axis], float(k + 1) / n)
		_span(a, b, finish, mult)


## Outer facades. side: 0 = front (+z), 1 = back, 2 = left (-x), 3 = right.
## Positions on a facade: `u` along it (left to right seen from outside),
## `y` up, `o` outward from its outer face (negative = inside the wall).
func _facade_box(
	side: int, u0: float, u1: float, y0: float, y1: float, o0: float, o1: float, finish: int, mult := 1.0
) -> void:
	_facade_any(side, u0, u1, y0, y1, o0, o1, finish, mult, Materials.Kind.CONCRETE)


func _facade_any(
	side: int,
	u0: float,
	u1: float,
	y0: float,
	y1: float,
	o0: float,
	o1: float,
	finish: int,
	mult: float,
	kind: int,
) -> void:
	var a := _facade_point(side, u0, y0, o0)
	var b := _facade_point(side, u1, y1, o1)
	_span(
		Vector3(minf(a.x, b.x), y0, minf(a.z, b.z)),
		Vector3(maxf(a.x, b.x), y1, maxf(a.z, b.z)),
		finish,
		mult,
		kind
	)


## A moulded piece on a facade (ShapeLibrary: "string", "sill", "cap",
## "corona", "crown"): the same span as _facade_box, turned so its profile
## faces out (local x along the facade, z outward).
func _facade_piece(
	side: int, u0: float, u1: float, y0: float, y1: float, o0: float, o1: float, shape: String, mult := 0.6
) -> void:
	var origin := _facade_point(side, 0.0, 0.0, 0.0)
	var along := _facade_point(side, 1.0, 0.0, 0.0) - origin
	var outward := _facade_point(side, 0.0, 0.0, 1.0) - origin
	var a := _facade_point(side, u0, y0, o0)
	var b := _facade_point(side, u1, y1, o1)
	var size := Vector3(absf(u1 - u0), y1 - y0, absf(o1 - o0))
	var basis := Basis(along, Vector3.UP, outward)
	var stone := Materials.Finish.TRAVERTINE
	_box((a + b) * 0.5, size, stone, mult, Materials.Kind.CONCRETE, basis, false, shape)


func _facade_point(side: int, u: float, y: float, o: float) -> Vector3:
	match side:
		0:
			return Vector3(u, y, D * 0.5 + o)
		1:
			return Vector3(-u, y, -D * 0.5 - o)
		2:
			return Vector3(-W * 0.5 - o, y, u)
	return Vector3(W * 0.5 + o, y, -u)


## Rotated slab on a facade (pediments): centre at (u, y, o), `length`
## along the facade, tilted by `angle` (radians, positive rises to the right).
func _facade_tilted(
	side: int, u: float, y: float, o: float, size: Vector3, angle: float, finish: int
) -> void:
	var c := _facade_point(side, u, y, o)
	var along := Vector3.RIGHT
	var normal := Vector3.BACK
	match side:
		1:
			along = Vector3.LEFT
			normal = Vector3.FORWARD
		2:
			along = Vector3.BACK
			normal = Vector3.LEFT
		3:
			along = Vector3.FORWARD
			normal = Vector3.RIGHT
	var basis := Basis(along, Vector3.UP, normal).rotated(normal, angle)
	_box(c, size, finish, 0.6, Materials.Kind.CONCRETE, basis)


func _side_length(side: int) -> float:
	return W if side < 2 else D - 2.0 * WT


# --- Palace ---------------------------------------------------------------------


func _build_palace() -> void:
	for side in 4:
		for s in STOREYS.size():
			_facade_storey(side, s)
		_string_courses(side)
		_quoins(side)
	_bench()
	_portal()
	_arcade()
	_courtyard_walls()
	_loggia()
	for s in STOREYS.size():
		_floor(STOREYS[s].y)
	_cornice()
	_roof()


## Window centres and widths along one facade storey.
func _windows(side: int, s: int) -> Array[Vector2]:
	var n := BAYS_FRONT if side < 2 else BAYS_SIDE
	var length := _side_length(side)
	var res: Array[Vector2] = []
	for k in n:
		var w := WINDOW_W[s]
		if side == 0 and s == 0 and k == n / 2:
			w = PORTAL_W
		res.append(Vector2(-length * 0.5 + (k + 0.5) * length / n, w))
	return res


func _facade_storey(side: int, s: int) -> void:
	var st := STOREYS[s]
	var base := st.x
	var top := st.y
	var sill := st.z
	var head := st.w
	var length := _side_length(side)
	var bay := length / (BAYS_FRONT if side < 2 else BAYS_SIDE)
	var wall := Materials.Finish.STONE if s == 0 else Materials.Finish.PLASTER_OCHRE
	var wins := _windows(side, s)
	# Piers between the windows, up to the window heads.
	var edge := -length * 0.5
	for k in wins.size() + 1:
		var stop := length * 0.5 if k == wins.size() else wins[k].x - wins[k].y * 0.5
		_facade_box(side, edge, stop, base, head, -WT, 0.0, wall, 1.4)
		if k < wins.size():
			edge = wins[k].x + wins[k].y * 0.5
	for k in wins.size():
		var c := wins[k].x
		var ww := wins[k].y
		var portal := ww >= PORTAL_W
		# A band over each bay rests on the piers either side.
		var u0 := maxf(c - bay * 0.5, -length * 0.5)
		var u1 := minf(c + bay * 0.5, length * 0.5)
		_facade_box(side, u0, u1, head, top, -WT, 0.0, wall, 1.0)
		if portal:
			continue
		_facade_box(side, c - ww * 0.5, c + ww * 0.5, base, sill, -WT, 0.0, wall, 0.9)
		var shut := s > 0 and _rng.randf() < 0.3
		if shut:
			_facade_any(
				side,
				c - ww * 0.5,
				c + ww * 0.5,
				sill,
				head,
				-0.34,
				-0.26,
				Materials.Finish.SHUTTER,
				0.4,
				Materials.Kind.WOOD
			)
		else:
			_facade_any(
				side,
				c - ww * 0.5 + 0.02,
				c + ww * 0.5 - 0.02,
				sill,
				head,
				-0.31,
				-0.26,
				Materials.Finish.RAW,
				0.3,
				Materials.Kind.GLASS
			)
		_window_dressing(side, s, c, ww, sill, head)


## Stone frames: a sill on every window; on the piano nobile of the front,
## pilaster jambs and a pediment, triangular and flat in turn.
func _window_dressing(side: int, s: int, c: float, ww: float, sill: float, head: float) -> void:
	var stone := Materials.Finish.TRAVERTINE
	if s == 0:
		_facade_piece(side, c - ww * 0.5 - 0.15, c + ww * 0.5 + 0.15, sill - 0.18, sill, 0.0, 0.18, "sill")
		return
	_facade_piece(side, c - ww * 0.5 - 0.25, c + ww * 0.5 + 0.25, sill, sill + 0.15, 0.0, 0.24, "sill")
	var cap_w := ww * 0.5 + 0.3
	if side == 0 and s == 1:
		for sx: float in [-1.0, 1.0]:
			var ju := c + sx * (ww * 0.5 + 0.1)
			_facade_box(side, ju - 0.1, ju + 0.1, sill + 0.15, head, 0.0, 0.14, stone, 0.6)
	_facade_piece(side, c - cap_w, c + cap_w, head, head + 0.22, 0.0, 0.26, "cap")
	if not (side == 0 and s == 1):
		return
	var k := int(roundf((c + W * 0.5) / (W / BAYS_FRONT) - 0.5))
	if k % 2 == 0:
		# Triangular pediment: two raking slabs on the cap.
		var angle := deg_to_rad(20.0)
		var half := cap_w + 0.05
		var length := half / cos(angle)
		var t := 0.14
		var rise := sin(angle) * length * 0.5 + cos(angle) * t * 0.5
		var y := head + 0.22 + rise
		_facade_tilted(side, c - half * 0.5, y, 0.13, Vector3(length, t, 0.26), angle, stone)
		_facade_tilted(side, c + half * 0.5, y, 0.13, Vector3(length, t, 0.26), -angle, stone)
	else:
		# Flat pediment: a second, deeper cornice with a raised middle.
		_facade_box(side, c - cap_w + 0.1, c + cap_w - 0.1, head + 0.22, head + 0.36, 0.0, 0.3, stone, 0.6)
		_facade_box(side, c - 0.35, c + 0.35, head + 0.36, head + 0.58, 0.0, 0.2, stone, 0.6)


## A moulded string course runs round the palace at each floor.
func _string_courses(side: int) -> void:
	for s in 2:
		var y := STOREYS[s].y
		var length := W + 0.44 if side < 2 else D
		var u := length * 0.5
		var pieces := ceili(length / 6.0)
		for k in pieces:
			var a := -u + k * length / pieces
			var b := -u + (k + 1) * length / pieces
			_facade_piece(side, a, b, y + 0.15, y + SLAB, 0.0, 0.22, "string", 0.7)


## Stone quoins up the corners of the rendered storeys, long and short in
## turn, a thin face over the plaster.
func _quoins(side: int) -> void:
	for s in [1, 2]:
		var y0: float = STOREYS[s].x
		var y1: float = STOREYS[s].y
		var n := int(roundf((y1 - y0) / 0.58))
		var h := (y1 - y0) / n
		for k in n:
			var long := (k + (1 if side >= 2 else 0)) % 2 == 0
			var l := 0.9 if long else 0.55
			var y := y0 + k * h
			for end: float in [-1.0, 1.0]:
				var outer := W * 0.5 + 0.1 if side < 2 else D * 0.5
				var a := end * outer
				var b := end * (outer - l)
				_facade_box(
					side, minf(a, b), maxf(a, b), y, y + h, 0.0, 0.1, Materials.Finish.TRAVERTINE, 0.5
				)


## The stone bench along the front (the old palaces lent it to the street).
func _bench() -> void:
	for w in _windows(0, 0):
		if w.y >= PORTAL_W:
			continue
		var bay := W / BAYS_FRONT
		_facade_box(
			0,
			w.x - bay * 0.5 + 0.25,
			w.x + bay * 0.5 - 0.25,
			0.0,
			0.48,
			0.0,
			0.5,
			Materials.Finish.STONE,
			0.8
		)


## The main door: rusticated jambs, a cornice and a pediment.
func _portal() -> void:
	var stone := Materials.Finish.TRAVERTINE
	var half := PORTAL_W * 0.5
	var head := STOREYS[0].w
	for sx: float in [-1.0, 1.0]:
		_facade_box(
			0,
			sx * half if sx > 0 else -half - 0.55,
			half + 0.55 if sx > 0 else -half,
			0.0,
			head,
			0.0,
			0.3,
			stone,
			1.2
		)
	_facade_box(0, -half - 0.8, half + 0.8, head, head + 0.36, 0.0, 0.4, stone, 0.9)
	var angle := deg_to_rad(13.0)
	var span := half + 0.85
	var length := span / cos(angle)
	var t := 0.18
	var y := head + 0.36 + sin(angle) * length * 0.5 + cos(angle) * t * 0.5
	_facade_tilted(0, -span * 0.5, y, 0.18, Vector3(length, t, 0.36), angle, stone)
	_facade_tilted(0, span * 0.5, y, 0.18, Vector3(length, t, 0.36), -angle, stone)


## The courtyard: round arches on marble columns all round the ground floor
## (no block overlaps: springers sit on the imposts, the voussoirs start
## above them, stepped spandrels fill up to the floor above).
func _arcade() -> void:
	var top := STOREYS[0].y
	var cols := _courtyard_columns()
	for c in cols:
		_column(c, 0.0, 0.7, 2.925, Materials.Finish.MARBLE)
		_box(c + Vector3(0, 3.1, 0), Vector3(0.95, 0.35, 0.95), Materials.Finish.TRAVERTINE, 1.4)
		_box(c + Vector3(0, 3.425, 0), Vector3(0.95, 0.3, 0.95), Materials.Finish.TRAVERTINE, 1.4)
	var y0 := 3.575
	_arch_row(Vector3(-AX, y0, AZ), Vector3.RIGHT, 5, top)
	_arch_row(Vector3(AX, y0, -AZ), Vector3.LEFT, 5, top)
	_arch_row(Vector3(-AX, y0, -AZ), Vector3.BACK, 3, top)
	_arch_row(Vector3(AX, y0, AZ), Vector3.FORWARD, 3, top)


func _courtyard_columns() -> Array[Vector3]:
	var res: Array[Vector3] = []
	for i in 6:
		for z: float in [-AZ, AZ]:
			res.append(Vector3(-AX + i * PITCH, 0, z))
	for j in [1, 2]:
		for x: float in [-AX, AX]:
			res.append(Vector3(x, 0, -AZ + j * PITCH))
	return res


## A round column from `y` up `h`: a carved base (unless it stands between
## parapets), a shaft of two drums and a carved Tuscan capital (modelled in
## Blender, tools/make_sculptures.py).
func _column(at: Vector3, y: float, dia: float, h: float, finish: int, with_base := true) -> void:
	var base_h := dia * 0.4 if with_base else 0.0
	var cap_h := dia * 0.5
	var foot := dia * 1.35
	var concrete := Materials.Kind.CONCRETE
	if with_base:
		var base := Vector3(foot, base_h, foot)
		_box(at + Vector3(0, y + base_h * 0.5, 0), base, finish, 1.6, concrete, Basis(), true, "base")
	var shaft := (h - base_h - cap_h) * 0.5
	for d in 2:
		_box(
			at + Vector3(0, y + base_h + (d + 0.5) * shaft, 0),
			Vector3(dia, shaft, dia),
			finish,
			1.6,
			concrete,
			Basis(),
			true
		)
	var cap := Vector3(foot, cap_h, foot)
	_box(at + Vector3(0, y + h - cap_h * 0.5, 0), cap, finish, 1.6, concrete, Basis(), true, "capital")


## Arches from the column at `start` along `dir`, `n` of them, springing at
## start.y; `top` = height of the floor they carry.
func _arch_row(start: Vector3, dir: Vector3, n: int, top: float) -> void:
	_arches(start, dir, n, top, PITCH, 0.95, CT, Materials.Finish.TRAVERTINE, Materials.Finish.PLASTER_CREAM)


## Generic arcade: `imp` = impost width, `depth` = thickness of the arcade.
## Arch span = pitch - imp; the ring is 0.4 m and its crown touches `top`.
func _arches(
	start: Vector3,
	dir: Vector3,
	n: int,
	top: float,
	pitch: float,
	imp: float,
	depth: float,
	ring_fin: int,
	fill_fin: int
) -> void:
	var side := Vector3.UP.cross(dir)
	var r := (pitch - imp) * 0.5
	var ring := 0.4
	var big := r + ring
	var y0 := start.y
	var hs := big * 0.5  # springers up to 30 degrees on the extrados
	var spring_half := pitch * 0.5 - r * cos(deg_to_rad(30.0))
	var h1 := minf(y0 + big * 0.78, top) - y0
	for i in n + 1:
		var at := start + dir * (i * pitch)
		# Springer and stepped spandrels over this impost; half ones at the ends.
		# At a corner the next row's springer holds the corner square.
		var lo := -spring_half if i > 0 else -imp * 0.5
		var hi := spring_half if i < n else -depth * 0.5
		_dir_box(at, dir, side, lo, hi, y0, y0 + hs, depth, ring_fin, 1.3)
		var w1 := pitch * 0.5 - sqrt(big * big - hs * hs)
		var w2 := pitch * 0.5 - sqrt(maxf(big * big - h1 * h1, 0.0))
		var end := -depth * 0.5
		_dir_box(
			at,
			dir,
			side,
			-w1 if i > 0 else -imp * 0.5,
			w1 if i < n else end,
			y0 + hs,
			y0 + h1,
			depth,
			fill_fin,
			1.0
		)
		_dir_box(
			at,
			dir,
			side,
			-w2 if i > 0 else -imp * 0.5,
			w2 if i < n else end,
			y0 + h1,
			top,
			depth,
			fill_fin,
			1.0
		)
	# Voussoirs from where the springers stop (on the intrados) to the top.
	var a0 := asin(clampf(hs / r, 0.0, 1.0))
	var count := 5
	var rm := r + ring * 0.5
	for i in n:
		var c := start + dir * ((i + 0.5) * pitch)
		for k in count:
			var a := lerpf(a0, PI - a0, (k + 0.5) / count)
			var len := rm * (PI - 2.0 * a0) / count * 0.98
			var p := c + dir * (cos(a) * rm) + Vector3.UP * (sin(a) * rm)
			var basis := Basis(dir, Vector3.UP, side).rotated(side, -a)
			# Box: x = radial thickness, y = along the arc, z = depth.
			_box(p, Vector3(ring, len, depth), ring_fin, 1.2, Materials.Kind.CONCRETE, basis)


## Box along an arcade: from `a` to `b` along dir from `at`, y0..y1, `depth`
## across.
func _dir_box(
	at: Vector3,
	dir: Vector3,
	side: Vector3,
	a: float,
	b: float,
	y0: float,
	y1: float,
	depth: float,
	finish: int,
	mult: float
) -> void:
	if b - a < 0.05 or y1 - y0 < 0.05:
		return
	var p0 := at + dir * a - side * depth * 0.5
	var p1 := at + dir * b + side * depth * 0.5
	_span(
		Vector3(minf(p0.x, p1.x), y0, minf(p0.z, p1.z)),
		Vector3(maxf(p0.x, p1.x), y1, maxf(p0.z, p1.z)),
		finish,
		mult
	)


## Piano nobile round the courtyard: rendered walls, a window over each arch.
func _courtyard_walls() -> void:
	var st := STOREYS[1]
	var base := st.x
	var top := st.y
	var sill := base + 0.9
	var head := base + 3.6
	var ww := 1.3
	var fin := Materials.Finish.PLASTER_CREAM
	# Along x (full length, they hold the corners), then along z between them.
	for z: float in [-AZ, AZ]:
		_court_wall(
			Vector3(-AX - CT * 0.5, 0, z),
			Vector3.RIGHT,
			2.0 * AX + CT,
			5,
			CT * 0.5 + PITCH * 0.5,
			base,
			top,
			sill,
			head,
			ww,
			fin
		)
	for x: float in [-AX, AX]:
		_court_wall(
			Vector3(x, 0, -AZ + CT * 0.5),
			Vector3.BACK,
			2.0 * AZ - CT,
			3,
			PITCH * 0.5 - CT * 0.5,
			base,
			top,
			sill,
			head,
			ww,
			fin
		)


func _court_wall(
	start: Vector3,
	dir: Vector3,
	length: float,
	n: int,
	first: float,
	base: float,
	top: float,
	sill: float,
	head: float,
	ww: float,
	fin: int
) -> void:
	var side := Vector3.UP.cross(dir)
	var edge := 0.0
	for k in n + 1:
		var c := first + k * PITCH
		var stop := length if k == n else c - ww * 0.5
		_dir_box(start, dir, side, edge, stop, base, head, CT, fin, 1.3)
		if k == n:
			break
		_dir_box(start, dir, side, c - ww * 0.5, c + ww * 0.5, base, sill, CT, fin, 0.9)
		var glass_lo := start + dir * (c - ww * 0.5 + 0.02) - side * 0.03
		var glass_hi := start + dir * (c + ww * 0.5 - 0.02) + side * 0.03
		_span(
			Vector3(minf(glass_lo.x, glass_hi.x), sill, minf(glass_lo.z, glass_hi.z)),
			Vector3(maxf(glass_lo.x, glass_hi.x), head, maxf(glass_lo.z, glass_hi.z)),
			Materials.Finish.RAW,
			0.3,
			Materials.Kind.GLASS
		)
		edge = c + ww * 0.5
	for k in n:
		var c := first + k * PITCH
		var a := 0.0 if k == 0 else c - PITCH * 0.5
		var b := length if k == n - 1 else c + PITCH * 0.5
		_dir_box(start, dir, side, a, b, head, top, CT, fin, 1.0)


## Top floor round the courtyard: an open loggia, slim columns, stone
## architraves and a parapet in each bay.
func _loggia() -> void:
	var st := STOREYS[2]
	var base := st.x
	var top := st.y
	var cap_y := top - 0.35 - 0.25
	for c in _courtyard_columns():
		_column(c, base, 0.42, cap_y - base, Materials.Finish.MARBLE, false)
		_box(c + Vector3(0, cap_y + 0.125, 0), Vector3(0.6, 0.25, 0.6), Materials.Finish.TRAVERTINE, 1.2)
	var beam_y := cap_y + 0.25
	for z: float in [-AZ, AZ]:
		_cut(
			Vector3(-AX - 0.25, beam_y, z - 0.25),
			Vector3(AX + 0.25, top, z + 0.25),
			Materials.Finish.TRAVERTINE,
			1.2,
			4.4
		)
		for i in 5:
			var x0 := -AX + i * PITCH + 0.21
			_span(
				Vector3(x0, base, z - 0.12),
				Vector3(x0 + PITCH - 0.42, base + 0.95, z + 0.12),
				Materials.Finish.TRAVERTINE,
				0.6
			)
	for x: float in [-AX, AX]:
		_cut(
			Vector3(x - 0.25, beam_y, -AZ + 0.25),
			Vector3(x + 0.25, top, AZ - 0.25),
			Materials.Finish.TRAVERTINE,
			1.2,
			4.4
		)
		for j in 3:
			var z0 := -AZ + j * PITCH + 0.21
			_span(
				Vector3(x - 0.12, base, z0),
				Vector3(x + 0.12, base + 0.95, z0 + PITCH - 0.42),
				Materials.Finish.TRAVERTINE,
				0.6
			)


## A floor on top of the walls at `y` (the top of a storey's walls): the
## four wings, from the outer face to the courtyard face, in pieces.
func _floor(y: float) -> void:
	var hx := W * 0.5
	var hz := D * 0.5
	var ix := AX - CT * 0.5
	var iz := AZ - CT * 0.5
	var fin := Materials.Finish.TRAVERTINE
	_cut(Vector3(-hx, y, iz), Vector3(hx, y + SLAB, hz), fin, 1.4)
	_cut(Vector3(-hx, y, -hz), Vector3(hx, y + SLAB, -iz), fin, 1.4)
	_cut(Vector3(-hx, y, -iz), Vector3(-ix, y + SLAB, iz), fin, 1.4)
	_cut(Vector3(ix, y, -iz), Vector3(hx, y + SLAB, iz), fin, 1.4)


## The great cornice: brackets on the top floor, a deep corona on them, a
## moulding on top; and a lighter cornice round the courtyard.
func _cornice() -> void:
	var y := STOREYS[2].y + SLAB
	var stone := Materials.Finish.TRAVERTINE
	for side in 4:
		var length := _side_length(side)
		var u := length * 0.5
		var n := int(length / 1.5)
		for k in n:
			var c := -u + (k + 0.5) * length / n
			_console(side, c, y)
		# Backing course behind the brackets.
		var bu := u if side < 2 else u
		var pieces := ceili(length / 6.0)
		for k in pieces:
			_facade_box(
				side,
				-bu + k * length / pieces,
				-bu + (k + 1) * length / pieces,
				y,
				y + 0.35,
				-WT,
				-0.3,
				stone,
				0.8
			)
		# Corona and top moulding: the front and back ones run over the corners.
		var cu := u + 1.15 if side < 2 else D * 0.5 - WT
		var cl := cu * 2.0
		pieces = ceili(cl / 6.0)
		for k in pieces:
			var a := -cu + k * cl / pieces
			var b := -cu + (k + 1) * cl / pieces
			_facade_piece(side, a, b, y + 0.35, y + 0.85, -WT, 1.15, "corona", 0.8)
		var mu := u + 1.25 if side < 2 else D * 0.5 - WT
		var ml := mu * 2.0
		for k in pieces:
			var a := -mu + k * ml / pieces
			var b := -mu + (k + 1) * ml / pieces
			_facade_piece(side, a, b, y + 0.85, y + 1.05, -WT, 1.25, "crown")
	# Courtyard cornice on the inner edge of the top floor.
	var ix := AX + CT * 0.5
	var iz := AZ + CT * 0.5
	_cut(Vector3(-ix, y, iz - CT - 0.45), Vector3(ix, y + 0.3, iz), stone, 0.7)
	_cut(Vector3(-ix, y, -iz), Vector3(ix, y + 0.3, -iz + CT + 0.45), stone, 0.7)
	_cut(Vector3(-ix, y, -iz + CT + 0.45), Vector3(-ix + CT + 0.45, y + 0.3, iz - CT - 0.45), stone, 0.7)
	_cut(Vector3(ix - CT - 0.45, y, -iz + CT + 0.45), Vector3(ix, y + 0.3, iz - CT - 0.45), stone, 0.7)


## A carved bracket under the cornice at `c` along facade `side`: a scroll
## pushed out of the wall, its tip outward.
func _console(side: int, c: float, y: float) -> void:
	var a := _facade_point(side, c, y, -0.3)
	var b := _facade_point(side, c, y, 0.75)
	var outward := (b - a).normalized()
	var basis := Basis(Vector3.UP.cross(outward), Vector3.UP, outward)
	var size := Vector3(0.24, 0.35, 1.05)
	var stone := Materials.Finish.TRAVERTINE
	_box(
		(a + b) * 0.5 + Vector3(0, 0.175, 0),
		size,
		stone,
		0.6,
		Materials.Kind.CONCRETE,
		basis,
		false,
		"console"
	)


## Low hipped roof of terracotta round the courtyard, in steps behind the
## cornice, with a few chimneys on the ridge.
func _roof() -> void:
	var y := STOREYS[2].y + SLAB
	var ox := W * 0.5 - WT
	var oz := D * 0.5 - WT
	var ix := AX + CT * 0.5
	var iz := AZ + CT * 0.5
	var tile := Materials.Finish.TERRACOTTA
	for k in 4:
		var yk := y + k * 0.4
		var o := Vector2(ox, oz) - Vector2.ONE * ROOF_STEP * k
		var i := Vector2(ix, iz) + Vector2.ONE * ROOF_STEP * k
		if o.x - i.x < 0.3 or o.y - i.y < 0.3:
			break
		_cut(Vector3(-o.x, yk, i.y), Vector3(o.x, yk + 0.4, o.y), tile, 0.8)
		_cut(Vector3(-o.x, yk, -o.y), Vector3(o.x, yk + 0.4, -i.y), tile, 0.8)
		_cut(Vector3(-o.x, yk, -i.y), Vector3(-i.x, yk + 0.4, i.y), tile, 0.8)
		_cut(Vector3(i.x, yk, -i.y), Vector3(o.x, yk + 0.4, i.y), tile, 0.8)
	var ridge := y + 4.0 * 0.4
	var mz := (oz + iz) * 0.5
	var mx := (ox + ix) * 0.5
	for at: Vector3 in [
		Vector3(-8.0, 0, mz), Vector3(6.5, 0, mz), Vector3(2.0, 0, -mz), Vector3(mx, 0, -1.5)
	]:
		_span(
			Vector3(at.x - 0.45, ridge, at.z - 0.45),
			Vector3(at.x + 0.45, ridge + 1.7, at.z + 0.45),
			Materials.Finish.BRICK,
			0.7
		)
		_span(
			Vector3(at.x - 0.6, ridge + 1.7, at.z - 0.6),
			Vector3(at.x + 0.6, ridge + 1.88, at.z + 0.6),
			Materials.Finish.TRAVERTINE,
			0.5
		)


# --- Bell tower -------------------------------------------------------------------


func _build_campanile() -> void:
	var half := TS * 0.5
	# Plinth.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var lo := Vector3(minf(0.0, sx * 3.9), 0.0, minf(0.0, sz * 3.9))
			var hi := Vector3(maxf(0.0, sx * 3.9), 0.8, maxf(0.0, sz * 3.9))
			_span(lo, hi, Materials.Finish.STONE, 2.0)
	var y := 0.8
	for c in COURSES:
		_tower_course(c, y)
		y += COURSE
		if c % 5 == 4 and c < COURSES - 1:
			_tower_floor(y, TS)
			y += SLAB
	# Machicolations: corbels carry the gallery out over the shaft.
	for face in 4:
		for k in 4:
			var u := -2.2 + k * 4.4 / 3.0
			_tower_face_box(face, u - 0.25, u + 0.25, y, y + 1.0, -TT, 0.9, Materials.Finish.STONE, 1.2)
	y += 1.0
	var g := TS * 0.5 + 0.9
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_span(
				Vector3(minf(0.0, sx * g), y, minf(0.0, sz * g)),
				Vector3(maxf(0.0, sx * g), y + SLAB, maxf(0.0, sz * g)),
				Materials.Finish.TRAVERTINE,
				1.2
			)
	y += SLAB
	# Merlons round the gallery.
	for face in 4:
		var us: Array[float] = [-1.4, 1.4]
		if face < 2:
			us = [-g + 0.45, -1.4, 1.4, g - 0.45]
		for u in us:
			_tower_face_box(
				face,
				u - 0.45,
				u + 0.45,
				y,
				y + 1.05,
				-0.4 + (0.9 if face < 2 else 0.9),
				0.9,
				Materials.Finish.BRICK,
				0.6
			)
	# Belfry: corner piers, an arch on each face, the bell in a timber frame.
	var bh := TS * 0.5 - 0.5  # half size of the belfry
	var pier := 1.3
	var pitch := 2.0 * bh - pier
	var spring := y + 2.8
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var c := Vector3(sx * (bh - pier * 0.5), 0, sz * (bh - pier * 0.5))
			_span(
				c + Vector3(-pier * 0.5, y, -pier * 0.5),
				c + Vector3(pier * 0.5, spring, pier * 0.5),
				Materials.Finish.TRAVERTINE,
				1.6
			)
	var crown := spring + (pitch - pier) * 0.5 + 0.4
	var pc := bh - pier * 0.5
	_arches(
		Vector3(-pc, spring, pc),
		Vector3.RIGHT,
		1,
		crown,
		pitch,
		pier,
		pier,
		Materials.Finish.TRAVERTINE,
		Materials.Finish.BRICK
	)
	_arches(
		Vector3(pc, spring, -pc),
		Vector3.LEFT,
		1,
		crown,
		pitch,
		pier,
		pier,
		Materials.Finish.TRAVERTINE,
		Materials.Finish.BRICK
	)
	_arches(
		Vector3(-pc, spring, -pc),
		Vector3.BACK,
		1,
		crown,
		pitch,
		pier,
		pier,
		Materials.Finish.TRAVERTINE,
		Materials.Finish.BRICK
	)
	_arches(
		Vector3(pc, spring, pc),
		Vector3.FORWARD,
		1,
		crown,
		pitch,
		pier,
		pier,
		Materials.Finish.TRAVERTINE,
		Materials.Finish.BRICK
	)
	var frame_top := y + 2.6
	for sx: float in [-1.0, 1.0]:
		_span(
			Vector3(sx * 1.35 - 0.15, y, -0.15),
			Vector3(sx * 1.35 + 0.15, frame_top, 0.15),
			Materials.Finish.RAW,
			0.8,
			Materials.Kind.WOOD
		)
	_span(
		Vector3(-1.7, frame_top, -0.18),
		Vector3(1.7, frame_top + 0.3, 0.18),
		Materials.Finish.RAW,
		0.8,
		Materials.Kind.WOOD
	)
	# The bell, cast in one piece (modelled in Blender).
	_box(
		Vector3(0, frame_top - 0.75, 0),
		Vector3(1.5, 1.5, 1.5),
		Materials.Finish.BRONZE,
		2.0,
		Materials.Kind.METAL,
		Basis(),
		true,
		"bell"
	)
	# Roof of the belfry, a cornice, then a lantern under a copper dome.
	y = crown
	_tower_floor(y, 2.0 * bh)
	y += SLAB
	_span(
		Vector3(-bh - 0.35, y, -bh - 0.35),
		Vector3(bh + 0.35, y + 0.3, bh + 0.35),
		Materials.Finish.TRAVERTINE,
		0.9
	)
	y += 0.3
	var drums: Array[Vector3] = [
		Vector3(3.4, 1.7, Materials.Finish.TRAVERTINE),
		Vector3(3.9, 0.25, Materials.Finish.TRAVERTINE),
		Vector3(3.4, 0.6, Materials.Finish.VERDIGRIS),
		Vector3(2.8, 0.55, Materials.Finish.VERDIGRIS),
		Vector3(2.1, 0.5, Materials.Finish.VERDIGRIS),
		Vector3(1.3, 0.45, Materials.Finish.VERDIGRIS),
		Vector3(0.7, 0.5, Materials.Finish.VERDIGRIS),
		Vector3(0.36, 1.6, Materials.Finish.VERDIGRIS),
		Vector3(0.6, 0.6, Materials.Finish.BRONZE),
	]
	var band := 0
	for dr in drums:
		var metal := int(dr.z) in [Materials.Finish.BRONZE, Materials.Finish.VERDIGRIS]
		var kind := Materials.Kind.METAL if metal else Materials.Kind.CONCRETE
		# The copper dome's bands are carved pieces (their curve modelled in
		# Blender to these sizes: tools/make_sculptures.py DOME).
		var shape := ""
		if int(dr.z) == Materials.Finish.VERDIGRIS and band < 5:
			shape = "dome_%d" % band
			band += 1
		var size := Vector3(dr.x, dr.y, dr.x)
		_box(Vector3(0, y + dr.y * 0.5, 0), size, int(dr.z), 1.0, kind, Basis(), true, shape)
		y += dr.y
	_span(
		Vector3(-0.06, y, -0.06),
		Vector3(0.06, y + 1.1, 0.06),
		Materials.Finish.BRONZE,
		0.6,
		Materials.Kind.METAL
	)
	_span(
		Vector3(-0.35, y + 0.62, -0.06),
		Vector3(-0.06, y + 0.74, 0.06),
		Materials.Finish.BRONZE,
		0.6,
		Materials.Kind.METAL
	)
	_span(
		Vector3(0.06, y + 0.62, -0.06),
		Vector3(0.35, y + 0.74, 0.06),
		Materials.Finish.BRONZE,
		0.6,
		Materials.Kind.METAL
	)


## One course of the shaft: on even courses the front and back walls run
## the full width, on odd ones the sides do, so the corners interlock. Each
## wall is three stones; the ones at the corners are travertine quoins.
## A window course leaves out the middle stone.
func _tower_course(c: int, y: float) -> void:
	var lower := c < 6
	for face in 4:
		var full := (face < 2) == (c % 2 == 0)
		var stones: Array[float] = [1.5, 2.0, 1.5]
		if full:
			stones = [2.0, 3.0, 2.0]
		var u := -TS * 0.5 if full else -TS * 0.5 + TT
		var window := not full and c in [3, 4, 8, 9, 13, 14] and (face < 2) == (c % 2 == 1)
		for k in 3:
			var l: float = stones[k]
			var fin := Materials.Finish.STONE
			if not lower:
				fin = Materials.Finish.TRAVERTINE if full and k != 1 else Materials.Finish.BRICK
			if window and k == 1:
				_tower_face_box(face, u, u + l, y, y + 0.4, -TT, 0.0, fin, 1.5)
			else:
				_tower_face_box(face, u, u + l, y, y + COURSE, -TT, 0.0, fin, 1.5)
			u += l


func _tower_floor(y: float, size: float) -> void:
	var h := size * 0.5
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_span(
				Vector3(minf(0.0, sx * h), y, minf(0.0, sz * h)),
				Vector3(maxf(0.0, sx * h), y + SLAB, maxf(0.0, sz * h)),
				Materials.Finish.TRAVERTINE,
				1.4
			)


## Box on a tower face (0 = +z, 1 = -z, 2 = -x, 3 = +x): u along the face,
## o outward from the shaft's outer face.
func _tower_face_box(
	face: int, u0: float, u1: float, y0: float, y1: float, o0: float, o1: float, fin: int, mult: float
) -> void:
	var h := TS * 0.5
	var a: Vector3
	var b: Vector3
	match face:
		0:
			a = Vector3(u0, y0, h + o0)
			b = Vector3(u1, y1, h + o1)
		1:
			a = Vector3(-u0, y0, -h - o0)
			b = Vector3(-u1, y1, -h - o1)
		2:
			a = Vector3(-h - o0, y0, u0)
			b = Vector3(-h - o1, y1, u1)
		_:
			a = Vector3(h + o0, y0, -u0)
			b = Vector3(h + o1, y1, -u1)
	_span(Vector3(minf(a.x, b.x), y0, minf(a.z, b.z)), Vector3(maxf(a.x, b.x), y1, maxf(a.z, b.z)), fin, mult)
