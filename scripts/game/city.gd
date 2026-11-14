class_name City
extends RefCounted
## A toy city for two giants: the brutes keep their size and the city is
## small around them, about a tenth of a real one. Houses come up to their
## knees, offices to their heads, and four towers stand three times as high
## as they do. Eight blocks around a square, with avenues between them wide
## enough to fight in: downtown on the four sides of the square (a tower,
## offices, a few houses), houses at the corners. Cars along the kerbs and
## on the road, trees, and a railway on stilts with a train on it.
##
## What is lower than Fighter.WADE (the houses, the cars, the trees, the
## railway) a brute walks through; the rest it has to break.
## Given as boxes; Structure cuts them into shards. The square is in the
## middle; +Z is where you start from, looking in.

## A block is BLOCK m across, and an avenue AVENUE wide.
const BLOCK := 9.0
const AVENUE := 3.6
const PITCH := BLOCK + AVENUE
## A block is laid out as three by three lots.
const LOT := BLOCK / 3.0
## Shards are about this big (m): finer for what is small. A thing cut
## with WHOLE is left in one piece (a car, a roof, the crown of a tree).
const FINE := 0.6
const COARSE := 0.75
const WHOLE := 4.0
## kg/m3 of what it is made of: little, a toy city is hollow.
const DENSITY := 300.0
## Where the two brutes start, on the square.
const PLAYER := Vector3(0, 0.05, 3.2)
const BRUTE := Vector3(1.5, 0.05, -2.5)
## How fine the grid on the walls is (squares of 0.2 m: it reads as windows).
const SQUARES_PER_METRE := 1.25
## Cars are parked KERB m from the middle of an avenue, and drive LANE m
## from it.
const KERB := AVENUE * 0.5 - 0.45
const LANE := 0.5
## The railway: how high its deck stands (m), and how long a span is.
const RAIL_HIGH := 0.62
const RAIL_SPAN := 2.85

const HOUSES: Array[Color] = [
	Color(0.86, 0.8, 0.68),
	Color(0.8, 0.7, 0.6),
	Color(0.88, 0.84, 0.78),
	Color(0.76, 0.66, 0.58),
	Color(0.82, 0.78, 0.66),
]
const ROOFS: Array[Color] = [Color(0.55, 0.3, 0.24), Color(0.4, 0.36, 0.36), Color(0.5, 0.34, 0.26)]
const OFFICES: Array[Color] = [
	Color(0.62, 0.66, 0.72),
	Color(0.7, 0.7, 0.72),
	Color(0.58, 0.62, 0.66),
	Color(0.74, 0.72, 0.68),
]
const GLASS: Array[Color] = [Color(0.52, 0.64, 0.74), Color(0.6, 0.7, 0.76), Color(0.48, 0.58, 0.7)]
const CARS: Array[Color] = [
	Color(0.8, 0.2, 0.18),
	Color(0.9, 0.75, 0.2),
	Color(0.2, 0.4, 0.75),
	Color(0.9, 0.9, 0.9),
	Color(0.2, 0.2, 0.22),
	Color(0.25, 0.6, 0.35),
]
const TRUNK := Color(0.45, 0.32, 0.22)
const LEAVES := Color(0.3, 0.55, 0.28)
const CONCRETE := Color(0.6, 0.6, 0.6)
const TRAIN := Color(0.85, 0.5, 0.15)


## Adds the city to `s`, placed by `xf`.
static func build(s: Structure, xf: Transform3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for bz: int in [-1, 0, 1]:
		for bx: int in [-1, 0, 1]:
			if bx == 0 and bz == 0:
				continue  # the square
			var out := Vector3(bx, 0, bz)
			if absi(bx) + absi(bz) == 1:
				_downtown(s, xf, out, rng)
			else:
				_suburb(s, xf, out * PITCH, rng)
	_traffic(s, xf, rng)
	_square(s, xf)
	_railway(s, xf)


## The pads the blocks and the square stand on: where to lay a pavement
## (each one a middle and a size on the ground).
static func pads() -> Array[Array]:
	var out: Array[Array] = []
	for bz: int in [-1, 0, 1]:
		for bx: int in [-1, 0, 1]:
			out.append([Vector3(bx * PITCH, 0, bz * PITCH), Vector2(BLOCK + 0.5, BLOCK + 0.5)])
	return out


## A tour of the city for the showcase: where to stand and what to look
## at. Each tower from its forecourt, the two lots beside each forecourt
## from the avenue, and two corners.
static func tour() -> Array[Array]:
	var stops: Array[Array] = []
	for out: Vector3 in [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT]:
		var tower := out * PITCH
		var side := out.cross(Vector3.UP)
		stops.append([tower - out * (LOT + 0.2), tower + Vector3.UP * 1.0])
		for way: int in [-1, 1]:
			var lot := tower - out * LOT + side * way * LOT
			stops.append([lot - out * (LOT * 0.5 + 1.2), lot + Vector3.UP * 0.5])
	for corner: int in [-1, 1]:
		var lot := Vector3(corner * (PITCH - LOT), 0, corner * PITCH)
		stops.append([lot - Vector3(corner * (LOT * 0.5 + 1.2), 0, 0), lot + Vector3.UP * 0.5])
	return stops


## A block on a side of the square (`out` from it): a tower in the middle,
## a forecourt between it and the square, three offices, and houses.
static func _downtown(s: Structure, xf: Transform3D, out: Vector3, rng: RandomNumberGenerator) -> void:
	var middle := out * PITCH
	var lots: Array[Vector3] = []
	for lz: int in [-1, 0, 1]:
		for lx: int in [-1, 0, 1]:
			var lot := Vector3(lx, 0, lz)
			if lot != Vector3.ZERO and lot != -out:
				lots.append(middle + lot * LOT)
	_shuffle(lots, rng)
	_tower(s, xf, middle, rng)
	for corner: Vector3 in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, 1)]:
		_tree(s, xf, middle - out * LOT + corner * 1.15, 1.0)
	for k in lots.size():
		if k < 3:
			_office(s, xf, lots[k], rng)
		else:
			_houses(s, xf, lots[k], rng)


## A block at a corner: houses, an office and a park.
static func _suburb(s: Structure, xf: Transform3D, middle: Vector3, rng: RandomNumberGenerator) -> void:
	var lots: Array[Vector3] = []
	for lz: int in [-1, 0, 1]:
		for lx: int in [-1, 0, 1]:
			lots.append(middle + Vector3(lx, 0, lz) * LOT)
	_shuffle(lots, rng)
	for k in lots.size():
		if k == 0:
			_office(s, xf, lots[k], rng)
		elif k == 1:
			_park(s, xf, lots[k], rng)
		else:
			_houses(s, xf, lots[k], rng)


## Shuffled with `rng` (the same city every time).
static func _shuffle(lots: Array[Vector3], rng: RandomNumberGenerator) -> void:
	for k in range(lots.size() - 1, 0, -1):
		var other := rng.randi_range(0, k)
		var kept := lots[k]
		lots[k] = lots[other]
		lots[other] = kept


## A tower: a tall body, a narrower top and a mast.
static func _tower(s: Structure, xf: Transform3D, at: Vector3, rng: RandomNumberGenerator) -> void:
	var tint := GLASS[rng.randi() % GLASS.size()]
	var tall := rng.randf_range(4.4, 5.6)
	_box(s, xf, at, Vector3(1.9, tall, 1.9), 0.0, tint, COARSE)
	_box(s, xf, at + Vector3(0, tall, 0), Vector3(1.2, 0.8, 1.2), 0.0, tint.darkened(0.15), FINE)
	var mast := Vector3(0.12, 0.9, 0.12)
	_box(s, xf, at + Vector3(0, tall + 0.8, 0), mast, 0.0, CONCRETE.darkened(0.3), WHOLE)


## An office: as high as a brute or a little more, with a darker roof.
static func _office(s: Structure, xf: Transform3D, at: Vector3, rng: RandomNumberGenerator) -> void:
	var tint := OFFICES[rng.randi() % OFFICES.size()]
	var size := Vector3(rng.randf_range(1.9, 2.4), rng.randf_range(1.5, 2.5), rng.randf_range(1.9, 2.4))
	_box(s, xf, at, size, 0.0, tint, COARSE)
	var roof := Vector3(size.x * 0.6, 0.25, size.z * 0.6)
	_box(s, xf, at + Vector3(0, size.y, 0), roof, 0.0, tint.darkened(0.25), WHOLE)


## Two houses on a lot, side by side, each with its roof.
static func _houses(s: Structure, xf: Transform3D, at: Vector3, rng: RandomNumberGenerator) -> void:
	var turn := rng.randi_range(0, 1) * PI * 0.5
	for side: int in [-1, 1]:
		var size := Vector3(rng.randf_range(1.05, 1.3), rng.randf_range(0.6, 0.85), rng.randf_range(1.3, 1.9))
		var place := at + Vector3(side * 0.72, 0, 0).rotated(Vector3.UP, turn)
		_box(s, xf, place, size, turn, HOUSES[rng.randi() % HOUSES.size()], FINE)
		var roof := Vector3(size.x + 0.1, 0.14, size.z + 0.1)
		_box(s, xf, place + Vector3(0, size.y, 0), roof, turn, ROOFS[rng.randi() % ROOFS.size()], WHOLE)


## A lot of trees.
static func _park(s: Structure, xf: Transform3D, at: Vector3, rng: RandomNumberGenerator) -> void:
	for k in 5:
		var spot := at + Vector3(rng.randf_range(-1.1, 1.1), 0, rng.randf_range(-1.1, 1.1))
		_tree(s, xf, spot, rng.randf_range(0.8, 1.2))


static func _tree(s: Structure, xf: Transform3D, at: Vector3, grown: float) -> void:
	_box(s, xf, at, Vector3(0.09, 0.32, 0.09) * grown, 0.0, TRUNK, WHOLE)
	_box(s, xf, at + Vector3(0, 0.32 * grown, 0), Vector3(0.42, 0.4, 0.42) * grown, 0.0, LEAVES, WHOLE)


## Cars on the four avenues: parked along the kerbs, and a few on the road.
static func _traffic(s: Structure, xf: Transform3D, rng: RandomNumberGenerator) -> void:
	var ends := PITCH + BLOCK * 0.5
	for line: int in [-1, 1]:
		for lane: float in [-KERB, -LANE, LANE, KERB]:
			var across := line * PITCH * 0.5 + lane
			var parked := absf(lane) > LANE
			for turned in 2:
				var along := -ends + rng.randf_range(0.4, 3.0)
				while along < ends:
					# (Not where two avenues cross.)
					if absf(absf(along) - PITCH * 0.5) > AVENUE * 0.5 + 0.2:
						var at := Vector3(along, 0, across) if turned == 1 else Vector3(across, 0, along)
						_car(s, xf, at, turned * PI * 0.5, CARS[rng.randi() % CARS.size()])
					along += rng.randf_range(1.5, 4.5) if parked else rng.randf_range(4.0, 10.0)


static func _car(s: Structure, xf: Transform3D, at: Vector3, turn: float, tint: Color) -> void:
	_box(s, xf, at, Vector3(0.24, 0.13, 0.5), turn, tint, WHOLE)
	_box(s, xf, at + Vector3(0, 0.13, 0), Vector3(0.21, 0.09, 0.26), turn, tint.lightened(0.25), WHOLE)


## Trees round the square.
static func _square(s: Structure, xf: Transform3D) -> void:
	var edge := BLOCK * 0.5 - 0.4
	for k: int in [-3, -1, 1, 3]:
		for side: int in [-1, 1]:
			_tree(s, xf, Vector3(k * 0.9, 0, side * edge), 1.0)
			_tree(s, xf, Vector3(side * edge, 0, k * 0.9), 1.0)


## A railway on stilts down the middle of the far avenue, from one end of
## the city to the other, and a train of four cars on it.
static func _railway(s: Structure, xf: Transform3D) -> void:
	var z := -PITCH * 0.5
	var from := -PITCH - BLOCK * 0.5
	var spans := roundi((PITCH * 2.0 + BLOCK) / RAIL_SPAN)
	for k in spans + 1:
		var x := from + k * RAIL_SPAN
		var stilt := Vector3(0.22, RAIL_HIGH, 0.22)
		_box(s, xf, Vector3(x, 0, z), stilt, 0.0, CONCRETE.darkened(0.1), WHOLE)
		if k < spans:
			var deck := Vector3(RAIL_SPAN, 0.16, 0.7)
			_box(s, xf, Vector3(x + RAIL_SPAN * 0.5, RAIL_HIGH, z), deck, 0.0, CONCRETE, 1.0)
	for k in 4:
		var car := Vector3(0.92, 0.26, 0.34)
		_box(s, xf, Vector3(-2.4 + k * 1.0, RAIL_HIGH + 0.16, z), car, 0.0, TRAIN, WHOLE)


## A box standing at `at` (the middle of its foot), turned `turn` rad about
## the vertical. What is low or cut coarse is cut plain (see
## Structure.add_box): a house in four to six, a car in one.
static func _box(
	s: Structure, xf: Transform3D, at: Vector3, size: Vector3, turn: float, tint: Color, grain: float
) -> void:
	var placed := Transform3D(Basis(Vector3.UP, turn), at + Vector3(0, size.y * 0.5, 0))
	s.add_box(xf * placed, size, tint, grain, grain >= 1.0 or size.y < 1.0)
